# Immersive integration (M3-W2/W3/W4 + M3b) — source-level notes

Components (all in-repo):
- `runtime/native-shell/Sources/Shell.swift` — SwiftUI App shell:
  - WindowGroup hosts `LauncherSplitViewController` via `NSClassFromString`
  - ImmersiveSpace("vr") + `CompositorLayer`
  - Listens for `VRMCGameStarted` (posted by `ios_uikit_bridge.m`), opens immersive after a 15 s settle delay
  - Parks windows and listens for background notifications → `VRMCCompositor_RequestStop()`
  - **M3b**: epoch-guarded open/dismiss with foreground app+window-scene gating, confirmed dismiss + settle,
    stale-generation filtering, bounded auto-retry (2) when a layer dies right after opening; scene chrome
    driven by `persistentSystemOverlays(.hidden)` (plus `vrmc-hide-chrome-always.flag` for A/B)
- `runtime/native-shell/Sources/VRMCCompositor.mm` — CompositorServices thread:
  - ARKit world tracking at presentation time; `cp_drawable_set_device_anchor`
  - resolves `vrmc_shared_eye_textures`/`vrmc_shared_set_tracking` from `Frameworks/libvrmc_bridge.dylib`
  - per-eye **reprojection** of the provider eye textures (CompositorServices projection/view transforms +
    provider FOV tangents); flat sampling control; procedural test pattern
  - **M3b diagnostics/no-black**: CPU ray→UV center/corner/9×9 coverage logs, provider eye-texture 32×32
    centre readback (RGB+alpha+luma, auto test-pattern if black twice), colour-coded debug branches,
    alpha forced to 1, `cp_view_texture_map` texture index/viewport, command-buffer health logging; flags
    `vrmc-reproj-off/on/debug`, `vrmc-test-pattern`, `vrmc-no-sampling`; mode badge strip
    (red=reprojection, green=flat, blue=test pattern)
  - safe exit checks; posts `VRMCImmersiveEnded` (with `generation`) on exit
- `patches/vrmc-m3w2-shell-hook.patch` — main.m dlopen of VRMCShell.framework; game-start notification in
  `UIKit_launchMinecraftSurfaceVC`
- `patches/vrmc-m3w3-modal-game-surface.patch` (**M3b**) — present the game surface **modally over the live
  SwiftUI hosting controller** instead of replacing `window.rootViewController`; keeps the WindowGroup scene
  alive so the window-chrome preference survives the game launch. Amethyst root-VC assumptions replaced by
  `vrmcCurrentSurfaceViewController()` (input bridge, gyro/controller, external display, sdl3 view lookup,
  `isRunning`, resolution sync). Escape hatch: `Documents/vrmc-legacy-root-swap.flag`.
- `scripts/build_shell.sh` — xcodegen/xcodebuild visionOS framework
- `scripts/build_launcher.sh` — PLATFORM=11 native payload + Info.plist adjustments + framework embedding
  (applies all `patches/*.patch` in order)
- `scripts/build_provider.sh` / `scripts/build_bridge.sh` / `scripts/stage_native_app.sh` /
  `scripts/push_provider_jar.sh` — **M3b** reproducible provider jar, bridge dylib, signed app staging and
  device mod push

Root cause of EV-0086 issue 1/2: game launch replaced `window.rootViewController` with
`SurfaceViewController`, destroying the SwiftUI WindowGroup view (chrome preference + lifecycle subscriptions).
M3b fixes the cause with the modal presentation; the app-level `ShellCoordinator` remains a second line of
defence for the immersive lifecycle. EV-0087 documents the validation; the device run is EV-0088.
