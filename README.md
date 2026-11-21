# SLBZT VPN client (Windows, Linux, macOS)

A headless (no GUI) VPN client built from NetBird, pre-configured for **zt.skylinebiz.in**. It runs as a
background service. Optionally, it can also install **SLBZT Proxy**, an HTTP/HTTPS proxy that listens only on the
machine's VPN address.

# Installation

**Before you start:**
- Get a **setup key** from the dashboard. A new machine needs one; an update does not.
- You need administrator rights (Windows) or `sudo` (Linux, macOS).
- The same file installs on a new machine and updates an existing one. Updating keeps the machine's settings,
  identity and VPN IP, so **do not uninstall before updating**.

## Windows

Works on Windows 10/11 (x64 and ARM64) and Windows 7/8/8.1 (64- and 32-bit). The one setup file picks the right
build for the PC.

**Install**
1. Download **[slbzt_windows_setup.exe](https://github.com/wmsid/trying/raw/main/bin/slbzt_windows_setup.exe)**.
2. Double-click it and allow the administrator prompt. The file is not code-signed, so if Windows shows
   "Windows protected your PC", click **More info**, then **Run anyway**.
3. Click through the wizard:
   - **Components:** "SLBZT VPN client" is always installed. Tick "SLBZT Proxy" only if this PC should run the
     proxy (see [Optional proxy](#optional-slbzt-proxy)).
   - **Setup key:** paste your key.
4. The last page shows the PC's **DNS name** and **IP address** on the VPN.

The setup also keeps the VPN adapter on the **Private** network profile. Windows would otherwise label it an
"Unidentified network" and treat it as Public, where firewall block rules and "block all incoming connections"
apply. A hidden scheduled task, "SLBZT network profile", re-applies Private at startup, whenever a network connects
and every 5 minutes. It touches only the VPN adapter; uninstalling removes it.

**Check** (PowerShell as Administrator):
```powershell
& "$env:ProgramFiles\slbzt\slbzt.exe" status
```

**Update:** run the newest `slbzt_windows_setup.exe` again. It detects the existing install, skips the folder
page and makes the setup key optional. Leave the key empty unless the PC was removed from the dashboard.

**Silent install / update** (for scripts and deployment tools, run as Administrator):
```powershell
.\slbzt_windows_setup.exe /S /SETUPKEY=<SETUP_KEY>
```
```powershell
.\slbzt_windows_setup.exe /S
```
The first installs on a new PC (key required); the second updates an existing one. Exit codes: 0 = OK,
4 = installed but not connected, 5 = new PC without a key, 6 = unsupported Windows, 7 = proxy port invalid or in
use, 8 = proxy login missing or invalid, 9 = proxy service failed to start.

**Uninstall:** Settings > Apps > **SLBZT** > Uninstall, or silently:
```powershell
& "$env:ProgramFiles\slbzt\uninstall.exe" /S
```

## Linux

Works on x86_64, arm64, 32-bit ARM (armv6/armv7) and 32-bit x86, on any distribution with systemd or SysV init.
The script detects the CPU, downloads the matching build and checks its checksum.

**Install:**
```bash
curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_linux_setup.sh | sudo bash -s -- <SETUP_KEY>
```
When run in a terminal, the script asks whether to also install SLBZT Proxy (default: No).

**Check:**
```bash
sudo slbzt status
```

**Update:**
```bash
curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_linux_setup.sh | sudo bash
```
If the machine was removed from the dashboard or its login expired, the script says so; run the install command
above with a setup key.

**Uninstall** (removes the client, the proxy if installed, and their settings):
```bash
sudo slbzt-proxy service stop 2>/dev/null; sudo slbzt-proxy service uninstall 2>/dev/null; sudo rm -rf /usr/local/bin/slbzt-proxy /var/lib/slbzt-proxy
```
```bash
sudo slbzt down; sudo slbzt service stop; sudo slbzt service uninstall; sudo rm -rf /usr/local/bin/slbzt /var/lib/slbzt /etc/slbzt /var/log/slbzt
```
(Or run `sudo ./uninstall.sh` from an extracted `slbzt_*_linux_*.tar.gz` archive.)

## macOS

Works on Apple Silicon and Intel Macs. The script detects the CPU (also from a Terminal running under Rosetta),
downloads the matching build and checks its checksum. Run these in **Terminal**; `sudo` asks for your Mac password.

**Install:**
```bash
curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_macos_setup.sh | sudo bash -s -- <SETUP_KEY>
```
The script asks whether to also install SLBZT Proxy (default: No). Files downloaded this way are not blocked by
Gatekeeper, even though they are not signed.

**Check:**
```bash
sudo slbzt status
```

**Update:**
```bash
curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_macos_setup.sh | sudo bash
```

**Uninstall:** the same commands as on [Linux](#linux).

## Optional: SLBZT Proxy

An HTTP/HTTPS proxy that lets machines on the VPN send traffic out through this machine's internet connection, for
example to reach a service that only accepts certain IP addresses. It is **not installed unless you choose it**.
- It listens **only on the machine's VPN address**, never on its local network or the internet.
- It requires a **username and password** (at least 8 characters), chosen during installation.
- The **port** defaults to 3128; the installer checks that it is free.

**Choose it during installation:**
- **Windows:** tick **SLBZT Proxy** on the Components page, then enter the port, username and password.
  Silently, add `/PROXY=1 /PROXYPORT=3128 /PROXYUSER=<user> /PROXYPASS=<password>` to the setup command.
- **Linux / macOS:** answer **y** when asked, then enter the port, username and password. Without prompts (for
  example over SSH automation), put the password in a file and run (use `slbzt_macos_setup.sh` on a Mac):
  ```bash
  curl -fsSL https://github.com/wmsid/trying/raw/main/bin/slbzt_linux_setup.sh | sudo bash -s -- <SETUP_KEY> --proxy --proxy-port 3128 --proxy-user <user> --proxy-password-file /path/to/password.txt
  ```

**Updates** keep an installed proxy with its port and login. To change them, run the installer again and enter new
values (Linux/macOS: add `--proxy-port <port>` and/or `--proxy-user <user> --proxy-password-file <file>`).
To remove only the proxy: untick it in the Windows setup (silently: `/PROXY=0`), or add `--no-proxy` on Linux/macOS.

**Allow access in the dashboard:** add an access policy that allows your server(s) to reach these machines on the
proxy port (TCP 3128 by default). Without it, the VPN blocks the connection.

**Use it from your server:**
```bash
curl -x http://<user>:<password>@<machine VPN IP>:3128 https://example.com
```

---

# For maintainers

## Build

1. Edit `brand.env` (name, display name, `MGMT_URL`, upstream `NETBIRD_VERSION`) and **always raise
   `BUILD_VERSION`** for any change users install (see `CLAUDE.md`).
2. `./scripts/build.sh` (needs Go, git, zip, curl, makensis). Output in `dist/`: `slbzt_windows_setup.exe`,
   `slbzt_linux_setup.sh`, `slbzt_macos_setup.sh`, plus per-OS/CPU `.zip`/`.tar.gz` archives.
   Pushing to `main` makes GitHub Actions build and commit them to `bin/` (what users download);
   pushing a `v*` tag attaches them to a GitHub release.

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

## How the proxy works (`slbzt-proxy`)
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

## Requirements / caveats
- You need a NetBird **management server** (self-hosted) - it issues setup keys. The client is only the peer side.
- Binaries are unsigned. Sign them (Authenticode on Windows; Developer ID + notarization on macOS) or Gatekeeper/SmartScreen will warn. The macOS script clears the quarantine flag, which helps for CLI use only.
- Built with `CGO_ENABLED=0`; cross-compiled, so macOS/Windows runtime behavior was **not** tested here.
- The rebrand patch is regex-based; when bumping `NETBIRD_VERSION`, check the build output for `WARN: leftover brand strings`.

## Windows installer (.exe)
`slbzt_windows_setup.exe` is a real setup program: admin prompt, installs to Program Files, registers the
service (does not modify PATH; run it from the install folder), shows in Add/Remove Programs, includes an uninstaller.
Uninstall: Settings > Apps, or `"%ProgramFiles%\slbzt\uninstall.exe" /S`.
The per-architecture `.zip` files still contain `install.ps1` for manual installs; if PowerShell blocks it, use
`powershell -ExecutionPolicy Bypass -File .\install.ps1`.

## Linux archives
Normally use `slbzt_linux_setup.sh` (see Installation). The per-CPU `*_linux_{amd64,arm64,arm,386}.tar.gz` archives it downloads can
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
