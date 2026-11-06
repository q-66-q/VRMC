# M7 — Simplified gesture set + Gesture Lab data collector

Status: **all 14 action datasets accepted (EV-0213…EV-0227); M7 engine implemented behind a mode
switch (EV-0228) and re-fitted against the datasets with an independent replay gate (EV-0237)**.
The thresholds below are now the implemented, data-fitted values (see §5/§15); device A/B is the only
remaining acceptance gate. See `M7_ENGINE.md` and `M7_ACCURACY_ITERATION.md`. This milestone replaces
the M4 per-finger micro-gesture layer with the operator's preferred, whole-hand scheme.

## 1. Operator intent, made precise

| # | Action | Intended gesture | Notes / conflicts resolved |
|---|---|---|---|
| 1 | Menu / UI click | System eye hover highlights; **right pinch** activates | Raw eye gaze is not exposed to third-party apps. Native SwiftUI menus get system gaze hover. In-game Minecraft GUI (a texture) cannot: see §3. |
| 2 | Escape | **left fist tap** | No close gesture; Escape/back lives in Options. |
| 3 | Walk / run | **left thumb-index pinch hold + move the left hand like a joystick** (forward/back = walk, left/right = strafe; EV-0248/EV-0249) | Analog free-move via Vivecraft `keyFreeMoveStrafe`; turning by body/head. Replaces the earlier both-fist swing walk. Left pinch is also teleport; teleport is suppressed while moving (see §2). |
| 4 | Jump | **physical head rise** (or auto-jump for one block) | Auto-jump enabled by default. Head-rise detector has hysteresis; seated fallback remains. |
| 5 | Sneak | **physical head lowering** (sustained) | Seated fallback remains; sneaking by looking down must NOT trigger. |
| 6 | Teleport | **left pinch hold → aim → release to commit** | Conflict with movement on the same pinch: teleport is suppressed while movement axes are non-zero; a dedicated gesture is still needed. |
| 7 | Attack entity / break block | **right-hand swing** = entity attack; **held right pinch** = break/mine block, release stops | Short right pinch remains place/select. Held pinch and swing are suppressed while walking, bow drawing, eating, GUI open, or climbing. |
| 8 | Eat / drink | **right hand close to head** while holding food/drink | Hold near head to continue; release/away stops. Suppressed while bow drawing. |
| 9 | Bow | **both fists, one hand front, other back; draw back hand back; release back fist** | Context override: if a bow is held, both fists mean bow, not walk. |
| 10 | Place block / break | **short right pinch** at gaze/head target while holding a block = place; **held right pinch (>~350 ms)** = break/mine continuously, release stops | A single pinch gesture is disambiguated by duration: tap = place, hold = break. Right-hand swing remains the entity attack; block breaking uses the held pinch. GUI context suppresses both. |
| 11 | Inventory | **both fists tap**; gaze/head highlight; **right pinch hold** grabs, release places | Drag semantics use pinch press/release, not click. |
| 12 | Hotbar | **right-hand tap** selects next slot; double-tap previous | Kept deliberately simple; direct 1–9 wheel remains available as fallback. |
| 13 | Climbing | **alternating hand reach up + grab + pull**, release and repeat | Detection is alternating vertical hand motion while a climbable is in reach; maps to climb actions; release on open hand. |
| 14 | Visible hands | simple 3D hand + finger geometry driven by 27 ARKit joints | Lab shows the model first; in-game overlay/renderer is a separate step. |

## 2. Why the original description needed editing

- **Eye tracking is private.** visionOS apps cannot read continuous gaze. `SpatialEventGesture` and
  `HoverEffect` give system-managed gaze hover only for SwiftUI/native controls; a rendered Minecraft
  GUI cannot know which pixel the eyes are on. The practical game-GUI implementation is a **head/eye-ray
  reticle** (head ray is available from `DeviceAnchor`) that highlights the Minecraft control under it.
  True eye hover remains native-UI only. This must be accepted or the GUI must be re-implemented natively.
