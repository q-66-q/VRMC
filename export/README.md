# VRMC — native immersive integration (M3-W3/W4) — **current issue**

**Date:** 2026-11-01
**Status:** PARTIAL / blocked on the three operator-confirmed issues below. The native app now launches the game, opens an
immersive CompositorServices space by itself, hides the game window's content, samples the provider's
eye `MTLTexture`s (`eyes=1`) and feeds real ARKit tracking into the provider. Remaining issues are
listed below (evidence EV-0083/EV-0084/EV-0085).


## Issue summary (operator-confirmed, 2026-11-01)

1. **The window cannot be hidden.** Parking the window (alpha = 0 / isHidden) hides its content, but the
   visionOS window bottom bar/ornament still shows in immersive mode.
2. **The game cannot present again after running in the background.** The game keeps running after
   backgrounding, but the immersive space cannot be re-entered/presented again.
3. **The perspective is exotropia.** The stereo eye images diverge outward (exotropia); swapping the
   eye/view mapping did not fix it. Presentation is still a flat fullscreen sample without per-eye
   projection/FOV parity.

## What already works

| Item | Evidence |
|---|---|
| Native visionOS launcher builds/runs (UIKit idiom fix), launcher UI + Play | EV-0079 |
| SwiftUI app-lifecycle shell hosts `LauncherSplitViewController` and opens `ImmersiveSpace`/`CompositorLayer` | EV-0081 |
| Game-start auto-open (15 s settle delay), game survives, no Vulkan device-loss | EV-0083 |
| Compositor samples provider eye textures (`eyes=1`, e.g. 0x722b0b2300/0x722b0b2080) | EV-0083/84/85 |
| ARKit poses reach the provider (`tracking frame … head=(-0.02,1.17,0.02)`) | EV-0083/84/85 |
| Game window content parked (`windows=3 alpha=0.0`) | EV-0084/85 |
| Background compositor exit is now clean (`stop/invalidation after timing wait; exiting without submission`, `posted VRMCImmersiveEnded`) — no new crash | EV-0085 |

## Current issues

### 1. Window cannot be hidden (window chrome remains despite parking)
`alpha = 0` and `isHidden = true` hide the window content, but the visionOS **window bottom bar / ornament
still shows** (it is scene-level chrome, not window content). Need to close/deactivate the window scene
while immersive is active, or avoid having a game window scene in immersive mode.

### 2. Game cannot present again after running in the background
After the game starts, `UIKit_launchMinecraftSurfaceVC` replaces the window's root view controller with
`SurfaceViewController`. That **destroys the SwiftUI `WindowGroup` view and its NotificationCenter
subscriptions** (`willResignActive` / `didEnterBackground` / `VRMCImmersiveEnded` / `scenePhase`). Shell
log final run stops after `window parked`; no lifecycle notifications are handled afterward. The game
keeps running, but the shell cannot reopen the immersive space.

**Fix direction:** keep the SwiftUI root/observers alive — present `SurfaceViewController` modally over
the SwiftUI hosting controller instead of replacing the window root, or move lifecycle handling to an
app-level observer (AppDelegate/global object) that does not depend on the WindowGroup view.

### 3. Perspective is exotropia (stereo misalignment)
The compositor samples each 1024×1024 eye texture and draws it as a flat fullscreen image. It has no
per-eye projection/FOV parity with Minecraft; swapping view 0/view 1 did not fix the exotropia.
**Fix direction:** pass CompositorServices per-eye tangents/FOV to the provider so MC renders a matching
projection (or reproject in the compositor), then verify eye order/orientation with a stereo test.

## Reproduction

1. Install the native build (see patches/build-native-vrmc.sh; scripts/build_launcher.sh PLATFORM=11)
2. StikDebug → Enable JIT → VRMC
3. Play `fabric-loader-0.20.1-26.2`; wait ~15 s for auto-open
4. Observed: window content disappears but bottom bar remains; eye images exotropic; backgrounding ends
   the immersive and it cannot be re-entered.

## Evidence / logs

- `logs/vrmc-shell.log` — final run: auto-open, window parked, no lifecycle lines after root replacement
- `logs/vrmc-compositor.log` — `eyes=1`, anchor=1, tracking, clean exit on background
- `logs/latestlog.txt` — provider tracking frames, MC/Vivecraft
- `logs/AngelAuraAmethyst-background-crash-113422.ips` — historical background crash at
  `cp_frame_end_submission` (fixed by the final build's clean-exit guard; latest final run has no new crash)
- `logs/summary.log` — detailed evidence narrative
- `evidence/EV-0079/81/82/83/84/85.md` — milestone entries

## Next implementation order

1. Keep SwiftUI observers alive (modal game surface or app-level observer) → background/return works
2. Window scene chrome handling while immersive is active
3. Per-eye projection/FOV parity + stereo eye-order test
4. `MTLSharedEvent`/Vk timeline sync, then pacing/acceptance
