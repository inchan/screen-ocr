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

Decision: Support `SCREEN_OCR_EMBED_RUNTIME=1 scripts/build_app_bundle.sh`, which copies the OCR Python packages, sidecar source, and fixtures into `Contents/Resources`, and replaces absolute venv symlinks with executable wrappers so strict codesign resource sealing passes.

Reason: The Mac utility should not have to depend on the source tree for OCR packages and sidecar code. Embedding the OCR resources proves the app can run its OCR path from bundle resources.

Constraint: The current local venv was created from Homebrew Python and points to `/opt/homebrew/opt/python@3.12/bin/python3.12`; the wrapper still uses that interpreter. This is project-independent, but not a fully standalone Python framework distribution.

Rejected: Claim a fully self-contained runtime in this slice. That would require bundling and signing a Python framework/interpreter, which is separate release engineering work.

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
