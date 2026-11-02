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
> stereo with hands for an hour, with no PC involved. (PSVR2 Sense controller support is P1, post-MVP.)

### 1.2 MVP success criteria (mirrored in `VERIFY.md` §1)

| ID | Criterion |
|---|---|
| AC-1 | Fresh sideload → in-world in ≤ 30 min on a 100 Mbps link, using only documented steps. |
| AC-2 | Immersive stereo via CompositorServices: correct per-eye projection and eye order, head tracking active, 90 Hz target with graceful fallback. |
| AC-3 | Core play: move, turn, teleport, jump/sneak, break/place, attack/use, inventory, hotbar, crafting/chests, pause/settings, bow, climbing, save/reload. |
| AC-4 | Every P0 action reachable from hands; no stuck input on tracking loss. (PSVR2 controllers are P1, post-MVP.) |
| AC-5 | 60-minute session, 20 cold launches, 10 world loads, zero compositor watchdog kills. |
| AC-6 | No Minecraft binaries in git; ownership gate + EULA notice; GPL-3.0 source published; third-party notices complete. |

### 1.3 Non-goals (MVP)

App Store/TestFlight/Ad Hoc; AOT builds; PC/cloud streaming; SteamVR/OpenVR/OpenXR runtime;
modpack marketplace; shaders/Iris parity; multiplayer hosting; video streaming; MC 26.3+ until
Vivecraft supports it; redistribution of Minecraft binaries or assets; **PSVR2 Sense controller support (P1, post-MVP — not a temporary blocker)**.

### 1.4 Positioning

A public project (`rebelancap/vivecraft-visionos`) already runs MC 26.2 + Vivecraft on Vision Pro
via GraalVM AOT + Klepton, sideloaded. We do not compete on "first to run it". We compete on the
**launcher**: accounts, user-managed installs and mods, version agility, diagnostics, and input /
comfort polish.

**Input positioning (scope revision 2026-11-01): hands-only, deeply optimized hand interaction.**
PSVR2 Sense controller support is **P1 (post-MVP)** — this is a scope decision, not a temporary
constraint, and input parity is **not** claimed as an MVP feature.

**Tracked external references:** `rebelancap/vivecraft-visionos` (benchmark only; no code copied) and
**macstream** — LGPL-3.0 reference; design reference + partial port into the LGPL provider; **no code
in the GPL launcher**; upstream commit `ec5a851c066856b0a3ca3eadc530d5ea18e88930` (ADR-0009).

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
- Spike progress: S1 host pre-test `PARTIAL` (EV-0004); **S1a `PASS (compat)` (EV-0021: five cold runs
  with JIT26 mappings, tier 3/4 compiles, `HELLOJIT`, exit 0)**; S1b native visionOS harness built/signed
  (EV-0022, 39 JRE Mach-O relabelled VISIONOS; EV-0023 launches; **EV-0024 PASS: native visionOS JIT
  mapping + tier 3/4 + `HELLOJIT`**); S2 host boot `PARTIAL` (EV-0005); S3
  **PASS** (EV-0006 static + EV-0009 desktop runtime: Mixin substitutes `VisionVR`, no SteamVR; no
  fork); S1a scaffold EV-0007. S3's M0 gate is closed; S1's internal reproduction gate is now met in
  compatibility and native modes; S1b native JIT `PASS` (EV-0024); S2 device graphics primitives `PASS`
  (EV-0025–EV-0028) and **MC 26.2 renders a world on D1 through Vulkan/MoltenVK (EV-0034)** with a
  4m20s clean session (EV-0035); the 30-minute device soak is **deferred** (user stopped early) and is
  the only outstanding ST-S2 item. The re-signed Amethyst launcher (bundled UniversalJIT26, MoltenVK,
  Vulkan bridge) installs and runs on D1 (EV-0029), giving an MC-on-device test path. MC 26.2 now
  renders a Vulkan world on D1 (EV-0034) with a 4m20s clean session (EV-0035); the 30-minute soak is
  deferred. **M0 formally closed as of EV-0034** (Decision 45=A); the 30-minute soak is now an M1 gate.
  **M1 execution plan: `docs/mvp/M1_PLAN.md`** (launcher shell, runtime provisioning, JIT readiness,
  MC install, input, soak). **M1 is CLOSED (EV-0057)**: source-built Amethyst v1.2.0 branded as VRMC
  boots MC 26.2 to a Vulkan/MoltenVK world (EV-0036/EV-0043), JIT readiness UX (EV-0051), 30-minute
  soak (EV-0044), save/relaunch (EV-0052). **M2 started (EV-0058)**: `docs/mvp/M2_PLAN.md`, native
  bridge ABI v1 stub, provider mod skeleton — next is the S4a Vulkan→Metal eye-handoff spike.
- Evidence baseline: `VERIFY.md` EV-0001…EV-0009: toolchain/reference baseline, external JIT26,
  tooling self-test, host S1/S2 pre-tests, S3 static + desktop runtime, S1a scaffold, and the
  device-build blocker. Only evidence IDs recorded in `VERIFY.md` §6 are valid.

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
│   ├─ (P1) GameController GCSpatialAccessory + AccessoryTrackingProvider — PSVR2, not MVP
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
| Native VR bridge | ARKit hand/world tracking, eye-texture handoff, frame pacing; `(P1) GCSpatialAccessory/AccessoryTrackingProvider` for PSVR2 controllers | **HIGH** |
| Input mapping | Hand gestures → Vivecraft actions (hands-only MVP; PSVR2 profile is P1) | **HIGH** (no controller fallback) |
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
| **LOW** | 33 | accounts, downloads, Fabric install, menus, Files import, diagnostics, provider injection |
| **MEDIUM** | 19 | launcher shell, JIT launch flow, provider wiring, audio, GUI interaction |
| **HIGH** | 10 | OpenJDK 25 xros runtime, Vulkan/MoltenVK boot, stereo eye handoff, frame pacing, perf/thermal, hands-only input (G2/G3/G4) |

Counts: P0 items drop 65 → 62 because **F1–F3 (PSVR2) moved to P1** (−3 MEDIUM); **G2/G3/G4 raised
MEDIUM → HIGH** (−3 MEDIUM, +3 HIGH). (The prior HIGH count was 7 in this register; the review's "8"
assumed a different snapshot.) Hands-only input has no controller fallback — see §11. Counts reflect
**A2 = MEDIUM** after EV-0002; C3 stays HIGH until the runtime/LWJGL/code-cache path is built. Any
further move must follow §4.7.

### 4.3 P0 feature register by area

#### A. Install, launch, lifecycle

