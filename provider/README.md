# Provider (Vivecraft companion mod)

**Status:** M4-W1 in progress 2026-11-01. Provider side **host PASS**: bridge ABI v3 handshake, gesture engine / hand-pose / layout JVM tests, and the C→Java cross-language fixture replay (see "M4-W1 immersive input" below). Earlier host harness PASS (EV-0060): bridge handshake, `VisionVR.init()` success, stereo eye targets and per-frame `vrmc_submit_eyes` on desktop Fabric (GL texture ids). Real-hands and device input are **NOT RUN** (AC-4/ST-S5-hands unchanged); the window/UIKit input path is untouched. VisionVR/VisionRenderer structure is adapted from macstream's proven RemoteVR backend (`docs/mvp/MACSTREAM_REFERENCE.md`).

LGPL-3.0 Fabric mod that integrates VRMC with Vivecraft without forking it: it Mixins the provider
selection in `VRState.initializeVR` and implements `VisionVR extends MCVR` plus a
`VRRenderer` that submits eye targets to the native bridge.

Planned contents:

- `src/main/java/.../VisionVR.java` — provider: init/poll/processInputs, poses, IPD, play area;
  M4-W1 input poll + action dispatch (`[VRMC-M4]` logs).
- `src/main/java/.../VisionRenderer.java` — eye targets, projection, submission hook.
- `src/main/java/.../VisionInput.java` — M4-W1 pure-Java gesture engine: ABI v3 snapshot parse,
  pinch/fist hysteresis + released-state arming, fist-tap/both-fist pulses, stale/tracking-loss
  release, action-set gating and the W1 binding table (origins 1 = LEFT, 2 = RIGHT).
- `src/main/java/.../VisionHandPose.java` — M4-W1 JOML-only hand→controller pose math
  (`R*(0,0,-1)=aim`) and the shoulder/gaze fallback for untracked hands.
- `src/main/java/.../mixin/VRStateMixin.java` — substitutes `VisionVR` for `MCOpenVR`.
- `src/main/java/.../mixin/VRInputActionMixin.java` — M4-W1 generic-backend `isEnabled` fix.
- `src/main/resources/` — mixin config, `provider.json` mapping profile.
- `LICENSE` — LGPL-3.0 (present).

Rules:

- Separate, replaceable artifact; source published (ADR-0004, ADR-0006).
- Version-locked to Vivecraft 26.2-1.3.15; fail closed on mismatch.
- S3 must evidence the injection point in the decompiled jar and across 26.2.x before M2 hardens;
  the fork fallback is decided at M0 exit.
- No SteamVR/OpenVR dependency; no OpenXR assumption.
## Flag-gated GPU eye-frame sync (off by default)

The provider can hand the compositor a GPU timeline sync pair for the zero-copy eye handoff: one
exportable timeline `VkSemaphore` on the game's MoltenVK device, its `MTLSharedEvent` exported through
`VK_EXT_metal_objects`, signalled once per frame through MC's own `VulkanCommandEncoder` submission and
published to the bridge with `VrmcBridge.submitEyesSynced` (bridge native-shared API; Java ABI v2
unchanged). Any failure logs one warning and falls back to the existing unsynchronized `submitEyes` path.

* Enable: `vrmc-gpu-sync.flag` in the Minecraft game directory, or `-Dvrmc.gpuSync=1`.
  `-Dvrmc.gpuSync=0` force-disables; `-Dvrmc.gpuSync.debug=true` traces the reflection path.
* `VK_EXT_metal_objects` must be enabled at device creation: the first flagged launch requests it in
  `VRSettings.requiredVulkanDeviceExtensions` (same mechanism as `OpenVRStereoRenderer`), saves settings
  and falls back, so ONE GAME RESTART is needed before the sync path can activate.
* Host tests: `provider/tests/run_tests.sh` (flags, fallback, reflection plumbing, real MoltenVK
  semaphore + `MTLSharedEvent` export).
* Full design, device procedure and expected log lines: `docs/analysis/provider-gpu-sync.md`.
* Status: host PASS; device path NOT RUN. The compositor only needs to wait when the acquired frame has
  `sync.valid != 0` (see `docs/analysis/bridge-sync.md`).

## M4-W1 immersive input (ARKit hands → Vivecraft actions)

