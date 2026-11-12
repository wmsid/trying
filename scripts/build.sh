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
    local wdir=amd64; [ "$arch" = arm64 ] && wdir=arm64; [ "$arch" = 386 ] && wdir=x86
    cp "$WORK/wintun/bin/$wdir/wintun.dll" "$out/wintun.dll"
    # stage for the single setup.exe: amd64 / arm64 / win7_amd64 / win7_386
    local v="$arch"; [ "$label" = windows7 ] && v="win7_$arch"
    mkdir -p "$WORK/win/$v"; cp "$out/${BRAND_NAME}.exe" "$out/wintun.dll" "$WORK/win/$v/"
    (cd "$DIST" && zip -qr "$pkg.zip" "$pkg")
  elif [ "$os" = linux ]; then cp "$ROOT"/installers/linux/install.sh "$ROOT"/installers/linux/uninstall.sh "$out/"; chmod +x "$out"/*.sh; tar -C "$DIST" -czf "$DIST/$pkg.tar.gz" "$pkg"
  else cp "$ROOT"/installers/macos/*.sh "$out/"; chmod +x "$out"/*.sh; tar -C "$DIST" -czf "$DIST/$pkg.tar.gz" "$pkg"; fi
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
# ONE Windows setup.exe for all PCs (picks the build at run time; installs or updates)
if [ -d "$WORK/win/amd64" ] && [ -d "$WORK/win/arm64" ]; then
NSIS_WIN7=(); [ -d "$WORK/win/win7_amd64" ] && [ -d "$WORK/win/win7_386" ] && NSIS_WIN7=(-DHAVE_WIN7)
makensis -V1 -DBRAND="$BRAND_NAME" -DDISPLAY="$BRAND_DISPLAY" -DVERSION="$BUILD_VERSION" -DWINDIR="$WORK/win" "${NSIS_WIN7[@]}" \
  -DOUT="$DIST/${BRAND_NAME}_windows_setup.exe" "$ROOT/installers/windows/installer.nsi"
fi

# ONE Linux script for all CPUs (downloads the matching build; installs or updates)
[ ! -f "$DIST/${BRAND_NAME}_${BUILD_VERSION}_linux_amd64.tar.gz" ] || {
sed -e "s#@BRAND@#${BRAND_NAME}#g" -e "s#@DISPLAY@#${BRAND_DISPLAY}#g" -e "s#@VERSION@#${BUILD_VERSION}#g" \
    -e "s#@BASE_URL@#${DOWNLOAD_URL}#g" "$ROOT/installers/linux/setup.sh" > "$DIST/${BRAND_NAME}_linux_setup.sh"
chmod +x "$DIST/${BRAND_NAME}_linux_setup.sh"; }
ls -la "$DIST"