| ID | Feature | Hardness | Note |
|---|---|---|---|
| A1 | Sideload install (SideStore/IPA) + first-run wizard | MEDIUM | External sideload tooling is the dependency |
| A2 | JIT launch flow + guided readiness | MEDIUM | External JIT26 requires a debugger-prepared memory step per launch (EV-0002), so the productization case is the per-launch ritual. Still open: M2/M5 coverage, persistence across kill/reboot, distribution closure, failure UX. LOW only if provisioning persists; back to HIGH if our app cannot use the protocol. **Criterion 4 is met (EV-0021: five cold relaunches), but provisioning is not persistent — StikDebug needs `universal.js` assigned to the app per install and a per-launch enabler — so A2 stays MEDIUM.** |
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
| E1 | `VisionVR` selected without SteamVR | LOW | Mixin proven on desktop Fabric (EV-0006 + EV-0009); device runtime is M2 |
| E2 | `VRRenderer` subclass + Vulkan eye targets | MEDIUM | Reuse `VulkanHelper` patterns |
| E3 | Action data for ~105 actions × 2 hands | MEDIUM | No external injection layer exists |
| E4 | Haptic routing | LOW | No-op for hands |
| E5 | IPD, eye offsets, play area, runtime identity | LOW | — |

#### F. Controller input — P1 (post-MVP), see §4.4

PSVR2 Sense support is **out of MVP scope** (scope decision 2026-11-01). F1–F3 are deferred to the P1
register; **no F-group code is written until P1** (unverifiable code is a liability and would consume
M2–M4 time). The G-group is the sole P0 input path and has no fallback.

#### G. Hand input

| ID | Feature | Hardness | Note |
|---|---|---|---|
| G1 | 27-joint skeleton, both hands, per-frame timestamps | LOW | ARKit API is straightforward |
| G2 | Gesture set with hysteresis | **HIGH** | **Sole P0 input path with no controller fallback**; bad gesture recognition = unplayable. Usability tuning is the risk |
| G3 | Virtual stick, snap turn, teleport gesture | **HIGH** | **Sole locomotion path; no controller alternative.** Dead zone/deflection tuning |
| G4 | Tracking-loss release/reacquire | **HIGH** | **Sole safety mechanism; no controller fallback.** No stuck input is the acceptance bar |
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
| **PSVR2 Sense controllers (F1–F3, deferred 2026-11-01)** | MEDIUM |
| Controller remap + left-handed profile | MEDIUM |
| Localization | LOW |
| Cloud save | MEDIUM |
| App Store feasibility study | **HIGH** |

### 4.5 Spike hardness and critical path

| Spike | Question | Hardness | Status | Fallback |
|---|---|---|---|---|
| S1 | JIT mechanism on visionOS (reference JVM + minimal app; OpenJDK 25 build is C3) | MEDIUM | `PASS` — EV-0021 (compat, five cold runs) and EV-0024 (native visionOS: JIT26 mapping, tier 3/4, `HELLOJIT`, exit 0) | Pivot to AOT; launcher scope reduces |
| S2 | MC 26.2 Vulkan on MoltenVK/xros | **HIGH** | `PASS (M0 gate)` — Device graphics substrate PASS (EV-0025 + EV-0026 + EV-0027); device world render PASS (EV-0034). Full 30-minute soak NOT RUN — deferred to M1 per Decision 45=A. | GL/LTW→ANGLE path |
| S3 | Vivecraft provider without SteamVR | MEDIUM | `PASS` (desktop injection; EV-0006 + EV-0009); provider/renderer and device runtime are M2 | Fork approved by ADR; not triggered |
| S4a-host | Eye-texture handoff, **host stage** (macOS MoltenVK: `vkGetMTLTextureMVK` + `MTLSharedEvent` works) | **HIGH** | **PASS (EV-0063)** — VkImage→MTLTexture export + Metal readback + timeline-semaphore MTLSharedEvent sync verified on host | GPU blit, then readback as last resort |
| S4a-device | Eye-texture handoff, **device stage** (visionOS MoltenVK/Metal; host PASS does not imply device PASS) | **HIGH** | **PASS (EV-0065)** — bundled MoltenVK 1.4.3 on D1: MTLDevice/MTLTexture export, Metal readback correct, timeline MTLSharedEvent sync | GPU blit fallback |
| S4 | Compositor stereo (both eyes presented, 90 Hz, no tearing) | **HIGH** | `NOT RUN` | GPU blit, then readback as last resort |
| S5-hands | Hands drive all P0 actions (sole P0 input path) | **HIGH** | `NOT RUN` | None — hands-only has no controller fallback; G2–G4 are HIGH |
| S5-controllers | PSVR2 controllers | MEDIUM | `DEFERRED (out of MVP scope)` | P1 register |
| S6 | Frame pacing / thermals on device | **HIGH** | `NOT RUN` | Lower preset, 45 Hz lock, render-distance cap |

**Milestone scope check (2026-11-01 review):** M2-W4/W5 = **host PASS (EV-0060)**; **M2-W6 = NOT RUN**
(device bring-up); **M3 = NOT RUN** (compositor stereo + head tracking). Host provider/stereo work is
**not** device evidence: device stereo, head tracking, hands, PSVR2, and thermal/frame-rate are all
`NOT RUN`. S4a has two separate gates (host/device); a host PASS must never be reported as device PASS.

**Gate order:** S1 (internal reproduction) → S2 → S4a-host → S4a-device → S4 → S6. EV-0002 de-risks the mechanism only; M1
does not start until S1 has an internal EV. If S1 fails internally, the launcher pivots to AOT. When a
spike changes status, apply §4.7 in the same commit.

### 4.6 Subsystem heat map

