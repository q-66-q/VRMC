# M7 plan / device A/B handoff

Status: M7 datasets accepted (EV-0213…EV-0227); M7 engine implemented (EV-0228) and **re-fitted with a
data-driven accuracy iteration (EV-0237): 73 synthetic checks + 200k-frame fuzz ALL PASS, literal replay
gate 20/24 rows (up from 12/24)**; **device A/B NOT RUN**. The installed D1 provider remains the EV-0236
jar — no device behaviour is claimed for EV-0237.

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

- **Replay gates (EV-0237, evaluator v2): primary gate 22/24 rows pass** (90 Hz rate-matched pulse GT +
  bounded-latency-aware held scoring; held 8/8, context 9/9). Residual primary rows: hotbar recall 0.75
  (18/24 taps, precision 1.00) and attack recall 0.77 / precision 0.71 (38 pulses for 35 rate-matched
  swings; cross 2.80/min within the 3.0/min budget) — genuine frozen-engine behaviour, left failing
  rather than over-fitted. Literal conservative gate 20/24 (hotbar precision 0.83, attack precision
  0.66, walk false 0.18, eat false 0.25 are 18 Hz-GT/causal-latency artifacts). See
  `M7_ACCURACY_ITERATION.md` / `M7_EVAL_REPLAY.md`.
- **Device A/B for the new engine is the acceptance gate:** push the EV-0237 provider jar, verify the
  item-context probe and threshold log, exercise the operator mapping table, then record the A/B.
- **Sneak transition data:** second SNEAK_HEAD pass still useful (first dataset over-represents held
  crouches); the dt-corrected/adapt-band engine now passes the replay gate for both jump and sneak.
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
| 1 | menu/escape | **PARTIAL (2026-11-02):** menu GUI clicks triggered but frequently missed targets; left-fist escape triggered. Head-ray GUI cursor added (EV-0234); retest needed. |
| 2 | inventory | **PARTIAL:** both-fist inventory triggered sometimes but frequently missed; fist threshold 0.55→0.65 and tap window 350→450 ms (EV-0234); retest needed. |
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
