# Immersive input (M4-W1) — design and interface contract

Status: **IMPLEMENTED — host + simulator PASS (EV-0095); device synthetic and real-hands runs NOT RUN**
(2026-11-01). Owner: Lead. This document is the interface contract for the M4-W1 workstream: make the
game controllable **from the immersive scene**, not only from the 2D window. Verification checklist and
independent audit: [m4-input-verification.md](m4-input-verification.md).

## 0. Problem statement and scope

Today (post EV-0094) a JIT game renders correctly in the immersive space with stereo + head tracking,
but the only working input path is the visionOS **window**: the game surface view (Amethyst
SurfaceViewController, still alive behind the parked window) receives UIKit touch/pointer events, so a
user can move the pointer and click while the window is interactive. Once the immersive space is up, the
windows are parked (alpha 0, isUserInteractionEnabled=false), the compositor only presents provider eye
textures, and there is **no input path at all** — the user cannot click through the Vivecraft main menu
or act in the world. That is the reported defect: *"when the game is launching the user can only control
using the window, not from the immersive scene."*

M4-W1 delivers the first end-to-end hands-only slice:

1. ARKit hand tracking in the compositor -> bridge -> Java provider (new ABI v3 input channel).
2. Gesture recognition (pinch / fist, with hysteresis, arming, and fail-safe release) in the provider.
3. Gaze/hand-aim pointer: right hand pose drives Vivecraft's controller-0 aim so the Vivecraft GUI
   cursor follows the hand ray; a head-gaze fallback pose is used when a hand is not tracked.
4. Action bindings that make the launch/menu path usable from the immersive scene (GUI click, GUI
   right-click, GUI shift, menu/Escape, inventory) plus basic in-world actions (attack, use, teleport,
   contextual interact).

Explicitly **out of scope for W1** (tracked as M4-W2+): free-move virtual stick / snap-turn locomotion,
jump/sneak/hotbar/scroll gestures, the on-screen VR keyboard, seated-mode GUI pointer parity, hand
rendering polish, haptics, PSVR2 (P1/DEFERRED). Device evidence for real hands is **NOT RUN** until an
operator session; simulator/host evidence covers the plumbing.

## 1. Status semantics (read before claiming anything)

- **Host PASS** (JVM gesture/pose unit tests, C bridge tests, cross-language fixture) proves logic and
  the byte contract, **not** hands.
- **Simulator PASS** (fake provider + synthetic input in the visionOS simulator) proves the real
  compositor->bridge publication path and wire format, **not** ARKit hand capture on device.
- **Device synthetic PASS** (real app, vrmc-input-sim.flag) proves the real device stack down to the
  game's action handling without hands; it is still **not hands evidence**.
- **Hands PASS** requires an operator wearing the headset using real hands (ST-S5-hands). It is NOT
  claimed by this workstream. VERIFY.md AC-4 stays NOT RUN unless that session is recorded.

## 2. Architecture / data flow

~~~
 ARKit HandTrackingProvider (compositor thread, same ARKit session as WorldTracking)
   |  27 joints + wrist transform, anchor-predicted time, device space
   v
 VRMCCompositor.mm  --build vrmc_input_state-->  vrmc_shared_publish_input()   [bridge dylib]
   |                                                    | (mutex-protected snapshot)
   |                                                    v
   |                                          vrmc_poll_input()  <-- JNI nativePollInput(ByteBuffer)
   |                                                    |
   |                                          VrmcBridge.pollInput(ByteBuffer)        [provider, JVM]
   |                                                    v
   |                                          VisionInput: parse -> gestures -> per-action states
   |                                                    v
   |                                          VisionVR.processInputs(): VRInputAction.pressBinding()
   |                                                    v
   +-- compositor still presents eye textures --  Vivecraft: MCVR.processBindings()/GuiHandler tick
                                                   -> key bindings / GUI cursor / teleport / attack
~~~

The window path is untouched: window input keeps working whenever a window is interactive. The input
channel is additive and independent of presentation.

## 3. ABI v3 contract (bridge/abi/vrmc_abi.h + vrmc_native_shared.h)

**ABI version bumps 2 -> 3** (new struct layout crossing the Java boundary). Both bridge dylib and
provider jar ship together in the app; an old provider with a new bridge (or vice versa) fails closed at
vrmc_init.

caps_json sent by the provider: {"abi":3,"eyes":2,"hands":2,"input":1}. The bridge rejects any other
"abi" major. New capability token: input.

