# m3c-provider-sim — provider-sampling simulator harness

Objective, headset-free verification that the real VRMC CompositorServices renderer samples a provider
eye texture correctly, and (M4-W1) that the real compositor publishes synthetic hand-input snapshots
through the bridge input channel. It embeds the **real** `VRMCShell.framework` in a minimal
visionOS-simulator host app and replaces the bridge with a **fake provider dylib** that publishes two
real `MTLTexture`s with a known pattern and implements the M4-W1 input surface — no JVM, Minecraft,
JIT, or device involved.

What it exercises:

- bridge dylib resolution + `vrmc_shared_acquire_eyes` (and the legacy `vrmc_shared_eye_textures`) path
- flat fullscreen sampling shader + drawable viewport mapping and orientation
- the optional GPU-timeline wait path (`sync.valid=1` → `encodeWaitForEvent` before sampling)
- shell auto-open path (`Documents/vrmc-open-on-launch.flag`) and first-frame-gated window parking
- the drawn-drawable readback dump used as device evidence (`Documents/vrmc-drawable-L.raw`)
- **M4-W1 input**: the real compositor's ARKit-input publication path with synthetic hands
  (`Documents/vrmc-input-sim.flag`): `vrmc_shared_publish_input` per frame, the 752-byte
  `vrmc_input_state` wire layout, the zeroed release snapshot before `ar_session_stop`, and the
  gesture geometry the provider thresholds depend on

Known pattern (fake left eye; right eye has a different palette for future stereo assertions):

```
black 100-px top strip
+----------------+----------------+
| red            | green          |
+----------------+----------------+
| blue           | white          |
+----------------+----------------+
```

Expected drawable readback through the compositor flat path (64x64 dump top → bottom): green flat-mode
badge, black strip, red/green, blue/white — asserted by `check.py`.

## Run

```bash
runtime/probes/m3c-provider-sim/run.sh              # all presentation scenarios (default)
runtime/probes/m3c-provider-sim/run.sh input        # M4-W1 synthetic-hand input scenario
runtime/probes/m3c-provider-sim/run.sh input flat   # named scenarios, in order
FULL=1 runtime/probes/m3c-provider-sim/run.sh       # rebuild framework + fake dylib first
```

M8 render-feedback scenario: `render` (`SHARPEN=off|auto|0.05..1.0` env writes
`Documents/vrmc-sharpening.txt` before launch to A/B the compositor's foveated sharpening knob).

Scenarios: `flat` (provider texture through the flat sampled path), `sync` (same with a real
`MTLSharedEvent` → compositor `encodeWaitForEvent`), `hidepark` (alpha+isHidden parking A/B),
`nopark` (parking disabled), `pattern` (eye-distinct stereo/alignment test pattern: proof border, warm
left-eye tint, white centre fusion cross, red eye marker), `reentry` (background via Settings →
foreground VRMC → the immersive space reopens and presents again), `input` (M4-W1 synthetic hand
input publication + release).

Requires the visionOS simulator (default `F025E133-019D-4811-944F-F3C8226E14CB`; override with
`SIM=<udid>`). Outputs per scenario: `/tmp/vrmc-provider-sim/case-<name>/` (override `OUT=`) with
screenshot + compositor/shell logs + drawable raw + meta. Exit code 0 = PASS.

## M4-W1 input scenario (`run.sh input`)

Flags written into the app's Documents/: `vrmc-open-on-launch.flag`, `vrmc-reproj-off.flag`,
`vrmc-input-sim.flag` (content `cycle`). `INPUT_SYNC=1` additionally writes
`vrmc-fake-provider-sync.flag` so the same run also exercises the GPU-timeline wait path (A/B only,
not input-related). The real compositor:

1. logs `INPUT-SIM SYNTHETIC input enabled script=cycle ...` (synthetic hands are fabricated; ARKit
   hand data is never used and no authorization is required for this path),
2. publishes one `vrmc_input_state` per frame through the fake bridge
   (`vrmc_shared_publish_input`), logging `INPUT-SIM SYNTHETIC input publish seq=... valid_mask=3 ...`
   and rate-limited `input hands L=1 R=1 wristL=... wristR=...` lines,
3. walks the scripted cycle both-open → right pinch → release → left fist → release → both fists →
   release (one lap is logged as `input script=cycle lap complete`),
4. when the harness backgrounds the app (the shell calls `VRMCCompositor_RequestStop` from
   `didEnterBackground`), publishes a zeroed release snapshot before `ar_session_stop` and logs
   `INPUT-SIM SYNTHETIC input release valid_mask=0 ...`.

The fake provider records every published snapshot to
`Documents/vrmc-input-capture.txt` (copied to `case-input/input-capture.txt`), one CSV line per
publish:

```
seq, frame_index, valid_mask, timestamp_ns, right_pinch_m, left_pinch_m, right_fist_ratio, left_fist_ratio
```

(`#`-prefixed header lines are comments; pinch/fist metrics use the provider's documented formulas.) `check.py --require-input` asserts: ≥30 snapshots; `valid_mask` framing (both hands
tracked = 3 for the scripted frames, final release frame = 0); monotonic sequence/frame counters and
non-zero timestamps; right-pinch crossings below `pinchOn` (0.030) and above `pinchOff` (0.045);
left-fist ratio crossings below `fistOn` (1.25) and above `fistOff` (1.55); the compositor's
`INPUT-SIM`/publish/release lines; and **no** compositor input errors.

**Evidence class:** the input scenario is simulator **plumbing** evidence for
compositor → bridge publication and the wire format. The visionOS simulator has no ARKit hand data, so
it is **never hands evidence** and does not prove gesture quality or real-hand tracking.

## Provenance

The depth-clear black-immersive bug (EV-0093) cannot be reproduced in the simulator — the simulator
displays correctly with the wrong depth clear — so this harness is **not** evidence for the presentation
path. It is a plumbing/shader regression guard for the sampled path and the GPU-sync wait wiring.
The M4-W1 input scenario is likewise a plumbing guard for the input publication/release path, not
hands evidence (see `docs/analysis/immersive-input.md` §1/§7).
