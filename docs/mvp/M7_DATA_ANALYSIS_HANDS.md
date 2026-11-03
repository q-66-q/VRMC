# M7 hand/pinch datasets - measured analysis (host-side)

Status: **analysis complete, read-only on data and provider code**. This document is generated from
`scripts/m7_lab_stats_hands.py`; every number below is printed by that script (sections 1-12 of its
output). Run from the repo root:

    python3 scripts/m7_lab_stats_hands.py

Raw data: `export/gesturelab-data/accepted/gesturelab-*.jsonl` (15 files, gitignored) plus the
top-level `gesturelab-IDLE-20261102-173326.jsonl` loaded for provenance/twin checks only - it is the
pre-relabel MENU capture and **there is no gesture-free idle capture** in this folder, so any "IDLE" row
in the script's negative-control tables duplicates MENU and must not be read as idle data. The rejected
17:31 batch is excluded (21-58 samples per file, no `headMatrix`).

## 1. Method, features, data inventory

All features are recomputed from the raw joint matrices; stored `*Features` are only compared against
the recomputation, never trusted:

| feature | definition |
|---|---|
| pinch | `|thumbTip - indexFingerTip|` (m) |
| fist ratio | mean over index/middle/ring/little of `dist(tip, knuckle) / max(0.02, dist(wrist, knuckle))` (smaller = more closed) |
| velocity | finite difference of joint world position `m[12..14]` over recorded `t` (epoch s); traces break on tracking loss or dt > 0.25 s |
| head frame | `headMatrix` column-major: right = col0, up = col1, forward = -col2; head pos = `m[12..14]` |
| durations | first ON sample -> first following OFF sample (reproduces the accepted summary durations) |

Data facts and caveats:

- 15 accepted files / 9,508 samples / 18.0 Hz (recorded dt p50 0.0555 s, p95 0.0562 s, max gaps up to
  2.25 s in head-only recordings). All media-time constants in the engine are therefore quantised to
  +/- 56 ms in a replay (section 10).