### 3.1 vrmc_hand_state — one hand, one frame (device space, meters)

| offset | type | field | meaning |
|---:|---|---|---|
| 0 | uint32 | tracked | 1 = wrist/joints valid this frame; 0 = not tracked |
| 4 | uint32 | chirality | NORMALIZED 0 = left, 1 = right. NOT the raw ARKit enum (ar_hand_chirality_right = 0, left = 1); the publisher maps it. Consumers index hands[] by slot, not by this field. |
| 8 | uint64 | timestamp_ns | anchor-predicted timestamp the hand was queried at |
| 16 | vrmc_quat | wrist_orientation | device-space orientation (q x,y,z,w) |
| 32 | vrmc_vec3 | wrist_position | device-space position of ARKit joint 0 |
| 44 | vrmc_vec3[27] | joints | ARKit joint index order (0..26), device space |
| **368** | | | **sizeof**, 8-byte aligned; no implicit padding |

ARKit joint indices used by consumers: 0 wrist, 4 thumb tip, 9 index tip, 11 middle knuckle (palm
length), 14 middle tip, 19 ring tip, 24 little tip, 5 index metacarpal, 20 little metacarpal.
The full 27-joint array is published so M4-W2+ (visible hands, climbing, hotbar) does not need another
ABI bump.

### 3.2 vrmc_input_state — one published input snapshot

| offset | type | field | meaning |
|---:|---|---|---|
| 0 | uint32 | frame_index | compositor frame counter |
| 4 | uint32 | valid_mask | bit0 = hands[0] left tracked, bit1 = hands[1] right tracked |
| 8 | uint64 | timestamp_ns | predicted anchor time of this snapshot |
| 16 | vrmc_hand_state[2] | hands | [0] = LEFT, [1] = RIGHT (explicit, independent of chirality) |
| **752** | | | **sizeof**, 8-byte aligned |

Chirality in hands[] must still be set correctly; consumers must index by hand slot, not chirality.
The space is the **same device/anchor space as vrmc_tracking_state.head** (ARKit origin, y-up,
-Z forward, meters). No additional transform is applied between head and hands.

### 3.3 Functions

- vrmc_poll_input(void *out, size_t out_len) (existing v3 signature): requires
  out_len >= sizeof(vrmc_input_state); copies the latest snapshot. Before the compositor ever
  published (e.g. immersive not opened), returns 0 with a zeroed snapshot (valid_mask = 0, all hands
  untracked) — that is "safe, no hands", not an error. Errors only for uninitialized bridge / null
  out / short out_len.
- New native-shared entry points (not part of the Java ABI version, additive):
  - int32_t vrmc_shared_publish_input(const vrmc_input_state *state) — compositor thread only.
  - int32_t vrmc_shared_acquire_input(vrmc_input_state *out) — JVM/other threads.
  - uint64_t vrmc_shared_input_sequence(void) — starts at 1, increments per successful publish;
    consumers use it only for change/staleness detection.
- JNI: Java_dev_vrmc_provider_bridge_VrmcBridge_nativePollInput(JNIEnv*, jclass, jobject directBuffer)
  (validates capacity >= 752, calls vrmc_poll_input).

### 3.4 Java-side constants (must match the tables above; enforced by tests)

~~~
ABI_VERSION                = 3
INPUT_BYTES                = 752      INPUT_OFF_FRAME_INDEX = 0   INPUT_OFF_VALID_MASK = 4
                                      INPUT_OFF_TIMESTAMP   = 8   INPUT_OFF_HANDS      = 16
HAND_STATE_BYTES           = 368      HAND_STRIDE = 368
HAND_OFF_TRACKED=0  HAND_OFF_CHIRALITY=4  HAND_OFF_TIMESTAMP=8
HAND_OFF_WRIST_QUAT=16  HAND_OFF_WRIST_POS=32  HAND_OFF_JOINTS=44  JOINT_STRIDE=12
JOINT_COUNT                = 27
~~~

## 4. Native compositor (runtime/native-shell/Sources/VRMCCompositor.mm)

1. **Session**: create a ar_hand_tracking_provider_t in the same ar_session_t as world tracking
   (data providers array = {world, hand}); log ar_hand_tracking_provider_is_supported() once.
   If unsupported, keep the session world-only and rely on synthetic input (vrmc-input-sim.flag) or
   fall back gracefully. Do not block/crash on missing hand tracking.
