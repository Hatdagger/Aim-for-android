package main

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"strings"
	"time"
)

// apiHandler serves the account API (HTTPS on the public port).
func (a *App) apiHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/signup", a.handleSignup)
	mux.HandleFunc("/api/v1/invites", a.handleCreateInvite)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" || strings.HasPrefix(r.URL.Path, "/i/") {
			a.webHandler().ServeHTTP(w, r) // invite pages work over https too
			return
		}
		apiErr(w, 404, "not_found", "Not found.")
	})
	return mux
}

func apiErr(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": msg, "code": code})
}

func apiOK(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	if r.Method != http.MethodPost {
		apiErr(w, 405, "method", "Use POST.")
		return false
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(v); err != nil {
		apiErr(w, 400, "bad_request", "That request didn't make sense to the server.")
		return false
	}
	return true
}

type signupReq struct {
	InviteCode string `json:"invite_code"`
	ScreenName string `json:"screen_name"`
	Password   string `json:"password"`
	DeviceID   string `json:"device_id"`
}

func cleanDevice(id string) string {
	id = strings.TrimSpace(id)
	if len(id) > 64 {
		id = id[:64]
	}
	return id
}

func (a *App) handleSignup(w http.ResponseWriter, r *http.Request) {
	var req signupReq
	if !readJSON(w, r, &req) {
		return
	}
	status, code, msg := a.Signup(r.Context(), req, hostOnly(r.RemoteAddr))
	if status != 200 {
		apiErr(w, status, code, msg)
		return
	}
	apiOK(w, map[string]any{"ok": true})
}

// Signup creates an account from an invite. Returns HTTP status, error code, message.
func (a *App) Signup(ctx context.Context, req signupReq, ip string) (int, string, string) {
	mg := a.Mgmt()
	if mg == nil {
		return 503, "offline", "The AIM server is offline right now. Try again later."
	}
	sn := strings.TrimSpace(req.ScreenName)
	dev := cleanDevice(req.DeviceID)
	if dev == "" {
		return 400, "bad_request", "This app is missing its device id. Update the app."
	}
	if err := ValidateScreenName(sn); err != nil {
		return 400, "name_invalid", err.Error()
	}
	if err := ValidatePassword(req.Password); err != nil {
		return 400, "password_weak", err.Error()
	}
	limits := a.Settings.Get().Limits
	now := time.Now().UTC()

	var status int
	var code, msg string
	var suspendLater []string
	err := a.Store.Do(func(d *StoreData) error {
		if d.IsBanned("ip", ip, now) || d.IsBanned("device", dev, now) {
			status, code, msg = 403, "banned", "Sign-ups from this device or network are blocked. Ask the server owner."
			return errors.New("stop")
		}
		inv := d.Invite(req.InviteCode)
		if inv == nil {
			status, code, msg = 404, "invalid_invite", "That invite code isn't valid. Check it and try again."
			return errors.New("stop")
		}
		if err := inv.Usable(now); err != nil {
			status, code = 410, "invite_used"
			if err == errInviteExpired {
				code = "invite_expired"
			} else if err == errInviteRevoked {
				code = "invalid_invite"
			}
			msg = err.Error()
			return errors.New("stop")
		}
		if !inv.ByOwner && d.IsBanned("inviter", inv.By, now) {
			status, code, msg = 410, "invalid_invite", "This invite is no longer valid."
			return errors.New("stop")
		}
		if d.Account(sn) != nil {
			status, code, msg = 409, "name_taken", "That screen name is taken. Try another."
			return errors.New("stop")
		}
		verdict := d.AbuseCheck(limits, ip, dev, inv.By, inv.ByOwner, now)
		if verdict.Verdict == VerdictBan {
			d.Bans = addMark(d.Bans, "ip", ip, "auto: "+verdict.Reason, now)
			d.Bans = addMark(d.Bans, "device", dev, "auto: "+verdict.Reason, now)
			if !inv.ByOwner {
				d.Bans = addMark(d.Bans, "inviter", inv.By, "auto: "+verdict.Reason, now)
			}
			for _, acct := range verdict.Burst {
				if acct.Status != "suspended" {
					acct.Status, acct.Reason = "suspended", "auto: "+verdict.Reason
					suspendLater = append(suspendLater, acct.ScreenName)
				}
			}
			a.Log.Add("Sign-up blocked and banned (IP %s, device %.8s…, inviter %s): %s", ip, dev, inv.By, verdict.Reason)
			status, code, msg = 429, "rate_limited", "Too many accounts have been made from here. The server owner has been asked to review it."
			return nil // save the bans
		}
		// create the account on the server while holding the lock so two
		// sign-ups can't race for one invite
		cctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()
		if err := mg.CreateUser(cctx, sn, req.Password); err != nil {
			var me *MgmtError
			switch {
			case errors.As(err, &me) && me.Status == 409:
				status, code, msg = 409, "name_taken", "That screen name is taken. Try another."
			case errors.As(err, &me) && me.Status == 400:
				status, code, msg = 400, "name_invalid", me.Msg
				if strings.Contains(strings.ToLower(me.Msg), "password") {
					code = "password_weak"
				}
			default:
				status, code, msg = 503, "offline", "The AIM server couldn't create the account: "+err.Error()
			}
			return errors.New("stop")
		}
		acct := &Account{ScreenName: sn, InvitedBy: inv.By, Code: inv.Code, IP: ip, Device: dev,
			Created: now, Status: "ok"}
		if verdict.Verdict == VerdictFlag {
			acct.Status, acct.Reason = "review", verdict.Reason
			a.Log.Add("New account %s flagged for review: %s", sn, verdict.Reason)
		}
		d.Accounts = append(d.Accounts, acct)
		inv.Uses++
		inv.UsedBy = append(inv.UsedBy, sn)
		status = 200
		a.Log.Add("New account %s (invited by %s, code %s)", sn, inv.By, inv.Code)
		return nil
	})
	if err != nil && status == 0 {
		return 500, "server_error", "The server couldn't save that. Try again."
	}
	for _, sn := range suspendLater {
		c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		if err := mg.SetSuspended(c, sn, true); err != nil {
			a.Log.Add("Couldn't suspend %s: %v", sn, err)
		}
		cancel()
	}
	return status, code, msg
}

type inviteReq struct {
	ScreenName string `json:"screen_name"`
	Password   string `json:"password"`
	DeviceID   string `json:"device_id"`
	Kind       string `json:"kind"`
}

func (a *App) handleCreateInvite(w http.ResponseWriter, r *http.Request) {
	var req inviteReq
	if !readJSON(w, r, &req) {
		return
	}
	mg := a.Mgmt()
	if mg == nil {
		apiErr(w, 503, "offline", "The AIM server is offline right now. Try again later.")
		return
	}
	ip := hostOnly(r.RemoteAddr)
	now := time.Now().UTC()
	sn := strings.TrimSpace(req.ScreenName)
	limits := a.Settings.Get().Limits

	var blocked bool
	a.Store.Read(func(d *StoreData) {
		blocked = d.TooManyFailures(ip, now)
	})
	if blocked {
		apiErr(w, 429, "rate_limited", "Too many wrong passwords. Wait an hour and try again.")
		return
	}
	a.mu.Lock()
	lanAddr := a.ocfg.LANListen
	a.mu.Unlock()
	if err := CheckPasswordFrom(net.ParseIP(ip), lanAddr, sn, req.Password); err != nil {
		switch {
		case errors.Is(err, ErrSuspended):
			apiErr(w, 403, "banned", "This account is suspended.")
		case errors.Is(err, ErrTooFast):
			apiErr(w, 429, "rate_limited", "Too many sign-on attempts. Wait a minute and try again.")
		case errors.Is(err, ErrBadLogin):
			a.Store.Read(func(d *StoreData) {
				d.FailedLogins = append(d.FailedLogins, &Mark{Kind: "ip", Value: ip, At: now})
			})
			apiErr(w, 401, "bad_login", "Incorrect screen name or password.")
		default:
			apiErr(w, 503, "offline", "The AIM server couldn't check your password right now.")
		}
		return
	}
	display := sn
	if u, err := mg.User(r.Context(), sn); err == nil && u.ScreenName != "" {
		display = u.ScreenName
	}
	var deny string
	a.Store.Read(func(d *StoreData) {
		if d.IsBanned("inviter", display, now) {
			deny = "banned"
			return
		}
		if acct := d.Account(display); acct != nil && acct.Status != "ok" {
			deny = "review"
			return
		}
		n := 0
		for _, inv := range d.Invites {
			if !inv.ByOwner && ident(inv.By) == ident(display) && now.Sub(inv.Created) < 24*time.Hour {
				n++
			}
		}
		if n >= limits.InvitesPerDay {
			deny = "limit"
		}
	})
	switch deny {
	case "banned":
		apiErr(w, 403, "banned", "You can't create invites on this server. Ask the server owner.")
		return
	case "review":
		apiErr(w, 403, "banned", "Your account is waiting for the server owner to approve it before you can invite people.")
		return
	case "limit":
		apiErr(w, 429, "rate_limited", "You've made a lot of invites today. Try again tomorrow.")
		return
	}
	inv, err := a.CreateInvite(display, false, req.Kind, 0, 0)
	if err != nil {
		apiErr(w, 500, "server_error", "The server couldn't save the invite.")
		return
	}
	host := a.InviteHost("")
	a.Log.Add("%s created a %s invite %s", display, inv.Kind, inv.Code)
	apiOK(w, map[string]any{
		"code":       inv.Code,
		"link":       a.InviteLink(host, inv),
		"app_link":   a.AppLink(host, inv),
		"uses_left":  inv.MaxUses - inv.Uses,
		"expires_at": inv.Expires.Format(time.RFC3339),
	})
}
