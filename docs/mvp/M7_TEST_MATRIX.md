# M7 synthetic + replay test matrix (host)

Two host gates cover the M7 engine:

1. `provider/tests/dev/vrmc/provider/VisionM7GestureTest.java` — **73 synthetic checks** (pure state
   machine, synthetic 27-joint hands/head, explicit context bits).
2. `provider/tests/dev/vrmc/provider/VisionM7GestureFuzzTest.java` — **200,000 random frames** with
   untracked/NaN/malformed input, time jumps, GUI/seated/context flips and releaseAll calls: 0
   violations (no exception; no hand-driven action latched after both hands are lost for 10 frames;
   releaseAll complete; outputs pure).
3. `scripts/m7_lab_replay.sh` — replays the 14 recorded Gesture Lab datasets through the real engine and
   scores them with the independent evaluator `scripts/m7_eval_replay.py` (host analysis, not device
   evidence). See `M7_ACCURACY_ITERATION.md` for the final table.

These are synthetic/recorded-data checks; none is device evidence.

## Synthetic check list (73)

| # | Check | Class |
|---|---|---|
| 1 | short pinch not place while held | place/break |
| 2 | short right pinch releases place | place/break |
| 3 | short right pinch does not break | place/break |
| 4 | lowered-hand pinch does not place | place safety |
| 5 | lowered-hand pinch does not break | place safety |
| 6 | fist pinch does not place | accidental-pinch |
| 7 | pinch not break before threshold | break boundary |
| 8 | held right pinch breaks | break |
| 9 | held right pinch does not place | place/break |
| 10 | held right pinch release does not place | place/break |
| 11 | held right pinch release clears break | release |
| 12 | held pinch does not place after threshold | boundary |
| 13 | single-frame pinch jitter does not place | debounce |
| 14 | single-frame pinch jitter does not break | debounce |
| 15 | left pinch hold aims teleport (120 ms) | teleport |
| 16 | left pinch release ends teleport | teleport |
| 17 | seated suppresses teleport | seated |
| 18 | lowered left pinch does not teleport | teleport safety |
| 19 | left fist tap fires menu | menu |
| 20 | long left fist hold does not fire menu | menu |
| 21 | left-fist tap after inventory does not open menu | menu/inventory |
| 22 | GUI left fist tap produces close pulse | GUI |
| 23 | GUI left fist tap does not fire world menu | GUI |
| 24 | both-fist tap fires inventory | inventory |
| 25 | both-fist tap does not walk | inventory/walk |
| 26 | long both-fist hold does not fire inventory | inventory |
| 27 | inventory suppressed by tracking loss | safety |
| 28 | alternating both-fist swing starts walk | walk |
| 29 | walk forward analog > 0 | walk |
| 30 | walk stops without swing | walk stop |
| 31 | walk survives a one-frame fist dropout | walk tracking |
| 32 | seated suppresses walk | walk safety |
| 33 | GUI suppresses walk | walk safety |
| 34 | walk uses the head-forward frame | walk frame |
| 35 | bow draw with a bow held | bow/context |
| 36 | releasing the back fist fires the bow | bow fire |
| 37 | bow fire clears draw | bow |
| 38 | bow geometry alone never draws without a bow (auto context) | bow context |
| 39 | bow context=off fallback detects the draw from geometry | bow fallback |
| 40 | releasing a drawn bow fires | bow semantics |
| 41 | sub-arm bow flick does not fire | bow noise |
| 42 | near-head hand with food eats | eat/context |
| 43 | eat stops when the hand leaves the head | eat hysteresis |
| 44 | eat requires the edible context bit | eat context |
| 45 | near-head without food does not eat (auto context) | eat context |
| 46 | head rise fires jump | jump |
| 47 | GUI suppresses jump | jump safety |
| 48 | seated suppresses jump | jump safety |
| 49 | head drop latches sneak (500 ms) | sneak |
| 50 | sneak persists through a sustained 5 s crouch | sneak baseline |
| 51 | sneak release hysteresis keeps sneak briefly | sneak hysteresis |
| 52 | sneak releases after standing up | sneak |
| 53 | index-finger tap cycles hotbar next (delayed decision) | hotbar |
| 54 | double index tap steps the hotbar back | hotbar double |
| 55 | fast wrist swing does not cycle hotbar | hotbar/attack |
| 56 | hotbar suppressed after a pinch release | hotbar/pinch |
| 57 | closed-fist swing attacks | attack |
| 58 | open-hand fast motion does not attack | attack/fist |
| 59 | both-fist swing does not attack | attack/walk |
| 60 | climbable context + closed hands grab | climb/context |
| 61 | both hands pulling down triggers climb jump | climb jump |
| 62 | no climb grab without climb context (auto) | climb context |
| 63 | GUI suppresses climb grab | climb safety |
| 64 | upward reach is not a climb jump | climb direction |
| 65 | GUI right pinch fires click on press | GUI |
| 66 | GUI right pinch does not place in the world | GUI/world |
| 67 | releaseAll clears menu | release |
| 68 | releaseAll clears inventory | release |
| 69 | releaseAll clears break | release |
| 70 | releaseAll clears walk | release |
| 71 | releaseAll clears teleport | release |
| 72 | null joints fail closed | safety |
| 73 | NaN pinch for one untracked hand does not break the other hand | safety |

Device-only M7 behaviours (not part of the 73 host checks, verified on D1): left-thumb virtual-stick movement
(EV-0248; the 73 host checks still cover the engine's internal both-fist walk detector), GUI head-ray cursor position
and right-pinch click (EV-0239/EV-0242/EV-0243/EV-0244), and direct touch-hotbar selection on the
rendered inventory bar (EV-0246; the provider logs `touch hotbar armed/hover/select` lines).

## Replay gate (latest host run, evaluator v2)

`scripts/m7_lab_replay.sh` reports both variants from one fresh run:
- **Primary gate: 22/24 rows pass** (90 Hz rate-matched pulse GT + bounded-latency-aware held windows;
  policy table in `M7_EVAL_REPLAY.md`).
- **Literal conservative gate: 20/24 rows pass** (raw-18 Hz GT, zero-latency windows; first-engine
  baseline 12/24). Context suppression **9/9** in both.

Passing primary rows: place, menu, inventory, bowFire, jump, break, teleport, walk, bowDraw, eat, sneak,
climbGrabLeft, climbGrabRight. Residual primary failures: hotbar recall 0.75 (18/24 taps, precision
1.00) and attack recall 0.77 / precision 0.71 (38 pulses, 27/35 matched, cross 2.80/min within the
3.0/min budget) — analysed in `M7_ACCURACY_ITERATION.md`; no engine threshold was fitted to the gate.
Literal-only failures: walk false-active 0.18, eat false-active 0.25, literal hotbar precision 0.83
(causal-latency / 18 Hz-GT artifacts, all passing under the aware scoring).

## Live provider regression

`provider/tests/run_tests.sh` runs the full host suite (provider build, M4/M5 safety/fuzz tests, the
M7 synthetic + fuzz tests and the optional cross-language input fixture). Latest run: **ALL PASS**
(see `evidence/EV-0237/provider-tests.log` locally; the committed summary is in `VERIFY.md`).
