package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
)

//go:embed panel.html
var panelHTML []byte

// Panel is the control panel, served only to this computer.
type Panel struct {
	App   *App
	Token string
	Port  int
	Quit  func()
}

func (p *Panel) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("aim-server")) })
	mux.HandleFunc("/", p.index)
	mux.HandleFunc("/favicon.ico", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) })
	api := map[string]func(*http.Request) (any, error){
		"GET /api/status":             p.status,
		"POST /api/start":             func(*http.Request) (any, error) { return nil, p.App.Start() },
		"POST /api/stop":              func(*http.Request) (any, error) { p.App.StopAndRemember(); return nil, nil },
		"POST /api/quit":              p.quit,
		"POST /api/recheck":           p.recheck,
		"GET /api/settings":           func(*http.Request) (any, error) { return p.App.Settings.Get(), nil },
		"POST /api/settings":          p.saveSettings,
		"GET /api/accounts":           p.accounts,
		"POST /api/accounts/add":      p.addAccount,
		"POST /api/accounts/delete":   p.deleteAccount,
		"POST /api/accounts/password": p.setPassword,
		"POST /api/accounts/suspend":  p.suspend,
		"POST /api/accounts/kick":     p.kick,
		"GET /api/online":             p.online,
		"GET /api/invites":            p.invites,
		"POST /api/invites/add":       p.addInvite,
		"POST /api/invites/revoke":    p.revokeInvite,
		"GET /api/review":             p.review,
		"POST /api/review/approve":    p.approve,
		"POST /api/marks/add":         p.addMark,
		"POST /api/marks/remove":      p.removeMark,
		"GET /api/log":                func(*http.Request) (any, error) { return p.App.Log.Lines(), nil },
		"GET /api/clients":            func(*http.Request) (any, error) { return p.App.Clients.Info(), nil },
		"POST /api/clients/refresh":   p.refreshClients,
	}
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		if !p.authorized(r) {
			http.Error(w, `{"error":"Open the control panel from the AIM Server app."}`, 401)
			return
		}
		f, ok := api[r.Method+" "+r.URL.Path]
		if !ok {
			http.Error(w, `{"error":"not found"}`, 404)
			return
		}
		out, err := f(r)
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		if err != nil {
			w.WriteHeader(400)
			json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
			return
		}
		if out == nil {
			out = map[string]bool{"ok": true}
		}
		json.NewEncoder(w).Encode(out)
	})
	return p.guard(mux)
}

// guard blocks requests that didn't come to 127.0.0.1/localhost by name
// (stops web pages using DNS tricks to reach the panel).
func (p *Panel) guard(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, err := net.SplitHostPort(r.Host)
		if err != nil {
			host = r.Host
		}
		if host != "127.0.0.1" && host != "localhost" && host != "[::1]" && host != "::1" {
			http.Error(w, "forbidden", 403)
			return
		}
		w.Header().Set("X-Frame-Options", "DENY")
		h.ServeHTTP(w, r)
	})
}

const cookieName = "aimpanel"

func (p *Panel) authorized(r *http.Request) bool {
	c, err := r.Cookie(cookieName)
	if err != nil || c.Value != p.Token {
		return false
	}
	if r.Method != http.MethodGet && r.Header.Get("X-AIM-Panel") != "1" {
		return false // custom header: other web pages can't send it
	}
	return true
}

func (p *Panel) URL() string {
	return "http://127.0.0.1:" + strconv.Itoa(p.Port) + "/?t=" + p.Token
}

func (p *Panel) index(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	if t := r.URL.Query().Get("t"); t != "" {
		if t == p.Token {
			http.SetCookie(w, &http.Cookie{Name: cookieName, Value: p.Token, Path: "/", HttpOnly: true,
				SameSite: http.SameSiteStrictMode, MaxAge: 10 * 365 * 24 * 3600})
		}
		http.Redirect(w, r, "/", http.StatusFound)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Write(panelHTML)
}

func decode(r *http.Request, v any) error {
	if err := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 64<<10)).Decode(v); err != nil {
		return errors.New("bad request")
	}
	return nil
}

func (p *Panel) mgmt() (*Mgmt, error) {
	m := p.App.Mgmt()
	if m == nil {
		return nil, errors.New("Start the server first.")
	}
	return m, nil
}

func ctx5() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 10*time.Second)
}

// ---------------------------------------------------------------- status

