package main

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

// App ties everything together: settings, the server program, the one-port
// router, the account API, invite pages and the router (UPnP) port opening.
type App struct {
	Dir      string
	OscarBin string // explicit path from the command line, if any
	Settings *SettingsStore
	Store    *Store
	Log      *LogBuffer
	Clients  *ClientCache
	Cert     tls.Certificate
	FP       string // certificate fingerprint for invite links

	// NoNetworkChecks skips public-IP lookups and UPnP (tests).
	NoNetworkChecks bool

	mu       sync.Mutex
	state    string // stopped | starting | running | stopping
	lastErr  string
	proc     *OscarProcess
	router   *Router
	servers  []*http.Server
	mgmt     *Mgmt
	ocfg     OscarConfig
	net      NetStatus
	upnp     *UPnP
	cancel   context.CancelFunc
	started  time.Time
	restarts int
}

type NetStatus struct {
	LocalIP       string    `json:"local_ip"`
	LocalIPs      []string  `json:"local_ips"`
	PublicIP      string    `json:"public_ip"`
	RouterIP      string    `json:"router_ip"`  // the router's own internet address (UPnP)
	UPnPState     string    `json:"upnp_state"` // off | searching | open | failed | n/a
	UPnPMessage   string    `json:"upnp_message"`
	CGNAT         bool      `json:"cgnat"`
	PublicChanged string    `json:"public_changed,omitempty"`
	Checked       time.Time `json:"checked"`
}

func NewApp(dir, oscarBin string) (*App, error) {
	st, err := LoadSettings(dir)
	if err != nil {
		return nil, fmt.Errorf("settings.json: %w", err)
	}
	store, err := OpenStore(dir)
	if err != nil {
		return nil, fmt.Errorf("state.json: %w", err)
	}
	cert, fp, err := LoadOrCreateCert(dir)
	if err != nil {
		return nil, fmt.Errorf("certificate: %w", err)
	}
	log := NewLogBuffer(800)
	a := &App{
		Dir: dir, OscarBin: oscarBin, Settings: st, Store: store, Log: log,
		Cert: cert, FP: fp, state: "stopped",
	}
	a.Clients = NewClientCache(dir, log, func() string { return a.Settings.Get().ClientRepo })
	return a, nil
}

func (a *App) internal(offset int) string {
	return "127.0.0.1:" + strconv.Itoa(a.Settings.Get().InternalBase+offset)
}

// Mgmt returns the management API client (nil when stopped).
func (a *App) Mgmt() *Mgmt {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.state != "running" {
		return nil
	}
	return a.mgmt
}

func (a *App) State() (string, string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.state, a.lastErr
}

func (a *App) Net() NetStatus {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.net
}

// Start brings everything up.
func (a *App) Start() error {
	a.mu.Lock()
	if a.state != "stopped" {
		a.mu.Unlock()
		return errors.New("the server is already " + a.state)
	}
	a.state, a.lastErr = "starting", ""
	a.mu.Unlock()

	err := a.start()
	a.mu.Lock()
	if err != nil {
		a.state, a.lastErr = "stopped", err.Error()
	} else {
		a.state, a.started, a.restarts = "running", time.Now(), 0
	}
	a.mu.Unlock()
	if err != nil {
		a.Log.Add("Start failed: %v", err)
		return err
	}
	a.Settings.Update(func(s *Settings) { s.AutoStart = true })
	a.Log.Add("AIM server is running on port %d.", a.Settings.Get().Port)
	return nil
}