Design/interface contract: [docs/analysis/immersive-input.md](../docs/analysis/immersive-input.md).
This is the provider side (W1-C): the compositor publishes ARKit 27-joint hand tracking over bridge
**ABI v3** (`caps {"abi":3,"eyes":2,"hands":2,"input":1}`); the provider polls it once per frame into
ONE preallocated direct buffer (`VrmcBridge.pollInput`) and turns gestures into Vivecraft actions.
Vivecraft stays unmodified: `VRInputActionMixin` takes over `VRInputAction.isEnabled()` only while
`MCVR.get() instanceof VisionVR` (generic backend/origin/priority path; the MCOpenVR path is
untouched).

Frame order (design §5.6, mirrors MCOpenVR): `getTracking -> pollInput (gestures + controller poses)
-> pollDisplayViews -> updateAim -> processInputs -> hmdSampling`.

Bindings (design §5.4; origin `1 = left hand`, `2 = right hand`):

| action | hand | source | set |
|---|---|---|---|
| `key.attack` | RIGHT | pinch (hold) | ingame |
| `key.use` | RIGHT | fist tap | ingame |
| `vivecraft.key.teleport` | LEFT | pinch (hold) | ingame |
| `vivecraft.key.vrInteract` | LEFT+RIGHT | pinch (hold) | contextual |
| `vivecraft.key.climbeyGrab` | LEFT+RIGHT | pinch (hold) | contextual |
| `vivecraft.key.guiLeftClick` | RIGHT | pinch (hold) | gui |
| `vivecraft.key.guiRightClick` | RIGHT | fist tap | gui |
| `vivecraft.key.guiShift` | LEFT | pinch (hold) | gui |
| `vivecraft.key.ingameMenuButton` | LEFT | fist tap | global |
| `key.inventory` | both fists | both-fist tap | global |

Safety (G4, the safety-critical failure is stuck input): a hand that stops tracking releases all of
its sources on the same frame; input older than 250 ms (compositor stopped/frozen) releases
everything and logs; every source needs 100 ms of continuous release after acquisition before it may
present a press; fist-tap/both-fist are 2-frame press edges, never latches; the both-fist chord
suppresses the per-hand fist taps while both fists are engaged (a both-fists hold fires only
key.inventory, never a simultaneous click + Escape + inventory); seated mode logs a clear
warning ("gesture input needs standing mode") and does not dispatch gestures (seated parity is
M4-W2).

Tuning, read once at init: game-dir `vrmc-input-tune.properties` keys `pinch.on` (0.030 m),
`pinch.off` (0.045), `fist.on` (1.25), `fist.off` (1.55), `fist.hold.ms` (400), `arm.ms` (100),
`stale.ms` (250), `tap.frames` (2); individual `-Dvrmc.input.<key>=<value>` system properties
override the file. The file is logged at init (`[VRMC-M4] input tuning: ...`).

Host tests: `provider/tests/run_tests.sh` step `m4-input-tests` — `VisionInputLayoutTest` (ABI v3
sizes/offsets vs the documented literal table + documented-offset round-trip),
`VisionInputTest` (hysteresis/arming/taps/stale/action-set gating/binding table/tuning/both-fist
chord priority),
`VisionHandPoseTest` (basis/aim/orthonormality/gaze fallback), and the optional cross-language
`VisionInputFixtureTest`: set `VRMC_INPUT_FIXTURE` to the 752-byte C image (and optionally
`VRMC_INPUT_FIXTURE_FRAMES` to its 10-record / 7520-byte timeline) generated by
`bridge/tests/make_input_fixture.c`; unset = explicit SKIP, set-but-missing = FAIL.

### Action-dispatch evidence (F12, device runbook Step 1)

Every real dispatched edge of a W1-bound action is logged so the device synthetic run can prove the
chain down to the game action (not just the gesture engine):

    [VRMC-M4] action <keyMappingName> press origin=<left|right|none>
    [VRMC-M4] action <keyMappingName> release origin=<left|right|none>

