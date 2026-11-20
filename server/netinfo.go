package main

import (
	"context"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

var cgnatBlock = mustCIDR("100.64.0.0/10")

func mustCIDR(s string) *net.IPNet {
	_, n, err := net.ParseCIDR(s)
	if err != nil {
		panic(err)
	}
	return n
}

// isLocalIP is true for addresses inside a home network (or this computer).
func isLocalIP(ip net.IP) bool {
	return ip != nil && (ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast())
}

// isPublicIP is true for an address the wider internet can route to.
func isPublicIP(ip net.IP) bool {
	return ip != nil && ip.To4() != nil && !isLocalIP(ip) && !cgnatBlock.Contains(ip) &&
		!ip.IsUnspecified() && !ip.IsMulticast()
}

// LocalIP is this computer's address on the home network: the one used to
// reach the internet.
func LocalIP() net.IP {
	if c, err := net.Dial("udp4", "8.8.8.8:80"); err == nil { // sends nothing
		defer c.Close()
		if a, ok := c.LocalAddr().(*net.UDPAddr); ok && !a.IP.IsLoopback() {
			return a.IP.To4()
		}
	}
	ips := LocalIPs()
	if len(ips) > 0 {
		return ips[0]
	}
	return net.IPv4(127, 0, 0, 1).To4()
}

// LocalIPs lists every private IPv4 address of this computer.
func LocalIPs() []net.IP {
	var out []net.IP
	ifs, _ := net.Interfaces()
	for _, ifc := range ifs {
		if ifc.Flags&net.FlagUp == 0 || ifc.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := ifc.Addrs()
		for _, a := range addrs {
			if n, ok := a.(*net.IPNet); ok {
				if ip := n.IP.To4(); ip != nil && ip.IsPrivate() {
					out = append(out, ip)
				}
			}
		}
	}
	return out
}

var publicIPServices = []string{
	"https://api.ipify.org",
	"https://icanhazip.com",
	"https://ifconfig.me/ip",
	"https://checkip.amazonaws.com",
}

// PublicIP asks a what's-my-IP service which address the internet sees.
func PublicIP(ctx context.Context) (net.IP, error) {
	var last error
	client := &http.Client{Timeout: 6 * time.Second}
	for _, u := range publicIPServices {
		req, _ := http.NewRequestWithContext(ctx, "GET", u, nil)
		req.Header.Set("User-Agent", "aim-server")
		resp, err := client.Do(req)
		if err != nil {
			last = err
			if ctx.Err() != nil {
				break
			}
			continue
		}
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 100))
		resp.Body.Close()
		ip := net.ParseIP(strings.TrimSpace(string(b)))
		if ip != nil && ip.To4() != nil {
			return ip.To4(), nil
		}
		last = io.ErrUnexpectedEOF
	}
	return nil, last
}

func remoteIP(addr net.Addr) net.IP {
	switch a := addr.(type) {
	case *net.TCPAddr:
		return a.IP
	case *net.UDPAddr:
		return a.IP
	}
	host, _, err := net.SplitHostPort(addr.String())
	if err != nil {
		return nil
	}
	return net.ParseIP(host)
}

func hostOnly(remoteAddr string) string {
	h, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		return remoteAddr
	}
	return h
}
