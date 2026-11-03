# M7 lab replay evaluator (independent ground truth) - v2.1

Status: **host analysis gate; not device evidence.** Script: `scripts/m7_eval_replay.py`
(python3 stdlib only, ~3 s runtime). It re-derives expected gesture events from the raw Gesture Lab
JSONL with its own feature code and scores the Java replay harness
(`provider/tests/dev/vrmc/provider/M7LabReplay.java`) against them, then enforces per-action
recall / false-trigger gates. Engine source/constants are never imported for feature derivation; the
only engine input is the documented latency **policy table**, parsed from the current
`VisionM7Gesture` constants.

v2 adds two fairness corrections while keeping the literal conservative gates intact:

1. **Frame-rate-matched pulse ground truth.** Pulse GT is re-derived on the same 90 Hz interpolated
   frame grid the replay harness uses (linear interpolation identical to
   `scripts/m7_lab_fixture.py --rate 90`), so pulse analysis is no longer limited by ~18 Hz sampling
   of fast taps/swings. The raw-18 Hz GT is still computed and reported as the conservative row.
v2.1 is the robustness fix for the regression gate: a silent target dataset/action now scores
recall/coverage 0.0 and FAILs with a clear reason instead of crashing the evaluator (see
"Empty-target robustness" and the `--self-check` command).

2. **Bounded-latency-aware held scoring.** Each expected held window is transformed to
   `[start + onset_latency, end + release_latency]`, with the per-action bounds read from the current
   `VisionM7Gesture` constants. The literal windows/metrics/gates are unchanged and reported next to
   the aware variant.

Exit policy: the **conservative literal gate governs the exit code by default** (no silent
loosening). `--exit-primary` enforces the rate-matched pulse + latency-aware held gate instead. Both
results are always printed and stored in `eval.json`.

## How to run

End-to-end (build provider -> regenerate 18 Hz + 90 Hz fixtures -> replay both cadences -> evaluate):

```
scripts/m7_lab_replay.sh            # --skip-build to reuse /tmp/vrmc-provider-build
```

The wrapper completes every stage (build, fixtures, 90 Hz auto, 90 Hz no-context, 18 Hz, evaluation)
and then exits 1 because the conservative literal gate is currently short of the bar (see below); the
evaluator is the last step and still writes `export/m7-replay/eval.json`.

Direct evaluator run:

```
python3 scripts/m7_eval_replay.py \
  --events export/m7-replay-90/events.jsonl \      # 90 Hz replay (pulse-gate source)
  --events-raw export/m7-replay/events.jsonl \    # literal ~18 Hz replay (held-gate source)
  --data export/gesturelab-data \
  --json export/m7-replay/eval.json
```

`--events-90` remains a deprecated alias; `--exit-primary` selects the fairness gate for the exit
code. Exit codes: 0 = gate rows pass, 1 = gate failures, 2 = no raw recordings. Missing replay files
print SKIP instead of crashing.

The header prints replay / fixture / engine mtimes; gate results are only current when no staleness
warning is printed.

### Self-check (wire into the wrapper / evidence step)

```
python3 scripts/m7_eval_replay.py --self-check
```

Runs synthetic regression checks on empty replay event sets, with **no raw data or engine source
needed** (fallback latency policy is used). It asserts that a silent target dataset scores
recall/coverage 0.0 and FAILs cleanly, that a genuinely absent raw recording stays SKIP, that
malformed/skipped score dicts cannot crash the gate builders, that a dataset with only unrelated
events still scores its target action, and that the report formatters render zero-score rows. Exit
0 = all checks pass, 1 = a regression/crash. Current output: `SELF-CHECK: 6/6 PASS -> OK` in <0.1 s.

## Empty-target robustness (regression gate)

A raw target recording that exists but whose replay emits **no events for a gated action** (for
example an engine regression silences BOW) is still scored - never dropped: pulse `recall = 0.0`,
held `coverage = 0.0`, and the gate row FAILs with the explicit reason
`no replay events for target dataset(s): ...`. The run also prints
`WARNING: target dataset(s) produced no replay events (gate FAIL, not skipped)`. A score is only
`skipped` when the raw recording is genuinely absent from `--data` or the replay file itself is
missing; skipped rows are never gated. Dataset selection is fixture-source based (all
`accepted/` + top-level IDLE recordings), so a replay file that drops a whole dataset still produces
failing gate rows for it.

## Ground truth

Per dataset, seconds since the first recorded sample. Ground truth is derived twice: literally on
the raw samples, and (pulse actions only) on the 90 Hz interpolated grid.

