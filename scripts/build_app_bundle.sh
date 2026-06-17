#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Screen OCR"
BUNDLE_ID="dev.screenocr.local"
if [[ -n "${SCREEN_OCR_VERSION:-}" ]]; then
  APP_VERSION="$SCREEN_OCR_VERSION"
elif [[ -f "VERSION" ]]; then
  APP_VERSION="$(tr -d '[:space:]' < VERSION)"
else
  APP_VERSION="0.0.1"
fi
ENABLE_SPARKLE_UPDATES="${SCREEN_OCR_ENABLE_SPARKLE_UPDATES:-0}"
SPARKLE_FEED_URL="${SCREEN_OCR_SPARKLE_FEED_URL:-https://inchan.github.io/screen-ocr/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SCREEN_OCR_SPARKLE_PUBLIC_ED_KEY:-}"
APP_PATH="dist/${APP_NAME}.app"
CONTENTS_PATH="$APP_PATH/Contents"
MACOS_PATH="$CONTENTS_PATH/MacOS"
FRAMEWORKS_PATH="$CONTENTS_PATH/Frameworks"
RESOURCES_PATH="$CONTENTS_PATH/Resources"
EMBED_RUNTIME="${SCREEN_OCR_EMBED_RUNTIME:-0}"

swift build -c release --product ScreenOCRApp >/dev/null
BIN_PATH="$(swift build -c release --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$MACOS_PATH" "$FRAMEWORKS_PATH" "$RESOURCES_PATH"

cp "$BIN_PATH/ScreenOCRApp" "$MACOS_PATH/ScreenOCRApp"
chmod +x "$MACOS_PATH/ScreenOCRApp"

SPARKLE_FRAMEWORK_SOURCE="$BIN_PATH/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  SPARKLE_FRAMEWORK_SOURCE="$(
    find .build -path '*/Sparkle.framework' -type d \
      | grep -E '/(debug|release)/Sparkle.framework$' \
      | head -1 \
      || true
  )"
