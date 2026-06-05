#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_COUNT="${SCREEN_OCR_RELIABILITY_RUNS:-20}"
MIN_SUCCESS_RATE="${SCREEN_OCR_MIN_SUCCESS_RATE:-0.95}"
REPORT_PATH="artifacts/hotkey/latest-reliability.json"
RUN_LOG_DIR="artifacts/hotkey/reliability-runs"

mkdir -p "$RUN_LOG_DIR"
rm -f "$REPORT_PATH"
rm -f "$RUN_LOG_DIR"/*.json "$RUN_LOG_DIR"/*.log 2>/dev/null || true

if ! [[ "$RUN_COUNT" =~ ^[0-9]+$ ]] || [[ "$RUN_COUNT" -le 0 ]]; then
  printf 'FAIL: SCREEN_OCR_RELIABILITY_RUNS must be a positive integer\n' >&2
  exit 1
fi

swift build --product ScreenOCRApp --product ScreenOCRFixtureWindow >/dev/null

started_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"
passed_count=0
skipped_count=0
failed_count=0

for run_index in $(seq 1 "$RUN_COUNT"); do
  run_log="$RUN_LOG_DIR/run-${run_index}.log"
  set +e
  SCREEN_OCR_SKIP_BUILD=1 scripts/run_hotkey_smoke.sh >"$run_log" 2>&1
  exit_status="$?"
  set -e

  if [[ -f artifacts/hotkey/latest-hotkey-smoke.json ]]; then
    cp artifacts/hotkey/latest-hotkey-smoke.json "$RUN_LOG_DIR/run-${run_index}.json"
  else
    ruby -rjson -rtime -e '
      payload = {
        "created_at" => Time.now.utc.iso8601,
        "status" => "failed",
        "reason" => "run_hotkey_smoke.sh did not produce latest-hotkey-smoke.json",
        "elapsed_ms" => 0,
        "actual_text" => "",
        "image_path" => ""
      }
      File.write(ARGV.fetch(0), JSON.pretty_generate(payload))
    ' "$RUN_LOG_DIR/run-${run_index}.json"
  fi

  run_status="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("status")' "$RUN_LOG_DIR/run-${run_index}.json")"
  run_elapsed="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("elapsed_ms", 0)' "$RUN_LOG_DIR/run-${run_index}.json")"
  case "$run_status" in
    passed)
      passed_count=$((passed_count + 1))
      ;;
    skipped)
      skipped_count=$((skipped_count + 1))
      ;;
    *)
      failed_count=$((failed_count + 1))
      ;;
  esac

  printf 'run=%02d/%02d status=%s elapsed_ms=%s exit=%s\n' "$run_index" "$RUN_COUNT" "$run_status" "$run_elapsed" "$exit_status"
done

finished_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"
REPORT_PATH="$REPORT_PATH" \
RUN_LOG_DIR="$RUN_LOG_DIR" \
RUN_COUNT="$RUN_COUNT" \
PASSED_COUNT="$passed_count" \
FAILED_COUNT="$failed_count" \
SKIPPED_COUNT="$skipped_count" \
ELAPSED_MS="$((finished_at_ms - started_at_ms))" \
MIN_SUCCESS_RATE="$MIN_SUCCESS_RATE" \
ruby -rjson -rtime -e '
  runs = Dir[File.join(ENV.fetch("RUN_LOG_DIR"), "run-*.json")]
    .sort_by { |path| path[/run-(\d+)\.json/, 1].to_i }
    .map { |path| JSON.parse(File.read(path)).merge("report_path" => path) }

  total = Integer(ENV.fetch("RUN_COUNT"))
  passed = Integer(ENV.fetch("PASSED_COUNT"))
  failed = Integer(ENV.fetch("FAILED_COUNT"))
  skipped = Integer(ENV.fetch("SKIPPED_COUNT"))
  min_success_rate = Float(ENV.fetch("MIN_SUCCESS_RATE"))
  success_rate = total.zero? ? 0.0 : passed.to_f / total
  elapsed_values = runs.map { |run| run.fetch("elapsed_ms", 0).to_i }.select { |value| value.positive? }
  sorted_elapsed = elapsed_values.sort
  median_elapsed = if sorted_elapsed.empty?
    0
  elsif sorted_elapsed.length.odd?
    sorted_elapsed[sorted_elapsed.length / 2]
  else
    (sorted_elapsed[sorted_elapsed.length / 2 - 1] + sorted_elapsed[sorted_elapsed.length / 2]) / 2.0
  end

  payload = {
    "created_at" => Time.now.utc.iso8601,
    "status" => success_rate >= min_success_rate && skipped == 0 ? "passed" : "failed",
    "run_count" => total,
    "passed_count" => passed,
    "failed_count" => failed,
    "skipped_count" => skipped,
    "success_rate" => success_rate.round(4),
    "min_success_rate" => min_success_rate,
    "elapsed_ms" => Integer(ENV.fetch("ELAPSED_MS")),
    "median_run_elapsed_ms" => median_elapsed,
    "runs" => runs
  }
  File.write(ENV.fetch("REPORT_PATH"), JSON.pretty_generate(payload))
  puts JSON.pretty_generate(payload.reject { |key, _| key == "runs" })
  exit(payload.fetch("status") == "passed" ? 0 : 1)
'
