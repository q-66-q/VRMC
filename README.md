# VRMC — Minecraft VR on Apple Vision Pro

VRMC runs **Minecraft: Java Edition 26.2 + Fabric + the real Vivecraft mod** natively on Apple
Vision Pro, with head-tracked stereo and hand-tracked input (PSVR2 controllers are P1, post-MVP)
when present. No PC, no streaming.

> **Status: M3 visual acceptance PASS (EV-0094); M4-W1 immersive input PASSED ON DEVICE (EV-0096); M4-W2–W4, M5 first slice + recenter chord + launcher settings panel/command channel and M6 offline groundwork host/build PASS (EV-0097…EV-0106); device gates still NOT RUN.**
> The launcher, JVM/JIT runtime, Minecraft 26.2 + Fabric + Vivecraft and the VRMC provider (LGPL) run
> end-to-end on Apple Vision Pro. The black-immersive root cause was found and fixed (drawable
> depth-clear value; EV-0093), and the immersive path passed on-device acceptance: the stereo/alignment
> pattern displays and a JIT game run renders the Vivecraft menu world in the immersive space with
> stereo aligned and head tracking (EV-0094). M4-W1 adds the ABI v3 ARKit hand-input channel, a
> hands-only pinch/fist gesture slice and the immersive GUI/menu + attack/use/teleport bindings; the
> on-device session passed both the synthetic plumbing step and **real hands** (authorization allowed,
> continuous tracking, game controllable from the immersive scene — operator: “It ran very well!”,
> EV-0096). Open items: a reproducible shutdown-only JVM SIGSEGV to triage, the full hands P0
> checklist/locomotion, and the W2 work requested by the operator (gaze highlight + pinch selection,
> smoothly tracked hands). Window chrome, re-entry, GPU-sync device run and pacing/soak remain open.
> Status claims are governed by [`VERIFY.md`](VERIFY.md); the operating manual is
> [`AGENT.md`](AGENT.md), the current plans are
> [`docs/mvp/M3C_PLAN.md`](docs/mvp/M3C_PLAN.md) and [`docs/mvp/M4_PLAN.md`](docs/mvp/M4_PLAN.md),
> and the input design/ABI contract is
> [`docs/analysis/immersive-input.md`](docs/analysis/immersive-input.md).

## What is decided

- **Runtime:** on-device JVM with JIT, Amethyst-derived (GPL-3.0), sideload distribution.
- **Pinned stack:** Minecraft **26.2** (Java 25, LWJGL 3.4.1, experimental Vulkan), Fabric
  **0.19.3**, Vivecraft **26.2-1.3.15**.
- **Graphics:** MC "Prefer Vulkan" → MoltenVK → Metal. Fallback: GL/LTW → ANGLE.
- **VR integration:** an LGPL companion mod Mixins Vivecraft's provider selection and implements
  `MCVR`/`VRRenderer` for CompositorServices; Vivecraft stays unmodified unless S3 proves Mixin
  injection unstable.
- **Input:** hands-only MVP (ARKit 27-joint tracking + gestures). PSVR2 Sense is P1, post-MVP — not claimed as MVP input parity.
- **Evidence:** every `PASS` needs an entry in [`VERIFY.md`](VERIFY.md) §6. Simulator is never
  evidence for hands, stereo optics, thermals, or latency.

## Quick start (M0 tooling)

```bash
./scripts/check_versions.sh      # toolchain + reference pin check (read-only)
./scripts/bootstrap.sh           # local dirs + checks + next steps
./scripts/log_evidence.sh --title "example" --dry-run
```

Build/test commands (implemented):

```bash
scripts/build_shell.sh                  # visionOS SwiftUI shell framework (CompositorServices)
MODE=both scripts/build_bridge.sh       # ABI v3 VRMC bridge dylib (device + host)
OUT_DIR=/tmp/vrmc-provider-build scripts/build_provider.sh   # Vivecraft provider mod jar
scripts/m3c_selfcheck.sh                # presentation + input host/simulator one-command suite
scripts/m4_input_selfcheck.sh           # immersive-input ABI/gesture/fixture/simulator suite
```

Device staging and the M4 input runbook: [`docs/mvp/M4_DEVICE_RUN.md`](docs/mvp/M4_DEVICE_RUN.md).

## Layout

| Path | Purpose |
|---|---|
| `AGENT.md` | Operating manual: architecture, hardness register, spikes, milestones, rules |
| `VERIFY.md` | Acceptance criteria, test suites, evidence log |
| `docs/adr/` | Architecture decision records |
| `docs/mvp/` | MVP scope, spike procedures, acceptance guide |
| `scripts/` | Tooling (version check, bootstrap, evidence logging) |
| `launcher/` | visionOS launcher app (Amethyst-derived, GPL-3.0; build/stage scripts in `scripts/`) |
| `runtime/` | native visionOS SwiftUI shell + CompositorServices compositor (`runtime/native-shell/`) and probes |
| `provider/` | Vivecraft companion mod, LGPL-3.0 (provider + M4-W1 gesture engine) |
| `bridge/` | Native VR bridge, C/ObjC++ (ABI v3: tracking, eye handoff, display views, immersive input) |
| `docs/analysis/` | Design/root-cause dossiers (incl. `immersive-input.md`, M4-W1 ABI contract) |
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
