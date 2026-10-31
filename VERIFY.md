# VRMC — Verification and Acceptance Log

**Authority:** This file is the single source of truth for verification, acceptance, evidence, and
release sign-off. Where it conflicts with `AGENT.md` on acceptance, this file wins.
**Last updated:** 2026-10-31.
**Baseline commit:** `a96e13b` (repo reset; no product code).
**Release candidate:** none.
**Next evidence ID:** `EV-0005`.
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

---

## 1. Scope of acceptance

VRMC is accepted only when all of the following hold on device (Apple Vision Pro), with evidence:

| ID | Acceptance criterion | Status |
|---|---|---|
| AC-1 | Fresh sideload → in-world in ≤ 30 min on a 100 Mbps link, using only documented steps. | `NOT RUN` |
| AC-2 | Immersive stereo via CompositorServices: correct per-eye projection and eye order, head tracking active, 90 Hz target with graceful fallback. | `NOT RUN` |
| AC-3 | Core play: move, turn, teleport, jump/sneak, break/place, attack/use, inventory, hotbar, crafting/chests, pause/settings, bow, climbing, save/reload. | `NOT RUN` |
| AC-4 | Every P0 action reachable from hands; P0 actions also reachable from PSVR2 Sense; no stuck input on tracking loss. | `NOT RUN` |
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

### 4.2 Spikes (go/no-go)

| ID | Question | Pass criteria | Fallback | Status |
|---|---|---|---|---|
| ST-S1 | Can the JIT26 mechanism be reproduced internally? | **Reference JVM** + minimal app JIT-compiles and runs on D1 under JIT26; log proves debugger-prepared memory and compiled methods; no W^X failure; recorded **internal** EV required. EV-0002 is external; EV-0004 is host-only. OpenJDK 25 xros build is C3, not S1 | AOT pivot; launcher scope reduces | `NOT RUN` (external `PARTIAL` EV-0002; host `PARTIAL` EV-0004) |
| ST-S2 | Does MC 26.2 Vulkan boot on MoltenVK/xros? | World renders; F3 reports Vulkan; 30 min stable | GL/LTW→ANGLE | `NOT RUN` |
| ST-S3 | Does Vivecraft enter VR with `VisionVR`, no SteamVR? | Provider init; action debug populated; stereo eye targets; **injection point evidenced in the decompiled 26.2‑1.3.15 jar and stable across 26.2.x** | Fork approved by ADR + LGPL source | `NOT RUN` |
| ST-S4 | Can eye textures reach CompositorServices reliably? | Both eyes correct; shared-event sync; 90 Hz; no tearing over 10 min | GPU blit; readback last resort | `NOT RUN` |
| ST-S5 | Do PSVR2 + hands drive all P0 actions? | Full P0 action checklist in both modes | Hands-only MVP | `NOT RUN` |
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

### 4.5 Controller tests (PSVR2 Sense)

| ID | Test | Expected | Status |
|---|---|---|---|
| CT-01 | Detect controllers | Both tracked; type reported | `NOT RUN` |
| CT-02 | Buttons | All mapped actions fire | `NOT RUN` |
| CT-03 | Sticks | Walk/turn with no drift | `NOT RUN` |
| CT-04 | Triggers | Analog range + thresholds | `NOT RUN` |
| CT-05 | Grips | Hotbar/grab behavior | `NOT RUN` |
| CT-06 | Haptics | Pulse on impact/use | `NOT RUN` |
| CT-07 | Handoff controller ↔ hands | No double input; **assumption pending S5** that visionOS 27 stops hand tracking for a held controller | `NOT RUN` |
| CT-08 | Disconnect/reconnect | Inputs release; recovery | `NOT RUN` |

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

**Artifacts:** `evidence/EV-0004/S1-report.md` (965e72a7fce0);
`evidence/EV-0004/host_java_version.log` (f5c5b56aa6d0);
`evidence/EV-0004/host_jit_mac.log` (d893e249f9f6);
`evidence/EV-0004/host_jit26_request.log` (e72bd84f7f89);
`evidence/EV-0004/macho_list.txt` (8d3ee4abbdca).

**Limitations:** host-only macOS run. It does not prove dyld/AMFI acceptance or JIT inside a native
visionOS process; device S1 remains `NOT RUN`. Research by teammate s1-openjdk; the JIT and TXM runs
were reproduced by the Lead.

---

## 7. Status dashboard

| Area | Status | Basis |
|---|---|---|
| Specification (AGENT.md) | `PARTIAL` | Review revisions applied; see §9 |
| Reference baseline | `PARTIAL` | EV-0001, EV-0002 |
| Repo foundation + tooling | `PASS` | EV-0003; commit `3332cdb` |
| JIT mechanism (S1) | `NOT RUN` | External `PARTIAL` (EV-0002); host pre-test `PARTIAL` (EV-0004); device pending |
| JVM/JIT runtime (C3) | `NOT RUN` | OpenJDK 25 xros build pending |
| Graphics (Vulkan/MoltenVK) | `NOT RUN` | ST-S2 pending |
| Provider integration | `NOT RUN` | ST-S3 pending |
| Stereo compositor | `NOT RUN` | ST-S4 pending |
| Input (controllers/hands) | `NOT RUN` | ST-S5 pending |
| Performance/thermal | `NOT RUN` | ST-S6 pending |
| Launcher shell | `NOT RUN` | M1 |
| Acceptance AC-1…AC-6 | `NOT RUN` | Device tests pending |

---

## 8. Open blockers

| Blocker | Owner | Unblock condition |
|---|---|---|
| ST-S1 internal reproduction not yet attempted | Lead | Reference JVM + minimal app under JIT26 on D1 (EV-0002 is external context; OpenJDK build is C3) |
| S1 internal evidence pending | Lead | Record an internal reference-JVM EV; EV-0002 alone does not satisfy S1 |
| ST-S2 MC Vulkan not yet attempted | Lead | MoltenVK xros build + MC 26.2 boot harness |
| All device tests | Lead | Product build exists |

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

---

## 10. Sign-off

| Role | Name | Decision | Date |
|---|---|---|---|
| Verification owner | — | pending | — |
| Lead | — | pending | — |
