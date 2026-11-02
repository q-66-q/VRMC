# M3c plan — black immersive on device: presentation-stage isolation (2026-11-01)

Status: **IN PROGRESS / device-blocked**. Evidence: EV-0091 (fresh post-JNI-fix runs), EV-0092 (M3c
diagnostics + simulator control). No gate is claimed. M3-W3/W4 remains PARTIAL.

## 0. Operator directive (2026-11-01, recorded)

- The game currently runs in a visionOS **Window scene**, not an immersive space; head rotation only
  moves the window. True VR requires the game output to be presented by **CompositorServices in an
  ImmersiveSpace**.
- Do **not** jump to the Info.plist preferred-scene-role route (Option 1) yet. Stage Option 2 first:
  keep a minimal startup window, add a **manual "Enter VR" trigger**, verify it on device, then make the
  automatic post-JIT open the default; keep the window/error surface as fallback; record an EV per stage.
- Confirm the game render loop is CompositorServices-driven. In VRMC the renderer already works this
  way: Minecraft renders stereo eye targets (Vulkan/MoltenVK), the provider exports `MTLTexture`
  handles, and the native CompositorServices renderer samples them into the drawable (the window's
  `CAMetalLayer` is only the 2D launcher/game surface and is parked when immersive is active).

Implemented for this directive: manual `Enter VR` overlay button in the window (with failure message),
automatic open retained after `VRMCGameStarted` (JIT proven by the game starting), audible first-frame
canary, alpha-only parking after the first presented frame + periodic re-park, willResignActive grace,
and objective scene-activation/layer-state logging. Info.plist unchanged.

## 1. What is proven (device)

- Provider/display-view path is correct: display views published/applied (Lpos/Rpos exact), per-eye
  textures bright (luma 103-154), no command-buffer failures, provider applied to both eyes
  (EV-0091, EV-0092).
- The CompositorServices compositor writes a **bright image into the presented built_in drawable**:
  - one drawable, target built_in, 2 views, 2 textures, depth present, no rasterization-rate maps;
  - `encNil=0`, `nilColor=0`, first command buffer completed, frames 960-12000+;
  - 64x64 strided drawn-drawable readback: mean luma 130.6 (pattern) / 64-75 (game),
    nonBlack ~4096/4096, raw dumps `vrmc-drawable-L/R.raw` + `.meta`.
- **Yet the headset shows a black immersive.** In the JIT game run the operator confirmed full
  immersion was active (no passthrough; pitch-black room) with the game visible only in a floating 2D
  window and no immersive content. In the no-JIT selftest the operator also reported black.
- **Same framework displays correctly in the simulator**: a minimal visionOS-simulator host app that
  dlopens the real `VRMCShell.framework` and calls `vrmc_shell_start` shows the full-screen test
  pattern (`evidence/EV-0092/sim-real-shell-pattern.png`). So the shell/compositor logic is not
  inherently broken; the failure is device-specific.

## 2. Hypotheses still open (ranked)

1. **Two-view dedicated layout presentation**: device hands out `views=2, textures=2` per drawable;
   the simulator control only has `views=1`. Our per-view encode/present path may be incomplete for
   the stereo drawable even though both textures contain content. (Test: M3A probe = known-good
   stereo display; layered-layout A/B.)
2. **Hybrid Amethyst app environment**: the device app is a UIKit `main()` that starts the SwiftUI
   App; the simulator control is a pure-SwiftUI host. The M3A probe (pure SwiftUI) is the control.
3. **Device anchor / reprojection**: the anchor is set every frame from ARKit; a bad assignment could
   keep content off-screen. (Test: `vrmc-no-anchor.flag` A/B.)
4. **Window/scene state**: full immersion is active but the window remains visible (alpha-only parking
   was not visually effective in the game run — the game window stayed visible). Periodic re-parking is
   now implemented; the no-park vs re-park A/B is staged.
5. Lower: frame-timing misses / compositor drop; GPU sync between MoltenVK and Metal (provider sync
   deferred; unsynchronized readback is still a correctness issue but cannot black a forced pattern).

