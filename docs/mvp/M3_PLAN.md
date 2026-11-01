# M3 plan — Compositor stereo + head tracking (started 2026-11-01)

Status: **IN PROGRESS — M3a COMPLETE**: gate 1 **PASS (EV-0071)**; **gate 2 PASS (EV-0074)**; **gate 3 PASS (EV-0077)**: immersive space opens and the CompositorServices loop runs (2700+ frames, no crash), but stereo content is not presented (passthrough) and ARKit anchor/presentation-time wiring is missing. M2 CLOSED (EV-0070). M3 turns the provider's two exported `MTLTexture`s into an
**immersive CompositorServices stereo view with real head tracking**.

## 0. Architectural gate (M3a) — native visionOS app required

The current launcher is an **iOS-compatibility app** (built `PLATFORM=2`). Compatibility apps cannot
open visionOS immersive spaces or use CompositorServices. Therefore M3 requires a **native visionOS
(xros) app shell**: `PLATFORM=11`, `UISceneSessionRoleImmersiveSpaceApplication`, CompositorServices
`LayerRenderer`, ARKit tracking.

Options considered (ADR-0010):
- **(A, chosen) native visionOS app**: launcher 2D window + immersive space in the same app. Product
  path; reuses the M2 provider/bridge over the same process.
- (B, fallback) separate native companion app for the immersive layer, IPC/shared-texture bridge to
  the compat JVM/MC app. 4th app slot + IPC complexity; only if (A) fails.
- (C) immersive in compat app — **impossible** (platform limitation).

**M3a sub-gates:**
1. `PLATFORM=11` build succeeds and the native app launches on D1 (window UI).
2. A minimal immersive space opens with a CompositorServices layer renderer drawing a test pattern;
   ARKit head pose is logged.
3. The native app can host the JVM/MC + JIT + Vulkan path (Amethyst relabelled natives/JRE), because
   the provider and bridge live in the same process as MC. This is the highest risk; fallback (B).

## 1. Exit criteria

1. Native app opens an immersive space; both eyes present with correct per-eye content (test pattern,
   then MC render).
2. Per-eye projection matches the bridge FOV; no tearing over 10 minutes; presentation at 90 Hz
   target (or documented graceful fallback).
3. Real head tracking: ARKit predicted anchor → bridge → provider `hmdPose`; recenter works; latency
   recorded.
4. Provider eye `MTLTexture`s are sampled into the compositor drawables (zero-copy, documented sync).
5. 10-minute immersive run with no compositor watchdog kill.
6. Evidence: EV per gate; simulator never counts for optics/tracking.

## 2. Workstreams

| ID | Workstream | Deliverable |
|---|---|---|
| M3a | Native shell + immersive-space spike | PLATFORM=11 app builds/launches; minimal CompositorServices immersive space with test pattern; ARKit poses logged |
| M3-W1 | Native launcher integration | Native app keeps the launcher window + JIT/MC path; bundle/scan/sign pipeline for xros; `dev.vrmc.vrmc` native build |
| M3-W2 | Compositor layer | `LayerRenderer` setup, per-eye drawables, projection/FOV, frame timing |
| M3-W3 | Eye sampling | Bridge exposes the provider's two `MTLTexture`s; compositor samples them with timeline `MTLSharedEvent` sync (S4a findings) |
| M3-W4 | Head tracking | `WorldTrackingProvider` predicted anchor → `vrmc_get_tracking`; provider applies pose; recenter; timestamp alignment |
| M3-W5 | Presentation/perf | pacing, missed-frame handling, thermal/FPS instrumentation |
| M3-W6 | Device acceptance | criteria 1–5 on D1 + EV |

## 3. Key carry-overs from M2

- Bridge ABI is **v2** (provider+bridge ship together; ABI evolution policy in
  `bridge/abi/vrmc_abi.h`/`M2_PLAN §9`).
- Eye export: `VkImage → MTLTexture` works on device (EV-0069); timeline `MTLSharedEvent` required for
  sync (S4a: EV-0063/EV-0065).
- Provider uses identity/stub tracking; M3-W4 replaces it with real tracking.
- Device currently runs Fabric **0.20.1** (repo pin 0.19.3) — pin/ADR decision in M3.
- The current iOS-compat VRMC build remains the M2 test vehicle but **cannot** deliver immersive
  stereo.

## 4. Risks

- Native visionOS app hosting MC/JVM/JIT/Vulkan is unproven (highest); fallback two-process companion.
- UIKit launcher UI on native xros may need adaptation.
- CompositorServices + MoltenVK external texture sync/timing is new integration (substrate validated).
- Free-team 3-app limit: fallback (B) would need a slot (SideStore/StikDebug/VRMC are all used).
- Perf/thermal (S6) remains high risk once presentation works.


## 5. Gate-2 findings (EV-0072)

- Native immersive space + `CompositorLayer` + Metal render loop work; **gate 2 PASS (EV-0074)** — operator saw per-eye red/green stereo.
- Fixed three crash modes: premature `endSubmission` (`__BUG_IN_CLIENT__`), missing
  `cp_drawable_encode_present`, main-thread blocking (scene-update watchdog).
