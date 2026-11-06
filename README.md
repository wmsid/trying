# Headless, unbranded NetBird client (Windows + macOS)

A build pipeline that takes upstream NetBird, strips the branding, bakes in **your**
management server, and ships a UI-less client that runs as a system service.

End-user experience:

```
# Windows (admin PowerShell)             # macOS
.\install.ps1                            sudo ./install.sh
vpnagent up --setup-key abcd             sudo vpnagent up --setup-key abcd
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

## Requirements / caveats
- You need a NetBird **management server** (self-hosted) - it issues setup keys. The client is only the peer side.
- Binaries are unsigned. Sign them (Authenticode on Windows; Developer ID + notarization on macOS) or Gatekeeper/SmartScreen will warn. The macOS script clears the quarantine flag, which helps for CLI use only.
- Built with `CGO_ENABLED=0`; cross-compiled, so macOS/Windows runtime behavior was **not** tested here.
- The rebrand patch is regex-based; when bumping `NETBIRD_VERSION`, check the build output for `WARN: leftover brand strings`.
