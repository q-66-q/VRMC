# M3c diagnostic flags (device + simulator)

Flags are empty marker files in the app data container `Documents/` (or, for provider flags, in the
Minecraft game directory `Documents/instances/default/`). Most are read once when the shell/compositor
thread starts, so **relaunch the app after pushing/removing one**. `devicectl` can copy and list files
but not delete them; push `vrmc-clear-diagnostics.flag` to have the shell delete the diagnostic set at
startup (it removes itself last and never touches `vrmc-capture.flag`/`vrmc-drawable-dump.flag`).

## Shell flags (Documents/)

| Flag | Effect |
|---|---|
| `vrmc-clear-diagnostics.flag` | At startup, delete the diagnostic flags below + stale `autolaunch.flag`; logs one line per deletion, then deletes itself. |
| `vrmc-immersive-selftest.flag` | Open the immersive space without the game/JIT ~3 s after launch (retries 1/s for 15 s), leave windows visible, force the procedural pattern + proof overlay + drawable dumps. Diagnostic only. |
| `vrmc-open-on-launch.flag` | Open the immersive space ~3 s after launch WITHOUT forcing the test pattern (used by the simulator provider-sampling harness; with a real game it is a manual-style open). |
| `vrmc-no-parking.flag` | Never park the 2D windows in immersive mode (A/B; windows stay visible). |
| `vrmc-hide-windows.flag` | Use `window.isHidden = true` (plus alpha 0) for parking instead of alpha-only. A/B for "window still visible on device". |
| `vrmc-hide-chrome-always.flag` | Keep `persistentSystemOverlays(.hidden)` active even outside the immersive space (chrome A/B). |
| `autolaunch.flag` (stale) | Legacy launcher auto-start; removed by `vrmc-clear-diagnostics.flag`. |

## Compositor flags (Documents/)

| Flag | Effect |
|---|---|
| `vrmc-reproj-off.flag` | Force flat fullscreen sampling (the path used once display views are live). |
| `vrmc-reproj-on.flag` | Force the reprojection path. |
| `vrmc-reproj-debug.flag` | Colour-code reprojection failure branches (magenta = outside provider frustum, blue = behind camera, orange = non-finite). |
| `vrmc-test-pattern.flag` / `vrmc-no-sampling.flag` | Force the procedural test pattern / disable provider-texture sampling. |
| `vrmc-present-proof.flag` | Draw only the 8 px checker border around each eye (presentation alive without hiding the centre). |
| `vrmc-clear-probe.flag` | Clear-only probe: solid magenta left eye / cyan right eye, no draws. |
| `vrmc-drawable-dump.flag` | Force raw 64x64 drawn-drawable dumps every ~300 frames (useful during a game run; pull `vrmc-drawable-L/R.raw` + `.meta`). |
| `vrmc-present-wait.flag` | Wait for command-buffer completion before `end_submission` (EV-0074 probe parity). |
| `vrmc-depth-zero.flag` | **Regression A/B only**: restore the old 0.0 drawable depth clear. 0.0 makes the immersive layer black on visionOS 27.2 (EV-0093). Regression test `scripts/tests/DepthClearRegressionTest.sh`. |
| `vrmc-legacy-single-drawable.flag` | Use the deprecated singular `cp_frame_query_drawable` instead of the array API (A/B). |
| `vrmc-no-anchor.flag` | Skip `cp_drawable_set_device_anchor` (anchor/reprojection A/B). |

## Provider flags (game directory `Documents/instances/default/`)

| Flag | Effect |
|---|---|
| `vrmc-capture.flag` | Enable off-by-default eye-target PNG capture: `<gameDir>/vrmc-capture/vrmc_eye_L_f<N>.png`, `vrmc_eye_R_f<N>.png`, `vrmc_world_f<N>.png` (defaults: every 300 frames, max 3). |

## Expected log lines for a healthy manual/immersive run

- shell: `OPEN-ON-LAUNCH`/`SELFTEST` (if flagged) → `openImmersiveSpace result=opened` →
  `VRMCCompositorRunning` → `window parked after first presented frame` (alpha-only) →
  `STATE ... scenes=[CPSceneSessionRoleImmersiveSpaceApplication:fgActive,...]`.
- compositor: `diagnostics: ... depthZero=0`; `drawable topology: count=1 mainTarget=0(built_in)`;
  `first presented frame: ... -> posting VRMCCompositorRunning`; periodic `frame N ... layerState=2 ...
  encNil=0 nilColor=0`; `drawable proof` mean/max luma non-black; `shading mode=flat (auto)` once the
  provider display views are live.
- game run: provider `[VRMC-DIAG]` lines (pass/level/menuWorld/displayViews/eye positions) and
  `display views gen=... applied=...` with exact Lpos/Rpos.

## One-command log triage

```bash
DEVICE=<udid> scripts/m3c_pull_and_check.sh      # pulls + prints the decisive lines; exit 2 on hard regression
scripts/m3c_pull_and_check.sh --from <dir>       # analyse an existing pull
```
