package main

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// ---------------------------------------------------------------- password check

var (
	ErrBadLogin  = errors.New("incorrect screen name or password")
	ErrSuspended = errors.New("this account is suspended")
)

// CheckPassword asks Open OSCAR Server whether the screen name and password
// are right, using the same MD5 sign-on an AIM 5.x client uses. It stops after
// the password step, so nobody is actually signed on.
func CheckPassword(addr, screenName, password string) error {
	c, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		return err
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(10 * time.Second))
	seq := uint16(1)
	send := func(ch byte, data []byte) error {
		h := []byte{0x2A, ch, byte(seq >> 8), byte(seq), byte(len(data) >> 8), byte(len(data))}
		seq++
		_, err := c.Write(append(h, data...))
		return err
	}
	read := func() (byte, []byte, error) {
		var h [6]byte
		if _, err := io.ReadFull(c, h[:]); err != nil {
			return 0, nil, err
		}
		if h[0] != 0x2A {
			return 0, nil, errors.New("not an OSCAR server")
		}
		d := make([]byte, binary.BigEndian.Uint16(h[4:]))
		_, err := io.ReadFull(c, d)
		return h[1], d, err
	}
	snac := func(fam, sub uint16, body []byte) error {
		b := make([]byte, 10, 10+len(body))
		binary.BigEndian.PutUint16(b[0:], fam)
		binary.BigEndian.PutUint16(b[2:], sub)
		binary.BigEndian.PutUint32(b[6:], uint32(sub))
		return send(2, append(b, body...))
	}
	readSnac := func() (uint16, uint16, []byte, error) {
		for {
			ch, d, err := read()
			if err != nil {
				return 0, 0, nil, err
			}
			if ch == 4 {
				return 0, 0, nil, errors.New("server closed the connection")
			}
			if ch != 2 || len(d) < 10 {
				continue
			}
			return binary.BigEndian.Uint16(d), binary.BigEndian.Uint16(d[2:]), d[10:], nil
		}
	}
	tlv := func(t uint16, v []byte) []byte {
		b := []byte{byte(t >> 8), byte(t), byte(len(v) >> 8), byte(len(v))}
		return append(b, v...)
	}

	if err := send(1, []byte{0, 0, 0, 1}); err != nil {
		return err
	}
	var chal []byte
	chal = append(chal, tlv(0x01, []byte(screenName))...)
	chal = append(chal, tlv(0x4B, nil)...)
	chal = append(chal, tlv(0x5A, nil)...)
	if err := snac(0x17, 0x06, chal); err != nil {
		return err
	}
	fam, sub, body, err := readSnac()
	for err == nil && !(fam == 0x17 && (sub == 0x07 || sub == 0x03 || sub == 0x01)) {
		fam, sub, body, err = readSnac()
	}
	if err != nil {
		return err
	}
	if sub != 0x07 {
		return loginErr(sub, body)
	}
	if len(body) < 2 || len(body) < 2+int(binary.BigEndian.Uint16(body)) {
		return errors.New("bad key from server")
	}
	key := body[2 : 2+binary.BigEndian.Uint16(body)]
	pw := md5.Sum([]byte(password))
	h := md5.New()
	h.Write(key)
	h.Write(pw[:])
	h.Write([]byte("AOL Instant Messenger (SM)"))
	var login []byte
	login = append(login, tlv(0x01, []byte(screenName))...)
	login = append(login, tlv(0x03, []byte("AIM Server app password check"))...)
	login = append(login, tlv(0x25, h.Sum(nil))...)
	login = append(login, tlv(0x4C, nil)...)
	if err := snac(0x17, 0x02, login); err != nil {
		return err
	}
	fam, sub, body, err = readSnac()
	for err == nil && !(fam == 0x17 && (sub == 0x03 || sub == 0x01)) {
		fam, sub, body, err = readSnac()
	}
	if err != nil {
		return err
	}
	return loginErr(sub, body)
}

func loginErr(sub uint16, body []byte) error {
	if sub != 0x03 {
		return fmt.Errorf("sign-on error")
	}
	tl := parseTLVs(body)
	if e, ok := tl[0x08]; ok && len(e) >= 2 {
		switch binary.BigEndian.Uint16(e) {
		case 0x11:
			return ErrSuspended
		default:
			return ErrBadLogin
		}
	}
	if _, ok := tl[0x06]; ok {
		return nil // got a sign-on cookie: password is right
	}
	return ErrBadLogin
}

func parseTLVs(b []byte) map[uint16][]byte {
	m := map[uint16][]byte{}
	for len(b) >= 4 {
		t := binary.BigEndian.Uint16(b)
		l := int(binary.BigEndian.Uint16(b[2:]))
		if 4+l > len(b) {
			break
		}
		if _, dup := m[t]; !dup {
			m[t] = b[4 : 4+l]
		}
		b = b[4+l:]
	}
	return m
}

