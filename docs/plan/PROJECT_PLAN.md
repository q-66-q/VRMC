# VRMC Project Plan

**Status:** Active — M0 complete; M1 partial.
**Baseline date:** 2026-10-29.
**Governing documents:** `AGENT.md` (process/architecture), `VERIFY.md` (acceptance),
`docs/feasibility/FEASIBILITY_AUDIT.md`, ADR-0001..0006.

---

## 1. Planning assumptions

- A small experienced team (2–4 engineers) with access to a Windows VR PC, SteamVR, a
  Minecraft/Vivecraft profile, and at least one physical Vision Pro for M2+.
- v1 supports Windows + NVIDIA + visionOS 27 + Minecraft 1.21.11 + Vivecraft 1.3.15 only.
- The client is distributed via TestFlight/Ad Hoc; App Store is not a v1 requirement.
- No game/mod binaries are distributed; users own and install them.
- Estimates are engineer-months (EM) and exclude downloads, legal review, and hardware
  procurement. They include tests/docs.
- Hardware-dependent work cannot pass gates in a workspace without the hardware; it is marked
  BLOCKED, not skipped.

---

## 2. Work breakdown structure

### WS-0 — Program, architecture, and verification

| ID | Task | Deliverable | Depends | Verification |
| --- | --- | --- | --- | --- |
| 0.1 | Repository reset and governance | AGENT.md, VERIFY.md, LICENSE, notices | — | docs check |
| 0.2 | Feasibility audit | FEASIBILITY_AUDIT.md | — | source references |
| 0.3 | ADRs | 0001..0006 | 0.2 | review |
| 0.4 | Project plan/test strategy | this file, TEST_STRATEGY.md | 0.2 | review |
| 0.5 | Skeleton, build scripts, CI | tree, scripts, workflows | 0.1 | AT-BUILD-* |
| 0.6 | Phase reports and risk log | handoffs, VERIFY updates | all | gate review |

### WS-1 — Protocol, transport, clocks

| ID | Task | Deliverable | Depends | Verification |
| --- | --- | --- | --- | --- |
| 1.1 | Protocol v1 spec | `protocol/PROTOCOL.md` | 0.3 | review |
| 1.2 | Reference codec + vectors | `protocol/tools`, `protocol/vectors` | 1.1 | AT-PROTO-04 |
| 1.3 | Swift codec | VRMCore | 1.2 | AT-PROTO-01/02 |
| 1.4 | C++ codec | bridge/core | 1.2 | AT-CPP-01/02 |
| 1.5 | Pairing + AEAD + replay | client/core + host | 1.1 | AT-NET-01/02 |
| 1.6 | Clock sync | both | 1.1 | AT-TIME-01/02, S-11 |
| 1.7 | UDP media/input framing, NACK/IDR | both | 1.1 | AT-PROTO-03, AT-SESSION-03 |
| 1.8 | Conformance + fuzz | scripts/tests | 1.3/1.4 | AT-CPP-02, CI |

### WS-2 — visionOS client platform

| ID | Task | Deliverable | Depends | Verification |
| --- | --- | --- | --- | --- |
| 2.1 | Swift package skeleton | VRMCore/Video/Render/Tracking | 0.5 | AT-BUILD-01 |
| 2.2 | App shell, permissions, pairing UI | VRMCApp | 2.1 | simulator build |
| 2.3 | Immersive CompositorServices renderer | VRMCRender | 2.1 | AT-BUILD-02 |
| 2.4 | VideoToolbox decoder | VRMCVideo | 2.1 | AT-VID-01/02 |
| 2.5 | Transport client + session state | VRMCore/Net | 1.3/1.5 | AT-SESSION-* |
| 2.6 | Telemetry + diagnostics | VRMCore | 1.1 | AT-TELEM-* |
| 2.7 | Synthetic provider + simulator demo | VRMCTracking/App | 2.2/2.3 | AT-E2E-01 |
| 2.8 | Privacy manifest, usage strings, archive validation | Resources | 2.2 | compliance |

### WS-3 — Hand tracking, gestures, mapping

