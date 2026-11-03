# M7 head gestures: dataset analysis, head-pose math, and a dt-corrected jump/sneak design

Status: **analysis complete (host data only; no device A/B yet)**. Reproduce every number below with
`python3 scripts/m7_lab_stats_head.py` from the repo root (read-only over the gitignored JSONL captures;
prints sections 1-9 used here). Engine code analysed but **not modified**:
`provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java` lines 53-56/178-195.

## 0. Data used

15 accepted captures under `export/gesturelab-data/accepted/` plus the top-level
`gesturelab-IDLE-20261102-173326.jsonl` (label IDLE, used as the negative). `rejected/` holds four
1.1-3.2 s fragments from the earlier recorder bug and is not used. **Important data finding:** the
"IDLE" capture is byte-identical frame-by-frame to the accepted MENU_RIGHT_PINCH capture (563/563
frames), i.e. it is the pre-relabel MENU source, not a gesture-free recording (section 7).

## 1. Sampling / frame rate / stale frames

Lab captures run at a nominal **18.05 Hz** (dt p50 = 55.5 ms, p95 = 56.2 ms), while the production
engine runs `VisionM7Gesture.update()` once per **90 Hz** render frame (`VisionVR.poll()`,
missed90HzFrames budget). Per capture (n = samples; joint_rep = consecutive samples where all parsed
joint positions of a tracked hand are bit-identical):

| dataset | n | dur s | mean Hz | dt p50 ms | dt p95 ms | dt max ms | gaps>250ms | joint_rep |
|---|---|---|---|---|---|---|---|---|
| ATTACK_RIGHT_SWING | 520 | 31.41 | 16.52 | 55.6 | 56.2 | 934.2 | 5 | 0 |
| BOW_BOTH_FISTS | 819 | 46.66 | 17.53 | 55.5 | 56.2 | 845.7 | 2 | 0 |
| BREAK_RIGHT_PINCH_HOLD | 588 | 31.11 | 18.87 | 52.1 | 57.7 | 60.0 | 0 | 0 |
| CLIMB_ALTERNATE | 561 | 31.09 | 18.01 | 55.5 | 55.8 | 59.6 | 0 | 0 |
| EAT_RIGHT_HAND_HEAD | 455 | 30.85 | 14.72 | 55.5 | 134.1 | 1360.4 | 7 | 0 |
| ESCAPE_LEFT_FIST | 561 | 31.18 | 17.96 | 55.6 | 56.1 | 136.5 | 0 | 0 |
| HOTBAR_RIGHT_TAP | 558 | 30.94 | 18.00 | 55.5 | 56.1 | 58.0 | 0 | 0 |
| INVENTORY_BOTH_FISTS | 562 | 31.14 | 18.02 | 55.6 | 55.7 | 57.3 | 0 | 0 |
| JUMP_HEAD | 923 | 80.03 | **11.52** | 55.5 | **180.7** | **2249.6** | **42** | 0 |
| MENU_RIGHT_PINCH | 563 | 31.23 | 18.00 | 55.6 | 55.7 | 60.9 | 0 | 0 |
| PLACE_RIGHT_PINCH | 1062 | 59.19 | 17.93 | 55.6 | 55.8 | 302.9 | 1 | 0 |
| SNEAK_HEAD | 524 | 31.00 | 16.87 | 55.5 | 56.0 | 604.2 | 4 | 0 |
| TELEPORT_LEFT_PINCH | 551 | 31.09 | 17.69 | 55.5 | 56.2 | 603.8 | 1 | 0 |
| TELEPORT_LEFT_PINCH#2 | 703 | 38.97 | 18.01 | 55.5 | 55.9 | 96.8 | 0 | 0 |
| WALK_BOTH_FISTS | 558 | 30.97 | 17.98 | 55.6 | 56.1 | 88.1 | 0 | 0 |
| IDLE | 563 | 31.23 | 18.00 | 55.6 | 55.7 | 60.9 | 0 | 0 |

