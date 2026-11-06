# M7 engine integration (data-driven v2; host replay-validated, device A/B pending)

## What landed

- `VisionM7Gesture` (pure Java): whole-hand state machine now fitted against the accepted Gesture Lab
  datasets and scored by an independent replay evaluator. It consumes the 27 ARKit joint positions,
  the HMD pose (head position + head right/forward axes) and a game-context bitmask.
- `VisionVR` supplies the head axes from `hmdPose`, computes the context bits and dispatches:
  - `-Dvrmc.gesture.mode=m7` (default), or tuning file `Documents/instances/default/vrmc-input-tune.properties`
    → `gesture.mode=m7`. `gesture.mode=m4`/`legacy` keeps the previous M4 binding table for A/B.
- Context bitmask: GUI open, seated, bow/crossbow held (either hand), food/drink held (main/off hand,
  reflective `DataComponents.FOOD/CONSUMABLE` probe), Vivecraft climbable context
  (`ClimbTracker.isGrabbingLadder()/isClimbeyClimb()`). Every probe is fail-safe; if the item probe is
  unavailable the engine still runs and `m7.context=off` forces the geometry-only fallback.
- New tuning keys (all optional): `m7.pinch.on/off` (fallback to the calibrated `pinch.on/off`),
  `m7.fist.on/off`, `m7.context=auto|off`. `apply-hand-calibration`/launcher sliders keep working for
  the pinch pair; the M7 fist ratio is a different metric (tip→knuckle) and therefore has its own keys.
- Minecraft `autoJump` is enabled by default in M7 mode for one-block steps.
- Host regression: full provider suite **ALL PASS**, including `m7-gesture` **73 synthetic checks** and
  `m7-fuzz` **200,000 random frames / 0 violations** (see `M7_TEST_MATRIX.md`).
- Replay gate: all 14 accepted datasets (~9,508 samples / 10,071 frames) are replayed through the real
  engine at the recorded ~18 Hz cadence and at the game's ~90 Hz cadence, then scored against an
  independent ground-truth extractor (`scripts/m7_eval_replay.py`). See `M7_ACCURACY_ITERATION.md`
  and `M7_EVAL_REPLAY.md`.

## Implemented thresholds (fitted from the datasets; device feel still to validate)

| Domain | Values |
|---|---|
| pinch | on < 0.025 m / off > 0.045 m (internal Schmitt hysteresis), 30 ms debounce, 80 ms re-arm; a deliberate world pinch also needs the hand raised in front (forward > 0.15 m, up > -0.55 m) and a press-time wrist speed < 1.6 m/s |
| fist | curl Schmitt on < 0.55 / off > 0.65; only a confirmed grip (< 0.45) blocks a pinch press |
| place/break | release < 320 ms = place pulse; held ≥ 320 ms = break (data gap 0.61–1.16 s makes any split there clean; 320 ms keeps a causal recognition latency) |
| teleport | left pinch hold ≥ 120 ms starts aim; release commits; world/seat/GUI/walk/bow/climb suppression |
| menu | left fist tap 60–550 ms with a quiet left hand, no chord/bow/climb/pinch/attack context |
| inventory | both-fist tap ≤ 450 ms, max wrist separation < 0.50 m, never walk/bow/climb/tracking-loss |
| walk | engine detector: both fists + opposite-phase swing on the head-forward axis; starts on 2 crossings (or 1 crossing with ≥ 0.18 m amplitude), continues while both fists are closed, stops 1.2 s after the swing motion ends. **Operator mapping changed 2026-11-05 (EV-0248): movement dispatch is now the left thumb-middle pinch virtual stick (forward/back/strafe analog via `keyFreeMoveStrafe`); the both-fist walk output is retained only as an internal context/suppression signal and the replay-gate walk rows remain engine tests.** |
| attack | one-handed closed-hand swing, 120 ms windowed wrist speed ≥ 1.4 m/s (peak-aligned policy), 400 ms cooldown, re-arm < 0.8 m/s, suppression by both-fist/walk/bow/eat/pinch/climb/head contexts |
| bow | bow held + both fists + |head-forward separation| > 0.30 m (exit 0.22) at chest height (max up > -0.30), armed 100 ms; release of the draw fires (Minecraft hold-to-draw semantics) |
| eat | food/drink held + right hand in the 0.30 m face ball (forward > -0.02, lateral < 0.28, up -0.45…0.10), 60 ms latch, 150 ms tracking-gap bridging, exit hysteresis 0.32 m |
| hotbar | quiet-wrist index-fingertip tap (60 ms tip window > 0.82 m/s, wrist 120 ms window < 0.45, index ≥ 1.35× middle), 320 ms delayed single-tap decision → next; a second tap 500–650 ms later → previous (one pulse per physical tap, return motion ignored). **Direct touch selection (EV-0246):** the right index fingertip on the rendered wrist/HUD inventory bar selects that slot (6 cm proximity, 60 ms same-slot dwell with <3 cm drift, 300 ms cooldown; guarded off in GUI/seated/HEAD-HUD/untracked) |
| jump / sneak | dt-corrected head baseline (τ = 2 s) frozen outside a 0.10 m dead-band; jump = 0.10 m rise + 0.35 m/s windowed velocity, 0.7 s cooldown; sneak = 0.12 m drop latched 0.5 s, released below 0.05 m for 250 ms; steep look-down (pitch < ~-46°) gates both; landing after a jump cannot sneak |
| climb | Vivecraft climb context + closed hand above the chest (up > -0.10 m in context mode); grab latches until the hand opens or the pull passes -0.50 m; jump chord = both hands pulling down within 250 ms |
| GUI | right pinch press = click; left-fist tap close pulse; world gestures suppressed |

