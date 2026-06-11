# Roadmap

## Phase 0: Autonomous Project System

Goal: Establish the rules and evidence surfaces that let agents proceed without repeated permission checks.

Exit criteria:
- `AGENTS.md` exists.
- Required docs exist.
- `scripts/agent_gate.sh` passes.
- Next implementation gate is clear.

## Phase 1: Research And Filtering

Goal: Verify PaddleOCR, macOS hotkey, capture, permissions, clipboard, and packaging facts from primary sources.

Exit criteria:
- `docs/research.md` contains source-backed facts.
- `docs/decisions.md` records included and rejected paths.
- Unknowns are converted into spikes or test tasks.

Current status: complete for the local MVP direction. PaddleOCR and Apple API research have been integrated; direct macOS 15.2+ capture and the macOS 14 ScreenCaptureKit fallback are both documented, and packaging plus cold/warm latency are covered by local bundle smokes and OCR benchmark artifacts.

## Phase 2: Testable Core Pipeline

Goal: Build a platform-independent pipeline for capture image -> OCR result -> clipboard text using fakes first.

Exit criteria:
- Behavior tests pass for OCR normalization, fake OCR, error mapping, and clipboard adapter.
- Diagnostics are structured.

## Phase 3: PaddleOCR Sidecar

Goal: Run local PaddleOCR against fixture images and report text, scores, boxes, and timings.

Exit criteria:
- Pinned Python environment installs.
- PaddlePaddle runtime check passes.
- OCR fixture benchmark is recorded.

Current setup:
- `scripts/setup_ocr_env.sh` creates `.venv-ocr` with Python 3.12 by default and installs `paddlepaddle==3.3.0` plus `paddleocr==3.6.0`.
- `scripts/verify_ocr_runtime.sh` verifies installed package versions, runs `paddle.utils.run_check()`, and constructs the default OCR instance.
- `fixtures/ocr/manifest.json` now defines 20 controlled Korean/English UI-style fixtures.
- `scripts/run_ocr_fixture_benchmark.py` records aggregate CER and latency metrics for the corpus.
- Next performance spike: replace per-request one-shot OCR subprocess calls with a persistent local OCR worker. Research target is OCR request median under 500 ms after worker ready, with 20/20 fixture quality preserved and worker crash/timeout behavior documented.

## Phase 4: macOS Menu Bar Host

Goal: Implement menu bar app, hotkey, region capture, permission state, and clipboard write.

Exit criteria:
- App launches as menu bar utility.
- `Cmd+Shift+0` starts capture.
- OCR success writes text to clipboard.
- Permission failures are visible and actionable.

Current status: MVP workflow verified locally. `ScreenOCRApp` builds with menu bar item, verified hotkey registration, Screen Recording preflight/request, transparent region selection overlay, ScreenCaptureKit capture adapter, fixture OCR-to-pasteboard path, and real capture-to-OCR pipeline wiring. Noninteractive real screen capture/OCR/clipboard smoke passes through `ScreenOCRSmoke`; scripted `Cmd+Shift+0` hotkey-to-selection-to-clipboard smoke passes through `scripts/run_hotkey_smoke.sh`; 20-cycle hotkey reliability passes through `scripts/run_hotkey_reliability.sh`; forced macOS 14 ScreenCaptureKit filter/sourceRect capture passes through `scripts/run_legacy_capture_smoke.sh`. Packaging polish and real-world corpus verification remain.

## Phase 5: Packaging And Product Verification

Goal: Make the utility installable and prove the target workflow.

Exit criteria:
- Local `.app` build artifact is produced.
- Manual smoke matrix passes.
- Quantitative report is complete.
- Remaining risks are documented.

Current status: local MVP verification is implemented. `scripts/build_app_bundle.sh` creates `dist/Screen OCR.app`, `scripts/verify_app_bundle.sh` validates bundle metadata and OCR root linkage, `scripts/sign_app_bundle.sh` applies an ad-hoc local signature, `scripts/verify_app_signature.sh` verifies the ad-hoc signature, and `scripts/run_app_bundle_smoke.sh` verifies the signed bundle executable registers the hotkey when launched from outside the repository root. `SCREEN_OCR_EMBED_RUNTIME=1 scripts/build_app_bundle.sh` embeds OCR Python packages, Python.framework, sidecar source, and fixtures; `scripts/run_embedded_fixture_smoke.sh` verifies fixture OCR from bundle resources. `.github/workflows/unsigned-release.yml` validates pull requests and builds/publishes an ad-hoc signed, non-notarized GitHub Release artifact when a `VERSION` change is merged to `main` or when manually dispatched. `scripts/final_acceptance.sh` ties the local gate, screen smoke, hotkey smoke, legacy capture smoke, bundle smoke, embedded OCR-resource smoke, signature verification, and quantitative artifact assertions together. Repeated local workflow reliability is measured at 20/20 passed. Developer ID signing, notarization, and stapling remain optional future work only if a verified Gatekeeper experience is needed.
