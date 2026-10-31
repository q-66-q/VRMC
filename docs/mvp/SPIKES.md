# Spike Procedures

**Authority:** status lives in [`VERIFY.md`](../../VERIFY.md) (§4.2 spikes, §6 evidence, §7
dashboard) and is summarized in [`AGENT.md`](../../AGENT.md) §4.5/§6. This file defines *how* to
run each spike. When a spike status changes, apply `AGENT.md` §4.7.

Status at time of writing (2026-10-31): S1 `NOT RUN` (external `PARTIAL`, EV-0002); S2–S6 `NOT RUN`.

| Spike | Question | Hardness | Depends on | Fallback |
|---|---|---|---|---|
| S1 | Can a reference JVM JIT on D1 under JIT26? | MEDIUM | — | AOT pivot |
| S2 | Does MC 26.2 Vulkan boot on MoltenVK/xros? | **HIGH** | S1 for device run; macOS pre-test independent | GL/LTW→ANGLE |
| S3 | Is the Vivecraft provider injection point real and stable? | MEDIUM | — (static + desktop JVM) | Fork via ADR |
| S4 | Can eye textures reach CompositorServices reliably? | **HIGH** | S2 | GPU blit, then readback |
| S5 | Do PSVR2 + hands drive all P0 actions? | MEDIUM | S3/S4 | Hands-only MVP |
| S6 | Do frame pacing and thermals hold? | **HIGH** | S2/S4/S5 | Lower preset, 45 Hz lock |

## S1 — JIT mechanism, internal reproduction

**Question.** Can a reference JVM execute JIT-compiled code on D1 (paired Apple Vision Pro,
visionOS 27.2) under the JIT26 debugger-prepared-memory protocol?

**Known.** No JIT entitlement exists on visionOS. EV-0002 records an external demonstration
(Apparition + ARMSX2/UTM): the app requests prepared memory with `brk #0xf00d`, an attached
debugger prepares each 16 KiB page, the app executes from it and writes code through a writable
alias. EV-0004 records the host-only pre-test below. Internal device reproduction is the gap.

**Pre-spike findings (2026-10-31, EV-0004, host-only).**

- The likely reference JRE is Amethyst's prebuilt OpenJDK 25 iOS bundle (`assets.angelauramc.dev`),
  built from `jdk25u` with the `MirrorMappedCodeCache` patch: the code cache is reserved through a
  debugger request (`brk #0x69`), mirrored RW/RX with `vm_remap`, and code writes go through the
  writable alias. Log lines: `[JIT26] Requesting…`, `[JIT26] Got JIT mapping…`,
  `[JIT26] mapping at RW=…,RX=…`.
- dyld will not load IOS-platform images into a visionOS process; images must be relabelled
  (`vtool -set-build-version 11 …`) and re-signed. On macOS, relabel+resign made the shipped JRE run
  and JIT (tiers 3/4), and `XNU_HAS_TXM=1` trapped at the request site (exit 133).
- Open questions are therefore platform acceptance (AMFI/library validation), the on-device script's
  semantics for the JVM's allocation-style request, TXM detection, and in-process `JLI_Launch` —
  not the JIT mechanism itself.

**Scope.** A reference JVM + minimal app. The OpenJDK 25 xros runtime is **C3**, not S1.

**Prerequisites.**
- Paired D1 (visionOS 27.2) and a signing team (personal team observed on M1; 7-day provisioning).
- Xcode 27.2 / visionOS 27.2 SDK.
- A reference JRE candidate: relabelled+re-signed Amethyst `jre25` bundle (fast) or a rebuilt xros
  runtime (C3, later).
- A JIT-enablement path: Xcode-attached debugger, StikDebug-style tool, or Apparition-style
  sideloader. Record which one is used.
- A provisioning profile containing the AVP UDID (the current free-team profile covers iOS/xrOS but
  only the iPad), Developer Mode enabled on D1, and the enabler installed.

**Plan.**
- **S1a (compat mode, ~1 week).** Wrap the unmodified iOS JRE in a small iOS app (`HelloJit` + hot
  loop), install via Apparition, "Launch with JIT", capture `[JIT26]` lines + `PrintCompilation`.
  Proves the reference JVM + JIT26 on D1 but **not** native xros: record as `PASS (compat)` only
  with device evidence; it does not satisfy ST-S1's native requirement.
- **S1b (target, 1.5–3 weeks).** Native visionOS harness with the relabelled+re-signed JRE; request
  JIT through the on-device enabler (poll `CS_DEBUGGED`, then `JLI_Launch`). A **custom** script is
  required because the JVM's `0x69` request is allocation-style (`x0 = size`), unlike the enabler's
  default serve. Do not copy AGPL-3.0 StikDebug script text; Amethyst is GPL-3.0, Apparition MIT.
- JVM args: `-XX:+UnlockExperimentalVMOptions -XX:+MirrorMappedCodeCache -XX:+PrintCompilation
  -XX:ReservedCodeCacheSize=64m -XX:-UseCompressedClassPointers`; provide the TXM signal the build
  expects (environment/exported symbol).
- Control run: the same app without JIT enablement (interpreter), to measure the speedup.

**Pass criteria.**
- Device evidence shows a debugger-prepared mapping (`[JIT26] Got JIT mapping` / `mapping at RW=…,
  RX=…`), compiled methods (tier 3/4), and 10 minutes without W^X faults.
