# VRMC — Agent Operating Manual

**Project:** VRMC (working name) — Minecraft: Java Edition + Vivecraft running natively on Apple Vision Pro.
**Status:** M0 — specification, spikes, and skeleton. No product code exists yet.
**Last updated:** 2026-10-31.
**Baseline commit:** `a96e13b` (repo reset); the two reference source trees are untracked in the working tree.
**Authority:** `AGENT.md` governs process, architecture, and scope. `VERIFY.md` governs acceptance and
evidence; where they conflict on acceptance, `VERIFY.md` wins.

---

## 0. Read-first rules

1. Read §1–§4 of this file and all of `VERIFY.md` before changing anything that affects a gate.
2. **Never claim a feature works without an evidence entry in `VERIFY.md`.** Code inspection is
   `PARTIAL`, not `PASS`. The simulator is never evidence for hands, stereo optics, thermals, or
   latency.
3. Do not commit third-party source trees (`Amethyst-iOS-main/`, `VivecraftMod-Multiloader-26.2/`),
   Minecraft binaries/assets, prebuilt IPAs, or SteamVR/OpenVR binaries. See §10.4.
4. Hardness ratings in §4 are planning commitments. If a spike invalidates one, update §4 **and**
   log the change in `VERIFY.md` §10.
5. Version pins live in one place (`versions.env`, planned). Changing a pin requires an ADR.
6. The app is **GPL-3.0** (Amethyst-derived). Our Vivecraft companion mod is **LGPL-3.0** with
   published source. Vivecraft itself stays unmodified. See §10.6.
7. Comfort is a feature, not polish. Vignette, snap turn, teleport, seated mode, and recenter are
   acceptance criteria.

---

## 1. What we are building

### 1.1 MVP definition

> A user installs VRMC on Apple Vision Pro, signs in with Microsoft (or uses Offline), installs
> Minecraft 26.2 + Fabric + Vivecraft from the launcher, enters a world, and plays in head-tracked
> stereo with hands — and with PlayStation VR2 Sense controllers when present — for an hour, with
> no PC involved.

### 1.2 MVP success criteria (mirrored in `VERIFY.md` §1)

| ID | Criterion |
|---|---|
| AC-1 | Fresh sideload → in-world in ≤ 30 min on a 100 Mbps link, using only documented steps. |
| AC-2 | Immersive stereo via CompositorServices: correct per-eye projection and eye order, head tracking active, 90 Hz target with graceful fallback. |
| AC-3 | Core play: move, turn, teleport, jump/sneak, break/place, attack/use, inventory, hotbar, crafting/chests, pause/settings, bow, climbing, save/reload. |
| AC-4 | Every P0 action reachable from hands; P0 actions also reachable from PSVR2 controllers; no stuck input on tracking loss. |
| AC-5 | 60-minute session, 20 cold launches, 10 world loads, zero compositor watchdog kills. |
| AC-6 | No Minecraft binaries in git; ownership gate + EULA notice; GPL-3.0 source published; third-party notices complete. |

### 1.3 Non-goals (MVP)

App Store/TestFlight/Ad Hoc; AOT builds; PC/cloud streaming; SteamVR/OpenVR/OpenXR runtime;
modpack marketplace; shaders/Iris parity; multiplayer hosting; video streaming; MC 26.3+ until
Vivecraft supports it; redistribution of Minecraft binaries or assets.

### 1.4 Positioning

A public project (`rebelancap/vivecraft-visionos`) already runs MC 26.2 + Vivecraft on Vision Pro
via GraalVM AOT + Klepton, sideloaded. We do not compete on "first to run it". We compete on the
**launcher**: accounts, user-managed installs and mods, version agility, diagnostics, and input /
comfort polish.

---

## 2. Current state (2026-10-31)

- Git history: a single `delete` commit (`a96e13b`) removed the previous remote-streaming
  implementation. That architecture is retired; only its hand-mapping and comfort research informs
  this design.
- Reference sources are present and **git-ignored** (never committed):
  - `Amethyst-iOS-main/` — 525 files, 126 MB (GPL-3.0 iOS launcher).
  - `VivecraftMod-Multiloader-26.2/` — 863 files, 13 MB (LGPL-3.0, MC 26.2, Vivecraft 1.3.15).
- **M0 foundation landed** (`3332cdb`, `d25aa49`, `7c684f2`, `d07436d`): `.gitignore`, `versions.env`,
  GPL/LGPL licenses + third-party notices, ADRs 0001–0006, `docs/mvp/{MVP_SCOPE,SPIKES,ACCEPTANCE}.md`,
  component READMEs (`launcher/`, `runtime/`, `provider/`, `bridge/`), and tooling
  (`check_versions.sh`, `bootstrap.sh`, `log_evidence.sh`). Product code is not started.
