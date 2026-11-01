# macstream reference — proven “no OpenVR” Vivecraft backend (external)

Source: `/Volumes/Untitled/Projects/macstream` (separate project, outside this repo, not committed).
Upstream commit: `ec5a851c066856b0a3ca3eadc530d5ea18e88930` (2026-10-24, Phase 9 S9.1 complete).
License: LGPL-3.0 (Vivecraft derivative). Tracked reference: ADR-0009.
It streams Vivecraft from macOS to a Quest 3 without SteamVR and already has an end-to-end working
build. This note records what we reuse for VRMC M2 and what must differ on visionOS.

## 1. What macstream proved

- Vivecraft’s backend abstraction can be replaced by a **custom `MCVR` provider** (`RemoteVR`) with
  **no OpenVR/SteamVR runtime**. Their fork adds `VRSettings.VRProvider.REMOTEVR` and a
  `VRState.initializeVR` branch (equivalent to our Mixin substitution, already proven in VRMC EV-0059).
- A custom `VRRenderer` (`RemoteVRStereoRenderer`) creates the eye pair with MC 26.2’s GPU abstraction
  (`VRTextureTarget.builder(...).withFormat(RGBA8_UNORM)`), renders both eyes, and in `endFrame()`
  hands the eye textures to native via JNI **texture ids only** (pixels never cross JNI).
- A **synthetic-pose harness** (`SyntheticPoseSource`) drives the bridge without a headset — this is
  their bridge test suite and a pattern we should copy for host/desktop and simulator runs.
- Pose/input path: native ring buffer → preallocated direct buffers → `poll()` updates `hmdPose`,
  `hmdRotation`, `controllerPose[]`, tracking flags, then `updateAim()` + `hmdSampling()`.
- Source reference paths:
  - `spike/vivecraftmod/common/src/main/java/org/vivecraft/client_vr/provider/remotevr/RemoteVR.java`
  - `.../RemoteVRStereoRenderer.java`, `.../RemoteVRBridge.java`, `.../SyntheticPoseSource.java`,
    `.../TouchPlusInput.java`, `.../RemoteVRAudioTee.java`
  - fork hooks: `VRState.java` (REMOTEVR branch), `VRSettings.java` (JVM flag `-Dmacstream.vr=remote`),
    `MCVR.java` (origin→controller mapping), `GlSurfaceMirrorMixin.java` (GL frame mirror).

## 2. Mapping to VRMC M2

| macstream | VRMC M2 |
|---|---|
| Fork + `VRSettings.REMOTEVR` enum | **Mixin `@Redirect`** on `ClientDataHolderVR.vr` (EV-0006/EV-0009/EV-0059) — no fork, no enum edit |
| `RemoteVR extends MCVR`, identity pose + IPD, `initSuccess=true` | `VisionVR.init()`: call `vrmc_init(caps)` (ABI v1), set identity pose, `populateInputActions()`, `initSuccess=true` |
| `RemoteVRBridge` JNI static wrapper + direct buffers | `VrmcBridge` JNI wrapper over our `vrmc_*` ABI (no per-frame allocation; direct `ByteBuffer`s) |
| `RemoteVRStereoRenderer` eye pair, per-eye FOV, `endFrame` handoff | `VisionRenderer` same structure; **replace GL texture id handoff** with the MoltenVK/Metal path from S4a (Vulkan backend; `GraphicsHelper.getTextureHandle` returns 0 on Vulkan — macstream explicitly notes this) |
| `SyntheticPoseSource` test harness | port as our harness driver for host/desktop and simulator runs |
| `TouchPlusInput` (ALVR button events → actions) | reference for M4 input (PSVR2 Sense / GameController path, not ALVR) |
| ALVR streaming/encode path | not applicable to VRMC M2/M3 (we render to CompositorServices on the headset, not encode to Quest) |

## 3. What must differ on visionOS

1. **Graphics**: macstream = Blaze3D **OpenGL** on macOS, eye handoff via GL texture ids. VRMC =
   Minecraft **Vulkan** → MoltenVK. Eye handoff must use `VK_EXT_metal_objects` /
   `vkGetMTLTextureMVK` (see `docs/mvp/S4A_FINDINGS.md`) or a GPU blit fallback.
2. **Presentation**: macstream encodes and streams to an ALVR client; VRMC presents stereo directly
   through CompositorServices (M3).
3. **Tracking**: macstream poses come from ALVR; VRMC gets ARKit/WorldTracking + AccessoryTracking
   (M3/M4). M2 uses stub/identity or synthetic poses through the same bridge ABI.
4. **Provider selection**: macstream forks Vivecraft; VRMC keeps the LGPL Mixin mod (ADR/S3 decision).
   If a needed hook cannot be Mixined cleanly, macstream’s fork is the proven fallback (ADR required).

## 4. License

macstream’s `spike/vivecraftmod` is a derivative of Vivecraft (LGPL-3.0). **Status: `VisionVR`,
`VisionRenderer` and the bridge wiring contain code/design derived from macstream (`RemoteVR`,
`RemoteVRStereoRenderer`), LGPL-3.0, upstream commit `ec5a851c…`.** That code stays in our LGPL provider
with notices; **no macstream/derived code enters the GPL launcher**. The provider remains a separate
published artifact (ADR-0004/ADR-0006, ADR-0009).

## 5. Concrete next uses in M2

1. Port `VisionVR` init/poll skeleton from `RemoteVR` (identity pose, IPD, `updateAim`, `hmdSampling`).
2. Port `VisionRenderer` create/endFrame structure; log eye targets; handoff stub until S4a.
3. Add `SyntheticPoseSource`-style harness to drive M2 without a headset.
4. Host harness acceptance: provider init success (`VR provider: VRMC`) and two eye targets rendering.