| action | rule |
|---|---|
| place | right pinch (`|thumbTip-indexTip|`, on <0.025 / off >0.045 m) run < 0.35 s; expected at release |
| break | right pinch run >= 0.35 s; expected window = the run |
| teleport | left pinch run; expected window = the run |
| menu | left-fist run (curl Schmitt on <0.50 / off >0.60), 0.08-0.45 s; expected at release |
| inventory | both-fist run <= 0.45 s with max wrist separation < 0.55 m; expected at release |
| walk | both-fist frames, head-forward wrist-difference sign changes with amplitude > 0.05 m; windows span each crossing burst (gap < 1.0 s) |
| bowDraw | both-fist frames, `|head-forward hand separation| > 0.30 m`, both wrists > -0.30 m rel head, sustained >= 0.25 s (<=0.15 s tracking gaps merged) |
| bowFire | a draw window ends with the back hand opening while the front hand is still closed |
| eat | right wrist within 0.30 m of the head, forward > -0.02 m, up in [-0.45, 0.10] m; gaps < 0.15 s merged |
| attack | right-wrist 120 ms windowed displacement speed local peak >= 1.4 m/s, one-handed (left not closed), 0.40 s cooldown |
| hotbar | right index-tip 60 ms windowed speed local peak >= 1.0 m/s while wrist 120 ms speed < 0.5 m/s, 0.18 s cooldown |
| jump | head-y rise above a dt-corrected baseline (tau 2 s, frozen while `|dev| > 0.05 m`) > 0.08 m with 100 ms head velocity > 0.25 m/s, 0.7 s cooldown |
| sneak | head drop below the same baseline > 0.10 m sustained 0.30 s; released after drop < 0.05 m for 0.25 s |
| climb | per-hand fist runs with wrist height rel head > -0.60 m |

### 90 Hz frame-rate-matched pulse ground truth

The pulse-target recordings are resampled with the fixture's exact 90 Hz rule: linear interpolation
of head pose and all 27 joints between consecutive samples, `steps = round(dt/(1/90))`, hand
interpolation only when both endpoint hand-tracking flags are set, no bridging of gaps > 0.20 s.
Sentinel head rows (head not tracked / empty head matrix) are carried from the last tracked pose so a
missing head orientation never invents motion. Basis is derived exactly as the replay harness does
(normalised matrix columns; forward = -col2; up = right x forward). Only the sampling grid changes:
the feature rules above are identical and still computed by this evaluator.

Validation: the derived 90 Hz frame grid matches the Java fixture frame counts for **8/8** pulse
target datasets (e.g. 2579, 4083, 2811 frames); the evaluator reports this check in `eval.json`
(`gt90FrameChecks`) and warns on mismatch.

Expected-count changes from raw-18 Hz -> 90 Hz GT (current recordings): place 115 -> 115,
menu 20 -> 18, inventory 24 -> 24, hotbar 18 -> 24, attack 31 -> 35, bowFire 10 -> 10,
jump 28 -> 29. The hotbar/attack increases are the under-resolution the rate fix removes.

## Scoring

- Pulse: maximum-cardinality one-to-one time matching on the 1-D time axis within the per-action
  tolerance (place/menu/inventory/hotbar 0.70 s, attack 0.50 s, bowFire 1.00 s, jump 0.60 s);
  `recall = matched/expected`, `precision = matched/detected` over target datasets; cross-dataset
  false pulses and their per-minute rate are reported. `median_match_offset_s` /
  `max_match_offset_s` quantify detection timing.
- Held: `coverage = overlap(detected runs, expected windows) / expected time`;
  `false = detected active time outside expected windows / non-expected time`; runs vs expected
  windows; cross active s/min. Literal windows use the ground-truth intervals. Latency-aware windows
  use `[start + onset, end + release]` per action.
- Target scenarios: `place` = PLACE_RIGHT_PINCH + MENU_RIGHT_PINCH (a right-pinch menu click is the
  same short-pinch detector); `menu` = ESCAPE_LEFT_FIST (left-fist tap; the engine's `leftFistTap`
  pulse is accepted as an alternative detection); `hotbar` = next/prev union on
  HOTBAR_RIGHT_TAP; `teleport` = both TELEPORT recordings; the rest map 1:1 by label.

## Bounded-latency held policy

Bounds are parsed at runtime from
`provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java` (77 constants in the current
revision, which is frozen for this evaluation). If the source is unreadable the evaluator falls back
to documented values and prints a warning; it never silently invents a bound when the source exists.

