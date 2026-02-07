# QatVasl: Implementation and Worklog

Date: 2026-02-07

## Current Architecture (Native App)

QatVasl is implemented as a native SwiftUI macOS app in:

- `QatVasl/`

Core runtime components:

- `QatVaslApp.swift`: app entry point, menu bar scene, dashboard scene, settings scene.
- `NetworkMonitor.swift`: probe loop, route detection, state evaluation, notifications.
- `NetworkModels.swift`: state enums, settings model, probe and history models.
- `SettingsStore.swift`: persistence + launch-at-login toggling.
- `ContentView.swift`: dashboard UI.
- `MenuBarContentView.swift`: menu bar popover UI.
- `SettingsView.swift`: settings UI.
- `DashboardComponents.swift`: reusable UI building blocks.
- `QatVasl/justfile`: build/run/package automation commands.

## Feature Set Implemented

- Menu bar status with compact label (`OFF`, `IR`, `LMT`, `VPN`, `OPEN`) and colored dot.
- Dashboard with:
  - overview,
  - probes,
  - transition timeline,
  - settings shortcut.
- Route context detection:
  - system VPN-route detection,
  - system proxy detection,
  - best-effort VPN client label (service/process based).
- Connectivity probes:
  - domestic,
  - global,
  - blocked direct,
  - blocked via proxy.
- Notifications on connectivity transitions.
- Launch-at-login toggle.
- Close dashboard with `⌘W` while app stays in menu bar.

## Connectivity State Model

- `OFFLINE`: no reliable connectivity
- `IR ONLY`: domestic up, global down
- `LIMITED`: global up, blocked target down
- `VPN OK`: blocked target reachable through configured proxy
- `VPN/PROXY`: system VPN/proxy active, direct-path verdict not authoritative
- `OPEN`: blocked target reachable directly

## Performance Work Completed

Recent optimizations to improve responsiveness:

- Route detection moved off main actor with short-lived cache.
- `URLSession` reuse for direct and proxy probes (instead of per-request session creation).
- Lightweight `HEAD` probe requests with cache bypass.
- Reduced redundant `@Published` writes.
- Debounced settings persistence and monitor restarts while editing fields.

## UX Work Completed

- Improved menu bar readability with compact status label and dot.
- Sidebar-based dashboard layout.
- Settings button behavior fixed and wired.
- App activation policy management:
  - dashboard visible => Dock app visible,
  - dashboard closed => menu-bar-only behavior.

## Build/Run/Package Tooling

`justfile` includes:

- `build-debug`, `build-release`
- `run`, `dev`
- `clean`
- `archive`
- `package-app`
- `dmg`, `open-dmg`
- `install`
- `logs`
- `reset-settings`

## Suggested Next Iterations

- Per-ISP profile presets and quick switcher.
- Persistent route-quality trend charts.
- Optional repeated alerts for prolonged degraded states.
- Export/import settings profiles.
- Optional richer diagnostics panel (active interfaces, recent failures, proxy latency trend).