- Overall dt p50 = 55.5 ms, p95 = 56.2 ms, max = 2.25 s; 10 071 samples in 16 captures, mean 17.23 Hz.
- **JUMP_HEAD is compromised by 42 sample gaps > 250 ms** (max 2.25 s): its 80.03 s recording only has
  923 samples (effective 11.52 Hz). Any 90 Hz replay interpolates through those gaps: event timing there
  is approximate.
- **No stale frames by the consecutive-identical-joint-position test**: 0 of 16 083 tracked-hand pairs
  across all 16 captures; the recorder writes fresh joint matrices every line. (Pair scopes differ:
  16 083 = per-hand consecutive pairs with both frames tracked; 10 055 = all consecutive sample pairs.)
  Head-position repeats are 0 over head-tracked rows; over ALL recorded rows there are 3/10 055, and all
  three are the headTracked=false zero-fill rows (`head=[0,0,0]`, empty headMatrix) of
  TELEPORT_LEFT_PINCH#2 at t=21.149/21.202/21.253 s relative to capture start - missing-data sentinels,
  not a real head-anchor hold (the hands are tracked/fresh there). The accepted set contains exactly
  these 5 headTracked=false rows in total (indices 380, 381, 382, 383, 403), all in that capture, and
  they are excluded from every head-relative feature. The related data issue is the per-joint ARKit
  `tracked` flag: 50.6 % of joint records inside tracked hands (223 753/441 963) are flagged false,
  but the matrices are valid - so derive features from matrices and ignore that flag (section 7
  provenance check). Note this flag rate is 51.2 % (216 154/421 929) if only the 15 accepted captures
  are counted (scope reconciliation with docs/mvp/M7_DATA_ANALYSIS_HANDS.md).
- **Frame-rate bug:** the current baseline EMA is per-frame `alpha=0.985`, so its time constant is
  tau = 0.735 s at 90 Hz but **3.666 s at 18.05 Hz** (design intent is tau = 2 s). The lab cannot
  validate the shipped behaviour, and a frame-rate drop to 45 Hz halves the game time constant. A
  dt-corrected alpha is required.

## 2. Head pose math (headMatrix convention, provider formulas)

8 379 frames carry `headMatrix` (all accepted captures except ESCAPE_LEFT_FIST and MENU_RIGHT_PINCH,
and IDLE, which predate the 2026-11-02 "full 4x4 head transform" lab change; TELEPORT_LEFT_PINCH#2 has
5 head-tracked=false frames whose headMatrix is an empty list - excluded). Every parsed 4x4:

| check | max error |
|---|---|
| column length vs 1 | 3.89e-07 |
| column dot product | 2.43e-07 |
| det(R) vs +1 | 9.72e-07 |
| m[3], m[7], m[11], m[15]-1 | 2.38e-07 |
| translation vs recorded head position | 0.00e+00 m |
| cross(col0,col1) vs col2 | 3.53e-07 |
| cross(forward,up) vs col0 | 3.94e-07 |

**Verified convention:** column-major simd_float4x4 in ARKit device orientation; col0 = right,
col1 = up, col2 = backward, col3 = translation (= head position). det = +1 and
cross(right,up) = backward => right-handed, **forward = -col2**. Semantic cross-check on
EAT_RIGHT_HAND_HEAD (the eating hand must be in front of the face): wrist->head projection on
forward = p05/p50/p95 **0.099/0.206/0.381 m** (100.0 % of frames in front); projection on +col2 is
the negated distribution. So forward = -col2 is correct.

Exact provider formulas (flat JSON array layout; the Java accessors are the same column-major layout -
`VisionVR` line 981 already uses `hmdPose.m30/m31/m32` as the head position):

    float fwdX = -m[8], fwdY = -m[9], fwdZ = -m[10];   // forward = -col2 (backward)
    float upX  =  m[4], upY  =  m[5], upZ  =  m[6];    // up      =  col1
    float rgtX =  m[0], rgtY =  m[1], rgtZ =  m[2];    // right   =  col0
    float pitch = asin(clamp(fwdY, -1, 1));             // radians, + = looking up
    float yaw   = atan2(-fwdX, -fwdZ);                  // 0 = facing -Z
    // head position = (m[12], m[13], m[14]) = hmdPose.m30/m31/m32