- **Movement mapping (EV-0248/EV-0249):** movement is the **left thumb-index pinch virtual stick** (hold the pinch,
  move the left hand forward/back/left/right); the both-fist alternating swing no longer moves the player
  (the engine retains it only as a context/suppression signal). Left pinch is also teleport, so teleport is
  suppressed while movement axes are non-zero; a dedicated teleport gesture is a follow-up.
- **Both-fist walking conflicts** with both-fist inventory, both-fist bow, right-fist use, and both-fist
  climbing. Resolve by context + timing: tap (<250 ms, little motion) = inventory; sustained alternating
  swing = walk; bow in hand = bow; climbable in reach = climb.
- **Head-rise jump / head-lower sneak** can false-trigger from looking up/down or from recentering.
  Use vertical displacement relative to a slowly adapting baseline + velocity, with hysteresis and a
  "sitting/lying" fallback. Do not map pitch to jump/sneak.
- **"Right hand tap to select items" (resolved 2026-11-05, EV-0246):** the operator meant tapping the
  rendered HUD inventory bar itself. M7 now selects the touched slot directly: the right index fingertip
  within 6 cm of the wrist-HUD bar, the same slot held for >= 60 ms with < 3 cm drift and a 300 ms
  cooldown (guarded off in GUI/seated/HEAD-HUD/untracked/stale input). The air index-tap cycling
  (single next / double previous) remains as a fallback; no world-space hotbar item is spawned and the
  selection uses `Inventory.setSelectedSlot` (vanilla lazy carried-item packet path unchanged).
- **Climbing with alternating arms** needs a climb action held while the hand is closed/gripping; the
  existing Vivecraft climb action expects grab enable/disable. Drive it per-hand from grip above head
  plus alternating pull, and release when the hand opens.
- **GUI right pinch is the left mouse button (EV-0249):** press = click, hold = long press/drag, release =
  lift. The head-ray cursor is offset 8% below screen centre for bottom-row selection.
- **Inventory "right hand hold"** conflicts with right-fist use only outside the GUI; inside the GUI,
  right-pinch press/hold/release is the drag, and world actions are disabled.

## 3. Game-GUI gaze policy

1. Native menus (launcher, native overlays): use system gaze hover + right pinch; no custom gaze data.
2. Minecraft GUI: draw a **head-ray reticle** from the HMD forward axis; right pinch activates the
   highlighted slot; inventory drag = right pinch press/hold/release. This is head-aimed, not eye-aimed.
3. If the operator rejects head-aim for the GUI, the only true-eye option is replacing that GUI with a
   native SwiftUI/RealityKit UI — a much larger, separate milestone.

## 4. Gesture state machine (priority high → low)

1. GUI open: reticle + right pinch/drag; no locomotion/attack.
2. Bow held + both fists + front/back hand separation: bow draw/release.
3. Climbable in reach + alternating reach/pull: climb grab/release.
4. Left thumb-index pinch hold + move left hand: analog walk/strafe (EV-0249). The both-fist
   alternating swing no longer moves the player; it remains only an internal context/suppression signal.
5. Right hand near head + edible/drinkable held: eat/drink.
6. Right-hand swing velocity/acceleration above threshold: attack.
7. Short right pinch: place/select. Held right pinch: break/mine (after a 350 ms threshold), release stops.
8. Left pinch hold: teleport aim; release commits.
8. Right pinch: place block/interact at reticle.
9. Right-wrist tap: hotbar next/previous. Tapping the rendered HUD inventory bar with the right index
   fingertip selects that slot directly (touch-hotbar, EV-0246).
10. Both-fist tap: inventory.
11. Left-fist tap: Escape.
12. Idle: release all.

Every digital source has a release path on tracking loss, GUI close, mode change, and game stop.
Hysteresis: on/off thresholds differ; mode entry requires 2–3 frames; mode exit uses hold timers.

## 5. Feature definitions (implemented, fitted from the datasets)

