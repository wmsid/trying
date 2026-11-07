#!/usr/bin/env bash
# Usage: rebrand.sh <netbird-source-dir>   (reads ../brand.env)
# Rewrites user-visible names, paths, service/pipe names and the default
# management URL. The Go module path is left alone (never shown to users).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/brand.env"
SRC="${1:?netbird source dir}"
cd "$SRC"

export NAME="$BRAND_NAME" DISPLAY_NAME="$BRAND_DISPLAY"
mapfile -t FILES < <(find client util shared -name '*.go' \
  ! -name '*_test.go' ! -path 'client/ui/*' ! -path 'client/ios/*' \
  ! -path 'client/android/*' ! -path 'client/wasm/*' ! -path 'client/ssh/detection/*' \
  ! -path 'client/internal/anonymize/*' ! -path 'client/anonymize/*')

# Only touch lines holding a string/comment; skip import lines and netbird.io hosts.
perl -i -pe '
  next if /netbirdio|^\s*"[^"]*\/[^"]*"\s*$/ && /github\.com/;
  next unless /["`\/]/;
  s{(?<![\w])netbird(?![\w])(?!\.io)}{$ENV{NAME}}g;
  s{(?<=\\n)netbird(?=\s)}{$ENV{NAME}}g;
  s{(?<![\w])Net[Bb]ird(?![\w])(?!\.io)}{$ENV{DISPLAY_NAME}}g;
' "${FILES[@]}"

# `up` prints the received DNS domain and assigned IP after "Connected"
cp "$ROOT/patches/up_summary.go" client/cmd/up_summary.go
python3 - <<'PY'
p = "client/cmd/up.go"
s = open(p).read()
old = '\tcmd.Println("Connected")\n\treturn nil\n}\n\nfunc doDaemonUp'
assert s.count(old) == 1, "up.go patch anchor not found"
s = s.replace(old, '\tcmd.Println("Connected")\n\tprintConnectionSummary(ctx, cmd, client)\n\treturn nil\n}\n\nfunc doDaemonUp')
open(p, "w").write(s)
PY

# Default management URL; remove every remaining upstream endpoint.
sed -i "s#https://api.netbird.io:443#${MGMT_URL}#" client/internal/profilemanager/config.go
sed -i 's#https://app.netbird.io:443#'"${MGMT_URL}"'#' client/internal/profilemanager/config.go
sed -i 's#https://ingest.netbird.io[^"]*#http://127.0.0.1:1#' \
  client/internal/metrics/push.go client/internal/metrics/env.go
sed -i 's#https://publickeys.netbird.io[^"]*#http://127.0.0.1:1#' client/internal/updater/installer/repourl_prod.go
grep -rl 'https://docs.netbird.io' client --include=*.go | xargs -r sed -i 's#https://docs.netbird.io/[^" ]*#'"${MGMT_URL}"'#g'

sed -i 's/non-netbird\.io domains/non-internal domains/' client/cmd/root.go

# Coexistence: separate WireGuard interface name and listen port
sed -i "s#\"wt0\"#\"${WG_IFACE}\"#" client/iface/configurer/name.go
sed -i "s#\"utun100\"#\"${WG_IFACE_DARWIN}\"#" client/iface/configurer/name_darwin.go
sed -i "s#DefaultWgPort *= 51820#DefaultWgPort = ${WG_PORT}#" client/iface/iface.go
# Windows adapter GUID must differ from stock NetBird, or both cannot exist side by side
sed -i "s#{f2f29e61-d91f-4d76-8151-119b20c4bdeb}#${WG_GUID_WINDOWS}#" client/iface/device/device_windows.go
grep -q "$WG_GUID_WINDOWS" client/iface/device/device_windows.go || { echo "guid patch failed"; exit 1; }
grep -q "$WG_IFACE" client/iface/configurer/name.go && grep -q "$WG_PORT" client/iface/iface.go || { echo "coexistence patch failed"; exit 1; }

# Leave nothing behind
LEFT=$(grep -rniE 'netbird' client/cmd/root.go client/cmd/service.go client/cmd/up.go client/cmd/status.go \
        | grep -vE 'github.com/netbirdio|migrateToNetbird' || true)
[ -z "$LEFT" ] || { echo "WARN: leftover brand strings:"; echo "$LEFT"; }
echo "rebrand ok"
