# Headless, unbranded NetBird client (Windows + macOS)

A build pipeline that takes upstream NetBird, strips the branding, bakes in **your**
management server, and ships a UI-less client that runs as a system service.

End-user experience:

```
# Windows (admin PowerShell)             # macOS
.\install.ps1                            sudo ./install.sh
slbzt up --setup-key abcd             sudo slbzt up --setup-key abcd
```
(or one step: `.\install.ps1 -SetupKey abcd` / `sudo ./install.sh abcd`)

No management URL to type, no GUI, no "NetBird" anywhere in CLI, service name,
config dirs (`%ProgramData%\<name>`, `/var/lib/<name>`), socket or pipe names.

## Build

1. Edit `brand.env` (name, display name, `MGMT_URL`, upstream version).
2. `./scripts/build.sh` (needs Go, git, zip). Output in `dist/`:
   `*_windows_{amd64,arm64}.zip`, `*_darwin_{amd64,arm64}.tar.gz`.
   Or push a `v*` tag and GitHub Actions builds and attaches them to a release.

Hand users the archive for their OS plus a setup key from your dashboard.

## What the rebrand does (`scripts/rebrand.sh`)
- Renames CLI, service, config/log/state dirs, unix socket, Windows pipe, help text.
- Default management URL -> `MGMT_URL`.
- Points upstream docs/telemetry/updater-key endpoints at nothing (metrics push is already off by default).
- Keeps the Go module path (invisible to users) so upstream upgrades are a version bump.

