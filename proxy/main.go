// Command <brand>-proxy is a small HTTP/HTTPS forward proxy that listens ONLY on this machine's VPN IP.
//
// It is deliberately separate from the VPN client: its own program, its own service, its own config. The only
// link is the client's public CLI (`<brand> status --ipv4`), polled to learn the current VPN IP, so the
// upstream NetBird client can be upgraded without touching this code.
//
//	<brand>-proxy run                         run in the foreground (also the service entry point)
//	<brand>-proxy service install|uninstall|start|stop|restart|status
//	<brand>-proxy set-port <port> [--no-check] save the port (checked to be free unless --no-check)
//	<brand>-proxy check-port <port>           exit 0 = free, 1 = in use, 2 = invalid
//	<brand>-proxy get-port                    print the configured port
//	<brand>-proxy set-auth <user> --password-file <file> | --password-stdin
//	                                          set the login (required: the proxy will not listen without one)
//	<brand>-proxy has-auth                    exit 0 if a login is set
//	<brand>-proxy version
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/kardianos/service"
)

// Set at build time with -ldflags -X.
var (
	brand   = "slbzt"
	display = "SLBZT"
	version = "dev"
)

func serviceName() string { return brand + "-proxy" }

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "run":
		runService()
	case "service":
		if len(os.Args) < 3 {
			usage()
			os.Exit(2)
		}
		os.Exit(controlService(os.Args[2]))
	case "set-port":
		os.Exit(cmdSetPort(os.Args[2:]))
	case "check-port":
		os.Exit(cmdCheckPort(os.Args[2:]))
	case "set-auth":
		os.Exit(cmdSetAuth(os.Args[2:]))
	case "has-auth":
		cfg, err := loadConfig()
		if err != nil || !cfg.hasAuth() {
			os.Exit(1)
		}
		fmt.Println(cfg.User)
	case "get-port":
		cfg, err := loadConfig()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println(cfg.Port)
	case "version", "--version", "-v":
		fmt.Println(version)
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	n := serviceName()
	fmt.Fprintf(os.Stderr, `%s %s - HTTP/HTTPS proxy on this machine's VPN IP

Usage:
  %s run
  %s service install|uninstall|start|stop|restart|status
  %s set-port <port> [--no-check]
  %s check-port <port>
  %s get-port
  %s set-auth <user> --password-file <file> | --password-stdin
  %s has-auth
  %s version
`, display, "Proxy", n, n, n, n, n, n, n, n)
}

func parsePort(s string) (int, bool) {
	p, err := strconv.Atoi(s)
	if err != nil || p < 1 || p > 65535 {
		return 0, false
	}
	return p, true
}

func cmdCheckPort(args []string) int {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "check-port: port required")
		return 2
	}
	p, ok := parsePort(args[0])
	if !ok {
		fmt.Fprintf(os.Stderr, "invalid port %q (use 1-65535)\n", args[0])
		return 2
	}
	if err := portFree(p); err != nil {
		fmt.Fprintf(os.Stderr, "port %d is in use: %v\n", p, err)
		return 1
	}
	fmt.Printf("port %d is free\n", p)
	return 0
}

func cmdSetPort(args []string) int {
	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "set-port: port required")
		return 2
	}
	p, ok := parsePort(args[0])
	if !ok {
		fmt.Fprintf(os.Stderr, "invalid port %q (use 1-65535)\n", args[0])
		return 2
	}
	check := !(len(args) > 1 && args[1] == "--no-check")
	if check {
		if err := portFree(p); err != nil {
			fmt.Fprintf(os.Stderr, "port %d is in use: %v\n", p, err)
			return 1
		}
	}
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	cfg.Port = p
	if err := saveConfig(cfg); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Printf("proxy port set to %d\n", p)
	return 0
}

func newService(prg service.Interface) (service.Service, error) {
	return service.New(prg, &service.Config{
		Name:        serviceName(),
		DisplayName: display + " Proxy",
		Description: display + " HTTP/HTTPS proxy, listening only on the VPN IP",
		Arguments:   []string{"run"},
	})
}

func controlService(action string) int {
	s, err := newService(&program{})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if action == "status" {
		st, err := s.Status()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		fmt.Println(map[service.Status]string{service.StatusRunning: "running", service.StatusStopped: "stopped"}[st])
		return 0
	}
	if err := service.Control(s, action); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Printf("%s Proxy service: %s ok\n", display, action)
	return 0
}

func cmdSetAuth(args []string) int {
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "set-auth: usage: set-auth <user> --password-file <file> | --password-stdin")
		return 2
	}
	user := args[0]
	var pass string
	switch {
	case args[1] == "--password-stdin":
		line, err := bufio.NewReader(os.Stdin).ReadString('\n')
		if err != nil && line == "" {
			fmt.Fprintln(os.Stderr, "set-auth: no password on stdin")
			return 2
		}
		pass = strings.TrimRight(line, "\r\n")
	case args[1] == "--password-file" && len(args) > 2:
		b, err := os.ReadFile(args[2])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		pass = strings.TrimRight(string(b), "\r\n")
	default:
		fmt.Fprintln(os.Stderr, "set-auth: give --password-file <file> or --password-stdin")
		return 2
	}
	cfg, err := loadConfig()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if err := cfg.setAuth(user, pass); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if err := saveConfig(cfg); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Printf("proxy login set for user %s\n", user)
	return 0
}
