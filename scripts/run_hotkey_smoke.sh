#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPORT_PATH="artifacts/hotkey/latest-hotkey-smoke.json"
APP_STATUS_PATH="artifacts/app/latest-status.json"
WORKER_STATUS_PATH="artifacts/app/latest-worker-status.json"
FIXTURE_PATH="artifacts/hotkey/fixture-window.json"
mkdir -p artifacts/hotkey artifacts/app artifacts/captures

convert_appkit_points_to_event_points() {
  local appkit_start_x="$1"
  local appkit_start_y="$2"
  local appkit_end_x="$3"
  local appkit_end_y="$4"

  HOTKEY_SMOKE_START_X="$appkit_start_x" \
  HOTKEY_SMOKE_START_Y="$appkit_start_y" \
  HOTKEY_SMOKE_END_X="$appkit_end_x" \
  HOTKEY_SMOKE_END_Y="$appkit_end_y" \
  swift - <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

let env = ProcessInfo.processInfo.environment
let start = CGPoint(
    x: Double(env["HOTKEY_SMOKE_START_X"]!)!,
    y: Double(env["HOTKEY_SMOKE_START_Y"]!)!
)
let end = CGPoint(
    x: Double(env["HOTKEY_SMOKE_END_X"]!)!,
    y: Double(env["HOTKEY_SMOKE_END_Y"]!)!
)

struct DisplayMapping {
    let appKitFrame: CGRect
    let captureBounds: CGRect
}

let mappings: [DisplayMapping] = NSScreen.screens.compactMap { screen in
    guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
        return nil
    }

    return DisplayMapping(
        appKitFrame: screen.frame,
        captureBounds: CGDisplayBounds(displayID.uint32Value)
    )
}

func mapping(containing point: CGPoint) -> DisplayMapping {
    if let exact = mappings.first(where: { $0.appKitFrame.contains(point) }) {
        return exact
    }

    return mappings.min { left, right in
        hypot(left.appKitFrame.midX - point.x, left.appKitFrame.midY - point.y) <
            hypot(right.appKitFrame.midX - point.x, right.appKitFrame.midY - point.y)
    }!
}

func eventPoint(fromAppKit point: CGPoint) -> CGPoint {
    let display = mapping(containing: point)
    return CGPoint(
        x: display.captureBounds.minX + point.x - display.appKitFrame.minX,
        y: display.captureBounds.minY + display.appKitFrame.maxY - point.y
    )
}

let eventStart = eventPoint(fromAppKit: start)
let eventEnd = eventPoint(fromAppKit: end)
print(
    [eventStart.x, eventStart.y, eventEnd.x, eventEnd.y]
        .map { String(Int($0.rounded())) }
        .joined(separator: " ")
)
SWIFT
}

