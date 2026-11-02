# Provider-side GPU eye-frame sync — flag-gated implementation (task-7)

**Owner:** bridge-sync (task-7)
**Date:** 2026-11-01
**Scope:** `provider/` (implementation + host tests) and `docs/analysis/`. Java ABI v2 unchanged; bridge and
`runtime/native-shell` untouched.
**Status:** **host PASS** (flag parsing, fallback, reflection plumbing, real MoltenVK semaphore + event
export); **device path NOT RUN**. Off by default.

---

## 1. What was implemented

The provider-side half of the zero-copy eye handoff proven in task-4 (see `docs/analysis/bridge-sync.md`):
the JVM provider now creates its own exportable timeline `VkSemaphore` on the game's MoltenVK device,
exports its `MTLSharedEvent` via `VK_EXT_metal_objects`, appends a monotonically increasing
signal to MC 26.2's **own** frame submission, and publishes the `(event, value)` pair to the bridge
atomically with the eye textures. The CompositorServices renderer can then wait on that exact GPU frame
before sampling the eye textures.

Everything is **off unless explicitly requested** and every step degrades gracefully to the existing
unsynchronized `submitEyes` path (the game must keep running).

### 1.1 Files

| File | Purpose |
|---|---|
| `provider/src/main/java/dev/vrmc/provider/GpuSyncFlags.java` | Pure flag logic (no game imports, host-testable): `<gameDir>/vrmc-gpu-sync.flag` or `-Dvrmc.gpuSync=1`; explicit `0/false/…` overrides the flag file. |
| `provider/src/main/java/dev/vrmc/provider/VkReflect.java` | Package-private reflection shim: builds the `VkExportMetalObjectCreateInfoEXT` + `VkSemaphoreTypeCreateInfo` + `VkSemaphoreCreateInfo` chain, calls `vkCreateSemaphore`/`vkExportMetalObjectsEXT`/`vkDestroySemaphore`. Zero compile-time LWJGL dependency (the provider build has no LWJGL jars; the running game does). Optional trace: `-Dvrmc.gpuSync.debug=true`. |
| `provider/src/main/java/dev/vrmc/provider/GpuEyeSync.java` | Enable/disable lifecycle: flag check, Vulkan-backend detection, extension-enabled check + restart request, semaphore/event creation, per-frame signal, fallback warnings, close. |
| `provider/src/main/java/dev/vrmc/provider/VisionRenderer.java` | Resolves the sync once in the constructor; `endFrame()` signals through MC's encoder then uses `VrmcBridge.submitEyesSynced(...)`; falls back per-frame/bridge-compat; `destroy()` destroys the semaphore. |
| `provider/src/main/java/dev/vrmc/provider/bridge/VrmcBridge.java` | Additive `nativeSubmitEyesSynced(...)` + `submitEyesSynced(...)` wrapper (the JNI symbol exists in the task-4 bridge build; Java ABI version and all `vrmc_abi.h` structs unchanged). |
| `provider/tests/run_tests.sh` | Host suite (see §4). |
| `provider/tests/GpuSyncFlagsTest.java` | Pure flag-semantics test. |
| `provider/tests/dev/vrmc/provider/GpuEyeSyncFallbackTest.java` | `tryEnable` contract: never throws, requested-but-unavailable returns null after one warning, off path silent. |
| `provider/tests/dev/vrmc/provider/VkReflectSmokeTest.java` | Reflection plumbing with/without LWJGL (live vs fail-closed). |
| `provider/tests/dev/vrmc/provider/GpuSyncVulkanHostTest.java` | Real MoltenVK (macOS): reflective `vkCreateSemaphore` + `vkExportMetalObjectsEXT` returns a non-zero timeline semaphore **and** a non-zero `MTLSharedEvent`; `vkDestroySemaphore` works. |
| `docs/analysis/provider-gpu-sync-host-tests.log` | Captured host suite log (ALL PASS). |

### 1.2 Activation (off by default)

Enable for one launch with either:

1. **Game-directory flag** — on device, the Minecraft game dir is
   `Documents/instances/default/` inside the app data container:

   ```
   printf 1 > /tmp/vrmc-gpu-sync.flag
   xcrun devicectl device copy to --device <D1-UDID> \
     --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc \
     --source /tmp/vrmc-gpu-sync.flag \
     --destination Documents/instances/default/vrmc-gpu-sync.flag
   ```

