#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH="${1:-dist/Screen OCR.app}"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/ScreenOCRApp"
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
PROJECT_ROOT_FILE="$APP_PATH/Contents/Resources/project-root.txt"
PYTHON_BIN="$APP_PATH/Contents/Resources/python-runtime/bin/python"
SIDECAR_PATH="$APP_PATH/Contents/Resources/sidecar/screen_ocr_sidecar"
FIXTURE_PATH="$APP_PATH/Contents/Resources/fixtures/ocr/mixed-ko-en-simple.png"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

[[ -d "$APP_PATH" ]] || fail "missing app bundle: $APP_PATH"
[[ -f "$INFO_PLIST" ]] || fail "missing Info.plist"
[[ -x "$EXECUTABLE" ]] || fail "missing executable: $EXECUTABLE"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

[[ "$(plist_value CFBundlePackageType)" == "APPL" ]] || fail "CFBundlePackageType must be APPL"
[[ "$(plist_value CFBundleExecutable)" == "ScreenOCRApp" ]] || fail "CFBundleExecutable must be ScreenOCRApp"
[[ "$(plist_value CFBundleName)" == "Screen OCR" ]] || fail "CFBundleName must be Screen OCR"
[[ "$(plist_value LSUIElement)" == "true" ]] || fail "LSUIElement must be true"
[[ "$(plist_value LSMinimumSystemVersion)" == "14.0" ]] || fail "LSMinimumSystemVersion must be 14.0"
[[ -d "$SPARKLE_FRAMEWORK" ]] || fail "missing Sparkle.framework"
otool -L "$EXECUTABLE" | grep -q '@rpath/Sparkle.framework' || fail "executable must link Sparkle through @rpath"

if /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST" >/dev/null 2>&1; then
  [[ "$(plist_value SUFeedURL)" == "https://inchan.github.io/screen-ocr/appcast.xml" ]] || fail "SUFeedURL must point at GitHub Pages appcast"
  /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" >/dev/null 2>&1 || fail "SUPublicEDKey required when SUFeedURL exists"
  [[ "$(plist_value SUEnableAutomaticChecks)" == "false" ]] || fail "SUEnableAutomaticChecks must default to false"
  [[ "$(plist_value SUAutomaticallyUpdate)" == "false" ]] || fail "SUAutomaticallyUpdate must default to false"
  [[ "$(plist_value SUAllowsAutomaticUpdates)" == "false" ]] || fail "SUAllowsAutomaticUpdates must be false so Sparkle cannot silently install on quit"
  [[ "$(plist_value SUScheduledCheckInterval)" == "86400" ]] || fail "SUScheduledCheckInterval must be 86400"
fi

if [[ -f "$PROJECT_ROOT_FILE" ]]; then
  PROJECT_ROOT="$(cat "$PROJECT_ROOT_FILE")"
  [[ -d "$PROJECT_ROOT/sidecar/screen_ocr_sidecar" ]] || fail "project root resource must point at sidecar directory"
  [[ -x "$PROJECT_ROOT/.venv-ocr/bin/python" ]] || fail "project root resource must point at OCR Python runtime"
elif [[ -x "$PYTHON_BIN" && -d "$SIDECAR_PATH" && -f "$FIXTURE_PATH" ]]; then
  :
else
  fail "bundle must include either project-root.txt or embedded OCR resources"
fi

pass "verified app bundle: $APP_PATH"