func (p *Panel) status(*http.Request) (any, error) {
	a := p.App
	st, lastErr := a.State()
	set := a.Settings.Get()
	n := a.Net()
	var warnings []string
	port := strconv.Itoa(set.Port)
	if n.CGNAT {
		warnings = append(warnings, "Your internet provider seems to share one internet address between many homes "+
			"(called CGNAT): your router's address ("+n.RouterIP+") isn't your public address. People outside your home "+
			"probably can't reach this server, even with the port open. People on your home Wi-Fi can. Fixes: ask your "+
			"provider for a public IP address, or use a VPN app like Tailscale.")
	}
	if st == "running" && set.UPnP && n.UPnPState == "failed" {
		warnings = append(warnings, "Couldn't open the port on your router automatically ("+n.UPnPMessage+"). "+
			"To let people outside your home in, open your router's settings page and forward TCP port "+port+
			" to "+n.LocalIP+" (this computer).")
	}
	if st == "running" && !set.UPnP {
		warnings = append(warnings, "Automatic port opening is off. For people outside your home, forward TCP port "+
			port+" on your router to "+n.LocalIP+".")
	}
	if n.PublicChanged != "" {
		warnings = append(warnings, n.PublicChanged+" Tip: a free dynamic DNS name (Settings → Server address) keeps links working.")
	}
	if st == "running" && n.PublicIP == "" && !a.NoNetworkChecks {
		warnings = append(warnings, "Couldn't find your public internet address. Is this computer online?")
	}
	if _, err := FindOscarBinary(a.OscarBin, a.Dir); err != nil {
		warnings = append(warnings, "Problem: "+err.Error())
	}
	var accounts, review, invites int
	a.Store.Read(func(d *StoreData) {
		accounts = len(d.Accounts)
		for _, x := range d.Accounts {
			if x.Status != "ok" {
				review++
			}
		}
		now := time.Now()
		for _, i := range d.Invites {
			if i.Usable(now) == nil {
				invites++
			}
		}
	})
	online := -1
	if m := a.Mgmt(); m != nil {
		c, cancel := ctx5()
		if s, err := m.Sessions(c); err == nil {
			online = len(s)
		}
		cancel()
	}
	return map[string]any{
		"state": st, "error": lastErr, "port": set.Port, "net": n, "warnings": warnings,
		"invite_host": a.InviteHost(""), "fingerprint": a.FP, "server_name": set.ServerName,
		"lan_address": net.JoinHostPort(n.LocalIP, port), "public_address": addrOrEmpty(n.PublicIP, port),
		"hostname": set.Hostname, "accounts": accounts, "review": review, "invites": invites, "online": online,
		"require_passwords": set.RequirePasswords, "data_dir": a.Dir,
	}, nil
}

func addrOrEmpty(ip, port string) string {
	if ip == "" {
		return ""
	}
	return net.JoinHostPort(ip, port)
}

func (p *Panel) quit(*http.Request) (any, error) {
	go func() {
		time.Sleep(300 * time.Millisecond)
		p.App.Stop()
		p.Quit()
	}()
	return nil, nil
}

func (p *Panel) recheck(*http.Request) (any, error) {
	p.App.Recheck()
	return nil, nil
}

func (p *Panel) saveSettings(r *http.Request) (any, error) {
	var in Settings
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	in.Hostname = strings.TrimSpace(in.Hostname)
	if strings.ContainsAny(in.Hostname, " /:@") {
		return nil, errors.New("Server address should be a plain name like myaim.duckdns.org (no http://, no port).")
	}
	old := p.App.Settings.Get()
	_, err := p.App.Settings.Update(func(s *Settings) {
		lastIP, auto := s.LastPublicIP, s.AutoStart
		*s = in
		s.LastPublicIP, s.AutoStart = lastIP, auto
	})
	if err != nil {
		return nil, err
	}
	nw := p.App.Settings.Get()
	needRestart := old.Port != nw.Port || old.InternalBase != nw.InternalBase || old.Hostname != nw.Hostname ||
		old.RequirePasswords != nw.RequirePasswords || old.UPnP != nw.UPnP
	if needRestart {
		if st, _ := p.App.State(); st == "running" {
			go p.App.Restart()
			return map[string]any{"ok": true, "restarted": true}, nil
		}
	}
	return nil, nil
}

func (p *Panel) refreshClients(*http.Request) (any, error) {
	go p.App.Clients.Refresh(context.Background(), true)
	return nil, nil
}

// ---------------------------------------------------------------- accounts

type accountRow struct {
	ScreenName string    `json:"screen_name"`
	Suspended  bool      `json:"suspended"`
	InvitedBy  string    `json:"invited_by,omitempty"`
	Code       string    `json:"code,omitempty"`
	IP         string    `json:"ip,omitempty"`
	Device     string    `json:"device,omitempty"`
	Created    time.Time `json:"created,omitempty"`
	Status     string    `json:"status,omitempty"`
	Reason     string    `json:"reason,omitempty"`
	Online     bool      `json:"online"`
}

