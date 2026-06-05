#!/usr/bin/env bash
set -euo pipefail

PYTHON_BIN="${SCREEN_OCR_PYTHON:-python3.12}"

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

print(f"PASS: Python {version.major}.{version.minor}.{version.micro} is compatible with PaddlePaddle macOS docs")
PY