| ID | Task | Deliverable | Depends | Verification |
| --- | --- | --- | --- | --- |
| 3.1 | ARKit hand/world adapters | VRMCTracking | 2.1 | MT-04 |
| 3.2 | Skeleton model, filters, prediction | VRMCore | 2.1 | AT-HAND-* |
| 3.3 | Gesture recogniser | VRMCore | 3.2 | AT-GEST-* |
| 3.4 | Mapping profiles + controller synthesis | VRMCore | 3.3, 1.1 | AT-MAP-* |
| 3.5 | Calibration/recenter UI + debug overlay | App | 3.1 | MT-04/07 |
| 3.6 | Tracking loss/occlusion state machine | VRMCore | 3.2 | AT-HAND-04, HT-08..10 |
| 3.7 | Usability tuning | profiles/docs | 3.4 | S-06, HT-02..19 |

### WS-4 — PC host and SteamVR driver

| ID | Task | Deliverable | Depends | Verification |
| --- | --- | --- | --- | --- |
| 4.1 | Portable bridge core + IPC | bridge/core | 1.4 | AT-CPP-* |
| 4.2 | OpenVR device provider | driver | 4.1 | AT-DRV-01, S-01 |
| 4.3 | Virtual HMD + display component | driver | 4.2 | S-01, S-12 |
| 4.4 | Two knuckles controllers + inputs/skeleton | driver | 4.2 | S-08 |
| 4.5 | Shared-memory snapshot + extrapolation | host/driver | 4.1 | AT-CPP-05 |
| 4.6 | WGC window capture | host/win | 4.1 | AT-CAP-01, S-07 |
| 4.7 | NVENC HEVC/H.264 low-latency | host/win | 4.6 | AT-ENC-01, S-07 |
| 4.8 | Host networking/session/clock/ABR | host | 1.5/1.6 | AT-NET-*, S-11 |
| 4.9 | Driver installer/uninstaller | scripts | 4.2 | MT-01/02 |
| 4.10 | Vivecraft profile/mirror configuration | scripts/docs | 4.2 | MT-02 |
| 4.11 | Runtime monitoring/restart | host | 4.8 | NF-08..10 |

### WS-5 — Media, rendering, latency

| ID | Task | Deliverable | Depends | Verification |
| --- | --- | --- | --- | --- |
| 5.1 | SBS eye mapping + projection validation | client | 2.3 | AT-RENDER-01 |
| 5.2 | Rotation-only late reprojection | client | 5.1 | AT-RENDER-02, S-05 |
| 5.3 | Latency telemetry end-to-end | both | 1.6, 2.6 | AT-TELEM-* |
| 5.4 | High-speed camera M2P study | test rig | 5.3 | MT-09, S-05 |
| 5.5 | ABR/quality degradation | both | 1.7, 4.7 | NF-05, MT-10 |
| 5.6 | Performance/thermal soak | test | 5.4 | MT-10 |

### WS-6 — Reliability and security

| ID | Task | Deliverable | Depends | Verification |
| --- | --- | --- | --- | --- |
| 6.1 | Client connection state machine | VRMCore | 2.5 | AT-SESSION-01..05 |
| 6.2 | Input release on every failure path | client/host | 3.6, 4.5 | AT-MAP-05 |
| 6.3 | Packet/replay/fuzz hardening | both | 1.5 | AT-NET-02, AT-CPP-02 |
| 6.4 | Clock recovery/no pose jump | both | 1.6 | AT-SESSION-05 |
| 6.5 | Runtime restart recovery | host/client | 4.11 | NF-08..10 |
| 6.6 | Security/privacy review | docs | 6.3 | compliance |

### WS-7 — Documentation and release

| ID | Task | Deliverable | Depends | Verification |
| --- | --- | --- | --- | --- |
| 7.1 | Architecture/protocol/hand mapping/streaming docs | docs | 0.2 | review |
| 7.2 | Install/run/troubleshoot/limits | docs/user | M3 | MT-12 |
| 7.3 | Performance report | docs/performance | 5.4 | MT-09 |
| 7.4 | Release scripts/notices/checklist | scripts, notices | all | AT-BUILD-* |
| 7.5 | new-user reproducibility test | docs | 7.2 | MT-12 |
| 7.6 | Final DoD audit/sign-off | VERIFY §10 | all | sign-off |

---

## 3. Milestones and exit criteria

