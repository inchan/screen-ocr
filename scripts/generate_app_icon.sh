#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from design/appicon.svg
# Requires: rsvg-convert (brew install librsvg), iconutil (macOS)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SVG="design/appicon.svg"
OUT="Resources/AppIcon.icns"

command -v rsvg-convert >/dev/null || { printf 'FAIL: rsvg-convert not found (brew install librsvg)\n' >&2; exit 1; }
command -v iconutil >/dev/null || { printf 'FAIL: iconutil not found\n' >&2; exit 1; }
[[ -f "$SVG" ]] || { printf 'FAIL: missing %s\n' "$SVG" >&2; exit 1; }

mkdir -p Resources
TMP="$(mktemp -d)"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

gen() { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$ICONSET/$2"; }
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$TMP"
printf 'Generated %s\n' "$OUT"