## 3. Staged device bisect matrix (apps staged, operator required)

| # | App bundle | What it isolates | Flags |
|---|---|---|---|
| **T1** | `/tmp/VRMC-probe-signed.app` (known-good M3A probe, EV-0074, re-signed as dev.vrmc.vrmc) | Can ANY CompositorServices app still display on D1? Pure-SwiftUI window + button "Open immersive space" + per-eye pattern. | none |
| **T2** | `/tmp/VRMC-native-v3.app` (current full app + manual Enter VR + scene/layer logging + periodic parking) | Manual Option-2 path end to end; objective scene activation + compositor layer state; test pattern (no eyes) or game image | `vrmc-clear-diagnostics.flag` |
| **T3** | `/tmp/VRMC-native-v4-minwin.app` (minimal SwiftUI window instead of the Amethyst UIKit host) | Isolates the hybrid Amethyst window/host from the CompositorServices path | `vrmc-immersive-selftest.flag` |
| **T4** | `/tmp/VRMC-native-v5-layered.app` (same shell/compositor, `layout = .layered`) | Two separate 2D textures (dedicated) vs one 2D-array texture (layered) | `vrmc-immersive-selftest.flag` |
| **T5** | `/tmp/VRMC-native-v6-noanchor.app` | Device anchor/reprojection path | `vrmc-post` + `vrmc-no-anchor.flag` |
| **T6** | `/tmp/VRMC-native-v2-legacy.app` (EV-0081-era compositor + current shell) | Whether the M3c compositor rewrite caused the regression vs the shell/environment | `vrmc-immersive-selftest.flag` (legacy compositor draws red/green when no provider eyes) |

Notes:
- Flags are read at shell/compositor start; the app must be relaunched after pushing them.
- `vrmc-clear-diagnostics.flag` deletes stale diagnostic flags (test-pattern, reproj, no-sampling,
  legacy-root-swap, immersive-on-launch, selftest, clear-probe, autolaunch) and itself.
- Devicectl cannot delete individual container files, hence the cleanup flag.
- Operator procedure: unlock/wear D1, Launch VRMC (devicectl or Home), for T1 tap "Open immersive
  space"; for T2 tap "Enter VR"; for T3-T6 the selftest opens automatically ~3-4 s after launch and
  leaves the space open. Report: pattern / game image / black / window state. Pull
  `Documents/{vrmc-shell.log,vrmc-compositor.log,latestlog.txt,vrmc-drawable-*.raw,.meta}`.

## 4. Reading the decisive evidence

- `[shell] STATE ... scenes=[<role>:<state>]`: proves whether the immersive scene
  (`CPSceneSessionRoleImmersiveSpaceApplication`) is `fgActive` while the compositor presents.
- `[vrmc-comp] frame ... layerState=N`: `cp_layer_renderer_get_state` (2 = running).
- `[vrmc-comp] drawable proof ...`: mean/max/nonBlack of the drawn drawable (what we presented).
- `[shell] VRMCCompositorRunning` + audible beep: first presented frame.
- T1 vs T2/T3: if the probe displays but our app does not, the difference is in the app/shell
  environment; T3 vs T2 isolates the Amethyst host; T4/T5 isolate layout/anchor; T6 isolates the
  compositor rewrite.

## 5. Follow-ups once a displaying configuration wins

1. Re-run the game with JIT (StikDebug -> Enable JIT -> VRMC -> Play) and confirm gameplay fills the FOV.
2. Make the automatic entry the default (already implemented; manual button stays as recovery).
3. Provider-side GPU sync (bridge additive API ready; provider wiring deferred): export timeline
   `MTLSharedEvent` from the provider and have the compositor `encodeWaitForEvent` before sampling.
4. Eye-target PNG capture (`instances/default/vrmc-capture.flag`) for off-device content inspection.
5. Window chrome: verify `persistentSystemOverlays(.hidden)` survives with the modal game surface once
   the window no longer has to be forced visible for debugging.
6. Record EV-0093+ per stage with the operator report; update VERIFY §7/§8 and AGENT §7/§13.
