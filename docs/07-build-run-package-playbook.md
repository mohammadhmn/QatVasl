# Build, Run, and Package Playbook

This document is the operational manual for development and release.

## 1) Prerequisites

- macOS with Xcode installed.
- Command line tools available (`xcodebuild`).
- Optional: `just` installed for short commands.

Install `just`:

```bash
brew install just
```

## 2) One-Time Sanity Check

```bash
just doctor
```

This verifies:

- Xcode version
- Project/scheme visibility

## 3) Daily Development Commands

From repo root:

- `just build-debug`  
  Build Debug configuration.
- `just run Debug`  
  Build (if needed), kill previous app process, open app.
- `just dev`  
  Shortcut for `run Debug`.
- `just clean`  
  Clean build artifacts.

## 4) Manual `xcodebuild` (Without `just`)

```bash
xcodebuild \
  -project QatVasl.xcodeproj \
  -scheme QatVasl \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 5) Release Artifact Commands

From repo root:

- `just build-release`  
  Build release binary.
- `just package-app`  
  Create distributable `.app` in `build/dist/`.
- `just dmg`  
  Build release and generate DMG in `build/dist/`.
- `just open-dmg`  
  Build DMG and open it.
- `just install`  
  Copy release app into `/Applications/QatVasl.app`.

## 6) Logging and Diagnostics

- Live logs:

```bash
just logs
```

- Reset settings to defaults:

```bash
just reset-settings
```

## 7) Recommended Release Checklist

1. `just clean`
2. `just build-debug`
3. Launch and smoke test:
   - menu bar appears
   - refresh works
   - settings persist
   - notifications behave correctly
4. `just build-release`
5. `just dmg`
6. Test install from produced DMG.

## 8) Build Output Paths

- Debug app: `build/DerivedData/Build/Products/Debug/QatVasl.app`
- Release app: `build/DerivedData/Build/Products/Release/QatVasl.app`
- DMG: `build/dist/QatVasl.dmg`

## 9) Common Build Problems

- **Scheme not found**:
  - Run `just doctor`, confirm scheme is `QatVasl`.
- **Xcode path issues**:
  - Ensure Xcode is installed and selected.
- **Stale derived data weirdness**:
  - Run `just clean` then rebuild.

For runtime issues, see `docs/08-troubleshooting-and-faq.md`.