func (a *App) start() error {
	set := a.Settings.Get()
	bin, err := FindOscarBinary(a.OscarBin, a.Dir)
	if err != nil {
		return err
	}
	a.refreshNetwork(context.Background(), true)

	cfg := a.oscarConfig()
	proc := &OscarProcess{Bin: bin, DataDir: a.Dir, Log: a.Log}
	a.Log.Add("Starting Open OSCAR Server (%s)", bin)
	if err := proc.Start(cfg); err != nil {
		return err
	}

	tlsConf := &tls.Config{Certificates: []tls.Certificate{a.Cert}, MinVersion: tls.VersionTLS12}
	backend := func(ip net.IP) string {
		a.mu.Lock()
		defer a.mu.Unlock()
		if a.proc == nil || !a.proc.Running() {
			return ""
		}
		if isLocalIP(ip) {
			return a.ocfg.LANListen
		}
		return a.ocfg.WANListen
	}
	r, err := NewRouter(":"+strconv.Itoa(set.Port), tlsConf, backend, a.Log)
	if err != nil {
		proc.Stop()
		return fmt.Errorf("port %d is busy (is another AIM server running?): %v", set.Port, err)
	}
	apiSrv := &http.Server{Handler: a.apiHandler(), ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout: 30 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second}
	webSrv := &http.Server{Handler: a.webHandler(), ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout: 60 * time.Second}
	go apiSrv.Serve(r.HTTPS)
	go webSrv.Serve(r.HTTP)
	go r.Serve()

	ctx, cancel := context.WithCancel(context.Background())
	a.mu.Lock()
	a.proc, a.router, a.servers, a.cancel = proc, r, []*http.Server{apiSrv, webSrv}, cancel
	a.mgmt, a.ocfg = NewMgmt(cfg.APIListen), cfg
	a.mu.Unlock()

	go a.openPort(ctx)
	go a.watch(ctx)
	go a.Clients.Refresh(ctx, false)
	return nil
}

func (a *App) oscarConfig() OscarConfig {
	set := a.Settings.Get()
	n := a.Net()
	port := strconv.Itoa(set.Port)
	lan := n.LocalIP
	if lan == "" {
		lan = "127.0.0.1"
	}
	wan := set.Hostname
	if wan == "" {
		wan = n.PublicIP
	}
	if wan == "" {
		wan = lan
	}
	return OscarConfig{
		LANListen:        a.internal(0),
		WANListen:        a.internal(1),
		APIListen:        a.internal(2),
		TOCListen:        a.internal(3),
		LANAdvertise:     net.JoinHostPort(lan, port),
		WANAdvertise:     net.JoinHostPort(wan, port),
		RequirePasswords: set.RequirePasswords,
	}
}

// Stop takes everything down and closes the router port again.
func (a *App) Stop() {
	a.mu.Lock()
	if a.state != "running" {
		a.mu.Unlock()
		return
	}
	a.state = "stopping"
	proc, r, servers, cancel, up := a.proc, a.router, a.servers, a.cancel, a.upnp
	a.mu.Unlock()

	cancel()
	if up != nil {
		ctx, c := context.WithTimeout(context.Background(), 4*time.Second)
		if err := up.DeletePortMapping(ctx, a.Settings.Get().Port); err == nil {
			a.Log.Add("Closed port %d on the router.", a.Settings.Get().Port)
		}
		c()
	}
	r.Close()
	for _, s := range servers {
		s.Close()
	}
	proc.Stop()
	a.mu.Lock()
	a.state, a.proc, a.router, a.servers, a.mgmt, a.upnp = "stopped", nil, nil, nil, nil, nil
	a.net.UPnPState = "off"
	a.mu.Unlock()
	a.Log.Add("AIM server stopped.")
}

// StopAndRemember stops and also turns off auto-start (the owner chose to stop).
func (a *App) StopAndRemember() {
	a.Stop()
	a.Settings.Update(func(s *Settings) { s.AutoStart = false })
}

// Restart applies new settings.
func (a *App) Restart() error {
	if st, _ := a.State(); st == "running" {
		a.Stop()
		return a.Start()
	}
	return nil
}

