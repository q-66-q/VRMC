# VRMC — Agent Operating Manual

> **Status:** Active. This is a living document.
> **Owner:** Lead architect / integration owner.
> **Last updated:** 2026-10-29.
> **Companion document:** [`VERIFY.md`](VERIFY.md). `VERIFY.md` is authoritative for
> acceptance decisions. If the two documents disagree, `VERIFY.md` wins and this document
> must be corrected in the same change.

---

## 1. How to use this document

Every agent or developer must read this file and `VERIFY.md` before changing the repository.

1. Find the workstream and phase in §8 and §9.
2. Check the relevant spike or assumption in §11. Do not silently assume it is true.
3. Implement only behind the interfaces and protocols described here or in an accepted ADR.
4. Run the commands in §6 and record evidence in `VERIFY.md` §9.
5. Update this file and `VERIFY.md` in the same pull request when behaviour, commands,
   architecture, or acceptance status changes.

**The prime directive:** no agent may claim success without evidence recorded in
`VERIFY.md`. "It builds" is not "it works". "It worked on my machine" is not reproducible
evidence. If a hardware-dependent result cannot be produced, record it as `BLOCKED` or
`NOT RUN` with the blocking reason. Never fabricate a pass.

---

## 2. Project context

### 2.1 Goal

VRMC lets a user play **Minecraft: Java Edition with Vivecraft on Apple Vision Pro** in a
real, playable VR session, with **both hands fully tracked** and driving real gameplay.

The system must:

- run the real, unmodified Vivecraft mod and the real Minecraft Java client;
- present a low-latency, per-eye stereo view in a visionOS immersive space;
- stream articulated hand skeletons from Vision Pro to the PC and use them for:
  grab/release, break/place, attack/use/consume, UI pointing and pinch selection, inventory
  and menu interaction, locomotion/turning, and two-handed interactions;
- recover from tracking loss, occlusion, packet loss, network loss, runtime restarts, and
  frame drops without restarting the whole stack;
- be reproducible, documented, tested, and releasable by another engineer.

### 2.2 Non-goals

- Minecraft Bedrock Edition, consoles, or mobile Minecraft.
- Running Minecraft or Vivecraft **natively on visionOS**. This was investigated and
  rejected; see ADR-0001 and `docs/feasibility/FEASIBILITY_AUDIT.md`.
- Distributing Minecraft, Minecraft assets, Vivecraft binaries, Java runtimes, or any
  copyrighted game content in this repository or its release artifacts.
- Circumventing Minecraft authentication, EULA, or platform security.
- Supporting arbitrary OpenVR games in v1. The bridge is specialised for Vivecraft's input
  and mirror path. The protocol may be reusable later, but that is not an acceptance goal.
- A flat "virtual monitor" experience. The acceptance target is immersive stereo VR with
  head tracking and hand-driven interaction.
- Controller-only operation as the primary path. Controllers may be a fallback, but hand
  tracking is a first-class input and must satisfy the acceptance tests.
- Audio is a v1.1 workstream; v1 must be playable without relying on audio cues. If audio is
  shipped earlier, it must not compromise the latency budgets.

### 2.3 Hard constraints

| ID | Constraint | Consequence |
| --- | --- | --- |
| C-01 | visionOS has no OpenXR or OpenVR runtime. | Vivecraft cannot initialise on the headset itself. A remote PC runtime is required. |
| C-02 | Vivecraft uses SteamVR/OpenVR, including SteamVR Input action bindings. | The bridge must present coherent OpenVR devices and controller input to SteamVR. |
| C-03 | Vivecraft must run unmodified. | No binary patching, no required Vivecraft fork, no JAR redistribution. |
| C-04 | Hand data must remain usable at interaction latency. | Timestamped input, prediction, and late-latching are mandatory design elements. |
| C-05 | 90 Hz target, graceful degradation to 72 Hz. | Every stage has a frame budget; overload must degrade resolution/bitrate, not correctness. |
| C-06 | No copyrighted assets or game binaries in Git. | Install scripts fetch user-owned software; release artifacts contain only VRMC code. |
| C-07 | App must be deployable through ordinary Apple channels. | No JIT, private APIs, jailbreaks, or entitlements unavailable to normal developers. |
| C-08 | A new developer must reproduce the build from this document. | Pin versions and checksums; automate setup; no undocumented local state. |
| C-09 | Evidence is mandatory. | `VERIFY.md` is updated with every milestone and release candidate. |

### 2.4 Definitions

- **Client / AVP client:** the visionOS app (`client/`).
- **Bridge / host:** the Windows service that captures, encodes, serves media, receives
  tracking, and drives the SteamVR devices (`bridge/`).
- **SteamVR driver:** `driver_vrmc`, the OpenVR server driver DLL that exposes the virtual
  HMD and two virtual Index-style controllers.
- **Vivecraft runtime:** the user-installed Minecraft + Fabric + Vivecraft + SteamVR stack on
  the PC. VRMC never redistributes it.
- **Hand snapshot:** the 27-joint skeleton for one hand, plus timestamp, tracking state, and
  predicted pose.
- **Intent:** the normalised, gesture-derived controller state (trigger, grip, stick, buttons)
  produced on the client from hand snapshots.
- **Frame:** one encoded stereo video access unit with capture metadata.
- **Motion-to-photon (M2P):** time from a physical head/hand motion to the corresponding
  photons in the user's eyes. View M2P is measured separately from action-to-feedback latency.

---

## 3. Architecture

### 3.1 Chosen architecture (ADR-0001)

**Remote, unmodified Vivecraft runtime + custom low-latency stereo stream + virtual
SteamVR driver + visionOS hand-tracking client.**