Every value below is the constant implemented in `VisionM7Gesture` and scored by
`scripts/m7_eval_replay.py`; each is derived from the recorded distributions in
`M7_DATA_ANALYSIS_HANDS.md` / `M7_DATA_ANALYSIS_HEAD.md` and is host-replay validated (device A/B NOT RUN).

- **Pinch distance:** `|thumbTip - indexTip|`; Schmitt on < 0.025 m / off > 0.045 m, 30 ms debounce,
  80 ms re-arm. A world pinch also requires the hand raised in front (forward > 0.15 m, up > -0.55 m),
  press-time wrist speed < 1.6 m/s, and an open (not fist-gripped, curl ≥ 0.45) hand.
- **Fist curl:** mean fingertip→knuckle distance divided by wrist→knuckle distance (four fingers);
  Schmitt on < 0.55 / off > 0.65. Open-hand release p50 of the recorded relaxed hands is 0.90-0.99.
- **Walk swing:** both fists; left/right wrist difference projected on the head-forward axis (head pose
  from the HMD, not world Z); start on 2 swing crossings (or 1 crossing with ≥ 0.18 m amplitude);
  continue while both fists stay closed; stop 1.2 s after the swing motion ends. Ambient/data gap
  0.5–1.0 s.
- **Attack:** one-handed closed-hand swing; 120 ms windowed wrist displacement speed ≥ 1.4 m/s,
  400 ms cooldown, re-arm below 0.8 m/s; suppressed by both fists, walk, bow, eat, pinch, climb, GUI,
  near-head and head-gesture states (recorded accidental pinches abort within 250 ms if the hand
  accelerates like a swing).
- **Head jump:** dt-corrected head-y baseline (τ = 2 s, EMA α = 1 − e^(−dt/τ)) frozen outside a 0.10 m
  dead-band; jump if rise > 0.10 m with 120 ms windowed upward velocity > 0.35 m/s; 0.7 s cooldown;
  steep look-down (pitch < ~-46°) gated.
- **Head sneak:** `baseline - y > 0.12 m` latched 0.5 s; exit when the drop < 0.05 m for 250 ms;
  baseline freeze keeps a sustained physical crouch latched (the old per-frame EMA dropped it after ~1 s).
- **Eat/drink:** food/drink held (item context) and right wrist inside the 0.30 m face ball
  (forward > -0.02 m, |lateral| < 0.28 m, up -0.45…0.10 m); 60 ms latch, 150 ms tracking-gap bridge,
  0.32 m exit hysteresis.
- **Bow:** bow held (item context) + both fists + |head-forward wrist separation| > 0.30 m (exit 0.22 m)
  with the hands at chest height (max up > -0.30 m), armed for 100 ms; releasing the drawn bow fires
  (Minecraft hold-to-draw semantics). Without a bow in hand the gesture does nothing (context auto);
  `m7.context=off` restores a geometry-only fallback.
- **Climb:** Vivecraft climbable context + closed hand above the chest (up > -0.10 m); the grab latches
  until the hand opens or the pull passes -0.50 m; both hands pulling down within a 250 ms window is the
  climb-jump chord.
- **Hotbar tap:** right index fingertip 60 ms windowed speed > 0.82 m/s with a quiet wrist
  (120 ms window < 0.45 m/s) and index ≥ 1.35× the middle-finger tip speed; 320 ms delayed single-tap
  decision → next; a second tap 500–650 ms later → previous (one pulse per physical tap, the tap's
  return motion is ignored). No hotbar during walk/bow/eat/climb/GUI or within 1.5 s of a pinch.
- **Direct touch-hotbar (EV-0246):** when the HUD is wrist/hand-locked (`vrHudLockMode != HEAD`,
  `vrTouchHotbar` on, HUD rendered), the right index fingertip within 6 cm of the rendered bar selects
  the slot under it after a 60 ms same-slot dwell (<3 cm drift) and 300 ms cooldown. This mirrors
  Vivecraft's own `InteractiveHotbarModule` bar geometry (`GUI_RENDER_POS_ROOM`,
  `GUI_RENDER_ROTATION_ROOM`, `GUI_OFFSET_LOCAL`, `GUI_SCALE_APPLIED/MAX`); the air index-tap cycling
  above remains as the fallback.