- A measurable speedup versus the interpreter control (report the ratio; target ≥ 2× on the hot loop).
- Safe, explained failure when preparation is absent.
- Recorded as an internal EV with device log, app build SHA-256, and manifest. Host-only runs are
  `PARTIAL` (EV-0004).

**Artifacts.** Device log, `PrintCompilation` excerpt, enabler script log, app build SHA-256, launch
procedure, video of the device run, manifest.

**Fallback.** A different JVM candidate; if no JVM can JIT, pivot to AOT (ADR-0001 fallback) and
re-baseline M1.

**Timebox.** 3–4 weeks total: S1a ~1 week, S1b 1.5–3 weeks, evidence 2–3 days.

## S2 — Minecraft 26.2 Vulkan via MoltenVK

**Question.** Does MC 26.2's experimental Vulkan renderer run through MoltenVK on macOS, and then on
visionOS?

**Split.**
1. **Pre-test on M1 (macOS):** run MC 26.2 with Graphics API = Prefer Vulkan using a MoltenVK build;
   confirm F3 reports Vulkan and a world renders for 30 minutes. This validates the MC/MoltenVK pair
   without the JVM port.
2. **Device test:** requires S1 (a JVM on device). Run the same MC instance under the device JVM and
   capture F3, logs, frame timing.

**Prerequisites.** MC 26.2 client/libraries/assets (user-owned account), MoltenVK pinned build,
LWJGL 3.4.1 vulkan natives, `versions.env` hashes.

**Pass criteria.** World renders via Vulkan (F3 backend line + logs) for 30 minutes; no device loss;
MoltenVK/extension gaps documented; evidence recorded per stage (macOS stage may be PARTIAL for the
device gate).

**Fallback.** GL/LTW → ANGLE path; ADR update and S4 re-plan.

**Timebox.** 2–3 weeks.

## S3 — Provider injection

**Question.** Is there a real, stable injection point for a `VisionVR` provider in Vivecraft
26.2-1.3.15, without forking?

**Steps.**
1. Obtain the Vivecraft jar from the official source (user-owned); record its hash.
2. Decompile `VRState.initializeVR`, `MCVR`, `VRRenderer`, and the provider factory path; capture the
   exact target and descriptor for the Mixin.
3. Build a minimal companion mod that Mixins the selection path and instantiates a stub `MCVR`.
4. Run on desktop JVM (Fabric, MC 26.2) to prove the Mixin applies; capture logs.
5. Check the same injection across available 26.2.x Vivecraft patch versions; note drift.
6. Record the decompiled excerpts (with the mod's LGPL notice) as evidence.

**Pass criteria.** Mixin applies, the stub provider is instantiated without SteamVR, and the
injection point is evidenced in the decompiled 26.2-1.3.15 jar and holds across 26.2.x patches.
Decision deadline: **M0 exit**. If unstable, approve the fork by ADR and re-baseline M2.

**Fallback.** Fork Vivecraft under LGPL-3.0 with published source and a rebase strategy.

**Timebox.** 2–3 weeks.

## S4 — Eye texture handoff and CompositorServices

**Question.** Can Minecraft's Vulkan eye images be presented through CompositorServices reliably at
90 Hz?

**Steps.**
1. Build a harness that allocates two eye targets on the MC Vulkan device, renders a test pattern,
   and hands the images to the compositor (Metal object export and/or GPU blit).
2. Present per-eye with the correct projection and eye order; verify no vertical flip.
3. Hold 90 Hz for 10 minutes; instrument frame deadlines and synchronization.
4. Record tearing/stall observations with a high-speed camera if available.

**Pass criteria.** Both eyes correct, shared synchronization works, 10-minute run without tearing or
deadline misses that trip the watchdog, evidence recorded.

**Fallback.** GPU blit path; readback only as a last resort (and then re-evaluate feasibility).

**Timebox.** 2–3 weeks.

## S5 — Input coverage

**Question.** Do PSVR2 Sense and hand gestures drive every P0 action?

**Steps.**
1. Inventory the P0 actions from `AGENT.md` §4.3 (F/G/H) into a checklist.
2. Implement the PSVR2 profile and the gesture profile; expose a debug overlay.
3. Run the checklist in controller mode and in hands-only mode; record failures.
4. Run tracking-loss and takeover tests (HT/CT suites).
5. Measure gesture recognition over 30 trials per gesture across 3 testers (≥ 90%).

**Pass criteria.** Full checklist passes in both modes (or hands-only accepted if no controllers),
no stuck inputs, gesture bar met.

**Fallback.** Hands-only MVP; controllers move to P1.

**Timebox.** 2–3 weeks.

## S6 — Performance and thermals

**Question.** Can the device hold frame pacing and thermals at the target presets?

**Steps.**
1. Build the fixed benchmark world/scene and a repeatable route.
2. Measure frame timing via CompositorServices timing, for 10 minutes per preset.
3. Run a 30-minute thermal soak; record thermal state and frame floor.
4. Tune presets and caps; document the final numbers.

**Pass criteria.** K2/K5 met, or a documented waiver with mitigation; evidence recorded.

**Fallback.** Lower default preset, 45 Hz repeat lock, render-distance cap.

**Timebox.** 2–3 weeks.

## Recording rules

- Every spike run gets an `EV-####` entry (`scripts/log_evidence.sh`), even when it fails.
- A spike passes only with an EV entry; code inspection is `PARTIAL`, never `PASS`.
- Simulator runs are not evidence for S1 (device JIT), S4 (optics), S5 (hands), or S6 (thermals).
