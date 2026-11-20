package main

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"math/big"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Invite is a sign-up code.
type Invite struct {
	Code    string    `json:"code"`
	Kind    string    `json:"kind"` // single | household
	By      string    `json:"by"`   // inviter's screen name, as shown
	ByOwner bool      `json:"by_owner,omitempty"`
	MaxUses int       `json:"max_uses"`
	Uses    int       `json:"uses"`
	Created time.Time `json:"created"`
	Expires time.Time `json:"expires"`
	Revoked bool      `json:"revoked,omitempty"`
	UsedBy  []string  `json:"used_by,omitempty"`
}

func (i *Invite) Usable(now time.Time) error {
	switch {
	case i.Revoked:
		return errInviteRevoked
	case now.After(i.Expires):
		return errInviteExpired
	case i.Uses >= i.MaxUses:
		return errInviteUsed
	}
	return nil
}

var (
	errInviteRevoked = errors.New("This invite was cancelled.")
	errInviteExpired = errors.New("This invite has expired. Ask for a new one.")
	errInviteUsed    = errors.New("This invite has already been used. Ask for a new one.")
)

// Account is a sign-up the app knows about (accounts made elsewhere aren't here).
type Account struct {
	ScreenName string    `json:"screen_name"`
	InvitedBy  string    `json:"invited_by"`
	Code       string    `json:"code"`
	IP         string    `json:"ip"`
	Device     string    `json:"device"`
	Created    time.Time `json:"created"`
	Status     string    `json:"status"` // ok | review | suspended
	Reason     string    `json:"reason,omitempty"`
}

// Mark is a ban or a trust entry on an IP, device id or inviter.
type Mark struct {
	Kind   string    `json:"kind"` // ip | device | inviter
	Value  string    `json:"value"`
	Note   string    `json:"note,omitempty"`
	At     time.Time `json:"at"`
	Expire time.Time `json:"expire,omitempty"`
}

type StoreData struct {
	Invites      []*Invite  `json:"invites"`
	Accounts     []*Account `json:"accounts"`
	Bans         []*Mark    `json:"bans"`
	Trusted      []*Mark    `json:"trusted"`
	FailedLogins []*Mark    `json:"-"` // password-check failures, in memory only
}

// Store keeps invites, sign-ups, bans and trusted households in state.json.
type Store struct {
	mu   sync.Mutex
	path string
	d    StoreData
}

func OpenStore(dir string) (*Store, error) {
	s := &Store{path: filepath.Join(dir, "state.json")}
	b, err := os.ReadFile(s.path)
	if err == nil {
		if err := json.Unmarshal(b, &s.d); err != nil {
			return nil, err
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	return s, nil
}

// Do runs f with the store locked and saves afterwards.
func (s *Store) Do(f func(d *StoreData) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := f(&s.d); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(&s.d, "", "  ")
	return writeFileAtomic(s.path, b, 0o600)
}

// Read runs f with the store locked, without saving.
func (s *Store) Read(f func(d *StoreData)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	f(&s.d)
}

// ---------------------------------------------------------------- helpers

// ident is the comparable form of a screen name ("New Kid" -> "newkid").
func ident(sn string) string {
	return strings.ToLower(strings.ReplaceAll(sn, " ", ""))
}

// ValidateScreenName mirrors Open OSCAR Server's rules.
func ValidateScreenName(sn string) error {
	if sn == "" || !isLetter(sn[0]) || strings.HasSuffix(sn, " ") {
		return errors.New("Screen names must start with a letter and use only letters, numbers and spaces.")
	}
	for i := 0; i < len(sn); i++ {
		c := sn[i]
		if !isLetter(c) && !(c >= '0' && c <= '9') && c != ' ' {
			return errors.New("Screen names must start with a letter and use only letters, numbers and spaces.")
		}
	}
	if n := len(strings.ReplaceAll(sn, " ", "")); n < 3 || len(sn) > 16 {
		return errors.New("Screen names must be 3 to 16 characters long.")
	}
	return nil
}

func isLetter(c byte) bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') }

func ValidatePassword(pw string) error {
	if len(pw) < 4 || len(pw) > 16 {
		return errors.New("Passwords must be 4 to 16 characters long.")
	}
	return nil
}

// Code alphabet: no 0/O/1/I so codes read clearly aloud.
const codeAlphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

func NewCode() string {
	b := make([]byte, 8)
	for i := range b {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(codeAlphabet))))
		b[i] = codeAlphabet[n.Int64()]
	}
	return string(b[:4]) + "-" + string(b[4:])
}