## 6. Gesture Lab app (separate visionOS app)

- Bundle id `dev.vrmc.s2probe` (existing profile), installed alongside VRMC.
- SwiftUI window + immersive `RealityView`; 27-joint hand skeleton (spheres + bones) for left/right,
  plus head marker; records:
  - timestamp, current label, hand joint names/transforms (anchor space), head transform,
  - derived features (pinch, fist curl, wrist velocities, classification),
  - JSONL in the app's Documents, throttled to ~30 Hz; pull via devicectl.
- Manual label buttons + guided capture sequence; live deterministic classifier output so actions can
  be distinguished while recording.
- It is deliberately a data/label tool, not the production input path. Production changes land in the
  provider only after the recordings establish thresholds.
- Built app bundle: `dev.vrmc.s2probe` (signed manually; free-profile slot freed by temporarily
  removing SideStore; SideInstaller remains). Source: `runtime/gesture-lab/`.

## 7. Acceptance for M7

- Lab installs/launches, tracks both hands, renders fingers, records and exports labeled JSONL.
- Recordings cover 10 repetitions of each action for each operator; thresholds fitted and documented.
- Provider state machine implements §4 with host tests and device A/B against the old scheme.
- Device evidence for each mapping, plus no stuck input across 30 min of mixed actions.

## 8. Accepted datasets

- `MENU_RIGHT_PINCH`: 31.23 s / 563 samples / 42 pinch events; pinch p05/p50/p95 =
  0.006/0.083/0.148 m; right hand tracked throughout; source picker was IDLE and the canonical copy is
  relabelled with `sourceLabel=IDLE`. Raw JSONL stays local under
  `export/gesturelab-data/accepted/`; summary/analysis tracked. This establishes the starting
  0.030 m on / 0.045 m off pinch band; device A/B still required.

## 9. Lab data-quality fixes (EV-0214)

- Recorder now writes on either hand's anchor update (left-hand-only actions previously starved: 31 s wall
  recording yielded only 18.15 s of samples with an 11.5 s gap).
- Fist metric changed to mean(tip→knuckle / wrist→knuckle), threshold <0.55; the old palm-center ratio
  could exceed 1.0 in a fist, so live `isFist` never fired.
- Analyzer re-derives fist ratios from recorded joint transforms; existing sparse ESCAPE_LEFT_FIST data
  is not accepted; re-record required.

- `ESCAPE_LEFT_FIST`: 31.18 s / 561 samples; left hand 561/561 tracked; left fist curl p05/p50/p95 =
  0.298/0.905/0.983; 146 frames <0.55; **24 left-fist events** (0.22–0.67 s); right fist 0 frames.
  Source picker stayed MENU_RIGHT_PINCH; canonical copy relabelled with `sourceLabel` provenance.

## 10. Headset tracking in the lab (2026-11-02)

- The lab already ran `WorldTrackingProvider`; the window now shows live head x/y/z and each sample stores
  the full `headMatrix` (4x4) in addition to the `head` position, alongside the hand joints.
- Head marker (yellow sphere) remains in the immersive scene. This covers head-rise jump / head-lower
  sneak data collection without changing the game.

- `WALK_BOTH_FISTS`: 30.97 s / 558 samples; both fists 420/558 (75%); fist p50 L/R 0.359/0.348;
  relative-to-head wrist z range 0.788/0.645 m with z correlation **−0.73** (opposite phase), ~25 cycles
  (~0.8 Hz); head tracked 558/558 with full 4×4 transform. Source picker stayed MENU_RIGHT_PINCH;
  canonical copy relabelled with provenance.

