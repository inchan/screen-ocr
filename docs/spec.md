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
- Default shortcut: `Cmd+Shift+0` through `RegisterEventHotKey`.
- Capture: ScreenCaptureKit region capture. The implementation uses direct display-agnostic rect capture on macOS 15.2+ and a display-filter/sourceRect fallback for macOS 14+.
- OCR: local Python PaddleOCR sidecar.
- Default language profile: Korean plus English.
- Distribution target: local development `.app` bundle with ad-hoc local signing first, embedded OCR-resource bundle next, fully standalone signed Developer ID distribution later.

## Clipboard Contract

On OCR success, the clipboard contains recognized plain text.

On clipboard write success, the app shows a short-lived nonactivating confirmation toast anchored below the menu bar status item. The toast message is `📋 Copied to clipboard`.

On OCR failure, the app must not silently destroy useful state. The implementation should preserve the captured image when feasible, expose the failure in menu status, and write diagnostics.

## Permissions

The app must detect and explain missing screen capture permissions. If the chosen global hotkey path requires Accessibility or Input Monitoring permission, the app must detect and expose that state.

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
