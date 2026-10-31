# VRMC — Verification and Acceptance Log

**Authority:** This file is the single source of truth for verification, acceptance, evidence, and
release sign-off. Where it conflicts with `AGENT.md` on acceptance, this file wins.
**Last updated:** 2026-10-31.
**Baseline commit:** `a96e13b` (repo reset; no product code).
**Release candidate:** none.
**Next evidence ID:** `EV-0011`.
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
| AT-010 | S1a harness scaffold self-check | `build.sh --check` passes; HelloJit executes on host with harness flags | `PASS` (EV-0007) |

**AT allocation rule:** AT IDs are assigned sequentially when a test is added to this registry — no
gaps, no reuse. `scripts/log_evidence.sh` allocates **EV** IDs only; it never allocates AT IDs. The
EV that first evidences a test is recorded in the Status column.

### 4.2 Spikes (go/no-go)

| ID | Question | Pass criteria | Fallback | Status |
|---|---|---|---|---|
| ST-S1 | Can the JIT26 mechanism be reproduced internally? | Four criteria: (1) JIT-compiled methods **execute**, not only compile; (2) no `brk #0x69` trap; (3) the code cache stays executable after the enabler detaches; (4) a cold relaunch reproduces the result or persistence is proven. **Criterion 4 decides A2 MEDIUM vs LOW.** Reference JVM + minimal app; OpenJDK 25 xros is C3. EV-0002 is external; EV-0004 is host-only | AOT pivot; launcher scope reduces | `NOT RUN` (external `PARTIAL` EV-0002; host `PARTIAL` EV-0004) |
| ST-S2 | Does MC 26.2 Vulkan boot on MoltenVK/xros? | Host: backend Vulkan + MoltenVK, no GL fallback. Device: world renders, 30 min stable | GL/LTW→ANGLE | `NOT RUN` (host boot PASS EV-0005; visionOS MoltenVK built EV-0010; device pending) |
| ST-S3 | Does Vivecraft enter VR with `VisionVR`, no SteamVR? | Provider init; action debug populated; stereo eye targets; **injection point evidenced in the decompiled 26.2‑1.3.15 jar and stable across 26.2.x** | Fork approved by ADR + LGPL source | `PASS` (desktop injection: EV-0006 static + EV-0009 runtime); full provider/renderer and device runtime are M2 |
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

---

## 7. Status dashboard

| Area | Status | Basis |
|---|---|---|
| Specification (AGENT.md) | `PARTIAL` | Committed; M0 review pending |
| Reference baseline | `PARTIAL` | EV-0001, EV-0002 |
| Repo foundation + tooling | `PASS` | EV-0003; commit `3332cdb` |
| JIT mechanism (S1) | `NOT RUN` | External `PARTIAL` (EV-0002); host pre-test `PARTIAL` (EV-0004); device pending |
| JVM/JIT runtime (C3) | `NOT RUN` | OpenJDK 25 xros build pending |
| Graphics (Vulkan/MoltenVK) | `NOT RUN` | Host boot PASS (EV-0005); visionOS MoltenVK built (EV-0010); world render/soak and device pending |
| Provider integration | `PASS` | Desktop injection EV-0006 + EV-0009; full provider/renderer and device runtime are M2 |
| Stereo compositor | `NOT RUN` | ST-S4 pending |
| Input (controllers/hands) | `NOT RUN` | ST-S5 pending |
| Performance/thermal | `NOT RUN` | ST-S6 pending |
| S1a harness (scaffold) | `PARTIAL` | Compiles + host flags (EV-0007); device build `BLOCKED` (EV-0008) |
| Launcher shell | `NOT RUN` | M1 |
| Acceptance AC-1…AC-6 | `NOT RUN` | Device tests pending |

---

## 8. Open blockers

| Blocker | Owner | Unblock condition |
|---|---|---|
| ST-S1 internal reproduction not yet attempted | Lead | Reference JVM + minimal app under JIT26 on D1 (EV-0002 is external context; OpenJDK build is C3) |
| S1 internal evidence pending | Lead | Record an internal reference-JVM EV; EV-0002 alone does not satisfy S1 |
| AVP provisioning profile missing | Lead/user | Only an iPad profile exists (expires 2026-11-05). **Unlock/wear the AVP**, then re-run `xcodebuild -allowProvisioningUpdates` in `runtime/probes/s1a` to register the device and create the profile |
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
| 2026-10-31 | EV-0005 records the S2 host pre-test (`PARTIAL`): MC 26.2 boots with Vulkan via MoltenVK 1.4.2 and no GL fallback. Device S2, world render, and soak remain `NOT RUN`. |
| 2026-10-31 | EV-0006 records S3 static analysis (`PARTIAL`): injection point exists and `initializeVR` bytecode is identical across 1.3.14/1.3.15; runtime Mixin test pending. Added interpretation/scope notes to EV-0004/EV-0005 and the AT allocation rule. |
| 2026-10-31 | S1a harness scaffolded in `runtime/probes/s1a`; EV-0007 records the build self-check and host JIT run (`PARTIAL`). EV-0008 records the device-build attempt (`BLOCKED`: AVP locked; no AVP profile). |
| 2026-10-31 | EV-0009 records the S3 runtime probe (`PASS`, desktop): the Mixin substitutes `VisionVR` for `MCOpenVR` with no SteamVR. Injection decision: Mixin, no fork. |
| 2026-10-31 | EV-0010 records the MoltenVK v1.4.2 visionOS build (`PASS`, host): `xros-arm64`, platform VISIONOS, minos 27.2. Device stage still `NOT RUN`. Next ID `EV-0011`. |

---

## 10. Sign-off

| Role | Name | Decision | Date |
|---|---|---|---|
| Verification owner | — | pending | — |
| Lead | — | pending | — |