## Replay gate status (2026-11-03, evaluator v2)

- **Primary gate: 22 / 24 rows pass** (pulse GT re-derived on the same 90 Hz interpolated frame grid as
  the replay; held windows scored with a documented bounded-latency policy read from the engine
  constants). **Literal conservative gate: 20 / 24 rows** (raw-18 Hz GT, zero-latency windows; the
  first-engine baseline was 12/24). Context suppression **9/9** on both.
- Passing primary rows: place, menu, inventory, bowFire, jump, break, teleport, walk, bowDraw, eat,
  sneak, climbGrabLeft/Right + context.
- Residual primary failures: **hotbar recall 0.75 vs 0.80** (one pulse per physical tap; 18/24 detected,
  precision 1.00 — the gate set is deliberately conservative) and **attack recall 0.77 / precision 0.71
  vs 0.80/0.80** (38 pulses, 27 matched of 35 rate-matched swing peaks; cross rate 2.80/min is inside
  the 3.0/min budget). These are documented in `M7_ACCURACY_ITERATION.md`; no thresholds were tuned to
  the gate.
- Literal-only failures (walk false-active 0.18, eat false-active 0.25, literal hotbar precision 0.83)
  are causal-latency / 18 Hz-GT artifacts and pass under the bounded-latency aware scoring.
- These are host-replay metrics against the recorded datasets; they are **not** device evidence.

## Known gaps / next device work

- Device A/B is **NOT RUN** for this engine revision. **EV-0238** pushed the provider jar `d2c8a8d9…`
  (120,666 bytes) to D1 and verified the installed jar by read-back (push round-trip + device integrity
  PASS; pre-push installed jar was `cf3ef0a0…`). The app could not be relaunched for testing at push time
  (`devicectl` RSD allocation error), so behaviour, real ARKit hand jitter at 90 Hz, the item-context
  probe, GUI-cursor click mapping and hand tracking dropouts remain device-unknown; operator A/B required.
- M7 GUI remains head-ray + right-pinch click (no true eye hover, no drag-and-hold inventory). The
  click is dispatched directly through `InputSimulator.pressMouse/releaseMouse` on the engine pulse edge:
  Vivecraft's own `guiLeftClick` binding is swallowed because `GuiHandler.processBindingsGui` gates it on
  `CONTROLLER_MOUSE_*` (written only by `processGui`, which the M7 head-cursor mixin cancels). The installed
  Vivecraft 26.2-1.3.15 runtime was bytecode-audited (EV-0245) to confirm the APIs used by the cursor/click
  fixes exist there (WindowExtension has no getActualWindowSize, onMove scale 0.5, pressMouse present +
  access widener).
- GUI cursor is centred when a screen opens and kept centred while the head ray misses the GUI plane
  (a valid hit is never overwritten by a miss). On this Vivecraft/visionOS runtime the MouseHandlerVRMixin
  scales onMove arguments by GUI_WIDTH/actualWindowSize while VR is running, so a raw uv*screenWidth write
  lands at half position and clicks miss; the provider measures that factor with a one-time probe write +
  MouseHandler read-back when a screen opens and divides every cursor write by it. The probe is keyed on
  `VRState.VR_RUNNING` and window size: the onMove scale only applies in VR, so the provider re-probes on
  the flat↔VR transition (the window does not resize when the immersive space opens) and re-centres with
  the new scale (EV-0242/0243). While a GUI is open the provider logs a rate-limited `cursor diag` line
  with uv/mouse/read-back/cursorScale/vr/window-framebuffer-GUI sizes/plane/head/dir so the on-device
  mapping can be verified from the log (EV-0239/0242/0243).
- Climb uses the Vivecraft climb context plus the geometry heuristic; no climbable-block raycast.
- Bow/eat context probes are reflective and fail closed to "not held"; verify on device and use
  `m7.context=off` if a device API drift disables the context.
- No snap-turn gesture is generated by M7 (physical turning; M4 fallback exists).

## Rollback

`gesture.mode=m4` in `vrmc-input-tune.properties` then launcher **Reload input** (or relaunch). The
provider logs `[VRMC-M7] gesture mode=...` and `[VRMC-M7] engine thresholds ... context=...` at init.
