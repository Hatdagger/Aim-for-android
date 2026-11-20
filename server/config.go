package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

// Limits are the sign-up abuse limits. "Allow" is how many sign-ups in 24 hours
// are fine; above that new accounts are flagged for review; at "Ban" the
// sign-up is refused and the device, IP and inviter are banned.
type Limits struct {
	IPAllow       int `json:"ip_allow"`
	IPBan         int `json:"ip_ban"`
	DeviceAllow   int `json:"device_allow"`
	DeviceBan     int `json:"device_ban"`
	InviterAllow  int `json:"inviter_allow"`
	InviterBan    int `json:"inviter_ban"`
	BurstFlag     int `json:"burst_flag"` // any one signal within 10 minutes
	BurstBan      int `json:"burst_ban"`
	InvitesPerDay int `json:"invites_per_day"` // codes one user may create per 24 h

	SingleDays    int `json:"single_days"`
	HouseholdDays int `json:"household_days"`
	HouseholdUses int `json:"household_uses"`
}

func defaultLimits() Limits {
	return Limits{
		IPAllow: 12, IPBan: 25,
		DeviceAllow: 8, DeviceBan: 15,
		InviterAllow: 10, InviterBan: 20,
		BurstFlag: 6, BurstBan: 10,
		InvitesPerDay: 20,
		SingleDays:    7, HouseholdDays: 30, HouseholdUses: 8,
	}
}

// Settings are saved in settings.json in the data folder.
type Settings struct {
	ServerName       string `json:"server_name"`       // shown on invite pages
	Port             int    `json:"port"`              // the one public port (5190)
	PanelPort        int    `json:"panel_port"`        // control panel, this computer only
	InternalBase     int    `json:"internal_base"`     // Open OSCAR Server's private ports start here
	Hostname         string `json:"hostname"`          // optional name or address people use from outside
	InviteAddress    string `json:"invite_address"`    // "auto", "public", "lan"
	UPnP             bool   `json:"upnp"`              // open the port on the router automatically
	RequirePasswords bool   `json:"require_passwords"` // DISABLE_AUTH=false
	AutoStart        bool   `json:"auto_start"`        // start the server when the app opens
	ClientRepo       string `json:"client_repo"`       // GitHub repo with the client's "latest" release
	LastPublicIP     string `json:"last_public_ip"`
	Limits           Limits `json:"limits"`
}

func defaultSettings() Settings {
	return Settings{
		ServerName:       "AIM Server",
		Port:             5190,
		PanelPort:        8190,
		InternalBase:     15190,
		InviteAddress:    "auto",
		UPnP:             true,
		RequirePasswords: true,
		ClientRepo:       "Hatdagger/Aim-for-android",
		Limits:           defaultLimits(),
	}
}

type SettingsStore struct {
	mu   sync.Mutex
	path string
	s    Settings
}

func LoadSettings(dir string) (*SettingsStore, error) {
	st := &SettingsStore{path: filepath.Join(dir, "settings.json"), s: defaultSettings()}
	b, err := os.ReadFile(st.path)
	if err == nil {
		if err := json.Unmarshal(b, &st.s); err != nil {
			return nil, err
		}
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	st.fix()
	return st, st.saveLocked()
}

func (st *SettingsStore) fix() {
	d := defaultSettings()
	s := &st.s
	if s.Port <= 0 || s.Port > 65535 {
		s.Port = d.Port
	}
	if s.PanelPort <= 0 || s.PanelPort > 65535 {
		s.PanelPort = d.PanelPort
	}
	if s.InternalBase <= 0 || s.InternalBase > 65530 {
		s.InternalBase = d.InternalBase
	}
	switch s.InviteAddress {
	case "auto", "public", "lan":
	default:
		s.InviteAddress = "auto"
	}
	if s.ClientRepo == "" {
		s.ClientRepo = d.ClientRepo
	}
	if s.ServerName == "" {
		s.ServerName = d.ServerName
	}
	l, dl := &s.Limits, d.Limits
	fixPos := func(v *int, def int) {
		if *v <= 0 {
			*v = def
		}
	}
	fixPos(&l.IPAllow, dl.IPAllow)
	fixPos(&l.IPBan, dl.IPBan)
	fixPos(&l.DeviceAllow, dl.DeviceAllow)
	fixPos(&l.DeviceBan, dl.DeviceBan)
	fixPos(&l.InviterAllow, dl.InviterAllow)
	fixPos(&l.InviterBan, dl.InviterBan)
	fixPos(&l.BurstFlag, dl.BurstFlag)
	fixPos(&l.BurstBan, dl.BurstBan)
	fixPos(&l.InvitesPerDay, dl.InvitesPerDay)
	fixPos(&l.SingleDays, dl.SingleDays)
	fixPos(&l.HouseholdDays, dl.HouseholdDays)
	fixPos(&l.HouseholdUses, dl.HouseholdUses)
}

func (st *SettingsStore) Get() Settings {
	st.mu.Lock()
	defer st.mu.Unlock()
	return st.s
}

func (st *SettingsStore) Update(f func(*Settings)) (Settings, error) {
	st.mu.Lock()
	defer st.mu.Unlock()
	f(&st.s)
	st.fix()
	return st.s, st.saveLocked()
}

func (st *SettingsStore) saveLocked() error {
	b, _ := json.MarshalIndent(st.s, "", "  ")
	return writeFileAtomic(st.path, b, 0o600)
}

func writeFileAtomic(path string, data []byte, perm os.FileMode) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, perm); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
