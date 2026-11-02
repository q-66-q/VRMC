# Bridge eye-handoff audit — lifetime, thread safety, GPU synchronization (task-4)

**Owner:** bridge-sync (task-4)
**Date:** 2026-11-01
**Scope:** `bridge/` (ABI headers, stub implementation, JNI shim, new host tests) + `docs/analysis`.
**Java ABI v2:** unchanged. All additions are in the native-shared surface
(`bridge/abi/vrmc_native_shared.h`), which is explicitly outside the Java ABI contract.
**Device access:** none used. Every claim below is code analysis, host evidence, or existing
device-log analysis. Device verification of the new path is **NOT RUN**.

---

## 1. Verdict (the four questions)

| # | Question | Verdict |
|---|----------|---------|
| 1 | Is the shared eye/tracking state thread-safe (locking/atomics)? Is a returned handle potentially torn/stale? | **NO — it was a data race, now fixed.** `vrmc_submit_eyes` published an 80-byte `vrmc_eye_targets` copy (and `vrmc_shared_set_tracking` a 96-byte state) with **no mutex, atomics or release/acquire ordering** while the compositor thread copied the same bytes. A reader could observe a new left handle with the old right handle, or a new texture with a stale frame index/signal. Fixed: all cross-thread state is now published/read under a bridge mutex through `vrmc_shared_publish_eyes` / `vrmc_shared_acquire_eyes` (and tracking/display views likewise). Concurrency proof: `bridge_sync_test` under ThreadSanitizer, 4 readers x 200k publishes, 0 torn frames, no TSan report. |
| 2 | Do exported MTLTextures stay valid across framebuffer reinit (resize / window parking)? Does the compositor notice handle changes? | **No lifetime protocol existed, and the compositor could not notice a change.** Handles are raw `id<MTLTexture>` pointers owned by the provider's eye `VRTextureTarget`s; `VRRenderer.destroyBuffers()` destroys them on reinit. The compositor re-read `vrmc_shared_eye_textures` every frame but had no generation counter and no retain, so a stale/freed handle could be sampled for at least one frame. Fixed bridge-side: `texture_generation` bumps whenever the left/right handle or size changes; `publish_sequence` allows new-frame detection. Compositor contract documented (re-acquire every frame, retain for the command buffer, drop retained textures on generation change); the provider must keep the previous eye targets alive a few frames after a reinit (documented in §6). |
| 3 | How to add correct cross-queue GPU sync (S4a: MTLSharedEvent only from a timeline VkSemaphore; binary exports nil)? | **Confirmed absent; additive API designed, implemented and host-proven.** New native-shared API: provider publishes `(shared_event, signal_value)` atomically with the eye textures; compositor encodes `[cb encodeWaitForEvent:ev value:value]` before sampling. Host probe (real MoltenVK 1.4.2 + Metal): exported timeline semaphore -> `MTLSharedEvent`, two frames signaled 5 then 6, a *separate compositor thread on a separate MTLCommandQueue* waited and shader-sampled the Vulkan-written texture with exact expected pixels. Host PASS; device path still requires provider wiring (§5) and a device run. |
| 4 | MTLTextureUsage `ShaderRead` hypothesis ("readback bright but sampling black because the texture was exported without shader-read usage") — true? | **DISPROVEN (both by MC 26.2 code analysis and by host MoltenVK).** MC 26.2 `RenderTarget.createBuffers` creates the color texture with `usage=15` = COPY_DST|COPY_SRC|**TEXTURE_BINDING**|RENDER_ATTACHMENT; `VulkanConst.textureUsageToVk` maps TEXTURE_BINDING -> `VK_IMAGE_USAGE_SAMPLED_BIT`, so the eye `VkImage` is `SAMPLED|COLOR_ATTACHMENT|TRANSFER_SRC|TRANSFER_DST`. A host probe exporting an image with **exactly those usage flags** through `vrmc_export_mtl_texture` gets a Metal texture with `usage=0x5` = `MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget`, and a shader `read()` of it returns the Vulkan clear pixels. So the exported eye texture **is** sampleable; the black immersive must be explained elsewhere (§2). The remaining runtime check for the compositor is a one-line `tex.usage` log. |

