# QatVasl V2 Roadmap and Implementation Plan

This plan turns QatVasl into a clear, fast, and practical network reliability tool.

## Product North Star

- Core promise: in seconds, show whether internet is usable, through which route, and what to do next.
- Primary UX outcomes:
  - instant status clarity
  - low-noise notifications
  - plain-language diagnosis with concrete actions
- Technical outcomes:
  - crash-free monitoring loop
  - stable route classification (DIRECT / VPN / PROXY)
  - maintainable architecture with clean boundaries

## Phase 1 — Product Clarity and UX Contract (2–3 days)

- Finalize top-level state model:
  - `Checking`
  - `Usable`
  - `Degraded`
  - `Offline`
- Finalize route model:
  - `DIRECT`
  - `VPN`
  - `PROXY`
  - `VPN+PROXY`
- Rename and standardize probe labels in plain language.
- Add short “what this means” descriptions for each status/probe.
- Deliverable: approved naming + UX contract doc used as source of truth.

## Phase 2 — Architecture Consolidation (2–3 days)

- Refactor into clear layers:
  - `Core` (models, state machine, rules)
  - `Services` (probe engine, route inspection, persistence)
  - `ViewModels` (UI state composition)
  - `UI` (SwiftUI views/components)
- Introduce a single app state store for all derived view state.
- Remove remaining backward/legacy pathways.
- Deliverable: cleaner dependency graph and easier onboarding/maintenance.

## Phase 3 — Probe Engine and Route Accuracy (4–5 days)

- Keep `VPN` detection based on TUN/system route evidence only.
- Keep `PROXY` detection based on configured proxy endpoint health + successful routed check.
- Strengthen probe execution:
  - strict timeout policy
  - bounded retries
  - cancellation safety
  - non-overlapping check scheduling
- Deliverable: reliable classification under real network switching conditions.

## Phase 4 — Diagnosis Engine and “Fix Now” Actions (3–4 days)

- Build rules to translate probe matrix into human diagnosis text.
- Add ordered action recommendations per failure mode.
- Add one-click quick actions:
  - rerun targeted checks
  - copy diagnostics
  - open relevant settings section
- Deliverable: each bad state includes a clear reason and next steps.

## Phase 5 — Timeline, History, and ISP Profiles (4–5 days)

- Persist recent health snapshots/events (24h and 7d windows).
- Add timeline view:
  - uptime percent
  - drop count
  - average latency
  - mean recovery time
- Add ISP profiles with per-profile:
  - probe set
  - proxy port
  - check interval
- Deliverable: users compare reliability by ISP and time.

## Phase 6 — Critical Services Monitoring (3–4 days)

- Add configurable list of “critical services” (e.g., Telegram, GitHub).
- Evaluate each service per relevant route (direct / proxy / vpn).
- Show service availability matrix in dashboard.
- Deliverable: users immediately know which services are usable now.

## Phase 7 — Notifications and Menubar UX (2–3 days)

- Emit notifications only on meaningful transitions:
  - healthy -> degraded/offline
  - degraded/offline -> recovered
- Add anti-spam cooldown and optional quiet hours.
- Improve menubar icon semantics for at-a-glance clarity.
- Preserve menubar residency on window close (`⌘W` behavior).
- Deliverable: high-signal alerts without notification fatigue.

## Phase 8 — Performance and Stability Hardening (3–5 days)

- Audit concurrency flow to guarantee single monitor loop ownership.
- Add robust cancellation and lifecycle guards.
- Profile with Instruments for startup, render, and memory churn.
- Add tests for:
  - state machine transitions
  - route classification rules
  - diagnosis mapping
- Deliverable: snappy runtime and reduced crash risk.

## Phase 9 — Docs, Packaging, and Operations Readiness (2–3 days)

- Keep docs understandable for non-Swift users.
- Maintain `just` workflows for build/run/package/release routines.
- Add support bundle export (`diagnostics.txt` + recent events).
- Define release checklist for stable `.app` and `.dmg` delivery.
- Deliverable: easy handoff and reproducible release process.

## Suggested Delivery Milestones

- Milestone A (must-have): Phases 1–4
- Milestone B (power-user): Phases 5–7
- Milestone C (hardening): Phases 8–9

## Success Metrics

- Median time to status insight: <= 3 seconds
- False “healthy” classification rate: minimized and tracked
- Notification spam incidents: near zero
- Crash-free monitoring sessions: continuous multi-hour runs
- User task success: quicker recovery after drops and route failures
