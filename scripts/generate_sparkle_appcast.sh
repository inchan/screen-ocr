#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RELEASE_DIR="${SCREEN_OCR_RELEASE_DIR:-dist/release}"
APPCAST_OUTPUT="${SCREEN_OCR_APPCAST_OUTPUT:-docs/appcast.xml}"
RELEASE_TAG="${SCREEN_OCR_RELEASE_TAG:-}"
DOWNLOAD_PREFIX="${SCREEN_OCR_RELEASE_DOWNLOAD_PREFIX:-}"
MAXIMUM_VERSIONS="${SCREEN_OCR_APPCAST_MAXIMUM_VERSIONS:-3}"

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf 'FAIL: SPARKLE_PRIVATE_KEY is required to generate a Sparkle appcast\n' >&2
  exit 1
fi

if [[ ! -d "$RELEASE_DIR" ]]; then
  printf 'FAIL: release directory does not exist: %s\n' "$RELEASE_DIR" >&2
  exit 1
fi

if ! find "$RELEASE_DIR" -maxdepth 1 -name '*.zip' -type f -print -quit | grep -q .; then
  printf 'FAIL: release directory has no zip archives: %s\n' "$RELEASE_DIR" >&2
  exit 1
fi

if [[ -z "$DOWNLOAD_PREFIX" ]]; then
  if [[ -z "$RELEASE_TAG" ]]; then
    printf 'FAIL: set SCREEN_OCR_RELEASE_TAG or SCREEN_OCR_RELEASE_DOWNLOAD_PREFIX\n' >&2
    exit 1
  fi
  DOWNLOAD_PREFIX="https://github.com/inchan/screen-ocr/releases/download/${RELEASE_TAG}"
fi

GENERATE_APPCAST=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -x "$GENERATE_APPCAST" ]]; then
  GENERATE_APPCAST="$(find .build/artifacts -path '*/Sparkle/bin/generate_appcast' -type f -perm -111 -print -quit 2>/dev/null || true)"
fi
if [[ -z "$GENERATE_APPCAST" || ! -x "$GENERATE_APPCAST" ]]; then
  printf 'FAIL: missing Sparkle generate_appcast tool; run swift build first\n' >&2
  exit 1
fi

mkdir -p "$(dirname "$APPCAST_OUTPUT")"

printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --embed-release-notes \
  --maximum-versions "$MAXIMUM_VERSIONS" \
  -o "$APPCAST_OUTPUT" \
  "$RELEASE_DIR" >/dev/null

printf 'Generated Sparkle appcast: %s\n' "$APPCAST_OUTPUT"