fi
if [[ -z "$SPARKLE_FRAMEWORK_SOURCE" || ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  printf 'FAIL: missing Sparkle.framework from SwiftPM build artifacts\n' >&2
  exit 1
fi
rsync -a --delete "$SPARKLE_FRAMEWORK_SOURCE/" "$FRAMEWORKS_PATH/Sparkle.framework/"
if ! otool -l "$MACOS_PATH/ScreenOCRApp" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$MACOS_PATH/ScreenOCRApp"
fi

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

  python_info="$(
    .venv-ocr/bin/python - <<'PY'
import pathlib
import sys

base = pathlib.Path(sys._base_executable).resolve()
framework_root = None
for path in (base, *base.parents):
    if path.name == "Python.framework":
        framework_root = path
        break

if framework_root is None:
    raise SystemExit("FAIL: selected Python is not a framework build")

print(f"{sys.version_info.major}.{sys.version_info.minor}")
print(base)
print(framework_root)
PY
  )"
  python_version="$(printf '%s\n' "$python_info" | sed -n '1p')"
  python_base_executable="$(printf '%s\n' "$python_info" | sed -n '2p')"
  python_framework_root="$(printf '%s\n' "$python_info" | sed -n '3p')"

  if [[ -z "$python_version" || ! -x "$python_base_executable" || ! -d "$python_framework_root" ]]; then
    printf 'FAIL: could not resolve framework Python from .venv-ocr/bin/python\n' >&2
    exit 1
  fi

  python_framework_parent="$FRAMEWORKS_PATH"
  python_framework_bundle="$python_framework_parent/Python.framework"
  mkdir -p "$python_framework_parent"
  rsync -a --delete \
    --delete-excluded \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    "$python_framework_root/" "$python_framework_bundle/"
  ln -sfn "$python_version" "$python_framework_bundle/Versions/Current"
  ln -sfn "Versions/Current/Python" "$python_framework_bundle/Python"
  ln -sfn "Versions/Current/Headers" "$python_framework_bundle/Headers"
  ln -sfn "Versions/Current/Resources" "$python_framework_bundle/Resources"

  bundled_python_executable="$python_framework_bundle/Versions/$python_version/bin/python$python_version"
  bundled_python_library="$python_framework_bundle/Versions/$python_version/Python"
  [[ -x "$bundled_python_executable" ]] || {
    printf 'FAIL: missing bundled Python executable: %s\n' "$bundled_python_executable" >&2
    exit 1
  }
  [[ -f "$bundled_python_library" ]] || {
    printf 'FAIL: missing bundled Python framework library: %s\n' "$bundled_python_library" >&2
    exit 1
  }

  patch_python_framework_dependency() {
    local binary="$1"
    local replacement="$2"

    [[ -f "$binary" ]] || return 0
    otool -L "$binary" \
      | awk '/Python\.framework\/Versions\/[0-9.]+\/Python/ { print $1 }' \
      | while read -r dependency; do
          install_name_tool -change "$dependency" "$replacement" "$binary"
        done
  }

  # Make the copied framework relocatable. Homebrew and Python.org framework builds link
  # launchers to an absolute Python.framework path, which fails on another Mac.
  patch_python_framework_dependency "$bundled_python_executable" "@executable_path/../Python"
  patch_python_framework_dependency \
    "$python_framework_bundle/Versions/$python_version/Resources/Python.app/Contents/MacOS/Python" \
    "@executable_path/../../../../Python"
  install_name_tool -id "@rpath/Python.framework/Versions/$python_version/Python" "$bundled_python_library"

  for python_name in python python3 python3.12; do
    rm -f "$RESOURCES_PATH/python-runtime/bin/$python_name"
    cat >"$RESOURCES_PATH/python-runtime/bin/$python_name" <<PYTHON_WRAPPER
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
RUNTIME_DIR="\$(cd "\$SCRIPT_DIR/.." && pwd)"
RESOURCES_DIR="\$(cd "\$RUNTIME_DIR/.." && pwd)"
CONTENTS_DIR="\$(cd "\$RESOURCES_DIR/.." && pwd)"
SITE_PACKAGES="\$(find "\$RUNTIME_DIR/lib" -maxdepth 2 -type d -name site-packages -print -quit)"
if [[ -n "\$SITE_PACKAGES" ]]; then
  if [[ -n "\${PYTHONPATH:-}" ]]; then
    export PYTHONPATH="\$SITE_PACKAGES:\$PYTHONPATH"
  else
    export PYTHONPATH="\$SITE_PACKAGES"
  fi
fi
export PYTHONDONTWRITEBYTECODE=1
export PYTHONNOUSERSITE=1
exec "\$CONTENTS_DIR/Frameworks/Python.framework/Versions/$python_version/bin/python$python_version" "\$@"
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

SPARKLE_PLIST_KEYS=""
if [[ "$ENABLE_SPARKLE_UPDATES" == "1" ]]; then
  if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    printf 'FAIL: SCREEN_OCR_SPARKLE_PUBLIC_ED_KEY is required when SCREEN_OCR_ENABLE_SPARKLE_UPDATES=1\n' >&2
    exit 1
  fi
  SPARKLE_PLIST_KEYS="$(cat <<PLIST
  <key>SUFeedURL</key>
  <string>${SPARKLE_FEED_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${SPARKLE_PUBLIC_ED_KEY}</string>
  <key>SUEnableAutomaticChecks</key>
  <false/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUAllowsAutomaticUpdates</key>
  <false/>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
PLIST
)"
fi

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
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
${SPARKLE_PLIST_KEYS}
</dict>
</plist>
PLIST

# Sign with a stable identity when one exists. TCC keys an ad-hoc (linker-signed) bundle by
# its code hash, so every rebuild used to invalidate the Screen Recording grant and the next
# capture popped the system permission dialog again. A developer-certificate signature keeps
# the same identity across rebuilds, so the grant survives.
if [[ -z "${SCREEN_OCR_CODESIGN_IDENTITY:-}" ]]; then
  SCREEN_OCR_CODESIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1
  )"
fi
if [[ -n "${SCREEN_OCR_CODESIGN_IDENTITY:-}" ]]; then
  SCREEN_OCR_CODESIGN_IDENTITY="$SCREEN_OCR_CODESIGN_IDENTITY" "$ROOT/scripts/sign_app_bundle.sh" "$APP_PATH"
else
  printf 'WARN: no codesigning identity found; leaving ad-hoc signature (TCC grants will not survive rebuilds)\n' >&2
fi

if [[ "$EMBED_RUNTIME" == "1" ]]; then
  printf 'Built %s with embedded OCR resources\n' "$APP_PATH"
else
  printf 'Built %s\n' "$APP_PATH"
fi
