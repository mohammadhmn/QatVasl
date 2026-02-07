# QatVasl

QatVasl is a native macOS menu bar app for monitoring unstable or restricted internet connectivity.

It is built for users who frequently switch between direct internet, VPN, and local proxy routes and need a fast, reliable signal of "is my network usable right now?".

## Highlights

- Native macOS menu bar app (SwiftUI)
- Continuous connectivity probe cycles
- Clear status model: `CHECKING`, `USABLE`, `DEGRADED`, `OFFLINE`
- Route awareness: `DIRECT`, `VPN`, `PROXY`, `VPN + PROXY`
- Service checks for direct and proxy paths
- Dashboard with health, diagnostics, and timeline metrics
- Stays active in the menu bar when window closes

## How It Works

Each probe cycle checks multiple endpoints and route signals, then computes:

- A top-level connectivity state (usable/degraded/offline)
- Active route interpretation (direct/vpn/proxy/both)
- Actionable diagnostics for quick troubleshooting

Default checks include:

- Domestic reachability: `https://www.aparat.com/`
- Global reachability: `https://www.google.com/generate_204`
- Restricted direct route: `https://web.telegram.org/`
- Proxy endpoint: `127.0.0.1:10808` (SOCKS5)

## Tech Stack

- Swift
- SwiftUI
- Xcode project-based build
- `just` task runner for local workflows

## Getting Started

### Requirements

- macOS
- Xcode
- `just` (optional, recommended)

Install `just`:

```bash
brew install just
```

### Run in Xcode

1. Open `QatVasl.xcodeproj`
2. Select scheme `QatVasl`
3. Press `Cmd+R`

### Run from Terminal

```bash
just dev
```

## Common Commands

```bash
just doctor         # Check Xcode setup and project schemes
just dev            # Build/run Debug
just build-debug    # Debug build
just build-release  # Release build
just dmg            # Build dmg in build/dist/
just logs           # Stream app logs
just reset-settings # Reset app defaults
```

## Project Structure

- `QatVasl/` application source code
- `QatVasl.xcodeproj/` Xcode project
- `docs/` onboarding, architecture notes, troubleshooting, roadmap
- `justfile` development and packaging commands

## Documentation

Start at `docs/README.md`.

Recommended order for new contributors:

1. `docs/04-zero-to-running-qatvasl.md`
2. `docs/05-swift-swiftui-macos-primer.md`
3. `docs/06-codebase-walkthrough.md`
4. `docs/07-build-run-package-playbook.md`
5. `docs/08-troubleshooting-and-faq.md`

## Contributing

Contributions are welcome. Please read `CONTRIBUTING.md` first.

## Security

If you find a vulnerability, please follow `SECURITY.md`.

## License

MIT License. See `LICENSE`.
