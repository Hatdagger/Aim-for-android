package main

import (
	"bytes"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// UPnP talks to the home router (Internet Gateway Device) to open a port.
type UPnP struct {
	ControlURL  string
	ServiceType string
	LocalIP     net.IP
	client      *http.Client
}

var errNoRouter = errors.New("no router answered (UPnP may be turned off on the router)")

// DiscoverUPnP finds the router's port-mapping service on the home network.
func DiscoverUPnP(ctx context.Context, localIP net.IP) (*UPnP, error) {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: localIP})
	if err != nil {
		conn, err = net.ListenUDP("udp4", nil)
		if err != nil {
			return nil, err
		}
	}
	defer conn.Close()
	dst := &net.UDPAddr{IP: net.IPv4(239, 255, 255, 250), Port: 1900}
	targets := []string{
		"urn:schemas-upnp-org:device:InternetGatewayDevice:1",
		"urn:schemas-upnp-org:device:InternetGatewayDevice:2",
		"urn:schemas-upnp-org:service:WANIPConnection:1",
		"urn:schemas-upnp-org:service:WANIPConnection:2",
		"urn:schemas-upnp-org:service:WANPPPConnection:1",
	}
	send := func() {
		for _, st := range targets {
			msg := "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nST: " + st +
				"\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\n\r\n"
			conn.WriteToUDP([]byte(msg), dst)
		}
	}
	send()
	deadline := time.Now().Add(3500 * time.Millisecond)
	if d, ok := ctx.Deadline(); ok && d.Before(deadline) {
		deadline = d
	}
	seen := map[string]bool{}
	var locations []string
	buf := make([]byte, 2048)
	resent := false
	for time.Now().Before(deadline) {
		if !resent && time.Until(deadline) < 2*time.Second {
			send() // UDP can get lost; ask once more
			resent = true
		}
		conn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
		n, _, err := conn.ReadFromUDP(buf)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(buf[:n]), "\r\n") {
			if i := strings.IndexByte(line, ':'); i > 0 && strings.EqualFold(strings.TrimSpace(line[:i]), "location") {
				loc := strings.TrimSpace(line[i+1:])
				if !seen[loc] {
					seen[loc] = true
					locations = append(locations, loc)
				}
			}
		}
	}
	if len(locations) == 0 {
		return nil, errNoRouter
	}
	client := &http.Client{Timeout: 5 * time.Second}
	var lastErr error = errNoRouter
	for _, loc := range locations {
		u, err := findWANService(ctx, client, loc)
		if err != nil {
			lastErr = err
			continue
		}
		u.LocalIP = localIP
		u.client = client
		return u, nil
	}
	return nil, lastErr
}

type upnpService struct {
	ServiceType string `xml:"serviceType"`
	ControlURL  string `xml:"controlURL"`
}

type upnpDevice struct {
	Services []upnpService `xml:"serviceList>service"`
	Devices  []upnpDevice  `xml:"deviceList>device"`
}

type upnpRoot struct {
	URLBase string     `xml:"URLBase"`
	Device  upnpDevice `xml:"device"`
}

func findWANService(ctx context.Context, client *http.Client, loc string) (*UPnP, error) {
	req, _ := http.NewRequestWithContext(ctx, "GET", loc, nil)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	var root upnpRoot
	if err := xml.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&root); err != nil {
		return nil, err
	}
	base, err := url.Parse(loc)
	if err != nil {
		return nil, err
	}
	if root.URLBase != "" {
		if b, err := url.Parse(root.URLBase); err == nil {
			base = b
		}
	}
	var found *upnpService
	var walk func(d upnpDevice)
	walk = func(d upnpDevice) {
		for i := range d.Services {
			s := d.Services[i]
			if strings.Contains(s.ServiceType, "WANIPConnection") ||
				(found == nil && strings.Contains(s.ServiceType, "WANPPPConnection")) {
				if found == nil || strings.Contains(s.ServiceType, "WANIPConnection") {
					found = &s
				}
			}
		}
		for _, c := range d.Devices {
			walk(c)
		}
	}
	walk(root.Device)
	if found == nil {
		return nil, errors.New("router has no port-mapping service")
	}
	ctl, err := base.Parse(strings.TrimSpace(found.ControlURL))
	if err != nil {
		return nil, err
	}
	return &UPnP{ControlURL: ctl.String(), ServiceType: strings.TrimSpace(found.ServiceType)}, nil
}