`<keyMappingName>` is the exact Vivecraft/Minecraft KeyMapping name (`key.attack`, `key.use`,
`key.inventory`, `vivecraft.key.teleport`, `vivecraft.key.vrInteract`, `vivecraft.key.climbeyGrab`,
`vivecraft.key.guiLeftClick`, `vivecraft.key.guiRightClick`, `vivecraft.key.guiShift`,
`vivecraft.key.ingameMenuButton`). `origin` is resolved from the action's last dispatched origin via
`VisionVR.originControllerType` (1 = left, 2 = right; unknown = none). The line is emitted only when
the provider actually calls `VRInputAction.pressBinding()` / the release paths
(`unpressBinding*`, tracking-loss / stale / seated / destroy immediate releases), not for raw
gestures. W1-bound actions only; binding rows are unique (action, hand) pairs, dedupe state is
preallocated per row, and the hot dispatch path allocates nothing unless a line is printed. Rate
limit: the first 60 transitions of each kind (press / release counted separately), then every 300th;
rate-limited transitions still update the dedupe state, so a printed line is always a real edge (for
the device synthetic run all lines fall in the first-60 burst).

Grep patterns for a device log (`latestlog.txt`):

    grep -E '^\[VRMC-M4\] action .+ (press|release) origin=(left|right|none)$' latestlog.txt
    grep -E '^\[VRMC-M4\] action (key\.(attack|use|inventory)|vivecraft\.key\.(teleport|guiLeftClick|guiRightClick|guiShift|ingameMenuButton|vrInteract|climbeyGrab)) (press|release) origin=' latestlog.txt
    # per scripted cycle (compositor 'cycle': right pinch -> left fist -> both fists), GUI-screen state:
    grep -E '^\[VRMC-M4\] action (key\.attack|vivecraft\.key\.guiLeftClick) press origin=right' latestlog.txt

Expected per synthetic cycle (compositor `cycle` script: 0.35 s open / 0.90 s right pinch / 0.35 s open /
0.90 s left fist / 0.35 s open / 0.90 s both fists / 0.35 s open), when a GUI screen is open
(main-menu case; `key.attack` replaces `guiLeftClick` while no screen is open, and a single-hand
right fist tap would log `key.use` instead of `guiRightClick`):

    right pinch phase:   action vivecraft.key.guiLeftClick press origin=right
                         action vivecraft.key.guiLeftClick release origin=right
    left fist phase:     action vivecraft.key.ingameMenuButton press origin=left   (400 ms hold -> tap)
                         action vivecraft.key.ingameMenuButton release origin=left
    both-fists phase:    action key.inventory press origin=right                    (both-fist chord)
                         action key.inventory release origin=right
                         (the chord suppresses the per-hand fist taps: no key.use/guiRightClick and no
                          second ingameMenuButton in this phase)

No-screen variant: the right pinch logs `action key.attack press origin=right`; `ingameMenuButton`
(global) and `key.inventory` (global) appear in both variants. `key.use` (ingame) / `guiRightClick`
(gui) appear only for a SINGLE-hand right fist tap - never during a both-fists chord (the synthetic
`cycle` holds the chord for its last phase). Use the compositor's single-gesture scripts to exercise
them: `fist-left` produces one `ingameMenuButton` pulse and no inventory pulse because the right hand
stays open. `vrInteract`/`climbeyGrab` only appear when Vivecraft gameplay enables those actions
(e.g. climbing claws); they are `setEnabled(false)` by default, so a default synthetic run shows no
lines for them.

### Pose diagnostic (device runbook triage)

Rate-limited wrist/aim evidence for the real-hands device run (the runbook triage row for a cursor
missing while hands are tracked greps this line):

    [VRMC-M4] pose: right wrist=(x.xxx,y.xxx,z.xxx) aim=(x.xxx,y.xxx,z.xxx) left wrist=(x.xxx,y.xxx,z.xxx) aim=(x.xxx,y.xxx,z.xxx)

Emitted on the first tracked pose of each tracking episode and then every ~300 tracked frames while
at least one hand is tracked; untracked hands are skipped (no gaze-fallback numbers are printed). aim
is R*(0,0,-1) of the posed controller, i.e. the direction MCVR.getAimVector(0) gives the GUI cursor -
if the cursor is missing or mis-pointing while hands are tracked, this line shows the wrist/aim values
to tune VisionHandPose or the hand coordinate convention. Allocation happens only on the ~300-frame
log path, never per frame.

    grep -E '^\[VRMC-M4\] pose:' latestlog.txt

Status honesty: host/JVM logic + byte-contract PASS only; **real-hands and device runs are NOT RUN**
until an operator session (see `docs/mvp/M4_DEVICE_RUN.md`). Simulator synthetic input is plumbing
evidence, never hands evidence.