Head yaw is **not** stable while walking in place: WALK_BOTH_FISTS has net yaw sweep -0.1 deg but a
p2-p98 span of **181.7 deg** (one ~182 deg turn), yaw-rate p50/p95/max = **11.3/85.5/294.0 deg/s**,
17.2 % of frames > 30 deg/s. Body forward is **not recorded** (no body/anchor pose in the JSONL), so a
head-frame walk detector cannot rely on a fixed world forward axis; head-relative features must be
anchored at gesture start.

Pitch -> HMD height lever, fitted on 9 body-height-stable captures (n = 5 312 frames, residual std
6.0 mm): `y_hmd(theta) = y0 + 0.1038*cos(theta) + 0.0945*sin(theta)` (theta = head pitch, radians).
Pitch-only height change: -20 deg = -38.6 mm, -30 deg = -61.2 mm, **-40 deg = -85.0 mm, -50 deg =
-109.5 mm, -60 deg = -133.7 mm**; +30 deg = +33.4 mm, +45 deg = +36.4 mm. So a fast look-up cannot
reach the 0.10 m jump threshold (max pitch-up effect ~37 mm), but a sustained look at the feet can
cross the 0.10 m sneak threshold beyond about -47 deg.

## 3. JUMP_HEAD

- n = 923, dur 80.03 s, head tracked 923/923. Head Y min/p05/p50/p95/max =
  **1.057/1.285/1.460/1.650/1.809 m**. Per-frame vertical speed |v| p50/p95/max =
  **0.23/1.51/2.36 m/s** (matches the accepted summary's "upward velocity p95 = 1.51, max = 2.36").
- **Reference segmentation** (baseline EMA alpha = 0.02/sample at 18 Hz ~ tau 2.75 s, event when
  gap > 0.08 m, release when gap <= 0.03 m): **29 events**, peaks **0.114-0.317 m**, durations
  **0.22-3.95 s** (median 0.39 s; one 3.95 s stay). This reproduces the accepted summary's 29 rises /
  peaks 0.11-0.30 m / mostly 0.27-0.95 s + one 3.95 s stay (max peak 0.317 rounds to 0.32 vs 0.30).
- Per-event rise time to peak is 0.00-0.17 s (sampling-limited); 100 ms-window peak velocities within
  the 29 events are 0.11-1.69 m/s. The acceptance criterion "velocity > 0.25 m/s" is amortised: a
  rise lasting > 0.32 s with 0.08 m of travel has a mean velocity below 0.25 m/s, so **single-frame
  velocity is fragile** at both 18 and 90 Hz; a 120 ms window is stable.
- Detector comparison on JUMP_HEAD (jump pulses / sneak latch intervals):

| simulation | jumps | sneak intervals | sneak active |
|---|---|---|---|
| current engine, lab 18 Hz replay | 30 | 1 | 0.11 s |
| current engine, 90 Hz replay | 31 | 2 | 0.86 s |
| dt-corrected tau=2 s, 90 Hz (thresholds unchanged) | 31 | 4 | 1.00 s |
| **PROPOSED, 18 Hz replay** | 30 | 0 | 0.00 s |
| **PROPOSED, 90 Hz** | 31 | 0 | 0.00 s |

- Against the 29 reference events: current@90 matches 29/29 with 2 multi-trigger events (a second pulse
  inside one rise: 7.72/8.56 s and 57.58/58.81 s); **proposed@90 matches 29/29 with 1 extra pulse
  (9.99 s, inside the gap-interpolated 3.95 s elevated stay; not a new physical jump) and 1
  multi-trigger**. Proposed jump-trigger head pitch min/median/max = **-26.1 / -4.9 / +6.9 deg**
  (deepest look-down in the capture -51.4 deg), so the -45 deg pitch gate costs no recall here.
- Frame-rate dependence (JUMP_HEAD, current vs proposed J/S): 18.05 Hz 31/3 vs 31/0; 30 Hz 31/4 vs
  31/0; 45 Hz 30/3 vs 31/0; 90 Hz 31/2 vs 31/0; 120 Hz 32/2 vs 31/0; 144 Hz **34/1** vs 31/0. The
  current detector's output depends on frame rate; the proposed one does not. The 2 current sneak
  latches on JUMP_HEAD are baseline-adaptation artefacts, not crouches.
- Head-y variance decomposition: var(head y) = **0.01148 m^2** (std 0.107 m), range 0.752 m. The
  pitch-only model explains only **R^2 = 0.06** of head-y variance in this capture; the other 0.94 is
  body height (jumps, squats, step-ups, sensor noise). Reference-event vertical travel = 6.04 m (sum
  of 29 peak gaps) vs total travel sum|dy| = 28.10 m, so ~78 % of vertical travel is not the jump
  gesture. Baseline-adaptation effects: the 3.95 s elevated stay spans three sample gaps; a 90 Hz
  replay sees a slow smooth rise there and the current engine fires extra pulses. No reference rise is
  missed by the current detector on this capture, so the damage is false positives/double pulses, not
  misses.

## 4. SNEAK_HEAD: the sustained-crouch dropout is real

- n = 524, dur 31.00 s, head tracked 524/524. Head Y min/p05/p50/p95/max =
  **0.779/0.822/0.956/1.492/1.509 m**; dt p50/p95/max 55.5/56.0/604.2 ms; max head speed **1.66 m/s**
  (accepted summary reproduced).
- Reference downward events (same alpha = 0.02 baseline, drop > 0.10 m, release > 0.05 m): **5 events**,
  durations **4.89 / 4.38 / 0.39 / 2.56 / 1.22 s**, peak baseline gaps **0.11-0.60 m**. The accepted
  summary's event count and "two ~4.9 s holds + 0.33/2.56/1.33 s" shape match; **the accepted
  "depths 0.10-0.25 m" cannot be reproduced**: stand-to-crouch minima are **0.56-0.71 m** drops.
- Physical crouch intervals (raw head y < standing-0.20 m; 1.4 s debounce of gaps; deliberately deeper
  than the -0.12 m detector threshold): **5.06 / 7.49 / 3.78 / 3.00 / 6.31 s**, total 25.63 s.
- **Frame-by-frame current-algorithm replay** (exact `:178-195` logic: alpha 0.985/frame, rise/drop
  thresholds, 350 ms latch, instant release, 700 ms jump cooldown):

| input | sneak latches | latch intervals (s) | jump pulses | physical crouch covered | dropout |
|---|---|---|---|---|---|
| current, lab 18 Hz replay | 4 | 1.28-5.78, 8.77-12.04, 21.52-23.58, 25.39-25.94 | 5 | 10.38/25.63 s | 15.24 s (59 %) |
| **current, 90 Hz replay** | 5 | 1.24-2.36, 8.00-8.88, 16.50-16.84, 21.28-21.99, 24.83-25.17 | 5 | **3.38/25.63 s** | **22.25 s (87 %)** |
| dt-corrected tau=2 s, 90 Hz | 6 | 1.22-4.16, 4.54-5.63, 8.12-10.23, 16.62-16.81, 21.37-23.47, 24.91-25.51 | 6 | 9.02/25.63 s | 16.61 s (65 %) |
| **PROPOSED, 18 Hz replay** | 4 | 1.50-6.56, 8.17-15.89, 16.61-20.30, 21.41-30.94 | 0 | 23.63/25.63 s | 2.00 s (8 %) |
| **PROPOSED, 90 Hz** | 4 | 1.40-6.54, 8.07-15.72, 16.53-20.26, 21.34-30.76 | 0 | **23.97/25.63 s** | **1.65 s (6 %)** |

  At 90 Hz a 4.9 s physical crouch produces sneak for only **1.11 s** (event 1) / **0.88 s** (event 2);
  the flag releases while the headset is still lowered (mechanism: with tau = 0.735 s the gap decays as
  D*exp(-t/tau) and falls back under 0.10 m after tau*ln(D/0.10) = 0.67 s for D = 0.25 m and 1.31 s for
  D = 0.60 m). The same code replayed at the lab's 18 Hz does not drop out as fast, which is why the
  lab recording hides the bug. The 5 jump pulses the current engine fires on the SNEAK capture are
  **false jumps on standing up** after the fast baseline was dragged down.
- Synthetic tests (90 Hz, y starts at 1.50 m): a 4.9 s crouch holds: current releases after 0.34 s
  (depth 0.25 m) / 1.00 s (depth 0.60 m); proposed keeps the latch for 4.85 / 4.91 s until the operator
  actually stands. A 0.20 m step-up + 3 s stay + 0.30 s down: current 1 jump + 1 sneak, proposed
  1 jump / 0 sneak. A slow 0.15 m rise over 1.5 s: 0/0 for all detectors (correct - not a jump). A
  walking bob (0.0545 m amplitude, 0.65 Hz, 10 s): 0/0 for all.
- Look-down risk: the current 0.10 m threshold is below the pitch-only drop beyond about -47 deg
  (see section 2). Synthetic -30/-50 deg look-down: 0/0; **-60 deg look-down: current fires a false
  JUMP on the return (baseline inversion), dt-corrected/proposed latch sneak for ~1 s**. Real
  look-down data: PLACE has head pitch p2/p50/p98 = -51.4/-18.7/+29.6 deg, TELEPORT#2 -35.0/-9.6/+0.9
  deg; SNEAK itself -56.4/-32.4/-2.4 deg (the operator looks down while crouching, so a
  pitch-compensated height is the clean phase-2 fix, not a pitch gate).

## 5. Cross-dataset head motion + false-trigger rates

Current = shipped detector replayed at 90 Hz; proposed = section 6 algorithm. yRange = head y span,
winV95/winVmax = 120 ms-window vertical speed p95/max, pitch = head pitch p2/p98 (deg).

| dataset | dur s | yRange m | winV95 m/s | winVmax m/s | pitch02/98 deg | current J/min | current S/min | proposed J/min |
|---|---|---|---|---|---|---|---|---|
| ATTACK_RIGHT_SWING | 31.41 | 0.052 | 0.07 | 0.15 | -22.8/-1.0 | 0.0 | 0.0 | 0.0 |
| BOW_BOTH_FISTS | 46.66 | 0.048 | 0.03 | 0.09 | -9.2/1.6 | 0.0 | 0.0 | 0.0 |
| BREAK_RIGHT_PINCH_HOLD | 31.11 | 0.060 | 0.05 | 0.14 | -10.9/28.9 | 0.0 | 0.0 | 0.0 |
| CLIMB_ALTERNATE | 31.09 | 0.113 | 0.10 | 0.21 | -7.4/28.3 | 0.0 | 0.0 | 0.0 |
| EAT_RIGHT_HAND_HEAD | 30.85 | 0.030 | 0.03 | 0.05 | -11.8/3.7 | 0.0 | 0.0 | 0.0 |
| ESCAPE_LEFT_FIST | 31.18 | 0.062 | 0.04 | 0.07 | n/a | 0.0 | 0.0 | 0.0 |
| HOTBAR_RIGHT_TAP | 30.94 | 0.040 | 0.03 | 0.12 | -10.5/6.8 | 0.0 | 0.0 | 0.0 |
| INVENTORY_BOTH_FISTS | 31.14 | 0.066 | 0.05 | 0.16 | -13.2/36.7 | 0.0 | 0.0 | 0.0 |
| JUMP_HEAD | 80.03 | 0.752 | 1.47 | 2.08 | -34.8/1.7 | 23.2 | 1.5 | 23.2 |
| MENU_RIGHT_PINCH | 31.23 | 0.095 | 0.10 | 0.20 | n/a | 0.0 | 0.0 | 0.0 |
| PLACE_RIGHT_PINCH | 59.19 | 0.471 | 0.52 | 1.58 | -51.4/29.6 | **4.1** | 0.0 | 1.0 |
| SNEAK_HEAD | 31.00 | 0.731 | 1.25 | 1.63 | -56.4/-2.4 | **9.7** | 9.7 | 0.0 |
| TELEPORT_LEFT_PINCH | 31.09 | 0.053 | 0.05 | 0.13 | -14.1/2.9 | 0.0 | 0.0 | 0.0 |
| TELEPORT_LEFT_PINCH#2 | 38.97 | 0.110 | 0.06 | 0.14 | -35.0/0.9 | 0.0 | 0.0 | 0.0 |
| WALK_BOTH_FISTS | 30.97 | 0.150 | 0.62 | 0.89 | -28.8/3.8 | 0.0 | 0.0 | 0.0 |
| IDLE (negative) | 31.23 | 0.095 | n/a | n/a | n/a | 0.0 | 0.0 | 0.0 |

Counts (not rate-normalised): current JUMP 31 jumps/2 sneak, SNEAK 5 jumps/5 sneak, PLACE 4 jumps;
proposed JUMP 31/0, SNEAK 0/4, PLACE 1/0; all other captures 0/0.

**WALK is walking-in-place with real physical bobbing** (~0.65 Hz, p2-p98 0.109 m, 120 ms-window
vertical speed p95 0.62 m/s / max 0.89 m/s) and a ~182 deg head yaw turn - yet neither detector fires on it: the
2 s baseline and the 0.10 m rise / 0.12 m drop thresholds reject the periodic bob. **Strongest residual
false-positive class is PLACE**: the operator physically bends down and stands back up while placing
(head y range 0.471 m, pitch to -65 deg); a fast stand-up is indistinguishable from a jump by head y
alone. Current fires 4 jump pulses; the proposed -45 deg pitch gate removes 3 (trigger pitches
-65/-46/-48 deg), leaving 1 at -33 deg that needs context gating (suppress jump while placing) or A/B.

## 6. Recommended dt-corrected head algorithm (concrete constants)

Replace the head block of `VisionM7Gesture.update()` (`:178-195`):

| constant | current | proposed | why |
|---|---|---|---|
| baseline update | `alpha=0.985` per frame | `alpha = 1-exp(-dt/2.0)` | frame-rate independent; tau = 2 s design intent |
| BASELINE_ADAPT_BAND | none | **0.10 m** | adapt only while |headY-baseline| <= band; freeze outside => crouch cannot drop out |
| HEAD_JUMP_RISE | 0.08 m | **0.10 m** | 29/29 JUMP rises still detected; trims stand-up false positives |
| jump velocity | >0.25 m/s single-frame | **>0.35 m/s over a 120 ms window** | single-frame dy/dt is edge-case fragile (gaps, duplicate stamps); window is rate-robust |
| HEAD_JUMP_COOLDOWN | 0.70 s | 0.70 s | unchanged; still allows a double pulse inside a 3.95 s stay - acceptable |
| HEAD_JUMP_PITCH_GATE | none | **-45 deg** | ignore head rise while looking deeper down (needs hmdPose pitch); PLACE 4 -> 1 |
| HEAD_SNEAK_DROP | 0.10 m | **0.12 m** | real crouches are 0.56-0.71 m; 0.12 m sits above the -50 deg pitch-only drop (109.5 mm) with 10 mm margin (-60 deg still crosses it - phase 2) |
| HEAD_SNEAK_LATCH | 0.35 s | **0.50 s** | proposed baseline trade-off: JUMP sneak pulses 2 at 0.35 s -> 0 at 0.50/0.60 s; SNEAK latches stay 4 at all three; PLACE 1/0 at 0.50 s |
| HEAD_SNEAK_EXIT | none (instant) | **0.05 m for 0.25 s** | documented design hysteresis; ends chattering |
| jump/sneak interaction | none | jump cancels sneak + 0.30 s re-latch suppression | jump wins; never both |
| baseline re-init | none | reset on tracking loss > 500 ms, seated toggle, manual recentre | avoids a stuck baseline after environment changes |
| phase 2 (optional) | - | `headY_eff = headY - (0.1038*cos(pitch) + 0.0945*sin(pitch))` | removes look-down/up height lever entirely; needs the full hmdPose (or pitch) passed into update(); current signature only passes headX/Y/Z |

Pseudocode:

    dt = clamp((nowNs - prevNs)*1e-9, 1e-3, 0.25)
    gap = headY - baseline
    if abs(gap) <= ADAPT_BAND: baseline += (1 - exp(-dt/TAU)) * gap   // re-centre near the baseline
    vel = (headY - headY[t-0.12s]) / 0.12                            // windowed, not single-frame
    if !gui && !seated && now >= jumpCooldown && gap > RISE && vel > VEL && pitch > -45:
        jumpPulse(80ms); jumpCooldown = now + 700ms; suppressSneakUntil = now + 300ms
        if sneaking: sneaking = false                                // jump wins, never both
    if gap < -DROP && now >= suppressSneakUntil:
        sneakSince = sneakSince or now; if now - sneakSince >= LATCH: sneaking = true
    else sneakSince = null
    if sneaking && gap >= -EXIT for EXIT_HOLD: sneaking = false      // exit hysteresis

Under the proposed baseline a latch of 0.35 s gives 2 JUMP sneak pulses, 4 SNEAK latches (5.29/7.80/3.87/
9.56 s) and PLACE 1/1; 0.50 s gives 0 / 4 (5.14/7.66/3.72/9.41 s) / 1/0; 0.60 s gives 0 / 4
(5.03/7.56/3.62/9.30 s) / 1/0. 0.50 s is the smallest latch that removes the jump-anticipation
squats while keeping the intended long holds.

Simulation results at 90 Hz across all captures: only JUMP (31/0), SNEAK (0/4) and PLACE (1/0) produce
any output; every other capture, including the IDLE negative and WALK, is 0/0. Rate invariance
(proposed, 18.05/30/45/90/120/144 Hz): JUMP always 31/0, SNEAK always 0/4, WALK 0/0, PLACE 1/0.

## 7. IDLE negative analysis (all 14 gesture candidates) - and a data trap

**The "IDLE" capture is not an idle negative.** It is byte-identical to the accepted MENU_RIGHT_PINCH
capture (563/563 frames; same labels except the relabel; sourceLabel=IDLE). It contains deliberate
MENU activity, and there is **no true idle recording** in `export/gesturelab-data`. For jump/sneak it
is still a valid negative (head y range 0.095 m, |v| p95 0.10 m/s, 0 false jumps/sneak); for hand
gestures it must be read as MENU data. IDLE quality: n=563, 31.23 s, right hand tracked 563/563, left
only 179/563. **Feature provenance:** the recorded `rightFeatures.fistRatio` is a STALE pre-fix metric
for this MENU/IDLE capture only - stored 454/563 frames < 0.65 (p50 0.604) vs **198/563 recomputed from
the joint matrices (p50 0.665, mean |diff| 0.066, p95 0.138)**; all 13 other accepted captures match
stored == recomputed exactly. Stored pinch equals |thumbTip-indexTip| recomputed to **1.5e-08 over 9 185
frames**, proving the matrices are the exact ones the lab classifier used. Fist thresholds must be
fitted on the recomputed ratio for MENU/IDLE (cross-checked with docs/mvp/M7_DATA_ANALYSIS_HANDS.md).

| candidate detector | rule | events | events/min |
|---|---|---|---|
| pinch RIGHT (menu/place/break) | pinch < 0.025 on, > 0.05 off, 40 ms debounce | 38 (42 raw) | 73.0 |
| pinch LEFT (teleport) | same | 0 | 0.0 |
| fist LEFT (escape) | curl < 0.65, > 0.75 off (recomputed) | 1 (75 frames <0.65) | 1.9 |
| fist RIGHT (use/climb) | same | **5 (198 frames <0.65)** | 9.6 |
| both fists | L and R < 0.65 together | 2 | 3.8 |
| walk (alternating swing) | >=2 z-sign crossings, |dz|>0.04, 600 ms stop | 0 | 0.0 |
| bow (both fists + separation) | both fists and sep > 0.55 m | 0 | 0.0 |
| climb grab (fist above chest) | fist and wrist.y-head.y > -0.05 m | 2 | 3.8 |
| attack (right wrist speed) | >1.4 m/s | 0 | 0.0 |
| eat (right hand near head) | wrist-head < 0.28 m, 250 ms latch | 0 | 0.0 |
| **hotbar (right index tip)** | tip speed > 1.2 and wrist speed < 0.5 m/s | **12** | **23.1** |
| jump (current detector) | rise > 0.08 + v > 0.25 | 0 | 0.0 |
| jump (proposed detector) | rise > 0.10 + 120 ms windowed v > 0.35 | 0 | 0.0 |
| sneak (current detector) | drop > 0.10, 350 ms latch | 0 | 0.0 |
| sneak (proposed detector) | drop > 0.12, 500 ms latch | 0 | 0.0 |

Reading: the right-pinch count (42 raw 0.030/0.045 edges = the accepted MENU summary's 42) validates
both the detector and the IDLE==MENU identification. The **hotbar fingertip rule fires 12 times in
31 s of menu pinching** - a real false-trigger risk (pinch finger motion looks like a fingertip tap)
that the hands chain should re-check with the full engine gate set (it reduces to ~1 pulse there).
Using the recomputed ratio, 198/563 = 35.2 % of MENU frames read as fist at 0.65 (p50 0.665) - a much
smaller caveat than the stale 81 % implied; this matters for the fist-based gestures
(walk/inventory/bow/climb), not for jump/sneak.

## 8. Cross-check against the accepted summaries

| claim | recomputed | verdict |
|---|---|---|
| JUMP 29 rises > 0.08 m, peaks 0.11-0.30 m, mostly 0.27-0.95 s + one 3.95 s stay | 29 events, peaks 0.114-0.317 m, median 0.39 s, one 3.95 s stay | reproduced (max peak 0.317 vs 0.30) |
| JUMP upward velocity p95 1.51 / max 2.36 m/s | |v| p95 1.51 / max 2.36 m/s | reproduced |
| SNEAK 5 drops, two ~4.9 s holds, durations ~0.33/2.56/1.33 s | 5 drops, durations 4.89/4.38/0.39/2.56/1.22 s | reproduced |
| SNEAK depths 0.10-0.25 m | stand->min 0.56-0.71 m; alpha=0.02 baseline gaps 0.11-0.60 m | **not reproducible - prior summary is wrong** |
| SNEAK max head speed 1.66 m/s | 1.66 m/s | reproduced |
| MENU 42 pinch events (source picker IDLE) | 42 raw pinch edges in the byte-identical IDLE file | reproduced |

## 9. Data-quality issues / blockers

1. **IDLE is mislabelled MENU data** (byte-identical) - a true 30 s idle capture must be recorded before
   any negative-rate table for hand gestures can be trusted. Head jump/sneak negatives are unaffected.
2. **JUMP_HEAD has 42 gaps > 250 ms** (max 2.25 s, effective 11.52 Hz); 90 Hz event timing there is
   interpolation, and the 3.95 s stay is gap-merged. No stale joint repeats exist in any capture (0 of
   16 083 pairs), but a clean 90 s re-record is recommended before final constant tuning.
3. The lab runs at 18 Hz while the engine runs at 90 Hz per frame; a fixed per-frame EMA cannot be
   validated on this data at all - the dt-corrected design above is the fix.
4. Three captures (ESCAPE_LEFT_FIST, MENU_RIGHT_PINCH, IDLE) predate the headMatrix change and
   have no head pose beyond x/y/z; TELEPORT_LEFT_PINCH#2 has the dataset's only 5 headTracked=false
   frames (indices 380,381,382,383,403) with head=[0,0,0] and empty headMatrix - the zero-fill sentinel
   behind the 3 all-row head-position repeats above; excluded from every head-relative feature.
5. PLACE data implies a residual stand-up-as-jump false positive (1 pulse in 59 s with the pitch gate);
   in-game A/B with placing is needed.
6. **The recorded rightFeatures.fistRatio is stale for the MENU/IDLE capture only** (stored 454/563 vs
   198/563 recomputed < 0.65; mean |diff| 0.066). Per-joint `tracked` flags are unreliable (50.6 %
   false inside tracked hands) but matrices are valid (pinch reproduced to 1.5e-08); derive features
   from matrices and ignore the flag - confirmed independently by docs/mvp/M7_DATA_ANALYSIS_HANDS.md
   (task-1).
7. Phase-2 pitch compensation needs the engine to receive the full hmdPose (or at least pitch); the
   current `update()` signature only passes headX/Y/Z.
