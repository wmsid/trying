#!/usr/bin/env bash
# Builds branded headless clients for Windows + macOS into dist/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/brand.env"
WORK="${WORK:-$ROOT/.work}"; DIST="$ROOT/dist"
rm -rf "$WORK" "$DIST"; mkdir -p "$WORK" "$DIST"
git clone -q --depth 1 --branch "$NETBIRD_VERSION" https://github.com/netbirdio/netbird.git "$WORK/src"
"$ROOT/scripts/rebrand.sh" "$WORK/src"
# WireGuard's Wintun driver DLL (signed by WireGuard LLC); the Windows client loads it from next to the exe.
WINTUN_SHA256=07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51
curl -fsSL -o "$WORK/wintun.zip" https://www.wintun.net/builds/wintun-0.14.1.zip
echo "$WINTUN_SHA256  $WORK/wintun.zip" | sha256sum -c - >/dev/null
unzip -q "$WORK/wintun.zip" -d "$WORK"
cd "$WORK/src"
export GOTOOLCHAIN=auto CGO_ENABLED=0
LDF="-s -w -X github.com/netbirdio/netbird/version.version=${BUILD_VERSION}"
pack() { # pack <os> <arch> <label> <gobin>
  local os=$1 arch=$2 label=$3 gobin=$4 ext=""; [ "$os" = windows ] && ext=".exe"
  local pkg="${BRAND_NAME}_${BUILD_VERSION}_${label}_${arch}"; local out="$DIST/$pkg"; mkdir -p "$out"
  echo ">> $label/$arch"
  GOOS=$os GOARCH=$arch "$gobin" build -ldflags "$LDF" -o "$out/${BRAND_NAME}${ext}" ./client
  for bad in 'pkgs.netbird.io' 'github.com/netbirdio/netbird/releases' 'ingest.netbird.io' 'publickeys.netbird.io' \
             'NetbirdDebugTriggerEvent' 'f2f29e61-d91f-4d76-8151-119b20c4bdeb' 'upload.debug.netbird.io'; do
    if grep -aqF "$bad" "$out/${BRAND_NAME}${ext}"; then echo "FATAL: binary still contains upstream string: $bad"; exit 1; fi
  done
  cp "$ROOT/brand.env" "$out/brand.env"
  if [ "$os" = windows ]; then
    cp "$ROOT"/installers/windows/*.ps1 "$out/"
    local narch=x64 wdir=amd64
    [ "$arch" = arm64 ] && { narch=arm64; wdir=arm64; }
    [ "$arch" = 386 ] && { narch=x86; wdir=x86; }
    cp "$WORK/wintun/bin/$wdir/wintun.dll" "$out/wintun.dll"
    makensis -V1 -DBRAND="$BRAND_NAME" -DDISPLAY="$BRAND_DISPLAY" -DVERSION="$BUILD_VERSION" -DARCH="$narch" \
      -DEXE="$out/${BRAND_NAME}.exe" -DWINTUN="$out/wintun.dll" -DOUT="$DIST/${pkg}_setup.exe" "$ROOT/installers/windows/installer.nsi"
    (cd "$DIST" && zip -qr "$pkg.zip" "$pkg")
  else cp "$ROOT"/installers/$([ "$os" = linux ] && echo linux || echo macos)/*.sh "$out/"; chmod +x "$out"/*.sh; tar -C "$DIST" -czf "$DIST/$pkg.tar.gz" "$pkg"; fi
  rm -rf "$out"
}
for t in ${TARGETS:-windows/amd64 windows/arm64 darwin/amd64 darwin/arm64 linux/amd64 linux/arm64 linux/arm linux/386}; do pack "${t%/*}" "${t#*/}" "${t%/*}" go; done

# Windows 7/8/8.1: needs a community-patched Go toolchain (official Go dropped Win7 in 1.21).
# Built from source at a pinned tag; used ONLY for these two archives.
if [ -n "${WIN7_GO_TAG:-}" ] && [ "${SKIP_WIN7:-0}" != 1 ]; then
  git clone -q --depth 1 --branch "$WIN7_GO_TAG" https://github.com/thongtech/go-legacy-win7.git "$WORK/go7"
  (cd "$WORK/go7/src" && GOROOT_BOOTSTRAP="$(go env GOROOT)" ./make.bash >/dev/null)
  G7="$WORK/go7/bin/go"
  for a in amd64 386; do GOROOT="$WORK/go7" GOTOOLCHAIN=local pack windows "$a" windows7 "$G7"; done
fi
ls -la "$DIST"
