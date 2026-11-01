# ADR-0009 — macstream as a tracked external reference (design + partial port)

**Status:** Accepted (2026-11-01)
**Related:** AGENT §1.4/§5/§10.4/§11; `docs/mvp/MACSTREAM_REFERENCE.md`; `docs/mvp/M2_PLAN.md` §1b/§2;
EV-0059/EV-0060; ADR-0004 (provider split), ADR-0006 (licenses)

## Context

M2 needs a proven "no OpenVR" Vivecraft backend. The external project **macstream**
(`/Volumes/Untitled/Projects/macstream`) already has a working end-to-end build of exactly that
concept: a forked Vivecraft with a `RemoteVR` MCVR provider, a custom stereo renderer, a JNI bridge,
a synthetic-pose harness and ALVR streaming. The user directed us to use it as a reference.

macstream is **LGPL-3.0** (Vivecraft derivative). Its upstream commit is
`ec5a851c066856b0a3ca3eadc530d5ea18e88930` (2026-10-24, Phase 9 S9.1 complete). Our provider is also
LGPL-3.0 and ships separately from the GPL launcher (ADR-0004/ADR-0006), so adapting code into the
provider is license-compatible.

## Decision

1. **macstream is a tracked external reference** (not a dependency, not vendored). Its absolute path and
   upstream commit are recorded in AGENT §5/§10.4 and `docs/mvp/MACSTREAM_REFERENCE.md`.
2. **Design + partial port into the LGPL provider:** `VisionVR`, `VisionRenderer` and the bridge wiring
   contain code/design derived from macstream's `RemoteVR`/`RemoteVRStereoRenderer` (LGPL-3.0, upstream
   commit `ec5a851c…`). This is recorded in `docs/mvp/MACSTREAM_REFERENCE.md` §4 and M2_PLAN §1b.
3. **No macstream-derived code in the GPL launcher.** The provider remains a separate replaceable
   artifact with LGPL-3.0 notices.
4. **Update rule:** when we refresh the reference (or port more code), update the recorded upstream
   commit and the derivation statement in the same commit.
5. macstream's `RemoteVR` backend also validates our architecture choice (no SteamVR/OpenVR runtime,
   custom `MCVR`/`VRRenderer`); its GL texture-id handoff is **not** portable to our Vulkan path and is
   replaced by the S4a Metal-handle work (S4a-host and S4a-device are separate gates).

## Consequences

- License compliance is explicit: LGPL provider, notices, no code in the GPL app; no new dependency to
  build or ship.
- We gain a proven reference for provider init/pose/renderer structure and a synthetic-pose harness.
- We must not claim macstream code as original; the derivation statement is part of the compliance
  record.
- If later we decide to adopt its fork approach instead of the Mixin, a new ADR is required (that would
  change the provider injection strategy, ADR/S3 decision).