// ---------------------------------------------------------------- management API

// Mgmt talks to Open OSCAR Server's management API (this computer only).
type Mgmt struct {
	Base   string // http://127.0.0.1:port
	client *http.Client
}

func NewMgmt(addr string) *Mgmt {
	return &Mgmt{Base: "http://" + addr, client: &http.Client{Timeout: 10 * time.Second}}
}

type MgmtError struct {
	Status int
	Msg    string
}

func (e *MgmtError) Error() string {
	if e.Msg != "" {
		return e.Msg
	}
	return fmt.Sprintf("server answered %d", e.Status)
}

func (m *Mgmt) do(ctx context.Context, method, path string, in, out any) error {
	var body io.Reader
	if in != nil {
		b, _ := json.Marshal(in)
		body = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, m.Base+path, body)
	if err != nil {
		return err
	}
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := m.client.Do(req)
	if err != nil {
		return errors.New("the AIM server isn't running")
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if resp.StatusCode >= 300 {
		msg := strings.TrimSpace(string(b))
		var j struct {
			Message string `json:"message"`
		}
		if json.Unmarshal(b, &j) == nil && j.Message != "" {
			msg = j.Message
		}
		return &MgmtError{Status: resp.StatusCode, Msg: msg}
	}
	if out != nil && len(b) > 0 {
		return json.Unmarshal(b, out)
	}
	return nil
}

type MgmtUser struct {
	ID              string `json:"id"`
	ScreenName      string `json:"screen_name"`
	IsICQ           bool   `json:"is_icq"`
	SuspendedStatus string `json:"suspended_status"`
}

func (m *Mgmt) Users(ctx context.Context) ([]MgmtUser, error) {
	var u []MgmtUser
	err := m.do(ctx, "GET", "/user", nil, &u)
	return u, err
}

func (m *Mgmt) User(ctx context.Context, sn string) (*MgmtUser, error) {
	var u MgmtUser
	err := m.do(ctx, "GET", "/user/"+url.PathEscape(sn)+"/account", nil, &u)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (m *Mgmt) CreateUser(ctx context.Context, sn, pw string) error {
	return m.do(ctx, "POST", "/user", map[string]string{"screen_name": sn, "password": pw}, nil)
}

func (m *Mgmt) DeleteUser(ctx context.Context, sn string) error {
	return m.do(ctx, "DELETE", "/user", map[string]string{"screen_name": sn}, nil)
}

func (m *Mgmt) SetPassword(ctx context.Context, sn, pw string) error {
	return m.do(ctx, "PUT", "/user/password", map[string]string{"screen_name": sn, "password": pw}, nil)
}

// SetSuspended suspends an account ("suspended") or clears it ("").
func (m *Mgmt) SetSuspended(ctx context.Context, sn string, suspended bool) error {
	v := ""
	if suspended {
		v = "suspended"
	}
	err := m.do(ctx, "PATCH", "/user/"+url.PathEscape(sn)+"/account", map[string]any{"suspended_status": v}, nil)
	var me *MgmtError
	if errors.As(err, &me) && me.Status == 304 {
		return nil
	}
	if err == nil && suspended {
		m.Kick(ctx, sn)
	}
	return err
}

func (m *Mgmt) Kick(ctx context.Context, sn string) error {
	return m.do(ctx, "DELETE", "/session/"+url.PathEscape(sn), nil, nil)
}

type MgmtSession struct {
	ScreenName    string `json:"screen_name"`
	OnlineSeconds int    `json:"online_seconds"`
	IsAway        bool   `json:"is_away"`
	IdleSeconds   int    `json:"idle_seconds"`
	Instances     []struct {
		RemoteAddr string `json:"remote_addr"`
		ClientID   string `json:"client_id"`
	} `json:"instances"`
}

func (m *Mgmt) Sessions(ctx context.Context) ([]MgmtSession, error) {
	var r struct {
		Sessions []MgmtSession `json:"sessions"`
	}
	err := m.do(ctx, "GET", "/session", nil, &r)
	return r.Sessions, err
}

type MgmtRoom struct {
	Name         string `json:"name"`
	Participants []struct {
		ScreenName string `json:"screen_name"`
	} `json:"participants"`
}

func (m *Mgmt) Rooms(ctx context.Context) ([]MgmtRoom, error) {
	var pub, priv []MgmtRoom
	if err := m.do(ctx, "GET", "/chat/room/public", nil, &pub); err != nil {
		return nil, err
	}
	m.do(ctx, "GET", "/chat/room/private", nil, &priv)
	return append(pub, priv...), nil
}