```text
┌──────────────────────── Apple Vision Pro (visionOS 27+) ────────────────────────┐
│ VRMC.app                                                                        │
│  ┌──────────────┐   ┌─────────────────────┐   ┌───────────────────────────────┐ │
│  │ ARKitSession │──▶│ Hand pipeline       │──▶│ Intent + controller synthesis │ │
│  │ HandTracking │   │ filter/predict/     │   │ gestures → trigger/grip/stick │ │
│  │ WorldTracking│   │ skeleton (27 joints)│   │ buttons, timestamped events   │ │
│  └──────────────┘   └─────────────────────┘   └──────────────┬────────────────┘ │
│         │ head pose                                          │ encrypted UDP    │
│         ▼                                                    ▼                  │
│  ┌──────────────────────┐   ┌───────────────────┐   ┌───────────────────────┐   │
│  │ CompositorServices   │◀──│ VideoToolbox      │◀──│ Reassembly/jitter     │   │
│  │ Metal stereo render  │   │ HEVC/H.264 decode │   │ buffer/NACK/keyframe  │   │
│  │ + late reprojection  │   └───────────────────┘   └───────────▲───────────┘   │
│  └──────────────────────┘                                       │ encrypted UDP │
└─────────────────────────────────────────────────────────────────┼───────────────┘
                                                                  │ LAN / Wi‑Fi 6E
┌──────────────────────────── Windows 11 PC ──────────────────────┼───────────────┐
│ vrmc_host.exe                                                   │               │
│  ┌────────────────┐   ┌──────────────────┐   ┌─────────────────▼────────────┐   │
│  │ WGC window     │──▶│ NVENC HEVC/H.264 │──▶│ Packetiser + clock sync      │   │
│  │ capture 2×eye  │   │ low-latency      │   │ + NACK + telemetry           │   │
│  └───────▲────────┘   └──────────────────┘   └──────────────────────────────┘   │
│          │ DUAL mirror (both eyes, side by side)                                │
│  ┌───────┴────────────────────────────────────────────────────────────────────┐ │
│  │ SteamVR                                                                    │ │
│  │  ┌─────────────────┐   HMD pose + controller state     ┌────────────────┐  │ │
│  │  │ driver_vrmc.dll │◀────────────────────────────────▶ │ VRMC host IPC  │  │ │
│  │  │ virtual HMD +   │  shared memory, seqlock           │ + prediction   │  │ │
│  │  │ 2× controllers  │                                   └────────────────┘  │ │
│  │  └────────┬────────┘                                                       │ │
│  │           │ OpenVR                                                         │ │
│  │  ┌────────▼─────────────────────────────────────────────────────────────┐  │ │
│  │  │ Minecraft Java + Fabric + Vivecraft (unmodified, user-installed)     │  │ │
│  │  └──────────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Why this path wins:** it is the shortest path that runs the real Vivecraft while keeping
hand tracking, latency, and recovery under our control. It reuses Vivecraft's proven VR
gameplay and SteamVR Input bindings; the only novel PC-side surface is a virtual HMD and two
virtual controllers. It avoids porting Minecraft, LWJGL, OpenGL, SteamVR, or Vivecraft to
visionOS. See ADR-0001 for the full comparison.

### 3.2 Frozen architectural decisions

| ADR | Decision | Status |
| --- | --- | --- |
| [ADR-0001](docs/adr/0001-remote-vivecraft-runtime.md) | Remote unmodified Vivecraft + stereo stream + virtual SteamVR devices | Accepted |
| [ADR-0002](docs/adr/0002-video-path-vivecraft-dual-mirror.md) | Capture Vivecraft DUAL mirror output; do not implement direct-mode frame submission in v1 | Accepted |
| [ADR-0003](docs/adr/0003-hand-input-as-virtual-knuckles.md) | Emulate two Index (`knuckles`) controllers from hands; gestures synthesise OpenVR inputs | Accepted |
| [ADR-0004](docs/adr/0004-transport-and-time.md) | Separate reliable control channel and unreliable encrypted media/input datagrams; NTP-style clock sync; prediction + late latching | Accepted |
| [ADR-0005](docs/adr/0005-compositor-and-reprojection.md) | CompositorServices/Metal stereo rendering with rotation-only late reprojection in v1; depth reprojection deferred | Accepted |
| [ADR-0006](docs/adr/0006-licensing-and-distribution.md) | Apache-2.0 original code; no game/Vivecraft binaries; arm's-length integration; user-supplied runtime | Accepted |

Any change to these decisions requires a new superseding ADR, an update to this file and
`VERIFY.md`, and an explicit re-verification plan.

### 3.3 Module boundaries

- **Transport is dumb.** It frames, encrypts, sequences, and delivers bytes. It does not know
  about hands, gestures, or Minecraft.
- **Tracking is platform-specific.** ARKit lives in `VRMCTracking`; the rest of the system
  consumes `HandSnapshot`/`HeadSnapshot` value types.
- **Gesture recognition is pure Swift** and testable with synthetic skeletons.
- **Intent mapping is policy, not transport.** A mapping profile converts intent to virtual
  controller state. Profiles are versioned and testable.
- **Video decode/render are separate.** `VRMCVideo` produces `CVPixelBuffer`s and metadata;
  `VRMCRender` consumes eye textures and drawable transforms.
- **The PC bridge shares a portable protocol core** (`bridge/core`) used by both the Windows
  host and unit tests; Windows-only capture/encode/driver code is isolated behind interfaces.
- **The SteamVR driver is a thin device server.** All policy (gesture mapping, prediction of
  intent, preferences) lives in the host/client. The driver only exposes devices and moves
  bytes.

### 3.4 Coordinate and time conventions

- All positions are metres; all quaternions are `(x, y, z, w)`, normalised, right-handed.
- Apple world space: +Y up, right-handed, origin fixed at ARKit session start. Vision Pro
  hand joints and device anchors are reported in this space.
- OpenVR/SteamVR standing space: +Y up, −Z forward, right-handed. The bridge applies a
  calibrated rigid transform from Apple world space to SteamVR space (yaw + translation;
  no scale unless explicitly configured).
- Capture metadata uses the PC monotonic clock (`QueryPerformanceCounter` converted to ns).
  Input timestamps use the client monotonic clock. Clock sync estimates offset and drift;
  packets carry both raw and synchronised timestamps for auditability.
- The protocol's canonical time unit is **nanoseconds, uint64**. Every pose and frame has a
  timestamp; no stage may silently substitute "now".
- Video is encoded as Annex-B NAL units. The stream carries SBS (left eye left half, right
  eye right half), no lens distortion. FOV, projection, eye offsets, and display frequency
  are sent in `StreamConfig` and checked by the client.

### 3.5 The user-visible session flow

1. User starts SteamVR (with VRMC driver enabled) and the prepared Minecraft/Vivecraft
   profile on the PC. Alternatively, `vrmc_host --launch-profile` launches both.
2. User launches VRMC on Vision Pro, grants hand-tracking permission, and selects or
   auto-discovers the PC (`_vrmc._tcp`).
3. Pairing: host displays a six-digit code; user enters it once. Keys are exchanged and the
   session is encrypted.
4. Host captures the Vivecraft DUAL mirror window, encodes, and streams. Client enters a
   full immersive space and renders both eyes.
5. Client streams head pose and hand skeletons at sensor rate. Host predicts, maps to
   SteamVR devices, and writes the driver IPC snapshot.
6. Tracking/network/runtime failures are handled by the state machines in §3.6; the user sees
   a non-blocking overlay and the session resumes automatically where possible.
7. On quit, inputs are released, the driver marks poses invalid, and resources are closed
   deterministically.

### 3.6 Failure state machines

**Client tracking state (per hand):**
`searching → tracking → degraded(hold ≤120 ms) → lost → searching`.
On `lost`: release all buttons/axes derived from that hand, stop emitting pose as valid, show
a ghost hand; do not close the session. On reacquisition: require 3 consecutive tracked
samples, re-anchor the hand-to-controller offset, and resume.

**Client link state:**
`idle → connecting → handshaking → streaming → degraded(no media >250 ms) → reconnecting`.
`degraded`: keep the last frame, stop input emission, show "Link degraded", request an IDR on
recovery. `reconnecting`: exponential backoff (250 ms → 2 s, capped), re-handshake, reset
clock sync, request config and IDR. Never block the main render thread.

**Host capture/encoder state:**
`waiting_for_window → capturing → encoding → streaming`.
On window loss: keep serving the last frame for 500 ms, then send a "runtime unavailable"
state; retry window discovery every 500 ms. On encoder failure: recreate encoder once,
request IDR; if it fails again, degrade codec/profile and surface a diagnostic.

**SteamVR/runtime restart:**
Host detects driver/Vivecraft/SteamVR loss via process and IPC health. It releases all
virtual inputs, marks the HMD/controllers invalid, and attempts a bounded restart of the
configured profile (default: do not kill Minecraft; prompt if it exited). Client remains in
the immersive space in `degraded` and reconnects when media returns. The whole Vision Pro app
must not need relaunching.

### 3.7 Security and privacy

- LAN sessions are encrypted and authenticated. The pairing code is used only to authenticate
  an X25519 key exchange; session keys are derived with HKDF-SHA256. Media/input use
  ChaCha20-Poly1305 with monotonically increasing nonces. Replay windows are enforced.
- No hand data, video, or telemetry leaves the user's LAN by default. Analytics are opt-in and
  must never include skeletons, video, world seed, server address, or account identifiers.
- The client redacts IP addresses and tokens from user-facing logs. Diagnostics bundles are
  user-initiated.
- macOS/Windows firewall prompts and Local Network permission are documented. Bonjour
  discovery is optional and can be disabled.
- The host binds to the selected LAN interface, not all interfaces, in release mode.
- Apple privacy manifest and usage strings are mandatory; see §10.4.
- No DRM circumvention, no credential collection, no game-file distribution.

### 3.8 Licensing and distribution

- VRMC original code: **Apache-2.0** (see `LICENSE`).
- The SteamVR driver links against the OpenVR SDK (BSD-3-Clause); notices included.
- The Windows host may link against NVIDIA NVENC headers (MIT-style NVIDIA license) and use
  the NVIDIA driver at runtime. FFmpeg, if used, is a separate process or dynamically linked
  in an LGPL-compatible configuration; notices included.
- Vivecraft is LGPL-3.0. VRMC does **not** link to, modify, or redistribute Vivecraft. It
  integrates at arm's length through SteamVR's public interfaces. Any future companion mod
  must be LGPL-3.0 and live in its own process/JAR; it is out of scope for v1.
- Minecraft is proprietary. Users must own it. VRMC ships no Minecraft code, assets, or
  binaries. Install scripts fetch official/user-owned files and verify checksums.
- Apple: no private APIs, no JIT, no sideload-only entitlements required for the documented
  TestFlight/Ad Hoc path. Hand tracking requires explicit authorisation.
- Release artifacts contain only VRMC binaries, docs, and notices.

---

## 4. Repository map and ownership

```text
AGENT.md                     Operating manual (this file)                 lead
VERIFY.md                    Verification and acceptance source of truth  verification owner
README.md                    Project overview and quick start             lead
LICENSE                      Apache-2.0 for original code                 lead
THIRD_PARTY_NOTICES.md       Dependency licenses and notices              release owner
versions.env                 Pinned tool/runtime versions                 build owner
client/                      visionOS client and shared Swift packages     client owner
  Package.swift              Swift package: VRMCore, protocol, tests      client owner
  project.yml                XcodeGen definition for the app              client owner
  VRMC.xcodeproj/            Generated project (committed for repro)      client owner
  Sources/VRMCore/           Pure Swift: protocol, time, prediction,      client owner
                             gestures, mapping, session, telemetry
  Sources/VRMCTracking/      ARKit adapters (visionOS only)               tracking owner
  Sources/VRMCVideo/         VideoToolbox decode, NAL parsing             media owner
  Sources/VRMCRender/        Metal + CompositorServices renderer         render owner
  Sources/VRMCApp/           SwiftUI shell, immersive space, UI          client owner
  Tests/VRMCoreTests/        Unit and integration tests                  verification owner
  Tests/VRMCVideoTests/      Decode and packet tests                     media owner
  Resources/                 Privacy manifest, strings, app icon          client owner
