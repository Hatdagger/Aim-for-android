package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

// LogBuffer keeps the last lines of the app's and the server's output.
type LogBuffer struct {
	mu    sync.Mutex
	lines []string
	max   int
}

func NewLogBuffer(max int) *LogBuffer { return &LogBuffer{max: max} }

func (l *LogBuffer) Add(format string, a ...any) {
	line := time.Now().Format("15:04:05 ") + fmt.Sprintf(format, a...)
	l.mu.Lock()
	l.lines = append(l.lines, line)
	if len(l.lines) > l.max {
		l.lines = append([]string(nil), l.lines[len(l.lines)-l.max:]...)
	}
	l.mu.Unlock()
	if os.Getenv("AIM_SERVER_LOG_STDOUT") != "" {
		fmt.Println(line)
	}
}

func (l *LogBuffer) Lines() []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]string{}, l.lines...)
}

// OscarConfig is what the Open OSCAR Server process is started with.
type OscarConfig struct {
	LANListen, WANListen string // private ports it listens on (127.0.0.1)
	LANAdvertise         string // address told to clients on the home network
	WANAdvertise         string // address told to clients on the internet
	APIListen            string // management API (never exposed)
	TOCListen            string
	RequirePasswords     bool
}

func (c OscarConfig) env() []string {
	auth := "true"
	if c.RequirePasswords {
		auth = "false"
	}
	return []string{
		"OSCAR_LISTENERS=LAN://" + c.LANListen + ",WAN://" + c.WANListen,
		"OSCAR_ADVERTISED_LISTENERS_PLAIN=LAN://" + c.LANAdvertise + ",WAN://" + c.WANAdvertise,
		"TOC_LISTENERS=" + c.TOCListen,
		"API_LISTENER=" + c.APIListen,
		"WEBAPI_ENABLED=false",
		"DB_PATH=oscar.sqlite",
		"DISABLE_AUTH=" + auth,
		"DISABLE_MULTI_LOGIN_NOTIF=true",
		"LOG_LEVEL=info",
		"ICQ_LEGACY_ENABLED=false",
	}
}

// OscarProcess runs Open OSCAR Server as a child program.
type OscarProcess struct {
	Bin     string
	DataDir string
	Log     *LogBuffer

	mu      sync.Mutex
	cmd     *exec.Cmd
	done    chan struct{}
	exitErr error
	stopped bool // stop was asked for
}

// FindOscarBinary looks next to this program, then in the data folder, then PATH.
func FindOscarBinary(explicit, dataDir string) (string, error) {
	name := "open_oscar_server"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	var cands []string
	if explicit != "" {
		cands = append(cands, explicit)
	}
	if exe, err := os.Executable(); err == nil {
		if r, err := filepath.EvalSymlinks(exe); err == nil {
			exe = r
		}
		cands = append(cands, filepath.Join(filepath.Dir(exe), name),
			filepath.Join(filepath.Dir(exe), "oscar", name))
	}
	cands = append(cands, filepath.Join(dataDir, name))
	for _, c := range cands {
		if st, err := os.Stat(c); err == nil && !st.IsDir() {
			return c, nil
		}
	}
	if p, err := exec.LookPath(name); err == nil {
		return p, nil
	}
	return "", fmt.Errorf("can't find %s (it should be in the same folder as this app)", name)
}

func (p *OscarProcess) Running() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.cmd != nil && p.done != nil && !isClosed(p.done)
}

func isClosed(c chan struct{}) bool {
	select {
	case <-c:
		return true
	default:
		return false
	}
}

// Start launches the server and waits until its management API answers.
func (p *OscarProcess) Start(cfg OscarConfig) error {
	p.mu.Lock()
	if p.cmd != nil && !isClosed(p.done) {
		p.mu.Unlock()
		return errors.New("already running")
	}
	env := cfg.env()
	var file strings.Builder
	file.WriteString("# Written by AIM Server app each time it starts the server. Edits here are replaced.\n")
	for _, e := range env {
		file.WriteString(e + "\n")
	}
	if err := os.WriteFile(filepath.Join(p.DataDir, "settings.env"), []byte(file.String()), 0o600); err != nil {
		p.mu.Unlock()
		return err
	}
	cmd := exec.Command(p.Bin, "-config", "settings.env")
	cmd.Dir = p.DataDir
	cmd.Env = append(os.Environ(), env...)
	hideWindow(cmd)
	out, _ := cmd.StdoutPipe()
	cmd.Stderr = cmd.Stdout
	if err := cmd.Start(); err != nil {
		p.mu.Unlock()
		return fmt.Errorf("couldn't start the server program: %w", err)
	}
	p.cmd = cmd
	p.done = make(chan struct{})
	p.stopped = false
	p.exitErr = nil
	done := p.done
	p.mu.Unlock()

	go p.pump(out)
	go func() {
		err := cmd.Wait()
		p.mu.Lock()
		p.exitErr = err
		stopped := p.stopped
		p.mu.Unlock()
		if !stopped {
			p.Log.Add("Server program stopped unexpectedly: %v", err)
		}
		close(done)
	}()

	// wait for the management API
	deadline := time.Now().Add(20 * time.Second)
	client := &http.Client{Timeout: time.Second}
	for time.Now().Before(deadline) {
		select {
		case <-done:
			return fmt.Errorf("the server program quit while starting (see Log): %v", p.exitErr)
		default:
		}
		resp, err := client.Get("http://" + cfg.APIListen + "/version")
		if err == nil {
			resp.Body.Close()
			return nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	p.Stop()
	return errors.New("the server program didn't become ready in time (see Log)")
}

func (p *OscarProcess) pump(r io.Reader) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		p.Log.Add("[oscar] %s", sc.Text())
	}
}

// Stop ends the server program (politely first where the OS allows).
func (p *OscarProcess) Stop() {
	p.mu.Lock()
	cmd, done := p.cmd, p.done
	if cmd == nil || done == nil || isClosed(done) {
		p.mu.Unlock()
		return
	}
	p.stopped = true
	p.mu.Unlock()
	interrupt(cmd)
	select {
	case <-done:
	case <-time.After(6 * time.Second):
		cmd.Process.Kill()
		<-done
	}
}

// Done is closed when the current server program exits.
func (p *OscarProcess) Done() <-chan struct{} {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.done == nil {
		c := make(chan struct{})
		close(c)
		return c
	}
	return p.done
}

func waitCtx(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}
