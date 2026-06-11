#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swiftc \
  Sources/ScreenOCRApp/AppSettings.swift \
  Sources/ScreenOCRApp/HotkeyRecorderView.swift \
  Sources/ScreenOCRApp/SettingsWindowController.swift \
  scripts/settings_window_layout_smoke.swift \
  -o /tmp/screen-ocr-settings-window-layout-smoke

/tmp/screen-ocr-settings-window-layout-smoke
