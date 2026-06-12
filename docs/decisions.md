# Decision Log

Use this file for accepted and rejected project decisions.

## D-0001: Build the autonomous operating system before app code

Status: accepted

Decision: Create repo-local `AGENTS.md`, process docs, and a validation script before implementing the macOS utility.

Reason: The user explicitly requested a self-directed system first, and the project needs many gates: research, filtering, tech stack, BDD/TDD, quantitative validation, debugging, roadmap, and feedback loops.

Rejected: Start by writing app code immediately. It would skip the requested operating system and increase the chance of undocumented assumptions.

## D-0002: Default to local PaddleOCR, not hosted OCR

Status: accepted

Decision: Use local PaddleOCR by default. Hosted PaddleOCR APIs are out of scope unless the user explicitly accepts credentials, network transfer, and privacy tradeoffs.

Reason: Screen OCR can include private data. Local OCR is aligned with a menu bar utility and avoids token/account requirements.

Rejected: Hosted API as default. It introduces network, credentials, privacy, and availability risks.

## D-0003: Use Swift/AppKit host plus Python OCR sidecar as the provisional stack

Status: provisional

Decision: Start with a native macOS menu bar host and a Python sidecar for OCR.

Reason: AppKit gives direct menu bar and pasteboard access. PaddleOCR is officially exposed through Python and CLI paths.

Rejected: Full Swift-native OCR integration now. It would require a larger bridge before the OCR path is proven.

Review Trigger: Change this decision if a spike proves another capture/hotkey/OCR integration path is simpler and more reliable.

## D-0004: Treat capture, OCR, and clipboard as separately testable stages

Status: accepted

Decision: Design the pipeline as capture -> OCR -> clipboard, with observable stage outputs for tests and diagnostics.

Reason: The user requires quantitative validation and debugging strategy. Stage boundaries make failures measurable.

Rejected: A single opaque command flow. It would be shorter initially but harder to test and debug.

## D-0005: Use ScreenCaptureKit for screen capture

Status: accepted

Decision: Use ScreenCaptureKit as the default capture implementation. Prefer `SCScreenshotManager` and `SCScreenshotConfiguration.sourceRect` for region capture when supported by the deployment target.

Reason: Apple directs developers away from deprecated screen capture APIs, and ScreenCaptureKit is the modern permission-aware path.

Rejected: Legacy `CGWindowListCreateImage`, `CGDisplayStream`, or shelling out to `screencapture` as the production path. They may help spikes but are not the target implementation.

## D-0006: Use RegisterEventHotKey for the default global shortcut

Status: accepted

Decision: Register `Cmd+Shift+0` through `RegisterEventHotKey` and surface registration failure as a normal app state.

Reason: It is the smallest known global hotkey path that avoids default Accessibility/Input Monitoring requirements.

Rejected: `NSEvent.addGlobalMonitorForEvents` and `CGEventTap` as default hotkey paths because they increase permission burden and do not match the minimal shortcut requirement.

## D-0007: Default to menu-bar-only UI

Status: accepted

Decision: Build a menu-bar utility using `MenuBarExtra` or `NSStatusItem`, with `LSUIElement=true` for no Dock icon.

Reason: The workflow is repeated utility behavior, not a document or window-first app.

Rejected: A normal Dock-first app as the MVP surface.

## D-0008: Constrain MVP capture to single-display selection unless stitching is proven

Status: provisional

Decision: MVP may reject cross-display selections with a clear status message. Multi-display stitching is a later enhancement unless tests show it is cheap and reliable.

Reason: ScreenCaptureKit `sourceRect` behavior is display-relative and Retina/non-Retina scaling must be validated. Single-display capture reduces first vertical-slice risk.

Rejected: Silent cross-display capture with unclear pixel mapping.

## D-0009: Use direct ScreenCaptureKit rect capture for the first real capture slice

Status: accepted

Decision: The first real capture implementation used `SCScreenshotManager.captureImage(in:)` and reported an unsupported-OS error below macOS 15.2.