func (p *Panel) accounts(*http.Request) (any, error) {
	m, err := p.mgmt()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx5()
	defer cancel()
	users, err := m.Users(c)
	if err != nil {
		return nil, err
	}
	online := map[string]bool{}
	if ss, err := m.Sessions(c); err == nil {
		for _, s := range ss {
			online[ident(s.ScreenName)] = true
		}
	}
	rows := []accountRow{}
	p.App.Store.Read(func(d *StoreData) {
		for _, u := range users {
			if u.IsICQ {
				continue
			}
			row := accountRow{ScreenName: u.ScreenName, Suspended: u.SuspendedStatus != "", Online: online[ident(u.ScreenName)]}
			if a := d.Account(u.ScreenName); a != nil {
				row.InvitedBy, row.Code, row.IP, row.Device, row.Created, row.Status, row.Reason =
					a.InvitedBy, a.Code, a.IP, a.Device, a.Created, a.Status, a.Reason
			}
			rows = append(rows, row)
		}
	})
	sort.Slice(rows, func(i, j int) bool { return ident(rows[i].ScreenName) < ident(rows[j].ScreenName) })
	return rows, nil
}

type snReq struct {
	ScreenName string `json:"screen_name"`
	Password   string `json:"password"`
	Suspended  bool   `json:"suspended"`
}

func (p *Panel) addAccount(r *http.Request) (any, error) {
	var in snReq
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	in.ScreenName = strings.TrimSpace(in.ScreenName)
	if err := ValidateScreenName(in.ScreenName); err != nil {
		return nil, err
	}
	if err := ValidatePassword(in.Password); err != nil {
		return nil, err
	}
	m, err := p.mgmt()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx5()
	defer cancel()
	if err := m.CreateUser(c, in.ScreenName, in.Password); err != nil {
		var me *MgmtError
		if errors.As(err, &me) && me.Status == 409 {
			return nil, errors.New("That screen name is taken.")
		}
		return nil, err
	}
	p.App.Log.Add("Owner created account %s", in.ScreenName)
	return nil, nil
}

func (p *Panel) deleteAccount(r *http.Request) (any, error) {
	var in snReq
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	m, err := p.mgmt()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx5()
	defer cancel()
	m.Kick(c, in.ScreenName)
	if err := m.DeleteUser(c, in.ScreenName); err != nil {
		return nil, err
	}
	p.App.Store.Do(func(d *StoreData) error {
		out := d.Accounts[:0]
		for _, a := range d.Accounts {
			if ident(a.ScreenName) != ident(in.ScreenName) {
				out = append(out, a)
			}
		}
		d.Accounts = out
		return nil
	})
	p.App.Log.Add("Owner deleted account %s", in.ScreenName)
	return nil, nil
}

func (p *Panel) setPassword(r *http.Request) (any, error) {
	var in snReq
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if err := ValidatePassword(in.Password); err != nil {
		return nil, err
	}
	m, err := p.mgmt()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx5()
	defer cancel()
	return nil, m.SetPassword(c, in.ScreenName, in.Password)
}

func (p *Panel) suspend(r *http.Request) (any, error) {
	var in snReq
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	m, err := p.mgmt()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx5()
	defer cancel()
	if err := m.SetSuspended(c, in.ScreenName, in.Suspended); err != nil {
		return nil, err
	}
	p.App.Store.Do(func(d *StoreData) error {
		if a := d.Account(in.ScreenName); a != nil {
			if in.Suspended {
				a.Status, a.Reason = "suspended", "suspended by owner"
			} else {
				a.Status, a.Reason = "ok", ""
			}
		}
		return nil
	})
	return nil, nil
}

func (p *Panel) kick(r *http.Request) (any, error) {
	var in snReq
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	m, err := p.mgmt()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx5()
	defer cancel()
	return nil, m.Kick(c, in.ScreenName)
}

func (p *Panel) online(*http.Request) (any, error) {
	m, err := p.mgmt()
	if err != nil {
		return nil, err
	}
	c, cancel := ctx5()
	defer cancel()
	ss, err := m.Sessions(c)
	if err != nil {
		return nil, err
	}
	rooms, _ := m.Rooms(c)
	if ss == nil {
		ss = []MgmtSession{}
	}
	if rooms == nil {
		rooms = []MgmtRoom{}
	}
	return map[string]any{"sessions": ss, "rooms": rooms}, nil
}

// ---------------------------------------------------------------- invites

type inviteRow struct {
	*Invite
	Link   string `json:"link"`
	Active bool   `json:"active"`
	State  string `json:"state"`
}