write_report() {
  local smoke_status="$1"
  local reason="${2:-}"
  local elapsed_ms="${3:-0}"
  local actual_text="${4:-}"
  local image_path="${5:-}"
  local debug_image_path="${6:-}"
  local debug_text_path="${7:-}"
  local debug_manifest_path="${8:-}"
  local capture_elapsed_ms="${9:-}"
  local ocr_elapsed_ms="${10:-}"
  local clipboard_elapsed_ms="${11:-}"
  local total_elapsed_ms="${12:-}"
  local worker_ready_elapsed_ms="${13:-}"
  local worker_init_elapsed_ms="${14:-}"
  local worker_rss_mb="${15:-}"
  local selection_elapsed_ms="${16:-}"
  local screen_capture_elapsed_ms="${17:-}"
  local png_write_elapsed_ms="${18:-}"
  local image_capture_elapsed_ms="${19:-}"
  local post_selection_to_clipboard_elapsed_ms="${20:-}"
  local preprocess_elapsed_ms="${21:-}"
  local preprocess_applied="${22:-}"
  local preprocess_original_width="${23:-}"
  local preprocess_original_height="${24:-}"
  local preprocess_width="${25:-}"
  local preprocess_height="${26:-}"
  local preprocess_status="${27:-}"
  local ocr_image_path="${28:-}"
  local preprocessed_image_path="${29:-}"

  HOTKEY_SMOKE_STATUS="$smoke_status" \
  HOTKEY_SMOKE_REASON="$reason" \
  HOTKEY_SMOKE_ELAPSED_MS="$elapsed_ms" \
  HOTKEY_SMOKE_ACTUAL_TEXT="$actual_text" \
  HOTKEY_SMOKE_IMAGE_PATH="$image_path" \
  HOTKEY_SMOKE_DEBUG_IMAGE_PATH="$debug_image_path" \
  HOTKEY_SMOKE_DEBUG_TEXT_PATH="$debug_text_path" \
  HOTKEY_SMOKE_DEBUG_MANIFEST_PATH="$debug_manifest_path" \
  HOTKEY_SMOKE_CAPTURE_ELAPSED_MS="$capture_elapsed_ms" \
  HOTKEY_SMOKE_OCR_ELAPSED_MS="$ocr_elapsed_ms" \
  HOTKEY_SMOKE_CLIPBOARD_ELAPSED_MS="$clipboard_elapsed_ms" \
  HOTKEY_SMOKE_TOTAL_ELAPSED_MS="$total_elapsed_ms" \
  HOTKEY_SMOKE_WORKER_READY_ELAPSED_MS="$worker_ready_elapsed_ms" \
  HOTKEY_SMOKE_WORKER_INIT_ELAPSED_MS="$worker_init_elapsed_ms" \
  HOTKEY_SMOKE_WORKER_RSS_MB="$worker_rss_mb" \
  HOTKEY_SMOKE_SELECTION_ELAPSED_MS="$selection_elapsed_ms" \
  HOTKEY_SMOKE_SCREEN_CAPTURE_ELAPSED_MS="$screen_capture_elapsed_ms" \
  HOTKEY_SMOKE_PNG_WRITE_ELAPSED_MS="$png_write_elapsed_ms" \
  HOTKEY_SMOKE_IMAGE_CAPTURE_ELAPSED_MS="$image_capture_elapsed_ms" \
  HOTKEY_SMOKE_POST_SELECTION_TO_CLIPBOARD_ELAPSED_MS="$post_selection_to_clipboard_elapsed_ms" \
  HOTKEY_SMOKE_PREPROCESS_ELAPSED_MS="$preprocess_elapsed_ms" \
  HOTKEY_SMOKE_PREPROCESS_APPLIED="$preprocess_applied" \
  HOTKEY_SMOKE_PREPROCESS_ORIGINAL_WIDTH="$preprocess_original_width" \
  HOTKEY_SMOKE_PREPROCESS_ORIGINAL_HEIGHT="$preprocess_original_height" \
  HOTKEY_SMOKE_PREPROCESS_WIDTH="$preprocess_width" \
  HOTKEY_SMOKE_PREPROCESS_HEIGHT="$preprocess_height" \
  HOTKEY_SMOKE_PREPROCESS_STATUS="$preprocess_status" \
  HOTKEY_SMOKE_OCR_IMAGE_PATH="$ocr_image_path" \
  HOTKEY_SMOKE_PREPROCESSED_IMAGE_PATH="$preprocessed_image_path" \
  ruby -rjson -rtime -e '
    payload = {
      "created_at" => Time.now.utc.iso8601,
      "status" => ENV.fetch("HOTKEY_SMOKE_STATUS"),
      "reason" => ENV.fetch("HOTKEY_SMOKE_REASON"),
      "elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_ELAPSED_MS").to_i,
      "actual_text" => ENV.fetch("HOTKEY_SMOKE_ACTUAL_TEXT"),
      "image_path" => ENV.fetch("HOTKEY_SMOKE_IMAGE_PATH"),
      "debug_image_path" => ENV.fetch("HOTKEY_SMOKE_DEBUG_IMAGE_PATH"),
      "debug_text_path" => ENV.fetch("HOTKEY_SMOKE_DEBUG_TEXT_PATH"),
      "debug_manifest_path" => ENV.fetch("HOTKEY_SMOKE_DEBUG_MANIFEST_PATH")
    }
    {
      "capture_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_CAPTURE_ELAPSED_MS"),
      "ocr_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_OCR_ELAPSED_MS"),
      "clipboard_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_CLIPBOARD_ELAPSED_MS"),
      "total_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_TOTAL_ELAPSED_MS"),
      "selection_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_SELECTION_ELAPSED_MS"),
      "screen_capture_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_SCREEN_CAPTURE_ELAPSED_MS"),
      "png_write_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_PNG_WRITE_ELAPSED_MS"),
      "image_capture_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_IMAGE_CAPTURE_ELAPSED_MS"),
      "post_selection_to_clipboard_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_POST_SELECTION_TO_CLIPBOARD_ELAPSED_MS"),
      "preprocess_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_PREPROCESS_ELAPSED_MS"),
      "preprocess_applied" => ENV.fetch("HOTKEY_SMOKE_PREPROCESS_APPLIED"),
      "preprocess_original_width" => ENV.fetch("HOTKEY_SMOKE_PREPROCESS_ORIGINAL_WIDTH"),
      "preprocess_original_height" => ENV.fetch("HOTKEY_SMOKE_PREPROCESS_ORIGINAL_HEIGHT"),
      "preprocess_width" => ENV.fetch("HOTKEY_SMOKE_PREPROCESS_WIDTH"),
      "preprocess_height" => ENV.fetch("HOTKEY_SMOKE_PREPROCESS_HEIGHT")
    }.each do |key, value|
      payload[key] = value.to_i unless value.empty?
    end
    {
      "preprocess_status" => ENV.fetch("HOTKEY_SMOKE_PREPROCESS_STATUS"),
      "ocr_image_path" => ENV.fetch("HOTKEY_SMOKE_OCR_IMAGE_PATH"),
      "preprocessed_image_path" => ENV.fetch("HOTKEY_SMOKE_PREPROCESSED_IMAGE_PATH")
    }.each do |key, value|
      payload[key] = value unless value.empty?
    end
    {
      "worker_ready_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_WORKER_READY_ELAPSED_MS"),
      "worker_init_elapsed_ms" => ENV.fetch("HOTKEY_SMOKE_WORKER_INIT_ELAPSED_MS"),
      "worker_rss_mb" => ENV.fetch("HOTKEY_SMOKE_WORKER_RSS_MB")
    }.each do |key, value|
      payload[key] = value.to_f unless value.empty?
    end
    File.write(ARGV.fetch(0), JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload)
  ' "$REPORT_PATH"
}

