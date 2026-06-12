#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swiftc \
  Sources/ScreenOCRApp/PermissionDropPanel.swift \
  scripts/permission_drop_panel_smoke.swift \
  -o /tmp/screen-ocr-permission-drop-panel-smoke

/tmp/screen-ocr-permission-drop-panel-smoke
