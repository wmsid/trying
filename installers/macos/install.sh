#!/usr/bin/env bash
# Installs, or updates in place, the VPN client and (optionally) the proxy. Same file on Linux and macOS.
#
#   sudo ./install.sh [SETUP_KEY] [options]          (old form `install.sh [SETUP_KEY]` still works)
#
# VPN client (always installed/updated):
#   - SETUP_KEY given: always used to connect (fresh machine, or one that must log in again)
#   - no key, already set up: keeps the config and reconnects as the same peer
#   - no key, fresh machine: installs only (later: sudo <name> up --setup-key <KEY>)
#   --setup-key <KEY>            same as the positional SETUP_KEY
#
# Proxy (HTTP/HTTPS, listens only on this machine's VPN IP; NOT installed unless chosen):
#   --proxy                      install/update it         --no-proxy   remove it if installed
#   --proxy-port <port>          default: current port, else 3128 (must be free)
#   --proxy-user <user>          login (required for a new proxy; optional on update = keep current)
#   --proxy-password-file <f>    password (min 8 chars); or env PROXY_PASSWORD
#   Without --proxy/--no-proxy: an installed proxy is updated (keeping port and login); otherwise, when run
#   in a terminal, you are asked (default: No); when not in a terminal, the proxy is left out.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"
[ "$(uname -s)" != Darwin ] || xattr -dr com.apple.quarantine . 2>/dev/null || true   # browser downloads
source ./brand.env

KEY=""; PROXY=""; P_PORT=""; P_USER=""; P_PASS="${PROXY_PASSWORD:-}"
die() { echo "ERROR: $*" >&2; exit 3; }
while [ $# -gt 0 ]; do
  case "$1" in
    --setup-key)            KEY="${2:?--setup-key needs a value}"; shift 2 ;;
    --proxy)                PROXY=1; shift ;;
    --no-proxy)             PROXY=0; shift ;;
    --proxy-port)           P_PORT="${2:?--proxy-port needs a value}"; shift 2 ;;
    --proxy-user)           P_USER="${2:?--proxy-user needs a value}"; shift 2 ;;
    --proxy-password-file)  P_PASS="$(head -n1 "${2:?--proxy-password-file needs a file}" | tr -d '\r\n')"; shift 2 ;;
    -h|--help)              sed -n '2,20p' "$0"; exit 0 ;;
    -*)                     die "unknown option: $1" ;;
    *)                      [ -z "$KEY" ] && KEY="$1" || die "unexpected argument: $1"; shift ;;
  esac
done

BIN=/usr/local/bin/$BRAND_NAME
PNAME=$BRAND_NAME-proxy
PBIN=/usr/local/bin/$PNAME
NEWP="./$PNAME"
CONF_DIR="${NB_STATE_DIR:-/var/lib/$BRAND_NAME}"

UPDATE=0
if [ -f "$CONF_DIR/default.json" ] || [ -f "/etc/$BRAND_NAME/config.json" ]; then UPDATE=1; fi
P_INSTALLED=0; [ -x "$PBIN" ] && P_INSTALLED=1

# terminal for questions (works under `curl ... | sudo bash` too); none = non-interactive defaults
TTY=0; if { exec 3</dev/tty; } 2>/dev/null; then TTY=1; fi
ask() { # ask <prompt> <default>  -> REPLY
  local a=""; printf '%s' "$1" >&2
  read -r -t 120 -u 3 a || a=""
  REPLY="${a:-$2}"
}

# ---------- decide and validate everything BEFORE changing the system ----------
if [ -z "$PROXY" ]; then
  if [ "$P_INSTALLED" = 1 ]; then PROXY=1
  elif [ "$TTY" = 1 ] && [ -x "$NEWP" ]; then
    ask "Also install $BRAND_DISPLAY Proxy (HTTP/HTTPS proxy on this machine's VPN IP)? [y/N] " n
    case "$REPLY" in [yY]*) PROXY=1 ;; *) PROXY=0 ;; esac
  else PROXY=0; fi
fi