- The per-joint `tracked` flag written by the recorder is unreliable (51.2% of joint records in tracked
  hands are flagged false in the 15 accepted files; 50.6% if the IDLE twin is counted, matching
  analyst-head's 223,753/441,963) while the matrices are still valid. The matrices are fresh every line:
  **0/10,055 consecutive samples repeat the full tracked-hand joint position set** (verified). All-row
  head positions repeat in only 3/10,055 pairs, but that is **not** a head-anchor hold: it is the
  `headTracked=false` zero-fill sentinel block of TELEPORT_LEFT_PINCH-175731 (rows 380-383 and 403:
  head=[0,0,0], headMatrix=[]; rel t 21.10-22.38 s). Head-tracked-only repeats are 0; all 5 untracked
  head rows in the whole accepted set are exactly this sentinel block, and they are excluded from every
  head-relative feature here. Features use the matrices exactly as the live classifier and provider ABI
  do; only the hand-level tracked flag is honoured.
- `MENU` and `ESCAPE` were recorded before `headMatrix` existed (~17:45); they have head position but no
  head orientation, so head-frame geometry excludes them.
- Provenance (checked): accepted `MENU` is frame-identical to top-level `IDLE` (same 563 frames, same
  t/head/joint data; only label/sourceLabel differ); accepted `ESCAPE` matches top-level
  `MENU_RIGHT_PINCH-174228`; accepted `WALK`/others are relabelled copies. IDLE is therefore the
  pre-relabel MENU session, **not a gesture-free negative**: the confusion matrix shows it duplicating
  MENU (36 place pulses each), and the script's negative-control tables list it only for completeness.

| dataset | n | dur s | rate Hz | tracked L/R/head/headMatrix |
|---|---|---|---|---|
| MENU_RIGHT_PINCH | 563 | 31.2 | 18.0 | 179/563/563/0 |
| PLACE_RIGHT_PINCH | 1062 | 59.2 | 17.9 | 668/1055/1062/1062 |
| BREAK_RIGHT_PINCH_HOLD | 588 | 31.1 | 18.9 | 578/588/588/588 |
| TELEPORT_LEFT_PINCH (1) | 551 | 31.1 | 17.7 | 484/403/551/551 |
| TELEPORT_LEFT_PINCH (2) | 703 | 39.0 | 18.0 | 629/591/698/698 |
| ESCAPE_LEFT_FIST | 561 | 31.2 | 18.0 | 561/349/561/0 |
| INVENTORY_BOTH_FISTS | 562 | 31.1 | 18.0 | 562/562/562/562 |
| WALK_BOTH_FISTS | 558 | 31.0 | 18.0 | 544/507/558/558 |
| BOW_BOTH_FISTS | 819 | 46.7 | 17.5 | 695/758/819/819 |
| CLIMB_ALTERNATE | 561 | 31.1 | 18.0 | 526/534/561/561 |
| ATTACK_RIGHT_SWING | 520 | 31.4 | 16.5 | 25/503/520/520 |
| EAT_RIGHT_HAND_HEAD | 455 | 30.8 | 14.7 | 180/386/455/455 |
| HOTBAR_RIGHT_TAP | 558 | 30.9 | 18.0 | 519/558/558/558 |
| IDLE (MENU twin; not a gesture-free negative) | 563 | 31.2 | 18.0 | 179/563/563/0 |

Stored-vs-recomputed: pinch identical everywhere (max diff < 1e-6 - proof the recorded matrices are the
same ones the lab classifier used). Fist ratio identical for every recording **except MENU/IDLE**, whose
stored value predates the metric fix: stored p50 0.60 vs recomputed p50 0.67 (0.595 vs 0.636 on
pinch-closed frames). Concretely, the stale stored metric says 454/563 (80.6%) of MENU right-hand frames
are "fist" at <0.65, while recomputed-from-joints is **198/563 (35.2%)** overall and 72.3% only during
pinch holds (at <0.55: 105 vs 5 frames). Do not fit any threshold on the stored MENU fistRatio.

## 2. Pinch family

Recomputed pinch traces, hysteresis segmentation at the accepted 0.030 on / 0.045 off (and the engine's
0.025/0.050):

| dataset | hand | pair | completed events | unfinished | dur p25/p50/p95/max (s) | inter-event gap min/p50 (s) |
|---|---|---|---|---|---|---|
| PLACE | R | 0.025/0.050 | 76 | 0 | 0.11/0.17/0.22/4.06 | 0.22/0.50 |
| PLACE | R | 0.030/0.045 | 76 | 1 | 0.11/0.17/0.22/4.06 | 0.22/0.50 |
| BREAK | R | 0.030/0.045 | 7 | 0 | 1.98/2.24/10.44/10.44 | 1.69/2.35 |
| MENU | R | 0.030/0.045 | 42 | 0 | 0.11/0.17/0.28/0.34 | 0.17/0.72 |
| TELEPORT | L | 0.030/0.045 | 16 | 0 | 0.56/1.83/4.06/4.56 | 1.11/4.78 |

- PLACE: 76 events, **72 short < 0.35 s** (0.06-0.22 s), 4 long operator holds **0.36 / 0.61 / 3.39 /
  4.06 s**. BREAK: exactly the summary's **1.21/1.49/1.98/2.24/3.36/4.33/10.44 s**. MENU: 42 events,
  1.34 events/s. TELEPORT: 16 left holds 0.05-4.56 s across the two files.
- Margin (raw contact < 0.030 vs raw open > 0.045): contact p99 = 0.019-0.030 m, open p01 =
  0.046-0.052 m -> **17-30 mm positive margin**; only 2-19 frames per dataset sit latched in the
  0.030-0.045 jitter band (PLACE 19, MENU 18, BREAK 2, TELEPORT 3). The 0.045 off threshold is what
  absorbs those; the engine currently has no off threshold (PINCH_OFF declared but unused).
- Jitter inside holds (>=0.30 s): within-event std p50 0.0016-0.0121 m, p95 0.0033-0.0154; max sample
  step p95 0.010-0.029 m.
- Short-vs-held boundary: pooled duration histogram has a clean gap from **0.61 s (longest non-BREAK
  hold) to 1.16 s (shortest BREAK hold)**. A 0.35 s split puts the 72 PLACE short taps plus 4 PLACE
  hold outliers (0.36-4.06 s) on the long side and classifies 100% of BREAK holds as long; any split in
  (0.61, 1.16) s is 100% clean. Keep 350 ms for product intent, but the data supports 450-500 ms if
  device jitter matters.
- Debounce evidence: settle time (last frame >= 0.040 m inside the event) p50 0.000 s, p95 0.111 s
  (PLACE) / 0.222 s (MENU), max 0.555 s; only 1/0/2/1 raw contacts are a single frame (would be missed
  by the 40 ms debounce). **But** replaying the engine's exact debounce+single-threshold rule emits only
  65/76 PLACE, 36/42 MENU, 15/16 TELEPORT, 7/7 BREAK presses: 11 PLACE + 6 MENU + 1 TELEPORT contacts
  dip below 0.025 for too few frames (or bounce back into the 0.025-0.050 band) - the missing off
  threshold loses real short pinches.
- False-pinch exposure (raw frames pinch < 0.025 on the relevant hand): ATTACK R 51 frames / 11 events;
  EAT R 72 / 14; PLACE L 19 / 3; WALK L 25 / 6; SNEAK L 19 / 7; TELEPORT R 5. Pinch events during
  attack swings and eating are real in this data and will fire place/teleport if not context-suppressed.
- Pinch posture vs fist: frames inside pinch holds that also read as "fist" (< FIST_ON 0.65) =
  PLACE 75.1%, BREAK 71.6%, MENU 72.3%, TELEPORT 89.3%; at 0.55 the shares drop to PLACE 10.8%,
  BREAK 17.4%, MENU 3.1%, TELEPORT 49.4%.

## 3. Fist / both-fist family

Fist-ratio distributions (recomputed; selected rows; full table in script 3.1):

| dataset | hand | p05/p50/p95 | frames <0.55 | frames <0.65 |
|---|---|---|---|---|
| ESCAPE (tap hand) | L | 0.30/0.90/0.98 | 146 | 155 |
| INVENTORY | L | 0.31/0.93/0.97 | 91 | 103 |
| INVENTORY | R | 0.30/0.94/0.98 | 88 | 97 |
| WALK | L | 0.31/0.36/0.65 | 499 | 515 |
| WALK | R | 0.31/0.35/0.74 | 457 | 463 |
| BOW | L (front) | 0.31/0.35/0.97 | 440 | 451 |
| BOW | R (string) | 0.33/0.39/0.98 | 426 | 432 |
| CLIMB | L / R | 0.30/0.42 + 0.31/0.39 (p95 0.97) | 281 / 321 | 290 / 341 |
| EAT (eating hand) | R | 0.43/0.63/0.99 | 90 | 214 |
| HOTBAR (tap hand) | R | 0.58/0.65/0.81 | 4 | 287 |
| PLACE / MENU (pinch hand) | R | 0.55/0.68/0.88, 0.61/0.67/0.75 | 41 / 5 | 385 / 198 |

So the engine's FIST_ON=0.65 correctly catches sustained walk fists (p50 ~0.35) and deliberate fist
taps (~0.30), but it also reads 35-58% of *all* pinch-dataset frames (72-89% of pinch-hold frames) and
55% of the eating hand as "fist".

Single-hand fist events (0.55 on / 0.75 off): ESCAPE L **24** (p50 0.28 s), INVENTORY L/R **24/24**
(p50 0.28/0.22 s); with 0.65 on / 0.75 off ESCAPE still gives 24, INVENTORY 24. 0.55 on / 0.85 off also
gives 24/24 -> a 0.55/0.85 Schmitt pair is safe for these actions.

Both-fist co-occurrence (single threshold on both hands):

| dataset | both <0.55 | both <0.65 |
|---|---|---|
| INVENTORY | **24 runs / 75 frames** (p50 0.17 s, max 0.28 s) | 24 runs / 86 frames |
| WALK | 21 runs / 420 frames (p50 0.61 s, max 4.00 s) | 17 runs / 439 frames (p50 0.83 s, max 8.61 s) |
| BOW | 24 runs / 216 frames (p50 0.39 s) | 25 runs / 229 frames |
| CLIMB | 19 runs / 117 frames (p50 0.22 s) | 22 runs / 134 frames |
| EAT / HOTBAR / PLACE / BREAK | 3/1/0/0 frames | 31/108/1/0 frames |

The accepted INVENTORY summary (24 runs, 75 frames) uses the 0.55 threshold; WALK is sustained on for
420/558 frames at 0.55 (summary matches) and 439/558 at 0.65.

WALK swing signal (engine world-Z rule vs head frames; full table in script 3.4):

| signal | amp p95 |\|diff\| range | L-R corr | zero crossings | interval p50 / max | intervals >0.60 s |
|---|---|---|---|---|---|---|
| world Z (engine) | 0.445 | 1.159 | **-0.728** | 53 | 0.555 / 2.722 | 10 of 52 |
| raw head frame forward | 0.360 | 0.916 | -0.376 | 59 | 0.500 / 0.923 | 10 |
| head-yaw (yaw only) | - | - | - | 59 | 0.500 / 0.945 | 8 |
| EMA-smoothed head yaw (tau 0.8 s) | 0.485 | - | **-0.743** | 55 | 0.500 / 1.589 | 12 |

Head swing period ~1.0-1.1 s (0.9-1.0 Hz). The raw head-frame correlation is poor only because the
operator turned ~150 deg (t=13-18 s) and pitched up to 30 deg; a low-passed head yaw recovers the
body-relative signal (-0.743, better than world-Z) without the room-orientation assumption.

Engine walk replay on the WALK recording: 27 episodes, 8.61 s active of 31.0 s (**28%**). Root causes:
the engine's bow rule (both fists + raw 3D separation > 0.55) flags **159/439 both-fist frames (36%)**
as bowDraw (walk arm swing separates the hands), and crossing state resets on every transient both-fist
dropout. Measured repair path:

| walk rule variant | episodes | coverage |
|---|---|---|
| engine as coded | 27 | 28% |
| no crossing reset on both-fist drop | 40 | 44% |
| + bow guarded by projected sep > 0.40 m | 18 | 68% |
| + fist Schmitt 0.55/0.75 | 17 | 68% |
| + stop window 900 ms | 18 | 69% |

The 600 ms stop window itself is adequate for the steady ~0.9 Hz cadence (crossing interval p50
0.555 s); 12 of 52 plain intervals exceed 600 ms (turns/pauses), so 900 ms is safer but secondary.

## 4. ATTACK

Right-wrist speed (recomputed per-sample vs stored per-anchor-update):

| dataset | rec p50/p95/max | stored p50/p95/max | rec frames >1.4 | stored frames >1.4 |
|---|---|---|---|---|
| ATTACK | 1.32/2.97/4.75 | 1.41/3.20/5.15 | 228 | 253 |
| WALK | 1.36/2.48/3.75 | 1.80/3.40/6.52 | 240 | 326 |
| PLACE | 0.60/1.81/4.04 | 0.78/2.39/8.97 | 112 | 209 |
| CLIMB | 0.65/1.71/2.79 | 0.95/2.56/4.32 | 53 | 164 |
| EAT | 0.65/1.95/2.74 | 0.76/2.28/2.77 | 42 | 65 |
| BOW | 0.28/1.06/2.46 | 0.35/1.41/3.36 | 20 | 41 |
| HOTBAR | 0.10/0.36/0.65 | 0.12/0.54/0.96 | 0 | 0 |
| IDLE/MENU | 0.08/0.42/1.05 | 0.09/0.57/1.06 | 0 | 0 |

**Per-frame speed alone cannot separate attack from walking** (WALK p50 1.36 vs ATTACK 1.32, WALK p95
2.48 vs 2.97), and PLACE reaches 4.04 m/s. One-handed evidence: ATTACK has left hand tracked in only
25/503 frames and both-fist in 4/503 frames; WALK is both-fist in 439/558. Windowed displacement over
>=110 ms gives ATTACK p95 3.01 / max 4.75, WALK 2.48/3.13, PLACE 1.79/4.04, CLIMB 1.71/2.79.

Swing segmentation (speed>1.4 with re-arm): re-arm <0.8 m/s gives exactly **28 swings**, min inter-swing
gap 0.22 s, p50 0.78 s. The engine rule re-fires every 300 ms cooldown and emits **52 pulses for 28
swings**; it also fires **35 pulses on PLACE**, 13 on CLIMB, 9 on WALK, 7 on BOW, 7 on EAT.

Acceleration (right wrist) p50/p95/max: ATTACK 13.92/42.88/81.32; WALK 11.38/27.03/42.74; PLACE
4.47/17.10/88.87; EAT 6.28/18.17/26.69; CLIMB 3.03/10.89/20.06 m/s^2. Candidate rule sweep
(speed + accel + !both + !nearHead, 300 ms refractory):

| rule | ATTACK episodes | false episodes elsewhere | worst false datasets |
|---|---|---|---|
| speed>1.4 & accel>8 | 43 | 52 | PLACE 27, CLIMB 7, EAT 5, BREAK 5 |
| speed>2.0 & accel>12 | 27 (~28 true swings) | 22 | PLACE 11, WALK 3, EAT 3, BREAK 3 |
| speed>2.4 & accel>15 | 23 | 8 | PLACE 5, WALK 1, EAT 1, CLIMB 1 |
| speed>2.8 & accel>18 | 13 | 3 | PLACE 2, WALK 1 |

## 5. HOTBAR

Right index-tip vs wrist speed (recomputed): HOTBAR tip p50/p90/p95/p99/max =
0.27/0.75/1.27/2.53/3.76 m/s, wrist p95 0.36 / max 0.65. The tap is finger-only; in ATTACK/PLACE the
wrist is also fast (tip p95 4.63/3.28, wrist 2.97/1.81) so fingertip speed alone is not enough.

Independent segmentation (tip >1.2 m/s, re-arm <0.5): **22 HOTBAR events**, durations 0.05-0.22 s
(p50 0.11), peak tip 3.76 m/s. Inter-tap gaps (s, sorted): 0.50, 0.61, 0.72x5, 0.78, 0.83x2,
0.89x3, 0.94, 1.00, 1.11, 1.50, 2.22, 2.33, 4.06, 4.61. **No inter-tap gap < 0.50 s**, so the 450 ms
HOTBAR_DOUBLE_NS window matches zero of these 22 taps; this recording contains no deliberate double
tap at a normal cadence.

Engine replay emits only **7 hotbarNext pulses** for the 22 taps. Gate diagnostics at the tap start:
fist ratio p50 0.647 (p05/p95 0.60/0.73) -> 11/22 blocked by `!fistR`; 9/22 blocked by prev-tip<0.6
(fast ramp through the 0.6-1.2 band in one frame); 3/22 wrist>=0.5; 1/22 pinch<0.025.

False-tap sweep (tip-speed threshold, no other gates): at 1.2 m/s the 22 true HOTBAR taps come with 221
non-HOTBAR tap events (PLACE 44, INVENTORY 35, WALK 31, CLIMB 22, EAT 20, BREAK 16, ATTACK 14, BOW 14,
MENU/IDLE 12, ESCAPE 1), so the wrist<0.5/fist/pinch co-gates are essential.

## 6. EAT

Right wrist->head distance: EAT tracked frames n=386, p01/p05/p10/p25/p50/p95 =
0.196/0.218/0.227/0.247/0.283/0.734 m; frames <0.22/<0.25/<0.28/<0.30 m = 21/105/181/216 (46.9% of
tracked frames inside the 0.28 m gate). Other datasets with frames under 0.28 m: BOW 191 (draw hand
near the head), HOTBAR 32, CLIMB 22, PLACE 21, BREAK 5, ATTACK 1; WALK/INVENTORY/MENU/IDLE 0.

Near-head events (enter <0.28, leave >0.35): strict segmentation gives 45 fragmented events because the
recorder lost the right hand 15 times (gaps >0.2 s); **bridging tracking loss gives exactly 11 events,
durations 0.22-6.04 s (10 latched >=250 ms)** - matching the accepted summary. Latch stability inside
the bridged holds: 75-100% of frames within 0.30 m, distance range 0.054-0.129 m per hold.

Head-relative geometry (matrix head frame, datasets with headMatrix; 181 EAT near-head frames):

| group | forward p05/p50/p95 | up p05/p50/p95 | \|lateral\| p50/p95 |
|---|---|---|---|
| EAT frames <0.28 m | 0.098/0.148/0.220 | -0.211/-0.167/-0.104 | 0.080/0.128 |
| EAT frames >=0.28 m | 0.063/0.259/0.399 | -0.701/-0.229/-0.122 | 0.138/0.283 |
| all other datasets | -0.018/0.262/0.491 | -0.611/-0.202/-0.017 | 0.135/0.310 |

=> the eating hand is in front of the face, ~0.10-0.22 m forward, 0.10-0.21 m below the head, within
0.13 m laterally. A front-of-face gate `forward>0.05 && |lateral|<0.15 && up in [-0.25,-0.05]` is
satisfied by the eating frames and rejects hands beside/behind the head.

The current `eatHeld = nearHead && !fistR` gate suppresses **69.1% of EAT near-head frames** (the
eating hand is a loose half-fist, fist p50 0.63). Engine replay yields 21 eat episodes for the 11 true
near-head events (the !fist gate flickers the hold on/off), plus 9 false episodes on CLIMB, 7 on BOW,
3 on PLACE. The 250 ms latch described in the design is not present in the code.

## 7. BOW

Raw 3D wrist separation vs head-forward projection (both hands tracked):

| dataset | raw p05/p50/p95/max | projected p50/p95/max | frames raw>0.55 | frames proj>0.35 |
|---|---|---|---|---|
| BOW | 0.224/0.503/0.726/1.049 | 0.367/0.589/0.650 | 287 | 330 |
| WALK | 0.350/0.502/0.705/0.810 | 0.197/0.360/0.504 | 186 (~38%) | 33 |
| CLIMB | 0.294/0.474/0.678/0.745 | 0.167/0.373/0.466 | 180 | 52 |
| INVENTORY | 0.280/0.298/0.370/0.436 | 0.055/0.233/0.264 | 0 | 0 |
| EAT | 0.374/0.426/0.528/0.601 | 0.171/0.359/0.458 | 5 | 12 |

Raw 0.55 m corresponds to only ~0.37-0.40 m of forward separation; a projected enter of 0.35 m (exit
0.28) gives 17 runs (16 completed) vs the raw rule's 16 runs, while WALK only reaches 33 frames above
0.35 projected (vs 186 raw).

Draw cycles (raw >0.55 on, <0.44 off): **16 runs, 15 completed**, durations 0.11-4.06 s (the 16th is
still open at EOF), matching the accepted summary. Hand roles during high separation: left forward
p50 0.502 m vs right 0.049 m -> **left = front/bow hand**; left fist p50 0.34 (closed) vs right p50
0.83 (often open) -> **right = string/back hand**. Release evidence: the right hand opens inside 10/15
completed runs before the separation exits; the left opens first in only 6. Fire recommendation:
`(right fist crosses FIST_OFF while sep > 0.45) OR separation exits`.

Engine replay: BOW 19 bowDraw episodes / 17 fires for 16 draws; **WALK 44 bowDraw / 41 bowFire** and
CLIMB 20/19 are false - the raw-0.55 rule overrides walk whenever the arm swing separates the hands.

## 8. CLIMB

Closed-hand height h = wrist_y - head_y (fist ratio <0.65):

| hand | closed frames | h p05/p50/p95 | h min/max | %h>0 | %h>-0.05 (engine) | down p50/p95 | up p95 |
|---|---|---|---|---|---|---|---|
| L | 290 | -0.402/-0.290/+0.158 | -0.454/+0.208 | 17.2% | 20.7% | 0.50/1.55 | 0.41 |
| R | 341 | -0.466/-0.336/+0.160 | -0.508/+0.241 | 14.4% | 17.9% | 0.57/1.85 | 0.82 |

Alternation: L-R height difference range 1.324 m, **29 strict zero crossings** in 31 s (~15
alternating reach/pull cycles). The accepted summary's 31 is not reproducible by any natural variant
(carry-forward across tracking loss, >0 sign rule, closed-hand subsets all give 29); treat 29 as the
measured value.

Release evidence: only 1 open-hand release vs **26 height-drop releases** at the engine's -0.05 m cut -
today the grab ends mid-pull when the hand passes 5 cm below head height. Keep the open release, move
the height release to ~ -0.35 m (closed-hand h p05 is -0.40/-0.47).

Current heuristic exposure: CLIMB grabL 17 episodes/2.50 s, grabR 21/3.16 s, but also **PLACE grabR
18 episodes/3.53 s**, ATTACK grabR 13/2.74 s, BREAK 8, IDLE 2 - a closed fast hand at chest/head
height is read as a climb grab. Climb-jump never fires: 0 same-frame both-down frames and 0 windowed
(+/-0.2 s) both-down frames in CLIMB (strictly alternating), so it needs a windowed criterion and its
own dataset before trusting it.

## 9. Confusion matrix (engine replay, gui=false, seated=false, no item/climbable context)

Episode counts per dataset (15 columns; full table in script section 9, key entries):

| detector | true dataset: episodes | false episodes elsewhere |
|---|---|---|
| place (short R pinch) | PLACE 62 | MENU 36 + IDLE 36 (same recording, same gesture), EAT 12, INVENTORY/HOTBAR 3+5, CLIMB 2 |
| breakHeld (held R pinch) | BREAK 7 | PLACE 2, ESCAPE 1, EAT 1 |
| menu (left-fist tap) | ESCAPE 18 | PLACE 6, TELEPORT 3, ATTACK 2 |
| inventory (both-fist tap) | INVENTORY 24 | EAT 7, HOTBAR 4, CLIMB 4 |
| walk | WALK 27 | **0** (only clean detector) |
| bowDraw / bowFire | BOW 19 / 17 | WALK 44/41, CLIMB 20/19, EAT 1/1 |
| climbGrabL | CLIMB 17 | TELEPORT/HOTBAR/ESCAPE 1 each |
| climbGrabR | CLIMB 21 | PLACE 18, ATTACK 13, BREAK 8 |
| eat | EAT 21 | CLIMB 9, BOW 7, PLACE 3 |
| attack | ATTACK 52 | PLACE 35, CLIMB 13, WALK 9, EAT 7 |
| hotbarNext | HOTBAR 7 | CLIMB 2, BOW 2, PLACE 1 |
| teleport (L pinch hold) | TELEPORT 15 | WALK 6, PLACE 4, BOW 2 |
| climbJump | CLIMB 0 | 0 |

MENU/IDLE duplicate each other (same underlying recording); MENU is a right short-pinch session, so it
correctly appears in the place column in a non-GUI replay (same physical gesture, different game
context). Worst real false positives: bow on walk/climb, attack on place/climb, climbGrabR on
place/attack, eat on climb/bow, place on eat/climb due to loose-hand thumb-index closure.

## 10. Frame-rate caveat (18 Hz recordings vs per-anchor-update features)

- Recorded dt p50 0.0555 s / p95 0.0562 s (18.0 Hz); 15 of 455 EAT samples have gaps >0.2 s, up to
  1.36 s; JUMP has 46 gaps. Any replay must break velocity traces across gaps (the script does, >0.25 s).
- Stored per-anchor-update speed is systematically peakier than a 18 Hz finite difference: overall
  rec/stored ratio p50 0.73; for ATTACK rec p95/max 2.97/4.75 vs stored 3.20/5.15 (-7%/-8%), PLACE max
  4.04 vs 8.97, WALK 3.75 vs 6.52. The stored tails come from very short anchor-update dt; the 18 Hz
  replay is the conservative view.
- Decimating ATTACK to 9/6 Hz: speed p95 2.97 -> 2.74 -> 2.54 m/s, max 4.75 -> 4.20 -> 4.11, frames
  >1.4 m/s 228 -> 102 -> 59. Thresholds must be re-derived per sample rate or expressed as windowed
  displacement.
- Engine constants at 18 Hz: PINCH_DEBOUNCE 40 ms = 0.7 frames, PINCH_ARM 100 ms = 1.8, PLACE_MAX
  350 ms = 6.3, INVENTORY_TAP_MAX 450 ms = 8.1, ATTACK_COOLDOWN 300 ms = 5.4, HOTBAR_DOUBLE 450 ms =
  8.1, hotbar re-trigger 150 ms = 2.7, walk stop 600 ms = 10.8, bow fire 250 ms = 4.5, eat latch 250 ms
  = 4.5. Anything under ~110 ms is effectively one frame; quantisation is +/- 56 ms.
- Replay-robust: windowed wrist displacement (>=110 ms), pinch/fist ratios and hysteresis, wrist-head
  distances and head-relative geometry, fist ratio thresholds. Device-dependent: per-frame speed/
  acceleration thresholds (they see ~7-8% lower peaks in replay), sub-110 ms windows.

## 11. Cross-check against the accepted summaries

| dataset | claim | summary | recomputed | verdict |
|---|---|---|---|---|
| PLACE | pinch events | 76 | 76 | match |
| PLACE | short <0.35 s | 72 | 72 | match (0.06-0.22 s) |
| PLACE | long holds | 4 (4.06/3.39/0.63/0.61) | 4 (4.06/3.39/0.61/0.36) | match count; one duration differs by one release frame |
| BREAK | holds | 7 | 7 | durations 1.21/1.49/1.98/2.24/3.36/4.33/10.44 exact |
| MENU | events | 42 | 42 | match; 1.34/s |
| TELEPORT | left events | 16 | 16 | match; 0.05-4.56 s |
| ESCAPE | left-fist events | 24 | 24 | match at 0.55/0.75 (p50 0.28 s) |
| INVENTORY | both-fist runs / frames | 24 / 75 | 24 / 75 | match at fist <0.55 |
| HOTBAR | taps | 22 | 22 | match (0.05-0.22 s) |
| WALK | both-fist frames | 420 | 420 | match at fist <0.55 (439 at 0.65) |
| WALK | L/R z correlation | -0.73 | -0.728 | match |
| BOW | draw cycles | 16 | 16 | match (last open at EOF) |
| ATTACK | swings | ~28 | 28 | match at re-arm <0.8 m/s |
| ATTACK | frames >1.4 m/s | 228 | 228 | match (recomputed) |
| EAT | near-head events | 11 | 11 | match only when tracking loss is bridged (strict = 45) |
| CLIMB | height zero crossings | 31 | 29 | -2; no natural rule variant gives 31 (see 8) |
| MENU | fist ratio | stale stored | recomputed p50 0.67 | stored p50 0.60; recomputed used |

The only non-matches are definitional (PLACE 4th hold one release sample; CLIMB crossing count in a
one-off summary script), not data drift.

## Recommended engine changes

Concrete values, ordered by measured impact. Evidence references the sections above.

**P0 - correctness blockers**

1. **Do not let the bow rule override walk.** Today `bow = both fists && raw ||wL-wR|| > 0.55` flags
   159/439 both-fist frames of the WALK recording as bowDraw and fires 41 bow-fire pulses there; walk
   coverage on its own dataset is only 28%. Change: project the wrist separation on the head forward
   axis, **enter > 0.35 m / exit < 0.28 m** (raw 0.55 ~ projected 0.37-0.40; WALK has only 33/493
   frames above projected 0.35 vs 186 above raw 0.55); suppress bow while the walk/alternating-swing
   state is active. Fire = back (right) fist crosses **FIST_OFF (0.85)** while separation > 0.45 m, OR
   the separation run exits (observed 10/15 early opens, all 16 draws still fire).
2. **Fist threshold 0.65 -> 0.55, add off hysteresis FIST_OFF=0.85.** 0.65 misclassifies 72-89% of
   pinch-hold frames (0.55: 3-17% except TELEPORT 49%), 69.1% of EAT near-head frames and 11/22 HOTBAR
   taps; it also drives PLACE/ATTACK false climb grabs. 0.55 still yields ESCAPE 24 events / 146
   frames, INVENTORY 24 runs / 75 frames, WALK 420/558 both-fist frames; 0.55/0.85 Schmitt keeps walk
   fists latched on 80.1% of samples and still gives 24 events on ESCAPE/INVENTORY.
3. **Pinch: use the declared hysteresis.** Engine raw = pinch < 0.025 with no off threshold; implement
   **on 0.025 / off 0.050** (or 0.030/0.045). Data: contact p99 0.019-0.030 vs open p01 0.046-0.052
   (17-30 mm margin), 2-19 jitter-band frames per dataset, and the single-threshold replay misses
   11/76 PLACE, 6/42 MENU, 1/16 TELEPORT presses. Also pinch events fire during ATTACK swings (11
   events, 51 frames) and eating (14 events, 72 frames): suppress place/teleport while attack/walk/eat
   states are active, not just by threshold.
4. **Walk state: stop resetting the swing counter on transient both-fist drops**, and use a
   body-relative signal. Keep crossing>=2/600 ms as a start gate but use **900 ms stop**; measure the
   swing on the head-relative forward axis (EMA head yaw, tau ~0.8 s) or world-Z (both correlate
   -0.73/-0.74) with amplitude > 0.04 m. Coverage on WALK: 28% as coded -> 68% with the above
   (44% from no-reset alone).
5. **Attack: rising edge + windowed speed + walk suppression.** Replace "speed>1.4 re-fires every
   300 ms" (52 pulses for 28 swings, 35 false on PLACE) with: windowed 110 ms wrist speed > 2.0 m/s
   AND acceleration > 12 m/s^2, rising edge re-arm < 0.8 m/s, and require `!walkActive && !both &&
   !nearHead`. This keeps 27/28 true swings and cuts false episodes to 22 before item/climb context
   (PLACE 11, WALK 3, EAT 3, BREAK 3); 2.4/15 would give 23 true / 8 false.
6. **Climb grab/release.** Move the grab rule from `fist && h > -0.05` (only 18-21% of closed frames,
   releases mid-pull) to **`fist && h > +0.05`** for the grab onset and release on **fist open OR
   h < -0.35 m** (closed-hand h p05 = -0.40/-0.47; 26/27 current releases are the -0.05 height cut vs
   1 open-hand). Add the alternation gate (29 L-R height crossings in 31 s) and suppress while
   place/attack states are hot to cut the PLACE 18 / ATTACK 13 false grabR episodes. Climb-jump:
   current same-frame rule fires 0 times on its own dataset; use a +/-0.2 s window with both hands
   closed above the chest and moving down (vy < -0.3 each), or leave it disabled until data exists.
7. **Eat: latch + drop the fist gate.** Implement the designed **250 ms latch + on 0.28 / off 0.35**
   (currently absent; the bridged 11 holds are 0.22-6.04 s long and 75-100% of frames stay under
   0.30 m). Remove `!fistR` or use FIST_ON=0.55 (69.1% of true near-head frames are suppressed today).
   Optional front-of-face gate: **forward > 0.05 m && |lateral| < 0.15 m && up in [-0.25,-0.05]** from
   the measured EAT geometry (forward p05/p95 0.098/0.220, lateral p95 0.128, up -0.211/-0.104).

**P1 - accuracy / ergonomics**

8. **Hotbar:** drop `!fistR` and relax `prevTipSpeed < 0.6` to < 0.9 (11/22 and 9/22 taps blocked
   respectively; engine sees 7/22). Keep tip > 1.2 m/s & wrist < 0.5 m/s. Do not rely on the 450 ms
   double-tap window: no inter-tap gap < 0.50 s exists in the HOTBAR recording (22 taps, cadence
   0.7-1.0 s), so either raise the double window / require a much faster second tap, or drop
   double-tap for now.
9. **Inventory:** keep the both-fist tap <= 450 ms, but add `hand separation < 0.50 m` during the tap
   (INVENTORY separation p50 0.298 / max 0.436) and suppress while walk/bow/climb are active; the
   current rule fires 7 false episodes on EAT, 4 on HOTBAR, 4 on CLIMB while catching 24/24 true taps.
10. **Teleport:** require a left-pinch hold >= 150 ms and suppress while both-fist/walk/attack; false
    left pinches occur in WALK (6 events), SNEAK (7), PLACE (3).
11. **Short-vs-held split:** keep 350 ms as product intent (72 short taps <=0.22 s; 7 BREAK holds
    1.21-10.44 s; clean gap 0.61-1.16 s), but note 18 Hz quantisation is +/- 56 ms; 450-500 ms is the
    jitter-safe choice. Implement the split from the *first closed sample* (press time), which the
    code already does.
12. **Pinch debounce:** keep 40 ms (=1 frame at 18 Hz) - it misses only 0/1/2 single-frame contacts per
    recording; do not extend it to 2 frames, which would lose more short taps (PLACE 72 short events).
13. **Menu/place context:** MENU right short pinch is the same gesture as PLACE (both replay into the
    place detector when GUI is closed: MENU 36 place pulses). Keep GUI context gating, do not add a
    separate pinch semantic for MENU.

**P2 - data/tooling**

14. Replay harness: reset per-hand velocity history on every tracking transition (engine stale-joint
    semantics can spike a re-track frame), break traces over gaps > 0.25 s, and do not compare per-frame
    speeds directly against device values (18 Hz replay is ~7-8% lower at the attack tail; PLACE/WALK
    stored transients are 2x higher).
15. Re-record CLIMB if climb-jump is needed (alternating data has zero simultaneous both-hand-down
    frames); the current dataset validates the alternating grab/pull pattern only.
