# Daily Operations Checklist (QatVasl)

Date: 2026-02-07

## Goal

Reduce decision fatigue and wasted time during unstable connectivity periods by following one repeatable flow.

## Daily Startup (2–3 minutes)

1. Connect your preferred ISP.
2. Start VPN client (if needed) and verify local endpoint (for example `127.0.0.1:10808`).
3. Open QatVasl menu bar panel.
4. Confirm current route mode:
   - `Route: DIRECT`
   - `Route: VPN`
   - `Route: PROXY`
   - `Route: VPN + PROXY`
5. Read top status and diagnosis, then begin work only after stable `USABLE`.

## State-Based Action Table

- `OFFLINE`:
  - Action: switch ISP first, then retest.
- `DEGRADED` + diagnosis says domestic-only:
  - Action: switch ISP first, then re-test VPN/proxy route.
- `DEGRADED` + diagnosis says restricted services fail:
  - Action: rotate VPN/proxy profile/config and re-check.
- `USABLE` on `PROXY` route:
  - Action: continue work and monitor latency/drop trend.
- `USABLE` on `VPN` route:
  - Action: continue work; direct-path verdict is not authoritative while VPN/TUN is active.
- `USABLE` on `DIRECT` route:
  - Action: keep VPN optional and continue work until state changes.

## ISP Switching Sequence

Keep one deterministic daily order:

1. Primary ISP
2. Secondary ISP
3. Tertiary ISP

After each switch:

1. Wait 30–60 seconds.
2. Press `Refresh` in QatVasl.
3. Read state and latencies.
4. Move to next ISP only if still degraded.

## VPN Profile Rotation Sequence

For each ISP, test profiles in strict order:

1. Last known stable profile
2. Backup A
3. Backup B
4. Experimental profiles last

For each profile:

1. Connect.
2. Wait one full monitor interval.
3. Check state + restricted-service proxy probe latency.
4. Keep only if it produces stable `USABLE` with acceptable performance.

## Stability Confirmation Rule

When state becomes `USABLE`:

1. Observe for 10 minutes.
2. If transition drops quickly, mark profile as unstable.
3. Rotate to next profile rather than repeating random toggles.

## Incident Playbook (When Work Is Fully Blocked)

1. Record: ISP + VPN profile + route mode.
2. Switch ISP once.
3. Test top two VPN profiles only.
4. If still blocked, pause 10 minutes before next cycle.

This protects you from 2–4 hour random troubleshooting loops.

## Use These Dashboard Sections

- `Services`: verify Telegram/GitHub/etc per direct/proxy route.
- `Timeline`: verify uptime %, drops, and recovery behavior.
- `Overview → Export report`: save diagnostics snapshot when debugging hard failures.

## Minimal Daily Log Template

- Date:
- ISP:
- VPN profile:
- Route mode:
- Initial state:
- Stable minutes:
- Verdict: stable / unstable / unusable

After a week, this produces evidence-backed “best pairings” for faster decisions.
