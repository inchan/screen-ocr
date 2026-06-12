# Sparkle Update Experiment

Last updated: 2026-06-12.

## Goal

Experimentally add a reversible macOS update path for the unsigned GitHub
Release distribution without taking ownership of the full updater problem in
app code.

## Decisions

- Use Sparkle 2 as the updater engine.
- Hide Sparkle behind a thin `AppUpdater` wrapper so the experiment can be
  reverted by removing the wrapper, package dependency, settings section, and
  release workflow steps.
- The app reads a Sparkle appcast only. It does not call the GitHub Releases API
  directly.
- The appcast URL is `https://inchan.github.io/screen-ocr/appcast.xml`.
- Automatic update checks default to off.
- When automatic update checks are enabled, the app checks in the background
  only. Sparkle's automatic download setting is disabled because Sparkle treats
  automatic downloads as eligible for automatic installation on app termination,
  which violates the explicit install/relaunch contract.
- Version and update controls live at the bottom of Settings > General.
- The menu bar shows an install/relaunch item only when an update is ready.
- Stable semver releases are the only supported channel. GitHub prereleases and
  non-semver tags are ignored.
- Current update artifacts are arm64 only until a universal release is
  intentionally added.
- Updating from outside `/Applications` is not a supported automatic path. The
  UI should guide users to move the app first if Sparkle cannot install.

## Security

- Sparkle EdDSA update signatures are required for update archives.
- `SUAllowsAutomaticUpdates` remains `false` so Sparkle cannot silently install
  a downloaded update when the app quits.
- The public EdDSA key may be committed or injected into the bundle at build
  time.
- The private EdDSA key must never be committed. CI must read it only from the
  GitHub Actions secret `SPARKLE_PRIVATE_KEY`.
- Once update support is enabled for release builds, a missing Sparkle signing
  secret must fail the release instead of publishing unsigned update metadata.
- The unsigned distribution limits remain: Gatekeeper warning and Screen
  Recording permission re-approval can still happen after an update.

## Experiment Boundary

The first implementation proves:

- Sparkle can be linked through Swift Package Manager.
- The custom `swift build` bundle script can copy and sign `Sparkle.framework`.
- Settings can show current version, update state, manual check, automatic
  check preference, and install/relaunch entry point.
- Release automation can build with Sparkle metadata only when
  `SCREEN_OCR_ENABLE_SPARKLE_UPDATES=1`, generate a signed appcast with the
  `SPARKLE_PRIVATE_KEY` secret, and commit the regenerated `docs/appcast.xml`
  after publishing the GitHub Release.

The first implementation does not claim:

- notarized update UX,
- Intel/universal updates,
- silent installation,
- bypassing Gatekeeper,
- preserving Screen Recording permission across every update.
