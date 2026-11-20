package main

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// ---------------------------------------------------------------- client builds

// ClientCache keeps copies of the AIM client builds from the client repo's
// "latest" GitHub release, so invite pages can hand them out.
type ClientCache struct {
	Dir  string
	Log  *LogBuffer
	Repo func() string

	mu      sync.Mutex
	last    time.Time
	running bool
	status  map[string]string
}

var clientFiles = []struct{ Name, Label string }{
	{"aim-android.apk", "Android"},
	{"aim-windows.zip", "Windows"},
	{"aim-linux.tar.gz", "Linux / Steam Deck"},
}

func NewClientCache(dataDir string, log *LogBuffer, repo func() string) *ClientCache {
	d := filepath.Join(dataDir, "clients")
	os.MkdirAll(d, 0o755)
	return &ClientCache{Dir: d, Log: log, Repo: repo, status: map[string]string{}}
}

func (c *ClientCache) Path(name string) (string, bool) {
	p := filepath.Join(c.Dir, name)
	st, err := os.Stat(p)
	return p, err == nil && st.Size() > 0
}

type ClientInfo struct {
	Name     string    `json:"name"`
	Label    string    `json:"label"`
	Have     bool      `json:"have"`
	Size     int64     `json:"size"`
	Modified time.Time `json:"modified"`
	Status   string    `json:"status"`
}

func (c *ClientCache) Info() []ClientInfo {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []ClientInfo
	for _, f := range clientFiles {
		ci := ClientInfo{Name: f.Name, Label: f.Label, Status: c.status[f.Name]}
		if st, err := os.Stat(filepath.Join(c.Dir, f.Name)); err == nil && st.Size() > 0 {
			ci.Have, ci.Size, ci.Modified = true, st.Size(), st.ModTime()
		}
		out = append(out, ci)
	}
	return out
}

// Refresh downloads newer builds (at most once every 6 hours unless forced).
func (c *ClientCache) Refresh(ctx context.Context, force bool) {
	c.mu.Lock()
	if c.running || (!force && time.Since(c.last) < 6*time.Hour) {
		c.mu.Unlock()
		return
	}
	c.running, c.last = true, time.Now()
	c.mu.Unlock()
	defer func() {
		c.mu.Lock()
		c.running = false
		c.mu.Unlock()
	}()
	repo := c.Repo()
	if os.Getenv("AIM_SERVER_NO_CLIENT_DOWNLOAD") != "" || repo == "" {
		return
	}
	for _, f := range clientFiles {
		u := "https://github.com/" + repo + "/releases/download/latest/" + f.Name
		st, err := c.fetch(ctx, u, f.Name)
		c.mu.Lock()
		if err != nil {
			c.status[f.Name] = "download failed: " + err.Error()
		} else {
			c.status[f.Name] = st
		}
		c.mu.Unlock()
		if err != nil {
			c.Log.Add("Client build %s: %v", f.Name, err)
		} else if st == "updated" {
			c.Log.Add("Client build %s downloaded.", f.Name)
		}
	}
}

func (c *ClientCache) fetch(ctx context.Context, url, name string) (string, error) {
	dst := filepath.Join(c.Dir, name)
	etagPath := dst + ".etag"
	req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
	if _, ok := c.Path(name); ok {
		if et, err := os.ReadFile(etagPath); err == nil {
			req.Header.Set("If-None-Match", strings.TrimSpace(string(et)))
		}
	}
	client := &http.Client{Timeout: 10 * time.Minute}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotModified {
		return "up to date", nil
	}
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("GitHub answered %s", resp.Status)
	}
	tmp := dst + ".part"
	f, err := os.Create(tmp)
	if err != nil {
		return "", err
	}
	_, err = io.Copy(f, io.LimitReader(resp.Body, 500<<20))
	f.Close()
	if err != nil {
		os.Remove(tmp)
		return "", err
	}
	if err := os.Rename(tmp, dst); err != nil {
		return "", err
	}
	if et := resp.Header.Get("ETag"); et != "" {
		os.WriteFile(etagPath, []byte(et), 0o644)
	}
	return "updated", nil
}

// inviteJSON is placed next to the client program inside desktop downloads.
func inviteJSON(server, code, fp, by string) []byte {
	b, _ := json.MarshalIndent(map[string]string{"server": server, "code": code, "fp": fp, "by": by}, "", "  ")
	return b
}

