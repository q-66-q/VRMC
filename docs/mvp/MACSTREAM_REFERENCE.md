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
`VisionRenderer`, the bridge wiring and the M4 input dispatch/gesture plumbing contain code/design
derived from macstream (`RemoteVR`, `RemoteVRStereoRenderer`, `RemoteVR.processInputs`/`dispatchAction`,
`TouchPlusInput` binding-table + action-set shape), LGPL-3.0, upstream commit `ec5a851c…`.** That code
stays in our LGPL provider with notices; **no macstream/derived code enters the GPL launcher**. The
provider remains a separate published artifact (ADR-0004/ADR-0006, ADR-0009).

## 5. Concrete next uses in M2

1. Port `VisionVR` init/poll skeleton from `RemoteVR` (identity pose, IPD, `updateAim`, `hmdSampling`).
2. Port `VisionRenderer` create/endFrame structure; log eye targets; handoff stub until S4a.
3. Add `SyntheticPoseSource`-style harness to drive M2 without a headset.
4. Host harness acceptance: provider init success (`VR provider: VRMC`) and two eye targets rendering.

## 6. Phase 8 root causes reused for VRMC M3-W3/W4 alignment (2026-11-01)

macstream's Phase 8 (VERIFY.md, runs 27–31) found five root causes. Two of them map directly onto the
visionOS immersive alignment work; we ported the same fixes in a CompositorServices form:

| macstream Phase 8 root cause | VRMC implementation |
|---|---|
| **3. Eye matrices contained the full head pose** — MCVR multiplies them onto `hmdPose`, so head motion was applied twice per eye; now head-relative, from ALVR `ViewsConfig local_view_transform` (IPD 67.4 mm) | Compositor publishes `cp_view_get_transform` (view→device = eye-to-head) in `vrmc_display_views`; `VisionVR.pollDisplayViews()` sets `hmdPoseLeftEye`/`hmdPoseRightEye` from those matrices (head-relative). |
| **4. Projection used the NullVR stub (110° symmetric, aspect 1.0)** instead of the client's asymmetric per-eye FOV; missing cache invalidation kept the stub FOV = exotropia | Compositor publishes the headset's per-eye `cp_view_get_tangents`; `VisionRenderer.setEyeFov()` stores signed tangents and `getProjectionMatrix()` builds `frustum(left·near, right·near, down·near, up·near, …)`; `lastFarClip`/`lastReverseFarClip` set to `NaN` to rebuild both cached projections (macstream's 43981c8 fix). |
| **5. Foveation mismatched** (not applicable to our direct display) | N/A — we render straight to CompositorServices, no foveated encode. |
| (also) client FOV consumes display projection, client does its own compositing | Compositor switches to **flat 1:1 eye-texture mapping** once display views are published, instead of reprojecting with a guessed FOV (EV-0086 black branch). |

Related macstream lesson kept as a separate item: **pose-to-display-time alignment** (their
`pose-to-display-time alignment` fix) is still pending for VRMC; our compositor labels the frame with
the newest ARKit pose rather than the pose Minecraft rendered with, so motion lag remains.

Offline verification: `scripts/test_display_views.sh` (JOML frustum test, PASS) + bridge stub
display-view roundtrip + provider compile against MC/Vivecraft jars (host PASS, EV-0088). Device run is
the remaining evidence.

## 6b. M4 input reuse (2026-11-01)

macstream is the only proven non-OpenVR Vivecraft **input** backend, so M4-W1 ports its shape, not its
transport: `RemoteVR.processInputs()`' per-action dispatch loop (`dispatchAction`, including the
`ignorePressesNextFrame`/movement-key return-to-neutral handling) and `TouchPlusInput`'s
source -> action binding table + `updateActiveActionSets` gating + origin convention (1 = LEFT,
2 = RIGHT). What differs on visionOS: sources are ARKit hand joints (pinch/fist) instead of ALVR
button paths, the pose comes from the 27-joint hand skeleton, and the single hard-coded
`MCOpenVR.get() == null -> false` check in `VRInputAction.isEnabled()` is replaced by a provider Mixin
(the same fallback macstream implements by forking Vivecraft; VRMC stays Mixin-only).

## 7. Batch/one-shot pipeline reuse

macstream's batch rendering guidance (pre-recorded pose/camera frames, one pass) is directly applicable
to our eventual M3-W5 frame-pacing work; not used yet because interactive VR needs live ARKit poses.
