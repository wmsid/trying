#!/usr/bin/env bash
# sudo ./install.sh [SETUP_KEY]
# Installs, or updates in place, and connects.
#   - fresh machine: connects with SETUP_KEY (or later: sudo <name> up --setup-key <KEY>)
#   - already set up: keeps the config, reconnects as the same peer; no key needed (a given one is ignored)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"
xattr -dr com.apple.quarantine . 2>/dev/null || true   # browser-downloaded archives
source ./brand.env
KEY="${1:-}"
BIN=/usr/local/bin/$BRAND_NAME
CONF_DIR="${NB_STATE_DIR:-/var/lib/$BRAND_NAME}"

UPDATE=0
if [ -f "$CONF_DIR/default.json" ] || [ -f "/etc/$BRAND_NAME/config.json" ]; then UPDATE=1; fi

OLD=""
if [ -x "$BIN" ]; then
  OLD="$("$BIN" version 2>/dev/null || true)"
  "$BIN" service stop 2>/dev/null || true
  "$BIN" service uninstall 2>/dev/null || true
fi
mkdir -p /usr/local/bin
install -m 755 "./$BRAND_NAME" "$BIN"
xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
"$BIN" service install
"$BIN" service start

# wait (up to ~15 s) until the service answers, so `up` does not race the service start
for _ in $(seq 15); do "$BIN" status >/dev/null 2>&1 && break; sleep 1; done

NEW="$("$BIN" version 2>/dev/null || true)"
if [ "$UPDATE" = 1 ]; then
  echo "$BRAND_DISPLAY updated${OLD:+ from $OLD} to $NEW (settings kept)."
  # The service reconnects by itself with the saved config. Do NOT run `up` here: if this
  # machine needed a new login, `up` would wait for an interactive login and hang the update.
  for _ in $(seq 30); do
    if "$BIN" status 2>/dev/null | grep -qE 'Daemon status: (NeedsLogin|LoginFailed|SessionExpired)'; then
      echo "This machine must log in again (removed from the dashboard or login expired)."
      echo "Connect with: sudo $BRAND_NAME up --setup-key <KEY>"
      exit 2
    fi
    IP="$("$BIN" status --ipv4 2>/dev/null | tr -d '[:space:]' || true)"
    if echo "$IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then echo "Connected: $IP"; break; fi
    sleep 1
  done
  [ -n "${IP:-}" ] && echo "$IP" | grep -qE '^[0-9.]+$' || echo "Still connecting in the background; check with: sudo $BRAND_NAME status"
elif [ -n "$KEY" ]; then
  echo "$BRAND_DISPLAY $NEW installed."
  "$BIN" up --setup-key "$KEY"
else
  echo "$BRAND_DISPLAY $NEW installed. Connect with: sudo $BRAND_NAME up --setup-key <KEY>"
  exit 0
fi
"$BIN" status
