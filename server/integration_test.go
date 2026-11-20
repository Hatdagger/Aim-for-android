package main

import (
	"bytes"
	"context"
	"crypto/md5"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Runs against a real Open OSCAR Server. Set OSCAR_BIN to its path.

func freePort(t *testing.T) int {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func startTestApp(t *testing.T) (*App, string) {
	bin := os.Getenv("OSCAR_BIN")
	if bin == "" {
		t.Skip("OSCAR_BIN not set")
	}
	os.Setenv("AIM_SERVER_NO_CLIENT_DOWNLOAD", "1")
	dir := t.TempDir()
	app, err := NewApp(dir, bin)
	if err != nil {
		t.Fatal(err)
	}
	app.NoNetworkChecks = true
	port := freePort(t)
	base := freePort(t)
	for base > 65000 || (base <= port && port <= base+3) {
		base = freePort(t)
	}
	app.Settings.Update(func(s *Settings) { s.Port = port; s.InternalBase = base })
	if err := app.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(app.Stop)
	return app, "127.0.0.1:" + strconv.Itoa(port)
}

// pinnedClient behaves like the AIM client: accepts the self-signed
// certificate only if its fingerprint matches.
func pinnedClient(fp string) *http.Client {
	return &http.Client{Timeout: 15 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{
		InsecureSkipVerify: true,
		VerifyPeerCertificate: func(raw [][]byte, _ [][]*x509Cert) error {
			h := sha256.Sum256(raw[0])
			if hex.EncodeToString(h[:]) != fp {
				return errors.New("fingerprint mismatch")
			}
			return nil
		},
	}}}
}

func postJSON(t *testing.T, c *http.Client, url string, body any) (int, map[string]any) {
	b, _ := json.Marshal(body)
	resp, err := c.Post(url, "application/json", bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

// fullSignOn does BUCP through the public port as a client that waits for the
// server to speak first, follows the BOS redirect and checks the server greets.
func fullSignOn(t *testing.T, addr, sn, pw string) string {
	flapRead := func(c net.Conn) (byte, []byte) {
		h := make([]byte, 6)
		if _, err := io.ReadFull(c, h); err != nil {
			t.Fatalf("read: %v", err)
		}
		d := make([]byte, binary.BigEndian.Uint16(h[4:]))
		io.ReadFull(c, d)
		return h[1], d
	}
	seq := uint16(100)
	flapSend := func(c net.Conn, ch byte, d []byte) {
		h := []byte{0x2A, ch, byte(seq >> 8), byte(seq), byte(len(d) >> 8), byte(len(d))}
		seq++
		c.Write(append(h, d...))
	}
	tlv := func(t uint16, v []byte) []byte {
		return append([]byte{byte(t >> 8), byte(t), byte(len(v) >> 8), byte(len(v))}, v...)
	}
	snac := func(f, s uint16, b []byte) []byte {
		h := make([]byte, 10)
		binary.BigEndian.PutUint16(h, f)
		binary.BigEndian.PutUint16(h[2:], s)
		return append(h, b...)
	}
	c, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(15 * time.Second))
	if ch, _ := flapRead(c); ch != 1 { // server greeting arrives without us speaking
		t.Fatalf("expected greeting, got channel %d", ch)
	}
	flapSend(c, 1, []byte{0, 0, 0, 1})
	flapSend(c, 2, snac(0x17, 0x06, append(tlv(1, []byte(sn)), tlv(0x4B, nil)...)))
	_, d := flapRead(c)
	key := d[12 : 12+binary.BigEndian.Uint16(d[10:])]
	pwh := md5sum([]byte(pw))
	hash := md5sum(append(append(append([]byte{}, key...), pwh...), []byte("AOL Instant Messenger (SM)")...))
	var body []byte
	body = append(body, tlv(1, []byte(sn))...)
	body = append(body, tlv(0x25, hash)...)
	body = append(body, tlv(0x4C, nil)...)
	flapSend(c, 2, snac(0x17, 0x02, body))
	_, d = flapRead(c)
	tl := parseTLVs(d[10:])
	bos, cookie := string(tl[0x05]), tl[0x06]
	if cookie == nil {
		t.Fatalf("no cookie; tlvs %v", tl)
	}
	// connect to BOS through the same public port
	_, bport, _ := net.SplitHostPort(bos)
	b, err := net.Dial("tcp", "127.0.0.1:"+bport)
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close()
	b.SetDeadline(time.Now().Add(15 * time.Second))
	flapRead(b) // greeting
	flapSend(b, 1, append([]byte{0, 0, 0, 1}, tlv(6, cookie)...))
	ch, d := flapRead(b)
	if ch != 2 || binary.BigEndian.Uint16(d) != 1 || binary.BigEndian.Uint16(d[2:]) != 3 {
		t.Fatalf("expected host-online SNAC, got ch %d %x", ch, d[:4])
	}
	return bos
}

func TestIntegration(t *testing.T) {
	app, addr := startTestApp(t)
	ctx := context.Background()
	mg := app.Mgmt()
	if err := mg.CreateUser(ctx, "Owner One", "ownerpw1"); err != nil {
		t.Fatal(err)
	}
	inv, err := app.CreateInvite("Owner One", true, "household", 0, 0)
	if err != nil {
		t.Fatal(err)
	}
	cli := pinnedClient(app.FP)
	api := "https://" + addr + "/api/v1/"

	// invite page over plain HTTP on the same port
	resp, err := http.Get("http://" + addr + "/i/" + strings.ToLower(inv.Code))
	if err != nil {
		t.Fatal(err)
	}
	page, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || !bytes.Contains(page, []byte("Owner One invited you")) ||
		!bytes.Contains(page, []byte("aim://invite?")) || !bytes.Contains(page, []byte(app.FP)) {
		t.Fatalf("landing page wrong (%d): %s", resp.StatusCode, page)
	}

	// sign up
	st, out := postJSON(t, cli, api+"signup", map[string]string{"invite_code": inv.Code, "screen_name": "New Kid", "password": "secret12", "device_id": "devA"})
	if st != 200 || out["ok"] != true {
		t.Fatalf("signup: %d %v", st, out)
	}
	st, out = postJSON(t, cli, api+"signup", map[string]string{"invite_code": inv.Code, "screen_name": "newkid", "password": "secret12", "device_id": "devA"})
	if st != 409 || out["code"] != "name_taken" {
		t.Fatalf("dup: %d %v", st, out)
	}

	// wrong fingerprint is refused by the client
	if _, err := pinnedClient(strings.Repeat("0", 64)).Post(api+"signup", "application/json", strings.NewReader("{}")); err == nil {
		t.Fatal("expected pin failure")
	}

	// password check through the public port (client speaks first)
	if err := CheckPassword(addr, "newkid", "secret12"); err != nil {
		t.Fatalf("check password: %v", err)
	}
	if err := CheckPassword(addr, "newkid", "nope1234"); !errors.Is(err, ErrBadLogin) {
		t.Fatalf("wrong password should fail, got %v", err)
	}

	// full sign-on as a client that waits for the server first
	bos := fullSignOn(t, addr, "New Kid", "secret12")
	if !strings.HasSuffix(bos, ":"+strconv.Itoa(app.Settings.Get().Port)) {
		t.Fatalf("BOS redirect %q should point at the public port", bos)
	}

	// user creates an invite from the app
	st, out = postJSON(t, cli, api+"invites", map[string]string{"screen_name": "newkid", "password": "bad", "device_id": "devA", "kind": "single"})
	if st != 401 {
		t.Fatalf("bad password invite: %d %v", st, out)
	}
	st, out = postJSON(t, cli, api+"invites", map[string]string{"screen_name": "newkid", "password": "secret12", "device_id": "devA", "kind": "single"})
	if st != 200 || out["uses_left"].(float64) != 1 || !strings.Contains(out["link"].(string), "#fp="+app.FP+"&by=New%20Kid") {
		t.Fatalf("invite: %d %v", st, out)
	}
	code := out["code"].(string)
	st, out = postJSON(t, cli, api+"signup", map[string]string{"invite_code": code, "screen_name": "Third Kid", "password": "secret12", "device_id": "devB"})
	if st != 200 {
		t.Fatalf("signup with user invite: %d %v", st, out)
	}
	st, out = postJSON(t, cli, api+"signup", map[string]string{"invite_code": code, "screen_name": "Fourth Kid", "password": "secret12", "device_id": "devC"})
	if st != 410 || out["code"] != "invite_used" {
		t.Fatalf("reuse single invite: %d %v", st, out)
	}

	// abuse: tighten limits, then flood from one device
	app.Settings.Update(func(s *Settings) {
		s.Limits.DeviceAllow, s.Limits.DeviceBan = 2, 4
		s.Limits.BurstFlag, s.Limits.BurstBan = 50, 60
		s.Limits.IPAllow, s.Limits.IPBan = 100, 200
		s.Limits.InviterAllow, s.Limits.InviterBan = 100, 200
	})
	big, _ := app.CreateInvite("Owner One", true, "household", 20, 1)
	codes := []int{}
	for i := 0; i < 4; i++ {
		st, _ := postJSON(t, cli, api+"signup", map[string]string{"invite_code": big.Code, "screen_name": "Flood " + string(rune('A'+i)), "password": "secret12", "device_id": "evil"})
		codes = append(codes, st)
	}
	if codes[0] != 200 || codes[1] != 200 || codes[2] != 200 || codes[3] != 429 {
		t.Fatalf("flood statuses %v", codes)
	}
	app.Store.Read(func(d *StoreData) {
		if a := d.Account("Flood C"); a == nil || a.Status != "suspended" {
			t.Errorf("Flood C should be suspended after the ban: %+v", a)
		}
		if !d.IsBanned("device", "evil", time.Now()) {
			t.Error("device should be banned")
		}
	})
	if err := CheckPassword(addr, "Flood A", "secret12"); !errors.Is(err, ErrSuspended) {
		t.Fatalf("Flood A should be suspended on the server, got %v", err)
	}
	st, out = postJSON(t, cli, api+"signup", map[string]string{"invite_code": big.Code, "screen_name": "Flood Z", "password": "secret12", "device_id": "evil"})
	if st != 403 || out["code"] != "banned" {
		t.Fatalf("banned device: %d %v", st, out)
	}

	// panel approve lifts the suspension
	p := &Panel{App: app}
	req, _ := http.NewRequest("POST", "/", strings.NewReader(`{"screen_name":"Flood A"}`))
	if _, err := p.approve(req); err != nil {
		t.Fatal(err)
	}
	if err := CheckPassword(addr, "Flood A", "secret12"); err != nil {
		t.Fatalf("approved account should sign on: %v", err)
	}
}

type x509Cert = x509.Certificate

func md5sum(b []byte) []byte { h := md5.Sum(b); return h[:] }
