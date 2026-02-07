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
- `justfile`: build/run/package automation commands.

## Feature Set Implemented

- Menu bar status with compact label (`CHK`, `OFF`, `DEG`, `OK`) and status icon.
- Dashboard with:
  - overview,
  - probes,
  - services matrix,
  - timeline,
  - settings shortcut.
- Route context detection:
  - system VPN-route detection (TUN/system overlay evidence),
  - configured proxy route detection (host/port reachable + proxied blocked-service check),
  - best-effort VPN client label (service/process based).
- Connectivity probes:
  - domestic,
  - global,
  - restricted service (direct),
  - restricted service (proxy).
- Plain-language diagnosis + recommended actions per state.
- Critical services matrix (direct/proxy checks per configured service).
- Timeline metrics over recent history (24h summary view).
- ISP profiles (save/apply/remove).
- Notifications with cooldown + quiet hours.
- Diagnostics report export from dashboard.
- Launch-at-login toggle.
- Close dashboard with `⌘W` while app stays in menu bar.

## Connectivity State Model

- `CHECKING`: monitor loop is running probes.
- `OFFLINE`: no usable route detected.
- `DEGRADED`: partial connectivity only.
- `USABLE`: route is currently usable.

Route labels:

- `DIRECT`
- `VPN`
- `PROXY`
- `VPN + PROXY`

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
- Export diagnostics action in dashboard.
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

## Remaining Work (Shortlist)

- Add automated tests for state evaluation and route classification.
- Add optional repeated reminders for prolonged outage windows.
- Add import/export for full settings + profile bundles.