- `JUMP_HEAD`: 80.03 s / 923 samples; head 923/923 tracked; head Y 1.057–1.809 m; **29 head-rise
  events** >0.08 m, peaks 0.11–0.30 m, durations 0.27–0.95 s; upward velocity p95 1.51 m/s, max 2.36.
  Starting detector: baseline EMA (τ≈2 s), >0.08 m rise and >0.25 m/s upward, 300 ms release. Minecraft
  auto-jump remains enabled for one-block steps.

- `SNEAK_HEAD`: 31.00 s / 524 samples; head 524/524 tracked; head Y 0.779–1.509 m; **5 downward
  events** >0.10 m with depths 0.10–0.25 m (two ~4.9 s holds); max speed 1.66 m/s. Starting detector:
  baseline EMA (τ≈2 s), >0.10 m drop sustained 350 ms, release within 0.05 m for 250 ms. Long holds mean
  a second pass should add more transitions.

- `TELEPORT_LEFT_PINCH`: two samples 31.09 s/551 and 38.97 s/703; left tracked 484/629; **16 left-pinch
  events** total at 0.030 on/0.045 off, from 0.05 s taps to 4.56 s aimed holds. Mapping: pinch press
  starts aim, release commits, open hand/tracking loss cancels.

- `ATTACK_RIGHT_SWING`: 31.41 s / 520 samples; right tracked 503, left 25 (one-handed); right wrist speed
  p50/p95/max 1.30/2.97/4.75 m/s; acceleration p50/p95/max 5.85/21.39/50.61 m/s²; 228 frames >1.4 m/s,
  186 >8 m/s², ~28 swings. Starting detector: right speed >1.4 m/s or acceleration >8 m/s², one-handed,
  with GUI/bow/eat/climb/both-fist suppression.

- `EAT_RIGHT_HAND_HEAD`: 30.85 s / 455 samples; right 386/455 tracked; wrist→head p05/p50/p95
  0.218/0.283/0.734 m; 181 frames <0.28 m; **11 near-head events** 0.22–6.04 s. Starting detector
  ~0.28 m with 250 ms latch, edible/drinkable context, stop >0.35 m; 0.22–0.25 m is a stronger trigger.

- `BOW_BOTH_FISTS`: 46.66 s / 819 samples; left/right 695/758 tracked; wrist separation
  0.156–1.049 m; **16 draw/release cycles** >0.55 m; left fist p50 0.349 (bow hand closed), right p50
  0.479/p95 0.983 (string hand opens on release). Starting detector: both fists, separation >0.55 m,
  release on back-hand open, walk suppressed while bow context is active.

## 11. Pinch-duration split (operator change, 2026-11-02)

- **Short right pinch (< ~350 ms)**: place block / select in world or GUI.
- **Held right pinch (> ~350 ms)**: break/mine block continuously; release stops. This replaces using a
  pinch-hold for attack. Entity attack remains the right-hand swing.
- The split needs separate datasets: `PLACE_RIGHT_PINCH` (short taps) and
  `BREAK_RIGHT_PINCH_HOLD` (1–2 s holds). Menu pinch data already represents the short end; the break
  hold dataset is still to be recorded.
- In-game context: if holding a block, short = place, hold = break; if GUI open, both are GUI actions.

- `PLACE_RIGHT_PINCH`: 59.19 s / 1062 samples; right 1055 tracked; 76 pinch events, **72 short
  <0.35 s** (mostly 0.11–0.22 s) plus 4 long holds excluded from the place fit. Short pinch =
  place/select; the long outliers belong to break semantics.

- `BREAK_RIGHT_PINCH_HOLD`: 31.11 s / 588 samples; right 588/588 tracked; 470 frames <0.03 m;
  **7 held-pinch events** 1.21–10.44 s (no short taps). Confirms short (<0.35 s) = place/select and
  held (≥0.35 s) = break/mine; the 10.44 s hold exercises long-hold stability.

