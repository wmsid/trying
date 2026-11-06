#!/usr/bin/env bash
# sudo ./install.sh [SETUP_KEY]
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"
xattr -dr com.apple.quarantine . 2>/dev/null || true   # browser-downloaded archives
source ./brand.env
BIN=/usr/local/bin/$BRAND_NAME
mkdir -p /usr/local/bin
if [ -x "$BIN" ]; then "$BIN" service stop 2>/dev/null || true; "$BIN" service uninstall 2>/dev/null || true; fi
install -m 755 "./$BRAND_NAME" "$BIN"
xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
"$BIN" service install
"$BIN" service start
echo "$BRAND_NAME service installed and running. Connect with: sudo $BRAND_NAME up --setup-key <KEY>"
[ -z "${1:-}" ] || "$BIN" up --setup-key "$1"