| action | onset | release | source |
|---|---|---|---|
| break | 0.35 s | 0.03 s | `PLACE_MAX_NS + PINCH_DEBOUNCE_NS` / `PINCH_DEBOUNCE_NS` |
| teleport | 0.15 s | 0.03 s | `TELEPORT_MIN_HOLD_NS + PINCH_DEBOUNCE_NS` / `PINCH_DEBOUNCE_NS` |
| walk | 0.00 s | 0.82 s | onset inside GT window (2-crossing start) / `WALK_STOP_NS + WALK_FIST_GRACE_NS` |
| bowDraw | 0.10 s | 0.03 s | `BOW_ARM_NS` / `PINCH_DEBOUNCE_NS` |
| eat | 0.06 s | 0.15 s | `EAT_LATCH_NS` / `EAT_GAP_NS` |
| sneak | 0.50 s | 0.25 s | `HEAD_SNEAK_LATCH_NS` / `HEAD_SNEAK_RELEASE_NS` |
| climbGrabLeft/Right | 0.00 s | 0.10 s | fist Schmitt transition / policy bound (no timing constant) |

## Gate

Thresholds are unchanged from v1 (`GATE_PULSE`, `GATE_HELD`, `GATE_CONTEXT` at the top of the
script): 7 pulse rows (min recall / min precision / max cross false per minute), 8 held rows (min
coverage / max false-active / max cross active s/min), 9 context-suppression rows. The two gate sets
share the same thresholds; only the GT/measurement method differs. A target action with zero replay
events is scored 0.0 and FAILs (never silently skipped); only genuinely absent raw recordings/replay
files are SKIP (see "Empty-target robustness").

Current frozen-engine run (evaluator 2026-11-03 07:26:02, produced by the final wrapper run; replays
07:25:58; engine source 07:11:23 -> fresh, no staleness warning; the empty-target robustness fix in
v2.1 does not change any of these numbers). The provider source had been edited again at 07:11:23
after the initial "frozen" note, so the wrapper was re-run after it settled; this snapshot postdates
that edit and the fix.

**Conservative literal: 20/24 rows pass -> FAIL (exit 1)**

| action | result | literal metric |
|---|---|---|
| pulse place / menu / inventory / bowFire / jump | PASS (5) | e.g. place 0.94/1.00, menu 1.00/1.00, inventory 1.00/1.00, bowFire 0.80/1.00, jump 1.00/0.93 |
| pulse hotbar | FAIL | precision 0.83 < 0.85 |
| pulse attack | FAIL | precision 0.66 < 0.80 |
| held break / teleport / bowDraw / sneak / climbGrabLeft / climbGrabRight | PASS (6) | coverage 0.90 / 0.96 / 0.78 / 0.91 / 0.96 / 0.90 |
| held walk | FAIL | false-active 0.18 > 0.10 |
| held eat | FAIL | false-active 0.25 > 0.15 |
| context suppression | PASS 9/9 | - |

**Rate-matched + latency-aware primary: 22/24 rows pass -> FAIL (2 residual rows)**

| action | result | rate-matched / latency-aware metric |
|---|---|---|
| pulse place | PASS | 0.94/1.00 (unchanged) |
| pulse menu | PASS | 1.00/0.90 |
| pulse inventory | PASS | 1.00/1.00 |
| pulse hotbar | FAIL | recall 0.75 (GT90 expects 24 taps; engine detects 18, all matched) |
| pulse attack | FAIL | recall 0.77, precision 0.71 (GT90 expects 35; engine 38 detections, 27 matched) |
| pulse bowFire | PASS | 0.80/1.00 |
| pulse jump | PASS | 1.00/0.97 |
| held break | PASS | aware coverage 1.00 / false 0.03 |
| held teleport | PASS | 1.00 / 0.00 |
| held walk | PASS | false-active 0.18 -> 0.00 (release lag <= WALK_STOP+FIST_GRACE) |
| held bowDraw | PASS | 0.97 / 0.02 |
| held eat | PASS | false-active 0.25 -> 0.11 (EAT_LATCH + EAT_GAP bound) |
| held sneak | PASS | 0.95 / 0.00 |
| held climbGrabLeft / climbGrabRight | PASS | 0.92/0.02, 0.87/0.03 |
| context suppression | PASS 9/9 | - |

Honest interpretation of the deltas:

- **walk false-active and eat false-active are method effects**: both are fully explained by the
  engine's documented release hysteresis (walk stop+fist grace 0.82 s; eat latch 0.06 s + exit gap
  0.15 s). With those bounds applied the rows pass; the literal gates remain in place.
