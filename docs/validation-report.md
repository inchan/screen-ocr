# Validation Report

Last updated: 2026-06-08.

## 2026-06-08 Cycle: Worker round-trip hardening (timeout, slim payload, opt-in filter)

Scope: D-0017 — buffered worker reads + hard request timeout (Swift), slim worker payload and opt-in low-score line filter (Python).

Verified in this environment (Linux web container; `swift` is not installed here):
- Python sidecar tests: `scripts/run_python_tests.sh` → 18 tests OK (5 new: min-score filter on/default, slim `{text, score}` worker payload, env-driven filter, invalid-env fallback). Baseline before this cycle was 13 tests.
- `python3 -m py_compile` of `worker.py` and `ocr.py`: OK.
- Defaults preserved: with `SCREEN_OCR_MIN_LINE_SCORE` unset, recognized text and line count are unchanged (covered by `test_recognize_image_keeps_all_lines_when_min_score_is_default` and the unchanged existing contract tests).
- Test-runner portability fix: `scripts/run_python_tests.sh` now falls back to `python3` when neither `.venv-ocr` nor `python3.12` is present, so sidecar tests run in the web container.

Not verified in this environment (requires a macOS host with the Swift toolchain):
- `swift test` for `ScreenOCRCoreTests`, including the new `testPersistentPythonSidecarOCRTimesOutWhenWorkerHangs` (R1) and the existing persistent-worker tests that also cover the slim `{text, score}` payload shape.
- `swift build` for `ScreenOCRApp`, `ScreenOCRSmoke`, `ScreenOCRFixtureWindow`.
- The Swift-dependent portions of `scripts/agent_gate.sh` (swift test/build, `.app` bundle build/sign) and `scripts/run_ocr_fixture_benchmark.py` against the real PaddleOCR runtime.

Next verification step (macOS host): run `swift test`, `swift build --product ScreenOCRApp`, `scripts/agent_gate.sh`, and a 7-repeat `scripts/run_ocr_fixture_benchmark.py` to confirm 20/20 and that warm median stays at or below the recorded 281.285 ms.

## Current Claim

The repository has an autonomous operating-system layer, a tested core OCR pipeline, a local PaddleOCR sidecar, a local `.app` bundle build, and a macOS menu bar utility whose scripted end-to-end smoke verifies `Cmd+Shift+0` -> drag selection -> ScreenCaptureKit capture -> PaddleOCR -> clipboard. On successful clipboard copy, the app now shows a transient `📋 Copied to clipboard` toast anchored below the menu bar item.

## Evidence To Collect

- Required files exist.
- Required sections exist in `AGENTS.md`.
- Research, decisions, spec, test plan, roadmap, debugging, and feedback docs exist.
- Completion audit maps original requirements to evidence.
- The local gate script passes.
- The final acceptance script passes.
- Swift core tests pass.
- Python sidecar tests pass.
- The macOS app target builds.
- The local `.app` bundle builds and has menu-bar utility metadata.
- The local `.app` bundle can be ad-hoc signed and strict signature verification passes.
- The `.app` bundle can be built with embedded OCR packages, sidecar source, and fixtures, then run fixture OCR from bundle resources.
- The app launches without immediate crash.
- The local `.app` bundle launch path registers the hotkey when run outside the repository root.
- The real hotkey-to-clipboard workflow passes on the local macOS host after permissions are granted.
- Clipboard-success toast message and menu-bar-anchored placement logic are covered by Swift tests.
- The real hotkey-to-clipboard workflow has a repeated success-rate report.
- The macOS 14 ScreenCaptureKit filter/sourceRect fallback path can be forced and passes hotkey-to-clipboard smoke on the local host.
- The controlled OCR fixture corpus has at least 20 generated images and aggregate CER/latency metrics.

## Latest Result

