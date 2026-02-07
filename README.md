# QatVasl

QatVasl is a native macOS menu-bar app for monitoring unstable/restricted internet connectivity.

It is designed for environments where you constantly switch ISP and VPN configs and need quick, reliable status without manual checks.

## Quick Start (Native App)

1. Open the project in Xcode:
   - `QatVasl.xcodeproj`
2. Build and run:
   - Press `⌘R` in Xcode
3. Or from terminal:
   - `just dev`

After launch, QatVasl appears in the menu bar.  
Closing dashboard window (`⌘W`) keeps QatVasl alive in menu bar and removes it from Dock.

## What QatVasl Monitors

Each cycle it probes:
- Domestic reachability (default: `https://www.aparat.com/`)
- Global reachability (default: `https://www.google.com/generate_204`)
- Blocked target directly (default: `https://web.telegram.org/`)
- Blocked target through your local proxy/VPN endpoint (default: `127.0.0.1:10808`, SOCKS5)

Connectivity states:
- `OFF` / `OFFLINE`: no reliable route
- `IR` / `IR ONLY`: domestic works, global fails
- `LMT` / `LIMITED`: global works, blocked target fails
- `VPN` / `VPN OK`: blocked target works through proxy
- `VPN` / `VPN/PROXY`: system VPN/proxy overlay is active (direct-path verdict paused)
- `OPEN`: blocked target works without proxy

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