accessibility_trusted="$(swift -e 'import ApplicationServices; print(AXIsProcessTrusted())')"
if [[ "$accessibility_trusted" != "true" ]]; then
  write_report "skipped" "Accessibility permission is required to synthesize Cmd+Shift+2 and drag events."
  exit 2
fi

screen_recording_trusted="$(swift -e 'import CoreGraphics; print(CGPreflightScreenCaptureAccess())')"
if [[ "$screen_recording_trusted" != "true" ]]; then
  write_report "skipped" "Screen Recording permission is required for ScreenCaptureKit capture."
  exit 2
fi

if [[ "${SCREEN_OCR_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --product ScreenOCRApp --product ScreenOCRFixtureWindow >/dev/null
fi

pkill -f ".build/debug/ScreenOCRApp" 2>/dev/null || true
pkill -f ".build/debug/ScreenOCRFixtureWindow" 2>/dev/null || true
pkill -f "$ROOT/dist/Screen OCR.app/Contents/MacOS/ScreenOCRApp" 2>/dev/null || true
pkill -f "screen_ocr_sidecar.worker" 2>/dev/null || true

rm -f "$APP_STATUS_PATH" "$WORKER_STATUS_PATH" "$FIXTURE_PATH" "$REPORT_PATH"
printf '__SCREEN_OCR_HOTKEY_SMOKE_SENTINEL__' | pbcopy
touch artifacts/hotkey/smoke-start.marker

APP_PID=""
FIXTURE_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]]; then kill "$APP_PID" 2>/dev/null || true; fi
  if [[ -n "$FIXTURE_PID" ]]; then kill "$FIXTURE_PID" 2>/dev/null || true; fi
  pkill -f "screen_ocr_sidecar.worker" 2>/dev/null || true
}
trap cleanup EXIT

