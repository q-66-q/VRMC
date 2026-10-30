# VRMC — Vivecraft on Apple Vision Pro

VRMC lets you play **Minecraft: Java Edition with the real, unmodified Vivecraft mod** on
**Apple Vision Pro**, with both hands fully tracked and driving gameplay.

> **Project status: implementation in progress.** The architecture, governance, protocol,
> and verification framework are in place. Hardware acceptance (physical Vision Pro +
> Windows/SteamVR + Vivecraft) is **not yet verified**. See [`VERIFY.md`](VERIFY.md) for the
> authoritative, evidence-based status. Do not treat this README as a claim of completion.

## How it works

VRMC keeps the game where it belongs — on a VR-capable PC — and turns Vision Pro into a
low-latency stereo headset with first-class hand tracking.

```text
Vision Pro: ARKit hands + head ──▶ timestamped input ──▶ Windows host
            CompositorServices ◀── HEVC/H.264 stereo ◀── WGC capture of Vivecraft DUAL mirror
Windows PC: virtual SteamVR HMD + two Index-style controllers (driver_vrmc)
            real Minecraft + Fabric + Vivecraft + SteamVR (unmodified)
```

- **No native Vivecraft port.** visionOS has no OpenXR/OpenVR runtime; a native port would be
  a multi-quarter fork. See [ADR-0001](docs/adr/0001-remote-vivecraft-runtime.md).
- **No direct-mode driver in v1.** Vivecraft's DUAL mirror already emits both eyes side by
  side; the host captures it. See [ADR-0002](docs/adr/0002-video-path-vivecraft-dual-mirror.md).
- **Hands are first-class.** A 27-joint skeleton per hand is filtered, predicted, and mapped to
  two virtual Index controllers; gestures drive trigger, grip, use, sticks, and buttons. See
  [ADR-0003](docs/adr/0003-hand-input-as-virtual-knuckles.md) and
  [HAND_MAPPING.md](docs/architecture/HAND_MAPPING.md).
- **Time matters.** Encrypted control/media channels, clock synchronisation, bounded
  prediction, late latching, and rotation-only reprojection are designed in, not bolted on.
  See [ADR-0004](docs/adr/0004-transport-and-time.md) and
  [STREAMING.md](docs/architecture/STREAMING.md).
- **Failures are expected.** Hand occlusion, packet loss, Wi‑Fi outages, SteamVR restarts, and
  Minecraft crashes recover without relaunching the headset app. See
  [VERIFY.md](VERIFY.md) §2.4.

## Status at a glance

| Piece | Status |
| --- | --- |
| Governance, feasibility audit, ADRs, plan | Drafted (M0) |
| Protocol v1 + reference codec | In progress |
| visionOS client core (tests, gestures, mapping, clock) | In progress |
| visionOS immersive app + decoder + renderer | In progress |
| Simulator end-to-end demo (mock host) | In progress |
| PC host + OpenVR virtual-device driver | Source in progress; **no Windows/SteamVR runtime evidence** |
| Physical Vision Pro hand tracking | **BLOCKED** — no device in this workspace |
| Full Vivecraft session / gameplay / latency | **BLOCKED** — depends on PC + device |

The only acceptable evidence lives in [`VERIFY.md`](VERIFY.md) §9. Simulator screenshots are
explicitly not evidence for device hand tracking, Vivecraft, or latency.

## Requirements (baseline)

- Apple Vision Pro, visionOS 27.x (M2 or later).
- Windows 11 PC, 8+ CPU cores, 32 GB RAM, NVIDIA RTX 4070+ (NVENC HEVC), wired to a 5 GHz
  Wi‑Fi 6/6E access point.
- Minecraft Java **1.21.11**, Fabric Loader **0.20.1**, Vivecraft **1.3.15** (Fabric), SteamVR.
  You must own Minecraft; VRMC distributes no game or mod binaries.
- Xcode 27.1 / Swift 6.4 for the client build, VS 2022 + Windows SDK for the bridge.

Exact pins and hashes: [`versions.env`](versions.env). Setup:
[`docs/user/INSTALL.md`](docs/user/INSTALL.md).

## Quick start (development)

```bash
./scripts/bootstrap.sh
./scripts/test_all.sh
./scripts/build_client.sh --simulator
./scripts/demo_simulator.sh          # mock host + synthetic hands, no hardware
```

Hardware path (once available):

```bash
pwsh ./scripts/build_bridge.ps1 -Configuration Release
pwsh ./scripts/install_driver.ps1
pwsh ./scripts/run_host.ps1 -Profile "VRMC 1.21.11"
```

See [`AGENT.md`](AGENT.md) §6 for every command and
[`docs/user/RUN.md`](docs/user/RUN.md) for the user flow.

## Documentation

- [AGENT.md](AGENT.md) — operating manual, architecture, commands, phase plan, agent rules.
- [VERIFY.md](VERIFY.md) — acceptance criteria, test matrix, budgets, evidence log, release
  checklist.
- [docs/feasibility/FEASIBILITY_AUDIT.md](docs/feasibility/FEASIBILITY_AUDIT.md) — why this
  architecture, with rejected alternatives.
- [docs/plan/PROJECT_PLAN.md](docs/plan/PROJECT_PLAN.md) — WBS, milestones, risks, fallbacks.
- [docs/architecture/](docs/architecture/) — protocol, streaming, hand mapping.
- [docs/adr/](docs/adr/) — architecture decision records.
- [docs/user/](docs/user/) — install, run, troubleshoot, known limitations.
- [docs/performance/PERF_REPORT.md](docs/performance/PERF_REPORT.md) — measurement report
  (pending hardware).

## Legal and safety

VRMC is an independent project. It is **not affiliated with or endorsed by** Mojang,
Microsoft, Vivecraft, Valve, or Apple. Minecraft is a trademark of Microsoft. You must own
Minecraft Java Edition and comply with its EULA. Vivecraft is LGPL-3.0 and is installed
unmodified by the user; VRMC integrates at arm's length through SteamVR's public interfaces.
No game assets, game binaries, Vivecraft JARs, or SteamVR binaries are included. VRMC's
original code is Apache-2.0; see [LICENSE](LICENSE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

VR can cause discomfort. Read the comfort guidance in
[docs/user/RUN.md](docs/user/RUN.md) and stop if you feel unwell. This project is not a
medical device.
