#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${SCREEN_OCR_PYTHON:-}" ]]; then
  PYTHON_BIN="$SCREEN_OCR_PYTHON"
elif [[ -x "$ROOT/.venv-ocr/bin/python" ]]; then
  PYTHON_BIN="$ROOT/.venv-ocr/bin/python"
else
  PYTHON_BIN="python3.12"
fi

cd "$ROOT"
PYTHONPATH="$ROOT/sidecar" "$PYTHON_BIN" -m unittest discover -s sidecar/tests -p 'test_*.py'