Additional defect found while auditing the display-view path (fixed): `vrmc_eye_targets.left_fov/right_fov`
still reported the old symmetric 110° stub (±1.428 tangent) even after the compositor published the real
display views (visible in the EV-0090 log: `provider eye tangents L=(-1.428,1.428,-1.428,1.428)` while
`displayViewsPublished=1`). Harmless while the compositor uses flat mapping, but any fallback to
reprojection would have used the wrong frustum. The JNI now derives the published FOV from the display-view
tangents when they exist (§7).

---

## 2. What this means for the black-immersive blocker

This task does not claim to have found the black-immersive root cause, but it removes three hypotheses and
produces one hard constraint for the next device run:

1. **Provider texture usage/sampleability is not the cause** — proven above.
2. **The EV-0089/EV-0090 "provider eye textures are non-black" readbacks are not trustworthy as evidence of
   what the sampling pass sees.** The 32x32 readback is a Metal blit command buffer on the compositor queue
   with **no synchronization against the game's writes**, exactly like the sampling path. The EV-0090
   compositor log contains physically impossible snapshots of the *same* texture:
   ```
   frame 300:  provider tex L mean=(120.3,120.3,120.3) max=(255,255,255) nonBlack=1016/1024
               provider tex R mean=(0.0,0.0,0.0)        max=(0,0,0)         nonBlack=0/1024
   frame 900:  R mean=(181.0,207.0,255.0) alpha=0.0
   frames 1200/1800/2100/2700/3000/3600: R identical (181.0,207.0,255.0) alpha=0.0 while L changes every probe
   frame 4800/5400/5700/6000: R mean=(9..13, 10..14, 18) alpha=0.0 while L alpha=255.0
   ```
   (evidence/EV-0090/vrmc-compositor.log lines 332-333, 342, 347, 356, 360, 369, 374, 383, 401, 410, 414, 419.)
   These are snapshots taken mid-write / from different in-flight frames, not a property of the texture.
   Any future "provider content is Y" conclusion must be taken **behind the frame event** (§5/§6).
3. **If `vrmc-test-pattern.flag` is present and the immersive is still black, texture sampling and the whole
   bridge handoff are off the presenting path for that frame.** With the flag the compositor encodes a
   procedural pattern and never samples a provider texture; the render pass also clears to red (left) / green
   (right) before drawing. Pure black therefore means the render pass/drawable is not reaching the display.
   The current compositor **silently tolerates `[cb renderCommandEncoderWithDescriptor:]` returning nil**
   (invalid descriptor -> no clear, no draw, command buffer still "completed"). Compositor-side action: log
   `enc == nil` and the descriptor's color/depth texture nil/type/slice; also log `tex.usage` once. (Sent to
   the compositor teammate; not edited here — `runtime/native-shell/Sources` is not this task's write scope.)
4. **Thread-safety and lifetime are real defects independent of the black screen.** They can produce torn
   frames and use-after-free across a reinit; they are now fixed/covered as described here.

---

## 3. Bridge changes (additive; Java ABI v2 unchanged)

Files changed by this task:

| File | Change |
|---|---|
| `bridge/abi/vrmc_native_shared.h` | Additive API: `vrmc_shared_frame_sync`, `vrmc_shared_eye_frame`, `vrmc_shared_publish_eyes`, `vrmc_shared_acquire_eyes`, `vrmc_shared_get_frame_sync`; sync/lifetime contract documented. |
| `bridge/src/vrmc_stub.c` | Mutex-protected eye-frame publication (no torn 80-byte swaps), tracking override and display views; publish sequence + texture generation; `vrmc_submit_eyes` now publishes through the same path without a sync pair; thread-local last-error; extended stub self-test. |
| `bridge/src/vrmc_jni.c` | New JNI entry `nativeSubmitEyesSynced(..., jlong sharedEvent, jlong signalValue)` publishing the sync pair atomically with the textures; both submit paths now report the published display-view frustum instead of the symmetric 110° stub when display views exist. |
| `bridge/tests/bridge_sync_test.c` | New host test: protocol/generation/sync + concurrent producer/consumer + concurrent tracking/display views; layout static asserts; TSan-clean. |
| `bridge/tests/bridge_metal_sync_host.mm` | New host probe (real MoltenVK 1.4.2 + Metal): bridge texture export usage check, timeline semaphore -> MTLSharedEvent, foreign-thread/queue wait + shader sample across two frame values. |
| `bridge/tests/run_tests.sh` | One-command host suite (stub, sync, TSan, display-view layout, bridge build both modes, optional Metal probe). |
| `docs/analysis/bridge-sync-host-tests.log` | Captured suite log (ALL PASS). |
| `docs/analysis/bridge-sync-provider-reachability.java/.log` | Compile-time proof that the provider-side timeline-semaphore export/signal wiring needs only MC 26.2 public API (plus the `GpuDevice.backend` access-widener/reflection note). |

