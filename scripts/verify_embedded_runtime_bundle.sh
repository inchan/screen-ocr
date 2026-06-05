#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH="${1:-dist/Screen OCR.app}"
RESOURCES_PATH="$APP_PATH/Contents/Resources"
PYTHON_BIN="$RESOURCES_PATH/python-runtime/bin/python"
SIDECAR_PATH="$RESOURCES_PATH/sidecar/screen_ocr_sidecar"
FIXTURE_PATH="$RESOURCES_PATH/fixtures/ocr/mixed-ko-en-simple.png"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ -d "$APP_PATH" ]] || fail "missing app bundle: $APP_PATH"
[[ -x "$PYTHON_BIN" ]] || fail "missing embedded Python runtime: $PYTHON_BIN"
[[ -d "$SIDECAR_PATH" ]] || fail "missing embedded OCR sidecar: $SIDECAR_PATH"
[[ -f "$FIXTURE_PATH" ]] || fail "missing embedded OCR fixture: $FIXTURE_PATH"

PYTHONPATH="$RESOURCES_PATH/sidecar" "$PYTHON_BIN" - <<'PY'
import importlib.util
import sys

for module_name in ("paddleocr", "paddle", "screen_ocr_sidecar.ocr"):
    if importlib.util.find_spec(module_name) is None:
        raise SystemExit(f"missing module: {module_name}")

print(f"PASS: embedded OCR environment wrapper uses Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro} and has OCR modules")
PY

printf 'PASS: verified embedded runtime bundle: %s\n' "$APP_PATH"
