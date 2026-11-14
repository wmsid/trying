package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/kardianos/service"
)

const pollEvery = 5 * time.Second

// clientCLI finds the VPN client's CLI: next to this program first (Windows install folder),
// then the usual Unix location, then PATH.
func clientCLI() string {
	exe := brand
	if runtime.GOOS == "windows" {
		exe += ".exe"
	}
	if self, err := os.Executable(); err == nil {
		p := filepath.Join(filepath.Dir(self), exe)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	if runtime.GOOS != "windows" {
		if _, err := os.Stat("/usr/local/bin/" + brand); err == nil {
			return "/usr/local/bin/" + brand
		}
	}
	if p, err := exec.LookPath(exe); err == nil {
		return p
	}
	return exe
}

// vpnIP asks the VPN client for this machine's current VPN IPv4 (empty/error when not connected).
func vpnIP() (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, clientCLI(), "status", "--ipv4").Output()
	if err != nil {
		return "", fmt.Errorf("%s status: %w", brand, err)
	}
	s := strings.TrimSpace(string(out))
	ip := net.ParseIP(s)
	if ip == nil || ip.To4() == nil || ip.IsUnspecified() {
		return "", errors.New("VPN not connected")
	}
	return ip.String(), nil
}

type program struct {
	cancel context.CancelFunc
	done   chan struct{}
}

func (p *program) Start(s service.Service) error {
	ctx, cancel := context.WithCancel(context.Background())
	p.cancel, p.done = cancel, make(chan struct{})
	go func() { defer close(p.done); loop(ctx) }()
	return nil
}

func (p *program) Stop(s service.Service) error {
	if p.cancel != nil {
		p.cancel()
		select {
		case <-p.done:
		case <-time.After(5 * time.Second):
		}
	}
	return nil
}

func runService() {
	setupLog()
	s, err := newService(&program{})
	if err != nil {
		log.Fatal(err)
	}
	if err := s.Run(); err != nil {
		log.Fatal(err)
	}
}

// setupLog writes to <dataDir>/proxy.log (rotated once at 10 MB) and stderr.
func setupLog() {
	_ = os.MkdirAll(dataDir(), 0o755)
	p := filepath.Join(dataDir(), "proxy.log")
	if st, err := os.Stat(p); err == nil && st.Size() > 10<<20 {
		_ = os.Rename(p, p+".1")
	}
	f, err := os.OpenFile(p, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	log.SetOutput(io.MultiWriter(os.Stderr, f))
	log.SetFlags(log.LstdFlags | log.LUTC)
}

// loop keeps one HTTP server bound to <current VPN IP>:<port>, re-binding when the IP or the
// configured port changes, and listening on nothing while the VPN is down.
func loop(ctx context.Context) {
	log.Printf("%s Proxy %s starting (config %s)", display, version, configPath())
	var (
		srv      *http.Server
		boundTo  string
		boundCfg Config
		lastNote string
	)
	note := func(msg string) { // log a state only when it changes
		if msg != lastNote {
			log.Print(msg)
			lastNote = msg
		}
	}
	stop := func() {
		if srv != nil {
			sctx, c := context.WithTimeout(context.Background(), 3*time.Second)
			_ = srv.Shutdown(sctx)
			c()
			log.Printf("stopped listening on %s", boundTo)
			srv, boundTo = nil, ""
		}
	}
	defer stop()

	t := time.NewTicker(pollEvery)
	defer t.Stop()
	for {
		cfg, err := loadConfig()
		if err != nil {
			note("config: " + err.Error())
		}
		want := ""
		if !cfg.hasAuth() {
			note("no login set: refusing to listen (run: " + serviceName() + " set-auth <user> --password-stdin)")
		} else if ip, err := vpnIP(); err != nil {
			note("waiting for VPN: " + err.Error())
		} else {
			want = net.JoinHostPort(ip, fmt.Sprint(cfg.Port))
		}
		if want != boundTo || (srv != nil && cfg != boundCfg) {
			stop()
			if want != "" {
				ln, err := net.Listen("tcp", want)
				if err != nil {
					note(fmt.Sprintf("cannot listen on %s: %v", want, err))
				} else {
					srv = newServer(cfg)
					boundTo, boundCfg = want, cfg
					lastNote = ""
					log.Printf("listening on %s", want)
					go func(s *http.Server, l net.Listener) {
						if err := s.Serve(l); err != nil && !errors.Is(err, http.ErrServerClosed) {
							log.Printf("serve: %v", err)
						}
					}(srv, ln)
				}
			}
		}
		select {
		case <-ctx.Done():
			log.Print("shutting down")
			return
		case <-t.C:
		}
	}
}
