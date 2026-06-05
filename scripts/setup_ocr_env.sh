#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${SCREEN_OCR_PYTHON:-python3.12}"
VENV_DIR="${SCREEN_OCR_VENV:-$ROOT/.venv-ocr}"

cd "$ROOT"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  printf 'FAIL: compatible Python not found: %s\n' "$PYTHON_BIN" >&2
  exit 1
fi

"$PYTHON_BIN" - <<'PY'
import sys
version = sys.version_info
if not ((3, 9) <= (version.major, version.minor) <= (3, 13)):
    raise SystemExit(
        f"FAIL: Python {version.major}.{version.minor}.{version.micro} is outside PaddlePaddle macOS supported range 3.9-3.13"
    )
print(f"PASS: selected Python {version.major}.{version.minor}.{version.micro}")
PY

if [[ ! -d "$VENV_DIR" ]]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

"$VENV_DIR/bin/python" -m pip install --upgrade pip
"$VENV_DIR/bin/python" -m pip install paddlepaddle==3.3.0 -i https://www.paddlepaddle.org.cn/packages/stable/cpu/
"$VENV_DIR/bin/python" -m pip install paddleocr==3.6.0

printf 'PASS: OCR environment ready at %s\n' "$VENV_DIR"