- Hardware is available: a paired Apple Vision Pro (`RealityDevice14,1`, N301AP, 1 TB, visionOS 27.2
  reported) and a Mac build host (MacBook Pro Mac16,7, Apple M4 Pro, 24 GB, macOS 27.0.1,
  Xcode 27.2, visionOS 27.2 SDK, visionOS 27.0 simulator runtime).
- Spike progress: S1 host pre-test `PARTIAL` (EV-0004: relabelled iOS JRE 25 JITs on macOS and the
  JIT26 request site traps); S2 host boot `PARTIAL` (EV-0005: MC 26.2 Vulkan via MoltenVK 1.4.2,
  no GL fallback); S3 static analysis `PARTIAL` (EV-0006: stable injection point); S1a harness
  scaffolded and compile-checked (EV-0007). Device S1/S2, world render/soak, and S3 runtime remain
  `NOT RUN`; the AVP provisioning profile is still missing.
- Evidence baseline: `VERIFY.md` EV-0001 (`PARTIAL`, toolchain/reference inspection), EV-0002
  (`PARTIAL`, external JIT26 demonstration), EV-0003 (`PASS`, tooling self-test), EV-0004
  (`PARTIAL`, host-only S1 pre-test), EV-0005 (`PARTIAL`, host-only S2 boot pre-test), and EV-0006
  (`PARTIAL`, S3 static analysis). Only evidence IDs recorded in `VERIFY.md` §6 are valid.

---

## 3. Architecture

### 3.1 Stack

```text
visionOS app (SwiftUI + ObjC++ bridge)
├─ Launcher shell (SwiftUI) ....... accounts, installer, settings, logs, JIT check
├─ JVM runtime ................... OpenJDK 25 HotSpot (xros), JIT via debugger-prepared memory
│   ├─ Minecraft 26.2 + Fabric 0.19.3
│   ├─ Vivecraft 26.2-1.3.15 (unmodified, user-installed)
│   └─ VRMC Vision Provider (LGPL-3.0 mod): MCVR + VRRenderer + action data
├─ Native VR bridge (ObjC++/C)
│   ├─ ARKit HandTrackingProvider (27 joints) + WorldTrackingProvider (predicted head)
│   ├─ GameController GCSpatialAccessory (PSVR2 Sense) + AccessoryTrackingProvider
│   └─ CompositorServices LayerRenderer (stereo, foveation)
└─ Graphics: MC "Prefer Vulkan" → MoltenVK (visionOS build) → Metal
```

### 3.2 Components

| Component | Responsibility | Hardness |
|---|---|---|
| Launcher shell | First-run, accounts, installs, settings, logs, JIT gate, immersive entry | MEDIUM |
| JVM/JIT runtime | OpenJDK 25 on xros, JIT provisioning, memory limits, LWJGL 3.4.1 natives | **HIGH** |
| Graphics path | MC Vulkan renderer via MoltenVK; GL/LTW fallback | **HIGH** |
| Vision Provider mod | `MCVR` + `VRRenderer` subclasses; action data without SteamVR | MEDIUM |
| Native VR bridge | Head/hand/controller tracking, eye-texture handoff, frame pacing | **HIGH** |
| Input mapping | PSVR2 profile + hand gestures → Vivecraft actions | MEDIUM |
| Gameplay verification | Vivecraft features exercised in VR end-to-end | MEDIUM |
| Diagnostics | Boot/frame/thermal logs, overlay, export | LOW |
| Compliance | GPL/LGPL/EULA obligations, notices, ownership gate | MEDIUM |

### 3.3 Data flow (per frame)

1. ARKit/world tracking produces a predicted device anchor for the presentation time.
2. Bridge passes head pose + controller/hand state to the provider (JNI, versioned ABI).
3. Provider fills `hmdPose`/`hmdRotation`/`controllerPose[]` and per-hand `VRInputAction` data.
4. Minecraft renders both eye targets through its Vulkan backend (MoltenVK).
5. Provider publishes the two eye images; bridge obtains `MTLTexture` handles and samples them into
   the CompositorServices drawable for the matching eye.
6. Compositor presents; timing feedback (deadline, predicted anchor) is returned to the provider.

### 3.4 Bridge ABI (v1, version-checked at init)

`vrmc_init(caps_json)`, `vrmc_get_head_pose(out, timestamp)`, `vrmc_poll_input(out)`,
`vrmc_submit_eyes(left, right, fence, frame_index)`, `vrmc_frame_timing(out)`,
`vrmc_recenter(mode)`, `vrmc_haptic(hand, amplitude, frequency, duration)`.

Failure to parse `caps_json` or a version mismatch must fail loudly at startup, never silently.

### 3.5 Provider integration rule

- Default path: Vivecraft stays **unmodified**. A separate LGPL mod Mixins `VRState.initializeVR`
  to instantiate `VisionVR` and select our renderer.
