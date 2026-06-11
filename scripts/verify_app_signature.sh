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

PYTHON_FRAMEWORK="$APP_PATH/Contents/Frameworks/Python.framework"
if [[ -d "$PYTHON_FRAMEWORK" ]]; then
  verify_output="$(codesign --verify --strict --verbose=2 "$APP_PATH" 2>&1)" || {
    printf '%s\n' "$verify_output" >&2
    fail "codesign strict app verification failed"
  }
  verify_output="$(codesign --verify --deep --verbose=2 "$APP_PATH" 2>&1)" || {
    printf '%s\n' "$verify_output" >&2
    fail "codesign deep app verification failed"
  }
  framework_python="$(
    find "$PYTHON_FRAMEWORK/Versions" -path '*/bin/python3.*' -type f -perm -111 -print -quit 2>/dev/null || true
  )"
  [[ -n "$framework_python" ]] || fail "missing signed Python executable in embedded framework"
  verify_output="$(codesign --verify --strict --verbose=2 "$framework_python" 2>&1)" || {
    printf '%s\n' "$verify_output" >&2
    fail "codesign strict Python executable verification failed"
  }
else
  verify_output="$(codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1)" || {
    printf '%s\n' "$verify_output" >&2
    fail "codesign verification failed"
  }
fi

details="$(codesign -dvvv "$APP_PATH" 2>&1)"
printf '%s\n' "$details" | grep -q 'Signature=adhoc' || fail "expected ad-hoc signature for local development bundle"
printf '%s\n' "$details" | grep -q 'Sealed Resources' || fail "expected sealed bundle resources"

if [[ -d "$PYTHON_FRAMEWORK" ]]; then
  framework_python_details="$(codesign -dvvv "$framework_python" 2>&1)"
  printf '%s\n' "$framework_python_details" | grep -q 'Signature=adhoc' || fail "expected ad-hoc signature for embedded Python"
fi

printf 'PASS: verified app signature: %s\n' "$APP_PATH"