bridge/                      Windows PC bridge                            bridge owner
  CMakeLists.txt             Cross-platform core + Windows targets       build owner
  core/                      Portable protocol, clock, pose, IPC layout   bridge owner
  host/                      Windows capture, encode, net, session       bridge owner
  driver/                    OpenVR server driver (Windows DLL)          driver owner
  tests/                     Portable C++ tests + protocol vectors       verification owner
  resources/                 Driver manifest, input profile, bindings    driver owner
protocol/                    Language-neutral spec and vectors            protocol owner
  PROTOCOL.md                Wire protocol v1                            protocol owner
  schema/                    JSON schemas for config/telemetry           protocol owner
  vectors/                   Shared conformance binaries/JSON           protocol owner
tools/                       Mock host, provisioning, benchmarks          tooling owner
  mock_host/                 Synthetic stream + input audit for simulator tooling owner
  diagnostics/               Log collectors, latency analyser             tooling owner
scripts/                     Build, test, demo, package, verify          build owner
docs/                        Architecture, ADRs, plans, guides, evidence  lead / owners
artifacts/                   Generated artifacts (gitignored)             build owner
```

**Ownership rule:** cross-boundary changes require review by the owning workstream and the
integration owner. Protocol changes require the protocol owner plus an update to
`protocol/PROTOCOL.md`, conformance vectors, and both language implementations.

---

## 5. Supported environment and pinned versions

All pins live in `versions.env`. Changing a pin requires a full verification run of the
affected matrix row.

| Component | Baseline | Notes |
| --- | --- | --- |
| Headset | Apple Vision Pro (M2), visionOS 27.x | Additional devices in `VERIFY.md` §4.1 |
| Client build | Xcode 27.1, Swift 6.4, visionOS 27.0 SDK | macOS 27.0.1 on Apple silicon |
| PC OS | Windows 11 24H2+ | Linux is not a v1 target |
| GPU | NVIDIA RTX 4070+ (NVENC HEVC) | Minimum 8 GB VRAM; 12 GB recommended |
| CPU | 8-core modern x86-64, 32 GB RAM | 16 GB minimum |
| Minecraft | Java Edition 1.21.11 | User-owned; not distributed |
| Mod loader | Fabric Loader 0.18.x (pin exact in `versions.env`) | Profile created by user |
| Vivecraft | 1.3.15 Fabric for 1.21.11 | User-installed; LGPL-3.0 |
| SteamVR | Current stable at verification time, pinned in evidence | Must support custom drivers |
| Network | 5 GHz Wi‑Fi 6/6E or Ethernet; ≥300 Mbps LAN | Dedicated AP/SSID recommended |
| Audio (v1.1) | Opus 48 kHz stereo | Not an acceptance dependency |

Exact patch versions and SHA-256 hashes are recorded in `versions.env` and every evidence
entry. "Latest" is never an acceptable reproducible pin.

---

## 6. Commands

All commands run from the repository root unless stated. `make help` (where available) is
informational only; scripts are the source of truth.

### 6.1 Bootstrap

```bash
./scripts/bootstrap.sh              # checks tools, installs Swift/JS test deps if needed
./scripts/bootstrap.sh --pc         # Windows/PowerShell: prints/enables PC prerequisites
source versions.env                 # optional; scripts read it directly
```

### 6.2 Build

```bash
# Swift core + unit tests (macOS, fast)
cd client && swift build && swift test