## Running next to stock NetBird
Everything that could collide is separate: service name, config/log/state dirs, daemon socket/pipe,
firewall chain names, WireGuard interface (`slbzt0`, `utun150` on macOS) and listen port (51821 vs 51820).
Remaining caveat: both overlays should use **different IP ranges** (your management server's
network range vs NetBird's default 100.64.0.0/10) and not push conflicting DNS/routes.

## Install or update: one file per OS
The same file installs on a new machine and updates an existing one. It detects the system and does the right thing:
- **New machine:** installs and connects with the setup key you give it.
- **Already set up** (config in `/var/lib/<name>` or `%ProgramData%\<display name>`): replaces the program, keeps the
  config, and reconnects as the same peer with the same IP. No setup key is needed, but if you give one it is used
  (useful when the machine was removed from the dashboard or its login expired).

Do **not** uninstall before updating: uninstalling deletes the config, so the machine would register as a new peer.
Linux/macOS uninstall: `sudo ./uninstall.sh` from an extracted archive (removes the service, program, config and logs).

**Linux**: `bin/slbzt_linux_setup.sh` detects the CPU (x86_64, arm64, armv6/7, i386/i686), downloads the matching
build, checks its SHA-256 and installs or updates.
```bash
curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_linux_setup.sh | sudo bash -s -- <SETUP_KEY>   # new machine
curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_linux_setup.sh | sudo bash                    # update
```

**macOS**: `bin/slbzt_macos_setup.sh` detects Apple Silicon or Intel (also when the shell runs under Rosetta),
downloads the matching build, checks its SHA-256 and installs or updates. Files fetched with `curl` get no
quarantine flag, so Gatekeeper does not block the unsigned binary.
```bash
curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_macos_setup.sh | sudo bash -s -- <SETUP_KEY>   # new Mac
curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_macos_setup.sh | sudo bash                    # update
```

On Linux and macOS an update without a key does not run `up`: the service reconnects by itself with the saved config. If the
machine has to log in again (removed from the dashboard, or login expired), the script says so and prints the
`up --setup-key` command instead of waiting. The Windows setup behaves the same way.

**Windows**: `bin/slbzt_windows_setup.exe` contains every Windows build and picks one at run time: Windows 10/11 x64,
Windows 10/11 ARM64, or the Win7-compatible build on Windows 7/8/8.1 and 32-bit Windows. Double-click it; on a new
PC it asks for the setup key, and on an already set-up PC it shows "update", skips the folder page and makes the key optional.
Silent: `slbzt_windows_setup.exe /S /SETUPKEY=<key>` (new PC; optional `/MGMT=https://other:443`) or
`slbzt_windows_setup.exe /S` (update). Exit codes: 5 = new PC without key, 6 = unsupported Windows.

Check the result with `sudo slbzt version` / `sudo slbzt status`
(Windows: `& "$env:ProgramFiles\slbzt\slbzt.exe" status`).

## Optional proxy (`slbzt-proxy`)
An HTTP/HTTPS forward proxy that can be installed next to the VPN client, so machines on the VPN can send
traffic out through a client's internet connection (for sites that allow only certain IP addresses).
- **Separate program and service** (`proxy/`, service `slbzt-proxy`), never mixed into the NetBird source, so the
  client stays a plain version bump. Its only link to the client is `slbzt status --ipv4`, polled to learn the VPN IP.
- **Listens only on the VPN IP** (nothing while the VPN is down; follows IP changes). Who can reach it is decided
  by your dashboard: add an access policy allowing the server(s) to the clients on the proxy port.
- **Login required** (HTTP Basic, username + password of at least 8 characters, set per machine at install; only a
  salted hash is stored in `/var/lib/slbzt-proxy/config.json` or `%ProgramData%\slbzt-proxy\config.json`).
- HTTPS goes through as an unchanged tunnel (CONNECT); plain HTTP is forwarded.
- By default it refuses destinations on loopback, LAN, link-local and the VPN range, so VPN users cannot reach the
  client's own network. Set `"allow_private": true` in its config to allow that.
- Log: `proxy.log` in the same folder.

**Not installed unless chosen.** Existing commands behave exactly as before.
- **Windows:** the setup has a Components page; the proxy is unticked unless already installed. Ticking it shows a
  page for the port (default 3128, checked to be free) and the login. Silent:
  `/PROXY=1 /PROXYPORT=3128 /PROXYUSER=<user> /PROXYPASS=<password>`; `/PROXY=0` removes it. Exit codes 7 (port
  invalid or in use) and 8 (login missing or invalid).
- **Linux/macOS:** when run in a terminal, the script asks whether to install the proxy (default No), then asks for
  the port and login. Unattended:
  ```bash
  PROXY_PASSWORD='<password>' bash -c 'curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_linux_setup.sh | sudo -E bash -s -- <SETUP_KEY> --proxy --proxy-user <user> --proxy-port 3128'
  ```
  Options: `--proxy`, `--no-proxy` (remove), `--proxy-port <port>`, `--proxy-user <user>`,
  `--proxy-password-file <file>` (or the `PROXY_PASSWORD` environment variable).
- **Updates** keep an installed proxy with its port and login, unless you give new ones.
- Use it from the server: `curl -x http://<user>:<password>@<client VPN IP>:3128 https://example.com`.

## Requirements / caveats
- You need a NetBird **management server** (self-hosted) - it issues setup keys. The client is only the peer side.
- Binaries are unsigned. Sign them (Authenticode on Windows; Developer ID + notarization on macOS) or Gatekeeper/SmartScreen will warn. The macOS script clears the quarantine flag, which helps for CLI use only.
- Built with `CGO_ENABLED=0`; cross-compiled, so macOS/Windows runtime behavior was **not** tested here.
- The rebrand patch is regex-based; when bumping `NETBIRD_VERSION`, check the build output for `WARN: leftover brand strings`.

## Windows installer (.exe)
`slbzt_windows_setup.exe` (see above) is a real setup program: admin prompt, installs to Program Files, registers the
service (does not modify PATH; run it from the install folder), shows in Add/Remove Programs, includes an uninstaller.
Uninstall: Settings > Apps, or `"%ProgramFiles%\slbzt\uninstall.exe" /S`.
The per-architecture `.zip` files still contain `install.ps1` for manual installs; if PowerShell blocks it, use
`powershell -ExecutionPolicy Bypass -File .\install.ps1`.

## Linux
Use `slbzt_linux_setup.sh` (see above). The per-CPU `*_linux_{amd64,arm64,arm,386}.tar.gz` archives it downloads can
also be used by hand: `tar xzf ...; cd ...; sudo ./install.sh [SETUP_KEY]` (same install-or-update behaviour).
It installs a systemd (or init) service via `slbzt service install`. Static binaries (no libc dependency).

## Windows 7 / 8 / 8.1
The Win7 builds (inside `slbzt_windows_setup.exe`, and `*_windows7_{amd64,386}.zip`) are compiled with the community Go fork go-legacy-win7 (pinned in `brand.env`),
because official Go dropped Win7 in 1.21. They compile cleanly but are **untested on real Windows 7**.
The machine needs SP1 plus the SHA-2 code-signing update (KB4474419) for the network driver to load.
Set `WIN7_GO_TAG=` empty to skip.

## Prebuilt binaries
Every push to the working branch rebuilds and commits the archives into `bin/` (with `SHA256SUMS`).
Each build adds ~50 MB to repo history; if that grows too large, switch the workflow to force-push
`bin/` to a separate `builds` branch instead. Run `git pull` before pushing your own changes,
since the bot commits to the same branch.