2. **JVM property** `-Dvrmc.gpuSync=1` (if the launcher passes JVM args). `-Dvrmc.gpuSync=0` explicitly
   disables even when the flag file exists (useful to A/B the same install without deleting the flag).

To disable again, delete `Documents/instances/default/vrmc-gpu-sync.flag` (or launch with
`-Dvrmc.gpuSync=0` for that run). `-Dvrmc.gpuSync.debug=true` adds reflection tracing.

**First launch needs one restart:** `VK_EXT_metal_objects` must be enabled at `vkCreateDevice` time, which
has already happened by the time VR starts. On a flagged launch where the extension is not enabled, the
provider logs one warning, records `VK_EXT_metal_objects` in
`ClientDataHolderVR.vrSettings.requiredVulkanDeviceExtensions` and calls `saveOptions()` (the same mechanism
`OpenVRStereoRenderer` uses; `VulkanBackendVRMixin` adds the setting to the next device creation), then
uses the unsynchronized path for that launch. Quit to the launcher and start the game again; the second
launch enables the sync path.

---

## 2. Expected device log lines (flag ON)

First launch (extension not enabled yet, one warning, game keeps running):
```
[VRMC-M2][gpu-sync] WARNING: VK_EXT_metal_objects is not enabled on the current Vulkan device; requested it
  in VRSettings for the next launch (ONE GAME RESTART required, the setting is saved now). Falling back to
  unsynchronized eye submission for this launch.
```

Second launch (extension enabled at device creation):
```
[VRMC-M2][gpu-sync] ENABLED: timeline VkSemaphore=0x... -> MTLSharedEvent=0x...; each endFrame() ends with
  signalSemaphore(value) on MC's own frame submission and submitEyesSynced(event,value); first wait value=1
[VRMC-M2][gpu-sync] first frame signaled through MC's submission: value=1
[VRMC-M2][gpu-sync] frame 1 using synced submit: event=0x... waitValue=1
```
Then `value` rises once per rendered frame in the `first frame signaled`-style trace (only the first is
logged at INFO; add `-Dvrmc.gpuSync.debug=true` for per-call tracing). The compositor side should show its
own acquire line with `sync.valid=1` and the same increasing value (if the compositor build logs it).

Failure fallbacks (each is one warning; the game keeps rendering):
```
[VRMC-M2][gpu-sync] WARNING: enable failed: <ExceptionClass> (<message>); falling back to unsynchronized eye submission
[VRMC-M2][gpu-sync] WARNING: backend is not Vulkan (backend=...); falling back to unsynchronized eye submission
[VRMC-M2][gpu-sync] WARNING: LWJGL Vulkan classes not reachable by reflection; falling back to unsynchronized eye submission
[VRMC-M2][gpu-sync] WARNING: GpuDevice.backend is not reachable by reflection; falling back to unsynchronized eye submission
[VRMC-M2][gpu-sync] WARNING: bridge dylib has no nativeSubmitEyesSynced (...); falling back to unsynchronized eye submission
[VRMC-M2][gpu-sync] WARNING: disabling GPU sync for the rest of this renderer: ...; reverting to unsynchronized eye submission
```
When the flag is absent there are **no** `[gpu-sync]` lines at all.

---

## 3. Design / integration details

