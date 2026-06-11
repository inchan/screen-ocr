#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH="${1:-dist/Screen OCR.app}"
RESOURCES_PATH="$APP_PATH/Contents/Resources"
PYTHON_BIN="$RESOURCES_PATH/python-runtime/bin/python"
PYTHON_FRAMEWORK="$APP_PATH/Contents/Frameworks/Python.framework"
SIDECAR_PATH="$RESOURCES_PATH/sidecar/screen_ocr_sidecar"
FIXTURE_PATH="$RESOURCES_PATH/fixtures/ocr/mixed-ko-en-simple.png"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -d "$APP_PATH" ]] || fail "missing app bundle: $APP_PATH"
[[ -x "$PYTHON_BIN" ]] || fail "missing embedded Python runtime: $PYTHON_BIN"
[[ -d "$PYTHON_FRAMEWORK" ]] || fail "missing embedded Python framework: $PYTHON_FRAMEWORK"
[[ -d "$SIDECAR_PATH" ]] || fail "missing embedded OCR sidecar: $SIDECAR_PATH"
[[ -f "$FIXTURE_PATH" ]] || fail "missing embedded OCR fixture: $FIXTURE_PATH"

if grep -E -q '/opt/homebrew|/Users/runner|/Library/Frameworks/Python\.framework' "$PYTHON_BIN"; then
  fail "embedded Python wrapper must not point at a build-machine Python"
fi

PYTHONPATH="$RESOURCES_PATH/sidecar" "$PYTHON_BIN" - <<'PY'
import importlib.util
import sys

for module_name in ("paddleocr", "paddle", "screen_ocr_sidecar.ocr"):
    if importlib.util.find_spec(module_name) is None:
        raise SystemExit(f"missing module: {module_name}")

print(f"PASS: embedded OCR environment wrapper uses Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro} and has OCR modules")
PY

framework_python="$(
  find "$PYTHON_FRAMEWORK/Versions" -path '*/bin/python3.*' -type f -perm -111 -print -quit 2>/dev/null || true
)"
[[ -n "$framework_python" ]] || fail "missing executable inside embedded Python framework"
linked_libraries="$(otool -L "$framework_python" 2>&1)"
if printf '%s\n' "$linked_libraries" | grep -E -q '/opt/homebrew|/Users/runner|/Library/Frameworks/Python\.framework'; then
  printf '%s\n' "$linked_libraries" >&2
  fail "embedded Python executable links to a build-machine Python framework"
fi

printf 'PASS: verified embedded runtime bundle: %s\n' "$APP_PATH"
