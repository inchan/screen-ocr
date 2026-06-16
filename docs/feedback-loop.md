# Feedback Loop

Use this log to make the agent operating system improve over time.

## Entry Template

```text
Date:
Observation:
Evidence:
Adjustment:
Status: proposed | adopted | rejected
```

## Entries

### 2026-06-05

Observation: The workspace started nearly empty while the user requested a large autonomous build process.

Evidence: `find . -maxdepth 4 -type f` showed only `.omx` runtime files and no project `AGENTS.md`, docs, code, or tests.

Adjustment: Add repo-local `AGENTS.md`, core docs, and `scripts/agent_gate.sh` before app implementation.

Status: adopted

### 2026-06-16 Documentation Link Gate

Observation: Repository cleanup can fix broken documentation links once, but
the same drift can return unless local Markdown links are part of the normal
gate.

Evidence: A local Markdown link inventory returned no missing targets, while
`scripts/agent_gate.sh` had no documentation link check to preserve that state.

Adjustment: Add `scripts/check_docs_links.sh`, connect the documentation map
through `docs/README.md`, and run the link checker from `scripts/agent_gate.sh`.

Status: adopted

### 2026-06-16 Agent Documentation Search Map

Observation: A future agent could open the documentation index and see file
names, but still miss current canonical facts such as default OCR engine,
worker-count behavior, update constraints, release branch flow, and where
historical experiment scripts moved.

Evidence: `docs/README.md` listed documents by category but did not provide a
resume path, active product facts, or searchable terms for engine, settings,
permission, release, update, and experiment work.

Adjustment: Add an Agent Quick Start and Search Map to `docs/README.md`, and
point the root `README.md` documentation section at that starting map.

Status: adopted

### 2026-06-16 Documented Script Reference Gate

Observation: The repository had many documented `scripts/...` commands, but no
automated check that those paths still existed after cleanup.

Evidence: The scripts audit found all current documented commands present, while
`scripts/agent_gate.sh` only checked selected commands manually.

Adjustment: Add `scripts/check_documented_scripts.sh` and run it from
`scripts/agent_gate.sh` and PR CI.

Status: adopted

### 2026-06-16 Experiment Harness Quarantine

Observation: Root-level `scripts/` mixed supported automation with historical
research harnesses, making cleanup audits treat useful reproduction scripts as
ambiguous dead code.

Evidence: The parallel cleanup audit found experiment files such as
`bench_stage.py`, `bench_real_capture.py`, and `exp_h*.sh` had no product
callers, while performance docs still relied on them as research evidence.

Adjustment: Move historical reproduction harnesses under
`scripts/experiments/`, document their non-gate status in
`scripts/experiments/README.md`, and make shell syntax checks recursive so
retained experiment scripts still fail fast on syntax drift.

Status: adopted

### 2026-06-16 Release Policy Enforcement

Observation: Written branch policy is not enough if GitHub Actions can publish
a release outside the `develop -> main` gate.

Evidence: The release audit found `workflow_dispatch` could publish a release
without a `main` merge and PR validation did not reject feature PRs to `main` or
release PRs missing `VERSION`.

Adjustment: Enforce PR base/head policy in the release workflow, require
`VERSION` on `develop -> main` release PRs, restrict manual dispatch to the
current `VERSION` on `main`, and validate stable semver.

Status: adopted

### 2026-06-16 Develop-First Release Flow

Observation: The project needed an explicit branch policy so ordinary feature
work does not target `main` and releases happen through a controlled
`develop -> main` PR.

Evidence: User requested that `CLAUDE.md` and `AGENTS.md` direct agents to start
work from `origin/develop`, open implementation PRs to `origin/develop`, and
release by PR from `develop` to `main`.

Adjustment: `AGENTS.md` now defines the develop-first branching, PR, and release
flow. `CLAUDE.md` mirrors the same Claude-facing defaults and points back to
`AGENTS.md` as the primary contract.

Status: adopted

### 2026-06-11 Permission Helper Needs Destination Affordance

Observation: A permission helper can expose a draggable app icon and still fail the user if it does not show the destination list clearly.

Evidence: Local install feedback reported that opening the permission popup launched System Settings and showed the app icon, but the helper did not make it clear where the icon should be dragged.

