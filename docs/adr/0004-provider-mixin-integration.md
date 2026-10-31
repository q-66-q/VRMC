# ADR-0004 — Vivecraft provider integration via companion Mixin mod

**Status:** Accepted (2026-10-31), injection decision due at M0 exit
**Related:** S3; AGENT §3.5, §6; `VERIFY.md` ST-S3; ADR-0006

## Context

Vivecraft is ~95% runtime-agnostic: the VR runtime sits behind `MCVR` (14 abstract members) and
`VRRenderer` (6), with OpenVR-specific code confined to `MCOpenVR`/`OpenVRStereoRenderer` and ten
LWJGL mixins (~4.4% of the mod). But Vivecraft exposes **no public provider-replacement API**
(`VRClientAPI` is read-only), and provider selection is an internal `if` in
`VRState.initializeVR` (`OPENVR` → `MCOpenVR`, otherwise `NullVR`). There is no OpenXR backend.

We need a visionOS provider (`VisionVR`) plus a renderer that submits to CompositorServices, while
keeping Vivecraft replaceable and updateable.

## Decision

1. **Default: Vivecraft stays unmodified.** Ship a separate **LGPL-3.0** companion mod that Mixins
   `VRState.initializeVR` to instantiate `VisionVR` and select our renderer. The mod depends on
   Vivecraft classes but is distributed as its own jar with source.
2. **S3 must prove the injection point** against the decompiled 26.2-1.3.15 jar and show it is
   stable across 26.2.x patch versions, not just that it worked once.
3. **Fork fallback:** if S3 shows the Mixin is unstable or insufficient, fork Vivecraft under
   LGPL-3.0 via a new ADR, publish source + rebase strategy, and re-baseline M2. The decision is
   made at the **M0 exit gate**, not deferred to M2.
4. Provider/renderer code that touches Vivecraft internals lives only in `provider/` (LGPL-3.0).

## Consequences

- Keeps Vivecraft's gameplay logic (locomotion, bow, climbing, GUI, trackers) instead of
  reimplementing it.
- The companion jar is version-coupled to the pinned Vivecraft; the launcher enforces a
  compatibility check and fails closed on mismatch.
- Mixin fragility across Vivecraft patches is a real risk; S3's stability criterion and the
  launcher's version guard are the mitigations.
- LGPL source-publication and replaceability obligations must be met for every release.

## Alternatives considered

- **Fork-only.** Rejected as the default: heavier maintenance and drift; retained as the fallback.
- **OpenVR shim (`libopenvr_api` reimplementation).** Rejected for MVP: larger C ABI surface and
  no advantage over a provider subclass; revisited only if Mixin fails.
- **OpenXR backend.** Rejected: Vivecraft has no OpenXR implementation, and visionOS has no
  OpenXR runtime.