// refreshNetwork finds local/public addresses (and the router, when asked).
func (a *App) refreshNetwork(ctx context.Context, withUPnP bool) {
	set := a.Settings.Get()
	local := LocalIP()
	ns := a.Net()
	ns.LocalIP = local.String()
	ns.LocalIPs = nil
	for _, ip := range LocalIPs() {
		ns.LocalIPs = append(ns.LocalIPs, ip.String())
	}
	ns.Checked = time.Now()
	if a.NoNetworkChecks {
		ns.UPnPState = "n/a"
		a.mu.Lock()
		a.net = ns
		a.mu.Unlock()
		return
	}
	var wg sync.WaitGroup
	var pub net.IP
	var up *UPnP
	var upErr error
	var routerIP net.IP
	wg.Add(1)
	go func() {
		defer wg.Done()
		c, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()
		pub, _ = PublicIP(c)
	}()
	if withUPnP && set.UPnP {
		wg.Add(1)
		go func() {
			defer wg.Done()
			c, cancel := context.WithTimeout(ctx, 8*time.Second)
			defer cancel()
			up, upErr = DiscoverUPnP(c, local)
			if up != nil {
				routerIP, _ = up.ExternalIP(c)
			}
		}()
	}
	wg.Wait()
	if pub != nil {
		ns.PublicIP = pub.String()
		if set.LastPublicIP != "" && set.LastPublicIP != ns.PublicIP {
			ns.PublicChanged = "Your public address changed from " + set.LastPublicIP + " to " + ns.PublicIP +
				". Invite links made before this won't work from outside your home."
			a.Log.Add("%s", ns.PublicChanged)
		}
		a.Settings.Update(func(s *Settings) { s.LastPublicIP = pub.String() })
	}
	if withUPnP {
		switch {
		case !set.UPnP:
			ns.UPnPState, ns.UPnPMessage, ns.RouterIP = "off", "", ""
		case up == nil:
			ns.UPnPState, ns.UPnPMessage, ns.RouterIP = "failed", upErrText(upErr), ""
		default:
			ns.UPnPState, ns.UPnPMessage = "searching", "Found your router."
			if routerIP != nil {
				ns.RouterIP = routerIP.String()
			}
		}
		a.mu.Lock()
		a.upnp = up
		a.mu.Unlock()
	}
	ns.CGNAT = false
	if ns.RouterIP != "" {
		rip := net.ParseIP(ns.RouterIP)
		if !isPublicIP(rip) || (ns.PublicIP != "" && ns.PublicIP != ns.RouterIP) {
			ns.CGNAT = true
		}
	}
	a.mu.Lock()
	a.net = ns
	a.mu.Unlock()
}