Adjustment: Add a dedicated permission helper smoke that verifies the draggable app icon, direction cue, and Screen Recording list destination hint. Keep Settings entry focused on the Capture permission controls when Screen Recording permission is missing.

Status: adopted

### 2026-06-12 Capture Overlay Should Preserve Background Settings

Observation: Activating an LSUIElement app for capture input can unintentionally promote already-open app windows, such as Settings, even when the user had put them behind another app.

Evidence: User install feedback reported that when Settings was open in the background, starting capture mode brought Settings back to the top.

Adjustment: Keep a window-ordering smoke for capture activation policy. Capture may activate the app for overlay keyboard/first-click input, but inactive normal app windows must be ordered back unless the app was already active.

Status: adopted

### 2026-06-05 Swift Gate

Observation: After Swift code was added, the original agent gate still checked only documentation.

Evidence: `swift test` was run separately and passed 2 tests, but `scripts/agent_gate.sh` did not execute it.

Adjustment: Update `scripts/agent_gate.sh` so it runs `swift test` whenever `Package.swift` exists.

Status: adopted

### 2026-06-05 Sidecar Gate

Observation: PaddleOCR requires a constrained Python version, while the default local `python3` is outside the documented supported range.

Evidence: `python3 --version` returned 3.14.5; `python3.12 --version` returned 3.12.13; `scripts/check_ocr_env.sh` passed with Python 3.12.13.

Adjustment: Add `scripts/check_ocr_env.sh`, `scripts/run_python_tests.sh`, and run both from `scripts/agent_gate.sh` when the sidecar exists.

Status: adopted

### 2026-06-05 OCR Fixture Threshold

Observation: The first real PaddleOCR fixture recognized all visible characters but dropped one Korean word-space.

Evidence: `scripts/run_ocr_fixture_benchmark.py` returned `OCR테스트\nHello 123` for expected `OCR 테스트\nHello 123`, with raw character error rate 0.0588.

Adjustment: Set the fixture-level development threshold to 0.06 while preserving the product-readiness target of median CER under 0.05 in `docs/test-plan.md`.

Status: adopted

### 2026-06-05 Hotkey Smoke

Observation: A raw synthesized drag can verify the real hotkey path, but the fixture window must be guaranteed visible or the test can capture the wrong app behind it.

Evidence: The first event-driven run reached `capture_ocr_finished` but OCR text came from another app. The captured image showed the intended coordinates were obscured. After making the fixture window floating/frontmost, `scripts/run_hotkey_smoke.sh` returned `status: passed` with clipboard text `OCR 테스트\nHello 123`.

Adjustment: Keep the fixture smoke window frontmost and use `scripts/run_hotkey_smoke.sh` as the repeatable local end-to-end hotkey verifier.

Status: adopted

### 2026-06-05 Release Bundle Gate

Observation: Debug builds passed while the release app bundle build surfaced a missing `return` in the app root resolver.

Evidence: `scripts/build_app_bundle.sh` failed during `swift build -c release --product ScreenOCRApp` with `missing return in instance method expected to return 'URL'`.

Adjustment: Add local app bundle creation and verification to `scripts/agent_gate.sh` so release-only compile failures and bundle metadata regressions are caught by the normal gate.

Status: adopted

### 2026-06-05 Fixture Corpus Gate

Observation: A single OCR fixture was too weak to support the user's requirement for quantified validation data.

Evidence: `fixtures/ocr/manifest.json` contained 1 fixture before the corpus expansion. After adding 20 controlled fixtures, `scripts/run_ocr_fixture_benchmark.py` reported 20/20 passed, median CER 0.0, mean CER 0.0094, max CER 0.0588, and median warm OCR 286.755 ms.

Adjustment: Expand the controlled corpus to 20 generated fixtures, add aggregate CER metrics to the benchmark report, and make `scripts/agent_gate.sh` verify fixture count plus generated image existence.

Status: adopted

### 2026-06-05 Hotkey Reliability Gate

Observation: Single hotkey smoke passes prove the workflow can work, but they do not quantify repeat reliability.

Evidence: `scripts/run_hotkey_reliability.sh` ran 20 end-to-end hotkey cycles and reported 20/20 passed, success rate 1.0, median run elapsed 6071 ms, and minimum success-rate gate 0.95.

