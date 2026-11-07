#!/usr/bin/env bash
# Builds branded headless clients for Windows + macOS into dist/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/brand.env"
WORK="${WORK:-$ROOT/.work}"; DIST="$ROOT/dist"
rm -rf "$WORK" "$DIST"; mkdir -p "$WORK" "$DIST"
git clone -q --depth 1 --branch "$NETBIRD_VERSION" https://github.com/netbirdio/netbird.git "$WORK/src"
"$ROOT/scripts/rebrand.sh" "$WORK/src"
cd "$WORK/src"
export GOTOOLCHAIN=auto CGO_ENABLED=0
LDF="-s -w -X github.com/netbirdio/netbird/version.version=${BUILD_VERSION}"
pack() { # pack <os> <arch> <label> <gobin>
  local os=$1 arch=$2 label=$3 gobin=$4 ext=""; [ "$os" = windows ] && ext=".exe"
  local pkg="${BRAND_NAME}_${BUILD_VERSION}_${label}_${arch}"; local out="$DIST/$pkg"; mkdir -p "$out"
  echo ">> $label/$arch"
  GOOS=$os GOARCH=$arch "$gobin" build -ldflags "$LDF" -o "$out/${BRAND_NAME}${ext}" ./client
  cp "$ROOT/brand.env" "$out/brand.env"
  if [ "$os" = windows ]; then
    cp "$ROOT"/installers/windows/*.ps1 "$out/"
    local narch=x64; [ "$arch" = arm64 ] && narch=arm64; [ "$arch" = 386 ] && narch=x86
    makensis -V1 -DBRAND="$BRAND_NAME" -DDISPLAY="$BRAND_DISPLAY" -DVERSION="$BUILD_VERSION" -DARCH="$narch" \
      -DEXE="$out/${BRAND_NAME}.exe" -DOUT="$DIST/${pkg}_setup.exe" "$ROOT/installers/windows/installer.nsi"
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