Reason: The SDK provides a direct display-agnostic rect capture API, which avoids a larger display-filter/sourceRect implementation while preserving the intended region-capture behavior.

Rejected at the time: Implement the older `SCContentFilter` plus `SCStreamConfiguration.sourceRect` path in the same slice.

Superseded by: D-0013 adds the macOS 14 ScreenCaptureKit fallback path after the direct capture slice was proven.

## D-0010: Ship a local development app bundle before distribution packaging

Status: accepted

Decision: Build `dist/Screen OCR.app` as a local development bundle that contains the Swift executable, menu-bar `Info.plist`, and a `project-root.txt` resource pointing back to this repository for the Python sidecar, `.venv-ocr`, fixtures, and diagnostics.

Reason: The user asked for a Mac utility. A `.app` bundle proves the app shape and Finder/menu-bar launch path without prematurely copying a roughly gigabyte OCR runtime or introducing Developer ID signing requirements.

Rejected: Bundle the whole Python virtual environment and PaddleOCR model cache in this slice. It would make the artifact large and complicate signing before the core workflow and packaging constraints are fully measured.

Rejected: Treat the SwiftPM executable alone as the final Mac utility surface. It works for development, but it does not prove the app-bundle behavior expected for a menu bar utility.

## D-0011: Use ad-hoc signing for local bundle verification

Status: accepted

Decision: Sign `dist/Screen OCR.app` with an ad-hoc local identity by default and verify it with `codesign --verify --deep --strict`.

Reason: Local ad-hoc signing proves bundle resource sealing and catches signing regressions without requiring a Developer ID certificate, Apple account credentials, or notarization upload.

Rejected: Attempt Developer ID signing/notarization in the autonomous local workflow. That requires external credentials and an Apple developer account, so it must remain an explicit credential-gated release step.

## D-0012: Add an embedded OCR-resource bundle mode

Status: accepted

Decision: Support `SCREEN_OCR_EMBED_RUNTIME=1 scripts/build_app_bundle.sh`, which copies the OCR Python packages, sidecar source, fixtures, and Python.framework into the app bundle. The build patches the embedded Python launcher to load `Contents/Frameworks/Python.framework` instead of a build-machine interpreter, then ad-hoc signs the nested Python code and app bundle.

Reason: The Mac utility should not have to depend on the source tree or the builder's Homebrew/Python install for OCR packages and sidecar code. Embedding the OCR resources and interpreter lets the app keep both PaddleOCR and Apple Vision selectable in an unauthenticated distribution build.

Constraint: The embedded PaddleOCR bundle is large. The latest local embedded bundle is about 853 MB before zip packaging.

Rejected: Keep wrapping `/opt/homebrew/opt/python@3.12/bin/python3.12`. That verifies on the build machine but fails as a real distribution artifact on Macs without the same Homebrew path.

## D-0013: Keep ScreenCaptureKit as the macOS 14 fallback path

Status: accepted

Decision: Use `SCScreenshotManager.captureImage(in:)` on macOS 15.2+ and fall back to `SCShareableContent` + `SCContentFilter(display:excludingWindows:)` + `SCStreamConfiguration.sourceRect` + `SCScreenshotManager.captureImage(contentFilter:configuration:)` on older macOS 14 hosts.

Reason: The app's package target is macOS 14. ScreenCaptureKit has a macOS 14 image capture API and point-based `sourceRect`, so we can preserve the native capture stack instead of switching to deprecated CoreGraphics capture or shelling out to `screencapture`.

Verification: `SCREEN_OCR_FORCE_LEGACY_CAPTURE=1 scripts/run_hotkey_smoke.sh` passed on the local host and copied `OCR 테스트\nHello 123`.

Constraint: This forced fallback proves the code path on the current host, but a real macOS 14 machine should still run the same smoke before release.

## D-0014: Limit PaddleOCR detector side length for small screen crops

