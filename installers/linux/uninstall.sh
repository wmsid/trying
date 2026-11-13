#!/usr/bin/env bash
# sudo ./uninstall.sh   Removes the service, the program and its config/logs
# (after this, installing again registers the machine as a new peer and needs a setup key).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"; source ./brand.env
BIN=/usr/local/bin/$BRAND_NAME
[ ! -x "$BIN" ] || { "$BIN" down 2>/dev/null || true; "$BIN" service stop || true; "$BIN" service uninstall || true; rm -f "$BIN"; }
rm -rf "/var/lib/$BRAND_NAME" "/etc/$BRAND_NAME" "/var/log/$BRAND_NAME" "/var/run/$BRAND_NAME.sock"
echo "$BRAND_DISPLAY removed."