// UPnPError is a fault returned by the router.
type UPnPError struct {
	Code int
	Desc string
}

func (e *UPnPError) Error() string {
	switch e.Code {
	case 718:
		return "the router says another device already uses this port"
	case 725:
		return "the router only allows permanent port openings"
	case 606, 401:
		return "the router refused (port opening by apps may be turned off)"
	}
	if e.Desc != "" {
		return fmt.Sprintf("router error %d (%s)", e.Code, e.Desc)
	}
	return fmt.Sprintf("router error %d", e.Code)
}

var (
	reErrCode = regexp.MustCompile(`<(?:\w+:)?errorCode>\s*(\d+)\s*</`)
	reErrDesc = regexp.MustCompile(`<(?:\w+:)?errorDescription>([^<]*)</`)
)

func (u *UPnP) call(ctx context.Context, action string, args [][2]string) (string, error) {
	var b strings.Builder
	b.WriteString(`<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>`)
	fmt.Fprintf(&b, `<u:%s xmlns:u="%s">`, action, u.ServiceType)
	for _, a := range args {
		fmt.Fprintf(&b, "<%s>", a[0])
		xml.EscapeText(&b, []byte(a[1]))
		fmt.Fprintf(&b, "</%s>", a[0])
	}
	fmt.Fprintf(&b, `</u:%s></s:Body></s:Envelope>`, action)
	req, _ := http.NewRequestWithContext(ctx, "POST", u.ControlURL, bytes.NewBufferString(b.String()))
	req.Header.Set("Content-Type", `text/xml; charset="utf-8"`)
	req.Header.Set("SOAPAction", `"`+u.ServiceType+"#"+action+`"`)
	resp, err := u.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	if resp.StatusCode != 200 {
		e := &UPnPError{Code: resp.StatusCode}
		if m := reErrCode.FindSubmatch(body); m != nil {
			e.Code, _ = strconv.Atoi(string(m[1]))
		}
		if m := reErrDesc.FindSubmatch(body); m != nil {
			e.Desc = strings.TrimSpace(string(m[1]))
		}
		return "", e
	}
	return string(body), nil
}

// ExternalIP is the address the router has on the internet side.
func (u *UPnP) ExternalIP(ctx context.Context) (net.IP, error) {
	body, err := u.call(ctx, "GetExternalIPAddress", nil)
	if err != nil {
		return nil, err
	}
	m := regexp.MustCompile(`<NewExternalIPAddress>\s*([0-9.]+)\s*<`).FindStringSubmatch(body)
	if m == nil {
		return nil, errors.New("router did not say its address")
	}
	return net.ParseIP(m[1]).To4(), nil
}

// AddPortMapping forwards TCP port on the router to this computer.
func (u *UPnP) AddPortMapping(ctx context.Context, port int, lease time.Duration) error {
	args := func(l int) [][2]string {
		return [][2]string{
			{"NewRemoteHost", ""},
			{"NewExternalPort", strconv.Itoa(port)},
			{"NewProtocol", "TCP"},
			{"NewInternalPort", strconv.Itoa(port)},
			{"NewInternalClient", u.LocalIP.String()},
			{"NewEnabled", "1"},
			{"NewPortMappingDescription", "AIM Server"},
			{"NewLeaseDuration", strconv.Itoa(l)},
		}
	}
	_, err := u.call(ctx, "AddPortMapping", args(int(lease.Seconds())))
	var ue *UPnPError
	if errors.As(err, &ue) && ue.Code == 725 {
		_, err = u.call(ctx, "AddPortMapping", args(0))
	}
	return err
}

func (u *UPnP) DeletePortMapping(ctx context.Context, port int) error {
	_, err := u.call(ctx, "DeletePortMapping", [][2]string{
		{"NewRemoteHost", ""},
		{"NewExternalPort", strconv.Itoa(port)},
		{"NewProtocol", "TCP"},
	})
	return err
}
