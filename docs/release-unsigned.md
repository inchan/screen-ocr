# Unsigned Distribution

## Goal

Distribute Screen OCR without an Apple Developer account, Developer ID
certificate, or notarization, while keeping both OCR engines available:

- PaddleOCR remains available through the embedded Python/Paddle runtime.
- Apple Vision remains selectable on supported macOS versions.

## User Experience

Unsigned distribution is possible, but macOS Gatekeeper will warn that the
developer cannot be verified. Users must explicitly allow the app through
Finder's Open flow or System Settings > Privacy & Security > Open Anyway.

Apple references:

- https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Build Shape

The unsigned release artifact is:

1. A release-built `Screen OCR.app`.
2. Ad-hoc signed with `codesign --sign -`.
3. Not notarized.
4. Packaged as a `.zip` with `ditto --sequesterRsrc --keepParent`.
5. Accompanied by a SHA-256 checksum.

The embedded runtime bundle includes:

- `Contents/Resources/python-runtime` for Python packages and PaddleOCR deps.
- `Contents/Frameworks/Python.framework` for the Python interpreter.
- `Contents/Resources/sidecar` for the OCR sidecar source.
- `Contents/Resources/fixtures` for fixture verification.

`scripts/build_app_bundle.sh` patches the embedded Python launcher to load the
Python framework from inside the app bundle instead of the build machine.

## GitHub Actions

`.github/workflows/unsigned-release.yml` provides two paths:

- Pull requests: build/test Swift and run layout smokes.
- Main merges: when `VERSION` changes on `main`, build the embedded runtime
  bundle, verify it, zip it, upload it as an artifact, and publish/update a
  GitHub Release named `v<VERSION>`.
- Manual dispatch: optionally build/publish a specific version without changing
  `VERSION`.

No Apple secrets are required. The workflow only uses GitHub's built-in token to
create or update the GitHub Release.

## Limits

- Gatekeeper warning is expected and cannot be removed without Developer ID
  signing and notarization.
- Users must trust the release source and manually allow first launch.
- Screen Recording permission is still required for real capture.
- Each ad-hoc signed build has a different identity/hash, so users may need to
  re-approve permissions after updating.
