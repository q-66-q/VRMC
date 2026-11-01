# M3 plan — Compositor stereo + head tracking (started 2026-11-01)

Status: **IN PROGRESS** — gate 1 **PASS (EV-0071)**; **gate 2 PASS (EV-0074)**: immersive space opens and the CompositorServices loop runs (2700+ frames, no crash), but stereo content is not presented (passthrough) and ARKit anchor/presentation-time wiring is missing. M2 CLOSED (EV-0070). M3 turns the provider's two exported `MTLTexture`s into an
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
