# S4a findings — Vulkan→Metal eye-texture handoff (M2, started 2026-11-01)

Question (from `M2_PLAN.md` §4): can the native bridge obtain both eye images rendered by Minecraft's
Vulkan backend (MoltenVK) without a full GPU copy, and what synchronization is needed?

## Evidence so far (static, from the shipped MoltenVK 1.4.3 dylib)

`Amethyst-1.2.0 / libMoltenVK.dylib` (`sha256 03198606…`) exports / references:

- `VK_EXT_metal_objects` (plus `VK_EXT_external_memory_metal`, `VK_EXT_external_memory_host`)
- `vkGetMTLDeviceMVK`, `vkGetMTLCommandQueueMVK`, `vkGetMTLBufferMVK`, `vkGetMTLTextureMVK`,
  `vkSetMTLTextureMVK` (export **and** import of `MTLTexture`)
- IOSurface-backed texture creation (`newTextureWithDescriptor:iosurface:plane:`) and
  `MTLSharedTextureHandle`
- `VK_KHR_timeline_semaphore`, `VK_KHR_synchronization2`, `MTLSharedEvent`

**Reading:** the MoltenVK build shipped in the launcher supports Metal-object export/import and shared
events. The preferred path is:

1. MC's Vulkan renderer renders each eye into a `VkImage` backed by a `MTLTexture`.
2. The provider asks MoltenVK for the `MTLTexture` (`vkGetMTLTextureMVK` / `vkGetMemoryMetalHandle`).
3. The bridge hands the two `MTLTexture`s to the compositor path (M3) or samples them now; frame
   completion is signalled with a `MTLSharedEvent` / timeline semaphore so the compositor does not
   sample in-flight work.

Fallback if runtime capability checks fail on visionOS (e.g. iOS restrictions on exporting textures):
**GPU blit** from each eye image into an app-owned `MTLTexture` (`vkCmdBlitImage` to an imported image,
or a Metal compute/blit pass on the exported handle). Cost: one full-screen copy per eye per frame;
acceptable for M2, revisit in S6 perf.

## Host gate result — PASS (EV-0063)

Host spike (`runtime/probes/s4a-host/spike_s4a.mm`, macOS MoltenVK 1.4.2) proved the path:

- `VK_EXT_metal_objects` present; `MTLDevice` export works.
- Exportable `VkImage` → `MTLTexture` (RGBA8Unorm, 64×64); Vulkan clear to red; Metal readback
  `255,0,0,255` — pixels correct.
- **Shared-event sync:** `MTLSharedEvent` export works only for a **timeline** `VkSemaphore`
  (`VK_SEMAPHORE_TYPE_TIMELINE`, timelineSemaphore feature). A binary semaphore exports `nil`.
  Signaled value 42 from Vulkan was observed by `MTLSharedEvent`.

## Device gate result — PASS (EV-0065)

The in-app probe (`runtime/probes/s4a-device/`, triggered by `Documents/vrmc_s4a_device.flag`) ran on
D1 with the **bundled MoltenVK 1.4.3**:

- `VK_EXT_metal_objects` present; `MTLDevice` export works.
- `VkImage` → `MTLTexture` export works (64×64 RGBA8Unorm); Metal readback of the Vulkan red clear
  = `255,0,0,255`.
- Timeline `MTLSharedEvent` export + Vulkan signal(42) visible to Metal.

Both S4a gates PASS. This is the zero-copy eye-texture/compositor substrate for M3 (M3 itself remains
NOT RUN).

## Gates (separate — host PASS does not imply device PASS)

- **S4a-host:** macOS MoltenVK export + `MTLSharedEvent` sync works; pixels correct.
- **S4a-device:** the same path works on visionOS (separate EV required).

## Next steps (host, then device)

1. Host spike with MoltenVK on macOS: create a `VkImage`, export its `MTLTexture`, render into it from
   Metal/RenderTarget and sample it; verify no validation errors and correct pixels.
2. Repeat with the **iOS** MoltenVK binary in a visionOS app (capability check at startup:
   `VK_EXT_metal_objects` in device extensions; fail over to blit path if absent).
3. Record EV with spike code + images/hashes; then wire `vrmc_submit_eyes` and the JNI binding (M2-W4).

## Caveat

Static symbol presence does not prove runtime availability on visionOS; the spike's first gate is a
runtime capability check on a real device (or visionOS simulator where possible). Do not harden the
renderer before that.
