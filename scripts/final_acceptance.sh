#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPORT_DIR="artifacts/acceptance"
REPORT_PATH="$REPORT_DIR/latest-final-acceptance.json"
STEP_LOG="$(mktemp)"
mkdir -p "$REPORT_DIR"

failures=0

append_step() {
  local name="$1"
  local command="$2"
  local status="$3"
  local exit_code="$4"
  local elapsed_ms="$5"

  STEP_NAME="$name" \
  STEP_COMMAND="$command" \
  STEP_STATUS="$status" \
  STEP_EXIT_CODE="$exit_code" \
  STEP_ELAPSED_MS="$elapsed_ms" \
  ruby -rjson -e '
    payload = {
      "name" => ENV.fetch("STEP_NAME"),
      "command" => ENV.fetch("STEP_COMMAND"),
      "status" => ENV.fetch("STEP_STATUS"),
      "exit_code" => ENV.fetch("STEP_EXIT_CODE").to_i,
      "elapsed_ms" => ENV.fetch("STEP_ELAPSED_MS").to_i
    }
    puts JSON.generate(payload)
  ' >>"$STEP_LOG"
}

run_step() {
  local name="$1"
  local command="$2"
  local started_at_ms
  local finished_at_ms
  local exit_code
  local status

  printf '\n==> %s\n' "$name"
  printf '%s\n' "$command"
  started_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"
  bash -lc "$command"
  exit_code=$?
  finished_at_ms="$(ruby -e 'puts (Time.now.to_f * 1000).to_i')"

  if [[ "$exit_code" -eq 0 ]]; then
    status="passed"
  else
    status="failed"
    failures=$((failures + 1))
  fi

  append_step "$name" "$command" "$status" "$exit_code" "$((finished_at_ms - started_at_ms))"
}

write_report() {
  local final_status="$1"

  FINAL_ACCEPTANCE_STATUS="$final_status" \
  ruby -rjson -rtime - "$STEP_LOG" "$REPORT_PATH" <<'RUBY'
step_log_path = ARGV.fetch(0)
report_path = ARGV.fetch(1)

steps = File.readlines(step_log_path, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }

def read_json(path)
  return nil unless File.exist?(path)
  JSON.parse(File.read(path))
end

benchmark = read_json("artifacts/ocr/latest-benchmark.json")
reliability = read_json("artifacts/hotkey/latest-reliability.json")
normal_hotkey = read_json("artifacts/acceptance/latest-normal-hotkey-smoke.json")
legacy_hotkey = read_json("artifacts/hotkey/latest-legacy-capture-smoke.json")
screen_smoke = read_json("artifacts/smoke/latest-screen-smoke.json")
embedded_smoke = read_json("artifacts/app/latest-embedded-fixture-smoke.json")
bundle_smoke = read_json("artifacts/app/latest-bundle-smoke.json")

summary = {
  "screen_smoke_status" => screen_smoke&.fetch("status", nil),
  "normal_hotkey_status" => normal_hotkey&.fetch("status", nil),
  "legacy_hotkey_status" => legacy_hotkey&.fetch("status", nil),
  "bundle_smoke_status" => bundle_smoke&.fetch("status", nil),
  "embedded_fixture_smoke_status" => embedded_smoke&.fetch("status", nil),
  "benchmark_fixture_count" => benchmark&.fetch("fixture_count", nil),
  "benchmark_passed_count" => benchmark&.fetch("passed_count", nil),
  "benchmark_median_cer" => benchmark&.fetch("median_character_error_rate", nil),
  "benchmark_mean_cer" => benchmark&.fetch("mean_character_error_rate", nil),
  "benchmark_median_warm_ms" => benchmark&.fetch("median_warm_elapsed_ms", nil),
  "reliability_run_count" => reliability&.fetch("run_count", nil),
  "reliability_success_rate" => reliability&.fetch("success_rate", nil),
  "reliability_median_run_ms" => reliability&.fetch("median_run_elapsed_ms", nil)
}

payload = {
  "created_at" => Time.now.utc.iso8601,
  "status" => ENV.fetch("FINAL_ACCEPTANCE_STATUS"),
  "steps" => steps,
  "summary" => summary,
  "rerun_benchmark" => ENV.fetch("SCREEN_OCR_ACCEPTANCE_RERUN_BENCHMARK", "0") == "1",
  "rerun_reliability" => ENV.fetch("SCREEN_OCR_ACCEPTANCE_RERUN_RELIABILITY", "0") == "1"
}

File.write(report_path, JSON.pretty_generate(payload))
puts JSON.pretty_generate(payload)
RUBY
}

run_step "agent gate" "scripts/agent_gate.sh"
run_step "screen capture OCR smoke" "scripts/run_screen_smoke.sh"
run_step "normal hotkey OCR smoke" "scripts/run_hotkey_smoke.sh && cp artifacts/hotkey/latest-hotkey-smoke.json artifacts/acceptance/latest-normal-hotkey-smoke.json"
run_step "forced macOS 14 capture fallback hotkey smoke" "scripts/run_legacy_capture_smoke.sh"
run_step "signed local bundle launch smoke" "scripts/run_app_bundle_smoke.sh"
run_step "embedded OCR bundle fixture smoke" "SCREEN_OCR_EMBED_RUNTIME=1 scripts/build_app_bundle.sh && scripts/sign_app_bundle.sh && scripts/verify_embedded_runtime_bundle.sh && scripts/run_embedded_fixture_smoke.sh && scripts/verify_app_signature.sh"

if [[ "${SCREEN_OCR_ACCEPTANCE_RERUN_BENCHMARK:-0}" == "1" ]]; then
  run_step "OCR fixture benchmark rerun" "scripts/run_ocr_fixture_benchmark.py"
fi

if [[ "${SCREEN_OCR_ACCEPTANCE_RERUN_RELIABILITY:-0}" == "1" ]]; then
  run_step "20-run hotkey reliability rerun" "scripts/run_hotkey_reliability.sh"
fi

run_step "quantitative artifact assertions" "scripts/assert_acceptance_artifacts.rb"

if [[ "$failures" -eq 0 ]]; then
  write_report "passed"
  rm -f "$STEP_LOG"
  printf '\nFINAL_ACCEPTANCE=PASS\n'
  exit 0
fi

write_report "failed"
rm -f "$STEP_LOG"
printf '\nFINAL_ACCEPTANCE=FAIL\n'
exit 1
