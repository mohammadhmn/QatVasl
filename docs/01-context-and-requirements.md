# QatVasl: Context and Requirements

Date: 2026-02-07

## Real-World Problem

In heavily restricted networks, internet health is not binary (`online`/`offline`):

- Domestic domains may work while global routes fail.
- Global routes may work while blocked services (for example Telegram) fail.
- VPN may connect but still be unstable.
- TUN/proxy routing can hide true direct-path behavior.
- Connection state can degrade quickly after initially succeeding.

The practical impact is severe: repeated ISP switching, VPN profile rotation, and lost work time.

## Product Goal

Build a native macOS menu-bar app that continuously answers:

1. Is direct internet usable now?
2. Is blocked traffic reachable through VPN/proxy now?
3. Did connectivity degrade or recover compared to last cycle?
4. Is system-level tunneling/proxy currently active, making direct-path verdict ambiguous?

## Functional Requirements

- Must run as a menu-bar-first macOS app.
- Must continue running after dashboard window closes.
- Must perform periodic checks on configurable interval.
- Must classify connection into meaningful operational states.
- Must support local proxy endpoint (host, port, type).
- Must send notifications on state transitions.
- Must show route context:
  - direct path,
  - system proxy active,
  - TUN active,
  - detected VPN client label (best effort).

## UX Requirements

- At-a-glance menu label and status dot.
- Clear state detail and recommended action.
- One-click manual refresh.
- Simple settings with presets.
- Minimal cognitive load under stress.

## Technical Requirements

- Native stack: Swift + SwiftUI + AppKit integration where needed.
- Low-overhead probing (fast, lightweight requests).
- Stable persistence for settings and transition history.
- Robust behavior when proxies/TUN are enabled.
- Buildable from both Xcode and CLI (`just`, `xcodebuild`).

## Default Operating Assumptions

- Platform: macOS.
- Typical local VPN endpoint: `127.0.0.1:10808` (SOCKS5).
- Example VPN tools: Happ / V2Ray / Xray / OpenVPN / WireGuard.
- User may rotate multiple ISP links.

## Success Criteria

- User can trust menu-bar state for fast decision making.
- Degrade/recovery alerts are timely and low-noise.
- App remains responsive while monitoring in background.
- Setup and daily usage remain simple for non-Swift users.
