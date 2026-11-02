# M5 device acceptance runbook (D1; NOT RUN yet)

Purpose: verify the gameplay loop, comfort controls and diagnostics of the current M4/M5 build on a
Vision Pro, and capture evidence for `M5_ACCEPTANCE.md` / VERIFY.

## Optional pre-run integrity check (no unlock needed)

```
scripts/m6_device_integrity.sh            # prints installed VRMC version + provider jar sha256 match
```

## Preconditions

- Current build installed (see `export/latest-build-identity.txt`; currently app `926f663d…` +
  provider `4fa76795…`; refresh after each staging).
- JIT tooling available (StikDebug); hand-tracking permission granted.
- Logs/export path known: launcher **Export diagnostics**.
- Read `M4_CONTROLS.md` and the in-game **Controls help** first.

## After the session (read-only pull)

```
scripts/m6_device_diagnostics_pull.sh /tmp/vrmc-device-diag
```

Copies shell/compositor/thermal/shutdown/status/settings/log files for offline review; no launch or
unlock required. Behavior evidence still comes from the operator notes + this bundle.

## Procedure

1. **Startup/UI:** launch VRMC; open VRMC settings; verify controls respond, crash guard is clean,
   thermal/status line updates after a game session. Save a settings change and confirm
   `vrmc-runtime.properties`/`vrmc-input-tune.properties` were written (Export diagnostics includes them).
2. **JIT game + immersive:** StikDebug → Enable JIT → VRMC → Play. Confirm immersive opens ~15 s after
   game start, stereo stays aligned, head tracking works, window is parked (no chrome).
3. **H1 menu:** look at the Minecraft menu; right pinch clicks; left fist tap opens/escapes menu.
4. **H2 locomotion:** left middle pinch + push around: walk forward/back/strafe; pick turn angle 0 and
   45 in launcher, reload settings/next launch, test smooth vs snap; left pinch teleport; avoid
   teleport while drawing bow.
5. **H4 combat/interact:** right pinch attack; right fist hold use; interact with entities/blocks.
6. **H5 inventory/hotbar:** both-fist tap inventory; both ring pinches + left-hand move + release to
   choose slots 1–9; test GUI drag/click.
7. **H8 bow:** hold right fist to draw a bow, aim, release; confirm no teleport/menu interference.
8. **H9 climbing:** grab a ladder with both-hand pinch; both-middle tap for climb jump.
9. **H7/T2:** inspect hands/held item; optionally set `hands.componentMode=joints` and A/B appearance.
10. **H10 save/reload:** save, quit cleanly; confirm shutdown journal ends with `destroy-complete`;
    relaunch and load the world.
11. **Comfort:** test vignette on/off; recenter (both-middle double-tap); seated mode.
12. **Diagnostics:** export diagnostics; verify bundle contains shell/compositor/thermal/status/
    shutdown/command files and (if present) crash reports; record package hash.

## Evidence to record

- Build identity (app tree/provider sha256) and settings files used.
- Operator notes per H1–H10 (pass/fail + gesture/threshold issues).
- `vrmc-shutdown.log`, `vrmc-status.json`, diagnostics bundle hash.
- Frame-pacing diag lines (poll P50/P95/missed90) and thermal log while playing.
- Any crash: shutdown journal missing `destroy-complete`, `hs_err_pid*`, crash reports.

Record as a new VERIFY entry (`EV-…`) with `PASS`/`PARTIAL`, limitations, and artifacts; never claim
device PASS from simulator/host data.
