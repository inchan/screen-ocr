# Research Log

Last updated: 2026-06-05.

This log stores externally verified facts and separates them from implementation decisions.

## PaddleOCR Facts

Sources:
- PaddleOCR releases: https://github.com/PaddlePaddle/PaddleOCR/releases
- PaddleOCR installation: https://www.paddleocr.ai/latest/en/version3.x/installation.html
- PaddleOCR OCR pipeline usage: https://www.paddleocr.ai/main/en/version3.x/pipeline_usage/OCR.html
- PaddleOCR high-performance inference: https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/deployment/high_performance_inference.en.md
- PaddlePaddle macOS pip install: https://www.paddlepaddle.org.cn/documentation/docs/install/pip/macos-pip_en.html

Current fact snapshot:
- PaddleOCR latest observed release is `v3.6.0`, released 2026-05-28.
- Base install path is `python -m pip install paddleocr`; heavier optional extras are not needed for simple screen OCR.
- PaddlePaddle macOS pip docs describe CPU-only local install on 64-bit arm64, Python 3.9-3.13, with `paddlepaddle==3.3.0`.
- Local OCR can use the Python API with `from paddleocr import PaddleOCR` and `ocr.predict(image_path)`.
- Hosted PaddleOCR API paths require credentials and network access; they are not the default for private screen OCR.
- For Korean plus English screenshots, use a Korean-capable OCR profile and verify with mixed fixtures.
- The starting pinned runtime is Python 3.11 or 3.12 arm64, `paddleocr==3.6.0`, and `paddlepaddle==3.3.0`, subject to install verification.
- The sidecar output contract should normalize PaddleOCR output to `[{ "text": string, "score": number, "box": [[number, number], ...] }]`.
- PaddleOCR 3.x `predict()` exposes per-call detector controls including `text_det_limit_side_len` and `text_det_limit_type`; these can be measured as warm-inference knobs for small screen crops.
- PaddleOCR 3.x Python usage supports creating a `PaddleOCR(...)` object and calling `predict(...)` repeatedly. Local research measured a persistent in-process worker at 268.77 ms median request roundtrip after a one-time 4801.60 ms ready cost.
- PaddleOCR high-performance inference can be enabled with `enable_hpi=True` in the Python API, but the local runtime rejected it because `ultra-infer` is not installed. Adding that dependency is a separate dependency decision, not part of the next minimal slice.
- Inference-related settings include CPU thread count and MKL-DNN/cache controls. Local probes showed only small warm-latency movement compared with the much larger process/model reuse effect.

## Apple/macOS Facts

Sources:
- NSStatusItem: https://developer.apple.com/documentation/appkit/nsstatusitem
- NSPasteboard: https://developer.apple.com/documentation/appkit/nspasteboard
- ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit
- CGPreflightScreenCaptureAccess: https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()
- NSEvent global monitor: https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29
- CGEventTapCreate: https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29
- CGPreflightListenEventAccess: https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess%28%29
- CGRequestListenEventAccess: https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess%28%29
- macOS 15 ScreenCaptureKit release notes: https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes
- SCScreenshotManager: https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
- SCScreenshotConfiguration.sourceRect: https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/sourcerect
- Capturing screen content in macOS: https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos
- NSPasteboardTypePNG: https://developer.apple.com/documentation/appkit/nspasteboardtypepng
- MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
- LSUIElement: https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement
- Notarizing macOS software: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- App Sandbox: https://developer.apple.com/documentation/security/app_sandbox

Current fact snapshot:
- `Cmd+Shift+2` is feasible as the default global shortcut target. `Cmd+Shift+0` remains a feasible fallback, and registration can fail due to app/user/global conflicts and must be observable.
- The minimal-permission shortcut path is `RegisterEventHotKey`. Avoid `NSEvent.addGlobalMonitorForEvents` for the default path because key monitoring requires Accessibility trust and global monitors only observe events.
- Avoid `CGEventTap` unless raw event filtering becomes necessary, because event taps can require Accessibility or Input Monitoring permission.
- Screen capture should use ScreenCaptureKit rather than deprecated CoreGraphics capture APIs. macOS 15 notes call out deprecated capture API privacy warnings and migration to ScreenCaptureKit.
- Region capture should use `SCScreenshotManager` plus `SCScreenshotConfiguration.sourceRect` when the deployment target supports it.
- `sourceRect` uses display logical points. Retina/non-Retina and multi-display behavior must be tested explicitly.
- Screen Recording permission is required for ScreenCaptureKit. First-run permission grant may require relaunch before capture succeeds.
- Clipboard output should use `NSPasteboard.general` with plain text for OCR success and optionally PNG/`NSImage` when preserving captured image state.
- A menu-bar-only app can use SwiftUI `MenuBarExtra` on macOS 13+ or AppKit `NSStatusItem`. `LSUIElement=true` removes Dock and app switcher presence.
- Outside Mac App Store distribution requires Developer ID signing, hardened runtime, timestamping, notarization, and usually stapling. App Store distribution adds sandbox requirements.

## Open Research Questions

- What exact macOS deployment target gives the best balance between `SCScreenshotManager` simplicity and user reach?
- What is the smallest transparent overlay implementation for single-display region selection?
- Should MVP reject cross-display selections or stitch per-display captures?
- What packaging approach can bundle or bootstrap the Python OCR sidecar while keeping installation understandable and notarizable?
- What cold-start latency is acceptable for first OCR model load on target Macs?
- What resident-memory budget is acceptable for a preloaded OCR worker? The current measured worker RSS is about 854 MB after model load.

## Filtered-Out Paths

- Hosted OCR: rejected for default use because it requires network access, credentials, and screen-content transfer.
- `paddleocr[all]`: rejected for MVP because screen OCR does not need document parsing, information extraction, or translation extras.
- `NSEvent.addGlobalMonitorForEvents`: rejected for default hotkey capture because it increases permission burden and only observes events.
- `CGEventTap`: rejected for default hotkey capture because it is heavier and permission-sensitive.
- Deprecated CoreGraphics screen capture APIs: rejected for MVP because ScreenCaptureKit is the forward path and macOS 15 warns on deprecated capture APIs.