Adjustment: Add a repeated reliability runner that reuses `scripts/run_hotkey_smoke.sh`, skips redundant rebuilds during loops, and writes `artifacts/hotkey/latest-reliability.json`.

Status: adopted

### 2026-06-05 Local Signature Gate

Observation: A release executable can be linker ad-hoc signed while the `.app` bundle resource seal is still invalid.

Evidence: `codesign --verify --deep --strict --verbose=2 "dist/Screen OCR.app"` initially failed with `code has no resources but signature indicates they must be present`. After `scripts/sign_app_bundle.sh`, `scripts/verify_app_signature.sh` passed strict verification.

Adjustment: Add ad-hoc bundle signing and strict signature verification to the normal agent gate while keeping Developer ID notarization as an explicit credential-gated release step.

Status: adopted

### 2026-06-05 Embedded Runtime Boundary

Observation: Copying `.venv-ocr` into the app bundle is not enough because the venv contains absolute symlinks to Homebrew Python, which break strict bundle verification and are not a standalone interpreter.

Evidence: The first embedded bundle signing attempt failed strict verification with `invalid destination for symbolic link in bundle`. After replacing `python`, `python3`, and `python3.12` with wrapper executables that add embedded site-packages to `PYTHONPATH`, strict verification passed and `scripts/run_embedded_fixture_smoke.sh` copied `OCR테스트\nHello 123` from bundle resources.

Adjustment: Treat this as an embedded OCR-resource bundle, not a fully standalone Python distribution. Preserve the fully standalone Python framework bundle as a separate release-engineering gap.

Status: adopted

### 2026-06-11 Release Trigger Must Follow PR Merge

Observation: Pushing a release tag from a feature branch can publish a release before the PR is merged, which leaves the release target outside the main branch until a later merge.

Evidence: `v0.0.1` was created from `harden-ocr-worker-roundtrip` before PR #1 was merged. The release succeeded, but the healthier project flow is PR validation first, then merge, then release from `main`.

Adjustment: The unsigned release workflow now treats pull requests as validation only. A normal release is triggered by merging a `VERSION` change to `main`; manual dispatch remains available for exceptional rebuilds.

Status: adopted

### 2026-06-11 Embedded Runtime Must Prove Interpreter Portability

Observation: An embedded OCR bundle can pass module import on the build machine while still pointing its Python wrapper at `/opt/homebrew` or another builder-local interpreter path.

Evidence: The pre-existing embedded runtime wrapper executed `/opt/homebrew/opt/python@3.12/bin/python3.12`. After updating `scripts/build_app_bundle.sh`, the bundle includes `Contents/Frameworks/Python.framework`, patches the Python launcher dependency to `@executable_path/../Python`, and `scripts/verify_embedded_runtime_bundle.sh` rejects wrappers or linked libraries that point at build-machine Python paths.

Adjustment: Embedded runtime verification must check both importability and portability: no build-machine Python path in the wrapper or Python launcher linkage.

Status: adopted

### 2026-06-05 Signature Preservation After OCR

Observation: Even after a bundle signs cleanly, running embedded Python can mutate sealed resources by creating `__pycache__` files inside the app bundle.

Evidence: After `scripts/run_embedded_fixture_smoke.sh`, `scripts/verify_app_signature.sh` reported added `__pycache__/*.pyc` files under `Contents/Resources`, invalidating the resource seal. After setting `PYTHONDONTWRITEBYTECODE=1` in both the Swift sidecar process environment and embedded Python wrappers, the sequence `run_embedded_fixture_smoke.sh` then `verify_app_signature.sh` passed.

Adjustment: Disable bytecode writes for OCR subprocesses and embedded wrappers; build embedded resources with `--delete-excluded` so stale pycache files are removed before signing.

Status: adopted

### 2026-06-05 Legacy Capture Fallback

Observation: The package target was macOS 14, but the first capture implementation only used the macOS 15.2 direct rect API.

Evidence: `docs/validation-report.md` still listed macOS 14 fallback as missing. SDK headers show `SCScreenshotManager.captureImage(contentFilter:configuration:)` and `SCStreamConfiguration.sourceRect` are available on macOS 14. `SCREEN_OCR_FORCE_LEGACY_CAPTURE=1 scripts/run_hotkey_smoke.sh` passed with clipboard text `OCR 테스트\nHello 123`.

