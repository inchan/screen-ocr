# Validation Report

Last updated: 2026-06-16.

## 2026-06-16 Cycle: Agent documentation search map

Scope: Improve documentation discoverability for future agents by making
`docs/README.md` a practical starting map, not only a category list.

Verified on the local macOS host:
- `scripts/check_docs_links.sh` passed with `DOC_LINKS=PASS checked=21`.
- `scripts/check_documented_scripts.sh` passed with
  `DOC_SCRIPT_REFS=PASS checked=29`.

Implementation evidence:
- `docs/README.md` now starts with an Agent Quick Start, current canonical
  facts, and a Search Map for OCR engine, worker count, settings, permission,
  release, update, performance, and capture topics.
- Root `README.md` now points agents to `docs/README.md` for current facts and
  search keywords, not only the documentation list.
- `docs/feedback-loop.md` records the discoverability gap and adopted fix.

Known verification gap:
- This is a documentation-only discoverability change; no product behavior was
  changed.

## 2026-06-16 Cycle: Experiment harness quarantine

Scope: Keep research reproduction artifacts, but separate them from supported
root-level automation so cleanup audits and release gates can distinguish
active scripts from historical experiments.

Verified on the local macOS host:
- `scripts/check_docs_links.sh` passed with `DOC_LINKS=PASS checked=21`.
- `scripts/check_documented_scripts.sh` passed with
  `DOC_SCRIPT_REFS=PASS checked=29`.
- Recursive shell syntax sweep over `scripts/**/*.sh` passed with `bash -n`.
- Workflow YAML parse passed with
  `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/unsigned-release.yml")'`.
- Moved Python experiment scripts passed syntax compilation with
  `python3 -m py_compile scripts/experiments/*.py`.