The Java ABI (`vrmc_abi.h`, `VRMC_ABI_VERSION == 2`, structs, existing entry points) is untouched: the
existing `vrmc_submit_eyes`/`vrmc_shared_eye_textures` pair still works exactly as before. The provider can
migrate to the synced call incrementally.

### API reference

```c
typedef struct {
    uint64_t shared_event;  /* opaque id<MTLSharedEvent> exported from a timeline VkSemaphore; 0 = none */
    uint64_t signal_value;  /* wait until signaledValue >= this before sampling */
    uint32_t frame_index;   /* provider frame index this value belongs to */
    uint32_t valid;         /* 1 = usable (shared_event, signal_value) wait pair */
} vrmc_shared_frame_sync;

typedef struct {
    vrmc_eye_targets eyes;         /* same Java ABI v2 eye struct the compositor already uses */
    vrmc_shared_frame_sync sync;   /* GPU wait target for those textures */
    uint64_t publish_sequence;     /* starts at 1, +1 per publish (0 = nothing published yet) */
    uint32_t texture_generation;   /* +1 when left/right handle or size changes */
    uint32_t reserved;
} vrmc_shared_eye_frame;

int32_t vrmc_shared_publish_eyes(const vrmc_eye_targets *targets, const vrmc_shared_frame_sync *sync);
int32_t vrmc_shared_acquire_eyes(vrmc_shared_eye_frame *out);
int32_t vrmc_shared_eye_textures(vrmc_eye_targets *out);      /* legacy, kept */
int32_t vrmc_shared_get_frame_sync(vrmc_shared_frame_sync *out);
```

Semantics:
* `vrmc_shared_publish_eyes` copies `targets` and `sync` under one mutex; `sync == NULL` (or
  `sync->valid == 0`) publishes an unsynchronized frame (`sync.valid = 0`). Publishing `valid = 1` with a
  zero event or zero value fails closed.
* `vrmc_shared_acquire_eyes` returns one coherent snapshot (textures + sync + sequence + generation).
  It fails (nonzero) until the first publish. Never blocks on the GPU.
* The bridge deliberately does **not** transport or retain Objective-C objects; the event and texture
  pointers are opaque tokens owned by the provider. See the lifetime contract in the header and §6.

### Threading fixes (detail)

* `g_frame_mutex` protects the published eye frame, publish sequence, texture generation and the
  frame-timing counter. `pthread_mutex` is used (no Objective-C dependency in the dylib).
* `g_tracking_mutex` protects the compositor -> JVM tracking override. `vrmc_shared_set_tracking` no longer
  requires `vrmc_init` first (the compositor can start before the provider, so the first poses are not
  dropped); `vrmc_init` no longer wipes a pre-init override.