Adjustment: Add a ScreenCaptureKit display-filter/sourceRect fallback, force-test it through `scripts/run_legacy_capture_smoke.sh`, and update docs to distinguish forced local validation from a real macOS 14 host smoke.

Status: adopted

### 2026-06-05 OCR Performance Baseline Preservation

Observation: OCR optimization claims are weak unless the exact pre-change benchmark artifact is preserved before `artifacts/ocr/latest-benchmark.json` is overwritten.

Evidence: The H1 detector-limit optimization used `artifacts/ocr/baseline-ocr-latency-20260605T060041Z.json` as the pre-change baseline and `artifacts/ocr/final-evaluator-benchmark-20260605T061018Z.json` as the final evaluator evidence, showing median warm OCR improved from 299.21 ms to 281.285 ms.

Adjustment: For future performance work, copy the fresh baseline artifact before changing code and record both artifact paths plus the improvement calculation in `docs/performance-analysis.md` and `docs/validation-report.md`.

Status: adopted

### 2026-06-05 Hotkey Timing Smoke Isolation

Observation: Stage timing can appear missing if an older bundled `ScreenOCRApp` remains running and handles the global hotkey instead of the newly built debug app.

Evidence: The first instrumented `scripts/run_hotkey_smoke.sh` run passed but `artifacts/app/latest-status.json` had no timing fields. `pgrep -af "ScreenOCR|Screen OCR"` showed `dist/Screen OCR.app/Contents/MacOS/ScreenOCRApp` was still running. After killing that bundle path in the smoke setup, the next runs recorded `capture_elapsed_ms`, `ocr_elapsed_ms`, `clipboard_elapsed_ms`, and `total_elapsed_ms`.

Adjustment: Make `scripts/run_hotkey_smoke.sh` terminate the local dist bundle executable before launching the debug app, and copy app-internal timing fields into the smoke report.

Status: adopted

### 2026-06-05 Persistent Worker Memory Gate

Observation: A persistent OCR worker can make request latency fast enough for sub-second clipboard feasibility, but it changes the product cost from per-request latency to resident memory.

Evidence: The persistent JSONL worker spike returned post-ready OCR requests in 268.77 ms median, but measured about 854 MB RSS after loading PaddleOCR.

Adjustment: Future persistent-worker implementation must report both request latency and RSS in its smoke artifact before being accepted as a product performance improvement.

Status: adopted

### 2026-06-05 Post-Selection Timing Boundary

Observation: A hotkey smoke `capture_elapsed_ms` number includes overlay wait and drag time, so it cannot prove the user's "region selection complete to clipboard" latency target by itself.

Evidence: The first persistent-worker hotkey smoke reported OCR stage 352 ms, but capture elapsed 1084 ms still included scripted selection delay. After splitting selection, ScreenCaptureKit capture, PNG write, and post-selection-to-clipboard timings, the final evaluator `scripts/run_hotkey_smoke.sh` reported 57 ms image capture after selection, 353 ms OCR, 0 ms clipboard, and 410 ms post-selection-to-clipboard.

Adjustment: Keep `post_selection_to_clipboard_elapsed_ms` as the acceptance metric for this performance goal, while preserving full capture/selection timings for debugging.

Status: adopted

### 2026-06-05 OCR Runtime Python For Preprocessing Tests

Observation: Once preprocessing reads PNG pixels with Pillow, Python sidecar tests need the OCR runtime environment, not the bare system `python3.12`.

Evidence: After adding `screen_ocr_sidecar.preprocess`, `scripts/run_python_tests.sh` failed with `ModuleNotFoundError: No module named 'PIL'` under the system Python. The OCR virtual environment already had Pillow because PaddleOCR depends on it. Updating the test runner to prefer `.venv-ocr/bin/python` made the 13 Python tests pass.

Adjustment: Keep `scripts/run_python_tests.sh` aligned with the actual OCR runtime unless a dependency-free preprocessing path is introduced.

Status: adopted

### 2026-06-05 Auto-Trim Needs OCR-Aware Padding

Observation: A crop that is visually correct can still be too tight for PaddleOCR and cause line fragmentation or slower recognition.

