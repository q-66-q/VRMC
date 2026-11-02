# Vivecraft eye-texture content analysis (provider side) — what `framebufferEye[]` must contain and why it can be near-black

**Author:** vivecraft-render (task-2) · **Date:** 2026-11-01 (HST) · **Scope:** provider/ + docs/analysis/
**Source of truth:** Vivecraft 26.2-1.3.15 tree (`VivecraftMod-Multiloader-26.2/`, git-ignored reference) and
the device logs in `evidence/EV-0090/` + `evidence/EV-0091-fresh/` (`/tmp/vrmc-pull-1650/`).

## 0. Verdict (short)

1. **The provider's eye textures are supposed to contain the whole rendered eye view each frame: world
   (or the menu room/menu world) + the in-world GUI/screen quad + VR hands, post-processed**, on both
   eyes. The GUI is **not** composited by the post-process copy — it is rendered as a world-space quad
   into the same render target before the post-process copy, so it ends up in `framebufferEye` "for
   free". There is no provider setting required to get the menu GUI into the eye target.
2. **In the newest device run (2026-11-02 02:39 UTC = 16:39 HST, post-JNI-fix build) the provider eye
   textures were NOT black.** The compositor's own readback of the exact exported textures shows bright
   content at every sampled frame (frame 0: L mean RGB 115.6/110.4/89.1 = luma 105, R 113.9/108.7/87.6 =
   luma 103; frames 300/600/900 luma 103–154; alpha 255; nonBlack 919–1024 of 1024). Display views were
   applied correctly (Lpos/Rpos in the provider log match the compositor's published views).
   **Therefore the current "pure black immersive" is not caused by black provider content.**
3. A provider-side black *can* be produced in early/edge situations, and the important ones are
   enumerated in §4: the first frames before the first VR pass/post-process has executed, a menu-world
   fallback/clear path at night, a skipped GUI quad, framebuffer reinit with stale exported handles, and
   GPU asynchrony between the game queue and the compositor. **None of them can explain a persistent
   black screen while the game is rendering** (the compositor's forced test-pattern flag would make the
   provider texture irrelevant anyway).
4. Two real (but not black-causing) provider bugs were found and fixed: the per-frame IPD fallback was
   overwriting the headset's display-view eye transforms, and the bridge was being told a symmetric 110°
   frustum instead of the applied display-view frustum. Instrumentation was added to settle the GUI and
   reinit questions on the next device run (§7).

## 1. Per-frame VR render pipeline (26.2-1.3.15)

Entry point: `Minecraft.renderFrame` → Vivecraft mixins in `mixin/client_vr/MinecraftVRMixin.java`.

```
renderFrame
 ├─ MinecraftVRMixin.vivecraft$setupRenderGUI (L312-348)
 │    → VRRenderer.setupRenderConfiguration()            (creates/reuses framebufferEye[0/1] via createRenderTexture)
 │    → RenderPassManager.setGUIRenderPass()             (mainRenderTarget = GuiHandler.GUI_FRAMEBUFFER)
 │    → GameRenderer.extract(deltaTracker, renderLevel=false)
 ├─ Minecraft.renderFrame → GameRenderer.render(deltaTracker, false)   ← GUI-only pass
 │    → VRPassHelper? no: vanilla GameRenderer.render with mainRenderTarget = GUI_FRAMEBUFFER,
 │      vivecraft$shouldDrawScreen=true; GameRendererVRMixin.vivecraft$mainMenu (L189-208) returns early
 │      because (!renderLevel && shouldDrawScreen) → the title screen/HUD is rendered into GUI_FRAMEBUFFER
 ├─ MinecraftVRMixin.vivecraft$renderGUI (L350-361) sets shouldDrawScreen=false, pushes modelview
 ├─ MinecraftVRMixin.vivecraft$renderVRPassesFabric (L363-370) → VRPassHelper.renderAndSubmit(renderLevel, ...)
 │    ├─ GUI cursor into GUI_FRAMEBUFFER (VRPassHelper L131-146)
 │    └─ for each RenderPass (LEFT, RIGHT, [CENTER/THIRD/scope/camera])    (VRPassHelper L188-244)
 │         ├─ RenderPassManager.setWorldRenderPass(...)                 (mainRenderTarget = framebufferVrRender)
 │         └─ VRPassHelper.renderSingleView(pass)                       (VRPassHelper L40-119)
 │              ├─ clear mainRenderTarget (framebufferVrRender) color=BLACK_SOLID + depth 0   (L41-43)
 │              ├─ gameRenderer.update/extract + gameRenderer.render    (L47-60)
 │              │     └─ GameRendererVRMixin.vivecraft$mainMenu: if (!renderLevel || level==null ||
 │              │        menu room) → VREffectsHelper.renderMenuRoom(...) and CANCEL the vanilla path (L189-208)
 │              │            renderMenuRoom (VREffectsHelper L606-648):
 │              │              menu environment (menu world / fallback panorama / dark room)   L625
 │              │              GUI layer: GUI_FRAMEBUFFER drawn as a world quad                 L626
 │              │              keyboard + radial + VR hands                                    L628-641
 │              ├─ restore player, endFrame buffers                     (L63-67)
 │              ├─ optional FSAA                                       (L82-90)
 │              └─ ShaderHelper.doVrPostProcess(eye, mainTarget, framebufferEye[L/R], ...)   (L93-95)
 │                    → full-screen quad from mainRenderTarget into framebufferEye[eye]   (ShaderHelper L191-214)
 └─ VRPassHelper.renderAndSubmit: vrPlayer.postRender(); vrRenderer.endFrame()  (L248-252)
      → VisionRenderer.endFrame(): export framebufferEye[0/1] (VkImage→MTLTexture) + vrmc_submit_eyes()
```

Relevant details:

- **Eye targets**: created once per `setupRenderConfiguration` reinit by the provider
  (`VisionRenderer.createRenderTexture`, same as NullVR/OpenVR): `VRTextureTarget` 1024x1024,
  `GpuFormat.RGBA8_UNORM`, **no depth, no clear colour** (`VRTextureTarget` only clears at creation if
  `withClearColor` was used; see `client_vr/VRTextureTarget.java:45-63`). They are the only images the
  compositor sees; their content is whatever the last `doVrPostProcess` wrote.
- **Post-process copy**: `ShaderHelper.doVrPostProcess` (L191-214) renders one full-screen quad from
  `mainRenderTarget.getColorTextureView()` (that frame's `framebufferVrRender`, i.e. world+GUI+hands)
  into `framebufferEye[eye].getColorTextureView()` with `flipEyeVertically()`
  (`VulkanHelper.flipEyeVertically() == true`, `OpenGLHelper` default false). The shipped fragment
  shader `assets/vivecraft/shaders/core/postprocessing_vr.fsh` only applies damage/freeze/sleep/FOV
  effects; otherwise **`fragColor = bkg_color`**, i.e. colour **and alpha are copied through unchanged**.
  So the eye target's alpha is the source alpha (§5).
- **GUI placement**: for the menu room (title/loading screens), `VREffectsHelper.renderMenuRoom` draws
  `GuiHandler.GUI_FRAMEBUFFER` as a non-depth-tested quad at `guiState.worldPos` with `uiRenderMode ==
  MENU` (`VREffectsHelper.renderScreen` L1040-1074, `renderGuiLayer` L1087-1099,
  `VRRenderState.extract` L189-197). In the menu room the screen is placed at a fixed room position
  (0.02, 1.3, −1.5) with GUI scale 2 (`GuiHandler.onScreenChanged` L412-423), i.e. directly in front of
  and slightly above the head. In-world the HUD/screen is placed relative to head/controller
  (`GuiHandler.extractGui`). `VRRenderState.renderGui` gates the quad (L257-260).
- **Menu world**: if `dh.menuWorldRenderer.isReady()` the menu room renders the downloaded menu world
  (`VREffectsHelper.renderTechjarsAwesomeMainMenuRoom` L531-597) + GUI + hands; otherwise it falls back
  to the panorama or the "Jrbuddas" dark room (L660-690). The menu-world clear colour is the current
  **MC fog colour with alpha 0.0** (L546-551) and the sky/fog uses the in-game time of day derived from
  the local wall clock (L536-540), so a "night" menu world is legitimately dark blue.
- **When endFrame runs** (answer to question (e)): `VRPassHelper.renderAndSubmit` calls
  `vrRenderer.endFrame()` **after both LEFT/RIGHT passes have executed and after each pass's
  `createCommandEncoder().submit()`** (`VRPassHelper.renderSingleView` L118), and after
  `vrPlayer.postRender`. Exporting and submitting the eye handles there is the correct place: the
  handles refer to the images that were just rendered for this frame, in submission order on the
  Vulkan queue. **What this does not guarantee is GPU completion / cross-queue visibility for the
  compositor** (it is a different thread and a different MTLCommandQueue); that is the bridge timeline
  semaphore work (task-4/bridge-sync), not the provider's. No provider-side black is implied by this.
- **Eye order**: `framebufferEye[0]` = LEFT, `[1]` = RIGHT, submitted as `left_texture`/`right_texture`
  by `VisionRenderer.endFrame`; the compositor picks `isLeft ? left_texture : right_texture` using its
  own `leftView` determination, and publishes `dv.left_tangents/left_eye_to_head` for the same view, so
  there is no L/R swap in the handoff.

## 2. What the eye textures should contain, per scene

| Scene | Expected `framebufferEye[L/R]` content |
|---|---|
| Title screen / menu room (title, loading, WinScreen; `MC.level == null`) | Menu world (or fallback panorama / dark room) + the in-world title screen quad (GUI_FRAMEBUFFER) + hands; no HUD. Viewed from the fixed menu-room camera. |
| In world, no screen | World (+HUD/crosshair depending on HUD mode) + hands; the HUD quad is drawn in-world (head- or hand-locked). |
| In world, container/inventory screen | World + the floating screen quad (same GUI_FRAMEBUFFER) + hands. |
| VR "connecting to runtime"/error screen | GUI-only content; the connecting message is drawn into the `mainRenderTarget` used by the GUI pass. |
| Just after renderer init, before first pass | Do not care: `endFrame` is only called after the passes in the same frame; the bridge has no non-zero eye handles before the first submit, so the compositor is in test-pattern mode. |

**Answer to "is the MC main-menu GUI expected in framebufferEye at the title screen?" — Yes.** It is
in the eye texture at the title screen (drawn in-world by `renderGuiLayer` inside the LEFT/RIGHT passes),
not just on the desktop mirror. A title-screen capture without any GUI would be a genuine defect (GUI
quad not rendered or outside the eye frustum), and the new `[VRMC-DIAG]` line proves which it is.

## 3. Why the compositor's 32x32-centre readback is not "no GUI" evidence

The compositor samples a 32x32 centre strip of each 1024² eye texture (1.56 % of width). On the title
screen the GUI quad covers a large solid angle but is mostly *text/buttons with transparent background*;
the exact screen centre of the 1.3 m-high menu panel is not guaranteed to contain GUI pixels. A uniform
centre therefore says little about GUI presence. The new provider diagnostic logs the GUI's own NDC per
eye (`guiNDC L/R`) so a device log can prove whether the GUI centre is inside the rendered frustum.

## 4. When the eye textures can legitimately be near-black (and which of these could be the device black)

1. **First frames before the first post-process has executed.** The eye targets are created without a
   clear (`VRTextureTarget` has no default clear; driver memory is undefined/typically zero). The first
   non-zero handle submitted to the bridge is always from a frame whose passes ran (endFrame ordering,
   §1), but the compositor can still *query and sample* the texture before the game's GPU work for that
   frame is visible (different queue; no fence). This yields at most a frame or two of black/stale
   content — never a persistent black screen while MC keeps rendering. The compositor's own
   `eyes=0 → test pattern` and the readback logs already cover this.
2. **Menu-room night.** `renderTechjarsAwesomeMainMenuRoom` clears to the menu world's fog colour with
   alpha 0 at the MC time-of-day derived from the local clock (`VREffectsHelper` L536-551). At night this
   is a dark blue (observed on device: dark blue centre reads `mean=(42.5,41.5,108.0)`,
   `max=(52,50,127)` — these are *expected menu-world night values*, not a render failure).
3. **Menu world not ready / failed.** Before `MenuWorlds: Built …` the fallback panorama (default
   `menuWorldFallbackPanorama=true`) or the dark JR room is used; if the menu-world download fails
   (`menuworlds/worldNN.mmw` is fetched from vivecraft.org) the game keeps the fallback. The newest
   run's log shows the world was built (5,258,196 blocks, 126 buffers) with no exception.
4. **GUI quad skipped.** `vrState.renderGui == false` (`VRRenderState.extract` L257-260), a null
   `GuiHandler.GUI_FRAMEBUFFER`, or a GUI pose outside the eye frustum leaves only world/clear content.
   For the title screen this cannot be inferred from the centre readback (§3) — the new diag settles it.
5. **Framebuffer reinit / stale exported handle.** `setupRenderConfiguration` → `destroyBuffers()` +
   `createRenderTexture()` recreates both VkImages. The bridge keeps the *old* MTLTexture handles until
   the next `endFrame()` submits the new ones (zero handles are rejected by the bridge, so the provider
   cannot clear them through ABI v2: `bridge/src/vrmc_stub.c:78-88`). The window is sub-frame, but the
   compositor could sample a destroyed/reused texture once. The provider now logs
   `[VRMC-DIAG] eye target handles changed ... (framebuffer reinit)` so the next device log shows whether
   this ever happens during a session. (Clearing the bridge handles on destroy is a bridge-scope fix;
   reported to the Lead, not changed here.)
6. **Post-process/render failure.** If a Vulkan shader/pipeline failed, the copy could produce nothing and
   the eye target would keep its previous/undefined content. The device run proves the post-process works
   (readback shows a copy of the rendered scene), so this is not the current cause.
7. **Compositor never samples.** If `vrmc-test-pattern.flag` (or `vrmc-no-sampling.flag`) is present, the
   compositor draws the procedural pattern and never samples the provider image. **If the operator saw
   "pure black" while a forced test-pattern flag was active, the provider image and the sampling path are
   provably irrelevant — the failure is in the drawable/presentation path** (that is task-3/compositor
   scope). NOTE: the compositor does not currently log `forceTestPattern`, only `samplingDisabled`;
   `samplingDisabled=0` in the newest log confirms the no-sampling flag was absent, but says nothing
   about `vrmc-test-pattern.flag`. Suggest the compositor log both flags (Lead/task-3).

**None of 1–7 explains a persistent black image while the compositor runs and the provider textures are
bright.** The latest run's evidence rules the provider out as the black source.

## 5. Why alpha=0 appeared in some right-eye readbacks (question (d))

The post-process fragment shader copies alpha straight through (§1). The menu-room clear uses the fog
colour with **alpha 0.0** (`renderTechjarsAwesomeMainMenuRoom` L546-551), and MC's sky/clear paths also
write alpha 0 in places (Vivecraft has a dedicated "alpha clear" full-screen pass for that reason,
`VRPassHelper` L71-75). Therefore alpha 0 simply means "those pixels came from the menu-room clear/sky",
not "unrendered". The compositor forces `alpha = 1.0` in both sampling shaders, so alpha cannot cause
black. The EV-0090-era readbacks with `R mean=(181,207,255) alpha=0.0` are sky/fog-coloured pixels with
transparent source alpha, exactly as designed (an earlier build; not reproduced in the newest run, where
all sampled alphas were 255).

## 6. Provider differences vs NullVR / OpenVR / macstream RemoteVR (question (c))

| Aspect | OpenVR | NullVR | macstream RemoteVR | VRMC VisionRenderer (before fix) | Assessment |
|---|---|---|---|---|---|
| Eye targets | RGBA8_UNORM, no depth/clear | same | same | same | correct |
| Projection | runtime raw tangents | NullVR settings; invalidates cache on setting change | client ViewsConfig tangents (`setEyeFov` + NaN cache invalidation) | display-view tangents + NaN cache invalidation | correct (same mechanism as macstream) |
| Eye-to-head transforms | runtime `GetEyeToHeadTransform` | ±IPD/2 | ViewsConfig matrices applied **only when generation changes**, IPD fallback only when none | display-view matrices applied when gen changes, **but IPD fallback overwrote them every frame** | **bug fixed** — see §7 |
| endFrame | `VRCompositor_Submit` + `PostPresentHandoff` | poll bookkeeping | bridge submit (GL ids) + optional PNG capture | bridge submit (VkImage→MTL) | ordering correct |
| Stencil | provides stencil mesh | false | false | false | correct |
| Render passes | base getRenderPasses | base | base | base | correct (LEFT,RIGHT active in log) |
| Frustum reported to runtime | implicit runtime; no report needed | implicit | — | symmetric 110° reported to bridge even when display views active | **misleading, partially fixed** (§7) |
| Eye capture harness | — | — | `Screenshot.grab(RenderTarget)` PNG capture behind a property | added (§7) | — |

The bridge's `vrmc_eye_targets.left_fov/right_fov` still only accepts a symmetric half-angle
(`nativeSubmitEyes`, `bridge/src/vrmc_jni.c:38-53`), so the provider can only report the widest
display-view half-angle, not the asymmetric tangents. When display views are published the compositor
uses the flat path, so this value is diagnostic only today; if the reprojection fallback ever fires it
would use the wrong (too wide/narrow) frustum. Fixing it properly needs a per-eye tangent field in the
bridge ABI (bridge-scope; recommend an additive `left_fov[4]/right_fov[4]` submit variant).

## 7. Provider changes made (compile-verified: `scripts/build_provider.sh`, exit 0)

`provider/src/main/java/dev/vrmc/provider/VisionVR.java`
- **Fix (real bug):** the per-frame IPD fallback no longer overwrites `hmdPoseLeftEye/RightEye` while the
  compositor's display views are live. Before, any frame where the display-view generation did not
  change silently reverted the eye poses to a symmetric ±IPD/2 offset (the headset's real eye offsets are
  asymmetric: published `Lpos=(-0.0322,-0.0266,-0.0356) Rpos=(0.0321,-0.0246,-0.0354)`), which would
  produce persistent alignment jumps/exotropia — exactly the class of issue seen in EV-0086. macstream's
  RemoteVR already does it this way (`pollViews()` owns the matrices; IPD fallback only when no views).
- Throttled the per-generation display-view log (it was one line per frame, ~19 000 lines/h in the device
  log) to first 3 + every 120th apply.

`provider/src/main/java/dev/vrmc/provider/VisionRenderer.java`
- `[VRMC-DIAG]` line every `vrmc.diagEvery` frames (default 300): frame, current pass, menu-room,
  level, menu-world state, screen class, seated, GUI framebuffer presence, display-views active, applied
  per-eye frustum tangents, `renderGui`, GUI world position and its **NDC in each eye**, and the actual
  eye world positions. This answers "was the GUI rendered / was it inside the frustum / did the eye poses
  track the published display views" from a single device log.
- `[VRMC-DIAG] eye target handles changed …` when a reinit changes the exported textures (stale-handle
  window, §4.5).
- **Eye-target PNG capture** (off by default): `-Dvrmc.captureDir=<dir>` or a `vrmc-capture.flag` file in
  the game directory (`<gameDir>/vrmc-capture/`), interval `-Dvrmc.captureEvery` (default 300 frames),
  max `-Dvrmc.captureMax` (default 3 captures). Captures `framebufferEye[0]`, `framebufferEye[1]` **and the
  pre-post-process `mainRenderTarget`** via vanilla `Screenshot.grab(File,String,RenderTarget,int,Consumer)`
  — the same proven FBO→PNG path macstream's RemoteVRStereoRenderer uses (LGPL reference, ADR-0009).
  This gives the exact exported image (with alpha) on device, pullable with devicectl, so "provider content
  vs presentation" needs no operator judgment.
- Cached `resolution`/`ss` in `getRenderTextureSizes()` (matches NullVR/OpenVR shape; no behaviour change).

Build: `/tmp/vrmc-provider-build/vrmc-provider.jar` sha256 `a80c7040735d0f7ff75265e29953dae87ab5a4e35045a3d959700245ef938605`
(compile exit 0; not yet device-tested — the Lead stages/installs).

### How to use the new diagnostics on the next device run (Lead)

1. Stage the new provider jar (`scripts/build_provider.sh` + `scripts/push_provider_jar.sh`).
2. To get eye images with no extra JVM args, push `vrmc-capture.flag` into the **game directory**
   (the instance dir, sibling of `screenshots/`), e.g. `instances/default/vrmc-capture.flag` inside the
   app data container. PNGs land in `instances/default/vrmc-capture/` and can be pulled with
   `devicectl device copy from`.
   (Alternatively pass `-Dvrmc.captureDir=/absolute/dir` from the launcher's JVM args.)
3. Expected new log lines in `latestlog.txt`:
   `[VRMC-DIAG] frame=300 pass=RIGHT menuRoom=1 level=null menuWorld=ready screen=TitleScreen seated=0 fbGUI=1 displayViews=1 tanL=... renderGui=1 guiPos=(0.02,1.30,-1.50) guiNDC L=(... ) R=(...) eyeL=(...) eyeR=(...)`
   and, when captured, `[VRMC-CAP] frame … vrmc_eye_L_… -> <path>.png`.
   If `guiNDC` is inside [-1,1] and the captured `vrmc_eye_L/R` PNG shows the menu world **and** the title
   GUI, the provider is fully cleared and the black screen is presentation-side.

## 8. Off-device verification via the host harness (proposal, question (f))

The host harness (`provider/HOST_HARNESS.md`, `scripts/build_provider.sh`) is the right place to prove
"eye texture content at the title screen" without the headset:

- A host Fabric run is possible on the Mac build host (it was used for EV-0059/EV-0060) but the previous
  run dir (`/tmp/mc-fabric`) and classpath file have been cleaned, so it must be recreated:
  JDK 25 (`/Library/Java/JavaVirtualMachines/temurin-25.jdk`), the official-mapped MC 26.2 client jar
  (already in `~/.gradle/caches/neoformruntime/artifacts/`), the compiled Vivecraft common classes
  (`VivecraftMod-Multiloader-26.2/common/build/classes/java/main`) + stubs jar, JOML/Mixin from the Gradle
  cache, MC assets from `~/Library/Application Support/Swift Craft Launcher/meta/assets`, a host bridge
  dylib (`scripts/build_bridge.sh MODE=host`), and `-Dvrmc.stub`-free launch of
  `net.fabricmc.loader.impl.launch.knot.KnotClient` with `-Dvrmc.hostHarness=true
  -Dvrmc.bridge.lib=/tmp/libvrmc_bridge.dylib`.
- On this Mac the GL backend is used (`OpenGLHelper`, `flipEyeVertically=false`), the provider submits GL
  texture ids (the compositor is not involved), and the new capture can be enabled with
  `-Dvrmc.captureDir=/tmp/vrmc-host-capture -Dvrmc.captureEvery=200 -Dvrmc.captureMax=3`. Expected result:
  PNGs of `framebufferEye` showing the menu world + title GUI at the title screen, proving the provider's
  content contract in isolation (no device, no compositor, no headset).
- If the host run is not worth the setup time, the device capture flag above gives the same ground truth
  directly from the device in ~1 minute of operator time.
- Note: the GL host path proves the *pipeline* (world+GUI into the eye target, orientation, capture), not
  the Vulkan/MoltenVK output; the device capture covers that.

## 9. Residual provider issues / recommendations (not fixed here)

1. **Stale exported handles across reinit**: bridge rejects zero handles, so the provider cannot clear the
   shared eye targets on `destroyBuffers`; until the bridge adds a clear/validation path (task-4), the
   compositor can sample a stale MTLTexture for <1 frame after a reinit. The new handle-change log will
   show whether this happens on device.
2. **Cross-queue synchronization**: the provider submits handles + frame index; the compositor samples the
   texture from its own queue with no timeline semaphore wait. This is the bridge-sync task (S4a showed
   timeline `MTLSharedEvent` is the working mechanism). Until then, the compositor may sample the previous
   frame or, on the first frames, undefined content — a 1–2 frame artifact, never a persistent black.
3. **Asymmetric FOV not reported to the bridge** (§6): needs an additive eye-target FOV field; currently
   the compositor's reprojection fallback would use a symmetric 110° instead of the display frustum.
4. **Resolution**: 1024x1024 per eye versus the CompositorServices viewport 1888x1792; flat mapping
   upscales by ~1.8x. Fine for bring-up, worth raising (`-Dvrmc.eyeWidth/-Dvrmc.eyeHeight`) once content
   is visible; not related to black.
5. **Eye transform ownership**: the fix assumes `hmdPoseLeftEye/RightEye` are written only by the provider
   (true in this code base: only `VisionVR.init/poll/pollDisplayViews` write them). If a future Vivecraft
   version changes `MCVR` to recompute them, revisit.

## 10. Evidence used

- Device logs, newest post-JNI-fix run: `/tmp/vrmc-pull-1650/` (= `evidence/EV-0091-fresh/`):
  `vrmc-compositor.log` sessions starting at lines 427/486 — `provider tex L/R` means quoted in §0/§4;
  `published display views L tangents=(-1.732,1.000,1.000,-1.192) Lpos=(-0.0322,-0.0266,-0.0356) …`;
  `frame 0 command buffer completed (first)`; `samplingDisabled=0`.
  `latestlog.txt`: `[VRMC-M2] eye target L/R 1024x1024`, `vulkan eye export: VkImage=0x13f951400 ->
  MTLTexture=0x72274da300`, `display views gen=1 applied ipd=0.0644 Lpos=(-0.0322,-0.0266,-0.0356)
  Rpos=(0.0321,-0.0246,-0.0354)`, `MenuWorlds: Built 5258196 blocks in 2772 ms`,
  `Vivecraft: Active RenderPasses: LEFT, RIGHT`.
- Pre-fix run (EV-0090-era, 15:28 local): dark menu-world centre reads (luma 17–81, dark blue
  `L=(42.5,41.5,108.0)`, `R=(181,207,255) alpha=0`) — consistent with a night menu world with no GUI in
  the sampled centre, not with a post-process failure.
- Vivecraft 26.2-1.3.15 sources cited inline (paths relative to
  `VivecraftMod-Multiloader-26.2/common/src/main/java/org/vivecraft/`).
- macstream reference: `spike/vivecraftmod/.../remotevr/RemoteVRStereoRenderer.java` (capture harness),
  `RemoteVR.pollViews()` (display-view ownership).
