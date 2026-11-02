# Provider (Vivecraft companion mod)

**Status:** M2 in progress 2026-11-01. Host harness PASS (EV-0060): bridge ABI v1 handshake, `VisionVR.init()` success, stereo eye targets and per-frame `vrmc_submit_eyes` on desktop Fabric (GL texture ids). VisionVR/VisionRenderer structure is adapted from macstream's proven RemoteVR backend (`docs/mvp/MACSTREAM_REFERENCE.md`). Next: S4a Metal-handle path + device bring-up (M2-W6).

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
## Flag-gated GPU eye-frame sync (off by default)

The provider can hand the compositor a GPU timeline sync pair for the zero-copy eye handoff: one
exportable timeline `VkSemaphore` on the game's MoltenVK device, its `MTLSharedEvent` exported through
`VK_EXT_metal_objects`, signalled once per frame through MC's own `VulkanCommandEncoder` submission and
published to the bridge with `VrmcBridge.submitEyesSynced` (bridge native-shared API; Java ABI v2
unchanged). Any failure logs one warning and falls back to the existing unsynchronized `submitEyes` path.

* Enable: `vrmc-gpu-sync.flag` in the Minecraft game directory, or `-Dvrmc.gpuSync=1`.
  `-Dvrmc.gpuSync=0` force-disables; `-Dvrmc.gpuSync.debug=true` traces the reflection path.
* `VK_EXT_metal_objects` must be enabled at device creation: the first flagged launch requests it in
  `VRSettings.requiredVulkanDeviceExtensions` (same mechanism as `OpenVRStereoRenderer`), saves settings
  and falls back, so ONE GAME RESTART is needed before the sync path can activate.
* Host tests: `provider/tests/run_tests.sh` (flags, fallback, reflection plumbing, real MoltenVK
  semaphore + `MTLSharedEvent` export).
* Full design, device procedure and expected log lines: `docs/analysis/provider-gpu-sync.md`.
* Status: host PASS; device path NOT RUN. The compositor only needs to wait when the acquired frame has
  `sync.valid != 0` (see `docs/analysis/bridge-sync.md`).