# visionOS app for the simulator (no signing)
./scripts/build_client.sh --simulator

# visionOS device build (unsigned unless DEVELOPMENT_TEAM is set)
./scripts/build_client.sh --device

# PC portable core and tests (macOS/Linux; Windows-only targets are skipped)
./scripts/build_bridge.sh --core

# PC host + OpenVR driver (Windows PowerShell, requires VS 2022 + Windows SDK)
pwsh ./scripts/build_bridge.ps1 -Configuration Release

# Language-neutral protocol conformance (Python reference codec)
./scripts/test_protocol.sh
```

### 6.3 Test

```bash
./scripts/test_all.sh               # Swift + C++ core + protocol conformance
cd client && swift test             # Swift only
ctest --test-dir build/bridge -V   # C++ core only (after build_bridge.sh)
./scripts/test_protocol.sh          # vectors only
```

The full automated suite is listed in `VERIFY.md` §7. Hardware tests are in §6 of that file.

### 6.4 Run

```bash
# Simulator end-to-end demo with synthetic stereo video + synthetic hands
./scripts/demo_simulator.sh

# Manual simulator launch
./scripts/build_client.sh --simulator
xcrun simctl install booted build/client/VRMC.app
xcrun simctl launch booted dev.vrmc.app -VRMCDemoMode YES

