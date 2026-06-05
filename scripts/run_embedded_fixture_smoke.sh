#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH="${1:-dist/Screen OCR.app}"
EXECUTABLE="$ROOT/$APP_PATH/Contents/MacOS/ScreenOCRApp"
STATUS_PATH="$ROOT/artifacts/app/latest-status.json"
REPORT_PATH="$ROOT/artifacts/app/latest-embedded-fixture-smoke.json"

mkdir -p "$ROOT/artifacts/app"
rm -f "$STATUS_PATH" "$REPORT_PATH"

write_report() {
  local smoke_status="$1"
  local reason="${2:-}"
  local actual_text="${3:-}"

  EMBEDDED_FIXTURE_SMOKE_STATUS="$smoke_status" \
  EMBEDDED_FIXTURE_SMOKE_REASON="$reason" \
  EMBEDDED_FIXTURE_SMOKE_ACTUAL_TEXT="$actual_text" \
  ruby -rjson -rtime -e '
    payload = {
      "created_at" => Time.now.utc.iso8601,
      "status" => ENV.fetch("EMBEDDED_FIXTURE_SMOKE_STATUS"),
      "reason" => ENV.fetch("EMBEDDED_FIXTURE_SMOKE_REASON"),
      "actual_text" => ENV.fetch("EMBEDDED_FIXTURE_SMOKE_ACTUAL_TEXT")
    }
    File.write(ARGV.fetch(0), JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload)
  ' "$REPORT_PATH"
}

[[ -x "$EXECUTABLE" ]] || {
  write_report "failed" "Missing app bundle executable."
  exit 1
}

scripts/verify_embedded_runtime_bundle.sh "$APP_PATH" >/dev/null

printf '__SCREEN_OCR_EMBEDDED_FIXTURE_SENTINEL__' | pbcopy

APP_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]]; then kill "$APP_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

(
  cd /
  unset SCREEN_OCR_PROJECT_ROOT
  export SCREEN_OCR_ARTIFACT_ROOT="$ROOT/artifacts"
  export SCREEN_OCR_RUN_FIXTURE_ON_LAUNCH=1
  "$EXECUTABLE"
) >"$ROOT/artifacts/app/embedded-fixture-smoke.log" 2>&1 &
APP_PID="$!"

deadline=$((SECONDS + 45))
while (( SECONDS < deadline )); do
  if [[ -f "$STATUS_PATH" ]]; then
    status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["status"] rescue ""' "$STATUS_PATH")"
    if [[ "$status" == "fixture_ocr_finished" ]]; then
      actual_text="$(pbpaste)"
      if [[ "$actual_text" == *"Hello 123"* ]]; then
        write_report "passed" "" "$actual_text"
        exit 0
      fi
      write_report "failed" "Fixture OCR finished but clipboard did not contain expected text." "$actual_text"
      exit 1
    fi
  fi

  if ! kill -0 "$APP_PID" 2>/dev/null; then
    write_report "failed" "App exited before fixture OCR finished." "$(pbpaste)"
    exit 1
  fi

  sleep 0.5
done

write_report "failed" "Timed out waiting for fixture_ocr_finished from embedded runtime." "$(pbpaste)"
exit 1