Evidence: The first large-empty auto-trim used 32 px padding and reduced the image to 267x158, but OCR latency regressed from 385.425 ms to 444.606 ms and text split into `OCR`, `테스트`, `Hello`, `123`. A padding probe showed 64 px preserved `OCR테스트\nHello 123` and improved the benchmark to 397.901 ms -> 267.591 ms.

Adjustment: Default auto-trim padding is 64 px, and future preprocessing changes must verify OCR text plus latency, not only crop size.

Status: adopted

### 2026-06-08 Swift Toolchain Absent In Web Container

Observation: The Claude Code web execution container is Linux without `swift`, so `swift test`, `swift build`, and the Swift-dependent half of `scripts/agent_gate.sh` cannot run there. Swift changes made in a web session are unverified until a macOS host runs them.

Evidence: `command -v swift` returned nothing in the container for the D-0017 cycle; only `python3`/`python3.12`/`ruby` were available. Python sidecar tests passed (18/18), but the Swift timeout/buffered-reader changes could only be syntax-reviewed, not compiled. Separately, `scripts/run_python_tests.sh` defaulted to `python3.12`, which exists in this container but lacked Pillow, while the bare fallback needed to be `python3`.

Adjustment: (1) `scripts/run_python_tests.sh` now falls back to `python3` when `.venv-ocr` and `python3.12` are absent, so sidecar tests run in the web container. (2) Validation reports written from a web session must explicitly separate "verified here" from "needs a macOS host," and must not claim Swift gates pass without a macOS run.

Status: adopted

### 2026-06-11 Engine Comparison Needs Ground Truth

Observation: A single real screenshot can strongly favor one OCR engine on speed and text structure, but it cannot justify a default-engine change without exact expected text.

Evidence: On the user-provided 5044x2130 screenshot, Apple Vision returned 30 lines in 4278 ms while PaddleOCR returned 110 fragmented lines in 7478 ms after a 5957 ms worker init. The result favors Vision for that image. The same comparison cycle still found Vision-specific substitutions on `fixtures/stage-bench/medium-window.png` (`Performance` -> `Pertormance`, `fans` -> `tans`, `def` -> `det`, `five` -> `tive`), and the provided screenshot has no exact transcript for CER.

Adjustment: Keep qualitative real-screenshot comparisons in `docs/performance-analysis.md`, but require a representative real-screen corpus with exact expected text before changing the default OCR engine.

Status: adopted

### 2026-06-11 Settings UI Needs AppKit Harness

Observation: Settings UI changes can be compile-verified through `swift test`/`agent_gate`, but the project has no automated way to assert that a specific AppKit settings row is visible/enabled/disabled after launch.

Evidence: The Paddle worker-count setting cycle verified the underlying worker environment behavior and built `ScreenOCRApp`, but `docs/validation-report.md` still had to list screenshot-based settings-window verification as a known gap.

Adjustment: Add a lightweight settings-window smoke harness before relying on visual settings changes as fully verified. Adopted slices: `scripts/run_hotkey_recorder_layout_smoke.sh` verifies the custom hotkey recorder baselines; `scripts/run_settings_window_layout_smoke.sh` constructs the full settings window and verifies sidebar navigation plus PaddleOCR section visibility.

Status: adopted

### 2026-06-12 Updater Terms Need SDK Semantics Check

Observation: Product wording such as "automatic download" can hide SDK-specific
behavior. In Sparkle 2, automatic downloading is coupled to automatic
installation on app termination, which conflicts with Screen OCR's explicit
install/restart contract.

Evidence: `SPUUpdaterDelegate.h` documents that Sparkle always attempts to
install an automatically downloaded update when the app terminates, and
`SPUUpdater.h` describes `automaticallyDownloadsUpdates` as automatic
download/install behavior. The implementation was corrected to keep
`automaticallyDownloadsUpdates=false` and `SUAllowsAutomaticUpdates=false`.

Adjustment: Before encoding updater or installer decisions, confirm the SDK's
exact semantics for "automatic" operations and automate the safety invariant
when possible. `scripts/verify_app_bundle.sh` now rejects Sparkle-enabled
bundles unless silent automatic update installation remains disabled.

Status: adopted