Status: accepted

Decision: Pass `text_det_limit_side_len=736` and `text_det_limit_type=max` to PaddleOCR `predict()` by default in the Python sidecar.

Reason: The controlled screen OCR fixtures are small UI crops, mostly 640-900 px wide and 180-220 px tall. The final 7-repeat evaluator benchmark improved corpus median warm OCR latency from 299.21 ms to 281.285 ms while keeping 20/20 fixtures passing and improving mean CER from 0.0094 to 0.0072.

Rejected: Lower detector limits such as 640 or 512 as the default. They were faster in a probe, but increased character error risk on punctuation/terminal-style fixtures.

Constraint: This is a warm-inference optimization. Cold first use is still dominated by PaddleOCR initialization and Python sidecar process startup.

Superseded by: D-0019 updates the production worker detector cap to `1152..1536` adaptive sizing after wide-strip and 5K-screen real-capture regressions.

## D-0015: Prototype a persistent local OCR worker before adding OCR dependencies

Status: accepted

Decision: Use a long-lived local Python OCR worker that keeps one PaddleOCR instance loaded and accepts image-path requests over JSONL. The app starts this worker during launch and reuses it for hotkey and fixture OCR flows.

Reason: Local research measured the current one-shot Python sidecar at 3641.83 ms median, while a JSONL-style persistent worker returned post-ready OCR requests in 268.77 ms median. The implemented hotkey smoke reduced the app OCR stage from the previous 4617 ms median subprocess cost to 353 ms, and measured region-selection-complete to clipboard at 410 ms on the controlled two-line fixture.

Constraint: Worker startup still costs seconds and measured resident memory is about 845 MB RSS after model load. The app exposes worker warm-up/status and handles worker error responses, invalid JSON, and EOF/crash by dropping the process so the next request can restart it. A hard request timeout remains a separate reliability gap.

Rejected: Add PaddleOCR HPI dependencies as the next step. `enable_hpi=True` failed locally because `ultra-infer` is not installed, and new dependencies are not allowed without a separate decision.

Rejected: Tune detector limits below 736 as the next step. Lower limits are faster but increased OCR quality risk on code/terminal fixtures.

## D-0016: Add OCR input preprocessing between screenshot save and PaddleOCR

Status: accepted

Decision: Insert a preprocessing step after screenshot PNG save and before PaddleOCR prediction. The first implementation is a conservative auto-trim that writes a preprocessed PNG only when it can safely reduce mostly-empty margins, and OCR runs against the preprocessed path.

Reason: Web research and local timing show large image area directly increases text detection work. For a 2400x1600 mostly-empty synthetic region containing the existing two-line fixture, preprocessing reduced OCR request median from 397.901 ms to 267.591 ms, a 130.31 ms / 32.749% improvement while preserving `OCR테스트\nHello 123`.

Constraint: Preprocessing must preserve the original capture for debugging, record preprocessing time and original/preprocessed dimensions, and fall back to the original image when trim confidence or area reduction is insufficient.

Rejected: Replacing PaddleOCR before measuring preprocessing. The current engine is fast enough on small crops after prewarm; the large-region problem first needs input-size evidence.

## D-0017: Harden the persistent worker round-trip (timeout, slim payload, opt-in line filter)

Status: accepted

Decision: Make three changes to the persistent OCR worker round-trip that are behavior-preserving by default:
1. The Swift client reads worker responses through a buffered line reader and enforces a hard per-request timeout (`SCREEN_OCR_OCR_TIMEOUT_MS`, default 15000 ms). On timeout the worker process is terminated so the in-flight read unblocks via EOF, and the next request restarts it.
2. The worker drops `box` polygon arrays from the per-line response payload, because the Swift client only consumes `text` and `score`. The one-shot CLI and the fixture benchmark still call `recognize_image` directly and keep `box`.
3. The worker honors an opt-in low-confidence line filter (`SCREEN_OCR_MIN_LINE_SCORE`, default unset → no filtering) via a new `min_score` parameter on `recognize_image`.