.build/debug/ScreenOCRFixtureWindow >artifacts/hotkey/fixture-window.log 2>&1 &
FIXTURE_PID="$!"
.build/debug/ScreenOCRApp >artifacts/hotkey/screen-ocr-app.log 2>&1 &
APP_PID="$!"

deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  app_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["status"] rescue ""' "$APP_STATUS_PATH")"
  [[ "$app_status" == "hotkey_registered" ]] && break
  sleep 0.25
done

if [[ "${app_status:-}" != "hotkey_registered" ]]; then
  write_report "failed" "ScreenOCRApp did not register Cmd+Shift+2 within 20 seconds."
  exit 1
fi

deadline=$((SECONDS + 45))
while (( SECONDS < deadline )); do
  worker_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["status"] rescue ""' "$WORKER_STATUS_PATH")"
  [[ "$worker_status" == "ready" ]] && break
  if [[ "$worker_status" == "failed" ]]; then
    worker_error="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["error"] rescue ""' "$WORKER_STATUS_PATH")"
    write_report "failed" "OCR worker failed during prewarm: $worker_error"
    exit 1
  fi
  sleep 0.25
done

if [[ "${worker_status:-}" != "ready" ]]; then
  write_report "failed" "OCR worker did not become ready within 45 seconds."
  exit 1
fi

worker_ready_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["ready_elapsed_ms"] rescue ""' "$WORKER_STATUS_PATH")"
worker_init_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["worker_init_elapsed_ms"] rescue ""' "$WORKER_STATUS_PATH")"
worker_rss_mb="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["worker_rss_mb"] rescue ""' "$WORKER_STATUS_PATH")"

deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  [[ -f "$FIXTURE_PATH" ]] && break
  sleep 0.25
done

if [[ ! -f "$FIXTURE_PATH" ]]; then
  write_report "failed" "Fixture window did not publish its frame within 20 seconds."
  exit 1
fi

read -r start_x start_y end_x end_y < <(
  ruby -rjson -e '
    frame = JSON.parse(File.read(ARGV.fetch(0)))
    x = frame.fetch("content_x", frame.fetch("x"))
    y = frame.fetch("content_y", frame.fetch("y"))
    width = frame.fetch("content_width", frame.fetch("width"))
    height = frame.fetch("content_height", frame.fetch("height"))
    coords = [
      x + 28,
      y + 18,
      x + width - 28,
      y + height - 12
    ]
    puts coords.map(&:round).join(" ")
  ' "$FIXTURE_PATH"
)

read -r event_start_x event_start_y event_end_x event_end_y < <(
  convert_appkit_points_to_event_points "$start_x" "$start_y" "$end_x" "$end_y"
)

started_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"
HOTKEY_SMOKE_EVENT_START_X="$event_start_x" \
HOTKEY_SMOKE_EVENT_START_Y="$event_start_y" \
HOTKEY_SMOKE_EVENT_END_X="$event_end_x" \
HOTKEY_SMOKE_EVENT_END_Y="$event_end_y" \
swift -e 'import CoreGraphics; import Foundation
let env = ProcessInfo.processInfo.environment
let sx = Double(env["HOTKEY_SMOKE_EVENT_START_X"]!)!
let sy = Double(env["HOTKEY_SMOKE_EVENT_START_Y"]!)!
let ex = Double(env["HOTKEY_SMOKE_EVENT_END_X"]!)!
let ey = Double(env["HOTKEY_SMOKE_EVENT_END_Y"]!)!
let flags: CGEventFlags = [.maskCommand, .maskShift]
func postKey(_ keyCode: CGKeyCode, _ down: Bool) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)!
    event.flags = flags
    event.post(tap: .cghidEventTap)
}
let source = CGEventSource(stateID: .hidSystemState)
func postMouse(_ type: CGEventType, _ point: CGPoint) {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
    event.post(tap: .cghidEventTap)
}
postKey(19, true)
usleep(80_000)
postKey(19, false)
usleep(700_000)
let start = CGPoint(x: sx, y: sy)
let end = CGPoint(x: ex, y: ey)
postMouse(.leftMouseDown, start)
for step in 1...24 {
    let t = CGFloat(step) / 24.0
    let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    postMouse(.leftMouseDragged, point)
    usleep(8_000)
}
postMouse(.leftMouseUp, end)
'

