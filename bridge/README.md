# Bridge (native VR bridge)

**Status:** not started. S4/S5.

ObjC++/C layer between the JVM provider and visionOS frameworks, and the owner of the frame handoff
to CompositorServices.

Planned contents:

- `abi/` — versioned C ABI (`vrmc_init`, `vrmc_get_head_pose`, `vrmc_poll_input`,
  `vrmc_submit_eyes`, `vrmc_frame_timing`, `vrmc_recenter`, `vrmc_haptic`) and shared structs.
- `tracking/` — ARKit `WorldTrackingProvider` (predicted device anchor) and
  `HandTrackingProvider` (27 joints); `AccessoryTrackingProvider` + GameController for PSVR2.
- `compositor/` — `LayerRenderer` setup, per-eye drawables, projection, foveation, frame pacing.
- `graphics/` — MoltenVK eye-texture interop (Metal object export or GPU blit) and synchronization.
- `tests/` — ABI/version handshake and pose-conversion tests (AT-005).

Rules:

- The ABI is versioned and fails closed on mismatch; no silent fallback.
- Frame submission must respect `presentationDeadline`; a missed frame is a defect, not a warning.
- Any behavior change to the ABI or handoff requires an ADR update and S4 re-run.