func (p *Panel) invites(*http.Request) (any, error) {
	host := p.App.InviteHost("")
	now := time.Now()
	var rows []inviteRow
	var tree []*TreeNode
	p.App.Store.Read(func(d *StoreData) {
		for i := len(d.Invites) - 1; i >= 0; i-- {
			inv := *d.Invites[i]
			st := "active"
			if err := inv.Usable(now); err != nil {
				switch err {
				case errInviteExpired:
					st = "expired"
				case errInviteUsed:
					st = "used up"
				default:
					st = "cancelled"
				}
			}
			rows = append(rows, inviteRow{Invite: &inv, Link: p.App.InviteLink(host, &inv), Active: st == "active", State: st})
		}
		tree = d.Tree()
	})
	if rows == nil {
		rows = []inviteRow{}
	}
	return map[string]any{"invites": rows, "tree": tree, "host": host}, nil
}

func (p *Panel) addInvite(r *http.Request) (any, error) {
	var in struct {
		By   string `json:"by"`
		Kind string `json:"kind"`
		Uses int    `json:"uses"`
		Days int    `json:"days"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	by := strings.TrimSpace(in.By)
	if by == "" {
		by = p.App.Settings.Get().ServerName
	}
	inv, err := p.App.CreateInvite(by, true, in.Kind, in.Uses, in.Days)
	if err != nil {
		return nil, err
	}
	p.App.Log.Add("Owner created a %s invite %s (from %s)", inv.Kind, inv.Code, by)
	return map[string]any{"code": inv.Code, "link": p.App.InviteLink(p.App.InviteHost(""), inv)}, nil
}

func (p *Panel) revokeInvite(r *http.Request) (any, error) {
	var in struct {
		Code string `json:"code"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	return nil, p.App.Store.Do(func(d *StoreData) error {
		inv := d.Invite(in.Code)
		if inv == nil {
			return errors.New("no such invite")
		}
		inv.Revoked = true
		return nil
	})
}

// ---------------------------------------------------------------- review, bans, trust

func (p *Panel) review(*http.Request) (any, error) {
	var flagged []*Account
	var bans, trusted []*Mark
	p.App.Store.Read(func(d *StoreData) {
		for _, a := range d.Accounts {
			if a.Status != "ok" {
				c := *a
				flagged = append(flagged, &c)
			}
		}
		bans = append(bans, d.Bans...)
		trusted = append(trusted, d.Trusted...)
	})
	if flagged == nil {
		flagged = []*Account{}
	}
	if bans == nil {
		bans = []*Mark{}
	}
	if trusted == nil {
		trusted = []*Mark{}
	}
	return map[string]any{"accounts": flagged, "bans": bans, "trusted": trusted}, nil
}

func (p *Panel) approve(r *http.Request) (any, error) {
	var in snReq
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	var wasSuspended bool
	err := p.App.Store.Do(func(d *StoreData) error {
		a := d.Account(in.ScreenName)
		if a == nil {
			return errors.New("no such account")
		}
		wasSuspended = a.Status == "suspended"
		a.Status, a.Reason = "ok", ""
		return nil
	})
	if err != nil {
		return nil, err
	}
	if wasSuspended {
		m, err := p.mgmt()
		if err != nil {
			return nil, err
		}
		c, cancel := ctx5()
		defer cancel()
		return nil, m.SetSuspended(c, in.ScreenName, false)
	}
	return nil, nil
}

type markReq struct {
	List  string `json:"list"` // bans | trusted
	Kind  string `json:"kind"` // ip | device | inviter
	Value string `json:"value"`
	Note  string `json:"note"`
}

func (p *Panel) addMark(r *http.Request) (any, error) {
	var in markReq
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if in.Kind != "ip" && in.Kind != "device" && in.Kind != "inviter" {
		return nil, errors.New("kind must be ip, device or inviter")
	}
	if strings.TrimSpace(in.Value) == "" {
		return nil, errors.New("enter a value")
	}
	if in.Kind == "ip" && net.ParseIP(strings.TrimSpace(in.Value)) == nil {
		return nil, errors.New("that isn't an IP address")
	}
	now := time.Now().UTC()
	return nil, p.App.Store.Do(func(d *StoreData) error {
		if in.List == "trusted" {
			d.Trusted = addMark(d.Trusted, in.Kind, in.Value, in.Note, now)
		} else {
			d.Bans = addMark(d.Bans, in.Kind, in.Value, in.Note, now)
		}
		return nil
	})
}

func (p *Panel) removeMark(r *http.Request) (any, error) {
	var in markReq
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	return nil, p.App.Store.Do(func(d *StoreData) error {
		if in.List == "trusted" {
			d.Trusted = removeMark(d.Trusted, in.Kind, in.Value)
		} else {
			d.Bans = removeMark(d.Bans, in.Kind, in.Value)
		}
		return nil
	})
}
