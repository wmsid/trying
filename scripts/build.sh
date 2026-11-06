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
for t in ${TARGETS:-windows/amd64 windows/arm64 darwin/amd64 darwin/arm64}; do
  os=${t%/*}; arch=${t#*/}; ext=""; [ "$os" = windows ] && ext=".exe"
  pkg="${BRAND_NAME}_${BUILD_VERSION}_${os}_${arch}"; out="$DIST/$pkg"; mkdir -p "$out"
  echo ">> $t"
  GOOS=$os GOARCH=$arch go build -ldflags "$LDF" -o "$out/${BRAND_NAME}${ext}" ./client
  cp "$ROOT/brand.env" "$out/brand.env"
  if [ "$os" = windows ]; then cp "$ROOT"/installers/windows/*.ps1 "$out/"; (cd "$DIST" && zip -qr "$pkg.zip" "$pkg")
  else cp "$ROOT"/installers/macos/*.sh "$out/"; chmod +x "$out"/*.sh; tar -C "$DIST" -czf "$DIST/$pkg.tar.gz" "$pkg"; fi
  rm -rf "$out"
done
ls -la "$DIST"