- There is **no public provider-replacement API** (the public `VRClientAPI` is read-only), so the
  injection point is an internal detail. S3 must prove it against the decompiled 26.2‑1.3.15 jar
  and across 26.2.x patch versions.
- If S3 shows Mixin injection is unstable, a fork is the approved fallback: an ADR, an LGPL‑3.0
  source release, and a documented rebase strategy. The Mixin-vs-fork decision is made at the M0
  exit gate, not deferred to M2.
- All provider code that touches Vivecraft internals stays in `provider/` and is LGPL-3.0.

### 3.6 Repo layout (planned in M0)

`launcher/` (Swift/SwiftUI), `runtime/` (JRE build, LWJGL stubs/natives), `provider/` (Java mod),
`bridge/` (C++/ObjC++), `scripts/`, `docs/`, `evidence/` (ignored), `versions.env`.

---

## 4. Hardness ratings

### 4.1 Rubric

| Rating | Meaning | Typical effort | Required before implementation |
|---|---|---|---|
| **LOW** | Established pattern; local change; no platform unknowns | Days | Unit test or documented device check |
| **MEDIUM** | Integration across ≥2 subsystems, or needs device measurement | 1–3 weeks | Design note + test plan |
| **HIGH** | Unproven platform capability or architecture-invalidating risk | ≥3 weeks | Spike with go/no-go and a fallback |

Rules: HIGH items must be resolved by a spike before dependent work hardens. A failed HIGH item
triggers its fallback and a scope/ADR change, not silent scope creep.

### 4.2 Summary (MVP P0 register, 65 items)

| Hardness | Count | Examples |
|---|---|---|
| **LOW** | 32 | accounts, downloads, Fabric install, menus, Files import, diagnostics |
| **MEDIUM** | 26 | launcher shell, JIT launch flow, provider wiring, input mapping, gestures, audio |
| **HIGH** | 7 | OpenJDK 25 xros runtime, Vulkan/MoltenVK boot, stereo eye handoff, frame pacing, perf/thermal |

Counts reflect **A2 = MEDIUM** after EV-0002 (external JIT26 demonstration). A2 drops to LOW only if
provisioning persists across launches; C3 stays HIGH until the OpenJDK 25 xros runtime, LWJGL natives,
and the in-MC code-cache path are built. Any further move must follow §4.7.

### 4.3 P0 feature register by area

#### A. Install, launch, lifecycle

| ID | Feature | Hardness | Note |
|---|---|---|---|
| A1 | Sideload install (SideStore/IPA) + first-run wizard | MEDIUM | External sideload tooling is the dependency |
| A2 | JIT launch flow + guided readiness | MEDIUM | External JIT26 requires a debugger-prepared memory step per launch (EV-0002), so the productization case is the per-launch ritual. Still open: M2/M5 coverage, persistence across kill/reboot, distribution closure, failure UX. LOW only if provisioning persists; back to HIGH if our app cannot use the protocol. **S1a criterion 4 (cold-relaunch reproduction or proven persistence) makes the LOW/MEDIUM call** |
| A3 | Hand-tracking permission + denial handling | LOW | Standard ARKit authorization |
| A4 | Launcher → game window → immersive entry prompt | LOW | One immersive space; do not auto-immerse |
| A5 | Boot progress, phase log, timing | LOW | — |
| A6 | Save-and-exit, suspend/resume, scene phase | MEDIUM | Must not corrupt saves |
| A7 | Crash capture + safe restart | MEDIUM | Needs log capture before process death |
| A8 | Storage management / disk-full handling | LOW | — |

#### B. Accounts

| ID | Feature | Hardness | Note |
|---|---|---|---|
| B1 | Microsoft device-code sign-in (Keychain) | LOW | Amethyst has the flow; device code preferred in VR |
| B2 | Offline profile (single-player only) | LOW | — |
| B3 | Ownership gate + cached-token offline start | LOW | Policy to be recorded in ADR-0006 (planned) |
| B4 | Account list, switch, remove | LOW | Per-account worlds |

#### C. Game install and runtime

| ID | Feature | Hardness | Note |
|---|---|---|---|
| C1 | Pinned 26.2 catalog; unsupported versions blocked | LOW | Vivecraft supports `26.2.x` only |
| C2 | Download/verify/resume (jar, libs, assets) | LOW | SHA-1 from Mojang metadata |
| C3 | Bundled Java 25 runtime for xros | **HIGH** | Stays HIGH until the full runtime exists: OpenJDK 25 xros build + LWJGL 3.4.1 natives + `-XX:+MirrorMappedCodeCache` inside a real MC process. EV-0002 and S1 prove the mechanism only; they do not build or validate this runtime |
| C4 | Memory defaults/limits + VA validation | MEDIUM | visionOS jetsam ceiling undocumented |
| C5 | Fabric 0.19.3 install | LOW | Official metadata |
| C6 | Vivecraft 26.2-1.3.15 download/verify/install | LOW | Modrinth/official source only |
| C7 | Provider mod install + version compatibility | LOW | Fail closed on mismatch |
| C8 | Files import/export (worlds, mods) | LOW | — |

