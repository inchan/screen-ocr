# Screen OCR Documentation

This directory is the project record for product behavior, implementation decisions, validation evidence, and release operations.

## Agent Quick Start

When joining the project or resuming after context loss, read these first:

1. `AGENTS.md` for workflow, branch policy, and verification requirements.
2. [Specification](spec.md) for the product contract.
3. [Decisions](decisions.md) for accepted/rejected technical choices.
4. [Validation Report](validation-report.md) for the freshest proof of what was
   actually verified.
5. [Test Plan](test-plan.md) for behavior gates before changing product behavior.

Current canonical facts:
- Feature work starts from `origin/develop`; implementation PRs target
  `develop`; releases happen through a `develop -> main` PR with `VERSION`.
- Default OCR engine remains `PaddleOCR`. `Apple Vision` is selectable only on
  supported macOS versions and is not the default without a representative
  exact-transcript corpus.
- PaddleOCR worker count is configurable only on the Engine settings page.
  `Auto` is the default and preserves the Python sidecar CPU-count heuristic.
- Settings use a macOS two-pane layout: General, Capture, and Engine. Saved
  output location belongs in General; capture history is recorded but not shown
  as a settings page.
- Sparkle update support is experimental. Automatic update checks are off by
  default, and Sparkle automatic download/install remains disabled.
- Historical research scripts live under `scripts/experiments/`; they are
  reproduction aids, not supported release automation.

## Search Map

Use these terms when searching the repo:

- OCR engine, Apple Vision, PaddleOCR, worker count, Auto workers:
  [Decisions](decisions.md), [Test Plan](test-plan.md),
  [Settings Redesign](settings-redesign.md), [Performance Analysis](performance-analysis.md).
- Performance, benchmark, latency, CER, real screenshot corpus:
  [Performance Analysis](performance-analysis.md), [Validation Report](validation-report.md),
  [Experiment Harnesses](../scripts/experiments/README.md).
- Settings, General, Capture, Engine, saved output location, Screen Recording:
  [Settings Redesign](settings-redesign.md), [Test Plan](test-plan.md).
- Permission popup, draggable icon, left arrow, Screen Recording list:
  [Test Plan](test-plan.md), [Feedback Loop](feedback-loop.md),
  [Debugging](debugging.md).
- Unsigned release, Gatekeeper, appcast, Sparkle, auto update, `develop -> main`:
  [Unsigned Release](release-unsigned.md), [Update Experiment](update-experiment.md),
  `.github/workflows/unsigned-release.yml`.
- Capture overlay, hotkey, ScreenCaptureKit, macOS 14 fallback, window ordering:
  [Specification](spec.md), [Decisions](decisions.md), [Test Plan](test-plan.md),
  [Validation Report](validation-report.md).

## Product And Planning

- [Research](research.md): external and local research notes.
- [Decisions](decisions.md): accepted and rejected technical/product decisions.
- [Specification](spec.md): product behavior, permissions, data flow, and non-goals.
- [Test Plan](test-plan.md): behavior scenarios, fixtures, and metric families.
- [Roadmap](roadmap.md): staged delivery plan.
- [Completion Audit](completion-audit.md): requirement coverage against evidence.

## Runtime And Debugging

- [Debugging](debugging.md): diagnostic capture contract and failure evidence.
- [Autonomous System](autonomous-system.md): agent operating model for this repo.
- [Feedback Loop](feedback-loop.md): adopted process improvements.
- [Validation Report](validation-report.md): latest verification commands and results.

## Release And Distribution

- [Unsigned Release](release-unsigned.md): ad-hoc signed distribution without Apple Developer ID notarization.
- [Appcast](appcast.xml): Sparkle-compatible update feed used by the experimental updater.
- [Update Experiment](update-experiment.md): experimental automatic update design and reversibility notes.

## UI And Design

- [Settings Redesign](settings-redesign.md): settings IA, layout, and interaction rules.
- [Icon Design](icon-design.md): menu bar/app icon design notes.
- [Icon Design Preview](icon-design.html): static local preview for the icon concept.

## Performance

- [Performance Analysis](performance-analysis.md): OCR engine performance and experiment notes.
- [Experiment Harnesses](../scripts/experiments/README.md): historical, non-gate reproduction scripts for OCR research.