Clipboard-success toast implementation passed on 2026-06-05:
- implementation: the menu bar app converts the `NSStatusItem` button frame to screen coordinates and shows a nonactivating borderless toast below that anchor after successful clipboard writes
- toast message: `📋 Copied to clipboard`
- Swift evidence: `swift test` executed 17 tests with 0 failures, including `testClipboardToastMessageStartsWithEmoji` and `testClipboardToastFrameIsBelowMenuBarAnchorAndClampedToVisibleScreen`
- hotkey smoke evidence: `scripts/run_hotkey_smoke.sh` passed after the toast change with OCR text `OCR테스트\nHello 123`, OCR stage 355 ms, clipboard write 0 ms, and region-selection-complete to clipboard 416 ms
- gate evidence: `scripts/agent_gate.sh` passed after the toast change with `AGENT_GATE=PASS`

Persistent OCR worker implementation passed the local short-text post-selection latency target after the app began prewarming PaddleOCR at launch. The earlier standalone OCR detector-limit optimization also remains accepted.

Optimization summary:
- baseline artifact: `artifacts/ocr/baseline-ocr-latency-20260605T060041Z.json`
- optimized artifact: `artifacts/ocr/final-evaluator-benchmark-20260605T061018Z.json`
- baseline median warm OCR: 299.21 ms over 7 repeats per fixture
- optimized median warm OCR: 281.285 ms over 7 repeats per fixture
- measured improvement: 17.925 ms / 5.991%
- quality: 20/20 fixtures passed, median CER 0.0, mean CER improved from 0.0094 to 0.0072, max CER stayed 0.0588
- evaluator: `SCREEN_OCR_BENCHMARK_REPEATS=7 scripts/run_ocr_fixture_benchmark.py && scripts/run_python_tests.sh && scripts/agent_gate.sh` passed on 2026-06-05
- behavior test: `scripts/run_python_tests.sh` passed 10 unittest cases after adding detector-limit and persistent-worker contract tests

Hotkey-to-clipboard stage timing is now instrumented.

Stage timing summary from three scripted hotkey smoke samples on 2026-06-05:
- sample artifacts: `artifacts/hotkey/latest-hotkey-smoke-timing-sample-1.json`, `artifacts/hotkey/latest-hotkey-smoke-timing-sample-2.json`, `artifacts/hotkey/latest-hotkey-smoke-timing-sample-3.json`
- median smoke harness elapsed: 6669 ms
- median app internal total: 5701 ms
- median capture/selection/image availability: 1079 ms
- median OCR subprocess: 4617 ms
- median clipboard write: 0 ms
- conclusion: sub-second end-to-end is not plausible through detector tuning alone; the dominant target is replacing per-request Python/PaddleOCR startup with a persistent preloaded OCR worker.

Persistent OCR worker research completed on 2026-06-05:
- one-shot Python sidecar CLI median: 3641.83 ms over 3 requests
- persistent JSONL worker one-time ready latency: 4801.60 ms
- persistent JSONL worker post-ready request median: 268.77 ms over 7 requests
- persistent worker internal OCR median: 268.65 ms over 7 requests
- persistent worker RSS after ready: 854.0 MB
- ScreenCaptureKit capture plus PNG write median: 26 ms over 5 noninteractive samples
- HPI probe: `enable_hpi=True` failed because `ultra-infer` is not installed
- CPU tuning probe: `cpu_threads=4` measured 267.74 ms warm median, a small secondary improvement compared with process/model reuse

Persistent OCR worker implementation smoke passed on 2026-06-05:
- app path: `ScreenOCRApp` starts `screen_ocr_sidecar.worker` at launch and reuses it for hotkey OCR
- smoke artifact: `artifacts/hotkey/latest-hotkey-smoke.json`
- worker ready elapsed before capture: 4459 ms
- worker-reported init elapsed: 4409.577 ms
- worker RSS after ready: 845.4 MB
- scripted selection UI elapsed: 1028 ms
- image capture after selection: 57 ms, split into 50 ms ScreenCaptureKit capture and 7 ms PNG write
- OCR stage through the persistent worker: 353 ms
- clipboard write: 0 ms
- region-selection-complete to clipboard: 410 ms
- improvement against the prior hotkey OCR subprocess median: 4617 ms -> 353 ms, 4264 ms faster / 92.4% reduction
- target result: 410 ms is below the 700 ms target for the controlled two-line fixture