#### D. Graphics and presentation

| ID | Feature | Hardness | Note |
|---|---|---|---|
| D1 | Vulkan via MoltenVK on visionOS | **HIGH** | S2; push descriptors/dynamic rendering untested |
| D2 | Flat window mode (title/menus/installers) | MEDIUM | Needs LWJGL 3.4.1 GLFW stub + native layer |
| D3 | Immersive stereo via CompositorServices | **HIGH** | S4; per-eye texture handoff |
| D4 | Head tracking, recenter, seated/standing | MEDIUM | Predicted anchor correctness matters |
| D5 | Frame pacing, 45 Hz repeat, thermal step-down | **HIGH** | S6; watchdog terminates on misses |
| D6 | Resolution presets + render scale | MEDIUM | Tuned by S6 |
| D7 | Debug overlay (frames, backend, pose, thermal) | LOW | — |

#### E. VR provider

| ID | Feature | Hardness | Note |
|---|---|---|---|
| E1 | `VisionVR` selected without SteamVR | MEDIUM | S3; Mixin into `VRState` |
| E2 | `VRRenderer` subclass + Vulkan eye targets | MEDIUM | Reuse `VulkanHelper` patterns |
| E3 | Action data for ~105 actions × 2 hands | MEDIUM | No external injection layer exists |
| E4 | Haptic routing | LOW | No-op for hands |
| E5 | IPD, eye offsets, play area, runtime identity | LOW | — |

#### F. Controller input (P0 when PSVR2 Sense is available)

| ID | Feature | Hardness | Note |
|---|---|---|---|
| F1 | Detect PSVR2 Sense: poses, buttons, sticks, triggers, grips | MEDIUM | visionOS 26+ spatial accessories |
| F2 | Default Touch-style mapping profile | MEDIUM | Parity with prior art bindings |
| F3 | Per-hand takeover (controller vs hands) | MEDIUM | **Assumption pending S5:** visionOS 27 is documented to stop hand tracking for a held controller; verify on device, do not treat as fact |

#### G. Hand input

| ID | Feature | Hardness | Note |
|---|---|---|---|
| G1 | 27-joint skeleton, both hands, per-frame timestamps | LOW | ARKit API is straightforward |
| G2 | Gesture set with hysteresis | MEDIUM | Usability tuning is the risk |
| G3 | Virtual stick, snap turn, teleport gesture | MEDIUM | Dead zone/deflection tuning |
| G4 | Tracking-loss release/reacquire | MEDIUM | No stuck input is the acceptance bar |
| G5 | Calibration: dominant hand, height, recenter | LOW | — |

#### H. Gameplay (Vivecraft features)

| ID | Feature | Hardness | Note |
|---|---|---|---|
| H1 | Continue newest / title screen / create world | LOW | Launcher + game entry |
| H2 | Free move, smooth/snap turn, teleport, jump, sneak | LOW | Vivecraft implements; mapping matters |
| H3 | Seated and standing modes | LOW | Vivecraft settings |
| H4 | Break/place/attack/use/eat/entity interact | MEDIUM | Verification across both input modes |
| H5 | Inventory, hotbar, crafting, chests, drag/drop | MEDIUM | In-world GUI interaction |
| H6 | Pause, options, death/respawn | MEDIUM | Menus in VR |
| H7 | Visible hands, held item, player model | LOW | — |
| H8 | Bow (two-handed draw/aim/release) | MEDIUM | Two-hand tracking accuracy |
| H9 | Climbing (grab/climb/jump-off) | MEDIUM | Interaction + comfort |
| H10 | Save/reload, settings persistence | LOW | — |

#### I. Launcher UX and diagnostics

| ID | Feature | Hardness | Note |
|---|---|---|---|
| I1 | Home (account, Continue, Title, resolution, details, launch) | LOW | — |
| I2 | Settings (graphics, audio, comfort, controls, advanced) | LOW | — |
| I3 | Progress, errors, retry, cancel | LOW | — |
| I4 | Diagnostics: log viewer/export, frame graph, versions, thermal | LOW | — |

#### J. Platform and compliance

| ID | Feature | Hardness | Note |
|---|---|---|---|
| J1 | Audio via OpenAL (xros) + AVAudioSession | MEDIUM | openal-soft rebuild required |
| J2 | Haptics (CoreHaptics) for controllers | LOW | — |
| J3 | Files app integration | LOW | — |
| J4 | Privacy manifest, usage strings, no default telemetry | LOW | — |
| J5 | GPL source publication, notices, EULA/ownership gate | MEDIUM | Legal boundary for the provider mod |

