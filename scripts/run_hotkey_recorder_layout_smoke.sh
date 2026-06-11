#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swiftc \
  Sources/ScreenOCRApp/AppSettings.swift \
  Sources/ScreenOCRApp/HotkeyRecorderView.swift \
  scripts/hotkey_recorder_layout_smoke.swift \
  -o /tmp/screen-ocr-hotkey-recorder-layout-smoke

/tmp/screen-ocr-hotkey-recorder-layout-smoke
