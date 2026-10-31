# Provider (Vivecraft companion mod)

**Status:** not started. S3, then E-series and F/G input.

LGPL-3.0 Fabric mod that integrates VRMC with Vivecraft without forking it: it Mixins the provider
selection in `VRState.initializeVR` and implements `VisionVR extends MCVR` plus a
`VRRenderer` that submits eye targets to the native bridge.

Planned contents:

- `src/main/java/.../VisionVR.java` — provider: init/poll/processInputs, poses, IPD, play area.
- `src/main/java/.../VisionRenderer.java` — eye targets, projection, submission hook.
- `src/main/java/.../VisionInput.java` — action data for Vivecraft's action sets.
- `src/main/resources/` — mixin config, `provider.json` mapping profile.
- `LICENSE` — LGPL-3.0 (present).

Rules:

- Separate, replaceable artifact; source published (ADR-0004, ADR-0006).
- Version-locked to Vivecraft 26.2-1.3.15; fail closed on mismatch.
- S3 must evidence the injection point in the decompiled jar and across 26.2.x before M2 hardens;
  the fork fallback is decided at M0 exit.
- No SteamVR/OpenVR dependency; no OpenXR assumption.