# PC host (Windows, after build)
pwsh ./scripts/run_host.ps1 -Profile "VRMC 1.21.11"

# Install/refresh the SteamVR driver (Windows, elevated as required by SteamVR)
pwsh ./scripts/install_driver.ps1
```

### 6.5 Lint and static checks

```bash
./scripts/lint.sh                  # swiftformat/swiftlint if installed; clang-format; docs links
./scripts/check_docs.sh            # required files, broken local links, stale status markers
```

Lint is advisory in developer builds and required in CI for changed files. Formatting must be
deterministic; do not reformat unrelated files.

### 6.6 Package and release

```bash
./scripts/package_release.sh --version 1.0.0   # client archive + bridge zip + checksums + notices
./scripts/verify_release.sh --version 1.0.0    # release checklist automation
```

Outputs go to `artifacts/<version>/` and are **not** committed. Release candidates require a
completed `VERIFY.md` §10 checklist and a signed-off evidence table.

### 6.7 Evidence capture

```bash
./scripts/collect_evidence.sh --id EV-0001 --note "description"
```

The script records date, Git commit, dirty state, host/device identifiers, build hashes, and
the paths of attached logs. Artifacts are stored under `evidence/<id>/` (large binaries are
excluded from Git; a manifest and hashes are committed).

---

## 7. Coding standards

### 7.1 General

- Prefer small, testable modules with explicit dependency injection. No global mutable
  singletons in new code; platform singletons are wrapped.
- Every network packet, pose, and frame is timestamped and validated. Reject malformed input
  without crashing.
- Never block the render thread or the ARKit update consumer. Use bounded queues and drop
  oldest media frames under pressure.
- No unbounded memory growth. Define and enforce queue sizes; log drops with counters.
- Errors are typed and surfaced. Fatal errors are reserved for unrecoverable invariant
  violations; user-visible failures go through the session state machine.
- All user-facing strings are localisable (English baseline). No hand data in logs by
  default.
- Comments explain *why*, invariants, and units. Do not narrate obvious code.
- Security-sensitive code (crypto, packet parsing, IPC) requires tests for malformed input
  and a second reviewer.

### 7.2 Swift

- Swift 6 language mode, strict concurrency. `Sendable` across actor boundaries.
- Value types for protocol and tracking data. Actors for session, transport, and decode;
  `@MainActor` for UI state.
- No force unwraps in production code except provable constants; use `guard`/typed errors.
- Units in names: `Milliseconds`, `Nanoseconds`, `Meters`, `Radians`. No naked `Double`
  timestamps.
- Use `ContinuousClock`/`mach_continuous_time` for intervals; wall clock only for logs.
- Public APIs documented; modules keep `internal` by default.
- Tests use deterministic clocks and seeded synthetic data. No `sleep`-based assertions where
  a virtual clock can be used.

### 7.3 C++

- C++20. `-Wall -Wextra -Werror` for core; warnings allowed only with a tracked TODO.
- No exceptions across the driver ABI. Use `noexcept`, error codes, and fail closed.
- All shared-memory structs are trivially copyable, fixed-width, explicitly padded, and
  guarded by the versioned seqlock protocol in `bridge/core/ipc.h`.
- Windows-only code is isolated in `host/win` and `driver/`, behind interfaces testable on
  POSIX. Do not include Windows headers in `core/`.
- OpenVR API calls are confined to the driver and a thin host adapter; core never depends on
  SteamVR.
- Every external input is bounds-checked. Use `std::span`, avoid raw pointer arithmetic in
  parsing.

### 7.4 Protocol

- Versioned, little-endian, length-prefixed. Unknown fields are skipped only where the spec
  allows; otherwise reject.
- Never reuse a packet type number. Deprecate, do not delete, within a major version.
- Every message has a maximum size and a schema/vector. Strings are UTF-8 with explicit
  length bounds.
- Conformance vectors are generated by the reference implementation and consumed by Swift
  and C++ tests. Both implementations must produce identical bytes.
- Media packets may be dropped; control messages are reliable and ordered. Input datagrams
  are unreliable but authenticated and replay-protected.

### 7.5 Documentation

- ADRs are immutable once accepted; supersede with a new ADR.
- Status markers are exact: `VERIFIED`, `PARTIAL`, `BLOCKED`, `NOT RUN`, `FAIL`.
  `PARTIAL` requires a link to the evidence and a list of what is missing.
- Commands in docs must be copy-pasteable and tested by `scripts/check_docs.sh` where
  feasible.
- Never claim hardware results without a recorded device, build hash, procedure, and
  evidence path.

---

## 8. Git, branching, review, and handoff

### 8.1 Branching

- `main` is always releasable and must pass CI. No direct pushes except the integration
  owner during a declared phase gate, and even then with a recorded verification run.
- Work branches: `feat/<area>-<short>`, `fix/<area>-<short>`, `docs/<short>`,
  `spike/<id>-<short>`. Spikes may be discarded but their findings must be recorded.
- Rebase onto `main` before review; do not merge `main` into a feature branch repeatedly.
- Tags: `vMAJOR.MINOR.PATCH-rc.N` and `vMAJOR.MINOR.PATCH`. Never move a published tag.

### 8.2 Commit messages

Conventional Commits, imperative, scoped:

```text
feat(client): add 27-joint hand snapshot and synthetic provider
fix(bridge): mark controller poses invalid on tracking loss
docs(verify): record EV-0007 simulator stream pass
test(protocol): cover truncated media fragment and replay window
chore(release): pin Vivecraft 1.3.15 and add notices
```

Body must state what changed, why, verification performed, and `VERIFY.md` evidence IDs. A
commit that changes behaviour without evidence is incomplete.

### 8.3 Review checklist

- [ ] Does it respect the module boundaries in §3.3 and the ADRs?
- [ ] Are all new packets/fields documented and covered by conformance vectors?
- [ ] Are timestamps, units, coordinate frames, and clock domains explicit?
- [ ] Are failure paths tested (loss, occlusion, malformed input, disconnect, restart)?
- [ ] Are UI and logs free of secrets and hand data by default?
- [ ] Are resources bounded and render-critical paths allocation-free where practical?
- [ ] Do build/test commands still work from a clean checkout?
- [ ] Is `AGENT.md` updated for process/command/architecture changes?
- [ ] Is `VERIFY.md` updated for acceptance/evidence changes?
- [ ] Are licenses/notices correct for new dependencies?
- [ ] Is the change reproducible without undocumented local state?

### 8.4 Handoff protocol

At the end of every phase, the responsible agent posts a handoff containing:

1. **Built:** components and exact commit.
2. **Verified:** test IDs and `VERIFY.md` evidence IDs; explicitly list what was *not* run.
3. **Failed/blocked:** failures with logs, root-cause status, and impact.
4. **Plan delta:** changes to scope, sequence, risks, or ADRs; documents updated.
5. **Next phase:** entry criteria, owner, and blocking dependencies.

Handoff is not complete until `VERIFY.md` and `AGENT.md` reflect it and `git status` is clean.

---

## 9. Phase plan, milestone gates, and exit criteria

The plan is deliberately front-loaded with feasibility and a thin end-to-end path. No phase
may claim completion without evidence in `VERIFY.md` §9.

### M0 — Governance, feasibility, and skeleton

**Deliverables:** `AGENT.md`, `VERIFY.md`, feasibility audit, ADR-0001..0006, project plan,
test strategy, budgets, repository skeleton, CI config, protocol v1 draft, legacy-prototype
inventory.

**Exit:** documents internally consistent; all high-risk assumptions have a spike plan and
owner; cost/risk comparison complete; repo builds empty test targets; no product feature is
claimed.

### M1 — Client core + simulator streaming

**Deliverables:** Swift package core (protocol, clock, prediction, gestures, mapping, session,
telemetry), encrypted transport skeleton, H.264/HEVC decode, Metal stereo renderer,
CompositorServices immersive app, synthetic hand provider, mock host, simulator demo, unit
tests.

**Exit:** simulator connects to mock host, decodes a stereo stream, renders in immersive
space, sends synthetic input; automated tests pass; frame/latency telemetry exists. No
device-only claim.

### M2 — Real hand tracking and intent pipeline (device)

**Deliverables:** ARKit hand/world tracking adapters, 27-joint snapshots, filtering and
prediction, gesture recogniser, Intent→virtual controller mapping, calibration UI, tracking
loss/occlusion state machine, on-device hand HUD, input capture evidence.

**Exit:** both hands tracked on Vision Pro with measured update rate and latency; all
gestures in the mapping spec fire with false-positive rate within target; loss/occlusion
recovery passes; evidence recorded. Depends on M1 and a physical Vision Pro.

### M3 — PC bridge and Vivecraft session

**Deliverables:** portable bridge core, OpenVR virtual HMD + two knuckles controllers, driver
installer, shared-memory IPC, Windows host (WGC capture, NVENC, networking, clock sync),
Vivecraft DUAL mirror configuration, launch scripts, host tests, driver smoke test.

**Exit:** Vivecraft starts in VR with the virtual devices; DUAL mirror capture is stereo
correct; client shows live gameplay; all driver inputs reach Vivecraft; SteamVR/runtime
restart recovery works; evidence recorded. Depends on a Windows VR-capable PC and SteamVR.

### M4 — End-to-end hand-driven gameplay

**Deliverables:** complete mapping profile, two-handed interactions, UI pointing, inventory,
locomotion/turning, comfort options, late reprojection, latency measurement, failure-recovery
polish, manual test campaign.

**Exit:** every interaction in AC-3 demonstrated on device; M2P within documented targets or
a quantified limitation + mitigation; failure matrix passes; evidence recorded.

### M5 — Release hardening

**Deliverables:** security review, dependency/license audit, privacy manifest, user guide,
troubleshooting, known limitations, release checklist, CI green, reproducible clean-checkout
build, signed/archived artifacts, final DoD audit.

**Exit:** all ACs verified; `VERIFY.md` §10 signed off; no open P0/P1 defects; release
artifacts built from a tagged commit with checksums.

### 9.1 Dependencies

```
M0 ─▶ M1 ─▶ M2 ─┐
        └──────▶ M3 ─▶ M4 ─▶ M5
