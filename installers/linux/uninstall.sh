#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"; source ./brand.env
BIN=/usr/local/bin/$BRAND_NAME
[ ! -x "$BIN" ] || { "$BIN" down 2>/dev/null || true; "$BIN" service stop || true; "$BIN" service uninstall || true; rm -f "$BIN"; }
