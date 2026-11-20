package main

import (
	"bufio"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"sync"
	"time"
)

// Router owns the one public port. Each new connection is sent where it
// belongs by its first byte:
//
//	0x2A ('*')  OSCAR (AIM)      -> Open OSCAR Server
//	0x16        TLS              -> account API (HTTPS)
//	letters     plain HTTP       -> invite pages and downloads
//	(silence)   OSCAR clients that wait for the server to speak first
type Router struct {
	ln        net.Listener
	TLSConfig *tls.Config
	HTTPS     *chanListener
	HTTP      *chanListener
	// Backend chooses the Open OSCAR Server listener for a client address:
	// the home-network one for local clients, the internet one otherwise.
	Backend func(remote net.IP) string
	// SniffWait is how long to wait for a client to speak before assuming
	// it is an AIM client waiting for the server's greeting.
	SniffWait time.Duration
	Log       *LogBuffer

	sem  chan struct{}
	wg   sync.WaitGroup
	once sync.Once
}

func NewRouter(addr string, tlsConf *tls.Config, backend func(net.IP) string, log *LogBuffer) (*Router, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, err
	}
	r := &Router{
		ln:        ln,
		TLSConfig: tlsConf,
		HTTPS:     newChanListener(ln.Addr()),
		HTTP:      newChanListener(ln.Addr()),
		Backend:   backend,
		SniffWait: 800 * time.Millisecond,
		Log:       log,
		sem:       make(chan struct{}, 4000),
	}
	return r, nil
}

func (r *Router) Addr() net.Addr { return r.ln.Addr() }

func (r *Router) Serve() {
	for {
		c, err := r.ln.Accept()
		if err != nil {
			var ne net.Error
			if errors.As(err, &ne) && ne.Timeout() {
				time.Sleep(50 * time.Millisecond)
				continue
			}
			return
		}
		select {
		case r.sem <- struct{}{}:
		default:
			c.Close() // too many connections at once
			continue
		}
		r.wg.Add(1)
		go func() {
			defer r.wg.Done()
			defer func() { <-r.sem }()
			r.handle(c)
		}()
	}
}

func (r *Router) Close() {
	r.once.Do(func() {
		r.ln.Close()
		r.HTTPS.Close()
		r.HTTP.Close()
	})
}

func (r *Router) handle(c net.Conn) {
	if tc, ok := c.(*net.TCPConn); ok {
		tc.SetKeepAlive(true)
		tc.SetKeepAlivePeriod(2 * time.Minute)
	}
	br := bufio.NewReaderSize(c, 4096)
	c.SetReadDeadline(time.Now().Add(r.SniffWait))
	first, err := br.Peek(1)
	c.SetReadDeadline(time.Time{})
	pc := &peekedConn{Conn: c, r: br}
	if err != nil {
		var ne net.Error
		if errors.As(err, &ne) && ne.Timeout() {
			r.proxyOSCAR(pc)
			return
		}
		c.Close()
		return
	}
	switch b := first[0]; {
	case b == 0x2A:
		r.proxyOSCAR(pc)
	case b == 0x16:
		tc := tls.Server(pc, r.TLSConfig)
		if !r.HTTPS.deliver(tc) {
			c.Close()
		}
	case b >= 'A' && b <= 'Z':
		if !r.HTTP.deliver(pc) {
			c.Close()
		}
	default:
		c.Close()
	}
}

func (r *Router) proxyOSCAR(c *peekedConn) {
	defer c.Close()
	target := r.Backend(remoteIP(c.RemoteAddr()))
	if target == "" {
		return
	}
	b, err := net.DialTimeout("tcp", target, 5*time.Second)
	if err != nil {
		return
	}
	defer b.Close()
	done := make(chan struct{}, 2)
	go func() {
		io.Copy(b, c) // includes any bytes already peeked
		if tc, ok := b.(*net.TCPConn); ok {
			tc.CloseWrite()
		}
		done <- struct{}{}
	}()
	go func() {
		io.Copy(c.Conn, b)
		if tc, ok := c.Conn.(*net.TCPConn); ok {
			tc.CloseWrite()
		}
		done <- struct{}{}
	}()
	<-done
	// give the other direction a moment to finish, then tear down
	select {
	case <-done:
	case <-time.After(5 * time.Second):
	}
}

// peekedConn is a connection whose first bytes were already read into r.
type peekedConn struct {
	net.Conn
	r *bufio.Reader
}

func (p *peekedConn) Read(b []byte) (int, error) { return p.r.Read(b) }

// chanListener hands connections from the router to an http.Server.
type chanListener struct {
	addr   net.Addr
	ch     chan net.Conn
	closed chan struct{}
	once   sync.Once
}

func newChanListener(addr net.Addr) *chanListener {
	return &chanListener{addr: addr, ch: make(chan net.Conn), closed: make(chan struct{})}
}

func (l *chanListener) deliver(c net.Conn) bool {
	select {
	case l.ch <- c:
		return true
	case <-l.closed:
		return false
	case <-time.After(10 * time.Second):
		return false
	}
}

func (l *chanListener) Accept() (net.Conn, error) {
	select {
	case c := <-l.ch:
		return c, nil
	case <-l.closed:
		return nil, net.ErrClosed
	}
}

func (l *chanListener) Close() error {
	l.once.Do(func() { close(l.closed) })
	return nil
}

func (l *chanListener) Addr() net.Addr { return l.addr }
