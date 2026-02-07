# QatVasl Codebase Walkthrough

This guide explains how the app is organized and where to edit specific behaviors.

## 1) Project Layout

- Native app root: `QatVasl/`
- Xcode project: `QatVasl.xcodeproj`
- Build automation: `justfile`

Primary source files:

- `QatVasl/QatVaslApp.swift`
- `QatVasl/NetworkMonitor.swift`
- `QatVasl/NetworkModels.swift`
- `QatVasl/SettingsStore.swift`
- `QatVasl/ContentView.swift`
- `QatVasl/MenuBarContentView.swift`
- `QatVasl/SettingsView.swift`
- `QatVasl/DashboardComponents.swift`

## 2) Entry Point and App Scenes

File: `QatVasl/QatVaslApp.swift`

Responsibilities:

- Creates shared app state (`SettingsStore`, `NetworkMonitor`).
- Declares scenes:
  - dashboard window,
  - menu bar popover,
  - settings window.
- Manages Dock/menu-bar-only behavior through activation policy.

If you need to change app lifecycle behavior, start here.

## 3) Monitoring Engine

File: `QatVasl/NetworkMonitor.swift`

Responsibilities:

- Runs periodic loop (`restartLoop`, `runCheck`).
- Detects route context:
  - VPN route active?
  - system proxy active?
  - likely VPN client name?
- Runs four probes.
- Evaluates final `ConnectivityState`.
- Tracks transition history.
- Sends notifications on degrade/recovery.

### Data published to UI

`@Published` values used by views:

- `currentState`
- `lastSnapshot`
- `lastCheckedAt`
- `isChecking`
- `transitionHistory`
- `tunnelDetected`
- `systemProxyDetected`
- `vpnClientLabel`

### Performance-sensitive sections

- Route detection is executed off-main with short cache.
- Network sessions are reused.
- Settings-triggered restarts are debounced.

## 4) Domain Models

File: `QatVasl/NetworkModels.swift`

Contains:

- `ConnectivityState`
- `MonitorSettings`
- `ProxyType`
- `ProbeResult`
- `ProbeSnapshot`
- `StateTransition`
- `SettingsPreset`

This file is your first stop for changing:

- status names,
- default URLs,
- default interval/timeout,
- proxy defaults,
- state detail text and suggested actions.

## 5) Persistence and Settings Logic

File: `QatVasl/SettingsStore.swift`

Responsibilities:

- Load settings from `UserDefaults`.
- Persist settings (debounced).
- Apply presets.
- Reset to defaults.
- Manage launch-at-login toggling.

## 6) UI Surfaces

### Dashboard UI

File: `QatVasl/ContentView.swift`

Contains:

- Sidebar navigation.
- Hero status area.
- Probe cards.
- Transition timeline.
- Settings shortcuts.

### Menu bar popover UI

File: `QatVasl/MenuBarContentView.swift`

Contains compact operational panel:

- current state,
- probe summaries,
- route mode/client,
- quick actions.

### Settings UI

File: `QatVasl/SettingsView.swift`

Contains editable controls for monitor and proxy behavior.

### Shared visual components

File: `QatVasl/DashboardComponents.swift`

Contains reusable components:

- `GlassCard`
- `StatusPill`
- `StateGlyph`
- `ProbeMetricCard`

## 7) State Evaluation Logic (Operationally Important)

In `NetworkMonitor.evaluate(...)`:

1. If VPN/proxy overlay is active:
   - any reachable probe => `VPN/PROXY`
   - else => `OFFLINE`
2. If no overlay:
   - blocked direct reachable => `OPEN`
   - else blocked via proxy reachable => `VPN OK`
   - else domestic yes + global no => `IR ONLY`
   - else global yes => `LIMITED`
   - else => `OFFLINE`

This ordering defines how QatVasl interprets network reality.

## 8) How to Add a Feature Safely

Example: add a new probe target.

1. Add model field in `MonitorSettings` and defaults.
2. Add UI field in `SettingsView`.
3. Add probe call in `NetworkMonitor.runCheck`.
4. Extend `ProbeSnapshot` and UI rendering.
5. Rebuild and validate.

## 9) Common Edit Recipes

- Change default proxy port:
  - `QatVasl/NetworkModels.swift`
- Change app launch behavior:
  - `QatVasl/QatVaslApp.swift`
- Change notification wording:
  - `QatVasl/NetworkMonitor.swift`
- Change menu bar UI text:
  - `QatVasl/MenuBarContentView.swift`

## 10) Recommended Reading Sequence for New Contributors

1. `QatVaslApp.swift`
2. `NetworkModels.swift`
3. `NetworkMonitor.swift`
4. `ContentView.swift`
5. `SettingsView.swift`
