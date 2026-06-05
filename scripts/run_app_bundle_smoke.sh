#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH="${1:-dist/Screen OCR.app}"
EXECUTABLE="$ROOT/$APP_PATH/Contents/MacOS/ScreenOCRApp"
STATUS_PATH="$ROOT/artifacts/app/latest-status.json"
REPORT_PATH="$ROOT/artifacts/app/latest-bundle-smoke.json"

mkdir -p "$ROOT/artifacts/app"
rm -f "$STATUS_PATH" "$REPORT_PATH"

write_report() {
  local smoke_status="$1"
  local reason="${2:-}"

  BUNDLE_SMOKE_STATUS="$smoke_status" \
  BUNDLE_SMOKE_REASON="$reason" \
  ruby -rjson -rtime -e '
    payload = {
      "created_at" => Time.now.utc.iso8601,
      "status" => ENV.fetch("BUNDLE_SMOKE_STATUS"),
      "reason" => ENV.fetch("BUNDLE_SMOKE_REASON")
    }
    File.write(ARGV.fetch(0), JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload)
  ' "$REPORT_PATH"
}

[[ -x "$EXECUTABLE" ]] || {
  write_report "failed" "Missing app bundle executable."
  exit 1
}

APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]]; then kill "$APP_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

(
  cd /
  export SCREEN_OCR_ARTIFACT_ROOT="$ROOT/artifacts"
  "$EXECUTABLE"
) >"$ROOT/artifacts/app/bundle-smoke.log" 2>&1 &
APP_PID="$!"

deadline=$((SECONDS + 15))
while (( SECONDS < deadline )); do
  if [[ -f "$STATUS_PATH" ]]; then
    status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["status"] rescue ""' "$STATUS_PATH")"
    if [[ "$status" == "hotkey_registered" ]]; then
      write_report "passed" ""
      exit 0
    fi
  fi

  if ! kill -0 "$APP_PID" 2>/dev/null; then
    write_report "failed" "App bundle executable exited before registering the hotkey."
    exit 1
  fi

  sleep 0.25
done

write_report "failed" "Timed out waiting for hotkey_registered from app bundle."
exit 1