OCR preprocessing implementation passed its synthetic large-empty benchmark on 2026-06-05:
- benchmark artifact: `artifacts/preprocess/latest-preprocess-benchmark.json`
- test image: 2400x1600 mostly-empty region with the existing two-line OCR fixture centered
- no-preprocessing request median: 397.901 ms
- auto-trim request median: 267.591 ms
- improvement: 130.31 ms / 32.749%
- preprocessing elapsed in latest sample: 28 ms
- input dimensions reduced from 2400x1600 to 331x222
- recognized text preserved: `OCR테스트\nHello 123`
- small hotkey smoke after preprocessing remained below target: `post_selection_to_clipboard_elapsed_ms=483`, `preprocess_status=skipped_small`, OCR text `OCR테스트\nHello 123`

`scripts/final_acceptance.sh` passes the local MVP acceptance gate. It runs the local agent gate, real screen smoke, normal hotkey smoke, forced macOS 14 capture fallback smoke, signed bundle launch smoke, embedded OCR-resource bundle fixture smoke, post-smoke signature verification, and quantitative artifact assertions.

Final acceptance summary:
- latest report: `artifacts/acceptance/latest-final-acceptance.json`
- screen smoke: passed
- normal hotkey smoke: passed
- legacy capture smoke: passed
- signed bundle launch smoke: passed
- embedded fixture smoke: passed
- benchmark artifact: 20/20 fixtures passed, median CER 0.0, mean CER 0.0094, median warm OCR 286.755 ms
- reliability artifact: 20 runs, success rate 1.0, median run elapsed 6071 ms

`scripts/agent_gate.sh` also passed on 2026-06-05 inside the final acceptance run.

Result summary:
- required files: 11/11 present
- required section/content checks: pass
- failures: 0
- gate result: `AGENT_GATE=PASS`
- bundle gate: `scripts/build_app_bundle.sh` + `scripts/verify_app_bundle.sh` pass inside `scripts/agent_gate.sh`
- signing gate: `scripts/sign_app_bundle.sh` + `scripts/verify_app_signature.sh` pass inside `scripts/agent_gate.sh`
- embedded OCR-resource smoke: `SCREEN_OCR_EMBED_RUNTIME=1 scripts/build_app_bundle.sh` + `scripts/run_embedded_fixture_smoke.sh` pass
- fixture corpus gate: 20 fixture records and 20 generated images verified inside `scripts/agent_gate.sh`
- reliability report: `scripts/run_hotkey_reliability.sh` passed 20/20 runs with success rate 1.0
- legacy capture smoke: `scripts/run_legacy_capture_smoke.sh` passes with `SCREEN_OCR_FORCE_LEGACY_CAPTURE=1`

Research integration summary:
- PaddleOCR local CPU sidecar path documented.
- Apple ScreenCaptureKit, menu bar, pasteboard, shortcut, permission, and packaging constraints documented.
- Filtered-out paths documented: hosted OCR, `paddleocr[all]`, global key monitors, event taps, and deprecated capture APIs.

Swift core result:
- `swift test` passed on 2026-06-05.
- Test count: 17 XCTest cases.
- Covered behaviors: successful fake capture/OCR/clipboard pipeline, clipboard-success toast message and menu-bar-anchored frame calculation, post-selection timing reporting, capture/OCR/clipboard failure reporting, Swift-to-Python sidecar JSON parsing, persistent Swift-to-Python worker JSONL parsing, persistent worker error mapping, Swift-to-Python process failure reporting, debug timing manifest persistence, and screen selection geometry.