Reason: This resolves the "hard request timeout remains a separate reliability gap" called out in D-0015 (a hung worker could otherwise freeze the menu bar app indefinitely). The buffered reader replaces a one-byte-at-a-time read loop, and the slim payload reduces the bytes transferred and decoded per request. The line filter is opt-in so default OCR quality and the 20/20 fixture benchmark are unchanged.

Constraint: Defaults must preserve current behavior — `min_score=0.0` filters nothing, the timeout is generous, and the slim payload still decodes into the existing `OCRDocument` (which already ignored `box`). The blocking worker read runs on a background dispatch queue, not the actor's executor or a cooperative thread.

Rejected: Filtering low-score lines by default. It would change recognized text and the fixture benchmark without separate quality evidence, so it stays behind an explicit env opt-in.

## D-0018: Keep PaddleOCR as the default while Apple Vision remains an optional engine

Status: accepted

Decision: Keep `.paddleOCR` as the default OCR engine and expose Apple Vision as a selectable, in-process engine rather than replacing the default.

Reason: Apple Vision is materially faster on several local probes and avoids the Python worker startup/RSS cost, but the current evidence is mixed. On the user-provided 5044x2130 screenshot, Vision returned 30 lines in 4278 ms while PaddleOCR returned 110 fragmented lines in 7478 ms after a 5957 ms worker init. However, the medium-window fixture showed Vision-specific English substitutions (`Performance` -> `Pertormance`, `fans` -> `tans`, `def` -> `det`, `five` -> `tive`). A default replacement needs a representative corpus and acceptance thresholds, not a single favorable screenshot.

Verification: `swift run ScreenOCRSmoke engine-bench <provided screenshot> --engine vision --repeats 1` saved `artifacts/engine-bench/provided-screenshot-vision-20260611.json`; `SCREEN_OCR_OCR_TIMEOUT_MS=60000 SCREEN_OCR_REC_TIMEOUT_S=60 swift run ScreenOCRSmoke engine-bench <provided screenshot> --engine paddle --repeats 1` saved `artifacts/engine-bench/provided-screenshot-paddle-20260611.json`.

Constraint: Vision has no worker prewarm, worker status, stage streaming, or model-cache diagnostics. The app must continue treating worker lifecycle controls as PaddleOCR-only.

Rejected: Switch the default engine to Vision from the current data. The provided screenshot favors Vision, but the fixture evidence still shows accuracy regressions on some English/code-like text.

## D-0019: Use adaptive PaddleOCR detector sizing for the production worker path

Status: accepted

Decision: The production PaddleOCR worker path uses `text_det_limit_side_len` starting at `1152`, scaling large captures up to `1536` when needed to keep detector scale near 0.3x.

Reason: The older `736` cap improved small synthetic fixture latency but failed wide single-line crops by shrinking text too much. A fixed `1152` cap restored wide-strip detection and cut detection time on 2560-class captures, but a 5086px-wide real capture clipped leading characters at 0.226x detector scale. The adaptive `1152..1536` cap keeps ordinary captures on the fast setting while preserving detection scale for very large screenshots.

Rejected: Keep documenting `736` as the current production default. It is now historical benchmark context, not the current worker behavior.

## D-0020: Expose PaddleOCR worker count as a settings-level override

Status: accepted

Decision: Add a PaddleOCR-only worker-count setting with `Auto` as the default. `Auto` omits `SCREEN_OCR_REC_WORKERS` so the Python sidecar keeps using its current CPU-count heuristic; numeric selections set `SCREEN_OCR_REC_WORKERS` for the next Paddle worker process. Apple Vision remains selectable only when the platform supports Vision.

Reason: Recent engine experiments showed PaddleOCR quality/speed depends on worker behavior, and users need a safe way to tune the recognizer pool without editing environment variables. Keeping `Auto` as the default preserves the existing CPU-derived behavior and avoids changing current performance unexpectedly.

