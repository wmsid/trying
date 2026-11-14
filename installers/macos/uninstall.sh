#!/usr/bin/env bash
# sudo ./uninstall.sh   Removes the VPN client and the proxy (services, programs, config, logs).
# After this, installing again registers the machine as a new peer and needs a setup key.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"; source ./brand.env
BIN=/usr/local/bin/$BRAND_NAME
PBIN=/usr/local/bin/$BRAND_NAME-proxy
[ ! -x "$PBIN" ] || { "$PBIN" service stop 2>/dev/null || true; "$PBIN" service uninstall 2>/dev/null || true; rm -f "$PBIN"; }
rm -rf "/var/lib/$BRAND_NAME-proxy"
[ ! -x "$BIN" ] || { "$BIN" down 2>/dev/null || true; "$BIN" service stop || true; "$BIN" service uninstall || true; rm -f "$BIN"; }
rm -rf "/var/lib/$BRAND_NAME" "/etc/$BRAND_NAME" "/var/log/$BRAND_NAME" "/var/run/$BRAND_NAME.sock"
echo "$BRAND_DISPLAY removed."
