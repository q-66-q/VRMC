# m3c-provider-sim — provider-sampling simulator harness

Objective, headset-free verification that the real VRMC CompositorServices renderer samples a provider
eye texture correctly. It embeds the **real** `VRMCShell.framework` in a minimal visionOS-simulator host
app and replaces the bridge with a **fake provider dylib** that publishes two real `MTLTexture`s with a
known pattern through the native-shared API — no JVM, Minecraft, JIT, or device involved.

What it exercises:

- bridge dylib resolution + `vrmc_shared_acquire_eyes` (and the legacy `vrmc_shared_eye_textures`) path
- flat fullscreen sampling shader + drawable viewport mapping and orientation
- the optional GPU-timeline wait path (`sync.valid=1` → `encodeWaitForEvent` before sampling)
- shell auto-open path (`Documents/vrmc-open-on-launch.flag`) and first-frame-gated window parking
- the drawn-drawable readback dump used as device evidence (`Documents/vrmc-drawable-L.raw`)

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
runtime/probes/m3c-provider-sim/run.sh        # reuse cached framework/dylib build
FULL=1 runtime/probes/m3c-provider-sim/run.sh # rebuild framework + fake dylib
```

Scenarios: `flat` (provider texture through the flat sampled path), `sync` (same with a real
`MTLSharedEvent` → compositor `encodeWaitForEvent`), `hidepark` (alpha+isHidden parking A/B),
`nopark` (parking disabled), `pattern` (eye-distinct stereo/alignment test pattern: proof border, warm
left-eye tint, white centre fusion cross, red eye marker), `reentry` (background via Settings →
foreground VRMC → the immersive space reopens and presents again).

Requires the visionOS simulator (default `F025E133-019D-4811-944F-F3C8226E14CB`; override with
`SIM=<udid>`). Outputs per scenario: `/tmp/vrmc-provider-sim/case-flat/` and `case-sync/`
(screenshot + compositor/shell logs + drawable raw + meta). Exit code 0 = both scenarios PASS.

## Provenance

The depth-clear black-immersive bug (EV-0093) cannot be reproduced in the simulator — the simulator
displays correctly with the wrong depth clear — so this harness is **not** evidence for the presentation
path. It is a plumbing/shader regression guard for the sampled path and the GPU-sync wait wiring.