- Full agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`,
  including documentation link checks, documented script reference checks,
  recursive shell syntax checks, 28 Swift tests, AppKit smokes, bundle
  verification, signature verification, OCR environment check, and 26 Python
  sidecar tests.

Implementation evidence:
- Historical experiment and benchmark scripts now live under
  `scripts/experiments/` with `scripts/experiments/README.md` documenting their
  non-gate, reproduction-only status.
- Moved scripts now compute the repository root from their deeper location, and
  their usage strings/reference comments point at `scripts/experiments/...`.
- `docs/README.md` links the experiment harness inventory, and
  `docs/performance-analysis.md` points H6 reproduction evidence to the new
  `bench_real_capture.py` location.
- `scripts/agent_gate.sh` and `.github/workflows/unsigned-release.yml` now run
  shell syntax checks recursively so experiment `.sh` files remain syntactically
  valid even though they are not release automation.
- Removed generated `__pycache__` directories from `scripts/`.

Known verification gap:
- Experiment harnesses were syntax/path checked, not re-run end to end, because
  several require historical real captures or intentionally exercise disruptive
  worker-shutdown scenarios.

## 2026-06-16 Cycle: Parallel repository audit and release-policy cleanup

Scope: Run a parallel, file-by-file audit across documentation, Swift app/core,
Python OCR/fixtures, scripts, release automation, and reference graph. Apply
only safe cleanup that does not change product behavior.

Parallel lanes:
- Documentation lane: no broken local Markdown links found; flagged stale
  `docs/completion-audit.md` date and Paddle-only wording in
  `docs/autonomous-system.md`.
- Swift lane: confirmed active menu bar, hotkey, capture, OCR engine, worker
  count, and updater paths; flagged unused app helpers and stale hardcoded
  shortcut/status strings.
- Python/OCR lane: confirmed 20 manifest fixtures map to 20 PNGs; flagged a
  stale test reference to `mixed-ko-en.png` and experimental scripts with no
  production callers.
- Scripts lane: confirmed documented commands exist; recommended shell syntax
  and documented-script reference checks in the normal gate.
- Release lane: found that manual workflow dispatch could publish outside the
  documented `develop -> main` gate and that PR validation did not enforce
  release-PR shape.
- Reference graph lane: confirmed `design/icons.html` as the only high-confidence
  delete; classified experiment scripts as research artifacts rather than safe
  deletion.

Verified on the local macOS host:
- `scripts/check_docs_links.sh` passed with `DOC_LINKS=PASS checked=20`.
- `scripts/check_documented_scripts.sh` passed with
  `DOC_SCRIPT_REFS=PASS checked=28`.
- Shell syntax sweep over `scripts/*.sh` passed with `bash -n`.
- Workflow YAML parse passed with
  `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/unsigned-release.yml")'`.
- `swift test` passed 28 Swift tests.
- `swift build --product ScreenOCRApp` passed. The remaining
  `CGDisplayStream` deprecation warning is the documented macOS 14 permission
  compatibility probe.
- `scripts/run_python_tests.sh` passed 26 Python sidecar tests.
- Correction loop: the first full `scripts/agent_gate.sh` run failed because
  `scripts/check_documented_scripts.sh` treated placeholder prose such as
  `scripts/...` as a real path. The checker now skips placeholders.
- Full agent gate: final `scripts/agent_gate.sh` passed with
  `AGENT_GATE=PASS`, including documentation link checks, documented script
  reference checks, shell syntax checks, 28 Swift tests, AppKit smokes, bundle
  verification, signature verification, OCR environment check, and 26 Python
  sidecar tests.

Implementation evidence:
- `.github/workflows/unsigned-release.yml` now enforces PR branch policy:
  implementation PRs target `develop`; release PRs to `main` must come from
  `develop` and include `VERSION`.
- Manual release dispatch is limited to rebuilding the current `VERSION` on
  `main`; the optional input must match that file.
- Release version values must match stable semver `x.y.z`.
- PR CI now runs documentation link checks, documented script reference checks,
  and shell syntax checks in addition to Swift build/test and layout smokes.
- `scripts/check_documented_scripts.sh` was added and wired into
  `scripts/agent_gate.sh`.
- Removed unused app helpers: `runFixtureOCR()`, `CopyToastPresenter.dismiss()`,
  and `PermissionDropPanelController.close()`.
- Worker warmup status now uses the configured hotkey display string instead of
  hardcoded `Cmd+Shift+0`.
- Stale TIFF capture error text and the stale fixture test path were corrected.
- `docs/release-unsigned.md`, `docs/roadmap.md`, `docs/autonomous-system.md`,
  and `docs/completion-audit.md` were updated to match current behavior.

Known verification gap:
- Hosted GitHub Actions policy behavior was not executed in this local cycle;
  the workflow was syntax/parse checked locally.
- Experiment scripts with no inbound references were retained because they are
  research reproduction artifacts, not proven dead product code.

## 2026-06-16 Cycle: Repository cleanup and documentation link gate

Scope: Remove unused repository artifacts, connect scattered documentation,
add a durable local Markdown link check, and keep code cleanup behavior-neutral.

Verified on the local macOS host:
- Local Markdown link inventory before cleanup found no missing local targets.
- New documentation gate: `scripts/check_docs_links.sh` passed with
  `DOC_LINKS=PASS checked=20`.
- Correction loop: the first `scripts/agent_gate.sh` run failed because the
  cleanup used `String(decoding:as:)` with `CChar` bytes. The code now maps
  `CChar` to `UInt8` before UTF-8 decoding, and `swift build --product
  ScreenOCRApp` passed.
- Full agent gate: final `scripts/agent_gate.sh` passed with
  `AGENT_GATE=PASS`, including 28 Swift tests, AppKit layout smokes, app bundle
  verification, signature verification, OCR environment check, and 26 Python
  sidecar tests.

Implementation evidence:
- `docs/README.md` now provides the documentation map and links the previously
  isolated update experiment and icon design notes.
- Root `README.md` now points to `docs/README.md`.
- `scripts/check_docs_links.sh` checks inline and reference-style local Markdown
  links, and `scripts/agent_gate.sh` runs it.
- Removed unreferenced duplicate `design/icons.html`; the canonical icon notes
  remain in `docs/icon-design.md` and `docs/icon-design.html`.
- Removed ignored `.DS_Store` files from runtime output directories.
- `ScreenOCRApp.nudgeWorkerToExit()` no longer uses deprecated
  `String(cString:)` on the `proc_pidpath` buffer.

Known verification gap:
- The macOS 14 `CGDisplayStream` compatibility warning remains intentional
  because it protects the documented legacy capture fallback path.

## 2026-06-16 Cycle: Develop-first workflow instructions

Scope: Update repository agent instructions so feature work starts from
`origin/develop`, implementation PRs target `origin/develop`, and releases are
performed through a `develop -> main` PR.

Verified on the local macOS host:
- Instruction files: `AGENTS.md` now contains a dedicated Branching, PR, And
  Release Flow section; `CLAUDE.md` was added with the same Claude-facing
  branch and release defaults.
- Branch context check: `git branch -r --list` showed only `origin/main` before
  the instruction update, so the new guidance explicitly says to create or
  synchronize `origin/develop` from `origin/main` if it is missing.

Known verification gap:
- This cycle updates instructions only. It does not create `origin/develop` or
  change GitHub branch protection/rulesets.

## 2026-06-12 Cycle: Experimental Sparkle updater path

Scope: Add a reversible Sparkle-based update experiment for the unsigned GitHub
Release distribution. The app reads only the GitHub Pages appcast, keeps
automatic update checks off by default, disables Sparkle automatic
download/install, shows version/update controls in Settings > General, and makes
release appcast generation conditional on explicit Sparkle key configuration.

Verified on the local macOS host:
- Settings update smoke: `bash scripts/run_settings_window_layout_smoke.sh`
  passed. It verifies the General > Version section, current version text,
  update status text, manual check button, install/restart button, and
  automatic update checkbox defaulting off in a fresh settings store.
- App build: `swift build --product ScreenOCRApp` passed with Sparkle linked.
- Script syntax and workflow parse checks passed:
  `bash -n scripts/build_app_bundle.sh scripts/verify_app_bundle.sh scripts/generate_sparkle_appcast.sh scripts/agent_gate.sh`
  and `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/unsigned-release.yml")'`.
- Missing appcast private key guard: `scripts/generate_sparkle_appcast.sh`
  failed as expected with `FAIL: SPARKLE_PRIVATE_KEY is required to generate a Sparkle appcast`.
- Missing Sparkle public key guard:
  `SCREEN_OCR_ENABLE_SPARKLE_UPDATES=1 SCREEN_OCR_CODESIGN_IDENTITY=- scripts/build_app_bundle.sh`
  failed as expected with
  `FAIL: SCREEN_OCR_SPARKLE_PUBLIC_ED_KEY is required when SCREEN_OCR_ENABLE_SPARKLE_UPDATES=1`.
- Opt-in bundle metadata:
  `SCREEN_OCR_ENABLE_SPARKLE_UPDATES=1 SCREEN_OCR_SPARKLE_PUBLIC_ED_KEY=dummy-public-ed-key SCREEN_OCR_CODESIGN_IDENTITY=- scripts/build_app_bundle.sh && scripts/verify_app_bundle.sh`
  passed, proving the bundle can include Sparkle metadata only when the
  experiment is enabled.
- Full agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`,
  including Swift tests, AppKit layout smokes, app bundle verification,
  signature verification, OCR environment check, and 26 Python sidecar tests.
- Release prep: `VERSION` was advanced to `0.0.3` so merging the PR to `main`
  satisfies the unsigned release workflow's VERSION-change gate.

Implementation evidence:
- `Package.swift` links Sparkle 2 through Swift Package Manager.
- `AppUpdater` wraps Sparkle behind a small app-owned boundary, refuses to start
  update checks outside `/Applications`, keeps `automaticallyDownloadsUpdates`
  false so Sparkle cannot silently install on quit, and exposes localized status
  for Settings and the menu item.
- `SettingsWindowController` shows the Version section in General and persists
  `automaticUpdateChecks` with a default of `false`.
- `scripts/build_app_bundle.sh` copies `Sparkle.framework`, injects Sparkle
  Info.plist keys only when `SCREEN_OCR_ENABLE_SPARKLE_UPDATES=1`, and fails if
  the public key is missing. The injected Sparkle keys keep
  `SUAutomaticallyUpdate=false` and `SUAllowsAutomaticUpdates=false`.
- `scripts/generate_sparkle_appcast.sh` generates `docs/appcast.xml` from the
  unsigned release zip using `SPARKLE_PRIVATE_KEY`.
- `.github/workflows/unsigned-release.yml` keeps the existing PR/release flow
  and conditionally generates plus commits the appcast only when the repository
  variable `SCREEN_OCR_ENABLE_SPARKLE_UPDATES` is `1`.

Known verification gap:
- A real Sparkle update was not installed because no production EdDSA key is
  configured in this local cycle.
- Hosted GitHub Actions release, GitHub Pages propagation, and a real
  `SPARKLE_PRIVATE_KEY` appcast signature remain to be verified after the
  experiment is enabled in repository settings.

## 2026-06-11 Cycle: Screen Recording permission guidance

Scope: Make the missing Screen Recording permission path easier to complete. When permission is missing, app Settings should open directly to the Capture permission controls, and the floating System Settings helper should visually show where to drag the app icon.

Verified on the local macOS host:
- Red settings smoke before implementation: `bash scripts/run_settings_window_layout_smoke.sh` failed because `SettingsWindowController` had no `focusCapturePermissions()` member.
- Red permission helper smoke before implementation: `bash scripts/run_permission_drop_panel_smoke.sh` failed because `PermissionDropPanelController` had no `makeContentView(...)` member.
- Settings focus smoke after implementation: `bash scripts/run_settings_window_layout_smoke.sh` passed. It now verifies that programmatic permission focus opens `settings.detail.capture`.
- Permission guidance smoke after implementation: `bash scripts/run_permission_drop_panel_smoke.sh` passed. It verifies the draggable app icon, direction cue, and Screen Recording list destination hint.
- Full Swift suite: `swift test` passed 28 tests.
- App build: `swift build --product ScreenOCRApp` passed.
- Full agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`, including the new permission helper guidance smoke.

Implementation evidence:
- `AppDelegate.openSettings()` now presents the Capture permission page when `canCaptureScreen()` is false.
- `SettingsWindowController` exposes `focusCapturePermissions()` and `presentCapturePermissions()` for permission-missing entry.
- `PermissionDropPanelController` builds a reusable panel content view with an app-icon source, arrow cue, and System Settings Screen Recording list destination hint.
- `scripts/agent_gate.sh` now includes the permission helper guidance smoke.

Known verification gap:
- The permission helper smoke verifies view structure and copy, not a pixel screenshot or a real TCC drag/drop grant.

## 2026-06-11 Cycle: Progress popup default

Scope: Keep the General > Display > progress popup checkbox unchecked on first launch.

Verified on the local macOS host:
- Settings layout smoke: `bash scripts/run_settings_window_layout_smoke.sh` passed after adding assertions that a fresh `SettingsStore` has `showDebugProgress == false` and the settings checkbox starts `.off`.
- Full agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`.

Implementation evidence:
- `AppSettings` already defaulted `showDebugProgress` to `false`; the settings smoke now locks the first-launch UI state.
- `settings.control.debug-progress` identifies the checkbox for AppKit UI-state verification.

Known verification gap:
- Existing user settings files that already persisted `showDebugProgress: true` are intentionally preserved; this only controls first-launch/default state.

## 2026-06-12 Cycle: Minimal permission helper cue

Scope: Keep the permission helper visually minimal while still showing the leftward drag direction and drop destination clearly.

Verified on the local macOS host:
- Permission guidance smoke: `bash scripts/run_permission_drop_panel_smoke.sh` passed after asserting that `permission.drop.direction` is the left arrow `←`, the arrow font is at least 40 pt, the arrow and copy share an aligned row, the copy names the left Screen Recording list destination, and the extra destination card/title are absent.
- Full agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`.

Implementation evidence:
- `PermissionDropPanelController` now shows only the draggable app icon, a large left-pointing arrow aligned with `왼쪽 화면 기록 목록에 드래그해서 넣어주세요.`, and the relaunch button.

Known verification gap:
- This verifies view structure and copy only; it does not screenshot the panel or perform a real TCC drag/drop grant.

## 2026-06-12 Cycle: Capture overlay window ordering

Scope: Starting capture mode should not promote a Settings window that was already open but behind another app.

Verified on the local macOS host:
- Window ordering policy smoke: `bash scripts/run_window_ordering_policy_smoke.sh` passed. It verifies that inactive visible normal windows are selected for restore-behind behavior, while active app windows and floating panels are not.
- Full agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`.

Implementation evidence:
- `SelectionOverlayController` records inactive normal windows before `NSApp.activate(ignoringOtherApps:)`, then orders those windows back after the screen-saver-level overlay becomes key.
- `WindowOrderingPolicy` keeps the selection rule small and independently smoke-tested.

Known verification gap:
- The smoke verifies the ordering policy, not a full hotkey run with a live Settings window behind another app.

## 2026-06-12 Cycle: 0.0.2 release prep

Scope: Prepare the current permission-helper and capture-window-ordering fixes for the unsigned release flow.

Verified on the local macOS host:
- `VERSION` was advanced to `0.0.2` so merging this PR to `main` will satisfy the release workflow's VERSION-change gate.
- `.github/workflows/unsigned-release.yml` now runs the permission helper guidance smoke and window ordering policy smoke during PR checks, matching the local gate coverage for this slice.
- Full agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`.

Known verification gap:
- The hosted GitHub Actions PR check and release job must still run after push/PR/merge.

## 2026-06-11 Cycle: Unsigned embedded release path

Scope: Support distribution without an Apple Developer account while keeping both PaddleOCR and Apple Vision selectable.

Verified on the local macOS host:
- Embedded runtime build: `SCREEN_OCR_EMBED_RUNTIME=1 SCREEN_OCR_CODESIGN_IDENTITY=- scripts/build_app_bundle.sh` completed and produced `dist/Screen OCR.app`.
- Embedded runtime verification: `scripts/verify_embedded_runtime_bundle.sh` passed. It verifies PaddleOCR/Paddle/sidecar importability and rejects build-machine Python paths in the embedded wrapper or Python launcher linkage.
- Signature verification: `scripts/verify_app_signature.sh` passed for the ad-hoc signed app with embedded Python.framework.
- Embedded fixture smoke: `scripts/run_embedded_fixture_smoke.sh` passed and copied `OCR 테스트\nHello 123`.
- Full agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`.
- Local unsigned zip: `dist/release/Screen-OCR-local-unsigned-macos-arm64.zip` was created with SHA-256 sidecar.
- Bundle size: latest local embedded app bundle is about 853 MB before zip packaging.
  The local zip is about 246 MB.

Implementation evidence:
- `scripts/build_app_bundle.sh` now embeds `Contents/Frameworks/Python.framework` in embedded-runtime mode and patches the Python launcher to use the bundled framework.
- `scripts/sign_app_bundle.sh` explicitly signs the embedded Python framework executables before signing the app bundle.
- `.github/workflows/unsigned-release.yml` builds/tests pull requests and publishes an ad-hoc signed, non-notarized zip release when `VERSION` changes on `main` or when manually dispatched.
- `docs/release-unsigned.md` documents Gatekeeper expectations and the unsigned release contract.

Known verification gap:
- The GitHub Actions workflow has not run on a hosted macOS runner in this local cycle. Local build, embedded import verification, signature verification, fixture smoke, agent gate, and zip packaging passed.

## 2026-06-11 Cycle: Settings two-pane redesign

Scope: Redesign the settings window into a macOS-style left sidebar and right detail pane. Categories are General, Capture, and Engine. The detail pane starts directly with sectioned form content, uses OS language for settings UI text, keeps save history out of settings, and preserves immediate application of existing controls.

Verified on the local macOS host:
- Design artifact: `docs/settings-redesign.md` records the category split, layout rules, OS language rule, and General/Capture/Engine ASCII wireframes.
- Narrow construction smoke: `bash scripts/run_settings_window_layout_smoke.sh` passed. It constructs `SettingsWindowController` with an isolated temp settings file, verifies the resizable two-pane window, sidebar items, General/Capture/Engine page switching, and PaddleOCR section show/hide behavior.
- Existing custom-control alignment smoke: `bash scripts/run_hotkey_recorder_layout_smoke.sh` passed with `first=17.00` and `last=7.00`.
- App build: `swift build --product ScreenOCRApp` passed.
- Full Swift suite: `swift test` passed 28 tests.
- Agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`, including the new settings window layout smoke, Swift builds, bundle/signature checks, OCR environment check, and 26 Python sidecar tests.

Implementation evidence:
- `SettingsWindowController` now builds a two-pane settings window with a simple icon sidebar and sectioned form detail pages.
- The settings categories are General, Capture, and Engine; the former Advanced/debug option is absorbed into General > Display.
- Settings strings are selected from OS language: Korean for Korean preferred language, English otherwise.
- Engine page keeps the PaddleOCR worker section visible only when PaddleOCR is selected.
- `SettingsStore` supports an optional file URL for isolated layout smoke tests; production still uses the default Application Support settings path.
- `scripts/agent_gate.sh` now runs the settings window layout smoke after Swift tests.

Known verification gap:
- The smoke validates construction, navigation, and visibility state. It does not yet capture a rendered screenshot for pixel-level visual review.

## 2026-06-11 Cycle: Hotkey settings row alignment

Scope: Align the "캡처 단축키" settings title with the hotkey input field in the AppKit settings grid.

Verified on the local macOS host:
- Red check before implementation: `bash scripts/run_hotkey_recorder_layout_smoke.sh` failed with `firstBaselineOffsetFromTop: actual=0.00 expected=17.00`, proving the custom recorder view exposed no usable text baseline to `NSGridView`.
- Narrow layout smoke after implementation: `bash scripts/run_hotkey_recorder_layout_smoke.sh` passed with `first=17.00` and `last=7.00`.
- Full Swift suite: `swift test` passed 28 tests.
- Agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`, including the new hotkey recorder layout smoke, Swift app builds, bundle/signature checks, OCR environment check, and 26 Python sidecar tests.

Implementation evidence:
- `HotkeyRecorderView` now exposes `firstBaselineOffsetFromTop` and `lastBaselineOffsetFromBottom` by forwarding the vertically centered internal label baselines.
- `scripts/agent_gate.sh` now runs the hotkey recorder layout smoke after `swift test`.

Known verification gap:
- This proves the custom control baseline contract numerically. It does not capture a screenshot of the full settings window.

## 2026-06-11 Cycle: Settings engine selection and Paddle worker count

Scope: Add settings support for OCR engine selection plus a PaddleOCR-only worker-count setting. `Auto` must preserve the existing CPU-count heuristic; numeric selections must reach the next Paddle worker process. Vision must not be selectable on unsupported platforms.

Verified on the local macOS host:
- Red check before implementation: `swift test --filter ScreenOCRCoreTests/testPersistentPythonSidecarOCRPassesExplicitRecognitionWorkerCount` failed to compile because `PersistentPythonSidecarOCR` had no `recognitionWorkerCount` initializer yet.
- Explicit worker count: `swift test --filter ScreenOCRCoreTests/testPersistentPythonSidecarOCRPassesExplicitRecognitionWorkerCount` passed; the fake worker saw `SCREEN_OCR_REC_WORKERS=4`.
- Auto worker count: `swift test --filter ScreenOCRCoreTests/testPersistentPythonSidecarOCRAutoRecognitionWorkerCountClearsParentEnv` passed; with parent `SCREEN_OCR_REC_WORKERS=9`, the worker still saw `auto` because the Swift client removed the variable for Auto.
- Full Swift suite: `swift test` passed 28 tests.
- Agent gate: `scripts/agent_gate.sh` passed with `AGENT_GATE=PASS`, including Swift tests, `ScreenOCRApp`/`ScreenOCRSmoke`/`ScreenOCRFixtureWindow` builds, local app bundle verification, local signature verification, OCR Python environment check, and 26 Python sidecar tests.

Implementation evidence:
- Settings persist `paddleOCRWorkerCount` as an optional integer; missing/invalid values normalize to `Auto`.
- The settings window shows a Paddle worker-count popup under the engine popup only when PaddleOCR is selected.
- `PersistentPythonSidecarOCR` accepts `recognitionWorkerCount`; numeric values set `SCREEN_OCR_REC_WORKERS`, while Auto removes it.
- The app recreates the cached Paddle worker when the configured worker count changes.
- Vision availability is normalized through platform checks; unsupported platforms fall back to PaddleOCR and the UI disables the Vision menu item.

Known verification gap:
- The settings window was compile/gate verified, but no screenshot-based UI harness exists for this AppKit settings form in this cycle.

## 2026-06-11 Cycle: Provided screenshot engine comparison

Scope: Compare Apple Vision and PaddleOCR worker on the user-provided 5044x2130 screenshot, then document whether Vision is ready to replace PaddleOCR as the default.

Verified on the local macOS host:
- Input metadata: `file` and `sips` confirmed a 5044x2130 PNG.
- Vision run: `swift run ScreenOCRSmoke engine-bench <image> --engine vision --repeats 1` saved `artifacts/engine-bench/provided-screenshot-vision-20260611.json`.
- PaddleOCR run: `SCREEN_OCR_OCR_TIMEOUT_MS=60000 SCREEN_OCR_REC_TIMEOUT_S=60 swift run ScreenOCRSmoke engine-bench <image> --engine paddle --repeats 1` saved `artifacts/engine-bench/provided-screenshot-paddle-20260611.json`.
- Gate after documentation update: `scripts/agent_gate.sh` passed on 2026-06-11 with `AGENT_GATE=PASS` after running Swift tests/builds, bundle verification/signature checks, OCR environment check, and 26 Python sidecar tests.

Engine comparison on the provided screenshot:

| Engine | Request elapsed | Worker init | Line count | Result |
| --- | ---: | ---: | ---: | --- |
| Apple Vision | 4278 ms | n/a | 30 | Better line grouping and overall structure on this screenshot. |
| PaddleOCR worker | 7478 ms | 5957 ms | 110 | More fragmented lines and visibly worse spacing/reading order on this screenshot. |

Interpretation:
- Vision is the better engine for this specific screenshot.
- This does not justify changing the default engine yet. In the same comparison cycle, `fixtures/stage-bench/medium-window.png` showed Vision-specific English substitutions (`Performance` -> `Pertormance`, `fans` -> `tans`, `def` -> `det`, `five` -> `tive`).
- Decision log updated: D-0018 keeps PaddleOCR as default and treats Vision as an optional fast engine pending a representative corpus.
- Performance analysis updated: H7 records this screenshot result plus counter-evidence from fixture comparisons.

Known verification gap:
- The provided screenshot has no exact expected transcript, so this comparison is qualitative for text structure and relative speed. It is not a CER proof.

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

The repository has an autonomous operating-system layer, a tested core OCR pipeline, a local PaddleOCR sidecar, an optional Apple Vision OCR engine, a local `.app` bundle build, and a macOS menu bar utility whose scripted end-to-end smoke verifies `Cmd+Shift+0` -> drag selection -> ScreenCaptureKit capture -> OCR -> clipboard. PaddleOCR remains the default engine; Apple Vision is selectable for fast in-process OCR while its default-replacement quality gate remains open.

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
- Apple Vision is promising on the provided dense screenshot, but default replacement still needs a representative real-screen corpus with exact expected text and per-engine CER thresholds.
- Hotkey smoke now records selection, image capture, OCR worker, clipboard, post-selection-to-clipboard, worker startup, and worker RSS timings. The remaining performance gap is representative real-screen validation beyond the controlled two-line fixture.
- Local default `python3` is 3.14.5; scripts intentionally use `python3.12` for the PaddleOCR runtime.
