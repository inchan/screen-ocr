# Test Plan

## Test Strategy

Use vertical BDD/TDD slices. Add one behavior-level test, make it pass with the smallest implementation, then refactor only while green.

## Test Levels

- Unit: OCR result normalization, error mapping, text cleanup, metric calculation.
- Unit UI logic: clipboard-success toast message and menu-bar-anchored frame calculation.
- Integration: Python OCR wrapper against fixture images, clipboard adapter with injectable pasteboard, capture pipeline with injectable image source.
- System smoke: hotkey -> capture -> OCR -> clipboard on macOS.
- Manual permission smoke: first-run permission states and recovery.
- Packaging smoke: signed local build checks once distribution starts.
- Local bundle smoke: build `dist/Screen OCR.app`, verify `Info.plist` menu-bar metadata, run the bundle executable outside the repo root, and confirm hotkey registration diagnostics.
- Local signature smoke: ad-hoc sign the local bundle, verify strict code signature/resource seal, and rerun bundle launch smoke.
- Embedded OCR-resource smoke: build with `SCREEN_OCR_EMBED_RUNTIME=1`, verify bundled OCR packages/sidecar/fixtures, reject Python.framework links to build-machine paths, run fixture OCR from bundle resources, and confirm clipboard text.
- OCR runtime setup smoke: when PaddleOCR's Python runtime, sidecar, version, modules, or embedded framework links are missing or incompatible, verify the app reports `OCR 설치 필요`, writes worker diagnostics, and shows install/setup guidance instead of a raw Python error.
- Version smoke: direct region capture on macOS 15.2+ and fallback ScreenCaptureKit filter/sourceRect capture on macOS 14+.
- Legacy capture smoke: force the macOS 14 ScreenCaptureKit filter/sourceRect path with `SCREEN_OCR_FORCE_LEGACY_CAPTURE=1` and verify hotkey-to-clipboard behavior.
- Noninteractive screen smoke: render known text, capture it through ScreenCaptureKit, OCR it with PaddleOCR, and verify clipboard text.
- Scripted hotkey smoke: launch the app and fixture window, synthesize `Cmd+Shift+0`, drag a known region, and verify `capture_ocr_finished` plus clipboard text.
- Persistent OCR worker smoke: start the worker, wait for ready, run repeated fixture OCR requests through the worker protocol, verify text quality, record ready latency, request median, timeout behavior, and RSS.
- Persistent OCR worker configuration: verify explicit Paddle worker counts are passed as `SCREEN_OCR_REC_WORKERS`, and `Auto` omits that variable so the Python sidecar uses its safe single-process default.
- OCR preprocessing unit/integration: given a large mostly-empty screenshot with two text-like regions, generate a preprocessed PNG after capture and before OCR, verify dimensions shrink with padding, record elapsed time, and verify unsafe/small images fall back to the original path.
- Clipboard-success toast smoke boundary: verify the successful hotkey path still reaches clipboard and status success; visual toast placement is covered by deterministic frame calculation tests unless a later screenshot-based UI harness is added.
- Hotkey reliability smoke: repeat the scripted hotkey smoke 20 times and require at least 95% success after permissions are granted.
- OCR engine comparison smoke: run `ScreenOCRSmoke engine-bench` on the same image with `--engine vision` and `--engine paddle`, record latency, line count, and qualitative text-shape differences. For default-engine decisions, use a representative corpus with exact expected text so CER can be compared per engine.
- Settings engine availability: verify Vision is selectable only on macOS/Vision-capable builds; unsupported platforms must show it disabled or normalize persisted `vision` settings back to PaddleOCR.
- Settings hotkey layout smoke: compile the real `HotkeyRecorderView` with its settings types, instantiate it under AppKit, and verify its exposed first/last baselines match the centered label baselines so the `NSGridView` settings row can align "캡처 단축키" with the input field.
- Settings redesign smoke: build `ScreenOCRApp` and verify the settings window can construct the two-pane General/Capture/Engine layout without losing existing controls or side-effect handlers. A screenshot/UI-state harness should follow for full visual proof.
- Settings update smoke: verify the General page includes the Version section, current bundle version text, update status text, manual check button, install/restart button, and an automatic update checkbox that starts off on a fresh settings store.
- Permission guidance smoke: compile the real permission helper panel content and verify it exposes the draggable app icon, a large left-pointing direction cue aligned with the instruction text, and minimal copy that names the left Screen Recording list destination. Settings layout smoke must also verify that the app can programmatically focus the Capture permission page when permission is missing.
- Capture window ordering smoke: verify that capture overlay activation preserves already-front app windows but sends visible normal app windows that were behind another app back behind the overlay after activation.

## Initial Fixtures

Create deterministic image fixtures before OCR implementation:

- English simple: `Hello 123`
- Korean simple: `안녕하세요 123`
- Mixed: `OCR 테스트 Hello 123`
- Low contrast UI text
- Small font UI text

Each fixture needs expected text and metadata:
- font name and size,
- image dimensions,
- foreground/background colors,
- expected normalized output,
- acceptable character error rate.

## Quantitative Gates

Initial development gates:
- OCR wrapper returns nonempty text for at least 20 controlled fixture images.
- Character error rate is recorded for every fixture.
- Warm OCR latency is recorded over at least 5 runs per fixture.
- Failure path returns structured error data.
- Shortcut registration result is recorded during app startup.
- Capture image dimensions are recorded for Retina and non-Retina selections when available.

