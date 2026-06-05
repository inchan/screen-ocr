#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

scripts/check_ocr_env.sh
swift build --product ScreenOCRApp
exec .build/debug/ScreenOCRApp
