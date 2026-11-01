# VRMC — native visionOS launcher UI blocker (current issue)

**Date:** 2026-11-01
**Status:** **blocked on the native launcher UI only** — the native app runs the whole Minecraft stack
(JVM + JIT + MC 26.2 + Fabric + Vivecraft + VRMC provider + Vulkan/MoltenVK + eye-texture export), but
its **UIKit launcher content does not render** (blank window) and the root-VC workaround crashes.

> This dossier **replaces** the old 2026-10-31 `export/` contents (Amethyst release IPA / LWJGL 3.3.3
> blocker), which is resolved: VRMC is now built from an Amethyst 1.2.0 source tree with LWJGL 3.4.1,
> and MC 26.2 boots on device and in the native app.

---

## 1. Why native at all

visionOS **compatibility apps cannot open immersive spaces or use CompositorServices**. M3 therefore
requires a native visionOS app (`PLATFORM=11`). ADR-0010 chose the single-process native app (launcher +
JVM/MC + provider + immersive renderer).

## 2. What already works (evidence in this repo)

| Item | Evidence |
|---|---|
| Native visionOS payload builds (relabelled VISIONOS; arm64) | EV-0071 |
| Native app opens a CompositorServices immersive space and presents per-eye stereo (red/green test pattern) | EV-0074 |
| Native app hosts JVM/JIT/MC 26.2/Fabric 0.20.1/Vivecraft/provider/Vulkan/MoltenVK and device eye export | **EV-0077** |
| StikDebug Enable JIT works for the native app (`isJITEnabled=1`, always-attached JIT) | EV-0077 |
| Native window/scene/root VC are created and sized correctly (1280×720) | EV-0076 |
| Root-VC swap workaround fires and then crashes (launcher VCs assume split view) | **EV-0078** |

**Auto-launch bypass**: putting `Documents/autolaunch.flag` in the container makes the native app launch
the selected profile ~10 s after start; with this, EV-0077 proved the full native MC stack. The
auto-launch hook was a local refbuild patch (not yet in `patches/` of the repo).

## 3. Current blocker (reproduce)

1. Install the native build (see `patches/build-native-vrmc.sh`).
2. StikDebug → Enable JIT → VRMC.
3. The app launches; a window title/toolbar is visible, **content is blank**. Logs show:
   - `willConnect bounds={{0,0},{1280,720}}`, `rootVC=LauncherSplitViewController`, window visible,
     view 1280×720 with 2 subviews (EV-0076).
4. With `VRMCNativeBuild=true` the launcher swaps the root to
   `LauncherNavigationController(root=LauncherProfilesViewController)`: the branch runs
   (`rootVC=LauncherNavigationController`), then the app crashes:
   `NSException` in `-[LauncherProfilesViewController viewWillAppear:]` →

   ```
   @[sidebarViewController drawAccountButton, self.createButtonItem]
   ```

   `sidebarViewController` is defined as
   `((LauncherMenuViewController *)self.splitViewController.viewControllers[0].viewControllers[0])`;
   with a plain navigation root, `self.splitViewController` is nil → nil element → exception.
   (EV-0078, crash report `logs/AngelAuraAmethyst-2026-11-01-085003.ips`.)

## 4. Attempts so far

| Attempt | Result |
|---|---|
| Native app with `LauncherSplitViewController` root | Window valid, content blank (EV-0076) |
| Plain `LauncherNavigationController(root=LauncherProfilesViewController)` root | Crash: split-view-dependent sidebar macro (EV-0078) |
| Auto-launch bypass (no UI interaction) | **Works** — full MC stack boots in native app (EV-0077) |

## 5. Next options (M3-W1)

1. **Native-specific shell (preferred):** a small SwiftUI/UIKit shell that (a) shows a minimal launcher
   (instance/profile + Play) and (b) calls the existing launch path (`LauncherNavigationController`
   /`launchMinecraft:`), without instantiating the split-view-dependent view controllers.
2. **Split-view-compatible shim:** keep `LauncherSplitViewController` but render it in a way visionOS
   accepts (host it in a SwiftUI window, force layout/transaction, or replace the split view with a
   plain container that sets each child's `splitViewController` expectations).
3. Interim: keep the auto-launch flag for development; do not ship.

Either way, the *game hosting* problem is solved; only UI presentation remains.

## 6. Folder map

- `logs/` — native gate-3 boot log, native UI logs, crash report, summary.
- `patches/build-native-vrmc.sh` — build/brand/sign/install recipe for the native app.
- `patches/native-ui-workaround.md` — source-level details of the attempted root-VC swap, diagnostics,
  and auto-launch hook.
- `evidence/EV-0077.md`, `evidence/EV-0078.md` — evidence entries copied for offline readers.
