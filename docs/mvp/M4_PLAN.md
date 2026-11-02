# M4 plan — hands-only input (M4-W1: immersive-scene control)

Status: **M4-W1 PASSED ON DEVICE; W2 smooth hands + shutdown hardening host+simulator PASS (EV-0097); gaze tracking-areas host build/tests PASS but runtime/device NOT RUN (EV-0098); W3 middle-pinch locomotion/core actions host PASS (EV-0099); W4 partial swipe hotbar/scroll + radial host PASS (EV-0100), swipe action table for hotbar/chat/keyboard/swap/drop host PASS (EV-0106); device NOT RUN.** **M4-W1 PASSED ON DEVICE — host + simulator PASS (EV-0095) and on-device acceptance PASS
(EV-0096): synthetic plumbing + real-hands operator confirmation (“It ran very well!”); two follow-ups
recorded: a reproducible shutdown-only JVM SIGSEGV to triage, and the operator-requested W2 features
below.** This plan is scoped to the reported defect: once the game is in the immersive space the user
cannot control it there; only the 2D window accepts input. Full M4 (gesture set, locomotion, comfort,
S5-hands acceptance) remains the milestone; W1 is the first end-to-end slice.
Device procedure: [M4_DEVICE_RUN.md](M4_DEVICE_RUN.md) (Step 1 synthetic = SYNTHETIC evidence only;
Step 2 real hands = the S5-hands check).

Design + byte contract: [docs/analysis/immersive-input.md](../analysis/immersive-input.md).
Device procedure: [M4_DEVICE_RUN.md](M4_DEVICE_RUN.md).

## 1. Why W1 exists (root cause of the reported defect)

M3 (EV-0094) closed presentation: the game renders stereo-correctly in the immersive space. Input was
never wired: VRMC's provider (`VisionVR.processInputs()`) is an empty M4 stub, `vrmc_poll_input`
returns zeros, and the compositor never starts ARKit hand tracking. While a window is visible the
Amethyst game surface still receives UIKit pointer events, so the game is controllable there; after the
compositor parks the windows (alpha 0, non-interactive) there is no input path at all. The immersive
scene is a custom CompositorServices layer, not a UIKit view, so system window gestures do not reach
the game either.

W1 adds the missing channel: ARKit 27-joint hand tracking -> bridge ABI v3 input snapshot -> provider
gesture recognition -> Vivecraft `VRInputAction` data -> key bindings/GUI cursor. Vivecraft stays
unmodified; the one hard-coded OpenVR check that would disable all actions for a non-OpenVR backend is
replaced by a provider Mixin (the proven macstream approach).

## 2. W1 scope (deliverables)

| # | Deliverable | Acceptance (host/simulator) | Device |
|---|---|---|---|
| W1-A | ABI v3 input channel in the bridge (structs, `vrmc_poll_input`, native-shared publish/acquire, JNI) | layout static asserts; publish/acquire round-trip; TSan concurrency; old-buffer fail-closed | shared app build |
| W1-B | Compositor ARKit hand tracking + per-frame publication + release-on-exit | simulator synthetic-input scenario shows published snapshots with expected cycles; release frames on exit | real hands NOT RUN; synthetic runbook |
| W1-C | Provider gesture engine + action bindings + dispatch + `isEnabled` Mixin | JVM unit tests (hysteresis, arming, taps, stale/loss release, action-set gating, pose math); cross-language fixture; provider jar builds | actions NOT RUN on device |
| W1-D | Cross-language contract fixture + one-command self-check + docs | `scripts/m4_input_selfcheck.sh` PASS; `m3c_selfcheck.sh` includes it | procedure in M4_DEVICE_RUN.md |

W1 bindings (canonical Oculus-profile parity for the actions that exist without controller buttons):
right pinch = attack / GUI left click; right fist tap = use / GUI right click; left pinch = teleport /
GUI shift; left fist tap = menu (Escape); both fists = inventory. Locomotion beyond teleport, jump,
sneak, hotbar, scroll, radial, VR keyboard: **not W1**.

## 3. Non-goals / status honesty