- **Verified by readback (EV-0073):** the per-eye render path is correct — eye0 pixel is
  r=0.800/g=0.050/b=0.050/a=1.000, view count 2, 1888×1792 rgba16Float, command buffer completes with
  no error. Remaining blocker: **presentation** — with the ARKit anchor set the user sees black, without
  it passthrough. Next iteration ports/compares the remaining layer/drawable setup:
  `predict_timing` → `start_update/end_update` → wait `optimal_input_time` → `start_submission` →
  `query_drawable` → `cp_drawable_set_device_anchor` → render → `cp_drawable_encode_present` → commit →
  `end_submission`, with `cp_time_to_cf_time_interval` for the ARKit timestamp.
- The probe temporarily replaced the VRMC app; the normal launcher was reinstalled and its data
  container preserved.


## 6. Gate-3 status and next options (EV-0075)

The native visionOS launcher **installs, launches, and does not crash**, but it shows only the window
title/toolbar with **blank content**. Pre-init logging runs (device, visionOS version, entitlements,
version list 923 versions) and there is no crash report; direct launch behaves the same. JIT is
therefore inconclusive and MC/JVM/Vulkan hosting in the native app is **unverified** — gate 3 stays NOT
RUN.

Next options, in order:
1. **Fix native window content (preferred):** instrument `SceneDelegate` (window frame / root VC /
   `launchInitialViewController`), try forcing the root view controller after `makeKeyAndVisible`, or
   provide a minimal SwiftUI window shell that presents the launcher VC. This is M3-W1 work.
2. **ADR-0010 fallback (B):** keep the proven compat app for JVM/MC/JIT and add a native immersive
   companion that receives the provider's eye textures over IPC/shared memory (IOSurface handoff) and
   ARKit poses back. Needs an app-slot plan (free-team limit 3) and a new ADR; larger than option 1.


## 7. Gate-3 diagnostics (EV-0076)

The native app's window hierarchy is correct: `willConnect` gets a 1280×720 window scene;
`rootViewController` is `LauncherSplitViewController`; the window is visible with alpha 1; the split
view's impl view is 1280×720 with 2 subviews after layout. The user still sees blank content, so the
failure is in **UIKit content rendering/presentation on native visionOS**, not in scene setup or
sizing.

Implication: the native-app route needs a UI workaround before gate 3 can be tested:
- **Option 1 (next, M3-W1):** host the launcher view controller from a minimal **SwiftUI window shell**
  (`UIViewControllerRepresentable`) or replace the initial VC with a plain `UIViewController`
  containing the launcher menu, to isolate the split-view rendering issue.
- **Option 2 (fallback B, ADR-0010):** compat JVM/MC app (proven JIT) + native immersive companion
  receiving eye textures over IPC/IOSurface and returning ARKit poses; needs an app-slot plan.


## 8. M3a complete (EV-0071/EV-0074/EV-0077)

All three M3a gates pass:
1. Native visionOS payload builds (EV-0071).
2. Native app opens a CompositorServices immersive space and presents per-eye stereo; the missing piece
   was the drawable depth attachment/rasterization-rate map (EV-0074).
3. The native app hosts the whole MC stack: JVM (Java 25) + JIT (always-attached TXM path) + MC 26.2 +
   Fabric Loader 0.20.1 + Vivecraft + VRMC provider/bridge ABI 2 + Vulkan/MoltenVK + device
   `VkImage→MTLTexture` eye export + tracking frames (EV-0077).

Gate 3 was reached via a **programmatic auto-launch** (`Documents/autolaunch.flag`) because the native
UIKit launcher content still renders blank (`LauncherSplitViewController` is created and sized
correctly, EV-0076). That UI issue is now **M3-W1** (not a hostability risk). The auto-launch hook is
currently a local refbuild patch; refresh `patches/vrmc-m1-amethyst-1.2.0.patch` before release.

Next: **M3-W1** native launcher UI, then **M3-W2/W3** (CompositorServices consumes the provider's two
`MTLTexture`s with timeline shared-event sync), **M3-W4** ARKit pose → bridge → provider hmdPose,
**M3-W5/W6** pacing and device acceptance.


## 9. M3-W1 status (EV-0078)

Two UI attempts failed:
1. Keep `LauncherSplitViewController` as root → valid window/scene (1280×720) but **blank content**
   (EV-0076).
2. Swap to a plain `LauncherNavigationController(root: LauncherProfilesViewController)` (native-only
   Info.plist marker) → branch executes, then **crash** in
   `-[LauncherProfilesViewController viewWillAppear:]` because
   `@[sidebarViewController drawAccountButton, ...]` uses `self.splitViewController.viewControllers[0]`
   and `splitViewController` is nil (EV-0078).

Conclusion: the existing launcher VCs hard-depend on the split-view container. M3-W1 needs one of:
- a native-specific UI shell (SwiftUI/UIKit) that calls the existing launch path without instantiating
  split-dependent VCs;
- a split-view-compatible shim/container that keeps `self.splitViewController` valid while rendering
  in a visionOS-friendly way.

Interim: the `VRMC_NATIVE_AUTOLAUNCH`/`Documents/autolaunch.flag` path remains the only proven way to
boot the game in the native app (EV-0077). The current-issue dossier is in `export/`
(`VRMC-native-ui-blocker-2026-11-01.zip`).