2. **Authorization (required)**: ARKit does NOT prompt from ar_session_run(); call
   ar_session_request_authorization(session, ar_authorization_type_hand_tracking, handler) once at
   session start (after ar_session_create, around/after ar_session_run), log the resulting
   ar_authorization_status (allowed / denied / not_determined) exactly once, and on denied keep
   presenting, publish untracked hands, and log one clear line (never crash, never pretend hands work).
   The handler runs on an arbitrary queue: only set an atomic flag and log, never touch render state.
   The Info.plist NSHandsTrackingUsageDescription required for the prompt is already embedded.
   When synthetic input (vrmc-input-sim.flag) is enabled, skip the authorization request/wait entirely
   (no real hands are needed), so the synthetic device run can never block on a permission prompt;
   if no answer arrives for a real-hands session, log an explicit "allow it, then relaunch" line.
3. **Query per frame** (after the device anchor query, before presenting): use
   cp_frame_timing_get_trackable_anchor_time(timing) converted by cp_time_to_cf_time_interval and
   ar_hand_tracking_provider_query_anchors_at_timestamp with two preallocated ar_hand_anchor_t. For each
   hand: ar_hand_anchor_is_tracked, then ar_hand_anchor_get_origin_from_anchor_transform (anchor origin
   transform = device space) and, per joint index 0..26, ar_hand_skeleton_get_joint_named +
   ar_skeleton_joint_get_anchor_from_joint_transform; final joint transform =
   anchorTransform * anchorFromJoint; publish positions (column 3) and the wrist orientation
   (simd_quaternion(wristTransform)).
4. **Publish**: fill vrmc_input_state, set frame_index/valid_mask/timestamp_ns, and call the
   dlsym-resolved vrmc_shared_publish_input once per frame. Missing symbol = old bridge: log once, keep
   running.
5. **Release on exit**: before ar_session_stop, publish a zeroed snapshot (valid_mask = 0) so the
   provider sees tracking loss and releases every held action (no stuck input when the space closes).
6. **Synthetic input** (Documents/vrmc-input-sim.flag, diagnostic only, SIMULATOR/device A/B): ignore
   real hands and publish a scripted cycle so the full chain can be exercised without hands. Content
   selects the script: pinch-right | pinch-left | fist-left | both | cycle (default cycle). Generated
   hands are plausible 27-joint layouts (wrist in front of the head, thumb/index tips separated by
   0.005 m while "pinched" and 0.07 m while open, fist curls tips toward the wrist). Every synthetic log
   line must start with INPUT-SIM and say SYNTHETIC (never real).
7. **Logging** (rate-limited, decisive): hand-support/authorization line; per ~60 frames
   hands L=1 R=0 wristL=(x,y,z) wristR=... seq=N; first publish and every 300th; any publish error;
   release-on-exit. Never log raw joint arrays every frame.

## 5. Provider (provider/src/main/java/dev/vrmc/provider/**)

### 5.1 Parsing

VrmcBridge (provider/.../bridge/VrmcBridge.java): ABI_VERSION=3, caps {"abi":3,"eyes":2,"hands":2,"input":1},
new constants + nativePollInput(ByteBuffer). VisionVR preallocates ONE direct buffer of INPUT_BYTES;
polls it every frame (no per-frame allocation).

### 5.2 Poses (VisionHandPose, JOML-only, unit-testable)

For each tracked hand, controllerPose[c] (MCVR index: RIGHT=0, LEFT=1):

- translation = wrist_position;
- rotation basis built from joints so that R * (0,0,-1) == aim (MathUtils.BACK is (0,0,-1) in
  getAimVector): aim = normalize(joint9 - joint0); side = normalize(joint20 - joint5);
  up = normalize(cross(side, aim)); z = -aim; x = cross(up, z); matrix columns (x, up, z).
- controllerTracking[c] = hand.tracked.
- **Gaze fallback** when a hand is not tracked: controller pose = hmd pose translated to a shoulder
  offset (RIGHT: hmd + (-0.2, -0.2, -0.05), LEFT: hmd + (+0.2, -0.2, -0.05), meters) with the same
  orientation as the head, so the GUI pointer keeps a sane ray and body-yaw estimation never sees two
  coincident hands. Logged once per acquisition/loss episode.
- controllerTracking[c] stays false for the gaze fallback when no hand is tracked (honest signal); the
  GUI cursor only moves while a hand is actually tracked, which is also when a pinch can happen.

### 5.3 Gestures (VisionInput, no Minecraft/Vivecraft imports; host-testable)

Tunable constants (defaults; overridable via game-dir vrmc-input-tune.properties and/or -D system
properties, read once):

