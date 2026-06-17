# Debugging Strategy

## Stage Boundaries

Debug by isolating stages:

1. Hotkey event received.
2. Region selection completed.
3. Image captured.
4. OCR sidecar invoked.
5. OCR JSON parsed.
6. Text normalized.
7. Clipboard written.
8. Menu status updated.

Each stage should emit a structured event once code exists.

## Required Diagnostic Fields

- timestamp
- stage
- success/failure
- elapsed milliseconds
- input image id or path
- OCR config
- subprocess exit code
- stderr summary
- recognized text count
- clipboard write status
- permission state

## Failure Playbooks

Hotkey does not fire:
- Check shortcut conflict.
- Check `RegisterEventHotKey` registration result.
- Check `artifacts/app/latest-status.json` for `hotkey_registered` or `hotkey_unavailable`.
- Check `artifacts/debug-runs/latest-pair.json` for the latest paired debug capture.
- For each `Cmd+Shift+2` run (or fallback `Cmd+Shift+0` run), inspect matching `artifacts/debug-runs/<run-id>.png` and `artifacts/debug-runs/<run-id>.txt` files.
- Accessibility/Input Monitoring should not be required for the default shortcut path; if it is, record the implementation and OS evidence.
- Verify app is running and status item is alive.

Capture fails:
- Check Screen Recording permission.
- Check whether region selection was cancelled.
- Check whether the selected region spans multiple displays.
- Check Retina/non-Retina coordinate conversion.
- Check macOS version; macOS 15.2+ uses direct `SCScreenshotManager.captureImage(in:)`, while macOS 14+ should use the ScreenCaptureKit filter/sourceRect fallback. Force the fallback on newer hosts with `SCREEN_OCR_FORCE_LEGACY_CAPTURE=1`.
- Re-run with a fixture image to separate capture from OCR.

OCR fails:
- Run Python sidecar directly on the same image.
- Run PaddlePaddle runtime check.
- Check model download/cache state.
- Compare fake OCR path to real OCR path.

Clipboard fails:
- Test pasteboard write with a static string.
- Confirm OCR text normalization output is nonempty.
- Confirm app sandbox/entitlement constraints if sandboxing is enabled.