- Real-hands behavior is **NOT RUN** until an operator session on D1 (ST-S5-hands stays NOT RUN).
- Simulator results are never stereo/optics/hands evidence (VERIFY §0.7); a visionOS simulator does
  not provide ARKit hand data. The simulator proves plumbing only.
- A device synthetic run (`vrmc-input-sim.flag`) is labelled SYNTHETIC and is not hands evidence.
- The window/UIKit input path is unchanged (no regression allowed there).
- PSVR2 is P1/DEFERRED; no controller code is added.

## 4. Verification matrix

| Check | Command | Evidence class |
|---|---|---|
| Bridge ABI/layout/concurrency | `bridge/tests/run_tests.sh` (new `bridge_input_test` + TSan) | host |
| C->Java byte contract | `bridge/tests/make_input_fixture.c` + provider `VisionInputFixtureTest` | host (cross-language) |
| Gestures/pose/action logic | `provider/tests/run_tests.sh` (new M4 steps) | host (JVM) |
| Compositor input publication | `runtime/probes/m3c-provider-sim/run.sh` (new `input` scenario) | simulator (plumbing only) |
| One command all of the above | `scripts/m4_input_selfcheck.sh` | host + simulator |
| Presentation no-regression | `scripts/m3c_selfcheck.sh` | host + simulator |
| Device synthetic | `docs/mvp/M4_DEVICE_RUN.md` Step 1 (`vrmc-input-sim.flag`) | device, SYNTHETIC, NOT RUN |
| Real hands | M4_DEVICE_RUN.md Step 2 | device, hands, NOT RUN |

## 5. Risks

| Risk | Mitigation |
|---|---|
| Hand tracking authorization denied / unsupported (simulator) | supported check + graceful untracked publication + synthetic mode; the window path stays; logged once |
| Stuck input (G4, the safety-critical failure) | same-frame release on loss; 250 ms stale-input release; released-state arming; tap pulses are edges, not latches; unit-tested |
| Coordinate/aim convention mismatch on device (hand ray not matching VRData direction) | joint-derived basis is unit-tested against `R*(0,0,-1)=aim`; `vrmc-input-tune.properties` tuning knobs; device A/B flag for gaze aim (W2) |
| `VRInputAction.isEnabled` Mixin fragile across Vivecraft patches | pinned Vivecraft 26.2-1.3.15; mixin only takes over when the active backend is `VisionVR`; the MCOpenVR path is untouched; provider build fails on compile drift |
| ARM64 alignment / JNI direct-buffer mistakes | C static asserts + Java layout asserts + cross-language fixture test |
| Seated mode silently broken | explicit warning log; seated parity is M4-W2; standing/room-scale is the MVP path |
| ABI v3 vs already-installed v2 app | app rebuild stages shell+bridge+provider together; a mismatched pair fails closed at init (visible error, not silent) |

## 6. Exit criteria for W1 (what can be claimed in this change)

1. Bridge + provider + shell build clean (device + host + simulator SDK).
2. All host tests above PASS, including TSan for the new input handoff.
3. The simulator `input` scenario PASSes (real compositor publishes synthetic hands; fake provider
   records the snapshot stream; release on exit).
4. `scripts/m4_input_selfcheck.sh` and `scripts/m3c_selfcheck.sh` PASS end-to-end.
5. No change to the window input path; no presentation regression in the m3c scenarios.
6. A staged, signed app bundle + provider jar and an operator runbook for the device session.

Status after this change: W1 host/simulator **PASS, recorded as EV-0095** (bridge suite incl. TSan,
cross-language C->Java fixture, provider gesture/pose/dispatch tests, simulator input scenario, and the
full `scripts/m3c_selfcheck.sh` including the M4 step); real-hands/device still **NOT RUN**
(AC-4/ST-S5-hands unchanged). The defect is fixed in code and evidenced at the host + simulator level;
the operator-confirmed in-headset fix is the next device session (`M4_DEVICE_RUN.md`).

## 6b. W2 — operator-requested follow-ups (2026-11-01 device session)

After the on-device acceptance run the operator requested, in this priority order:

1. **Gaze highlight + pinch selection** (chosen interaction: eyes highlight the target; pinch confirms — no
   click-free dwell). Implementation path (API spike + design in
   [docs/analysis/gaze-and-hand-input.md](../analysis/gaze-and-hand-input.md)): CompositorServices
   **tracking areas** (visionOS 26+) — render interactive region IDs into the drawable tracking-area
   textures, `addHoverEffect(.automatic)` gives true-gaze system highlight, and the SwiftUI
   cross-import `LayerRenderer.onSpatialEvent` + `SpatialEventCollection.Event.trackingAreaIdentifier`
   reports which region was activated. First iteration: tile the game GUI into tracking areas, map the
   activated tile to GUI pixel coordinates in the provider, and synthesize the GUI click (the same
   InputSimulator path GUI clicks already use). Keep the existing hand-ray/pinch path as fallback and
   behind a flag while the two are compared.
2. **Smooth, continuous hands**: real 27-joint tracking is already live end-to-end (EV-0096); add pose
   smoothing/filtering (One-Euro) and, if useful, visible hands/held item rendering from the joint data;
   tune fist thresholds (device run observed a right-fist engage at ratio 1.24 vs threshold 1.25 — too
   little margin) and the aim basis for stability.

Also to fix before M4 exit: the reproducible **shutdown-only JVM SIGSEGV** after `[Minecraft] Stopping!`
(`objc_retain` in a native thread; faulting register equals a provider eye `MTLTexture`); hypothesis is
the M3 eye-texture lifetime/teardown race — add a clean-shutdown step to the device acceptance.

## 6c. W2 progress (2026-11-01, EV-0097)

- **Smooth hands (host + simulator PASS; device pending):** `VisionPoseSmoother` One-Euro filter on
  controller translation + angle-adaptive slerp orientation, integrated in `VisionVR.updateControllerPoses`
  for tracked hands (fallback poses unsmoothed), reset on tracking loss, enabled by default. Tuning keys:
  `input.smooth`, `input.smooth.posMinCutoff`, `posBeta`, `derivativeCutoff`, `rotMinCutoff`, `rotBeta`
  in `vrmc-input-tune.properties` or `-Dvrmc.input.smooth.*`. Startup log
  `[VRMC-M4] hand smoothing: enabled=…`. Host test `VisionPoseSmootherTest` 11 checks PASS.
- **Shutdown SIGSEGV hardening (code done; quit-game device run pending):** provider
  `VisionVR.destroy()` clears shared eye-texture handles first (`nativeClearEyeTextures`); compositor
  CFRetains sampled eye textures and releases them in the command-buffer completion handler. Bridge
  stub clear/resubmit contract tested.
- **Gaze highlight + pinch selection (implemented offline, EV-0098):** bridge gaze mailbox, SwiftUI
  `onSpatialEvent` hook, compositor tracking-area grid + automatic hover mask, provider tile→GUI-plane
  mapping + pinch-confirm click. Opt-in via `Documents/vrmc-gaze.flag`. Host build/tests PASS; runtime
  mask pipeline and true-gaze behaviour are device-only and NOT RUN.

## 6d. W3 progress (2026-11-01, EV-0099)

- **Middle-pinch gesture family** (thumb tip ↔ middle tip, disjoint from the W1 thumb–index pinch):
  hysteresis + released-state arming, short-tap and double-tap edge detection, long holds never
  emit taps, tracking loss releases everything. `middle.enabled=false` keeps W1-only.
- **Bindings:** right middle tap → `key.jump`, right middle hold → `key.sneak` (INGAME set).
- **Locomotion:** `VisionLocomotion` maps the left wrist relative to the head to a virtual stick while
  the left middle pinch is held; `keyFreeMoveStrafe` analog (x strafe / y forward-back) with neutral
  band, radial deadzone and clamp; non-finite input always yields zero. Left middle tap → snap turn
  left, double-tap → right, via `keyRotateLeft/Right` analog pulses.
- **Tuning keys:** `middle.enabled/on/off/tapMs/doubleMs`, `move.originZ/forwardScale/strafeScale/
  deadzone/rotatePulseMs` in `vrmc-input-tune.properties` or `-Dvrmc.input.*`.
- **Evidence:** m4-middle 15 checks + m4-locomotion 7 checks PASS, provider suite ALL PASS; real-hands
  threshold/feel tuning and AC-4 checklist remain device-only (W5).