* **One semaphore per renderer.** Created in `GpuEyeSync.tryEnable` from
  `GpuEyeSync.tryEnable(Minecraft.gameDirectory)` in the `VisionRenderer` constructor; destroyed in
  `VisionRenderer.destroy()` (Vivecraft's `VRState` calls `vrRenderer.destroy()`). The game's VkDevice comes
  from the private `GpuDevice.backend` field (Vivecraft itself reads it via `vivecraft.accesswidener`; the
  provider uses reflection so the jar builds without new access-widener plumbing — see
  `docs/analysis/bridge-sync-provider-reachability.java`).
* **Signal on MC's own submission.** `GpuEyeSync.signalOnGameFrameSubmit(value)` calls
  `VulkanCommandEncoder.signalSemaphore(semaphore, value, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT)` on
  `VulkanDevice.createCommandEncoder()`. That appends a semaphore signal to MC's current frame submission —
  it does **not** submit. `VisionRenderer.endFrame()` is called after the eye passes (VRPassHelper), so the
  signal rides the game's frame submit instead of creating a competing queue submission.
* **Publish atomically.** The same `endFrame()` calls
  `VrmcBridge.submitEyesSynced(lt, rt, frameIndex, w, h, halfFov, event, value)`; the bridge publishes
  textures + sync pair under one mutex (task-4), so the compositor can never observe a mixed frame.
* **Value lifetime.** Values start at 1 (semaphore/event initial 0) and increase by one per submit. The
  compositor must wait `encodeWaitForEvent:event value:value` before sampling the textures of that same
  published frame. If the published frame is sampled again later, the same wait is instantly satisfied.
* **No behaviour change when off.** The only added work is the one-time flag check in the renderer
  constructor; `endFrame` stays on the exact previous code path.

---

## 4. Host verification (ALL PASS; `docs/analysis/provider-gpu-sync-host-tests.log`)

`provider/tests/run_tests.sh`:
```
=== build-provider ===   scripts/build_provider.sh: 8 classes / 7 sources, jar + sha256, exit 0   PASS
=== flag-test ===        off by default; flag file; -Dvrmc.gpuSync=1/true/yes/on; 0/false override;   PASS
                         null game dir; no cross-directory leakage
=== fallback-test ===    no flag -> null silently; flag file -> warning + null; -Dvrmc.gpuSync=1 ->   PASS
                         warning + null (GpuEyeSync.tryEnable never throws)
=== vkreflect-smoke ===  without LWJGL -> UnavailableException (fail closed); with LWJGL 3.4.1 ->      PASS
                         structs/constants resolve (sharedEventBit=32 timeline=1 success=0
                         allCommands=0x10000)
=== vulkan-host-test === real macOS MoltenVK 1.4.2: reflective vkCreateSemaphore with the export     PASS
                         chain -> non-zero timeline VkSemaphore + non-zero MTLSharedEvent;
                         vkDestroySemaphore ok
[provider-tests] ALL PASS
```
Provider jar identity (the jar tool stamps META-INF with the build time, so sha256 changes every build —
use the number printed by the build command that stages the jar):
`27711 bytes, sha256 e.g. 87b8fdc21846b9959ff3444ab4838ccd067f85944b6706fbb6cd5f0cd2138ee7` (captured log run).

Two bugs were caught by these host tests before any device run:
1. heap `LongBuffer` for `vkCreateSemaphore`'s output caused a SIGSEGV inside MoltenVK (LWJGL passes the
   buffer address straight to the driver; fixed by using a direct buffer) — a crash the device run would
   have shown as a mysterious app kill at VR start;
2. the reflection path must fail closed with a clear exception when LWJGL is not on the classpath.

---

## 5. Failure modes and limitations

* **Extension not enabled this launch** → one warning + unsynchronized path; request persisted for the next
  launch (one game restart). No abort, no VR-init failure.
* **MC API/reflection change** (future MC patch) → `enable failed` warning + unsynchronized path.
* **Bridge without the new JNI symbol** → `UnsatisfiedLinkError` caught on first synced submit; the renderer
  reverts permanently to `submitEyes` for that session.
* **Signal never submitted**: if `signalSemaphore` appends the op but MC's frame submission is dropped
  (should not happen in normal play), the compositor's wait on that value could stall GPU work. The
  flag-gated, operator-supervised test is the mitigation; an `AUTO TEST-PATTERN`/black screen with a
  compositor-side "wait value = X" log is the observable symptom, and removing the flag restores today's
  behaviour.
* **Ordering assumption (device-only):** that MC's frame submission containing the signal is submitted after
  the eye render passes is an MC-internals property we cannot test on the host. The first device run must
  confirm the compositor's acquired `sync.valid/value` advance with the provider's logged values (see §2).
* **Device path NOT RUN.** No install/launch was performed. Host evidence covers flag/fallback/reflection
  and real-MoltenVK semaphore creation + `MTLSharedEvent` export; it does not cover visionOS, MC's encoder
  call site, or the compositor wait.
* If the compositor build cannot consume the sync yet, the published pair is simply ignored (the bridge's
  legacy accessor still works); there is no compatibility risk.