* `g_display_views_mutex` was already present and is unchanged apart from documentation.
* `vrmc_last_error` is now `_Thread_local`, making the ABI comment ("valid until the next call on the same
  thread") true under the two-thread model.

---

## 4. Host verification (ALL PASS; captured log `docs/analysis/bridge-sync-host-tests.log`)

Command: `bridge/tests/run_tests.sh` (needs Xcode CLT; the Metal probe additionally needs a macOS MoltenVK
SDK at `/tmp/vrmc-host-mvk` — see the script header; it is skipped with a message otherwise).

```
=== stub-test ===                 [vrmc-stub-test] ok version=2 ... publish_seq=4 texture_gen=2    PASS
=== sync-test ===                 protocol PASS; 200000 publishes x 4 readers, 687534 acquires, 0 torn PASS
=== sync-test-tsan ===            same test with -fsanitize=thread: ALL PASS, no TSan report            PASS
=== display-views-layout ===      [display-views-layout] PASS                                         PASS
=== build-bridge ===              scripts/build_bridge.sh MODE=both: device dylib verified, 27 exported symbols PASS
                                  device sha256 38624e129544d71e6ae5919e1d510a6f0457c25c8e5604a4952b853256061d8a
=== metal-host-probe ===          [bridge-mvk] exported MTLTexture: 64x64 fmt=70 usage=0x5
                                  (ShaderRead=1 RenderTarget=1)
                                  [bridge-mvk] exported MTLSharedEvent: yes
                                  [bridge-mvk] frame 0 (wait value 5): sampled RGB=64,128,191 in a shader,
                                               event seen=5: PASS
                                  [bridge-mvk] frame 1 (wait value 6): sampled RGB=10,200,30 in a shader,
                                               event seen=6: PASS
                                  [bridge-mvk] unsynchronized publication (sync.valid=0): PASS
                                  [bridge-mvk] ALL PASS                                          PASS
[bridge-tests] ALL PASS
```

The Metal probe uses the **exact MC 26.2 VR-target VkImage usage flags**
(`SAMPLED|COLOR_ATTACHMENT|TRANSFER_SRC|TRANSFER_DST`), exports the texture through the bridge
(`vrmc_export_mtl_texture`, i.e. `vkGetMTLTextureMVK`), creates an exportable timeline VkSemaphore, clears
the image through Vulkan, signals value 5/6 **without waiting on the CPU**, publishes through
`vrmc_shared_publish_eyes`, and lets a separate pthread with its own `MTLCommandQueue` encode
`encodeWaitForEvent:value:`, shader-read the texture into an offscreen target, blit it to a shared buffer and
verify the exact pixels. `MTL_DEBUG_LAYER=1` was enabled; no Metal validation errors. This is a host gate:
it proves the protocol and the Metal usage, **not** visionOS behavior (device evidence is EV-0065's scope).

Build artifacts (not checked in): `/tmp/vrmc-bridge-tests-final/bridge-build/libvrmc_bridge.dylib` (device,
visionOS 1.0/1.0) and `libvrmc_bridge_host.dylib` (host).

### Test-dependency note
The Metal probe needs a macOS MoltenVK build (host runs Metal; the device dylib is visionOS and cannot load on
macOS). The probe was tested with MoltenVK **1.4.2** (the same version EV-0063 used; the device bundles 1.4.3).
Version difference is acceptable for a protocol/usage gate, and the device-path evidence remains EV-0065.

---

## 5. Provider-side integration

> **Status update (task-7, 2026-11-01):** implemented in `provider/`, flag-gated and OFF by default —
> see `docs/analysis/provider-gpu-sync.md` for activation, expected log lines, host tests and failure
> modes. The spec below is retained as the design/implementation reference.

### 5.1 Enable `VK_EXT_metal_objects` at device creation (one restart when first enabled)

Exportable timeline semaphores require the device extension at `vkCreateDevice` time. MC creates the Vulkan
device before VR init, and Vivecraft already has the supported mechanism (`VulkanBackendVRMixin` adds
`vrSettings.requiredVulkanDeviceExtensions` to the device extension set at creation;
`VulkanHelper.checkExtensionSupport` fails with a "restart required" RenderConfigException when the
extension is not enabled yet). In `VisionRenderer`:

```java
@Override
public void checkCapabilities() throws RenderConfigException {
    super.checkCapabilities();
    if (GraphicsHelper.INSTANCE instanceof VulkanHelper vk) {
        String ext = "VK_EXT_metal_objects";
        // Remembered in vrsettings and applied at the next device creation (one game restart).
        ClientDataHolderVR.getInstance().vrSettings.requiredVulkanDeviceExtensions = ext;
        vk.checkExtensionSupport(List.of(), List.of(ext)); // throws until enabled -> user restarts once
    }
}
```

If the extension is unavailable this launch, keep publishing unsynchronized frames (`sync = null`); the
compositor then behaves exactly as today (no wait). Log the state once, never silently.

### 5.2 Create + export the timeline semaphore -> MTLSharedEvent (once, in renderer init)

The MC 26.2 API needed here is available without a mixin or fork. This was proven by **compiling** a
provider-side snippet against the shipped `26.2.jar` + the game's LWJGL 3.4.1 jar
(`docs/analysis/bridge-sync-provider-reachability.java`, log `...-reachability.log`): **PASS**.
Public members used: `VulkanDevice.vkDevice()`, `VulkanDevice.createCommandEncoder()`,
`VulkanCommandEncoder.signalSemaphore(long vkSemaphore, long value, long stageMask)` (appends a semaphore
signal operation to the game's **current** frame submission; it does not submit by itself — do NOT call
`encoder.submit()` from `endFrame()`, that would flush MC's frame early). LWJGL 3.4.1 in the game classpath
has the `EXTMetalObjects` bindings (`VkExportMetalObjectsInfoEXT`, `VkExportMetalSharedEventInfoEXT`,
`VkExportMetalObjectCreateInfoEXT`; `mtlSharedEvent()` returns a raw `long` handle).
One access caveat: `GpuDevice.backend` is **private**; Vivecraft compiles
`RenderSystem.getDevice().backend` only because it ships `vivecraft.accesswidener`. Our provider must either
add the same access-widener entry to its own jar (cleanest) or read the field via reflection (what the
reachability probe does). Everything below the `VulkanDevice` reference is public API.

```java
private long syncSemaphore;   // raw VkSemaphore handle (address)
private long sharedEvent;     // raw id<MTLSharedEvent> handle (address), 0 = unavailable
private long syncSignalValue; // monotonic, starts at 0

private void initFrameSync() {
    if (!(GraphicsHelper.INSTANCE instanceof VulkanHelper)) return;
    VulkanDevice device = gameDevice(); // access widener or reflection; see the note above
    VkDevice vk = device.vkDevice();
    try (MemoryStack stack = MemoryStack.stackPush()) {
        VkExportMetalObjectCreateInfoEXT export = VkExportMetalObjectCreateInfoEXT.calloc(stack)
            .sType$Default()
            .exportObjectType(EXTMetalObjects.VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT);
        VkSemaphoreTypeCreateInfo type = VkSemaphoreTypeCreateInfo.calloc(stack)
            .sType$Default()
            .semaphoreType(VK12.VK_SEMAPHORE_TYPE_TIMELINE)
            .initialValue(0L);
        type.pNext(export.address());
        VkSemaphoreCreateInfo ci = VkSemaphoreCreateInfo.calloc(stack).sType$Default().pNext(type.address());
        LongBuffer out = stack.mallocLong(1);
        if (VK12.vkCreateSemaphore(vk, ci, null, out) != VK_SUCCESS) { /* log once, stay unsynchronized */ return; }
        syncSemaphore = out.get(0);

        VkExportMetalSharedEventInfoEXT seInfo = VkExportMetalSharedEventInfoEXT.calloc(stack)
            .sType$Default().semaphore(syncSemaphore);
        VkExportMetalObjectsInfoEXT exportInfo = VkExportMetalObjectsInfoEXT.calloc(stack).sType$Default();
        exportInfo.pNext(seInfo.address());
        EXTMetalObjects.vkExportMetalObjectsEXT(vk, exportInfo);
        sharedEvent = seInfo.mtlSharedEvent(); // 0 if the extension was not enabled at device creation
        if (sharedEvent == 0) VRSettings.LOGGER.warn("VRMC: MTLSharedEvent export unavailable (restart required)");
    }
}
```

### 5.3 Per frame, in `VisionRenderer.endFrame()` (after the eye targets were rendered/submitted)

```java
long lt = textureHandle(framebufferEye[0]);
long rt = textureHandle(framebufferEye[1]);
if (lt != 0 && rt != 0) {
    long value = ++syncSignalValue;
    if (sharedEvent != 0) {
        VulkanCommandEncoder encoder = ((VulkanDevice) RenderSystem.getDevice().backend).createCommandEncoder();
        // Appends "signal timeline semaphore = value" to the game's own frame submission; it fires after
        // the eye render commands and is observed by Metal as MTLSharedEvent.signaledValue.
        encoder.signalSemaphore(syncSemaphore, value, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT);
    }
    int rc = VrmcBridge.submitEyesSynced(lt, rt, (int) frameIndex, EYE_WIDTH, EYE_HEIGHT,
                                         EYE_HALF_FOV_RAD, sharedEvent, sharedEvent != 0 ? value : 0);
    ...
}
```

Java bridge additions (provider side, matching the new JNI symbol):

```java
public static native int nativeSubmitEyesSynced(long leftTexture, long rightTexture, int frameIndex,
        int width, int height, float halfFovRad, long sharedEvent, long signalValue);

public static int submitEyesSynced(long left, long right, int frameIndex, int width, int height,
        float halfFovRad, long sharedEvent, long signalValue) {
    return nativeSubmitEyesSynced(left, right, frameIndex, width, height, halfFovRad, sharedEvent, signalValue);
}
```

Fallbacks, in order of preference if `signalSemaphore`/the extension is not usable this launch:
1. publish unsynchronized (`sharedEvent = 0`) and let the compositor run without the wait;
2. if a signal must be produced out-of-band, submit a semaphore-only `VkQueueSubmit` on
   `device.graphicsQueue()` after `endFrame()` (the eye render command buffers are already enqueued by MC's
   render thread at that point). This relies on same-queue submission order rather than MC's own submission
   bookkeeping and is the less-preferred path; it is documented as a stop-gap, not the design.
3. Last resort: GPU blit/readback (S4a fallback) — not needed given the host probe.

**Ordering caveat to verify on device:** the exact guarantee that MC's frame submission (which carries the
signal op) is submitted *after* the eye render commands is an MC-internals property we could not test without
a device. The compositor-side wait makes stale-reads visible as an unchanging frame rather than corruption, so
the first device run should log `sync.valid`, `signal_value` and the acquired `publish_sequence` to confirm
values advance (see §8).

---

## 6. Compositor-side integration (NOT implemented here; `runtime/native-shell` is not my write scope)

Sent to the compositor teammate. Summary:

```c
/* resolveBridge() */
typedef int32_t (*acquire_eyes_fn)(vrmc_shared_eye_frame *);
static acquire_eyes_fn gAcquireFn;
gAcquireFn = (acquire_eyes_fn)dlsym(h, "vrmc_shared_acquire_eyes");

/* per frame */
vrmc_shared_eye_frame eyeFrame;
memset(&eyeFrame, 0, sizeof(eyeFrame));
BOOL haveEyes = (gAcquireFn != NULL && gAcquireFn(&eyeFrame) == 0 &&
                 eyeFrame.eyes.left_texture != 0 && eyeFrame.eyes.right_texture != 0);
const vrmc_eye_targets *eyes = &eyeFrame.eyes;   /* rest of the code unchanged */

/* once per frame, before the first eye render pass */
id<MTLCommandBuffer> cb = [queue commandBuffer];
if (haveEyes && eyeFrame.sync.valid) {
    id<MTLSharedEvent> ev = (__bridge id<MTLSharedEvent>)(void *)(uintptr_t)eyeFrame.sync.shared_event;
    if (ev != nil && [ev conformsToProtocol:@protocol(MTLSharedEvent)])
        [cb encodeWaitForEvent:ev value:eyeFrame.sync.signal_value];
}
```

Lifetime rules for the compositor:
* Re-acquire every frame; do not cache handles. `publish_sequence` identifies a new frame.
* Two `id<MTLTexture>` locals per frame; if you retain explicitly, release after `[cb commit]` (Metal
  retains resources referenced by a committed command buffer until it completes).
* `texture_generation` change => the provider replaced the eye targets (resize/reinit): log it and drop any
  retained/reused old textures; the old handles may be freed by the provider.
* Keep the existing `tex.device != device` guard; a one-time `tex.usage` log is the requested runtime
  capability check.
* `sync.valid == 0` means "legacy/unsynchronized publisher" — encode no wait (today's behaviour).

Provider retention requirement (keep old handles alive across reinit): after
`VisionRenderer.createRenderTexture` replaces `framebufferEye[]`, keep the previous two
`VRTextureTarget`s referenced for at least N compositor frames (e.g. N = 8, longer than the compositor's
in-flight command buffers) before `destroyBuffers()`. This closes the use-after-free window that the bridge
cannot close itself (no Objective-C retain in the bridge by design).

---

## 7. Display-view JNI layout + tracking struct audit (requested check)

**Verdict: consistent.** `bridge/src/vrmc_jni.c:nativeGetDisplayViews` packs floats only (no generation):
byte offsets **L tangents 0, L matrix 16, R tangents 80, R matrix 96, ipd 160** (164 bytes total).
`VisionVR.pollDisplayViews()` reads eye `o = eye * (4+16)*4 = eye*80`: tangents `o..o+16`, matrix
`o+16..o+80` and ipd at `40*4 = 160`. `VrmcBridge.DISPLAY_VIEWS_BYTES = (4+16+4+16+1)*4 = 164`.
The C struct `vrmc_display_views` is 168 bytes (generation@0, payload@4); the JNI capacity check accepts the
164-byte Java buffer. `scripts/tests/DisplayViewsLayoutTest.c` (EV-0090) covers this and passes in the suite
above.

Generation semantics: correct. `vrmc_shared_set_display_views` compares the payload (all bytes after
`generation`) under `g_display_views_mutex` and bumps `generation` only on change; `VisionVR` applies
only when the returned generation changes. Because eye transforms change every frame, the generation will
normally bump every frame while tracking is live — that is expected and cheap.

Tracking struct: C `sizeof(vrmc_tracking_state) == 96` = `VrmcBridge.TRACKING_BYTES = 8+28+28+28+4`;
head pose at 8, controllers at 36/64, `ipd_m` at 92 — exactly the offsets `VisionVR.poll()` reads. These
invariants are now `_Static_assert`ed in `bridge/tests/bridge_sync_test.c` so a future struct change cannot
silently desynchronize Java. (`VrmcBridge.FRAME_TIMING_BYTES = 48` over-allocates the 40-byte C struct;
harmless.)

---

## 8. Device verification plan (for the next run, when provider wiring lands)

Expected new log lines after the provider switch (and after one restart with `VK_EXT_metal_objects`
enabled):

* provider: `[VRMC-M2]` one-time sync init line: semaphore created, `sharedEvent != 0`, or the explicit
  fallback warning.
* compositor: acquire path returns `sync.valid=1`, and `signal_value` increases with
  `eyes.frame_index`/publish_sequence. Add a temporary log line:
  `[vrmc-comp] frame N acquire seq=... texgen=... sync=1 value=...`.
* If the eye image is still black with a **valid** sync wait and a forced test pattern, the remaining cause is
  presentation (render pass encoder or drawable), not the bridge.

Suggested acceptance for the sync change (host PASS is not enough): on device, the compositor and provider
both report monotonic `signal_value`, no `AUTO TEST-PATTERN` due to black readbacks, and a stable image
across at least a few thousand frames; then record it as its own EV (the Lead records evidence).

---

## 9. Limitations / honest gaps

* **Device path NOT RUN.** The provider Java wiring (§5) and compositor wiring (§6) are not implemented by
  this task; host evidence covers the bridge implementation and the Metal/Vulkan protocol only.
* The Metal host probe used MoltenVK **1.4.2** (macOS; EV-0063's version) while the device bundles **1.4.3**.
  The usage/sync mapping is the same code path, but the device gate remains EV-0065's scope.
* The exact Vulkan ordering guarantee of MC's `signalSemaphore` relative to the eye render commands in the
  same frame submission could not be verified without running the game. Fallbacks are specified in §5.3; the
  first device run must confirm values advance (§8).
* The bridge intentionally does not retain Objective-C objects; the use-after-free window across a render
  target reinit is only fully closed together with the provider's retention ring (§6).
* The new JNI entry only takes effect when the provider calls it; the legacy path still publishes
  unsynchronized frames (deliberate, so old jars keep working).

---

## 10. References

* Host suite log: `docs/analysis/bridge-sync-host-tests.log` (ALL PASS).
* S4a: `docs/mvp/S4A_FINDINGS.md`, evidence/EV-0063 (host), evidence/EV-0065 (device).
* Device-run logs analysed: `evidence/EV-0090/vrmc-compositor.log`, `evidence/EV-0091-fresh/`.
* MC 26.2 class evidence (shipped `26.2.jar`, javap): `com.mojang.blaze3d.pipeline.RenderTarget`
  (`createBuffers`: color/depth `createTexture(..., 15, ...)`), `com.mojang.blaze3d.vulkan.VulkanConst`
  (`textureUsageToVk`), `com.mojang.blaze3d.vulkan.VulkanGpuTexture` (uses `textureUsageToVk`),
  `com.mojang.blaze3d.vulkan.VulkanCommandEncoder` (`signalSemaphore(long,long,long)`,
  `waitSemaphore`, `execute`, `submit`), `com.mojang.blaze3d.vulkan.VulkanDevice` (`vkDevice()`,
  `createCommandEncoder()`, `graphicsQueue()`).
* Display-view layout: `scripts/tests/DisplayViewsLayoutTest.c` (EV-0090), rerun in the suite above.
* Provider API reachability (compile PASS): `docs/analysis/bridge-sync-provider-reachability.java` +
  `docs/analysis/bridge-sync-provider-reachability.log`.