| Subsystem | Hardness | Why |
|---|---|---|
| JIT mechanism (S1) | MEDIUM | JIT26 executes on D1 in compatibility mode (EV-0021) and in a **native visionOS app** (EV-0024); relabelled iOS JRE works, so no fresh xros OpenJDK build is needed |
| OpenJDK 25 xros runtime + LWJGL natives + code cache (C3) | **HIGH** | Runtime build and in-MC integration unproven |
| Graphics translation | **HIGH** | Host boot EV-0005; D1 executes Vulkan render + present (EV-0025/EV-0028); **MC 26.2 world renders via Vulkan/MoltenVK on D1 (EV-0034)**; device world render closes S2's M0 gate, 30-min soak is an M1 gate |
| Stereo compositor | **HIGH** | Foreign-texture handoff + deadline discipline |
| Performance/thermal | **HIGH** | Watchdog kills on missed frames |
| VR provider | **MEDIUM (host) / HIGH (device)** | Host: Mixin injection + bridge handshake + stereo eye targets + submit loop PASS (EV-0059/EV-0060). Device: provider init, Vulkan eye handoff, no-runtime check **NOT RUN** (M2-W6) |
| Input & gestures | **HIGH** | **Hands-only P0 path with no controller fallback** (G2/G3/G4 HIGH); PSVR2 is P1/DEFERRED |
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
| MoltenVK | 1.4.3 | Prior pin: 1.4.2. EV-0016's 5/5 extensions and 9/9 features were verified against 1.4.2; either re-verify against 1.4.3 or record in ADR-0007 that the 1.4.2 verification stands in for 1.4.3 unless a behavioral difference is found |
| Xcode / SDK | 27.2 / visionOS 27.2 | Build host measured |
| Sideload | SideStore / iloader | No TrollStore/Ad Hoc on visionOS |
| Amethyst (app build) | 1.2.0 | Prior pin: 1.0-development. ADR-0007 records the change; EV-0001/EV-0004/EV-0005 reference 1.0-development and are retained as historical records. Upstream reference `AngelAuraMC/Amethyst-iOS`, GPL-3.0, do not commit |
| StikDebug script | amethyst.js | Prior script: universal.js. BundleScriptMap persistence must be re-confirmed for amethyst.js |
| Prior art (benchmark) | `rebelancap/vivecraft-visionos` | Not a dependency; no code copied |
| Tracked external reference | `/Volumes/Untitled/Projects/macstream` | LGPL-3.0 reference project (Vivecraft streaming to Quest 3, proven no-OpenVR RemoteVR backend): design reference + **partial port into our LGPL provider** (`VisionVR`/`VisionRenderer`/bridge wiring); **no code in the GPL launcher**. Upstream commit `ec5a851c066856b0a3ca3eadc530d5ea18e88930`; outside the repo, not committed; ADR-0009 |

All pins move to `versions.env` in M0; changes require an ADR.

---

## 6. Spikes and gates

| ID | Goal | Pass criteria | Evidence | Timebox |
|---|---|---|---|---|
| S1 | JIT mechanism on device (internal reproduction) | A **reference JVM** + minimal Java app JIT-compiles and runs on D1 under JIT26; log proves debugger-prepared memory and compiled methods; no W^X failure. **EV-0021 `PASS` (compat, five cold runs)** and **EV-0024 `PASS` (native visionOS, JIT26 mapping + tier 3/4 + `HELLOJIT`)**; the relabelled iOS JRE removes the fresh-xros-build need | `PASS` EV-0021 + EV-0024; S2 device render next | 3–4 wk (done inside M0) |
| S2 | MC 26.2 Vulkan boots | Host: backend Vulkan + MoltenVK, no fallback. Device: world renders (M0 gate). The 30-minute soak is an **M1 gate** (Decision 45=A) | `PASS (M0 gate)` — Host EV-0005/EV-0014; D1 capability EV-0016; render/surface/swapchain EV-0025–EV-0028; **D1 MC 26.2 world EV-0034**. Soak: NOT RUN, deferred to M1 (EV-0035 feasibility) | 2–3 wk |
| S3 | Provider integration | Vivecraft enters VR with `VisionVR`; action debug populated; no SteamVR; **and** the injection point is evidenced in the decompiled 26.2‑1.3.15 jar and holds across 26.2.x patch versions | `PASS` (desktop) — EV-0006 static + EV-0009 runtime; device provider M2 | DONE (M0) |
| S4a-host | Host eye-texture handoff | On macOS host, `vkGetMTLTextureMVK` export + `MTLSharedEvent` sync works and pixels are correct | **`PASS` (EV-0063)** | DONE |
| S4a-device | Device eye-texture handoff | Same path works on visionOS (separate gate; host PASS ≠ device PASS) | `NOT RUN` | 3–5 days |
| S4 | Compositor stereo | Both eyes correct; shared-event sync; 90 Hz; no tearing over 10 min | `NOT RUN` | 2–3 wk |
| S5-hands | Hands-only input coverage | Full P0 action checklist from hands (sole P0 input path) | `NOT RUN` | 2–3 wk |
| S5-controllers | PSVR2 controllers | `DEFERRED (out of MVP scope)` — P1 register, not counted at MVP exit | `DEFERRED` | P1 |
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
| **M0** | Docs, skeleton, versions.env, S1/S2, S3 decision | **CLOSED 2026-10-31** — S1 PASS (EV-0021 + EV-0024); S3 CLOSED (EV-0006 + EV-0009); S2 device world render PASS (EV-0034). The 30-minute device soak (K4 precursor) is deferred to M1 and recorded in §7 M1 exit criteria. | **HIGH** | 3–4 wk |
| **M1** | Launcher shell + install + flat MC boot | **CLOSED 2026-11-01 (EV-0057)** — fresh install → world (EV-0043), 30-minute soak (EV-0044), save/relaunch (EV-0052), W1–W7 closed/accepted (input cursor cosmetic accepted); M1_ACCEPTANCE.md matrix | MEDIUM | DONE (4–6 wk plan: `docs/mvp/M1_PLAN.md`) |
| **M2** | Provider + Vulkan VR | **CLOSED 2026-11-01 (EV-0070)** — provider init + stereo eye targets + no VR runtime (EV-0068); ABI v2 device eye handoff: VkImage→MTLTexture export + submit (EV-0069); S4a host+device PASS (EV-0063/EV-0065); matrix `docs/mvp/M2_ACCEPTANCE.md`. **M3 compositor/head tracking and M4 input NOT RUN** (device view raw/low, not clickable). | **HIGH** | DONE |
| **M3** | Compositor stereo + head tracking | **IN PROGRESS** — M3a COMPLETE; M3-W1/W2 PASS; M3-W3/W4 PARTIAL. Provider/display-view path device-proven (EV-0091: correct display views, bright eye textures, no command-buffer failures; EV-0092: the compositor provably writes a bright image into the presented built_in drawable). Remaining blocker is **device presentation**: D1 shows a black immersive while the same shell/compositor displays correctly in the simulator; probe/bisect device runs are next. Manual "Enter VR" entry (Option 2 staging), scene-activation/layer-state logging, alpha-only first-frame-gated parking + periodic re-park and selftest mode are implemented. | **HIGH** | 4 wk |
| **M4** | Input (**hands only**, PSVR2 is P1) | **P0 action checklist passes from hands**; no controller fallback. M4 can close on schedule; G2/G3/G4 are HIGH because hands are the sole path | MEDIUM (scope) / HIGH (gesture risk) | 4–6 wk |
| **M5** | Gameplay loop + comfort + diagnostics | All H features pass | MEDIUM | 3–4 wk |
| **M6** | Hardening + acceptance | AC-1…AC-6 + K gates evidenced. **AC-4 verification is hands-only**; PSVR2 is not checked at MVP exit | MEDIUM | 2–3 wk |

