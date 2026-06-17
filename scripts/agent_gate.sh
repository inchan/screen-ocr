#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required_files=(
  "AGENTS.md"
  "docs/autonomous-system.md"
  "docs/research.md"
  "docs/decisions.md"
  "docs/spec.md"
  "docs/test-plan.md"
  "docs/roadmap.md"
  "docs/debugging.md"
  "docs/script-inventory.md"
  "docs/feedback-loop.md"
  "docs/validation-report.md"
  "docs/completion-audit.md"
)

failures=0

note() {
  printf '%s\n' "$*"
}

fail() {
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

pass() {
  printf 'PASS: %s\n' "$*"
}

for file in "${required_files[@]}"; do
  if [[ -f "$file" ]]; then
    pass "required file exists: $file"
  else
    fail "missing required file: $file"
  fi
done

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if [[ ! -f "$file" ]]; then
    fail "$label cannot be checked because $file is missing"
    return
  fi

  if grep -Eiq "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_contains "AGENTS.md" "Autonomy" "AGENTS declares autonomy"
check_contains "AGENTS.md" "Required Workflow" "AGENTS declares required workflow"
check_contains "AGENTS.md" "Phase Gates" "AGENTS declares phase gates"
check_contains "AGENTS.md" "Parallel Work" "AGENTS declares parallel work policy"
check_contains "AGENTS.md" "Test And Metrics Contract" "AGENTS declares test and metrics contract"
check_contains "AGENTS.md" "Self-Feedback And Growth" "AGENTS declares self-feedback growth"
check_contains "docs/spec.md" "Cmd\\+Shift\\+2" "spec covers Cmd+Shift+2"
check_contains "docs/spec.md" "Cmd\\+Shift\\+0" "spec covers Cmd+Shift+0 fallback"
check_contains "docs/spec.md" "clipboard" "spec covers clipboard behavior"
check_contains "docs/spec.md" "PaddleOCR" "spec covers PaddleOCR"
check_contains "docs/test-plan.md" "character error rate" "test plan covers OCR quality metric"
check_contains "docs/test-plan.md" "Warm OCR latency" "test plan covers latency metric"
check_contains "docs/roadmap.md" "Phase 0" "roadmap has Phase 0"
check_contains "docs/feedback-loop.md" "Status: adopted" "feedback loop has adopted entry"
check_contains "docs/research.md" "https://" "research log contains source links"
check_contains "docs/completion-audit.md" "Requirement Coverage" "completion audit maps requirements to evidence"

if [[ -x "scripts/check_docs_links.py" ]]; then
  if scripts/check_docs_links.py; then
    pass "documentation links"
  else
    fail "documentation links"
  fi
else
  fail "scripts/check_docs_links.py is missing or not executable"
fi

if [[ -f "fixtures/ocr/manifest.json" ]]; then
  fixture_count="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("fixtures").size' fixtures/ocr/manifest.json)"
  if [[ "$fixture_count" -ge 20 ]]; then
    pass "OCR fixture corpus has at least 20 fixtures"
  else
    fail "OCR fixture corpus must have at least 20 fixtures; found $fixture_count"
  fi

  missing_fixture_count="$(ruby -rjson -e 'root = Dir.pwd; fixtures = JSON.parse(File.read(ARGV.fetch(0))).fetch("fixtures"); print fixtures.count { |fixture| !File.exist?(File.join(root, fixture.fetch("path"))) }' fixtures/ocr/manifest.json)"
  if [[ "$missing_fixture_count" -eq 0 ]]; then
    pass "OCR fixture image files exist"
  else
    fail "OCR fixture manifest has $missing_fixture_count missing image files"
  fi
else
  fail "missing OCR fixture manifest"
fi

if [[ -f "Package.swift" ]]; then
  if command -v swift >/dev/null 2>&1; then
    note "Running swift test because Package.swift exists..."
    if ! xcrun --find xctest >/dev/null 2>&1; then
      fail "swift test unavailable because xctest is not installed or xcode-select does not point at a full Xcode"
    elif swift test; then
      pass "swift test"
    else
      fail "swift test"
    fi

    note "Running hotkey recorder layout smoke..."
    if bash scripts/run_hotkey_recorder_layout_smoke.sh; then
      pass "hotkey recorder layout smoke"
    else
      fail "hotkey recorder layout smoke"
    fi

    note "Running settings window layout smoke..."
    if bash scripts/run_settings_window_layout_smoke.sh; then
      pass "settings window layout smoke"
    else
      fail "settings window layout smoke"
    fi

    note "Running permission drop panel guidance smoke..."
    if bash scripts/run_permission_drop_panel_smoke.sh; then
      pass "permission drop panel guidance smoke"
    else
      fail "permission drop panel guidance smoke"
    fi

    note "Running window ordering policy smoke..."
    if bash scripts/run_window_ordering_policy_smoke.sh; then
      pass "window ordering policy smoke"
    else
      fail "window ordering policy smoke"
    fi

    if grep -q 'ScreenOCRApp' Package.swift; then
      note "Running swift build for ScreenOCRApp..."
      if swift build --product ScreenOCRApp; then
        pass "swift build --product ScreenOCRApp"
      else
        fail "swift build --product ScreenOCRApp"
      fi
    fi

    if grep -q 'ScreenOCRSmoke' Package.swift; then
      note "Running swift build for ScreenOCRSmoke..."
      if swift build --product ScreenOCRSmoke; then
        pass "swift build --product ScreenOCRSmoke"
      else
        fail "swift build --product ScreenOCRSmoke"
      fi
    fi

    if grep -q 'ScreenOCRFixtureWindow' Package.swift; then
      note "Running swift build for ScreenOCRFixtureWindow..."
      if swift build --product ScreenOCRFixtureWindow; then
        pass "swift build --product ScreenOCRFixtureWindow"
      else
        fail "swift build --product ScreenOCRFixtureWindow"
      fi
    fi

    if [[ -x "scripts/build_app_bundle.sh" && -x "scripts/verify_app_bundle.sh" ]]; then
      note "Running local app bundle build and verification..."
      if scripts/build_app_bundle.sh && scripts/verify_app_bundle.sh; then
        pass "local app bundle verification"
      else
        fail "local app bundle verification"
      fi
    fi

    if [[ -x "scripts/sign_app_bundle.sh" && -x "scripts/verify_app_signature.sh" ]]; then
      note "Running local app bundle signing verification..."
      if scripts/sign_app_bundle.sh && scripts/verify_app_signature.sh; then
        pass "local app bundle signature verification"
      else
        fail "local app bundle signature verification"
      fi
    fi

    if [[ -x "scripts/final_acceptance.sh" ]]; then
      pass "final acceptance script exists"
    else
      fail "scripts/final_acceptance.sh is missing or not executable"
    fi
  else
    fail "Package.swift exists but swift is not available"
  fi
fi

if [[ -d "sidecar/screen_ocr_sidecar" ]]; then
  if [[ -x "scripts/check_ocr_env.sh" ]]; then
    if scripts/check_ocr_env.sh; then
      pass "OCR Python environment check"
    else
      fail "OCR Python environment check"
    fi
  else
    fail "sidecar exists but scripts/check_ocr_env.sh is missing or not executable"
  fi

  if [[ -x "scripts/run_python_tests.sh" ]]; then
    if scripts/run_python_tests.sh; then
      pass "Python sidecar tests"
    else
      fail "Python sidecar tests"
    fi
  else
    fail "sidecar exists but scripts/run_python_tests.sh is missing or not executable"
  fi
fi

note "Gate metrics:"
note "- required_files=${#required_files[@]}"
note "- failures=$failures"

if [[ "$failures" -eq 0 ]]; then
  note "AGENT_GATE=PASS"
else
  note "AGENT_GATE=FAIL"
  exit 1
fi