macOS app scaffold result:
- `swift build --product ScreenOCRApp` passed on 2026-06-05.
- `scripts/build_app_bundle.sh` produced `dist/Screen OCR.app` on 2026-06-05.
- `scripts/verify_app_bundle.sh` passed on 2026-06-05. It verified `CFBundlePackageType=APPL`, `CFBundleExecutable=ScreenOCRApp`, `CFBundleName=Screen OCR`, `LSUIElement=true`, and the bundled project-root resource pointing to the local OCR runtime.
- `scripts/sign_app_bundle.sh` signed `dist/Screen OCR.app` with an ad-hoc identity on 2026-06-05.
- `scripts/verify_app_signature.sh` passed on 2026-06-05. It verified `codesign --verify --deep --strict`, `Signature=adhoc`, and sealed bundle resources.
- `scripts/run_app_bundle_smoke.sh` passes. It launches the signed bundle executable from `/` and observes `hotkey_registered` diagnostics written to the repository artifacts path.
- Embedded OCR-resource bundle: `SCREEN_OCR_EMBED_RUNTIME=1 scripts/build_app_bundle.sh` produced an app bundle with `Contents/Resources/python-runtime`, `Contents/Resources/sidecar`, and `Contents/Resources/fixtures` on 2026-06-05.
- `scripts/verify_embedded_runtime_bundle.sh` passed on 2026-06-05. It verified the embedded OCR environment wrapper, PaddleOCR modules, sidecar module, and fixture resource.
- `scripts/run_embedded_fixture_smoke.sh` passes. It launches the signed bundle from `/` with `SCREEN_OCR_RUN_FIXTURE_ON_LAUNCH=1`, without `SCREEN_OCR_PROJECT_ROOT`, and verifies fixture OCR clipboard text `OCR테스트\nHello 123`.
- `scripts/verify_app_signature.sh` passed after the embedded fixture OCR smoke, proving the bundle did not create `__pycache__` or otherwise mutate sealed resources during OCR execution.
- Implemented host slice: menu bar status item, `Cmd+Shift+0` registration via `RegisterEventHotKey`, Screen Recording permission preflight/request, transparent selection overlay, ScreenCaptureKit image capture through the direct macOS 15.2+ path and the macOS 14+ filter/sourceRect fallback, fixture OCR action, and pasteboard text writer.
- Launch smoke: `.build/debug/ScreenOCRApp` stayed alive for 3 seconds without immediate crash; the test process was then terminated.
- Hotkey registration smoke: `artifacts/app/latest-status.json` recorded `status: hotkey_registered` and `shortcut: Cmd+Shift+0` at 2026-06-05T03:20:59Z.
- Noninteractive real screen smoke: `scripts/run_screen_smoke.sh` passed on 2026-06-05. It rendered a known text window, captured it with ScreenCaptureKit, ran PaddleOCR, wrote OCR text to clipboard, and saved `artifacts/smoke/latest-screen-smoke.json`.
- Latest smoke result: actual text `OCR테스트\nHello 123`, line count 2, image `artifacts/smoke/screen-smoke.png`; elapsed time is recorded in `artifacts/smoke/latest-screen-smoke.json`.
- Scripted hotkey smoke: `scripts/run_hotkey_smoke.sh` passed on 2026-06-05. It launched the app and fixture window, synthesized `Cmd+Shift+0`, dragged the fixture region, waited for `capture_ocr_finished`, verified clipboard text, and recorded app-internal stage timings.
- Latest instrumented hotkey smoke result: actual text `OCR테스트\nHello 123`, smoke elapsed 4208 ms, app total 1438 ms, selection 1028 ms, image capture after selection 57 ms, OCR worker 353 ms, clipboard 0 ms, region-selection-complete to clipboard 410 ms, worker ready 4459 ms before capture, worker RSS 845.4 MB.
- Hotkey reliability smoke: `scripts/run_hotkey_reliability.sh` passed on 2026-06-05 at 2026-06-05T03:51:56Z.
- Reliability result: 20/20 passed, 0 failed, 0 skipped, success rate 1.0, minimum success-rate gate 0.95, median run elapsed 6071 ms, total elapsed 140946 ms, report `artifacts/hotkey/latest-reliability.json`.
- Legacy capture smoke: `scripts/run_legacy_capture_smoke.sh` passes with forced ScreenCaptureKit display-filter/sourceRect capture. Result text is `OCR 테스트\nHello 123`; elapsed time and captured image path are recorded in `artifacts/hotkey/latest-legacy-capture-smoke.json`.

