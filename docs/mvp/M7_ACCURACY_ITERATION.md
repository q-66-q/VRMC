# M7 gesture accuracy iteration (2026-11-03, host replay; device NOT RUN)

Status: the M7 engine was re-fitted against the 14 accepted Gesture Lab datasets and validated with an
independent replay evaluator. Full provider suite is ALL PASS; the literal replay gate is **20/24 rows**
with the four residual failures analysed below. **No device/A-B evidence exists for this revision**:
the provider jar was not pushed to D1 and the installed build remains EV-0236. This document is a host
analysis record, not device evidence.

## Inputs

- 14 labelled actions / 15 accepted JSONL files (9,508 samples, ~18 Hz) under
  `export/gesturelab-data/accepted/` (gitignored; summaries/analysis tracked).
- Two independent analyses (scripts + reports, committed):
  - `docs/mvp/M7_DATA_ANALYSIS_HANDS.md` + `scripts/m7_lab_stats_hands.py` — pinch/fist/attack/
    hotbar/eat/bow/climb/walk/teleport/menu/inventory measured distributions, event segmentation,
    engine-replay confusion matrix, frame-rate caveat, P0/P1/P2 recommendations.
  - `docs/mvp/M7_DATA_ANALYSIS_HEAD.md` + `scripts/m7_lab_stats_head.py` — jump/sneak, head pose math,
    frame-rate baseline bug, sustained-crouch dropout, pitch lever, cross-dataset negatives.
- Dataset quality finding: the top-level `gesturelab-IDLE-…-173326` recording is numerically identical
  to accepted `MENU_RIGHT_PINCH-…-173326` (563/563 frames); it is **not** idle data, so there is no true
  gesture-free negative capture. False-trigger rates are measured on context-wrong datasets instead.
  MENU/ESCAPE predate `headMatrix`; the stored MENU fist ratio predates the lab metric fix (recompute).

## Tooling added

| Tool | Purpose |
|---|---|
| `scripts/m7_lab_fixture.py` | Converts raw JSONL into a compact binary fixture (literal ~18 Hz and optionally 90 Hz interpolated), never committed |
| `provider/tests/dev/vrmc/provider/M7LabReplay.java` | Replays fixtures through the real `VisionM7Gesture` (per-label game context) and emits every action event |
| `scripts/m7_eval_replay.py` | Independent ground-truth extraction from the raw JSONL + recall/precision/coverage/false-trigger scoring + per-action gates (`M7_EVAL_REPLAY.md`) |
| `scripts/m7_lab_replay.sh` | One command: build → fixtures → 90 Hz + raw replays → evaluation |
| `provider/tests/.../VisionM7GestureFuzzTest.java` | 200k random frames, no stuck hand actions, releaseAll completeness |

## What the data changed in the engine (baseline → fitted)

| Area | First M7 engine (EV-0228…0236) | Fitted engine | Evidence |
|---|---|---|---|
| Pinch | single < 0.025 threshold, `PINCH_OFF` unused | Schmitt 0.025/0.045 + raised-hand + press-speed/grip gates; releases during swings abort | hands §2 |
| Fist | single < 0.65 threshold (no off) | Schmitt 0.55/0.65; only a confirmed grip (< 0.45) blocks pinch presses | hands §3 |
| Attack | per-frame speed > 1.4 re-fired every 300 ms (52 pulses / 28 recorded swings, 35 false on PLACE) | one-handed closed-hand swing, 120 ms windowed speed ≥ 1.4 (peak policy), 400 ms cooldown, re-arm < 0.8, context suppression | hands §4 |
| Walk | raw wrist Z difference, 600 ms stop, crossings reset on every tracking dropout; bow rule stole 36% of walk | head-forward axis swing, starts on a strong first crossing, continues while both fists close, 1.2 s motion stop | hands §3 |
| Bow | both fists + raw 3D separation > 0.55 (44 false draws / 41 false fires on WALK) | bow-held context + head-forward separation 0.30/0.22 at chest height, release fires | hands §7 |
| Eat | instantaneous near-head + `!fist` (69% of true frames suppressed) | edible context + face-ball geometry + 60 ms latch + tracking-gap bridge + 0.32 m exit hysteresis | hands §6 |
| Climb | `fist && h > -0.05` (released mid-pull; false grabs on PLACE/ATTACK) | Vivecraft climb context, grab latches above the chest, releases on open hand or h < -0.50, windowed pull-down jump | hands §8 |
| Hotbar | 7/22 taps survived gates; double-tap window had no evidence | quiet-wrist index tap with index/middle specificity; delayed single decision + 500–650 ms double = one pulse per tap; return motion ignored | hands §5 |
| Jump/sneak | per-frame EMA baseline (frame-rate dependent), no adapt band; 87% sustained-crouch dropout, 5 false stand-up jumps | dt-corrected τ=2 s baseline frozen outside 0.10 m, windowed velocity, 0.12 m/0.5 s sneak, pitch gate, landing suppression | head §2–§5 |
| Context | none | GUI, seated, bow held, food/drink held, Vivecraft climbable (all fail-safe; `m7.context=off` fallback) | — |