#### K. Quality gates

| ID | Target | Hardness | Note |
|---|---|---|---|
| K1 | Launcher ≤ 10 s; launch → in-world ≤ 90 s | MEDIUM | JIT + MC load time |
| K2 | 90 Hz target; ≥ 72 fps sustained at default preset | **HIGH** | S6; main performance risk |
| K3 | Rotational M2P ≤ 50 ms P50 / ≤ 65 ms P95 | **HIGH** | Measurement dependency: the 240 fps rig protocol **and rig availability** must be delivered in M0/M1; otherwise M6 cannot produce evidence |
| K4 | 60-min session, 20 launches, 10 loads, no watchdog kill | MEDIUM | Soak discipline |
| K5 | Thermal step-down predictable; 45 fps floor | **HIGH** | Sustained load on a wearable |
| K6 | Install ≤ 3.5 GB; first install ≤ 30 min | LOW | — |

### 4.4 P1 register (post-MVP)

| Feature | Hardness |
|---|---|
| Mod manager UI + Modrinth install | MEDIUM |
| Multiple MC versions | MEDIUM |
| Join multiplayer servers | MEDIUM |
| Voice chat | MEDIUM |
| System-keyboard chat | MEDIUM |
| Controller remap + left-handed profile | MEDIUM |
| Mirror window, screenshots, recording | LOW |
| Foveation / dynamic quality tuning | MEDIUM |
| Multiple instances | LOW |
| Shaders / Iris | **HIGH** |
| Pass-through / mixed reality | **HIGH** |
| Full-body trackers | MEDIUM |
| Custom spatial accessories | MEDIUM |
| Localization | LOW |
| Cloud save | MEDIUM |
| App Store feasibility study | **HIGH** |

### 4.5 Spike hardness and critical path

| Spike | Question | Hardness | Status | Fallback |
|---|---|---|---|---|
| S1 | JIT mechanism on visionOS (reference JVM + minimal app; OpenJDK 25 build is C3) | MEDIUM | `NOT RUN` — external `PARTIAL` (EV-0002) + host `PARTIAL` (EV-0004) | Pivot to AOT; launcher scope reduces |
| S2 | MC 26.2 Vulkan on MoltenVK/xros | **HIGH** | `NOT RUN` — host boot `PASS` for host stage (EV-0005); device pending | GL/LTW→ANGLE path |
| S3 | Vivecraft provider without SteamVR | MEDIUM | `NOT RUN` — static analysis `PARTIAL` (EV-0006); runtime Mixin pending | Fork approved by ADR + LGPL source |
| S4 | Eye textures → CompositorServices | **HIGH** | `NOT RUN` | GPU blit, then readback as last resort |
| S5 | PSVR2 + hands drive all P0 actions | MEDIUM | `NOT RUN` | Hands-only MVP |
| S6 | Frame pacing / thermals on device | **HIGH** | `NOT RUN` | Lower preset, 45 Hz lock, render-distance cap |

**Gate order:** S1 (internal reproduction) → S2 → S4 → S6. EV-0002 de-risks the mechanism only; M1
does not start until S1 has an internal EV. If S1 fails internally, the launcher pivots to AOT. When a
spike changes status, apply §4.7 in the same commit.

### 4.6 Subsystem heat map

| Subsystem | Hardness | Why |
|---|---|---|
| JIT mechanism (S1) | MEDIUM | JIT26 demonstrated externally (EV-0002); host pre-test EV-0004; device reproduction pending |
| OpenJDK 25 xros runtime + LWJGL natives + code cache (C3) | **HIGH** | Runtime build and in-MC integration unproven |
| Graphics translation | **HIGH** | Host boot verified with MoltenVK 1.4.2 (EV-0005); xros stack unproven |
| Stereo compositor | **HIGH** | Foreign-texture handoff + deadline discipline |
| Performance/thermal | **HIGH** | Watchdog kills on missed frames |
| VR provider | MEDIUM | Static injection point exists and is stable 1.3.14→1.3.15 (EV-0006); runtime Mixin unproven |
| Input & gestures | MEDIUM | Usability, not feasibility |
| Launcher shell | MEDIUM | visionOS UI port |
| Accounts/downloads | LOW | Amethyst-proven logic |
| Compliance | MEDIUM | GPL/LGPL/EULA boundaries |

### 4.7 Status propagation checklist

When a spike resolves (pass or fail), **one commit** must update every location that encodes its
status. A status present in one place and stale in another is a review-rejecting defect.

| # | Location | What changes |
|---|---|---|
| 1 | §4.2 summary | counts, if a feature hardness moves |
| 2 | §4.3 affected feature rows | hardness and notes |
| 3 | §4.5 spike table + critical path | status, evidence pointer, ordering |
| 4 | §4.6 subsystem heat map | split or close rows |
| 5 | §6 spike table | pass criteria, status, timebox, EV pointer |
| 6 | §7 milestone exit criteria | gate wording |
| 7 | §11 risk register | close or split rows |
| 8 | `VERIFY.md` | EV entry (§6), next ID (header/§5.1), dashboard (§7) |
| 9 | §13 change log | one line naming the EV |

