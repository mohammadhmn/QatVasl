# Daily Operations Checklist (QatVasl)

Date: 2026-02-07

## Goal

Reduce decision fatigue and wasted time during unstable connectivity periods by following one repeatable flow.

## Daily Startup (2–3 minutes)

1. Connect your preferred ISP.
2. Start VPN client (if needed) and verify local endpoint (for example `127.0.0.1:10808`).
3. Open QatVasl menu bar panel.
4. Confirm current route mode:
   - `Route: Direct path`
   - `Route: VPN active`
   - `Route: PROXY active`
   - `Route: VPN + PROXY`
5. Read connectivity state and begin work only after stable result.

## State-Based Action Table

- `OFFLINE`:
  - Action: switch ISP first, then retest.
- `IR ONLY`:
  - Action: ISP is partially usable; rotate VPN profile/config.
- `LIMITED`:
  - Action: global web is up but blocked route is down; rotate VPN route/profile.
- `VPN OK`:
  - Action: continue work, monitor for drops.
- `VPN ACTIVE`:
  - Action: VPN/TUN overlay is active; direct-path verdict is paused. Disable VPN if you need true direct-path verification.
- `OPEN`:
  - Action: direct blocked target is reachable now; VPN may be optional.

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
3. Check state + blocked-via-proxy latency.
4. Keep only if it produces stable `VPN OK` / acceptable performance.

## Stability Confirmation Rule

When state becomes `VPN OK`:

1. Observe for 10 minutes.
2. If transition drops quickly, mark profile as unstable.
3. Rotate to next profile rather than repeating random toggles.

## Incident Playbook (When Work Is Fully Blocked)

1. Record: ISP + VPN profile + route mode.
2. Switch ISP once.
3. Test top two VPN profiles only.
4. If still blocked, pause 10 minutes before next cycle.

This protects you from 2–4 hour random troubleshooting loops.

## Minimal Daily Log Template

- Date:
- ISP:
- VPN profile:
- Route mode:
- Initial state:
- Stable minutes:
- Verdict: stable / unstable / unusable

After a week, this produces evidence-backed “best pairings” for faster decisions.
