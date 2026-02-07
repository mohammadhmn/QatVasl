# Zero to Running QatVasl (Beginner Guide)

This guide is for people who have never built a Swift/macOS app before.

## 1) What You Need

- A Mac.
- Xcode installed from the App Store.
- Optional but recommended: `just` command runner.

Install `just`:

```bash
brew install just
```

## 2) Open the Project

From Finder:

1. Go to the repo folder.
2. Open `QatVasl.xcodeproj`.

From terminal:

```bash
open QatVasl.xcodeproj
```

## 3) First Build and Run (Xcode)

1. In Xcode, select scheme `QatVasl`.
2. Select target device `My Mac`.
3. Press `⌘R` (Run).

What should happen:

- App launches.
- A new menu bar item appears (status icon + short label like `CHK`, `OFF`, `DEG`, `OK`).
- Dashboard window opens.

## 4) Daily Run (Terminal Way)

From repo root:

```bash
just dev
```

Useful commands:

- Debug build: `just build-debug`
- Release build: `just build-release`
- Clean: `just clean`

## 5) How to Use the App

### Menu bar popover

Click menu bar item to open quick panel:

- Current state summary
- Probe results
- Route mode (`DIRECT`, `VPN`, `PROXY`, `VPN + PROXY`)
- Detected VPN client label (best effort)
- Buttons: `Refresh`, `Settings`, `Dashboard`

### Dashboard

Sidebar sections:

- Overview
- Probes
- Services
- Timeline
- Settings

Use `Refresh Now` when you change ISP/VPN and want immediate recheck.

### Settings

Configure:

- Interval and timeout
- Probe target URLs
- Proxy host/port/type
- ISP profiles
- Critical services list
- Notifications
  - cooldown
  - quiet hours
- Launch at login

## 6) Important Behavior (Not a Bug)

When you press `⌘W` on dashboard:

- Dashboard closes.
- App disappears from Dock.
- App **stays alive in menu bar**.

This is intentional so QatVasl behaves like a true menu-bar utility.

## 7) Recommended First Configuration

If using Happ/V2Ray locally:

- Proxy type: `SOCKS5`
- Host: `127.0.0.1`
- Port: `10808`
- Keep default targets initially.

Then:

1. Connect VPN.
2. Press `Refresh`.
3. Check if state becomes `USABLE`.

## 8) Understanding Status Quickly

- `CHECKING`: running probes now.
- `OFFLINE`: no reliable route.
- `DEGRADED`: partial connectivity only.
- `USABLE`: internet is currently usable.

Use route indicators (`DIRECT`, `VPN`, `PROXY`) and diagnosis text to understand exactly which path works.

## 9) Diagnostics Export

From dashboard overview:

1. Click `Export report`.
2. Save generated `.txt` file.
3. Share/report it for troubleshooting.

## 10) Where Settings Are Stored

QatVasl stores settings in macOS user defaults.

Reset settings:

```bash
just reset-settings
```

## 11) Next Steps

If you now want to understand code:

- Read `docs/05-swift-swiftui-macos-primer.md`.
