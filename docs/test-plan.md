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
- Embedded OCR-resource smoke: build with `SCREEN_OCR_EMBED_RUNTIME=1`, verify bundled OCR packages/sidecar/fixtures, run fixture OCR from bundle resources, and confirm clipboard text.
- Version smoke: direct region capture on macOS 15.2+ and fallback ScreenCaptureKit filter/sourceRect capture on macOS 14+.
- Legacy capture smoke: force the macOS 14 ScreenCaptureKit filter/sourceRect path with `SCREEN_OCR_FORCE_LEGACY_CAPTURE=1` and verify hotkey-to-clipboard behavior.
- Noninteractive screen smoke: render known text, capture it through ScreenCaptureKit, OCR it with PaddleOCR, and verify clipboard text.
- Scripted hotkey smoke: launch the app and fixture window, synthesize `Cmd+Shift+0`, drag a known region, and verify `capture_ocr_finished` plus clipboard text.
- Persistent OCR worker smoke: start the worker, wait for ready, run repeated fixture OCR requests through the worker protocol, verify text quality, record ready latency, request median, timeout behavior, and RSS.
- OCR preprocessing unit/integration: given a large mostly-empty screenshot with two text-like regions, generate a preprocessed PNG after capture and before OCR, verify dimensions shrink with padding, record elapsed time, and verify unsafe/small images fall back to the original path.
- Clipboard-success toast smoke boundary: verify the successful hotkey path still reaches clipboard and status success; visual toast placement is covered by deterministic frame calculation tests unless a later screenshot-based UI harness is added.
- Hotkey reliability smoke: repeat the scripted hotkey smoke 20 times and require at least 95% success after permissions are granted.

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
- Warm OCR median over 7 runs per fixture: 281.285 ms after applying `text_det_limit_side_len=736` and `text_det_limit_type=max`.
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

Product-readiness candidate gates:
- At least 20 real representative screen crops, separate from the controlled synthetic fixture corpus.
- Mixed Korean/English median character error rate under 5% on controlled fixtures.
- Warm OCR median latency under 2.0 seconds on target Mac hardware.
- Persistent worker post-ready OCR request median under 500 ms before claiming sub-second clipboard feasibility.
- Prewarmed app path keeps region-selection-complete to clipboard under 700 ms on short controlled two-line screen text.
- OCR preprocessing keeps small-crop behavior unchanged and records `preprocess_elapsed_ms`, original/preprocessed dimensions, and applied/fallback status before claiming large-region speed improvements.
- Hotkey-to-clipboard success rate at least 95% across 20 repeated runs after permissions are granted.
- On macOS 15+, normal capture produces no deprecated capture API privacy warning.
- Release candidate passes signing, notarization, and stapler checks when Developer ID distribution begins.

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