Total ≈ 12–17 engineer-months. S1's internal reproduction is the M0 gate; S2 and the S3 decision
also bound M0.

**M0 timing and exit rule.** M0 is **evidence-gated, not calendar-gated**. Target 3–4 weeks with S3
run in parallel and the AVP provisioning profile started early.

**M0 closed 2026-10-31.** S1 PASS (EV-0021 + EV-0024); S3 CLOSED (EV-0006 + EV-0009); S2 device world
render PASS (EV-0034). The 30-minute device soak (K4 precursor) is deferred to M1 per Decision 45=A.
No `NOT RUN` item may be presented as passed.

**M1 exit criteria addendum (Decision 45=A).** 30-minute device soak (K4 precursor) PASS. Deferred from
M0 per Decision 45=A; EV-0035 (4m20s) is the partial that establishes feasibility, not the gate. This
must not be forgotten once M1 starts — it is a dated M1 obligation, not an optional extension.

---

## 8. Commands

| Command | Purpose | Status |
|---|---|---|
| `scripts/check_versions.sh` | Toolchain + reference-pin check (read-only) | IMPLEMENTED (2026-10-31) |
| `scripts/bootstrap.sh` | Prerequisite check + local dirs (no downloads) | IMPLEMENTED (2026-10-31) |
| `scripts/log_evidence.sh` | Allocate EV ID, bundle artifacts, write manifest + entry template | IMPLEMENTED (self-tested 2026-10-31) |
| `scripts/build_jre.sh` | Build OpenJDK 25 for xros | NOT IMPLEMENTED |
| `scripts/build_launcher.sh` | Build the visionOS app | IMPLEMENTED (ADR-0008): reproducible payload build from a prepared Amethyst 1.2.0 tree + `patches/vrmc-m1-amethyst-1.2.0.patch`; see `docs/mvp/LAUNCHER_BUILD.md` |
| `scripts/build_provider.sh` | Build the provider mod jar (javac 25 + jar, classpath auto-resolved; no Gradle) | IMPLEMENTED (M3b 2026-11-01) |
| `scripts/build_bridge.sh` | Build the bridge dylib (`MODE=device\|host\|both`; clang cross-build + `vtool` visionOS retag; verifies platform/symbols) | IMPLEMENTED (M3b 2026-11-01) |
| `scripts/build_shell.sh` | Build the visionOS SwiftUI shell framework (`runtime/native-shell`) | IMPLEMENTED (M3-W2) |
| `scripts/stage_native_app.sh` | Copy the app bundle, swap framework/bridge, embed profile, re-sign 169 Mach-O, `codesign --verify --deep --strict` | IMPLEMENTED (M3b 2026-11-01) |
| `scripts/push_provider_jar.sh` | `devicectl device copy to` the provider jar into the app data container mods dir + sha256 round-trip | IMPLEMENTED (M3b 2026-11-01) |
| `scripts/test_local.sh` | Run host-side unit tests | NOT IMPLEMENTED |
| `scripts/install_device.sh` | Install to a paired Vision Pro | IMPLEMENTED (T2, 2026-10-31) |
| `scripts/latency_rig.sh` | Drive the K3 camera protocol + tabulate samples | NOT IMPLEMENTED |
| `runtime/probes/s1a/build.sh` | Build/sign/install the S1a iOS JIT probe | SCAFFOLD — compiles; signing/install pending AVP profile |
| `scripts/sign_ipa.sh` | Re-sign an `.app` for a dev team/profile (Amethyst, StikDebug, M1 app) | IMPLEMENTED (T2, 2026-10-31) |
| `scripts/push_jit_script.sh` | Push a StikDebug script (default `runtime/jit/amethyst.js`) | IMPLEMENTED (T2, 2026-10-31) |
| `scripts/set_mc_options.sh` | Set MC `preferredGraphicsBackend:"vulkan"` + `startedCleanly:true` on device | IMPLEMENTED (T2, 2026-10-31) |
| `scripts/capture_device_logs.sh` | Collect Amethyst log + crash logs + StikDebug log into a directory | IMPLEMENTED (T2, 2026-10-31) |

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
- **macstream** is a tracked external reference (ADR-0009): record its upstream commit, state explicitly whether code was copied/ported, and keep any ported code inside the LGPL provider — never in the GPL launcher. Current state: `VisionVR`/`VisionRenderer`/bridge wiring contain code/design derived from macstream's `RemoteVR` backend (LGPL-3.0), commit `ec5a851c…`.

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
| MC Vulkan on MoltenVK fails | **HIGH** (device substrate closed; soak + M2 VR remain) | Host boot EV-0005; **device world render PASS EV-0034** via MoltenVK 1.4.3; the 30-minute soak is now an M1 gate (Decision 45=A). GL/LTW fallback |
| Eye-texture handoff unstable | **HIGH** | Split gates: **S4a-host** (macOS MoltenVK export/shared-event) and **S4a-device** (visionOS) are separate; host PASS does not imply device PASS. GPU blit fallback |
| Performance/thermals on device | **HIGH** | Presets, 45 Hz repeat, caps |
| JIT onboarding friction | MEDIUM | Guided setup + docs |
| Vivecraft/MC drift | MEDIUM | Pin 26.2; version guard; injection decision: Mixin, no fork (EV-0006 + EV-0009) |
| **Hands-only input has no fallback** | **HIGH** | Gesture recognition or tracking-loss failures become MVP blockers with no controller workaround; G2/G3/G4 raised to HIGH, S5-hands is the only S5 scope. PSVR2 is P1 (not a workaround) |
| Provider device runtime unproven | **HIGH (device)** | Host PASS (EV-0060) only; M2-W6 device bring-up, S4a-device, Vulkan/Metal eye handoff all NOT RUN. Do not report host progress as device readiness |
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
| 2026-10-31 | S1a device-build attempt blocked (EV-0008): the AVP must be unlocked for development services; automatic signing then creates the AVP profile. |
| 2026-10-31 | S3 gate closed: EV-0009 (`PASS`, desktop) proves the Mixin substitutes `VisionVR` for `MCOpenVR` with no SteamVR; decision: Mixin, no fork. E1 → LOW; counts 33/25/7. |
| 2026-10-31 | EV-0010 (`PASS`, host): MoltenVK v1.4.2 built for visionOS (`xros-arm64`, platform VISIONOS, minos 27.2). Next S2 steps: xros LWJGL natives, GLFW/CAMetalLayer shim, D1 probe. |
| 2026-10-31 | EV-0011: S1a build/sign PASS with an AVP provisioning profile; install `BLOCKED` by the free-profile 3-app limit (Amethyst, StikDebug, SideStore). |
| 2026-10-31 | EV-0012: LWJGL 3.4.1 / spirv-cross / openal dylibs retagged to VISIONOS (`vtool`, 12/12); load test pending; jemalloc absent, launch needs `-Dorg.lwjgl.system.allocator=system`. |
| 2026-10-31 | EV-0013: visionOS S2 capability probe app builds/signs with MoltenVK + the 12 retagged natives embedded; not installed (app-slot limit, EV-0011). |
| 2026-10-31 | EV-0014: host world render via Vulkan/MoltenVK for 21 minutes with clean shutdown; full 30-minute soak still pending. |
| 2026-10-31 | EV-0015: Amethyst removed with approval, S1AProbe installed on D1. Correction: the crash is UIKit UIScene-adoption assertion, not JIT26; both probe apps need UIScene before any JVM/JIT conclusion. |
| 2026-10-31 | EV-0016 (`PASS`, D1): MoltenVK 1.4.2 on visionOS (Apple M2) exposes all 5 required extensions and 9 required features (`maxPushDescriptors=287`). Both probes now adopt UIScene; S1AProbe bundle paths fixed. |
| 2026-10-31 | EV-0017/0018: fixed the S1a harness by calling `JLI_Launch` from `main()` (no UI); console harness starts the JVM and traps at `BreakGetJITMapping` without an enabler. Patched StikDebug `universal.js` for allocation-style `0x69`; JIT run pending. |
| 2026-10-31 | EV-0019 (`FAIL`): post-patch launches still trap at the JIT26 request; JIT was not active (Home launch or script not applied). Script-selection/launch-flow confirmation is the next step. |
| 2026-10-31 | EV-0020 (`FAIL`, BLOCKED): StikDebug attaches/detaches without JIT26 preparation even with all four scripts patched; S1a device JIT is blocked pending an enabler decision (Apparition / custom enabler / AOT). |
| 2026-10-31 | **EV-0021 (`PASS (compat)`): S1 gate closed in compatibility mode** — assign `universal.js` to the app in StikDebug and use the harness JIT26 extension handshake; five cold launches got JIT26 mappings, compiled tier 3/4 and executed `HELLOJIT` with clean exits. S1b native xros and S2 device render remain open; A2 stays MEDIUM. |
| 2026-10-31 | EV-0022 (`PARTIAL`): native visionOS S1b harness built/signed; the iOS JRE's 39 Mach-O files relabelled to VISIONOS. Device install blocked by the free-profile 3-app limit (S1AProbe still counted) and a locked/asleep device; S1AProbe must be uninstalled before S1BProbe can install. |
| 2026-10-31 | EV-0023 (`PARTIAL`): after uninstalling S1AProbe, `dev.vrmc.s1b` installs and launches natively on D1 with no scene crash; it waits for the JIT debugger and exits cleanly without one. Next: StikDebug Enable JIT pass on S1BProbe. |
| 2026-10-31 | **EV-0024 (`PASS`): S1 spike complete** — native visionOS app (`dev.vrmc.s1b`) with the VISIONOS-relabelled JRE received a JIT26 mapping, compiled tier 3/4 and executed `HELLOJIT` (616 ms, exit 0). The relabelled iOS JRE works, so C3's remaining risk is LWJGL/natives + full-MC integration. S2 device render is the last open M0 gate. |
| 2026-10-31 | EV-0025 (`PASS`): D1 executes a Vulkan offscreen clear+readback through MoltenVK/M2 (pixel 64,128,191,255). |
| 2026-10-31 | EV-0026 (`PASS`): all 12 retagged VISIONOS natives dlopen on D1; representative exports resolve. |
| 2026-10-31 | EV-0027 (`PASS`): CAMetalLayer → VkSurfaceKHR works on D1 (1280x720, 60 formats); probe clean. |
| 2026-10-31 | EV-0028 (`PASS`): VK_KHR_swapchain + present works on D1 (1280x720, 3 images, FIFO). S2 device graphics primitives complete; MC boot/title/world (S2 step 6) is next. |
| 2026-10-31 | EV-0030 (`FAIL`): Amethyst launched via StikDebug dies immediately (attach→continue→detach, no crash report); normal launch stays alive. Workaround: set up MC normally, then relaunch under StikDebug for the game JVM. |
| 2026-10-31 | EV-0031 (`PARTIAL`): Amethyst external Java 25 + always-attached JIT + dyld bypass reach MC 26.2 main on D1; boot aborts on missing LWJGL 3.4.1 spvc (release bundles 3.3.3). Next: install the current development build. |
| 2026-10-31 | EV-0032 (`FAIL`): grafting LWJGL 3.4.1 Java/natives clears the spvc error but the JVM SIGSEGVs in the app's embedded 3.3.3 `JNI_OnLoadGLFW`; the launcher must be rebuilt from current source. Full problem exported to `export/` with logs, hs_err and evidence. |
| 2026-10-31 | EV-0033 (`PARTIAL`): StikDebug 3.2.0 reinstalled for <TEAM_ID> (pairing/DDI/scripts preserved, amethyst.js present); launch verification blocked by device lock. Next: wake/unlock and reassign the script. |