Current benchmark baseline:
- Controlled fixture corpus: 20 Korean/English UI-style images.
- Latest run: 20/20 fixtures passed.
- PaddleOCR initialization: 4391.28 ms.
- Historical warm OCR median over 7 runs per fixture: 281.285 ms after applying the earlier `text_det_limit_side_len=736` and `text_det_limit_type=max` monolithic benchmark setting.
- Current PaddleOCR production worker detector behavior: adaptive `text_det_limit_side_len` from 1152 to 1536, scaling large captures to preserve detection while retaining the faster 1152 cap for ordinary captures.
- Median character error rate: 0.0.
- Mean character error rate: 0.0072.
- Max observed character error rate: 0.0588.
- Fresh pre-optimization baseline for this cycle was 299.21 ms median warm OCR over 7 runs per fixture, so the accepted detector-limit change improved median warm latency by 17.925 ms / 5.991%.
- Scripted hotkey-to-clipboard smoke: latest normal pass copied `OCR 테스트\nHello 123`; elapsed time is recorded in `artifacts/acceptance/latest-normal-hotkey-smoke.json`.
- Prewarmed persistent-worker hotkey smoke: latest local pass copied `OCR테스트\nHello 123`, measured worker ready 4459 ms before capture, worker RSS 845.4 MB, OCR stage 353 ms, image capture after selection 57 ms, and region-selection-complete to clipboard 410 ms.
- OCR preprocessing benchmark: latest synthetic large-empty pass reduced request median from 397.901 ms to 267.591 ms, a 130.31 ms / 32.749% improvement, while preserving `OCR테스트\nHello 123`.
- Scripted hotkey reliability: 20/20 passed, success rate 1.0, median run elapsed 6071 ms, minimum success-rate gate 0.95.
- Forced legacy ScreenCaptureKit fallback smoke: passed with clipboard text `OCR 테스트\nHello 123`; elapsed time is recorded in `artifacts/hotkey/latest-legacy-capture-smoke.json`.
- Local app bundle structure and launch smoke are required before treating the project as a Mac utility rather than only a SwiftPM executable.
- Local ad-hoc app signature verification passes with strict codesign verification.
- Embedded OCR-resource bundle fixture smoke passes with clipboard text `OCR테스트\nHello 123`.
- User-provided dense screenshot engine comparison on 2026-06-11: Vision 4278 ms / 30 lines, PaddleOCR worker 7478 ms / 110 lines plus 5957 ms worker init. Vision was better on this screenshot, but this was qualitative because no exact expected transcript exists.

Product-readiness candidate gates:
- At least 20 real representative screen crops, separate from the controlled synthetic fixture corpus.
- Mixed Korean/English median character error rate under 5% on controlled fixtures.
- Warm OCR median latency under 2.0 seconds on target Mac hardware.
- Persistent worker post-ready OCR request median under 500 ms before claiming sub-second clipboard feasibility.
- Prewarmed app path keeps region-selection-complete to clipboard under 700 ms on short controlled two-line screen text.
- OCR preprocessing keeps small-crop behavior unchanged and records `preprocess_elapsed_ms`, original/preprocessed dimensions, and applied/fallback status before claiming large-region speed improvements.
- Hotkey-to-clipboard success rate at least 95% across 20 repeated runs after permissions are granted.
- On macOS 15+, normal capture produces no deprecated capture API privacy warning.
- Unsigned release candidate passes embedded runtime verification, ad-hoc signature verification, zip packaging, and manual Gatekeeper-open documentation checks. Embedded fixture smoke should also check that no new macOS `Python-*.ips` crash reports are created. Developer ID notarization/stapling checks apply only if a future credentialed distribution path begins.
- Default OCR engine changes require a representative real-screen corpus with exact expected text, per-engine CER/latency reports, and no material regression on Korean, English, code-like, dense, and wide-strip cases.
- Paddle worker-count UI changes must preserve `Auto` as the default safe single-process mode and prove that numeric choices affect the next worker process rather than only the settings file.
- Settings row alignment changes must include a layout smoke or screenshot harness that proves custom controls expose sane AppKit baselines instead of relying on visual inspection only.
- Settings redesign changes must preserve immediate application of existing settings and keep PaddleOCR worker controls visible only on the Engine page while PaddleOCR is selected.
- Update integration changes must keep automatic update checks off by default, keep Sparkle automatic download/install disabled, verify Sparkle bundle metadata only when update support is explicitly enabled for a build, reject enabled builds without a public key, reject appcast generation without `SPARKLE_PRIVATE_KEY`, and never publish update metadata without an EdDSA signature.
- Permission guidance changes must preserve a clean icon-plus-left-arrow instruction, align the arrow and text in one row, name the left Screen Recording list destination, avoid extra destination cards/explanatory copy, and keep permission-missing Settings entry focused on the Capture page.
- Capture overlay changes must not promote a previously backgrounded Settings window to the front merely because the overlay activates the LSUIElement app.

These thresholds are starting gates and must be revised with evidence.

## Red-Green-Refactor Order

1. Test OCR result normalization with static JSON.
2. Test OCR wrapper contract with a fake OCR command.
3. Test fixture-image OCR through the real Python sidecar.
4. Test clipboard adapter with injectable pasteboard.
5. Test app pipeline with fake capture and fake OCR.
6. Test clipboard-success toast message and menu-bar-anchored frame calculation.
7. Test shortcut registration state mapping.
8. Test capture permission state mapping.
9. Smoke test real capture and real OCR noninteractively on macOS.
10. Smoke test the real hotkey and selection overlay with `scripts/run_hotkey_smoke.sh`.
11. Run 20-cycle hotkey reliability with `scripts/run_hotkey_reliability.sh`.
12. Force legacy ScreenCaptureKit capture with `scripts/run_legacy_capture_smoke.sh`.
13. Run final acceptance with `scripts/final_acceptance.sh`.
