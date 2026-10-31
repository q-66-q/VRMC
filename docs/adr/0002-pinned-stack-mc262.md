# ADR-0002 — Pin Minecraft 26.2 / Fabric 0.19.3 / Vivecraft 26.2-1.3.15

**Status:** Accepted (2026-10-31)
**Related:** ADR-0003; `versions.env`; AGENT §5; `VERIFY.md` §2.2

## Context

Vivecraft 26.2-1.3.15 declares `fabric_mc_range=["26.2.x"]`; it is not compatible with 26.3 or the
26.4 snapshots. Minecraft 26.2 uses Java 25 and LWJGL 3.4.1, and ships an **experimental Vulkan
renderer** (Vulkan 1.2, dynamic rendering, push descriptors) behind a Graphics API setting.
Minecraft 26.3 moves to LWJGL 3.4.3 + SDL; 26.4 snapshots make Vulkan the default. A moving target
makes an already-risky platform port untestable.

## Decision

MVP supports exactly:

- Minecraft Java **26.2** (release)
- Fabric loader **0.19.3**
- Vivecraft **26.2-1.3.15** (LGPL-3.0)
- Java **25** (`java-runtime-epsilon` upstream)
- LWJGL **3.4.1**

Pins live in `versions.env`. The launcher shows other versions but blocks them with an
"unsupported until Vivecraft updates" message. A pin change requires a new ADR and re-running the
affected spikes.

## Consequences

- Deterministic behavior and one testable matrix for M0–M6.
- No 26.3/26.4 support until Vivecraft publishes a compatible build; users on newer versions are
  out of luck for the MVP.
- The Vulkan backend is experimental even on desktop; this is a known risk tracked by S2.
- Moving to a later version later will also move the graphics baseline (Vulkan default, SDL), so it
  is a new integration project, not a version bump.

## Alternatives considered

- **26.3/26.4.** Rejected: Vivecraft incompatible; also changes LWJGL/SDL and the renderer default.
- **Multiple versions in MVP.** Rejected: multiplies the platform surface; defer to P1.