// NormalizeCode accepts "7kq2m9xd", "7KQ2-M9XD", " 7kq2 m9xd ".
func NormalizeCode(c string) string {
	var b []byte
	for _, r := range strings.ToUpper(c) {
		if r < 128 && strings.IndexByte(codeAlphabet, byte(r)) >= 0 {
			b = append(b, byte(r))
		}
	}
	if len(b) != 8 {
		return string(b)
	}
	return string(b[:4]) + "-" + string(b[4:])
}

func (d *StoreData) Invite(code string) *Invite {
	code = NormalizeCode(code)
	for _, i := range d.Invites {
		if i.Code == code {
			return i
		}
	}
	return nil
}

func (d *StoreData) Account(sn string) *Account {
	id := ident(sn)
	for _, a := range d.Accounts {
		if ident(a.ScreenName) == id {
			return a
		}
	}
	return nil
}

func markValue(kind, v string) string {
	if kind == "inviter" {
		return ident(v)
	}
	return strings.TrimSpace(v)
}

func findMark(list []*Mark, kind, value string, now time.Time) *Mark {
	if value == "" {
		return nil
	}
	v := markValue(kind, value)
	for _, m := range list {
		if m.Kind == kind && markValue(kind, m.Value) == v && (m.Expire.IsZero() || now.Before(m.Expire)) {
			return m
		}
	}
	return nil
}

func (d *StoreData) IsBanned(kind, value string, now time.Time) bool {
	return findMark(d.Bans, kind, value, now) != nil
}

func (d *StoreData) IsTrusted(kind, value string, now time.Time) bool {
	return findMark(d.Trusted, kind, value, now) != nil
}

func addMark(list []*Mark, kind, value, note string, now time.Time) []*Mark {
	if value == "" || findMark(list, kind, value, now) != nil {
		return list
	}
	return append(list, &Mark{Kind: kind, Value: strings.TrimSpace(value), Note: note, At: now})
}

func removeMark(list []*Mark, kind, value string) []*Mark {
	v := markValue(kind, value)
	out := list[:0]
	for _, m := range list {
		if !(m.Kind == kind && markValue(kind, m.Value) == v) {
			out = append(out, m)
		}
	}
	return out
}

// ---------------------------------------------------------------- abuse limits

type Verdict int

const (
	VerdictOK Verdict = iota
	VerdictFlag
	VerdictBan
)

// AbuseCheck decides what to do with a new sign-up from ip/device using an
// invite from inviter. Reason explains which limit tripped; Burst lists the
// recent accounts that share the tripped signal (suspended on a ban).
type AbuseResult struct {
	Verdict Verdict
	Reason  string
	Burst   []*Account
}