| 2026-10-31 | M1 planning started while the ST-S2 30-min soak is deferred: `docs/mvp/M1_PLAN.md` covers the tested device stack (Amethyst 1.2.0, StikDebug 3.2.0, Java 25, LWJGL 3.4.1, MoltenVK 1.4.3), workstreams W1–W7, and sprint-1 tasks T1–T6. |
| 2026-10-31 | M0 gate formally closed. S2's M0 exit gate is device world render only (Decision 45=A); the 30-minute soak is an M1 gate. This is not a redefinition of S2 — it is the explicit split between S2's device-proven state and the soak-quality state that M1 must complete. |
| 2026-10-31 | M1 stack pinning: Amethyst → 1.2.0, MoltenVK → 1.4.3, StikDebug script → amethyst.js. Justification ADR pending (see ADR-0007). Prior M0 evidence (EV-0001, EV-0010, EV-0016, EV-0021) retains its original values with a forward-reference to the new pins. |
| 2026-10-31 | **ADR-0007 accepted**: Amethyst 1.2.0 fixes the EV-0032 JNI root cause by shipping matching LWJGL 3.4.1 JNI; MoltenVK 1.4.3 is device-proven (EV-0016's 1.4.2 verification needs re-checking on 1.4.3); `amethyst.js` is a new combined script whose BundleScriptMap assignment must be re-confirmed (Decision 36). `versions.env` + `docs/mvp/DEVICE_STACK.md` updated with pins/hashes. |
| 2026-10-31 | **T3 resolved (app-shell route): build Amethyst from source with submodules, brand as `dev.vrmc.vrmc`, add the VRMC first-run layer**; pinning/re-signing the tested 1.2.0 binary is retained only as an immediate boot-test vehicle. Rationale and follow-through in `docs/mvp/M1_PLAN.md` §5a. Sprint-1 starts a recursive source clone and `payload` build. |
| 2026-10-31 | T3 build prep: recursive clone of `AngelAuraMC/Amethyst-iOS` at `f98c413` (Makefile `VERSION := 1.2.0`, 4 submodules) + Temurin/Zulu JDK 8 toolchain obtained; `make PLATFORM=2 payload` started. T5 source finding: Amethyst gates `GCMouse` deltas on `windowScene.pointerLockState.locked`, which visionOS does not provide — documented as the mouse/cursor root cause candidate in `M1_PLAN.md` W5. |
| 2026-10-31 | **EV-0036 (`PASS`): T3 acceptance** — source-built Amethyst v1.2.0 (167 binaries re-signed, app tree hash recorded) launched under StikDebug JIT and rendered MC 26.2’s Vulkan world on D1. Build composition and remaining M1 work recorded in `M1_PLAN.md` / `DEVICE_STACK.md`. |
| 2026-10-31 | **EV-0037 (`PASS`): T4 app-side defaults** — the launcher now forces the Vulkan backend and clears `startedCleanly` before every launch, so a reset `options.txt` (`default`/`false`) still boots MC 26.2’s Vulkan world on D1. T1 hashes completed (MoltenVK 1.4.3 dylib, MC version JSON, source-build app trees). |
| 2026-10-31 | Sprint-1 close-out: **T1 EV-0038** (stack pins+sha256, `check_versions.sh` 8/8), **T2 EV-0039** (repo scripts parameterized/re-runnable), **T5 EV-0040 PARTIAL** (visionOS mouse-delta patch installed; follow-up `task-1`), **T3 EV-0041** (ADR-0008: build Amethyst 1.2.0 from source and brand `dev.vrmc.vrmc`; pin route only as fallback). T4 (fresh-install provisioning) and T6 (30-minute soak, now defined) remain open. |
| 2026-10-31 | EV-0042 (`PARTIAL`): branded **VRMC app (`dev.vrmc.vrmc`, display name VRMC)** signed and installed on D1; the `dev.vrmc.amethyst` test app was removed, giving a fresh container for the T4 first-run acceptance. |
| 2026-10-31 | **EV-0043 (`PASS`): T4 fresh-install acceptance** — fresh branded VRMC container reaches the MC 26.2 world with app-side provisioning (forced TXM always-attached JIT, bundled Java 25, Vulkan); **EV-0044 (`PASS`): T6 30-minute soak** — 1805 s continuous, no game crash/watchdog kill, thermal `serious` recorded (StikDebug watchdog kill noted). **EV-0045 (`FAIL`)**: cursor not hidden + rotation not smooth (SDL3 absolute-cursor path when `isGrabbing` false); **EV-0046 (`FAIL`)**: background freeze + audio loss (scene lifecycle/audio session); fixes for the lifecycle defect are installed for retest. |
| 2026-11-01 | **EV-0047 (`PARTIAL`)** input retest: grab path active (`nativeSetGrabbing 1`), rotation smooth; cursor stays visible because visionOS reports pointer-lock support but never locks (`pointerLockSupported=1, locked=0`) — accepted as cosmetic. **EV-0048 (`PASS`)** lifecycle/audio retest: background/foreground resumes with sound after SceneDelegate+audio-session fix. `task-1/2/3` closed. |
| 2026-11-01 | **EV-0049 (`PASS`): W1 reproducible launcher build** — `scripts/build_launcher.sh` + `patches/vrmc-m1-amethyst-1.2.0.patch` + `docs/mvp/LAUNCHER_BUILD.md`; tested from a fresh Amethyst 1.2.0 tree with submodules and cached depends (no `dep_mg`/`dep_mobilegl`; payload 1.2.0, Java 25 + LWJGL 3.4.1). |
| 2026-11-01 | **EV-0050 (`PARTIAL`): W3 JIT readiness** — explicit TXM alert (Assign Script → `amethyst.js`, Enable JIT → VRMC) and `[JIT] preflight` logging built/installed; no-JIT flow verification pending. Added `docs/mvp/M1_ACCEPTANCE.md` with the M1 acceptance matrix and gaps (W6 in-app crash report, W7 save/relaunch, W1 icon/first-run, GPL source offer). |
| 2026-11-01 | **EV-0051 (`PASS`): W3 no-JIT preflight verified** (`[JIT] preflight isJITEnabled=0` → guidance → game continues after JIT enabled). **EV-0052 (`PASS`): W7 save/relaunch verified** (clean save/quit + reload preserved). M1 acceptance #2 and #4 now PASS; remaining gaps recorded in `M1_ACCEPTANCE.md` (#5 in-app crash/share, #6 keyboard/controller defaults, #7 GPL source-offer artifact, W1 icon/first-run). |
| 2026-11-01 | **EV-0053 (`PASS`): W6 observability** — launcher Send logs + in-game Log output share path confirmed, crash reports retrievable, scripts capture logs; M1 acceptance #5 PASS. **EV-0054 (`PARTIAL`): W1 polish** — VRMC icon assets + one-time first-run checklist built/signed; install pending device wake. |
| 2026-11-01 | **EV-0055 (`PASS`)**: reproducible build re-verified end-to-end with VRMC branding assets + the 11-file patch (fresh tree, exit 0, payload 1.2.0 Java 25/LWJGL 3.4.1). W1 icon/first-run build remains pending install on an awake device. |
| 2026-11-01 | **EV-0056 (`PASS`): W1 app shell complete** — final branded build (VRMC icon + one-time first-run checklist, 167 Mach-O re-signed, tree `ee8d4558…`) installed on D1. M1 acceptance matrix: #1/#2/#3/#4/#5/#7 PASS; #6 (keyboard/controller defaults) PARTIAL; icon/welcome visual check cosmetic. |
| 2026-11-01 | **EV-0057 (`PASS`): M1 milestone CLOSED** (fresh install→world, 30-min soak, save/relaunch; matrix in `docs/mvp/M1_ACCEPTANCE.md`). **EV-0058 (`PASS`): M2 started** — `docs/mvp/M2_PLAN.md`, bridge `vrmc_abi.h` v1 + compiled/tested stub, provider mod scaffold from S3 evidence. Next: S4a eye-texture interop spike + provider build harness. |
| 2026-11-01 | **EV-0059 (`PASS`): M2-W1 host harness** — provider scaffold compiled/packaged and injected as `VisionVR` on desktop Fabric (Mixin redirect fired, `dh.vr is now dev.vrmc.provider.VisionVR`), failing closed with `VR provider: VRMC` and no SteamVR. **S4a static findings**: shipped MoltenVK 1.4.3 exposes `VK_EXT_metal_objects`, `vkGetMTLTextureMVK`/`vkSetMTLTextureMVK`, `MTLSharedEvent`, timeline semaphores — zero-copy eye handoff is plausible; runtime device capability check is the next gate. |
| 2026-11-01 | **EV-0060 (`PASS`): M2 host integration** — bridge ABI v1 handshake, `VisionVR.init()` success, stereo eye targets, per-frame `vrmc_submit_eyes` on desktop Fabric (GL ids), 8400+ tracking frames, no SteamVR; provider/dylib hashes recorded. Structure adapted from **macstream's proven RemoteVR backend** (`docs/mvp/MACSTREAM_REFERENCE.md`): the external project already demonstrates a working no-OpenVR Vivecraft provider; its GL id handoff is replaced by the S4a Metal-handle path on visionOS. |
| 2026-11-01 | **M2 review propagation + PSVR2 scope downgrade.** EV-0060 explicitly scoped as **M2-W4/W5 host PASS**; M2-W6 device bring-up and M3 are **NOT RUN** (§4.5/§6/§7/§11/VERIFY). Identity controller transforms marked **host-only**; device missing transforms must fail loudly (code comment + `provider/HOST_HARNESS.md`). macstream recorded as tracked LGPL-3.0 reference (upstream `ec5a851c…`, design + partial port into the LGPL provider, no code in the GPL launcher; ADR-0009, §1.4/§5/§10.4). **PSVR2 Sense is P1/DEFERRED, not BLOCKED**: AC-4 and §1.1/§1.2/§1.3/§1.4/§3.1/§3.2/§4.2/§4.3/§4.4/§4.5/§4.6/§6/§7/§11 updated; G2/G3/G4 → HIGH (hands-only has no fallback); S5 split into S5-hands (P0) and S5-controllers (P1); F1–F3 moved to the P1 register. VERIFY gains a `DEFERRED (out of MVP scope)` status. |
| 2026-11-01 | ABI evolution policy added to `bridge/abi/vrmc_abi.h` + `docs/mvp/M2_PLAN.md` (§9): additive field = major bump + reject; v1 old/new mismatches fail closed; `vrmc_init(caps_json)` mismatch is a hard reject, never warn-and-continue. M2-W6 preconditions recorded (Fabric → Vivecraft → provider/bridge). |
| 2026-11-01 | **EV-0061 (`PASS`)**: M2 review fixes (host vs device scope, host-only identity fallback, macstream compliance, S4a split gates, W6 preconditions, ABI evolution policy). **EV-0062 (`DEFERRED`)**: PSVR2 Sense controller input moved out of MVP scope to P1 (not BLOCKED); hands-only is the sole P0 input path. |
| 2026-11-01 | **EV-0063 (`PASS`): S4a-host** — macOS MoltenVK `VK_EXT_metal_objects` works end-to-end: exportable VkImage→MTLTexture, Metal readback of a Vulkan clear is pixel-correct, and MTLSharedEvent observes Vulkan signals **only with a timeline semaphore** (binary exports nil). S4a-device remains NOT RUN. |
| 2026-11-01 | **EV-0065 (`PASS`): S4a-device** — the bundled-MoltenVK probe in the VRMC app proves on D1 that `MTLDevice`/`MTLTexture` export works, Metal readback of a Vulkan clear is pixel-correct, and a timeline `MTLSharedEvent` observes Vulkan signals. This de-risks M3's zero-copy eye handoff; S4a-host and S4a-device are both PASS. |
| 2026-11-01 | **EV-0066 (`PARTIAL`): M2-W6 prep** — arm64-ios JNI bridge dylib built, embedded and signed in the VRMC app (168 Mach-O), launcher passes `-Dvrmc.bridge.lib`; `vrmc-provider.jar` + Vivecraft jar staged in the device instance mods. Remaining: Fabric 0.19.3 loader install on D1; W6 provider run NOT RUN. |
| 2026-11-01 | **EV-0067 (`FAIL`)**: W6 attempt 1 crashed on the identity guard applied to static component transforms (component offsets ≠ tracking data). **EV-0068 (`PASS`)**: after fix, device provider init + bridge ABI v1 handshake + stereo render passes LEFT/RIGHT + 1501+ tracking frames + no SteamVR; device used Fabric Loader 0.20.1 (compatibility candidate; pin 0.19.3 decision pending). M2 remainder: wire S4a eye export/submit into VisionRenderer; M3/M4 NOT RUN. |
| 2026-11-01 | **EV-0069 (`PASS`): M2-W5 device eye handoff** — ABI v2 export on D1: `Vulkan VkImage -> MTLTexture`, submitted from `VisionRenderer`. **EV-0070 (`PASS`): M2 milestone CLOSED** (provider init, stereo targets, handshake, eye handoff, no runtime, host harness; matrix `docs/mvp/M2_ACCEPTANCE.md`). M3/M4 explicitly NOT RUN; device view is still raw/low because presentation is M3 and input is M4. Fabric 0.20.1 compatibility candidate carried to M3. |
| 2026-11-01 | **EV-0071 (`PASS`): M3 started / M3a gate 1** — the launcher builds as a native visionOS (`PLATFORM=11`) payload; ADR-0010 records the native-app route (immersion impossible in the iOS-compat shell) and `docs/mvp/M3_PLAN.md` defines gates 1–3 and workstreams. Native launch, immersive space, ARKit tracking and MC-in-native-app hosting remain NOT RUN. |
| 2026-11-01 | **EV-0072 (`PARTIAL`): M3a gate 2** — native immersive space + CompositorServices loop work on D1 (2700+ frames, three crash modes fixed), but no stereo image is presented and the ARKit anchor is unresolved; next probe iteration uses the C sample's device-anchor/presentation-time path. VRMC launcher restored after the probe. |
| 2026-11-01 | **EV-0073 (`PARTIAL`): M3a gate 2 diagnostics** — per-eye GPU content verified by readback (red pixel in eye0, command buffer completed) but presentation is black with the ARKit anchor and passthrough without it; remaining blocker is presentation/anchor wiring, next step compares the reference sample or ports its remaining layer setup. VRMC launcher restored. |
| 2026-11-01 | **EV-0074 (`PASS`): M3a gate 2** — native immersive space presents CompositorServices per-eye stereo (red/green operator-confirmed); root cause of black screen was the missing drawable depth attachment/rasterization-rate map. Gate 3 (MC/JVM/JIT/Vulkan inside the native app) next. |
| 2026-11-01 | **EV-0075 (`PARTIAL`/blocked): M3a gate 3** — native launcher installs/launches without crash but shows a blank window; no JIT lines and no game launch, so native-app MC/JVM hosting is unverified. Gate 2 remains PASS. Compat launcher restored with data intact. Next: native window/scene debugging or ADR-0010 fallback B. |
| 2026-11-01 | **EV-0076 (`PARTIAL`): M3a gate 3 diagnostics** — native window/scene and launcher split VC are created and sized correctly (1280x720) but render blank; native-visionOS UIKit presentation issue, not scene setup. Compat launcher restored. Next: SwiftUI window shell or companion fallback. |
| 2026-11-01 | **EV-0077 (`PASS`): M3a gate 3** — native visionOS app booted MC 26.2 + Fabric 0.20.1 + 21 mods + Vivecraft + VRMC provider with JIT and Vulkan/MoltenVK; provider init, LEFT/RIGHT passes, device VkImage→MTLTexture eye export and 601+ tracking frames inside the native app. **M3a complete.** Remaining: native launcher UI (M3-W1) and compositor/pose wiring (M3-W2..). |
| 2026-11-01 | **EV-0078 (`PARTIAL`): M3-W1 root-VC workaround** — native branch runs then crashes in `LauncherProfilesViewController viewWillAppear` (split-view sidebar macro nil); native launcher needs a native-specific UI shell. **`export/` replaced with the native-UI blocker dossier** (old Amethyst/LWJGL issue cleared); compat launcher restored. |
| 2026-11-01 | **EV-0079 (`PASS`): M3-W1** — native launcher UI renders after the UIKit idiom fix; Play launches the game in the native app with no autolaunch. `build_launcher.sh` gains `PLATFORM=11`; `export/` now holds the resolved build notes/evidence. Next: M3-W2/W3 compositor consumption of provider eye textures + ARKit poses. |
| 2026-11-01 | **EV-0080 (`PASS`, host): M3-W2 groundwork** — bridge shared eye-texture/ARKit-pose surface added (Java ABI v2 unchanged, stub test passes). Next: SwiftUI app-lifecycle shell for immersive scenes, then compositor consumption. |
| 2026-11-01 | **EV-0081 (`PASS`): M3-W2 shell** — SwiftUI app-lifecycle shell hosts launcher + opens immersive CompositorServices space (test pattern). **EV-0082 (`PARTIAL`): M3-W3/W4** — auto-open on game start, compositor 1080 frames/ARKit OK but eyes=0; MC VK_ERROR_DEVICE_LOST; mitigations staged. |
| 2026-11-01 | **EV-0083 (`PARTIAL`): M3-W3/W4 first light** — game survives with mitigations; `eyes=1` provider eye textures sampled and ARKit tracking reaches the provider; immersive opener works after 15 s. Remaining: alignment/window/scenePhase. |
| 2026-11-01 | **EV-0084 (`PARTIAL`): M3-W3/W4** — window parking works; provider eye textures sampled (`eyes=1`) with live tracking; backgrounding crashes compositor at `cp_frame_end_submission`; alignment still pending. |
| 2026-11-01 | **EV-0085 (`PARTIAL`, final attempt): M3-W3/W4** — clean background exit, but root-VC replacement destroys SwiftUI observers (no re-entry), window chrome persists, exotropia remains. `export/` updated with current-issue dossier/evidence. |
| 2026-11-01 | **Operator-confirmed blockers (export update)**: (1) window cannot hide (visionOS chrome remains), (2) no immersive re-present after background (game keeps running), (3) perspective is exotropia (view swap did not fix). `export/` updated with issue summary + evidence. |
| 2026-11-01 | **EV-0086 (`PARTIAL`): three-fix device run** — shell background/foreground reopen now works; immersive black (reprojection/UV) and window chrome still visible; provider FOV/IPD data confirmed in compositor logs. export/ updated with evidence. |
| 2026-11-01 | **EV-0087 (`PARTIAL`, build/static): M3b fixes integrated** — compositor math validated on Metal + simulator (EV-0086 device views 87.9% inside, 0 behind/NaN); no-black diagnostics + provider-texture readback + auto test-pattern; Shell epoch-guarded re-entry; Amethyst modal game-surface patch (`vrmc-m3w3-modal-game-surface.patch`, legacy root swap behind a flag) keeps the SwiftUI scene alive for chrome hiding; provider jar/bridge reproducible builds + staging scripts; signed app installed on D1. **Device run NOT RUN**; next ID `EV-0088`. |
| 2026-11-01 | **EV-0088 (`PASS`, host): display-view alignment fix** — macstream Phase 8 root causes 3+4 ported (head-relative eye matrices, client per-eye FOV, NaN projection-cache invalidation, flat mapping); offline frustum/bridge/provider checks PASS; device run pending. |
| 2026-11-01 | **EV-0089 (`PARTIAL`)** — recovered M3b device logs: provider eye textures non-black, first command buffer completed, chrome/windows parked; session backgrounded before the visual alignment check. **EV-0090 (`PARTIAL`)** — display-view device run: display views published/applied, flat sampling of provider textures (frames 6360); found and fixed a JNI grouped-vs-interleaved layout bug that corrupted the left-eye transform; pre-fix black was partly dark menu-world content. App rebuilt/installed; relaunch pending. |
| 2026-11-01 | **EV-0091 (`PARTIAL`)** — fresh post-JNI-fix device runs (15:36/16:39 HST) recovered: provider eye-render + display-view channel correct and eye textures bright (luma 103-154), first command buffer completed; `vrmc-test-pattern.flag` present since 16:13 (that build does not log the resolved flag). Operator-reported black is not explained by provider content. |
| 2026-11-01 | **EV-0092 (`PARTIAL`)** — M3c presentation diagnostics on D1: the compositor provably writes a bright image into the presented built_in drawable (64x64 strided readback + raw dumps, encNil=0, single drawable/2 views) yet the headset shows a black immersive; in a JIT game run full immersion was active but the game stayed in a floating 2D window. The same VRMCShell.framework displays the full-screen test pattern correctly in a simulator host app. Manual "Enter VR" button, scene-activation + layer-state logging, alpha-only first-frame parking with periodic re-park, willResignActive grace and a no-JIT immersive selftest are implemented. Presentation root cause not isolated; bisect matrix staged. |
| 2026-11-01 | **Operator directive (M3c, Option 2)** — keep the startup window, add a manual "Enter VR" trigger first, verify it on device, then make the automatic post-JIT entry the default; do not change the Info.plist preferred scene role until the manual path works; record an EV per stage. Implemented in the shell (manual overlay button + failure message + auto path); device validation pending. |
