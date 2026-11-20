package main

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"crypto/tls"
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestScreenNameRules(t *testing.T) {
	good := []string{"Hatdagger", "New Kid", "abc", "A1 2 3", "sixteen chars xx"}
	bad := []string{"", "ab", "1abc", "abc ", "a_b_c", "seventeen chars x", " abc", "a  "}
	for _, s := range good {
		if err := ValidateScreenName(s); err != nil {
			t.Errorf("%q should be valid: %v", s, err)
		}
	}
	for _, s := range bad {
		if ValidateScreenName(s) == nil {
			t.Errorf("%q should be invalid", s)
		}
	}
}

func TestCodes(t *testing.T) {
	for i := 0; i < 200; i++ {
		c := NewCode()
		if len(c) != 9 || c[4] != '-' {
			t.Fatalf("bad code %q", c)
		}
		for _, bad := range "01OI" {
			if bytes.ContainsRune([]byte(c), bad) {
				t.Fatalf("code %q has %c", c, bad)
			}
		}
		if NormalizeCode(" "+string(bytes.ToLower([]byte(c[:4])))+" "+c[5:]) != c {
			t.Fatalf("normalize failed for %q", c)
		}
	}
}

func TestAbuseLimits(t *testing.T) {
	l := defaultLimits()
	now := time.Now()
	d := &StoreData{}
	add := func(ip, dev, inviter string, ago time.Duration) {
		d.Accounts = append(d.Accounts, &Account{ScreenName: NewCode(), IP: ip, Device: dev, InvitedBy: inviter, Created: now.Add(-ago)})
	}
	// a big household: 12 accounts from one IP over the day, different devices and inviters
	for i := 0; i < 11; i++ {
		add("1.1.1.1", "dev"+string(rune('a'+i)), "inv"+string(rune('a'+i)), time.Duration(i+1)*time.Hour)
	}
	if v := d.AbuseCheck(l, "1.1.1.1", "new", "someone", false, now); v.Verdict != VerdictOK {
		t.Fatalf("12th from one IP should be fine, got %v %s", v.Verdict, v.Reason)
	}
	add("1.1.1.1", "devz", "invz", 30*time.Minute)
	if v := d.AbuseCheck(l, "1.1.1.1", "new", "someone", false, now); v.Verdict != VerdictFlag {
		t.Fatalf("13th from one IP should be flagged, got %v", v.Verdict)
	}
	// trusted household skips
	d.Trusted = addMark(d.Trusted, "ip", "1.1.1.1", "", now)
	if v := d.AbuseCheck(l, "1.1.1.1", "new", "someone", false, now); v.Verdict != VerdictOK {
		t.Fatalf("trusted IP should pass")
	}
	// burst: 9 from one device within 10 minutes, the 10th is banned
	d2 := &StoreData{}
	for i := 0; i < 9; i++ {
		d2.Accounts = append(d2.Accounts, &Account{ScreenName: NewCode(), IP: "2.2.2." + string(rune('0'+i)), Device: "d", InvitedBy: "x" + string(rune('a'+i)), Created: now.Add(-time.Minute)})
	}
	v := d2.AbuseCheck(l, "3.3.3.3", "d", "y", false, now)
	if v.Verdict != VerdictBan || len(v.Burst) != 9 {
		t.Fatalf("burst should ban with 9 burst accounts, got %v %d", v.Verdict, len(v.Burst))
	}
	// owner invites don't count against an inviter
	d3 := &StoreData{}
	for i := 0; i < 30; i++ {
		d3.Accounts = append(d3.Accounts, &Account{ScreenName: NewCode(), IP: "9.9.9." + string(rune('0'+i%10)), Device: NewCode(), InvitedBy: "Owner", Created: now.Add(-time.Duration(i+1) * 40 * time.Minute)})
	}
	if v := d3.AbuseCheck(l, "8.8.8.8", "fresh", "Owner", true, now); v.Verdict != VerdictOK {
		t.Fatalf("owner invites should skip inviter limit, got %v %s", v.Verdict, v.Reason)
	}
	if v := d3.AbuseCheck(l, "8.8.8.8", "fresh", "Owner", false, now); v.Verdict != VerdictBan {
		t.Fatalf("a user inviter with 30 sign-ups should be banned, got %v", v.Verdict)
	}
}

func TestTreeNoLoops(t *testing.T) {
	d := &StoreData{Accounts: []*Account{
		{ScreenName: "A", InvitedBy: "B"}, {ScreenName: "B", InvitedBy: "A"}, {ScreenName: "C", InvitedBy: "Owner"},
	}}
	tr := d.Tree()
	if len(tr) != 1 || tr[0].ScreenName != "Owner" {
		t.Fatalf("unexpected tree %+v", tr)
	}
}

