# Screen OCR

macOS menu bar utility for region OCR.

When the app is running, press `Cmd+Shift+0`, drag a screen region, and release. The app captures the region with ScreenCaptureKit, runs local PaddleOCR, and writes the recognized text to the macOS clipboard.

## Stack

- Swift/AppKit menu bar host
- Carbon `RegisterEventHotKey` for `Cmd+Shift+0`
- ScreenCaptureKit region capture with a direct macOS 15.2+ path and a macOS 14+ filter/sourceRect fallback
- Python 3.12 PaddleOCR sidecar using `paddleocr==3.6.0` and `paddlepaddle==3.3.0`

## Documentation

See `docs/README.md` for the agent starting map, current canonical facts,
search keywords, product specs, decisions, validation evidence, release notes,
and design artifacts.

## Setup

```sh
scripts/setup_ocr_env.sh
scripts/verify_ocr_runtime.sh
```

The local OCR runtime lives in `.venv-ocr`. The default system `python3` is not used because the current local default is outside PaddlePaddle's supported macOS Python range.

## Debug Outputs

Every `Cmd+Shift+0` capture writes a paired debug copy under `artifacts/debug-runs/`:

- `<run-id>.png`: captured screenshot
- `<run-id>.txt`: OCR text copied from that screenshot
- `<run-id>.json`: manifest linking the image and text paths
- `latest-pair.json`: latest debug pair manifest

## Run

```sh
scripts/run_app.sh
```

The first real capture may require macOS Screen Recording permission. After granting it, run the app again and press `Cmd+Shift+0`.

## Build Local App Bundle

```sh
scripts/build_app_bundle.sh
scripts/sign_app_bundle.sh
open "dist/Screen OCR.app"
```

The local bundle points back to this project directory for `.venv-ocr`, the Python sidecar, and diagnostics artifacts. `scripts/sign_app_bundle.sh` applies an ad-hoc local development signature by default. It is not a Developer ID distribution signature.

To build a heavier bundle that embeds the OCR Python packages, sidecar, and fixtures instead of pointing back to the project directory:

```sh
SCREEN_OCR_EMBED_RUNTIME=1 scripts/build_app_bundle.sh
scripts/sign_app_bundle.sh
scripts/verify_embedded_runtime_bundle.sh
scripts/run_embedded_fixture_smoke.sh
```

This embedded bundle includes a bundled Python.framework plus the PaddleOCR
Python packages, so PaddleOCR and Apple Vision can both remain selectable in an
unauthenticated distribution build.

## Unsigned Distribution

This project can produce an ad-hoc signed, non-notarized GitHub Release without
an Apple Developer account:

```sh
SCREEN_OCR_EMBED_RUNTIME=1 SCREEN_OCR_CODESIGN_IDENTITY=- scripts/build_app_bundle.sh
scripts/verify_embedded_runtime_bundle.sh
scripts/verify_app_signature.sh
ditto -c -k --sequesterRsrc --keepParent "dist/Screen OCR.app" "dist/Screen-OCR-unsigned.zip"
```

macOS Gatekeeper will warn that the developer cannot be verified. Users must
explicitly allow first launch through Finder's Open flow or System Settings >
Privacy & Security > Open Anyway. See `docs/release-unsigned.md`.

## Verify

```sh
scripts/agent_gate.sh
scripts/run_screen_smoke.sh
scripts/run_hotkey_smoke.sh
scripts/run_capture_alignment_smoke.sh
scripts/run_legacy_capture_smoke.sh
scripts/run_hotkey_reliability.sh
scripts/run_app_bundle_smoke.sh
scripts/run_embedded_fixture_smoke.sh
scripts/run_ocr_fixture_benchmark.py
scripts/verify_app_signature.sh
scripts/final_acceptance.sh
```

`scripts/run_hotkey_smoke.sh` sends real local keyboard and mouse events, so it requires Accessibility permission for the terminal/Codex host process.
`scripts/run_capture_alignment_smoke.sh` opens a fixture with red/green/blue/yellow corner markers, triggers `Cmd+Shift+0`, drags the content area, and verifies the saved debug PNG by pixel quadrant. Use it when changing selection or ScreenCaptureKit coordinates:

```sh
scripts/run_capture_alignment_smoke.sh
SCREEN_OCR_FORCE_LEGACY_CAPTURE=1 scripts/run_capture_alignment_smoke.sh
SCREEN_OCR_FIXTURE_ORIGIN_Y=120 scripts/run_capture_alignment_smoke.sh
SCREEN_OCR_FIXTURE_ORIGIN_Y=120 SCREEN_OCR_FORCE_LEGACY_CAPTURE=1 scripts/run_capture_alignment_smoke.sh
```

The OCR benchmark currently covers 20 controlled Korean/English UI-style fixtures and writes aggregate CER/latency metrics to `artifacts/ocr/latest-benchmark.json`.
The hotkey reliability runner defaults to 20 end-to-end runs and writes success-rate metrics to `artifacts/hotkey/latest-reliability.json`.

## Current Limits

- Region capture has a direct macOS 15.2+ path and a ScreenCaptureKit filter/sourceRect fallback for macOS 14+; the fallback has been forced and verified on the local host, but still needs a real macOS 14 host smoke before release.
- Developer ID signing/notarization is not required for the unsigned release path, but Gatekeeper manual approval is expected. Real-world screenshot corpus collection is still a roadmap item.
