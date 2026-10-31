# ADR-0003 — Graphics path: Minecraft Vulkan via MoltenVK

**Status:** Accepted (2026-10-31)
**Related:** S2; ADR-0002; AGENT §3.1, §4.5; `VERIFY.md` ST-S2

## Context

visionOS exposes only Metal. Minecraft 26.2's OpenGL renderer cannot run directly; the options are
GL translation (LTW → ANGLE) or Minecraft's experimental Vulkan renderer through MoltenVK. MoltenVK
supports visionOS builds and Vulkan 1.3; the prior-art app uses the ANGLE path. Vivecraft already
has a Vulkan render helper (`VulkanHelper`, Vulkan mixins), and a Vulkan path gives us Metal texture
handles for the CompositorServices handoff via MoltenVK/Metal interop.

## Decision

Primary path: **MC Graphics API = Prefer Vulkan → MoltenVK (visionOS build) → Metal.**

- No native Metal `GpuDevice` for Minecraft in the MVP.
- Fallback only if S2 fails: GL/LTW → ANGLE → Metal (prior-art-compatible), with an ADR update.
- Eye textures are consumed from the same MoltenVK device for the compositor; interop mechanism
  (Metal object export vs GPU blit) is an S4 decision.

## Consequences

- S2 becomes a hard M0 gate; MoltenVK feature coverage (push descriptors, dynamic rendering,
  timeline semaphores) must be verified against MC's usage.
- One translation layer instead of two; Vulkan resource semantics are closer to the compositor's
  Metal expectations than GL.
- Risk: MC 26.2's Vulkan backend is experimental and may use features MoltenVK lacks; the GL
  fallback carries more integration work and a second graphics path to maintain.
- MoltenVK is Apache-2.0; notices required; pin recorded in `versions.env`.

## Alternatives considered

- **GL/LTW → ANGLE as primary.** Rejected: no direct Metal texture handoff, extra shim layer, and
  ANGLE visual fidelity/perf risk on visionOS; kept as fallback.
- **Native Metal renderer for Minecraft.** Rejected: years of work, out of scope.
- **Zink → MoltenVK.** Rejected: unproven on visionOS, another Mesa layer.
