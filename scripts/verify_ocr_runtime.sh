#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${SCREEN_OCR_VENV:-$ROOT/.venv-ocr}"
PYTHON_BIN="${SCREEN_OCR_RUNTIME_PYTHON:-$VENV_DIR/bin/python}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  printf 'FAIL: OCR runtime Python not found: %s\n' "$PYTHON_BIN" >&2
  printf 'Run scripts/setup_ocr_env.sh first.\n' >&2
  exit 1
fi

PYTHONPATH="$ROOT/sidecar" "$PYTHON_BIN" - <<'PY'
import importlib.metadata
import paddle

print(f"paddlepaddle={importlib.metadata.version('paddlepaddle')}")
print(f"paddleocr={importlib.metadata.version('paddleocr')}")
paddle.utils.run_check()

from screen_ocr_sidecar.ocr import create_default_ocr

ocr = create_default_ocr()
print(f"PASS: created PaddleOCR instance: {type(ocr).__name__}")
PY

