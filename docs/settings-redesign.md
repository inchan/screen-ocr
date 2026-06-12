# Settings Redesign

Last updated: 2026-06-11.

## Goal

Redesign the settings window from a single mixed form into a macOS-style two-pane layout:

- left sidebar for category navigation,
- right detail pane for the selected category,
- no detail title or explanatory hero text because the sidebar already gives the page context,
- simple, consistent form sections and rows.

## Language Rule

Settings UI text follows the OS preferred language:

- Korean OS language: Korean labels.
- Any non-Korean OS language: English labels.
- Product and engine names remain unchanged: `Screen OCR`, `PaddleOCR`, `Apple Vision`.

This redesign localizes the settings window only. Menu-bar status strings, diagnostics, artifacts, and OCR result files stay outside this slice.

## Categories

### General

Sections:

- Launch
  - Open at login
- Save
  - Save screenshots
  - Save text results
  - Save location: path, change button, open button
  - Retention
- Display
  - Show progress popup: unchecked by default on first launch

The app records saved outputs, but settings does not show a history or record browser.

### Capture

Sections:

- Shortcut
  - Capture shortcut
  - Existing inline conflict feedback stays local to the shortcut recorder flow.
- Permission
  - Screen Recording permission status
  - Open Screen Recording settings button
  - When Screen Recording permission is missing, opening Settings selects this Capture page automatically.

### Engine

Sections:

- OCR Engine
  - Engine selector: `PaddleOCR`, `Apple Vision`
  - `Apple Vision` is disabled when the platform does not support Vision.
- PaddleOCR
  - Worker count selector: `Auto`, `1...10`
  - Shown only when `PaddleOCR` is selected.
  - `Auto` keeps the existing CPU-count worker calculation by not setting `SCREEN_OCR_REC_WORKERS`.

## Layout Rules

- Window default size: fit the current settings content without crowding.
- Window is resizable, with a practical minimum size.
- Sidebar width: about 180 pt.
- Sidebar item height: 32 pt.
- Sidebar icons are simple SF Symbols used as identifiers, not decoration.
- Detail pane starts directly with sections; no page title, no page description.
- Section title: 13 pt semibold.
- Row shape: fixed-width label, control, optional short help text.
- Row gap: 12-14 pt.
- Section gap: about 24 pt.
- No nested cards and no marketing-style content.
- Changes apply immediately when a control changes. Settings that affect a future process, such as PaddleOCR worker count, state that constraint in help text.

## Wireframes

### General

```text
+--------------------+----------------------------------------------+
|  gear  General     |  Launch                                      |
|  view  Capture     |    Login Item       [x] Open at login        |
|  cpu   Engine      |                                              |
|                    |  Save                                        |
|                    |    Save Items       [x] Save screenshots     |
|                    |                     [x] Save text results   |
|                    |    Save Location    ~/.../captures [Change] |
|                    |                                      [Open]  |
|                    |    Retention        [1 day v] after delete  |
|                    |                                              |
|                    |  Display                                     |
|                    |    Progress        [ ] Show progress popup  |
+--------------------+----------------------------------------------+
```

### Capture

```text
+--------------------+----------------------------------------------+
|  gear  General     |  Shortcut                                    |
|  view  Capture     |    Capture Shortcut    [   Shift-Command-0 ] |
|  cpu   Engine      |                                              |
|                    |  Permission                                  |
|                    |    Screen Recording   Required              |
|                    |                       [Open Settings...]    |
+--------------------+----------------------------------------------+
```

### Engine

```text
+--------------------+----------------------------------------------+
|  gear  General     |  OCR Engine                                  |
|  view  Capture     |    Engine          [PaddleOCR v]             |
|  cpu   Engine      |                                              |
|                    |  PaddleOCR                                   |
|                    |    Workers         [Auto (CPU based) v]      |
|                    |                    Applies to the next       |
|                    |                    PaddleOCR worker.         |
+--------------------+----------------------------------------------+
```

When `Apple Vision` is selected, the `PaddleOCR` section is hidden.
