#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH="${1:-dist/Screen OCR.app}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -d "$APP_PATH" ]] || fail "missing app bundle: $APP_PATH"

verify_output="$(codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1)" || {
  printf '%s\n' "$verify_output" >&2
  fail "codesign verification failed"
}

details="$(codesign -dvvv "$APP_PATH" 2>&1)"
printf '%s\n' "$details" | grep -q 'Signature=adhoc' || fail "expected ad-hoc signature for local development bundle"
printf '%s\n' "$details" | grep -q 'Sealed Resources' || fail "expected sealed bundle resources"

printf 'PASS: verified app signature: %s\n' "$APP_PATH"
