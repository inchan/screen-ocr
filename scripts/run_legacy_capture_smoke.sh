#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPORT_PATH="artifacts/hotkey/latest-legacy-capture-smoke.json"
mkdir -p artifacts/hotkey

SCREEN_OCR_FORCE_LEGACY_CAPTURE=1 scripts/run_hotkey_smoke.sh
cp artifacts/hotkey/latest-hotkey-smoke.json "$REPORT_PATH"
printf 'Copied legacy capture smoke report to %s\n' "$REPORT_PATH"
