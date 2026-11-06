# M5 device acceptance runbook (D1; operator-attested PASS 2026-11-05)

> **Status:** operator states the M5 loop was tested previously and waived a fresh current-build run.
> Recorded as operator-attested PASS (EV-0258); M6 AC/K gates remain.

> Scope update 2026-11-05 (EV-0257): operator descoped teleport. M7 mapping below is the accepted
> mapping; do not test teleport. M7 H1–H10 actions are already device-passed; this run covers the
> launcher/settings/comfort/diagnostics loop and the remaining M5/M6 gates.

Purpose: verify the gameplay loop, comfort controls and diagnostics of the current M4/M5 build on a
Vision Pro, and capture evidence for `M5_ACCEPTANCE.md` / VERIFY.

## Optional pre-run integrity check (no unlock needed)

```
scripts/m6_device_integrity.sh            # prints installed VRMC version + provider jar sha256 match
```

## Preconditions

- Current build installed (see `export/latest-build-identity.txt`; currently app `926f663d…` +
  provider `683efdd3…`; refresh after each staging).
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
4. **H2 locomotion:** left **thumb-index pinch hold + move** (player-relative analog stick): walk
   forward/back/strafe; pick turn angle 0 and 45 in launcher, reload settings/next launch, test
   smooth vs snap. **Teleport is descoped.**
5. **H4 combat/interact:** short right pinch = attack on an entity / place-or-use on a block; hold
   right pinch >=350 ms = break/mine; confirm no hotbar change during these actions.
6. **H5 inventory/hotbar:** both-fist tap inventory; right pinch = LMB pick/place; test touch-hotbar
   selection and GUI drag/click; close with left fist tap.
7. **H8 bow:** both fists front/back draw; release the back fist to fire; confirm no menu/hotbar interference.
8. **H9 climbing:** alternating closed-hand reach/pull; confirm grab and climb jump; record false grabs.
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

## M7 device A/B companion checks (pre-M5 acceptance; M7 scope closed EV-0257)

Record these alongside H1–H10:

1. **Rollback:** set `gesture.mode=m4` in `vrmc-input-tune.properties`, Reload input, confirm old M4
   mapping is playable; restore `gesture.mode=m7` and reload.
2. **GUI click accuracy:** open inventory/chest/crafting; right-pinch clicks must land on the intended
   slot; record mis-clicks and whether drag-and-hold is needed. No M7 reticle exists yet.
3. **Seated comfort:** seated mode + head turn + forward movement; note sideways-walk discomfort. If
   present, snap turn becomes required before M6 and the seated-mode scope must be resolved.
4. **Climb false triggers:** hands hanging naturally / holding items / reaching above head; record
   false grab/climb triggers from the current fist-height heuristic.
5. **Sneak transitions:** record a second transition-heavy sneak pass before final M7 tuning.
6. **Hand-tracking dropouts:** record frequency, whether looking at a hand restores tracking, and
   impact on M7 movement/actions; this is an ARKit/visibility issue shared by both mappings.
7. **Teleport:** descoped; skip.