Evidence IDs are allocated only by recording an entry in `VERIFY.md` §6.

---

## 5. Pins

| Component | Pin | Notes |
|---|---|---|
| Minecraft Java | 26.2 | Java 25; LWJGL 3.4.1; experimental Vulkan (Vulkan 1.2) |
| Minecraft assets | Downloaded at install | Never committed |
| Fabric loader | 0.19.3 | Matches Vivecraft build |
| Vivecraft | 26.2-1.3.15 | LGPL-3.0; supports `26.2.x` only |
| Java runtime | OpenJDK 25 (xros build, TBD) | Component `java-runtime-epsilon` upstream |
| LWJGL | 3.4.1 | visionOS natives TBD |
| MoltenVK | Pinned build TBD | visionOS support required |
| Xcode / SDK | 27.2 / visionOS 27.2 | Build host measured |
| Sideload | SideStore / iloader | No TrollStore/Ad Hoc on visionOS |
| Amethyst reference | Upstream `AngelAuraMC/Amethyst-iOS` | GPL-3.0; do not commit |
| Prior art (benchmark) | `rebelancap/vivecraft-visionos` | Not a dependency; no code copied |

All pins move to `versions.env` in M0; changes require an ADR.

---

## 6. Spikes and gates

| ID | Goal | Pass criteria | Evidence | Timebox |
|---|---|---|---|---|
| S1 | JIT mechanism on device (internal reproduction) | A **reference JVM** + minimal Java app JIT-compiles and runs on D1 under JIT26; log proves debugger-prepared memory and compiled methods; no W^X failure. OpenJDK 25 xros is **C3**, not S1. EV-0002 is external and EV-0004/EV-0007 are host-only; none satisfies this row | EV-0002 external + EV-0004 host pre-test + EV-0007 scaffold, all `PARTIAL`; device EV pending | 3–4 wk (S1a ~1 wk, S1b 1.5–3 wk) |
| S2 | MC 26.2 Vulkan boots | Host: backend Vulkan + MoltenVK, no fallback. Device: world renders; 30 min stable | EV-0005 (host boot, `PARTIAL`); device EV pending | 2–3 wk |
| S3 | Provider integration | Vivecraft enters VR with `VisionVR`; action debug populated; no SteamVR; **and** the injection point is evidenced in the decompiled 26.2‑1.3.15 jar and holds across 26.2.x patch versions | EV-0006 (static, `PARTIAL`); runtime EV pending | 2–3 wk |
| S4 | Compositor stereo | Both eyes correct; shared-event sync; 90 Hz; no tearing over 10 min | pending | 2–3 wk |
| S5 | Input coverage | Full P0 action checklist from hands and controllers | pending | 2–3 wk |
| S6 | Perf/thermal | K2/K5 met or a documented waiver with mitigation | pending | 2–3 wk |

EV-0002 records an external JIT26 demonstration on Vision Pro (`PARTIAL`). It is **context, not
project evidence**: S1 still requires a recorded internal EV from a reference JVM on D1, and C3 owns
the OpenJDK 25 xros build.

S3 carries an **M0 exit deadline**: if the Mixin injection point is not evidenced as stable by then,
the fork fallback is chosen by ADR and the provider work plan is re-baselined.

A spike passes only with a `VERIFY.md` evidence entry. A failed spike triggers its fallback and an
ADR; it is never quietly downgraded.

---

## 7. Milestones

| Milestone | Scope | Exit criteria | Hardness | Est. |
|---|---|---|---|---|
| **M0** | Docs, skeleton, versions.env, S1/S2, S3 decision | S1 internal reproduction EV (EV-0002 is external only); status propagated per §4.7; S2 pass; S3 Mixin-vs-fork decision recorded | **HIGH** | 3–4 wk |
| **M1** | Launcher shell + install + flat MC boot | Fresh install → flat world | MEDIUM | 4–6 wk |
| **M2** | Provider + Vulkan VR | Provider init, stereo eye targets, no SteamVR | **HIGH** | 4–5 wk |
| **M3** | Compositor stereo + head tracking | 30-min immersive session | **HIGH** | 4 wk |
| **M4** | Input (controllers, hands, gestures) | P0 action checklist passes | MEDIUM | 4–6 wk |
| **M5** | Gameplay loop + comfort + diagnostics | All H features pass | MEDIUM | 3–4 wk |
| **M6** | Hardening + acceptance | AC-1…AC-6 + K gates evidenced | MEDIUM | 2–3 wk |

Total ≈ 12–17 engineer-months. S1's internal reproduction is the M0 gate; S2 and the S3 decision
also bound M0.