func TestInviteInjection(t *testing.T) {
	dir := t.TempDir()
	// zip like Compress-Archive makes: files at the root
	zp := filepath.Join(dir, "w.zip")
	{
		var b bytes.Buffer
		zw := zip.NewWriter(&b)
		w, _ := zw.Create("aim_for_android.exe")
		w.Write([]byte("MZ"))
		w, _ = zw.Create("data/app.so")
		w.Write([]byte("x"))
		zw.Close()
		os.WriteFile(zp, b.Bytes(), 0o644)
	}
	var out bytes.Buffer
	if err := WriteZipWithInvite(&out, zp, []byte(`{"code":"X"}`)); err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(bytes.NewReader(out.Bytes()), int64(out.Len()))
	if err != nil {
		t.Fatal(err)
	}
	names := map[string]string{}
	for _, f := range zr.File {
		r, _ := f.Open()
		b, _ := io.ReadAll(r)
		names[f.Name] = string(b)
	}
	if names["invite.json"] != `{"code":"X"}` || names["aim_for_android.exe"] != "MZ" || names["data/app.so"] != "x" {
		t.Fatalf("zip contents wrong: %v", names)
	}

	// tar.gz like `tar czf x -C release bundle`
	tp := filepath.Join(dir, "l.tar.gz")
	{
		var b bytes.Buffer
		gw := gzip.NewWriter(&b)
		tw := tar.NewWriter(gw)
		tw.WriteHeader(&tar.Header{Name: "bundle/", Typeflag: tar.TypeDir, Mode: 0o755})
		tw.WriteHeader(&tar.Header{Name: "bundle/aim_for_android", Typeflag: tar.TypeReg, Mode: 0o755, Size: 3})
		tw.Write([]byte("ELF"))
		tw.Close()
		gw.Close()
		os.WriteFile(tp, b.Bytes(), 0o644)
	}
	out.Reset()
	if err := WriteTarGzWithInvite(&out, tp, []byte(`{}`), "aim_for_android"); err != nil {
		t.Fatal(err)
	}
	gr, _ := gzip.NewReader(&out)
	tr := tar.NewReader(gr)
	found := map[string]bool{}
	for {
		h, err := tr.Next()
		if err != nil {
			break
		}
		found[h.Name] = true
	}
	if !found["bundle/invite.json"] || !found["bundle/aim_for_android"] {
		t.Fatalf("tar contents wrong: %v", found)
	}
}

func TestRouterSniff(t *testing.T) {
	// fake OSCAR backend that greets first
	be, _ := net.Listen("tcp", "127.0.0.1:0")
	defer be.Close()
	go func() {
		for {
			c, err := be.Accept()
			if err != nil {
				return
			}
			go func() {
				c.Write([]byte{0x2A, 1, 0, 1, 0, 4, 0, 0, 0, 1})
				io.Copy(c, c) // echo afterwards
			}()
		}
	}()
	dir := t.TempDir()
	cert, _, _ := LoadOrCreateCert(dir)
	r, err := NewRouter("127.0.0.1:0", &tls.Config{Certificates: []tls.Certificate{cert}},
		func(net.IP) string { return be.Addr().String() }, NewLogBuffer(10))
	if err != nil {
		t.Fatal(err)
	}
	r.SniffWait = 200 * time.Millisecond
	defer r.Close()
	go r.Serve()
	addr := r.Addr().String()

	// 1) client that waits for the server greeting
	c, _ := net.Dial("tcp", addr)
	c.SetDeadline(time.Now().Add(3 * time.Second))
	h := make([]byte, 10)
	if _, err := io.ReadFull(c, h); err != nil || h[0] != 0x2A {
		t.Fatalf("waiting client got no greeting: %v %x", err, h)
	}
	c.Close()

	// 2) client that speaks first
	c, _ = net.Dial("tcp", addr)
	c.SetDeadline(time.Now().Add(3 * time.Second))
	c.Write([]byte{0x2A, 1, 0, 1, 0, 4, 0, 0, 0, 1})
	got := make([]byte, 20)
	if _, err := io.ReadFull(c, got); err != nil || got[10] != 0x2A {
		t.Fatalf("speaking client: %v %x", err, got)
	}
	c.Close()

	// 3) HTTP and TLS go to their listeners
	go func() {
		c, _ := net.Dial("tcp", addr)
		c.Write([]byte("GET / HTTP/1.0\r\n\r\n"))
	}()
	hc, err := r.HTTP.Accept()
	if err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 3)
	io.ReadFull(hc, buf)
	if string(buf) != "GET" {
		t.Fatalf("http got %q", buf)
	}
	go tls.Dial("tcp", addr, &tls.Config{InsecureSkipVerify: true})
	tc, err := r.HTTPS.Accept()
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := tc.(*tls.Conn); !ok {
		t.Fatalf("https listener got %T", tc)
	}
}
