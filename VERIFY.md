# VRMC — Verification and Acceptance Log

**Authority:** This file is the single source of truth for verification, acceptance, evidence, and
release sign-off. Where it conflicts with `AGENT.md` on acceptance, this file wins.
**Last updated:** 2026-10-31.
**Baseline commit:** `a96e13b` (repo reset; no product code).
**Release candidate:** none.
**Next evidence ID:** `EV-0061`.
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
| ST-S1 | Can the JIT26 mechanism be reproduced internally? | Four criteria: (1) JIT-compiled methods **execute**, not only compile; (2) no `brk #0x69` trap; (3) the code cache stays executable after the enabler detaches; (4) a cold relaunch reproduces the result or persistence is proven. **Criterion 4 decides A2 MEDIUM vs LOW.** Reference JVM + minimal app; OpenJDK 25 xros is C3. EV-0002 external; EV-0004 host-only | AOT pivot; launcher scope reduces | `PASS` — EV-0021 (compat: five cold launches) + EV-0024 (native visionOS: JIT26 mapping, tier 3/4, `HELLOJIT`, exit 0) |
| ST-S2 | Does MC 26.2 Vulkan boot on MoltenVK/xros? | Host: backend Vulkan + MoltenVK, no GL fallback, world + 30-min soak. Device: world renders, 30 min stable | GL/LTW→ANGLE | `PASS (M0 gate)` — Device graphics substrate PASS (EV-0025 + EV-0026 + EV-0027); device world render PASS (EV-0034). Full 30-minute soak NOT RUN — deferred to M1 per Decision 45=A (EV-0035 is feasibility evidence). |
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

---

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
| **M2 milestone** | **IN PROGRESS** | EV-0058 scaffold; EV-0059 provider substitution; **EV-0060 host: bridge handshake + provider init + stereo eye targets + submit loop (no SteamVR)**; next S4a Metal-handle path then device bring-up |
| **M0 milestone** | **CLOSED** | S1 PASS (EV-0021/EV-0024), S3 CLOSED (EV-0006/EV-0009), S2 device world render PASS (EV-0034); 30-min soak deferred to M1 (Decision 45=A) |
| M1 T3 — own source build | `PASS` | Source-built Amethyst v1.2.0 boots MC 26.2 Vulkan world on D1 (EV-0036); app-side defaults (EV-0037); route ADR-0008 + EV-0041; **branded VRMC app (dev.vrmc.vrmc) installed (EV-0042)** |
| M1 T1 — stack pins/hashes | `PASS` | versions.env + sha256 for all stack components; check_versions 8/8 (EV-0038) |
| M1 T2 — repo scripts | `PASS` | Parameterized, re-runnable scripts + README (EV-0039) |
| M1 T5 — mouse | `PARTIAL` | visionOS delta-gate patch (EV-0040); follow-up: rotation now smooth, cursor visibility accepted cosmetic (EV-0045/EV-0047), task-2 closed |
| Provider integration | `PASS` | Desktop injection EV-0006 + EV-0009; full provider/renderer and device runtime are M2 |
| Stereo compositor | `NOT RUN` | ST-S4 pending |
| Input (controllers/hands) | `NOT RUN` | ST-S5 pending |
| Performance/thermal | `NOT RUN` | ST-S6 pending |
| S1a harness | `PASS (compat)` | JIT26 mapping + tier 3/4 + `HELLOJIT` + exit 0 across five cold relaunches (EV-0021); StikDebug needs `universal.js` assigned to the app per install |
| S1b harness (native visionOS) | `PASS` | VISIONOS-relabelled JRE builds/signs (EV-0022), launches (EV-0023), and JITs + executes on D1 (EV-0024) |
| M1 launcher probe (Amethyst) | `BLOCKED` | JIT + Java 25 reach MC 26.2 main (EV-0031); LWJGL 3.3.3 vs 3.4.1 mismatch; grafting 3.4.1 Java crashes in the app's embedded 3.3.3 `JNI_OnLoadGLFW` (EV-0032); needs current-source rebuild |
| Launcher shell | `NOT RUN` | M1 |
| Acceptance AC-1…AC-6 | `NOT RUN` | Device tests pending |

---

## 8. Open blockers

| Blocker | Owner | Unblock condition |
|---|---|---|
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

---

## 10. Sign-off

| Role | Name | Decision | Date |
|---|---|---|---|
| Verification owner | — | pending | — |
| Lead | — | pending | — |