**M0 timing and exit rule.** M0 is **evidence-gated, not calendar-gated**. Target 3–4 weeks with S3
run in parallel and the AVP provisioning profile started early. If the calendar slips, M0 may close
only when all three gates pass — S1 internal EV, S2 device pass, S3 decision — plus a written
documentation-convergence plan. No `NOT RUN` item may be presented as passed.

---

## 8. Commands

| Command | Purpose | Status |
|---|---|---|
| `scripts/check_versions.sh` | Toolchain + reference-pin check (read-only) | IMPLEMENTED (2026-10-31) |
| `scripts/bootstrap.sh` | Prerequisite check + local dirs (no downloads) | IMPLEMENTED (2026-10-31) |
| `scripts/log_evidence.sh` | Allocate EV ID, bundle artifacts, write manifest + entry template | IMPLEMENTED (self-tested 2026-10-31) |
| `scripts/build_jre.sh` | Build OpenJDK 25 for xros | NOT IMPLEMENTED |
| `scripts/build_launcher.sh` | Build the visionOS app | NOT IMPLEMENTED |
| `scripts/build_provider.sh` | Build the provider mod jar | NOT IMPLEMENTED |
| `scripts/test_local.sh` | Run host-side unit tests | NOT IMPLEMENTED |
| `scripts/install_device.sh` | Install to a paired Vision Pro | NOT IMPLEMENTED |
| `scripts/latency_rig.sh` | Drive the K3 camera protocol + tabulate samples | NOT IMPLEMENTED |
| `runtime/probes/s1a/build.sh` | Build/sign/install the S1a iOS JIT probe | SCAFFOLD — compiles; signing/install pending AVP profile |

`scripts/log_evidence.sh` is an **M0 deliverable** and is now implemented and self-tested (§13). Its
own acceptance is `AT-009`, logged in `VERIFY.md`.
The K3 latency-rig protocol (camera settings, measurement steps, sample table) is also an M0
deliverable, because K3 is HIGH for a measurement dependency rather than a feasibility risk.

Do not document or claim a command works until it exists and its run is logged.

---

## 9. Verification protocol

- Every test result goes into `VERIFY.md` as an `EV-####` entry. Format and manifest fields are in
  `VERIFY.md` §5.
- Status values: `PASS`, `PARTIAL`, `FAIL`, `BLOCKED`, `NOT RUN`, `N/A`.
- `PASS` requires a reproducible procedure, the exact build commit, and linked artifacts (log,
  screenshot, measurement, video). Re-run after any change that can affect the result.
- Never fabricate, backfill, or copy evidence between builds, devices, or sessions.
- Flaky failures are defects, not noise.
- Device evidence must include: date, commit, dirty state, device model/OS, app build hash,
  Minecraft/Fabric/Vivecraft versions, steps, expected/actual, artifact paths.
- The next evidence ID is always stated in the `VERIFY.md` header and §5.1.
- When a spike resolves, apply the §4.7 propagation checklist in the same commit; a stale status is
  a defect.

---

## 10. Agent rules

### 10.1 Scope discipline
Work only within the approved milestone. A new feature request goes to the backlog with a hardness
rating; it does not get silently added to the current milestone.

### 10.2 Evidence discipline
Update `VERIFY.md` in the same change that alters a gate. No "should work" language in status
surfaces. README/status tables must match `VERIFY.md`.

### 10.3 Change hygiene
- Read files before editing; prefer small targeted edits.
- Run the relevant tests before declaring a task done.
- Review the full diff before commit; do not commit generated binaries or caches.
- Keep `AGENT.md`, `VERIFY.md`, and `docs/mvp/*` consistent in the same commit.

### 10.4 Reference sources and third-party material
- `Amethyst-iOS-main/` and `VivecraftMod-Multiloader-26.2/` are **reference sources**, not part of
  this project. They must be git-ignored or moved to an ignored `vendor/` directory before the first
  product commit.
- Never commit Minecraft jars/assets, IPAs, prebuilt framework binaries, or SteamVR/OpenVR binaries.
- Record the upstream commit/hash whenever a reference is used in a design decision.

### 10.5 Licensing boundaries
- App: GPL-3.0 (derived from Amethyst). Publish corresponding source for every distributed build.
- Provider mod: LGPL-3.0. Publish source; keep it a separate artifact that can be replaced.
- Vivecraft: unmodified, user-installed; no derivative work unless an ADR approves a fork.
- Minecraft: user-owned; no redistribution; ownership gate and EULA notice required.
- Third-party notices for MoltenVK (Apache-2.0), LWJGL (BSD-3), openal-soft (LGPL-2), LTW (LGPL-3),
  ANGLE (BSD-3), and every bundled dependency.