## Replay gate (final host run, evaluator v2)

Command: `scripts/m7_lab_replay.sh` (fresh fixtures, 90 Hz + raw replays, evaluator v2). Numbers below
are from `export/m7-replay/eval.json`.

Evaluator v2 keeps the literal (raw-18 Hz GT, zero-latency) gate as the conservative cross-check and adds
the **primary** gate: pulse ground truth re-derived on the same 90 Hz interpolated frame grid as the
replay (still engine-independent), and held windows expanded by a documented bounded-latency policy per
action (constants read from `VisionM7Gesture`). Primary result: **22/24 rows pass**; literal result:
**20/24 rows pass** (baseline engine: 12/24 literal). No engine thresholds were changed to pass gates.

| Action | Rate / GT | Expected | Detected / matched | Recall | Precision | Cross fp/min | Literal | Primary |
|---|---|---|---|---|---|---|---|---|
| place | 90 Hz | 115 | 108 / 108 | 0.94 | 1.00 | 0.63 | PASS | PASS |
| menu | 90 Hz | 18 | 20 / 18 | 1.00 | 0.90 | 0.34 | PASS | PASS |
| inventory | 90 Hz | 24 | 24 / 24 | 1.00 | 1.00 | 0.22 | PASS | PASS |
| hotbar | 90 Hz | 24 | 18 / 18 | 0.75 | 1.00 | 0.56 | FAIL (literal precision 0.83) | **FAIL recall 0.75 < 0.80** |
| attack | 90 Hz | 35 | 38 / 27 | 0.77 | 0.71 | 2.80 | FAIL | **FAIL recall 0.77 / precision 0.71** |
| bowFire | 90 Hz | 10 | 8 / 8 | 0.80 | 1.00 | 0.00 | PASS | PASS |
| jump | 90 Hz | 29 | 30 / 29 | 1.00 | 0.97 | 0.12 | PASS | PASS |
| break | raw/held | 7 / 24.66 s | 7 runs / 22.6 s | 1.00 aware cov | 0.03 false | 1.0 | PASS (literal cov 0.90) | PASS |
| teleport | raw/held | 16 / 22.4 s | 15 runs / 21.7 s | 1.00 aware cov | 0.00 false | 0.4 | PASS | PASS |
| walk | raw/held | 3 / 25.7 s | 10 runs / 24.0 s | 0.87 aware cov | 0.00 false | 0.0 | FAIL (literal false 0.18) | PASS |
| bowDraw | raw/held | 10 / 4.94 s | 14 runs / 4.9 s | 0.97 aware cov | 0.02 false | 0.0 | PASS | PASS |
| eat | raw/held | 33 / 9.85 s | 19 runs / 12.3 s | 0.81 aware cov | 0.11 false | 0.0 | FAIL (literal false 0.25) | PASS |
| sneak | raw/held | 4 / 28.4 s | 4 runs / 26.0 s | 0.95 aware cov | 0.00 false | 0.0 | PASS | PASS |
| climbGrabLeft | raw/held | 16 / 14.7 s | 14 runs / 15.1 s | 0.92 aware cov | 0.02 false | 0.0 | PASS | PASS |
| climbGrabRight | raw/held | 17 / 16.9 s | 16 runs / 16.4 s | 0.87 aware cov | 0.03 false | 0.0 | PASS | PASS |
| context rows | mixed | 9 rows | 9/9 pass | — | — | — | PASS | PASS |