| Milestone | Scope | Exit criteria | Verified by |
| --- | --- | --- | --- |
| **M0** Governance/feasibility/skeleton | docs, ADRs, plan, repo, CI, protocol draft | docs consistent; skeleton builds empty tests; spikes planned | docs check, CI |
| **M1** Client core + simulator | Swift core, decode, render, mock host, synthetic hands | simulator E2E stream/render/input; unit tests green; telemetry | AT-E2E-01/02, AT-BUILD-* |
| **M2** Device hand tracking | ARKit adapters, gestures, mapping, loss handling | both hands 27 joints, ≥72 Hz, gestures, recovery; device evidence | HT-01..20, MT-04 |
| **M3** PC bridge + Vivecraft | driver, host, capture, encode, networking | Vivecraft enters VR; live stereo; inputs; restart recovery | MT-01..03, S-01/02/07/08 |
| **M4** End-to-end gameplay | all interactions, latency, failure campaign | AC-1..5 demonstrated; budgets met or waiver | MT-05..11 |
| **M5** Release | hardening, docs, packaging, audit | AC-6; release checklist; sign-off | VERIFY §10 |

**Gate rule:** a milestone passes only with `VERIFY.md` evidence, green CI for its scope, no
open P0, and a posted handoff. Hardware milestones cannot pass in a workspace without the
hardware.

---

## 4. Critical path and sequencing

```text
M0 docs ─▶ M1 protocol/client/sim ─┬─▶ M2 device hands ─┐
                                   └─▶ M3 PC/driver ───┴─▶ M4 E2E ─▶ M5 release
```

Critical path: **S-01/S-02** (driver + DUAL capture) and **S-03** (device hands). These must
start as early as hardware access allows. M1 should provide a mock host early so the client is
not blocked on Windows work.

**Parallelisation:**

- Protocol/reference codec can be built before either client or driver.
- Swift core/tests and C++ core/tests can be developed in parallel against vectors.
- Mock host/synthetic hands unblock simulator UI/render work.
- Driver install scripts/docs can be written against the pinned OpenVR sample before hardware.

**Hard dependencies:** M4 needs M2+M3; M5 needs M4; S-05 needs real hardware; release needs
compliance review.

---

## 5. Test strategy

Full detail in `VERIFY.md` and `docs/testing/TEST_STRATEGY.md`.

- **Unit:** protocol codecs/vectors, clock math, pose math, gesture recognition, mapping,
  session state, packet reassembly, IPC seqlock, reprojection math.
- **Integration:** mock host ↔ simulator (stream/input/reconnect), C++/Swift clock parity,
  driver IPC with a fake host.
- **Hardware:** device hand tracking, Vivecraft session, capture/encode, latency, failure
  matrix, soak/thermal.
- **Manual:** on-device interaction checklist, new-user reproducibility, comfort/usability.
- **CI:** macOS Swift + visionOS simulator build; Linux/macOS C++ core; Windows compile smoke;
  docs/link/status checks. Hardware jobs require a self-hosted runner and are not assumed.
- **Evidence:** every gate links to `VERIFY.md` entries. Simulator is never evidence for
  device/hand/latency acceptance.

---

## 6. Repository, build, and CI plan

- Monorepo: `client/` (Swift), `bridge/` (C++), `protocol/`, `tools/`, `docs/`, `scripts/`.
- Swift package for pure core + XcodeGen app project; commit generated project for
  reproducibility. Build signing disabled by default; device builds use a configured team.
- C++ CMake: portable `core` library + tests everywhere; Windows-only `host`/`driver` targets
  guarded by platform checks. OpenVR fetched/pinned via CMake FetchContent or a vendored
  subset with BSD notice; no network at test time for core.
- CI workflows: `client-core`, `client-visionos`, `bridge-core`, `bridge-windows`, `docs`.
- Version pins in `versions.env`; scripts read it. Checksums for external downloads.
- Lint: SwiftFormat/SwiftLint when available, clang-format, markdown link/status checks.
- Artifacts: `artifacts/<version>/` with SHA-256 manifest; never commit binaries.

---

## 7. Documentation plan

| Document | Audience | Owner | Gate |
| --- | --- | --- | --- |
| README.md | everyone | lead | M0 |
| AGENT.md | agents/devs | lead | living |
| VERIFY.md | verification | verification owner | living |
| FEASIBILITY_AUDIT.md | architects | lead | M0 |
| ADRs | architects | lead | M0 |
| PROJECT_PLAN.md | team | lead | M0 |
| PROTOCOL.md | implementers | protocol owner | M1 |
| STREAMING.md | media/network | media owner | M1 |
| HAND_MAPPING.md | client/UX | tracking owner | M2 |
| TEST_STRATEGY.md | QA | verification owner | M0 |
| MANUAL_DEVICE_TESTS.md | device testers | verification owner | M2 |
| INSTALL/RUN/TROUBLESHOOT/LIMITATIONS | users | release owner | M5 |
| PERF_REPORT.md | reviewers | media owner | M4 |
| RELEASE_CHECKLIST.md | release | release owner | M5 |