// WriteZipWithInvite copies a zip, adding invite.json beside the .exe.
func WriteZipWithInvite(w io.Writer, src string, invite []byte) error {
	zr, err := zip.OpenReader(src)
	if err != nil {
		return err
	}
	defer zr.Close()
	dir := ""
	for _, f := range zr.File {
		if strings.HasSuffix(strings.ToLower(f.Name), ".exe") && !strings.Contains(f.Name, "/data/") {
			dir = path.Dir(f.Name)
			if dir == "." {
				dir = ""
			}
			break
		}
	}
	target := path.Join(dir, "invite.json")
	zw := zip.NewWriter(w)
	for _, f := range zr.File {
		if f.Name == target {
			continue
		}
		if err := zw.Copy(f); err != nil {
			return err
		}
	}
	fw, err := zw.CreateHeader(&zip.FileHeader{Name: target, Method: zip.Deflate, Modified: time.Now()})
	if err != nil {
		return err
	}
	if _, err := fw.Write(invite); err != nil {
		return err
	}
	return zw.Close()
}

// WriteTarGzWithInvite copies a .tar.gz, adding invite.json beside the program.
func WriteTarGzWithInvite(w io.Writer, src string, invite []byte, exeName string) error {
	f, err := os.Open(src)
	if err != nil {
		return err
	}
	defer f.Close()
	gr, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	tr := tar.NewReader(gr)
	gw := gzip.NewWriter(w)
	tw := tar.NewWriter(gw)
	dir := ""
	found := false
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		name := strings.TrimPrefix(h.Name, "./")
		if path.Base(name) == "invite.json" {
			continue
		}
		if !found && h.Typeflag == tar.TypeReg && path.Base(name) == exeName {
			dir, found = path.Dir(h.Name), true
		}
		if err := tw.WriteHeader(h); err != nil {
			return err
		}
		if _, err := io.Copy(tw, tr); err != nil {
			return err
		}
	}
	if !found {
		dir = "."
	}
	h := &tar.Header{Name: path.Join(dir, "invite.json"), Mode: 0o644, Size: int64(len(invite)),
		ModTime: time.Now(), Typeflag: tar.TypeReg}
	if err := tw.WriteHeader(h); err != nil {
		return err
	}
	if _, err := tw.Write(invite); err != nil {
		return err
	}
	if err := tw.Close(); err != nil {
		return err
	}
	return gw.Close()
}

// ---------------------------------------------------------------- invite pages

func (a *App) webHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		a.renderPage(w, 200, pageData{Title: a.Settings.Get().ServerName,
			Message: "This is a private AIM server. To join, ask someone who's already on it for an invite link."})
	})
	mux.HandleFunc("/i/", a.handleInvitePage)
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		apiErr(w, 400, "use_https", "The account API needs a secure (https) connection.")
	})
	return mux
}

type pageData struct {
	Title, Message, Server, By, Link, Code string
	AppLink                                template.URL
	Error                                  bool
	Downloads                              []dlLink
}

type dlLink struct{ Label, Href, Note string }

func (a *App) handleInvitePage(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/i/"), "/"), "/")
	code := NormalizeCode(parts[0])
	var inv Invite
	var usable error
	var found bool
	a.Store.Read(func(d *StoreData) {
		if i := d.Invite(code); i != nil {
			inv, found = *i, true
			usable = i.Usable(time.Now())
			if usable == nil && !i.ByOwner && d.IsBanned("inviter", i.By, time.Now()) {
				usable = errInviteRevoked
			}
		}
	})
	name := a.Settings.Get().ServerName
	if !found {
		a.renderPage(w, 404, pageData{Title: name, Error: true,
			Message: "That invite link isn't valid. Check you copied all of it, or ask for a new one."})
		return
	}
	if usable != nil {
		a.renderPage(w, 410, pageData{Title: name, Error: true, Message: usable.Error()})
		return
	}
	host := a.InviteHost(r.Host)
	if len(parts) == 2 {
		a.serveDownload(w, r, parts[1], host, &inv)
		return
	}
	if len(parts) > 2 {
		http.NotFound(w, r)
		return
	}
	base := "/i/" + inv.Code + "/"
	pd := pageData{
		Title: name, Server: host, By: inv.By, Code: inv.Code,
		Link: a.InviteLink(host, &inv), AppLink: template.URL(a.AppLink(host, &inv)),
		Downloads: []dlLink{
			{"Android", base + "android.apk", "Then open the app: it finds this invite by itself."},
			{"Windows", base + "windows.zip", "Unzip it and run aim_for_android.exe."},
			{"Linux / Steam Deck", base + "linux.tar.gz", "Extract it and run bundle/aim_for_android."},
		},
	}
	a.renderPage(w, 200, pd)
}