- **hotbar precision was a GT-rate artifact**: on 90 Hz GT precision rises 0.83 -> 1.00 because the
  six "extra" engine detections were real taps that 18 Hz GT could not resolve. The residual failure
  is now recall 0.75: 6 of 24 interpolated-grid taps are not detected (unmatched GT times 8.0,
  20.2, 21.9, 22.8, 23.9 s are >1.2 s from any detection; 4.2 s is a second click adjacent to a
  matched one). Median detection delay of matched hotbar pulses is 0.28 s, consistent with
  `HOTBAR_SINGLE_DELAY_NS` (320 ms) and inside the 0.70 s tolerance.
- **attack stays genuinely imperfect**: GT90 raises expected swings 31 -> 35; precision rises
  0.66 -> 0.71 and recall 0.81 -> 0.77, still below the 0.80 gates. Median |dt| is 0.19 s; the 8
  unmatched GT90 swings all sit in the final 26-31 s tail (engine stops firing there), while 11
  unmatched engine detections cluster in 2-25 s with nearest expected 0.03-0.84 s (double-fires on
  swings). So this is not a GT-rate artifact alone: the frozen engine over-fires early in the
  recording and under-fires in the tail.

## Dataset quality finding: the "IDLE" recording is not idle

The evaluator's duplicate scan reports it automatically on every run:

- `gesturelab-IDLE-20261102-173326` is numerically identical to accepted
  `gesturelab-MENU_RIGHT_PINCH-20261102-173326`: same 563 frames, same timestamps, same head pose and
  all 27 joint translations. It is the pre-relabel MENU recording, **not** a gesture-free negative.
- The standalone `gesturelab-MENU_RIGHT_PINCH-20261102-174228` file is numerically identical to
  accepted `ESCAPE_LEFT_FIST-20261102-174228` (documented relabel source; not replayed).
- Consequence: **no true negative/idle dataset exists**; false triggers are measured on context-wrong
  datasets (cross matrix), and the IDLE replay is excluded from all gate denominators.

## Ambiguities resolved

1. MENU_RIGHT_PINCH is a right-pinch-tap recording -> ground truth `place` pulses; `menu` is the
   left-fist tap (ESCAPE).
2. IDLE duplicate (above).
3. Bow ground truth follows the spec literally (both fists closed): 10 draw windows / ~4.9 s vs 16
   labelled cycles; the looser "two-handed front/back posture, >=1 closed fist" variant (14 windows /
   ~15.3 s) is in eval.json (`bowDrawPostureVariant`), not gated.
4. Head baseline freeze uses `|dev| > 0.05 m`; SNEAK_HEAD is dominated by long head drops (28.4 s
   of 31.0 s expected sneak), matching a session where the operator stayed lowered.
5. Eat follows the spec literally (33 windows / 9.9 s after dropping zero-length single-frame
   fragments); the recording summary's 11 approach events used a different 0.28/0.35 m hysteresis.
6. Raw-18 Hz hotbar ground truth under-resolves fast taps (18 expected); the 90 Hz GT resolves 24.
7. Pulse matching is maximum-cardinality nearest on the time axis; unmatched detections on targets
   are false positives and any detection in a context-wrong dataset is a cross-dataset false trigger.
8. The two replay rates are generated separately; both are scored against their own derived GT.
9. Frame-rate-matched pulse GT is a fairness correction, not a green light: it changes expected counts
   and moves hotbar/attack residuals from precision to recall.
10. Held latency bounds are read from the current engine constants; the literal windows/gates stay as
    the conservative cross-check. Walk needs no onset shift (2-crossing start lies inside the GT
    window).
11. Exit code is conservative-literal by default; `--exit-primary` selects the fairness gate. Both
    are reported.

## Files

- `scripts/m7_eval_replay.py` - evaluator (schema 2 in `eval.json`); regression self-check:
  `python3 scripts/m7_eval_replay.py --self-check` (6/6 PASS, no raw data needed).
- `export/m7-replay/eval.json` - full metrics: groundTruth, groundTruth90, gt90FrameChecks, latency
  policy/table, both replay rates, cross matrix, `gates` (literal), `gatesLiteral`,
  `gatesPrimary`, `gatesRateMatchedPulse`, `gatesLatencyAwareHeld`, exit policy.
- `export/m7-replay{,-90,-90-nocontext}/events.jsonl` - harness output from
  `scripts/m7_lab_replay.sh` (local, gitignored).
