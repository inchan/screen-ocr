#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH="${1:-dist/Screen OCR.app}"
SIGN_IDENTITY="${SCREEN_OCR_CODESIGN_IDENTITY:--}"

[[ -d "$APP_PATH" ]] || {
  printf 'FAIL: missing app bundle: %s\n' "$APP_PATH" >&2
  exit 1
}

codesign \
  --force \
  --deep \
  --sign "$SIGN_IDENTITY" \
  --timestamp=none \
  "$APP_PATH"

printf 'Signed %s with identity %s\n' "$APP_PATH" "$SIGN_IDENTITY"
