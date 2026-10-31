# VRMC — Minecraft VR on Apple Vision Pro

VRMC runs **Minecraft: Java Edition 26.2 + Fabric + the real Vivecraft mod** natively on Apple
Vision Pro, with head-tracked stereo, hand-tracked input, and PlayStation VR2 Sense controllers
when present. No PC, no streaming.

> **Status: M0 (specification, spikes, and skeleton).** No product build exists yet. Status claims
> are governed by [`VERIFY.md`](VERIFY.md); the operating manual is [`AGENT.md`](AGENT.md).
> Current gate: S1 (JIT internal reproduction) and S2 (MC 26.2 Vulkan on MoltenVK) are `NOT RUN`;
> S3 (provider injection decision) is `NOT RUN`.

## What is decided

- **Runtime:** on-device JVM with JIT, Amethyst-derived (GPL-3.0), sideload distribution.
- **Pinned stack:** Minecraft **26.2** (Java 25, LWJGL 3.4.1, experimental Vulkan), Fabric
  **0.19.3**, Vivecraft **26.2-1.3.15**.
- **Graphics:** MC "Prefer Vulkan" → MoltenVK → Metal. Fallback: GL/LTW → ANGLE.
- **VR integration:** an LGPL companion mod Mixins Vivecraft's provider selection and implements
  `MCVR`/`VRRenderer` for CompositorServices; Vivecraft stays unmodified unless S3 proves Mixin
  injection unstable.
- **Input:** PSVR2 Sense first-class, hand gestures as fallback, per-hand takeover.
- **Evidence:** every `PASS` needs an entry in [`VERIFY.md`](VERIFY.md) §6. Simulator is never
  evidence for hands, stereo optics, thermals, or latency.

## Quick start (M0 tooling)

```bash
./scripts/check_versions.sh      # toolchain + reference pin check (read-only)
./scripts/bootstrap.sh           # local dirs + checks + next steps
./scripts/log_evidence.sh --title "example" --dry-run
```

These scripts are implemented and self-tested; the product build scripts are not written yet.

## Layout

| Path | Purpose |
|---|---|
| `AGENT.md` | Operating manual: architecture, hardness register, spikes, milestones, rules |
| `VERIFY.md` | Acceptance criteria, test suites, evidence log |
| `docs/adr/` | Architecture decision records |
| `docs/mvp/` | MVP scope, spike procedures, acceptance guide |
| `scripts/` | Tooling (version check, bootstrap, evidence logging) |
| `launcher/` | visionOS launcher app (not started) |
| `runtime/` | JVM/JIT runtime build (not started) |
| `provider/` | Vivecraft companion mod, LGPL-3.0 (not started) |
| `bridge/` | Native VR bridge, C++/ObjC++ (not started) |
| `versions.env` | Single source of truth for pins |

Third-party reference sources (`Amethyst-iOS-main/`, `VivecraftMod-Multiloader-26.2/`) are
git-ignored and never committed.

## Licensing

- VRMC application code: **GPL-3.0** (see [`LICENSE`](LICENSE)), because it derives from
  Amethyst (GPL-3.0).
- `provider/` (Vivecraft integration): **LGPL-3.0** (see [`provider/LICENSE`](provider/LICENSE)),
  distributed as a separate, replaceable artifact with source.
- Minecraft is proprietary; users must own it. No Minecraft binaries or assets are distributed.
- Vivecraft is installed by the user and used unmodified.
- See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Safety

VR can cause discomfort. VRMC ships comfort settings (vignette, snap turn, teleport, seated mode),
makes exit/recenter reachable at all times, and does not treat comfort as optional polish.

VRMC is not affiliated with Mojang, Microsoft, Vivecraft, Valve, Sony, or Apple.
