# Troubleshooting and FAQ

## Q1) I launched app but see nothing in menu bar

Checklist:

1. Confirm app process exists:
   - `pgrep -x QatVasl`
2. If not running:
   - `just dev`
3. Ensure app is not blocked by a crash (check Console/logs):
   - `just logs`

## Q2) Dashboard closed and app vanished from Dock

This is expected behavior.

QatVasl intentionally switches to menu-bar-only mode when no app window is visible.  
Use menu bar item → `Dashboard` to reopen window.

## Q3) Route shows `VPN`. What does that mean?

`VPN` means system-level VPN/TUN overlay is active.  
Direct-path verdict is not authoritative in this mode because traffic is being routed through overlay.

If you need true direct-path test:

1. Temporarily disable VPN.
2. Refresh QatVasl.

## Q4) VPN/proxy works in client, but app is not `USABLE`

Check in this order:

1. Proxy host/port/type in QatVasl settings.
2. Ensure local endpoint is actually listening.
3. Confirm blocked target URL is valid.
4. Press `Refresh`.

Useful port check:

```bash
lsof -nP -iTCP:10808 -sTCP:LISTEN
```

If no listener appears, VPN client may not expose local proxy at that port.

## Q5) Which VPN app is shown in `Client:` and can it be wrong?

Client label is best-effort:

1. It checks connected network services (`scutil --nc list`).
2. If not found, it checks running processes for known VPN tools.

So yes, it can be unknown or occasionally imperfect.

## Q6) Notifications do not show

1. In QatVasl settings, enable notifications.
2. In macOS System Settings, allow notifications for QatVasl.
3. Trigger transition (for example by changing network state) and verify.
4. Check notification cooldown and quiet hours settings.

## Q7) App feels slow or laggy

Current optimizations already include:

- off-main route detection,
- session reuse,
- lightweight probes,
- debounced settings writes.

If still laggy:

1. Increase interval (for example from 12s to 30–60s).
2. Increase timeout if network is very unstable.
3. Avoid unnecessary rapid settings edits.

## Q8) App says `PROXY` but traffic still fails

`PROXY` becomes active only when:

1. configured proxy port is reachable, and
2. restricted-service probe through proxy succeeds.

If your external app still fails, compare against `Services` tab per-service matrix and rotate node/profile.

## Q9) Build fails after changes

Do this sequence:

```bash
just clean
just build-debug
```

Then inspect first compiler error (not last).

## Q10) I want to fully reset app state

```bash
just reset-settings
```

Then relaunch app.

## Q11) How to inspect VPN/proxy state manually?

- Connected VPN services:
  - `scutil --nc list`
- Interfaces (look for VPN route interfaces like `utun*`):
  - `ifconfig`
- Known VPN processes:
  - `ps -axo comm | egrep -i 'happ|openvpn|wireguard|v2ray|xray|sing-box|clash'`

## Q12) How do I export diagnostics for support/debug?

From dashboard:

1. Open `Overview`.
2. Click `Export report`.
3. Share saved report text with timestamp + route + probe snapshot.

## Q13) How should I operate daily in unstable conditions?

Use:

- `docs/03-daily-ops-checklist.md`

for a strict ISP/VPN rotation workflow to avoid random troubleshooting loops.