Python sidecar result:
- `scripts/check_ocr_env.sh` passed with Python 3.12.13 on 2026-06-05.
- `scripts/run_python_tests.sh` passed on 2026-06-05.
- Test count: 13 unittest cases.
- Covered behaviors: PaddleOCR-style result normalization, injected fake OCR image recognition, default detector-limit forwarding, persistent worker request handling with a reused OCR instance, persistent worker structured request errors, preprocessing disable baseline mode, large mostly-empty auto-trim, small image fallback, empty-line text cleanup, array-like OCR box JSON conversion, and CER metric calculation.

Runtime setup result:
- `scripts/setup_ocr_env.sh` passed on 2026-06-05.
- `scripts/verify_ocr_runtime.sh` passed on 2026-06-05.
- Installed runtime: `paddlepaddle==3.3.0`, `paddleocr==3.6.0`.
- Runtime check: `paddle.utils.run_check()` reported PaddlePaddle works on 1 CPU.
- OCR model cache observed: `.venv-ocr` 938 MB, `PP-OCRv5_mobile_det` downloaded, `korean_PP-OCRv5_mobile_rec` downloaded. Earlier server-det cache also exists from the first verification attempt and is not part of the configured default.

Controlled OCR fixture benchmark:
- Fixture corpus: 20 generated Korean/English UI-style images under `fixtures/ocr/`.
- Latest benchmark report: `artifacts/ocr/latest-benchmark.json` at 2026-06-05T06:10:18Z.
- Latest run: 20/20 fixtures passed.
- PaddleOCR initialization elapsed: 4391.28 ms.
- Warm OCR repeat count: 7 per fixture.
- Corpus median warm OCR elapsed: 281.285 ms.
- Median character error rate: 0.0.
- Mean character error rate: 0.0072.
- Max observed character error rate: 0.0588.
- Optimization baseline for this cycle was 299.21 ms median warm OCR, so the current detector-limit default improves the measured median by 17.925 ms / 5.991%.
- Known OCR imperfections in the latest passing fixtures: Korean word-space drops in `mixed-ko-en-simple`, missing closing parenthesis in `code-snippet`, and Korean word-space drop in `punctuation`.

## Known Gaps

- The hotkey workflow has 20/20 scripted reliability on a controlled fixture; product-readiness still needs representative real-world regions and app/window arrangements.
- macOS 14 fallback is implemented and forced-smoke verified on the local host; it still needs a real macOS 14 host smoke before release.
- Local development `.app` bundling, ad-hoc signing, and embedded OCR-resource bundling are implemented; Developer ID signing, notarization, stapling, and a fully standalone Python framework/interpreter bundle are not implemented.
- Product-readiness still needs real representative screen crops; the current 20-image corpus is controlled/synthetic and useful for regression, not a substitute for real app screenshots.
- Hotkey smoke now records selection, image capture, OCR worker, clipboard, post-selection-to-clipboard, worker startup, and worker RSS timings. The remaining performance gap is representative real-screen validation beyond the controlled two-line fixture.
- Local default `python3` is 3.14.5; scripts intentionally use `python3.12` for the PaddleOCR runtime.
