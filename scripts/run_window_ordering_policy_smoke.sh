#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swiftc \
  Sources/ScreenOCRApp/WindowOrderingPolicy.swift \
  scripts/window_ordering_policy_smoke.swift \
  -o /tmp/screen-ocr-window-ordering-policy-smoke

/tmp/screen-ocr-window-ordering-policy-smoke
