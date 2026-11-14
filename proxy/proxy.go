package main

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

var hopHeaders = []string{
	"Connection", "Proxy-Connection", "Keep-Alive", "Proxy-Authenticate", "Proxy-Authorization",
	"Te", "Trailer", "Transfer-Encoding", "Upgrade",
}

type proxy struct {
	cfg       Config
	transport *http.Transport
}

func newServer(cfg Config) *http.Server {
	p := &proxy{cfg: cfg}
	p.transport = &http.Transport{
		Proxy:                 nil, // never chain to another proxy from the environment
		DialContext:           p.dial,
		MaxIdleConns:          100,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   15 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		ResponseHeaderTimeout: 60 * time.Second,
	}
	return &http.Server{
		Handler:           p,
		ReadHeaderTimeout: 15 * time.Second,
		IdleTimeout:       120 * time.Second,
		ErrorLog:          log.New(io.Discard, "", 0),
	}
}

// blockedNets are refused unless allow_private is set: this machine's loopback, LAN, link-local,
// the VPN's CGNAT range and other non-internet ranges. The proxy is for egress to the internet only.
var blockedNets = func() []*net.IPNet {
	var out []*net.IPNet
	for _, c := range []string{
		"0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12",
		"192.0.0.0/24", "192.168.0.0/16", "198.18.0.0/15", "224.0.0.0/4", "240.0.0.0/4",
		"::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8", "64:ff9b:1::/48",
	} {
		_, n, _ := net.ParseCIDR(c)
		out = append(out, n)
	}
	return out
}()

func blocked(ip net.IP) bool {
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	for _, n := range blockedNets {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

var errBlocked = errors.New("destination not allowed")

// dial resolves the host itself and connects to an allowed address, so a hostname cannot be used to
// reach a blocked address (no separate resolve-then-dial race).
func (p *proxy) dial(ctx context.Context, network, addr string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return nil, err
	}
	ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, err
	}
	d := net.Dialer{Timeout: 15 * time.Second, KeepAlive: 30 * time.Second}
	var lastErr error = errBlocked
	for _, ip := range ips {
		if !p.cfg.AllowPrivate && blocked(ip.IP) {
			continue
		}
		c, err := d.DialContext(ctx, "tcp", net.JoinHostPort(ip.IP.String(), port))
		if err == nil {
			return c, nil
		}
		lastErr = err
	}
	return nil, lastErr
}

func (p *proxy) authorized(r *http.Request) bool {
	h := r.Header.Get("Proxy-Authorization")
	const prefix = "Basic "
	if len(h) < len(prefix) || !strings.EqualFold(h[:len(prefix)], prefix) {
		return false
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(h[len(prefix):]))
	if err != nil {
		return false
	}
	user, pass, ok := strings.Cut(string(raw), ":")
	return ok && p.cfg.checkAuth(user, pass)
}

func (p *proxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	isProxyReq := r.Method == http.MethodConnect || r.URL.IsAbs()
	if !isProxyReq {
		http.Error(w, display+" Proxy: configure this address as an HTTP/HTTPS proxy", http.StatusBadRequest)
		return
	}
	if !p.authorized(r) {
		time.Sleep(500 * time.Millisecond) // slow down password guessing
		w.Header().Set("Proxy-Authenticate", `Basic realm="`+display+` Proxy"`)
		http.Error(w, "proxy login required", http.StatusProxyAuthRequired)
		if r.Header.Get("Proxy-Authorization") != "" {
			log.Printf("rejected login from %s", r.RemoteAddr)
		}
		return
	}
	if r.Method == http.MethodConnect {
		p.connect(w, r)
		return
	}
	p.forward(w, r)
}

func dialStatus(err error) int {
	if errors.Is(err, errBlocked) {
		return http.StatusForbidden
	}
	return http.StatusBadGateway
}

// connect tunnels HTTPS (and any TCP) unchanged: the proxy never sees inside TLS.
func (p *proxy) connect(w http.ResponseWriter, r *http.Request) {
	target := r.Host
	if _, _, err := net.SplitHostPort(target); err != nil {
		target = net.JoinHostPort(target, "443")
	}
	up, err := p.dial(r.Context(), "tcp", target)
	if err != nil {
		log.Printf("%s CONNECT %s: %v", r.RemoteAddr, target, err)
		http.Error(w, err.Error(), dialStatus(err))
		return
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		_ = up.Close()
		http.Error(w, "hijacking not supported", http.StatusInternalServerError)
		return
	}
	down, buf, err := hj.Hijack()
	if err != nil {
		_ = up.Close()
		return
	}
	log.Printf("%s CONNECT %s", r.RemoteAddr, target)
	_, _ = down.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))
	// bytes the client already sent after the CONNECT headers
	if n := buf.Reader.Buffered(); n > 0 {
		b, _ := buf.Reader.Peek(n)
		_, _ = up.Write(b)
	}
	pipe(down, up)
}

func pipe(a, b net.Conn) {
	var wg sync.WaitGroup
	wg.Add(2)
	cp := func(dst, src net.Conn) {
		defer wg.Done()
		_, _ = io.Copy(dst, src)
		if tc, ok := dst.(*net.TCPConn); ok {
			_ = tc.CloseWrite()
		} else {
			_ = dst.Close()
		}
	}
	go cp(a, b)
	go cp(b, a)
	wg.Wait()
	_ = a.Close()
	_ = b.Close()
}

// forward handles plain-HTTP proxy requests (absolute URL).
func (p *proxy) forward(w http.ResponseWriter, r *http.Request) {
	out := r.Clone(r.Context())
	out.RequestURI = ""
	removeHop(out.Header)
	if out.URL.Scheme != "http" {
		http.Error(w, fmt.Sprintf("unsupported scheme %q (use CONNECT for https)", out.URL.Scheme), http.StatusBadRequest)
		return
	}
	resp, err := p.transport.RoundTrip(out)
	if err != nil {
		log.Printf("%s %s %s: %v", r.RemoteAddr, r.Method, r.URL.Host, err)
		http.Error(w, err.Error(), dialStatus(err))
		return
	}
	defer resp.Body.Close()
	log.Printf("%s %s http://%s", r.RemoteAddr, r.Method, r.URL.Host)
	removeHop(resp.Header)
	for k, vs := range resp.Header {
		for _, v := range vs {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func removeHop(h http.Header) {
	for _, f := range strings.Split(h.Get("Connection"), ",") {
		if f = strings.TrimSpace(f); f != "" {
			h.Del(f)
		}
	}
	for _, k := range hopHeaders {
		h.Del(k)
	}
}
