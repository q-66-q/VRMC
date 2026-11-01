# Immersive integration (M3-W2/W3/W4) — source-level notes

Components (all in-repo):
- `runtime/native-shell/Sources/Shell.swift` — SwiftUI App shell:
  - WindowGroup hosts `LauncherSplitViewController` via `NSClassFromString`
  - ImmersiveSpace("vr") + `CompositorLayer`
  - Listens for `VRMCGameStarted` (posted by `ios_uikit_bridge.m`), opens immersive after a 15 s settle delay
  - Parks windows (alpha/skew) and listens for background notifications → `VRMCCompositor_RequestStop()`
- `runtime/native-shell/Sources/VRMCCompositor.mm` — CompositorServices thread:
  - ARKit world tracking at presentation time; `cp_drawable_set_device_anchor`
  - resolves `vrmc_shared_eye_textures`/`vrmc_shared_set_tracking` from `Frameworks/libvrmc_bridge.dylib`
  - samples provider eye textures into the drawable (flat fullscreen), clears red/green fallback
  - safe exit checks; posts `VRMCImmersiveEnded` on exit
- `patches/vrmc-m3w2-shell-hook.patch` — main.m dlopen of VRMCShell.framework; game-start notification in
  `UIKit_launchMinecraftSurfaceVC`
- `scripts/build_shell.sh` — xcodegen/xcodebuild visionOS framework
- `scripts/build_launcher.sh` — PLATFORM=11 native payload + Info.plist adjustments + framework embedding

Known root cause of issue 2: game launch replaces `window.rootViewController` with
`SurfaceViewController`, destroying the SwiftUI WindowGroup view that owns the lifecycle observers.