if [ "$PROXY" = 1 ]; then
  [ -x "$NEWP" ] || die "this package has no $PNAME"
  CUR_PORT="$("$NEWP" get-port 2>/dev/null || echo 3128)"
  HAS_AUTH=0; CUR_USER="$("$NEWP" has-auth 2>/dev/null)" && HAS_AUTH=1 || CUR_USER=""
  # port: must be free (the installed proxy's own current port counts as free)
  port_ok() {
    if [ "$P_INSTALLED" = 1 ] && [ "$1" = "$CUR_PORT" ]; then return 0; fi
    "$NEWP" check-port "$1" >/dev/null 2>&1
  }
  if [ -z "$P_PORT" ] && [ "$TTY" = 1 ]; then
    while :; do
      ask "Proxy port [$CUR_PORT]: " "$CUR_PORT"; P_PORT="$REPLY"
      case "$P_PORT" in ''|*[!0-9]*) echo "  not a number" >&2; continue ;; esac
      { [ "$P_PORT" -ge 1 ] && [ "$P_PORT" -le 65535 ]; } || { echo "  use 1-65535" >&2; continue; }
      port_ok "$P_PORT" && break
      echo "  port $P_PORT is already in use, choose another" >&2
    done
  fi
  P_PORT="${P_PORT:-$CUR_PORT}"
  case "$P_PORT" in ''|*[!0-9]*) die "invalid proxy port: $P_PORT" ;; esac
  { [ "$P_PORT" -ge 1 ] && [ "$P_PORT" -le 65535 ]; } || die "invalid proxy port: $P_PORT (use 1-65535)"
  port_ok "$P_PORT" || die "proxy port $P_PORT is already in use; choose another with --proxy-port"

  # login: required for a new proxy; on update optional (empty = keep current)
  NEED_AUTH=1; [ "$HAS_AUTH" = 1 ] && [ -z "$P_USER" ] && [ -z "$P_PASS" ] && NEED_AUTH=0
  if [ "$HAS_AUTH" = 1 ] && [ "$TTY" = 1 ] && [ -z "$P_USER" ] && [ -z "$P_PASS" ]; then
    ask "Proxy username [$CUR_USER] (Enter keeps the current login): " ""
    [ -n "$REPLY" ] && { P_USER="$REPLY"; NEED_AUTH=1; }
  fi
  if [ "$NEED_AUTH" = 1 ]; then
    if [ -z "$P_USER" ]; then
      [ "$TTY" = 1 ] || die "the proxy needs a login: --proxy-user <user> and --proxy-password-file <file> (or PROXY_PASSWORD)"
      while [ -z "$P_USER" ]; do ask "Proxy username: " ""; P_USER="$REPLY"; done
    fi
    case "$P_USER" in *[[:space:]:]*) die "proxy username must not contain spaces or ':'" ;; esac
    if [ -z "$P_PASS" ]; then
      [ "$TTY" = 1 ] || die "the proxy needs a password: --proxy-password-file <file> (or PROXY_PASSWORD)"
      while :; do
        printf 'Proxy password (min 8 characters): ' >&2; read -rs -u 3 P_PASS; echo >&2
        printf 'Repeat password: ' >&2; read -rs -u 3 P2; echo >&2
        [ "$P_PASS" = "$P2" ] || { echo "  passwords differ" >&2; continue; }
        [ "${#P_PASS}" -ge 8 ] && break
        echo "  too short" >&2
      done
    fi
    [ "${#P_PASS}" -ge 8 ] || die "proxy password must be at least 8 characters"
  fi
fi

# ---------- VPN client ----------
OLD=""
if [ -x "$BIN" ]; then
  OLD="$("$BIN" version 2>/dev/null || true)"
  "$BIN" service stop 2>/dev/null || true
  "$BIN" service uninstall 2>/dev/null || true
fi
mkdir -p /usr/local/bin
install -m 755 "./$BRAND_NAME" "$BIN"
[ "$(uname -s)" != Darwin ] || xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
"$BIN" service install
"$BIN" service start

# ---------- proxy ----------
if [ "$P_INSTALLED" = 1 ]; then
  "$PBIN" service stop 2>/dev/null || true
  "$PBIN" service uninstall 2>/dev/null || true
fi
if [ "$PROXY" = 1 ]; then
  install -m 755 "$NEWP" "$PBIN"
  [ "$(uname -s)" != Darwin ] || xattr -d com.apple.quarantine "$PBIN" 2>/dev/null || true
  "$PBIN" set-port "$P_PORT" --no-check >/dev/null
  if [ "${NEED_AUTH:-0}" = 1 ]; then printf '%s\n' "$P_PASS" | "$PBIN" set-auth "$P_USER" --password-stdin >/dev/null; fi
  "$PBIN" service install >/dev/null
  "$PBIN" service start >/dev/null
  echo "$BRAND_DISPLAY Proxy $("$PBIN" version) on port $P_PORT (user $("$PBIN" has-auth)); listens on the VPN IP once connected."
elif [ "$P_INSTALLED" = 1 ]; then
  rm -f "$PBIN"; rm -rf "/var/lib/$PNAME"
  echo "$BRAND_DISPLAY Proxy removed."
fi

# wait (up to ~15 s) until the client service answers, so `up` does not race the service start
for _ in $(seq 15); do "$BIN" status >/dev/null 2>&1 && break; sleep 1; done

NEW="$("$BIN" version 2>/dev/null || true)"
if [ -n "$KEY" ]; then
  if [ "$UPDATE" = 1 ]; then echo "$BRAND_DISPLAY updated${OLD:+ from $OLD} to $NEW (settings kept)."
  else echo "$BRAND_DISPLAY $NEW installed."; fi
  # with a setup key `up` never waits for an interactive login
  "$BIN" up --setup-key "$KEY"
elif [ "$UPDATE" = 1 ]; then
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
else
  echo "$BRAND_DISPLAY $NEW installed. Connect with: sudo $BRAND_NAME up --setup-key <KEY>"
  exit 0
fi
"$BIN" status
