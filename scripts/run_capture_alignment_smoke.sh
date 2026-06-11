#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPORT_PATH="artifacts/hotkey/latest-capture-alignment-smoke.json"
ANALYSIS_PATH="artifacts/hotkey/latest-capture-alignment-analysis.json"
APP_STATUS_PATH="artifacts/app/latest-status.json"
FIXTURE_PATH="artifacts/hotkey/fixture-window.json"
PYTHON_BIN="${SCREEN_OCR_PYTHON:-.venv-ocr/bin/python}"

if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="python3"
fi

mkdir -p artifacts/hotkey artifacts/app artifacts/captures

convert_appkit_points_to_event_points() {
  local appkit_start_x="$1"
  local appkit_start_y="$2"
  local appkit_end_x="$3"
  local appkit_end_y="$4"

  ALIGNMENT_SMOKE_START_X="$appkit_start_x" \
  ALIGNMENT_SMOKE_START_Y="$appkit_start_y" \
  ALIGNMENT_SMOKE_END_X="$appkit_end_x" \
  ALIGNMENT_SMOKE_END_Y="$appkit_end_y" \
  swift - <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

let env = ProcessInfo.processInfo.environment
let start = CGPoint(
    x: Double(env["ALIGNMENT_SMOKE_START_X"]!)!,
    y: Double(env["ALIGNMENT_SMOKE_START_Y"]!)!
)
let end = CGPoint(
    x: Double(env["ALIGNMENT_SMOKE_END_X"]!)!,
    y: Double(env["ALIGNMENT_SMOKE_END_Y"]!)!
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
  local image_path="${4:-}"
  local debug_image_path="${5:-}"
  local debug_text_path="${6:-}"
  local debug_manifest_path="${7:-}"
  local app_status="${8:-}"

  ALIGNMENT_SMOKE_STATUS="$smoke_status" \
  ALIGNMENT_SMOKE_REASON="$reason" \
  ALIGNMENT_SMOKE_ELAPSED_MS="$elapsed_ms" \
  ALIGNMENT_SMOKE_IMAGE_PATH="$image_path" \
  ALIGNMENT_SMOKE_DEBUG_IMAGE_PATH="$debug_image_path" \
  ALIGNMENT_SMOKE_DEBUG_TEXT_PATH="$debug_text_path" \
  ALIGNMENT_SMOKE_DEBUG_MANIFEST_PATH="$debug_manifest_path" \
  ALIGNMENT_SMOKE_APP_STATUS="$app_status" \
  ALIGNMENT_SMOKE_START_X="${start_x:-}" \
  ALIGNMENT_SMOKE_START_Y="${start_y:-}" \
  ALIGNMENT_SMOKE_END_X="${end_x:-}" \
  ALIGNMENT_SMOKE_END_Y="${end_y:-}" \
  ALIGNMENT_SMOKE_EVENT_START_X="${event_start_x:-}" \
  ALIGNMENT_SMOKE_EVENT_START_Y="${event_start_y:-}" \
  ALIGNMENT_SMOKE_EVENT_END_X="${event_end_x:-}" \
  ALIGNMENT_SMOKE_EVENT_END_Y="${event_end_y:-}" \
  ALIGNMENT_SMOKE_FORCE_LEGACY="${SCREEN_OCR_FORCE_LEGACY_CAPTURE:-0}" \
  ALIGNMENT_SMOKE_ANALYSIS_PATH="$ANALYSIS_PATH" \
  ALIGNMENT_SMOKE_FIXTURE_PATH="$FIXTURE_PATH" \
  ALIGNMENT_SMOKE_APP_STATUS_PATH="$APP_STATUS_PATH" \
  ruby -rjson -rtime -e '
    def read_json(path)
      return nil if path.empty? || !File.exist?(path)
      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end

    payload = {
      "created_at" => Time.now.utc.iso8601,
      "status" => ENV.fetch("ALIGNMENT_SMOKE_STATUS"),
      "reason" => ENV.fetch("ALIGNMENT_SMOKE_REASON"),
      "elapsed_ms" => ENV.fetch("ALIGNMENT_SMOKE_ELAPSED_MS").to_i,
      "force_legacy_capture" => ENV.fetch("ALIGNMENT_SMOKE_FORCE_LEGACY") == "1",
      "image_path" => ENV.fetch("ALIGNMENT_SMOKE_IMAGE_PATH"),
      "debug_image_path" => ENV.fetch("ALIGNMENT_SMOKE_DEBUG_IMAGE_PATH"),
      "debug_text_path" => ENV.fetch("ALIGNMENT_SMOKE_DEBUG_TEXT_PATH"),
      "debug_manifest_path" => ENV.fetch("ALIGNMENT_SMOKE_DEBUG_MANIFEST_PATH"),
      "app_status" => ENV.fetch("ALIGNMENT_SMOKE_APP_STATUS"),
      "selection" => {
        "start_x" => ENV.fetch("ALIGNMENT_SMOKE_START_X"),
        "start_y" => ENV.fetch("ALIGNMENT_SMOKE_START_Y"),
        "end_x" => ENV.fetch("ALIGNMENT_SMOKE_END_X"),
        "end_y" => ENV.fetch("ALIGNMENT_SMOKE_END_Y")
      },
      "event_selection" => {
        "start_x" => ENV.fetch("ALIGNMENT_SMOKE_EVENT_START_X"),
        "start_y" => ENV.fetch("ALIGNMENT_SMOKE_EVENT_START_Y"),
        "end_x" => ENV.fetch("ALIGNMENT_SMOKE_EVENT_END_X"),
        "end_y" => ENV.fetch("ALIGNMENT_SMOKE_EVENT_END_Y")
      },
      "fixture" => read_json(ENV.fetch("ALIGNMENT_SMOKE_FIXTURE_PATH")),
      "latest_app_status" => read_json(ENV.fetch("ALIGNMENT_SMOKE_APP_STATUS_PATH")),
      "analysis" => read_json(ENV.fetch("ALIGNMENT_SMOKE_ANALYSIS_PATH"))
    }
    File.write(ARGV.fetch(0), JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload)
  ' "$REPORT_PATH"
}

analyze_alignment_image() {
  local image_path="$1"

  ALIGNMENT_IMAGE_PATH="$image_path" \
  ALIGNMENT_ANALYSIS_PATH="$ANALYSIS_PATH" \
  "$PYTHON_BIN" - <<'PY'
import json
import os
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError as error:
    print(f"Pillow is required to analyze alignment pixels: {error}", file=sys.stderr)
    sys.exit(3)

image_path = Path(os.environ["ALIGNMENT_IMAGE_PATH"])
analysis_path = Path(os.environ["ALIGNMENT_ANALYSIS_PATH"])

image = Image.open(image_path).convert("RGB")
width, height = image.size
pixels = image.load()

quadrants = {
    "top_left": (0, 0, width // 2, height // 2),
    "top_right": (width // 2, 0, width, height // 2),
    "bottom_left": (0, height // 2, width // 2, height),
    "bottom_right": (width // 2, height // 2, width, height),
}

expected = {
    "top_left": "red",
    "top_right": "green",
    "bottom_left": "blue",
    "bottom_right": "yellow",
}

def classify(red, green, blue):
    if red > green + 50 and red > blue + 50:
        return "red"
    if green > red + 50 and green > blue + 50:
        return "green"
    if blue > red + 50 and blue > green + 50:
        return "blue"
    if red > blue + 50 and green > blue + 50 and abs(red - green) < 80:
        return "yellow"
    return None

counts = {}
observed = {}

for name, (left, top, right, bottom) in quadrants.items():
    quadrant_counts = {"red": 0, "green": 0, "blue": 0, "yellow": 0}
    for y in range(top, bottom):
        for x in range(left, right):
            color = classify(*pixels[x, y])
            if color is not None:
                quadrant_counts[color] += 1
    counts[name] = quadrant_counts
    observed[name] = max(quadrant_counts, key=quadrant_counts.get)

minimum_marker_pixels = max(200, int(width * height * 0.002))
failures = []
for quadrant, color in expected.items():
    actual = observed[quadrant]
    actual_count = counts[quadrant][color]
    if actual != color:
        failures.append(f"{quadrant} expected {color}, observed {actual}")
    if actual_count < minimum_marker_pixels:
        failures.append(
            f"{quadrant} expected {color} count {actual_count} below threshold {minimum_marker_pixels}"
        )

result = {
    "status": "passed" if not failures else "failed",
    "image_path": str(image_path),
    "width": width,
    "height": height,
    "expected": expected,
    "observed": observed,
    "counts": counts,
    "minimum_marker_pixels": minimum_marker_pixels,
    "failures": failures,
}

analysis_path.parent.mkdir(parents=True, exist_ok=True)
analysis_path.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
print(json.dumps(result, indent=2, sort_keys=True))
sys.exit(0 if result["status"] == "passed" else 1)
PY
}

accessibility_trusted="$(swift -e 'import ApplicationServices; print(AXIsProcessTrusted())')"
if [[ "$accessibility_trusted" != "true" ]]; then
  write_report "skipped" "Accessibility permission is required to synthesize Cmd+Shift+0 and drag events."
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

rm -f "$APP_STATUS_PATH" "$FIXTURE_PATH" "$REPORT_PATH" "$ANALYSIS_PATH"
touch artifacts/hotkey/alignment-smoke-start.marker

APP_PID=""
FIXTURE_PID=""
cleanup() {
  if [[ -n "$APP_PID" ]]; then kill "$APP_PID" 2>/dev/null || true; fi
  if [[ -n "$FIXTURE_PID" ]]; then kill "$FIXTURE_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

SCREEN_OCR_FIXTURE_MODE=alignment \
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
  write_report "failed" "ScreenOCRApp did not register Cmd+Shift+0 within 20 seconds." 0 "" "" "" "" "${app_status:-}"
  exit 1
fi

deadline=$((SECONDS + 20))
while (( SECONDS < deadline )); do
  [[ -f "$FIXTURE_PATH" ]] && break
  sleep 0.25
done

if [[ ! -f "$FIXTURE_PATH" ]]; then
  write_report "failed" "Fixture window did not publish its frame within 20 seconds." 0 "" "" "" "" "$app_status"
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
      x + 4,
      y + 4,
      x + width - 4,
      y + height - 4
    ]
    puts coords.map(&:round).join(" ")
  ' "$FIXTURE_PATH"
)

read -r event_start_x event_start_y event_end_x event_end_y < <(
  convert_appkit_points_to_event_points "$start_x" "$start_y" "$end_x" "$end_y"
)

started_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"
ALIGNMENT_SMOKE_EVENT_START_X="$event_start_x" \
ALIGNMENT_SMOKE_EVENT_START_Y="$event_start_y" \
ALIGNMENT_SMOKE_EVENT_END_X="$event_end_x" \
ALIGNMENT_SMOKE_EVENT_END_Y="$event_end_y" \
swift -e 'import CoreGraphics; import Foundation
let env = ProcessInfo.processInfo.environment
let sx = Double(env["ALIGNMENT_SMOKE_EVENT_START_X"]!)!
let sy = Double(env["ALIGNMENT_SMOKE_EVENT_START_Y"]!)!
let ex = Double(env["ALIGNMENT_SMOKE_EVENT_END_X"]!)!
let ey = Double(env["ALIGNMENT_SMOKE_EVENT_END_Y"]!)!
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
postKey(29, true)
usleep(80_000)
postKey(29, false)
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
debug_image_path=""
debug_text_path=""
debug_manifest_path=""
while (( SECONDS < deadline )); do
  app_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["status"] rescue ""' "$APP_STATUS_PATH")"
  latest_capture="$(ruby -e 'marker = File.mtime(ARGV.fetch(0)); files = Dir["artifacts/captures/screen-ocr-*.{png,tiff}"].select { |path| File.mtime(path) > marker }; puts(files.max_by { |path| File.mtime(path) } || "")' artifacts/hotkey/alignment-smoke-start.marker)"
  debug_image_path="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["debug_image_path"] rescue ""' "$APP_STATUS_PATH")"
  debug_text_path="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["debug_text_path"] rescue ""' "$APP_STATUS_PATH")"
  debug_manifest_path="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0)))["debug_manifest_path"] rescue ""' "$APP_STATUS_PATH")"

  if [[ ( "$app_status" == "capture_ocr_finished" || "$app_status" == "capture_ocr_failed" ) && -f "$debug_image_path" ]]; then
    finished_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"
    if analyze_alignment_image "$debug_image_path"; then
      write_report "passed" "" "$((finished_at_ms - started_at_ms))" "$latest_capture" "$debug_image_path" "$debug_text_path" "$debug_manifest_path" "$app_status"
      exit 0
    fi

    write_report "failed" "Captured image corner markers did not match the selected screen quadrants." "$((finished_at_ms - started_at_ms))" "$latest_capture" "$debug_image_path" "$debug_text_path" "$debug_manifest_path" "$app_status"
    exit 1
  fi
  sleep 1
done

finished_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"
write_report "failed" "Timed out waiting for a debug capture image." "$((finished_at_ms - started_at_ms))" "$latest_capture" "$debug_image_path" "$debug_text_path" "$debug_manifest_path" "${app_status:-}"
exit 1