Baseline for comparison (first fresh evaluator run, literal gates, same datasets): 12/24 rows; place
0.31 recall & 1.13 false/min; hotbar 0.78/0.58; attack 0.42/0.87; walk false 0.19; eat false 0.40;
teleport coverage 0.38; break coverage 0.83; bowDraw 0.60; sneak 0.37 (pre dt-corrected baseline).

## Residual primary-gate failures (analysed, not hidden)

1. **hotbar recall 0.75 vs 0.80** (rate-matched GT expects 24 taps; the engine intentionally emits one
   pulse per physical tap and detects 18/24). Every detection matches (precision 1.00); the engine's
   hotbar gate set (quiet wrist, index-only specificity, 1.5 s pinch-release quiet, single-tap decision)
   is conservative to avoid cycling during pinch/walk/bow/attack. Evaluator v2 detail: the 6 undetected
   rate-matched taps sit at 8.0 / 20.2 / 21.9 / 22.8 / 23.9 s (>1.2 s from any detection; 4.2 s is a
   second click next to a matched one) and the matched detections arrive a median 0.28 s after the tap
   (the designed `HOTBAR_SINGLE_DELAY_NS` 320 ms decision, inside the 0.70 s tolerance). Loosening the
   gates would trade recall for false triggers (cross budget 0.75/min; currently 0.56/min).
2. **attack recall 0.77 / precision 0.71 vs 0.80/0.80.** GT rule pinned: right-wrist 120 ms windowed
   displacement speed local peak ≥ 1.4 m/s, one-handed (left hand not closed), 0.40 s cooldown; the
   literal 18 Hz grid yields 31 expected swings, the rate-matched 90 Hz grid 35 (an independent literal
   local-peak variant counts 29, i.e. the count is rule-sensitive at the same physical swings). The
   rate-matched GT now resolves 35 swings (18 Hz saw 31). The engine fires 38 pulses and matches 27. Evaluator v2 decomposition: the 8 unmatched
   GT swings are **all in the final 26–31 s** (the engine under-fires there; the hand stream contains a
   run of incidental thumb-index contacts that keep aborting/suppressing pinch-side state), while the 11
   unmatched detections cluster in 2–25 s at 0.03–0.84 s from true swings (double-fires per swing where
   the windowed-speed profile stays above the re-arm threshold). Median timing error of matched pulses is
   0.19 s. Attack cross-dataset rate is 2.80/min (gate 3.0/min). This row is left failing rather than
   over-fitting thresholds to the replay; the device A/B session should decide whether to prefer the
   current recall or a longer cooldown that trades double-fires for fewer detected swings.
3. **Literal-only rows** (walk false-active 0.18 vs 0.10; eat false-active 0.25 vs 0.15; literal hotbar
   precision 0.83) are causal-latency / 18 Hz-GT artifacts; the bounded-latency-aware scoring (policy
   table in `M7_EVAL_REPLAY.md`) passes all held actions and the rate-matched GT fixes the pulse rows
   except the two above. Literal metrics stay in eval.json as the conservative record.

## Device validation plan (next gate)

1. Build/push the provider jar from this commit; verify `[VRMC-M7] engine thresholds ... context=auto`
   and `[VRMC-M7] item-context probe` in the log.
2. Test each mapping on D1 against the user table (short/held right pinch, left pinch hold, left fist
   tap, both-fist tap/swing, wide both fists, near-head, index tap/double, head rise/lower, alternating
   reach/pull) plus GUI right-pinch click and left-fist close.
3. Record false-trigger rate over a 10-minute mixed session (AC-4/S5-hands); if the item-context probe
   fails on device, A/B `m7.context=off` (geometry-only fallback).
4. Tune `m7.pinch/fist` keys or use the launcher calibration/Reload input if real-hand thresholds
   differ from the lab recordings; every M7 threshold is data-derived but not device-verified.