Constraint: Worker lifecycle controls are PaddleOCR-only. Vision is in-process and has no recognizer pool, so the worker-count control must be hidden unless PaddleOCR is selected. Unsupported platforms must not allow Vision to become the active engine.

Rejected: Treat the worker-count setting as a global environment preference. That would affect Vision (which has no worker) and make `Auto` ambiguous if the parent process already had `SCREEN_OCR_REC_WORKERS` set.

## D-0021: Redesign settings as a macOS two-pane form

Status: accepted

Decision: Redesign the settings window into a left sidebar and right detail pane with three categories: General, Capture, and Engine. The detail pane starts directly with sectioned form content and does not show a duplicate page title or page description.

Reason: The settings surface now mixes storage, capture, permissions, engine selection, and diagnostics in one grid. A two-pane macOS-style layout keeps navigation predictable while preserving a compact, utility-app feel.

Constraint: Settings UI text follows the OS preferred language: Korean for Korean OS language, English otherwise. Saved records/history are not browsed in settings; settings only exposes save location controls. Controls apply immediately, with help text only where the underlying effect happens on a future process or permission boundary.

Rejected: Keep a single-page settings grid. It became ambiguous after adding engine selection and PaddleOCR worker controls.

## D-0022: Support unsigned GitHub Releases without Apple Developer credentials

Status: accepted

Decision: Add an unauthenticated release path that produces an ad-hoc signed, non-notarized `.app` zip through GitHub Actions. Pull requests run validation only. A release is built when a PR that changes `VERSION` is merged to `main`, or when a maintainer runs the workflow manually. The release artifact embeds PaddleOCR runtime resources and keeps Apple Vision selectable, but it does not use Developer ID signing or Apple notarization.

Reason: The user does not have an Apple Developer account and explicitly wants distribution without Apple authentication. GitHub Releases can host the artifact using the repository's built-in token; no Apple secrets are needed.

Constraint: macOS Gatekeeper will warn that the developer cannot be verified. Users must manually allow the app through Finder's Open flow or System Settings > Privacy & Security > Open Anyway. Permission grants may need re-approval after updates because ad-hoc signed builds do not have a stable Developer ID identity.

Rejected: Require Developer ID signing/notarization for the first distribution path. It blocks the user's stated constraint.

Rejected: Ship a Vision-only build to avoid bundling Python. The user wants the current engine choice model to remain, so PaddleOCR must remain available in the unsigned artifact.

## D-0023: Experiment with Sparkle for unsigned app updates

Status: accepted

Decision: Introduce Sparkle 2 experimentally behind a small app-owned updater wrapper. The app reads a Sparkle appcast from GitHub Pages instead of calling the GitHub Releases API directly. Settings > General owns the visible version/update controls; automatic update checks default to off, automatic download/install is disabled, and installing a prepared update requires an explicit user action.

Reason: Updating a macOS app safely includes appcast parsing, archive signature verification, download state, installation, relaunch, and failure recovery. Sparkle already owns that problem and can verify update archives with EdDSA signatures without requiring an Apple Developer account.

Constraint: The unsigned release limits remain. Gatekeeper warnings and Screen Recording permission re-approval can still happen after updates because the app is ad-hoc signed and not notarized. Automatic update checks are supported only from `/Applications`. Sparkle's automatic download setting is not used because Sparkle can still attempt to install such an update on app termination. The Sparkle private key must live outside the repository, preferably in the GitHub Actions secret `SPARKLE_PRIVATE_KEY`; publishing update metadata without an EdDSA signature is not allowed once updater support is enabled for releases.

Rejected: Implement a custom GitHub Release JSON updater in the app. It would duplicate Sparkle's appcast, signature, download, install, and recovery behavior.

Rejected: Make updates fully silent in the first experiment. OCR/capture work, unsigned Gatekeeper behavior, install authorization, and permission re-approval make explicit install/restart the safer first product contract.
