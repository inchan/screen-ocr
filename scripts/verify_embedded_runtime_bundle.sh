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

reject_build_machine_python_link() {
  local binary="$1"
  local linked_libraries

  linked_libraries="$(otool -L "$binary" 2>&1)"
  if printf '%s\n' "$linked_libraries" | sed '1d' | grep -E -q '/opt/homebrew|/Users/runner|/Library/Frameworks/Python\.framework'; then
    printf '%s\n' "$linked_libraries" >&2
    fail "embedded Python framework binary links to a build-machine Python framework: $binary"
  fi
}

framework_python_count=0
for framework_binary in \
  "$PYTHON_FRAMEWORK"/Versions/*/bin/python3.* \
  "$PYTHON_FRAMEWORK"/Versions/*/Resources/Python.app/Contents/MacOS/Python \
  "$PYTHON_FRAMEWORK"/Versions/*/Python
do
  [[ -f "$framework_binary" ]] || continue
  reject_build_machine_python_link "$framework_binary"
  case "$framework_binary" in
    */bin/python3.*) framework_python_count=$((framework_python_count + 1)) ;;
  esac
done
[[ "$framework_python_count" -gt 0 ]] || fail "missing executable inside embedded Python framework"

PYTHONPATH="$RESOURCES_PATH/sidecar" "$PYTHON_BIN" - <<'PY'
import importlib.util
import sys

for module_name in ("paddleocr", "paddle", "screen_ocr_sidecar.ocr"):
    if importlib.util.find_spec(module_name) is None:
        raise SystemExit(f"missing module: {module_name}")

print(f"PASS: embedded OCR environment wrapper uses Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro} and has OCR modules")
PY

printf 'PASS: verified embedded runtime bundle: %s\n' "$APP_PATH"