- `INVENTORY_BOTH_FISTS`: 31.14 s / 562 samples; both hands 562/562 tracked; **24 both-fist tap runs
  0.06–0.28 s** (left/right matched); 75 frames both fists closed; hand separation 0.264–0.436 m.
  Rule: both fists close together <0.35 s with no sustained alternating swing → inventory.

- `HOTBAR_RIGHT_TAP`: 30.94 s / 558 samples; right 558 tracked; the tap is a **finger tap**, not a wrist
  flick: wrist max 0.65 m/s, right index-tip speed p95/p99 1.28/2.66 m/s, acceleration p95 20.8 (max
  62.6); **22 index-finger tap events 0.05–0.22 s**. Rule: quick right index-fingertip tap selects the
  next hotbar slot, double tap cycles back; suppress while walking/bow/GUI.


## 12. Dataset collection complete (2026-11-02)

All 14 intended actions have accepted labelled data. See
`export/gesturelab-data/accepted/README.md` for the consolidated table and starting thresholds. The
collected distributions are provisional: in-game A/B (and a second pass for sneak transitions) is still
required after the M7 engine lands.


## 13. GUI degradation (recorded before device A/B)

- **Current state:** the rendered Minecraft GUI receives the M7 **right-pinch click** only. There is no
  custom visual reticle and no drag-and-hold inventory gesture from M7. Native SwiftUI UI (launcher,
  system controls) still gets system gaze hover; a Minecraft GUI rendered into a texture cannot.
- **M5 device-run verification points:** inventory click accuracy (does the right-pinch click land on the
  intended slot?), whether drag-and-hold is actually needed for inventory transfer, and whether the
  missing reticle causes mis-selection.
- **Backlog:** a head-ray reticle (and, if needed, pinch-drag mapping) is M5/M6 polish. It does **not**
  block M7 device A/B; M7 should be judged on the core actions first.

## 14. Climb heuristic + runtime context

- M7 climb uses the **Vivecraft climb context** (`ClimbTracker.isGrabbingLadder()/isClimbeyClimb()`)
  plus the closed-hand-above-chest geometry and the alternating reach/pull pattern; the grab latches
  until the hand opens or the pull passes -0.50 m. In fallback mode (`m7.context=off`) it requires both
  hands; the old "closed hand above head" over-approximation was replaced after it produced false grabs
  during PLACE/ATTACK recordings (see `M7_ACCURACY_ITERATION.md`).

## 15. Accuracy iteration (2026-11-03, EV-0237; host replay, device NOT RUN)

- Two independent analyses (`M7_DATA_ANALYSIS_HANDS.md`, `M7_DATA_ANALYSIS_HEAD.md`) measured every
  gesture and found the first engine's main errors: bow rule overrode walk (44 false draws/41 false
  fires on WALK, walk coverage 28%), FIST_ON 0.65 misread pinch/eat/tap postures, `PINCH_OFF` was dead,
  attack fired per-frame speed (52 pulses / 28 swings), the eat latch was missing, the climb release cut
  the pull mid-move, the head baseline was frame-rate dependent (87% sustained-crouch dropout) and the
  hotbar lost 15/22 taps.
- The engine was re-fitted (§5) and is now scored by a replay harness + independent evaluator
  (`M7_EVAL_REPLAY.md`): literal gate 20/24 rows pass, up from 12/24; place 0.31→0.94 recall, inventory
  24/24, menu 20/20, jump 28/28, bow fire 8/8, break/teleport/bowDraw/sneak/climb rows pass,
  context-suppression 9/9. Residual literal failures are documented in
  `M7_ACCURACY_ITERATION.md` (hotbar/attack 18 Hz ground-truth resolution, walk/eat causal-latency
  tails); no device behaviour is claimed.
- Device A/B against the M4 mapping is still the acceptance gate (M7_PLAN.md step order unchanged).
- M5 device run must observe false-trigger rate while hands hang naturally, hold items, or reach above
  the head for other reasons. Expect false triggers; context gating is a follow-up.
