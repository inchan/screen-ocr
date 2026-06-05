#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

def read_json(path)
  raise "missing #{path}" unless File.exist?(path)

  JSON.parse(File.read(path))
end

failures = []

benchmark = read_json("artifacts/ocr/latest-benchmark.json")
failures << "benchmark must cover at least 20 fixtures" unless benchmark.fetch("fixture_count") >= 20
failures << "all benchmark fixtures must pass" unless benchmark.fetch("passed_count") == benchmark.fetch("fixture_count")
failures << "median CER must be <= 0.05" unless benchmark.fetch("median_character_error_rate").to_f <= 0.05
failures << "warm median latency must be <= 2000 ms" unless benchmark.fetch("median_warm_elapsed_ms").to_f <= 2000.0

reliability = read_json("artifacts/hotkey/latest-reliability.json")
failures << "reliability must cover at least 20 runs" unless reliability.fetch("run_count") >= 20
failures << "hotkey success rate must be >= 0.95" unless reliability.fetch("success_rate").to_f >= 0.95

{
  "artifacts/smoke/latest-screen-smoke.json" => "screen smoke",
  "artifacts/acceptance/latest-normal-hotkey-smoke.json" => "normal hotkey smoke",
  "artifacts/hotkey/latest-legacy-capture-smoke.json" => "legacy capture smoke",
  "artifacts/app/latest-bundle-smoke.json" => "bundle smoke",
  "artifacts/app/latest-embedded-fixture-smoke.json" => "embedded fixture smoke"
}.each do |path, label|
  report = read_json(path)
  failures << "#{label} must pass" unless report.fetch("status") == "passed"
end

if failures.empty?
  puts "quantitative assertions passed"
else
  warn failures.join("\n")
  exit 1
end
