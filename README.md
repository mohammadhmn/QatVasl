# QatVasl

QatVasl is a native macOS menu-bar app for monitoring unstable/restricted internet connectivity.

It is designed for environments where you constantly switch ISP and VPN configs and need quick, reliable status without manual checks.

## Quick Start

1. Open the project in Xcode:
   - `QatVasl.xcodeproj`
2. Build and run:
   - Press `⌘R` in Xcode
3. Or from terminal:
   - `just dev`

After launch, QatVasl appears in the menu bar.  
Closing dashboard window (`⌘W`) keeps QatVasl alive in menu bar and removes it from Dock.

## Probe Set

Each cycle it probes:
- Domestic reachability (default: `https://www.aparat.com/`)
- Global reachability (default: `https://www.google.com/generate_204`)
- Restricted service via direct path (default: `https://web.telegram.org/`)
- Restricted service via configured proxy endpoint (default: `127.0.0.1:10808`, SOCKS5)

## Status and Route Model

Top-level status:
- `CHECKING`: a probe cycle is in progress.
- `USABLE`: internet is currently usable for your configured workflow.
- `DEGRADED`: some routes/services work, but not enough for normal use.
- `OFFLINE`: no reliable route detected.

Route indicators:
- `DIRECT`: no system VPN route and no working proxy route.
- `VPN`: system TUN/VPN overlay route is active.
- `PROXY`: configured proxy endpoint is active and proxied probe succeeds.
- `VPN + PROXY`: both VPN and proxy route are active.

## Core Features

- Plain-language diagnosis with recommended actions.
- Critical services matrix (direct vs proxy per service).
- 24h timeline metrics (uptime, drops, latency, recovery).
- ISP profiles for quick switching.
- Notification cooldown + quiet hours.
- Diagnostics export (`Export report`) for support/debug sharing.

## Documentation Map

Start here:
- Docs index: `docs/README.md`

Core docs:
- `docs/01-context-and-requirements.md`
- `docs/02-implementation-and-worklog.md`
- `docs/03-daily-ops-checklist.md`

Beginner track (recommended for first-time Swift/macOS developers):
- `docs/04-zero-to-running-qatvasl.md`
- `docs/05-swift-swiftui-macos-primer.md`
- `docs/06-codebase-walkthrough.md`
- `docs/07-build-run-package-playbook.md`
- `docs/08-troubleshooting-and-faq.md`

## Common Commands

- `just dev`
- `just build-debug`
- `just build-release`
- `just dmg`