| gesture | rule |
|---|---|
| pinch L/R | d = abs(joint4 - joint9) (metres); press if d < pinchOn (0.030); release if d > pinchOff (0.045); hysteresis |
| fist L/R | r = avg(abs(joint9,14,19,24 - joint0)) / abs(joint11 - joint0); press if r < fistOn (1.25), release if r > fistOff (1.55) |
| fist tap L/R | fist continuously held >= holdMs (400 ms) -> one 2-frame press pulse (fires once per hold, re-armed on fist release) |
| both-fist tap | both fists held >= holdMs -> one key.inventory pulse (fires once per both-fist gesture). CHORD PRIORITY: while both hands' fist gesture is pressed, the per-hand fist-tap pulses are suppressed, so a both-fists gesture cannot also click/escape on the same frames; single-hand fist taps still work when the other hand is open |

Safety invariants (G4 minimum): hand not tracked -> all of that hand's sources released the same frame;
input stale (>250 ms since last publish or sequence frozen) -> everything released and a warning logged;
each source is *armed* only after 100 ms of continuous release after acquisition, so a relaxed/occluded
hand can never present as a stuck press; teleport/GUI-click state is a boolean edge, never a latch.

### 5.4 Binding table (W1)

Sources are per-hand digital states; origin convention 1=LEFT, 2=RIGHT (same as macstream's
TouchPlusInput; this is what getOrigins/getOriginControllerType expose to Vivecraft).

| action (KeyMapping name) | hand | source | action set |
|---|---|---|---|
| key.attack | RIGHT | pinch (hold) | ingame |
| key.use | RIGHT | fist tap | ingame |
| vivecraft.key.teleport | LEFT | pinch (hold) | ingame |
| vivecraft.key.vrInteract | LEFT+RIGHT | pinch (hold) | contextual |
| vivecraft.key.climbeyGrab | LEFT+RIGHT | pinch (hold) | contextual |
| vivecraft.key.guiLeftClick | RIGHT | pinch (hold) | gui |
| vivecraft.key.guiRightClick | RIGHT | fist tap | gui |
| vivecraft.key.guiShift | LEFT | pinch (hold) | gui |
| vivecraft.key.ingameMenuButton | LEFT | fist tap | global |
| key.inventory | — | both-fist tap | global |

Action-set activation mirrors MCOpenVR updateActiveActionSets (same shape as macstream
TouchPlusInput.isSetActive): INGAME active when no screen (or ingameBindingsInGui), CONTEXTUAL when no
screen, GUI while a screen is open, KEYBOARD while the keyboard/radial overlay shows, everything else
always. Tap actions emit a 2-frame press so KeyMapping.consumeClick() sees a click even at <=90 Hz.

### 5.5 Dispatch + Vivecraft action plumbing

VisionVR.processInputs() mirrors MCOpenVR's per-action loop (adapted from macstream RemoteVR; LGPL-3.0,
upstream commit ec5a851c..., see ADR-0009): for every VRInputAction, write DigitalData/AnalogData from
VisionInput, then pressBinding()/unpressBinding() using
isActive()/isButtonChanged()/isButtonPressed()/isEnabled(). getOrigins(action) returns the bound
origins; getOriginName returns "left hand"/"right hand"; findActiveBindingControllerType resolves
through the origin.

**Vivecraft is unmodified**: VRInputAction.isEnabled() hard-codes MCOpenVR.get() == null -> false, which
would disable every action for a non-OpenVR backend. A new provider Mixin (VRInputActionMixin, listed in
vrmc.mixins.json) replaces that path with a generic backend path only when MCVR.get() instanceof
VisionVR (the proven macstream fix: MCOpenVR-null branch does the same priority/origin checks through the
active MCVR backend). The MCOpenVR path, when MCOpenVR is the active backend, is untouched.

### 5.6 Frame order (VisionVR.poll)

getTracking -> parse input + update controller poses (tracked hand pose / gaze fallback) ->
pollDisplayViews -> updateAim -> processInputs -> hmdSampling -> markPolled.
processInputs must run after updateAim (poses are current) and before the game's tick-time
processBindings, exactly like MCOpenVR.

## 6. Failure modes / invariants