func upErrText(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// openPort asks the router to forward the port, and keeps renewing it.
func (a *App) openPort(ctx context.Context) {
	for {
		if !a.openPortOnce(ctx) {
			return
		}
		if !waitCtx(ctx, 20*time.Minute) {
			return
		}
	}
}

// openPortOnce returns false when there is no router to talk to.
func (a *App) openPortOnce(ctx context.Context) bool {
	a.mu.Lock()
	up := a.upnp
	a.mu.Unlock()
	if up == nil {
		return false
	}
	port := a.Settings.Get().Port
	c, cancel := context.WithTimeout(ctx, 6*time.Second)
	err := up.AddPortMapping(c, port, time.Hour)
	cancel()
	a.mu.Lock()
	if err != nil {
		a.net.UPnPState = "failed"
		a.net.UPnPMessage = err.Error()
	} else {
		if a.net.UPnPState != "open" {
			a.Log.Add("Router: opened TCP port %d to this computer (%s).", port, up.LocalIP)
		}
		a.net.UPnPState = "open"
		a.net.UPnPMessage = fmt.Sprintf("Port %d is open on your router.", port)
	}
	a.mu.Unlock()
	if err != nil {
		a.Log.Add("Router: couldn't open port %d: %v", port, err)
	}
	return true
}

// Recheck looks at the network again (and re-opens the port when running).
func (a *App) Recheck() {
	a.refreshNetwork(context.Background(), true)
	if st, _ := a.State(); st == "running" {
		a.openPortOnce(context.Background())
	}
}

// watch restarts a crashed server program and follows public address changes.
func (a *App) watch(ctx context.Context) {
	tick := time.NewTicker(10 * time.Minute)
	defer tick.Stop()
	for {
		a.mu.Lock()
		proc := a.proc
		a.mu.Unlock()
		if proc == nil {
			return
		}
		select {
		case <-ctx.Done():
			return
		case <-proc.Done():
			if ctx.Err() != nil {
				return
			}
			a.mu.Lock()
			a.restarts++
			n := a.restarts
			a.mu.Unlock()
			if n > 5 {
				a.Log.Add("The server program keeps stopping; giving up. Check the log, then press Start.")
				go a.Stop()
				a.mu.Lock()
				a.lastErr = "The server program keeps stopping (see Log)."
				a.mu.Unlock()
				return
			}
			a.Log.Add("Restarting the server program in 5 seconds...")
			if !waitCtx(ctx, 5*time.Second) {
				return
			}
			if err := proc.Start(a.oscarConfig()); err != nil {
				a.Log.Add("Restart failed: %v", err)
			}
		case <-tick.C:
			old := a.Net().PublicIP
			a.refreshNetwork(ctx, false)
			n := a.Net()
			if a.Settings.Get().Hostname == "" && n.PublicIP != "" && n.PublicIP != old {
				a.Log.Add("Public address changed to %s; restarting the server program so it tells clients the new address.", n.PublicIP)
				cfg := a.oscarConfig()
				proc.Stop()
				a.mu.Lock()
				a.ocfg = cfg
				a.mu.Unlock()
				if err := proc.Start(cfg); err != nil {
					a.Log.Add("Restart failed: %v", err)
				}
			}
		}
	}
}

// InviteHost is the host:port written into invite links.
// reqHost (from a web request) wins: that address evidently works.
func (a *App) InviteHost(reqHost string) string {
	set := a.Settings.Get()
	port := strconv.Itoa(set.Port)
	if reqHost != "" {
		h, p, err := net.SplitHostPort(reqHost)
		if err != nil {
			h, p = reqHost, "80"
		}
		if p == port {
			return net.JoinHostPort(h, p)
		}
	}
	n := a.Net()
	host := set.Hostname
	switch {
	case host != "":
	case set.InviteAddress == "lan":
		host = n.LocalIP
	case set.InviteAddress == "public" && n.PublicIP != "":
		host = n.PublicIP
	case n.PublicIP != "" && !n.CGNAT:
		host = n.PublicIP
	default:
		host = n.LocalIP
	}
	if host == "" {
		host = "127.0.0.1"
	}
	return net.JoinHostPort(host, port)
}

func (a *App) InviteLink(host string, inv *Invite) string {
	return "http://" + host + "/i/" + inv.Code + "#fp=" + a.FP + "&by=" + strings.ReplaceAll(url.QueryEscape(inv.By), "+", "%20")
}

func (a *App) AppLink(host string, inv *Invite) string {
	q := url.Values{}
	q.Set("server", host)
	q.Set("code", inv.Code)
	q.Set("fp", a.FP)
	q.Set("by", inv.By)
	return "aim://invite?" + strings.ReplaceAll(q.Encode(), "+", "%20")
}

// CreateInvite makes a new code. uses/days of 0 mean the defaults for kind.
func (a *App) CreateInvite(by string, byOwner bool, kind string, uses, days int) (*Invite, error) {
	l := a.Settings.Get().Limits
	if kind != "household" {
		kind = "single"
	}
	if uses <= 0 {
		uses = 1
		if kind == "household" {
			uses = l.HouseholdUses
		}
	}
	if days <= 0 {
		days = l.SingleDays
		if kind == "household" {
			days = l.HouseholdDays
		}
	}
	if uses > 500 || days > 3650 {
		return nil, errors.New("too many uses or days")
	}
	now := time.Now().UTC()
	inv := &Invite{Code: NewCode(), Kind: kind, By: by, ByOwner: byOwner, MaxUses: uses,
		Created: now, Expires: now.Add(time.Duration(days) * 24 * time.Hour)}
	err := a.Store.Do(func(d *StoreData) error {
		for d.Invite(inv.Code) != nil {
			inv.Code = NewCode()
		}
		d.Invites = append(d.Invites, inv)
		return nil
	})
	return inv, err
}
