# Bridge (native VR bridge)

**Status:** ABI **v2** implemented 2026-11-01: `abi/vrmc_abi.h` (fail-closed), `abi/vrmc_native_shared.h`
(native app-side shared surface, outside the Java ABI contract), `src/vrmc_stub.c` (deterministic fake
tracking + atomic eye-frame publication; host-only), `src/vrmc_jni.c` (JNI shim for
`dev.vrmc.provider.bridge.VrmcBridge`). Host build/test: `bridge/tests/run_tests.sh` (stub self-test,
frame-handoff protocol + ThreadSanitizer concurrency test, display-view layout test,
`scripts/build_bridge.sh MODE=both`, optional real MoltenVK+Metal shared-event host probe). Real
ARKit/Metal bridge + CompositorServices is M3.

ObjC++/C layer between the JVM provider and visionOS frameworks, and the owner of the frame handoff
to CompositorServices.

Contents:

- `abi/` — versioned Java C ABI (`vrmc_init`, `vrmc_get_tracking`, `vrmc_poll_input`,
  `vrmc_submit_eyes`, `vrmc_export_mtl_texture`, `vrmc_frame_timing`, `vrmc_recenter`,
  `vrmc_haptic`) and the additive native-shared surface (`vrmc_shared_eye_textures`,
  `vrmc_shared_set_tracking`, `vrmc_shared_set_display_views`, `vrmc_shared_publish_eyes`,
  `vrmc_shared_acquire_eyes`, `vrmc_shared_get_frame_sync`).
- `src/` — stub/shared-state implementation + JNI shim.
- `tests/` — `bridge_sync_test.c` (protocol, texture generation, publish_sequence, TSan concurrency),
  `bridge_metal_sync_host.mm` (real MoltenVK 1.4.2 + Metal: exported MTLTexture ShaderRead usage,
  timeline VkSemaphore -> MTLSharedEvent wait ordering on a foreign thread/queue), `run_tests.sh`.
- Still planned: `tracking/` (ARKit WorldTrackingProvider + 27-joint HandTrackingProvider),
  `compositor/` (LayerRenderer setup, frame pacing), `graphics/` (the real device bridge object that
  owns the provider-side exportable timeline semaphore described in `abi/vrmc_native_shared.h`).

Rules:

- The Java ABI is versioned and fails closed on mismatch; no silent fallback. Additive changes live in
  `vrmc_native_shared.h` and do not need an ABI bump.
- Frame submission must respect `presentationDeadline`; a missed frame is a defect, not a warning.
- Any behavior change to the ABI or handoff requires an ADR update and S4 re-run.
- The eye-frame handoff is **not** safe to sample without the published `(MTLSharedEvent, value)` pair.
  See `docs/analysis/bridge-sync.md` for the threading/lifetime/synchronization contract and the exact
  provider/compositor wiring.