func (a *App) serveDownload(w http.ResponseWriter, r *http.Request, file, host string, inv *Invite) {
	var name string
	switch file {
	case "android.apk":
		name = "aim-android.apk"
	case "windows.zip":
		name = "aim-windows.zip"
	case "linux.tar.gz":
		name = "aim-linux.tar.gz"
	default:
		http.NotFound(w, r)
		return
	}
	src, ok := a.Clients.Path(name)
	if !ok {
		go a.Clients.Refresh(context.Background(), true)
		a.renderPage(w, 503, pageData{Title: a.Settings.Get().ServerName, Error: true,
			Message: "This download isn't ready on the server yet. Try again in a few minutes."})
		return
	}
	ij := inviteJSON(host, inv.Code, a.FP, inv.By)
	w.Header().Set("Content-Disposition", `attachment; filename="`+name+`"`)
	w.Header().Set("Cache-Control", "no-store")
	switch file {
	case "android.apk":
		w.Header().Set("Content-Type", "application/vnd.android.package-archive")
		http.ServeFile(w, r, src)
	case "windows.zip":
		w.Header().Set("Content-Type", "application/zip")
		if err := WriteZipWithInvite(w, src, ij); err != nil {
			a.Log.Add("Download %s failed: %v", name, err)
		}
	case "linux.tar.gz":
		w.Header().Set("Content-Type", "application/gzip")
		if err := WriteTarGzWithInvite(w, src, ij, "aim_for_android"); err != nil {
			a.Log.Add("Download %s failed: %v", name, err)
		}
	}
}

var pageTmpl = template.Must(template.New("p").Parse(`<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{.Title}}</title>
<style>
body{margin:0;background:#008080;font:15px Tahoma,Verdana,sans-serif;color:#000;padding:16px}
.win{max-width:520px;margin:24px auto;background:#c0c0c0;border:2px solid;border-color:#fff #404040 #404040 #fff;box-shadow:1px 1px 0 #000}
.bar{background:linear-gradient(90deg,#000080,#1084d0);color:#fff;font-weight:bold;padding:4px 8px}
.body{padding:14px 16px}
h1{font-size:20px;margin:4px 0 10px}
.btn{display:block;text-align:center;text-decoration:none;color:#000;background:#c0c0c0;padding:10px;margin:8px 0;
border:2px solid;border-color:#fff #404040 #404040 #fff;font-weight:bold}
.btn:active{border-color:#404040 #fff #fff #404040}
.go{background:#ffffe1}
.note{font-size:12px;color:#333;margin:-4px 0 10px 2px}
.box{background:#fff;border:2px solid;border-color:#808080 #fff #fff #808080;padding:6px;word-break:break-all;font:12px monospace}
.err{color:#800000;font-weight:bold}
small{color:#333}
</style></head><body>
<div class="win"><div class="bar">{{.Title}}</div><div class="body">
{{if .Message}}<p class="{{if .Error}}err{{end}}">{{.Message}}</p>{{end}}
{{if .Code}}
<h1>{{.By}} invited you to AIM!</h1>
<p>Server: <b>{{.Server}}</b><br>Invite code: <b>{{.Code}}</b></p>
<a class="btn go" href="{{.AppLink}}">Already have the app? Open in AIM</a>
<p><b>Get the app:</b></p>
{{range .Downloads}}<a class="btn dl" href="{{.Href}}">Download for {{.Label}}</a><div class="note">{{.Note}}</div>{{end}}
<p><small>Your invite link (copied automatically when you tap a download):</small></p>
<div class="box" id="link">{{.Link}}</div>
<a class="btn" href="#" id="copy">Copy invite link</a>
<p><small>On Android you may need to allow installing apps from your browser. Only install apps from people you trust.</small></p>
<script>
(function(){
  var link=document.getElementById('link').textContent;
  function copy(){
    try{ if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(link);return true;} }catch(e){}
    var t=document.createElement('textarea');t.value=link;t.setAttribute('readonly','');t.style.position='fixed';t.style.opacity='0';
    document.body.appendChild(t);t.select();t.setSelectionRange(0,99999);var ok=false;try{ok=document.execCommand('copy');}catch(e){}
    document.body.removeChild(t);return ok;
  }
  var dls=document.querySelectorAll('a.dl');for(var i=0;i<dls.length;i++){dls[i].addEventListener('click',copy);}
  document.getElementById('copy').addEventListener('click',function(e){e.preventDefault();this.textContent=copy()?'Copied!':'Select the link above and copy it';});
})();
</script>
{{end}}
</div></div></body></html>`))

func (a *App) renderPage(w http.ResponseWriter, status int, pd pageData) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.WriteHeader(status)
	if err := pageTmpl.Execute(w, pd); err != nil && !errors.Is(err, http.ErrHandlerTimeout) {
		a.Log.Add("page error: %v", err)
	}
}