```

M2 and M3 can proceed in parallel after M1, but M4 requires both. Integration and acceptance
verification are centralised in the integration owner; workstreams do not self-certify.

### 9.2 Phase gate rule

A gate passes only when: all exit criteria have evidence, `VERIFY.md` is updated, the CI
pipeline for the phase is green, no unresolved P0 issue exists, and the handoff in §8.4 is
posted. If a gate fails, the project stays in the phase and the failure is recorded.

---

## 10. Definition of done by workstream

### 10.1 Client platform

- Builds for visionOS simulator and device from a clean checkout with documented commands.
- Runs on at least one physical Vision Pro; immersive space opens/closes cleanly.
- Hand and head tracking authorisation flows are correct and recoverable.
- Simulator mode works without hand hardware and is clearly labelled synthetic.
- No private APIs, JIT, or unavailable entitlements. Privacy manifest and usage strings pass
  App Store validation.
- Frame pacing meets budgets; thermal/quality degradation is observable and reversible.

### 10.2 Tracking and gestures

- Both hands, 27 joints each, positions and orientations, timestamps, tracking flags.
- Handedness correct; left/right never swap silently; calibration is reproducible.
- Gesture events are debounced and timestamped; no stuck buttons after loss.
- Unit tests cover pinch/fist/palm/pointing/locomotion/two-hand chords and noisy data.
- Manual false-positive/negative rates are recorded in `VERIFY.md`.
- Tracking loss, occlusion, and reacquisition meet the recovery targets.

### 10.3 PC bridge and driver

- Portable core tests pass on macOS/Linux; Windows targets build with pinned VS/SDK.
- Driver registers a virtual HMD and two controllers; SteamVR sees valid poses and inputs.
- HMD/controller poses update from the network with bounded extrapolation; invalid states are
  propagated, never frozen as valid.
- Host captures the DUAL mirror at target resolution/fps; stereo halves are aligned and
  correctly ordered.
- Encoder settings produce decodable streams at the target bitrate/fps with bounded queues.
- Runtime restart and network loss recovery pass the failure matrix.
- Installer/scripts are reversible and do not overwrite user files without backup.

### 10.4 Protocol and transport

- Versioned spec, schemas, conformance vectors, and reference codec.
- Swift and C++ implementations produce byte-identical control messages.
- Packet loss, reordering, duplication, truncation, replay, clock drift, and key rotation are
  tested.
- Crypto uses standard primitives correctly; keys never logged; pairing is rate-limited.
- MTU-safe fragmentation; no unbounded reassembly; NACK/IDR behaviour verified.

### 10.5 Video and rendering

- Decodes HEVC/H.264 Annex-B on visionOS hardware with P50/P95 decode times recorded.
- Stereo eye mapping is correct (no swapped eyes, no vertical flip, no colour-space error).
- FOV/projection/IPD metadata is honoured; mismatches are rejected or surfaced.
- Late reprojection reduces view latency without visible distortion beyond documented bounds.
- Budgets for resolution, fps, bitrate, and GPU/CPU are measured, not estimated.

### 10.6 Verification and release

- Acceptance matrix fully mapped to tests/procedures.
- Evidence log complete for the release candidate; all required entries `PASS`.
- User install/run/troubleshooting/limitations docs tested by someone other than the author.
- Clean-checkout reproducibility demonstrated.
- Licenses/notices/privacy/EULA compliance reviewed.
- Release checklist signed; unresolved limitations explicitly accepted.

---

## 11. Risks, assumptions, spikes, and open questions

Every assumption is labelled. Unverified assumptions may not be cited as fact in acceptance
decisions.

### 11.1 High-risk assumptions and spikes

| ID | Assumption / risk | Impact | Spike / validation | Status |
| --- | --- | --- | --- | --- |
| A-01 | SteamVR accepts a third-party virtual HMD with a display component and two `knuckles` controllers, and Vivecraft enters VR and renders. | Architecture invalid if false. | S-01: Windows + SteamVR + driver smoke test; inspect OpenVR samples/driver logs. | UNVERIFIED |
| A-02 | Vivecraft DUAL mirror produces complete, correctly ordered left/right eye images in the game window at frame rate. | Stereo path invalid. | S-02: source audit (done) + Windows capture of known scene; compare halves, frame counters. | PARTIAL (source inspected) |
| A-03 | Vision Pro ARKit hand tracking delivers both hands at ≥72 Hz in immersive CompositorServices apps, with usable joint accuracy. | Core input invalid. | S-03: device app; log anchor rate, joint jitter, occlusion recovery. | UNVERIFIED |
| A-04 | Hardware HEVC/H.264 decode + CompositorServices can sustain 90 Hz at target eye resolution. | Comfort/acceptance. | S-04: device decode/render benchmark with telemetry. | UNVERIFIED |
| A-05 | End-to-end view latency can meet the documented target with rotation-only reprojection. | Acceptance #4. | S-05: instrumented + high-speed-camera latency study. | UNVERIFIED |
| A-06 | Gesture-derived controller input is precise and comfortable enough for Vivecraft's default bindings. | Playability. | S-06: mapping usability study; tune thresholds; fallback profile. | UNVERIFIED |
| A-07 | WGC captures the Minecraft window at 90 fps without stutter or colour/format issues. | Media path. | S-07: Windows capture benchmark and frame-integrity check. | UNVERIFIED |
| A-08 | SteamVR Input accepts our synthetic component updates and Vivecraft's default bindings without a custom binding file. | Input path. | S-08: action trace in SteamVR + in-game test. | UNVERIFIED |
| A-09 | Pairing/encryption overhead fits the input/media budget and passes App Store review. | Release. | S-09: crypto benchmark + privacy review. | NOT STARTED |
| A-10 | A 3840×1080 DUAL mirror window is stable on the target GPU/driver and does not force desktop resolution changes. | Capture quality. | S-10: Windows display test at 90 Hz. | UNVERIFIED |
| A-11 | Vision Pro and PC clocks can be synchronised within ±2 ms on LAN/Wi-Fi 6E. | Prediction/reprojection. | S-11: clock sync soak with jitter/loss. | UNVERIFIED |
| A-12 | The virtual HMD's reported FOV/IPD can be matched closely enough to avoid stereo discomfort. | Comfort. | S-12: projection/IPD calibration and user test. | UNVERIFIED |

### 11.2 Known risks

- **SteamVR driver API churn.** Pin SteamVR; test upgrades explicitly; keep the driver small.
- **Vivecraft version coupling.** Bindings/mirror code can change between versions. Pin
  Minecraft/Vivecraft; run the compatibility matrix before claiming support.
- **Wi‑Fi latency spikes.** Prefer 6E/dedicated AP; implement jitter buffer, FEC/NACK, ABR, and
  a wired fallback. Degradation must be visible.
- **Hand tracking occlusion.** Hands below the field of view, behind the back, or occluded by
  the headset/hair are common. Design recovery and ghost feedback.
- **Gesture ambiguity/fatigue.** Pinch/fist held for locomotion can fatigue. Provide profiles
  and comfort settings; manual tuning is mandatory.
- **Minecraft tick latency.** Game actions are processed at 20 TPS (50 ms). Action feedback
  targets must account for this; do not conflate with view M2P.
- **Windows capture and DRM/fullscreen.** WGC cannot capture some protected content; Minecraft
  is not protected, but exclusive fullscreen/borderless behaviour must be tested. Use
  borderless window.
- **Encoder/GPU vendor differences.** NVENC path is baseline; AMD/Intel encode is out of scope
  for v1 unless a verified fallback is added.
- **Thermal throttling on Vision Pro.** Long sessions may reduce performance; measure 30-min
  stability and implement quality scaling.
- **App Review.** Remote game streaming and local-network access need clear descriptions and
  privacy compliance. TestFlight/Ad Hoc is the initial distribution path; App Store is not
  assumed.
- **Security.** A compromised LAN host can inject video/input. Pairing, encryption, and
  explicit host identity are required; do not auto-trust unknown hosts.

### 11.3 Open questions

- Q-01: Exact Vivecraft 1.3.15 DUAL mirror window sizing and whether the game window can be
  borderless at 3840×1080 on common GPUs without Windows scaling issues.
- Q-02: Whether SteamVR applies additional distortion/crop to the DUAL mirror blit that must
  be compensated in the client.
- Q-03: Best hand-to-controller offset for Vivecraft's arm model and pointing laser; needs
  on-device tuning.
- Q-04: Whether full finger skeleton data is consumed by Vivecraft 1.3.15; if not, skeleton is
  still used for gesture recognition and future visual hands.
- Q-05: Acceptable amount of rotation-only reprojection at the edges of a 100° FOV.
- Q-06: Whether audio can be added without violating the latency budget; v1.1 decision.
- Q-07: App Store vs TestFlight-only distribution for v1; licensing and policy review needed.

### 11.4 Spike protocol

Each spike has a one-page record in `docs/spikes/S-xx-*.md`: question, method, environment,
raw results, decision, and links to evidence. A spike that disproves an assumption triggers a
stop, a pivot proposal, ADR update, and `VERIFY.md` update before further implementation.

---

## 12. Rules for agents

### 12.1 Plan

- Before coding, state the phase, workstream, acceptance IDs, files to change, tests to add,
  and risks. If the work is not in the plan, update the plan first.
- Identify whether the task can be verified in this environment. If it requires hardware,
  write the code and the manual procedure, mark evidence `BLOCKED` with the exact reason, and
  do not claim the acceptance criterion.
- Prefer the smallest end-to-end vertical slice over broad unfinished scaffolding.

### 12.2 Implement

- Work behind interfaces; keep platform code at the edges.
- Update protocol/spec/docs together with code.
- Add tests in the same change. A bug fix needs a regression test unless impossible; then
  record why and add a manual test.
- Do not add a dependency without a license check, pin, and notice update.
- Do not modify generated Xcode project files by hand if `project.yml` is the source; regenerate
  and commit both when required for reproducibility.

### 12.3 Verify

- Run the automated tests relevant to the change and the full suite before a gate.
- For hardware claims, follow the manual procedure exactly and record: date, commit, dirty
  state, device model/OS, PC specs, SteamVR/Minecraft/Vivecraft versions, network, steps,
  expected, actual, logs/screenshots/video, verdict.
- A test that was not run is `NOT RUN`; a test that cannot run is `BLOCKED` with owner and
  unblock condition. Never mark `PASS` from code inspection alone.
- Flaky tests are defects. Quarantine with an issue and record it; do not retry until green.

### 12.4 Report and update docs

- Every phase report answers: what was built, what was verified and where, what failed, what
  changed in the plan/AGENT, and what is next.
- Update `VERIFY.md` evidence log and acceptance status before reporting completion.
- If a claim in `AGENT.md` becomes false, correct it in the same commit.
- Keep the repository clean: no build outputs, secrets, device dumps, or copyrighted assets.

### 12.5 Stop conditions

Stop implementation and escalate when:

- a high-risk assumption is disproven and the architecture may be invalid;
- a licensing or platform-policy violation is discovered;
- a security issue allows unauthenticated control or data exfiltration;
- acceptance evidence cannot be produced and the plan has no credible fallback;
- a change would require modifying/redistributing Minecraft or Vivecraft.

Escalation means documenting the evidence, proposing alternatives with cost/risk, updating
the ADRs/plan, and waiting for a decision rather than silently pivoting.

---

## 13. Current status snapshot

**As of 2026-10-29 (M0 in progress):**

- Governing documents created; feasibility audit and ADRs drafted from source inspection.
- The prior repository history contains a **native visionOS Minecraft prototype** (Amethyst +
  a custom stereo mod). It is preserved for reference but is **not** the selected
  architecture and does not satisfy the Vivecraft requirement. It is archived, not extended.
- Source inspection confirms Vivecraft 1.3.15 is OpenVR-only and its DUAL mirror mode renders
  both eyes side by side to the desktop window.
- No product code has been accepted yet. No device, SteamVR, or Vivecraft runtime evidence
  exists in this workspace.
- `VERIFY.md` currently records `NOT RUN`/`BLOCKED` for all hardware acceptance items. This is
  intentional and must not be reported as success.

See `docs/plan/PROJECT_PLAN.md` for the detailed WBS and `VERIFY.md` for the current evidence
state.

---

## 14. Document change log

| Date | Change | Author |
| --- | --- | --- |
| 2026-10-29 | Initial governance, architecture, plan, and agent rules | Lead architect |
