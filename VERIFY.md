# VRMC — Verification and Acceptance Log

**Authority:** This file is the single source of truth for verification, acceptance, evidence, and
release sign-off. Where it conflicts with `AGENT.md` on acceptance, this file wins.
**Last updated:** 2026-11-05.
**Baseline commit:** `a96e13b` (repo reset; no product code).
**Release candidate:** none.
**Next evidence ID:** `EV-0284`.
**Valid evidence:** only entries listed in §6. An ID cited elsewhere but absent from §6 is
unallocated and must not be used.

---

## 0. Rules

1. A milestone is not complete unless its evidence is recorded in §6 and its status in §7 is updated.
2. `PASS` requires a reproducible procedure and linked evidence (log, screenshot, measurement, or
   video) produced from the recorded build.
3. A test not executed is `NOT RUN`. A test that cannot be executed in the current environment is
   `BLOCKED` with an owner and an unblock condition. Code inspection is `PARTIAL`, never `PASS`.
4. Never fabricate, backfill, or copy evidence between builds, devices, or sessions. Re-run after any
   change that can affect the result.
5. Flaky or failing tests are defects. Record the failure; never average it away.
6. Device evidence must include: date, commit, dirty state, headset model/OS, Mac build host, app
   build hash, Minecraft/Fabric/Vivecraft versions, exact steps, expected, actual, and evidence paths.
7. The simulator is never evidence for hand tracking, stereo optics, thermals, or latency. It may be
   evidence for build success, UI logic, and transport plumbing.
8. Acceptance status is decided here, not in commit messages, demos, or chat reports.
9. A status change for a spike must apply the `AGENT.md` §4.7 propagation checklist in the same
   commit. Only IDs recorded in §6 count as evidence; an unlisted ID is unallocated.

**Status legend:** `PASS` · `PARTIAL` · `FAIL` · `BLOCKED` · `NOT RUN` · `N/A` (with reason).

`DEFERRED (out of MVP scope)` — Feature is applicable but explicitly moved out of MVP scope. Not counted
as PARTIAL, BLOCKED, or NOT RUN in MVP exit checks. Re-entry requires a new scope decision.

---

## 1. Scope of acceptance

VRMC is accepted only when all of the following hold on device (Apple Vision Pro), with evidence:

| ID | Acceptance criterion | Status |
|---|---|---|
| AC-1 | Fresh sideload → in-world in ≤ 30 min on a 100 Mbps link, using only documented steps. | `NOT RUN` |
| AC-2 | Immersive stereo via CompositorServices: correct per-eye projection and eye order, head tracking active, 90 Hz target with graceful fallback. | `NOT RUN` |
| AC-3 | Core play: move, turn, teleport, jump/sneak, break/place, attack/use, inventory, hotbar, crafting/chests, pause/settings, bow, climbing, save/reload. | `NOT RUN` |
| AC-4 | Every P0 action reachable from hands; no stuck input on tracking loss. (PSVR2 controllers are **P1 / DEFERRED**, not checked at MVP exit.) | `NOT RUN` |
| AC-5 | 60-minute session, 20 cold launches, 10 world loads, zero compositor watchdog kills. | `NOT RUN` |
| AC-6 | No Minecraft binaries in git; ownership gate + EULA notice; GPL-3.0 source published; third-party notices complete. | `NOT RUN` |

**Out of scope for acceptance:** audio quality beyond stability, multiplayer beyond a local/LAN test,
non-Vivecraft OpenVR content, App Store distribution, other Minecraft versions.

---

## 2. Environments

### 2.1 Devices

| ID | Role | Hardware | OS | Notes |
|---|---|---|---|---|
| D1 | Primary headset | Apple Vision Pro `RealityDevice14,1` (N301AP), 1 TB | visionOS 27.2 (reported by `devicectl`, 2026-10-31) | Paired with the build host; chip (M2 vs M5) recorded at first run — A2 boundary #3 |
| D2 | Secondary headset | Second Vision Pro or later revision, if available | visionOS 27.x | Compatibility only, not required for MVP |
| D3 | Simulator | visionOS 27.0 runtime (`xrOS-27-0`, 24M362) on Apple silicon | macOS 27.0.1 | Build/UI/plumbing only; never device evidence |
| M1 | Build host | MacBook Pro `Mac16,7`, Apple M4 Pro (14-core), 24 GB | macOS 27.0.1 (26A434), Xcode 27.2 (27B52), visionOS 27.2 SDK | Measured 2026-10-31 |

### 2.2 Software matrix

| Component | Baseline | Compatibility candidates | Evidence required |
|---|---|---|---|
| Minecraft Java | 26.2 (Java 25, LWJGL 3.4.1) | none for MVP | Launch + 10-min play per candidate |
| Mod loader | Fabric 0.19.3 | — | Launch |
| Vivecraft | 26.2-1.3.15 (LGPL-3.0) | none until upstream supports 26.3+ | Full acceptance on baseline |
| MC graphics API | Prefer Vulkan (experimental) | Prefer OpenGL (fallback) | Backend shown in F3 + diagnostics |
| Java runtime | OpenJDK 25 xros build (TBD) | — | Build string + JIT status in log |
| LWJGL | 3.4.1 (visionOS natives TBD) | — | Loaded natives reported at boot |
| MoltenVK | Pinned build (TBD) | — | Version in diagnostics |
| App build | Tagged commit | — | Build hash in every entry |
| Sideload | SideStore / iloader | — | Install log |

---

## 3. Performance and quality budgets

| ID | Budget | Measurement method | Status |
|---|---|---|---|
| K1 | Cold start → launcher ≤ 10 s; launch → in-world ≤ 90 s | Log timestamps on device, 10 runs | `NOT RUN` |
| K2 | 90 Hz target; ≥ 72 fps sustained in the benchmark world at the default preset; no > 2 consecutive missed deadlines in 10 min | CompositorServices frame timing + frame graph | `NOT RUN` |
| K3 | Rotational M2P ≤ 50 ms P50 / ≤ 65 ms P95 | 240 fps camera, 20 samples; **rig protocol and rig availability are M0/M1 deliverables** — otherwise M6 cannot produce evidence | `NOT RUN` |
| K4 | 60-min session, 20 launches, 10 world loads; no crash or watchdog kill | Soak logs + crash monitor | `NOT RUN` |
| K5 | Thermal step-down predictable; frame floor 45 fps; no shutdown | Thermal state + fps trace during 30-min soak | `NOT RUN` |
| K6 | Install footprint ≤ 3.5 GB; first install ≤ 30 min on 100 Mbps | Disk usage + timed install | `NOT RUN` |

Starting presets (tuned by S6): Low 2048, Balanced 2560, Sharp 3200, Native 3660 px per-eye width;
default **Balanced**. Any change requires a budget table update.

---

## 4. Test suites

### 4.1 Automated tests (planned in M0/M1)

| ID | Test | Expected | Status |
|---|---|---|---|
| AT-001 | Launcher settings schema round-trip | Valid JSON, unknown keys rejected | `NOT RUN` |
| AT-002 | Installer manifest + SHA-1 verification against a mock source | Checksum mismatch blocks install | `NOT RUN` |
| AT-003 | Instance/game-dir layout creation and validation | Idempotent, no path escape | `NOT RUN` |
| AT-004 | Provider config parse + version compatibility check | Mismatch fails closed | `NOT RUN` |
| AT-005 | Bridge ABI handshake (C++ unit) | Version mismatch rejected; caps parsed | `NOT RUN` |
| AT-006 | Mapping table → action intents | Every P0 action mapped | `NOT RUN` |
| AT-007 | Gesture state machine on synthetic joint fixtures | Hysteresis, tap/hold, drag disambiguation | `NOT RUN` |
| AT-008 | Diagnostics log parser + export bundle | Bundle reproducible, no secrets | `NOT RUN` |
| AT-009 | Evidence tooling self-test (allocate, hash, manifest, invalid input) | Valid bundle + manifest; collision advances ID; invalid input exits 2 | `PASS` (EV-0003) |
| AT-010 | S1a harness scaffold self-check | `build.sh --check` passes; HelloJit executes on host with harness flags | `PASS` (EV-0007) |

**AT allocation rule:** AT IDs are assigned sequentially when a test is added to this registry — no
gaps, no reuse. `scripts/log_evidence.sh` allocates **EV** IDs only; it never allocates AT IDs. The
EV that first evidences a test is recorded in the Status column.

### 4.2 Spikes (go/no-go)

| ID | Question | Pass criteria | Fallback | Status |
|---|---|---|---|---|
| ST-S1 | Can the JIT26 mechanism be reproduced internally? | Four criteria: (1) JIT-compiled methods **execute**, not only compile; (2) no `brk #0x69` trap; (3) the code cache stays executable after the enabler detaches; (4) a cold relaunch reproduces the result or persistence is proven. **Criterion 4 decides A2 MEDIUM vs LOW.** Reference JVM + minimal app; OpenJDK 25 xros is C3. EV-0002 external; EV-0004 host-only | AOT pivot; launcher scope reduces | `PASS` — EV-0021 (compat: five cold launches) + EV-0024 (native visionOS: JIT26 mapping, tier 3/4, `HELLOJIT`, exit 0) |
| ST-S2 | Does MC 26.2 Vulkan boot on MoltenVK/xros? | Host: backend Vulkan + MoltenVK, no GL fallback, world + 30-min soak. Device: world renders, 30 min stable | GL/LTW→ANGLE | `PASS (M0 gate)` — Device graphics substrate PASS (EV-0025 + EV-0026 + EV-0027); device world render PASS (EV-0034). Full 30-minute soak NOT RUN — deferred to M1 per Decision 45=A (EV-0035 is feasibility evidence). |
| ST-S3 | Does Vivecraft enter VR with `VisionVR`, no SteamVR? | Provider init; action debug populated; stereo eye targets; **injection point evidenced in the decompiled 26.2‑1.3.15 jar and stable across 26.2.x** | Fork approved by ADR + LGPL source | `PASS` (desktop injection: EV-0006 static + EV-0009 runtime); full provider/renderer and device runtime are M2 |
| ST-S4a-host | Host eye-texture handoff: macos MoltenVK export + shared-event sync | `vkGetMTLTextureMVK` + `MTLSharedEvent` works; pixels correct (host gate) | GPU blit | `NOT RUN` |
| ST-S4a-device | Device eye-texture handoff: visionOS MoltenVK/Metal | Same path works on device (host PASS does **not** imply device PASS) | GPU blit | `NOT RUN` |
| ST-S4 | Can eye textures reach CompositorServices reliably? | Both eyes correct; shared-event sync; 90 Hz; no tearing over 10 min | GPU blit; readback last resort | `NOT RUN` |
| ST-S5-hands | Do hands drive all P0 actions (sole P0 input path)? | Full P0 action checklist from hands | **None** — no controller fallback | `NOT RUN` |
| ST-S5-controllers | PSVR2 controllers | P1 — **DEFERRED (out of MVP scope)**, not counted at MVP exit | P1 register | `DEFERRED` |
| ST-S6 | Do frame pacing and thermals hold? | K2/K5 met or documented waiver | Lower preset, 45 Hz lock, caps | `NOT RUN` |

**S3 decision deadline:** the Mixin-vs-fork choice is made at the M0 exit gate. If the injection point
is not evidenced as stable by then, the fork fallback is approved by ADR and M2 is re-baselined.

### 4.3 Device tests

| ID | Test | Expected | Status |
|---|---|---|---|
| DT-01 | Sideload install + first launch | App launches to first-run wizard | `NOT RUN` |
| DT-02 | Microsoft device-code sign-in | Account added; token persists across restart | `NOT RUN` |
| DT-03 | Offline profile | Launches and saves; server join blocked with explanation | `NOT RUN` |
| DT-04 | Install MC 26.2 + Fabric 0.19.3 + Vivecraft | All artifacts verified; mods load | `NOT RUN` |
| DT-05 | Flat window boot to title screen | Renders; keyboard/pointer work | `NOT RUN` |
| DT-06 | Enter a world flat | World loads; stable 10 min | `NOT RUN` |
| DT-07 | Immersive space enter/exit | Stereo layer opens; exit preserves game | `NOT RUN` |
| DT-08 | Head tracking + recenter | Pose tracks; recenter persists; seated mode correct | `NOT RUN` |
| DT-09 | Stereo correctness | No eye swap, no vertical flip, projection matches | `NOT RUN` |
| DT-10 | Frame pacing, 10 min | No watchdog kill; frame graph within budget | `NOT RUN` |
| DT-11 | Save, exit, resume | Save intact; resume returns to world or safe menu | `NOT RUN` |
| DT-12 | Crash + safe restart | Log captured; restart without bad mod set | `NOT RUN` |
| DT-13 | Disk-full / storage errors | Actionable error; no corrupt install | `NOT RUN` |
| DT-14 | Boot timing (K1) | Within budget over 10 runs | `NOT RUN` |
| DT-15 | 60-min soak (K4) | No crash/watchdog kill | `NOT RUN` |
| DT-16 | Thermal soak (K5) | Predictable step-down; 45 fps floor | `NOT RUN` |
| DT-17 | Rotational latency (K3) | Within P50/P95 budgets | `NOT RUN` |
| DT-18 | JIT launch-flow boundaries | Recorded answers: (1) external debugger every cold launch? (2) state survives hot restart / kill / reboot? (3) M2 and M5 covered? (4) distribution closes without manual steps? Clear guidance if unavailable; no silent slow mode | `NOT RUN` |

### 4.4 Hand input tests

| ID | Test | Expected | Status |
|---|---|---|---|
| HT-01 | Index pinch | Attack/use asserts and releases once | `NOT RUN` |
| HT-02 | Middle pinch | Secondary action; no cross-talk | `NOT RUN` |
| HT-03 | Ring pinch | Assigned action only | `NOT RUN` |
| HT-04 | Little pinch | Menu/assigned action | `NOT RUN` |
| HT-05 | Fist / grip | Grab asserts; release clean | `NOT RUN` |
| HT-06 | Palm-up virtual stick | Movement axes smooth; exit clean | `NOT RUN` |
| HT-07 | Tap vs hold vs drag | Correct disambiguation; no accidental hotbar change | `NOT RUN` |
| HT-08 | Tracking loss / occlusion | Inputs released; reacquire ≤ 1 s | `NOT RUN` |
| HT-09 | Two-hand bow | Draw/aim/release works | `NOT RUN` |
| HT-10 | Handedness + calibration | Mirrored mapping correct; persists | `NOT RUN` |

Gesture acceptance: ≥ 90% recognition per gesture over 30 trials across 3 testers.

### 4.5 Controller tests (PSVR2 Sense) — P1, `DEFERRED (out of MVP scope)`

**Not run; not counted at MVP exit.** PSVR2 Sense hardware will not be purchased; re-entry requires a
new scope decision. Hands-only tests live in §4.4.

| ID | Test | Expected | Status |
|---|---|---|---|
| CT-01 | Detect controllers | Both tracked; type reported | `DEFERRED (P1)` |
| CT-02 | Buttons | All mapped actions fire | `DEFERRED (P1)` |
| CT-03 | Sticks | Walk/turn with no drift | `DEFERRED (P1)` |
| CT-04 | Triggers | Analog range + thresholds | `DEFERRED (P1)` |
| CT-05 | Grips | Hotbar/grab behavior | `DEFERRED (P1)` |
| CT-06 | Haptics | Pulse on impact/use | `DEFERRED (P1)` |
| CT-07 | Handoff controller ↔ hands | No double input; **assumption pending S5** that visionOS 27 stops hand tracking for a held controller | `DEFERRED (P1)` |
| CT-08 | Disconnect/reconnect | Inputs release; recovery | `DEFERRED (P1)` |

### 4.6 Soak tests

| ID | Test | Expected | Status |
|---|---|---|---|
| LT-01 | 60-min continuous play | No crash, no watchdog kill, stable memory | `NOT RUN` |
| LT-02 | 20 cold launches | All reach in-world; timing within K1 | `NOT RUN` |
| LT-03 | 10 world loads (varied) | No corruption; saves intact | `NOT RUN` |

---

## 5. Evidence protocol

### 5.1 ID and layout

- IDs are sequential: `EV-0001`, `EV-0002`, … The next free ID is stated at the top of this file.
- Only IDs with an entry in §6 are valid. An ID that is not recorded there is unallocated, even if it
  is referenced in a review, chat, or commit message.
- Artifacts live in `evidence/EV-####/` (git-ignored): `manifest.json`, `*.log`, screenshots,
  measurements, short video.
- Every artifact is hashed (SHA-256) in `manifest.json`.

### 5.2 Manifest fields

```json
{
  "id": "EV-####",
  "date": "YYYY-MM-DDTHH:MM:SS-10:00",
  "commit": "<sha>",
  "dirty": ["<paths>"],
  "app_build_sha256": "<hash or null>",
  "device": {"model": "", "os": "", "role": "D1"},
  "host": {"model": "", "macos": "", "xcode": ""},
  "versions": {"minecraft": "", "fabric": "", "vivecraft": "", "jre": "", "moltenvk": ""},
  "procedure": ["step"],
  "expected": "",
  "actual": "",
  "status": "PASS|PARTIAL|FAIL|BLOCKED|NOT RUN",
  "artifacts": [{"path": "", "sha256": ""}],
  "limitations": ""
}
```

### 5.3 Rules

- One entry per run; a re-run gets a new ID.
- A `PASS` with no artifacts is invalid.
- Simulator runs carry `"role": "D3"` and cannot satisfy AC-2…AC-5.
- Logs must come from the recorded build; do not edit logs before hashing.
- If a run is aborted, record it as `FAIL` or `BLOCKED` with the reason.
- When an entry changes a spike status, apply the `AGENT.md` §4.7 checklist in the same commit.

---

## 6. Evidence log

### EV-0001 — M0 workspace, toolchain, and reference baseline

| Field | Value |
|---|---|
| Date | 2026-10-31T10:59–11:05 (-10:00) |
| Commit | `a96e13b557cdb527cb73a08b25e9f5ed19b839a0` |
| Dirty state | `.DS_Store` modified; untracked `Amethyst-iOS-main/`, `VivecraftMod-Multiloader-26.2/` |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (N301AP, 1 TB), paired, visionOS 27.2 reported; chip not yet recorded; **no run executed** |
| Build host | M1 MacBook Pro `Mac16,7`, Apple M4 Pro, 24 GB, macOS 27.0.1 (26A434) |
| Toolchain | Xcode 27.2 (27B52); visionOS 27.2 SDK; simulator runtime visionOS 27.0 (24M362) |
| Status | `PARTIAL` |

**Procedure (static inspection only, no builds, no device runs):**

1. Inventoried the working tree and git state.
2. Inspected the two untracked reference trees and read their build pins.
3. Queried Mojang version metadata for 26.2 / 26.3.
4. Reviewed platform and prior-art documentation (links below).
5. Recorded host and device toolchain facts.

**Findings:**

- Reference trees present and structurally complete: `Amethyst-iOS-main/` 525 files / 126 MB
  (`Natives/JavaLauncher.m` present; README SHA-256
  `c147252e45ca562b28ec8c8204e6e03d855d9b6de923efd079c51d43f3355d14`);
  `VivecraftMod-Multiloader-26.2/` 863 files / 13 MB (`gradle.properties` SHA-256
  `7580f81c1655eb1dd72488a7a60b4aa03cc2807baf13c708bb535ed314b4682d`).
- Pins read from source: Minecraft `26.2`, Java `25`, Vivecraft `1.3.15`, LWJGL `3.3.6` (mod build
  dependency), Fabric loader `0.19.3`, Minecraft range `["26.2.x"]`.
- Mojang metadata for 26.2: Java component `java-runtime-epsilon` (major 25); LWJGL `3.4.1`
  (`lwjgl-vulkan` present); no SDL artifacts; 26.3 is the current release; 26.4 snapshots exist.
- Minecraft 26.2 ships an experimental Vulkan renderer (Vulkan 1.2, dynamic rendering, push
  descriptors) with a "Graphics API" setting: Default / Prefer Vulkan (Experimental) / Prefer OpenGL.
- Vivecraft is ~95% runtime-agnostic: `MCVR` has 14 abstract members, `VRRenderer` 6; OpenVR-specific
  code is ~4.4% of the mod. No OpenXR implementation exists. A Vulkan helper path already exists.
- Amethyst is GPL-3.0, iOS-only, JIT-mandatory (`CS_DEBUGGED`), with no visionOS support; the
  Java-side launcher logic is largely portable.
- visionOS constraints confirmed from documentation: no JIT entitlement (debugger-prepared memory
  only), no usable OpenGL ES (EAGL symbols are not exposed on visionOS), Metal-only
  CompositorServices, 27-joint hand tracking, PSVR2 Sense spatial accessories from visionOS 26.
- Prior art: `rebelancap/vivecraft-visionos` (MC 26.2 + Vivecraft on AVP via GraalVM AOT + Klepton,
  sideload, released 2026-10-15) — benchmark only; no code copied.
- Paired device and Mac build host are available, so device-gated work can proceed once spikes exist.

**Artifacts:** none committed (documentation-only entry). No `evidence/` directory yet.

**Limitations:** no build, install, or device execution; no performance or input data; findings are
source/documentation inspection (`PARTIAL` per §0 rule 3).

**Not proven by this entry:** JIT on visionOS (EV-0002 records an external demonstration only), any
build, stereo, hand/controller input, or performance. No internal run exists in this workspace as of
this entry.

**Sources:** repo files listed above; `https://piston-meta.mojang.com/mc/game/version_manifest_v2.json`;
`https://minecraft.wiki/w/Java_Edition_26.2`; `https://github.com/rebelancap/vivecraft-visionos`;
`https://github.com/KhronosGroup/MoltenVK`; Apple developer documentation for CompositorServices,
ARKit hand tracking, and visionOS capabilities.

---

### EV-0002 — External: JIT26 mechanism demonstrated on visionOS (Apparition)

| Field | Value |
|---|---|
| Date recorded | 2026-10-31 |
| Evidence class | External citation (third-party project + write-up); not produced in this workspace |
| Source | Ixion, *From a GitHub PR to PS2 on Vision Pro: how I ended up writing my own sideloader*, 2026-10-14 — https://blog.illixion.com/2026/10/building-apparition/ (CC BY 4.0; the article notes parts were AI-written) |
| Commit | `a96e13b` baseline; recorded in the docs revision adding this entry (no build involved) |
| Dirty state | docs-only revision |
| Device | Author's Apple Vision Pro, **visionOS 27**; sideloaded with a free Apple ID |
| Software | Apparition 0.1.0 (2026-10-14); ARMSX2 (PS2 emulator); UTM; StikDebug's JIT26 protocol |
| Status | `PARTIAL` |

**Procedure (as reported by the source):**

1. Pair, sign, and install on the headset with Apparition; launch the app with "Launch with JIT".
2. The app requests prepared memory with `brk #0xf00d` (JIT26); the attached debugger prepares each
   16 KiB page.
3. After detach, the app executes only from that prepared memory and writes code through a writable
   alias.
4. ARMSX2 requested a 305 MiB code region, reported JIT working, and ran GTA: San Andreas; UTM booted
   Alpine Linux.

**What this establishes:**

- On visionOS 27, a JIT-capable app can execute generated code when a debugger prepares the code
  memory; `CS_DEBUGGED` alone is not sufficient on A15/M2-class hardware.
- Preparation is per mapping/page and per launch. Reported cost: ~0.3 s for 256 MiB prepared on-device;
  ~211 s for 320 MiB via LLDB over Wi-Fi.
- An external JIT-launch step is required for emulator-style apps, which matches A2 boundary #1
  (per-cold-launch intervention) and supports **A2 = MEDIUM**.

**What this does not establish:**

- Our OpenJDK 25 xros build, LWJGL 3.4.1 natives, `-XX:+MirrorMappedCodeCache`, or a JVM inside
  Minecraft 26.2 (S1 internal, C3).
- Behaviour on our paired device (chip not yet recorded) or on M5 hardware.
- A no-manual-steps distribution path, or persistence across kill/reboot.
- Any stereo, input, performance, or latency result.

**Artifacts:** external URL only; no local artifacts. Internal reproduction (S1) is pending and must be
recorded as its own EV before S1 passes.

**Limitations:** third-party report; no independent reproduction here; measurements are the author's;
the source states parts of the article were AI-written.

---

### EV-0003 — M0 tooling self-test (check_versions, bootstrap, log_evidence)

| Field | Value |
|---|---|
| Date | 2026-10-31T11:43:18-10:00 |
| Commit | `3332cdb5730924dd05865dec9fb98cd64fecb448` |
| Dirty state | clean |
| Device | host-only (M1 MacBook Pro); no device run |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. Run `scripts/check_versions.sh` against the pinned reference trees.
2. Run `scripts/bootstrap.sh` (prerequisite check + local dirs).
3. Run `scripts/log_evidence.sh` in a sandbox root with a synthetic VERIFY.md.
4. Test collision allocation and invalid-input exit codes.
5. Validate manifest JSON fields and artifact hashes.

**Expected:** 8/8 environment checks pass; an evidence bundle is allocated with hashed artifacts;
invalid input exits 2.

**Actual:** 8/8 checks passed; the sandbox allocated EV-0003 and EV-0004 and stopped at an EV-0005
dry-run; all three invalid-input cases exited 2; manifest fields were complete with SHA-256 length 64.

**Artifacts:** `evidence/EV-0003/check_versions.log` (b31b08cbf318);
`evidence/EV-0003/evidence_tool_selftest.log` (8a9b2ed74c79);
`evidence/EV-0003/git_state.log` (7d7f89168973).

**Limitations:** host tooling only. No app build, no device run, no JIT evidence; this entry does not
satisfy ST-S1 or ST-S2.

### EV-0004 — S1 host pre-test: relabelled iOS JRE 25 JITs on macOS; JIT26 request path reached

| Field | Value |
|---|---|
| Date | 2026-10-31T11:51:26-10:00 |
| Commit | `d25aa49ec91bd68b9ee86f58dffa2280b56aeefb` |
| Dirty state | clean |
| Device | host-only (M1 MacBook Pro); no device run |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Identify the Amethyst `jre25` iOS bundle and its 39 Mach-O images.
2. Relabel the Mach-O images to platform macOS 11.0 with `vtool` and ad-hoc re-sign.
3. Run `bin/java -version` from the relabelled tree.
4. Run `HelloJit` with `-XX:+MirrorMappedCodeCache -XX:+PrintCompilation -XX:ReservedCodeCacheSize=64m`.
5. Run with `XNU_HAS_TXM=1` to force the JIT26 request path (`brk #0x69`).

**Expected:** JRE starts; `HelloJit` compiles at tier 3/4; `[JIT26] mapping at RW/RX` logged; the TXM
run traps at the request site (exit 133).

**Actual:** JRE 25.0.4 starts; `HelloJit::hot` and `main` compile at tiers 3/4; the log shows
`[JIT26] mapping at RW=0x11c1c4000, RX=0x1181c4000`; the TXM run exits 133 (Trace/BPT trap), proving
the request site. Full analysis: `evidence/EV-0004/S1-report.md`.

**Interpretation (added 2026-10-31, original results unchanged):** the `[JIT26] mapping` line proves
the JRE **entered the JIT26 branch**; exit 133 under `XNU_HAS_TXM=1` is TXM rejecting the subsequent
execution, not a successful JIT run. Relabel compatibility and branch reachability are verified;
JIT26 **execution** is unverified and deferred to S1a (iOS) and S1b (native visionOS).

**Artifacts:** `evidence/EV-0004/S1-report.md` (965e72a7fce0);
`evidence/EV-0004/host_java_version.log` (f5c5b56aa6d0);
`evidence/EV-0004/host_jit_mac.log` (d893e249f9f6);
`evidence/EV-0004/host_jit26_request.log` (e72bd84f7f89);
`evidence/EV-0004/macho_list.txt` (8d3ee4abbdca).

**Limitations:** host-only macOS run. It does not prove dyld/AMFI acceptance or JIT inside a native
visionOS process; device S1 remains `NOT RUN`. Research by teammate s1-openjdk; the JIT and TXM runs
were reproduced by the Lead.

### EV-0005 — S2 host pre-test: Minecraft 26.2 boots on Vulkan via MoltenVK 1.4.2 (macOS)

| Field | Value |
|---|---|
| Date | 2026-10-31T11:55:20-10:00 |
| Commit | `7c684f2dcead81dc37d7866beea4c7babd1d5248` |
| Dirty state | clean |
| Device | host-only (M1 MacBook Pro); no device run |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Assemble the 26.2 classpath from Mojang metadata (83 libraries + client jar).
2. Launch MC 26.2 with Temurin 25 and `--graphicsBackend vulkan`, pointing LWJGL at the bundled
   `libMoltenVK.dylib`.
3. Wait 70 s, capture `logs/latest.log`, stop the process.
4. Verify backend and required device extensions; confirm no GL fallback.

**Expected:** `Using graphics backend Vulkan` with MoltenVK; required extensions present; process
alive; no OpenGL fallback.

**Actual:** `Using graphics backend Vulkan, using drivers: 1.2.334 MoltenVK 1.4.2`; device Apple M4
Pro; extensions include dynamic rendering, push descriptor, synchronization2,
vertex_attribute_divisor, swapchain; process alive at 70 s, stopped for capture; menu only, no world.

**Scope (added 2026-10-31):** confirmed on the **macOS build host only**. Mojang ships MoltenVK
officially on macOS, so this de-risks MC 26.2's Vulkan backend logic and shows the xros S2 scope is
limited to three transplantable components: MoltenVK-xros, LWJGL-xros natives, and the
GLFW/CAMetalLayer shim. It is **not** evidence for S2 on device.

**Artifacts:** `evidence/EV-0005/host_pretest_summary.log` (f9f017c985ae);
`evidence/EV-0005/latest.log` (a0b1420a3d9a);
`evidence/EV-0005/S2_vulkan_report.md` (abf00e6e7270);
`evidence/EV-0005/probe_mvk_2026-10-31.out` (825984512f5b).

**Limitations:** host macOS only. No world render, no 30-minute stability, no visionOS run; it does
not satisfy ST-S2's device criterion. MC was force-stopped, not cleanly exited. Research by teammate
s2-vulkan; the launch and capture were reproduced by the Lead.

### EV-0006 — S3 static analysis: provider injection point exists and is stable across 1.3.14→1.3.15

| Field | Value |
|---|---|
| Date | 2026-10-31T12:06:06-10:00 |
| Commit | `ee6855999c10541710e18bdc5f542da6f6caae05` |
| Dirty state | clean |
| Device | host-only (static analysis); no runtime test |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Download the official Fabric jars for 26.2-1.3.15 and 26.2-1.3.14 from Modrinth; hash them.
2. `javap -p -c` `VRState` and extract the `initializeVR` bytecode.
3. Diff the method bytecode across the two versions.
4. Inspect `MCOpenVR` construction coupling and the `ClientDataHolderVR.vr` field type.

**Expected:** public/static `initializeVR` with an identifiable provider-selection branch, a stable
target across patch versions, and a viable Mixin injection point.

**Actual:** `VRState` is public, `initializeVR` is `public static`; the branch reads
`VRSettings.stereoProviderPluginID`, constructs `MCOpenVR` (ordinal-0 `PUTFIELD`) or `NullVR`
(ordinal-1); `initializeVR` bytecode is identical (19,772 bytes, sha256 `dcde94f…`) across 1.3.14 and
1.3.15; the `vr` field is a public `MCVR`; the `MCOpenVR` constructor makes no `org.lwjgl.openvr`
`VR_*` calls (only struct allocation and `Version.getVersion`).

**Preliminary conclusion:** Mixin injection is viable and stable across the two available 26.2.x
builds. Recommended target: `@Redirect` on the ordinal-0 `PUTFIELD ClientDataHolderVR.vr`, signature
`(ClientDataHolderVR, MCVR) -> MCVR`, returning `VisionVR`; set the provider setting to OPENVR in
`vrsettings.json`. `MCOpenVR` is still constructed and then discarded (harmless allocation). No
public provider API exists. Runtime Mixin test is still required; the fork path is not triggered yet.

**Artifacts:** `evidence/EV-0006/S3-static-summary.log` (b0d3ee1cdb69);
`evidence/EV-0006/VRState-1.3.15.javap.txt` (75f714cb126e);
`evidence/EV-0006/VRState-1.3.14.javap.txt` (75f714cb126e);
`evidence/EV-0006/jar-sha256.txt` (7053c0fbd55d);
`evidence/EV-0006/initializeVR-1.3.15.txt` (dcde94fbb281).

**Limitations:** static analysis only. No Mixin build/run and no desktop Fabric injection test; S3
remains `NOT RUN` until a Mixin is applied and a provider is instantiated. Jars were not committed.

### EV-0007 — S1a harness scaffold: iOS app compiles; HelloJit executes under harness JIT flags on host

| Field | Value |
|---|---|
| Date | 2026-10-31T12:08:25-10:00 |
| Commit | `91f40f8fe02d77b638b7ba94f6cc7d2a067d1191` |
| Dirty state | `runtime/probes/` (uncommitted scaffold at capture time) |
| Device | host-only (syntax + host JVM run); no device run |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Write the S1a iOS harness (`HelloJit`, `main.m` JLI_Launch wrapper, `Info.plist`, entitlements,
   `build.sh`, README).
2. Run `runtime/probes/s1a/build.sh --check` against the iOS SDK.
3. Compile `HelloJit` and run it with the harness flags on the relabelled iOS JRE (host).
4. Record JIT26 mapping, `PrintCompilation`, and `HelloJit` output.

**Expected:** iOS syntax check passes; `[JIT26]` mapping logged; `HelloJit::hot` compiles at tier 3/4;
`HELLOJIT` output printed.

**Actual:** check passed; `[JIT26] mapping at RW=0x11a1c4000, RX=0x1161c4000`; `HelloJit::hot` at
tiers 3/4; `HELLOJIT iterations=200000000 acc=-3264381489421335726 elapsed_ms=504`;
`java 25.0.4-internal`.

**Artifacts:** `evidence/EV-0007/harness_syntax.log` (0af8d99af294);
`evidence/EV-0007/hellojit_harness_flags.log` (788421386ae0);
`evidence/EV-0007/HelloJit.java` (f07400177ce2);
`evidence/EV-0007/main.m` (491487665fac);
`evidence/EV-0007/build.sh` (8d7b148aa55b);
`evidence/EV-0007/Info.plist` (628841107002).

**Limitations:** scaffold only — not signed, not installed, not run on device. No AVP provisioning
profile exists locally (only an iPad profile), so device S1a remains `NOT RUN`.

### EV-0008 — S1a device build attempt: blocked on AVP unlock and missing provisioning profile

| Field | Value |
|---|---|
| Date | 2026-10-31T12:25:29-10:00 |
| Commit | `fc25eacc7eb3420217c8496d577bb9490f513abe` |
| Dirty state | `runtime/probes/s1a/` (project.yml, generated project/info at capture time) |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, paired); **device locked** |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `BLOCKED` |

**Procedure:**

1. Generate the `S1AProbe` Xcode project with automatic signing (team `<TEAM_ID>`).
2. Run `xcodebuild` for the visionOS compatibility destination with `-allowProvisioningUpdates`.
3. Capture the destination list and build log.

**Expected:** build succeeds, the device is registered, and an AVP provisioning profile is created.

**Actual:** `xcodebuild` timed out waiting for the destination; Xcode reports *"Apple Vision Pro needs
to be unlocked to enable development services."* Only an iPad-only profile exists locally (expires
2026-11-05).

**Artifacts:** `evidence/EV-0008/xcodebuild.log` (d3f6662bd328);
`evidence/EV-0008/destinations.log` (9757aa407ec8).

**Unblock condition:** unlock/wear the AVP so development services start, then re-run the same
`xcodebuild` command; automatic signing should register the device and create the profile. No app was
installed.

### EV-0009 — S3 runtime: Mixin substitutes VisionVR in Vivecraft on desktop Fabric (no SteamVR)

| Field | Value |
|---|---|
| Date | 2026-10-31T12:30:51-10:00 |
| Commit | `e8fdb3c81de1d139e4ae2da72925b0a6d2d71634` |
| Dirty state | clean |
| Device | host-only (desktop Fabric); no visionOS device run |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. Build the probe mod (redirect Mixin + `VisionVR` stub) against MC 26.2, Fabric 0.19.3, Vivecraft 26.2-1.3.15.
2. Install the probe and Vivecraft in `/tmp/mc-fabric/mods` with `vrEnabled=true`.
3. Launch MC 26.2 through Fabric loader `KnotClient`.
4. Observe the redirect, provider construction, `dh.vr` assignment, and `init()` call.

**Expected:** redirect fires on `initializeVR`; `VisionVR` is constructed; `dh.vr` is `VisionVR`; `init()`
is reached without a SteamVR/OpenVR runtime.

**Actual:** log shows `redirect fired; original=…MCOpenVR`, `VisionVR constructed`,
`dh.vr is now dev.vrmc.probe.VisionVR`, `VisionVR.init() reached`. Vivecraft then shows
*"Render setup failed: VRMC S3 probe / VR provider: VRMC-S3-Probe"* because the stub intentionally
returns false. That dialog is the proof the substituted provider was instantiated.

**Artifacts:** `evidence/EV-0009/probe-summary.log` (ab641afdd790);
`evidence/EV-0009/latest.log` (dc7cdd6eee17);
`evidence/EV-0009/run2.log` (8586680eab8a);
`evidence/EV-0009/vrmc-s3-probe.jar` (8d02609a4b3d);
`evidence/EV-0009/VisionVR.java` (275e18690862);
`evidence/EV-0009/VRStateMixin.java` (9d7fdd714211);
`evidence/EV-0009/fabric.mod.json` (5e53442cfe77);
`evidence/EV-0009/vrmc.mixins.json` (3fdc8dbeae85);
`evidence/EV-0009/probe-sha256.txt` (53003a780f5d).

**Limitations:** desktop Fabric verification only; the full provider/renderer and the visionOS device
runtime are M2 scope.

### EV-0010 — S2 step 2: MoltenVK v1.4.2 visionOS xcframework built (xros-arm64, minos 27.2)

| Field | Value |
|---|---|
| Date | 2026-10-31T12:36:26-10:00 |
| Commit | `10acf808859b4fe9d304c2164e839b30923e41f7` |
| Dirty state | clean |
| Device | host-only build; not loaded on device |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. Clone `KhronosGroup/MoltenVK` at tag **v1.4.2** (commit `db66022`).
2. Run `./fetchDependencies --visionos`.
3. Run `make visionos` (scheme "MoltenVK Package (visionOS only)", destination `generic/platform=xrOS`).
4. Verify the `xros-arm64` slice is platform VISIONOS and record artifact hashes and dependency revisions.

**Expected:** `xros-arm64` dynamic and static `MoltenVK.xcframework` artifacts with platform VISIONOS.

**Actual:** build succeeded (fetch rc=0, make rc=0). The dynamic
`MoltenVK.xcframework/xros-arm64/MoltenVK.framework` is Mach-O arm64, **platform VISIONOS, minos 27.2,
sdk 27.2**; the static xcframework is also present. Framework binary sha256
`1e3554510f2dc97f8fff27ded14f67c4a6f1f4c7c1ca1cc34cc37c6db9794138`. Dependency revisions (SPIRV-Cross
`6c09849`, SPIRV-Tools `0d6fd73`, Vulkan-Headers `e3b1eec`, Volk `7768933`, cereal `a56bad8`, …) are in
the summary artifact.

**Artifacts:** `evidence/EV-0010/summary.log` (28780b914b99);
`evidence/EV-0010/build.log` (6a813f674d10);
`evidence/EV-0010/xcframework-Info.plist` (96c950ece239);
`evidence/EV-0010/MoltenVK-xros-arm64` (1e3554510f2d).

**Limitations:** build artifact only — not loaded, linked, or run on visionOS; S2 device stage remains
`NOT RUN`. Next S2 steps: xros LWJGL 3.4.1 natives, GLFW/CAMetalLayer shim, capability probe on D1.

### EV-0011 — S1a build and signing succeed; device install blocked by free-profile 3-app limit

| Field | Value |
|---|---|
| Date | 2026-10-31T13:44:25-10:00 |
| Commit | `2974b6cb02a201cee0f8139d8ca08a40b85f42d5` |
| Dirty state | `runtime/probes/s1a/` (project.yml and generated project) |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, paired) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `BLOCKED` |

**Procedure:**

1. Fix the iOS deployment target to 15.0 and regenerate the Xcode project.
2. Build with `JRE_DIR` = clean iOS JRE 25 and automatic signing; this created a visionOS profile
   containing the AVP UDID (`dev.vrmc.s1a`, expires **2026-11-07**).
3. Sign the 33 nested JRE Mach-O binaries, then re-sign the app with Xcode's generated entitlements
   (`application-identifier`, `team-identifier`, `get-task-allow`).
4. Verify deep/strict, attempt `devicectl install` twice, and enumerate installed apps.

**Expected:** the app installs on the AVP.

**Actual:** build and signing pass (`codesign --verify --deep --strict` rc=0; 120 MB app). Install fails:
the free-profile limit of 3 apps is already reached — **Amethyst**, **StikDebug**, **SideStore**. The
device app list confirms those three plus SideInstaller.

**Artifacts:** `evidence/EV-0011/xcodebuild-with-jre.log` (52d6f7581411);
`evidence/EV-0011/profile.txt` (f46cd047f708); `evidence/EV-0011/signing.txt` (e2efa8a79aa8);
`evidence/EV-0011/install.log` (0a5050e16b4d); `evidence/EV-0011/install2.log` (6fcc1617ad56);
`evidence/EV-0011/apps.json` (66f99de02435); `evidence/EV-0011/apps_cmd.log` (1f02c8223d8e).

**Unblock:** remove one free-profile app — **Amethyst** is the least disruptive; StikDebug and
SideStore are needed for JIT and re-signing — or enroll in the paid Developer Program. No app was
installed and device state is unchanged.

### EV-0012 — S2 step 4 groundwork: LWJGL 3.4.1 natives retagged to VISIONOS (12 dylibs)

| Field | Value |
|---|---|
| Date | 2026-10-31T13:45:16-10:00 |
| Commit | `e5402e29fe14aca22834b4186435df37b0725715` |
| Dirty state | clean |
| Device | host-only transform; no load test (device installs blocked) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Collect Amethyst's iOS LWJGL 3.4.1 natives, `libspirv-cross`, `libopenal`, and the EV-0010 MoltenVK
   xros framework.
2. Retag each Mach-O with `vtool -set-build-version 11 27.0 27.2 -replace`.
3. Ad-hoc sign and verify platform/minos for each dylib.
4. Record hashes, dependency notes, and remaining gaps.

**Expected:** all 12 dylibs report platform VISIONOS with consistent minos.

**Actual:** 12/12 dylibs are VISIONOS (MoltenVK minos 27.2; others 27.0); hashes recorded. The jemalloc
native is still missing, so the launch must set `-Dorg.lwjgl.system.allocator=system`; there is no
load test yet.

**Artifacts:** `evidence/EV-0012/summary.log` (a52427e42597).

**Limitations:** metadata transform only. Not linked/loaded in a visionOS process; device installs are
blocked by the free-profile 3-app limit (EV-0011). Next: add these to the visionOS probe app, add an
rpath or explicit `dlopen` path, and run the capability probe on D1.

### EV-0013 — S2 visionOS probe app builds with MoltenVK + retagged LWJGL natives (install pending)

| Field | Value |
|---|---|
| Date | 2026-10-31T13:46:21-10:00 |
| Commit | `79e67e8c371baad57d809b83bd8bdcfa8e13ed75` |
| Dirty state | `runtime/probes/s2-xros/` |
| Device | build only; not installed (free-profile app limit) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Adapt the host MoltenVK capability probe to a visionOS app (`dlopen Frameworks/libMoltenVK.dylib`).
2. Generate an Xcode project with xcodegen (visionOS 27.0, team `<TEAM_ID>`).
3. Build with the Vulkan headers and the EV-0012 native set; embed 12 dylibs.
4. Verify the app and embedded natives are platform VISIONOS.

**Expected:** a visionOS app with MoltenVK and LWJGL natives embedded, signed, ready to install and run
the capability probe.

**Actual:** build succeeded; app main binary is platform VISIONOS, minos 27.0; all 12 embedded dylibs
are VISIONOS; `codesign --verify --deep --strict` passes; 24 MB app. Not installed because the
free-profile limit is reached (EV-0011).

**Artifacts:** `evidence/EV-0013/build.log` (40c801b24368); `evidence/EV-0013/summary.log` (3ec92d0686b7).

**Limitations:** probe not executed. Install and run are gated on freeing a free-profile app slot or
enrolling in the paid Developer Program (EV-0011). S2 device stage remains `NOT RUN`.

### EV-0014 — S2 host world render: Vulkan world session for 21 minutes, clean shutdown (partial soak)

| Field | Value |
|---|---|
| Date | 2026-10-31T14:04:46-10:00 |
| Commit | `9588c0505a944c239d1cd1f1fa1bf983a0920321` |
| Dirty state | clean |
| Device | host-only (macOS); no device run |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Copy the "New World" save into `/tmp/s2-mc/saves`.
2. Launch MC 26.2 with `--graphicsBackend vulkan --quickPlaySingleplayer "New World"`.
3. Verify backend and world join; let the session run and capture logs on stop.

**Expected:** world renders via Vulkan for 30 minutes without a crash.

**Actual:** backend `Vulkan, using drivers: 1.2.334 MoltenVK 1.4.2`; `Dev joined the game` at 13:42:10;
the session stopped cleanly at 14:03:15 (**21m05s**) with saves flushed and no crash/exception. The
30-minute criterion was not reached.

**Artifacts:** `evidence/EV-0014/latest.log` (c0471fc09ddf);
`evidence/EV-0014/soak-partial-summary.log` (948d5344f672); `evidence/EV-0014/world.log` (e0487eb9421b).

**Limitations:** partial soak (21 of 30 minutes); clean shutdown, no crash. A full 30-minute host soak
is still required. Host-only; not device evidence.

### EV-0015 — S1a device control run: embedded JVM reaches the JIT26 request and traps (no enabler)

| Field | Value |
|---|---|
| Date | 2026-10-31T14:13:09-10:00 |
| Commit | `879acf1cfdb6239aed61c8d563898c678dc416e9` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2); app installed |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Install `dev.vrmc.s1a` after freeing the Amethyst app slot.
2. Launch via `devicectl` with `--console` (no JIT enabler attached).
3. Collect the crash reports and app-container state.

**Expected:** without a JIT enabler, the JVM's JIT26 request traps in the debugger-prepared-memory path.

**Actual:** the app launched and crashed twice with `EXC_BREAKPOINT` / `SIGTRAP` ("Trace/BPT trap: 5"); no
Documents log was written; crash reports were captured.

**Initial interpretation (superseded by the correction below):** the embedded iOS JRE loads and runs on
visionOS, and the JVM reaches the JIT26 request (`brk`); the trap is the expected no-enabler failure.

**Correction (added 2026-10-31, original results unchanged):** the crash backtrace is
`UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` on the main thread. Both probe apps omit
UIScene adoption, so UIKit traps at scene creation. This crash is **not** the JVM's JIT26 request; JVM
start is unverified. Fix: adopt UIScene in both probe apps, then re-run the control and JIT runs.

**Artifacts:** `evidence/EV-0015/S1AProbe-2026-10-31-141120.ips` (19749ec0b4f6);
`evidence/EV-0015/S1AProbe-2026-10-31-141204.ips` (62aaf7266b19);
`evidence/EV-0015/launch-console.log` (ee72d0114d9d); `evidence/EV-0015/summary.log` (85d7fb2511c1).

**Limitations:** control run only; no JIT enabled. The device JIT26 execution is still `NOT RUN`.

### EV-0016 — S2 device capability probe: MoltenVK 1.4.2 on visionOS exposes all MC 26.2 requirements (Apple M2)

| Field | Value |
|---|---|
| Date | 2026-10-31T14:17:10-10:00 |
| Commit | `53c9de17822dbc7874ad675174a300fde8021017` |
| Dirty state | `runtime/probes/` (UIScene fixes) |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, **Apple M2**) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. Build the native visionOS probe with UIScene adoption, MoltenVK and the retagged natives embedded.
2. Sign the embedded dylibs with the development identity and re-sign the app with its Xcode
   entitlements (the first run failed: "missing code signature").
3. Install and launch on D1; pull `Documents/s2-probe.log`.
4. Check the five required device extensions, nine required features, and push-descriptor limits.

**Expected:** all MC 26.2 required extensions and features are present on visionOS.

**Actual:** MoltenVK **1.4.2**; **Apple M2 GPU**; apiVersion 1.2.357; driverID 14 (MoltenVK);
**5/5 required extensions OK** (dynamic_rendering, push_descriptor, synchronization2,
vertex_attribute_divisor, swapchain); **9/9 required features = 1**; `maxPushDescriptors=287`;
`VK_EXT_metal_objects` present; `VK_EXT_multi_draw` absent (optional).

**Artifacts:** `evidence/EV-0016/s2-probe.log` (4c9ef9b7902f);
`evidence/EV-0016/s2probe-build5.log` (a70bdd783e26);
`evidence/EV-0016/s2probe-launch4.log` (dd0bf9105d6e);
`evidence/EV-0016/probe_mvk.c` (04a6f2247a05); `evidence/EV-0016/probe-main.m` (a39cc0704b2c).

**Limitations:** capability only. No swapchain/window or MC render on D1 yet; the probe did not enable
surface extensions, so surface support is not assessed. Device is **M2**; M5 is not covered.

### EV-0017 — S1a JIT attempts: IOKit/SwiftUI crashes before JVM output (superseded root cause)

| Field | Value |
|---|---|
| Date | 2026-10-31T14:40:01-10:00 |
| Device | D1 Apple Vision Pro (visionOS 27.2 compatibility mode) |
| Status | `FAIL` |

**What happened:** with a UIKit scene app, launches crashed in
`IOHIDEventSystemClientSetDispatchQueue` (`assertion failure: Dispatch queue already set`) before any
JVM output; a SwiftUI rewrite crashed with `AppGraph.shared may only be set once`. The same happened
with and without StikDebug.

**Root cause (found in EV-0018):** `JLI_Launch` calls back into the executable's `main` (`libjli.apple_main`
→ app `main` → UI framework `main`), re-entering the UI framework. Fixed by a console-style harness
where `main()` calls `JLI_Launch` directly and no UI exists (EV-0018).

**Artifacts:** `evidence/EV-0017/s1a-jit.log`, two `.ips` crash logs, `stikdebug-scripts.txt`,
`summary.log`.

---

### EV-0018 — S1a console harness: JVM starts on D1 and traps at BreakGetJITMapping (control run)

| Field | Value |
|---|---|
| Date | 2026-10-31T14:47:58-10:00 |
| Device | D1 Apple Vision Pro (visionOS 27.2 compatibility mode) |
| Status | `PARTIAL` |

**Procedure:** rewrite the harness so `main()` calls `JLI_Launch` directly (no UIApplication/SwiftUI);
embed/sign the JRE; install; launch via devicectl; pull log and crash report.

**Actual:** the JVM initializes (OpenJDK warning printed) and the crash backtrace is
`BreakGetJITMapping → get_debug_jit_mapping → os::pd_reserve_memory → CodeCache::initialize`
(`EXC_BREAKPOINT`). No enabler was attached, so no JIT executed — the expected control-run failure.

**Artifacts:** `evidence/EV-0018/s1a-jit.log`, `S1AProbe-2026-10-31-144339.ips`, `summary.log`.

**Next:** launch the same console app through StikDebug with a patched `universal.js` that implements
the JVM's allocation-style `0x69` request (built-in script rejects it).

### EV-0019 — S1a after patched script: launches still trap at BreakGetJITMapping (JIT not applied)

| Field | Value |
|---|---|
| Date | 2026-10-31T15:04:26-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2 compatibility mode) |
| Status | `FAIL` |

**Procedure:** user launched S1AProbe after the patched `universal.js` was pushed to StikDebug; then the
app log and crash reports were pulled.

**Expected:** a debugger-handled `0x69` allocates/prepares the code cache; the JVM continues and prints
`HELLOJIT`.

**Actual:** three launches at 14:58 all crash at `BreakGetJITMapping`; the app log shows only JVM
initialization — no `[JIT26]` mapping and no `HELLOJIT`. This matches a **normal launch without a
working enabler**, not a run under StikDebug's JIT flow.

**Artifacts:** `evidence/EV-0019/s1a-jit.log`, three `.ips` crash logs, `summary.log`.

**Next:** confirm the launch path. A Home-screen tap cannot enable JIT; the app must be launched from
inside StikDebug's Enable JIT flow, and the selected script must be the patched `universal` one. If
StikDebug cannot select/import it, switch to Apparition's custom-script flow or patch the JRE's
`BreakGetJITMapping` to the universal `0xf00d` protocol.

### EV-0020 — S1a: StikDebug attaches then detaches without script preparation; JIT26 still unhandled

| Field | Value |
|---|---|
| Date | 2026-10-31T15:14:34-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Status | `FAIL` |

**Procedure:** patch all four StikDebug scripts for allocation-style `0x69`, push them to the app
container; user launches S1AProbe from StikDebug Enable JIT; read StikDebug's `idevice_log` and the
S1AProbe crash logs.

**Actual:** StikDebug launched the app suspended, sent `vAttach`, then **detached after ~1 s without a
continue or any script/BRK handling**. All four scripts were verified patched on device. S1AProbe still
traps at `BreakGetJITMapping`. The prefs confirm `bundleID = dev.vrmc.s1a` and
`overrideTXMForScripts = true`.

**Conclusion:** StikDebug's JIT flow on this visionOS 27.2/TXM build does not perform JIT26 memory
preparation, so script content cannot fix it. Options: Apparition custom-script flow, a custom
CoreDevice debugserver enabler, or the AOT fallback.

**Artifacts:** `evidence/EV-0020/summary.log`, `stikdebug-excerpt.log`, `s1a-jit.log`, crash `.ips`,
StikDebug prefs plist.

### EV-0021 — S1a PASS (compat): JIT26 executes on D1 — mapping, tier 3/4, HELLOJIT, clean exit, 5 cold relaunches

| Field | Value |
|---|---|
| Date | 2026-10-31T15:55:35-10:00 |
| Commit | `e352bea01644f54ba71e67b34ff700068fc9583f` |
| Dirty state | `runtime/probes/s1a/main.c` |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, iOS compatibility mode) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. Assign `universal.js` to S1AProbe in StikDebug (long-press the app → Assign Script) and launch it
   with **Enable JIT**.
2. The console harness waits for an attached debugger, probes the legacy `0x69` request, detects
   `universal.js`'s refusal sentinel (`0xE0000069`), then sends a JIT26 extension script that maps
   `0x69` (`x0 = size`) to `JIT26PrepareRegion(NULL, size)` and detaches after the first breakpoint.
3. The JVM requests 64 MB, receives the prepared mapping, compiles and executes `HelloJit`.
4. Repeat cold launches and pull `Documents/s1a-jit.log`.

**Expected:** JIT26 mapping granted; tier 3/4 compiled methods execute; the debugger detaches; the
result reproduces on cold relaunch.

**Actual:** five cold launches (pids 1623/1625/1632/1634/1636) each logged
`[JIT26] Requesting 64 MB`, `Got JIT mapping 0x…`, tier 3/4 `HelloJit::hot`/`main`,
`HELLOJIT iterations=200000000 … elapsed_ms=616/620/799/759/730`, and `JLI_Launch returned 0`.
Three launches without a debugger cleanly reported the required StikDebug assignment. One crash at
15:41 occurred when no script was assigned.

**Criteria:** (1) compiled methods executed — `HELLOJIT` output + tier 3/4 compiles; (2) no
`brk #0x69` trap — successful runs exit 0; (3) cache executable after detach — detach-after-first-br
then continued compilation/execution; (4) cold relaunch reproduces — five distinct pids.

**Artifacts:** `evidence/EV-0021/s1a-jit.log`, `summary.log`, `main-fixed.c`, `main-fix.diff`, and the
15:41 crash `.ips`.

**Limitations:** S1a is compatibility-mode only; S1b native visionOS is still pending. The enabler
needs StikDebug with a script assigned to the app per install (free-profile 7-day re-sign), so A2 stays
MEDIUM.

### EV-0022 — S1b native visionOS harness: built and signed with a VISIONOS-relabelled JRE (device run pending)

| Field | Value |
|---|---|
| Date | 2026-10-31T16:12:16-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) — install blocked |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:** copy the iOS JRE and relabel all 39 Mach-O files to platform VISIONOS with `vtool`;
create a native visionOS console harness (`S1BProbe`) embedding the relabelled JRE and `HelloJit`;
build (`generic/platform=visionOS`), sign nested JRE + app, verify; attempt install on D1.

**Actual:** build, sign and verify pass; both the app and `libjvm.dylib` report platform VISIONOS
(minos 27.0/27.2). Uninstall of `dev.vrmc.s1a` fails
(`AMDeviceRemoteCopyMountedDevicesList returned no mount information`) and install fails
`ApplicationVerificationFailed`: the free-profile 3-app limit already counts `dev.vrmc.s1a`,
StikDebug and SideStore. The attempts also hit `IXRemoteErrorDomain 6` (connection invalid),
consistent with a locked/asleep device.

**Artifacts:** `evidence/EV-0022/build.log`, `summary.log`, `main.c`, `project.yml`,
`install-error.log`.

**Next:** unlock D1, free the slot (uninstall `dev.vrmc.s1a`), install `dev.vrmc.s1b`, control-run
(expect a JIT26 trap), then one StikDebug Enable JIT pass with a script assigned to `dev.vrmc.s1b`.

### EV-0023 — S1b native visionOS harness runs on D1: launches without UI/scene and waits for the JIT debugger

| Field | Value |
|---|---|
| Date | 2026-10-31T16:23:52-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, native app) |
| Status | `PARTIAL` |

**Procedure:** uninstall `dev.vrmc.s1a` to free the free-profile slot; install `dev.vrmc.s1b`; launch the
native visionOS console harness via devicectl (no enabler); pull `Documents/s1b-jit.log` and crashes.

**Actual:** the native app launches; the log shows `[S1B] console-start`, the resolved bundle/classes
paths, and `no JIT debugger attached (CS_DEBUGGED=0 ppid=1)` with the StikDebug instruction. It exits
cleanly with no crash report and no scene-lifecycle failure. The JVM is not started because the
handshake requires an attached debugger.

**Artifacts:** `evidence/EV-0023/s1b-jit.log`, `summary.log`.

**Next:** assign `universal.js` to S1BProbe in StikDebug, launch with Enable JIT, then check for the
native JIT26 mapping + `HELLOJIT`.

### EV-0024 — S1b PASS: native visionOS app JITs and executes on D1 with the VISIONOS-relabelled JRE

| Field | Value |
|---|---|
| Date | 2026-10-31T16:27:55-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, native `dev.vrmc.s1b`) |
| Status | `PASS` |

**Procedure:** assign `universal.js` to S1BProbe in StikDebug, then Enable JIT → S1BProbe; the harness
completes the JIT26 handshake and starts the JVM; pull the app log and crash reports.

**Actual:** log shows `universal JIT26 script detected; sending 0x69 extension`,
`[JIT26] Requesting 64 MB`, `Got JIT mapping 0x111d6c000`, `mapping at RW=…, RX=…`, tier 3/4
`HelloJit::hot`/`main`, `HELLOJIT iterations=200000000 … elapsed_ms=616`, and
`JLI_Launch returned 0`. No crash reports.

**Significance:** the **relabelled iOS JRE runs natively on visionOS with JIT26** — no fresh xros
OpenJDK build is needed for the JVM/code-cache path (C3's remaining risk is LWJGL/natives and full-MC
integration).

**Artifacts:** `evidence/EV-0024/s1b-jit.log`, `summary.log`.

**Next:** S2 device render — MC 26.2 Vulkan world on D1 (M0's last open gate).

### EV-0025 — S2 device render: Vulkan offscreen clear+readback executes on D1 (MoltenVK 1.4.2, Apple M2)

| Field | Value |
|---|---|
| Date | 2026-10-31T16:30:42-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, native `dev.vrmc.s2probe`) |
| Status | `PASS` |

**Procedure:** extend S2Probe with a Vulkan render test — create `VkDevice`, clear a 64×64 RGBA8 image
to `(0.25, 0.5, 0.75, 1.0)`, copy it to a host-visible buffer, and read the pixel back; build, sign,
install and launch the native visionOS probe on D1; pull `Documents/s2-probe.log`.

**Actual:** log shows `Created VkDevice ... Apple M2 GPU`, `RENDER-TEST pixel = (64,128,191,255)`,
`RENDER-TEST PASS`, and `probe rc=0`.

**Scope:** device **executes Vulkan commands** through MoltenVK/M2 — not just extension enumeration.
Still offscreen only: no swapchain/window/present and no Minecraft world, so ST-S2's device criterion
remains open.

**Artifacts:** `evidence/EV-0025/s2-probe.log`, `summary.log`, `probe_mvk.c`, `s2probe-build8.log`.

### EV-0026 — S2 step 4 load test: all 12 retagged VISIONOS natives dlopen in the D1 probe

| Field | Value |
|---|---|
| Date | 2026-10-31T16:32:12-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, native `dev.vrmc.s2probe`) |
| Status | `PASS` |

**Procedure:** embed the 12 retagged VISIONOS dylibs (MoltenVK, LWJGL 3.4.1 subset, SDL3, openal,
shaderc, spirv-cross, freetype) in S2Probe; pass the Frameworks directory to the probe; `dlopen` each
dylib and resolve a representative export; build/sign/install/launch and pull the log.

**Actual:** all 12 dylibs load in the visionOS process. Seven resolve their representative symbol
(MoltenVK, SDL3, freetype, lwjgl core, openal, shaderc, spirv-cross); the five LWJGL extension dylibs
(nanovg/opengl/stb/tinyfd/vma) load but do not export `JNI_OnLoad`, which is a symbol-name mismatch
rather than a load failure. `jemalloc` remains absent (use `-Dorg.lwjgl.system.allocator=system`).

**Artifacts:** `evidence/EV-0026/s2-probe.log`, `summary.log`, `probe_mvk.c`, `main.m`.

### EV-0027 — S2 step 5a: CAMetalLayer VkSurfaceKHR created on D1; probe clean with 12 natives loaded

| Field | Value |
|---|---|
| Date | 2026-10-31T16:34:19-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, native `dev.vrmc.s2probe`) |
| Status | `PASS` |

**Procedure:** attach a `CAMetalLayer` to the probe view and pass it to the Vulkan probe; create a
`VkSurfaceKHR` with `VK_EXT_metal_surface`; query caps/formats; also run the offscreen render and native
load tests; pull the log.

**Actual:** `SURFACE-TEST PASS` — `currentExtent 1280x720`, `minImageCount=2`, `maxImageCount=3`,
60 formats. `RENDER-TEST PASS`, native load test **12 ok / 0 failed**, `probe rc=0`.

**Scope:** surface creation only; swapchain/present and the MC world remain open (S2 steps 5b/6).

**Artifacts:** `evidence/EV-0027/s2-probe.log`, `summary.log`, `probe_mvk.c`, `main.m`,
`s2probe-build12.log`.

### EV-0028 — S2 step 5b: Vulkan swapchain + present on D1 (CAMetalLayer, 1280x720, 3 images)

| Field | Value |
|---|---|
| Date | 2026-10-31T16:47:54-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2, native `dev.vrmc.s2probe`) |
| Status | `PASS` |

**Procedure:** create a `VK_KHR_swapchain` device on the `CAMetalLayer` surface; acquire an image, clear
it, transition to `PRESENT_SRC`, submit and present; pull the log.

**Actual:** `## swapchain test: 1280x720 fmt=44 mode=2 images=3`, `submit=0 present=0`,
`## SWAPCHAIN-TEST PASS`, `probe rc=0`. `SURFACE-TEST` and offscreen `RENDER-TEST` also pass in the
same run.

**Scope:** present path proven; MC boot/title/world (S2 step 6) and the Java GLFW stub remain.

**Artifacts:** `evidence/EV-0028/s2-probe.log`, `summary.log`, `probe_mvk.c`, `main.m`,
`s2probe-build13.log`.

### EV-0029 — Amethyst re-signed for <TEAM_ID> installs and launches on D1 (MC boot pending)

| Field | Value |
|---|---|
| Date | 2026-10-31T16:54:26-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Status | `PARTIAL` |

**Procedure:** take the release Amethyst IPA (arm64, unsigned), change its bundle id to
`dev.vrmc.amethyst`, sign 22 nested Mach-O and the app with the free-team profile +
`get-task-allow`; install via devicectl and launch normally; pull crash logs.

**Actual:** installation and launch succeed; the `AngelAuraAmethyst` process remains alive. The only
crash log present is an older 12:46 entry, not this run.

**Why it matters:** Amethyst bundles `UniversalJIT26`/`Extension`, MoltenVK, EGL/LWJGL natives and the
Vulkan bridge, so it is the fastest path to an MC-on-device boot test.

**Next:** assign `universal.js` in StikDebug to Amethyst, launch it with Enable JIT, set up a demo/
offline account, install MC 26.2 and start a world; capture the MC logs and crash state.

### EV-0030 — Amethyst launched via StikDebug dies immediately (attach→continue→detach, no crash report)

| Field | Value |
|---|---|
| Date | 2026-10-31T16:59:44-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Status | `FAIL` |

**Procedure:** launch the re-signed Amethyst via StikDebug Enable JIT to configure Minecraft; inspect
StikDebug `idevice_log`, Amethyst `latestlog.txt`, process list and system crash logs.

**Actual:** StikDebug sends `$vAttach`, `$c`, `$D` within ~28 ms; the Amethyst process is gone
afterwards. No new crash report in `systemCrashLogs` (only the older 12:46 entry). A normal devicectl
launch keeps the process alive (pid 1889). Amethyst's log stops at version-list startup; no account or
version is installed yet.

**Likely cause / next:** the JIT launch path kills the app before setup, or Amethyst aborts at startup
when no script is assigned. Workaround to test: configure Minecraft with a normal launch, then relaunch
under StikDebug only for the game JVM (next evidence ID).

**Artifacts:** `evidence/EV-0030/summary.log`, `latestlog.txt`.

### EV-0031 — MC 26.2 on D1: Amethyst JIT + Java 25 work; boot aborts on missing LWJGL 3.4.1 spvc

| Field | Value |
|---|---|
| Date | 2026-10-31T18:00:12-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Status | `PARTIAL` |

**Procedure:** install Java 25 as an Amethyst external runtime; enable
`debug.debug_always_attached_jit` so its dyld bypass loads the external JRE; launch Amethyst via
StikDebug with `amethyst.js` assigned and press Play on MC 26.2; pull the launcher log and the
Minecraft crash report.

**Actual:** `[JIT26] Requesting 240 MB` → mapping granted; `[DyldLVBypass]` hooks active; Java 25
selected from `Documents/java_runtimes/java-25-openjdk`; `Launching Minecraft 26.2` and
`NativeLibrariesBootstrap` run. Crash: `Loading library spvc` →
`NoClassDefFoundError: org/lwjgl/util/spvc/Spvc`. The log reports **LWJGL 3.3.3-snapshot**; the released
IPA has no `lwjgl_versions.txt` or 3.4.1 assets, while MC 26.2 requires LWJGL 3.4.1.

**Conclusion:** the device launch stack (JIT → JVM → dyld bypass → Java 25 → MC main) is proven; the
remaining blocker is the launcher's bundled LWJGL version. Next: install the current Amethyst
development build (source supports LWJGL 3.4.1).

**Artifacts:** `evidence/EV-0031/latestlog.txt`, `crash.txt`, `summary.log`.

### EV-0032 — MC 26.2 on D1: after grafting LWJGL 3.4.1 Java, JNI_OnLoadGLFW in the app binary crashes (embedded 3.3.3 natives)

| Field | Value |
|---|---|
| Date | 2026-10-31T18:40:23-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Status | `FAIL` |

**Procedure:** graft merged LWJGL 3.4.1 Java jars + the current source's 3.4.1 iOS natives into the
launcher; re-sign and install; launch via StikDebug with `amethyst.js`; pull `latestlog` and `hs_err`.

**Actual:** the `spvc` class error is gone and MC 26.2's `Main` starts, but the JVM dies with
`SIGSEGV` in `jni_GetStaticObjectField`, called from `JNI_OnLoadGLFW` **inside the Amethyst app binary**,
reached from `org.lwjgl.system.Library.<clinit>`. The app binary embeds LWJGL 3.3.3 JNI code, which is
incompatible with the grafted 3.4.1 Java classes.

**Conclusion:** file grafting cannot fix the LWJGL version. The app must be rebuilt from current
Amethyst source (which supports 3.4.1), or another launcher/runtime must be used. The full problem
dossier has been exported to `export/` (and zipped).

**Artifacts:** `evidence/EV-0032/latestlog.txt`, `hs_err.log`, `summary.log`; `export/`.

### EV-0033 — StikDebug 3.2.0 reinstalled for <TEAM_ID>; pairing/DDI/scripts preserved and amethyst.js present

| Field | Value |
|---|---|
| Date | 2026-10-31T20:07:33-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Status | `PARTIAL` |

**Procedure:** download the official StikDebug 3.2.0 IPA; change its bundle id to the existing
`com.stik.stikdebug.<TEAM_ID>` and re-sign with a fresh free-team profile; install over the existing
app; push `amethyst.js` to `Documents/scripts`; verify container data; attempt launch.

**Actual:** install succeeds and the existing data is preserved — `pairingFile.plist`, `DDI/`, and
`Documents/scripts/` (`Geode.js`, `legacy.js`, `maciOS.js`, plus the pushed `amethyst.js`). Launch
verification is blocked by CoreDevice XPC errors (“connection invalidated”) while the device is
locked/asleep; no StikDebug crash report was produced.

**Next:** wake/unlock D1, open StikDebug, long-press Amethyst → Assign Script → `amethyst.js`. The
MC 26.2 LWJGL 3.4.1 blocker (EV-0031/EV-0032) is independent and still needs a current-source
Amethyst rebuild.

**Artifacts:** `evidence/EV-0033/summary.log`.

### EV-0034 — S2 DEVICE WORLD RENDER: Minecraft 26.2 runs a world on Apple Vision Pro with Vulkan/MoltenVK

| Field | Value |
|---|---|
| Date | 2026-10-31T20:28:16-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:** launch Amethyst via StikDebug Enable JIT (`amethyst.js`, JIT26 mapping 240 MB); force
`preferredGraphicsBackend:"vulkan"` + `startedCleanly:true` in MC `options.txt`; launch MC 26.2 with
LWJGL 3.4.1 + external Java 25; create and enter a singleplayer world; capture the MC log.

**Actual:** `[JavaLauncher] RENDERER is set to libMoltenVK.dylib`,
`Using graphics backend Vulkan, using drivers: 1.2.357 MoltenVK 1.4.3`,
`Backend library: LWJGL version 3.4.1-snapshot`, `[VulkanBridge] game renders through Vulkan` (no ANGLE
fallback). Sound engine and texture atlases loaded; world **“New World”** created: 49 spawn chunks,
`<player> joined the game` at 20:27:54.

**Significance:** first Minecraft 26.2 world rendered on Apple Vision Pro. `devicectl` screenshot
capture is unavailable on visionOS, so the MC log is the evidence. A 30-minute soak is running for the
ST-S2 device pass (next evidence ID).

**Artifacts:** `evidence/EV-0034/latestlog.txt`, `summary.log`.

### EV-0035 — S2 device world session: 4m20s of MC 26.2 Vulkan on D1 with a clean save and shutdown (30-min soak deferred)

| Field | Value |
|---|---|
| Date | 2026-10-31T20:32:38-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Status | `PARTIAL` |

**Procedure:** continue the EV-0034 world session; capture the MC log; measure duration and shutdown
behaviour.

**Actual:** joined 20:27:54, left/paused 20:32:14, stopped 20:32:16 = **4m20s in-world**, clean chunk
saves and `Stopping!`; no exception or crash. The user stopped early, so the 30-minute soak is deferred.
Mouse/cursor behaviour was abnormal on visionOS (noted for M1 input work; user says it does not matter
now).

**Artifacts:** `evidence/EV-0035/latestlog.txt`, `summary.log`.

### EV-0036 — M1 T3 acceptance: source-built Amethyst v1.2.0 runs Minecraft 26.2 Vulkan world on D1

| Field | Value |
|---|---|
| Date | 2026-10-31T22:26:08-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:** assemble the Amethyst 1.2.0 source tree (reference tree + submodules) and build `payload`
with the JDK 8 toolchain (deps: native, mcmetal, ame_vulkan, java, jre, assets; MobileGlues/MobileGL
renderer deps dropped for the Vulkan path); re-sign 167 Mach-O for <TEAM_ID> as `dev.vrmc.amethyst` and
install over the existing data container; set `preferredGraphicsBackend:"vulkan"` +
`startedCleanly:true`; launch via StikDebug with `amethyst.js` and press Play.

**Actual:** JIT26 mapping 240 MB; `LWJGL version 3.4.1-snapshot`;
`Using graphics backend Vulkan, using drivers: 1.2.357 MoltenVK 1.4.3`; 49 spawn chunks;
`<player> joined the game` at 22:24:18; process alive. App tree
`sha256 4b1f959a3ead6ad8cc8d08f3c1c672da1484de1764ba738fa5d74d46347cc20a` (558 MB), version
`1.2.0-development`.

**Limitations:** new data containers still need the manual `options.txt` defaults (crash-reset resets the
backend); MobileGlues/MobileGL renderers are not in this build (not needed for Vulkan). M1 remains open
on fresh-install acceptance, app-side defaults, BundleScriptMap re-check, input, and the 30-minute soak.

**Artifacts:** `evidence/EV-0036/latestlog.txt`, `summary.log`.

### EV-0037 — M1 T4: app-side defaults force Vulkan and clear the crash marker — MC boots from a reset options.txt

| Field | Value |
|---|---|
| Date | 2026-10-31T22:37:38-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Status | `PASS` |

**Procedure:** patch Amethyst `MinecraftOptionUtils` to force `preferredGraphicsBackend` (the
launcher-decided value) and set `startedCleanly:true` before every launch; deliberately reset device
`options.txt` to `preferredGraphicsBackend:"default"` + `startedCleanly:false` (the old failing state);
launch via StikDebug with `amethyst.js` and press Play.

**Actual:** post-launch options show `preferredGraphicsBackend:"vulkan"` and `startedCleanly:true`; no
“Detected unexpected shutdown” reset in the log; `Using graphics backend Vulkan, using drivers:
1.2.357 MoltenVK 1.4.3`; world joined 22:36:25; process alive. Patched app tree
`sha256 d8e7a6f6f95d1b4f5a77e70cae2e64a2ed816a32488070d4b36efd3d9a7c1156`.

**Artifacts:** `evidence/EV-0037/latestlog.txt`, `summary.log`.

### EV-0038 — M1 T1: stack pinned with sha256 for Amethyst, StikDebug, OpenJDK, LWJGL, MoltenVK, MC and amethyst.js; check_versions green

| Field | Value |
|---|---|
| Date | 2026-10-31T22:44:00-10:00 |
| Status | `PASS` |

**Actual:** `versions.env` rewritten with the M1 pins and per-component sha256 (Amethyst source-build
tree `3d3a7c18…`, StikDebug IPA `f3b4e1ea…`, JRE tree `7393cf1a…`, LWJGL jars `e6ff1d07…` + natives
`e5cd4f30…`, MoltenVK `03198606…`, MC JSON `267d4b17…`, `amethyst.js` `7fb4b14b…`); env file made
bash-sourceable; `scripts/check_versions.sh` → **8 passed, 0 failed**.

**Artifacts:** `evidence/EV-0038/versions.env`, `check_versions.out`, `summary.log`.

---

### EV-0039 — M1 T2: re-sign, install, push-JIT, MC-options and log-capture scripts live in scripts/ and are re-runnable

| Field | Value |
|---|---|
| Date | 2026-10-31T22:46:27-10:00 |
| Status | `PASS` |

**Actual:** added `scripts/install_device.sh` (DEVICE/UNINSTALL_BUNDLE_ID/DRY_RUN) and
`scripts/README.md`; parameterized `sign_ipa.sh` (BUNDLE_ID/TEAM_ID/IDENTITY/XCENT/PROFILE) and the
push/options/capture scripts (DEVICE + bundle ids). Rehearsals: sign copy of DummyProfile.app (3
Mach-O, team <TEAM_ID>), re-push `amethyst.js` (device hash matches `7fb4b1…`), re-run
`set_mc_options` (vulkan/true), capture logs, DRY_RUN install. Push hit one transient device disconnect
and succeeded on retry.

**Artifacts:** `evidence/EV-0039/summary.log`, rehearsal logs.

---

### EV-0040 — M1 T5: visionOS mouse-delta fix implemented; verdict PARTIAL pending post-patch on-headset verification

| Field | Value |
|---|---|
| Date | 2026-10-31T22:46:43-10:00 |
| Status | `PARTIAL` |

**Actual:** root cause: `GCMouse` deltas gated on `windowScene.pointerLockState.locked` (visionOS
provides no pointer lock). Patch forwards deltas when `isGrabbing` or virtual mouse is enabled;
installed in app tree `b1955fac…`. Post-patch mouse behaviour was not confirmed on the headset during
the sprint (device was relaunched with newer builds). **T5 closed as PARTIAL per directive**; follow-up
`task-1` (T5-FUP1) covers cursor visibility / edge-delta / grab-transition verification.

**Artifacts:** `evidence/EV-0040/summary.log`, `mouse-delta.patch`.

---

### EV-0041 — M1 T3: app-shell route decided — build Amethyst 1.2.0 from source, brand as dev.vrmc.vrmc (ADR-0008)

| Field | Value |
|---|---|
| Date | 2026-10-31T22:47:06-10:00 |
| Status | `PASS` |

**Actual:** ADR-0008 accepted: build Amethyst 1.2.0 (reference tree + submodules), apply VRMC patches,
brand `dev.vrmc.vrmc`; pin/re-sign route only as an emergency fallback that requires a recorded blocker
and transition deadline. Backed by EV-0036 (source build runs MC 26.2 Vulkan world), EV-0037 and
EV-0040. W1 remaining: branding/display name+icon, repo-committed reproducible build script, first-run
layer, clean-container acceptance.

**Artifacts:** `evidence/EV-0041/summary.log`, `docs/adr/0008-m1-app-shell-build-from-source.md`.

### EV-0042 — M1 T4 progress: branded VRMC app (dev.vrmc.vrmc) installed on D1 with a fresh container

| Field | Value |
|---|---|
| Date | 2026-10-31T22:55:20-10:00 |
| Device | D1 Apple Vision Pro `RealityDevice14,1` (visionOS 27.2) |
| Status | `PARTIAL` |

**Procedure:** create a `dev.vrmc.vrmc` provisioning profile; brand the source-built 1.2.0 payload as
VRMC (bundle id + display/name); re-sign 167 Mach-O; uninstall the `dev.vrmc.amethyst` test app (fresh
container) and install VRMC.

**Actual:** profile `<TEAM_ID>.dev.vrmc.vrmc` created; app signed, tree
`sha256 446862ef3c13a37ec95c8e12d3546ec3dc5ed593eb4fb492b1f2b9f4be91f884`; VRMC 1.2.0 installed.
Installed apps: SideStore, StikDebug 3.2.0, VRMC 1.2.0. **No Amethyst test app remains.** First-run
acceptance (VRMC-specific `amethyst.js` assignment, account, MC 26.2 download, world) is pending.

**Artifacts:** `evidence/EV-0042/summary.log`.

### EV-0043 — M1 T4 acceptance: fresh VRMC install reaches the MC 26.2 world with app-side provisioning

| Field | Value |
|---|---|
| Date | 2026-10-31T23:09:24-10:00 |
| Status | `PASS` |

**Actual:** fresh `dev.vrmc.vrmc` container, no test-build data; log shows forced always-attached JIT
on TXM, `DyldLVBypass` hooks active, internal `java-25-openjdk`, `preferredGraphicsBackend=vulkan`,
`Using graphics backend Vulkan … MoltenVK 1.4.3`, world joined 23:08:23. No Mac-side pushes for
JRE/options/script after install; only the on-device StikDebug script assignment and the launcher's
account/version flow.

**Artifacts:** `evidence/EV-0043/latestlog.txt`, `summary.log`.

---

### EV-0044 — M1 T6: 30-minute MC 26.2 world soak — no game crash, no watchdog kill; thermal recorded

| Field | Value |
|---|---|
| Date | 2026-10-31T23:40:30-10:00 |
| Status | `PASS` |

**Actual:** 1805 s continuous in-world (23:08:23–23:38:28); process alive at check; 0 ERROR/Exception
lines after join; no game crash, no game watchdog kill. Thermal recorded from system metadata:
`Thermal Level: 0 / Thermal State: serious` at 23:11:09. Incident: StikDebug 3.2.0 was SIGKILLed by a
FrontBoard scene-update watchdog at 23:11:09 (background); the game was unaffected.

**Artifacts:** `evidence/EV-0044/latestlog.txt`, `summary.log`, `StikDebug-…ips`.

---

### EV-0045 — T5-FUP1: in-world cursor does not hide and camera rotation is not smooth — FAIL

| Field | Value |
|---|---|
| Date | 2026-10-31T23:46:26-10:00 |
| Status | `FAIL` |

**Actual:** user report; source analysis shows the SDL3 path feeds absolute cursor positions when
`isGrabbing` is false (visible pointer + jerky rotation), raw deltas when true. SDL3 grab forwarding not
confirmed on visionOS. Follow-up `task-2`; T5 itself stays closed PARTIAL.

**Artifacts:** `evidence/EV-0045/summary.log`.

---

### EV-0046 — Background once freezes Minecraft (needs refresh) and audio is lost — FAIL, fix in progress

| Field | Value |
|---|---|
| Date | 2026-10-31T23:46:26-10:00 |
| Status | `FAIL` |

**Actual:** user backgrounded the game once; it froze and needed a refresh/relaunch, sound was lost.
Source: `SceneDelegate` lifecycle callbacks are empty; `updateAudioSettings()` only runs at `viewDidLoad`;
the render gate depends on `UIApplication` notifications. Fix in progress (scene callbacks + audio
reactivation/interruption handling); follow-up `task-3`.

**Artifacts:** `evidence/EV-0046/summary.log`.

### EV-0047 — T5-FUP1 retest: rotation smooth (grab path active); cursor still visible (cosmetic, accepted)

| Field | Value |
|---|---|
| Date | 2026-11-01T00:07:09-10:00 |
| Status | `PARTIAL` |

**Actual:** log shows `[Input] nativeSetGrabbing 1` → `grabState isGrabbing=1`; user confirms rotation is
now smooth. Cursor still visible: `pointerLockSupported=1` but `pointerLockState.locked=0` even while
grabbing, so visionOS never hides the system pointer through `prefersPointerLocked`. User accepted the
cursor visibility as cosmetic. `task-2` closed.

**Artifacts:** `evidence/EV-0047/latestlog.txt`, `summary.log`.

---

### EV-0048 — Lifecycle/audio retest: background/foreground resumes with sound after scene+audio fix

| Field | Value |
|---|---|
| Date | 2026-11-01T00:07:09-10:00 |
| Status | `PASS` |

**Actual:** user reports “everything else is good” with only the accepted cursor cosmetic issue; no
freeze and no sound loss on background/foreground. Log shows OpenAL CoreAudio initialized and a normal
session. `task-3` closed.

**Artifacts:** `evidence/EV-0048/latestlog.txt`.

### EV-0049 — M1 W1: reproducible launcher build script tested from a fresh Amethyst 1.2.0 tree + VRMC patches

| Field | Value |
|---|---|
| Date | 2026-11-01T00:10:30-10:00 |
| Status | `PASS` |

**Actual:** committed `scripts/build_launcher.sh`, `patches/vrmc-m1-amethyst-1.2.0.patch` and
`docs/mvp/LAUNCHER_BUILD.md`; ran the script against a fresh copy of the reference tree with submodules
and cached depends: exit 0, payload version 1.2.0 with `lwjgl_versions.txt`, `Frameworks/lwjgl34` and
bundled `java-25-openjdk`; unsigned payload tree `sha256 0b0b80ec…` (rebuild hashes are not bit-identical
because of zip/asset timestamps; inputs are pinned by `AMETHYST_SOURCE_TREE_SHA256` and
`VRMC_PATCH_SHA256`).

**Artifacts:** `evidence/EV-0049/buildtest.log`, `summary.log`.

### EV-0050 — M1 W3: explicit in-app JIT preflight guidance for StikDebug/amethyst.js installed (verification pending)

| Field | Value |
|---|---|
| Date | 2026-11-01T00:17:04-10:00 |
| Status | `PARTIAL` |

**Actual:** added `[JIT] preflight` logging (`isJITEnabled`/`hasTXM`/`hasMirrored`) and a TXM alert that
states the exact steps (long-press VRMC → Assign Script → `amethyst.js`; Enable JIT → VRMC; keep VRMC
open and the game continues automatically). Rebuilt, re-signed (167 Mach-O) and installed as
`dev.vrmc.vrmc` (tree `sha256 01804065…`). No-JIT launch-flow verification on D1 is pending.

**Artifacts:** `evidence/EV-0050/summary.log`.

### EV-0051 — M1 W3 verification: no-JIT launch preflight guides to StikDebug and the game continues after JIT is enabled — PASS

| Field | Value |
|---|---|
| Date | 2026-11-01T00:24:41-10:00 |
| Status | `PASS` |

**Actual:** log shows `[JIT] preflight isJITEnabled=0 hasTXM=1 hasMirrored=1`; user confirms the alert
flow (Assign Script → `amethyst.js`, Enable JIT → VRMC) and that the game continued after JIT was
enabled. Installed build tree `sha256 01804065…`.

**Artifacts:** `evidence/EV-0051/latestlog.txt`, `w3-summary.log`.

---

### EV-0052 — M1 W7 verification: clean save/quit and save preserved across relaunch — PASS

| Field | Value |
|---|---|
| Date | 2026-11-01T00:24:41-10:00 |
| Status | `PASS` |

**Actual:** log shows joined 00:23:17, `Saving and pausing game...` 00:23:56, `left the game` 00:23:57,
`Stopping!` 00:23:59. User confirms the relaunched world loads with changes preserved. Combined with the
30-minute soak (EV-0044), acceptance #2 is complete.

**Artifacts:** `evidence/EV-0052/latestlog.txt`, `w7-summary.log`.

### EV-0053 — M1 W6: log/crash retrieval path confirmed — in-app Send logs/Log output share + repo capture scripts

| Field | Value |
|---|---|
| Date | 2026-11-01T00:29:57-10:00 |
| Status | `PASS` |

**Actual:** launcher menu `Send logs` shares `latestlog.old.txt`; in-game **Log output** overlay
(`PLLogOutputView`) has a *Share latestlog.txt* action and per-line share, and appears on fatal exit;
MC crash reports are stored under `Documents/instances/default/crash-reports/`; repo scripts retrieve
logs (EV-0039). Device share-sheet not exercised per user decision.

**Artifacts:** `evidence/EV-0053/summary.log`.

### EV-0054 — M1 W1 polish: VRMC app icon + first-run welcome checklist built/signed (install pending device wake)

| Field | Value |
|---|---|
| Date | 2026-11-01T00:34:30-10:00 |
| Status | `PARTIAL` |

**Actual:** committed `assets/branding/` (VRMC icon PNGs) + `scripts/make_icon.py`, wired them into
`scripts/build_launcher.sh`; added a one-time “Welcome to VRMC” checklist in
`LauncherMenuViewController` (StikDebug script/JIT, account, MC install, Play; Java 25/LWJGL/Vulkan
note). Built and re-signed (tree `e9ad22b6…`); install failed 8× because the device is asleep/locked
(`AMDeviceCreate`/`IXRemoteError`). Install and visual verification pending the next awake-device
session.

**Artifacts:** `evidence/EV-0054/summary.log`.

### EV-0055 — M1 W1: reproducible build re-verified with VRMC branding assets and updated patch set

| Field | Value |
|---|---|
| Date | 2026-11-01T00:39:00-10:00 |
| Status | `PASS` |

**Actual:** `scripts/build_launcher.sh` ran from a fresh reference tree with the 11-file VRMC patch and
`assets/branding/` icon installation: exit 0, payload version 1.2.0 (Java 25/LWJGL 3.4.1), tree
`sha256 6c17e7b5…`. Icon files were regenerated after this run (layout tweak); branding-copy mechanics
unchanged.

**Artifacts:** `evidence/EV-0055/buildtest.log`, `summary.log`.

### EV-0056 — M1 W1: final branded VRMC build (icon + first-run checklist) installed on D1

| Field | Value |
|---|---|
| Date | 2026-11-01T00:43:00-10:00 |
| Status | `PASS` |

**Actual:** rebuilt with the final icon layout and first-run checklist, branded `dev.vrmc.vrmc` /
VRMC, 167 Mach-O re-signed; install succeeded on retry after the device woke (final app tree
`sha256 ee8d4558…`). App list shows VRMC. Visual verification of the icon/welcome screen pending the
next launch (cosmetic).

**Artifacts:** `evidence/EV-0056/summary.log`.

### EV-0057 — M1 milestone CLOSED — launcher shell + fresh install + flat MC boot + 30-minute soak all evidenced

| Field | Value |
|---|---|
| Date | 2026-11-01T00:39:13-10:00 |
| Status | `PASS` |

**Actual:** M1 exit criteria met — fresh install → world (EV-0043), 1805 s soak (EV-0044), save/relaunch
(EV-0052). Acceptance matrix #1–#5/#7 PASS; #6 PASS with controller-first defaults deferred to M4.
W1–W7 closed or closed-with-accepted-cosmetic. Matrix: `docs/mvp/M1_ACCEPTANCE.md`.

**Artifacts:** `evidence/EV-0057/summary.log`.

---

### EV-0058 — M2 started: plan + native bridge ABI v1 stub (compiled/tested) + provider mod skeleton

| Field | Value |
|---|---|
| Date | 2026-11-01T00:40:18-10:00 |
| Status | `PASS` |

**Actual:** `docs/mvp/M2_PLAN.md` committed; `bridge/abi/vrmc_abi.h` ABI v1 (fail-closed) +
`bridge/src/vrmc_stub.c` compiled (`libvrmc_bridge.dylib sha256 386e3a92…`) and `VRMC_STUB_TEST` prints
`ok version=1 frames=1 ipd=0.064`; provider scaffold (`VisionVR` fail-closed init, `VisionRenderer`,
`VRStateMixin`, resources). Next: S4a Vulkan→Metal eye-handoff spike + provider build harness.

**Artifacts:** `evidence/EV-0058/summary.log`.

### EV-0059 — M2-W1 host harness: provider scaffold substitutes VisionVR on desktop Fabric and fails closed without the bridge

| Field | Value |
|---|---|
| Date | 2026-11-01T00:43:38-10:00 |
| Status | `PASS` |

**Actual:** provider scaffold compiled (javac 25) against MC 26.2 + Fabric 0.19.3 + Vivecraft
26.2-1.3.15 and packaged; installed in the desktop Fabric harness with `vrEnabled=true`,
`stereoProviderPluginID=OPENVR`. Log: `[VRMC-M2] provider redirect; original=…MCOpenVR`,
`VisionVR constructed`, `dh.vr is now dev.vrmc.provider.VisionVR`, `init() skeleton reached; failing
closed`; Vivecraft shows `Render setup failed: VRMC M2: native bridge not wired yet / VR provider: VRMC`.
No SteamVR/OpenVR runtime involved. Provider jar `sha256 cc766804…`. S4a static findings in
`docs/mvp/S4A_FINDINGS.md`.

**Artifacts:** `evidence/EV-0059/m2-harness.log`, `summary.log`, `vrmc-provider.jar`.

### EV-0060 — M2-W4/W5 host: bridge handshake + provider init + stereo eye targets + per-frame submit loop (no SteamVR)

| Field | Value |
|---|---|
| Date | 2026-11-01T00:48:06-10:00 |
| Status | `PASS` |

**Actual:** JNI shim (`bridge/src/vrmc_jni.c`) + `VrmcBridge` + bridge-backed `VisionVR`/`VisionRenderer`
ported from the macstream reference; provider jar `sha256 9c91d7b9…`, bridge dylib
`sha256 303dbc35…`. Host harness log: `[VRMC-M2] bridge handshake ok (ABI v1)`,
`VisionVR.init() succeeded`, `VisionRenderer created`, `eye target L/R 1024x1024`,
`VR Provider supplied texture resolution: 1024 x 1024`, `Total shaded pixels per frame: 2.1MP`,
tracking polled 8400+ frames, no crash (operator-stopped), no SteamVR. First run hit an
`MCVR.updateAim` NPE from null controller component transforms — fixed with identity transforms.

**Artifacts:** `evidence/EV-0060/m2-bridge-run2.log`, `summary.log`, `vrmc-provider.jar`,
`libvrmc_bridge.dylib`.

### EV-0061 — M2 review fixes: host/device scope, host-only identity fallback, macstream compliance, S4a split gates, W6 preconditions, ABI evolution policy

| Field | Value |
|---|---|
| Date | 2026-11-01T01:08:52-10:00 |
| Commit | `ee81a466790e854b85eab5f9a0c32d4eac39a07b` |
| Dirty state | GENT.md, README.md, VERIFY.md, bridge/abi/vrmc_abi.h, docs/adr/0005-input-psvr2-and-hands.md, docs/mvp/M1_ACCEPTANCE.md, docs/mvp/M2_PLAN.md, docs/mvp/MACSTREAM_REFERENCE.md, docs/mvp/MVP_SCOPE.md, docs/mvp/SPIKES.md, provider/HOST_HARNESS.md, provider/src/main/java/dev/vrmc/provider/VisionVR.java, scripts/log_evidence.sh, docs/adr/0009-macstream-tracked-reference.md |
| Device | documentation + host harness only; device remains NOT RUN |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. apply the three required fixes and three confirmations from the M2 review
2. update AGENT/VERIFY/M2_PLAN/SPIKES/MACSTREAM_REFERENCE/ADR-0009/bridge ABI header and the provider host-only code path

**Expected:** EV-0060 explicitly host-scoped; identity fallback host-only with fail-loud device path; macstream port recorded; S4a split gates; W6 preconditions; ABI policy

**Actual:** all six applied; host harness code compiled; provider jar rebuilt with -Dvrmc.hostHarness flag path; docs propagated. Device items remain NOT RUN.

**Artifacts:** evidence/EV-0061/summary.log (0ba5f2374544)

**Limitations:** Companion scope EV-0062 records the PSVR2 P1/DEFERRED decision.

---

### EV-0062 — PSVR2 Sense controller input (F1–F3) — DEFERRED (out of MVP scope), not BLOCKED

| Field | Value |
|---|---|
| Date | 2026-11-01T01:08:52-10:00 |
| Commit | `ee81a466790e854b85eab5f9a0c32d4eac39a07b` |
| Dirty state | GENT.md, README.md, VERIFY.md, bridge/abi/vrmc_abi.h, docs/adr/0005-input-psvr2-and-hands.md, docs/mvp/M1_ACCEPTANCE.md, docs/mvp/M2_PLAN.md, docs/mvp/MACSTREAM_REFERENCE.md, docs/mvp/MVP_SCOPE.md, docs/mvp/SPIKES.md, provider/HOST_HARNESS.md, provider/src/main/java/dev/vrmc/provider/VisionVR.java, scripts/log_evidence.sh, docs/adr/0009-macstream-tracked-reference.md |
| Device | scope decision (no device run) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `DEFERRED` |

**Procedure:**

1. record the permanent scope decision and propagate it through the specification, ADR-0005, spikes, milestones, risks and verification docs

**Expected:** PSVR2 is P1/DEFERRED; MVC/P0 scope is hands-only; no document claims controller input parity

**Actual:** F1–F3 moved to the P1 register; AC-4 hands-only; M4/M6 exit hands-only; G2/G3/G4 HIGH (no fallback); ST-S5 split; DEFERRED status defined in VERIFY; ADR-0005 amended; docs propagated.

**Artifacts:** evidence/EV-0062/summary.log (2ec87797eec6)

**Limitations:** Re-entry requires a new scope decision. Not BLOCKED: BLOCKED would imply a future automatic resolution.

### EV-0063 — S4a-host PASS: MoltenVK MTLTexture export + Metal pixel readback + MTLSharedEvent synchronization work on macOS host

| Field | Value |
|---|---|
| Date | 2026-11-01T01:13:12-10:00 |
| Commit | `d329ed07e46d37aaf0ed37cdc16f78cecbb7584e` |
| Dirty state | runtime/probes/s4a-host/ |
| Device | host macOS (Mac16,7, MoltenVK 1.4.2; visual parity with bundled 1.4.3 build) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. spike runtime/probes/s4a-host/spike_s4a.mm: create VkInstance/device with VK_EXT_metal_objects; export MTLDevice; create exportable VkImage; clear it to red via Vulkan; export MTLTexture; read it back through Metal; verify pixels
2. create a timeline VkSemaphore with VK_EXPORT_METAL_OBJECT_TYPE_METAL_SHARED_EVENT_BIT_EXT; export MTLSharedEvent; signal value 42 from Vulkan; read signaledValue in Metal

**Expected:** MTLDevice + MTLTexture export works, Metal pixels match Vulkan clear, MTLSharedEvent observes Vulkan signal

**Actual:** PASS: exported MTLDevice yes; exported MTLTexture 64x64 (RGBA8Unorm); Metal readback pixel = 255,0,0,255 as expected; timeline VkSemaphore exported MTLSharedEvent, signaledValue=42 after Vulkan signal. Binary semaphore export yields nil (timeline required). S4a-device remains NOT RUN.

**Artifacts:** evidence/EV-0063/spike_s4a.mm (cce0584a3fa2); evidence/EV-0063/spike_s4a (7cb4158a87e0); evidence/EV-0063/spike_s4a.log (0816d75c4ebd); evidence/EV-0063/summary.log (8422d7310a4c)

**Limitations:** Host gate only. Device gate (S4a-device) is separate: macOS Metal object handles do not prove visionOS MoltenVK/Metal. M3 must use a timeline semaphore for shared-event sync.

### EV-0064 — S4a-device probe staged inside the VRMC app — NOT RUN (device locked)

| Field | Value |
|---|---|
| Date | 2026-11-01T01:27:44-10:00 |
| Commit | `f72572b5383b5361a2bc6982fed6bbbdafa9e9e1` |
| Dirty state | atches/vrmc-m1-amethyst-1.2.0.patch, scripts/build_launcher.sh, versions.env, assets/vulkan_include/, runtime/probes/s4a-device/ |
| Device | D1 Apple Vision Pro (passcodeRequired=true at attempt time) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `NOT RUN` |

**Procedure:**

1. add Natives/vrmc_s4a_probe.m to the app (triggered by Documents/vrmc_s4a_device.flag), wire it into CMake/main.m, build/sign/install with bundled MoltenVK 1.4.3
2. push the flag file and try to launch the app via devicectl

**Expected:** S4a-DEVICE PASS in Documents/s4a-device.log (MTLDevice+MTLTexture export, Metal readback, timeline MTLSharedEvent sync)

**Actual:** probe built/installed (tree 6d6d4773...), flag present; launch blocked because the device is locked; no log produced. NOT RUN.

**Artifacts:** evidence/EV-0064/vrmc_s4a_probe.m (d9b8176487ab); evidence/EV-0064/summary.log (69c29b4aa8f1); evidence/EV-0064/build.log (e0c75105d02a)

**Limitations:** Unlock the AVP and launch VRMC to execute the probe; then pull Documents/s4a-device.log. This is a separate gate from S4a-host (EV-0063).

### EV-0065 — S4a-device PASS: bundled MoltenVK 1.4.3 exports MTLDevice/MTLTexture and timeline MTLSharedEvent sync works on D1

| Field | Value |
|---|---|
| Date | 2026-11-01T06:14:36-10:00 |
| Commit | `a95cfe133faa1e506ecb9f6fcabe3b47a9b0ef22` |
| Dirty state | untime/probes/s4a-device/vrmc_s4a_probe.m |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. probe compiled into the VRMC app (runtime/probes/s4a-device), triggered by Documents/vrmc_s4a_device.flag on launch
2. load Frameworks/libMoltenVK.dylib; VK_EXT_metal_objects device extension; export MTLDevice; create exportable VkImage; clear red via Vulkan; export MTLTexture; read back via Metal; timeline MTLSharedEvent export + signal 42 via Vulkan

**Expected:** MTLDevice+MTLTexture export works, Metal pixel readback correct, timeline MTLSharedEvent sees Vulkan signal

**Actual:** PASS on D1: VK_EXT_metal_objects=1; MTLDevice export yes; MTLTexture 64x64 RGBA8Unorm export yes; Metal readback=255,0,0,255; timeline MTLSharedEvent export yes, signaledValue=42 after Vulkan signal. App tree 5089b4a8... . S4a-host and S4a-device gates both PASS.

**Artifacts:** evidence/EV-0065/s4a-device.log (f938eae4da2c); evidence/EV-0065/vrmc_s4a_probe.m (c10d310bd021); evidence/EV-0065/summary.log (a9503ebdde39); evidence/EV-0065/build.log (c25ce90131de)

**Limitations:** This validates the M3 eye-texture/compositor substrate on device. M2-W6 (provider init on device) and M3 (compositor stereo/head tracking) remain NOT RUN.

### EV-0066 — M2-W6 prep: iOS bridge dylib embedded/signed + JVM arg injection + provider/Vivecraft jars staged on device

| Field | Value |
|---|---|
| Date | 2026-11-01T06:18:52-10:00 |
| Commit | `2ed77e148dd1d7288a9483c1cb851484c4274afe` |
| Dirty state | atches/vrmc-m1-amethyst-1.2.0.patch, scripts/build_launcher.sh, versions.env |
| Device | D1 Apple Vision Pro (bridge dylib installed; Fabric loader missing) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. build libvrmc_bridge for arm64-apple-ios14 with JNI headers; embed in app Frameworks; sign (168 Mach-O); add -Dvrmc.bridge.lib in JavaLauncher when the dylib exists
2. install app; push vrmc-provider.jar and vivecraft-26.2-1.3.15-fabric.jar into Documents/instances/default/mods/

**Expected:** app+bridge+mods staged; W6 device provider run still needs Fabric loader

**Actual:** bridge dylib built (platform IOS minos 14.0, JNI symbols), embedded/signed (app tree 8dc643ae...); JVM arg injection added; provider+Vivecraft jars staged. Device has only vanilla 26.2 — Fabric 0.19.3 loader install remains, so W6 device run is NOT RUN.

**Artifacts:** evidence/EV-0066/libvrmc_bridge_ios.dylib (f43e80048646); evidence/EV-0066/summary.log (d7c8c3824b7b); evidence/EV-0066/build.log (5a3caa98a366)

**Limitations:** M2-W6 preconditions: Fabric 0.19.3 -> Vivecraft (staged) -> provider (staged) -> launch. Remaining device action: install Fabric loader via launcher UI.

### EV-0067 — M2-W6 device attempt 1 — provider init reached but crashed on component-transform guard; fix applied

| Field | Value |
|---|---|
| Date | 2026-11-01T06:41:08-10:00 |
| Commit | `5db3fd020b7af789043875f2d63d2d541509fa05` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro (Fabric 0.20.1 + Vivecraft 26.2-1.3.15 + vrmc-provider) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `FAIL` |

**Procedure:**

1. launch MC via VRMC with JIT; Fabric 0.20.1; provider mixin + bridge dylib; Vivecraft vrEnabled=true/OPENVR

**Expected:** provider init and stable frame loop with no SteamVR

**Actual:** provider redirect fired; VisionVR constructed; dh.vr=VisionVR; bridge handshake ok (ABI v1); VisionVR.init() succeeded; VisionRenderer created; eye targets 1024x1024. Then crashed in poll(): IllegalStateException 'missing controller/hand transform on device (controller=0, component=handgrip)' from the identity guard. Root cause: guard applied to static component offsets, not tracking data. Fix applied: identity component offsets; fail-loud moved to tracking-pose validation; new provider jar pushed.

**Artifacts:** evidence/EV-0067/latestlog.txt (840911a8cb09); evidence/EV-0067/crash.txt (4fb8cc85a244); evidence/EV-0067/summary.log (7d0c3eb6d324)

**Limitations:** Retry with updated provider jar; expected provider init + frame loop, then record EV-0068.

---

### EV-0068 — M2-W6 PASS: device provider init + bridge handshake + stereo render passes + no SteamVR (Fabric 0.20.1)

| Field | Value |
|---|---|
| Date | 2026-11-01T06:46:38-10:00 |
| Commit | `5db3fd020b7af789043875f2d63d2d541509fa05` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. launch MC 26.2 via VRMC with StikDebug JIT; Fabric Loader 0.20.1; Vivecraft 26.2-1.3.15 + vrmc-provider; bridge dylib ABI v1 stub; Vivecraft vrEnabled=true/OPENVR

**Expected:** provider init + bridge handshake + stereo eye targets/render passes + no SteamVR/OpenVR runtime

**Actual:** PASS: provider redirect fired; VisionVR constructed; dh.vr=VisionVR; [vrmc-stub] init ok abi=1; bridge handshake ok (ABI v1); VisionVR.init() succeeded; VisionRenderer created; eye targets L/R 1024x1024; Vivecraft 'Active RenderPasses: LEFT, RIGHT' + GUI/keyboard/radial/telescope targets; tracking frames polled (1501+); no crash report; no SteamVR failure. Game is not playable yet: M3 compositor/head tracking and M4 input are NOT RUN (low/unusable view, no click) — expected.

**Artifacts:** evidence/EV-0068/latestlog.txt (6109d4b0ce6b); evidence/EV-0068/summary.log (4e88c1f1aa1c)

**Limitations:** Fabric pin is 0.19.3 in versions.env; device used 0.20.1 as a compatibility candidate and the provider loaded + initialized successfully. M2 remainder: wire S4a device eye export/submit into VisionRenderer; M3/M4 next.

### EV-0069 — M2-W5 device eye handoff PASS: Vulkan VkImage exported to MTLTexture (ABI v2) and submitted from the provider

| Field | Value |
|---|---|
| Date | 2026-11-01T06:55:52-10:00 |
| Commit | `09646565f8bd8083d3fc24ea1bf6ebe5bbdb7e8c` |
| Dirty state | ridge/abi/vrmc_abi.h, bridge/src/vrmc_jni.c, bridge/src/vrmc_stub.c, provider/src/main/java/dev/vrmc/provider/VisionRenderer.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/src/main/java/dev/vrmc/provider/bridge/VrmcBridge.java |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2; Fabric 0.20.1, Vivecraft 26.2-1.3.15) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. provider VisionRenderer reads the Vulkan eye VkImage via GraphicsHelper.getTextureHandle; bridge ABI v2 vrmc_export_mtl_texture exports MTLTexture (vkGetMTLTextureMVK); vrmc_submit_eyes receives real Metal handles

**Expected:** first frame logs a non-zero VkImage->MTLTexture export and submit succeeds, no crash

**Actual:** device log: '[VRMC-M2] vulkan eye export: VkImage=0x139dccf00 -> MTLTexture=0x7107982300'; ABI 2 handshake; LEFT/RIGHT render passes; 9*300 tracking frames; no export/submit failures; clean stop.

**Artifacts:** evidence/EV-0069/latestlog.txt (456598e4b757); evidence/EV-0069/summary.log (9d696e716cae)

**Limitations:** Completes M2-W5's device eye-handoff item. Immersive presentation/head tracking remain M3; input remains M4.

---

### EV-0070 — M2 milestone CLOSED — provider init + stereo eye targets + ABI v2 eye handoff + no VR runtime, all evidenced

| Field | Value |
|---|---|
| Date | 2026-11-01T06:56:02-10:00 |
| Commit | `09646565f8bd8083d3fc24ea1bf6ebe5bbdb7e8c` |
| Dirty state | ridge/abi/vrmc_abi.h, bridge/src/vrmc_jni.c, bridge/src/vrmc_stub.c, provider/src/main/java/dev/vrmc/provider/VisionRenderer.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/src/main/java/dev/vrmc/provider/bridge/VrmcBridge.java, docs/mvp/M2_ACCEPTANCE.md |
| Device | D1 Apple Vision Pro (device bring-up) + host harness |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. review M2 exit criteria against the recorded evidence; verify the 2026-11-01 review's host-vs-device split is respected

**Expected:** M2 exit criteria 1-6 evidenced; M3/M4 explicitly NOT RUN

**Actual:** M2 CLOSED: provider init (EV-0068), stereo targets (EV-0068), handshake (EV-0068), eye handoff (host EV-0060; substrate EV-0063/EV-0065; device VkImage->MTLTexture EV-0069), no VR runtime (EV-0068), host harness (EV-0060). M3 compositor/head tracking and M4 input remain NOT RUN; game not playable yet by design.

**Artifacts:** evidence/EV-0070/summary.log (4c16ecfc39f8); evidence/EV-0070/M2_ACCEPTANCE.md (f44f89c6301a)

**Limitations:** Fabric 0.20.1 vs pin 0.19.3 recorded as candidate; pin/ADR decision carried to M3. Next milestone: M3.

### EV-0071 — M3a gate 1 PASS: the launcher builds as a native visionOS (xros) payload

| Field | Value |
|---|---|
| Date | 2026-11-01T06:58:52-10:00 |
| Commit | `c492da428ef78c456723da4d9731e5dd1d8035e4` |
| Dirty state | docs/adr/0010-m3-native-visionos-app.md, docs/mvp/M3_PLAN.md |
| Device | host build only (no device launch yet) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. make PLATFORM=11 RELEASE=0 payload with the VRMC patch set; verify Mach-O platform, Info.plist and relabelled natives

**Expected:** native visionOS payload builds (platform VISIONOS, arm64)

**Actual:** build exit 0; main binary platform VISIONOS minos 1.0 sdk 1.0; Frameworks/lwjgl34/liblwjgl.dylib relabelled VISIONOS; Info version 1.2.0. Native launch/immersive space/MC hosting NOT RUN.

**Artifacts:** evidence/EV-0071/xros-build.log (4ed0a94835cb); evidence/EV-0071/summary.log (5ee957097c35)

**Limitations:** M3a gate 1 of 3. Gates 2 (immersive space + ARKit poses) and 3 (MC/JVM/JIT/Vulkan inside the native app) remain NOT RUN; ADR-0010 chooses the native app route.

### EV-0072 — M3a gate 2 PARTIAL: native immersive space + CompositorServices render loop work on D1; stereo presentation still missing (passthrough)

| Field | Value |
|---|---|
| Date | 2026-11-01T07:45:21-10:00 |
| Commit | `b4ac6ae2c67f9e480405f84b7684355502f8a9fc` |
| Dirty state | runtime/probes/m3a-immersive/ |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. build/sign native visionOS probe (dev.vrmc.vrmc), install over the existing app, launch, tap Open immersive space
2. CompositorLayer + Metal clear per-eye test pattern + encodePresent; ARKit world tracking; log to Documents/m3a-probe.log

**Expected:** immersive red/green stereo test pattern visible; ARKit anchor logged

**Actual:** immersive space opened and the CompositorServices render loop ran 2700+ frames without a crash (frame 2400/2700 logs), but the user saw passthrough instead of the test pattern and the ARKit anchor stayed '(pending)'. Three crash modes were fixed (premature endSubmission, missing cp_drawable_encode_present, main-thread blocking watchdog); remaining: device anchor/presentation-time wiring. PARTIAL.

**Artifacts:** evidence/EV-0072/m3a-probe.log (7429c689f551); evidence/EV-0072/summary.log (bb6166ce7e0b); evidence/EV-0072/latest.ips (1d892683991f)

**Limitations:** Next: port probe to the Apple C sample structure (cp_drawable_set_device_anchor + cp_time_to_cf_time_interval) and verify visual presentation before marking gate 2 PASS.

### EV-0073 — M3a gate 2 diagnostics: per-eye GPU content renders correctly (readback red/green) but presentation is black/passthrough — PARTIAL

| Field | Value |
|---|---|
| Date | 2026-11-01T08:03:46-10:00 |
| Commit | `5ba0820bbccbdb47d4800423cbeb52b3989da2b5` |
| Dirty state | untime/probes/m3a-immersive/Sources/M3AProbeApp.swift, runtime/probes/m3a-immersive/project.yml, runtime/probes/m3a-immersive/Sources/Bridging.h, runtime/probes/m3a-immersive/Sources/ProbeRenderer.mm |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. C-sample-shaped native visionOS probe: CompositorLayer full immersion, dedicated thread, per-eye Metal clear, ARKit anchor at presentation time, encodePresent, GPU readback

**Expected:** user sees red/green stereo; readback proves content

**Actual:** readback eye0 pixel0 = r=0.800 g=0.050 b=0.050 a=1.000, cb completed status=4/no error; view count=2, 1888x1792 rgba16Float; user sees pure black with device anchor set and passthrough without it; ARKit anchor success pos=(-0.00,1.17,0.00). Rendering correct; presentation/anchor wiring missing.

**Artifacts:** evidence/EV-0073/m3a-probe.log (d7554f35b13e); evidence/EV-0073/summary.log (b5a7be9ba34f)

**Limitations:** Gate 2 remains PARTIAL. Next: compare against the Apple-style reference sample (build blocked: Metal Toolchain missing) or port remaining drawable/layer setup; no further device churn until then. VRMC launcher restored.

### EV-0074 — M3a gate 2 PASS: native visionOS immersive space presents per-eye CompositorServices stereo (red/green) on D1

| Field | Value |
|---|---|
| Date | 2026-11-01T08:07:45-10:00 |
| Commit | `ae6b4e49fcb3a1407e157ccaf839b5ae032ae640` |
| Dirty state | untime/probes/m3a-immersive/Sources/ProbeRenderer.mm |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. install native visionOS probe, open immersive space, render per-eye clear test pattern through CompositorServices (depth attachment + rate map parity), ARKit anchor at presentation time

**Expected:** user sees left-eye red / right-eye green immersive stereo; readable GPU content and completed command buffer

**Actual:** PASS: user reports seeing both red and green in the immersive space; log shows 2 views 1888x1792 rgba16Float, depthTex present, cb completed status=4/no error, eye0 readback r=0.800 g=0.050 b=0.050 a=1.000, ARKit anchor success. Root cause of earlier black screen: missing drawable depth attachment/rasterization-rate map in the render pass.

**Artifacts:** evidence/EV-0074/m3a-probe.log (3223a0efc509); evidence/EV-0074/summary.log (45101ebed920)

**Limitations:** Gate 2 PASS. Gate 3 (hosting MC/JVM/JIT/Vulkan in the native app) remains NOT RUN; next milestone step. VRMC launcher restored after the probe.

### EV-0075 — M3a gate 3 attempt PARTIAL/blocked: native visionOS launcher runs but its window content is blank, so JIT+MC hosting is unverified

| Field | Value |
|---|---|
| Date | 2026-11-01T08:18:40-10:00 |
| Commit | `c9a2103a940c186756c7bc07f85da14b60c7a079` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. native PLATFORM=11 build, brand/sign (168 Mach-O), install, StikDebug Enable JIT, launch, compare direct devicectl launch

**Expected:** launcher UI visible and playable, then MC/JVM/JIT/Vulkan start in the native app

**Actual:** App launches without crashing (process alive; pre-init/version list logged) but window title bar only, content blank; no [JIT] lines, no game launch. Direct launch shows the same blank window. No crash report; StikDebug did not crash. Gate 3 remains NOT RUN.

**Artifacts:** evidence/EV-0075/latestlog.txt (df4c114d892e); evidence/EV-0075/summary.log (f33411283127)

**Limitations:** Compat launcher reinstalled; data intact. Next: native window/scene debugging or ADR-0010 fallback B (companion) if not quickly fixable.

### EV-0076 — M3a gate 3 diagnostics: native window/scene + LauncherSplitViewController are correct (1280x720) but content renders blank

| Field | Value |
|---|---|
| Date | 2026-11-01T08:29:29-10:00 |
| Commit | `fb431a0b56d1fa331a3a2edd98cf7c9ea0591a84` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. install instrumented native launcher, launch via StikDebug JIT flow, read Documents/native-ui.log

**Expected:** launcher content visible; game launch possible

**Actual:** willConnect bounds 1280x720; rootVC=LauncherSplitViewController; window visible/alpha 1; view _UISplitViewControllerPanelImplView 1280x720 with 2 subviews; user still sees blank content. Native UIKit presentation issue; gate 3 NOT RUN.

**Artifacts:** evidence/EV-0076/native-ui.log (5a169b8ec222); evidence/EV-0076/latestlog.txt (905db9b62d30); evidence/EV-0076/summary.log (c80f05a7f355)

**Limitations:** Window/scene/rootVC are correct => issue is UIKit content rendering on visionOS native, not scene setup. Compat launcher restored. Next: SwiftUI window shell hosting launcher VC (M3-W1) or ADR-0010 fallback companion.

### EV-0077 — M3a gate 3 PASS: native visionOS app hosts MC 26.2 + Fabric + Vivecraft + provider + JIT + Vulkan (auto-launch bypass of blank UI)

| Field | Value |
|---|---|
| Date | 2026-11-01T08:38:21-10:00 |
| Commit | `53ccc91fbe7d4530915b5131b558700be25b4520` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. native PLATFORM=11 app with auto-launch flag; StikDebug Enable JIT -> VRMC; wait for game boot; inspect latestlog

**Expected:** JVM/JIT/Vulkan/MC/provider start inside the native app

**Actual:** PASS: [JIT] isJITEnabled=1 always-attached; MoltenVK Vulkan 1.4.3; Loading Minecraft 26.2 with Fabric Loader 0.20.1 (21 mods); VisionVR init + bridge ABI 2; LEFT/RIGHT render passes; VkImage->MTLTexture eye export; tracking frames 601+. Blank native UIKit launcher content remains the only gate-3b caveat (auto-launch used).

**Artifacts:** evidence/EV-0077/latestlog.txt (1dccd43e97e3); evidence/EV-0077/summary.log (c240486fcaf4)

**Limitations:** M3a gates 1/2/3 all PASS => M3a complete. Next: M3-W1 native UI (SwiftUI shell/root VC) + M3-W2 CompositorServices consumption of provider eye textures + ARKit poses. Compat launcher restored after the test.

### EV-0078 — M3-W1 attempt PARTIAL: native root-VC workaround fires but crashes — UIKit launcher VCs require UISplitViewController

| Field | Value |
|---|---|
| Date | 2026-11-01T08:51:12-10:00 |
| Commit | `cad8c38a834f37dde63dc5fab8c401b2b9485a5d` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. native build with VRMCNativeBuild marker; root VC swapped to LauncherNavigationController; launch via StikDebug JIT

**Expected:** launcher content renders as a plain navigation UI

**Actual:** native branch executed (rootVC=LauncherNavigationController logged) then crashed: NSException in -[LauncherProfilesViewController viewWillAppear:] building @[sidebarViewController drawAccountButton, ...] because self.splitViewController is nil (sidebar macro). Blank split-view content (EV-0076) + this crash confirm the native launcher needs a native-specific UI shell; auto-launch (EV-0077) remains the only working boot path.

**Artifacts:** evidence/EV-0078/latestlog-native-ui.txt (f11425cd3931); evidence/EV-0078/native-ui.log (8d4f97dd5eca); evidence/EV-0078/AngelAuraAmethyst-2026-11-01-085003.ips (9bac8011c069); evidence/EV-0078/summary.log (1dbffd0ebf69)

**Limitations:** export/ replaced with the native-UI blocker dossier per operator instruction; compat launcher restored. Next: native SwiftUI shell or split-view-compatible shim invoking the existing launch path.

### EV-0079 — M3-W1 PASS: native visionOS launcher UI renders and Play launches the game — UIKit idiom spoof fix

| Field | Value |
|---|---|
| Date | 2026-11-01T09:53:02-10:00 |
| Commit | `656905ddf4f6c0dd599ac50b9685a10f13af6f75` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. fresh Amethyst 1.2.0 tree with vrmc-m1 + vrmc-m3w1 patches; build_launcher.sh PLATFORM=11; brand/sign dev.vrmc.vrmc (visionOS profile); install; StikDebug Enable JIT -> VRMC; press Play

**Expected:** launcher UI visible; Play starts fabric-loader-0.20.1-26.2 without autolaunch

**Actual:** PASS: operator-confirmed launcher UI and Play launch (no autolaunch flag). Log: VSIONOS native app, JIT isJITEnabled=1/always-attached, Launching Minecraft fabric-loader-0.20.1-26.2, MC 26.2 + Fabric 0.20.1, Vulkan/MoltenVK 1.4.3, VisionVR provider init/ABI 2, LEFT/RIGHT passes, VkImage->MTLTexture export, 901+ tracking frames, Vivecraft MenuWorlds built. Root cause: init_hookUIKitConstructor forced Phone/Pad idiom, hiding native visionOS window content; fix skips spoof when realUIIdiom == 6.

**Artifacts:** evidence/EV-0079/latestlog.txt (5e66507217f9); evidence/EV-0079/summary.log (7c6a7e0af783)

**Limitations:** M3-W1 PASS. Remaining M3: M3-W2/W3 (CompositorServices consumes provider eye MTLTextures + pose transfer), W4 ARKit pose -> provider, W5/W6 pacing/acceptance. export/ blocker dossier resolved; replace with resolution/build notes.

### EV-0080 — M3-W2 groundwork PASS (host): native shared eye-texture and ARKit-pose surface added to the bridge without ABI v2 changes

| Field | Value |
|---|---|
| Date | 2026-11-01T09:55:57-10:00 |
| Commit | `bce705853fa7c5dcf4dc176fa236a0622486b4f2` |
| Dirty state | ridge/src/vrmc_stub.c, bridge/abi/vrmc_native_shared.h |
| Device | host stub test only (no device test for this increment) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. add vrmc_native_shared.h + shared state in vrmc_stub.c; build host dylib; run stub test harness

**Expected:** stub test passes; shared eye handles and tracking override honored; Java ABI remains v2

**Actual:** PASS: stub test ok version=2 frames=1 ipd=0.064 shared_left=0xaaa; shared eyes fail before submit and match after; tracking override/clear honored; symbols exported. Java ABI unchanged v2.

**Artifacts:** evidence/EV-0080/vrmc_native_shared.h (9f4807f33ab6); evidence/EV-0080/summary.log (6428a74a9115)

**Limitations:** Groundwork only: no device test; native app must be rebuilt with this bridge when the SwiftUI app-lifecycle shell lands (ImmersiveSpace/CompositorLayer require SwiftUI scenes; UIKit cannot create a LayerRenderer). Next: M3-W2 native SwiftUI shell + compositor consumption.

### EV-0081 — M3-W2 PASS: SwiftUI app-lifecycle shell hosts launcher + opens CompositorServices immersive space (test pattern)

| Field | Value |
|---|---|
| Date | 2026-11-01T11:07:06-10:00 |
| Commit | `c348cecd243c3afd03e1ecf0300a9c58ba52fc93` |
| Dirty state | cripts/build_launcher.sh, patches/vrmc-m3w2-shell-hook.patch, runtime/native-shell/, scripts/build_shell.sh |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. native app embedded VRMCShell.framework; main.m dlopen/vrmc_shell_start; WindowGroup hosts LauncherSplitViewController; ImmersiveSpace + CompositorLayer renderer; StikDebug JIT

**Expected:** launcher UI hosted by SwiftUI; immersive space opens and presents CompositorServices content

**Actual:** PASS: shell log shows vrmc_shell_start invoked, launcher host appeared, openImmersiveSpace result=opened; operator saw launched launcher and immersive red/green test pattern.

**Artifacts:** evidence/EV-0081/vrmc-shell.log (9e0aefc8f00a); evidence/EV-0081/g1-summary.log (ef846d78607b)

**Limitations:** Next: sample provider eye textures and push ARKit tracking; see the auto-open device-loss issue.

### EV-0082 — M3-W3/W4 attempt PARTIAL: auto-open immersive during game start causes VK_ERROR_DEVICE_LOST; mitigations staged (delayed open, no GPU block, sampling kill switch)

| Field | Value |
|---|---|
| Date | 2026-11-01T11:07:12-10:00 |
| Commit | `c348cecd243c3afd03e1ecf0300a9c58ba52fc93` |
| Dirty state | cripts/build_launcher.sh, patches/vrmc-m3w2-shell-hook.patch, runtime/native-shell/, scripts/build_shell.sh |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. shell auto-opens immersive on VRMCGameStarted; compositor samples provider eye textures and pushes ARKit tracking

**Expected:** game renders, immersive shows MC eye textures with head tracking

**Actual:** auto-open succeeded and compositor ran 1080 frames (anchor OK) but eyes=0; MC crashed with VK_ERROR_DEVICE_LOST 'Failed to wait for semaphore' (GuiRenderer); app crashed at cp_frame_end_submission during layer invalidation. Mitigations staged: 15 s settle delay before open, no waitUntilCompleted, layer-state-guarded endSubmission, MTLDevice identity check, Documents/vrmc-no-sampling.flag fallback.

**Artifacts:** evidence/EV-0082/autoopen-shell.log (97a3e691ed7e); evidence/EV-0082/vrmc-compositor.log (b064ca8e7d56); evidence/EV-0082/latestlog.txt (c7ceba38f7c0); evidence/EV-0082/crash-2026-11-01_11.02.41-client.txt (044165c49af2); evidence/EV-0082/app.ips (796070c18e60); evidence/EV-0082/g2-summary.log (494f35bee207)

**Limitations:** Awaiting retest with mitigations; if crash persists, use sampling kill switch to separate presentation/window transition from texture sampling as the cause.

### EV-0083 — M3-W3/W4 first light PARTIAL: compositor samples provider eye textures (eyes=1) and provider receives ARKit tracking; game survives; alignment/window/background issues

| Field | Value |
|---|---|
| Date | 2026-11-01T11:18:04-10:00 |
| Commit | `487cc5923ecff4f5ed19d01227e53a98291853d2` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. mitigation build: delayed immersive auto-open after game start; compositor samples vrmc_shared_eye_textures and pushes vrmc_shared_set_tracking

**Expected:** immersive shows MC eye textures aligned and head-tracked; game alive

**Actual:** Game alive; auto-open after 15 s; compositor eyes=1 (provider textures 0x72219ca580/0x72219ca300), anchor=1, head tracking reaches provider (tracking frames with real head positions). Operator: immersive did not align; game window remained visible/confusing; immersive quit when app went background. Flat fullscreen sampling without per-eye projection/FOV alignment; window/scene handling missing.

**Artifacts:** evidence/EV-0083/vrmc-compositor.log (f6db1e941f24); evidence/EV-0083/vrmc-shell.log (e5c3e7db7445); evidence/EV-0083/latestlog.txt (26f41a2ccf30); evidence/EV-0083/summary.log (bc01484d7a2b)

**Limitations:** M3-W3 data path proven; next: window visibility + scenePhase + per-eye projection/aspect/FOV parity.

### EV-0084 — M3-W3/W4 PARTIAL: window parking works; compositor crashes on background at cp_frame_end_submission; alignment still pending

| Field | Value |
|---|---|
| Date | 2026-11-01T11:36:41-10:00 |
| Commit | `2863aa4a6281305d96b57f38538a23bf5233a670` |
| Dirty state | untime/native-shell/Sources/Shell.swift, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. window-parking + scenePhase build; game start -> delayed auto-open -> immersive; background/return

**Expected:** game window hidden, immersive survives background, MC eye textures aligned

**Actual:** Window hidden (windows=3 alpha=0), compositor eyes=1/anchor=1/tracking to frame 2760. On background the app crashed: SIGABRT __BUG_IN_CLIENT__ at cp_frame_end_submission (VRMCCompositorThread) when the layer invalidated. Operator: window disappeared, immersive crashed after background, still not aligned.

**Artifacts:** evidence/EV-0084/vrmc-shell.log (40ad5a6638fa); evidence/EV-0084/vrmc-compositor.log (97a5778d012c); evidence/EV-0084/app.ips (d873f3ba0fa1); evidence/EV-0084/summary.log (7e03d7caef8b)

**Limitations:** Next: compositor graceful stop on scene background; then per-eye projection/FOV alignment.

### EV-0085 — M3-W3/W4 final attempt PARTIAL: background compositor exit is clean, but SwiftUI observers die with game root replacement; exotropia and window chrome remain

| Field | Value |
|---|---|
| Date | 2026-11-01T11:59:38-10:00 |
| Commit | `5493626878038d9876bf6f2c1d8d9c61484283ff` |
| Dirty state | untime/native-shell/Sources/Bridging.h, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Headers/Bridging.h, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. early-stop/window-hidden/eye-swap build: game start -> auto immersive -> window parked -> background -> return

**Expected:** immersive survives background and reopens; window chrome hidden; aligned stereo

**Actual:** Auto-open and window parking work; background compositor exits cleanly (no new crash; latest crash remains 11:34). But no willResignActive/didEnterBackground/VRMCImmersiveEnded/scenePhase logs after game start because SwiftUI WindowGroup content was destroyed when the game replaced window.rootViewController; re-entry fails. Operator: window bottom bar still present; exotropia persists despite eye swap.

**Artifacts:** evidence/EV-0085/vrmc-shell.log (9f467a879ad2); evidence/EV-0085/vrmc-compositor.log (8aee8497ce84); evidence/EV-0085/latestlog.txt (7beb4ddfac48); evidence/EV-0085/summary.log (069ad1a75765)

**Limitations:** Next: keep SwiftUI root/observers alive (present SurfaceViewController instead of replacing root, or app-level observer); window chrome/scene handling; per-eye projection/FOV parity. export/ updated with this dossier.

### EV-0086 — M3-W3/W4 fixes device run PARTIAL: shell re-entry lifecycle works, but immersive is black and window chrome remains; exotropia unverified

| Field | Value |
|---|---|
| Date | 2026-11-01T13:11:28-10:00 |
| Commit | `335a65ff995f6d5f25471f3d45313da6b54aa925` |
| Dirty state | ridge/abi/vrmc_abi.h, bridge/src/vrmc_jni.c, provider/src/main/java/dev/vrmc/provider/VisionRenderer.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/src/main/java/dev/vrmc/provider/bridge/VrmcBridge.java, runtime/native-shell/Sources/Bridging.h, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Headers/Bridging.h, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftdoc, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. install user's three fixes together (app+bridge+provider jar); JIT -> Play -> auto-open -> background/foreground

**Expected:** window chrome gone, immersive survives background and reopens, eyes aligned

**Actual:** Shell lifecycle works (auto-open, window parked windows=2 visible=false, background stop/dismiss/restore, foreground reopen generation 2 opened). But operator sees completely black immersive and windows still visible; compositor logs per-eye tangents/provider FOV/ipd and eyes=1 frames, so sampling runs but reprojection outputs black; chrome not removed by persistentSystemOverlays. Exotropia fix unverified.

**Artifacts:** evidence/EV-0086/vrmc-shell.log (989c5ad2213d); evidence/EV-0086/vrmc-compositor.log (430a9bbecd55); evidence/EV-0086/latestlog.txt (fca1227ebf2a); evidence/EV-0086/summary.log (5412378b4305)

**Limitations:** Next: debug reprojection (center/corner ray->uv logging), verify viewToDevice/inverse projection conventions and frustum mapping; alternative chrome hiding; generation-2 invalidation. export/ updated with this evidence.

### EV-0087 — M3b fixes integrated (build/static validation): no-black compositor diagnostics, modal game surface + chrome fixing, hardened re-entry; device run pending

| Field | Value |
|---|---|
| Date | 2026-11-01T14:02:40-10:00 |
| Commit | `c9a7a0da3681e697f8458c455f7c97ffcba76b59` |
| Dirty state | gitignore, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftdoc, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell, scripts/README.md, patches/vrmc-m3w3-modal-game-surface.patch, runtime/probes/m3b-reproj/, runtime/probes/m3b-shader-test/, scripts/build_bridge.sh, scripts/build_provider.sh, scripts/push_provider_jar.sh, scripts/stage_native_app.sh |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) - app reinstalled, no device test run |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Integrate M3b fixes: VRMCCompositor diagnostics/no-black fallbacks/black-texture detection; Shell.swift epoch-guarded reopen + scene-activity gating + chrome mode; Amethyst modal game-surface patch (vrmc-m3w3) keeping the SwiftUI scene alive; build/stage scripts; provider/bridge built reproducibly.
| **M3 milestone** | **IN PROGRESS** | M3a COMPLETE; M3-W1/W2 PASS; **M3-W3/W4 visual acceptance PASS on D1 (EV-0094)**. Black-immersive root cause was the M3b drawable depth-clear change 1.0 -> 0.0 (EV-0093); with the default 1.0 the immersive shows the eye-distinct stereo/alignment pattern (fusion cross, per-eye tint, checker border; drawable readback L luma 110.4 / R luma 110.4, centre ~171) and a JIT game run renders the Vivecraft menu world in the immersive space with stereo aligned and head tracking, operator-confirmed. The black-immersive blocker is CLOSED. Remaining M3 work: M4 input, window chrome, background re-entry device check, provider GPU-sync device run, M3-W5/W6 90 Hz/soak. |
3. Build Amethyst native executable from vendor/amethyst-build + patches 1-4 via cmake (Debug, iphoneos sysroot) then vtool -set-build-version 11 1.0 1.0; stage into the EV-0086 app bundle with new framework + rebuilt bridge, re-sign 169 Mach-O, codesign --verify --deep --strict.
4. Install the staged app on D1 with devicectl (update install, data container preserved).
5. Code/convention validation: macOS Metal shader unit test (runtime/probes/m3b-shader-test) and visionOS simulator reprojection probe (runtime/probes/m3b-reproj) incl. reconstructed EV-0086 device views.

**Expected:** Compositor ray->UV math validated; no-black diagnostic paths in place; installable signed app ready for a decisive device run of the three EV-0086 issues.

**Actual:** Compositor math validated (87.88% of reconstructed EV-0086 device pixels inside the provider frustum, 0 behind-camera, 0 NaN; exact shader reproduces a pattern 25/25 probe pixels incl. presented drawable; black provider texture reproduces EV-0086 black exactly). New compositor adds CPU ray->UV + per-eye coverage logs, provider eye-texture 32x32 centre readback with luma/alpha (auto test-pattern if black twice), colour-coded debug branches, alpha=1, texture-map/viewport use, command-buffer health logs and Documents flag switches. Shell.swift adds epoch-guarded open/dismiss, foreground-scene gating, confirmed-dismiss and bounded auto-retry. Amethyst patch presents the game surface modally over the live SwiftUI host (default) so persistentSystemOverlays(.hidden) keeps hiding the window chrome; legacy root swap behind vrmc-legacy-root-swap.flag. Provider jar/bridge rebuilt; app staged+installed. No device run performed (operator needed).

**Artifacts:** evidence/EV-0087/shader-test.log (d37f556e5b67); evidence/EV-0087/m3b-reproj-report.md (dca79dcfe491); evidence/EV-0087/m3b-reproj-summary.txt (2cd534a6e372); evidence/EV-0087/m3b-reproj-run.log (ed30384780e9); evidence/EV-0087/framework-build.log (29ba40e594b3); evidence/EV-0087/stage-app.log (fd66ee6af674); evidence/EV-0087/build-artifacts.txt (2a0d22d839d2); evidence/EV-0087/device-apps.txt (fcb4dc140b7b); evidence/EV-0087/git-diff-stat.txt (fb4b1600bb42)

**Limitations:** NOT device evidence: black-screen root cause narrowed to provider eye-texture content or device presentation (compositor math refuted); window-chrome fix depends on the new modal presentation actually preserving the chrome preference on device; re-entry hardening unverified. Next run must use the new diagnostics (cpu diag / provider tex / cmd buffer / mode badge) and record EV-0088. Simulator is not evidence for stereo optics/tracking (VERIFY 0.7).

### EV-0088 — M3-W3/W4 host PASS: macstream-style display-view channel (per-eye tangents + eye transforms -> provider projection) and flat mapping; device run pending

| Field | Value |
|---|---|
| Date | 2026-11-01T15:08:52-10:00 |
| Commit | `1b3b73c8312549fa73ddb93057c843411d92e737` |
| Dirty state | ridge/abi/vrmc_native_shared.h, bridge/src/vrmc_jni.c, bridge/src/vrmc_stub.c, provider/src/main/java/dev/vrmc/provider/VisionRenderer.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/src/main/java/dev/vrmc/provider/bridge/VrmcBridge.java, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell, scripts/test_display_views.sh, scripts/tests/ |
| Device | host validation only (device run NOT RUN) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. port macstream Phase 8 root causes 3+4: publish CompositorServices display views to provider, provider renders display frustum/eye transforms, compositor flat mapping; offline frustum test

**Expected:** provider frustum from display tangents maps near-plane corners to NDC corners; display-view bridge roundtrip; provider compiles

**Actual:** PASS: DisplayViewsTest PASS (both lopsided device views and symmetric fallback: corners exact; straight-ahead NDC offset matches -(r+l)/(r-l), -(top+bottom)/(top-bottom)); bridge stub test PASS incl. display views generation; provider javac PASS; jar rebuilt; app+shell+bridge rebuilt/signed/installed and provider jar hash-verified. Device validation pending.

**Artifacts:** evidence/EV-0088/display-views-test.log (c4c86568d9cb); evidence/EV-0088/summary.log (6082d71f7565)

**Limitations:** Device run is the remaining verification (EV-0088). Next: run the three-issue procedure and check aligned stereo/no black.

### EV-0088 — M3-W3/W4 host PASS: macstream-style display-view channel (per-eye tangents + eye transforms -> provider projection) and flat mapping; device run pending

| Field | Value |
|---|---|
| Date | 2026-11-01T15:08:52-10:00 |
| Commit | `1b3b73c8312549fa73ddb93057c843411d92e737` |
| Dirty state | ridge/abi/vrmc_native_shared.h, bridge/src/vrmc_jni.c, bridge/src/vrmc_stub.c, provider/src/main/java/dev/vrmc/provider/VisionRenderer.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/src/main/java/dev/vrmc/provider/bridge/VrmcBridge.java, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell, scripts/test_display_views.sh, scripts/tests/ |
| Device | host validation only (device run NOT RUN) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. port macstream Phase 8 root causes 3+4: publish CompositorServices display views to provider, provider renders display frustum/eye transforms, compositor flat mapping; offline frustum test

**Expected:** provider frustum from display tangents maps near-plane corners to NDC corners; display-view bridge roundtrip; provider compiles

**Actual:** PASS: DisplayViewsTest PASS (both lopsided device views and symmetric fallback: corners exact; straight-ahead NDC offset matches -(r+l)/(r-l), -(top+bottom)/(top-bottom)); bridge stub test PASS incl. display views generation; provider javac PASS; jar rebuilt; app+shell+bridge rebuilt/signed/installed and provider jar hash-verified. Device validation pending.

**Artifacts:** evidence/EV-0088/display-views-test.log (c4c86568d9cb); evidence/EV-0088/summary.log (6082d71f7565)

**Limitations:** Device run is the remaining verification (EV-0088). Next: run the three-issue procedure and check aligned stereo/no black.

### EV-0089 — Recovered M3b device logs PARTIAL: provider eye textures valid (non-black) and chrome/windows parked; session backgrounded before visual alignment check

| Field | Value |
|---|---|
| Date | 2026-11-01T15:11:31-10:00 |
| Commit | `6a440de4efff1531b0074aca3e60b16e1f40e2b6` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. recover Documents/vrmc-shell.log + vrmc-compositor.log from the 14:41 M3b session

**Expected:** provider eye textures valid and presentation proceeds; visual alignment confirmed

**Actual:** Provider textures non-black (L mean RGB 83/108/51, R 78/100/48; nonBlack 1024/1024, alpha 255) and first command buffer completed; chrome/windows hidden in shell log. Session backgrounded immediately (stop/invalidation + VRMCImmersiveEnded), so no visual alignment report. Confirms EV-0086 black was compositor reprojection/presentation, not provider content.

**Artifacts:** evidence/EV-0089/vrmc-shell.log (110619294653); evidence/EV-0089/vrmc-compositor.log (f7bb65acad9e); evidence/EV-0089/summary.log (5c5f4a682e0d)

**Limitations:** Display-view alignment fix (EV-0088) is built/installed but device-locked; alignment device run pending.

### EV-0090 — M3-W3/W4 device run PARTIAL: display views live; found/fixed JNI grouped-vs-interleaved left-eye transform bug; pre-fix pure black (dark menu world + wrong left transform)

| Field | Value |
|---|---|
| Date | 2026-11-01T15:35:43-10:00 |
| Commit | `65594d8e72d64e7ac1474eb5eeaec560222313af` |
| Dirty state | ridge/src/vrmc_jni.c, scripts/tests/DisplayViewsLayoutTest.c |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. run game with display-view build; pull shell/compositor/latestlog; compare published vs applied eye transforms; add layout test; fix JNI

**Expected:** applied left/right eye transforms match published display views; aligned non-black image

**Actual:** Compositor published display views (L tangents -1.732/1.000/1.000/-1.192, Lpos(-0.0328,-0.0259,-0.0403), Rpos(0.0311,-0.0250,-0.0404), ipd 0.0639), sampled provider textures (dark menu-world content, luma 14-59), frames 6360, flat mode. Provider applied RIGHT correctly but LEFT Lpos=(-0.0024,-0.0155,0.9999): JNI grouped layout vs provider interleaved layout bug. Operator saw pure black. JNI fixed to interleaved per-eye; DisplayViewsLayoutTest PASS; app rebuilt/installed; relaunch pending.

**Artifacts:** evidence/EV-0090/latestlog.txt (ae1dcc0b8ddd); evidence/EV-0090/vrmc-compositor.log (e956e49b44fa); evidence/EV-0090/vrmc-shell.log (aede819e1ab8); evidence/EV-0090/display-views-layout.log (0ff05a7324be); evidence/EV-0090/summary.log (e9de6a9fcaf4)

**Limitations:** Pre-fix black explained by (a) dark menu world world58 and (b) corrupted left-eye transform. Relaunch after install to verify applied Lpos/Rpos and visual.

### EV-0091 — Fresh post-JNI-fix device runs recovered PARTIAL: provider eye-render + display-view channel correct and eye textures bright; test-pattern flag present; operator-reported black remains unexplained by content

| Field | Value |
|---|---|
| Date | 2026-11-01T16:50:00-10:00 |
| Commit | `f4d0617` (installed `VRMC-native-layoutfix.app`, built from the interleaved-JNI fix working tree; device run logs pulled after the fact) |
| Dirty state | clean (logs pulled from the device container) |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull Documents/{latestlog.txt, vrmc-compositor.log, vrmc-shell.log} from D1 after the two post-JNI-fix runs (15:36 and 16:39 HST)
2. correlate provider display-view application, compositor frame/present logs, provider eye-texture readbacks, and Documents flags

**Expected:** a correct provider/display-view path produces bright per-eye textures, and the operator visual report matches that content

**Actual:** 16:39 run: display views applied exactly (Lpos -0.0322,-0.0266,-0.0356; Rpos 0.0321,-0.0246,-0.0354, ipd 0.0644), compositor mode=flat, frames 0..1080, first command buffer completed, provider eye textures bright (frame 0 L mean RGB 115.6/110.4/89.1 luma 105.05, R 113.9/108.7/87.6 luma 103.38; later probes luma 103-154, nonBlack 919-1024/1024, alpha 255). 15:36 run: display views correct (Lpos -0.0316,-0.0268,-0.0357) and bright textures (luma 43-128). Documents/vrmc-test-pattern.flag existed on the device since 16:13, and the shipped compositor forces the procedural pattern when that flag is present (the build does not log the resolved flag, so this is code-path certainty, not log certainty). The operator reported a pure-black immersive for this session; the app backgrounded ~13 s after the immersive opened. No command buffer FAILED lines exist in any log.

**Artifacts:** evidence/EV-0091-fresh/latestlog-1639.txt (e64e25f3f57e); evidence/EV-0091-fresh/vrmc-compositor.log; evidence/EV-0091-fresh/vrmc-shell.log

**Limitations:** No authoritative operator statement exists for the 15:36 run; the test-pattern flag state was not logged by this build; these runs used the pre-M3c shell (immediate alpha+isHidden parking) and `vrmc-legacy-root-swap.flag`, so the modal-game-surface path had never been exercised.

### EV-0092 — M3c presentation diagnostics PARTIAL: the compositor provably writes a bright image into the presented built_in drawable, yet the device shows a black immersive; the same shell/compositor displays correctly in the simulator

| Field | Value |
|---|---|
| Date | 2026-11-01T17:45:00-10:00 |
| Commit | `4e3220a` (M3c diagnostics build; staged app hashes below) |
| Dirty state | clean at pull time (working tree committed as 4e3220a; staged framework/bridge/provider hashes recorded) |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 17.2 |
| Status | `PARTIAL` |

**Procedure:**

1. build/stage/install the M3c diagnostic app: shell framework (CompositorServices present path rewritten to cp_frame_query_drawables, drawn-drawable readback, test-pattern/clear-probe/present-proof modes, no-JIT selftest, alpha-only parking after the first presented frame and periodic re-park), bridge `38624e12…`, provider jar `8e707022…`
2. no-JIT selftest: push Documents/vrmc-immersive-selftest.flag, launch via `devicectl device process launch --terminate-existing`, pull Documents/{vrmc-compositor.log, vrmc-shell.log, vrmc-drawable-L/R.raw,.meta}
3. JIT game run (operator-assisted): StikDebug -> Enable JIT -> VRMC -> Play; pull the same logs + latestlog
4. simulator control: a minimal visionOS-simulator host app that dlopens the same VRMCShell.framework and calls `vrmc_shell_start` (no JVM/game); selftest immersive + simctl screenshot

**Expected:** a bright drawable that the operator can see in the headset; if the drawable is bright but the headset is black, the CompositorServices/presentation stage above Metal is at fault

**Actual:** no-JIT selftest on D1: immersive space opened (openImmersiveSpace result=opened), compositor posted its first presented frame and ran 960 frames of the forced test pattern (one drawable, target built_in, views=2, textures=2, encNil=0, nilColor=0); the drawn-drawable readback is bright (64x64 strided proof: mean luma 130.6, top-strip 188.3, max 255, nonBlack 4096/4096; raw dumps + meta in evidence) and the first command buffer completed. Operator reported a purple/black immersive (no pattern visible). JIT game run: provider initialized (menu world world37), display views applied exactly (Lpos -0.0322,-0.0266,-0.0356), compositor presented 12000+ frames in flat mode sampling the provider textures (drawable proof luma 64-75, nonBlack >4000/4096, encNil=0), and the operator reported full immersion active (pitch-black room) with the game visible only in a floating 2D window and no immersive content. Simulator control with the same framework: the selftest immersive displays the full-screen test pattern correctly (simctl screenshot), so the shell/compositor logic is not inherently broken.

**Artifacts:** evidence/EV-0092/selftest-compositor.log (3555c613653e); evidence/EV-0092/selftest-shell.log (4c75eedcf003); evidence/EV-0092/vrmc-drawable-L.raw (b3ea116fbf64); evidence/EV-0092/vrmc-drawable-L.raw.meta (01e6bc469bda); evidence/EV-0092/manual-game-compositor.log (896719767f28); evidence/EV-0092/manual-game-shell.log (d9fb7f1dcf55); evidence/EV-0092/manual-game-latestlog.txt (6ec5e331a1a9); evidence/EV-0092/sim-real-shell-pattern.png (e207c907201c)

**Limitations:** the operator's report is informal (single observer, no recording); the presentation failure is reproducible on D1 but the cause is not yet isolated (candidate diffs: two-view dedicated layout vs simulator one-view, Amethyst hybrid window/scene environment vs pure-SwiftUI simulator host, device anchor/reprojection path). Manual "Enter VR" button and objective scene-activation/layer-state logging are implemented but the device re-test had not run when this entry was written. No PASS is claimed.

### EV-0093 — M3c ROOT CAUSE PASS (device A/B): the M3b drawable depth-clear change (1.0 -> 0.0) blacks out the CompositorServices immersive on visionOS 27.2; probe-parity 1.0 displays

| Field | Value |
|---|---|
| Date | 2026-11-01T18:10:00-10:00 |
| Commit | `4e3220a` (diagnostics builds; depth fix committed with this evidence) |
| Dirty state | working tree carried the depth-clear fix; staged app/framework/bridge/provider hashes recorded |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` (root cause + fix, device A/B operator-confirmed) |

**Procedure:**

1. control: install the known-good M3A probe app (re-signed as `dev.vrmc.vrmc`, EV-0074 code) on D1, operator taps "Open immersive space"
2. bisect A: install staged VRMC builds that differ only in one variable (minimal SwiftUI window; deprecated single-drawable API; clear-only colours) with drawable depth clear 0.0; operator observes; pull shell/compositor logs
3. bisect B: same build with probe-parity depth clear 1.0 (`vrmc-depth-near.flag`), operator observes
4. trace the depth-clear value across the compositor history (487cc59 .. f4d0617) and the M3A probe source

**Expected:** the variant(s) that differ in the causal variable separate black from visible content

**Actual:** PASS (root cause isolated, operator-confirmed):
- `486cc59/2863aa4/5493626/335a65f` compositor revisions clear the drawable depth to **1.0**; M3b commit `1b3b73c` changed it to **0.0** ("flat image at infinity"), and every device run from EV-0087 onward was black. The known-good M3A probe clears to 1.0.
- D1 A/B: depth 0.0 -> **black** (minimal-window build, deprecated-API build, pure-SwiftUI host build: operator "window and black"/"black immersive", while logs show `layerState=2`, frames presented, encNil=0 and a bright drawn-drawable readback); depth 1.0 -> **solid magenta/cyan immersive visible immediately** ("magenta/cyan visible now!"), same shell/compositor/app, only the depth clear value differs.
- Fix: default `rp.depthAttachment.clearDepth = 1.0`; `vrmc-depth-zero.flag` retains 0.0 for A/B. Regression guard `scripts/tests/DepthClearRegressionTest.sh` PASS.
- Verification lesson: the same depth-0.0 framework displays correctly in the visionOS simulator, so simulator output is not evidence for this presentation path (VERIFY §0.7); only D1 reproduces it.

**Artifacts:** evidence/EV-0093/probe-control-m3a-probe.log (8dc8ae00d41a); evidence/EV-0093/deprecated-api-depth0-compositor.log (2161a88ea084); evidence/EV-0093/minwin-depth0-compositor.log (5245b708fc19); evidence/EV-0093/minwin-depth0-shell.log (22836a827b20); evidence/EV-0093/pure-swiftui-host-depth0-shell.log (81878e2ebfd1); evidence/EV-0093/host-selftest-depth0-shell.log (3ca35f2b7b8c)

**Limitations:** the operator report is informal (single observer, no recording); the final default build (array-API path + depth 1.0, no diagnostic flags) is staged and installed but its visual confirmation and the first game-in-immersive run (JIT) are the remaining M3-W3/W4 acceptance steps (recorded as EV-0094 when run). Stereo alignment, window chrome, re-entry and provider GPU sync are still open.

---

### EV-0094 — M3c on-device visual acceptance PASS: manual/auto immersive shows the stereo/alignment pattern and a JIT game run renders the Vivecraft menu world in the immersive space (stereo aligned, head tracking active)

| Field | Value |
|---|---|
| Date | 2026-11-01T19:04:30-10:00 |
| Commit | audit-fix build: shell '83cb12b9b8e3', bridge '109328f8f560', provider jar '2b889090186a' (staged app VRMC-native-v14-auditfix.app) |
| Dirty state | clean (code+docs for the audit fixes committed together with this entry) |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | PASS (M3-W3/W4 visual acceptance; the black-immersive blocker is closed) |

**Procedure:**

1. build/stage/install VRMC-native-v14-auditfix.app; push the provider jar (round-trip sha256 verified: provider jar '2b889090186a'), set the game-dir capture flag content to 'off', push clear-diagnostics + drawable-dump flags
2. operator unlock/wear D1, launch VRMC, pinch the manual **Enter VR** overlay button
3. operator JIT flow: StikDebug -> assign script -> Enable JIT -> launch VRMC fresh -> press Play; the shell auto-opens the immersive space ~15 s after VRMCGameStarted
4. pull Documents/{vrmc-shell.log, vrmc-compositor.log, latestlog.txt, vrmc-drawable-*.raw,.meta} and inspect session-scoped triage

**Expected:** the immersive shows the eye-distinct stereo/alignment pattern (warm/red left, green right, single fused white centre cross, red/green corner eye markers, cyan/white checker border) and the JIT game renders the Vivecraft menu world in the immersive space with head tracking; no black, no floating window

**Actual:** PASS, operator-confirmed.
- Manual/immersive pattern (operator): "Yes - pattern + fusion cross + border visible, window faded". The logged session (05:00:16 UTC) shows depthZero=0, one built_in drawable with 2 views/2 textures, first presented frame, layerState=2, CPSceneSessionRoleImmersiveSpaceApplication:fgActive, and a bright per-eye drawable readback proving correct eye-distinct content: L mean RGB (183.5,77.9,69.8) luma 110.4, R mean RGB (55.3,163.2,112.7) luma 110.4, centre luma ~171, nonBlack 4096/4096; meta meanLuma=110.41.
- JIT game run (operator): "the game launched successfully! the eyesight is aligned and it shows the game properly in immersive!" Logged run: VRMCGameStarted 05:04:02 UTC; auto openImmersiveSpace result=opened 05:04:17; first presented frame -> VRMCCompositorRunning; windows parked alpha=0.00 (both app windows) with periodic re-park; compositor diagnostics depthZero=0, mode=flat; provider eye textures live and changing (mean luma 46 -> 35 -> 109 -> 156 as MenuWorlds world59 rendered; display views applied exactly, e.g. Lpos=(-0.0328,-0.0265,-0.0347) Rpos=(0.0316,-0.0246,-0.0347), ipd 0.0645); drawable proof luma 35 -> 118 -> 129, nonBlack ~4000/4096, first command buffer completed, no command-buffer FAILED lines; tracking frames present. Operator ended the session at 05:04:34 (headset off / crown) after confirming the view.
- This closes the black-immersive blocker: with the EV-0093 depth-clear fix active (depthZero=0) the same shell/compositor now displays both the procedural pattern and the live game image on D1, and the operator reports correct stereo alignment and head tracking.

**Artifacts:** evidence/EV-0094/step1-compositor.log (5266bbf170f1); evidence/EV-0094/step1-shell.log (2b7d561ce8af); evidence/EV-0094/step1-drawable-L.raw (e56de470180f); evidence/EV-0094/step1-drawable-R.raw (4eadbe925be1); evidence/EV-0094/step1-drawable-L.meta (98ec5e82b916); evidence/EV-0094/game-live-compositor.log (07af3471a8d1); evidence/EV-0094/game-live-shell.log (f7694840ff19); evidence/EV-0094/game-live-latestlog.txt (8e8ed4dbfea5); evidence/EV-0094/game-drawable-L.meta (4e10f56b5669); evidence/EV-0094/game-latestlog-final.txt (8e8ed4dbfea5)

**Limitations:** operator reports are informal (no recording) and the game session was ended by the operator ~17 s after the immersive opened, so this is functional first-light acceptance, not a stability/soak test (M3-W5/W6 remain). The 05:00 pattern session was opened by a stale selftest flag captured before clear-diagnostics (the H2 fix deliberately captured it); it proves the compositor/pattern path on device, while the manual button gesture itself uses the same openImmersiveSpace path exercised by the game run. Stereo alignment is operator-confirmed but not quantitatively measured; 90 Hz pacing, window chrome, background/foreground re-entry, M4 input and provider GPU-sync device paths remain open. Provider eye-target PNG capture was disabled for this run by flag content ('off').

### EV-0095 — M4-W1 immersive input (host + simulator): ABI v3 hand-input channel, gesture/action engine, cross-language contract fixture, simulator input scenario, one-command selfchecks

| Field | Value |
|---|---|
| Date | 2026-11-01T20:27:07-10:00 |
| Commit | M4-W1 frozen tree on `5d6622c`; staged app tree sha256 `102c0e55…21b1c` (git-ignored `artifacts/staged/VRMC-native-m4-input.app`); staged provider jar sha256 `94cfe0d9…84bd`. This entry and the M4-W1 change are committed together. |
| Dirty state | M4-W1 working tree (bridge ABI v3 + compositor input + provider gesture engine + M4 tests/docs/selfchecks); full path list + per-file sha256 in `evidence/EV-0095/manifest.json` and the frozen fingerprint `evidence/EV-0095/frozen-sha256.txt`. Tracked preview framework `runtime/native-shell/build/` restored to HEAD and NOT committed (F13 decision). |
| Device | host + visionOS 27.0 simulator D3 only — **no physical device run** |
| Host | M1 MacBook Pro Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` (host + simulator plumbing) — device synthetic and real hands **NOT RUN** |

**Procedure:**

1. `scripts/m4_input_selfcheck.sh` (full) on the frozen tree, `OUT_DIR=/tmp/vrmc-m4-input-final`: bridge host suite (incl. TSan input test), C->Java fixture generation, provider build, provider JVM tests with `VRMC_INPUT_FIXTURE`/`VRMC_INPUT_FIXTURE_FRAMES`, simulator input scenario.
2. `scripts/m3c_selfcheck.sh` (full): M3c presentation regressions, provider+bridge builds, bridge host suite, six provider-sampling simulator scenarios, and step 7/7 `scripts/m4_input_selfcheck.sh`.
3. Independent verifier re-run of every check plus static audit, frozen-tree fingerprints, staging verification: [docs/analysis/m4-input-verification.md](docs/analysis/m4-input-verification.md).

**Expected:** the ABI v3 input contract is identical across C and Java; the C->Java fixture timeline replays exactly; provider gesture/pose/action-set/dispatch logic is test-enforced with the no-stuck-input invariants; the real compositor publishes synthetic 27-joint snapshots through the bridge and a zeroed release snapshot on stop in the simulator; both one-command selfchecks PASS without presentation regression. Device and hands evidence are explicitly out of scope.

**Actual:** **PASS** (all commands exit 0, independently reproduced by the verifier).
- Bridge suite: 38 PASS lines, `ALL PASS`; new `input-test` + `input-test-tsan` (500k publishes × 4 readers, 0 torn, 0 races); `build_bridge MODE=both` (device platform 11 + host) exports `_vrmc_poll_input`, `_vrmc_shared_publish_input`, `_vrmc_shared_acquire_input`, `_vrmc_shared_input_sequence`, `_Java_…_nativePollInput`.
- Cross-language contract fixture: primary snapshot 752 B sha256 `50926fdc3ffc…562d77`; `.frames` timeline 7520 B (10 records × 752 B, 150 ms spacing) sha256 `43d52113c5e9…6fa45`; provider `VisionInputFixtureTest` 61 checks 0 failed (right pinch press/held/release rec1–3; left fist press rec4, hold rec4–f7 = 450 ms → exactly one fist-tap pulse at f7, no repeat f8, released f9).
- Provider: build PASS (jar 51,298 B); `m4-layout` 68 / `m4-gestures` 157 / `m4-pose` 61 / `m4-fixture` 61 checks, 0 failed; pre-existing GPU-sync/flag/fallback/VkReflect steps still PASS.
- Simulator input scenario (real `VRMCCompositor.mm` + fake bridge/provider, visionOS 27.0): capture 361 data rows, final row `valid_mask=0` release; right pinch 0.0050→0.0744 m crossing 0.030/0.045, left fist ratio 0.767→1.890 crossing 1.25/1.55; `INPUT-SIM … SYNTHETIC` + `input publish`/`input release` lines; zero compositor input errors; immersive scene fgActive.
- `scripts/m3c_selfcheck.sh` full: all steps PASS (DepthClearRegression, DisplayViews, device shell build, provider+bridge builds, bridge host suite, six presentation simulator scenarios, M4 selfcheck step); no presentation regression.
- Device staging: signed `artifacts/staged/VRMC-native-m4-input.app` (`codesign --verify --deep --strict` PASS; M4 framework markers present; ABI v3 bridge symbols exported) + `artifacts/staged/vrmc-provider.jar` (`94cfe0d9…`); nothing installed on the headset.

**Artifacts:** `evidence/EV-0095/` — `manifest.json` + 21 hashed artifacts including `vrmc-frozen-m4-selfcheck.log`, `vrmc-frozen-m3c-selfcheck.log`, `bridge-tests.log`, `fixture-run.log`, `provider-build.log`, `provider-tests.log`, `provider-sim-input.log`, `input-capture.txt`, simulator `compositor.log`/`shell.log`, both fixture files, the verifier report copy, independent verifier logs (`bridge-frozen.log`, `provider-frozen.log`, `frozen-abi-layout.log`, `frozen-hdrcheck.log`, `sim-input.log`, `sim-flat.log`, `frozen-sha256.txt`) and `staged-artifacts.txt`.

**Limitations:** Host + simulator plumbing evidence only. **NOT proven / not claimed:** real ARKit hand tracking on the Vision Pro; device input end-to-end (compositor→bridge→provider→Vivecraft actions); the device synthetic Step 1; hand-authorization prompt behavior; mixin application inside a live Minecraft/Fabric process (compile/target-level only on the host); hands acceptance (AC-4 / ST-S5-hands remain `NOT RUN`); stereo optics, thermals, latency, comfort. Simulator evidence is plumbing only (VERIFY §0 rule 7). Metal host probe SKIP (no MoltenVK macOS SDK on this host; pre-existing). Provider jar sha varies per build by design (jar timestamps). The operator device procedure is `docs/mvp/M4_DEVICE_RUN.md` (Step 1 synthetic = SYNTHETIC only; Step 2 real hands = the S5-hands check).

### EV-0096 — M4-W1 on-device immersive input acceptance: synthetic plumbing + real-hand operator confirmation (shutdown crash noted)

| Field | Value |
|---|---|
| Date | 2026-11-01T21:47:53-10:00 |
| Commit | `b352d84` (M4-W1) + signed staged app tree sha256 `102c0e55…21b1c` and provider jar sha256 `94cfe0d9…84bd` (git-ignored `artifacts/staged/`); installed over the EV-0094 build with the data container preserved |
| Dirty state | clean (this entry is committed with the device-run docs update) |
| Device | **D1 Apple Vision Pro RealityDevice14,1, visionOS 27.2 (physical)** |
| Host | M16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` (M4-W1 input slice, operator-confirmed) — full AC-4/ST-S5-hands remains `NOT RUN`; shutdown crash is a recorded follow-up defect |

**Procedure:**

1. Install `artifacts/staged/VRMC-native-m4-input.app` on D1 over the EV-0094 build (data container preserved), push the M4 provider jar (sha256 round-trip `94cfe0d9…`), push `vrmc-clear-diagnostics.flag`.
2. **Step 1 — synthetic:** push `vrmc-input-sim.flag=cycle`, launch VRMC through StikDebug/JIT, press Play, wait for auto-immersive, run two gesture cycles, quit; pull `vrmc-shell.log`, `vrmc-compositor.log`, `latestlog.txt`.
3. **Step 2 — real hands:** push the clear-diagnostics trigger (deletes the synthetic flag at app startup), relaunch through StikDebug/JIT, **allow the hand-tracking permission prompt**, use real hands in the immersive scene (right pinch = select/attack, right fist tap = right-click/use, left pinch = teleport/shift, left fist = menu, both fists = inventory), quit; pull the same logs.

**Expected:** the immersive scene is controllable from inside the headset — the synthetic gesture cycle drives Vivecraft actions through the ABI v3 channel, and real ARKit hands are authorized, tracked continuously and drive the same bindings; no stuck input; presentation unchanged.

**Actual:** **PASS** for the M4-W1 input slice; operator: **“It ran very well!”**
- **Step 1 (SYNTHETIC plumbing):** compositor `INPUT-SIM SYNTHETIC ... input publish ... valid_mask=3 source=synthetic` every frame, cycle phase/lap logs, **6144 presented frames**, windows parked, background→foreground re-entry OK; provider ABI 3 handshake, `input channel ready`, 12/12 binding rows over 10 actions, **120 action-dispatch lines** (`vivecraft.key.guiLeftClick` 19 pairs, `ingameMenuButton` 20, `key.inventory` 18, `key.attack` 3 after a screen closed so the INGAME set became active); the both-fist chord produced **only** `key.inventory` (no simultaneous click/Escape). Session end: compositor `input release valid_mask=0` + provider `hand lost` → `[WARN] input stale ... all actions released` (stuck-input safety path exercised on device).
- **Step 2 (REAL hands):** `hand tracking authorization: request result status=allowed`; `ARKit session started ... hand tracking supported=1 provider=started authorization=allowed inputMode=arkit`; every frame published with `source=arkit` and real `valid_mask` transitions as hands entered/left the camera view (`L1R0` → `L1R1` ↗), real wrist/aim `[VRMC-M4] pose:` diagnostics, real pinch/fist edges and **120 action-dispatch lines** across the W1 bindings; no stuck input, no input errors; operator confirmed the game was controllable from the immersive scene with real hands.
- **Known defect (recorded follow-up, reproduced 2/2 runs, shutdown only):** after `[Minecraft] Stopping!` the JVM writes a SIGSEGV report in a native Foundation thread (`objc_retain`); the faulting register equals a provider eye `MTLTexture` handle exported earlier in the same run (`0x7225e35900`). The host app keeps running (shell/compositor logs continue and it backgrounds normally), so this is a game-teardown crash (likely the M3 eye-texture lifetime/teardown race), **not an input-path failure** — all input verification completed before it. Triage/fix is a follow-up.

**Artifacts:** `evidence/EV-0096/` — 10 hashed artifacts: Step-1 compositor/shell/game logs + M4 extracts, Step-2 compositor/shell/game logs, and `operator-session.md` (full session notes, build identities, crash description/evidence-class statement).

**Limitations:** Operator reports are informal (no recording). This is device evidence for the **M4-W1 input slice only**, not full AC-4/ST-S5-hands acceptance: locomotion beyond look/pinch teleport, jump, sneak, hotbar, bow/climbing and the complete P0 action checklist were not exercised; it is also not stereo-optics, thermal, or latency evidence. The reproducible shutdown-only JVM crash is a real defect and must be fixed before claiming device stability. Targeted follow-ups are recorded in `docs/mvp/M4_PLAN.md` (W2) and the device run report.

### EV-0097 — M4-W2 first slice PARTIAL: One-Euro hand smoothing + shutdown eye-texture teardown hardening (host+simulator PASS)

| Field | Value |
|---|---|
| Date | 2026-11-01T22:03:30-10:00 |
| Commit | `883470e7d65823ac677b93003a103f978b4f6a15` |
| Dirty state | ridge/abi/vrmc_native_shared.h, bridge/src/vrmc_jni.c, bridge/src/vrmc_stub.c, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/src/main/java/dev/vrmc/provider/bridge/VrmcBridge.java, provider/tests/run_tests.sh, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftdoc, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell, provider/src/main/java/dev/vrmc/provider/VisionPoseSmoother.java, provider/tests/dev/vrmc/provider/VisionPoseSmootherTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. implement One-Euro smoother + integrate VisionVR; add provider teardown clearEyeTextures + compositor CFRetain/CFRelease; run provider tests and M4 selfcheck

**Expected:** smoothing test + all provider tests + m4 selfcheck PASS; no regression; device run pending

**Actual:** VisionPoseSmootherTest 11 checks PASS; provider/tests/run_tests.sh ALL PASS (m4-smoother PASS 11 checks, layout/gestures/pose/fixture PASS); scripts/m4_input_selfcheck.sh RESULT PASS (provider-sim input scenario PASS). Bridge stub clear test PASS. New app/provider jar built/signed/installed; device smoothing/shutdown run pending.

**Artifacts:** evidence/EV-0097/provider-tests.log (9caf84e62165); evidence/EV-0097/m4-selfcheck.log (550597c1a76b); evidence/EV-0097/summary.log (b5a22a8b33ce)

**Limitations:** Shutdown defect still needs a device quit-game run; smoothing needs operator feel check and fist-threshold tuning from logs.

### EV-0098 — M4-W2 gaze tracking areas: event mailbox, spatial-event hook, mask grid, provider tile->GUI click mapping (host build/tests PASS; runtime/device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T22:41:47-10:00 |
| Commit | `3c5d57c5a5124be6ddbc0d057ca3ea90fa9e48f9` |
| Dirty state | ridge/abi/vrmc_native_shared.h, bridge/src/vrmc_jni.c, bridge/src/vrmc_stub.c, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/src/main/java/dev/vrmc/provider/bridge/VrmcBridge.java, provider/tests/run_tests.sh, runtime/native-shell/Sources/Bridging.h, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Headers/Bridging.h, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell, runtime/probes/m3c-provider-sim/run.sh, provider/src/main/java/dev/vrmc/provider/VisionGazeMath.java, provider/tests/dev/vrmc/provider/VisionGazeMathTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. implement bridge gaze mailbox + JNI; compositor tracking-areas config/mask/hover + Swift onSpatialEvent publish; provider gaze poll/mapping/click; add geometry tests; run provider tests and shell build; attempt simulator gaze scenario

**Expected:** geometry tests PASS; provider suite PASS; shell build PASS; simulator tracking-area pipeline builds; device runtime NOT RUN

**Actual:** VisionGazeMathTest PASS 11 checks; provider suite ALL PASS; shell framework build PASS; provider jar builds; simulator gaze scenario could not run (black/sleeping simulator screen, app backgrounded before compositor log), so tracking-area MSL pipeline creation remains runtime-unverified; device NOT RUN.

**Artifacts:** evidence/EV-0098/provider-tests-gaze.log (1b64242b8ee6); evidence/EV-0098/provider-gaze-build2.log (531457ec74da); evidence/EV-0098/shell-build.log (37271352176f); evidence/EV-0098/gaze-sim-build.log (7774b3d91887); evidence/EV-0098/simulator-shell.log (f4a93465a34a); evidence/EV-0098/simulator-screenshot.png (f7d63fe0aac1); evidence/EV-0098/summary.log (eab7f8fd49d8)

**Limitations:** Gaze remains opt-in via Documents/vrmc-gaze.flag; fail-safe disables tracking areas on unsupported formats/pipeline failure. Device operator run needs: vrmc-gaze.flag, GUI open, true-gaze hover + pinch, provider log '[VRMC-M4] gaze tile=... uv=... mouse=...' and no duplicate W1 guiLeftClick.

### EV-0099 — M4-W3 middle-pinch locomotion/core actions: virtual stick, jump, sneak, snap turn (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T22:51:14-10:00 |
| Commit | `71c6ec0881f01bd6b85a308df15dfc86f2c334b6` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionInputTest.java, provider/tests/run_tests.sh, provider/src/main/java/dev/vrmc/provider/VisionLocomotion.java, provider/tests/dev/vrmc/provider/VisionLocomotionTest.java, provider/tests/dev/vrmc/provider/VisionMiddleGestureTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. extend VisionInput with middle-pinch tap/double-tap family; add jump/sneak bindings; implement VisionLocomotion virtual stick; wire analog freeMoveStrafe + rotateLeft/Right pulses in VisionVR; run provider suite

**Expected:** host gesture/locomotion tests PASS; provider suite PASS; no W1 regressions; device NOT RUN

**Actual:** m4-middle 15 checks PASS; m4-locomotion 7 checks PASS; provider suite ALL PASS; provider jar builds; no device/hands run.

**Artifacts:** evidence/EV-0099/provider-tests.log (b70ba486b223); evidence/EV-0099/provider-build.log (f66a275f7771); evidence/EV-0099/summary.log (27e7477c73c0)

**Limitations:** Middle gesture default ON with middle.enabled=false opt-out; movement only when ingame, not seated/GUI, input healthy; device operator must tune thresholds/axes from real hands.

### EV-0100 — M4-W4 partial: opt-in swipe hotbar/scroll + radial menu gesture (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T22:52:58-10:00 |
| Commit | `5534c744dbbedfff2e69a45cf2ba2a2fe68cb86d` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionInputTest.java, provider/tests/dev/vrmc/provider/VisionMiddleGestureTest.java, provider/tests/run_tests.sh, provider/tests/dev/vrmc/provider/VisionSwipeGestureTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add opt-in open-hand swipe detector; wire provider hotbar/scroll actions; bind right middle double-tap to radial menu; extend host tests

**Expected:** host swipe/middle tests PASS; full provider suite PASS; default behavior unchanged (swipe OFF)

**Actual:** m4-swipe 6 checks PASS; m4-middle radial binding PASS; full provider suite ALL PASS; provider jar builds; device NOT RUN.

**Artifacts:** evidence/EV-0100/provider-tests.log (e2a5ede7334d); evidence/EV-0100/provider-build.log (05154fb8ef3a); evidence/EV-0100/summary.log (b81f082129c9)

**Limitations:** Swipe default OFF for safety; enable with swipe.enabled=true after device tuning. Hotbar/scroll/radial are the first W4 actions; chat/keyboard/swap/drop/bow/climb still open.

### EV-0101 — M5 first slice: runtime/comfort/performance settings + provider diagnostics + shell thermal monitor (host/build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T22:55:12-10:00 |
| Commit | `42585debd8ebf24c7189929a0ae4afe56fe12fb9` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/run_tests.sh, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell, docs/mvp/M5_PLAN.md, docs/mvp/M6_PLAN.md, provider/src/main/java/dev/vrmc/provider/VisionRuntimeSettings.java, provider/tests/dev/vrmc/provider/VisionRuntimeSettingsTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add VisionRuntimeSettings parser/apply; integrate provider periodic diagnostics; add shell thermal/low-power monitor; host tests + shell build

**Expected:** parser tests PASS; provider suite PASS; shell builds; no changes absent config file; device NOT RUN

**Actual:** m5-settings 18 checks PASS; full provider suite ALL PASS; shell framework builds; device/gameplay NOT RUN.

**Artifacts:** evidence/EV-0101/provider-tests.log (1d1dd342a695); evidence/EV-0101/provider-build.log (9a464d57b596); evidence/EV-0101/shell-build.log (5d2fd886ca1e); evidence/EV-0101/summary.log (a7a60b5e3ac1)

**Limitations:** All settings opt-in via vrmc-runtime.properties; absent file leaves Minecraft/Vivecraft settings untouched. Thermal telemetry stays on-device only (no telemetry egress).

### EV-0102 — M6 offline groundwork: shutdown journal, soak/release harnesses, privacy + acceptance matrix (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T22:56:38-10:00 |
| Commit | `6f516a6c2b9bee1da283c655410deac3b79f2bc4` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java, PRIVACY.md, docs/mvp/M6_ACCEPTANCE.md, scripts/m6_release_manifest.sh, scripts/m6_soak_harness.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add provider shutdown journal; add m6_soak_harness dry-run/device monitor; add release manifest script; add PRIVACY.md and M6_ACCEPTANCE.md; run provider suite/dry-runs

**Expected:** provider suite PASS; soak dry-run PASS; release manifest generates with pins/hashes; device gates NOT RUN

**Actual:** provider suite ALL PASS; soak dry-run PASS; release manifest generated (dirty tree warning by design); docs added; device NOT RUN.

**Artifacts:** evidence/EV-0102/provider-tests.log (1ded9581e4f5); evidence/EV-0102/soak-dry-run.log (59b88eac7eb4); evidence/EV-0102/release-manifest.txt (bfe6b391532a); evidence/EV-0102/manifest.log (0ede66b2ec60); evidence/EV-0102/summary.log (16f337ddca42)

**Limitations:** Soak device mode intentionally does not automate JIT; operator starts the game. Manifest must be regenerated from a clean release commit for M6 sign-off.

### EV-0103 — M5 recenter safety chord: both-hand middle double-tap (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T22:57:44-10:00 |
| Commit | `c7b0275ebd81edbb2ae3eb6f9464b2615a0ae533` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionMiddleGestureTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add both-middle double-tap chord; perform room-origin recenter via reflective snapRoomOriginToPlayerEntity; extend middle tests; run provider suite

**Expected:** recenter chord detected; per-hand double actions suppressed; provider suite PASS; device NOT RUN

**Actual:** middle suite 18 checks PASS incl. recenter chord/suppression; full provider suite ALL PASS; provider builds; device recenter NOT RUN.

**Artifacts:** evidence/EV-0103/provider-tests.log (4241b932f2a2); evidence/EV-0103/provider-build.log (f3dc7e67d532); evidence/EV-0103/summary.log (77a75434e60e)

**Limitations:** Recenter requires middle gestures enabled (default ON, middle.enabled=false opt-out). Height calibration/world-scale persistence still open.

### EV-0104 — M5 launcher settings panel: seated/snap/preset/render-distance/frame-limit writes vrmc-runtime.properties (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T22:58:55-10:00 |
| Commit | `fea9e164ebd77fd6fedf923b0a5e5752eda4700e` |
| Dirty state | untime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add VRMC settings DisclosureGroup to VRControlOverlay; load/save vrmc-runtime.properties; shell framework build

**Expected:** shell builds; settings file round-trip; provider parser consumes; device UI NOT RUN

**Actual:** shell framework build PASS with settings panel; save/load implemented via local properties file; provider parser already tested (EV-0101); device interaction NOT RUN.

**Artifacts:** evidence/EV-0104/shell-build.log (fb5b4826b509); evidence/EV-0104/summary.log (895f825dbb46)

**Limitations:** Panel writes only its owned keys, keeps other user keys; applies next launch. No launcher game-screen settings yet (only VR/pre-game overlay).

### EV-0105 — M5 world-scale/height settings + runtime command channel + launcher command buttons (host/build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:00:39-10:00 |
| Commit | `d2e524608b3935e47c065efffa871af7ac346dae` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionRuntimeSettings.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionRuntimeSettingsTest.java, provider/tests/run_tests.sh, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell, provider/src/main/java/dev/vrmc/provider/VisionCommandFile.java, provider/tests/dev/vrmc/provider/VisionCommandFileTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. extend VisionRuntimeSettings with worldScale/manualHeight; add VisionCommandFile + provider polling; wire recenter/calibrate/reload/diag/status; add shell command buttons; run tests + shell build

**Expected:** settings/command tests PASS; provider suite PASS; shell build PASS; device NOT RUN

**Actual:** m5-settings 22 checks PASS; m5-command 9 checks PASS; full provider suite ALL PASS; shell framework builds; device UI/behavior NOT RUN.

**Artifacts:** evidence/EV-0105/provider-tests.log (926320e965b0); evidence/EV-0105/provider-build.log (be63b7ed87df); evidence/EV-0105/shell-build.log (2057e774c491); evidence/EV-0105/summary.log (e9e69f570ec1)

**Limitations:** Command file is local-only and whitelisted; unknown commands rejected+recorded. Buttons queue commands; provider consumes while the game runs.

### EV-0106 — M4-W4 extension: opt-in swipe action table for hotbar/chat/keyboard/swap/drop (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:01:43-10:00 |
| Commit | `4f361f18e4a42bcd1939b93e2198aca16e449782` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionInputTest.java, provider/tests/dev/vrmc/provider/VisionSwipeGestureTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add swipe-direction sources and bindings for hotbar/chat/keyboard/swap/drop; remove duplicate direct hotbar handling; extend swipe tests; run provider suite

**Expected:** binding/swipe tests PASS; provider suite PASS; swipe remains opt-in; device NOT RUN

**Actual:** binding table 21 rows/19 actions; swipe test 9 checks PASS; full provider suite ALL PASS; provider builds; device NOT RUN.

**Artifacts:** evidence/EV-0106/provider-tests.log (11c9d31fd299); evidence/EV-0106/provider-build.log (98f8adc38f13); evidence/EV-0106/summary.log (99a0ad94a659)

**Limitations:** swipe.enabled defaults false; enable + tune swipe.speed/openRatio/cooldownMs after D1 gesture feel test. Keyboard/chat requires the in-game keyboard overlay to be usable on device.

### EV-0107 — M5 diagnostics export: provider status JSON + local diagnostics bundle/ShareLink (host/build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:02:36-10:00 |
| Commit | `5c822758d19f3b6fac172588f944fad91e457cd3` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. write vrmc-status.json from provider; add shell diagnostics bundle builder and ShareLink export button; run provider suite and shell build

**Expected:** provider suite PASS; shell builds; no automatic network; device UI NOT RUN

**Actual:** full provider suite ALL PASS; shell framework builds with Export diagnostics/ShareLink; device share UI NOT RUN.

**Artifacts:** evidence/EV-0107/provider-tests.log (56b56f15c6d1); evidence/EV-0107/provider-build.log (e1ccdea80d40); evidence/EV-0107/shell-build.log (313319b40c4d); evidence/EV-0107/summary.log (05c45e72d18f)

**Limitations:** Export is user-initiated and local; logs capped/truncated inside the bundle. ShareLink behavior on visionOS still needs device verification.

### EV-0108 — M6: crash guard/safe mode + release readiness check (host/build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:03:38-10:00 |
| Commit | `622852021e4bf3899733d7877db8a0941bc868b2` |
| Dirty state | untime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftdoc, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell, scripts/m6_release_check.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add shell crash-guard startup evaluation + safe-mode suppression + clear control; add m6_release_check.sh; build shell; run release check

**Expected:** shell builds; crash shadow logic compiles; release check PASS on host; device NOT RUN

**Actual:** shell framework builds; m6_release_check.sh PASS (host readiness; dirty-tree note); device crash-guard/release acceptance NOT RUN.

**Artifacts:** evidence/EV-0108/shell-build.log (6ee8f1a78979); evidence/EV-0108/release-check.log (36b59c70780b); evidence/EV-0108/summary.log (dd6cadeec4d9)

**Limitations:** Crash guard relies on provider vrmc-shutdown.log destroy-complete; safe mode suppresses only automatic open, manual Enter VR remains available. Release check does not replace AC/K device evidence or VERIFY sign-off.

### EV-0109 — M4-W4: right-fist hold -> continuous key.use (bow draw/release) host PASS; device NOT RUN

| Field | Value |
|---|---|
| Date | 2026-11-01T23:04:45-10:00 |
| Commit | `83b1c1e77e3d5b723a422be8bf17c5f20e85c070` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/tests/dev/vrmc/provider/VisionInputTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. change W4 key.use binding from fist tap to fist hold; add use-hold host test; run provider suite

**Expected:** fist hold presses/uses continuously, releases on open; GUI right click unchanged; provider suite PASS

**Actual:** use-hold test PASS; m4-input 161 checks; full provider suite ALL PASS; provider builds; device bow/climb NOT RUN.

**Artifacts:** evidence/EV-0109/provider-tests.log (4e1fe7e96f2b); evidence/EV-0109/provider-build.log (81705d18fb2d); evidence/EV-0109/summary.log (1830b3f810a5)

**Limitations:** Behavior change vs W1 (use is now continuous while fist held); device operator must confirm menu/use feel and bow firing.

### EV-0110 — M5 frame-pacing telemetry: poll P50/P95/max + missed-90Hz count (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:05:37-10:00 |
| Commit | `85fda58a9b810692c032a7eed8ca917cab8a40eb` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/run_tests.sh, provider/src/main/java/dev/vrmc/provider/VisionFrameStats.java, provider/tests/dev/vrmc/provider/VisionFrameStatsTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add VisionFrameStats ring; integrate into [VRMC-M5] diag; host test; run provider suite

**Expected:** frame stats tests PASS; provider suite PASS; device pacing NOT RUN

**Actual:** m5-frame-stats 10 checks PASS; full provider suite ALL PASS; provider builds; device pacing/thermal NOT RUN.

**Artifacts:** evidence/EV-0110/provider-tests.log (c47c4dda76a5); evidence/EV-0110/provider-build.log (3cde07b85f12); evidence/EV-0110/summary.log (e02747b8ed3d)

**Limitations:** Poll intervals are a Java-side proxy; K2/K5 still need device measurements. Threshold 1.5x90Hz documented in the class.

### EV-0111 — M4-W4: both-middle tap chord -> climbeyJump (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:06:15-10:00 |
| Commit | `6b53f031c12bc4f5c706c4ba86f30f7cbf2bda4d` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/tests/dev/vrmc/provider/VisionInputTest.java, provider/tests/dev/vrmc/provider/VisionMiddleGestureTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add both-middle tap chord with per-hand tap suppression; bind vivecraft.key.climbeyJump; extend middle tests; run provider suite

**Expected:** chord detected; climb action bound; per-hand jump suppressed; provider suite PASS

**Actual:** middle suite 21 checks PASS; binding table 22 rows/20 actions; full provider suite ALL PASS; provider builds; device climb NOT RUN.

**Artifacts:** evidence/EV-0111/provider-tests.log (4e04e695e1d2); evidence/EV-0111/provider-build.log (4331c21b8dff); evidence/EV-0111/summary.log (a38d40b45ae3)

**Limitations:** Climb grab = both-hand pinch hold (unchanged); climb jump = both-middle tap. Device climbing/climb-jump behavior must be verified on D1.

### EV-0112 — M5 launcher panel extension: world scale, auto/manual height, diagnostics period (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:06:47-10:00 |
| Commit | `082759b69dddeda83f1e20776665c49991d890fb` |
| Dirty state | untime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. extend VRControlOverlay settings with world-scale slider, auto/manual height, diagnostics period; load/save vrmc-runtime.properties; build shell

**Expected:** shell builds; settings preserved/validated; device UI NOT RUN

**Actual:** shell framework builds with extended panel; save/load keys implemented; provider parser already tested (EV-0105); device UI NOT RUN.

**Artifacts:** evidence/EV-0112/shell-build.log (6a55a18a39bc); evidence/EV-0112/summary.log (29d68a893f91)

**Limitations:** All values apply at next game launch; invalid ranges clamped in UI and rejected by provider parser. Device interaction/comfort feel NOT RUN.

### EV-0113 — Build/staging: latest M4/M5/M6 build signed, installed on D1, provider jar pushed (no behavior test; device locked)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:09:52-10:00 |
| Commit | `dd6091df5d7cbe928fb0d471b3e73700fa77b0ee` |
| Dirty state | export/latest-build-identity.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. build native app with current shell/bridge; sign/verify; install on D1; build/push provider jar; record hashes

**Expected:** app signs/verifies, install succeeds, provider jar pushed; behavior NOT RUN without unlock/JIT

**Actual:** 169 Mach-O signed; codesign verify deep/strict PASS; app tree sha 3a03076f…; install OK; provider sha fc8cc4b1… pushed; device locked, no game/behavior run.

**Artifacts:** evidence/EV-0113/native-build.log (e1f539f6d838); evidence/EV-0113/provider-build.log (44196f63c4fa); evidence/EV-0113/latest-build-identity.txt (661e9651dd1d); evidence/EV-0113/summary.log (0b02eee0619a)

**Limitations:** Build identity is not a release manifest; regenerate from a clean commit. Behavior verification needs unlock + StikDebug JIT + operator.

### EV-0114 — M5: command action-bar feedback + live launcher status; latest build reinstalled (host/build/install PASS; behavior NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:14:17-10:00 |
| Commit | `317d18feaad44b71c7c444619005a8f73f028c23` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add reflective action-bar feedback for commands/recenter; add live status line in launcher from vrmc-status.json/thermal; rebuild provider/shell/app; sign/install/push; run tests

**Expected:** provider suite PASS; shell/native builds PASS; install OK; behavior NOT RUN

**Actual:** provider suite ALL PASS; shell build PASS; native app signed/verified/installed; provider jar pushed; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0114/provider-tests.log (75ea2cbaee5d); evidence/EV-0114/provider-build.log (167e80b31fb9); evidence/EV-0114/shell-build.log (82385402ab62); evidence/EV-0114/native-build.log (0c3dfa21caa8); evidence/EV-0114/latest-build-identity.txt (67e44be2d175); evidence/EV-0114/summary.log (3cb2106fb8f7)

**Limitations:** Build identity is not a release manifest. Action-bar feedback needs a running player; launcher status requires a prior provider session/status file.

### EV-0115 — M4/M6 safety hardening: 20k-frame fuzz test finds/fixes both-hand chord tracking-loss leak (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:15:37-10:00 |
| Commit | `230473f1b5b725b932e28d86c305015ac2fc3619` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/tests/run_tests.sh, provider/tests/dev/vrmc/provider/VisionInputFuzzTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. add deterministic VisionInput fuzz test with safety invariants; run it; fix both-hand chord release on tracking loss; rerun provider suite; push provider jar

**Expected:** 0 violations under random tracking loss/malformed/stale frames; provider suite PASS

**Actual:** initial run found 2 violations (both-hand chord pulses surviving a lost hand); fixed by clearing both-hand chord state when either hand is untracked; 20k frames/0 violations; full provider suite ALL PASS; provider jar pushed.

**Artifacts:** evidence/EV-0115/provider-tests.log (1e5b9cbcff75); evidence/EV-0115/provider-build.log (a880d963b969); evidence/EV-0115/summary.log (f0f04e33384f)

**Limitations:** Fuzz seed fixed for reproducibility. This is host safety evidence for G4-style release invariants; real-hands/no-stuck behavior still needs D1. Provider jar updated on device; app build unchanged.

### EV-0116 — M6: bridge shared-channel concurrency + TSan test (display views/gaze/tracking/game-stopping) host PASS

| Field | Value |
|---|---|
| Date | 2026-11-01T23:16:27-10:00 |
| Commit | `aee90d3473fbec09aa3d7561dbc43b20b52ed91c` |
| Dirty state | ridge/tests/run_tests.sh, bridge/tests/bridge_shared_test.c |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. add bridge_shared_test (writer/reader stress of all additive native-shared channels); wire normal+TSan steps; run full bridge suite

**Expected:** normal+TSan PASS; no races/regressions; device behavior separate

**Actual:** full bridge suite ALL PASS incl. shared-test and shared-test-tsan; build-bridge PASS; no device run.

**Artifacts:** evidence/EV-0116/bridge-tests.log (078cc2caef74); evidence/EV-0116/summary.log (9f825360698d)

**Limitations:** Host concurrency evidence only; device behavior still NOT RUN. Bridge source unchanged by this test addition, no new device push required.

### EV-0117 — M5 launcher gesture toggles + reference; updated app installed (build/install PASS; behavior NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:18:01-10:00 |
| Commit | `d46c678e6c742c51d3c93e84d8df3a1462fb7620` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add middle/swipe toggles writing vrmc-input-tune.properties and gesture cheat sheet; rebuild shell; stage/install app; record identity

**Expected:** shell builds; app signs/installs; device UI NOT RUN

**Actual:** shell builds; staged app 169 Mach-O signed, deep/strict verify PASS; install OK; app tree abc48c93…; provider unchanged d6de9469…; device locked, behavior NOT RUN.

**Artifacts:** evidence/EV-0117/shell-build.log (db94b95af99d); evidence/EV-0117/latest-build-identity.txt (3c13608e66f7); evidence/EV-0117/provider-tests.log (1e5b9cbcff75); evidence/EV-0117/summary.log (3a770569c513)

**Limitations:** Toggles persist in vrmc-input-tune.properties and are read by VisionInput at next launch. Build identity is not a release manifest.

### EV-0118 — M4-W4 direct hotbar wheel via both ring pinches; latest build installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:20:54-10:00 |
| Commit | `37bf0ee1c68fa9e502e46e5ab3c8927e9bb769e9` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionInputFuzzTest.java, provider/tests/run_tests.sh, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell, provider/src/main/java/dev/vrmc/provider/VisionHotbarWheel.java, provider/tests/dev/vrmc/provider/VisionHotbarWheelTest.java, provider/tests/dev/vrmc/provider/VisionRingChordTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add ring-pinch chord + hotbar wheel mapping/provider commit; tune keys; tests; rebuild/stage/install app and push provider jar

**Expected:** ring/hotbar tests PASS; provider suite PASS; shell/app install PASS; device NOT RUN

**Actual:** hotbar-wheel 8 checks + ring-chord 8 checks PASS; fuzz 20k/0; full provider suite ALL PASS; app tree 0726af92… installed; provider cc24d16b… pushed; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0118/provider-tests.log (6e0a69c09b59); evidence/EV-0118/provider-build.log (99ca4aa06c6e); evidence/EV-0118/shell-build.log (cfa6ee6a1020); evidence/EV-0118/latest-build-identity.txt (b33460e54b19); evidence/EV-0118/summary.log (63a8e69cf297)

**Limitations:** Ring pinch is a deliberate two-hand chord; hotbar.range configurable. Device latency/feel/commit behavior needs D1. Build identity is not a release manifest.

### EV-0119 — M6 release workflow: clean-tree manifest + development sideload package (host PASS; device acceptance NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:21:52-10:00 |
| Commit | `086d11c08467b8c65b6491c429cd9efeec8dd2b4` |
| Dirty state | export/release-manifest-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add release packaging script; on clean tree run release check, manifest, package signed app+provider+legal/docs; hash package

**Expected:** clean manifest dirty_tree=no; package created/hashed; release check PASS; device AC/K NOT RUN

**Actual:** release check PASS; manifest generated clean; package sha256 d583608d… bytes 206308244; device acceptance NOT RUN.

**Artifacts:** evidence/EV-0119/package.log (e4d85ea76e7e); evidence/EV-0119/manifest.log (384a16862c1a); evidence/EV-0119/release-check.log (a5f38166951f); evidence/EV-0119/package.sha256 (e8d65066cd48); evidence/EV-0119/release-manifest-dev.txt (9bc456cd859c); evidence/EV-0119/summary.log (4e37736b76ac)

**Limitations:** Development sideload package only; not App Store/final release. Final artifact must be rebuilt from the release commit and accompanied by device AC/K evidence/sign-off.

### EV-0120 — M5/M4 live input reload command + launcher button; latest build installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:23:45-10:00 |
| Commit | `5ca770ad2a3e6b9b3850affc26037aba3261e380` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionCommandFile.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionCommandFileTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add reload-input command to bridge command channel; recreate VisionInput from tune file in provider; add launcher button; test/build/stage/install/push

**Expected:** command accepted; provider suite PASS; shell/app install PASS; device NOT RUN

**Actual:** provider suite ALL PASS; shell builds; app 4d55c1b0… installed; provider 46699ae2… pushed; device locked, behavior NOT RUN.

**Artifacts:** evidence/EV-0120/provider-tests.log (86c9ce4a603e); evidence/EV-0120/provider-build.log (8fb2abfe3a0d); evidence/EV-0120/shell-build.log (cfa6ee6a1020); evidence/EV-0120/latest-build-identity.txt (78eef6124e26); evidence/EV-0120/summary.log (374ed178e108)

**Limitations:** Reload-input recreates the gesture engine; in-flight gesture state is dropped (safe release). Device behavior/latency NOT RUN. Build identity is not a release manifest.

### EV-0121 — M4/M5 bow/use teleport suppression + crash-log export; latest build installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:25:48-10:00 |
| Commit | `1a35509743e93812be9356f12ca7c7ecbc1dccf5` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/tests/dev/vrmc/provider/VisionInputTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. suppress teleport binding while right fist held; add crash artifacts to diagnostics bundle; tests/builds; stage/install app and push provider

**Expected:** host safety test PASS; provider suite PASS; shell/app install PASS; device NOT RUN

**Actual:** m4-input 164 checks PASS; full provider suite ALL PASS; shell builds; app tree a4500d7b… installed; provider 7bc599e7… pushed; device locked, behavior NOT RUN.

**Artifacts:** evidence/EV-0121/provider-tests.log (c2eec07cd584); evidence/EV-0121/provider-build.log (8cb156b403ec); evidence/EV-0121/shell-build.log (cfa6ee6a1020); evidence/EV-0121/latest-build-identity.txt (ae28e4103f50); evidence/EV-0121/summary.log (51f678111bfe)

**Limitations:** Teleport suppression is host-tested at binding level; device bow/climb feel NOT RUN. Crash-log collection is local-only; device share UI NOT RUN.

### EV-0122 — M5 comfort vignette in compositor + launcher control; latest app installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:27:26-10:00 |
| Commit | `3656ec1980795142b98ddab5b13e4acb74a95189` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add flat-path vignette shader/pipeline; read vrmc-vignette.flag; add launcher toggle/strength writing the flag; build/stage/install

**Expected:** compositor/shell build PASS; app install PASS; device appearance NOT RUN

**Actual:** shell framework builds; app 2914e6df… signed/installed; provider unchanged on device; device locked so runtime shader/comfort NOT RUN.

**Artifacts:** evidence/EV-0122/shell-build.log (cfa6ee6a1020); evidence/EV-0122/latest-build-identity.txt (f91fb5b5aeaa); evidence/EV-0122/summary.log (d63db95688ae)

**Limitations:** Runtime MSL compiled by compositor at runtime; failure would be logged and flat path used. Vignette applies to flat game image only (not test pattern). Device comfort/appearance NOT RUN.

### EV-0123 — M5 launcher advanced input tuning UI; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:29:37-10:00 |
| Commit | `f395514765c5afdd2f5c4252001dec7e47ae589e` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add middle/ring thresholds, swipe speed, hotbar range sliders writing vrmc-input-tune.properties; build/stage/install

**Expected:** shell build/install PASS; values saved with off>on; device UI NOT RUN

**Actual:** shell framework builds; app 8ec4b31a… signed/installed; provider unchanged; device locked so UI/tuning feel NOT RUN.

**Artifacts:** evidence/EV-0123/shell-build.log (cfa6ee6a1020); evidence/EV-0123/latest-build-identity.txt (acdd80e23954); evidence/EV-0123/summary.log (dd02f72787a9)

**Limitations:** Tuning keys are read by VisionInput/VisionVR at startup or via live reload-input. Device gesture feel remains NOT RUN.

### EV-0124 — M4/M5 in-game controls help + hand-controls reference; latest build installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:31:23-10:00 |
| Commit | `2b1c7bbfebb0bc2aa187fddbaa82686b85918c7d` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionCommandFile.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionCommandFileTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell, docs/mvp/M4_CONTROLS.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add controls command sending chat summary via reflection; launcher button; M4_CONTROLS.md reference; tests/build/stage/install/push

**Expected:** provider suite PASS; shell/app install PASS; docs published; device behavior NOT RUN

**Actual:** full provider suite ALL PASS; shell builds; app 17433e3d… installed; provider 1af22936… pushed; docs/mvp/M4_CONTROLS.md added; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0124/provider-tests.log (ff6225eebf8f); evidence/EV-0124/provider-build.log (7dd36c11c888); evidence/EV-0124/shell-build.log (cfa6ee6a1020); evidence/EV-0124/latest-build-identity.txt (064e28d66b8a); evidence/EV-0124/M4_CONTROLS.md (6c344a45024b); evidence/EV-0124/summary.log (138097fcf171)

**Limitations:** Chat help requires a running player; device UX NOT RUN. Reference doc reflects current mappings; tune with launcher/reload-input.

### EV-0125 — M4: both-fist/use conflict fix + optional fingertip component mode (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:32:50-10:00 |
| Commit | `108cbc9d708f3a09c997e24ab7de31ca8a1509b1` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionHandPose.java, provider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionHandPoseTest.java, provider/tests/dev/vrmc/provider/VisionInputTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add both-fist suppression of continuous use; implement optional joint-derived tip component mode; host tests; build/push provider

**Expected:** conflict host test PASS; tip offset math PASS; provider suite PASS; device appearance NOT RUN

**Actual:** m4-input 168 checks, m4-pose 67 checks; full provider suite ALL PASS; provider jar pushed; device locked so visual/behavior NOT RUN.

**Artifacts:** evidence/EV-0125/provider-tests.log (93454c128800); evidence/EV-0125/provider-build.log (0e7d87125348); evidence/EV-0125/latest-build-identity.txt (d49273c8af81); evidence/EV-0125/M4_CONTROLS.md (6c344a45024b); evidence/EV-0125/summary.log (db1c0152c7eb)

**Limitations:** hands.componentMode=joints is experimental and opt-in; default identity. Device held-item/hand appearance NOT RUN.

### EV-0126 — M4-W2 safety: gaze tracking-area config/spatial handler now opt-in; latest app installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:42:17-10:00 |
| Commit | `81020cf7fd083ab07868239ca7997deb9436f342` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. condition tracking-area layer config and onSpatialEvent on vrmc-gaze.flag; build/stage/install; attempt simulator input (backgrounds before compositor)

**Expected:** when gaze off, layer config/presentation path unchanged; shell builds/installs; simulator limitation documented

**Actual:** shell builds; app 926f663d… installed; simulator input still backgrounds app before compositor (same with opt-in), so not used as evidence; device behavior NOT RUN.

**Artifacts:** evidence/EV-0126/shell-build.log (cfa6ee6a1020); evidence/EV-0126/simulator-input.log (e9206b230fb5); evidence/EV-0126/latest-build-identity.txt (4ef512d059f3); evidence/EV-0126/summary.log (e3706caa87f8)

**Limitations:** Opt-in gaze config is a safety/regression-hygiene change; true gaze behavior still needs D1. Simulator input scenario currently unusable (app backgrounds immediately).

### EV-0127 — M5 turn-angle picker + acceptance matrix + device runbook; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:44:07-10:00 |
| Commit | `6b3253669c055c65818ee6be8bc57346e9f2d16e` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell, docs/mvp/M5_ACCEPTANCE.md, docs/mvp/M5_DEVICE_RUN.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. replace snap toggle with 0/15/30/45/90 turn picker saved to worldRotationIncrement; write M5 acceptance matrix and D1 runbook; build/stage/install

**Expected:** shell build/install PASS; docs published; device run NOT RUN

**Actual:** shell builds; app a2809f6d… installed; provider unchanged; M5_ACCEPTANCE/M5_DEVICE_RUN added; device run NOT RUN.

**Artifacts:** evidence/EV-0127/shell-build.log (cfa6ee6a1020); evidence/EV-0127/latest-build-identity.txt (27a12da5e806); evidence/EV-0127/M5_ACCEPTANCE.md (bd656e386648); evidence/EV-0127/M5_DEVICE_RUN.md (31ff1d3aa90b); evidence/EV-0127/summary.log (fd8b8b1e3439)

**Limitations:** Runbook is the planned D1 procedure; all device rows remain NOT RUN. Turn angle applies through the existing runtime settings path.

### EV-0128 — M5 diagnostics viewer + frame-pacing warning; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:47:03-10:00 |
| Commit | `57b165710ab598ae05230b3529b3a38fab2635e8` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add Recent diagnostics disclosure/status line providerJar check; add provider pacing WARN; build/test/stage/install/push

**Expected:** provider suite PASS; shell/app install PASS; device UI NOT RUN

**Actual:** full provider suite ALL PASS; shell builds; app bcdb5987… installed; provider 54353013… pushed; simulator still unusable; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0128/provider-tests.log (0be55cc76996); evidence/EV-0128/provider-build.log (52bc11129fdc); evidence/EV-0128/shell-build.log (cfa6ee6a1020); evidence/EV-0128/latest-build-identity.txt (01f882642a5a); evidence/EV-0128/summary.log (765bb8ce147d)

**Limitations:** Diagnostics viewer is local-only. Pacing warning threshold documented. Device behavior/UI NOT RUN.

### EV-0129 — M5 opt-in seated HMD pointer parity + installed build (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:48:43-10:00 |
| Commit | `4c36ef9a2f403cf719340542bafcc5e43f8d030a` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionRuntimeSettings.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionRuntimeSettingsTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add comfort.seatedHmdPointer setting/UI; provider allows HMD-aim fallback controllerTracking when seated; tests/build/stage/install/push

**Expected:** parser tests PASS; provider suite PASS; shell/app install PASS; device behavior NOT RUN

**Actual:** m5-settings 23 checks PASS; full provider suite ALL PASS; shell builds; app installed; provider pushed; device locked so seated behavior NOT RUN.

**Artifacts:** evidence/EV-0129/provider-tests.log (fd11a039a43a); evidence/EV-0129/provider-build.log (f8471ca67ffd); evidence/EV-0129/shell-build.log (cfa6ee6a1020); evidence/EV-0129/latest-build-identity.txt (1b6fe9a9333d); evidence/EV-0129/summary.log (4f49164b9ad8)

**Limitations:** Default off preserves prior behavior; only controllerTracking/GUI pointer uses the fallback, gesture actions still require real hands. Device seated parity NOT RUN.

### EV-0130 — M5 W1 tuning sliders + input tuning status (host/install PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:50:44-10:00 |
| Commit | `78a101f7f60cc5ef367ed049f43654288f0c6fa9` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionInputTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add W1 pinch/fist tuning sliders; expose VisionInput.tuningSummary in status JSON; tests/build/stage/install/push

**Expected:** tests PASS; provider suite PASS; shell/app install PASS; device NOT RUN

**Actual:** m4-input 172 checks PASS; full provider suite ALL PASS; shell builds; app installed; provider pushed; device locked so UI/tuning NOT RUN.

**Artifacts:** evidence/EV-0130/provider-tests.log (5685ee8fcf17); evidence/EV-0130/provider-build.log (f356a9985757); evidence/EV-0130/shell-build.log (cfa6ee6a1020); evidence/EV-0130/latest-build-identity.txt (c453fdf25530); evidence/EV-0130/summary.log (a063f480e02d)

**Limitations:** Thresholds apply via reload-input/next launch. Status summary is local-only. Device tuning feel NOT RUN.

### EV-0131 — M5 thermal pressure awareness from shell to provider; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:52:27-10:00 |
| Commit | `4ba17a20ac0f4961651b15e6ec8418632194e8bd` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/run_tests.sh, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell, provider/src/main/java/dev/vrmc/provider/VisionThermalState.java, provider/tests/dev/vrmc/provider/VisionThermalStateTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. write thermal-state file from shell; provider reads it and advises on serious/critical; status JSON thermalState; tests/build/stage/install/push

**Expected:** thermal parser tests PASS; provider suite PASS; shell/app install PASS; device NOT RUN

**Actual:** m5-thermal 8 checks PASS; full provider suite ALL PASS; shell builds; app installed; provider pushed; device locked so thermal behavior NOT RUN.

**Artifacts:** evidence/EV-0131/provider-tests.log (09df29da282f); evidence/EV-0131/provider-build.log (45067123086a); evidence/EV-0131/shell-build.log (cfa6ee6a1020); evidence/EV-0131/latest-build-identity.txt (7042d1733280); evidence/EV-0131/summary.log (861232a5ce08)

**Limitations:** Advisory only, no automatic setting changes; local file, no telemetry. Device K5 thermal behavior NOT RUN.

### EV-0132 — M6 compositor heartbeat + shell watchdog; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:54:11-10:00 |
| Commit | `8a587adf230294736a0620a38790f64754531d6b` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. write compositor heartbeat; add shell watchdog/status/diagnostics entry; build/stage/install

**Expected:** shell build/install PASS; heartbeat/watchdog logic present; device hang NOT RUN

**Actual:** shell framework builds; app installed; heartbeat+watchdog implemented; device locked so hang behavior NOT RUN.

**Artifacts:** evidence/EV-0132/shell-build.log (cfa6ee6a1020); evidence/EV-0132/latest-build-identity.txt (2001bf7b5c2e); evidence/EV-0132/summary.log (e91a95758471)

**Limitations:** Watchdog logs/surfaces stalls but does not auto-restart; product decision for auto-recovery remains device-tuned. Local file only.

### EV-0133 — M5 opt-in thermal quality reduction + launcher control; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:56:17-10:00 |
| Commit | `340f7595c04aa49fbe09de1103d93c9d66cd6584` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionRuntimeSettings.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionRuntimeSettingsTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add performance.thermalResponse notify/reduce parser/apply/provider cap/launcher picker; tests/build/stage/install/push

**Expected:** parser tests PASS; provider suite PASS; shell/app install PASS; device K5 NOT RUN

**Actual:** m5-settings 25 checks; full provider suite ALL PASS; shell builds; app installed; provider pushed; device locked so thermal behavior NOT RUN.

**Artifacts:** evidence/EV-0133/provider-tests.log (722a4fd1aa5a); evidence/EV-0133/provider-build.log (3e4bdda16629); evidence/EV-0133/shell-build.log (cfa6ee6a1020); evidence/EV-0133/latest-build-identity.txt (79fca55adb8c); evidence/EV-0133/summary.log (dc6459250ec3)

**Limitations:** Opt-in; notify default. Reduction is one-way until user raises settings. Device K5 behavior NOT RUN.

### EV-0134 — M5 provider-jar hash + reset settings; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-01T23:58:07-10:00 |
| Commit | `10f69f0be847744171e621e9e24bde13839774b1` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add CryptoKit provider jar SHA256 to status/diagnostics; add reset VRMC settings button; build/stage/install

**Expected:** shell builds/install PASS; hashes appear; device UI NOT RUN

**Actual:** shell framework builds; app installed; provider hash/reset implemented; device locked so UI NOT RUN.

**Artifacts:** evidence/EV-0134/shell-build.log (cfa6ee6a1020); evidence/EV-0134/latest-build-identity.txt (1c831ada913c); evidence/EV-0134/summary.log (db38a447c13e)

**Limitations:** Hash is computed locally from the game-dir provider jar; reset only removes VRMC config files, not saves/logs/crash guard. Device UI NOT RUN.

### EV-0135 — M5 opt-in adaptive framerate cap + launcher toggle; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:00:21-10:00 |
| Commit | `375d16af4205a050158725a5b5b75e106dac13d9` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionRuntimeSettings.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionRuntimeSettingsTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add performance.adaptiveFramerate parser/toggle; cap fps after 2 over-budget windows; status fields; tests/build/stage/install/push

**Expected:** parser tests PASS; provider suite PASS; shell/app install PASS; device K2 NOT RUN

**Actual:** m5-settings 27 checks; full provider suite ALL PASS; shell builds; app installed; provider pushed; device locked so pacing behavior NOT RUN.

**Artifacts:** evidence/EV-0135/provider-tests.log (15c0125e07f2); evidence/EV-0135/provider-build.log (e14aee376ff0); evidence/EV-0135/shell-build.log (cfa6ee6a1020); evidence/EV-0135/latest-build-identity.txt (083408945196); evidence/EV-0135/summary.log (9d823541fa1d)

**Limitations:** Opt-in; cap is one-way until user raises settings; local-only. Device K2 behavior NOT RUN.

### EV-0136 — M6 read-only device provider-integrity check PASS on D1 (behavior still NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:01:25-10:00 |
| Commit | `e468f0ff934ea68e3e4e159a560bddbc59cfc6cf` |
| Dirty state | ocs/mvp/M5_DEVICE_RUN.md, docs/mvp/M6_PLAN.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add m6_device_integrity.sh; list installed app; copy provider jar from device data container; compare sha256/size

**Expected:** installed VRMC listed; device provider jar hash equals local; behavior gates separate

**Actual:** VRMC 1.2.0 installed; device provider jar 4602605f…/85957 bytes matches local; RESULT PASS; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0136/device-integrity.log (6ec231ceb6b1); evidence/EV-0136/m6_device_integrity.sh (decd86f655da); evidence/EV-0136/latest-build-identity.txt (083408945196); evidence/EV-0136/summary.log (c9bb7ea72016)

**Limitations:** Integrity only; does not verify runtime behavior, gestures, UI or acceptance gates. Read-only device access.

### EV-0137 — M6 read-only device diagnostics pull; latest build not yet launched on D1 (behavior NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:02:14-10:00 |
| Commit | `4a77ddc2893bd4094992c3b1bc6a8c73405f8cf4` |
| Dirty state | ocs/mvp/M5_DEVICE_RUN.md, docs/mvp/M6_PLAN.md, scripts/m6_device_diagnostics_pull.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add device diagnostics pull script; copy local logs/status/config from app data container; inspect current installed state

**Expected:** read-only pull works; current/old session state identified; no behavior claims

**Actual:** pulled 3/18 files; current shell log absent => latest build not launched; old compositor log shows clean earlier session end; provider integrity PASS; behavior NOT RUN.

**Artifacts:** evidence/EV-0137/m6_device_diagnostics_pull.sh (3e3a27f0f5f7); evidence/EV-0137/Documents_vrmc-compositor.log (a8edb174bacc); evidence/EV-0137/Documents_vrmc-shell.prev.log (1a3527de8c6b); evidence/EV-0137/latest-build-identity.txt (083408945196); evidence/EV-0137/summary.log (0a2239f88c7b)

**Limitations:** Current-session behavior remains NOT RUN (device locked); evidence is installed-state/log snapshot only.

### EV-0138 — M5 locomotion tuning sliders; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:03:23-10:00 |
| Commit | `fc0983a653c36c29a1d4ce9710edee7f9dc434ee` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add move forward/strafe/deadzone/originZ/rotate-pulse sliders writing vrmc-input-tune.properties; build/stage/install

**Expected:** shell build/install PASS; values saved/preserved; device feel NOT RUN

**Actual:** shell builds; app installed; provider unchanged; device locked so locomotion feel NOT RUN.

**Artifacts:** evidence/EV-0138/shell-build.log (cfa6ee6a1020); evidence/EV-0138/latest-build-identity.txt (7066fe9f31f4); evidence/EV-0138/summary.log (f124c8bbacee)

**Limitations:** Tuning applies via reload-input or next launch; defaults match VisionLocomotion constants. Device feel NOT RUN.

### EV-0139 — M6 acceptance readiness report/gate; current NOT READY (device gates NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:03:59-10:00 |
| Commit | `45df37ac4ce069cbb5ef46877d88941c5fac971f` |
| Dirty state | ocs/mvp/M6_PLAN.md, export/acceptance-readiness.txt, scripts/m6_acceptance_report.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `NOT RUN` |

**Procedure:**

1. add m6_acceptance_report.sh parsing M5/M6 matrices; run report and require-pass; store snapshot; docs

**Expected:** report lists rows/counts; require-pass fails while device gates are NOT RUN; no device claims

**Actual:** rows=22 pass=0 partial=3 not-run=11; --require-pass exit 1 NOT READY; device behavior/gates NOT RUN.

**Artifacts:** evidence/EV-0139/acceptance-report.txt (ff06878c1ab8); evidence/EV-0139/acceptance-require.txt (3581eb490b6f); evidence/EV-0139/m6_acceptance_report.sh (bb9c07b8f7c7); evidence/EV-0139/acceptance-readiness.txt (ff06878c1ab8); evidence/EV-0139/summary.log (e4b1f0802cad)

**Limitations:** Reporting/gating tool only; current result NOT READY. Device AC/K/H gates remain NOT RUN.

### EV-0140 — M5 command-result feedback + Status button; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:05:41-10:00 |
| Commit | `5160a546b8048fbe5f75b7053e6a69273a3c059a` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. surface last vrmc-command-result line in launcher; add Status button; build/stage/install

**Expected:** shell build/install PASS; command result/status wired; device UI NOT RUN

**Actual:** shell builds; app installed; provider unchanged; device locked so UI NOT RUN.

**Artifacts:** evidence/EV-0140/shell-build.log (cfa6ee6a1020); evidence/EV-0140/latest-build-identity.txt (2d3ead3dca5d); evidence/EV-0140/summary.log (5d3c8a40cea2)

**Limitations:** Feedback appears after provider consumes a queued command; requires running game. Device UI NOT RUN.

### EV-0141 — M4 use/attack priority conflict hardening; provider pushed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:06:28-10:00 |
| Commit | `43605401bcda72e743bfb37ec3bbb08920c8da7c` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/tests/dev/vrmc/provider/VisionInputTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. suppress attack while right fist holds use; host test; build/push provider; device integrity check

**Expected:** m4-input PASS; full suite PASS; provider device hash match; device behavior NOT RUN

**Actual:** m4-input 176 checks PASS; full provider suite ALL PASS; provider pushed and integrity hash match; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0141/provider-tests.log (2bc6b4300a98); evidence/EV-0141/provider-build.log (b23fa13a8a7a); evidence/EV-0141/latest-build-identity.txt (47d5599a25bb); evidence/EV-0141/summary.log (99fc5ca2d6ae)

**Limitations:** Fist/use priority is host-tested at binding level; device bow/attack feel NOT RUN.

### EV-0142 — M4-W2 tracking-dropout pose hold + tuning slider; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:08:19-10:00 |
| Commit | `3619385a1dfdd416f52fd2b2abf521007dd42366` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. hold last valid hand pose for configurable dropout window; actions still release; launcher slider; tests/build/stage/install/push/integrity

**Expected:** provider suite PASS; shell/app install PASS; device integrity PASS; visual behavior NOT RUN

**Actual:** full provider suite ALL PASS; shell builds; app installed; provider pushed + integrity PASS; device locked so visual/aim dropout behavior NOT RUN.

**Artifacts:** evidence/EV-0142/provider-tests.log (487f7828f4f3); evidence/EV-0142/provider-build.log (a4c74ec0490e); evidence/EV-0142/shell-build.log (cfa6ee6a1020); evidence/EV-0142/latest-build-identity.txt (712e2d974ca2); evidence/EV-0142/summary.log (5ab4ddf9acd8)

**Limitations:** Pose hold affects only visual/aim fallback; actions release immediately. Device W2 visual/aim behavior NOT RUN.

### EV-0143 — M6 GPL/LGPL source offer + refreshed clean-tree development release package (device acceptance NOT READY)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:09:35-10:00 |
| Commit | `d2f51d4729bebb8ae3e326f655ac15fb0d11beac` |
| Dirty state | clean |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add SOURCE_OFFER.md and require/include docs in release check/package; clean tree -> release check/manifest/package with current app+provider; verify device provider hash; record hashes

**Expected:** release check PASS; manifest dirty_tree=no; package created/hashed; device integrity PASS; acceptance NOT READY

**Actual:** release check PASS; manifest clean; package bytes=206440226 sha=7cfc1433…; device provider integrity PASS; acceptance gate NOT READY.

**Artifacts:** evidence/EV-0143/release-check-current.log (09a75f960664); evidence/EV-0143/release-manifest-current.log (5e063341ee9d); evidence/EV-0143/release-manifest-dev.txt (93a7d84720db); evidence/EV-0143/release-package-current4.log (4c45313f2fb5); evidence/EV-0143/release-package-dev.txt (9b4e7ed49bb1); evidence/EV-0143/SOURCE_OFFER.md (32c110a900b3); evidence/EV-0143/release-package-list.txt (3dfacfd18da0); evidence/EV-0143/summary.log (2cb758755565)

**Limitations:** Development sideload package only; final release requires device AC/K/H PASS + legal sign-off + rebuild from release commit. No Minecraft/Vivecraft binaries included.

### EV-0144 — M5 fix invalid status JSON + launcher provider summary; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:11:28-10:00 |
| Commit | `12a62b33c653f60bcc3b3d21650191df9e6e6985` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. fix adaptiveFramerateApplied stray quote; add JSON parser/one-line provider summary in launcher; test/build/stage/install/push/integrity

**Expected:** provider suite PASS; shell builds; app install/provider integrity PASS; JSON validity fixed

**Actual:** full provider suite ALL PASS; shell builds; app 748e730e… installed; provider 9aeff79d… pushed + integrity PASS; no schema test for status JSON.

**Artifacts:** evidence/EV-0144/provider-tests.log (1d5b9fcf27d8); evidence/EV-0144/provider-build.log (1a7bcc438013); evidence/EV-0144/shell-build.log (cfa6ee6a1020); evidence/EV-0144/latest-build-identity.txt (3ebeffa2ae9d); evidence/EV-0144/summary.log (df6ece75b64c)

**Limitations:** Status JSON validity fix is not covered by an automated schema test; parser falls back to empty on invalid data. Device behavior NOT RUN.

### EV-0145 — M5 testable status JSON builder + strict validity regression test; provider pushed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:12:52-10:00 |
| Commit | `7db61c884caa8056cc51b06c63e8b1919ff0787d` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/run_tests.sh, provider/src/main/java/dev/vrmc/provider/VisionStatusJson.java, provider/tests/dev/vrmc/provider/VisionStatusJsonTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. extract VisionStatusJson builder; wire provider; add strict JSON parser test/escaping/regression; build/test/push provider/integrity

**Expected:** m5-status-json PASS; full suite PASS; device integrity PASS; device behavior NOT RUN

**Actual:** m5-status-json 12 checks PASS; full provider suite ALL PASS; provider pushed + integrity PASS; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0145/provider-tests.log (c5c021bcaf98); evidence/EV-0145/provider-build.log (fb0b7aec5f21); evidence/EV-0145/latest-build-identity.txt (145aca26e932); evidence/EV-0145/VisionStatusJson.java (8bd63f9703b0); evidence/EV-0145/VisionStatusJsonTest.java (c0a6c85422b5); evidence/EV-0145/summary.log (60182b5c0d31)

**Limitations:** Builder is pure/host-tested; actual file write remains untested against a live game instance. Device behavior NOT RUN.

### EV-0146 — M5 performance: throttle thermal-state polling to 5 s; provider pushed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:13:30-10:00 |
| Commit | `b0fb46527c8b7ab9db4cc401c6104244bd78df95` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. throttle per-frame thermal file read; build/test/push provider/integrity

**Expected:** provider suite PASS; device integrity PASS; no per-frame file I/O

**Actual:** full provider suite ALL PASS; provider pushed + integrity PASS; device locked so runtime performance NOT RUN.

**Artifacts:** evidence/EV-0146/provider-tests.log (d3a236cb65b0); evidence/EV-0146/provider-build.log (fe6d32b37787); evidence/EV-0146/latest-build-identity.txt (c3b14559f624); evidence/EV-0146/summary.log (c4ab0424a763)

**Limitations:** Host code-review fix of per-frame filesystem I/O; no device profiling. Device behavior/performance NOT RUN.

### EV-0147 — M5 allocation-free display/locomotion frame paths; provider pushed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:14:29-10:00 |
| Commit | `fe3d6339d3eb2313183539410b348e7f9c75e816` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionLocomotion.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionLocomotionTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. reuse display matrix scratch; allocation-free locomotion axes with stale-value clearing; tests/build/push/integrity

**Expected:** provider suite PASS; out-param test PASS; device integrity PASS; device perf NOT RUN

**Actual:** full provider suite ALL PASS; m4-locomotion 9 checks; provider pushed + integrity PASS; device locked so runtime perf NOT RUN.

**Artifacts:** evidence/EV-0147/provider-tests.log (0dfec3081fba); evidence/EV-0147/provider-build.log (8e4b8554a393); evidence/EV-0147/latest-build-identity.txt (6a9b6f94048c); evidence/EV-0147/summary.log (265c3831e17c)

**Limitations:** Static code-review allocation reduction; no runtime GC profiling. Device perf NOT RUN.

### EV-0148 — M5 frame pacing in status JSON + launcher summary; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:16:18-10:00 |
| Commit | `5141b2bca74079b92ea2368d3fe36772d6375ab9` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionStatusJson.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionStatusJsonTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add pacing fields to tested JSON builder/status; show in launcher; extend JSON test; build/stage/install/push/integrity

**Expected:** JSON test PASS; provider suite PASS; shell/app install PASS; device pacing NOT RUN

**Actual:** m5-status-json 15 checks; full provider suite ALL PASS; shell builds; app installed; provider pushed + integrity PASS; device locked so pacing NOT RUN.

**Artifacts:** evidence/EV-0148/provider-tests.log (1631d5796e15); evidence/EV-0148/provider-build.log (0ce6d2bbaf87); evidence/EV-0148/shell-build.log (cfa6ee6a1020); evidence/EV-0148/latest-build-identity.txt (2cfb325c83c4); evidence/EV-0148/summary.log (7afff9e7a0f1)

**Limitations:** Pacing fields come from the last diagnostic window; device K2 measurements NOT RUN.

### EV-0149 — M6 soak harness hardening + release-check dry-run (host PASS; device soak NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:16:50-10:00 |
| Commit | `fc0a3016f2d55ccb250e528055d44b936a2cb58d` |
| Dirty state | cripts/m6_release_check.sh, scripts/m6_soak_harness.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. fix game log path, add heartbeat/status artifacts and OOM/watchdog markers, enforce clean shutdown, wire dry-run into release check

**Expected:** bash syntax PASS; soak dry-run PASS; release check PASS; device soak NOT RUN

**Actual:** bash -n PASS; soak dry-run PASS; release check PASS (host readiness); device soak NOT RUN.

**Artifacts:** evidence/EV-0149/m6_soak_harness.sh (662678bbe09c); evidence/EV-0149/m6_release_check.sh (71b181af6452); evidence/EV-0149/release-check-soak.log (b70b35854a75); evidence/EV-0149/summary.log (36b47f3a206b)

**Limitations:** Device soak/AC-5 remains NOT RUN; REQUIRE_CLEAN_SHUTDOWN=1 makes a missing destroy-complete fail the run.

### EV-0150 — M6 host install metrics + device acceptance runbook; device gates NOT RUN

| Field | Value |
|---|---|
| Date | 2026-11-02T00:17:34-10:00 |
| Commit | `acdfc512777489bcea67bbe325bdc8f25a160bd1` |
| Dirty state | ocs/mvp/M6_PLAN.md, docs/mvp/M6_DEVICE_RUN.md, export/install-metrics-dev.txt, scripts/m6_install_metrics.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add m6_install_metrics.sh (app/provider/package sizes+hashes); write M6_DEVICE_RUN.md AC/K procedure; snapshot install metrics

**Expected:** metrics script PASS; runbook published; device gates NOT RUN

**Actual:** app 583,553,024 bytes/485 files/169 Mach-O; provider 89,469 bytes 57ddc366…; package 206,440,226 7cfc1433…; runbook published; device AC/K gates NOT RUN.

**Artifacts:** evidence/EV-0150/m6_install_metrics.sh (21a6fa3252a6); evidence/EV-0150/install-metrics-dev.txt (5985908ce746); evidence/EV-0150/M6_DEVICE_RUN.md (20a6aa4864b3); evidence/EV-0150/summary.log (3ba55eee003c)

**Limitations:** Host K6 groundwork only; device install-size/storage measurement and all AC/K gates remain NOT RUN.

### EV-0151 — M5 fix reload-input to apply all input-derived tuning; provider pushed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:18:44-10:00 |
| Commit | `849217c2886213ed1a82f3a535649bfa1d99ba5a` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. reload smoothing/move/hold/component config in reload-input; cancel hotbar wheel; tests/build/push/integrity

**Expected:** provider suite PASS; device integrity PASS; live reload behavior separate

**Actual:** full provider suite ALL PASS; provider pushed + integrity PASS; device locked so live reload behavior NOT RUN.

**Artifacts:** evidence/EV-0151/provider-tests.log (0043054296a1); evidence/EV-0151/provider-build.log (1a5649bfc30f); evidence/EV-0151/latest-build-identity.txt (6e2092d81117); evidence/EV-0151/summary.log (bbea3f474178)

**Limitations:** Host code fix of live tuning application; actual in-game reload behavior NOT RUN.

### EV-0152 — M4 validate hand-edited input tuning + host test; provider pushed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:19:58-10:00 |
| Commit | `2e87f8e36a64f899c61e2d994279d945fd747dce` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/tests/dev/vrmc/provider/VisionInputTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. validate tuning relations/ranges in VisionInput, warn+defaults/clamps; invalid-file test; build/push/integrity

**Expected:** m4-input test PASS; full suite PASS; device integrity PASS; device behavior NOT RUN

**Actual:** m4-input 184 checks; full provider suite ALL PASS; provider pushed + integrity PASS; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0152/provider-tests.log (43b43096f5b2); evidence/EV-0152/provider-build.log (78eb386a44cf); evidence/EV-0152/latest-build-identity.txt (fc3e3e86ab19); evidence/EV-0152/summary.log (7a6160728c96)

**Limitations:** Validation is host-tested at engine level; live hand-edited file behavior on device NOT RUN.

### EV-0153 — M6 async compositor heartbeat write (off render thread); installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:21:08-10:00 |
| Commit | `01d6e637ffc89dd8c38df692617ff8f062664660` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/VRMCCompositor.mm, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. dispatch atomic heartbeat write to utility queue; build/stage/install

**Expected:** shell build/install PASS; heartbeat watchdog behavior unchanged; device perf NOT RUN

**Actual:** shell framework builds; app installed; provider unchanged; device locked so runtime perf NOT RUN.

**Artifacts:** evidence/EV-0153/shell-build.log (cfa6ee6a1020); evidence/EV-0153/latest-build-identity.txt (5f6e988d09d0); evidence/EV-0153/summary.log (5ed23cbfd2e6)

**Limitations:** Host code-level I/O offload; no device timing measurement. Heartbeat semantics unchanged.

### EV-0154 — M6 reproducible provider jar (two builds identical); pushed + device integrity PASS

| Field | Value |
|---|---|
| Date | 2026-11-02T00:23:11-10:00 |
| Commit | `172397147c5f388cc5f4aef3da1a4ad6821c7218` |
| Dirty state | cripts/build_provider.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. set fixed jar entry timestamp; build twice compare hashes; rebuild canonical; provider suite; push/integrity

**Expected:** two builds same sha256; suite PASS; device integrity PASS; package metadata needs refresh

**Actual:** both builds fcd1df76… 90,619 bytes; suite ALL PASS; pushed + integrity PASS; release package metadata stale until regenerated.

**Artifacts:** evidence/EV-0154/repro-build1.log (fff057b5c270); evidence/EV-0154/repro-build2.log (b828b7c274a4); evidence/EV-0154/provider-tests-repro.log (0113634a8822); evidence/EV-0154/device-integrity-repro.log (3950e1ae3b89); evidence/EV-0154/summary.log (4d45489163c1)

**Limitations:** Reproducibility proven for same JDK/payload; device behavior NOT RUN. Existing dev package provider hash must be refreshed.

### EV-0155 — M6 reproducibility check + refreshed clean dev package (host PASS; device acceptance NOT READY)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:24:23-10:00 |
| Commit | `a35cc85f616caa57d27621ad9d450b3055a2394e` |
| Dirty state | xport/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add m6_reproducibility_check.sh; clean-tree release check/repro/package with latest app+provider; refresh manifest/package metadata

**Expected:** repro PASS; release check PASS; clean package created; acceptance NOT READY

**Actual:** repro two-build fcd1df76 PASS; release check PASS; package bytes=206459027 sha=3b3fa4fe…; acceptance NOT READY; device gates NOT RUN.

**Artifacts:** evidence/EV-0155/m6_reproducibility_check.sh (f0c575cc0fc9); evidence/EV-0155/repro.log (501420232b6a); evidence/EV-0155/release-check.log (b70b35854a75); evidence/EV-0155/package.log (c28919336cd5); evidence/EV-0155/release-manifest-dev.txt (6f871c57b1c8); evidence/EV-0155/release-package-dev.txt (f771ecc34027); evidence/EV-0155/summary.log (a9aa0170bc06)

**Limitations:** Development package only; device AC/K/H gates and final legal sign-off remain NOT RUN.

### EV-0156 — M6 release check proves provider reproducibility (host PASS; device acceptance NOT READY)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:24:52-10:00 |
| Commit | `f032caede06ef1437001571795d597ad9d51b9d2` |
| Dirty state | cripts/m6_release_check.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. invoke reproducibility check from release check and report provider hash; run release check

**Expected:** release check PASS incl. reproducibility; device acceptance separate

**Actual:** release check PASS; provider sha fcd1df76… reproducible; device acceptance NOT READY.

**Artifacts:** evidence/EV-0156/m6_release_check.sh (249eba0b627f); evidence/EV-0156/release-check-repro.log (dd2dd320aad8); evidence/EV-0156/summary.log (faa42aa5d4fe)

**Limitations:** Host release-readiness only; device AC/K/H gates remain NOT RUN.

### EV-0157 — M5 launcher toggle for fingertip held-item component; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:26:10-10:00 |
| Commit | `c83173637f6317987fe72cfb07ef3e0a30ad825f` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add hands.componentMode toggle save/load in launcher; build/stage/install

**Expected:** shell build/install PASS; default identity preserved; device visual behavior NOT RUN

**Actual:** shell builds; app installed; provider unchanged; device locked so visual/aim behavior NOT RUN.

**Artifacts:** evidence/EV-0157/shell-build.log (cfa6ee6a1020); evidence/EV-0157/latest-build-identity.txt (c142d910f3a0); evidence/EV-0157/summary.log (7248aee0f337)

**Limitations:** Experimental opt-in mode; default identity. Device visible-hands/held-item appearance NOT RUN.

### EV-0158 — M5 reset-settings confirmation dialog; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:27:55-10:00 |
| Commit | `651fc3129419fd78ddeebf119ae20707871ab3af` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. wrap Reset VRMC settings in confirmation dialog with scope message; build/stage/install

**Expected:** shell build/install PASS; no config deleted without confirm; device UI NOT RUN

**Actual:** shell builds; app installed; provider unchanged; device locked so UI interaction NOT RUN.

**Artifacts:** evidence/EV-0158/shell-build.log (cfa6ee6a1020); evidence/EV-0158/latest-build-identity.txt (754fb151d1a0); evidence/EV-0158/summary.log (43e007a4c70c)

**Limitations:** UI confirmation only; actual dialog interaction NOT RUN on device.

### EV-0159 — M5 diagnostics bundle completeness; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:29:43-10:00 |
| Commit | `e2808c875cf19fe01456f853c049b25ce4540c11` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add input tuning/thermal state/vignette/real game log to support bundle; build/stage/install

**Expected:** shell build/install PASS; bundle entries wired; device export UI NOT RUN

**Actual:** shell builds; app installed; provider unchanged; device locked so share UI NOT RUN.

**Artifacts:** evidence/EV-0159/shell-build.log (cfa6ee6a1020); evidence/EV-0159/latest-build-identity.txt (bdffef393e1b); evidence/EV-0159/summary.log (a6f0dd90b9fc)

**Limitations:** Bundle completeness is build-verified; actual export/share and contents on device NOT RUN.

### EV-0160 — M6 refreshed clean dev package to latest app a046bab6 + reproducible provider (host PASS; acceptance NOT READY)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:30:33-10:00 |
| Commit | `4bc1aea03655c356000e304f6b48ca3054e50018` |
| Dirty state | xport/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean-tree release check/repro/package with latest app+provider; refresh manifest/package metadata

**Expected:** release check/repro PASS; package created; acceptance NOT READY; device gates NOT RUN

**Actual:** release check PASS; repro PASS; package bytes=206458384 sha=4f89d0d6…; manifest dirty_tree=no; acceptance NOT READY.

**Artifacts:** evidence/EV-0160/release-check.log (480623cca40b); evidence/EV-0160/repro.log (baa99d9f094e); evidence/EV-0160/package.log (6a90c6406368); evidence/EV-0160/release-manifest-dev.txt (ac42829f20f6); evidence/EV-0160/release-package-dev.txt (77a932a88467); evidence/EV-0160/summary.log (1be45736cfcd)

**Limitations:** Development package only; device AC/K/H gates and final legal sign-off remain NOT RUN.

### EV-0161 — M6 fix acceptance readiness parser/status columns; still NOT READY (device gates NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:31:08-10:00 |
| Commit | `2474ba786cfc1b97de2b6ce34fe4be3835cb26c9` |
| Dirty state | xport/acceptance-readiness.txt, scripts/m6_acceptance_report.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. parse M6 status column, clean M5 statuses, correct counts; refresh acceptance snapshot; require-pass check

**Expected:** correct per-row statuses/counts; require-pass fails while device gates NOT RUN

**Actual:** rows=22 explicit-pass=0 not-run=17 partial=7; --require-pass exit 1 NOT READY; no device claims.

**Artifacts:** evidence/EV-0161/m6_acceptance_report.sh (74c825d345b4); evidence/EV-0161/acceptance-report3.txt (f93460be9335); evidence/EV-0161/acceptance-require3.txt (8d41a87eff1b); evidence/EV-0161/acceptance-readiness.txt (f93460be9335); evidence/EV-0161/summary.log (8a9aa6147aee)

**Limitations:** Reporting correctness fix only; device AC/K/H gates remain NOT RUN.

### EV-0162 — M4/M6 input fuzz 100k frames with W4 safety invariants; 0 violations (host; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:31:55-10:00 |
| Commit | `ad929e2337a30ffe0e326f730372af70257e012f` |
| Dirty state | rovider/tests/dev/vrmc/provider/VisionInputFuzzTest.java, provider/tests/run_tests.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. parameterize fuzz frames; add ring/chord/attack/teleport/use invariants; run 100k-frame suite

**Expected:** 100k frames 0 violations; full provider suite PASS; device behavior separate

**Actual:** frames=100000 violations=0; full provider suite ALL PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0162/VisionInputFuzzTest.java (5f535867a87e); evidence/EV-0162/fuzz-100k.log (49f98fa8ba60); evidence/EV-0162/summary.log (ecdff64b7e20)

**Limitations:** Host stress only; no device evidence.

### EV-0163 — Extreme stress: 1M-frame fuzz + TSan bridge suite (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:32:39-10:00 |
| Commit | `e1db0a9a0a1ed5e542ea8c646ad22e3ddd061ef0` |
| Dirty state | clean |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. run provider fuzz at 1,000,000 frames; run full bridge suite incl. TSan concurrency tests

**Expected:** 1M frames 0 violations; bridge TSan suite PASS; device gates separate

**Actual:** 1,000,000 frames/0 violations; full bridge suite incl. TSan ALL PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0163/provider-tests-fuzz1m.log (79004dbe4817); evidence/EV-0163/bridge-tests-stress.log (8f7fef0c57a1); evidence/EV-0163/summary.log (92fe9134162c)

**Limitations:** Host stress only; no device evidence. Fuzz frame count env-configurable.

### EV-0164 — M6 path-independent app hash + package verifier PASS (host; device acceptance NOT READY)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:33:58-10:00 |
| Commit | `28bd12bc97557ce3f9219700f9211385897104fd` |
| Dirty state | xport/latest-build-identity.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add app_tree_sha256/path-independent manifest hash; add package verifier; regenerate manifest/package; verify

**Expected:** package verifier PASS incl app/provider hashes; manifest dirty_tree=no; acceptance NOT READY

**Actual:** app hash d1d68596…; package bytes=206459032 sha=46b14b6a…; verifier PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0164/release-manifest.txt (fbfd6ff61bb5); evidence/EV-0164/release-package-dev.txt (67fe64019f31); evidence/EV-0164/verify.log (74508315a639); evidence/EV-0164/package.log (84a29d38c7de); evidence/EV-0164/summary.log (f289286c3e2a)

**Limitations:** Host package integrity only; device AC/K/H gates remain NOT RUN. App hashes before EV-0164 are not comparable.

### EV-0165 — M6 single-command release-ready gate; host/package/device PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T00:34:51-10:00 |
| Commit | `e8ff336647b83d5a7bc06e816351da4b9a2a1578` |
| Dirty state | scripts/m6_release_ready.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add m6_release_ready.sh aggregating release check/package verify/device integrity/acceptance gate; run against current dev package

**Expected:** all host gates PASS; acceptance correctly NOT READY

**Actual:** release check/package/device integrity PASS; acceptance 0/22 explicit PASS => RESULT NOT RELEASE READY (expected).

**Artifacts:** evidence/EV-0165/m6_release_ready.sh (7cb424ead4da); evidence/EV-0165/release-ready.log (c360986b1561); evidence/EV-0165/summary.log (64e236c2c794)

**Limitations:** Gate intentionally fails until device acceptance; no behavior claims.

### EV-0166 — M4 VisionHandPose 200k-case numerical fuzz: 0 violations (host; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:36:01-10:00 |
| Commit | `7732a01f50608ce57946b08b4066a6122f44492d` |
| Dirty state | rovider/tests/run_tests.sh, provider/tests/dev/vrmc/provider/VisionHandPoseFuzzTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add randomized pose fuzz test to provider suite; run 200k cases incl. extreme/degenerate values

**Expected:** 0 violations; full provider suite ALL PASS; device gates separate

**Actual:** cases=200000 nonFiniteSeen=0 violations=0; full provider suite ALL PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0166/VisionHandPoseFuzzTest.java (00c62839490b); evidence/EV-0166/provider-tests-posefuzz2.log (fe5f93469bde); evidence/EV-0166/summary.log (aef534a902e8)

**Limitations:** Host numerical stress only; no device evidence.

### EV-0167 — M4 pose smoother 100k-case numerical fuzz: 0 violations (host; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:36:43-10:00 |
| Commit | `a902d2f6d9eda8889dc4784628a1eb54f603dedd` |
| Dirty state | rovider/tests/run_tests.sh, provider/tests/dev/vrmc/provider/VisionPoseSmootherFuzzTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add randomized smoother fuzz test to provider suite; huge translations/timestamp irregularities/reset

**Expected:** 0 violations; full provider suite ALL PASS; device gates separate

**Actual:** cases=100000 violations=0; full provider suite ALL PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0167/VisionPoseSmootherFuzzTest.java (8a929f820025); evidence/EV-0167/provider-tests-smootherfuzz.log (2d5c81461034); evidence/EV-0167/summary.log (d06e35aae643)

**Limitations:** Host numerical stress only; no device evidence.

### EV-0168 — M5 status JSON 100k-case fuzz: 0 violations (host; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:37:30-10:00 |
| Commit | `ed6e04e18d187ee2fe47bb134e1751dbc6d36086` |
| Dirty state | rovider/tests/dev/vrmc/provider/VisionStatusJsonTest.java, provider/tests/run_tests.sh, provider/tests/dev/vrmc/provider/TestJson.java, provider/tests/dev/vrmc/provider/VisionStatusJsonFuzzTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. extract shared TestJson parser; add status JSON arbitrary-string/non-finite fuzz; run suite

**Expected:** 100k round-trips 0 violations; full suite PASS; device gates separate

**Actual:** cases=100000 violations=0; full provider suite ALL PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0168/VisionStatusJsonFuzzTest.java (6c70eec7c27f); evidence/EV-0168/TestJson.java (7c94a15f9b16); evidence/EV-0168/provider-tests-jsonfuzz2.log (4ede12c56c90); evidence/EV-0168/summary.log (b42abb3fa284)

**Limitations:** Host-only JSON robustness; device behavior NOT RUN.

### EV-0169 — M5 runtime-settings 100k-case fuzz: 0 violations (host; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:38:06-10:00 |
| Commit | `af01a7a8df312647c6f39b0c919cab99d9ab05c3` |
| Dirty state | rovider/tests/run_tests.sh, provider/tests/dev/vrmc/provider/VisionRuntimeSettingsFuzzTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add randomized VisionRuntimeSettings.parse fuzz with bound checks; run suite

**Expected:** 100k maps no throw/out-of-range; full suite PASS; device gates separate

**Actual:** cases=100000 violations=0; full provider suite ALL PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0169/VisionRuntimeSettingsFuzzTest.java (7d3f08f834a7); evidence/EV-0169/provider-tests-settingsfuzz.log (919784530e66); evidence/EV-0169/summary.log (e91454bd03ec)

**Limitations:** Host-only parser robustness; device behavior NOT RUN.

### EV-0170 — M5 command-file size cap + oversized rejection test; provider pushed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:38:43-10:00 |
| Commit | `23a6b32ac85eb9f6419ac22e5bdd33e5026ef09a` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionCommandFile.java, provider/tests/dev/vrmc/provider/VisionCommandFileTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. cap command file at 4096 bytes before reading; test rejection; build/push/integrity

**Expected:** command tests PASS; full suite PASS; device integrity PASS; device behavior NOT RUN

**Actual:** m5-command 14 checks; full provider suite ALL PASS; provider pushed + integrity PASS; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0170/VisionCommandFile.java (a9351fce30c2); evidence/EV-0170/provider-tests-cmdlimit.log (e23055a25eec); evidence/EV-0170/ev-cmdlimit-integrity.log (37cabce9abdf); evidence/EV-0170/summary.log (d6fc36a05df9)

**Limitations:** Host robustness only; device behavior NOT RUN.

### EV-0171 — M6 refreshed dev package to command-cap provider; verifier/gate host PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T00:39:54-10:00 |
| Commit | `45ee1b88173946d33c702cb7e698e722b88517e5` |
| Dirty state | xport/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean-tree release check/repro/manifest/package/verifier/release-ready; refresh export metadata

**Expected:** host/package/device integrity PASS; acceptance NOT READY

**Actual:** release check/repro/package verifier/release-ready host gates PASS; package bytes=206459555 sha=6e99d8e9…; acceptance NOT READY.

**Artifacts:** evidence/EV-0171/release-manifest.txt (738e6e6bb129); evidence/EV-0171/release-package-dev.txt (78ef07540012); evidence/EV-0171/verify.log (2f03ef85e9f0); evidence/EV-0171/release-ready.log (1dc4d1f17b8d); evidence/EV-0171/summary.log (aea752e0502f)

**Limitations:** Development package only; device AC/K/H gates NOT RUN. Acceptance gate intentionally fails.

### EV-0172 — M6 launcher-provider settings key parity guard (31 keys PASS; release check integrated)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:40:26-10:00 |
| Commit | `44fe4bebadae5dd0c27b79a44bf9cab751fdc0ef` |
| Dirty state | cripts/m6_release_check.sh, scripts/check_settings_keys.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add settings-key parity script; integrate into release check; run

**Expected:** all launcher keys recognized; release check PASS; device gates separate

**Actual:** checked=31 all OK; release check PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0172/check_settings_keys.sh (09173268aa41); evidence/EV-0172/settings-keys.log (0a5511214b4b); evidence/EV-0172/release-check-keys.log (ce557deab754); evidence/EV-0172/summary.log (9ed5bbedc228)

**Limitations:** Host drift guard only; does not execute device behavior.

### EV-0173 — M6 launcher status-field parity guard (11 fields PASS; release check integrated)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:40:52-10:00 |
| Commit | `ce3a643700fd2ae0f4839871599c49a187f7b2ef` |
| Dirty state | cripts/m6_release_check.sh, scripts/check_status_fields.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add status-field parity script; integrate into release check; run

**Expected:** all launcher status fields written; release check PASS; device gates separate

**Actual:** checked=11 all OK; release check PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0173/check_status_fields.sh (bb2eb557652c); evidence/EV-0173/status-fields.log (4c5c0367d7e7); evidence/EV-0173/release-check-fields.log (c571bdff64ef); evidence/EV-0173/summary.log (5d0e7e1e6847)

**Limitations:** Host drift guard only; no device behavior.

### EV-0174 — M4/M5 bow diagnostic telemetry in status/launcher; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:42:47-10:00 |
| Commit | `7df3ac076c9549baf9f95fa8f97fabaff5099da3` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionStatusJson.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionStatusJsonFuzzTest.java, provider/tests/dev/vrmc/provider/VisionStatusJsonTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add bowActive/notched/drawPercent to tested JSON builder/status; show in launcher; update tests/guards; build/install/push/integrity

**Expected:** builder/test/guard PASS; app install/provider integrity PASS; device bow behavior NOT RUN

**Actual:** status-json 18 checks + 100k fuzz PASS; provider suite ALL PASS; guard checked=14; app 6e4b7c5e… installed; provider 47713964… pushed + integrity PASS; device locked so bow behavior NOT RUN.

**Artifacts:** evidence/EV-0174/provider-tests-bowtel2.log (33e9f400c267); evidence/EV-0174/status-fields-bow.log (46078b52c176); evidence/EV-0174/ev-bowtel-integrity.log (ce3ab7ff4654); evidence/EV-0174/latest-build-identity.txt (976dd1087c5e); evidence/EV-0174/summary.log (6a189e8541de)

**Limitations:** Telemetry only; device two-hand bow/AC-4 behavior NOT RUN. Release package metadata needs refresh.

### EV-0175 — M6 refreshed dev package/metrics for bow-telemetry build; gate host PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T00:43:47-10:00 |
| Commit | `e8351a9a75b22a54c7a48b45581a36a635b7f29f` |
| Dirty state | xport/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean release check/repro/manifest/package/verifier/release-ready + install metrics for latest app/provider; refresh metadata

**Expected:** host/package/device PASS; acceptance NOT READY

**Actual:** package bytes=206462210 sha=8a82159e…; app 6e4b7c5e…; provider 47713964…; verifier/release-ready host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0175/release-manifest.txt (2200040f67a5); evidence/EV-0175/release-package-dev.txt (8880abb8344f); evidence/EV-0175/verify.log (b18b563424f5); evidence/EV-0175/release-ready.log (e7c1f8dd4307); evidence/EV-0175/install-metrics.txt (075aa68489a3); evidence/EV-0175/summary.log (48e6ad70d755)

**Limitations:** Development package only; device gates NOT RUN.

### EV-0176 — M4/M5 climb diagnostic telemetry in status/launcher; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:45:35-10:00 |
| Commit | `37278850a79dfcb587156fe7a6bdf866d50ac64e` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionStatusJson.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionStatusJsonFuzzTest.java, provider/tests/dev/vrmc/provider/VisionStatusJsonTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add climbGrabbing/climbeyClimb/climbActive to tested JSON builder/status; show in launcher; tests/guards/build/install/push/integrity

**Expected:** builder/tests/guards PASS; app install/provider integrity PASS; device H9 NOT RUN

**Actual:** status-json 21 checks + 100k fuzz PASS; provider suite ALL PASS; guard checked=17; app 90c83c0d… installed; provider 1d36487e… pushed + integrity PASS; device locked so H9 behavior NOT RUN.

**Artifacts:** evidence/EV-0176/provider-tests-climbtelem.log (401d6bf9b933); evidence/EV-0176/status-fields-climb.log (42eb86804954); evidence/EV-0176/ev-climbtelem-integrity.log (56a42208d776); evidence/EV-0176/latest-build-identity.txt (1db6e74ca2b5); evidence/EV-0176/summary.log (030deb8b1cd6)

**Limitations:** Telemetry only; device H9 climbing behavior NOT RUN. Release package metadata needs refresh.

### EV-0177 — M6 refreshed package/metrics for climb-telemetry build; host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T00:46:34-10:00 |
| Commit | `c913928f8bee5790c58770f1763ca66f7985be9f` |
| Dirty state | xport/acceptance-readiness.txt, export/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean release check/repro/manifest/package/verifier/release-ready + install metrics + acceptance snapshot

**Expected:** host/package/device PASS; acceptance NOT READY

**Actual:** package bytes=206468279 sha=9720b6527c5276b2ec25aa897ad9171e2799fbbbc5c2a05cf1383c0ce34abc2f; app=90c83c0d6e5d45df04a050a638aeb2ba11c6dad058a94d5f300cf15d5ecfd9f7; provider=1d36487eaead9cf5d53f363aa54ffcb7e4afe09124c1365aa11567a9e0ca7e16; verifier/release-ready host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0177/release-manifest.txt (b52cfe1f7f76); evidence/EV-0177/release-package-dev.txt (8f4f4748d59e); evidence/EV-0177/verify.log (c37dcb532479); evidence/EV-0177/release-ready.log (bf0d8edaee3f); evidence/EV-0177/acceptance.log (269b852e138e); evidence/EV-0177/install-metrics.txt (d0cc996800aa); evidence/EV-0177/summary.log (a6263a0013c7)

**Limitations:** Development package only; device gates NOT RUN.

### EV-0178 — M5 restore-performance command/button; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:49:19-10:00 |
| Commit | `3e3716dd2cfd1b46085dd698d4786308b66dd6d7` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionCommandFile.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionCommandFileTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. capture pre-reduction settings; add restore-performance command/launcher button; test/build/install/push/integrity

**Expected:** command tests PASS; provider suite PASS; app install/provider integrity PASS; device behavior NOT RUN

**Actual:** m5-command 15 checks; full provider suite ALL PASS; shell builds; app 2939c509… installed; provider 5379fe2c… (92008 bytes) pushed + integrity PASS; device locked so restore behavior NOT RUN.

**Artifacts:** evidence/EV-0178/provider-tests-restoreperf.log (517a82d7ba1a); evidence/EV-0178/repro-restoreperf.log (83636432c3a1); evidence/EV-0178/ev-restoreperf-integrity.log (a5e2ad53994d); evidence/EV-0178/latest-build-identity.txt (327ab6cf2b01); evidence/EV-0178/summary.log (7509bb119f6c)

**Limitations:** One-tap restore of thermal/adaptive caps; device behavior NOT RUN. Package metadata needs refresh.

### EV-0179 — M6 refreshed package/metrics to restore-performance build; host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T00:50:18-10:00 |
| Commit | `17f8c87abdffeec0b11e0e12beeb5fb30c192bc3` |
| Dirty state | xport/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean release check/repro/manifest/package/verifier/release-ready + install metrics

**Expected:** host/package/device PASS; acceptance NOT READY

**Actual:** package bytes=206470289 sha=20ffc04d980001124a9585f9511047b3a7f17bedc62b9482003486d6298ce648; app=2939c509d8522c92504c2cc19923336ddf8fa0d3530e7164f9aee0da403ee4d7; provider=5379fe2ced32d9cc1ece9bbb6cbf49684d0657584c0f22f06edb8e8df138baf6; verifier/release-ready host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0179/release-manifest.txt (fce3c924cd57); evidence/EV-0179/release-package-dev.txt (877c37ae4500); evidence/EV-0179/verify.log (8304f026f193); evidence/EV-0179/release-ready.log (29b6f2191a22); evidence/EV-0179/install-metrics.txt (80c1d1df28f9); evidence/EV-0179/summary.log (eaabf16260c6)

**Limitations:** Development package only; device gates NOT RUN.

### EV-0180 — M6 stale-package guard in release gate; current package freshness PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T00:50:55-10:00 |
| Commit | `8cdbd27771d003ca901ffbc16c879d67e4bb6276` |
| Dirty state | cripts/m6_release_ready.sh, scripts/m6_check_release_current.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add package-vs-current-build freshness check; run release-ready with explicit app/provider

**Expected:** freshness PASS; host gates PASS; acceptance NOT READY

**Actual:** app/provider manifest hashes match current builds; release-ready host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0180/m6_check_release_current.sh (6b610cf223e3); evidence/EV-0180/m6_release_ready.sh (121d88f06c49); evidence/EV-0180/release-current.log (081c7cc45479); evidence/EV-0180/release-ready-fresh.log (a42037f0d933); evidence/EV-0180/summary.log (9b3f6ba6c100)

**Limitations:** Host release integrity only; device AC/K/H gates NOT RUN.

### EV-0181 — M6 current-status/handoff document for user step-by-step review

| Field | Value |
|---|---|
| Date | 2026-11-02T00:51:19-10:00 |
| Commit | `0bcc15aa63bdaf9fa70aa66f094ca720f461aae4` |
| Dirty state | docs/mvp/STATUS.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. write STATUS.md summarizing build identity/milestones/features/host results/open device gates; link README

**Expected:** status doc accurate, no device claims; host evidence summarized

**Actual:** STATUS.md added with current app/provider hashes, host results, device-only remaining steps; device gates NOT RUN.

**Artifacts:** evidence/EV-0181/STATUS.md (c8883c387957); evidence/EV-0181/latest-build-identity.txt (327ab6cf2b01); evidence/EV-0181/summary.log (dc9205074b65)

**Limitations:** Handoff/documentation only; device acceptance remains NOT RUN.

### EV-0182 — M5 auto status JSON writes (start + diagnostic windows); provider pushed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:52:02-10:00 |
| Commit | `18c45d79acef6518a486b1a7021f47222721d1c2` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. auto-write status on first update and each diag window; tests/build/push/integrity

**Expected:** provider suite PASS; device integrity PASS; no per-frame I/O added; device behavior NOT RUN

**Actual:** full provider suite ALL PASS; reproducible provider 702e7193510c335bfacbb88543dd0facce1cca30e1d352ae26c1538c7e88e015 pushed + integrity PASS; app unchanged; device locked so auto-status behavior NOT RUN.

**Artifacts:** evidence/EV-0182/provider-tests-autostatus.log (92a1ad8cf668); evidence/EV-0182/repro-autostatus.log (ed3dde9eddaa); evidence/EV-0182/ev-autostatus-integrity.log (32a507a7d994); evidence/EV-0182/latest-build-identity.txt (0dde020b38dd); evidence/EV-0182/summary.log (511a1f03e7b3)

**Limitations:** Status freshness improvement; device behavior NOT RUN. Package metadata stale.

### EV-0183 — M6 refreshed package/metrics to auto-status build; host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T00:53:07-10:00 |
| Commit | `57c57b88b1ba63afc33e490dc1fb11cef41f23da` |
| Dirty state | xport/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean release check/repro/manifest/package/verifier/freshness/release-ready + install metrics

**Expected:** host/package/freshness/device PASS; acceptance NOT READY

**Actual:** package bytes=206470666 sha=f6a687ace74facb3e266f4a858fb0618d55b032f46750c70f7f010f711c843c0; app=2939c509d8522c92504c2cc19923336ddf8fa0d3530e7164f9aee0da403ee4d7; provider=702e7193510c335bfacbb88543dd0facce1cca30e1d352ae26c1538c7e88e015; verifier/freshness/release-ready host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0183/release-manifest.txt (3e3259e71db6); evidence/EV-0183/release-package-dev.txt (f131a74c575d); evidence/EV-0183/verify.log (883e8bd25e8e); evidence/EV-0183/release-ready.log (86c594e2a568); evidence/EV-0183/install-metrics.txt (777a59b044d9); evidence/EV-0183/summary.log (8aba2602e173)

**Limitations:** Development package only; device gates NOT RUN.

### EV-0184 — M5 auto-sprint settings/UI; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:54:51-10:00 |
| Commit | `fe3c8d9dfa5e861292bca5d676f17afa11717889` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionRuntimeSettings.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionRuntimeSettingsTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add comfort.autoSprint/threshold parser/apply/UI; settings tests/key guard; build/install/push/integrity

**Expected:** settings tests PASS; provider suite PASS; app install/provider integrity PASS; device feel NOT RUN

**Actual:** m5-settings 29 checks; full provider suite ALL PASS; guard checked=33; app 2388965a… installed; provider a109ae56… (92516 bytes) pushed + integrity PASS; device locked so sprint feel NOT RUN.

**Artifacts:** evidence/EV-0184/provider-tests-sprint2.log (215a623d1d82); evidence/EV-0184/repro-sprint.log (70a95ecd0ac8); evidence/EV-0184/ev-sprint-integrity.log (b67fb66f0a70); evidence/EV-0184/settings-keys-sprint.log (2d070d71c1ac); evidence/EV-0184/latest-build-identity.txt (c107ad2716be); evidence/EV-0184/summary.log (0db6a4999f26)

**Limitations:** Auto-sprint applies through Vivecraft settings; device feel NOT RUN. Package metadata needs refresh.

### EV-0185 — M6 refreshed package/metrics/status doc to auto-sprint build; host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T00:55:57-10:00 |
| Commit | `8ac7a91b7ab538be509532845392f88eaf137383` |
| Dirty state | ocs/mvp/STATUS.md, export/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean release check/repro/manifest/package/verifier/freshness/release-ready + metrics + STATUS update

**Expected:** host/package/freshness/device PASS; acceptance NOT READY

**Actual:** package bytes=206471014 sha=bc497dfe140db8433bffa532cfffa2e84488de0fcaf8ef11d2daba9189d2ebbd; app=2388965a1908f9630f80f77e4f5b8fc4b44ddddf58175452613182faabd375f3; provider=a109ae5661fd726b445ed083e3cce3c00b651fe5dd89154daf501a85ec19de58; verifier/freshness/release-ready host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0185/release-manifest.txt (adca8c6853ac); evidence/EV-0185/release-package-dev.txt (668ef4c4a4a3); evidence/EV-0185/verify.log (f3c646488d2e); evidence/EV-0185/release-ready.log (49c98a2ab55d); evidence/EV-0185/install-metrics.txt (388e583acf64); evidence/EV-0185/STATUS.md (7f412425bc2d); evidence/EV-0185/summary.log (bcb43e2289c4)

**Limitations:** Development package only; device gates NOT RUN.

### EV-0186 — M4 gaze math 500k-case fuzz: 0 violations (host; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T00:56:55-10:00 |
| Commit | `74205c0db2c0d33fcd96a4dedfc5e0e1d5d17a6f` |
| Dirty state | rovider/tests/run_tests.sh, provider/tests/dev/vrmc/provider/VisionGazeMathFuzzTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add randomized tile/ray/plane gaze fuzz to provider suite; run

**Expected:** 500k cases no exceptions/out-of-range; full suite PASS; device gates separate

**Actual:** cases=500000 violations=0; full provider suite ALL PASS; device gaze behavior NOT RUN.

**Artifacts:** evidence/EV-0186/VisionGazeMathFuzzTest.java (47b69c676c06); evidence/EV-0186/provider-tests-gazefuzz.log (7966f9f98363); evidence/EV-0186/summary.log (74cd9d757154)

**Limitations:** Host numerical stress only; no device evidence.

### EV-0187 — M6 release gate defaults app freshness to latest build identity; host gates PASS

| Field | Value |
|---|---|
| Date | 2026-11-02T00:57:34-10:00 |
| Commit | `b773f12db299d0438aad8c6951861472cbf60d2e` |
| Dirty state | cripts/m6_release_ready.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. parse staged app path from latest-build-identity when app override unset; run release-ready

**Expected:** app/provider freshness checked by default; host gates PASS; acceptance NOT READY

**Actual:** app hash 2388965a… and provider a109ae56… match; release-ready host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0187/m6_release_ready.sh (a72cebfe2158); evidence/EV-0187/release-ready-default.log (6c4b2e21bb34); evidence/EV-0187/latest-build-identity.txt (c107ad2716be); evidence/EV-0187/summary.log (7e9ec5c9470f)

**Limitations:** Host release integrity only; device AC/K/H gates NOT RUN.

### EV-0188 — Consolidated host regression: all suites/release gates PASS; acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T00:58:50-10:00 |
| Commit | `4686a514c009c177a470ef3f218c998f2f31e05b` |
| Dirty state | clean |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. run shell build, provider/bridge suites, M4 selfcheck, release check/ready, acceptance gate, device integrity

**Expected:** host suites/gates PASS; acceptance correctly NOT READY; device gates separate

**Actual:** all host suites/gates PASS; release-ready host gates PASS; acceptance 0/22 NOT READY; device AC/K/H NOT RUN.

**Artifacts:** evidence/EV-0188/shell-build.log (cfa6ee6a1020); evidence/EV-0188/provider-tests.log (4d37790c05a4); evidence/EV-0188/bridge-tests.log (09ce00017c65); evidence/EV-0188/m4-selfcheck.log (72e02fdc43a3); evidence/EV-0188/release-check.log (cc3d48a6589a); evidence/EV-0188/release-ready.log (12df4e7ab3fb); evidence/EV-0188/acceptance.log (ed7a41efcc08); evidence/EV-0188/device-integrity.log (b67fb66f0a70); evidence/EV-0188/timeline.txt (b765ea257d60); evidence/EV-0188/summary.log (0d22786b00f8)

**Limitations:** Consolidated host-only regression; device acceptance remains NOT RUN/NOT READY.

### EV-0189 — M4 plan updated to host-complete W4/W5 status; device-only gaps explicit

| Field | Value |
|---|---|
| Date | 2026-11-02T00:59:11-10:00 |
| Commit | `238428d02e61c68b5423fa666c8c436b611b0170` |
| Dirty state | ocs/mvp/M4_PLAN.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. append W4/W5 completion summary/device-only remainder to M4_PLAN; reference controls/evidence

**Expected:** docs accurately reflect implemented host features and open device gates

**Actual:** M4_PLAN 6w appended; no code changes; device gates remain NOT RUN.

**Artifacts:** evidence/EV-0189/M4_PLAN.md (b02a0276c498); evidence/EV-0189/summary.log (c013951d070b)

**Limitations:** Documentation only; no device behavior claims.

### EV-0190 — M4-W5 guided hand calibration command/button/report; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T01:01:43-10:00 |
| Commit | `7d37fd7f58ad4454ce4db7fd5b6a333129d3a212` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionCommandFile.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionCommandFileTest.java, provider/tests/run_tests.sh, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell, provider/src/main/java/dev/vrmc/provider/VisionHandCalibration.java, provider/tests/dev/vrmc/provider/VisionHandCalibrationTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add calibration module/test, command prompts/sampling/report, launcher button, diagnostics entry; build/install/push/integrity

**Expected:** calibration/command tests PASS; guards PASS; app install/provider integrity PASS; device calibration NOT RUN

**Actual:** m4-hand-calibration 15 checks; m5-command 16 checks; full suite ALL PASS; guards PASS; app b0680cac… installed; provider a4212200… (95870 bytes) pushed + integrity PASS; device locked so calibration behavior NOT RUN.

**Artifacts:** evidence/EV-0190/VisionHandCalibration.java (a9b4641de529); evidence/EV-0190/provider-tests-calib3.log (b5e094b20477); evidence/EV-0190/repro-calib.log (ac33f0cd57e2); evidence/EV-0190/ev-calib-integrity.log (40308d22dec5); evidence/EV-0190/latest-build-identity.txt (53185fb3ce0a); evidence/EV-0190/summary.log (846b01ff2aa7)

**Limitations:** Calibration is advisory; device protocol prompt/sampling NOT RUN. Release metadata stale.

### EV-0191 — M4-W5 calibration journal feedback + refreshed package/metrics/status; host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T01:04:04-10:00 |
| Commit | `7f88a0e2fe2d2bc804262ec9f292904ff3f11dce` |
| Dirty state | ocs/mvp/STATUS.md, export/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. append calibration completion result to command journal; clean package refresh/verify/freshness/gate; update metrics/status

**Expected:** provider suite PASS; package/freshness/verifier/gate host PASS; acceptance NOT READY

**Actual:** full provider suite ALL PASS; package bytes=206479055 sha=9540a8a947a2f360742b7c7f958474b975eab2132da74e944d2792aa8287a7ac; app b0680cac1e25fdbc8e59689528b6e893b4b0635c1777accb91b84d2cb449474b; provider 180290456350ef014967e4761f300158ddf7ff559355e8d37e2698b2fc92b5a0; host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0191/release-manifest.txt (11cbcb73bf15); evidence/EV-0191/release-package-dev.txt (b264074e5215); evidence/EV-0191/verify.log (94d2dccda566); evidence/EV-0191/release-ready.log (e98c7d23d176); evidence/EV-0191/install-metrics.txt (da410066bd2a); evidence/EV-0191/STATUS.md (1a2b271fcb28); evidence/EV-0191/summary.log (8bf210c58d7f)

**Limitations:** Development package only; device calibration behavior NOT RUN.

### EV-0192 — M4-W5 apply-hand-calibration + refreshed package; host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T01:07:03-10:00 |
| Commit | `88d2fcd67cf0bb23e0e75facdbb233c2cb1feeb1` |
| Dirty state | ocs/mvp/STATUS.md, export/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. parse/apply calibration report preserving tune keys; command/button; tests/build/install/push/integrity; clean package refresh/metrics/status

**Expected:** tests/guards PASS; app install/provider integrity PASS; host package gates PASS; acceptance NOT READY; device behavior NOT RUN

**Actual:** m4-hand-calibration 22 checks; m5-command 17; full suite ALL PASS; app 595982a25f9b5776a21d143fb33aa65b811f08302ac3f6d60548ee204591181b installed; provider 50cd776b2f7ab882171ebddd735e406e504eafb77fc3cf3d961e68dc4667a803 (98,928 bytes) pushed + integrity PASS; package bytes=206483529 sha=4e1d99823e79c3aa813b0cf3aad1ff0a3aade1f811f6d662b85643e0c87c9ef5; host gates PASS; acceptance NOT READY; device apply behavior NOT RUN.

**Artifacts:** evidence/EV-0192/provider-tests-calibapply2.log (4cb2731ba9ad); evidence/EV-0192/ev-calibapply-integrity.log (07de03090c0a); evidence/EV-0192/release-manifest.txt (fd2374427e78); evidence/EV-0192/release-package-dev.txt (bff86a120c9e); evidence/EV-0192/verify.log (c42d84009d53); evidence/EV-0192/release-ready.log (243429e4d8d6); evidence/EV-0192/install-metrics.txt (dba439011071); evidence/EV-0192/STATUS.md (bc12a66f6a5d); evidence/EV-0192/summary.log (e2530a3606be)

**Limitations:** Host apply/report tests only; device calibration/apply behavior NOT RUN. Development package only.

### EV-0193 — M5 targeted reset input tuning button; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T01:08:44-10:00 |
| Commit | `6ce5b900c0793fc979f77c77dc7656273a6a05fa` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add confirmation button resetting only input tune + queue reload-input; build/install; verify provider

**Expected:** shell build/install PASS; provider unchanged; device UI NOT RUN

**Actual:** shell builds; app f1ae3749… installed; provider 50cd776b… integrity PASS; device locked so UI NOT RUN.

**Artifacts:** evidence/EV-0193/shell-resetinput-build.log (cfa6ee6a1020); evidence/EV-0193/ev-resetinput-integrity.log (07de03090c0a); evidence/EV-0193/latest-build-identity.txt (0572845fba0c); evidence/EV-0193/summary.log (462cc2e2b6c7)

**Limitations:** UI only; device interaction NOT RUN. Package metadata stale.

### EV-0194 — M6 refreshed package/metrics/status to targeted-reset build; host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T01:09:46-10:00 |
| Commit | `d215cc8937d4d4a2d182303f27f186df78d93a93` |
| Dirty state | ocs/mvp/STATUS.md, export/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean package refresh/verify/freshness/release-ready; update metrics/STATUS

**Expected:** host/package/freshness/device PASS; acceptance NOT READY

**Actual:** package bytes=206486820 sha=efe71843f71e669e4e6164fab39c8cafcf144fb6d75917006918121f3b737cf5; app=f1ae3749de4ff230b0a396f7bad14e228853ad544108386d32af920b1b422113; provider=50cd776b2f7ab882171ebddd735e406e504eafb77fc3cf3d961e68dc4667a803; host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0194/release-manifest.txt (46adc17a3646); evidence/EV-0194/release-package-dev.txt (23380563a661); evidence/EV-0194/verify.log (28d694e5457a); evidence/EV-0194/release-ready.log (67029e578b4e); evidence/EV-0194/install-metrics.txt (55946e7964bf); evidence/EV-0194/STATUS.md (02b217e66034); evidence/EV-0194/summary.log (1f2383da3f87)

**Limitations:** Development package only; device gates NOT RUN.

### EV-0195 — M4 raw-gesture diagnostics summary; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T01:11:21-10:00 |
| Commit | `0e1c17acc10fef252e38d6fd23d03ebd2451b348` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionInput.java, provider/src/main/java/dev/vrmc/provider/VisionStatusJson.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionInputTest.java, provider/tests/dev/vrmc/provider/VisionStatusJsonFuzzTest.java, provider/tests/dev/vrmc/provider/VisionStatusJsonTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add gestureSummary to engine/status/launcher; tests/guards/build/install/push/integrity

**Expected:** input/summary tests PASS; guard PASS; app install/provider integrity PASS; device behavior NOT RUN

**Actual:** m4-input 187 checks; status-json tests PASS; guard checked=18; full suite ALL PASS; app 7d36ce9e… installed; provider 27155fd1… pushed + integrity PASS; device locked so gesture telemetry behavior NOT RUN.

**Artifacts:** evidence/EV-0195/provider-tests-gestures2.log (4d5b675b62aa); evidence/EV-0195/status-fields-gestures.log (29425c5a8aa6); evidence/EV-0195/ev-gestures-integrity.log (395142fdfedb); evidence/EV-0195/latest-build-identity.txt (97e2f34c09c6); evidence/EV-0195/summary.log (04b3fe5dd461)

**Limitations:** Diagnostics only; device behavior NOT RUN. Package metadata needs refresh.

### EV-0196 — M4/M5 release-input panic command/button; installed (host PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T01:13:50-10:00 |
| Commit | `70c5ef26fee0dd5f51c02062e4cfcb4685f49faf` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionCommandFile.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionCommandFileTest.java, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add release-input command resetting gesture engine/bindings/hotbar/pulse; launcher button; tests/build/install/push/integrity

**Expected:** command tests PASS; provider suite PASS; app install/provider integrity PASS; device behavior NOT RUN

**Actual:** m5-command 18 checks; full provider suite ALL PASS; shell builds; app cf231fc7… installed; provider 4587b5d2… (99576 bytes) pushed + integrity PASS; device locked so behavior NOT RUN.

**Artifacts:** evidence/EV-0196/provider-tests-releaseinput.log (378de1499365); evidence/EV-0196/shell-releaseinput-build.log (cfa6ee6a1020); evidence/EV-0196/ev-releaseinput-integrity.log (312e8988082c); evidence/EV-0196/latest-build-identity.txt (0e9d79ac4360); evidence/EV-0196/summary.log (93c23216e7f3)

**Limitations:** Safety command only; device behavior NOT RUN. Package metadata needs refresh.

### EV-0197 — M6 round-100 refresh to release-input build; host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T01:14:53-10:00 |
| Commit | `990a325013aae5544e11e70945a842261489d3bc` |
| Dirty state | ocs/mvp/STATUS.md, export/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean package refresh/verify/freshness/release-ready; update metrics/STATUS

**Expected:** host/package/freshness/device PASS; acceptance NOT READY

**Actual:** package bytes=206493046 sha=7e9e608ce8f5f53a857fff8bd87f1ba46cf39be9ce0aeebe34b333303bbe68bd; app=cf231fc74d407789e7de97d7767b4cd813bef1a82b198fa8ab3bbc39d4b701ab; provider=4587b5d2e0a894c4c314a6b8de7715b6829c58fcf05539aefd7fb2516b35a576; host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0197/release-manifest.txt (7223e490e05d); evidence/EV-0197/release-package-dev.txt (793c4cf0da62); evidence/EV-0197/verify.log (354370342aa0); evidence/EV-0197/release-ready.log (845fab935a22); evidence/EV-0197/install-metrics.txt (3cd7f6cb1351); evidence/EV-0197/STATUS.md (ad13a2134239); evidence/EV-0197/summary.log (9b2bdd28ab12)

**Limitations:** Development package only; device gates NOT RUN.

### EV-0198 — M5/M6 in-headset acceptance checklist; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T01:16:51-10:00 |
| Commit | `12a58512b7926a635eecff05e5fc46a5a090137e` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add acceptance checklist UI/persistence/diagnostics entry; build/install

**Expected:** shell build/install PASS; provider unchanged; device checklist interaction NOT RUN

**Actual:** shell builds; app 1990b20b… installed; provider 4587b5d2… integrity PASS; device locked so checklist UI NOT RUN.

**Artifacts:** evidence/EV-0198/shell-checklist-build.log (cfa6ee6a1020); evidence/EV-0198/ev-checklist-integrity.log (312e8988082c); evidence/EV-0198/latest-build-identity.txt (dfa4dcec20b0); evidence/EV-0198/summary.log (d31dee047ca2)

**Limitations:** UI/persistence only; device interaction/export NOT RUN. Package metadata stale.

### EV-0199 — M5/M6 checklist Markdown summary export; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T01:18:41-10:00 |
| Commit | `6e04285bb9542f413e95a368f0e420102056f415` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. write Markdown summary alongside checklist JSON; add diagnostics entry; build/install

**Expected:** shell build/install PASS; provider unchanged; device interaction NOT RUN

**Actual:** shell builds; app 73dee838… installed; provider unchanged + integrity PASS; device locked so save/export interaction NOT RUN.

**Artifacts:** evidence/EV-0199/shell-checklistmd-build.log (cfa6ee6a1020); evidence/EV-0199/ev-checklistmd-integrity.log (312e8988082c); evidence/EV-0199/latest-build-identity.txt (9c1c7dd301a4); evidence/EV-0199/summary.log (75d29b4afb6c)

**Limitations:** UI/export only; device interaction NOT RUN. Package metadata stale.

### EV-0200 — M5/M6 checklist status counts; installed (build PASS; device NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T01:20:05-10:00 |
| Commit | `e38293a09119c4e6f26562c64fd9119a23c244bc` |
| Dirty state | xport/latest-build-identity.txt, runtime/native-shell/Sources/Shell.swift, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/Project/arm64-apple-xros.swiftsourceinfo, runtime/native-shell/build/VRMCShell.framework/Modules/VRMCShell.swiftmodule/arm64-apple-xros.swiftmodule, runtime/native-shell/build/VRMCShell.framework/VRMCShell |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add PASS/PARTIAL/FAIL/NOT RUN count header to checklist; build/install; verify provider

**Expected:** shell build/install PASS; provider unchanged; device UI NOT RUN

**Actual:** shell builds; app a4663e16… installed; provider 4587b5d2… integrity PASS; device locked so checklist interaction NOT RUN.

**Artifacts:** evidence/EV-0200/shell-checklist-summary-build.log (cfa6ee6a1020); evidence/EV-0200/ev-checklist-summary-integrity.log (312e8988082c); evidence/EV-0200/latest-build-identity.txt (f3c45cbd71df); evidence/EV-0200/summary.log (3eae1aff0533)

**Limitations:** UI only; device interaction NOT RUN. Package metadata stale.

### EV-0201 — M6 refreshed package/metrics/status to checklist-summary build; host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T01:21:08-10:00 |
| Commit | `783e19622af9b8d9f1b4ee000e8de777f1f7346e` |
| Dirty state | ocs/mvp/STATUS.md, export/install-metrics-dev.txt, export/release-manifest-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. clean package refresh/verify/freshness/release-ready; update metrics/STATUS

**Expected:** host/package/freshness/device PASS; acceptance NOT READY

**Actual:** package bytes=206538366 sha=4d9141f05a8993a0c5242534df4ff102aaefe6fffd7ae555bf82c06dd9e3d2af; app=a4663e16b8dc57d16c67ccd72be770f15f2846dc0fdb3c913fa5203283ba7bfb; provider=4587b5d2e0a894c4c314a6b8de7715b6829c58fcf05539aefd7fb2516b35a576; host gates PASS; acceptance NOT READY.

**Artifacts:** evidence/EV-0201/release-manifest.txt (cc8faed03411); evidence/EV-0201/release-package-dev.txt (a66d66496612); evidence/EV-0201/verify.log (370a5ae02a1a); evidence/EV-0201/release-ready.log (3c4b46a5f2c0); evidence/EV-0201/install-metrics.txt (0d5fcef5cd00); evidence/EV-0201/STATUS.md (4b87ad1fad2c); evidence/EV-0201/summary.log (c4618df67295)

**Limitations:** Development package only; device gates NOT RUN.

### EV-0202 — Final consolidated host regression; all host gates PASS, acceptance NOT READY

| Field | Value |
|---|---|
| Date | 2026-11-02T01:22:43-10:00 |
| Commit | `9ebc23d68c914a8fc99a7404dfe53ec044caf9f3` |
| Dirty state | clean |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. run shell/provider/bridge/M4 selfcheck/release check/package freshness/verifier/device integrity/release gate/acceptance

**Expected:** all host suites/gates PASS; acceptance correctly NOT READY

**Actual:** all host suites/gates PASS; release-ready host PASS; acceptance 0/22 NOT READY; device AC/K/H NOT RUN.

**Artifacts:** evidence/EV-0202/shell-build.log (cfa6ee6a1020); evidence/EV-0202/provider-tests.log (3d00c1122605); evidence/EV-0202/bridge-tests.log (d22c13b03ab2); evidence/EV-0202/m4-selfcheck.log (a4e3a48d909a); evidence/EV-0202/release-check.log (4b1126b49c04); evidence/EV-0202/release-ready.log (11bb567e3724); evidence/EV-0202/acceptance.log (8c39c69a7abe); evidence/EV-0202/device-integrity.log (312e8988082c); evidence/EV-0202/timeline.txt (af5c43a1de1d); evidence/EV-0202/summary.log (57e1ea15b670)

**Limitations:** Consolidated host-only regression; device acceptance remains the only blocker.

### EV-0203 — M6 device acceptance checklist importer + host fixture tests

| Field | Value |
|---|---|
| Date | 2026-11-02T01:26:42-10:00 |
| Commit | `528dc3cc27f2d8ac8e685d93f8a44728b48c31cd` |
| Dirty state | export/device-acceptance-report.md, export/device-acceptance-status.txt, scripts/m6_import_device_checklist.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add checklist import (pull/input), JSON validation, Markdown/machine report; fix arg-loop hang; host fixture tests normal/FAIL/invalid

**Expected:** normal import reports correctly; FAIL/invalid handled; device pull NOT RUN

**Actual:** normal rows=3 PASS=1 PARTIAL=1 NOT_RUN=1; FAIL exit10 warning; bogus status rejected; missing input safe; device pull NOT RUN.

**Artifacts:** evidence/EV-0203/m6_import_device_checklist.sh (de385365e481); evidence/EV-0203/checklist-import-test.log (2f7d0c8a0dc0); evidence/EV-0203/device-acceptance-report.md (3c96f9bf63da); evidence/EV-0203/device-acceptance-status.txt (ba062b0033de); evidence/EV-0203/checklist-import-fail.log (15aafe8707b9); evidence/EV-0203/checklist-import-bad.log (58a84331c69e); evidence/EV-0203/summary.log (8b68dc4f5d4e)

**Limitations:** Host fixture evidence only; actual device checklist pull NOT RUN.

### EV-0204 — M6 release gate device-checklist FAIL check + fixtures

| Field | Value |
|---|---|
| Date | 2026-11-02T01:27:36-10:00 |
| Commit | `ea8d4cca83e637add5b82e572df8d52a9e0f2773` |
| Dirty state | xport/device-acceptance-report.md, export/device-acceptance-status.txt, scripts/m6_release_ready.sh, scripts/m6_check_device_checklist.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add checklist gate script/integration; test missing/partial/fail/pass; remove fixture exports; run release-ready

**Expected:** FAIL blocks release; incomplete noted; missing skipped; no fake device results

**Actual:** fail exit1/partial exit2/missing exit0/pass exit0; release-ready SKIPs with no device import; fixtures removed; host gates PASS otherwise, acceptance NOT READY.

**Artifacts:** evidence/EV-0204/m6_check_device_checklist.sh (aea93329d6f9); evidence/EV-0204/m6_release_ready.sh (ac435cb16298); evidence/EV-0204/checklist-fail.txt (a80208573f4c); evidence/EV-0204/checklist-partial.txt (ba062b0033de); evidence/EV-0204/release-ready-checklist2.log (ac43b391922f); evidence/EV-0204/summary.log (cc0b263763d6)

**Limitations:** Host fixtures only; device checklist/acceptance remains NOT RUN.

### EV-0206 — M6 K6 JRE-pruned lite package measured/verified; device NOT RUN

| Field | Value |
|---|---|
| Date | 2026-11-02T01:29:12-10:00 |
| Commit | `9a87b84c5ea5f326cfb5e443bfefdc471eff4c5d` |
| Dirty state | clean |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. stage lite app with VRMC_KEEP_JRE=25; build clean measurement package; verify hashes; keep canonical app unchanged

**Expected:** lite app signs; package verifies; sizes measured; canonical unchanged; device launch NOT RUN

**Actual:** lite app 245,747,712 bytes; lite package 89,919,699 bytes sha256 db3f6a48… verifier PASS; canonical unchanged; device launch NOT RUN.

**Artifacts:** evidence/EV-0206/package2.log (357acc332829); evidence/EV-0206/release-check.log (4b1126b49c04); evidence/EV-0206/verify2.log (7677fdd109be); evidence/EV-0206/zip.sha256 (20174302ee24); evidence/EV-0206/summary.log (20456051ada4)

**Limitations:** K6 experiment only; lite app not installed and not in release identity/metadata. Device launch behavior NOT RUN.

### EV-0207 — M6 read-only device JRE probe (java-25 used, external runtime dir empty)

| Field | Value |
|---|---|
| Date | 2026-11-02T01:30:36-10:00 |
| Commit | `fbe65a777e3293aaee4720f147a13128ec7684b9` |
| Dirty state | clean |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. list device runtime/instance files; pull launcher prefs/profiles + hs_err; inspect selected profile and JRE paths

**Expected:** identify actual JRE/profile used without launching; lite safety assessment; device launch still NOT RUN

**Actual:** Documents/java_runtimes empty; selected fabric-loader-0.20.1-26.2; hs_err JRE 25.0.4 loaded from app-bundled java-25; prefs internal 25. Lite launch still NOT RUN; canonical unchanged.

**Artifacts:** evidence/EV-0207/jre-probe-summary.txt (4687f1b78744); evidence/EV-0207/launcher_preferences.plist (9953b14a8749); evidence/EV-0207/launcher_profiles.json (fdde20e56ccf); evidence/EV-0207/summary.log (1c8b43546cdf)

**Limitations:** Read-only device evidence; no launch. Lite variant remains experimental.

### EV-0208 — M6 lite JRE pruning: binary reference analysis (host; lite launch NOT RUN)

| Field | Value |
|---|---|
| Date | 2026-11-02T01:31:02-10:00 |
| Commit | `b4d2b322a36e5127b017be615d95762d1fbe3884` |
| Dirty state | clean |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. inspect app/launcher strings for JRE dir hardcoding; compare full vs lite binaries

**Expected:** no hardcoded old JRE paths; dynamic version selection; lite launch NOT RUN

**Actual:** launcher builds java_runtimes/java-%@-openjdk dynamically; no hardcoded 8/17/21 refs; lite launch NOT RUN.

**Artifacts:** evidence/EV-0208/summary.log (6fe2c483983f)

**Limitations:** Host analysis only; lite app still experimental/uninstalled.

### EV-0209 — DEVICE BUG FIX: VR init IllegalFormatConversionException (f != Long)

| Field | Value |
|---|---|
| Date | 2026-11-02T06:13:02-10:00 |
| Commit | `c9954d07049705edba70842fa24068ff75fe0b3e` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/run_tests.sh, provider/src/main/java/dev/vrmc/provider/VisionLogFormat.java, provider/tests/dev/vrmc/provider/VisionLogFormatTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. diagnose device stack; fix printf type in startup locomotion log via tested formatter; build/test/push/integrity

**Expected:** provider suite PASS; provider pushed/verified; device retest required

**Actual:** m4-log-format 6 checks; full provider suite ALL PASS; provider 5fe2a842… (100378 bytes) pushed + device integrity PASS; retest required.

**Artifacts:** evidence/EV-0209/VisionLogFormat.java (6d406ab9248f); evidence/EV-0209/VisionLogFormatTest.java (d32fde68864a); evidence/EV-0209/provider-tests-initfix.log (89fd2651dae8); evidence/EV-0209/repro-initfix.log (a17f7a98146c); evidence/EV-0209/ev-initfix-integrity.log (e506f97bcc55); evidence/EV-0209/latest-build-identity.txt (7778b22f5c01); evidence/EV-0209/summary.log (7b0797363e9f)

**Limitations:** Device error reproduced by user; host fix verified, but VR init success after fix requires the user to relaunch the game.

### EV-0210 — DEVICE BUG FIX #2: init-time status write NPE (vrPlayer null)

| Field | Value |
|---|---|
| Date | 2026-11-02T06:21:32-10:00 |
| Commit | `d225b4c89324d2f2072a0776983c895d25a4e6de` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull latest game log; diagnose NPE; remove init status write; guard bow/climb fields; tests/build/push/integrity

**Expected:** provider suite PASS; provider pushed/verified; device retest required

**Actual:** NPE fixed in code; full provider suite ALL PASS; provider adeca91c… (100374 bytes) pushed + integrity PASS; retest required.

**Artifacts:** evidence/EV-0210/latest-game.log (a3a6c39bd93e); evidence/EV-0210/provider-tests-npefix.log (9c784ede159d); evidence/EV-0210/repro-npefix.log (dc9269366bdd); evidence/EV-0210/ev-npefix-integrity.log (d408147073b9); evidence/EV-0210/latest-build-identity.txt (9687736be827); evidence/EV-0210/summary.log (c75b4dd8b66b)

**Limitations:** Both device-found init issues fixed; VR init success after fix requires relaunch. The format fix was installed and did advance init before this second crash.

### EV-0211 — DEVICE BUG FIX #3: first status write NPE with null player

| Field | Value |
|---|---|
| Date | 2026-11-02T16:02:33-10:00 |
| Commit | `955d122df708f7dc25d96ef80050bb7a461ecfd8` |
| Dirty state | xport/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull latestlog; diagnose ClimbTracker isClimbeyClimb null player in auto-status; guard; tests/build/push/integrity

**Expected:** provider suite PASS; provider pushed/verified; device retest required

**Actual:** NPE fixed in code; full provider suite ALL PASS; provider e9f97a60… (100383 bytes) pushed + integrity PASS; retest required.

**Artifacts:** evidence/EV-0211/latestlog-before-fix.txt (b42e2a901e62); evidence/EV-0211/provider-tests-playerfix.log (b91aa0360362); evidence/EV-0211/repro-playerfix.log (6eb03d06643f); evidence/EV-0211/ev-playerfix-integrity.log (8edb425a7136); evidence/EV-0211/latest-build-identity.txt (f55139f764db); evidence/EV-0211/summary.log (0f1cd389d4c0)

**Limitations:** Init now succeeds on device; this fix targets the first-update status write before a player exists. Relaunch required.

### EV-0212 — DEVICE: first successful launched/played session; clean shutdown (partial acceptance)

| Field | Value |
|---|---|
| Date | 2026-11-02T16:08:20-10:00 |
| Commit | `3e72231c7a586fa1da5e5475d45e365eebddb7a8` |
| Dirty state | cripts/m6_device_diagnostics_pull.sh |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull latestlog/status/shutdown/compositor/shell/thermal after operator play session; scan errors; verify clean teardown and performance

**Expected:** device launch/presentation/input smoke works; no exceptions; clean shutdown; full checklist still pending

**Actual:** operator played; init/renderer/hands/input/display views OK; no exceptions; 12199 presented frames; clean destroy-complete; p50 8.34ms/p95 9.24ms; checklist pending.

**Artifacts:** evidence/EV-0212/Documents_latestlog.txt (4763d1d0b93c); evidence/EV-0212/Documents_instances_default_vrmc-status.json (4b1e0acd889f); evidence/EV-0212/Documents_instances_default_vrmc-shutdown.log (990c9220330c); evidence/EV-0212/Documents_vrmc-compositor.log (88fc9d371dbe); evidence/EV-0212/Documents_vrmc-shell.log (3bf433a49ebb); evidence/EV-0212/Documents_vrmc-thermal.log (1771aa20bd29); evidence/EV-0212/m6_device_diagnostics_pull.sh (95b6a0e1529a); evidence/EV-0212/summary.log (139f4493c945)

**Limitations:** Device behavior evidence for this session; full H/AC/K checklist and repeated sessions still required. Pull script fixed to include Documents/latestlog.txt and checklist/calibration files.

### EV-0213 — M7 accepted MENU_RIGHT_PINCH dataset from 31s recording

| Field | Value |
|---|---|
| Date | 2026-11-02T17:36:04-10:00 |
| Commit | `9b28a2ea84d3c694027ba93da55a6b63a64a4448` |
| Dirty state | gitignore, runtime/gesture-lab/Sources/ContentView.swift, runtime/gesture-lab/Sources/LabModel.swift, scripts/m7_analyze_lab_data.py, scripts/m7_pull_lab_data.sh, export/gesturelab-data/ |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull lab recordings; inspect duration/labels/tracking; relabel IDLE source as MENU_RIGHT_PINCH; measure pinch distribution/events; update analyzer/default label/reinstall

**Expected:** >=30s recording, right-hand tracked, clear pinch events; dataset accepted for threshold tuning

**Actual:** 31.23s, 563 samples, right 563/563; 42 pinch events; pinch p05/p50/p95=0.006/0.083/0.148; accepted.

**Artifacts:** evidence/EV-0213/MENU_RIGHT_PINCH-summary.md (1ebdc6e30070); evidence/EV-0213/gesturelab-analysis.md (eba23654ec53); evidence/EV-0213/m7_analyze_lab_data.py (0d1b58fe7c50); evidence/EV-0213/m7_pull_lab_data.sh (b62bae6831b6); evidence/EV-0213/summary.log (4d17ff0b1740)

**Limitations:** Raw JSONL remains local (gitignored) under export/gesturelab-data/accepted. Device A/B still required.

### EV-0214 — Gesture Lab: fix left-hand sampling gap and fist metric (data quality)

| Field | Value |
|---|---|
| Date | 2026-11-02T17:39:21-10:00 |
| Commit | `61c1fac02e6b95ee2e8b20baa49eb5beee1b82ed` |
| Dirty state | ERIFY.md, runtime/gesture-lab/Sources/LabModel.swift, runtime/gesture-lab/Sources/LabMotion.swift, scripts/m7_analyze_lab_data.py, export/gesturelab-data/gesturelab-analysis.md, export/gesturelab-data/gesturelab.log |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. analyze left-fist recording; fix recording trigger; replace fist ratio; update analyzer; rebuild/install

**Expected:** left-hand actions capture continuously; fist metric separates fist/open; re-record needed

**Actual:** trigger fixed (either hand); fist ratio now curl ratio; analyzer re-derives; app reinstalled; existing ESCAPE data has gap and is not accepted.

**Artifacts:** evidence/EV-0214/m7_analyze_lab_data.py (fddb2a9ab2da); evidence/EV-0214/gesturelab-analysis.md (24fa6bb35752); evidence/EV-0214/summary.log (c7ecde5395e5)

**Limitations:** Existing ESCAPE_LEFT_FIST recording is sparse due to the fixed trigger; re-record after app update.

### EV-0215 — M7 accepted ESCAPE_LEFT_FIST dataset + prominent label UI

| Field | Value |
|---|---|
| Date | 2026-11-02T17:44:24-10:00 |
| Commit | `f1792a7b4e3bcdea0c77653e8dfc0530f3efb2b2` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/ContentView.swift, export/gesturelab-data/accepted/ESCAPE_LEFT_FIST-summary.md, export/gesturelab-data/gesturelab-analysis.md, export/gesturelab-data/gesturelab.log |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull new recording; detect left-fist-only content; canonicalize/relabel; validate fist metric/events; improve label UI; rebuild/install

**Expected:** left fist data with both-arm visibility, clean events; label ambiguity removed

**Actual:** 31.18s/561 samples, left 561/561, 146 closed frames, 24 left-fist events; relabelled from MENU_RIGHT_PINCH; app label UI prominent + 60s button installed.

**Artifacts:** evidence/EV-0215/ESCAPE_LEFT_FIST-summary.md (d57a4e4f6c48); evidence/EV-0215/gesturelab-analysis.md (fc9aa461b912); evidence/EV-0215/gesturelab-build14.log (9959578879d9); evidence/EV-0215/summary.log (d9aa57682b92)

**Limitations:** Raw JSONL local/gitignored. Device A/B still required.

### EV-0216 — M7 accepted WALK_BOTH_FISTS dataset + head motion capture

| Field | Value |
|---|---|
| Date | 2026-11-02T17:49:20-10:00 |
| Commit | `3fef944b96dae189a0464935cf61212efad0d47d` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/WALK_BOTH_FISTS-summary.md, export/gesturelab-data/gesturelab-analysis.md, export/gesturelab-data/gesturelab.log |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate walk recording; compute fist percentages, relative wrist swing correlation, head ranges; canonicalize; set next default; reinstall

**Expected:** both fists held, alternating arm swing, head tracked; valid walk dataset

**Actual:** 30.97s, 558 samples, both fists 75%, z correlation -0.73, ~25 cycles, head tracked 558/558; accepted.

**Artifacts:** evidence/EV-0216/WALK_BOTH_FISTS-summary.md (8c4197d0f72d); evidence/EV-0216/gesturelab-analysis.md (80eefbe72196); evidence/EV-0216/m7_analyze_lab_data.py (fddb2a9ab2da); evidence/EV-0216/summary.log (2409f630222c)

**Limitations:** Raw JSONL local/gitignored. Device A/B pending.

### EV-0217 — M7 accepted JUMP_HEAD dataset (29 head-rise events)

| Field | Value |
|---|---|
| Date | 2026-11-02T17:52:15-10:00 |
| Commit | `19c48a9f73464dbeb8a711ef57ae3e8306c9b6d5` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/JUMP_HEAD-summary.md, export/gesturelab-data/gesturelab-analysis.md, export/gesturelab-data/gesturelab.log |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate jump recording; compute head Y distribution, adaptive-baseline excursions, amplitudes/durations/velocity; canonicalize; set next default

**Expected:** head tracked, repeated clear head rises; threshold candidate

**Actual:** 80.03s/923 samples; head 923/923; 29 events >0.08m; peaks 0.11-0.30m; vel p95 1.51; accepted.

**Artifacts:** evidence/EV-0217/JUMP_HEAD-summary.md (bcd5de3d4186); evidence/EV-0217/gesturelab-analysis.md (e696e2e6348d); evidence/EV-0217/summary.log (2bca5a8c504a)

**Limitations:** Raw JSONL local/gitignored; device A/B pending.

### EV-0218 — M7 accepted SNEAK_HEAD dataset (5 headset-lower events)

| Field | Value |
|---|---|
| Date | 2026-11-02T17:55:51-10:00 |
| Commit | `61a3e4d139c00d7ff4920f327a87683a405bfdcb` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/SNEAK_HEAD-summary.md, export/gesturelab-data/gesturelab-analysis.md, export/gesturelab-data/gesturelab.log |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate sneak recording; compute downward excursions/depths/durations/velocity; canonicalize; set next default

**Expected:** head tracked, clear downward displacement; threshold candidate

**Actual:** 31.00s/524 samples; head 524/524; 5 events >0.10m; depths 0.10-0.25m; accepted with long-hold caveat.

**Artifacts:** evidence/EV-0218/SNEAK_HEAD-summary.md (3a9974a314ff); evidence/EV-0218/gesturelab-analysis.md (bb38a7e626f6); evidence/EV-0218/summary.log (be4f6a6908fc)

**Limitations:** Raw JSONL local/gitignored; long holds; device A/B pending.

### EV-0219 — M7 accepted TELEPORT_LEFT_PINCH datasets (16 left-pinch events)

| Field | Value |
|---|---|
| Date | 2026-11-02T17:59:22-10:00 |
| Commit | `c96a31091b6512294562fbaad2854f5710003d9a` |
| Dirty state | gitignore, VERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, scripts/m7_analyze_lab_data.py, export/gesturelab-data/accepted/TELEPORT_LEFT_PINCH-summary.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull two teleport recordings; analyze left pinch stats/events; canonicalize both; add left-pinch analyzer columns; set next default

**Expected:** left pinch hold/release data, multiple events; teleport semantics supported

**Actual:** 31.09s/551 + 38.97s/703; 16 left-pinch events; accepted; analyzer left-pinch added.

**Artifacts:** evidence/EV-0219/TELEPORT_LEFT_PINCH-summary.md (83440b275daf); evidence/EV-0219/gesturelab-analysis.md (431701306aff); evidence/EV-0219/m7_analyze_lab_data.py (a9fbbcc6fe22); evidence/EV-0219/summary.log (c11e670f351b)

**Limitations:** Raw JSONL local/gitignored; device A/B pending.

### EV-0220 — M7 accepted ATTACK_RIGHT_SWING dataset

| Field | Value |
|---|---|
| Date | 2026-11-02T18:03:24-10:00 |
| Commit | `d60dfd37dfe29e4407749dea88e26ee329dd3d8a` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/ATTACK_RIGHT_SWING-summary.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate right swing recording; compute wrist speed/acceleration/event counts; canonicalize; set next default

**Expected:** one-handed fast swings separable from walk/idle; valid dataset

**Actual:** 31.41s/520 samples; right 503 tracked; speed p95 2.97, accel p95 21.39; ~28 swing events; accepted.

**Artifacts:** evidence/EV-0220/ATTACK_RIGHT_SWING-summary.md (ed62b10bde74); evidence/EV-0220/gesturelab-analysis.md (81502ee59a1e); evidence/EV-0220/summary.log (e86c003c0a65)

**Limitations:** Raw JSONL local/gitignored; device A/B pending.

### EV-0221 — M7 accepted EAT_RIGHT_HAND_HEAD dataset

| Field | Value |
|---|---|
| Date | 2026-11-02T18:05:26-10:00 |
| Commit | `2f82e55e4d8f86c3c017d104ce971bf87aa2e3d3` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/EAT_RIGHT_HAND_HEAD-summary.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate eat recording; compute wrist-to-head distance/events; canonicalize; set next default

**Expected:** right hand repeated near-head holds; valid dataset

**Actual:** 30.85s/455 samples; 181 frames <0.28m; 11 events; accepted.

**Artifacts:** evidence/EV-0221/EAT_RIGHT_HAND_HEAD-summary.md (0cf484a32b41); evidence/EV-0221/gesturelab-analysis.md (7fa5f6438c7d); evidence/EV-0221/summary.log (8282db4044c4)

**Limitations:** Raw JSONL local/gitignored; device A/B pending.

### EV-0222 — M7 accepted BOW_BOTH_FISTS dataset

| Field | Value |
|---|---|
| Date | 2026-11-02T18:07:48-10:00 |
| Commit | `3b624b7c5488229bf16376df2c9f93c6e0507b39` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/BOW_BOTH_FISTS-summary.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate bow recording; compute fist/separation/draw cycles; canonicalize; set next default

**Expected:** both hands, draw/release cycles, back-hand release; valid dataset

**Actual:** 46.66s/819 samples; 16 separation cycles; separation max 1.049m; accepted.

**Artifacts:** evidence/EV-0222/BOW_BOTH_FISTS-summary.md (c0c58f106563); evidence/EV-0222/gesturelab-analysis.md (3db37ac67030); evidence/EV-0222/summary.log (703b3df7b8b3)

**Limitations:** Raw JSONL local/gitignored; device A/B pending.

### EV-0223 — M7 accepted PLACE_RIGHT_PINCH short-pinch dataset

| Field | Value |
|---|---|
| Date | 2026-11-02T19:26:31-10:00 |
| Commit | `7ba9fbdd08493ed27a6ab324d27e3faf413bbf7d` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/PLACE_RIGHT_PINCH-summary.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate place recording; split short vs long pinch events; canonicalize; set next default

**Expected:** mostly short place pinches; long holds separated

**Actual:** 59.19s/1062 samples; 76 events, 72 short <0.35s, 4 long outliers; accepted.

**Artifacts:** evidence/EV-0223/PLACE_RIGHT_PINCH-summary.md (efe5488832d0); evidence/EV-0223/gesturelab-analysis.md (5fa6a276838f); evidence/EV-0223/summary.log (cc7974535947)

**Limitations:** Raw JSONL local/gitignored; device A/B pending.

### EV-0224 — M7 accepted BREAK_RIGHT_PINCH_HOLD dataset

| Field | Value |
|---|---|
| Date | 2026-11-02T19:30:22-10:00 |
| Commit | `635fbe80e9409e6ca20829dbdfedc1f4463ff31d` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/BREAK_RIGHT_PINCH_HOLD-summary.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate break hold recording; compute durations; canonicalize; set next default

**Expected:** held pinches only, 1-2s durations; valid break dataset

**Actual:** 31.11s/588 samples; 7 held events 1.21-10.44s; no short taps; accepted.

**Artifacts:** evidence/EV-0224/BREAK_RIGHT_PINCH_HOLD-summary.md (c7b9142e9fd0); evidence/EV-0224/gesturelab-analysis.md (c7681172edb2); evidence/EV-0224/summary.log (c0023f86cf4d)

**Limitations:** Raw JSONL local/gitignored; device A/B pending.

### EV-0225 — M7 accepted INVENTORY_BOTH_FISTS dataset

| Field | Value |
|---|---|
| Date | 2026-11-02T19:33:03-10:00 |
| Commit | `f124b9c5b6996699f7cf0c7c039c6f441a1114a8` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/INVENTORY_BOTH_FISTS-summary.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate inventory recording; detect both-fist tap runs; canonicalize; set next default

**Expected:** short both-fist taps separated from sustained walk; valid dataset

**Actual:** 31.14s/562 samples; 24 both-fist runs 0.06-0.28s; both hands tracked; accepted.

**Artifacts:** evidence/EV-0225/INVENTORY_BOTH_FISTS-summary.md (b8832fee8887); evidence/EV-0225/gesturelab-analysis.md (18fadbd49f56); evidence/EV-0225/summary.log (a1ba2c133e76)

**Limitations:** Raw JSONL local/gitignored; device A/B pending.

### EV-0226 — M7 accepted HOTBAR_RIGHT_TAP finger-tap dataset

| Field | Value |
|---|---|
| Date | 2026-11-02T19:35:04-10:00 |
| Commit | `a867e40d0e5301987f9eb65ca1edd2a3448b1d80` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, runtime/gesture-lab/Sources/LabModel.swift, export/gesturelab-data/accepted/HOTBAR_RIGHT_TAP-summary.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate hotbar recording; discover finger-tap vs wrist motion; compute index-tip speed/events; canonicalize; set next default

**Expected:** detectable tap separated from idle; valid dataset

**Actual:** 30.94s/558 samples; 22 index-finger tap events 0.05-0.22s; index-tip p95 1.28, p99 2.66; accepted.

**Artifacts:** evidence/EV-0226/HOTBAR_RIGHT_TAP-summary.md (031b859d50f0); evidence/EV-0226/gesturelab-analysis.md (0e7ebc8a4e58); evidence/EV-0226/summary.log (cebe96184d48)

**Limitations:** Raw JSONL local/gitignored; device A/B pending.

### EV-0227 — M7 accepted CLIMB_ALTERNATE dataset; all 14 actions collected

| Field | Value |
|---|---|
| Date | 2026-11-02T19:36:59-10:00 |
| Commit | `2087c23ed848c6115ace883cd8348ecdf21c778c` |
| Dirty state | ERIFY.md, export/gesturelab-data/accepted/gesturelab-analysis.md, export/gesturelab-data/accepted/CLIMB_ALTERNATE-summary.md, export/gesturelab-data/accepted/README.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull/validate climb recording; compute fist/vertical alternation; canonicalize; write accepted-dataset manifest

**Expected:** alternating hand climbs; complete data set

**Actual:** 31.09s/561 samples; both hands tracked; ~15 alternating cycles; all 14 action datasets accepted.

**Artifacts:** evidence/EV-0227/CLIMB_ALTERNATE-summary.md (655b00bfa812); evidence/EV-0227/README.md (a8e5390a0fc0); evidence/EV-0227/summary.log (992e3de17832)

**Limitations:** Raw JSONL local/gitignored; device A/B pending. Next: M7 engine implementation.

### EV-0228 — M7 engine implemented behind mode switch; host PASS, device A/B pending

| Field | Value |
|---|---|
| Date | 2026-11-02T19:44:32-10:00 |
| Commit | `c58d4b85cf48121c04438b511002a8e7833cfd21` |
| Dirty state | ERIFY.md, docs/mvp/M7_GESTURES.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/run_tests.sh, docs/mvp/M7_ENGINE.md, provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java, provider/tests/dev/vrmc/provider/VisionM7GestureTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add VisionM7Gesture + tests; integrate VisionVR dispatch/locomotion; default m7 with m4 fallback; build/provider suite/push/integrity

**Expected:** host suite PASS; m7 default; device A/B not run

**Actual:** provider suite ALL PASS; m7-gesture 23 checks; provider 367aa78a… pushed/integrity PASS; device not tested.

**Artifacts:** evidence/EV-0228/VisionM7Gesture.java (3d308fb0c617); evidence/EV-0228/VisionM7GestureTest.java (457d0c03c1ac); evidence/EV-0228/M7_ENGINE.md (30f0f52d5059); evidence/EV-0228/m7-final-tests.log (c2863847d487); evidence/EV-0228/m7-repro.log (d11ecbfd0f26); evidence/EV-0228/m7-device-integrity.log (f53b7efbd94d); evidence/EV-0228/summary.log (abfc97840631)

**Limitations:** M7 default is a behavior change vs earlier device runs; use gesture.mode=m4 for A/B. No device evidence yet.

### EV-0229 — M7 pre-A/B review: 40 checks, priority fixes, rollback prepared; device A/B NOT RUN

| Field | Value |
|---|---|
| Date | 2026-11-02T19:49:34-10:00 |
| Commit | `a479383415a7efb3b137ba125c25a865637eb3f2` |
| Dirty state | ERIFY.md, docs/mvp/M5_DEVICE_RUN.md, docs/mvp/M7_ENGINE.md, docs/mvp/M7_GESTURES.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java, provider/tests/dev/vrmc/provider/VisionM7GestureTest.java, docs/mvp/M7_PLAN.md, docs/mvp/M7_TEST_MATRIX.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. expand synthetic checks/adjacent priority; fix engine ordering; write test matrix; record GUI/climb/seated/sneak/release timing docs; push provider + m4 rollback tune; verify device integrity

**Expected:** all checks PASS; rollback prepared; device step 0 still required

**Actual:** 40 checks PASS; provider 1c75ae86… pushed/integrity PASS; tune gesture.mode=m4 read back; device playability NOT RUN.

**Artifacts:** evidence/EV-0229/VisionM7GestureTest.java (bbc649467060); evidence/EV-0229/m7-tests7.log (c50e5f774ea8); evidence/EV-0229/M7_TEST_MATRIX.md (8b3649241233); evidence/EV-0229/M7_PLAN.md (d61a73083267); evidence/EV-0229/M7_ENGINE.md (15ad117308c2); evidence/EV-0229/M5_DEVICE_RUN.md (f2a06e3ab811); evidence/EV-0229/integrity.log (b4b45d1ec4a1); evidence/EV-0229/readback.properties (8945a924efe5); evidence/EV-0229/latest-build-identity.txt (8311bb6daeb3); evidence/EV-0229/summary.log (5a427eb019c5)

**Limitations:** Device currently tuned to m4 for rollback step 0. No M7 device behavior evidence yet.

### EV-0230 — Rollback session was M4 (not M7); mode verified; M7 A/B still pending

| Field | Value |
|---|---|
| Date | 2026-11-02T20:30:40-10:00 |
| Commit | `94a46cea89de073f2519c2b6fa86195c10306b59` |
| Dirty state | ERIFY.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull latestlog/tune/status/shutdown; confirm mode; record M4 feedback; switch tune to m7; verify provider

**Expected:** M4 fallback active; switch to m7 for true A/B

**Actual:** log shows gesture mode=m4; M4 actions fired; feedback recorded; tune switched to m7; M7 behavior NOT RUN.

**Artifacts:** evidence/EV-0230/latestlog.txt (8abab158c7f5); evidence/EV-0230/tune-m4.properties (8945a924efe5); evidence/EV-0230/readback-m7.properties (bcd3e7af8ca5); evidence/EV-0230/vrmc-status.json (a87bc3242ed0); evidence/EV-0230/vrmc-shutdown.log (f07919a4f41a); evidence/EV-0230/summary.log (e498dd9fce42)

**Limitations:** Do not attribute the feedback to M7. M7 device A/B starts after relaunch with gesture.mode=m7.

### EV-0231 — M7 immersive entry blocked by crash safe mode; crash count reset

| Field | Value |
|---|---|
| Date | 2026-11-02T20:36:37-10:00 |
| Commit | `54aad33ab7f04c83ce5c95fd1ea51124190d302c` |
| Dirty state | ERIFY.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull latestlog/shell/crash count; diagnose safe mode; reset crash count to 0; verify tune m7

**Expected:** game enters immersive; M7 testable

**Actual:** safe mode suppressed auto VR; M7 init succeeded but immersive not opened; crash count reset; restart required; no M7 behavior test.

**Artifacts:** evidence/EV-0231/vrmc-shell.log (750b30e34832); evidence/EV-0231/latestlog.txt (13447d3d5272); evidence/EV-0231/crash-count-after.txt (5feceb66ffc8); evidence/EV-0231/tune.properties (bcd3e7af8ca5); evidence/EV-0231/summary.log (0cdcaa8ab158)

**Limitations:** Not an M7 engine failure. Restart app, verify immersive, then run M7 menu/escape. Quit cleanly to avoid re-triggering the guard.

### EV-0232 — M7 device step 1: immersive opened; menu/escape actions observed

| Field | Value |
|---|---|
| Date | 2026-11-02T21:51:25-10:00 |
| Commit | `e9dbcfa75029c4328251084be5a93b0d9c700ae5` |
| Dirty state | ERIFY.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. pull latestlog/shell/status/shutdown after first M7 session; verify mode/immersive; count action transitions and hand dropouts

**Expected:** M7 mode active, immersive opened, menu/escape respond

**Actual:** immersive opened; 8 gui clicks + left-fist menu press; attack pulse; no other action transitions; 3 right-hand dropouts; clean destroy-complete.

**Artifacts:** evidence/EV-0232/latestlog.txt (cb16ca54ecba); evidence/EV-0232/vrmc-shell.log (754351492acd); evidence/EV-0232/vrmc-status.json (3f77edf3e895); evidence/EV-0232/vrmc-shutdown.log (78951ba894ee); evidence/EV-0232/vrmc-crash-count.txt (6b86b273ff34); evidence/EV-0232/summary.log (21fb78bf28ef)

**Limitations:** Operator qualitative score not captured; step 1 is menu/escape. Continue A/B at step 2 inventory.

### EV-0233 — Operator clarification: M7 only launch/clean-quit verified; actions NOT RUN

| Field | Value |
|---|---|
| Date | 2026-11-02T21:52:43-10:00 |
| Commit | `91c5ad4dad77c3edf4c5ca1ba91beb649dcb4d8b` |
| Dirty state | ERIFY.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. record operator clarification; correct step-1 interpretation

**Expected:** no M7 action claims until deliberate test

**Actual:** immersive open + clean quit verified; no M7 action test.

**Artifacts:** evidence/EV-0233/latestlog.txt (cb16ca54ecba); evidence/EV-0233/vrmc-shell.log (754351492acd); evidence/EV-0233/summary.log (f07748e31d84)

**Limitations:** Corrects over-interpretation of incidental action transitions in EV-0232.

### EV-0234 — M7 GUI head-ray cursor + tap forgiveness; device retest required

| Field | Value |
|---|---|
| Date | 2026-11-02T22:00:38-10:00 |
| Commit | `d83704071e5a346591ad588dab32701de56f5d7d` |
| Dirty state | ERIFY.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. diagnose menu/inventory misses; add head-ray GUI cursor projection; loosen fist/tap thresholds; status M7 summary; tests/build/push/integrity

**Expected:** host tests PASS; provider pushed; device retest needed

**Actual:** 40 checks PASS; provider c69ccd3b… pushed/integrity PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0234/VisionM7Gesture.java (e091497cfba5); evidence/EV-0234/VisionVR.java (d82304553af4); evidence/EV-0234/m7-tests9.log (ba5de5cbca08); evidence/EV-0234/m7-repro3.log (d9db7b73d1c0); evidence/EV-0234/m7-integrity2.log (31f875c5c754); evidence/EV-0234/latest-build-identity.txt (ae51ff2f168d); evidence/EV-0234/summary.log (ad264b267814)

**Limitations:** Hand tracking dropout is not fixed; head-ray cursor is not raw eye tracking.

### EV-0235 — DEVICE CRASH FIX: M7 GUI cursor WindowExtension NoSuchMethodError

| Field | Value |
|---|---|
| Date | 2026-11-02T22:21:46-10:00 |
| Commit | `1bc533fec0c847976b0dbaa815982810050a0ed3` |
| Dirty state | ERIFY.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. read crash report; remove runtime-missing API from M7 cursor and gaze path; guard cursor; tests/build/push/integrity

**Expected:** no render-thread crash from GUI cursor; retest

**Actual:** crash fixed; full provider suite PASS; provider 3a3bf56e… pushed/integrity PASS; device retest required.

**Artifacts:** evidence/EV-0235/latestlog.txt (4621be995a4c); evidence/EV-0235/crash-report.txt (f43794bb7097); evidence/EV-0235/VisionVR.java (fc593122f258); evidence/EV-0235/m7-tests10.log (958632fbf760); evidence/EV-0235/m7-repro4.log (65bd0cbba112); evidence/EV-0235/m7-integrity3.log (c2c8de3ab52e); evidence/EV-0235/latest-build-identity.txt (51c73f76d796); evidence/EV-0235/summary.log (ac120dcaacb8)

**Limitations:** Root cause was the new M7 GUI cursor calling a Vivecraft method absent at runtime. Do not use WindowExtension.getActualWindowSize on this build.

### EV-0236 — M7 false-trigger fixes: pinch debounce, GUI close, hotbar suppression

| Field | Value |
|---|---|
| Date | 2026-11-02T22:38:32-10:00 |
| Commit | `317f5bb5b12a52c4af89566dd16767dfc0dfc0d4` |
| Dirty state | ERIFY.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionM7GestureTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. diagnose inventory/menu/hotbar false positives; add pinch debounce/arming; close GUI via Screen.onClose; suppress menu/hotbar around both-fist; head-cursor logging; tests/build/push/integrity

**Expected:** host tests PASS; device retest

**Actual:** 44 checks PASS; provider b77897dd… pushed/integrity PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0236/VisionM7Gesture.java (fbbbe2089d02); evidence/EV-0236/VisionVR.java (acd4c5067d5e); evidence/EV-0236/VisionM7GestureTest.java (16696f456536); evidence/EV-0236/m7-tests18.log (093c4c800585); evidence/EV-0236/m7-repro5.log (5c0e2d81e5e0); evidence/EV-0236/m7-integrity4.log (9ccda53c48aa); evidence/EV-0236/latest-build-identity.txt (0e6ca5edd391); evidence/EV-0236/summary.log (49c8e7296a23)

**Limitations:** Hand tracking dropout not fixed. Device retest for menu/inventory/pinch.

### EV-0237 — M7 data-driven gesture accuracy iteration + replay gate

| Field | Value |
|---|---|
| Date | 2026-11-03T07:27:22-10:00 |
| Commit | `dab273bb58f29ee7482c57f868fdee58a0697d5b` |
| Dirty state | gitignore, AGENT.md, VERIFY.md, docs/mvp/M7_ENGINE.md, docs/mvp/M7_GESTURES.md, docs/mvp/M7_PLAN.md, docs/mvp/M7_TEST_MATRIX.md, docs/mvp/STATUS.md, provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/src/main/resources/vrmc.mixins.json, provider/tests/dev/vrmc/provider/VisionM7GestureTest.java, provider/tests/run_tests.sh, docs/mvp/M7_ACCURACY_ITERATION.md, docs/mvp/M7_DATA_ANALYSIS_HANDS.md, docs/mvp/M7_DATA_ANALYSIS_HEAD.md, docs/mvp/M7_EVAL_REPLAY.md, docs/mvp/M7_VERIFICATION_HANDS_OFF.md, provider/src/main/java/dev/vrmc/provider/VisionM7ItemContext.java, provider/src/main/java/dev/vrmc/provider/mixin/GuiHandlerMixin.java, provider/tests/dev/vrmc/provider/M7LabReplay.java, provider/tests/dev/vrmc/provider/VisionM7GestureFuzzTest.java, scripts/m7_eval_replay.py, scripts/m7_lab_fixture.py, scripts/m7_lab_replay.sh, scripts/m7_lab_stats_hands.py, scripts/m7_lab_stats_head.py |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Analyse all 14 accepted datasets (two independent scripts/reports)
2. Replay datasets through real VisionM7Gesture at 18 Hz + 90 Hz with per-label game context
3. Score with independent evaluator v2.1 (rate-matched pulse GT + bounded-latency held policy; literal gates kept; 6/6 self-check)
4. Full provider host suite (73 synthetic checks + 200k-frame fuzz)
5. Independent verifier review: tests, metrics, code safety, docs/evidence consistency

**Expected:** No host regressions; replay gate rows pass and residuals are explained; independent verification confirms the claims

**Actual:** Provider suite ALL PASS; primary gate 22/24, literal 20/24, context 9/9; evaluator self-check 6/6; verifier host gates PASS (report included); residuals: hotbar recall 0.75, attack recall 0.77 precision 0.71 (primary); walk/eat/hotbar literal-only rows explained by latency/18Hz-GT effects

**Artifacts:** evidence/EV-0237/provider-build-a.log (f0e63d1206b1); evidence/EV-0237/provider-build-b.log (7518d2c52cf3); evidence/EV-0237/provider-tests-final2.log (e9a8cddc68cf); evidence/EV-0237/m7-replay-final3.log (e2de25944f13); evidence/EV-0237/eval.json (117b632510ca); evidence/EV-0237/fixtures-manifest.log (74a5476046a8); evidence/EV-0237/git-status.txt (cc7edb93be32); evidence/EV-0237/diff-stat.txt (cf42aba3c928); evidence/EV-0237/provider-jar.sha256 (e26d7201563f); evidence/EV-0237/M7_VERIFICATION_HANDS_OFF.md (b7cee39365f3); evidence/EV-0237/M7_EVAL_REPLAY.md (096936071d7a)

**Verification:** Independent verifier report `docs/mvp/M7_VERIFICATION_HANDS_OFF.md` (included in the bundle as M7_VERIFICATION_HANDS_OFF.md): host gates PASS, 73 checks + 200k fuzz reproduced, gate rows reproduced exactly, 9/9 headline metric families independently re-derived from the raw JSONL, cleanup proven dead-code-only, two-build jar `d2c8a8d9…`/120,666 B reproduced. This entry records the three verifier-required fixes: VERIFY §6 entry (this section), `export/latest-build-identity.txt` restored to the actually-installed EV-0236 provider, and evaluator empty-target robustness + `--self-check` (6/6 PASS).

**Limitations:** Host-only: 14 Gesture Lab datasets analysed/replayed; provider suite ALL PASS (73 synthetic + 200k fuzz); evaluator-v2.1 primary replay gate 22/24 rows, literal conservative gate 20/24 (first-engine baseline 12/24), context 9/9; residual primary rows: hotbar recall 0.75, attack 0.77/0.71; evaluator --self-check 6/6; independent verifier report included; DEVICE A/B NOT RUN (installed D1 provider remains EV-0236).

### EV-0238 — M7 EV-0237 provider pushed to D1 + installed integrity PASS (device launch blocked)

| Field | Value |
|---|---|
| Date | 2026-11-03T21:39:25-10:00 |
| Commit | `419f7f9c50dabd3d30c33d8faf57733059733243` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Push provider jar d2c8a8d9 to app data container and verify round-trip sha256
2. Run read-only device integrity check (installed jar vs local build)
3. Attempt app relaunch via devicectl (blocked: Failed to allocate RSD device)
4. Pull pre-push device diagnostics/logs/status/tune for the record

**Expected:** Installed D1 provider matches the committed EV-0237 build and the app can be launched for the operator A/B

**Actual:** Push round-trip PASS and device integrity PASS (d2c8a8d9/120666). App launch NOT RUN: RSD device allocation failed twice; game process still running the previous session build. Gesture A/B remains NOT RUN; operator session required.

**Artifacts:** evidence/EV-0238/push.log (c021e9efbcc7); evidence/EV-0238/integrity.log (668e0af1ee74); evidence/EV-0238/launch-attempt.log (9b2866c328f5); evidence/EV-0238/device-info.log (e09a85b5ebc1); evidence/EV-0238/tune.properties (bcd3e7af8ca5); evidence/EV-0238/pre-push-observation.txt (4ec6f36aeaf4); evidence/EV-0238/device-diag-pre-push.tgz (f71437b5d570); evidence/EV-0238/artifact-sha256.txt (1dfa2dbac5d3)

**Limitations:** Provider-only push of the EV-0237 jar; no app rebuild. Installed jar read-back matches local build. App launch/behaviour NOT RUN: devicectl launch failed with RSD allocation error at push time; gesture A/B still requires the operator session. Pre-push installed provider was cf3ef0a0 (110857 B, previous unrecorded push) - corrected in docs/identity.

**Notes:** This push corrects a state discrepancy found during the EV-0237 verification: the jar actually installed on D1 before this push was `cf3ef0a0…` (110,857 B), not the EV-0236 `b77897dd…` recorded earlier — the post-EV-0236 provider update had not been recorded in VERIFY. The read-back after the push is `d2c8a8d9…`/120,666 B (see artifacts). The app could not be relaunched at push time (`devicectl` RSD allocation error), so no gesture/behaviour evidence exists for EV-0237/EV-0238 yet.

### EV-0239 — M7 GUI cursor: centre-on-open + ray-miss fallback + device cursor diagnostics (retest pending)

| Field | Value |
|---|---|
| Date | 2026-11-04T06:30:46-10:00 |
| Commit | `d181595a3387bc185d38b800178994d870049bb7` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Read device log: cursor set only after a successful GUI-plane intersection; default mouse position is top-left
2. Add centre-on-open and centre-while-ray-misses fallback (valid hits are never overwritten)
3. Add rate-limited cursor diagnostic (every ~300 frames while a GUI is open)
4. Provider suite + two independent builds; push to D1 with round-trip/integrity verification

**Expected:** Cursor starts and stays in the middle of the view until a valid head-ray hit; diagnostics make the on-device mapping verifiable

**Actual:** Host suite ALL PASS; jar fdce66d4.../121326 B two-build identical; pushed and integrity PASS. Device visual retest NOT RUN (operator relaunch required).

**Artifacts:** evidence/EV-0239/push.log (f26dfacf69d3); evidence/EV-0239/integrity.log (0bc6f370de17); evidence/EV-0239/cursor-tests.log (dfd9b1adf1df); evidence/EV-0239/build-a.log (44fea2c5b2b0); evidence/EV-0239/build-b.log (773727fa0119)

**Limitations:** Operator feedback: GUI cursor appears in the top-left of the view instead of the middle. Host analysis of the device log showed the cursor was only positioned after a successful head-ray/GUI-plane intersection; until then MouseHandler keeps its default (0,0). Fix: centre the cursor when a GUI screen opens and keep it centred while the ray misses (never overwrite a valid hit), plus a rate-limited diag line (uv, mouse, read-back, window/framebuffer/GUI sizes, plane, head, dir). Provider suite ALL PASS; two-build reproducible; pushed/integrity PASS. Visual retest on D1 NOT RUN yet (needs app relaunch + operator observation).
### EV-0240 — D1 immersive did not open: crash-guard safe mode diagnosis + counter reset (no code change)

| Field | Value |
|---|---|
| Date | 2026-11-04T19:26:57-10:00 |
| Commit | `6293928fe29487be43364aa23f62b395184bd3bb` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Pull device diagnostics after the report (shell/latestlog/shutdown/status/crash-count)
2. Trace automatic immersive open suppression to the shell crash-guard safe mode (count=2, unclean prior sessions)
3. Reset Documents/vrmc-crash-count.txt to 0 on the device and verify the read-back
4. Archive the safe-mode evidence and document the clean-shutdown requirement (destroy-complete)

**Expected:** Automatic immersive open restored on the next app launch; manual Enter VR available immediately

**Actual:** Root cause identified and documented; crash counter reset to 0 (read-back 0). Running session still needs manual Enter VR. No provider code change; device visual cursor/gesture retest still pending.

**Artifacts:** evidence/EV-0240/diagnosis.txt (fe03a010569d); evidence/EV-0240/Documents_vrmc-shell.log (25d3abd40a33); evidence/EV-0240/Documents_latestlog.txt (604d09883841); evidence/EV-0240/Documents_instances_default_vrmc-shutdown.log (7b57f9a49cbe); evidence/EV-0240/Documents_instances_default_vrmc-status.json (818fd704ecaa); evidence/EV-0240/crash-count-after-reset.txt (5feceb66ffc8); evidence/EV-0240/safe-mode-flag-still-present.txt (8b3369944dd2)

**Limitations:** Operator reported the game did not enter the immersive space after the EV-0239 relaunch. Device logs show the shell crash guard counted two consecutive unclean VR-session shutdowns (app force-quit during the push/restart cycles) and suppressed the automatic immersive open: "CRASH-GUARD ... count=2", "safe mode enabled ... automatic VR open suppressed", then SAFE MODE at VRMCGameStarted. This is shell safe-mode behaviour, not a provider/M7 defect. Reset the on-device crash counter to 0 (read-back verified) so the next launch auto-opens again; the running shell needs a manual Enter VR / Clear crash safe mode for this session. Remote devicectl relaunch remains unavailable (RSD allocation). Provider jar fdce66d4 unchanged.

### EV-0241 — D1 immersive still closed: crash-guard double-start mechanism + second counter reset

| Field | Value |
|---|---|
| Date | 2026-11-04T22:26:48-10:00 |
| Commit | `b88cb51611e36c00cdc7ca73c4f50c5ed3c56c78` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Compare vrmc-shell.prev.log (launch #1) and vrmc-shell.log (launch #2) to reconstruct the count 0->1->2 sequence
2. Read the crash count and last shutdown.log lines to confirm the unclean-increment mechanism
3. Reset Documents/vrmc-crash-count.txt to 0 and verify the read-back
4. Document the clean-shutdown recovery path and the known rapid-relaunch hazard

**Expected:** Single app launch after the reset allows the automatic immersive open; a clean game shutdown permanently resets the guard

**Actual:** Mechanism identified; counter reset to 0 (read-back 0). Robust recovery needs the operator to quit Minecraft via its menu (clean destroy-complete) and/or reinstall a shell with crash-guard debounce. No provider change (jar fdce66d4 unchanged).

**Artifacts:** evidence/EV-0241/diagnosis.txt (e520ba3c535e); evidence/EV-0241/shell-launch1.log (1eb167a08ea2); evidence/EV-0241/shell-launch2.log (a060b3e71a5a); evidence/EV-0241/shutdown.log (dd47791c7eb0); evidence/EV-0241/latestlog.txt (6e0f9ffb92ca); evidence/EV-0241/vrmc-crash-count.txt (5feceb66ffc8)

**Limitations:** After the EV-0240 counter reset, the app restarted its shell twice within 26 s (22:23:35 and 22:24:01 HST). Each start evaluates the crash guard against the last unclean shutdown.log line, so the count went 0 -> 1 -> 2 and safe mode suppressed the automatic immersive open again. Not a provider/M7 fault and not operator error; shell-lifecycle interaction. Reset count to 0 again (read-back 0); single launch will auto-open. Robust fix is a clean game shutdown (destroy-complete) via the in-game Quit Game menu, or in-session Enter VR / Clear crash safe mode. A shell-side debounce is a candidate permanent fix but needs an app rebuild.

### EV-0242 — M7 GUI cursor half-scale onMove mapping + pinch-click misses: probe calibration fix

| Field | Value |
|---|---|
| Date | 2026-11-04T22:33:12-10:00 |
| Commit | `6957cd8ac63c71ae1b3585a56a6f78d6a35c3819` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Pull the immersive-session cursor diag lines (new telemetry)
2. Show MouseHandler readback = half the requested position and compute the resulting GUI pixel
3. Trace to the runtime MouseHandlerVRMixin onMove coordinate scale (GUI_WIDTH/actualWindowSize)
4. Add a one-time probe calibration and divide cursor writes by the measured scale; log cursorScale
5. Provider suite + two independent builds; push/integrity; set crash-count headroom for the relaunch

**Expected:** After the fix the stored MouseHandler position is uv*win (cursor under the head ray, centred when aimed at the GUI centre) and pinch clicks land on the aimed button

**Actual:** Root cause proven from device telemetry; calibration fix built/pushed/integrity-PASS (069ea641.../121,974 B). Device visual retest NOT RUN (requires one app relaunch; crash-count headroom -3 set).

**Artifacts:** evidence/EV-0242/diagnosis.txt (4026ae2fd251); evidence/EV-0242/latestlog-before-fix.txt (efbcf8d01447); evidence/EV-0242/shell-immersive.log (e0c06f3cda16); evidence/EV-0242/push.log (5508d4716414); evidence/EV-0242/integrity.log (bb021ac812e4); evidence/EV-0242/cursor-cal-tests.log (4a702ba08077); evidence/EV-0242/ev0242-build-a.log (782e47262164); evidence/EV-0242/ev0242-build-b.log (525f653fddfc); evidence/EV-0242/vrmc-crash-count-headroom.txt (615bdd17c255)

**Limitations:** In the EV-0239 immersive session the cursor sat upper-left and right-pinch clicks missed. The new cursor diag proved MouseHandler stores exactly half the requested position: mouse=(645.5,471.2) readback=(322.7,235.6), win/fb=1280x720, gui=427x240 -> GUI pixel ~107,78. The runtime Vivecraft MouseHandlerVRMixin scales onMove args by GUI_WIDTH/actualWindowSize while VR is running (actual window 2560x1440 vs 1280x720 screen), and the provider cannot call the runtime-missing WindowExtension helper (EV-0235). Fix: one-time calibration probe on screen open (write centre, read MouseHandler back, derive scale) and divide every cursor write by it; diag logs cursorScale/readback. Provider suite ALL PASS; two builds identical; pushed/integrity PASS. Device visual retest NOT RUN yet; crash-count headroom -3 set on the device for the relaunch.

### EV-0243 — VR-state-aware GUI cursor calibration (flat->VR probe re-run) — follow-up to EV-0242

| Field | Value |
|---|---|
| Date | 2026-11-04T22:34:46-10:00 |
| Commit | `e20e50b509f9c6ad5c0ec27c1076fb01e73b4a42` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Trace the EV-0242 calibration lifetime across the flat-window -> immersive transition (VRState.VR_RUNNING gates the runtime onMove scale)
2. Add VR_RUNNING to the calibration key; re-probe on state/window change and reset the valid-uv latch
3. Log vr= in the cursor diag; keep the flat case at scale 1.0
4. Provider suite + two independent builds; push/integrity

**Expected:** Cursor calibration is re-measured when the immersive space opens so the stored MouseHandler position equals uv*win and pinch clicks land on the aimed button

**Actual:** Fix built/pushed/integrity-PASS (4c917439.../122,089 B); suite ALL PASS. Device visual retest NOT RUN (operator relaunch).

**Artifacts:** evidence/EV-0243/diagnosis.txt (4dd5efde232f); evidence/EV-0243/push.log (c2e5b9c1345d); evidence/EV-0243/integrity.log (6c48e79fee4b); evidence/EV-0243/vrstate-tests.log (6dadba67ebff); evidence/EV-0243/ev0243-build-a.log (4d665404366b); evidence/EV-0243/ev0243-build-b.log (477f3df6efac)

**Limitations:** EV-0242s probe calibration could run while the game was still in its flat window (VR_RUNNING=false), where the runtime onMove scale is 1.0; the window does not resize when the immersive space opens, so the stale 1.0 calibration would persist into VR and the half-position cursor bug would remain. Re-probe on flat<->VR transitions (and window changes), clear the valid-uv latch so the cursor re-centres with the new scale, and log vr= in the cursor diag. Suite ALL PASS; jar 4c917439.../122,089 B two-build identical; pushed/integrity PASS. Device visual retest NOT RUN (relaunch required); crash-count headroom still -3.

### EV-0244 — M7 GUI pinch click swallowed by cancelled GuiHandler.processGui: direct vanilla mouse dispatch fix

| Field | Value |
|---|---|
| Date | 2026-11-04T22:41:55-10:00 |
| Commit | `6b833c254dc6689cd8432c04eccbe927e5bdf872` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Reproduce: cursor calibration correct in the next immersive session but GUI does not react to 18 guiLeftClick action pulses
2. Trace guiLeftClick to GuiHandler.processBindingsGui and its CONTROLLER_MOUSE_* / mouseValid gate
3. Identify that GuiHandler.processGui (the only writer of CONTROLLER_MOUSE_*) is cancelled by the M7 head-cursor mixin
4. Dispatch the M7 GUI click directly via InputSimulator.pressMouse/releaseMouse on the engine pulse edge; log stored mouse + screen
5. Provider suite + two independent builds; push/integrity; crash-count headroom for the relaunch

**Expected:** One right pinch in a GUI produces one vanilla Screen.mouseClicked at the aimed GUI pixel; the proof log shows gui click press with the calibrated stored position

**Actual:** Root cause proven from the device action/status logs; direct-dispatch fix built/pushed/integrity-PASS (71d08da4.../122,375 B), suite ALL PASS. Device visual retest NOT RUN (one operator relaunch).

**Artifacts:** evidence/EV-0244/diagnosis.txt (d7b7410ff6ec); evidence/EV-0244/latestlog-no-click-dispatch.txt (e9c88ca885f6); evidence/EV-0244/shell-immersive.log (3a8aa45ecfc6); evidence/EV-0244/status.json (1da9c5b9c486); evidence/EV-0244/click-tests.log (b4e1b606abd3); evidence/EV-0244/ev0244-build-a.log (1aab58220c4c); evidence/EV-0244/ev0244-build-b.log (eaceb1959f79); evidence/EV-0244/push.log (eb9cf1eb16e1); evidence/EV-0244/integrity.log (66bdebd2677b); evidence/EV-0244/vrmc-crash-count-headroom.txt (615bdd17c255)

**Limitations:** EV-0243s calibrated cursor is proven correct in the next immersive session (scale 0.5, readback = uv*win, vr=true), but GUI pinch clicks still did nothing although the log shows 18 guiLeftClick action pulses. Root cause: the M7 dispatch wrote Vivecrafts guiLeftClick VRInputAction, which GuiHandler.processBindingsGui only turns into a mouse press when CONTROLLER_MOUSE_* is valid; those fields are only updated in GuiHandler.processGui(), which our mixin cancels to own the head-ray cursor, so every click is swallowed. Fix: dispatch the click directly through InputSimulator.pressMouse/releaseMouse on the engine guiClick edge (cursor already positioned that frame), with a proof log line; release on pulse end/tracking loss. Suite ALL PASS; 71d08da4/122375 B two-build identical; pushed/integrity PASS; crash headroom -3. Device visual retest NOT RUN.

### EV-0245 — Installed Vivecraft 26.2-1.3.15 runtime audit: cursor onMove scale, swallowed-click gate, API availability

| Field | Value |
|---|---|
| Date | 2026-11-04T22:43:31-10:00 |
| Commit | `6b833c254dc6689cd8432c04eccbe927e5bdf872` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Copy the installed vivecraft-26.2-1.3.15-fabric.jar from D1 and hash it
2. javap the runtime InputSimulator/WindowExtension/VRState/GuiHandler/MCVR/ClientDataHolderVR surface used by the provider
3. Inspect bytecode of MouseHandlerVRMixin onMove scaling and GuiHandler.processBindingsGui click gating
4. Confirm the access widener is shipped (MouseHandler.onButton call is widened)
5. Check no provider call site still uses WindowExtension.getActualWindowSize

**Expected:** All Vivecraft APIs used by the M7 cursor/click fixes exist and behave like the fix assumes in the actually-installed 1.3.15 runtime

**Actual:** Audit passes: scale 0.5 formula, swallowed-click gate and InputSimulator/VRState availability all confirm the diagnosis and the compatibility of the fixes with the installed jar. Behavioural device retest still NOT RUN.

**Artifacts:** evidence/EV-0245/audit.txt (02c3a19db5cc); evidence/EV-0245/installed-vivecraft-jar.sha256 (48a16d0f079d); evidence/EV-0245/fabric.mod.json (c7ed7359e064); evidence/EV-0245/MANIFEST.MF (b273a193369b); evidence/EV-0245/javap-InputSimulator.txt (dd84cc4e128b); evidence/EV-0245/javap-WindowExtension.txt (00b29423ab44); evidence/EV-0245/javap-VRState.txt (912a2fe47c8c); evidence/EV-0245/javap-GuiHandler-fields.txt (cd66a1520a7e); evidence/EV-0245/javap-MCVR.txt (0edd97d328eb); evidence/EV-0245/javap-ClientDataHolderVR.txt (3dc12fe29e7b); evidence/EV-0245/bytecode-GuiHandler.processBindingsGui.txt (d8f19350d0a3); evidence/EV-0245/bytecode-MouseHandlerVRMixin.modifyX.txt (cd3aad94bee1); evidence/EV-0245/accesswidener-presence.txt (ac6e42b3d98c)

**Limitations:** Pulled the installed Vivecraft mod from D1 (sha256 e63aeed1..., 6,685,183 B, version 26.2-1.3.15) and audited the bytecode of the APIs used by the new M7 cursor/click fixes, because the provider compiles against newer repo sources (the EV-0235 class of failure). Confirmed: WindowExtension 1.3.15 only has getActualScreenWidth/Height (no getActualWindowSize -> probe calibration is right); MouseHandlerVRMixin scales onMove by GUI_WIDTH/actualScreenWidth = 0.5 (matches measured probe); processBindingsGui requires CONTROLLER_MOUSE_* which only processGui writes (cancelled by our mixin -> swallowed clicks); InputSimulator.pressMouse/releaseMouse exist and the jar ships an access widener making MouseHandler.onButton accessible, so direct click dispatch is runtime-legal; VRState.VR_RUNNING and GuiHandler/ClientDataHolder/MCVR members used by the provider are present. Host/device-artifact audit only; visual retest still required.

### EV-0246 — M7 direct touch-hotbar selection: tap the HUD inventory bar to select a slot

| Field | Value |
|---|---|
| Date | 2026-11-05T06:28:28-10:00 |
| Commit | `a03f2e0697034c0f0bdf4a3a69e765bc4e2aacce` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Read the operator request: select hotbar slot by tapping the rendered inventory bar
2. Mirror the installed InteractiveHotbarModule bar geometry (GUI_RENDER_POS_ROOM/ROTATION_ROOM, GUI_OFFSET_LOCAL, GUI_SCALE_APPLIED/MAX)
3. Use the right index fingertip with 6 cm proximity, 60 ms same-slot dwell, 3 cm drift limit and 300 ms cooldown; set Inventory selected slot reflectively
4. Guard off in GUI/seated/HEAD-HUD/untracked/stale; keep index-tap cycling as fallback
5. Bytecode-audit the installed Vivecraft 26.2-1.3.15 jar for the statics/math/API used
6. Provider suite + two independent builds; push/integrity; crash-count headroom for the relaunch

**Expected:** Tapping the rendered HUD hotbar with the right index finger selects that slot; the log shows armed geometry, hover and select lines

**Actual:** Feature built/pushed/integrity-PASS (747ed2ab.../124,561 B), suite ALL PASS, installed-runtime audit passes. Device tap test NOT RUN (operator relaunch required).

**Artifacts:** evidence/EV-0246/feature-note.txt (b541d139a668); evidence/EV-0246/hotbar-tests.log (7ef36d5bf585); evidence/EV-0246/ev0246-build-a.log (15ff65e33622); evidence/EV-0246/ev0246-build-b.log (cf53d09b8113); evidence/EV-0246/push.log (0167c5bb4fc9); evidence/EV-0246/integrity.log (687ac49bf45c); evidence/EV-0246/javap-installed-GuiHandler-HUD-statics.txt (b1c3b6253ac3); evidence/EV-0246/javap-installed-VRSettings-hotbar.txt (d6c03daeff19); evidence/EV-0246/javap-installed-InteractiveHotbarModule.txt (4613acc209ab); evidence/EV-0246/bytecode-InteractiveHotbarModule.getHotbarStart.txt (066c62f40ed8); evidence/EV-0246/bytecode-InteractiveHotbarModule.getHotbarEnd.txt (cf359b076efc); evidence/EV-0246/bytecode-InteractiveHotbarModule.isActive-head.txt (3b1b37c2cea1); evidence/EV-0246/bytecode-InteractiveHotbarModule.onPress-head.txt (676599a3a7fc); evidence/EV-0246/vrmc-crash-count-headroom.txt (615bdd17c255)

**Limitations:** Operator request: tap on the inventory bar to select. Implemented provider-side direct touch selection in M7: mirrors Vivecraft InteractiveHotbarModules rendered bar geometry from GuiHandler GUI_RENDER_*/GUI_OFFSET_LOCAL/GUI_SCALE_APPLIED statics and uses the right index fingertip; selects slot when within 6 cm of the bar, same slot dwelled >=60 ms with <3 cm drift, 300 ms cooldown; guarded off in GUI/seated/HEAD-HUD/untracked/stale; inventory access reflective (jspecify annotations absent from compile classpath). Installed Vivecraft 26.2-1.3.15 bytecode audited: geometry fields, vrTouchHotbar/vrHudLockMode, InteractiveHotbarModule math all present. Suite ALL PASS; 747ed2ab.../124,561 B two-build identical; pushed/integrity PASS; crash headroom -3. Device tap test NOT RUN.

### EV-0247 — Fail-safe wrapper around the direct touch-hotbar poll path (EV-0246 follow-up, jar refresh)

| Field | Value |
|---|---|
| Date | 2026-11-05T06:29:50-10:00 |
| Commit | `bbd1d9cf05282f636dc015fcfce27b8244e14a08` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Review the EV-0246 poll-path call for unguarded failure modes
2. Wrap updateM7TouchHotbar() in try/catch with bounded WARN logging (render-thread safety)
3. Provider suite + two independent builds; push/integrity; confirm crash headroom

**Expected:** No touch-hotbar failure can crash the render thread; behaviour identical otherwise

**Actual:** Wrapper added; suite ALL PASS; jar 0ee811fd.../124,629 B two-build identical; pushed/integrity PASS; crash count -3. Device tap test NOT RUN.

**Artifacts:** evidence/EV-0247/failsafe-note.txt (81f3483e0485); evidence/EV-0247/hotbar-failsafe-tests.log (4bb6cc0eaf95); evidence/EV-0247/ev0247-build-a.log (c5b0ffb1caaa); evidence/EV-0247/ev0247-build-b.log (bf2b3d009bc0); evidence/EV-0247/push.log (345f255bf265); evidence/EV-0247/integrity.log (9f96d733dc2d)

**Limitations:** EV-0246 touch-hotbar runs on the render thread in VisionVR.poll; all reads are guarded but a Throwable must never crash the frame (EV-0235 lesson), so the call is wrapped in try/catch with a bounded warning log. Behaviour and geometry unchanged; same guards/diagnostics. Suite ALL PASS; final jar 0ee811fd.../124,629 B two-build identical; pushed/integrity PASS; crash headroom -3. Device tap test NOT RUN.

### EV-0248 — M7 movement: left thumb-middle virtual stick replaces both-fist swing walk

| Field | Value |
|---|---|
| Date | 2026-11-05T16:02:33-10:00 |
| Commit | `57695981368da1a1d33d17a3412c1dcbb8f6bc49` |
| Dirty state | rovider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | D1 Apple Vision Pro (<D1-UDID>) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. Read the request: movement controlled by the left thumb
2. Remove the both-fist walk dispatch from M7 movement (engine detector retained for context/suppression and host gates)
3. Add left thumb-middle pinch virtual stick via VisionLocomotion + keyFreeMoveStrafe; zero in GUI/seated/keyboard/stale and on release paths
4. Add transition/3 s thumb-stick diagnostics
5. Provider suite + two independent builds; push/integrity; crash headroom for the relaunch

**Expected:** Holding the left thumb-middle pinch and moving the left hand walks/strafes analogously; no stuck movement on any release path

**Actual:** Feature built/pushed/integrity-PASS (37262f9c.../124,958 B), suite ALL PASS. Device movement test NOT RUN (operator relaunch required).

**Artifacts:** evidence/EV-0248/feature-note.txt (224559ecd795); evidence/EV-0248/thumb-tests.log (5097caed663d); evidence/EV-0248/ev0248-build-a.log (2c5a0b9d8cfd); evidence/EV-0248/ev0248-build-b.log (b3aad5b28e20); evidence/EV-0248/push.log (b987045c3946); evidence/EV-0248/integrity.log (9a214db52ea4); evidence/EV-0248/vrmc-crash-count-headroom.txt (615bdd17c255)

**Limitations:** Operator request: use the left thumb to control movement. Removed the both-fist alternating-swing walk dispatch; added left-thumb-middle-pinch + move-left-hand analog virtual stick (VisionLocomotion, shared move.* tunables) writing keyFreeMoveStrafe. Engine both-fist walk detector retained only as internal context/suppression and host gate. Zeroed in GUI/seated/keyboard/stale and on release paths. Thumb-middle pinch is disjoint from every M7 action (thumb-index = place/break/GUI, left hold = teleport). Suite ALL PASS; jar 37262f9c.../124,958 B two-build identical; pushed/integrity PASS; crash headroom -3. Device movement test NOT RUN.

### EV-0249 — M7 left-pinch movement + right-pinch LMB hold + cursor down

| Field | Value |
|---|---|
| Date | 2026-11-05T17:22:30-10:00 |
| Commit | `a0d8e082a49eb88b2988d801edbd5da1f7f5409f` |
| Dirty state | ocs/mvp/M7_ENGINE.md, docs/mvp/M7_GESTURES.md, docs/mvp/M7_PLAN.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. change movement to left pinch, GUI right pinch press/hold/release LMB, offset cursor down; test/build/push/integrity

**Expected:** host tests PASS; provider pushed; device retest

**Actual:** suite ALL PASS; provider a337481f… pushed/integrity PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0249/VisionM7Gesture.java (942d2a26e5cc); evidence/EV-0249/VisionVR.java (87db56a07a03); evidence/EV-0249/m7-tests20.log (6a695611234a); evidence/EV-0249/m7-repro7.log (b078f0898ac0); evidence/EV-0249/m7-integrity6.log (eee894ec43b2); evidence/EV-0249/latest-build-identity.txt (81d4105c21f4); evidence/EV-0249/summary.log (b8ce122aad88)

**Limitations:** Teleport shares left pinch and is suppressed while moving; dedicated teleport gesture needed. Device retest pending.

### EV-0250 — M7 movement fixed to player-relative HMD basis

| Field | Value |
|---|---|
| Date | 2026-11-05T17:35:50-10:00 |
| Commit | `b0bea21fddde4757e73da46fa2a7c668b6e329bf` |
| Dirty state | ERIFY.md, docs/mvp/M7_ENGINE.md, docs/mvp/M7_GESTURES.md, docs/mvp/M7_PLAN.md, docs/mvp/STATUS.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionLocomotion.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionLocomotionTest.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. project wrist-minus-head onto HMD forward/right; add axesRelative math/tests; build/push/integrity

**Expected:** host tests PASS; player-relative movement; device retest

**Actual:** suite ALL PASS; provider 85d18f61… pushed/integrity PASS; device NOT RUN.

**Artifacts:** evidence/EV-0250/VisionLocomotion.java (214e807cf98d); evidence/EV-0250/VisionVR.java (f7ccc108e24d); evidence/EV-0250/VisionLocomotionTest.java (be1babdfb545); evidence/EV-0250/m7-tests22.log (4858b5f83c10); evidence/EV-0250/m7-repro8.log (b8e9671ad986); evidence/EV-0250/m7-integrity7.log (34f218ecfee7); evidence/EV-0250/latest-build-identity.txt (e995d9967a72); evidence/EV-0250/summary.log (dd9426fe9043)

**Limitations:** Device movement test pending; teleport remains suppressed while moving.

### EV-0251 — M7 movement fix: remove teleport conflict, neutral pinch origin, strafe sign

| Field | Value |
|---|---|
| Date | 2026-11-05T17:43:58-10:00 |
| Commit | `0bbdee83b325a27ce62994d47c9f253e99a5e947` |
| Dirty state | ERIFY.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. read movement-failure logs; identify same-pinch teleport and lateral offset; capture neutral origin; fix right-basis sign; disable teleport on movement pinch; tests/build/push/integrity

**Expected:** host PASS; provider pushed; device retest

**Actual:** suite ALL PASS; provider 90a724fc… pushed/integrity PASS; device NOT RUN.

**Artifacts:** evidence/EV-0251/VisionVR.java (fdaa7b6a0482); evidence/EV-0251/m7-tests24.log (fb82dcf5f514); evidence/EV-0251/m7-repro9.log (73417225f90f); evidence/EV-0251/m7-integrity8.log (38ac04b01687); evidence/EV-0251/latest-build-identity.txt (47c2b8f239f4); evidence/EV-0251/summary.log (dd2a9ae988fc)

**Limitations:** Teleport temporarily disabled on left pinch; needs a dedicated gesture. Device movement retest pending.

### EV-0252 — M7 movement diagnostics + fixes; device retest pending

| Field | Value |
|---|---|
| Date | 2026-11-05T17:45:32-10:00 |
| Commit | `9915dfa4e9bc565dba562a29789e900d70018d58` |
| Dirty state | ERIFY.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. add movement diagnostic fields; build/tests/repro/push/integrity

**Expected:** host PASS; logs diagnose direction/action delivery

**Actual:** suite ALL PASS; provider d7f45be7… pushed/integrity PASS; device movement retest pending.

**Artifacts:** evidence/EV-0252/VisionVR.java (7232426e4845); evidence/EV-0252/m7-tests25.log (8258917f9376); evidence/EV-0252/m7-repro10.log (f842d195ac22); evidence/EV-0252/m7-integrity9.log (76fa5eb61bf8); evidence/EV-0252/latest-build-identity.txt (ae85786ebda3); evidence/EV-0252/summary.log (ccfc9b823690)

**Limitations:** No device evidence yet; teleport remains disabled on movement pinch.

### EV-0253 — DEVICE PASS: M7 movement (left pinch player-relative stick)

| Field | Value |
|---|---|
| Date | 2026-11-05T17:56:54-10:00 |
| Commit | `d14f643a378eae2f0ca0112bee9e23151a7c4dd3` |
| Dirty state | ERIFY.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. operator tested movement after neutral-origin/teleport-conflict/basis fixes; pull latestlog/status/shutdown

**Expected:** left pinch hold + hand movement walks/strafes player-relative; no teleport override

**Actual:** operator confirms pass; logs show active analog data and player-relative forward/strafe, no teleport transitions; clean shutdown.

**Artifacts:** evidence/EV-0253/latestlog.txt (a9a60747f4fb); evidence/EV-0253/vrmc-status.json (c5203230e068); evidence/EV-0253/vrmc-shutdown.log (da13ad1747eb); evidence/EV-0253/crash-count.txt (5feceb66ffc8); evidence/EV-0253/summary.log (74afa42d1dc7)

**Limitations:** Device PASS for movement only; other M7/M5/M6 gates remain.

### EV-0254 — M7 one-pinch context + hotbar gating + inventory instructions

| Field | Value |
|---|---|
| Date | 2026-11-05T18:53:45-10:00 |
| Commit | `334515f413f72650888b657db85d4bddfe64f7ef` |
| Dirty state | ERIFY.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java, provider/src/main/java/dev/vrmc/provider/VisionM7ItemContext.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. implement contextual one-pinch place/attack; fix item context probe; faster pinch; gate touch/air hotbar around actions; build/test/push/integrity

**Expected:** host PASS; device retest

**Actual:** suite ALL PASS; provider 475b7dda… pushed/integrity PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0254/VisionVR.java (ecc107b9db1d); evidence/EV-0254/VisionM7Gesture.java (749e622b1bd9); evidence/EV-0254/VisionM7ItemContext.java (44e5c45a67f8); evidence/EV-0254/m7-tests28.log (dffa4ac83f59); evidence/EV-0254/m7-repro11.log (d0688a848ed9); evidence/EV-0254/m7-integrity10.log (5cf164474b7d); evidence/EV-0254/latest-build-identity.txt (52c4a1753216); evidence/EV-0254/summary.log (07207621b4ab)

**Limitations:** Context ambiguity: holding a block while aiming at a block places; right swing remains an alternate attack. Stack-splitting right-click not mapped. Device test pending.

### EV-0255 — M7 right pinch final mapping: short attack/place/use, hold break

| Field | Value |
|---|---|
| Date | 2026-11-05T19:01:19-10:00 |
| Commit | `f07be0e847a694009332bf1e0d7fd51d19abc92e` |
| Dirty state | ERIFY.md, docs/mvp/M7_ENGINE.md, docs/mvp/M7_GESTURES.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionVR.java |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. implement short pinch entity attack / block use / place and hold break; gate hotbar; faster pinch; tests/build/push/integrity

**Expected:** host PASS; device retest

**Actual:** suite ALL PASS; provider 683efdd3… pushed/integrity PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0255/VisionVR.java (91f3cca1d030); evidence/EV-0255/VisionM7ItemContext.java (44e5c45a67f8); evidence/EV-0255/m7-tests31.log (26acf29ce5e8); evidence/EV-0255/m7-repro12.log (47ac2a78e80d); evidence/EV-0255/m7-integrity11.log (245bc791632d); evidence/EV-0255/latest-build-identity.txt (5abf65621b11); evidence/EV-0255/summary.log (108145048820)

**Limitations:** Short pinch does not break blocks; hold is break. Inventory stack splitting/right-click still unmapped. Device retest pending.

### EV-0256 — DEVICE PASS: M7 short-pinch attack/place/use + hold-break

| Field | Value |
|---|---|
| Date | 2026-11-05T19:09:51-10:00 |
| Commit | `d0917968aee981706e73a16f40d38c627935cfb1` |
| Dirty state | ERIFY.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. operator tested one-pinch semantics, hold-break, hotbar stability, inventory; pull latestlog/status/shutdown

**Expected:** short pinch attack/place/use, hold break, hotbar stable, inventory placement

**Actual:** operator all pass; logs show use/attack/inventory/jump actions; clean shutdown; no exceptions.

**Artifacts:** evidence/EV-0256/latestlog.txt (32df00077d7a); evidence/EV-0256/vrmc-status.json (82951c36c8db); evidence/EV-0256/vrmc-shutdown.log (9b9f39c24d83); evidence/EV-0256/vrmc-input-tune.properties (bcd3e7af8ca5); evidence/EV-0256/summary.log (8b656a6e2bc4)

**Limitations:** Device PASS for this mapping only. Teleport unbound; bow/eat/climb and M5/M6 remain.

### EV-0257 — M7 scope close: core actions pass; teleport descoped

| Field | Value |
|---|---|
| Date | 2026-11-05T19:16:55-10:00 |
| Commit | `26115e189b2815e032a0d3da0845723139f2c1d3` |
| Dirty state | ERIFY.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. operator confirms remaining M7 actions pass and teleports are not required; pull latest log/status/shutdown; update scope/runbook

**Expected:** M7 core action set accepted without teleport

**Actual:** operator: no teleport, other actions passed; logs clean, no exceptions, destroy-complete.

**Artifacts:** evidence/EV-0257/latestlog.txt (32df00077d7a); evidence/EV-0257/vrmc-status.json (82951c36c8db); evidence/EV-0257/vrmc-shutdown.log (9b9f39c24d83); evidence/EV-0257/vrmc-input-tune.properties (bcd3e7af8ca5); evidence/EV-0257/summary.log (52889fb921ef)

**Limitations:** Teleport removed from acceptance scope at operator request. Remaining gates M5/M6 and hand-tracking dropout metrics.

### EV-0258 — M5 acceptance operator-attested PASS (previously tested)

| Field | Value |
|---|---|
| Date | 2026-11-05T19:22:33-10:00 |
| Commit | `37de2f8eca2ba644fdff7aa52a2f2844965b41f3` |
| Dirty state | ERIFY.md, docs/mvp/M5_ACCEPTANCE.md, docs/mvp/M5_DEVICE_RUN.md, docs/mvp/STATUS.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. operator attested prior M5 test; update acceptance matrix/docs; no new device run

**Expected:** M5 loop accepted without retest

**Actual:** operator-attested PASS; latest logs corroborate clean session; M6 remains

**Artifacts:** evidence/EV-0258/latestlog.txt (32df00077d7a); evidence/EV-0258/vrmc-status.json (82951c36c8db); evidence/EV-0258/vrmc-shutdown.log (9b9f39c24d83); evidence/EV-0258/M5_ACCEPTANCE.md (1e2db1a1c19b); evidence/EV-0258/summary.log (c997ed666138)

**Limitations:** This is an operator waiver, not a fresh evidence run. M6 AC/K gates still require device execution or explicit waiver.

### EV-0259 — 10-min soak attempt fails clean-session check; harness false positive fixed

| Field | Value |
|---|---|
| Date | 2026-11-05T19:39:54-10:00 |
| Commit | `393ae0fe2a0d7b6de63fd49aaed2cf7f0ba10c83` |
| Dirty state | ERIFY.md, export/soak-10min-20261105-192524/, export/soak-10min-20261105-192816/ |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. run 10-min soak; review shutdown journal; harden harness clean-shutdown check

**Expected:** one continuous session, last event destroy-complete

**Actual:** monitor reported PASS but journal has multiple init/no destroy; game relaunched repeatedly; no crash report; AC-5/K4 not passed.

**Artifacts:** evidence/EV-0259/shutdown-193645.log (6b46009dce8c); evidence/EV-0259/m6_soak_harness.sh (f7ca62c6b603); evidence/EV-0259/summary.log (d1b60d93c10f); evidence/EV-0259/game-193822.log (a8cd07c8fe96); evidence/EV-0259/shell-193822.log (448004b9fec2); evidence/EV-0259/status-193801.json (080b463b3d26)

### EV-0260 — Reduced 10-min soak accepted PASS by operator waiver

| Field | Value |
|---|---|
| Date | 2026-11-05T19:51:27-10:00 |
| Commit | `966eee8f17b9ab7ff056556402f2ef8402bbac6e` |
| Dirty state | ocs/mvp/M6_DEVICE_RUN.md, docs/mvp/M7_ENGINE.md, docs/mvp/STATUS.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionM7GestureTest.java, export/soak-10min-20261105-192524/, export/soak-10min-20261105-192816/ |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. operator accepted reduced 10-min soak and stated relaunches are not defects

**Expected:** reduce soak to 10 min without blocking acceptance

**Actual:** operator waiver recorded; AC-5/K4 PASS with reduced-duration/relaunch caveat; harness tightened for future

**Artifacts:** evidence/EV-0260/summary.log (0041848394ef)

**Limitations:** Not a clean continuous session artifact; explicit operator waiver.

### EV-0261 — M7 bow open-hand draw + menu-hand gray box aligned to hand

| Field | Value |
|---|---|
| Date | 2026-11-05T19:51:35-10:00 |
| Commit | `966eee8f17b9ab7ff056556402f2ef8402bbac6e` |
| Dirty state | ERIFY.md, docs/mvp/M6_DEVICE_RUN.md, docs/mvp/M7_ENGINE.md, docs/mvp/STATUS.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionM7Gesture.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, provider/tests/dev/vrmc/provider/VisionM7GestureTest.java, export/soak-10min-20261105-192524/, export/soak-10min-20261105-192816/ |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. allow bow draw without fists; shift menu-hand controller pose to fingertip; tests/build/repro/push/integrity

**Expected:** host PASS; device retest

**Actual:** suite ALL PASS (m7-gesture 74 checks); provider fac54efa… pushed/integrity PASS; device behavior NOT RUN.

**Artifacts:** evidence/EV-0261/VisionM7Gesture.java (25cc2883cbb2); evidence/EV-0261/VisionVR.java (340ce3aa4103); evidence/EV-0261/VisionM7GestureTest.java (4eaaeb6b5e73); evidence/EV-0261/m7-tests35.log (8bc032f729bf); evidence/EV-0261/m7-repro13.log (582bdb931c60); evidence/EV-0261/m7-integrity12.log (3f4544328577); evidence/EV-0261/latest-build-identity.txt (9f246541d2f1); evidence/EV-0261/summary.log (2817c8917751)

**Limitations:** Menu-hand shift 0.18m local -Z while GUI open; device visual verification pending.

### EV-0262 — M7 bow perpendicular to hand (90deg local-forward roll)

| Field | Value |
|---|---|
| Date | 2026-11-05T20:58:16-10:00 |
| Commit | `0dd7bce180a365f1affbcc9179fd0ad0271cecea` |
| Dirty state | ERIFY.md, export/latest-build-identity.txt, provider/src/main/java/dev/vrmc/provider/VisionM7ItemContext.java, provider/src/main/java/dev/vrmc/provider/VisionVR.java, export/soak-10min-20261105-192524/, export/soak-10min-20261105-192816/ |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. detect bow-holding hand; roll controller pose 90deg local Z; build/test/push/integrity

**Expected:** bow appears perpendicular; host PASS

**Actual:** suite ALL PASS; provider 4e92b306… pushed/integrity PASS; device visual NOT RUN.

**Artifacts:** evidence/EV-0262/VisionVR.java (b9035d9fdf21); evidence/EV-0262/VisionM7ItemContext.java (57eb46e70658); evidence/EV-0262/m7-tests36.log (c9b4b04dc68a); evidence/EV-0262/m7-repro14.log (47371b175f22); evidence/EV-0262/m7-integrity13.log (00f18cf56e5a); evidence/EV-0262/latest-build-identity.txt (4c17db264142); evidence/EV-0262/summary.log (4d8eb734f6be)

**Limitations:** 90deg around local forward; flip sign if visual is wrong. Device retest pending.

### EV-0263 — Known bug: bow visual orientation parallel to hand (accepted, non-blocking)

| Field | Value |
|---|---|
| Date | 2026-11-05T21:03:35-10:00 |
| Commit | `9b16ab703acfd214436c551dc827ba2147e5b2b0` |
| Dirty state | ERIFY.md, export/soak-10min-20261105-192524/, export/soak-10min-20261105-192816/ |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. operator retest of 90deg roll; accept as known bug and continue

**Expected:** bow perpendicular to hand

**Actual:** still parallel; bow draw/fire works; operator says leave as bug and continue

**Artifacts:** evidence/EV-0263/summary.log (617f3cc2ff4c)

**Limitations:** Accepted non-blocking known issue; follow-up item-only bow transform.

### EV-0264 — AC-1 cold reinstall complete; first-run world pending; AC-6/K6 pass

| Field | Value |
|---|---|
| Date | 2026-11-05T21:24:57-10:00 |
| Commit | `79be0f154bf6fa4e6e3e231ef81c38530d77a958` |
| Dirty state | ocs/mvp/M6_ACCEPTANCE.md, docs/mvp/STATUS.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. uninstall app; cold install; verify empty app data; record install time; operator sign-off AC-6

**Expected:** fresh app container; install timing; first-run/world

**Actual:** cold install 23.66 s; app data empty; AC-1 first-run/world still pending; AC-6 sign-off recorded.

**Artifacts:** evidence/EV-0264/m6-cold-install.log (567e9ce7ff83); evidence/EV-0264/release-package-dev.txt (8b854e39a8da); evidence/EV-0264/acceptance-readiness.txt (8c3d02b1fe4c); evidence/EV-0264/summary.log (8b219c79f7e2)

**Limitations:** Operator must launch with JIT and complete first-run world; provider jar is absent from empty data container until stack setup.

### EV-0265 — DEVICE PASS: AC-1 fresh install to immersive world

| Field | Value |
|---|---|
| Date | 2026-11-05T21:37:53-10:00 |
| Commit | `eb39b5c3056a54ea0e1f65cd35df53cdf25fb1f3` |
| Dirty state | ocs/mvp/M6_ACCEPTANCE.md, docs/mvp/STATUS.md |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. clean uninstall/reinstall; restore Vivecraft/provider; launch JIT; enter immersive world

**Expected:** fresh app data launches to world natively

**Actual:** operator confirms pass; 21 mods, immersive, world, clean destroy-complete, no exceptions; manual mod restore caveat.

**Artifacts:** evidence/EV-0265/latestlog.txt (60116819da5f); evidence/EV-0265/vrmc-status.json (7ce5d09a17df); evidence/EV-0265/vrmc-shutdown.log (fd534a4209f2); evidence/EV-0265/vrmc-shell.log (b0faaaa5556e); evidence/EV-0265/summary.log (e306ca7a10df)

**Limitations:** Fresh install required manual Vivecraft/provider jars; launcher auto-provisioning gap recorded.

### EV-0266 — RELEASE READY: development package, 22/22 acceptance

| Field | Value |
|---|---|
| Date | 2026-11-05T21:38:54-10:00 |
| Commit | `c7bd981ad8f59bb7d4021dd6c565c5714a621561` |
| Dirty state | xport/install-metrics-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. rebuild clean package after AC-1 pass; verify manifest/app/provider; run release gate

**Expected:** release-ready gate green

**Actual:** 22/22 acceptance PASS; package verifier/freshness PASS; m6_release_ready RESULT: RELEASE READY.

**Artifacts:** evidence/EV-0266/release-package-dev.txt (e168052acea8); evidence/EV-0266/m6-ready-final.log (ec2c98b52299); evidence/EV-0266/m6-verify-final.log (e0ea71cbd85a); evidence/EV-0266/summary.log (0295fab6d36e)

**Limitations:** Development/sideload package; not App Store. Caveats: K3 waiver, manual mod restore on fresh install, bow visual known bug.

### EV-0266 — RELEASE READY: development package, 22/22 acceptance

| Field | Value |
|---|---|
| Date | 2026-11-05T21:38:54-10:00 |
| Commit | `c7bd981ad8f59bb7d4021dd6c565c5714a621561` |
| Dirty state | xport/install-metrics-dev.txt, export/release-package-dev.txt |
| Device | not recorded |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PASS` |

**Procedure:**

1. rebuild clean package after AC-1 pass; verify manifest/app/provider; run release gate

**Expected:** release-ready gate green

**Actual:** 22/22 acceptance PASS; package verifier/freshness PASS; m6_release_ready RESULT: RELEASE READY.

**Artifacts:** evidence/EV-0266/release-package-dev.txt (e168052acea8); evidence/EV-0266/m6-ready-final.log (ec2c98b52299); evidence/EV-0266/m6-verify-final.log (e0ea71cbd85a); evidence/EV-0266/summary.log (0295fab6d36e)

**Limitations:** Development/sideload package; not App Store. Caveats: K3 waiver, manual mod restore on fresh install, bow visual known bug.

## 7. Status dashboard

| Area | Status | Basis |
|---|---|---|
| Specification (AGENT.md) | `PASS` | M0 formally closed 2026-10-31 (Decision 45=A) |
| Reference baseline | `PARTIAL` | EV-0001, EV-0002 |
| Repo foundation + tooling | `PASS` | EV-0003; commit `3332cdb` |
| JIT mechanism (S1) | `PASS` | EV-0021 (compat, five cold runs) + EV-0024 (native visionOS: JIT26 mapping, tier 3/4, `HELLOJIT`) |
| JVM/JIT runtime (C3) | `PASS (relabelled JRE)` | OpenJDK 25.0.4 iOS JRE relabelled to VISIONOS works on D1 (EV-0022/EV-0024); no fresh xros OpenJDK build needed for the runtime path |
| Graphics (Vulkan/MoltenVK) | `PASS (M0 gate)` | Host boot EV-0005 + 21-min world EV-0014; D1 capability EV-0016, render EV-0025, natives EV-0026, surface EV-0027, swapchain EV-0028, **MC 26.2 Vulkan world EV-0034**; 30-min soak is an M1 gate (Decision 45=A) |
| **M1 milestone** | **CLOSED** | EV-0057: fresh install→world (EV-0043), 30-min soak (EV-0044), save/relaunch (EV-0052); matrix `docs/mvp/M1_ACCEPTANCE.md` |
| **M2 milestone** | **CLOSED** | EV-0070: provider init + stereo targets + ABI v2 eye handoff (EV-0069) + no VR runtime; matrix `docs/mvp/M2_ACCEPTANCE.md`. M3/M4 were NOT RUN at closure; **M4-W1 input now host+simulator PASS (EV-0095); device/hands still NOT RUN** |
| **M3 milestone** | **IN PROGRESS** | M3a COMPLETE; M3-W1/W2 PASS; **M3-W3/W4 visual acceptance PASS on D1 (EV-0094)**. Black-immersive root cause was the M3b drawable depth-clear change 1.0 -> 0.0 (EV-0093); with the default 1.0 the immersive shows the eye-distinct stereo/alignment pattern (fusion cross, per-eye tint, checker border; drawable readback L luma 110.4 / R luma 110.4, centre ~171) and a JIT game run renders the Vivecraft menu world in the immersive space with stereo aligned and head tracking, operator-confirmed. The black-immersive blocker is CLOSED. **M4-W1 input path host+simulator PASS (EV-0095); device/hands NOT RUN.** Remaining M3 work: M4-W1 device run, window chrome, background re-entry device check, provider GPU-sync device run, M3-W5/W6 90 Hz/soak. |
| **M4-W1 immersive input (host + simulator + device)** | **PASS (M4-W1 slice, operator-confirmed on D1) / AC-4 NOT RUN** | EV-0095 host+simulator plumbing PASS + **EV-0096 device acceptance PASS**: synthetic cycle and real ARKit hands (authorization=allowed) both drove Vivecraft through the ABI v3 channel in the immersive scene; operator: “It ran very well!”. W2 first slice (EV-0097): One-Euro hand smoothing + shutdown eye-texture teardown hardening host+simulator PASS. Remaining: gaze hover+pinch (design ready), full P0 hands checklist/locomotion. |
| **M4-W2 first slice (smooth hands + shutdown hardening)** | **PARTIAL (host+simulator PASS, EV-0097) / device NOT RUN** | One-Euro hand-pose smoothing integrated in provider (VisionPoseSmoother, tuning keys, reset on loss; host test 11 checks PASS; provider tests ALL PASS; M4 selfcheck PASS). Shutdown SIGSEGV hardening: provider clears shared eye textures on destroy + compositor CFRetain/CFRelease in-flight textures; device quit-game run pending. Gaze tracking-areas + pinch selection NOT implemented. |
| **M4-W2 gaze tracking areas (EV-0098)** | **PARTIAL (host build/tests PASS) / runtime+device NOT RUN** | Bridge gaze mailbox, compositor tracking-area mask grid + hover + Swift spatial-event hook, provider tile→GUI-plane click mapping; `vrmc-gaze.flag` opt-in; VisionGazeMath 11 checks + provider suite PASS; mask pipeline runtime unverified (simulator sleeping; D1 unavailable). |
| **M4-W3 middle-pinch locomotion/core actions (EV-0099)** | **PARTIAL (host PASS) / device NOT RUN** | Middle-pinch tap/double/hold family (opt-out `middle.enabled=false`), right-tap jump, right-hold sneak, left-hold virtual stick → `keyFreeMoveStrafe` analog, left tap/double → rotateLeft/Right pulses; 15+7 host checks PASS; full provider suite ALL PASS. Real-hands feel/thresholds need D1. |
| **M4-W4 partial: swipe hotbar/scroll + radial (EV-0100)** | **PARTIAL (host PASS) / device NOT RUN** | Opt-in open-hand swipe detector (`swipe.enabled`, default OFF) with speed/axis/cooldown gating; right-hand horizontal swipes → `changeHotbar` prev/next, vertical → mouse wheel; right middle double-tap → `vivecraft.key.radialMenu`; m4-swipe 6 checks + m4-middle PASS; full provider suite ALL PASS. Chat/keyboard/swap/drop/bow/climb + real-hands tuning remain. |
| **M4-W4 extension: swipe action table (EV-0106)** | **PARTIAL (host PASS) / device NOT RUN** | Opt-in swipe sources bound to hotbarNext/Prev (right horizontal), toggleKeyboard/chat (left up/down), swapOffhand/drop (left horizontal); right vertical remains direct mouse-wheel scroll; duplicate direct hotbar handling removed. Binding table 21 rows/19 actions; swipe tests 9 checks PASS; provider suite ALL PASS. Swipe default OFF; device feel NOT RUN. |
| **M4-W4 use-hold/bow (EV-0109)** | **PARTIAL (host PASS) / device NOT RUN** | In-game `key.use` now bound to **right-fist hold** (continuous use; release to fire a bow), while GUI right-click keeps the fist tap. Host use-hold test + 161 m4 checks PASS; full provider suite ALL PASS. Device bow/use/climb feel NOT RUN. |
| **M4-W4 climb-jump chord (EV-0111)** | **PARTIAL (host PASS) / device NOT RUN** | Both-hand middle single-tap chord fires `vivecraft.key.climbeyJump` and suppresses the per-hand middle taps (right jump / left snap-turn). Binding table 22 rows/20 actions; middle suite 21 checks PASS; provider suite ALL PASS. Device climbing grab/jump feel NOT RUN. |
| **M5 first slice: runtime settings + diagnostics + thermal (EV-0101)** | **PARTIAL (host/build PASS) / device NOT RUN** | Opt-in `vrmc-runtime.properties` (comfort seated/free-move/aim, snap angle, render/simulation distance, frame limit, VSync, presets; strict invalid-value warnings; absent file = no changes); provider `[VRMC-M5] diag:` periodic metrics; shell 30 s thermal/low-power log + vrmc-thermal.log. m5-settings 18 checks PASS; provider suite ALL PASS; shell builds. |
| **M6 offline groundwork (EV-0102)** | **PARTIAL (host/build PASS; device NOT RUN)** | Provider append-only `vrmc-shutdown.log` (init/destroy-start/destroy-complete); `scripts/m6_soak_harness.sh` dry-run PASS + device monitor for crash/hang markers; `scripts/m6_release_manifest.sh` (pins/hashes/licensing/no-binaries, dirty-tree guard); `PRIVACY.md`; `docs/mvp/M6_ACCEPTANCE.md` AC/K matrix. Soak/AC gates NOT RUN. |
| **M5 recenter safety chord (EV-0103)** | **PARTIAL (host PASS) / device NOT RUN** | both-hand middle double-tap (within 120 ms, 300 ms cooldown) → `snapRoomOriginToPlayerEntity(player,false,true)` via reflection; chord cancels per-hand double taps (no simultaneous radial/snap-turn); middle suite 18 checks PASS; provider suite ALL PASS. Device feel/height/world-scale pending. |
| **M5 launcher settings panel (EV-0104)** | **PARTIAL (build PASS) / device NOT RUN** | `VRControlOverlay` DisclosureGroup for seated/free-move/snap-45°/preset/render distance/frame limit; reads/writes `Documents/instances/default/vrmc-runtime.properties`, preserves unknown keys, atomic write + shell log; provider consumes at next launch (EV-0101). Shell build PASS; device UI interaction NOT RUN. |
| **M5 launcher panel extension (EV-0112)** | **PARTIAL (build PASS) / device NOT RUN** | Panel now also edits world scale (0.80–1.50×), auto/manual height (auto = -1, manual 1.30–2.10 m), diagnostics period (10–120 s) in `vrmc-runtime.properties`; load clamps to same ranges, save preserves other keys. Shell builds; device UI/comfort feel NOT RUN. |
| **M5 world-scale/height + command channel (EV-0105)** | **PARTIAL (host/build PASS) / device NOT RUN** | `comfort.worldScale`/`comfort.manualHeight` settings applied; local whitelisted `vrmc-command.txt` (recenter / calibrate-height / reload-settings / diag / status) consumed twice/sec with result journal `vrmc-command-result.txt`; launcher overlay buttons Recenter/Calibrate height/Reload settings/Diagnostics queue them. m5-settings 22 + m5-command 9 checks PASS; provider suite ALL PASS; shell builds. Device behavior NOT RUN. |
| **M5 diagnostics export (EV-0107)** | **PARTIAL (host/build PASS) / device NOT RUN** | Provider writes local `vrmc-status.json` (ABI/bridge/display-views/tracked/seated/input/hands/player/runtime settings); launcher button builds a capped local diagnostics bundle (shell/compositor/thermal/latestlog/status/shutdown/command/settings) and exposes ShareLink for manual save/AirDrop. No automatic upload. Provider suite ALL PASS; shell builds. Device share UI NOT RUN. |
| **M6 crash guard + release check (EV-0108)** | **PARTIAL (host/build PASS) / device NOT RUN** | Shell startup reads `vrmc-shutdown.log`; missing `destroy-complete` increments a crash count and after two consecutive unclean sessions enables `vrmc-safe-mode.flag`, suppressing automatic immersive open (manual Enter VR still available); clean session resets + launcher clear control. `scripts/m6_release_check.sh` PASS on host readiness (licenses/notices/privacy/source dirs/no tracked MC binaries/manifest fields). Device crash behavior/release acceptance NOT RUN. |
| **Latest build staged/installed (EV-0113)** | **PARTIAL (build/install PASS) / behavior NOT RUN** | Latest M4/M5/M6 code built; 169 Mach-O signed (deep/strict verify PASS); app tree sha `3a03076f…` installed on D1; provider jar `fc8cc4b1…` pushed. Device locked at staging, so no runtime/gesture/UI behavior test. |
| **M5 command feedback + live launcher status (EV-0114)** | **PARTIAL (host/build/install PASS) / behavior NOT RUN** | Commands/recenter show a best-effort Minecraft action-bar message via reflection; launcher overlay refreshes a 5 s status line (bridge, displayViewsGen, hands, seated, thermal, low-power) from `vrmc-status.json` + ProcessInfo. Latest app tree sha `46c80630…` installed; provider jar `39e9714a…` pushed. Device locked: behavior NOT RUN. |
| **M4/M6 safety fuzz (EV-0115)** | **PASS (host safety) / device NOT RUN** | Deterministic 20k-frame fuzz of VisionInput (tracking loss, malformed masks, NaN/Inf joints, stale gaps, environment flips) found both-hand chord pulses surviving a lost hand; fixed by clearing both-fist/both-middle chord state immediately when either hand is untracked. 0 violations; full provider suite PASS; updated provider jar pushed. Real-hands no-stuck still needs D1. |
| **M6 bridge concurrency/TSan (EV-0116)** | **PASS (host) / device NOT RUN** | `bridge_shared_test.c`: writer/reader stress for display views (20k), gaze mailbox (20k), tracking override and game-stopping; checks generation monotonicity/payload ranges/consumption; run normal + ThreadSanitizer. Full bridge suite ALL PASS. Device behavior separate. |
| **M5 gesture toggles + reference (EV-0117)** | **PARTIAL (build/install PASS) / device NOT RUN** | Launcher toggles middle-pinch and opt-in swipe gestures (persist to `vrmc-input-tune.properties`), plus gesture cheat sheet; updated app installed (tree `abc48c93…`, provider `d6de9469…`). Shell build/sign/install PASS. Device UI/gesture behavior NOT RUN. |
| **M4-W4 direct hotbar wheel (EV-0118)** | **PARTIAL (host/install PASS) / device NOT RUN** | Both thumb-ring pinches + left-hand horizontal displacement selects slot 1–9, action-bar feedback, release commits via reflective inventory set; ring.enabled/on/off + hotbar.range tuning; ring sources in fuzz invariants. m4-hotbar-wheel 8 + m4-ring-chord 8 checks, fuzz 20k/0, provider suite ALL PASS. Latest app tree `0726af92…` installed; provider `cc24d16b…` pushed. Device feel/commit NOT RUN. |
| **M6 release workflow (EV-0119)** | **PARTIAL (host PASS) / device acceptance NOT RUN** | Clean tree: release check PASS; manifest `dirty_tree=no`; development sideload package built (app + provider + licenses/notices/privacy/README/versions + manifest + INSTALL), sha256 `d583608d…`, 206,308,244 bytes. Device AC/K evidence and final release sign-off remain NOT RUN. |
| **M5/M4 live input reload (EV-0120)** | **PARTIAL (host/install PASS) / device NOT RUN** | `reload-input` command recreates VisionInput from game-dir `vrmc-input-tune.properties` (middle/ring/swipe/thresholds/hotbar range) without restart, resets binding tables, action-bar feedback; launcher button added. Provider suite PASS; app tree `4d55c1b0…` installed; provider `46699ae2…` pushed. Device behavior NOT RUN. |
| **M5 comfort vignette (EV-0122)** | **PARTIAL (build/install PASS) / device NOT RUN** | Compositor flat shader/pipeline darkens periphery by `Documents/vrmc-vignette.flag` strength (0–0.9, read per immersive session, test pattern unaffected); launcher toggle+strength slider writes/removes the flag. Shell/app build/sign/install PASS; runtime shader/comfort appearance NOT RUN. |
| **M5 advanced input tuning UI (EV-0123)** | **PARTIAL (build/install PASS) / device NOT RUN** | Launcher sliders for middle/ring on/off thresholds (mm), swipe speed (m/s), hotbar range (m); saved to `vrmc-input-tune.properties` (metres, off>on enforced, other keys preserved); applies via Reload input or next launch. Shell build/app install PASS (`8ec4b31a…`); device UI/feel NOT RUN. |
| **M4/M5 controls help + reference (EV-0124)** | **PARTIAL (host/install PASS) / device NOT RUN** | `controls` command sends a compact multi-line gesture reference to Minecraft chat via reflection; launcher Controls help button; `docs/mvp/M4_CONTROLS.md` published with current mappings/safety/tuning/gaps. Provider suite PASS; app `17433e3d…` installed; provider `1af22936…` pushed. Device chat UX NOT RUN. |
| **M4 conflict fix + fingertip component option (EV-0125)** | **PARTIAL (host PASS) / device NOT RUN** | Both-fist inventory chord now suppresses continuous `key.use` (single fist still uses; returns when one opens; m4-input 168 checks). Optional `hands.componentMode=joints` attaches the tip component to the index fingertip via host-tested local-offset math (m4-pose 67 checks); default identity preserved. Provider `4fa76795…` pushed. Device visual/behavior NOT RUN. |
| **M4-W2 gaze config opt-in (EV-0126)** | **PARTIAL (build/install PASS) / device NOT RUN** | `ShellLayerConfiguration` tracking-area format/usage and `onSpatialEvent` are only set when `Documents/vrmc-gaze.flag` exists; gaze-off sessions keep the EV-0094 accepted layer config. Shell/app build/install PASS (`926f663d…`); simulator input scenario unusable (immediate backgrounding, same with opt-in); true gaze device behavior NOT RUN. |
| **M5 turn picker + acceptance/runbook (EV-0127)** | **PARTIAL (build/install PASS) / device NOT RUN** | Launcher Turn picker Smooth/15/30/45/90 saved to `comfort.worldRotationIncrement`; `M5_ACCEPTANCE.md` H1–H10 matrix and `M5_DEVICE_RUN.md` D1 procedure published. Shell/app build/install PASS (`a2809f6d…`); device run NOT RUN. |
| **M5 diagnostics viewer + pacing warning (EV-0128)** | **PARTIAL (host/install PASS) / device NOT RUN** | Launcher Recent diagnostics disclosure extracts last error/warn/VRMC lines from compositor/shell/latestlog/status (refresh) and status line shows `providerJar=ok/MISSING`; provider emits a frame-pacing WARN when p95 >16.7 ms or missed90 > max(2, frames/10). Provider suite PASS; app `bcdb5987…` installed; provider `54353013…` pushed. Device UI NOT RUN. |
| **M5 seated HMD pointer parity (EV-0129)** | **PARTIAL (host/install PASS) / device NOT RUN** | Opt-in `comfort.seatedHmdPointer`: when seated and no hand tracked, HMD-aim fallback may drive controller/GUI pointer (`controllerTracking`); input actions still require real gestures. Default off preserves prior behavior. Parser tests 23 checks; provider suite ALL PASS; app `dfc8f9a1…` installed; provider `d07eb84b…` pushed. Device seated pointer NOT RUN. |
| **M5 W1 tuning sliders + status summary (EV-0130)** | **PARTIAL (host/install PASS) / device NOT RUN** | Launcher adds pinch on/off (mm) and fist on/off sliders beside middle/ring/swipe/hotbar (saved with off>on, reloadable); provider `vrmc-status.json` gains `inputTuning` + `hotbarRange`; m4-input 172 checks PASS; app `1981c5ed…` installed; provider `5fa45dc4…` pushed. Device UI/tuning NOT RUN. |
| **M5 thermal pressure awareness (EV-0131)** | **PARTIAL (host/install PASS) / device NOT RUN** | Shell writes game-dir `vrmc-thermal-state.txt`; provider reads it, logs/action-bar advises on `serious`/`critical` changes (no automatic settings), and includes `thermalState` in `vrmc-status.json`. m5-thermal 8 checks; provider suite ALL PASS; app `624cda74…` installed; provider `fc3d98d6…` pushed. Device K5 behavior NOT RUN. |
| **M6 heartbeat watchdog (EV-0132)** | **PARTIAL (build/install PASS) / device NOT RUN** | Compositor writes `vrmc-heartbeat.txt` ≤1 Hz (generation/frame/presented/layer state); shell watchdog logs one stale-heartbeat warning + launcher status if >20 s while immersive+presenting, logs recovery, includes heartbeat in diagnostics export; no auto-kill. Shell/app build/install PASS (`6b013be6…`). Device hang behavior NOT RUN. |
| **M5 thermal quality reduction (EV-0133)** | **PARTIAL (host/install PASS) / device NOT RUN** | Opt-in `performance.thermalResponse=notify|reduce` with launcher picker; on thermal serious/critical with `reduce`, provider caps render/simulation distance ≤8 and frame limit ≤72 once per episode (no auto-restore), logs/actionbar; m5-settings 25 checks; app `c6e05338…` installed; provider `afbbb507…` pushed. Device K5 NOT RUN. |
| **M5 provider hash + settings reset (EV-0134)** | **PARTIAL (build/install PASS) / device NOT RUN** | Launcher status shows provider-jar SHA256 (or MISSING); diagnostics bundle includes hash prefix/path; Reset VRMC settings removes runtime/input/vignette configs (not saves/logs). Shell/app build/install PASS (`b7e7cd63…`); provider unchanged. Device UI NOT RUN. |
| **M5 adaptive framerate (EV-0135)** | **PARTIAL (host/install PASS) / device NOT RUN** | Opt-in `performance.adaptiveFramerate` + launcher toggle: caps frame limit ≤72 once after 2 consecutive over-budget diag windows, logs/actionbar, reports adaptiveFramerate/Applied in status; parser tests 27 checks. App `a8196eda…` installed; provider `4602605f…` pushed. Device K2 pacing NOT RUN. |
| **M6 device provider-integrity check (EV-0136)** | **PASS (integrity only) / behavior NOT RUN** | `scripts/m6_device_integrity.sh` lists installed VRMC (1.2.0) and compares the data-container provider jar SHA256 with the local build: both `4602605f…`, 85,957 bytes => PASS. Read-only, no unlock/launch. Does not verify runtime behavior/acceptance. |
| **M6 device diagnostics pull (EV-0137)** | **PARTIAL (read-only pull) / behavior NOT RUN** | `scripts/m6_device_diagnostics_pull.sh` copies logs/status/config out of the app container without launching. Current D1: 3/18 files; current shell log absent => latest build not launched since install; old compositor log shows a clean earlier session end (4466 frames, game stopping, immersive ended, provider errorCode=0), no crash markers. Behavior NOT RUN. |
| **M5 locomotion tuning sliders (EV-0138)** | **PARTIAL (build/install PASS) / device NOT RUN** | Launcher adds forward/strafe scale, deadzone, originZ and snap-turn pulse sliders writing `move.*` keys to `vrmc-input-tune.properties` (other keys preserved; reloadable); shell/app build/install PASS (`cfaf72c7…`); provider unchanged. Device locomotion feel NOT RUN. |
| **M6 acceptance readiness gate (EV-0139)** | **NOT READY (report only)** | `scripts/m6_acceptance_report.sh` parses M5/M6 acceptance matrices; `--require-pass` exits non-zero unless all rows explicit PASS. Current report: rows=22 pass=0 partial=3 not-run=11 => NOT READY (device gates NOT RUN). Snapshot `export/acceptance-readiness.txt`. No device claims. |
| **M5 command-result feedback + Status button (EV-0140)** | **PARTIAL (build/install PASS) / device NOT RUN** | Launcher shows the last `vrmc-command-result.txt` line and adds a Status button queueing the existing status command; shell/app build/install PASS (`e82a7a89…`); provider unchanged. Device UI NOT RUN. |
| **M4 use/attack priority (EV-0141)** | **PARTIAL (host PASS) / device NOT RUN** | While right fist holds continuous use/bow draw, `key.attack` is suppressed even if pinch reads pressed during finger transition; use stays held and attack returns when the fist opens. m4-input 176 checks; full suite PASS; provider `94f868e8…` pushed and verified on device (85,963 bytes). Device feel NOT RUN. |
| **M4-W2 tracking pose hold (EV-0142)** | **PARTIAL (host/install PASS) / device NOT RUN** | On hand dropout, last valid controller pose is held for `tracking.holdLastPoseMs` (default 250 ms; 0–2000, launcher slider) before shoulder fallback; actions still release (`controllerTracking=false`), one throttled log per hand. Provider suite PASS; app `79b7a0cf…` installed; provider `7a9a1118…` pushed + integrity PASS. Device visual/aim behavior NOT RUN. |
| **M6 source offer + refreshed dev package (EV-0143)** | **PARTIAL (host PASS) / device acceptance NOT READY** | `SOURCE_OFFER.md` (GPL/LGPL corresponding source, 3-year written offer, no Minecraft/Vivecraft redistribution) now required by release check and included with M4/M5/M6 docs in the package. Clean-tree: release check PASS, manifest `dirty_tree=no`, package `/tmp/VRMC-dev-release.zip` bytes=206,440,226 sha256 `7cfc1433…`; device provider integrity PASS. Device AC/K/H gates NOT RUN/NOT READY. |
| **M5 status JSON fix + provider summary (EV-0144)** | **PARTIAL (host/install PASS) / device NOT RUN** | Fixed invalid `vrmc-status.json` (`adaptiveFramerateApplied` stray quote); launcher parses status each refresh and shows abi/bridge/tracked/hands/thermal/adaptive line, empty on invalid/missing. Provider suite PASS; app `748e730e…` installed; provider `9aeff79d…` pushed + integrity PASS. Device UI NOT RUN. |
| **M5 testable status JSON builder (EV-0145)** | **PARTIAL (host PASS) / device NOT RUN** | `VisionStatusJson` pure builder now owns `vrmc-status.json` (escaping/finite numbers); strict JSON-parser test covers field values/types, quote/backslash/control escapes and the EV-0144 trailing-quote regression (12 checks). Full provider suite PASS; provider `8a6f769a…` pushed + integrity PASS. Device behavior NOT RUN. |
| **M5 thermal poll throttle (EV-0146)** | **PARTIAL (host PASS) / device NOT RUN** | `pollThermalState()` no longer reads `vrmc-thermal-state.txt` every frame; throttled to 5 s (shell writes at thermal-change/30 s cadence), first call immediate, advisory logic unchanged. Provider suite PASS; provider `e66266dd…` pushed + integrity PASS. Device performance NOT RUN. |
| **M5 allocation-free frame paths (EV-0147)** | **PARTIAL (host PASS) / device NOT RUN** | Display-view eye transforms reuse a 16-float scratch array; locomotion uses an allocation-free `axes(..., Vector2f dest)` that always overwrites (no stale axes on bad input); m4-locomotion 9 checks. Provider suite PASS; provider `30ec7452…` pushed + integrity PASS. Device runtime/GC performance NOT RUN. |
| **M5 frame pacing in status JSON (EV-0148)** | **PARTIAL (host/install PASS) / device NOT RUN** | Status JSON adds frameP50Ms/frameP95Ms/missed90Frames from the last diagnostic window; launcher provider line shows p95/missed90; strict JSON test 15 checks. App `46756212…` installed; provider `57ddc366…` pushed + integrity PASS. Device K2 pacing NOT RUN. |
| **M6 soak harness hardening (EV-0149)** | **PARTIAL (host PASS) / device soak NOT RUN** | Soak now pulls the real game log (`instances/default/logs/latest.log`) plus heartbeat/status, flags OOM/watchdog, and fails if `destroy-complete` is missing in the shutdown journal (AC-5; override for still-running probes). Release check runs soak `--dry-run`. Bash -n/dry-run/release check PASS; device soak NOT RUN. |
| **M6 install metrics + device runbook (EV-0150)** | **PARTIAL (host metrics/runbook) / device gates NOT RUN** | Host metrics: app 583,553,024 bytes / 485 files / 169 Mach-O; provider 89,469 bytes `57ddc366…`; package 206,440,226 `7cfc1433…`. `M6_DEVICE_RUN.md` covers AC-1…AC-6/K1…K6 procedures, commands, evidence rules. Device install-size/K gates NOT RUN. |
| **M5 reload-input completeness fix (EV-0151)** | **PARTIAL (host PASS) / device NOT RUN** | `reload-input` recreated VisionInput/hotbar only; now also reloads smoothing, move origin/scales/deadzone/rotate pulse, `tracking.holdLastPoseMs`, `hands.componentMode`, rebuilds smoothers, cancels in-progress hotbar wheel, logs tuning, reports hold/move/components in result. Provider suite PASS; provider `a4cf0507…` pushed + integrity PASS. Device live-reload behavior NOT RUN. |
| **M4 tuning validation (EV-0152)** | **PARTIAL (host PASS) / device NOT RUN** | Hand-edited `vrmc-input-tune.properties` is validated: inverted on/off pairs, tap/double, stale<=arm restored to defaults with warning; speed/ratio/cooldown/hold/arm/stale/tap frames clamped. Invalid-file host test; m4-input 184 checks. Provider suite PASS; provider `cd7eacb7…` (90,619 bytes) pushed + integrity PASS. Device behavior NOT RUN. |
| **M6 async heartbeat write (EV-0153)** | **PARTIAL (build/install PASS) / device NOT RUN** | Heartbeat stays throttled ≤1 Hz on the frame thread but the atomic file write is dispatched to a utility QoS queue; render thread does no watchdog filesystem I/O. A dropped final write on abrupt death simply yields a stale heartbeat. Shell/app build/install PASS (`0aebb806…`); provider unchanged. Device runtime NOT RUN. |
| **M6 reproducible provider jar (EV-0154)** | **PARTIAL (host PASS) / device NOT RUN** | `build_provider.sh` fixes jar entry timestamps (`--date`, override `REPRO_TIMESTAMP`); two independent builds both `fcd1df76…` (90,619 bytes). Provider suite PASS; canonical jar pushed + device integrity PASS. Release manifest/package hashes need regeneration to the new provider hash. Device behavior NOT RUN. |
| **M6 reproducibility check + refreshed package (EV-0155)** | **PARTIAL (host PASS) / acceptance NOT READY** | `scripts/m6_reproducibility_check.sh`: two builds both `fcd1df76…` PASS. Clean-tree release check PASS; package refreshed bytes=206,459,027 sha256 `3b3fa4fe…` with app `0aebb806…` + provider `fcd1df76…`; manifest dirty_tree=no; acceptance NOT READY; device gates NOT RUN. |
| **M6 release check verifies reproducibility (EV-0156)** | **PASS (host readiness)** | `m6_release_check.sh` now runs `m6_reproducibility_check.sh` and reports the provider hash; mismatch fails host readiness. Current: PASS, provider `fcd1df76…`. Device acceptance remains separate/NOT READY. |
| **M5 fingertip component toggle (EV-0157)** | **PARTIAL (build/install PASS) / device NOT RUN** | Launcher Input tuning adds an experimental toggle for `hands.componentMode=joints|identity`, saved to `vrmc-input-tune.properties` and applied via Reload input/next launch; default identity preserves the accepted aim path. Shell/app build/install PASS (`25c1bac1…`); provider unchanged. Device visible-hands/held-item appearance NOT RUN. |
| **M5 reset-settings confirmation (EV-0158)** | **PARTIAL (build/install PASS) / device NOT RUN** | Destructive `Reset VRMC settings` now opens a confirmation dialog (Reset/Cancel) explaining scope (runtime/input/vignette only; saves/logs/crash guard kept). Shell/app build/install PASS (`1400889b…`); provider unchanged. Device dialog interaction NOT RUN. |
| **M5 diagnostics bundle completeness (EV-0159)** | **PARTIAL (build/install PASS) / device NOT RUN** | Bundle now also captures `vrmc-input-tune.properties`, `vrmc-thermal-state.txt`, `vrmc-vignette.flag` and the real Minecraft log `instances/default/logs/latest.log` alongside logs/status/shutdown/command/heartbeat/settings/crash artifacts. Shell/app build/install PASS (`a046bab6…`); provider unchanged. Device export/share UI NOT RUN. |
| **M6 refreshed dev package (EV-0160)** | **PARTIAL (host PASS) / acceptance NOT READY** | Clean-tree release check PASS, reproducibility PASS; package refreshed to latest app `a046bab6…` + provider `fcd1df76…`: bytes=206,458,384 sha256 `4f89d0d6…`; manifest dirty_tree=no. Acceptance NOT READY; device AC/K/H gates NOT RUN. |
| **M6 acceptance parser fix (EV-0161)** | **NOT READY (report correctness fixed)** | M6 rows were parsed from the evidence cell, not the status cell; now M5 last-cell/M6 status-cell parsing with backtick cleanup. Accurate: rows=22, explicit-pass=0, not-run=17, partial=7; `--require-pass` still NOT READY. Device gates NOT RUN. |
| **M4/M6 input fuzz 100k (EV-0162)** | **PARTIAL (host PASS) / device NOT RUN** | Fuzz frame count via `VRMC_FUZZ_FRAMES` (default 20k, cap 2M); per-frame invariants now include ring chord when either hand untracked, attack/teleport suppression under right fist, and use suppression under both fists. 100,000 frames, 0 violations; full provider suite PASS. Device behavior NOT RUN. |
| **Extreme stress 1M + TSan (EV-0163)** | **PARTIAL (host PASS) / device NOT RUN** | Provider fuzz at 1,000,000 frames / 0 violations (6.0 s). Full bridge suite incl. TSan: ALL PASS; concurrent sync 200k×4, tracking/display 500k, input 500k×4 with millions of reads and no torn state. Host-only; device gates NOT RUN. |
| **M6 path-independent app hash + package verifier (EV-0164)** | **PARTIAL (host PASS) / acceptance NOT READY** | App tree hash now bundle-relative/path-independent (`d1d68596…`); manifest regenerated; package bytes=206,459,032 sha256 `46b14b6a…`; verifier PASS (entries + app/provider hashes vs manifest + dirty_tree=no). Older app hashes (absolute paths) are not comparable. Device gates NOT RUN. |
| **M6 single-command release gate (EV-0165)** | **NOT RELEASE READY (expected)** | `m6_release_ready.sh` runs release check + package verifier + read-only device integrity + acceptance gate. Current: host/package/device-integrity PASS; acceptance 0/22 explicit PASS → exit 1 NOT RELEASE READY. Correct expected state until D1 acceptance. |
| **M4 pose numerical fuzz 200k (EV-0166)** | **PARTIAL (host PASS) / device NOT RUN** | Randomized finite/degenerate joints+quats+translations (zero, 1e-30, ±1e20, ±100): 200,000 cases, 0 non-finite, 0 violations; output basis unit/orthogonal/det≈+1, translation preserved, tipOffset/gazeFallback finite. Full provider suite PASS. Device behavior NOT RUN. |
| **M4 smoother numerical fuzz 100k (EV-0167)** | **PARTIAL (host PASS) / device NOT RUN** | Random normalized rotations, translations ±1e4/1e20, forward/duplicate/zero timestamps and periodic resets: 100,000 cases, 0 violations; outputs finite + rotation basis unit. Full provider suite PASS. Device behavior NOT RUN. |
| **M5 status JSON fuzz 100k (EV-0168)** | **PARTIAL (host PASS) / device NOT RUN** | Arbitrary strings (control chars/quotes/backslashes/BMP unicode/empty) in 3 fields + random ints/bools + NaN/Inf/huge hotbarRange: 100,000 build/parse round-trips, 0 violations; shared strict TestJson parser; status-json regression 15 checks PASS. Device behavior NOT RUN. |
| **M5 runtime-settings fuzz 100k (EV-0169)** | **PARTIAL (host PASS) / device NOT RUN** | 100,000 random maps over known/unknown keys with empty/boolean/NaN/Infinity/huge/negative/string values: no exceptions; applied values stay within documented bounds (rotation/scale/height/render/sim/fps/diagnostics/thermal/preset). Full provider suite PASS. Device behavior NOT RUN. |
| **M5 command-file size cap (EV-0170)** | **PARTIAL (host PASS) / device NOT RUN** | `VisionCommandFile.take` rejects >4096-byte files before `readString`, deletes them and records a REJECTED oversized result; host test covers rejection/consumption/result (m5-command 14 checks). Provider `bad3d955…` (90,791 bytes) pushed + integrity PASS. Device behavior NOT RUN. |
| **M6 refreshed package + verifier/gate (EV-0171)** | **PARTIAL (host PASS) / acceptance NOT READY** | Clean-tree release check/repro PASS; package bytes=206,459,555 sha256 `6e99d8e9…` (app d1d68596…, provider bad3d955…); package verifier PASS; release-ready host/package/device-integrity PASS, acceptance NOT READY (expected). Device gates NOT RUN. |
| **M6 settings-key parity guard (EV-0172)** | **PASS (host readiness)** | `check_settings_keys.sh` extracts all 31 launcher-written runtime/input keys and requires provider recognition; release check now runs it and reports PASS. Prevents silent UI/provider drift. Device gates NOT RUN. |
| **M6 status-field parity guard (EV-0173)** | **PASS (host readiness)** | `check_status_fields.sh` extracts the 11 `obj["..."]` fields the launcher reads and requires `VisionStatusJson` to write each; release check runs it and reports PASS. Prevents status/UI drift. Device gates NOT RUN. |
| **M4/M5 bow telemetry (EV-0174)** | **PARTIAL (host/install PASS) / device NOT RUN** | Status JSON adds `bowActive`/`bowNotched`/`bowDrawPercent` from `dh.bowTracker`; launcher shows `bow=notched NN%` while active; JSON tests 18 checks + 100k fuzz; status-field guard checked=14; app `6e4b7c5e…` installed; provider `47713964…` pushed + integrity PASS. Device two-hand bow behavior NOT RUN. |
| **M6 refreshed package/metrics for bow build (EV-0175)** | **PARTIAL (host PASS) / acceptance NOT READY** | Package refreshed: bytes=206,462,210 sha256 `8a82159e…` (app `6e4b7c5e…`, provider `47713964…`); verifier/release-ready host gates PASS; acceptance NOT READY. Metrics: app 583,630,848 bytes/485 files/169 Mach-O; provider 91,130 bytes. Device gates NOT RUN. |
| **M4/M5 climb telemetry (EV-0176)** | **PARTIAL (host/install PASS) / device NOT RUN** | Status JSON adds `climbGrabbing`/`climbeyClimb`/`climbActive` from `dh.climbTracker`; launcher shows climb state when active. JSON regression 21 checks + 100k fuzz; status-field guard checked=17; app `90c83c0d…` installed; provider `1d36487e…` (91,427 bytes) pushed + integrity PASS. Device H9 NOT RUN. |
| **M6 refreshed package/metrics for climb build (EV-0177)** | **PARTIAL (host PASS) / acceptance NOT READY** | Package refreshed: bytes=206,468,279 sha256 `9720b652…` (app `90c83c0d…`, provider `1d36487e…`); verifier/release-ready host gates PASS; acceptance NOT READY; metrics refreshed (app 583,630,848 bytes; provider 91,427 bytes). Device gates NOT RUN. |
| **M5 restore-performance command (EV-0178)** | **PARTIAL (host/install PASS) / device NOT RUN** | Provider captures pre-cap render/sim/fps; `restore-performance` restores once, clears applied flags/pressure, logs/action-bar; launcher button added; m5-command 15 checks; app `2939c509…` installed; provider `5379fe2c…` (92,008 bytes) pushed + integrity PASS. Device restore behavior NOT RUN. |
| **M6 refreshed package for restore build (EV-0179)** | **PARTIAL (host PASS) / acceptance NOT READY** | Package refreshed to app `2939c509…` + provider `5379fe2c…`: bytes=206,470,289 sha256 `20ffc04d…`; verifier/release-ready host gates PASS; acceptance NOT READY; metrics refreshed. Device gates NOT RUN. |
| **M6 stale-package guard (EV-0180)** | **PASS (host readiness)** | `m6_check_release_current.sh` compares embedded manifest app/provider hashes with current builds; release gate runs it before package verification. Current package app `2939c509…`/provider `5379fe2c…` match → freshness PASS; host gates PASS; acceptance NOT READY. Device gates NOT RUN. |
| **M6 status/handoff doc (EV-0181)** | **PARTIAL (documentation)** | Added `docs/mvp/STATUS.md`: current build identity, milestone states, feature summary, host verification commands/results, remaining device-only procedures, known risks; linked from README. No device claims; AC/K/H gates NOT RUN. |
| **M5 auto status JSON writes (EV-0182)** | **PARTIAL (host PASS) / device NOT RUN** | Provider writes `vrmc-status.json` automatically on first update with a game directory and after each diagnostic window, so launcher/support diagnostics stay current without the Status command. Full provider suite PASS; reproducible provider `702e7193…` (92,084 bytes) pushed + integrity PASS. Device behavior NOT RUN. |
| **M6 refreshed package for auto-status build (EV-0183)** | **PARTIAL (host PASS) / acceptance NOT READY** | Package refreshed to app `2939c509…` + provider `702e7193…`: bytes=206,470,666 sha256 `f6a687ac…`; freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics refreshed. Device gates NOT RUN. |
| **M5 auto-sprint settings (EV-0184)** | **PARTIAL (host/install PASS) / device NOT RUN** | `comfort.autoSprint` + `comfort.autoSprintThreshold` (0.5–1.0) applied to Vivecraft `autoSprint`/`autoSprintThreshold`, launcher toggle+slider; parser 29 checks; settings-key guard checked=33; app `2388965a…` installed; provider `a109ae56…` (92,516 bytes) pushed + integrity PASS. Device sprint feel NOT RUN. |
| **M6 refreshed package for auto-sprint build (EV-0185)** | **PARTIAL (host PASS) / acceptance NOT READY** | Package refreshed to app `2388965a…` + provider `a109ae56…`: bytes=206,471,014 sha256 `bc497dfe…`; freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics + STATUS.md updated. Device gates NOT RUN. |
| **M4 gaze math fuzz 500k (EV-0186)** | **PARTIAL (host PASS) / device NOT RUN** | Invalid/negative/huge tiles/grids, finite random tangents/NDC, random rotations/positions, zero/huge scale/aspect: 500,000 cases, 0 violations; tileToNdc null-or-in-range, eyeRay finite normalized, intersectGuiPlane null-or-in-[0,1]. Full provider suite PASS. Device gaze behavior NOT RUN. |
| **M6 release gate default app freshness (EV-0187)** | **PASS (host readiness)** | `m6_release_ready.sh` now defaults `RELEASE_APP_BUNDLE` from `export/latest-build-identity.txt`'s staged app path, so freshness checks both app tree and provider hashes without overrides. Current match app `2388965a…`/provider `a109ae56…`; host gates PASS; acceptance NOT READY. |
| **Consolidated host regression (EV-0188)** | **PARTIAL (host PASS) / acceptance NOT READY** | Shell build, provider suite (all fuzz), bridge suite incl. TSan, M4 selfcheck --fast, release check, package verifier/freshness, device integrity all PASS; release-ready host gates PASS; acceptance 0/22 NOT READY; device AC/K/H NOT RUN. |
| **M4 plan host-complete status doc (EV-0189)** | **PARTIAL (documentation)** | M4_PLAN 6w summarizes host-complete W4/W5 work (hotbar 1–9, use/hold conflicts, bow/climb telemetry, swipes, visible-hands options, fuzz/safety) and explicitly lists device-only remainder (AC-4 real hands, feel tuning, visible appearance). No behavior changes; device gates NOT RUN. |
| **M4-W5 guided hand calibration (EV-0190)** | **PARTIAL (host/install PASS) / device NOT RUN** | `VisionHandCalibration` 3×3 s open/fist/pinch protocol samples pinch/fist min-max, suggests thresholds/report; `calibrate-hands` command prompts action bar, writes `vrmc-hand-calibration.txt`; launcher button + diagnostics entry. m4-hand-calibration 15 checks, m5-command 16; guards PASS; app `b0680cac…` installed; provider `a4212200…` (95,870 bytes) pushed + integrity PASS. Device calibration NOT RUN. |
| **Calibration journal feedback + package refresh (EV-0191)** | **PARTIAL (host PASS) / acceptance NOT READY** | Calibration completion writes the one-line suggestion to `vrmc-command-result.txt` (launcher Last result). Package refreshed to app `b0680cac…` + provider `18029045…`: bytes=206,479,055 sha256 `9540a8a9…`; freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics/STATUS updated. Device gates NOT RUN. |
| **M4-W5 apply-hand-calibration (EV-0192)** | **PARTIAL (host/install PASS) / device NOT RUN** | `parseReport/applyReport` applies pinch/fist thresholds to `vrmc-input-tune.properties` preserving unrelated keys atomically; `apply-hand-calibration` command reloads input engine; launcher button. m4-hand-calibration 22 checks, m5-command 17; app `595982a2…` installed; provider `50cd776b…` (98,928 bytes) pushed + integrity PASS; package bytes=206,483,529 sha256 `4e1d9982…`; host gates PASS; acceptance NOT READY. Device apply behavior NOT RUN. |
| **M5 targeted reset input tuning (EV-0193)** | **PARTIAL (build/install PASS) / device NOT RUN** | Launcher `Reset input tuning` confirmation removes only `vrmc-input-tune.properties`, reloads UI defaults and queues `reload-input`; runtime/comfort/saves/logs/crash guard untouched. Shell/app build/install PASS (`f1ae3749…`); provider unchanged `50cd776b…` + integrity PASS. Device UI NOT RUN. |
| **M6 refreshed package for targeted-reset build (EV-0194)** | **PARTIAL (host PASS) / acceptance NOT READY** | Package refreshed to app `f1ae3749…` + provider `50cd776b…`: bytes=206,486,820 sha256 `efe71843…`; freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics/STATUS updated. Device gates NOT RUN. |
| **M4 raw-gesture diagnostics (EV-0195)** | **PARTIAL (host/install PASS) / device NOT RUN** | Status JSON adds compact `gestures` (per-hand pinch/fist/middle/ring/swipe + ring chord), launcher shows it only when non-empty for stuck-gesture/AC-4 debugging. m4-input 187 checks; status-field guard checked=18; app `7d36ce9e…` installed; provider `27155fd1…` (99,404 bytes) pushed + integrity PASS. Device behavior NOT RUN. |
| **M4/M5 release-input panic (EV-0196)** | **PARTIAL (host/install PASS) / device NOT RUN** | `release-input` resets the gesture engine/bindings/hotbar wheel/snap-turn pulse to release all held actions; gestures re-arm on fresh input; action-bar/log feedback + launcher button. m5-command 18 checks; full suite PASS; app `cf231fc7…` installed; provider `4587b5d2…` (99,576 bytes) pushed + integrity PASS. Device behavior NOT RUN. |
| **M6 round-100 package refresh (EV-0197)** | **PARTIAL (host PASS) / acceptance NOT READY** | Package refreshed to app `cf231fc7…` + provider `4587b5d2…`: bytes=206,493,046 sha256 `7e9e608c…`; freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics/STATUS updated. Device gates NOT RUN. |
| **M5/M6 acceptance checklist UI (EV-0198)** | **PARTIAL (build/install PASS) / device NOT RUN** | Launcher checklist tracks H1–H10 + AC-1..6 as NOT RUN/PARTIAL/PASS/FAIL, saves `vrmc-acceptance-checklist.json`, included in diagnostics export. Shell/app build/install PASS (`1990b20b…`); provider unchanged `4587b5d2…` + integrity PASS. Device interaction/export NOT RUN. |
| **M5/M6 checklist Markdown export (EV-0199)** | **PARTIAL (build/install PASS) / device NOT RUN** | Saving checklist also writes `vrmc-acceptance-summary.md` (Markdown table ready for VERIFY); diagnostics exports JSON + MD. Shell/app build/install PASS (`73dee838…`); provider unchanged `4587b5d2…` + integrity PASS. Device interaction NOT RUN. |
| **M5/M6 checklist status counts (EV-0200)** | **PARTIAL (build/install PASS) / device NOT RUN** | Checklist header shows `PASS/PARTIAL/FAIL/NOT RUN` counts at a glance. Shell/app build/install PASS (`a4663e16…`); provider unchanged `4587b5d2…` + integrity PASS. Device interaction NOT RUN. |
| **M6 refreshed package for checklist-summary build (EV-0201)** | **PARTIAL (host PASS) / acceptance NOT READY** | Package refreshed to app `a4663e16…` + provider `4587b5d2…`: bytes=206,538,366 sha256 `4d9141f0…`; freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics/STATUS updated. Device gates NOT RUN. |
| **Final consolidated host regression (EV-0202)** | **PARTIAL (host PASS) / acceptance NOT READY** | Shell build, provider suite, bridge suite, M4 selfcheck --fast, release check, package freshness/verifier, device integrity, release-ready host gates all PASS; acceptance 0/22 NOT READY. Device AC/K/H gates NOT RUN. |
| **M6 checklist importer (EV-0203)** | **PARTIAL (host fixtures PASS) / device pull NOT RUN** | `m6_import_device_checklist.sh` pulls (or `--input`) the in-headset checklist JSON, validates statuses, writes `export/device-acceptance-report.md` + machine status; `--require-no-fail` exits 10 on FAIL. Host fixtures: normal 3 rows, FAIL exit 10, bogus rejected, missing input safe; fixed an arg-loop hang. Device pull/import NOT RUN. |
| **M6 checklist FAIL release gate (EV-0204)** | **PARTIAL (host PASS) / device NOT RUN** | `m6_check_device_checklist.sh`: missing SKIP, FAIL exit1, incomplete exit2, all PASS exit0; release-ready runs it (FAIL fails host, incomplete notes). Host fixtures pass; fixture-generated exports removed; release-ready correctly SKIPs with no device checklist; acceptance NOT READY. |
| **M6 K6 JRE-pruned lite package (EV-0205/0206)** | **PARTIAL (host measurement PASS) / device NOT RUN** | Experimental `VRMC_KEEP_JRE=25` staging: app 245,747,712 bytes/72 Mach-O (vs 583,630,848/169), codesign verify PASS; clean lite measurement package bytes=89,919,699 sha256 `db3f6a48…`, verifier PASS. Canonical app/package/metadata unchanged. Device launch/JRE selection NOT RUN. |
| **M6 device JRE probe (EV-0207)** | **PARTIAL (read-only device evidence)** | Device `Documents/java_runtimes` empty; selected profile `fabric-loader-0.20.1-26.2`; pulled `hs_err_pid2642.log` shows OpenJDK **25.0.4** loaded from app-bundled `java_runtimes/java-25-openjdk`; launcher prefs map internal runtimes 8/17/21/25. Pruning 8/17/21 is likely safe for MC 26.2, but lite launch still NOT RUN; canonical build unchanged. |
| **M6 lite JRE binary analysis (EV-0208)** | **PARTIAL (host analysis) / lite launch NOT RUN** | Launcher binary resolves `java_runtimes/java-%@-openjdk` dynamically (`requiredJavaVersion`, `java_homes`); no hardcoded java-8/17/21 directory refs in Mach-O executables. Combined with EV-0207, pruning 8/17/21 is very likely safe; lite launch remains NOT RUN. |
| **DEVICE BUG FIX: VR init format crash (EV-0209)** | **PARTIAL (fix host PASS; device retest REQUIRED)** | User-reported `IllegalFormatConversionException: f != Long` at `VisionVR.init` line 262: startup locomotion log printed `swipeCooldownMillis()` (long) with `%.0f`. Fixed via host-tested `VisionLogFormat.locomotionLine` with explicit types (`m4-log-format` 6 checks). Full provider suite PASS; provider `5fe2a842…` (100,378 bytes) pushed + device integrity PASS; app unchanged. Retest requires relaunching the game. |
| **DEVICE BUG FIX #2: init-time status NPE (EV-0210)** | **PARTIAL (fix host PASS; device retest REQUIRED)** | After EV-0209 was verified installed and advanced init, device latestlog showed NPE `ClimbTracker.isActive -> isClimbeyClimb -> VisionVR.writeStatusReport:340` from `VisionVR.init:275`: auto-status write ran before `dh.vrPlayer/trackers` existed. Removed init-time status write (first update writes it) and guarded bow/climb fields with `vrPlayer != null`. Provider `adeca91c…` (100,374 bytes) pushed + integrity PASS; relaunch required. |
| **DEVICE BUG FIX #3: first status write null player (EV-0211)** | **PARTIAL (fix host PASS; device retest REQUIRED)** | Latest device run now reaches `VisionVR.init() succeeded`, renderer/eye targets/tracking/input/bindings OK. New NPE on first poll status write: `ClimbTracker.isClimbeyClimb` dereferences null `mc.player` via `writeStatusReport:344 -> poll:853`. Added player-null guard for that field. Provider `e9f97a60…` (100,383 bytes) pushed + integrity PASS; relaunch required. |
| **DEVICE first successful played session (EV-0212)** | **PARTIAL DEVICE PASS (launch/presentation/input smoke)** | Operator played; latestlog no exceptions; hands tracked/input healthy/player present; displayViewsGen 10421, trackedFrames 12446; compositor flat eyes=1 anchor=1 presentedFrames=12199; p50 8.34 ms / p95 9.24 ms, missed90=3/3586; clean `destroy-complete` no exception; thermal nominal. Full H/AC/K checklist NOT recorded. |
| **M7 accepted MENU_RIGHT_PINCH dataset (EV-0213)** | **PARTIAL (data accepted; device A/B pending)** | 31.23 s / 563 samples from Gesture Lab; picker stayed IDLE, canonical relabel `MENU_RIGHT_PINCH` (`sourceLabel=IDLE`). Right hand 563/563 tracked; pinch p05/p50/p95 0.006/0.083/0.148 m, min 0.002; 112 frames <0.030 m; **42 pinch events**; 0.030 on / 0.045 off consistent. Raw JSONL local/gitignored; summary+analysis tracked. |
| **M7 accepted ESCAPE_LEFT_FIST dataset (EV-0215)** | **PARTIAL (data accepted; device A/B pending)** | New 31.18 s/561-sample recording; label picker stayed MENU_RIGHT_PINCH but data is left-fist-only: left tracked 561/561, left fist curl p05/p50/p95=0.298/0.905/0.983, 146 frames <0.55, **24 left-fist events** 0.22–0.67 s, right fist 0 frames. Canonical copy relabelled ESCAPE_LEFT_FIST. Lab label UI made prominent + Record 60s; rebuilt/installed. |
| **M7 accepted WALK_BOTH_FISTS dataset (EV-0216)** | **PARTIAL (data accepted; device A/B pending)** | 30.97 s/558 samples; both fists 420/558 (75%); fist p50 L/R 0.359/0.348; wrist-to-head z range 0.788/0.645 m; **z correlation −0.73** (opposite phase), ~25 cycles (~0.8 Hz); head tracked 558/558 with full 4×4 transform. Pickers stayed MENU_RIGHT_PINCH; canonical copy relabelled WALK_BOTH_FISTS. Lab default now JUMP_HEAD for next capture. |
| **M7 accepted JUMP_HEAD dataset (EV-0217)** | **PARTIAL (data accepted; device A/B pending)** | 80.03 s/923 samples; head 923/923 tracked; head Y 1.057–1.809 m; **29 head-rise events** >0.08 m; peaks 0.11–0.30 m; durations mostly 0.27–0.95 s; upward velocity p95 1.51 m/s. Starting detector baseline EMA + 0.08 m rise/0.25 m/s. Lab default now SNEAK_HEAD. |
| **M7 accepted SNEAK_HEAD dataset (EV-0218)** | **PARTIAL (data accepted; device A/B pending)** | 31.00 s/524 samples; head 524/524 tracked; head Y 0.779–1.509 m; **5 downward events** >0.10 m, depths 0.10–0.25 m; two ~4.9 s held crouches; max speed 1.66 m/s. Starting detector: baseline EMA + 0.10 m drop/350 ms, 250 ms release. Lab default now TELEPORT_LEFT_PINCH. |
| **M7 accepted TELEPORT_LEFT_PINCH datasets (EV-0219)** | **PARTIAL (data accepted; device A/B pending)** | Two samples: 31.09 s/551 and 38.97 s/703; left tracked 484/629; **16 left-pinch events** total; holds from quick taps to 4.56 s aimed holds; 0.030 on/0.045 off. Analyzer now reports left-pinch stats/events. Teleport semantics: press starts aim, release commits, open/tracking loss cancels. Lab default now ATTACK_RIGHT_SWING. |
| **M7 accepted ATTACK_RIGHT_SWING dataset (EV-0220)** | **PARTIAL (data accepted; device A/B pending)** | 31.41 s/520 samples; right 503 tracked, left 25 (one-handed); wrist speed p50/p95/max 1.30/2.97/4.75 m/s; acceleration p50/p95/max 5.85/21.39/50.61 m/s²; 228 frames >1.4 m/s, 186 >8 m/s², ~28 swings. Starting detector: right speed >1.4 m/s or accel >8 m/s², one-handed, not both-fist/GUI/bow/eat/climb. Lab default now EAT_RIGHT_HAND_HEAD. |
| **M7 accepted EAT_RIGHT_HAND_HEAD dataset (EV-0221)** | **PARTIAL (data accepted; device A/B pending)** | 30.85 s/455 samples; right 386 tracked, head 455; wrist→head p05/p50/p95=0.218/0.283/0.734 m; 181 frames <0.28 m; **11 near-head events** 0.22–6.04 s. Starting detector ~0.28 m + 250 ms latch, edible context, stop >0.35 m. Lab default now BOW_BOTH_FISTS. |
| **M7 accepted BOW_BOTH_FISTS dataset (EV-0222)** | **PARTIAL (data accepted; device A/B pending)** | 46.66 s/819 samples; left/right 695/758 tracked; wrist separation 0.156–1.049 m; **16 draw/release cycles** >0.55 m; left fist p50 0.349, right p50 0.479/p95 0.983 (release hand opens). Starting detector: both fists + separation >0.55 m, release on back-hand open, walk suppressed in bow context. Lab default now PLACE_RIGHT_PINCH. |
| **M7 accepted PLACE_RIGHT_PINCH short-pinch dataset (EV-0223)** | **PARTIAL (data accepted; device A/B pending)** | 59.19 s/1062 samples; right 1055 tracked; 76 pinch events; **72 short <0.35 s** (mostly 0.11–0.22 s), 4 long outliers (4.06/3.39/0.63/0.61 s) excluded from the place fit. Short pinch = place/select; held pinch = break semantics. Lab default now BREAK_RIGHT_PINCH_HOLD. |
| **M7 accepted BREAK_RIGHT_PINCH_HOLD dataset (EV-0224)** | **PARTIAL (data accepted; device A/B pending)** | 31.11 s/588 samples; right 588/588 tracked; 7 held-pinch events **1.21–10.44 s**, no short taps; 470 frames <0.03 m. Split validated: <0.35 s = place/select, ≥0.35 s = break/mine; long 10.44 s hold for stability. Lab default now INVENTORY_BOTH_FISTS. |
| **M7 accepted INVENTORY_BOTH_FISTS dataset (EV-0225)** | **PARTIAL (data accepted; device A/B pending)** | 31.14 s/562 samples; both hands 562/562 tracked; **24 both-fist tap runs 0.06–0.28 s** (left/right matched); 75 frames both fists closed; hand separation 0.264–0.436 m. Rule: both fists close together <0.35 s without sustained alternating swing → inventory. Lab default now HOTBAR_RIGHT_TAP. |
| **M7 accepted HOTBAR_RIGHT_TAP dataset (EV-0226)** | **PARTIAL (data accepted; device A/B pending)** | 30.94 s/558 samples; right 558 tracked; the tap is **fingertip**, not wrist: wrist max 0.65 m/s, right index-tip p95/p99 1.28/2.66 m/s, accel p95 20.8; **22 index-finger tap events 0.05–0.22 s**. Rule: quick right index tap selects next slot, double tap back; suppress while walking/bow/GUI. Lab default now CLIMB_ALTERNATE. |
| **M7 accepted CLIMB_ALTERNATE dataset; all 14 actions collected (EV-0227)** | **PARTIAL (all datasets accepted; device A/B pending)** | 31.09 s/561 samples; left/right tracked 526/534; fist p50 0.425/0.394; vertical ranges 0.689/0.749 m; left−right height zero crossings 31 (~15 alternations). All 14 action datasets now accepted. Next: implement M7 engine behind a mode switch + device A/B. |
| **M4/M5 bow safety + crash export (EV-0121)** | **PARTIAL (host/install PASS) / device NOT RUN** | Right-fist use/bow hold suppresses left-pinch teleport (restored on fist release; m4-input 164 checks); diagnostics bundle includes prior logs, `hs_err_pid*.log` and crash-reports. Latest app `a4500d7b…` installed; provider `7bc599e7…` pushed. Device bow/UI behavior NOT RUN. |
| **M5 frame-pacing telemetry (EV-0110)** | **PARTIAL (host PASS) / device NOT RUN** | `VisionFrameStats` rolling poll-interval ring reports mean/P50/P95/max and a documented `missed90` count (>16.67 ms); provider diag line includes all four; window resets per period. m5-frame-stats 10 checks PASS; provider suite ALL PASS. Device K2/K5 measurements NOT RUN (poll intervals are a Java-side proxy). |
| **M0 milestone** | **CLOSED** | S1 PASS (EV-0021/EV-0024), S3 CLOSED (EV-0006/EV-0009), S2 device world render PASS (EV-0034); 30-min soak deferred to M1 (Decision 45=A) |
| M1 T3 — own source build | `PASS` | Source-built Amethyst v1.2.0 boots MC 26.2 Vulkan world on D1 (EV-0036); app-side defaults (EV-0037); route ADR-0008 + EV-0041; **branded VRMC app (dev.vrmc.vrmc) installed (EV-0042)** |
| M1 T1 — stack pins/hashes | `PASS` | versions.env + sha256 for all stack components; check_versions 8/8 (EV-0038) |
| S4a-host eye handoff | `PASS` | MoltenVK MTLTexture export + Metal pixel readback + timeline MTLSharedEvent sync on macOS host (EV-0063) |
| S4a-device eye handoff | `PASS` | Bundled MoltenVK 1.4.3: MTLDevice+MTLTexture export, Metal readback correct, timeline MTLSharedEvent sync on D1 (EV-0065) |
| M2-W5 device eye handoff | `PASS` | ABI v2 `vrmc_export_mtl_texture` on device: VkImage→MTLTexture + submit (EV-0069) |
| M2-W6 device provider init | `PASS` | Device: bridge handshake ABI v1, `VisionVR.init()`, stereo render passes LEFT/RIGHT, 1501+ tracking frames, no SteamVR (EV-0068); Fabric 0.20.1 compatibility candidate |
| M2 review propagation | `PASS` | Host-only EV-0060 scoping, host-only identity fallback, macstream compliance, S4a split gates, W6 preconditions, ABI policy (EV-0061) |
| PSVR2 controllers | `DEFERRED (out of MVP scope)` | P1 register; hands-only is the P0 input path (EV-0062) |
| M1 T2 — repo scripts | `PASS` | Parameterized, re-runnable scripts + README (EV-0039) |
| M1 T5 — mouse | `PARTIAL` | visionOS delta-gate patch (EV-0040); follow-up: rotation now smooth, cursor visibility accepted cosmetic (EV-0045/EV-0047), task-2 closed |
| Provider integration | `PASS (host) / NOT RUN (device)` | EV-0006/EV-0009 injection; EV-0059/EV-0060 host provider+stereo loop; **device runtime (M2-W6) NOT RUN** |
| Stereo compositor | `NOT RUN` | ST-S4 pending |
| Input (hands) | `NOT RUN` (hands) — `PASS` host+simulator plumbing (EV-0095) | ST-S5-hands pending; M4-W1 input path implemented and host/simulator-verified (ABI v3 channel, pinch/fist gesture slice, GUI/menu + attack/use/teleport bindings); hands-only is the sole P0 path (G2–G4 HIGH, no controller fallback) |
| Input (PSVR2 controllers) | `DEFERRED (out of MVP scope)` | P1 register; not counted at MVP exit |
| Performance/thermal | `NOT RUN` | ST-S6 pending |
| S1a harness | `PASS (compat)` | JIT26 mapping + tier 3/4 + `HELLOJIT` + exit 0 across five cold relaunches (EV-0021); StikDebug needs `universal.js` assigned to the app per install |
| S1b harness (native visionOS) | `PASS` | VISIONOS-relabelled JRE builds/signs (EV-0022), launches (EV-0023), and JITs + executes on D1 (EV-0024) |
| M1 launcher probe (Amethyst) | `BLOCKED` | JIT + Java 25 reach MC 26.2 main (EV-0031); LWJGL 3.3.3 vs 3.4.1 mismatch; grafting 3.4.1 Java crashes in the app's embedded 3.3.3 `JNI_OnLoadGLFW` (EV-0032); needs current-source rebuild |
| Launcher shell | `NOT RUN` | M1 |
| Acceptance AC-1…AC-6 | `NOT RUN` | Device tests pending |
| **M8 foveated 4K/120 rendering** | **PARTIAL (host+simulator PASS, EV-0268/EV-0269) / device NOT RUN** | Shell requests CompositorServices foveation when supported and maxRenderQuality=1.0 when the layer reports a usable default quality; compositor publishes 68-byte `vrmc_render_settings` (logical per-eye display size at the current render quality, physical foveated drawable, foveation/rate-map state, measured display cadence) and logs rate maps + cadence; provider sizes stereo eye targets from that logical size with an adaptive eyeScale (auto default), resizes only in stable states with hysteresis and reports cadence-aware pacing. Bridge+provider host suites ALL PASS; simulator `render` plumbing scenario PASS; host Metal foveation probe PASS (real rate map: logical UV mapping + screen-size viewport convention, EV-0270); host Fabric harness PASS (real MC client: provider eye targets resize 1024x1024 -> 1832x1600 from display feedback, EV-0272); M8.6 foveated sharpening PASS host/sim (4x-upscale edge acutance 1.17x, foveal taper 1.27 vs 1.00, EV-0273) with a rebuilt signed candidate and knob A/B (EV-0274); device verification tooling ready, including a one-command session and a vrmc-status.json render/pacing fallback in the A6–A9 classifier (EV-0275); resize texture-lifetime safety verified in the host Minecraft harness (EV-0276); compositor resize grace (no test-pattern flash during rebuilds) verified in the simulator `eyedrop` scenario (EV-0277); 120 Hz pursuit lever (`vrmc-target-hz.txt` target-cadence override) validated in the host Minecraft harness (EV-0278); content-first governor (keep 4K eye target, cut scene cost first) unit-tested + host-harness `CONTENT_FIRST=on` validated (EV-0279); target-cadence guardrail auto-revert validated in a real Minecraft harness with a simulated 90 Hz display (EV-0280), the full (non-fast) M3c self-check now passes end-to-end with env-limited scenarios reported as SKIP, a startup world-supersample (SSAA) knob for jagged edges was validated in the real Minecraft harness (EV-0281), the combined foveated-drawable + sharpening pass now passes on host Metal under a real rate map (EV-0282), and the M8 resize path survived a 120 s all-knobs soak with 8 render-target rebuilds and 0 exceptions (EV-0283) (`scripts/m8_device_session.sh prepare/collect`) (`scripts/m8_device_check.sh` + [M8_DEVICE_RUN.md](docs/mvp/M8_DEVICE_RUN.md)); a signed M8 device candidate is staged and verified ([export/m8-device-candidate.txt](export/m8-device-candidate.txt), EV-0271) with install/tuning helpers. Device D1 A6-A9 (foveation active, max-quality logical size, provider resizes, displayHz≈120 with acceptable repeats) NOT RUN — D1 unavailable; no public CompositorServices refresh-rate selector; engine-side foveation deferred (MoltenVK 1.4.3 lacks `VK_KHR_fragment_shading_rate`). [`docs/mvp/M8_PLAN.md`](docs/mvp/M8_PLAN.md) |

---

## 8. Open blockers

| Blocker | Owner | Unblock condition |
|---|---|---|
| M2-W6: Fabric loader on D1 | Open | Device instance has vanilla 26.2 only. Install Fabric 0.19.3 via launcher Profiles → + → "Install Fabric/Quilt" (Minecraft 26.2); Vivecraft + provider jars are already in `instances/default/mods`. Then launch with JIT to run the provider. |
| M1 T6: 30-minute device soak | **DONE** | 1805 s continuous world session, no game crash/watchdog kill, thermal `serious` recorded (EV-0044); StikDebug watchdog incident noted |
| Lifecycle/audio defect | **CLOSED** | Background freeze + sound loss fixed; retest PASS (EV-0048), task-3 closed |
| M1 W1 — reproducible build | `PASS` | `scripts/build_launcher.sh` + `patches/vrmc-m1-amethyst-1.2.0.patch` + `LAUNCHER_BUILD.md`; tested from a fresh tree (EV-0049) |
| M1 W3 — JIT readiness | `PASS` | explicit TXM alert + `[JIT] preflight` log (EV-0050); no-JIT flow verified (EV-0051) |
| M1 W7 — save/relaunch | `PASS` | clean save/quit + reload preserved (EV-0052) |
| M1 W6 — observability | `PASS` | in-app Send logs / Log output share + repo capture scripts (EV-0053) |
| M1 W1 polish — icon + first-run | `PASS (install)` | icon assets + first-run checklist; reproducible build re-verified (EV-0054/EV-0055); final build installed (EV-0056); visual check pending next launch |
| M1 T4: fresh-install acceptance | **DONE** | Fresh branded VRMC container reached the world with app-side provisioning (EV-0043); no Mac-side pushes |
| ST-S2 MC Vulkan not yet attempted | Lead | MoltenVK xros build + MC 26.2 boot harness |
| All device tests | Lead | Product build exists |
| M3c black immersive / device presentation | **CLOSED** | EV-0093 root cause fixed (CompositorServices drawable depth clear 1.0) and EV-0094 device acceptance PASS: stereo pattern + JIT game-in-immersive, aligned with head tracking, operator-confirmed. Remaining follow-ups (M4 input, chrome, re-entry, GPU-sync device run, 90 Hz soak) are tracked separately. |
| M4-W1 device input run (W1 slice) | **DONE (EV-0096)** | Synthetic Step 1 + real-hands Step 2 run on D1 with the staged M4 app/provider jar; operator-confirmed control from the immersive scene. Remaining: full AC-4/ST-S5-hands P0 checklist (locomotion/jump/…), gaze hover+pinch selection (not implemented), shutdown-crash fix device verification. |
| Shutdown JVM SIGSEGV after game stop | Open | Reproduced 2/2 device runs: `objc_retain` SIGSEGV in a native thread after `[Minecraft] Stopping!`; faulting register equals a provider eye `MTLTexture` handle. Hypothesis: M3 eye-texture lifetime/teardown race. Unblock: triage retain/stop ordering + reproduce with input path disabled; fix and re-run EV. |

---

## 9. Change log

| Date | Change |
|---|---|
| 2026-10-31 | File created; EV-0001 recorded (workspace/toolchain/reference baseline, `PARTIAL`). |
| 2026-10-31 | Acceptance criteria, budgets, test suites, and evidence protocol established. |
| 2026-10-31 | Review revision: rule/§ cross-references corrected, valid-EV rule added, S1/S3/K3/DT-18/CT-07 criteria tightened, device OS recorded, propagation requirement added. |
| 2026-10-31 | EV-0002 recorded (external JIT26 demonstration, `PARTIAL`); S1 internal reproduction remains `NOT RUN`; A2 → MEDIUM in AGENT.md; totals 32/26/7. |
| 2026-10-31 | M0 foundation committed (`3332cdb`); EV-0003 records the tooling self-test (`PASS`, AT-009). |
| 2026-10-31 | EV-0004 records the S1 host pre-test (`PARTIAL`): relabelled iOS JRE 25 JITs on macOS and the JIT26 request site traps as expected. Device S1 remains `NOT RUN`. |
| 2026-10-31 | EV-0005 records the S2 host pre-test (`PARTIAL`): MC 26.2 boots with Vulkan via MoltenVK 1.4.2 and no GL fallback. Device S2, world render, and soak remain `NOT RUN`. |
| 2026-10-31 | EV-0006 records S3 static analysis (`PARTIAL`): injection point exists and `initializeVR` bytecode is identical across 1.3.14/1.3.15; runtime Mixin test pending. Added interpretation/scope notes to EV-0004/EV-0005 and the AT allocation rule. |
| 2026-10-31 | S1a harness scaffolded in `runtime/probes/s1a`; EV-0007 records the build self-check and host JIT run (`PARTIAL`). EV-0008 records the device-build attempt (`BLOCKED`: AVP locked; no AVP profile). |
| 2026-10-31 | EV-0009 records the S3 runtime probe (`PASS`, desktop): the Mixin substitutes `VisionVR` for `MCOpenVR` with no SteamVR. Injection decision: Mixin, no fork. |
| 2026-10-31 | EV-0010 records the MoltenVK v1.4.2 visionOS build (`PASS`, host): `xros-arm64`, platform VISIONOS, minos 27.2. Device stage still `NOT RUN`. |
| 2026-10-31 | EV-0011: S1a builds and signs successfully (AVP profile created); install is `BLOCKED` by the free-profile 3-app limit. |
| 2026-10-31 | EV-0012: 12 LWJGL/helper dylibs retagged to platform VISIONOS (MoltenVK from EV-0010); load test pending. |
| 2026-10-31 | EV-0013: visionOS S2 probe app builds and signs with MoltenVK + retagged natives embedded; install pending the app-slot decision. |
| 2026-10-31 | EV-0014: host MC 26.2 world rendered through Vulkan/MoltenVK for 21 minutes, clean shutdown; full 30-min soak still pending. |
| 2026-10-31 | Amethyst removed with approval; S1AProbe installed on D1. EV-0015 corrected: UIScene-adoption crash, not JIT26. |
| 2026-10-31 | EV-0016 (`PASS`, D1): MoltenVK 1.4.2 on visionOS/Apple M2 exposes all 5 required extensions and 9 required features; maxPushDescriptors=287. Device render still pending. |
| 2026-10-31 | EV-0017 (`FAIL`): UIKit/SwiftUI probe crashed before JVM output; root cause is `JLI_Launch` re-entering the app main. EV-0018: console-style harness starts the JVM and traps at `BreakGetJITMapping` without an enabler. |
| 2026-10-31 | EV-0019 (`FAIL`): post-patch launches still trap at `BreakGetJITMapping`. |
| 2026-10-31 | EV-0020 (`FAIL`, BLOCKED): StikDebug launches/attaches then detaches without JIT26 preparation; all four on-device scripts patched. |
| 2026-10-31 | EV-0021 (`PASS (compat)`): Assign-Script + JIT26 extension handshake; five cold launches with `[JIT26]` mapping, tier 3/4, `HELLOJIT`, exit 0. |
| 2026-10-31 | EV-0022 (`PARTIAL`): native visionOS S1b harness built/signed; 39 JRE Mach-O relabelled VISIONOS; install blocked by the 3-app free-profile limit and device state. |
| 2026-10-31 | EV-0023 (`PARTIAL`): after freeing the slot, `dev.vrmc.s1b` installs and launches natively on D1 without a scene crash; waits for the JIT debugger and exits cleanly when none is attached. |
| 2026-10-31 | EV-0024 (`PASS`): native visionOS app JITs and executes on D1 with the VISIONOS-relabelled JRE (`HELLOJIT` 616 ms, exit 0). S1 spike complete (compat + native). |
| 2026-10-31 | EV-0025 (`PASS`): D1 executes a Vulkan offscreen clear+readback through MoltenVK/M2 (`pixel=(64,128,191,255)`). |
| 2026-10-31 | EV-0026 (`PASS`): all 12 retagged VISIONOS natives dlopen in the D1 probe. |
| 2026-10-31 | EV-0027 (`PASS`): CAMetalLayer→VkSurfaceKHR works on D1 (1280x720, 60 formats); probe clean with 12 natives. |
| 2026-10-31 | EV-0028 (`PASS`): VK_KHR_swapchain + present works on D1 (1280x720, 3 images, FIFO, submit/present 0). S2 device graphics primitives complete; MC boot/title/world remains. |
| 2026-10-31 | EV-0029 (`PARTIAL`): release Amethyst re-signed for <TEAM_ID> installs and launches on D1. |
| 2026-10-31 | EV-0030 (`FAIL`): Amethyst launched via StikDebug attaches/continues/detaches in ~28 ms and dies with no crash report; normal launch works. |
| 2026-10-31 | EV-0031 (`PARTIAL`): external Java 25 + always-attached JIT + dyld bypass work; MC 26.2 reaches `NativeLibrariesBootstrap` but aborts on missing `org.lwjgl.util.spvc.Spvc` (release bundles LWJGL 3.3.3). |
| 2026-10-31 | EV-0032 (`FAIL`): grafting 3.4.1 Java/natives clears `spvc` but crashes in the app's embedded 3.3.3 `JNI_OnLoadGLFW` (JVM SIGSEGV). Needs a current-source Amethyst rebuild; **problem exported to `export/` + zip**. |
| 2026-10-31 | EV-0033 (`PARTIAL`): StikDebug 3.2.0 reinstalled under the existing bundle id (pairing/DDI/scripts preserved); `amethyst.js` pushed. |
| 2026-10-31 | **EV-0034 (`PASS`): first Minecraft 26.2 world on Apple Vision Pro** — Vulkan via MoltenVK 1.4.3, LWJGL 3.4.1, JIT26 mapping, world “New World” joined at 20:27:54. |
| 2026-10-31 | EV-0035 (`PARTIAL`): 4m20s in-world with clean save/shutdown, no crash; user stopped early so the 30-min soak is deferred. |
| 2026-10-31 | **M0 formally CLOSED on EV-0034** (Decision 45=A): S2's M0 gate is device world render only; the 30-minute soak is now an **M1 exit gate** (EV-0035 = feasibility, not the gate). Recorded in AGENT §4.5/§5/§6/§7/§11/§13 and this dashboard. |
| 2026-10-31 | M1 stack pinning (Decision 46=A+C fact record): Amethyst → 1.2.0, MoltenVK → 1.4.3, StikDebug script → amethyst.js; ADR-0007 records the changes and evidence impact. |
| 2026-10-31 | **EV-0036 (`PASS`): T3 acceptance** — our own source-built Amethyst v1.2.0 (167 binaries re-signed) boots MC 26.2 to a Vulkan/MoltenVK world on D1. |
| 2026-10-31 | EV-0037 (`PASS`): app-side defaults force Vulkan + clear the crash marker; MC boots from a deliberately reset options.txt. |
| 2026-10-31 | Sprint-1 close-out: T1 EV-0038 (`PASS`), T2 EV-0039 (`PASS`), T5 EV-0040 (`PARTIAL`), T3 EV-0041 (`PASS`). T4/T6 open on device operations. |
| 2026-10-31 | EV-0042 (`PARTIAL`): branded **VRMC (dev.vrmc.vrmc)** installed with a fresh container. |
| 2026-10-31 | EV-0043 (`PASS`, T4), EV-0044 (`PASS`, T6), EV-0045/0046 (`FAIL`, input + lifecycle defects). |
| 2026-11-01 | EV-0057 M1 CLOSED; EV-0058 M2 scaffold; EV-0059 M2-W1 host harness. **EV-0060 (`PASS`) M2-W4/W5 host integration**: bridge ABI v1 handshake, provider init, stereo eye targets, per-frame `vrmc_submit_eyes`, no SteamVR; macstream reference mapped in `docs/mvp/MACSTREAM_REFERENCE.md`. Next ID `EV-0061`. |
| 2026-11-01 | **M2 review propagation + PSVR2 scope downgrade.** EV-0060 scoped as **M2-W4/W5 host PASS**; M2-W6 device bring-up and M3 are **NOT RUN**; S4a split into host/device gates. Identity controller transforms marked **host-only** (device missing data fails loudly). macstream is a tracked LGPL-3.0 reference (upstream `ec5a851c…`, design + partial provider port, no code in the GPL launcher; ADR-0009). PSVR2 Sense = **P1 / DEFERRED (out of MVP scope)**, not BLOCKED: F1–F3 moved to P1, AC-4/§1/§3/§4/§6/§7/§11 updated, G2/G3/G4 → HIGH (hands-only has no fallback), ST-S4/ST-S5 split. New status `DEFERRED (out of MVP scope)` added to the legend. Next ID `EV-0062`. |
| 2026-11-01 | **EV-0061 (`PASS`): M2 review fixes applied** (host/device scope, host-only identity fallback, macstream compliance, S4a split gates, W6 preconditions, ABI evolution policy). **EV-0062 (`DEFERRED`): PSVR2 Sense controller input — out of MVP scope (P1), not BLOCKED.** Next ID `EV-0063`. |
| 2026-11-01 | **EV-0063 (`PASS`): S4a-host** — exportable VkImage → MTLTexture works, Metal reads the Vulkan clear correctly, and MTLSharedEvent sync works with a **timeline** semaphore. **S4a-device remains NOT RUN** (separate gate). Next ID `EV-0064`. |
| 2026-11-01 | **EV-0064 (`NOT RUN`)**: S4a-device probe staged inside the VRMC app (bundled MoltenVK 1.4.3), marker pushed, but the device was locked (passcodeRequired=true) so it could not be launched. Unlock AVP and launch VRMC to execute; log = Documents/s4a-device.log. Next ID `EV-0065`. |
| 2026-11-01 | **EV-0065 (`PASS`): S4a-device** — bundled MoltenVK 1.4.3 on D1 exports MTLDevice/MTLTexture, Metal reads back the Vulkan clear correctly, and timeline MTLSharedEvent sync works (signaledValue 42). M3's zero-copy eye-handoff substrate is device-validated; **M2-W6 (provider init on device) and M3 remain NOT RUN**. Next ID `EV-0066`. |
| 2026-11-01 | **EV-0066 (`PARTIAL`): M2-W6 prep** — arm64-ios JNI bridge dylib built/embedded/signed; launcher passes `-Dvrmc.bridge.lib`; `vrmc-provider.jar` + Vivecraft jar staged in the device instance mods. **Remaining device step: install Fabric 0.19.3 loader**; W6 provider run still NOT RUN. Next ID `EV-0067`. |
| 2026-11-01 | **EV-0067 (`FAIL`)**: first W6 device attempt reached provider init + bridge handshake + eye targets, then crashed on the host-only identity guard applied to static component transforms; fix: identity component offsets + tracking-pose validity guard. **EV-0068 (`PASS`)**: after the fix, device provider init + stereo render passes (LEFT/RIGHT) + 1501+ tracking frames + no SteamVR; device used Fabric Loader **0.20.1** (pin is 0.19.3 → compatibility candidate; pin/ADR decision pending). Game remains unplayable by design: M3 compositor/head tracking and M4 input are NOT RUN. Next ID `EV-0069`. |
| 2026-11-01 | **EV-0069 (`PASS`): M2-W5 device eye handoff** — ABI v2 `vrmc_export_mtl_texture` on D1: `VkImage=0x139dccf00 -> MTLTexture=0x7107982300`, submitted; clean run. **EV-0070 (`PASS`): M2 milestone CLOSED** — all exit criteria evidenced; M2 acceptance matrix added. M3 compositor/head tracking and M4 input remain NOT RUN (game not playable yet). Fabric 0.20.1 vs pin 0.19.3 carry-over. Next ID `EV-0071`. |
| 2026-11-01 | **EV-0071 (`PASS`): M3 started, M3a gate 1** — `PLATFORM=11` native visionOS payload builds (platform VISIONOS, relabelled natives). **NOT RUN:** native app launch on D1, CompositorServices immersive space/ARKit, MC/JVM/JIT/Vulkan hosting in the native app. M2 remains CLOSED; M3 plan `docs/mvp/M3_PLAN.md`, ADR-0010 (native app route; companion fallback only if MC hosting fails). Next ID `EV-0072`. |
| 2026-11-01 | **EV-0072 (`PARTIAL`): M3a gate 2** — native visionOS immersive space + CompositorServices loop work (2700+ frames; three crash modes fixed: premature endSubmission, missing `cp_drawable_encode_present`, main-thread watchdog), but the user sees passthrough instead of the red/green test pattern and the ARKit anchor never resolves. Next: port to the C sample structure with `cp_drawable_set_device_anchor` + presentation-time conversion; then gate 3. VRMC launcher restored after the probe. Next ID `EV-0073`. || 2026-11-01 | **EV-0073 (`PARTIAL`): M3a gate 2 diagnostics** — GPU readback proves the per-eye render path is correct (eye0 pixel `r=0.800 g=0.050 b=0.050 a=1.000`, command buffer completed), but the user sees black with the ARKit device anchor set and passthrough without it. Rendering correct; presentation/anchor wiring is the remaining blocker. Next: compare against the reference sample (Metal Toolchain needed) or port its remaining drawable/layer setup. VRMC launcher restored. Next ID `EV-0074`. || 2026-11-01 | **EV-0074 (`PASS`): M3a gate 2** — native visionOS immersive space shows the per-eye red/green CompositorServices stereo test pattern (operator-confirmed); log: 2 views 1888x1792 rgba16Float, depth attachment present, cb completed, readback r=0.800. Root cause of earlier black screen: missing drawable depth attachment/rasterization-rate map. Gate 3 (MC/JVM/JIT/Vulkan in native app) next. Next ID `EV-0075`. || 2026-11-01 | **EV-0075 (`PARTIAL`/blocked): M3a gate 3 attempt** — native visionOS launcher installs and launches without crashing, but its window content is blank (pre-init/version list logged; no [JIT] lines, no game). Direct launch same. No crash report; StikDebug did not crash. Gate 3 remains NOT RUN; compat launcher restored, data intact. Next: native window/scene debugging or ADR-0010 fallback B. Next ID `EV-0076`. || 2026-11-01 | **EV-0076 (`PARTIAL`): M3a gate 3 diagnostics** — native window/scene and `LauncherSplitViewController` are created and sized correctly (1280x720, view 2 subviews) yet content renders blank; issue is native-visionOS UIKit presentation, not scene setup. Compat launcher restored; data intact. Next: SwiftUI window shell hosting the launcher VC (M3-W1) or ADR-0010 fallback companion. Next ID `EV-0077`. || 2026-11-01 | **EV-0077 (`PASS`): M3a gate 3** — the native visionOS app auto-launched MC 26.2/Fabric 0.20.1/Vivecraft and logged JIT enabled, Vulkan/MoltenVK, VisionVR provider init (ABI 2), LEFT/RIGHT passes, `VkImage→MTLTexture` eye export, tracking frames 601+. **M3a gates 1–3 all PASS.** Remaining native-app issue: blank UIKit launcher content (M3-W1); next M3-W2 consumes the eye textures/poses in CompositorServices. Compat launcher restored. Next ID `EV-0078`. || 2026-11-01 | **EV-0078 (`PARTIAL`): M3-W1 root-VC workaround** — the native branch runs (`rootVC=LauncherNavigationController`) but crashes in `-[LauncherProfilesViewController viewWillAppear:]`: `@[sidebarViewController drawAccountButton, ...]` with `self.splitViewController == nil` (sidebar macro). Blank split content + this crash prove a native-specific UI shell is required; auto-launch (EV-0077) remains the only boot path. **`export/` cleared of the old Amethyst/LWJGL dossier and replaced with the native-UI blocker dossier** per operator instruction; compat launcher restored. Next ID `EV-0079`. || 2026-11-01 | **EV-0079 (`PASS`): M3-W1** — native visionOS launcher UI renders after the UIKit idiom spoof fix (`vrmc-m3w1-visionos-idiom.patch`: skip spoof when real idiom is Vision/6); Play launched `fabric-loader-0.20.1-26.2` with no autolaunch flag. Log: JIT enabled, MC 26.2 + Fabric 0.20.1, Vulkan/MoltenVK 1.4.3, VisionVR provider/ABI 2, LEFT/RIGHT passes, VkImage→MTLTexture export, 901+ tracking frames. `build_launcher.sh` now supports `PLATFORM=11`; `export/` replaced with resolved/build notes. Next: M3-W2/W3 compositor consumption of provider textures + poses. Next ID `EV-0080`. || 2026-11-01 | **EV-0080 (`PASS`, host): M3-W2 groundwork** — bridge gains native-side shared state (`vrmc_shared_eye_textures`, `vrmc_shared_set_tracking`, `vrmc_shared_clear_tracking`; stub test passes, Java ABI stays v2). No device test. Next: SwiftUI app-lifecycle shell for ImmersiveSpace/CompositorLayer, then compositor consumption of provider eye textures + ARKit pose. Next ID `EV-0081`. || 2026-11-01 | **EV-0081 (`PASS`): M3-W2 shell** — SwiftUI app-lifecycle framework hosts `LauncherSplitViewController` and opens a CompositorServices immersive space (test pattern); `vrmc_shell_start` / `openImmersiveSpace result=opened` in `vrmc-shell.log`. **EV-0082 (`PARTIAL`): M3-W3/W4** — auto-open on game start + compositor 1080 frames/ARKit anchor but eyes=0; MC `VK_ERROR_DEVICE_LOST 'Failed to wait for semaphore'`, compositor `__BUG_IN_CLIENT__` at `cp_frame_end_submission`. Mitigations staged. Next ID `EV-0083`. || 2026-11-01 | **EV-0083 (`PARTIAL`): M3-W3/W4 first light** — mitigations fixed the device-loss; game alive; auto-open 15 s after start; compositor `eyes=1` (provider MTLTextures 0x72219ca580/0x72219ca300), anchor OK, provider tracking frames with real head poses. Operator: immersive did not align, game window remained visible, immersive quit when app backgrounded. Data path proven; next: window hiding, scenePhase, per-eye projection/FOV/aspect alignment. Next ID `EV-0084`. || 2026-11-01 | **EV-0084 (`PARTIAL`): M3-W3/W4** — window parking works (`windows=3 alpha=0`), immersive shows sampled provider eye textures (`eyes=1`) with live tracking, but backgrounding crashes the app (`__BUG_IN_CLIENT__` at `cp_frame_end_submission` on layer invalidation) and alignment is still flat fullscreen (no per-eye projection/FOV parity). Next: graceful compositor stop on background, then projection alignment/sync. Next ID `EV-0085`. || 2026-11-01 | **EV-0085 (`PARTIAL`, final attempt): M3-W3/W4** — background compositor exit is clean (no new crash) but after the game replaces the window root VC the SwiftUI observers are gone (`window parked` is the last shell line), so immersive cannot be re-entered; window bottom bar remains despite alpha/isHidden; exotropia persists after view 0/1 swap. Root causes documented; **`export/` replaced with the current immersive-integration blocker dossier + evidences**. Next: keep SwiftUI observers alive (modal game surface/app-level observer), window scene chrome, per-eye projection/FOV parity. Next ID `EV-0086`. || 2026-11-01 | **Operator-confirmed issue summary (export update)**: (1) **window cannot be hidden** — content parks (alpha/isHidden) but visionOS bottom bar/chrome remains; (2) **game cannot present again after background** — game keeps running but immersive cannot be re-entered (SwiftUI observers destroyed by game root-VC replacement); (3) **perspective is exotropia** — stereo eyes diverge outward, view swap did not fix; flat fullscreen sampling without per-eye projection/FOV parity. `export/README.md` + zip updated with the issue summary; evidence EV-0083/84/85. Next ID `EV-0086`. || 2026-11-01 | **EV-0086 (`PARTIAL`): three-fix device run** — integrated fixes (persistentSystemOverlays, app-level coordinator/reopen, symmetric 110° FOV + per-eye reprojection + measured IPD) with matching app/bridge/provider jar. **Shell re-entry works** (background stop/dismiss, foreground reopen generation 2). **Operator: completely black immersive + windows still visible**; compositor logs view tangents, provider tangents ±1.428, ipd 0.065, eyes=1 frames 1…1680 — data path runs, reprojection outputs black. Exotropia fix unverified. `export/` updated with evidence. Next: CPU ray→UV diagnostics/convention fix, chrome alternative. Next ID `EV-0087`. |
| 2026-11-01 | **EV-0087 (`PARTIAL`, build/static validation): M3b fixes integrated** — compositor reprojection math validated (Metal shader unit test + visionOS simulator probe; EV-0086 device views 87.9% inside / 0 behind / 0 NaN); no-black diagnostics added (CPU ray->UV, provider eye-texture readback + auto test-pattern, branch colours, alpha=1, command-buffer health, Documents flags); Shell epoch-guarded re-entry; Amethyst modal game-surface patch keeps the SwiftUI scene alive so window-chrome hiding can work; provider jar + bridge rebuilt; signed app installed on D1. **Device run NOT RUN** — next ID `EV-0088`. |

| 2026-11-01 | **EV-0091 (`PARTIAL`)**: fresh post-JNI-fix device logs recovered — provider eye-render + display-view channel correct, textures bright (luma 103-154), first command buffer completed; `vrmc-test-pattern.flag` present since 16:13 (not logged by that build). Next ID `EV-0092`. |
| 2026-11-01 | **EV-0092 (`PARTIAL`)**: M3c presentation diagnostics on D1 — no-JIT selftest and a JIT game run prove the compositor writes a bright image into the presented built_in drawable (raw readbacks + meta, encNil=0) yet the operator sees a black immersive; full immersion is active and the game remains in a floating 2D window. The same VRMCShell.framework displays the test pattern correctly in a simulator host app. Manual "Enter VR" button, scene-activation/layer-state logging, alpha-only first-frame parking + periodic re-park and willResignActive grace are implemented; presentation root cause not yet isolated. Next ID `EV-0093`. |
| 2026-11-01 | M3c operator directive (Option 2): keep the startup window, add a manual "Enter VR" trigger first, then make the automatic post-JIT entry the default; do not change the Info.plist preferred scene role until the manual path is verified. Implemented (manual overlay button + auto path + error surface); device validation pending. |

| 2026-11-01 | **EV-0093 (`PASS`, device A/B): black-immersive ROOT CAUSE** — M3b (`1b3b73c`) changed the CompositorServices drawable depth clear from 1.0 to 0.0; visionOS 27.2 then presents the whole immersive layer black even though the colour drawable is bright and the command buffer completes. Controls: known-good M3A probe displays (depth 1.0); minimal-window, deprecated-API and pure-SwiftUI-host builds with depth 0.0 are black; the same build with depth 1.0 shows solid magenta/cyan (operator-confirmed). Fix: default depth clear 1.0, `vrmc-depth-zero.flag` A/B, `scripts/tests/DepthClearRegressionTest.sh` PASS. Simulator did not reproduce (not evidence for this path). Next: EV-0094 final visual/game run. |
| 2026-11-01 | M3c recovery: a read->write round-trip on VERIFY.md/AGENT.md truncated their tails (VERIFY 2631->961 lines, AGENT 699->653); both restored from commit 3f9ab0d via `git show <commit>:FILE > FILE`, the intended M3c change-log rows re-applied, and AGENT.md gained rule 0.8 forbidding read->write round-trips on long files. |
| 2026-11-01 | M3c provider GPU sync (task-7): flag-gated, off-by-default provider half of the bridge task-4 GPU handoff implemented (exportable timeline VkSemaphore + MTLSharedEvent via VK_EXT_metal_objects, signalled through MC own Vulkan submission, submitEyesSynced); graceful fallback on every failure; host suite PASS incl. real MoltenVK (heap-buffer SIGSEGV caught pre-device). Java ABI v2 unchanged; device NOT RUN; EV-0094 build keeps the previous provider jar. |
| 2026-11-01 | M3c self-check tooling: runtime/probes/m3c-provider-sim/ headless simulator harness (flat sampling / GPU-timeline sync / stereo pattern / window-parking A-B / background->foreground re-entry - scenarios PASS) and scripts/m3c_selfcheck.sh one-command host+simulator suite; shell re-entry generalized + hardened for layer-invalidates-before-background. Device validation remains EV-0094. |
| 2026-11-01 | Build-artifact cleanup: removed the diagnostic A/B app bundles (VRMC-native-v1..v13, M3A/M3B probe shells) and temp logs/pulls used during the black-immersive investigation; the accepted EV-0094 build, provider jar, bridge/shell build dirs and Amethyst build caches are retained. stage_native_app.sh defaults and the export runbook now point at the accepted build. No product-code change. |
| 2026-11-01 | **EV-0094 (PASS, device): M3c visual acceptance** - operator-confirmed stereo/alignment pattern (border, fusion cross, per-eye tint; drawable readback L luma 110.4 / R luma 110.4, centre ~171) and a JIT game run rendering MenuWorlds world59 in the immersive space with stereo aligned and head tracking (auto-open 05:04:17 UTC, windows alpha-0 parked, depthZero=0, provider textures luma 35-156, drawable proof luma 35-129, no command-buffer failures). The black-immersive blocker is closed; root cause EV-0093. Remaining: M4 input, chrome, re-entry, GPU-sync device run, M3-W5/W6 pacing/soak. Next ID EV-0095. |
| 2026-11-01 | Propagation: M3C_PLAN (root cause, bisect results, next session), compositor-presentation.md §6 resolution, export/README root-cause + next-run dossier, scripts/README regression test. |
| 2026-11-01 | **EV-0096 (`PASS`, device D1): M4-W1 on-device input acceptance** — synthetic Step 1 (6144 presented frames, 120 action-dispatch lines, chord priority, release/stale safety path exercised) and real-hands Step 2 (`authorization=allowed`, `provider=started inputMode=arkit`, continuous real hand tracking, 120 action-dispatch lines); operator: “It ran very well!”. The reported “only the window can control the game” defect is fixed on device. Follow-ups: reproducible shutdown-only JVM SIGSEGV (likely M3 eye-texture teardown race), full AC-4/ST-S5-hands checklist (W2: gaze hover+pinch selection, smooth hands). Next ID `EV-0097`. |
| 2026-11-01 | **EV-0095 (`PASS`, host + simulator): M4-W1 immersive input** — ABI v3 hand-input channel (752 B `vrmc_input_state`, `vrmc_poll_input`, native-shared publish/acquire, `nativePollInput`), ARKit 27-joint compositor capture with explicit authorization + synthetic `vrmc-input-sim.flag` + zeroed release-on-exit, pure-Java pinch/fist gesture engine (hysteresis, 100 ms arming, 250 ms stale release, both-fist chord priority) + W1 action bindings + `VRInputAction.isEnabled` Mixin, cross-language C->Java fixture (`50926fdc…` / `43d52113…`), and a simulator input scenario. Host + simulator PASS including both one-command selfchecks; independent verifier: no open BLOCKER/HIGH (`docs/analysis/m4-input-verification.md`). **Device synthetic and real hands NOT RUN** — the reported "only the window can control the game" defect is fixed in code and operator validation is the next step (`docs/mvp/M4_DEVICE_RUN.md`). AC-4/ST-S5-hands unchanged. Next ID `EV-0096`. |

| 2026-11-05 | **EV-0268 (`PARTIAL`, host+simulator): M8 foveated 4K/120 rendering pipeline** — M8 implemented: foveation + max render quality layer configuration with capability-guarded fallbacks, a 68-byte `vrmc_render_settings` compositor→provider channel (bridge + JNI + fake-provider capture + C static asserts), compositor rate-map/geometry/cadence logging and `minimumFrameRepeatCount=0`, provider logical-size-driven eye targets with adaptive eyeScale and hysteresis resizes, and a simulator `render` scenario. Root cause fixed: the old fixed 1024x1024 eye target upscaled ~1.84x into a 1888x1792 drawable. Host: bridge suite ALL PASS (TSan clean), provider suite ALL PASS (m8-render 43 checks, m8-frame-stats 13 checks), sim scenario PASS (34 publications, mono 3840x2160 feedback). Device A6-A9 NOT RUN (D1 unavailable); 120 Hz is measured, not requested (no public refresh-rate selector); engine-side foveation deferred. Next ID `EV-0269`. |
| 2026-11-05 | **EV-0269 (`PARTIAL`, host+simulator): M8 round 2 — resize-safe eye targets, cadence-aware pacing diagnostics, device-verification tooling** — Provider resizes are gated to a stable state (menu room or level stable >=120 frames; 240-frame rate limit) and take 0.10 auto-scale steps under strong headroom; frame stats track missed90 vs measured-cadence missedTarget; periodic diag/render-state lines carry targetHz/displayHz/foveation/rateMaps/logical/eyeTarget/scale/resizes. Added `scripts/m8_device_check.sh` (+python analyser, host test for 4 outcomes, exit codes 0/2/3/4/5) and `docs/mvp/M8_DEVICE_RUN.md` so the next D1 session yields A6-A9 in one command. Host/sim ALL PASS (provider suite; classifier test; M3c fast self-check; simulator suite with render PASS 50 publications; reentry/gaze environment-limited). Device A6-A9 NOT RUN (D1 unavailable). Next ID `EV-0270`. |
| 2026-11-05 | **EV-0270 (`PASS`, host Metal): M8 foveation rendering-model probe** — full-screen sampling math rendered into a real `MTLRasterizationRateMap` pass (0.5 periphery / 1.0 centre; 1920x1080 logical -> 1488x848 physical): logical centre maps to the pattern white cross, logical upper-left quarter to the red quadrant; physical-size-viewport negative control corrupts the foveal centre; 6/6 checks PASS, wired into the M3c fast self-check. Host Metal only; device foveation/optics/cadence (A6-A9) remain NOT RUN. Next ID `EV-0271`. |
| 2026-11-05 | **EV-0271 (`PARTIAL`, host build/stage): M8 device candidate staged; device install/run NOT RUN** — signed M8 app (`/tmp/VRMC-native-m8.app`, tree `aea4bd4f…`, codesign deep/strict PASS) with M8 framework/bridge verified (render-settings symbols/strings) and matching provider jar `cd80b753…`; new `scripts/push_m8_render_config.sh` tuning helper (self-test/--print PASS) and `export/m8-device-candidate.txt` manifest. D1 install attempt CoreDeviceError 4016 (unavailable) → NOT RUN; A6-A9 pending. Next ID `EV-0272`. |
| 2026-11-05 | **EV-0272 (`PASS`, host GL): M8 host Fabric harness** — real Minecraft 26.2+Vivecraft client with the M8 provider and a host test bridge publisher (fake 3660x3200/foveation=1/120 Hz feedback): no-feedback 1024x1024 → parsed settings → eye-target resize 1024x1024 -> 1832x1600 via Vivecraft Reinit Render → auto ramp 0.60/0.70 (2200x1928/2568x2248) at the 240-frame cadence; 0 M8 exceptions; reproducible `scripts/m8_host_harness.sh` exit 0. Validates provider-side A7 path (host GL, fabricated feedback, menu room). Device A6-A9 still NOT RUN. Next ID `EV-0273`. |
| 2026-11-05 | **EV-0273 (`PARTIAL`, host Metal + simulator): M8.6 foveated sharpening + rebuilt candidate** — compositor CAS-lite fovea-weighted sharpening for sub-native provider renders (auto strength from upscale ratio, anti-halo clamp, live `vrmc-sharpening.txt`, `sharpen=` summary). Host probe 4x upscale: edge acutance 1.17x, meanAbsDiff 0.0158, centreGain 1.27 vs cornerGain 1.00 (10/10 checks). Simulator render PASS with sharpening active (47 publications). Push script `--sharpening` (21 self-test checks); self-check PASS; candidate rebuilt `53184ffe…`/`b1f48c2f…`/`cd80b753…` codesign PASS. Device A6-A9 NOT RUN. Next ID `EV-0274`. |
| 2026-11-05 | **EV-0274 (`PARTIAL`, host/simulator): M8.6 sharpening knob A/B + one-command device session tooling** — `SHARPEN=off` → no sharpening lines / `sharpen=0.00`; `SHARPEN=0.30` → fixed strength 0.30 / `sharpen=0.30`; both simulator scenarios PASS. New `scripts/m8_device_session.sh` (`prepare`: validate codesign+hashes, install app, push provider jar, operator checklist; `collect`: pull+classify A6-A9; `--dry-run`, `--from`) tested on dry-run, unavailable D1 (exit 5) and simulator pull. Device A6-A9 NOT RUN. Next ID `EV-0275`. |
| 2026-11-05 | **EV-0275 (`PASS`, host): M8 status diagnostics + device-check status fallback** — `vrmc-status.json` carries the M8 `render` summary; the A6-A9 classifier falls back to it (+frame p50/p95/missed) when logs rotated and prints it. Provider suite ALL PASS (jar `89a5910f…`/136,399 B reproducible); classifier 5/5 outcomes incl. status-only pull → PASS; self-check PASS. Device A6-A9 NOT RUN. Next ID `EV-0276`. |
| 2026-11-05 | **EV-0276 (`PASS`, host): M8 resize texture-lifetime safety** — provider clears the shared eye frame before each eye-target rebuild (closes the acquire-after-destroy window created by M8 dynamic resizes). Host Fabric harness: 2 resizes, each preceded by the clear line, 0 M8 exceptions; provider suite ALL PASS; jar `e9a08c52…`/136,579 B reproducible. Device A6-A9 NOT RUN. Next ID `EV-0277`. |
| 2026-11-05 | **EV-0277 (`PASS`, simulator+host): M8 resize grace** — compositor reuses its last sampled eye frame for up to 30 frames when the provider clears the shared frame for a rebuild (no test-pattern flash), then logs expiry/recovery. New `eyedrop` simulator scenario passes (reuse->expiry->recovery in order, survived, final pattern PASS); `render` regression PASS. Candidate rebuilt `6773acf1…`/`d53e148a…`/`ce11bac2…`/`e9a08c52…`, codesign PASS. Device A6-A9 NOT RUN. Next ID `EV-0278`. |
| 2026-11-05 | **EV-0278 (`PASS`, host): M8 target-cadence override** — `vrmc-target-hz.txt` (auto|60..120, live) aims the auto eye-scale policy at a chosen deadline instead of only the measured display cadence, so the provider can pursue 120 Hz; achieved rate stays measured. Provider suite ALL PASS (27/27 new checks; jar `144d47a7…`/137,501 B reproducible); host Minecraft harness PASS with `TARGET_HZ=100` honoured; push-script self-test 30 checks; classifier 5/5; self-check PASS. Device A6-A9 NOT RUN. Next ID `EV-0279`. |
| 2026-11-05 | **EV-0279 (`PASS`, host): M8 content-first governor** — opt-in `vrmc-content-first.txt` (`off` default): when the target cadence is missed, cut render/simulation distance (min 6, max 3 steps) before the eye-target resolution. Provider suite ALL PASS (65/65 policy checks; jar `5d418fd1…`/139,750 B reproducible); host harness PASS with `CONTENT_FIRST=on TARGET_HZ=120` (`content governor: on (file)…`, render state `contentFirst=1(0)`); push-script self-test 34 checks; classifier 5/5; self-check PASS. Device A6-A9 NOT RUN. Next ID `EV-0280`. |
| 2026-11-05 | **EV-0280 (`PASS`, host): M8 target-cadence guardrail + harness fix + full regression** — unreachable display target auto-reverts after 8 windows (`target cadence: N Hz unreachable … reverting to auto`), re-armed only when the knob changes; host harness `DISPLAY_HZ=90 TARGET_HZ=120` PASS with the revert line; harness now always re-points the dylib/provider vmArgs (stale-path fix) and the publisher accepts a game-dir display-Hz file; provider suite ALL PASS (guardrail 23/23; jar `6e2238d5…`/140,714 B reproducible); **full M3c self-check PASS (10 PASS rows)**, all simulator scenarios OVERALL PASS (reentry/gaze SKIP = environment-limited). Device A6-A9 NOT RUN. Next ID `EV-0281`. |
| 2026-11-06 | **EV-0281 (`PASS`, host): M8 world-supersample SSAA** — no MSAA in MC 26.2; `vrmc-world-supersample.txt` (off default, 1.0..2.0) maps to Vivecraft `renderScaleFactor`, world target = eye × √factor resolved down to the eye target. Host harness `SUPERSAMPLE=1.44`: VR 1832x1600 → Render target 2199x1921 @144% (4.2MP), 2016x1768 → 2420x2122; resize path unaffected. Provider suite ALL PASS (28/28 checks; jar `c055dabf…`/142,286 B reproducible); push self-test 41 checks; classifier 5/5; fast self-check PASS. Device A6-A9 NOT RUN. Next ID `EV-0282`. |
| 2026-11-06 | **EV-0282 (`PASS`, host Metal): combined foveation + sharpening** — sharpening validated under a real rasterization rate map (the device combination): 14/14 probe checks, combined centreGain 1.26 vs corner 1.01, meanAbsDiff 0.018 (bound 0.15); fast self-check PASS. Device A6-A9 NOT RUN. Next ID `EV-0283`. |
| 2026-11-06 | **EV-0283 (`PASS`, host): resize-failure containment + all-knobs soak** — wrapped eye-target rebuild (log/keep target/disable auto instead of crashing), decaying-pressure content-first trigger, `SOAK_SECONDS` harness mode; 120 s soak with all knobs: 8 resizes, 0 M8 exceptions, final eyeTarget 3112x2728 @120 Hz scale 0.90; earlier heavier-load run 2 resizes 0 exceptions scale 0.50→0.40. Provider suite ALL PASS (jar `2242c116…`/142,529 B reproducible); push 41 checks; classifier 5/5; fast self-check PASS. Device A6-A9 NOT RUN. Next ID `EV-0284`. |

---

## 10. Sign-off

| Role | Name | Decision | Date |
|---|---|---|---|
| Verification owner | — | pending | — |
| Lead | — | pending | — |
| 2026-11-01 | **EV-0088 (`PASS`, host): display-view alignment fix** — macstream Phase 8 root causes 3+4 ported: compositor `vrmc_shared_set_display_views` (per-eye `cp_view_get_tangents` + `cp_view_get_transform` + measured IPD); provider `getDisplayViews` renders `frustum(l·n,r·n,d·n,u·n)` with head-relative eye matrices and NaN cache invalidation; compositor switches to flat 1:1 mapping (reprojection/black branch bypassed). Host checks all PASS: DisplayViewsTest (both device display views + symmetric fallback, corners exact, straight-ahead NDC offset formula), bridge stub display-view roundtrip, provider javac. App+shell+bridge rebuilt/signed/installed; provider jar rebuilt/pushed/hash-verified. **Device run NOT RUN → next EV-0089.** |
| 2026-11-01 | **EV-0088 (`PASS`, host): display-view alignment fix** — macstream Phase 8 root causes 3+4 ported (display views, head-relative eye matrices, asymmetric per-eye frustum, NaN projection cache invalidation, flat mapping); offline frustum/bridge/provider checks PASS; app+bridge+provider built/installed. **EV-0089 (`PARTIAL`): recovered M3b device logs** — provider eye textures valid non-black (L/R mean RGB), first command buffer completed, chrome/windows parked/hidden; session backgrounded before visual alignment check. Device locked; alignment device run pending. Next ID `EV-0090`. || 2026-11-01 | **EV-0090 (`PARTIAL`): display-view device run** — compositor published display views and flat-sampled provider textures (frames 6360; L tangents -1.732/1.000/1.000/-1.192, Lpos(-0.0328,-0.0259,-0.0403), Rpos(0.0311,-0.0250,-0.0404), ipd 0.0639; provider textures dark menu world world58 luma 14–59). Provider applied RIGHT exactly but LEFT was garbage due JNI grouped vs provider interleaved layout; fixed to interleaved per-eye, `DisplayViewsLayoutTest` PASS, app rebuilt/installed; relaunch pending. Next ID `EV-0091`. || 2026-11-01 | **EV-0097 (`PARTIAL`): M4-W2 first slice** — One-Euro hand-pose smoothing (adaptive translation + angle-adaptive slerp, tuning keys, reset on tracking loss) integrated in VisionVR; shutdown defect hardening (provider clears shared eye textures in destroy; compositor CFRetains in-flight eye textures until command-buffer completion; bridge stub clear contract). Provider tests ALL PASS (m4-smoother 11 checks), M4 selfcheck RESULT PASS; new app/provider jar installed. Device smoothing + quit-game crash run pending; gaze tracking-areas + pinch selection still design-only. Next ID `EV-0098`. || 2026-11-01 | **EV-0098 (`PARTIAL`): M4-W2 gaze tracking areas** — `vrmc_gaze_event` mailbox + JNI; SwiftUI `onSpatialEvent` hook; ShellLayerConfiguration tracking format; compositor 32x18 tracking-area grid with automatic hover, tile render-value mask (r32/r16) gated by Documents/vrmc-gaze.flag; provider tile→NDC→eye ray→GUI plane→mouse/click mapping with W1 double-click suppression; VisionGazeMathTest 11 checks PASS, provider suite ALL PASS, shell/provider builds PASS. Runtime tracking-area pipeline unverified (simulator screen black; D1 unavailable); device NOT RUN. Next ID `EV-0099`. || 2026-11-01 | **EV-0099 (`PARTIAL`): M4-W3 middle-pinch locomotion/core actions** — middle-pinch gesture family (hysteresis, tap, double-tap, arming, tracking-loss release, opt-out `middle.enabled=false`); `key.jump` (right tap) and `key.sneak` (right hold) bindings; pure-Java `VisionLocomotion` virtual stick from left wrist relative to head → `vivecraft.key.freeMoveStrafe` analog; left middle tap/double → rotateLeft/Right analog pulses in VisionVR; movement zeroed on GUI/seated/stale/unhealthy. m4-middle 15 checks + m4-locomotion 7 checks PASS; provider suite ALL PASS. Device/real-hands NOT RUN. Next ID `EV-0100`. || 2026-11-01 | **EV-0100 (`PARTIAL`): M4-W4 partial** — opt-in open-hand swipe detector (`swipe.enabled=false` default; speed/axis/cooldown/open-hand gating; tracking-loss reset) wired to hotbar prev/next and mouse-wheel scroll; right middle-pinch double-tap bound to `vivecraft.key.radialMenu`; m4-swipe 6 checks PASS + full provider suite ALL PASS. Chat/keyboard/swap/drop/bow/climb and real-hands tuning still open; device NOT RUN. Next ID `EV-0101`. || 2026-11-01 | **EV-0101 (`PARTIAL`): M5 first slice** — `VisionRuntimeSettings` parses opt-in `vrmc-runtime.properties` (comfort seated/free-move/aim, worldRotationIncrement, performance presets + render/simulation distance/framerate/VSync, diagnostics period; absent file applies nothing; invalid values warned+ignored) and VisionVR applies them with a summary log; provider periodic `[VRMC-M5] diag:`; shell 30 s thermal/low-power lines to `vrmc-thermal.log` + state-change notifications. m5-settings 18 checks PASS; provider suite ALL PASS; shell build PASS. Device/gameplay NOT RUN. Next ID `EV-0102`. || 2026-11-01 | **EV-0102 (`PARTIAL`): M6 offline groundwork** — provider append-only `vrmc-shutdown.log` journal (init/destroy-start/destroy-complete; lets soak distinguish clean quit vs crash); `scripts/m6_soak_harness.sh` (dry-run PASS; device monitor fails on SIGSEGV/command-buffer/__BUG_IN_CLIENT__/panic and reports shutdown-complete); `scripts/m6_release_manifest.sh` (commit/pins/hashes/licensing/no-Minecraft-binaries checks, dirty-tree guard); `PRIVACY.md`; `docs/mvp/M6_ACCEPTANCE.md` AC-1..AC-6/K1..K6 matrix. Full provider suite ALL PASS. Device soak/acceptance NOT RUN. Next ID `EV-0103`. || 2026-11-01 | **EV-0103 (`PARTIAL`): M5 recenter safety chord** — both-hand middle double-tap within 120 ms (300 ms cooldown) fires a recenter; the chord cancels the per-hand double-tap pulses so it cannot also trigger right-hand radial or left-hand snap-turn. VisionVR performs `vrPlayer.snapRoomOriginToPlayerEntity(player,false,true)` via reflection and logs it. Middle suite 18 checks PASS; full provider suite ALL PASS. Device recenter/comfort and height/world-scale persistence NOT RUN. Next ID `EV-0104`. || 2026-11-01 | **EV-0104 (`PARTIAL`): M5 launcher settings panel** — launcher-window `VRControlOverlay` gains a collapsible settings panel (seated, seated free move, snap turn 45°/smooth, performance preset, render distance, frame limit) that loads/saves `Documents/instances/default/vrmc-runtime.properties` (owned keys only, other keys preserved, atomic write, shell log); provider applies at next game launch (EV-0101 parser). Shell build PASS; device UI interaction NOT RUN. Next ID `EV-0105`. || 2026-11-01 | **EV-0105 (`PARTIAL`): M5 world-scale/height + local command channel** — `comfort.worldScale` (0.1–5) and `comfort.manualHeight` (-1 auto/1.0–2.2) parsed+applied; `VisionCommandFile` whitelist (recenter | calibrate-height | reload-settings | diag | status) read at most twice/sec from `vrmc-command.txt`, unknown commands rejected+recorded, results appended to `vrmc-command-result.txt`; shell overlay buttons queue commands. m5-settings 22 checks + m5-command 9 checks PASS; provider suite ALL PASS; shell build PASS. Device behavior/UI NOT RUN. Next ID `EV-0106`. || 2026-11-01 | **EV-0106 (`PARTIAL`): M4-W4 swipe action table** — swipe direction sources + bindings (only active with `swipe.enabled=true`): right swipe right/left → hotbarNext/hotbarPrev; left swipe up/down → toggleKeyboard/chat; left swipe left/right → swapOffhand/drop; right swipe up/down stays direct mouse-wheel scroll. Direct duplicate hotbar handling removed. Binding table 21 rows/19 actions; swipe test 9 checks PASS; full provider suite ALL PASS. Device feel/chat UX NOT RUN. Next ID `EV-0107`. || 2026-11-01 | **EV-0107 (`PARTIAL`): M5 diagnostics export** — provider writes `vrmc-status.json` at init and on `status`; launcher `VRControlOverlay` builds `Documents/vrmc-diagnostics-<timestamp>.txt` (capped shell/compositor/thermal/latestlog/status/shutdown/command/settings sections, missing files marked) and offers ShareLink for manual save/AirDrop. Fully local, no telemetry/automatic upload. Full provider suite ALL PASS; shell build PASS; device share UI NOT RUN. Next ID `EV-0108`. || 2026-11-01 | **EV-0108 (`PARTIAL`): M6 crash guard + release readiness** — shell startup reads provider `vrmc-shutdown.log`; a last event other than `destroy-complete` increments `vrmc-crash-count.txt` and after two consecutive unclean sessions enables safe mode (`vrmc-safe-mode.flag`) which suppresses automatic immersive open while manual Enter VR remains available; clean sessions reset/remove it and the launcher can clear it manually. Added `scripts/m6_release_check.sh` (license/provider license/notices/privacy/source dirs/no tracked MC binaries/usage strings/manifest fields) → PASS on host readiness. Shell build PASS; device crash-guard/release acceptance NOT RUN. Next ID `EV-0109`. || 2026-11-01 | **EV-0109 (`PARTIAL`): M4-W4 use-hold/bow** — `SRC_FIST_HOLD` added; in-game `key.use` binding changed from the 2-frame fist tap to right-fist hold, giving continuous use (hold to draw, release to fire a bow) while GUI right-click remains tap-based; attack/teleport/climb unchanged. Host use-hold test PASS; m4-input 161 checks, full provider suite ALL PASS. Device bow/use/climb NOT RUN. Next ID `EV-0110`. || 2026-11-01 | **EV-0110 (`PARTIAL`): M5 frame-pacing telemetry** — `VisionFrameStats` (fixed-capacity poll-interval ring; mean/P50/P95/max ms; missed frames >1.5×90 Hz) integrated into `[VRMC-M5] diag:` with per-period reset; m5-frame-stats 10 checks PASS; full provider suite ALL PASS. Device K2/K5 pacing/thermal still NOT RUN; poll intervals are a Java-side proxy, not GPU timestamps. Next ID `EV-0111`. || 2026-11-01 | **EV-0111 (`PARTIAL`): M4-W4 climb-jump chord** — both-hand middle single-tap chord emits one 2-frame pulse and suppresses per-hand middle taps; binds `vivecraft.key.climbeyJump` (CONTEXTUAL, both origins). Binding table 22 rows/20 actions; middle suite 21 checks PASS; full provider suite ALL PASS. Device climb grab/jump NOT RUN. Next ID `EV-0112`. || 2026-11-01 | **EV-0112 (`PARTIAL`): M5 launcher panel extension** — added world-scale slider (0.80–1.50×), auto/manual height toggle+slider (auto=-1, manual 1.30–2.10 m) and diagnostics-period stepper (10–120 s) to the launcher VRMC settings panel; reads/writes existing `vrmc-runtime.properties` keys, clamps UI ranges, preserves unrelated keys; provider applies at next launch (EV-0105). Shell framework build PASS; device UI/comfort feel NOT RUN. Next ID `EV-0113`. || 2026-11-01 | **EV-0113 (`PARTIAL`): latest build staged/installed** — native app with current M4/M5/M6 code built and signed (169 Mach-O, codesign deep/strict PASS), app tree sha256 `3a03076f…`, installed on D1; provider jar sha256 `fc8cc4b1…` built and pushed. Device was locked (`passcodeRequired=true`), so no behavior/gesture/UI verification. Build identity is not a release manifest. Next ID `EV-0114`. || 2026-11-01 | **EV-0114 (`PARTIAL`): M5 command feedback + live launcher status; latest build** — command/recenter completion shows a reflective action-bar message (`[VRMC] <command>: <detail>`); launcher overlay polls `vrmc-status.json`/thermal every 5 s for bridge/display-views/hands/seated/thermal/low-power status. Full provider suite ALL PASS; shell/native builds PASS; app tree `46c80630…` installed; provider `39e9714a…` pushed. Device locked: behavior NOT RUN. Next ID `EV-0115`. || 2026-11-01 | **EV-0115 (`PASS`, host safety): M4/M6 fuzz hardening** — deterministic 20,000-frame `VisionInputFuzzTest` (seed 0x5EEDC0DE; tracking loss, malformed tracked bits, NaN/Inf joints, stale 300–700 ms gaps, environment flips) initially found 2 violations: both-hand tap/fist chord 2-frame pulses could outlive one hand's tracking. Fixed in `VisionInput.updateGestures` by clearing both-hand chord state the same frame a hand is untracked. 20k frames/0 violations; full provider suite ALL PASS; updated provider jar pushed to D1. Real-hands behavior still NOT RUN. Next ID `EV-0116`. || 2026-11-01 | **EV-0116 (`PASS`, host): M6 bridge shared-channel concurrency** — new `bridge_shared_test.c` runs a writer (20k display-view publishes, 20k gaze events, tracking override, game-stopping signals) against a reader consuming all channels; checks generation monotonicity/payload sanity/gaze consumption/boolean game-stopping; normal + ThreadSanitizer steps wired into `bridge/tests/run_tests.sh`. Full bridge suite ALL PASS. Device behavior still NOT RUN. Next ID `EV-0117`. || 2026-11-01 | **EV-0117 (`PARTIAL`): M5 gesture toggles + reference; app installed** — launcher panel toggles `middle.enabled`/`swipe.enabled` into `vrmc-input-tune.properties` (other keys preserved; applied next launch) and shows a gesture reference; shell rebuilt/staged/installed (169 Mach-O, deep/strict verify PASS; app tree `abc48c93…`), provider `d6de9469…` already on device. Device locked: UI/gesture behavior NOT RUN. Next ID `EV-0118`. || 2026-11-01 | **EV-0118 (`PARTIAL`): M4-W4 direct hotbar wheel** — VisionInput adds thumb-ring pinch chord state (hysteresis/arming/loss/opt-out, fuzz-covered); `VisionHotbarWheel` maps left-hand displacement to slots 1–9; VisionVR enters wheel on both ring pinches, shows action-bar slot changes, commits on release via reflection, cancels on stale/lost input. Tests: hotbar-wheel 8 + ring-chord 8 PASS, fuzz 20k/0, full provider suite PASS. App tree `0726af92…` installed, provider `cc24d16b…` pushed; device behavior NOT RUN. Next ID `EV-0119`. || 2026-11-01 | **EV-0119 (`PARTIAL`): M6 release workflow** — clean-tree release check PASS, manifest generated with `dirty_tree=no` and all pins/hashes/licensing fields, and `scripts/m6_package_release.sh` produced a development sideload package (app + provider jar + LICENSE/provider license/notices/privacy/README/versions.env/manifest/INSTALL) sha256 `d583608d…` (206,308,244 bytes). Device AC/K evidence and final release sign-off NOT RUN. Next ID `EV-0120`. || 2026-11-01 | **EV-0120 (`PARTIAL`): live input reload + launcher button** — command whitelist adds `reload-input`; VisionVR recreates VisionInput from the current `vrmc-input-tune.properties` (middle/ring/swipe/thresholds/hotbar range), resets binding resolution, logs flags and shows action-bar feedback; launcher gains a Reload input button. Provider suite ALL PASS; shell build PASS; app `4d55c1b0…` installed; provider `46699ae2…` pushed. Device locked: behavior NOT RUN. Next ID `EV-0121`. || 2026-11-01 | **EV-0121 (`PARTIAL`): bow/use teleport suppression + crash-log export** — `VisionInput.bindingPressed` suppresses teleport while the right fist is held for continuous use/bow draw (restores on release; host test, m4-input 164 checks); launcher diagnostics bundle adds prior shell/compositor logs + `hs_err_pid*.log` + crash-reports. Full provider suite ALL PASS; shell/app build/install PASS (app `a4500d7b…`, provider `7bc599e7…`). Device behavior NOT RUN. Next ID `EV-0122`. || 2026-11-01 | **EV-0122 (`PARTIAL`): M5 comfort vignette** — compositor `fmain_flat_vignette` pipeline darkens the flat-sampled image toward the periphery by `vrmc-vignette.flag` strength (0–0.9, empty=0.5, read once per immersive session; test pattern unaffected); launcher gains Comfort vignette toggle + 0.1–0.9 strength slider writing/removing the flag. Shell build/app install PASS (app `2914e6df…`); runtime shader compile/appearance/comfort NOT RUN. Next ID `EV-0123`. || 2026-11-01 | **EV-0123 (`PARTIAL`): M5 advanced input tuning UI** — launcher sliders for middle-pinch/ring-pinch on/off thresholds (20–70 mm), swipe speed (0.5–3.0 m/s) and hotbar range (0.10–0.30 m) write `vrmc-input-tune.properties` (metres, off>on enforced, other keys preserved); applies live via Reload input or next launch. Shell/app build/install PASS (app `8ec4b31a…`); device UI/tuning feel NOT RUN. Next ID `EV-0124`. || 2026-11-01 | **EV-0124 (`PARTIAL`): in-game controls help + reference** — command whitelist adds `controls`; provider sends a 6-line gesture reference to Minecraft chat via reflection; launcher Controls help button queues it; `docs/mvp/M4_CONTROLS.md` documents W1/W3/W4 gestures, opt-in swipes, safety/tuning and device-only gaps. Full provider suite ALL PASS; app `17433e3d…` installed; provider `1af22936…` pushed. Device chat UX NOT RUN. Next ID `EV-0125`. || 2026-11-01 | **EV-0125 (`PARTIAL`): M4 conflict fix + optional fingertip component mode** — both-fists (inventory chord) no longer also holds continuous use (single right fist still holds use; restored when one opens; m4-input 168 checks). Experimental `hands.componentMode=joints` uses `VisionHandPose.tipOffset` for the tip component (identity default; m4-pose 67 checks incl. rotation/degenerate). Full provider suite ALL PASS; provider jar `4fa76795…` pushed; app unchanged `17433e3d…`. Device visible-hands/held-item appearance NOT RUN. Next ID `EV-0126`. || 2026-11-01 | **EV-0126 (`PARTIAL`): gaze config opt-in safety** — tracking-area layer configuration and the spatial-event handler are now installed only when `Documents/vrmc-gaze.flag` exists (and no `vrmc-no-tracking-areas.flag`), keeping gaze-off sessions on the accepted EV-0094 presentation path. Shell/app build/install PASS (app `926f663d…`). Simulator input scenario backgrounds the app before any compositor log (reproduces with opt-in), so it is not used as evidence; true gaze/device behavior NOT RUN. Next ID `EV-0127`. || 2026-11-01 | **EV-0127 (`PARTIAL`): M5 turn-angle picker + acceptance/runbook** — launcher now offers Smooth/15/30/45/90 turn angles saved to `comfort.worldRotationIncrement` (existing runtime path); `docs/mvp/M5_ACCEPTANCE.md` maps H1–H10/comfort/diagnostics with honest status, and `docs/mvp/M5_DEVICE_RUN.md` is the step-by-step D1 procedure/evidence plan. Shell/app build/install PASS (app `a2809f6d…`); device run NOT RUN. Next ID `EV-0128`. || 2026-11-01 | **EV-0128 (`PARTIAL`): M5 diagnostics viewer + pacing warning** — launcher Recent diagnostics disclosure reads capped log tails and extracts `[VRMC-`/WARN/ERROR/FAIL/CRASH lines (refresh; last 8), status line reports providerJar presence; provider diag adds explicit frame-pacing WARN when p95 >16.7 ms or missed90 > max(2, frames/10). Provider suite ALL PASS; app `bcdb5987…` installed; provider `54353013…` pushed. Device UI/behavior NOT RUN; simulator remains unusable (immediate backgrounding). Next ID `EV-0129`. || 2026-11-01 | **EV-0129 (`PARTIAL`): M5 seated HMD pointer parity** — opt-in `comfort.seatedHmdPointer` lets the HMD-aim fallback pose drive controllerTracking/GUI pointer when seated with no tracked hand; actions still require gestures; default off. Launcher toggle added. m5-settings 23 checks, full provider suite ALL PASS; app `dfc8f9a1…` installed; provider `d07eb84b…` pushed. Device seated behavior NOT RUN. Next ID `EV-0130`. || 2026-11-01 | **EV-0130 (`PARTIAL`): M5 W1 tuning sliders + input tuning status** — launcher Input tuning adds W1 pinch on/off (mm) and fist on/off sliders (off>on enforced, other keys preserved, applies via reload-input/next launch); VisionInput.tuningSummary now reported in `vrmc-status.json` together with hotbarRange. m4-input 172 checks PASS; full provider suite ALL PASS; app `1981c5ed…` installed; provider `5fa45dc4…` pushed. Device UI/tuning NOT RUN. Next ID `EV-0131`. || 2026-11-01 | **EV-0131 (`PARTIAL`): M5 thermal pressure awareness** — shell thermal monitor writes `vrmc-thermal-state.txt` (state/lowPower/time); provider reads it, logs and shows an action-bar advisory on serious/critical state changes (advisory only; no automatic setting changes) and reports `thermalState` in `vrmc-status.json`. m5-thermal 8 checks PASS; full provider suite ALL PASS; app `624cda74…` installed; provider `fc3d98d6…` pushed. Device thermal behavior/K5 NOT RUN. Next ID `EV-0132`. || 2026-11-01 | **EV-0132 (`PARTIAL`): M6 compositor heartbeat + shell watchdog** — compositor writes `Documents/vrmc-heartbeat.txt` at most 1 Hz with generation/frame/presented/drawables/layer state; shell watchdog checks every 5 s during immersive+presenting, logs one stall warning + sets launcher status when >20 s stale, logs recovery, and includes the heartbeat in diagnostics export; does not auto-kill. Shell/app build/install PASS (app `6b013be6…`). Device hang/recovery behavior NOT RUN. Next ID `EV-0133`. || 2026-11-01 | **EV-0133 (`PARTIAL`): opt-in thermal quality reduction** — `performance.thermalResponse=notify|reduce` (default notify) parsed/applied; on serious/critical thermal state with reduce, provider caps renderDistance/simulationDistance ≤8 and framerateLimit ≤72 once per episode (never auto-restores), logs+action-bar; launcher picker added. m5-settings 25 checks; full provider suite ALL PASS; app `c6e05338…` installed; provider `afbbb507…` pushed. Device K5 thermal behavior NOT RUN. Next ID `EV-0134`. || 2026-11-01 | **EV-0134 (`PARTIAL`): provider hash + settings reset** — launcher status reports provider-jar SHA256 (first 12 hex) or `MISSING`, diagnostics bundle includes provider hash/path; added Reset VRMC settings button removing runtime/input/vignette configs only (saves/logs/crash guard untouched). Shell/app build/install PASS (app `b7e7cd63…`); provider unchanged. Device UI NOT RUN. Next ID `EV-0135`. || 2026-11-02 | **EV-0135 (`PARTIAL`): opt-in adaptive framerate** — `performance.adaptiveFramerate` (default false) caps framerateLimit to ≤72 once after two consecutive over-budget diag windows (p95>16.7 ms or missed90>max(2,frames/10)), logs+action-bar, no auto-restore; launcher toggle and status fields added. m5-settings 27 checks; full provider suite ALL PASS; app `a8196eda…` installed; provider `4602605f…` pushed. Device K2 pacing NOT RUN. Next ID `EV-0136`. || 2026-11-02 | **EV-0136 (`PARTIAL`): read-only device provider-integrity check PASS** — added `scripts/m6_device_integrity.sh`; D1 lists VRMC 1.2.0 and the data-container provider jar matches the local build (`4602605f…`, 85,957 bytes) => PASS. Read-only/no-unlock; device behavior, gestures, UI and AC/K gates remain NOT RUN. Next ID `EV-0137`. || 2026-11-02 | **EV-0137 (`PARTIAL`): read-only device diagnostics pull** — added `scripts/m6_device_diagnostics_pull.sh` (no launch/unlock, writes SHA256SUMS). Current D1 pull: 3/18 files; current shell log absent => latest build has not been launched since install; old compositor log tail shows a clean earlier session (presentedFrames=4466, game stopping -> input release -> VRMCImmersiveEnded, provider state=3 errorCode=0, no crash markers). Behavior/acceptance remain NOT RUN. Next ID `EV-0138`. || 2026-11-02 | **EV-0138 (`PARTIAL`): M5 locomotion tuning sliders** — launcher Input tuning adds move forward/strafe scale (1–6), deadzone (0.02–0.40), originZ (−0.30–0.30) and snap-turn pulse (60–300 ms) writing `move.*` keys to `vrmc-input-tune.properties` (other keys preserved; reload/next launch). Shell/app build/install PASS (app `cfaf72c7…`); provider unchanged. Device locomotion feel NOT RUN. Next ID `EV-0139`. || 2026-11-02 | **EV-0139 (`NOT RUN`): M6 acceptance readiness report/gate** — `scripts/m6_acceptance_report.sh` parses M5 H1–H10 + M6 AC-1..AC-6/K1..K6, prints per-row status/counts and `--require-pass` fails unless every row is explicit PASS. Current report: rows=22 pass=0 partial=3 not-run=11 => **NOT READY** (device gates NOT RUN); snapshot `export/acceptance-readiness.txt`. No device behavior claims. Next ID `EV-0140`. || 2026-11-02 | **EV-0140 (`PARTIAL`): command-result feedback + Status button** — launcher reads the last non-empty `vrmc-command-result.txt` line on each status refresh and displays it under the command buttons; adds Status button queueing the existing `status` command. Shell/app build/install PASS (app `e82a7a89…`); provider unchanged on device; device UI NOT RUN. Next ID `EV-0141`. || 2026-11-02 | **EV-0141 (`PARTIAL`): use/attack priority conflict hardening** — while the right fist holds continuous use/bow draw, `key.attack` is suppressed during a transitioning pinch; use remains held and attack returns after the fist opens. m4-input 176 checks; full provider suite ALL PASS; provider `94f868e8…` (85,963 bytes) pushed and device integrity PASS. Device feel/behavior NOT RUN. Next ID `EV-0142`. || 2026-11-02 | **EV-0142 (`PARTIAL`): M4-W2 tracking-dropout pose hold** — on dropout the last valid hand pose is held for `tracking.holdLastPoseMs` (default 250 ms, configurable 0–2000/launcher slider) before shoulder fallback; actions still release and no input latches; throttled per-hand log. Full provider suite ALL PASS; shell builds; app `79b7a0cf…` installed; provider `7a9a1118…` pushed + device integrity PASS. Device visual/aim dropout behavior NOT RUN. Next ID `EV-0143`. || 2026-11-02 | **EV-0143 (`PARTIAL`): source offer + refreshed dev package** — added `SOURCE_OFFER.md` for GPL/LGPL corresponding source (3-year written offer, rebuild instructions, no Minecraft/Vivecraft redistribution), required by release check and included with M4/M5/M6 docs; clean-tree release check PASS, manifest `dirty_tree=no`, package bytes=206,440,226 sha256 `7cfc1433f4378816984d4ae1cb677493ddd1641d06bdf8414ffecc831fffca45`; device provider integrity PASS. Device AC/K/H gates remain NOT RUN → acceptance NOT READY; development package only. Next ID `EV-0144`. || 2026-11-02 | **EV-0144 (`PARTIAL`): status JSON fix + launcher provider summary** — found/fixed invalid `vrmc-status.json` (`adaptiveFramerateApplied` had a stray quote); launcher now parses status each refresh and shows provider abi/bridge/tracked/hands/thermal/adaptive, falling back to empty on missing/invalid JSON. Full provider suite ALL PASS; app `748e730e…` installed; provider `9aeff79d…` pushed + device integrity PASS. No automated JSON-schema test; device UI NOT RUN. Next ID `EV-0145`. || 2026-11-02 | **EV-0145 (`PARTIAL`): testable status JSON builder** — extracted `VisionStatusJson` (pure) owning `vrmc-status.json` generation with string escaping/finite numbers; added `VisionStatusJsonTest` strict JSON parser covering values/types/escapes/trailing-comma regression (12 checks). Full provider suite ALL PASS; provider `8a6f769a…` (89,006 bytes) pushed + device integrity PASS. Actual file write against a live game remains untested; device behavior NOT RUN. Next ID `EV-0146`. || 2026-11-02 | **EV-0146 (`PARTIAL`): thermal-state polling throttle** — `pollThermalState()` had been doing `isRegularFile` + `readAllLines` every game frame (up to 90 Hz filesystem I/O on the render thread); now throttled to once per 5 s with immediate first poll, advisory behavior unchanged. Full provider suite ALL PASS; provider `e66266dd…` (89,045 bytes) pushed + device integrity PASS. Device runtime performance NOT RUN. Next ID `EV-0147`. || 2026-11-02 | **EV-0147 (`PARTIAL`): allocation-free display/locomotion paths** — `pollDisplayViews` reuses a 16-float scratch instead of allocating per eye/generation; `VisionLocomotion.axes(..., dest)` allocation-free path always overwrites (stale axes cleared on NaN), used by applyLocomotion; m4-locomotion 9 checks. Full provider suite ALL PASS; provider `30ec7452…` (89,200 bytes) pushed + device integrity PASS. Device runtime/GC performance NOT RUN. Next ID `EV-0148`. || 2026-11-02 | **EV-0148 (`PARTIAL`): frame pacing in status JSON + launcher** — status JSON now exposes last-window frameP50Ms/frameP95Ms/missed90Frames; launcher provider summary shows p95/missed90 alongside ABI/bridge/hands/thermal/adaptive; strict JSON test extended to 15 checks. Full provider suite ALL PASS; app `46756212…` installed; provider `57ddc366…` (89,469 bytes) pushed + device integrity PASS. Device K2 pacing NOT RUN. Next ID `EV-0149`. || 2026-11-02 | **EV-0149 (`PARTIAL`): soak harness hardening + release-check dry-run** — harness pulls the real Minecraft log path plus heartbeat/status, flags OOM/watchdog, and defaults to failing when the shutdown journal lacks `destroy-complete` (clean-teardown AC-5; `REQUIRE_CLEAN_SHUTDOWN=0` for probes). `scripts/m6_release_check.sh` now runs the soak dry-run. Bash syntax/dry-run/release check PASS; device soak NOT RUN. Next ID `EV-0150`. || 2026-11-02 | **EV-0150 (`PARTIAL`): host install metrics + device acceptance runbook** — added `scripts/m6_install_metrics.sh` (app bundle 583,553,024 bytes/485 files/169 Mach-O; provider 89,469 bytes `57ddc366…`; package 206,440,226 `7cfc1433…`) with snapshot `export/install-metrics-dev.txt`, and `M6_DEVICE_RUN.md` covering AC-1…AC-6/K1…K6 execution, commands and evidence rules. Device install-size and all device gates NOT RUN. Next ID `EV-0151`. || 2026-11-02 | **EV-0151 (`PARTIAL`): reload-input completeness fix** — live reload previously applied only gesture thresholds + hotbar range; it now also reloads smoothing, move origin/forward/strafe/deadzone/rotate-pulse, `tracking.holdLastPoseMs`, `hands.componentMode`, rebuilds smoothers, cancels an in-progress hotbar wheel, and reports the applied categories. Full provider suite ALL PASS; provider `a4cf0507…` (89,640 bytes) pushed + device integrity PASS. Device live-reload behavior NOT RUN. Next ID `EV-0152`. || 2026-11-02 | **EV-0152 (`PARTIAL`): input tuning validation** — VisionInput rejects inverted hysteresis/tap/stale relations and clamps speed/ratio/cooldown/hold/arm/stale/tap-frame ranges, falling back to safe defaults with a warning; invalid-file host test added (m4-input 184 checks). Full provider suite ALL PASS; provider `cd7eacb7…` (90,619 bytes) pushed + device integrity PASS. Device live behavior NOT RUN. Next ID `EV-0153`. || 2026-11-02 | **EV-0153 (`PARTIAL`): async compositor heartbeat write** — throttling stays on the frame thread (≤1 Hz) but the atomic heartbeat file write now runs on a utility QoS queue, removing synchronous watchdog filesystem I/O from the render thread; dropped final write on abrupt death is harmless (stale heartbeat). Shell/app build/install PASS (app `0aebb806…`); provider unchanged `cd7eacb7…`. Device runtime performance NOT RUN. Next ID `EV-0154`. || 2026-11-02 | **EV-0154 (`PARTIAL`): reproducible provider jar** — `build_provider.sh` now packages with a fixed `jar --date` timestamp (`REPRO_TIMESTAMP` override); two independent builds produced identical sha256 `fcd1df769cd0a6a25a3664938f1440bdf8c0292d1a3971bd59674f07b8d3cbe2` (90,619 bytes). Full provider suite ALL PASS; jar pushed + device integrity PASS. Release manifest/package metadata must be regenerated to the new hash; device behavior NOT RUN. Next ID `EV-0155`. || 2026-11-02 | **EV-0155 (`PARTIAL`): reproducibility check + refreshed dev package** — added `m6_reproducibility_check.sh` (two-build sha/bytes compare) and used it: both builds `fcd1df76…` (90,619 bytes) PASS. Clean-tree release check PASS; package refreshed to bytes=206,459,027 sha256 `3b3fa4fe…` (app `0aebb806…`, provider `fcd1df76…`); manifest `dirty_tree=no`; export metadata refreshed. Acceptance gate NOT READY; device gates NOT RUN. Next ID `EV-0156`. || 2026-11-02 | **EV-0156 (`PARTIAL`): release check verifies provider reproducibility** — `scripts/m6_release_check.sh` now invokes `m6_reproducibility_check.sh` (two independent builds) and reports the provider hash; mismatch fails host readiness. Current release check PASS with provider `fcd1df76…` (90,619 bytes). Device AC/K/H gates remain NOT RUN/NOT READY. Next ID `EV-0157`. || 2026-11-02 | **EV-0157 (`PARTIAL`): launcher toggle for fingertip component** — experimental `hands.componentMode=joints|identity` toggle added to Input tuning, saved to `vrmc-input-tune.properties`, applied via Reload input/next launch; default identity keeps the device-accepted aim path. Shell/app build/install PASS (app `25c1bac1…`); provider unchanged `fcd1df76…`. Device visual/aim behavior NOT RUN. Next ID `EV-0158`. || 2026-11-02 | **EV-0158 (`PARTIAL`): reset-settings confirmation dialog** — Reset VRMC settings now requires explicit confirmation with scope text (removes runtime/input-tune/vignette only; saves/logs/crash guard kept). Shell/app build/install PASS (app `1400889b…`); provider unchanged `fcd1df76…`. Device dialog interaction NOT RUN. Next ID `EV-0159`. || 2026-11-02 | **EV-0159 (`PARTIAL`): diagnostics bundle completeness** — support bundle adds input tuning, thermal state file, vignette flag and the real Minecraft log path (`instances/default/logs/latest.log`) to the existing logs/status/shutdown/command/heartbeat/settings/crash set. Shell/app build/install PASS (app `a046bab6…`); provider unchanged `fcd1df76…`. Device export/share UI and actual bundle contents NOT RUN. Next ID `EV-0160`. || 2026-11-02 | **EV-0160 (`PARTIAL`): refreshed clean dev package** — clean-tree release check PASS, reproducibility PASS, package refreshed to app `a046bab6…` + provider `fcd1df76…`: bytes=206,458,384 sha256 `4f89d0d690e266ac961a1c06bf37e058994c53183347ae984b41fedc0a36c696`; manifest `dirty_tree=no`; metadata updated. Development sideload package only; acceptance NOT READY / device gates NOT RUN. Next ID `EV-0161`. || 2026-11-02 | **EV-0161 (`PARTIAL`): acceptance parser/status-column fix** — M6 acceptance rows were parsed from the last/evidence cell; the report now reads the actual status cell for AC/K rows (and strips backticks for M5 H rows), yielding accurate statuses/counts: rows=22, explicit-pass=0, not-run=17, partial=7; `--require-pass` exits NOT READY. Device gates remain NOT RUN; no device claims. Next ID `EV-0162`. || 2026-11-02 | **EV-0162 (`PARTIAL`): input fuzz 100k frames with W4 safety invariants** — `VRMC_FUZZ_FRAMES` configurable (default 20k/cap 2M); invariants add no ring chord when either hand untracked, no attack/teleport while right fist held, no use while both fists held. 100,000 frames / 0 violations; full provider suite ALL PASS (default 20k also PASS). Host stress only; device behavior NOT RUN. Next ID `EV-0163`. || 2026-11-02 | **EV-0163 (`PARTIAL`): extreme stress — 1M fuzz + TSan bridge suite** — provider `VRMC_FUZZ_FRAMES=1000000`: 1,000,000 random frames/0 violations (6.0 s). Full bridge suite incl. TSan builds: ALL PASS (sync 200k publishes×4 readers, tracking/display 500k writes/reads, input 500k publishes×4 readers; no torn state). Host-only; device behavior/AC gates NOT RUN. Next ID `EV-0164`. || 2026-11-02 | **EV-0164 (`PARTIAL`): path-independent app hash + package verifier** — added `app_tree_sha256.sh` (bundle-relative sha lines) and used it in the release manifest; added `m6_verify_release_package.sh`. Package rebuilt: bytes=206,459,032 sha256 `46b14b6a870b02185d9835682ec256162e13329b01303ba4a895aa4afabc081a`, app path-independent `d1d68596…`, provider `fcd1df76…`; verifier PASS (required entries, app/provider hashes, dirty_tree=no). Older app hashes used absolute paths and are not comparable. Development package only; acceptance NOT READY. Next ID `EV-0165`. || 2026-11-02 | **EV-0165 (`PARTIAL`): single-command release gate** — added `scripts/m6_release_ready.sh` aggregating host release check, package verifier, read-only device provider integrity, and acceptance `--require-pass`. Current result: host/package/device PASS, acceptance 0/22 explicit PASS → **NOT RELEASE READY** (expected until D1 acceptance). No behavior claims. Next ID `EV-0166`. || 2026-11-02 | **EV-0166 (`PARTIAL`): VisionHandPose 200k numerical fuzz** — randomized joints/quats/translations incl. zero, 1e-30, ±1e20, ±100: 200,000 cases, nonFiniteSeen=0, violations=0; pose basis unit/orthogonal/det≈+1, translation preserved, tipOffset/gazeFallback finite. Full provider suite ALL PASS. Host numerical stress only; device behavior NOT RUN. Next ID `EV-0167`. || 2026-11-02 | **EV-0167 (`PARTIAL`): smoother 100k numerical fuzz** — random normalized rotations, translations ±1e4 with periodic 1e20, forward/duplicate/zero timestamps and resets: 100,000 cases, 0 violations; smoothed poses finite and rotations unit-length. Full provider suite ALL PASS. Host numerical stress only; device behavior NOT RUN. Next ID `EV-0168`. || 2026-11-02 | **EV-0168 (`PARTIAL`): status JSON 100k fuzz** — arbitrary/control/unicode strings in status fields, random ints/bools and NaN/Inf/huge `hotbarRange`: 100,000 build+strict-parse round-trips, 0 violations; shared strict `TestJson` parser, status-json regression 15 checks PASS. Full provider suite ALL PASS. Host-only; device behavior NOT RUN. Next ID `EV-0169`. || 2026-11-02 | **EV-0169 (`PARTIAL`): runtime-settings 100k fuzz** — 100,000 random `vrmc-runtime.properties` maps across known/unknown keys with empty/boolean/NaN/Infinity/huge/negative/random strings: parse never throws and all applied values stay within documented bounds. Full provider suite ALL PASS. Host-only parser robustness; device behavior NOT RUN. Next ID `EV-0170`. || 2026-11-02 | **EV-0170 (`PARTIAL`): command-file size cap** — oversized local command files (>4096 bytes) are rejected before reading, consumed, and recorded as REJECTED oversized; host test covers rejection/consumption/result (m5-command 14 checks). Full provider suite ALL PASS; provider `bad3d955…` (90,791 bytes) pushed + device integrity PASS. Device behavior NOT RUN. Next ID `EV-0171`. || 2026-11-02 | **EV-0171 (`PARTIAL`): refreshed package to command-cap provider** — clean-tree release check/repro PASS; package bytes=206,459,555 sha256 `6e99d8e994571ba75d134f5e95d14a903fd4b30df0dc3b75d86626c2110f819c` (app `d1d68596…`, provider `bad3d955…`); package verifier PASS; release-ready gate host/package/device-integrity PASS, acceptance NOT READY. Development package only; device AC/K/H gates NOT RUN. Next ID `EV-0172`. || 2026-11-02 | **EV-0172 (`PARTIAL`): launcher-provider settings key parity guard** — `scripts/check_settings_keys.sh` extracts all 31 launcher-written runtime/input key literals and requires provider source recognition; release check integrates/reports it. checked=31 all OK; release check PASS. Host drift guard only; device behavior/AC gates NOT RUN. Next ID `EV-0173`. || 2026-11-02 | **EV-0173 (`PARTIAL`): launcher status-field parity guard** — `scripts/check_status_fields.sh` validates all 11 launcher-read status fields are written by `VisionStatusJson`; release check integrates/reports it. checked=11 all OK; release check PASS. Host drift guard only; device behavior/AC gates NOT RUN. Next ID `EV-0174`. || 2026-11-02 | **EV-0174 (`PARTIAL`): bow diagnostic telemetry** — `VisionStatusJson` adds `bowActive`/`bowNotched`/`bowDrawPercent` (clamped from `dh.bowTracker`); launcher summary appends bow state only while active. JSON regression 18 checks + 100k fuzz PASS; full provider suite ALL PASS; status-field guard checked=14; app `6e4b7c5e…` installed; provider `47713964…` (91,130 bytes) pushed + device integrity PASS. Device two-hand bow/AC-4 behavior NOT RUN. Next ID `EV-0175`. || 2026-11-02 | **EV-0175 (`PARTIAL`): refreshed package/metrics for bow build** — clean-tree release check/repro PASS; package bytes=206,462,210 sha256 `8a82159e54eb5bf0abafc507301b2575cc5738c96efae98aa52280e970f4efcd` (app `6e4b7c5e…`, provider `47713964…`); verifier and release-ready host gates PASS; acceptance NOT READY. Metrics refreshed (app 583,630,848 bytes/485 files/169 Mach-O; provider 91,130 bytes). Development package only; device gates NOT RUN. Next ID `EV-0176`. || 2026-11-02 | **EV-0176 (`PARTIAL`): climb diagnostic telemetry** — status JSON adds `climbGrabbing`/`climbeyClimb`/`climbActive` (from `dh.climbTracker`); launcher displays climb state when active. JSON regression 21 checks + 100k fuzz PASS; full provider suite ALL PASS; status-field guard checked=17; app `90c83c0d…` installed; provider `1d36487e…` (91,427 bytes) pushed + device integrity PASS. Device H9 climbing behavior NOT RUN. Next ID `EV-0177`. || 2026-11-02 | **EV-0177 (`PARTIAL`): refreshed package/metrics for climb build** — clean release check/repro PASS; package bytes=206,468,279 sha256 `9720b6527c5276b2ec25aa897ad9171e2799fbbbc5c2a05cf1383c0ce34abc2f` (app `90c83c0d…`, provider `1d36487e…`); verifier/release-ready host gates PASS; acceptance NOT READY; metrics refreshed. Development package only; device gates NOT RUN. Next ID `EV-0178`. || 2026-11-02 | **EV-0178 (`PARTIAL`): restore-performance command/button** — provider captures original render/sim/fps before thermal/adaptive caps; new `restore-performance` restores them once, clears applied flags/pressure counter, logs/action-bar (or reports nothing to restore); launcher button added. m5-command 15 checks; full provider suite ALL PASS; app `2939c509…` installed; provider `5379fe2c…` (92,008 bytes) pushed + device integrity PASS. Device restore behavior NOT RUN. Next ID `EV-0179`. || 2026-11-02 | **EV-0179 (`PARTIAL`): refreshed package for restore-performance build** — package bytes=206,470,289 sha256 `20ffc04d980001124a9585f9511047b3a7f17bedc62b9482003486d6298ce648` (app `2939c509…`, provider `5379fe2c…`); verifier/release-ready host gates PASS; acceptance NOT READY; metrics refreshed. Development package only; device gates NOT RUN. Next ID `EV-0180`. || 2026-11-02 | **EV-0180 (`PARTIAL`): stale-package guard in release gate** — added `m6_check_release_current.sh` (embedded manifest app/provider hashes vs current local builds) and release-ready runs it before package verification. Current package app `2939c509…`/provider `5379fe2c…` match → PASS; host gates PASS; acceptance NOT READY. Device gates NOT RUN. Next ID `EV-0181`. || 2026-11-02 | **EV-0181 (`PARTIAL`): status/handoff document** — `docs/mvp/STATUS.md` summarizes current app/provider identity, milestone states, implemented features, host verification commands/results, remaining device-only runbooks and known risks; linked from README. Documentation only; device AC/K/H gates remain NOT RUN. Next ID `EV-0182`. || 2026-11-02 | **EV-0182 (`PARTIAL`): auto status JSON writes** — status is written automatically on first update and after every diagnostic window (no per-frame I/O), keeping launcher/support diagnostics current without a manual Status command. Full provider suite ALL PASS; reproducible provider `702e7193…` (92,084 bytes) pushed + device integrity PASS; app unchanged `2939c509…`. Device behavior NOT RUN. Next ID `EV-0183`. || 2026-11-02 | **EV-0183 (`PARTIAL`): refreshed package for auto-status build** — package bytes=206,470,666 sha256 `f6a687ace74facb3e266f4a858fb0618d55b032f46750c70f7f010f711c843c0` (app `2939c509…`, provider `702e7193…`); freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics refreshed. Development package only; device gates NOT RUN. Next ID `EV-0184`. || 2026-11-02 | **EV-0184 (`PARTIAL`): auto-sprint settings** — `comfort.autoSprint` and `comfort.autoSprintThreshold` (0.5–1.0) parsed/applied to Vivecraft `autoSprint`/`autoSprintThreshold`; launcher toggle+slider. m5-settings 29 checks PASS; settings-key guard checked=33; full provider suite ALL PASS; app `2388965a…` installed; provider `a109ae56…` (92,516 bytes) pushed + device integrity PASS. Device sprint/feel behavior NOT RUN. Next ID `EV-0185`. || 2026-11-02 | **EV-0185 (`PARTIAL`): refreshed package/metrics/status for auto-sprint build** — package bytes=206,471,014 sha256 `bc497dfe140db8433bffa532cfffa2e84488de0fcaf8ef11d2daba9189d2ebbd` (app `2388965a…`, provider `a109ae56…`); freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics + STATUS.md refreshed. Development package only; device gates NOT RUN. Next ID `EV-0186`. || 2026-11-02 | **EV-0186 (`PARTIAL`): gaze math 500k fuzz** — invalid/negative/huge tile ids/grid sizes, finite random tangents/NDC, random rotations/positions, zero/huge clamp scale/aspect: 500,000 cases, 0 violations; `tileToNdc` null-or-in-range, `eyeRay` finite normalized, `intersectGuiPlane` null-or-in-[0,1]. Full provider suite ALL PASS. Host math stress only; device gaze behavior NOT RUN. Next ID `EV-0187`. || 2026-11-02 | **EV-0187 (`PARTIAL`): release gate default app freshness** — `m6_release_ready.sh` defaults `RELEASE_APP_BUNDLE` from the identity file's staged app path; current package freshness checks app `2388965a…` + provider `a109ae56…` automatically (both match). Host gates PASS; acceptance NOT READY; device AC/K/H gates NOT RUN. Next ID `EV-0188`. || 2026-11-02 | **EV-0188 (`PARTIAL`): consolidated host regression** — shell build, provider suite (incl. all fuzz), bridge suite incl. TSan, M4 selfcheck --fast, release check, package verifier/freshness, device integrity all PASS; release-ready host gates PASS but acceptance 0/22 explicit PASS → NOT READY. Device AC/K/H gates NOT RUN. Next ID `EV-0189`. || 2026-11-02 | **EV-0189 (`PARTIAL`): M4 plan host-complete status** — appended 6w summary to `M4_PLAN.md` covering host-complete W4/W5 features and explicit device-only gaps; authoritative gesture map remains `M4_CONTROLS.md`. Documentation only; device AC/K/H gates NOT RUN. Next ID `EV-0190`. || 2026-11-02 | **EV-0190 (`PARTIAL`): guided hand calibration** — pure 3×3 s OPEN/FISTS/PINCH protocol collects pinch/fist min-max, suggests on/off thresholds and writes an advisory report; `calibrate-hands` command prompts via action bar/samples tracked hands/writes `vrmc-hand-calibration.txt`; launcher button and diagnostics entry added. m4-hand-calibration 15 checks, m5-command 16; guards PASS; app `b0680cac…` installed; provider `a4212200…` (95,870 bytes) pushed + device integrity PASS. Device calibration protocol NOT RUN. Next ID `EV-0191`. || 2026-11-02 | **EV-0191 (`PARTIAL`): calibration journal feedback + package refresh** — calibration completion appends the one-line suggestion to `vrmc-command-result.txt` so launcher Last result shows it. Package refreshed bytes=206,479,055 sha256 `9540a8a947a2f360742b7c7f958474b975eab2132da74e944d2792aa8287a7ac` (app `b0680cac…`, provider `18029045…`); freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics/STATUS updated. Device calibration behavior NOT RUN. Next ID `EV-0192`. || 2026-11-02 | **EV-0192 (`PARTIAL`): apply-hand-calibration command + package refresh** — parses the latest calibration one-liner, validates inverted/NaN reports, atomically updates only pinch.on/off + fist.on/off in `vrmc-input-tune.properties` preserving unrelated keys, then reloads the input engine; launcher button added. m4-hand-calibration 22 checks, m5-command 17; full suite ALL PASS; app `595982a2…` installed; provider `50cd776b…` (98,928 bytes) pushed + integrity PASS; package bytes=206,483,529 sha256 `4e1d99823e79c3aa813b0cf3aad1ff0a3aade1f811f6d662b85643e0c87c9ef5`; host gates PASS; acceptance NOT READY. Device calibration/apply behavior NOT RUN. Next ID `EV-0193`. || 2026-11-02 | **EV-0193 (`PARTIAL`): targeted reset input tuning** — confirmation button removes only `vrmc-input-tune.properties`, reloads UI defaults and queues `reload-input`, leaving runtime/comfort settings, saves, logs and crash guard intact. Shell/app build/install PASS (app `f1ae3749…`); provider unchanged `50cd776b…` + device integrity PASS. Device UI NOT RUN. Next ID `EV-0194`. || 2026-11-02 | **EV-0194 (`PARTIAL`): refreshed package for targeted-reset build** — package bytes=206,486,820 sha256 `efe71843f71e669e4e6164fab39c8cafcf144fb6d75917006918121f3b737cf5` (app `f1ae3749…`, provider `50cd776b…`); freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics/STATUS updated. Development package only; device gates NOT RUN. Next ID `EV-0195`. || 2026-11-02 | **EV-0195 (`PARTIAL`): raw-gesture diagnostics summary** — `VisionInput.gestureSummary` exposes held gesture sources per hand (pinch/fist/middle/ring/swipe) + ring chord; status JSON/launcher show it only when non-empty for stuck-input/AC-4 debugging. m4-input 187 checks; status-field guard checked=18; full provider suite ALL PASS; app `7d36ce9e…` installed; provider `27155fd1…` (99,404 bytes) pushed + device integrity PASS. Device behavior NOT RUN. Next ID `EV-0196`. || 2026-11-02 | **EV-0196 (`PARTIAL`): release-input panic command** — recreates the gesture engine with current tuning, clears bindings/hotbar wheel/snap pulse to release all held actions; gestures re-arm only on fresh input; launcher button and action-bar confirmation. m5-command 18 checks; full provider suite ALL PASS; app `cf231fc7…` installed; provider `4587b5d2…` (99,576 bytes) pushed + device integrity PASS. Device panic/recovery behavior NOT RUN. Next ID `EV-0197`. || 2026-11-02 | **EV-0197 (`PARTIAL`): round-100 package refresh** — package bytes=206,493,046 sha256 `7e9e608ce8f5f53a857fff8bd87f1ba46cf39be9ce0aeebe34b333303bbe68bd` (app `cf231fc7…`, provider `4587b5d2…`); freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics/STATUS updated. Development package only; device gates NOT RUN. Next ID `EV-0198`. || 2026-11-02 | **EV-0198 (`PARTIAL`): in-headset acceptance checklist** — launcher checklist tracks H1–H10 + AC-1..6 statuses, persists `vrmc-acceptance-checklist.json` atomically and includes it in diagnostics exports for device evidence sharing. Shell/app build/install PASS (app `1990b20b…`); provider unchanged `4587b5d2…` + device integrity PASS. Device interaction/export NOT RUN. Next ID `EV-0199`. || 2026-11-02 | **EV-0199 (`PARTIAL`): checklist Markdown export** — saving the in-headset checklist now also writes `vrmc-acceptance-summary.md` as a Markdown table for VERIFY evidence; diagnostics export includes JSON + MD. Shell/app build/install PASS (app `73dee838…`); provider unchanged `4587b5d2…` + device integrity PASS. Device interaction NOT RUN. Next ID `EV-0200`. || 2026-11-02 | **EV-0200 (`PARTIAL`): checklist status counts** — acceptance checklist header displays PASS/PARTIAL/FAIL/NOT RUN counts for at-a-glance device progress. Shell/app build/install PASS (app `a4663e16…`); provider unchanged `4587b5d2…` + device integrity PASS. Device interaction NOT RUN. Next ID `EV-0201`. || 2026-11-02 | **EV-0201 (`PARTIAL`): refreshed package for checklist-summary build** — package bytes=206,538,366 sha256 `4d9141f05a8993a0c5242534df4ff102aaefe6fffd7ae555bf82c06dd9e3d2af` (app `a4663e16…`, provider `4587b5d2…`); freshness/verifier/release-ready host gates PASS; acceptance NOT READY; metrics/STATUS updated. Development package only; device gates NOT RUN. Next ID `EV-0202`. || 2026-11-02 | **EV-0202 (`PARTIAL`): final consolidated host regression** — shell build, full provider suite, bridge suite, M4 selfcheck --fast, release check, package freshness/verifier, device integrity and release-ready host gates all PASS; acceptance 0/22 explicit PASS → NOT READY. Device AC/K/H gates remain NOT RUN; current build app `a4663e16…`/provider `4587b5d2…`, package `4d9141f0…`. Next ID `EV-0203`. || 2026-11-02 | **EV-0203 (`PARTIAL`): checklist importer** — `scripts/m6_import_device_checklist.sh` pulls (or `--input`) `vrmc-acceptance-checklist.json`, validates statuses, writes `export/device-acceptance-report.md` + machine status lines; `--require-no-fail` fails on FAIL. Host fixture tests cover normal/FAIL/bogus/missing; an argument-loop hang (`--require-no-fail` missing shift) was found and fixed. Actual device pull/import NOT RUN. Next ID `EV-0204`. || 2026-11-02 | **EV-0204 (`PARTIAL`): device-checklist FAIL release gate** — `m6_check_device_checklist.sh` consumes imported checklist status: missing SKIP, FAIL exit1, incomplete exit2, all-PASS exit0; release-ready fails on FAIL and notes incomplete. Host fixtures pass; fixture-generated export artifacts removed; release-ready correctly SKIPs while device acceptance NOT RUN. Next ID `EV-0205`. || 2026-11-02 | **EV-0206 (`PARTIAL`): verified JRE-pruned lite package measurement** — experimental lite staging (`VRMC_KEEP_JRE=25`) verified: app 245,747,712 bytes/72 Mach-O, deep/strict codesign PASS; clean measurement package bytes=89,919,699 sha256 `db3f6a4829cc1f606f34bde8463279b375777891cc7f6d3eda34f3070c5f27ad`, verifier PASS. Canonical installed app/package/metadata unchanged; device launch/JRE selection NOT RUN. Next ID `EV-0207`. || 2026-11-02 | **EV-0207 (`PARTIAL`): read-only device JRE probe** — device external `java_runtimes` empty; selected `fabric-loader-0.20.1-26.2`; pulled crash log shows OpenJDK 25.0.4 loaded from app-bundled `java_runtimes/java-25-openjdk`; launcher prefs map internal 8/17/21/25. Supports keeping only java-25 in the lite variant, but a real lite launch remains NOT RUN; canonical app/package unchanged. Next ID `EV-0208`. || 2026-11-02 | **EV-0208 (`PARTIAL`): lite JRE binary reference analysis** — launcher resolves `java_runtimes/java-%@-openjdk` dynamically and has no hardcoded java-8/17/21 directory refs; combined with EV-0207 (selected fabric 26.2 uses bundled java-25, external dir empty), pruning old JREs is very likely safe. Lite launch remains NOT RUN; lite app still experimental/uninstalled. Next ID `EV-0209`. || 2026-11-02 | **EV-0209 (`DEVICE BUG FIX`): VR init IllegalFormatConversionException** — device error at `VisionVR.init:262` caused by `%.0f` formatting `swipeCooldownMillis()` (long). Moved startup locomotion log to host-tested `VisionLogFormat.locomotionLine` with type-correct formatting; m4-log-format 6 checks; full provider suite ALL PASS; provider `5fe2a842…` (100,378 bytes) pushed + device integrity PASS. Game must be relaunched to confirm VR init. Next ID `EV-0210`. || 2026-11-02 | **EV-0210 (`DEVICE BUG FIX #2`): init-time status write NPE** — EV-0209 format fix was confirmed installed and advanced init; next device crash was `NullPointerException` in `ClimbTracker.isActive/isClimbeyClimb` from `VisionVR.writeStatusReport`, called during `VisionVR.init` before `dh.vrPlayer` existed. Removed the init-time status write (auto write now occurs on first update) and guarded bow/climb fields with `dh.vrPlayer != null`. Full provider suite ALL PASS; provider `adeca91c…` (100,374 bytes) pushed + device integrity PASS; game relaunch required. Next ID `EV-0211`. || 2026-11-02 | **EV-0211 (`DEVICE BUG FIX #3`): first auto-status write NPE with null player** — device logs confirm `VisionVR.init()` and core setup now succeed; first poll auto-status crashed because `ClimbTracker.isClimbeyClimb` dereferences `mc.player` when the player isn't loaded yet. Added `mc.player != null` guard for that field. Full provider suite ALL PASS; provider `e9f97a60…` (100,383 bytes) pushed + device integrity PASS; relaunch required. Next ID `EV-0212`. || 2026-11-02 | **EV-0212 (`PARTIAL DEVICE PASS`): first successful played session** — operator launched and played for a while; logs show init/renderer/hands/input/display views OK, no Unreported exceptions, 12,199 compositor frames (flat, eyes=1, anchor=1), p50 8.34 ms/p95 9.24 ms, clean `destroy-complete` with no teardown exception, thermal nominal. Full H1–H10/AC/K checklist still NOT recorded; pull script fixed to include `Documents/latestlog.txt` + checklist/calibration. Next ID `EV-0213`. || 2026-11-02 | **EV-0213 (`PARTIAL`): accepted MENU_RIGHT_PINCH dataset** — operator recorded 31.23 s/563 samples in Gesture Lab but the label picker stayed IDLE; canonical dataset relabelled MENU_RIGHT_PINCH (`sourceLabel=IDLE`). Right hand tracked 563/563; pinch p05/p50/p95=0.006/0.083/0.148 m; 112 frames <0.030 m; 42 pinch events (0.030 on/0.045 off); classifier independently saw RIGHT_PINCH. Raw JSONL local/gitignored; summary/analysis tracked. Device A/B still pending. Next ID `EV-0214`. |
| 2026-11-02 | **EV-0214 (`PARTIAL`): Gesture Lab data-quality fixes** — first left-fist recording exposed two lab bugs: samples were produced only on right-hand anchor updates (31 s wall recording → 18.15 s data with an 11.5 s gap) and the fist ratio exceeded 1 when the fist shortened the palm (live `isFist` never fired). Fixed to write on either hand update, and to use mean(tip→knuckle / wrist→knuckle) with <0.55 fist threshold; analyzer re-derives from recorded joints. App rebuilt/installed; ESCAPE_LEFT_FIST must be re-recorded. Next ID `EV-0215`. || 2026-11-02 | **EV-0215 (`PARTIAL`): accepted ESCAPE_LEFT_FIST dataset** — operator's 31.18 s/561-sample recording stayed labelled MENU_RIGHT_PINCH but contains only left-fist taps: left hand 561/561 tracked, left fist curl p05/p50/p95 0.298/0.905/0.983, 146 frames <0.55, 24 left-fist events 0.22–0.67 s, right fist 0. Canonical copy relabelled `ESCAPE_LEFT_FIST` (`sourceLabel=MENU_RIGHT_PINCH`). Lab UI now shows CURRENT ACTION prominently and the record button includes the label; Record 60s added. Raw JSONL local/gitignored; device A/B pending. Next ID `EV-0216`. || 2026-11-02 | **EV-0216 (`PARTIAL`): accepted WALK_BOTH_FISTS dataset** — 30.97 s/558 samples; both fists 420/558; fist p50 L/R 0.359/0.348; relative-to-head wrist z range 0.788/0.645 m, z correlation −0.73 (opposite phase), ~25 cycles at ~0.8 Hz; head tracked 558/558 (x/y/z ranges 0.279/0.150/1.969 m, full transform recorded). Source stayed labelled MENU_RIGHT_PINCH; canonical relabel WALK_BOTH_FISTS. Lab default changed to JUMP_HEAD for the next capture. Next ID `EV-0217`. || 2026-11-02 | **EV-0217 (`PARTIAL`): accepted JUMP_HEAD dataset** — 80.03 s/923 samples, head 923/923 tracked; 29 adaptive-baseline head-rise events >0.08 m with peaks 0.11–0.30 m and durations mostly 0.27–0.95 s; upward velocity p95 1.51 m/s, max 2.36. Starting jump detector: baseline EMA, 0.08 m rise + 0.25 m/s upward, 300 ms release. Lab default changed to SNEAK_HEAD. Next ID `EV-0218`. || 2026-11-02 | **EV-0218 (`PARTIAL`): accepted SNEAK_HEAD dataset** — 31.00 s/524 samples, head 524/524 tracked; 5 downward excursions >0.10 m (depths 0.10–0.25 m; two ~4.9 s holds plus 0.33/2.56/1.33 s); max head speed 1.66 m/s. Starting detector: baseline EMA, >0.10 m drop sustained 350 ms, release within 0.05 m for 250 ms. Dataset over-represents held crouch; a second sneak pass can add transitions. Lab default changed to TELEPORT_LEFT_PINCH. Next ID `EV-0219`. || 2026-11-02 | **EV-0219 (`PARTIAL`): accepted TELEPORT_LEFT_PINCH datasets** — two samples 31.09 s/551 and 38.97 s/703; left tracked 484/629; 214/336 frames <0.030 m; **16 left-pinch events** (0.030 on/0.045 off) ranging from 0.05 s taps to 4.56 s aimed holds. Analyzer extended with left-pinch stats/events. Teleport mapping: pinch press begins aim, release commits; open hand/tracking loss cancels. Lab default changed to ATTACK_RIGHT_SWING. Next ID `EV-0220`. || 2026-11-02 | **EV-0220 (`PARTIAL`): accepted ATTACK_RIGHT_SWING dataset** — 31.41 s/520 samples; right hand 503 tracked, left 25 (one-handed); right wrist speed p50/p95/max 1.30/2.97/4.75 m/s; acceleration p50/p95/max 5.85/21.39/50.61 m/s²; 228 frames >1.4 m/s, 186 >8 m/s², ~28 swing events. Starting detector: right speed >1.4 m/s or acceleration >8 m/s², one-handed, not both-fist/GUI/bow/eat/climb. Lab default changed to EAT_RIGHT_HAND_HEAD. Next ID `EV-0221`. || 2026-11-02 | **EV-0221 (`PARTIAL`): accepted EAT_RIGHT_HAND_HEAD dataset** — 30.85 s/455 samples; right 386 tracked, head 455; right-wrist→head p05/p50/p95 0.218/0.283/0.734 m; 181 frames <0.28 m; 11 near-head events 0.22–6.04 s. Starting detector ~0.28 m with 250 ms latch, edible/drinkable context, stop >0.35 m. Lab default changed to BOW_BOTH_FISTS. Next ID `EV-0222`. || 2026-11-02 | **EV-0222 (`PARTIAL`): accepted BOW_BOTH_FISTS dataset** — 46.66 s/819 samples; left/right 695/758 tracked; wrist separation min/p05/p50/p95/max 0.156/0.224/0.502/0.727/1.049 m; 16 draw/release cycles >0.55 m; left fist p50 0.349, right p50 0.479/p95 0.983. Starting detector: both fists + separation >0.55 m, release on back-hand open, suppress walk. Lab default changed to PLACE_RIGHT_PINCH. Next ID `EV-0223`. || 2026-11-02 | **EV-0223 (`PARTIAL`): accepted PLACE_RIGHT_PINCH short-pinch dataset** — 59.19 s/1062 samples; right hand 1055 tracked; 76 pinch events (0.030 on/0.045 off), **72 short <0.35 s** (mostly 0.11–0.22 s) plus 4 long holds (4.06/3.39/0.63/0.61 s) excluded from the place threshold fit. Under the updated rule short = place/select, held = break. Lab default changed to BREAK_RIGHT_PINCH_HOLD. Next ID `EV-0224`. || 2026-11-02 | **EV-0224 (`PARTIAL`): accepted BREAK_RIGHT_PINCH_HOLD dataset** — 31.11 s/588 samples; right hand 588/588 tracked; 470 frames <0.03 m; 7 held-pinch events 1.21/2.24/1.49/1.98/4.33/3.36/10.44 s, no short taps. Split validated: <0.35 s place/select, ≥0.35 s break/mine; the 10.44 s hold gives long-hold stability and can be clamped. Lab default changed to INVENTORY_BOTH_FISTS. Next ID `EV-0225`. || 2026-11-02 | **EV-0225 (`PARTIAL`): accepted INVENTORY_BOTH_FISTS dataset** — 31.14 s/562 samples; both hands 562/562 tracked; 24 both-fist short runs 0.06–0.28 s with matching left/right runs; 75 closed frames; hand separation 0.264–0.436 m. Rule: both fists close together <0.35 s without sustained alternating arm swing → inventory. Lab default changed to HOTBAR_RIGHT_TAP. Next ID `EV-0226`. || 2026-11-02 | **EV-0226 (`PARTIAL`): accepted HOTBAR_RIGHT_TAP dataset** — 30.94 s/558 samples; right hand 558 tracked; tap is a **finger tap**, not a wrist flick (wrist max 0.65 m/s; right index-tip speed p95/p99 1.28/2.66 m/s, acceleration p95 20.8, max 62.6); 22 index-finger tap events 0.05–0.22 s. Rule: quick right index-fingertip tap selects the next hotbar slot, double tap cycles back; suppress during walk/bow/GUI. Lab default changed to CLIMB_ALTERNATE for the last missing dataset. Next ID `EV-0227`. || 2026-11-02 | **EV-0227 (`PARTIAL`): CLIMB_ALTERNATE accepted; all 14 gesture datasets collected** — 31.09 s/561 samples; left/right 526/534 tracked; fist p50 0.425/0.394; hand-height ranges 0.689/0.749 m; left−right height zero crossings 31 (~15 alternations). Accepted datasets now cover MENU, ESCAPE, WALK, JUMP, SNEAK, TELEPORT, ATTACK, EAT, BOW, PLACE, BREAK, INVENTORY, HOTBAR, CLIMB. Next: implement the production M7 engine behind a mode switch with host invariant/fuzz tests, then device A/B. Next ID `EV-0228`. |
| 2026-11-02 | **EV-0228 (`PARTIAL`): M7 production engine implemented** — pure-Java `VisionM7Gesture` + VisionVR dispatch/locomotion branch; default `gesture.mode=m7`, fallback `m4`. Host suite ALL PASS, m7-gesture 23 synthetic checks; provider `367aa78a…` (108,325 bytes) pushed + device integrity PASS. Device A/B NOT RUN; GUI eye-hover/drag and climb context remain gaps; release metadata stale. Next ID `EV-0229`. |
| 2026-11-02 | **EV-0229 (`PARTIAL`): M7 pre-A/B review** — published 40 named synthetic checks (original 23 + adjacent-priority/boundary), all PASS; found/fixed bow/climb previous-state ordering bugs; documented GUI click-only/no reticle/no drag, climb heuristic, seated snap-turn check, SNEAK transition backlog, and release-metadata deferral. Rollback tune `gesture.mode=m4` pushed/read back; provider `1c75ae86…` pushed/integrity PASS. **Device A/B NOT RUN**; step 0 rollback playability is next. Next ID `EV-0230`. |
| 2026-11-02 | **EV-0230 (`PARTIAL`): rollback session was M4, not M7** — latestlog confirms `[VRMC-M7] gesture mode=m4`; operator feedback (hand-tracking dropouts, poor movement, accidental inventory/menu) applies to the M4 fallback. M4 launched/ran with actions and no provider exception; rollback switch works but usability is caveated. Tune switched to `gesture.mode=m7` and read back; provider `1c75ae86…` integrity PASS. **M7 device A/B NOT RUN.** Next ID `EV-0231`. |
| 2026-11-02 | **EV-0231 (`PARTIAL`): M7 immersive blocked by crash safe mode** — latestlog confirms `[VRMC-M7] gesture mode=m7` and `VisionVR.init() succeeded`, but shell crash guard count=2 enabled safe mode and suppressed automatic VR open; immersive never opened. Crash count reset to 0; app restart required. M7 behavior remains NOT RUN. Next ID `EV-0232`. |
| 2026-11-02 | **EV-0232 (`PARTIAL`): M7 first real session** — immersive opened with `[VRMC-M7] gesture mode=m7`; action log shows 8 right-pinch GUI clicks, 1 left-fist `ingameMenuButton` press, 1 attack press/release; no inventory/hotbar/walk/teleport/bow/eat/climb transitions. Three right-hand untracked episodes; clean `destroy-complete`; p95 40 ms during startup/world load. Step 1 menu/escape observed; operator qualitative score still needed. Next ID `EV-0233`. |
| 2026-11-02 | **EV-0233 (`PARTIAL`): M7 launch/clean-quit only** — operator clarifies no M7 actions were deliberately tested; only immersive open and clean quit. Incidental action transitions in EV-0232 are **not** step-1 evidence. M7 action A/B remains NOT RUN. Next ID `EV-0234`. |
| 2026-11-02 | **EV-0234 (`PARTIAL`): M7 GUI cursor + tap forgiveness** — operator reported menu/inventory frequently miss. Added M7 head-ray cursor projection onto the GUI plane (right-pinch click follows head aim; raw eye hover still unavailable), loosened fist curl 0.55→0.65 and tap window 350→450 ms, M7 status summary in JSON. Host suite ALL PASS (40 checks); provider `c69ccd3b…` (108,690 bytes) pushed/integrity PASS. Device retest required; hand-tracking dropouts remain. Next ID `EV-0235`. |
| 2026-11-02 | **EV-0235 (`DEVICE CRASH FIX`): M7 GUI cursor NoSuchMethodError** — launch crashed at `VisionVR.updateM7GuiCursor` because `WindowExtension.vivecraft$getActualWindowSize()` exists at compile time but not in the runtime Vivecraft build. Removed the call (direct window scaling), wrapped GUI cursor in try/catch, fixed the same latent call in the gaze path. Provider `3a3bf56e…` (108,623 bytes) pushed/integrity PASS; device retest required. Next ID `EV-0236`. |
| 2026-11-02 | **EV-0236 (`PARTIAL`): M7 false-trigger fixes** — feedback: inventory opens once then menu/glitch; pinch too sensitive. Added pinch debounce 40 ms + 100 ms arming (0.025 on/0.050 off), GUI left-fist now calls `Screen.onClose()` with pause suppression, menu suppressed around both-fist/inventory, hotbar suppressed after both-fist/inventory/menu. Head-ray cursor retained + logged. 44 checks PASS; provider `b77897dd…` (109,829 bytes) pushed/integrity PASS. Device retest required. Next ID `EV-0237`. |
| 2026-11-03 | **EV-0237 (`PARTIAL`, host): M7 data-driven gesture accuracy iteration + replay gate** — all 14 accepted Gesture Lab datasets (~9.5k samples) analysed by two independent scripts/reports (HANDS: pinch/fist/attack/hotbar/eat/bow/climb/walk/menu/inventory/teleport; HEAD: jump/sneak/head-frame/pitch/negatives; the top-level IDLE recording is the MENU twin — there is no true idle capture). Re-fitted `VisionM7Gesture`: pinch/fist Schmitt hysteresis, head-frame geometry, windowed speeds, dt-corrected head baseline + adapt band, press/peak gates, hotbar delayed single-vs-double decision, item context (bow, food/drink) and Vivecraft climb context via fail-safe probes (`m7.context=auto|off`). Added replay tooling: `scripts/m7_lab_fixture.py`, `M7LabReplay.java`, independent `scripts/m7_eval_replay.py` evaluator with per-action recall/precision/coverage/false gates, one-command `scripts/m7_lab_replay.sh`. Host: full provider suite ALL PASS including **m7-gesture 73 synthetic checks** and **m7-fuzz 200k frames / 0 violations**; literal replay gate **20/24 rows** and evaluator-v2 **primary gate 22/24 rows** (rate-matched 90 Hz pulse GT + bounded-latency-aware held scoring; baseline 12/24; context suppression 9/9). Residual literal rows: hotbar precision 0.83 vs 0.85, attack precision 0.66 vs 0.80, walk false-active 0.18 vs 0.10, eat false-active 0.25 vs 0.15; residual primary rows: hotbar recall 0.75 and attack recall 0.77/precision 0.71 — all root-caused in `M7_ACCURACY_ITERATION.md`; no threshold was loosened to hide them. Provider jar `d2c8a8d9…` (120,666 bytes), two-build reproducible. **Device A/B NOT RUN**: the installed D1 provider remains EV-0236 and no device behaviour is claimed for this engine revision. Next ID `EV-0238`. |
| 2026-11-03 | **EV-0238 (`PARTIAL`, device push): EV-0237 provider installed on D1** — pushed `d2c8a8d9…` (120,666 B) to `Documents/instances/default/mods/vrmc-provider.jar`; devicectl round-trip sha256 PASS and read-only device integrity PASS. Read-back before the push showed the actually-installed jar was `cf3ef0a0…` (110,857 B; a previous unrecorded post-EV-0236 push), correcting the earlier "installed remains EV-0236" claim. App relaunch for the operator A/B was **NOT RUN**: `devicectl device process launch` failed twice with "Failed to allocate RSD device" and the running game process is from the earlier session. Gesture A/B remains NOT RUN (operator required); rollback `gesture.mode=m4` unchanged. Next ID `EV-0239`. |
| 2026-11-04 | **EV-0239 (`PARTIAL`, host+device-push): M7 GUI cursor centre-on-open + diagnostics** — operator feedback: GUI cursor appears in the top-left of the view, not the middle. Device log analysis: the cursor is only positioned after a successful head-ray/GUI-plane intersection, so until then the mouse handler keeps its top-left default. Fix: centre the cursor when a GUI screen opens, keep it centred while the head ray misses (a valid hit is never overwritten), and log a rate-limited cursor diag (uv/mouse/read-back/window/framebuffer/GUI sizes/plane/head/dir). Provider suite ALL PASS; `fdce66d4…`/121,326 B two-build identical; pushed to D1 and integrity PASS. **Device visual retest NOT RUN** (app relaunch is operator-side); diagnostics will make the next session's cursor mapping verifiable. Next ID `EV-0240`. |
| 2026-11-04 | **EV-0240 (`PARTIAL`, device state): "game did not enter immersive" = shell crash-guard safe mode** — after the EV-0239 relaunch the app stayed in its flat window. Device logs (vrmc-shell.log) show the shell crash guard counted two consecutive unclean VR-session shutdowns from the push/restart cycles ("CRASH-GUARD ... count=2", "safe mode enabled ... automatic VR open suppressed", then SAFE MODE at VRMCGameStarted); latestlog shows displayViews=0/flat title screen. This is shell safe-mode behaviour, not a provider/M7 defect: manual Enter VR is intentionally allowed. Reset `Documents/vrmc-crash-count.txt` to 0 on D1 (read-back 0) so the next launch auto-opens again; the already-running shell needs the operator to tap Enter VR / Clear crash safe mode for this session. Quit the game via its menu (so the provider writes `destroy-complete`) instead of force-quitting. No provider change; jar remains `fdce66d4…`. Next ID `EV-0241`. |
| 2026-11-04 | **EV-0241 (`PARTIAL`, device state): immersive still closed — crash-guard double-start mechanism** — after the EV-0240 reset the app started its shell twice within 26 s (22:23:35 and 22:24:01 HST; `vrmc-shell.prev.log` + `vrmc-shell.log`). The crash guard evaluates once per shell launch against the last (unclean, `event=init`) shutdown.log line, so the count went 0→1 (safe mode off) then 1→2 (safe mode on → automatic VR open suppressed again). Not a provider/M7 fault and not operator error. Crash counter reset to 0 again (read-back 0): a single launch allows the automatic open; the robust recovery is a clean game shutdown via Minecraft's own **Quit Game** menu (writes `destroy-complete`, permanently resets the counter) or the in-session **Clear crash safe mode / Enter VR** overlay controls. Candidate permanent fix (not implemented): shell-side debounce of crash-guard increments across rapid starts of the same app session — needs an app rebuild. Jar unchanged (`fdce66d4…`). Next ID `EV-0242`. |
| 2026-11-04 | **EV-0243 (`PARTIAL`, host+device-push): VR-state-aware cursor calibration** — EV-0242's one-time probe could measure scale 1.0 while the game was still in its flat window (`VR_RUNNING=false`; the runtime onMove scale only applies in VR), and the window does not resize when the immersive space opens, so the stale calibration would persist into VR and the half-position cursor bug would remain. Calibration now keys on `VRState.VR_RUNNING` (re-probe on flat↔VR and window-size changes), clears the valid-uv latch so the cursor re-centres with the new scale, and logs `vr=` in the cursor diag. Suite ALL PASS; `4c917439…`/122,089 B two-build identical; pushed/integrity PASS; crash-count headroom `-3` on D1. **Device visual retest NOT RUN** (one operator relaunch). Next ID `EV-0244`. |
| 2026-11-05 | **EV-0246 (`PARTIAL`, host+device-push): M7 direct touch-hotbar selection** — operator clarified that "tap on the inventory bar to select" means tapping the rendered HUD hotbar itself, not cycling with air index taps. Implemented provider-side touch selection mirroring the installed `InteractiveHotbarModule` bar geometry (`GUI_RENDER_POS_ROOM/ROTATION_ROOM`, `GUI_OFFSET_LOCAL`, `GUI_SCALE_APPLIED/MAX`): right index fingertip within 6 cm of the bar, same slot dwelled ≥60 ms with <3 cm drift, 300 ms cooldown → `Inventory.setSelectedSlot` (reflective access; jspecify @Nullable absent from the compile classpath). Guarded off in GUI/seated/HEAD-HUD/untracked/stale; air index-tap cycling kept as fallback. Installed Vivecraft 26.2-1.3.15 bytecode audited for every field/method used. Suite ALL PASS; `747ed2ab…`/124,561 B two-build identical; pushed/integrity PASS; crash headroom -3. **Device tap test NOT RUN.** Next ID `EV-0247`. |
| 2026-11-05 | **EV-0247 (`PARTIAL`, host+device-push): fail-safe wrapper around the direct touch-hotbar path** — EV-0246's `updateM7TouchHotbar()` runs on the render thread from `VisionVR.poll()`; all its reads are guarded but a Throwable must never crash the frame (EV-0235 lesson), so the call is now wrapped in try/catch with a bounded WARN log. Behaviour/geometry/diagnostics unchanged; air index-tap cycling remains the fallback. Suite ALL PASS; final jar `0ee811fd…`/124,629 B two-build identical; pushed/integrity PASS; crash headroom -3. **Device tap test NOT RUN.** Next ID `EV-0248`. |
| 2026-11-05 | **EV-0248 (`PARTIAL`, host+device-push): M7 movement = left-thumb virtual stick** — operator requested movement controlled by the left thumb. Removed the both-fist alternating-swing walk dispatch; movement is now the **left thumb-middle pinch hold + move the left hand like a joystick** (forward/back = walk, left/right = strafe) via `VisionLocomotion` with the shared `move.originZ/forwardScale/strafeScale/deadzone` tunables, written to Vivecraft's `keyFreeMoveStrafe` analog action. The engine's both-fist walk detector is retained only as an internal context/suppression signal and its replay-gate rows remain engine tests. Zeroed in GUI/seated/keyboard/stale input and on `releaseM7Actions`/`releaseAllImmediately` (no stuck movement); diagnostics `[VRMC-M7] thumb stick engaged/released …`. The thumb-middle pinch is disjoint from every M7 action (thumb-index = place/break/attack/GUI, left hold = teleport). Suite ALL PASS; `37262f9c…`/124,958 B two-build identical; pushed/integrity PASS; crash headroom -2. **Device movement test NOT RUN.** Next ID `EV-0249`. |
| 2026-11-05 | **EV-0249 (`PARTIAL`, host+device-push): left-pinch movement, right-pinch LMB hold, cursor down** — movement changed to left thumb-index pinch hold + move left hand (teleport suppressed while moving); GUI right pinch now holds LMB down for long press/drag and releases on pinch end; head-ray cursor offset 8% down. Suite ALL PASS (73 checks); provider `a337481f…`/125,116 B pushed/integrity PASS. **Device retest NOT RUN.** Next ID `EV-0250`. |
| 2026-11-05 | **EV-0250 (`PARTIAL`, host+device-push): player-relative movement** — movement projected wrist-minus-head onto the HMD horizontal forward/right basis before deadzone/scale, so forward is relative to the player not world Z. Added `VisionLocomotion.axesRelative` + 3 checks (locomotion 12 total); suite ALL PASS; provider `85d18f61…`/125,525 B pushed/integrity PASS. **Device movement retest NOT RUN.** Next ID `EV-0251`. |
| 2026-11-05 | **EV-0251 (`PARTIAL`, host+device-push): movement fix after device failure** — logs showed left pinch emitting analog stick values **and** repeated `key.teleport` presses; teleport was still mapped to the same pinch and can override free move. Also a hand naturally left/right of the head produced constant strafe. Fixes: capture neutral along/right origin at pinch engage, use deltas; correct right-basis sign; disable teleport on the movement pinch (dedicated gesture TODO). Suite ALL PASS; provider `90a724fc…`/125,614 B pushed/integrity PASS. **Device movement retest NOT RUN.** Next ID `EV-0252`. |
| 2026-11-05 | **EV-0252 (`PARTIAL`, host+device-push): movement diagnostics** — after the player-relative/neutral-origin/teleport-conflict fixes, the pinch-stick log now includes delta along/right, HMD forward, analog data, active/enabled flags. Provider `d7f45be7…`/125,791 B pushed/integrity PASS; suite ALL PASS. **Device movement retest NOT RUN.** Next ID `EV-0253`. |
| 2026-11-05 | **EV-0253 (`DEVICE PASS`): M7 movement** — operator confirms movement passes after EV-0251/0252. Logs show `pinch stick(player-relative)` engaged with active analog data, forward/strafe response, **no key.teleport transitions**; clean `destroy-complete`, crash count 0, p50 8.26 ms/p95 9.26 ms, missed90=0. Known warning: item-context probe unavailable (`ItemStack.is(Item)` missing), bow/eat item context off/geometry fallback. Next: remaining M7 actions + M5/M6 device gates. Next ID `EV-0254`. |
| 2026-11-05 | **EV-0254 (`PARTIAL`, host+device-push): one-pinch context + hotbar gating** — right pinch now places when a block item is held and the crosshair is on a block; otherwise it attacks/breaks (hold continues; creative instant break). Old short-place/held-break conflict removed. Item context probe rewritten without runtime-missing `ItemStack.is(Item)`; pinch debounce 30→20 ms/arm 80→60 ms; touch/air hotbar suppressed during and 500 ms after right actions. Suite ALL PASS; provider `475b7dda…`/126,314 B pushed/integrity PASS. **Device retest pending.** Next ID `EV-0255`. |
| 2026-11-05 | **EV-0255 (`PARTIAL`, host+device-push): short-pinch attack/place/use, hold break** — short right pinch attacks when crosshair is on an entity, otherwise places/uses; hold >=350 ms breaks/mines; short pinch never breaks a block. Hotbar touch/air suppressed during/after actions; item-context probe fixed; pinch debounce 20 ms/arm 60 ms. Suite ALL PASS; provider `683efdd3…`/126,922 B pushed/integrity PASS. **Device retest pending.** Next ID `EV-0256`. |
| 2026-11-05 | **EV-0256 (`DEVICE PASS`): M7 short-pinch attack/place/use + hold-break** — operator says all pass for short entity attack / block-place-use, hold break, hotbar stability and inventory pick/place. Logs: 28 use, 15 attack, 6 menu, 8 jump, 2 hotbarNext, 1 inventory; clean `destroy-complete`, p50 8.34 ms/p95 9.27 ms, missed90=1; no exceptions. Teleport unbound; bow/eat/climb/M5/M6 pending. Next ID `EV-0257`. |
| 2026-11-05 | **EV-0257 (`DEVICE PASS`): M7 scope close** — operator: no teleport; all other M7 actions pass (menu/GUI, movement, inventory, short-pinch attack/place/use, hold-break, hotbar, jump/sneak, bow, eat, climb). Teleport removed from scope. Latest log clean (`destroy-complete`, no exceptions), diag p50 8.34 ms/p95 9.15–9.27 ms, missed90 0–1. Remaining: M5/M6 gates and hand-tracking dropouts. Next ID `EV-0258`. |
| 2026-11-05 | **EV-0258 (`PASS`, operator-attested): M5 acceptance** — operator states M5 launcher/settings/immersive/comfort/save-reload/diagnostics loop was tested previously and waived a fresh current-build run. Recorded as operator-attested PASS (not a new device run); M5 matrix/docs updated to current M7 mapping with teleport descoped. Latest EV-0257 logs corroborate clean session. **M6 AC/K remain NOT RUN.** Next ID `EV-0259`. |
| 2026-11-05 | **EV-0259 (`PARTIAL`): 10-min soak attempt not a clean pass; harness false positive fixed** — monitor reported PASS but shutdown journal had multiple `init` events and no `destroy-complete`; game JVM relaunched ~19:32/19:34/19:36 and immersive ended at 19:30:46 with CreativeModeInventoryScreen open. No new crash report/hs_err; cause unproven. Harness now snapshots the journal baseline and requires exactly one init + final `destroy-complete`. **AC-5/K4 NOT passed; one continuous run or root-cause needed.** Next ID `EV-0260`. |
| 2026-11-05 | **EV-0260 (`PASS`, operator waiver): reduced 10-min soak accepted** — operator accepted 10-minute soak as sufficient and confirmed repeated relaunches were not defects. AC-5/K4 marked PASS under explicit reduced-duration/relaunch waiver; harness now enforces fresh one-init/final-destroy for future runs. Next ID `EV-0261`. |
| 2026-11-05 | **EV-0261 (`PARTIAL`): bow open-hand draw + menu-hand alignment** — bow draw no longer requires both fists when a bow is held; both tracked hands held apart draw, fist-started draws still fire on fist release, open-hand draws fire by bringing hands together. Menu-hand controller pose shifted local -0.18 m while GUI open so Vivecraft's +Z gray box covers the hand. Suite ALL PASS (m7-gesture 74 checks); provider `fac54efa…`/127,015 B pushed/integrity PASS. **Device retest pending.** Next ID `EV-0262`. |
| 2026-11-05 | **EV-0262 (`PARTIAL`): bow perpendicular to hand** — 90° roll around local forward for the bow-holding hand; `VisionM7ItemContext` now reports main/off bow mask. Suite ALL PASS (m7 74 checks); provider `4e92b306…`/127,258 B pushed/integrity PASS. **Device visual retest pending**; flip to -90 if axis is wrong. Next ID `EV-0263`. |
| 2026-11-05 | **EV-0263 (`PARTIAL`): bow visual orientation accepted known bug** — 90° local-forward roll did not fix the bow lying parallel to the hand. Bow draw/fire works; operator says leave as a bug and continue. Non-blocking known issue; follow-up needs an item-only/model transform. Next ID `EV-0264`. |
| 2026-11-05 | **EV-0264 (`PARTIAL`): AC-1 cold reinstall complete** — uninstalled/reinstalled D1 app; cold install 23.66 s, app data container empty. K6 PASS; AC-6 operator sign-off + host legal checks PASS. AC-1 first-run/JIT/create-world still pending. Next ID `EV-0265`. |
| 2026-11-05 | **EV-0265 (`DEVICE PASS`): AC-1 fresh install → world** — clean uninstall/reinstall (23.66 s), empty app data; operator restored Vivecraft 26.2-1.3.15 + provider into fresh instance, launched with JIT, entered immersive and played a world. 21 mods loaded, clean `destroy-complete`, no exceptions, p50 8.34 ms/p95 9.21 ms missed90=0. Caveat: manual mod restore required; launcher auto-provisioning is a known gap. Acceptance 22/22. Next ID `EV-0266`. |
| 2026-11-05 | **EV-0266 (`PASS`): RELEASE READY development package** — rebuilt clean package with current app/provider; package verifier and freshness PASS; `m6_release_ready.sh --zip /tmp/VRMC-dev-release.zip` => **RELEASE READY**, 22/22 acceptance rows. zip bytes=206,567,700 sha256=`0fa384d9…`; app `a4663e16…`, provider `4e92b306…`. Caveats: K3 latency rig waived; AC-1 required manual Vivecraft/provider restore; bow visual known bug EV-0263. Next ID `EV-0267`. |
| 2026-11-05 | **EV-0267 (`PASS`): device app cleaned for handoff** — app uninstalled/reinstalled; `Documents` and `tmp` empty (0 files); only system `Library/Caches`+`Preferences`. Test worlds/accounts/mods/provider/logs/crash/config removed. Release package and repo evidence unaffected. Next ID `EV-0268`. |
| 2026-11-05 | **EV-0268 (`PARTIAL`, host+simulator): M8 foveated 4K/120 rendering pipeline** — root cause of the operator "resolution too low + jaggedness" report: fixed 1024x1024 provider eye target upscaled ~1.84x into the 1888x1792 per-eye drawable, foveation off, default render quality. Implemented M8: shell requests CompositorServices foveation when supported and sets maxRenderQuality=1.0 when the layer reports a usable default quality (guarded fallback for runtimes with NaN/unsupported quality, which otherwise abort CompositorLayer creation); compositor logs rate maps/geometry/measured display cadence and publishes a new 68-byte `vrmc_render_settings` native-shared payload; provider sizes stereo eye targets from the display logical size with adaptive eyeScale (auto default; game-dir/JVM knob) and resizes via `reinitFrameBuffers` with hysteresis. Host/sim ALL PASS: bridge suite ALL PASS (static layout asserts, 20k-publish concurrency + TSan, 44 exported symbols); provider suite ALL PASS (m8-render 43 checks, m8-frame-stats 13 checks, jar builds; provider jar `4db9d202…`/134,537 B, two-build reproducible); simulator render scenario PASS (34 feedback publications, logical 3840x2160 mono, sampled pattern/depth/parking PASS; simulator has no foveation/dynamic quality and runs 60 Hz). **Device D1 A6-A9 NOT RUN (D1 unavailable)**: foveation/rate maps, max-quality logical per-eye size, provider resizes and the measured displayHz≈120 claim require the headset; no public CompositorServices refresh-rate selector exists (minimumFrameRepeatCount=0 + measured cadence). Engine-side foveation deferred (MoltenVK 1.4.3 lacks VK_KHR_fragment_shading_rate). Next ID `EV-0269`. |
| 2026-11-05 | **EV-0269 (`PARTIAL`, host+simulator): M8 round 2 — resize-safe eye targets, cadence-aware pacing diagnostics, device-verification tooling** — Provider: eye-target resizes are gated to a stable state (menu room, or in-world with the level stable >=120 frames; >=60-frame warm-up; one resize per 240 frames) so the full render-target rebuild never lands in world loading; the auto eye-scale takes 0.10 steps under strong headroom (reaches the native logical size sooner); frame stats now track `missed90` and `missedTarget` (measured cadence) separately, and the periodic diag/render-state lines report `targetHz/displayHz/missedTarget/foveation/rateMaps/logical/eyeTarget/scale/resizes`. Device tooling: `scripts/m8_device_check.sh` (+python analyser) classifies A6-A9 from pulled logs (exit 0 PASS / 2 PARTIAL / 3 NOT RUN / 4 FAIL / 5 device unavailable); `docs/mvp/M8_DEVICE_RUN.md` operator runbook; host test `scripts/tests/M8DeviceCheckTest.sh` covers the four outcomes. Host/sim ALL PASS: provider suite ALL PASS (m8-render 49 checks, m8-frame-stats 13 checks; jar `cd80b753…` 136,067 B two-build reproducible); classifier test PASS (simulator pull -> PARTIAL with the expected 60 Hz/no-foveation rows; unavailable device -> NOT RUN exit 5); M3c fast self-check PASS; simulator suite flat/sync/hidepark/nopark/pattern/input/render PASS (render 50 feedback publications), reentry/gaze environment-limited as previously recorded, render harness log-copy race fixed. **Device A6-A9 still NOT RUN (D1 unavailable)**; no 4K-class/foveation/120 Hz device claim. Next ID `EV-0270`. |
| 2026-11-05 | **EV-0270 (`PASS`, host Metal): M8 foveation rendering-model probe** — `runtime/probes/m8-foveation/run.sh` renders the compositor's `vmain`+`fmain_flat` full-screen sampling math into a real macOS `MTLRasterizationRateMap` pass (rate map 0.5 periphery / 1.0 centre; screen 1920x1080 -> physical 1488x848 = 60.9% of screen pixels). Checks: rate-mapped pass encodes/completes; logical centre maps exactly to the pattern's white centre cross; logical upper-left quarter maps to the red quadrant (NDC->UV stays logical under variable rate); the negative control with a physical-size viewport corrupts the foveal centre (proves the screen-size viewport convention the compositor uses via `cp_view_texture_map_get_viewport`). 6/6 checks PASS; wired into `scripts/m3c_selfcheck.sh` (step 1c/7), whole fast self-check PASS. Cross-checked against Apple VRR docs, the public "Drawing Graphics on Apple Vision" article and Qt's visionOS qrhimetal rate-map viewport fix (M8_PLAN §8). **Host Metal only — NOT device/visionOS optics or eye-tracked foveation evidence; device A6-A9 still NOT RUN (D1 unavailable).** Next ID `EV-0271`. |
| 2026-11-05 | **EV-0271 (`PARTIAL`, host build/stage): M8 device-candidate app staged and verified; device install/run NOT RUN** — built the M8 device shell framework (xcodebuild generic/platform=visionOS BUILD SUCCEEDED) and the M8 device bridge dylib (44 exported symbols incl. `vrmc_shared_publish/acquire_render_settings` + JNI `nativePollRenderSettings`); staged a signed device-candidate app `/tmp/VRMC-native-m8.app` from the release Amethyst tree (tree sha256 `aea4bd4f…`, bundle `dev.vrmc.vrmc` 1.2.0, 169 Mach-O + 6 nested frameworks signed, `codesign --verify --deep --strict` PASS, profile provisions D1) and verified the M8 content via `nm`/`strings`. Matching M8 provider jar `cd80b753…`/136,067 B (two-build reproducible). Added `scripts/push_m8_render_config.sh` (offline self-test 15 checks PASS; `--print` devicectl preview PASS) and `export/m8-device-candidate.txt` (install/tuning/rollback manifest). Install attempt on D1: `CoreDeviceError 4016` (device unavailable) → **NOT RUN**; device A6–A9 still pending. Next ID `EV-0272`. |
| 2026-11-05 | **EV-0272 (`PASS`, host GL): M8 host Fabric harness — provider resizes eye targets from display feedback** — `scripts/m8_host_harness.sh` (docs `docs/mvp/M8_HOST_HARNESS.md`) runs the real M8 provider inside a real Minecraft 26.2 + Fabric + Vivecraft desktop client with a host test bridge dylib whose render-feedback publisher feeds fake 3660x3200 logical / 2412x2108 physical / foveation=1 / 120 Hz display geometry through the real native-shared channel. Result: provider init ABI 3; no-feedback path keeps 1024x1024; settings parsed; eye-target resize **1024x1024 -> 1832x1600** through Vivecraft `Reinit Render` (`VR Provider supplied texture resolution: 1832 x 1600`); auto scale then ramps 0.60 (2200x1928) and 0.70 (2568x2248) at the 240-frame cadence; 0 M8 exceptions. Reproducible script exit 0. Host desktop GL only (not visionOS Vulkan/MoltenVK), fabricated display feedback, menu room only — **device A6-A9 remain NOT RUN**. Next ID `EV-0273`. |
| 2026-11-05 | **EV-0273 (`PARTIAL`, host Metal + simulator): M8.6 foveated sharpening for sub-native 4K/120 rendering; rebuilt device candidate** — compositor CAS-lite 5-tap sharpening (`fmain_flat_sharp`/`flatSharp`) applied when provider eye texture < drawable logical view, fovea-weighted, anti-halo clamped, auto strength from upscale ratio (cap 0.45), live `Documents/vrmc-sharpening.txt` (auto/off/fixed), `sharpen=` in the cadence summary. Host Metal probe: 4x upscale edge acutance 0.0495 -> 0.0579 (**1.17x**), meanAbsDiff 0.0158 (bound 0.15), centreGain 1.27 vs cornerGain 1.00 (foveal taper), 10/10 checks. Simulator `render` scenario PASS with `foveated sharpening: auto strength=0.45 … upscale=3.75` + `sharpen=0.45` (47 publications; pattern/depth/parking PASS). Push script `--sharpening` self-test 21 checks; M3c fast self-check PASS; device candidate rebuilt and codesign deep/strict PASS (tree `53184ffe…`, framework `b1f48c2f…`, provider `cd80b753…`). **Device A6-A9 still NOT RUN (D1 unavailable)**; device visual/sharpening-halo judgement pending. Next ID `EV-0274`. |
| 2026-11-05 | **EV-0274 (`PARTIAL`, host/simulator): M8.6 sharpening knob A/B + one-command M8 device session tooling** — simulator render scenario gained `SHARPEN=<off|auto|0.05..1.0>` (writes `Documents/vrmc-sharpening.txt` before launch): `off` → 0 sharpening lines and `sharpen=0.00`; `0.30` → `foveated sharpening: fixed strength=0.30 …` and `sharpen=0.30`; both scenarios OVERALL PASS with pattern/depth/parking unchanged (auto path already EV-0273). New `scripts/m8_device_session.sh` one-command device session: `prepare` validates codesign + app-tree/provider hashes against the candidate manifest, installs app, pushes provider jar and prints the operator checklist; `collect` pulls + classifies A6–A9 (wraps `m8_device_check.sh`). Tested: dry-run validates candidate (`53184ffe…`/`cd80b753…`, codesign PASS) and prints commands; unavailable D1 → clear exit 5 after install retries; `--from` simulator pull → PARTIAL as expected. **Device A6–A9 still NOT RUN.** Next ID `EV-0275`. |
| 2026-11-05 | **EV-0275 (`PASS`, host): M8 diagnostics status render summary + device-check status fallback** — `vrmc-status.json` now carries an M8 `render` summary (eyeTarget, displayLogical, drawable, foveation, rateMaps, displayHz, eye scale auto/fixed, resizes, valid) written by the provider; `scripts/m8_device_check.py` uses it (plus frameP50/P95/missed) as a fallback for A6–A9 when compositor/provider logs rotated away, and prints it in the report. Provider suite ALL PASS (status JSON strict/fuzz updated; m8-render 49, m8-frame-stats 13); jar `89a5910f…`/136,399 B two-build reproducible; classifier test now 5/5 outcomes including a status-only pull → **PASS (A6-A9)**; M3c fast self-check PASS. **Device A6–A9 still NOT RUN.** Next ID `EV-0276`. |
| 2026-11-05 | **EV-0276 (`PASS`, host): M8 resize texture-lifetime safety — clear the shared eye frame before an eye-target rebuild** — `VisionRenderer.maybeResizeEyeTargets` now calls `VrmcBridge.clearEyeTextures()` immediately before `reinitFrameBuffers()` and logs it, closing the only unsafe window in an M8 dynamic resize (compositor could acquire the about-to-be-destroyed eye VkImages between destroyBuffers and the next submit; in-flight textures were already retained). Real Minecraft host Fabric harness: resize #1 1024x1024 -> 1832x1600 and #2 -> 2200x1928, each preceded by the clear line, **0 M8 exceptions**, render states resizes=1/2; provider suite ALL PASS; provider jar `e9a08c52…`/136,579 B two-build reproducible. **Device A6-A9 still NOT RUN.** Next ID `EV-0277`. |
| 2026-11-05 | **EV-0277 (`PASS`, simulator + host): M8 resize grace — compositor reuses its last sampled eye frame during provider eye-target rebuilds; rebuilt candidate** — the compositor keeps the last sampled MTLTexture pair retained and reuses it for up to 30 frames when the provider has cleared the shared eye frame before a rebuild, then logs grace expiry and recovery. New simulator `eyedrop` scenario (fake provider withholds the eye frame for 60 acquires, then resumes with a bumped generation): reuse -> expiry -> recovery logged in order, compositor survived, final known pattern PASS; `render` regression PASS (46 publications, sharpening active). Candidate rebuilt with the new framework: tree `6773acf1…`, framework `d53e148a…`, bridge `ce11bac2…`, provider `e9a08c52…`, codesign deep/strict PASS. **Device A6–A9 still NOT RUN.** Next ID `EV-0278`. |
| 2026-11-05 | **EV-0278 (`PASS`, host): M8 target-cadence override — pursue 120 Hz explicitly** — new game-dir knob `vrmc-target-hz.txt` (`auto` default, or 60..120 Hz, live ~300 frames): the auto eye-scale policy targets the configured deadline (8.33 ms at 120 Hz) instead of only the measured display cadence (90/96/100/120 chosen by the system), while the achieved rate stays measured. Logged as `target cadence: N Hz (file)…`, `render state … target=N(source)`, and in `vrmc-status.json`; `--target-hz` added to the push script (30 checks) and `TARGET_HZ` to the host harness. Verification: provider suite ALL PASS (27/27 target-cadence checks; jar `144d47a7…`/137,501 B two-build reproducible), real Minecraft Fabric harness PASS with `TARGET_HZ=100` honoured, classifier 5/5, M3c fast self-check PASS. **Device A6–A9 still NOT RUN.** Next ID `EV-0279`. |
| 2026-11-05 | **EV-0279 (`PASS`, host): M8 content-first governor — keep the 4K-class eye target, cut scene cost first** — opt-in `vrmc-content-first.txt` (`off` default, live): when the target cadence (e.g. 120 Hz via `vrmc-target-hz.txt`) is missed for two consecutive windows, reduce render distance (then simulation distance, then render again; min 6 chunks, max 3 steps/session) **before** lowering the eye-target resolution. Logged as `content governor: on/off (file)` + each reduction, `contentFirst=` in render state; `--content-first` push knob (34 self-test checks) and `CONTENT_FIRST` host-harness knob. Verification: provider suite ALL PASS (65/65 policy checks; jar `5d418fd1…`/139,750 B two-build reproducible), real Minecraft harness PASS with both knobs honoured, classifier 5/5, M3c fast self-check PASS. **Device A6–A9 still NOT RUN.** Next ID `EV-0280`. |
| 2026-11-05 | **EV-0280 (`PASS`, host): M8 target-cadence guardrail + harness reliability fix + full host/simulator regression** — if the measured display stays below an operator target cadence for 8 consecutive windows (~16-20 s), the provider logs `target cadence: N Hz unreachable … reverting to auto` and follows the measured cadence; the same file value is not re-applied until the knob changes (retry). Real Minecraft harness `DISPLAY_HZ=90 TARGET_HZ=120` PASS with the revert line after resize `1024x1024 -> 1832x1600`; harness now re-points `build.gradle` at the current test dylib/provider jar every run (stale-path bug) and the host publisher reads the simulated display cadence from a game-dir file. Provider suite ALL PASS (guardrail 23/23; jar `6e2238d5…`/140,714 B two-build reproducible); **full (non-fast) M3c self-check PASS, 10 PASS rows**, all simulator scenarios OVERALL PASS (reentry/gaze SKIP as documented environment limitations; presentation scenarios hard-asserted). **Device A6–A9 still NOT RUN.** Next ID `EV-0281`. |
| 2026-11-06 | **EV-0281 (`PASS`, host): M8 world-supersample (SSAA) knob for jagged edges** — Minecraft 26.2 has no MSAA; new startup-only game-dir knob `vrmc-world-supersample.txt` = `off` (default) or 1.0..2.0 maps to Vivecraft's `renderScaleFactor`: the world render target becomes eye-target × √factor per axis and is resolved down to the eye target (true super-sampling), recomputed at every M8 resize; logged as `world supersample: 1.44x (file) …`. Host Minecraft harness with `SUPERSAMPLE=1.44`: VR target 1832x1600 → **Render target 2199x1921 [Render scale 144.0%, 4.2MP]** (and 2016x1768 → 2420x2122 after the ramp), resize path unaffected. Provider suite ALL PASS (28/28 supersample checks; jar `c055dabf…`/142,286 B two-build reproducible); `--world-supersample` push knob (41 self-test checks); classifier 5/5; M3c fast self-check PASS. **Device A6–A9 still NOT RUN.** Next ID `EV-0282`. |
| 2026-11-06 | **EV-0282 (`PASS`, host Metal): M8 combined foveated drawable + fovea-weighted sharpening** — extended the host Metal probe with the exact device combination: a 480×270 checkerboard upscaled 4× into a 1920×1080 logical viewport backed by a **real rasterization rate map** (0.5 periphery/1.0 centre, physical 1488×848), plain bilinear vs the compositor's CAS-lite pass. Result: **14/14 checks**, combined `centreGain=1.26 vs cornerGain=1.01` (taper survives the rate map), `meanAbsDiff=0.0180` (bound 0.15); non-foveated upscale numbers unchanged (1.17× edge ratio, 1.27 vs 1.00). Fast M3c self-check PASS (8 rows). **Device A6–A9 still NOT RUN.** Next ID `EV-0283`. |
| 2026-11-06 | **EV-0283 (`PASS`, host): M8 resize-failure containment + all-knobs host soak** — the eye-target rebuild is now wrapped: a failing experimental rebuild logs a warning, keeps the current target and disables the auto eye scale instead of crashing the render loop. Content-first uses a broader decaying-pressure trigger (materially over budget counts; +1/−1, two points) so oscillating loads still act. Harness gained `SOAK_SECONDS`; 120 s soak with `TARGET_HZ=120 CONTENT_FIRST=on SUPERSAMPLE=1.44`: **resizes=8, M8-exceptions=0**, final state eyeTarget 3112x2728 / displayHz 120.0 / scale 0.90 / resizes=8 / contentFirst=1(0); earlier same-build heavier-load run: 2 resizes, 0 exceptions, scale 0.50→0.40. Provider suite ALL PASS (content-first 65/65; jar `2242c116…`/142,529 B two-build reproducible); push self-test 41; classifier 5/5; fast self-check PASS. **Device A6–A9 still NOT RUN.** Next ID `EV-0284`. |
