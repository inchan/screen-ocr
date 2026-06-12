# Product Specification

## Product

Screen OCR is a macOS menu bar utility that captures a selected screen region, recognizes text with local PaddleOCR, and copies recognized text to the clipboard.

## Users

Primary user: a macOS user who repeatedly needs to extract Korean and English text from apps, images, documents, websites, or screenshots without opening a heavyweight OCR tool.

## Core Behavior

1. The user presses `Cmd+Shift+0`.
2. The app starts a region selection capture flow if the shortcut is registered.
3. The user selects a rectangular screen region.
4. The app obtains an image for that region.
5. The OCR sidecar reads the image with local PaddleOCR.
6. The app normalizes recognized text.
7. The app writes recognized text to the clipboard.
8. The app briefly shows `📋 Copied to clipboard` below the menu bar item when clipboard copy succeeds.
9. The menu bar status reflects success, failure, or permission-required state.

## Implementation Shape

- Host app: native macOS menu-bar utility.
- Default UI: `MenuBarExtra` or `NSStatusItem` with `LSUIElement=true`.
- Settings UI: macOS-style two-pane window with a left sidebar (`General`, `Capture`, `Engine`) and right-side sectioned form details. Settings text follows OS language: Korean for Korean OS language, English otherwise.
- Settings > General shows app version and update controls at the bottom. Automatic update checks default to off. Manual checks are always user initiated, automatic download/install is disabled, and installing a prepared update requires an explicit install/restart action.
- Default shortcut: `Cmd+Shift+0` through `RegisterEventHotKey`.
- Capture: ScreenCaptureKit region capture. The implementation uses direct display-agnostic rect capture on macOS 15.2+ and a display-filter/sourceRect fallback for macOS 14+.
- OCR: local Python PaddleOCR sidecar by default; Apple Vision may be selected on macOS where the Vision framework is available.
- Default language profile: Korean plus English.
- Distribution target: unauthenticated `.app` zip distribution is supported through an ad-hoc signed, non-notarized embedded runtime bundle. It keeps both PaddleOCR and Apple Vision selectable. macOS Gatekeeper warning and manual user approval are expected without Developer ID signing/notarization.

## OCR Worker Contract

- The app reuses a long-lived PaddleOCR worker over JSONL (one request, one newline-delimited response). The Swift client reads responses with a buffered line reader.
- Each OCR request is bounded by a hard timeout. On timeout the worker process is terminated and the next request restarts it, so a hung worker never freezes the menu-bar app.
- The worker response carries `text` and per-line `{text, score}`; it omits detection `box` polygons because the app does not consume them. The one-shot `screen_ocr_sidecar.ocr` CLI still emits `box`.
- Settings expose the OCR engine. PaddleOCR remains the default; Apple Vision is disabled on platforms where Vision is unavailable.
- Updates are checked through a Sparkle appcast, not the GitHub Releases API. GitHub Releases host the downloadable unsigned artifact; `docs/appcast.xml` is the stable feed served through GitHub Pages. Automatic update checks are only supported from an installed app under `/Applications`; other locations should show a move-to-Applications guidance state instead of starting Sparkle.
- When PaddleOCR is selected, settings expose a Paddle worker-count control. The default `Auto` mode does not set `SCREEN_OCR_REC_WORKERS`, so the Python worker uses its existing CPU-count heuristic. Numeric values set `SCREEN_OCR_REC_WORKERS` for the next Paddle worker process.

### Configuration knobs (environment variables)

- `SCREEN_OCR_OCR_TIMEOUT_MS`: hard per-request OCR timeout in milliseconds. Default `15000`. Unset or non-positive falls back to the default.
- `SCREEN_OCR_MIN_LINE_SCORE`: opt-in minimum recognition confidence; lines below it are dropped from text and line count. Default unset → no filtering (current behavior). Invalid values are ignored.
- `SCREEN_OCR_PROJECT_ROOT`, `SCREEN_OCR_ARTIFACT_ROOT`, `SCREEN_OCR_FORCE_LEGACY_CAPTURE`: existing path/capture overrides (unchanged).

## Clipboard Contract

On OCR success, the clipboard contains recognized plain text.

On clipboard write success, the app shows a short-lived nonactivating confirmation toast anchored below the menu bar status item. The toast message is `📋 Copied to clipboard`.

On OCR failure, the app must not silently destroy useful state. The implementation should preserve the captured image when feasible, expose the failure in menu status, and write diagnostics.

## Permissions

The app must detect and explain missing screen capture permissions. If the chosen global hotkey path requires Accessibility or Input Monitoring permission, the app must detect and expose that state.

When Screen Recording permission is missing, opening app Settings must land on the `Capture` detail page so the permission controls are immediately visible. The guided System Settings helper is placed next to System Settings when possible; its visible content must stay minimal: the draggable app icon, a large left-pointing arrow aligned with the instruction text, and a short instruction naming the left Screen Recording list as the drop destination.

The default shortcut path should not require Accessibility or Input Monitoring. If it does in practice, that is a regression against the MVP design and must be documented with evidence.

## Display Handling

MVP must correctly handle single-display selections. Cross-display selections may be rejected with clear UI until a tested stitching implementation exists.

## Non-Goals For MVP

- Cloud OCR.
- Full document parsing.
- Translation.
- Table reconstruction.
- Multi-page OCR.
- User accounts or sync.
- Automatic upload of screenshots.

## BDD Scenarios

```gherkin
Feature: Screen region OCR

  Scenario: Successful region OCR copies text
    Given the app is running in the menu bar
    And screen capture permission is available
    And PaddleOCR is installed locally
    When the user presses Cmd+Shift+0
    And selects a region containing "Hello 123"
    Then the clipboard should contain "Hello 123"
    And the app should show "📋 Copied to clipboard" below the menu bar item
    And the menu bar status should show success

  Scenario: OCR failure preserves useful state
    Given the app captured a selected region
    When PaddleOCR fails
    Then the app should report the failure
    And the app should preserve the captured image when feasible
    And diagnostics should include the OCR command, error, and elapsed time

  Scenario: Missing screen capture permission is actionable
    Given screen capture permission is not available
    When the user presses Cmd+Shift+0
    Then the app should not run OCR
    And the menu bar status should show that permission is required
    And opening app Settings should focus the Capture permission controls
    And the System Settings helper should show where to drag the app icon

  Scenario: Shortcut registration failure is visible
    Given Cmd+Shift+0 is unavailable
    When the app starts
    Then the menu bar status should show that the shortcut is unavailable
    And the user should be able to choose a different shortcut in a later settings flow

  Scenario: Cross-display selection is not silent
    Given the MVP does not support stitching cross-display captures
    When the user selects a region spanning multiple displays
    Then the app should reject the selection
    And the clipboard should not be overwritten with misleading OCR text
```
