# M7 plan / device A/B handoff

Status: M7 datasets accepted (EV-0213…EV-0227); M7 engine host PASS (EV-0228, 40 synthetic checks);
**device A/B NOT RUN**.

## Release metadata timing

**Release metadata update is deferred to after M7 device A/B acceptance.** The current development
package/manifest is stale relative to the M7 provider. `scripts/m6_release_ready.sh` will fail until the
package is rebuilt from the post-A/B commit; do not treat that failure as a release regression during M7
A/B. Rebuild order after A/B pass:

1. commit M7 fixes,
2. refresh `export/latest-build-identity.txt`,
3. rebuild manifest/package/metrics,
4. rerun `m6_release_ready.sh`.

## Rollback path

- Tune file: `Documents/instances/default/vrmc-input-tune.properties` → `gesture.mode=m4`.
- Launcher: **Reload input** (or relaunch game); startup log must show `[VRMC-M7] gesture mode=m4`.
- **Status: PARTIAL (2026-11-02, EV-0230).** The m4 session launched and old actions fired; mode log
  confirmed `gesture.mode=m4`. The operator reported frequent hand-tracking dropouts, poor/random
  movement, and accidental inventory/menu in M4. Tune is now switched back to `gesture.mode=m7`.
  Treat M4 as a functional but usability-caveated fallback; the M7 A/B itself has NOT run.
- M7 default remains `m7`; fallback is one tune-file edit away.

## Risks / recorded backlog

- **Sneak transition data:** first SNEAK_HEAD dataset (EV-0218) over-represents held crouches; add a
  second, transition-heavy sneak pass before final tuning.
- **Climb heuristic:** no climbable-context gating; M5 device run records false-trigger rate.
- **GUI:** right-pinch click only; no reticle/drag-and-hold (see M7_GESTURES §13).
- **Seated snap turn:** currently absent; M5 device run must check seated + head turn + forward for
  discomfort and decide whether snap turn is required before M6.
- **Thresholds:** provisional from Gesture Lab; device A/B is the acceptance gate.

## Crash-guard precondition

- The first M7 launch attempt was blocked by the shell crash guard (count=2) from previous unclean exits:
  automatic VR open was suppressed, so the game never entered immersive even though the M7 provider
  initialized. This is not an M7 failure.
- Resolution: exit the app, restart VRMC; use **Enter VR** if the guard is still active, and quit the
  game cleanly (`destroy-complete`) so the count resets. Crash count was reset to 0 on 2026-11-02.

## Device A/B order

| Step | Action | Record |
|---|---|---|
| 0 | rollback to m4, reload, verify playable, return to m7 | mode log, playable Y/N |
| 1 | menu/escape | **NOT RUN.** EV-0232/0233 verified only immersive open + clean quit. Incidental action log entries are not evidence. |
| 2 | inventory | both-fist priority |
| 3 | walk | sustained swing |
| 4 | place/break | 0.35 s boundary |
| 5 | teleport | hold/release |
| 6 | attack | swing recognition |
| 7 | jump/sneak | head displacement |
| 8 | hotbar | tap vs swing |
| 9 | bow/eat | 0.55 m / 0.28 m spatial thresholds |
| 10 | climb | heuristic false-trigger rate |

Each row: **triggered (Y/N), false-trigger count (None/Occasional/Frequent), response timeliness,
operator 1–5 score.** Record m4 vs m7 side by side for the A/B.
