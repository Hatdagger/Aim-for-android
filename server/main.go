// AIM Server: a control panel and one-port front door for Open OSCAR Server.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

var version = "dev"

func main() {
	dataFlag := flag.String("data", "", "folder for settings, accounts and the database (default: AIM Server Data next to this program)")
	oscarFlag := flag.String("oscar", "", "path to open_oscar_server (default: next to this program)")
	noBrowser := flag.Bool("no-browser", false, "don't open the control panel in a browser")
	startFlag := flag.Bool("start", false, "start the AIM server right away")
	panelPort := flag.Int("panel-port", 0, "control panel port (default from settings, 8190)")
	port := flag.Int("port", 0, "public AIM port (default from settings, 5190)")
	offline := flag.Bool("offline", false, "skip public-address lookups and router (UPnP) port opening")
	showVersion := flag.Bool("version", false, "print version")
	flag.Parse()
	if *showVersion {
		fmt.Println("aim-server", version)
		return
	}

	dir, err := dataDir(*dataFlag)
	if err != nil {
		fatal(err)
	}
	app, err := NewApp(dir, *oscarFlag)
	if err != nil {
		fatal(err)
	}
	app.NoNetworkChecks = *offline
	if *port > 0 || *panelPort > 0 {
		app.Settings.Update(func(s *Settings) {
			if *port > 0 {
				s.Port = *port
			}
			if *panelPort > 0 {
				s.PanelPort = *panelPort
			}
		})
	}
	set := app.Settings.Get()
	token := loadToken(dir)
	panel := &Panel{App: app, Token: token, Port: set.PanelPort}

	ln, err := net.Listen("tcp", "127.0.0.1:"+strconv.Itoa(set.PanelPort))
	if err != nil {
		// Already running? Then just show its panel.
		if alreadyRunning(set.PanelPort) {
			if !*noBrowser {
				openBrowser(panel.URL())
			}
			fmt.Println("AIM Server is already running:", panel.URL())
			return
		}
		fatal(fmt.Errorf("control panel port %d is busy: %v", set.PanelPort, err))
	}
	quit := make(chan struct{})
	panel.Quit = func() { close(quit) }
	srv := &http.Server{Handler: panel.Handler(), ReadHeaderTimeout: 10 * time.Second}
	go srv.Serve(ln)
	app.Log.Add("AIM Server %s. Control panel: http://127.0.0.1:%d  Data: %s", version, set.PanelPort, dir)
	fmt.Println("Control panel:", panel.URL())

	if *startFlag || set.AutoStart {
		go app.Start()
	} else {
		go app.refreshNetwork(context.Background(), false)
	}
	if !*noBrowser {
		openBrowser(panel.URL())
	}

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	select {
	case <-sig:
	case <-quit:
	}
	app.Stop()
	srv.Shutdown(context.Background())
}

func dataDir(flagDir string) (string, error) {
	dir := flagDir
	if dir == "" {
		dir = os.Getenv("AIM_SERVER_DATA")
	}
	if dir == "" {
		exe, err := os.Executable()
		if err == nil {
			if r, err := filepath.EvalSymlinks(exe); err == nil {
				exe = r
			}
			dir = filepath.Join(filepath.Dir(exe), "AIM Server Data")
			if err := os.MkdirAll(dir, 0o700); err != nil || !writable(dir) {
				dir = ""
			}
		}
	}
	if dir == "" {
		base, err := os.UserConfigDir()
		if err != nil {
			return "", err
		}
		dir = filepath.Join(base, "AIM Server")
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return filepath.Abs(dir)
}

func writable(dir string) bool {
	f, err := os.CreateTemp(dir, ".w")
	if err != nil {
		return false
	}
	f.Close()
	os.Remove(f.Name())
	return true
}

func loadToken(dir string) string {
	p := filepath.Join(dir, "panel-token")
	if b, err := os.ReadFile(p); err == nil && len(strings.TrimSpace(string(b))) >= 32 {
		return strings.TrimSpace(string(b))
	}
	b := make([]byte, 24)
	rand.Read(b)
	t := hex.EncodeToString(b)
	os.WriteFile(p, []byte(t), 0o600)
	return t
}

func alreadyRunning(port int) bool {
	c := &http.Client{Timeout: 2 * time.Second}
	resp, err := c.Get("http://127.0.0.1:" + strconv.Itoa(port) + "/ping")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 64))
	return string(b) == "aim-server"
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "AIM Server:", err)
	// On Windows (no console) also leave a note the owner can find.
	if exe, e := os.Executable(); e == nil {
		os.WriteFile(filepath.Join(filepath.Dir(exe), "aim-server-error.txt"), []byte(err.Error()+"\n"), 0o644)
	}
	os.Exit(1)
}
