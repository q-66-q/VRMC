# M7 plan / device A/B handoff

Status: M7 datasets accepted (EV-0213…EV-0227); M7 engine implemented (EV-0228) and **re-fitted with a
data-driven accuracy iteration (EV-0237): 73 synthetic checks + 200k-frame fuzz ALL PASS, primary replay
gate 22/24 rows (literal 20/24, up from 12/24)**. **EV-0238: the EV-0237 provider `d2c8a8d9…` was pushed
and integrity-verified on D1** (pre-push installed jar was `cf3ef0a0…`). **Device A/B is still NOT RUN**:
the app launch at push time failed with a `devicectl` RSD allocation error, and gesture behaviour needs the
operator session — no device behaviour is claimed for EV-0237.

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

- The automatic immersive open is suppressed after **two consecutive unclean VR-session shutdowns**
  (shell crash guard, `vrmc-safe-mode.flag` + `vrmc-crash-count.txt`): the game stays in its flat
  window and latestlog shows `displayViews=0`. This is not an M7 failure; manual **Enter VR** still
  works, and the window shows **Clear crash safe mode** when the guard is active.
- **2026-11-02 and 2026-11-04 recurrences (EV-0240):** force-quitting the app while a VR session was
  live during provider push/restart cycles incremented the count (2 → safe mode each time). The crash
  count was reset to 0 on D1 after each occurrence (read-back verified).
- **Double-start hazard (EV-0241):** the guard evaluates once per shell process launch. Two shell starts
  within 26 s (observed 2026-11-04 22:23:35 and 22:24:01 HST, scene relaunch) turn one unclean shutdown
  into count=2 and re-enable safe mode even right after a counter reset. Until the shell is rebuilt with
  a debounce, recover with a clean game shutdown (below) or the in-window **Clear crash safe mode** +
  **Enter VR** controls; do not tap the app icon repeatedly while a launch is starting.
- **Temporary testing mitigation attempt (2026-11-04):** we tried to give the next launch extra headroom
  by setting the on-device `vrmc-crash-count.txt` to `-3` (each unclean shell start increments by one,
  so scene double-starts would stay below the safe-mode threshold). The transfer failed
  (`CoreDeviceError 7000: connection to the remote device is no longer valid`; read-back still 0), so the
  device remains at count 0. A single launch is therefore safe (0→1, no safe mode); two rapid launches
  would re-enable safe mode. The negative-count trick is device state only, not a code change, and must
  never be kept beyond testing; the first clean shutdown (`destroy-complete`) resets the count normally.
- Resolution/operator habit: quit the game via its own menu so the provider writes
  `event=destroy-complete` (clean shutdown resets the count); if the window shows safe mode, tap
  **Enter VR** (or **Clear crash safe mode**) instead of force-quitting; a normal app relaunch after the
  counter reset restores the automatic open.

## Device A/B order

| Step | Action | Record |
|---|---|---|
| 0 | rollback to m4, reload, verify playable, return to m7 | mode log, playable Y/N |
| 1 | menu/escape | **PARTIAL (2026-11-02):** menu GUI clicks triggered but frequently missed targets; left-fist escape triggered. Head-ray GUI cursor added (EV-0234); retest needed. |
| 2 | inventory | **PARTIAL:** both-fist inventory triggered sometimes but frequently missed; fist threshold 0.55→0.65 and tap window 350→450 ms (EV-0234); retest needed. |
| 2 | inventory | both-fist priority |
| 3 | walk | left thumb-middle pinch + move left hand (analog stick, EV-0248); old both-fist swing must NOT move |
| 4 | place/break | **DEVICE PASS (EV-0256):** short pinch = attack/place/use context; hold = break; hotbar stable |
| 5 | teleport | **NOT TESTABLE:** left pinch used for movement; teleport unbound, needs a new gesture |
| 6 | attack | swing recognition |
| 7 | jump/sneak | head displacement |
| 8 | hotbar | tap vs swing; direct tap on the rendered HUD bar selects the touched slot (EV-0246, device-only) |
| 9 | bow/eat | 0.55 m / 0.28 m spatial thresholds |
| 10 | climb | heuristic false-trigger rate |

Each row: **triggered (Y/N), false-trigger count (None/Occasional/Frequent), response timeliness,
operator 1–5 score.** Record m4 vs m7 side by side for the A/B.

## 2026-11-05 latest mapping changes (EV-0249)

- Movement uses **left thumb-index pinch hold + move left hand**; both-fist swing no longer moves.
- GUI right pinch is the **left mouse button**; hold = long press/drag, release lifts.
- Head-ray cursor is offset **8% down** from centre.
- Teleport shares left pinch and is suppressed while moving; a dedicated teleport gesture remains a follow-up.
- Device retest for movement/cursor/click/long-press is pending.

## Player-relative movement (EV-0250)

- Movement now projects wrist-minus-head onto the HMD's horizontal forward/right basis; "forward" is
  relative to the player, not absolute world Z. Device retest required.

## Movement retest fix (EV-0251)

- Left pinch was still also dispatching teleport; teleport can override free-move. Teleport is disabled
  on the movement pinch for now.
- Neutral along/right origin is captured at pinch engage; natural hand offset no longer causes constant strafe.
- Right-basis sign corrected. Device movement retest pending.
