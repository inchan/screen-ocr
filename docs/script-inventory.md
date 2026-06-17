# Script Inventory

This file keeps executable entry points discoverable and prevents helper scripts
from becoming undocumented orphans.

## Gate And Release

- [`scripts/agent_gate.sh`](../scripts/agent_gate.sh): repository gate. Checks required docs, docs links, fixture corpus, Swift/AppKit smokes, bundle/signature checks, OCR runtime, and Python tests.
- [`scripts/final_acceptance.sh`](../scripts/final_acceptance.sh): full local acceptance sequence.
- [`scripts/build_app_bundle.sh`](../scripts/build_app_bundle.sh): builds `dist/Screen OCR.app`; use `SCREEN_OCR_EMBED_RUNTIME=1` for unsigned distribution bundles.
- [`scripts/sign_app_bundle.sh`](../scripts/sign_app_bundle.sh): ad-hoc signs the bundle and nested embedded Python binaries.
- [`scripts/verify_app_bundle.sh`](../scripts/verify_app_bundle.sh): validates bundle metadata and Sparkle safety invariants.
- [`scripts/verify_app_signature.sh`](../scripts/verify_app_signature.sh): verifies ad-hoc signature integrity.
- [`scripts/verify_embedded_runtime_bundle.sh`](../scripts/verify_embedded_runtime_bundle.sh): validates embedded Python/PaddleOCR relocation and importability.
- [`scripts/run_embedded_fixture_smoke.sh`](../scripts/run_embedded_fixture_smoke.sh): runs fixture OCR from bundled resources.
- [`scripts/generate_sparkle_appcast.sh`](../scripts/generate_sparkle_appcast.sh): generates signed Sparkle appcast metadata when update signing keys are configured.

## Local Runtime And Tests

- [`scripts/setup_ocr_env.sh`](../scripts/setup_ocr_env.sh): creates `.venv-ocr`.
- [`scripts/check_ocr_env.sh`](../scripts/check_ocr_env.sh): verifies local OCR Python compatibility.
- [`scripts/verify_ocr_runtime.sh`](../scripts/verify_ocr_runtime.sh): checks Paddle/PaddleOCR runtime startup.
- [`scripts/run_python_tests.sh`](../scripts/run_python_tests.sh): runs sidecar unit tests.
- [`scripts/check_docs_links.py`](../scripts/check_docs_links.py): validates local Markdown/HTML documentation links.
- [`scripts/generate_ocr_fixtures.py`](../scripts/generate_ocr_fixtures.py): regenerates controlled OCR fixture images.
- [`scripts/run_ocr_fixture_benchmark.py`](../scripts/run_ocr_fixture_benchmark.py): measures controlled fixture OCR quality and latency.

## App Smokes

- [`scripts/run_app.sh`](../scripts/run_app.sh): starts the debug app after OCR environment checks.
- [`scripts/run_app_bundle_smoke.sh`](../scripts/run_app_bundle_smoke.sh): verifies a built bundle launches and registers a hotkey.
- [`scripts/run_screen_smoke.sh`](../scripts/run_screen_smoke.sh): noninteractive ScreenCaptureKit OCR smoke.
- [`scripts/run_hotkey_smoke.sh`](../scripts/run_hotkey_smoke.sh): end-to-end `Cmd+Shift+2` hotkey, drag, OCR, clipboard smoke.
- [`scripts/run_hotkey_reliability.sh`](../scripts/run_hotkey_reliability.sh): repeats the hotkey smoke for reliability metrics.
- [`scripts/run_legacy_capture_smoke.sh`](../scripts/run_legacy_capture_smoke.sh): forces the macOS 14 ScreenCaptureKit fallback path.
- [`scripts/run_capture_alignment_smoke.sh`](../scripts/run_capture_alignment_smoke.sh): verifies capture coordinates with color quadrant markers.
- [`scripts/run_hotkey_recorder_layout_smoke.sh`](../scripts/run_hotkey_recorder_layout_smoke.sh): compiles and runs hotkey recorder layout/default-shortcut checks.
- [`scripts/run_permission_drop_panel_smoke.sh`](../scripts/run_permission_drop_panel_smoke.sh): compiles and runs permission guide structure/focus checks.
- [`scripts/run_settings_window_layout_smoke.sh`](../scripts/run_settings_window_layout_smoke.sh): compiles and runs settings window layout checks.
- [`scripts/run_window_ordering_policy_smoke.sh`](../scripts/run_window_ordering_policy_smoke.sh): compiles and runs capture activation window-ordering checks.
- [`scripts/hotkey_recorder_layout_smoke.swift`](../scripts/hotkey_recorder_layout_smoke.swift): Swift source compiled by `run_hotkey_recorder_layout_smoke.sh`.
- [`scripts/permission_drop_panel_smoke.swift`](../scripts/permission_drop_panel_smoke.swift): Swift source compiled by `run_permission_drop_panel_smoke.sh`.
- [`scripts/settings_window_layout_smoke.swift`](../scripts/settings_window_layout_smoke.swift): Swift source compiled by `run_settings_window_layout_smoke.sh`.
- [`scripts/window_ordering_policy_smoke.swift`](../scripts/window_ordering_policy_smoke.swift): Swift source compiled by `run_window_ordering_policy_smoke.sh`.

## Manual Benchmarks And Debug Probes

These are not gate scripts. They are retained because `docs/performance-analysis.md`
and recent regressions use them as reproducible probes.

- [`scripts/bench_stage.py`](../scripts/bench_stage.py): creates/uses `fixtures/stage-bench` and measures production worker stages.
- [`scripts/bench_real_capture.py`](../scripts/bench_real_capture.py): measures production worker path on a supplied real capture.
- [`scripts/bench_image_encode.swift`](../scripts/bench_image_encode.swift): micro-benchmarks PNG/TIFF encoding.
- [`scripts/check_accuracy_guard.py`](../scripts/check_accuracy_guard.py): compares production worker OCR quality against a saved baseline.
- [`scripts/run_preprocess_benchmark.py`](../scripts/run_preprocess_benchmark.py): measures preprocessing impact on synthetic mostly-empty captures.
- [`scripts/exp_h1_rec_batch_det_threads.py`](../scripts/exp_h1_rec_batch_det_threads.py): recognizer batch size / detector thread / detector scale experiment; run `bench_stage.py` first to create stage-bench fixtures.
- [`scripts/exp_h2_tiff_vs_png_input.py`](../scripts/exp_h2_tiff_vs_png_input.py): PNG vs TIFF worker-input experiment; run `bench_stage.py` first to create stage-bench fixtures.
- [`scripts/exp_h3_adaptive_validate.py`](../scripts/exp_h3_adaptive_validate.py): adaptive detector cap validation on a supplied real capture.
- [`scripts/exp_h3_layout_debug.py`](../scripts/exp_h3_layout_debug.py): dumps OCR line geometry for layout-order debugging.
- [`scripts/exp_h4_worker_orphans.sh`](../scripts/exp_h4_worker_orphans.sh): reproduces recognizer child orphan behavior.
- [`scripts/exp_h5_quit_crash.sh`](../scripts/exp_h5_quit_crash.sh): probes quit-time Python crash reports.
- [`scripts/assert_acceptance_artifacts.rb`](../scripts/assert_acceptance_artifacts.rb): validates expected final acceptance artifacts.
- [`scripts/generate_app_icon.sh`](../scripts/generate_app_icon.sh): regenerates `Resources/AppIcon.icns` from `design/appicon.svg`.
