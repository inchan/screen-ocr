# Icon Design Concepts

Status: exploration artifact.

## Scope

`docs/icon-design.html` contains 30 self-contained SVG icon concepts for Screen OCR:

- Eastern philosophy perspective: 10 concepts.
- French art professor perspective: 10 concepts.
- Simple-is-best perspective: 10 concepts.

The artifact is for visual review in a browser. It does not select the production app icon, generate `.icns` assets, or change app behavior.

## Design Criteria

- Communicate screen region capture, local OCR, text extraction, and clipboard readiness.
- Remain legible at small menu-bar/app-icon sizes by using simple silhouettes and high-contrast strokes.
- Keep the three requested viewpoints distinct without turning the product into a decorative landing-page style.
- Use inline SVG so the concepts can be inspected, edited, and exported without external assets.

## Current Recommendation

For a production app icon direction, start from the `Simple is Best` set, especially `Crop Text`, `Lens Text`, or `Image to Lines`. They preserve the core Screen OCR contract most clearly at small sizes.

The Eastern philosophy and French art professor sets are useful for brand tone exploration, but they should be simplified further before becoming the final menu-bar icon.