### 10.6 Safety
VR discomfort is a real risk. Keep comfort settings reachable, warn about motion, default to
vignette + snap turn, support seated play, and never hide the exit/recenter path.

### 10.7 Device rules
The paired Vision Pro is shared hardware. Announce installs/runs, leave the device in a clean state,
and never record personal data (accounts, serials beyond the standard evidence fields) in the repo.

---

## 11. Top risks

| Risk | Hardness | Mitigation |
|---|---|---|
| JIT mechanism on visionOS (S1) | MEDIUM | Externally demonstrated (EV-0002) and host-reproduced (EV-0004, `PARTIAL`); device reproduction is the M0 gate. AOT pivot if it fails |
| OpenJDK 25 xros runtime + LWJGL natives + code cache inside MC (C3) | **HIGH** | EV-0002 does not cover it; runtime build and in-MC integration unproven |
| MC Vulkan on MoltenVK fails | **HIGH** | Host boot verified (EV-0005); the xros stack (MoltenVK-xros, LWJGL-xros, GLFW/CAMetalLayer) is the risk. GL/LTW fallback |
| Eye-texture handoff unstable | **HIGH** | S4; GPU blit fallback |
| Performance/thermals on device | **HIGH** | Presets, 45 Hz repeat, caps |
| JIT onboarding friction | MEDIUM | Guided setup + docs |
| Vivecraft/MC drift | MEDIUM | Pin 26.2; version guard; S3 injection decision at M0 exit (static point stable 1.3.14→1.3.15, EV-0006) |
| GPL/EULA constraints | MEDIUM | Source publication, ownership gate |
| Prior-art overlap | MEDIUM | Compete on launcher flexibility |

---

## 12. Glossary

- **AVP** — Apple Vision Pro.
- **MCVR / VRRenderer** — Vivecraft's VR runtime abstraction (`MCVR`) and stereo renderer base.
- **Provider** — our `VisionVR` implementation of `MCVR`.
- **Bridge** — native ObjC++/C layer between the JVM provider and visionOS frameworks.
- **EV** — evidence entry in `VERIFY.md`.
- **JIT26** — debugger-prepared-memory protocol required to execute generated code on visionOS 26+.
  Externally demonstrated (EV-0002); internal reproduction is S1; productization is A2: per-launch
  intervention vs persistent provisioning, chip coverage, and a distribution path with no manual steps.
- **CompositorServices** — Apple's Metal-only immersive rendering API.
- **MoltenVK** — Vulkan-to-Metal translation layer with visionOS support.
- **LTW** — PojavLauncher's Light Thin Wrapper (desktop GL → GLES), fallback graphics path.

---

## 13. Change log

| Date | Change |
|---|---|
| 2026-10-31 | Initial AGENT.md: MVP scope accepted, hardness register, spikes, milestones, rules. |
| 2026-10-31 | EV-0001 recorded workspace/toolchain/reference baseline (`PARTIAL`; no build, no device run, no JIT evidence). |
| 2026-10-31 | Review revision: S1/A2/C3 status semantics, S3 stability criteria + M0 decision, §3.5 fork wording, §4.7 propagation checklist, cross-reference fixes, K3 rig and F3 assumption notes, `log_evidence.sh` promoted to M0. |
| 2026-10-31 | EV-0002 recorded (external JIT26 demonstration, `PARTIAL`); A2 → MEDIUM, counts 32/26/7; §4.6/§11 split mechanism vs runtime; S1 scope aligned (reference JVM; C3 owns OpenJDK 25); §4.6 added to §4.7. Internal S1 reproduction still `NOT RUN`. |
| 2026-10-31 | M0 foundation: repo hygiene (`.gitignore`, `.DS_Store` untracked), `versions.env`, licenses/notices, ADRs 0001–0006, docs (scope/spikes/acceptance), component skeletons, and tooling (`check_versions.sh`, `bootstrap.sh`, `log_evidence.sh`, self-tested). No spike status changed. |
| 2026-10-31 | S1 groundwork: host pre-test EV-0004 (`PARTIAL`) and S1a/S1b harness plan in `docs/mvp/SPIKES.md`. Device S1 still `NOT RUN`. |
| 2026-10-31 | S2 groundwork: host boot pre-test EV-0005 (`PARTIAL`, Vulkan/MoltenVK 1.4.2) and S2 plan in `docs/mvp/SPIKES.md`. Device S2, world render, soak still `NOT RUN`. |
| 2026-10-31 | S3 static analysis EV-0006 (`PARTIAL`): `VRState.initializeVR` is public static, injection point stable across 1.3.14/1.3.15, no runtime Mixin yet. EV-0004/EV-0005 interpretation/scope notes added; AT allocation rule documented; M0 timing rule added. |
| 2026-10-31 | S1a harness scaffolded (`runtime/probes/s1a`); EV-0007 records the build self-check and host JIT run. Device S1a blocked on an AVP provisioning profile. |
