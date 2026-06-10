#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Screen OCR"
BUNDLE_ID="dev.screenocr.local"
APP_PATH="dist/${APP_NAME}.app"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
EMBED_RUNTIME="${SCREEN_OCR_EMBED_RUNTIME:-0}"

swift build -c release --product ScreenOCRApp >/dev/null
BIN_PATH="$(swift build -c release --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$MACOS_PATH" "$RESOURCES_PATH"

cp "$BIN_PATH/ScreenOCRApp" "$MACOS_PATH/ScreenOCRApp"
chmod +x "$MACOS_PATH/ScreenOCRApp"

if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$RESOURCES_PATH/AppIcon.icns"
else
  printf 'FAIL: missing Resources/AppIcon.icns (run scripts/generate_app_icon.sh)\n' >&2
  exit 1
fi
if [[ "$EMBED_RUNTIME" == "1" ]]; then
  [[ -x ".venv-ocr/bin/python" ]] || {
    printf 'FAIL: missing OCR Python runtime: .venv-ocr/bin/python\n' >&2
    exit 1
  }
  [[ -d "sidecar/screen_ocr_sidecar" ]] || {
    printf 'FAIL: missing OCR sidecar source\n' >&2
    exit 1
  }
  [[ -d "fixtures/ocr" ]] || {
    printf 'FAIL: missing OCR fixtures\n' >&2
    exit 1
  }

  rsync -a --delete \
    --delete-excluded \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    .venv-ocr/ "$RESOURCES_PATH/python-runtime/"
  python_target="$(readlink .venv-ocr/bin/python3.12 || true)"
  if [[ -z "$python_target" || ! -x "$python_target" ]]; then
    printf 'FAIL: .venv-ocr/bin/python3.12 must resolve to an executable Python interpreter\n' >&2
    exit 1
  fi
  for python_name in python python3 python3.12; do
    rm -f "$RESOURCES_PATH/python-runtime/bin/$python_name"
    cat >"$RESOURCES_PATH/python-runtime/bin/$python_name" <<PYTHON_WRAPPER
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
RUNTIME_DIR="\$(cd "\$SCRIPT_DIR/.." && pwd)"
SITE_PACKAGES="\$(find "\$RUNTIME_DIR/lib" -maxdepth 2 -type d -name site-packages -print -quit)"
if [[ -n "\$SITE_PACKAGES" ]]; then
  if [[ -n "\${PYTHONPATH:-}" ]]; then
    export PYTHONPATH="\$SITE_PACKAGES:\$PYTHONPATH"
  else
    export PYTHONPATH="\$SITE_PACKAGES"
  fi
fi
export PYTHONDONTWRITEBYTECODE=1
exec "$python_target" "\$@"
PYTHON_WRAPPER
    chmod +x "$RESOURCES_PATH/python-runtime/bin/$python_name"
  done
  rsync -a --delete \
    --delete-excluded \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    sidecar/ "$RESOURCES_PATH/sidecar/"
  rsync -a --delete --delete-excluded fixtures/ "$RESOURCES_PATH/fixtures/"
else
  printf '%s\n' "$ROOT" >"$RESOURCES_PATH/project-root.txt"
fi
printf 'APPL????' >"$CONTENTS_PATH/PkgInfo"

cat >"$CONTENTS_PATH/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ScreenOCRApp</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

if [[ "$EMBED_RUNTIME" == "1" ]]; then
  printf 'Built %s with embedded OCR resources\n' "$APP_PATH"
else
  printf 'Built %s\n' "$APP_PATH"
fi