---

## 8. Security, privacy, licensing, compliance plan

- Threat model: untrusted LAN peer, spoofed host, replay, malformed packets, DoS via
  allocation, leaked hand/video, driver privilege. Controls: pairing, authenticated
  encryption, replay window, bounded parsing, local-only default, redacted logs, least
  privilege.
- Privacy: hand data and video remain on LAN; no analytics; diagnostic bundles user-initiated;
  privacy manifest/usage strings.
- Licenses: Apache-2.0 original code; no Minecraft/Vivecraft binaries; OpenVR/NVENC/FFmpeg
  notices; arm's-length Vivecraft integration.
- Apple: public APIs, no JIT, normal entitlements; TestFlight/Ad Hoc v1; archive validation.
- Minecraft EULA: user-owned; no assets; no auth bypass.
- Release: artifact scan, notice audit, privacy review, encryption declaration.

---

## 9. Risk register

| Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- |
| SteamVR rejects virtual driver (S-01) | Medium | Critical | Prototype driver early; use simplehmd reference; fallback direct mode | Driver |
| DUAL capture unusable (S-02) | Low–Med | Critical | Source audit done; early Windows spike; fallback direct mode | Host |
| Hand tracking rate/accuracy insufficient (S-03) | Low | Critical | Early device spike; filter/predict; controller fallback | Tracking |
| Latency target missed (S-05) | Medium | High | Budgets, instrumentation, reprojection, ABR; quantified waiver path | Media |
| Gesture usability poor (S-06) | Medium | High | Profiles, tuning, controller fallback; manual tests | UX |
| Wi‑Fi instability | High | Medium | 6E/dedicated AP, jitter buffer, NACK/FEC, ABR, docs | Network |
| SteamVR/Vivecraft version drift | Medium | Medium | Pins, smoke matrix, compatibility docs | Integration |
| Windows capture/DPI issues | Medium | Medium | Borderless fixed-size window, validation, WGC tests | Host |
| Driver security/privilege | Low | High | Minimal driver, no network in driver, shared-memory validation | Driver |
| App Review/policy | Medium | Medium | TestFlight/Ad Hoc; privacy docs; policy review | Release |
| Hardware unavailable for gates | High in some environments | High | Mark BLOCKED; do not fake; plan self-hosted rig | Program |
| Thermal throttling | Medium | Medium | Quality scaling, 30-min soak | Client |
| Scope creep (audio, other games) | High | Medium | Explicit non-goals; v1.1 backlog | Lead |

---

## 10. Fallback plans

- **Driver rejected:** switch to a direct-mode driver (ADR-0002 upgrade) or a patched
  Vivecraft fork (LGPL, separate artifact) only after a new ADR and budget.
- **Mirror capture rejected:** direct-mode frame capture; or capture via a compositor API.
- **Latency missed:** reduce eye resolution/bitrate, target 72 Hz, increase reprojection,
  optimize capture path; if still missed, quantify and get an explicit waiver with mitigation.
- **Hand gestures unusable:** ship controller fallback for v1 and continue hand R&D; does not
  satisfy acceptance unless hands still drive core interactions.
- **Device unavailable:** complete M0/M1 and source-complete M2/M3; mark hardware gates
  BLOCKED. A release cannot be claimed.

---

## 11. Milestone log

| Milestone | Date | Commit | Evidence | Status |
| --- | --- | --- | --- | --- |
| M0 | 2026-10-30 | `aad28d0` | EV-0001/EV-0002; docs/CI | COMPLETE |
| M1 | 2026-10-30 | `aad28d0` | EV-0002/EV-0003 | PARTIAL (simulator passes; secure/device/PC incomplete) |
| M2 | — | — | — | BLOCKED (device) |
| M3 | — | — | — | BLOCKED (Windows/SteamVR) |
| M4 | — | — | — | BLOCKED |
| M5 | — | — | — | NOT STARTED |

---

## 12. Current next actions

1. Finish M0: commit docs, skeleton, scripts, CI, protocol draft; run docs/build checks.
2. Build M1 thin vertical slice: Swift core + tests, protocol reference codec, mock host,
   simulator stream/render, synthetic hands.
3. Prepare M2/M3 spike packages and hardware checklists; do not claim them without hardware.
4. Update `VERIFY.md` with actual local evidence and keep hardware items BLOCKED.
