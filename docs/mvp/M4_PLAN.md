# M4 plan — hands-only input (M4-W1: immersive-scene control)

Status: **M4-W1 IMPLEMENTED — host + simulator PASS (EV-0095); device synthetic and real-hands
verification NOT RUN.** This plan is scoped to the reported defect: once the game is in the immersive
space the user cannot control it there; only the 2D window accepts input. Full M4 (gesture set,
locomotion, comfort, S5-hands acceptance) remains the milestone; W1 is the first end-to-end slice.
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

## 7. W2+ backlog (unchanged milestone content)

- Locomotion: free-move virtual stick / snap turn, teleport comfort defaults, gaze-aim mode
  (`aimDevice=HMD` extended to the GUI cursor via `VRData.getAim()`), seated-mode pointer parity.
- Action coverage: jump/sneak/hotbar/scroll/radial menu, on-screen VR keyboard, chat.
- Visible hands/held item from the 27-joint data, two-hand bow, climbing, haptics.
- S5-hands acceptance checklist (AC-4), latency/comfort measurements, M4 exit evidence.
- Device: provider GPU-sync run, M3-W5/W6 90 Hz/soak (separate tracks).