| failure | required behavior |
|---|---|
| bridge ABI mismatch | vrmc_init fails; provider aborts VR init with a visible status; never silent fallback |
| hand tracking unsupported/denied | compositor logs it, publishes untracked hands; provider releases everything; GUI still renders; window path untouched |
| hand loses tracking mid-press | same-frame release; log once per episode; never a stuck attack/teleport |
| compositor input publication stops (space ends/crashes) | provider stale-input timer (250 ms) releases all and logs |
| malformed/short input buffer | JNI rejects; provider logs once and treats as untracked |
| pinch/fist jitter | hysteresis + arming; a press requires a released state for 100 ms after acquisition |
| seated mode | W1 logs a clear warning ("gesture input needs standing mode"); it does not silently pretend to work; seated parity is M4-W2 |
| old bridge without input symbols | compositor logs once and continues presenting; provider treats as untracked (fail safe, no crash) |

## 7. Verification plan (what we can prove without a headset)

1. **C bridge tests** (bridge/tests/run_tests.sh): bridge_input_test — layout static asserts
   (sizes/offsets above), publish/acquire round-trip, sequence monotonicity, acquire-before-publish safe
   zero state, short-buffer rejection, uninitialized rejection, concurrent publish/read torn-state
   detection (500k iterations) + TSan build.
2. **Cross-language contract fixture**: bridge/tests/make_input_fixture.c writes two files from the
   real C structs: argv[1] = ONE raw 752-byte vrmc_input_state contract snapshot (frame_index=8,
   valid_mask=3, both tracked; RIGHT hand pinch+fist, LEFT hand relaxed open) and argv[1].frames = an
   optional 10-record (7520-byte) documented timeline sidecar with per-record timestamp_ns at a
   documented 150 ms spacing (open both / right pinch on / held / off / left fist held f4-f7 with a
   450 ms hold -> tap must fire at f7 / still held f8 / open f9). The provider VisionInputFixtureTest
   parses the snapshot for
   layout/layering and replays the timeline through the gesture engine to assert the exact press/release
   timeline. This catches C-vs-Java offset/order drift.
3. **Provider JVM unit tests** (no game instance): gesture hysteresis, arming after tracking loss,
   fist-tap single-fire, both-fist, action-set gating, binding-table coverage, stale-input release, pose
   basis math (R*(0,0,-1)=aim, orthonormal, left/right, gaze fallback).
4. **Simulator harness** (runtime/probes/m3c-provider-sim): new input scenario — the real compositor
   runs with the fake bridge/provider in the visionOS simulator, synthetic input enabled; the fake
   provider records every published snapshot and check.py --require-input asserts publication rate, hand
   tracking bits, pinch/fist cycle values, and release frames.
5. **One-command self-check**: scripts/m4_input_selfcheck.sh runs 1-4 (+ builds) and the existing
   scripts/m3c_selfcheck.sh gains the M4 step, so a regression in presentation or input fails one
   command.
6. **Device (operator, separate)**: real app + new provider jar; Step 0 permission prompt for hand
   tracking; vrmc-input-sim.flag synthetic run first (proves the device stack without hands), then a
   real-hands session. Evidence must label synthetic vs hands; ST-S5-hands stays NOT RUN until the
   operator session. Procedure: docs/mvp/M4_DEVICE_RUN.md.

## 8. Workstreams and write scopes (Agent Teams)

| workstream | files (advisory write scope) | depends on |
|---|---|---|
| Lead | bridge/abi/*.h, docs/analysis/immersive-input.md, docs/mvp/M4_*.md, scripts/m4_input_selfcheck.sh, VERIFY.md/AGENT.md | — |
| bridge-input | bridge/src/**, bridge/tests/**, scripts/build_bridge.sh, bridge/README.md | ABI headers (Lead) |
| native-input | runtime/native-shell/Sources/VRMCCompositor.mm, runtime/probes/m3c-provider-sim/** | ABI headers (Lead), bridge symbols (stub) |
| provider-input | provider/src/**, provider/tests/**, provider/README.md | ABI headers (Lead) |
| verifier | docs/analysis/m4-input-verification.md (code read-only; defects reported, not patched) | all three |

Cross-team interface changes go through the Lead. No teammate installs/runs anything on the physical
headset; device work is staged for a later operator session.

## 9. Open items (M4-W2+)

- G3 locomotion: virtual stick / snap turn / teleport refinements; gaze-aim mode (aimDevice=HMD for GUI
  too, via the VRData.getAim() route) and comfort defaults.
- Jump/sneak/hotbar/scroll/radial and the on-screen VR keyboard; seated-mode pointer parity.
- Visible hands / held item from the 27-joint data; two-hand bow; climbing.
- Provider GPU-sync device run, M3-W5/W6 pacing/soak (unchanged, separate tracks).