func (d *StoreData) AbuseCheck(l Limits, ip, device, inviter string, inviterIsOwner bool, now time.Time) AbuseResult {
	if d.IsTrusted("ip", ip, now) || d.IsTrusted("device", device, now) {
		return AbuseResult{}
	}
	day, burst := now.Add(-24*time.Hour), now.Add(-10*time.Minute)
	type signal struct {
		name              string
		allow, ban        int
		match             func(a *Account) bool
		skip              bool
		count, quick      int
		accts, quickAccts []*Account
	}
	sigs := []*signal{
		{name: "same IP address", allow: l.IPAllow, ban: l.IPBan, match: func(a *Account) bool { return a.IP == ip }, skip: ip == ""},
		{name: "same device", allow: l.DeviceAllow, ban: l.DeviceBan, match: func(a *Account) bool { return a.Device == device }, skip: device == ""},
		{name: "same inviter", allow: l.InviterAllow, ban: l.InviterBan,
			match: func(a *Account) bool { return ident(a.InvitedBy) == ident(inviter) }, skip: inviter == "" || inviterIsOwner},
	}
	for _, a := range d.Accounts {
		if a.Created.Before(day) {
			continue
		}
		for _, s := range sigs {
			if s.skip || !s.match(a) {
				continue
			}
			s.count++
			s.accts = append(s.accts, a)
			if !a.Created.Before(burst) {
				s.quick++
				s.quickAccts = append(s.quickAccts, a)
			}
		}
	}
	res := AbuseResult{}
	for _, s := range sigs {
		if s.skip {
			continue
		}
		n, q := s.count+1, s.quick+1 // including this sign-up
		switch {
		case n >= s.ban:
			return AbuseResult{VerdictBan, "too many sign-ups from the " + s.name + " in 24 hours", s.accts}
		case q >= l.BurstBan:
			return AbuseResult{VerdictBan, "too many sign-ups from the " + s.name + " in 10 minutes", s.quickAccts}
		case n > s.allow && res.Verdict == VerdictOK:
			res = AbuseResult{VerdictFlag, "many sign-ups from the " + s.name + " in 24 hours", nil}
		case q >= l.BurstFlag && res.Verdict == VerdictOK:
			res = AbuseResult{VerdictFlag, "many sign-ups from the " + s.name + " in 10 minutes", nil}
		}
	}
	return res
}

// TooManyFailures limits password guessing through the invite API.
func (d *StoreData) TooManyFailures(ip string, now time.Time) bool {
	n := 0
	keep := d.FailedLogins[:0]
	for _, m := range d.FailedLogins {
		if now.Sub(m.At) < time.Hour {
			keep = append(keep, m)
			if m.Value == ip {
				n++
			}
		}
	}
	d.FailedLogins = keep
	return n >= 10
}

// InviteTree is who invited whom, for the control panel.
type TreeNode struct {
	ScreenName string      `json:"screen_name"`
	Status     string      `json:"status,omitempty"`
	Created    time.Time   `json:"created,omitempty"`
	Children   []*TreeNode `json:"children,omitempty"`
}

func (d *StoreData) Tree() []*TreeNode {
	nodes := map[string]*TreeNode{}
	get := func(sn string) *TreeNode {
		id := ident(sn)
		if n, ok := nodes[id]; ok {
			return n
		}
		n := &TreeNode{ScreenName: sn}
		nodes[id] = n
		return n
	}
	hasParent := map[string]bool{}
	for _, a := range d.Accounts {
		n := get(a.ScreenName)
		n.ScreenName, n.Status, n.Created = a.ScreenName, a.Status, a.Created
		p := get(a.InvitedBy)
		p.Children = append(p.Children, n)
		hasParent[ident(a.ScreenName)] = true
	}
	var roots []*TreeNode
	for id, n := range nodes {
		if !hasParent[id] {
			roots = append(roots, n)
		}
	}
	sort.Slice(roots, func(i, j int) bool { return ident(roots[i].ScreenName) < ident(roots[j].ScreenName) })
	// copy without loops (a re-created name could point back up the tree)
	seen := map[string]bool{}
	var cp func(n *TreeNode) *TreeNode
	cp = func(n *TreeNode) *TreeNode {
		seen[ident(n.ScreenName)] = true
		out := &TreeNode{ScreenName: n.ScreenName, Status: n.Status, Created: n.Created}
		for _, c := range n.Children {
			if !seen[ident(c.ScreenName)] {
				out.Children = append(out.Children, cp(c))
			}
		}
		return out
	}
	var res []*TreeNode
	for _, r := range roots {
		res = append(res, cp(r))
	}
	return res
}