## 6e. W4 progress (2026-11-01, EV-0100)

- **Opt-in open-hand swipes** (`swipe.enabled=false` by default): tracked open hand (fist ratio above
  `swipe.openRatio`, no pinch/fist/middle press) moving faster than `swipe.speed` emits a 2-frame
  directional pulse at most once per `swipe.cooldownMs`; horizontal/vertical dominance.
- **Provider actions:** right-hand swipe left/right → hotbar previous/next (`changeHotbar`), up/down →
  `InputSimulator.scrollMouse`; only the pulse rising edge acts; seated/keyboard suppressed.
- **Radial menu:** right middle-pinch double-tap → `vivecraft.key.radialMenu`.
- **Tuning:** `swipe.enabled/speed/openRatio/cooldownMs` in `vrmc-input-tune.properties` or
  `-Dvrmc.input.*`.
- **Still open for W4:** hotbar 1–9 selection, chat/keyboard toggle, swap/drop gestures, bow/climb
  chord semantics, visible hands/held-item polish, full P0 checklist (device-only).

## 6f. W4 extension (2026-11-01, EV-0106)

- Opt-in swipe sources now bind: right horizontal → `vivecraft.key.hotbarNext/Prev`; left up/down →
  `vivecraft.key.toggleKeyboard` / `key.chat`; left horizontal → `key.swapOffhand` / `key.drop`;
  right vertical remains direct mouse-wheel scroll. Bindings only act while `swipe.enabled=true`
  (default OFF) and obey Vivecraft action sets.
- Binding table is 21 rows / 19 actions; swipe tests 9 checks PASS; full provider suite ALL PASS.
- Still open: direct hotbar 1–9 selection, bow/climb two-hand chord semantics, visible-hands polish,
  real-hands tuning (W5).

## 6g. W4 use-hold/bow (2026-11-01, EV-0109)

- In-game `key.use` is now bound to **right-fist hold** (`SRC_FIST_HOLD`) rather than the 2-frame fist
  tap: holding the fist holds use (bow draw), releasing releases it (fire). GUI right-click remains
  the fist-tap edge; attack/teleport/climb bindings are unchanged.
- Host use-hold test PASS; m4-input 161 checks; full provider suite ALL PASS.
- Device bow/use/climb feel and two-hand draw semantics beyond held-use remain NOT RUN.

## 6h. W4 climb-jump chord (2026-11-01, EV-0111)

- Both-hand middle single-tap chord emits a climb-jump pulse and suppresses the per-hand middle taps
  (so it cannot also fire right-hand jump or left-hand snap-turn); bound to
  `vivecraft.key.climbeyJump` (CONTEXTUAL, both origins).
- Binding table 22 rows / 20 actions; middle suite 21 checks PASS; full provider suite ALL PASS.
- Climb grab remains both-hand pinch hold (W1); device climbing/climb-jump feel NOT RUN.

## 6i. Fuzz/safety hardening (2026-11-01, EV-0115)

- Deterministic 20k-frame fuzz test mixes tracking loss, malformed hand masks, NaN/Inf joints, stale
  publisher gaps and environment flips; asserts release invariants after every frame.
- It found a real G4-style bug: both-hand tap/fist chord 2-frame pulses could survive one hand losing
  tracking. Fixed by clearing both-hand chord state immediately when either hand is untracked.
- 0 violations; full provider suite PASS. Updated provider jar pushed to D1.
- Real-hands no-stuck behavior and gesture feel remain W5 device work.

## 7. W2+ backlog (unchanged milestone content)

- Locomotion: free-move virtual stick / snap turn, teleport comfort defaults, gaze-aim mode
  (`aimDevice=HMD` extended to the GUI cursor via `VRData.getAim()`), seated-mode pointer parity.
- Action coverage: jump/sneak/hotbar/scroll/radial menu, on-screen VR keyboard, chat.
- Visible hands/held item from the 27-joint data, two-hand bow, climbing, haptics.
- S5-hands acceptance checklist (AC-4), latency/comfort measurements, M4 exit evidence.
- Device: provider GPU-sync run, M3-W5/W6 90 Hz/soak (separate tracks).