deadline=$((SECONDS + 45))
latest_capture=""
while (( SECONDS < deadline )); do
  app_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["status"] rescue ""' "$APP_STATUS_PATH")"
  actual_text="$(pbpaste)"
  latest_capture="$(ruby -e 'marker = File.mtime(ARGV.fetch(0)); files = Dir["artifacts/captures/screen-ocr-*.png"].select { |path| File.mtime(path) > marker }; puts(files.max_by { |path| File.mtime(path) } || "")' artifacts/hotkey/smoke-start.marker)"
  debug_image_path="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["debug_image_path"] rescue ""' "$APP_STATUS_PATH")"
  debug_text_path="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["debug_text_path"] rescue ""' "$APP_STATUS_PATH")"
  debug_manifest_path="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["debug_manifest_path"] rescue ""' "$APP_STATUS_PATH")"
  capture_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["capture_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  ocr_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["ocr_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  clipboard_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["clipboard_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  total_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["total_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  selection_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["selection_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  screen_capture_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["screen_capture_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  png_write_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["png_write_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  image_capture_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["image_capture_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  post_selection_to_clipboard_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["post_selection_to_clipboard_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  preprocess_elapsed_ms="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["preprocess_elapsed_ms"] rescue ""' "$APP_STATUS_PATH")"
  preprocess_applied="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["preprocess_applied"] rescue ""' "$APP_STATUS_PATH")"
  preprocess_original_width="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["preprocess_original_width"] rescue ""' "$APP_STATUS_PATH")"
  preprocess_original_height="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["preprocess_original_height"] rescue ""' "$APP_STATUS_PATH")"
  preprocess_width="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["preprocess_width"] rescue ""' "$APP_STATUS_PATH")"
  preprocess_height="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["preprocess_height"] rescue ""' "$APP_STATUS_PATH")"
  preprocess_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["preprocess_status"] rescue ""' "$APP_STATUS_PATH")"
  ocr_image_path="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["ocr_image_path"] rescue ""' "$APP_STATUS_PATH")"
  preprocessed_image_path="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["preprocessed_image_path"] rescue ""' "$APP_STATUS_PATH")"
  if [[ "$app_status" == "capture_ocr_finished" && "$actual_text" == *"Hello 123"* && -f "$debug_image_path" && -f "$debug_text_path" && -f "$debug_manifest_path" ]] && grep -q "Hello 123" "$debug_text_path"; then
    finished_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"
    write_report "passed" "" "$((finished_at_ms - started_at_ms))" "$actual_text" "$latest_capture" "$debug_image_path" "$debug_text_path" "$debug_manifest_path" "$capture_elapsed_ms" "$ocr_elapsed_ms" "$clipboard_elapsed_ms" "$total_elapsed_ms" "$worker_ready_elapsed_ms" "$worker_init_elapsed_ms" "$worker_rss_mb" "$selection_elapsed_ms" "$screen_capture_elapsed_ms" "$png_write_elapsed_ms" "$image_capture_elapsed_ms" "$post_selection_to_clipboard_elapsed_ms" "$preprocess_elapsed_ms" "$preprocess_applied" "$preprocess_original_width" "$preprocess_original_height" "$preprocess_width" "$preprocess_height" "$preprocess_status" "$ocr_image_path" "$preprocessed_image_path"
    exit 0
  fi
  sleep 1
done

finished_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"
write_report "failed" "Timed out waiting for capture_ocr_finished with expected OCR clipboard text." "$((finished_at_ms - started_at_ms))" "$(pbpaste)" "$latest_capture"
exit 1
