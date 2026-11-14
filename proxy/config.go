package main

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

const defaultPort = 3128

// Config lives in its own directory (never inside the VPN client's), so either can be upgraded
// or removed without touching the other.
type Config struct {
	Port int `json:"port"`
	// AllowPrivate lets VPN users reach this machine's own LAN/loopback/VPN ranges through the proxy.
	// Off by default: the proxy is for egress to the internet only.
	AllowPrivate bool `json:"allow_private"`
	// Login required by the proxy (HTTP Basic). Only a salted SHA-256 of the password is stored.
	User     string `json:"user"`
	Salt     string `json:"salt"`
	PassHash string `json:"pass_sha256"`
}

func (c Config) hasAuth() bool { return c.User != "" && c.Salt != "" && c.PassHash != "" }

func hashPass(salt, pass string) string {
	h := sha256.Sum256([]byte(salt + "\x00" + pass))
	return hex.EncodeToString(h[:])
}

func (c *Config) setAuth(user, pass string) error {
	if err := validUser(user); err != nil {
		return err
	}
	if len(pass) < 8 {
		return errors.New("password must be at least 8 characters")
	}
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return err
	}
	c.User, c.Salt = user, hex.EncodeToString(b)
	c.PassHash = hashPass(c.Salt, pass)
	return nil
}

func validUser(u string) error {
	if u == "" {
		return errors.New("username must not be empty")
	}
	for _, r := range u {
		if r == ':' || r <= ' ' || r == 0x7f {
			return errors.New("username must not contain spaces, control characters or ':'")
		}
	}
	return nil
}

func (c Config) checkAuth(user, pass string) bool {
	if !c.hasAuth() {
		return false
	}
	okU := subtle.ConstantTimeCompare([]byte(user), []byte(c.User)) == 1
	okP := subtle.ConstantTimeCompare([]byte(hashPass(c.Salt, pass)), []byte(c.PassHash)) == 1
	return okU && okP
}

func dataDir() string {
	if runtime.GOOS == "windows" {
		pd := os.Getenv("ProgramData")
		if pd == "" {
			pd = `C:\ProgramData`
		}
		return filepath.Join(pd, serviceName())
	}
	return "/var/lib/" + serviceName()
}

func configPath() string { return filepath.Join(dataDir(), "config.json") }

func loadConfig() (Config, error) {
	cfg := Config{Port: defaultPort}
	b, err := os.ReadFile(configPath())
	if errors.Is(err, os.ErrNotExist) {
		return cfg, nil
	}
	if err != nil {
		return cfg, fmt.Errorf("read %s: %w", configPath(), err)
	}
	if err := json.Unmarshal(b, &cfg); err != nil {
		return cfg, fmt.Errorf("parse %s: %w", configPath(), err)
	}
	if cfg.Port < 1 || cfg.Port > 65535 {
		cfg.Port = defaultPort
	}
	return cfg, nil
}

func saveConfig(cfg Config) error {
	if err := os.MkdirAll(dataDir(), 0o700); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(cfg, "", "  ")
	tmp := configPath() + ".tmp"
	if err := os.WriteFile(tmp, append(b, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, configPath())
}

// portFree reports an error if anything already uses the TCP port: it must be bindable on all
// addresses, and nothing may answer on loopback or on this machine's VPN IP.
func portFree(port int) error {
	l, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return err
	}
	_ = l.Close()
	addrs := []string{"127.0.0.1"}
	if ip, err := vpnIP(); err == nil {
		addrs = append(addrs, ip)
	}
	for _, a := range addrs {
		c, err := net.DialTimeout("tcp", net.JoinHostPort(a, fmt.Sprint(port)), 700*time.Millisecond)
		if err == nil {
			_ = c.Close()
			return fmt.Errorf("something is already listening on %s:%d", a, port)
		}
	}
	return nil
}
