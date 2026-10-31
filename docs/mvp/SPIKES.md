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
- **S1a (compat mode, ~1 week).** Minimal harness: a Swift/ObjC app embedding the unmodified iOS
  JRE 25 + `HelloJit`, one enabler script (attach, prepare the code cache, detach, continue),
  installed and launched on D1. **Out of scope:** Minecraft, Vivecraft, CompositorServices (S1b/S2/S4).
  Pass requires the four criteria above; record as `PASS (compat)` only with device evidence — it does
  not satisfy ST-S1's native requirement. **Scaffold:** `runtime/probes/s1a/` compiles
  (`build.sh --check`, EV-0007). Device build is `BLOCKED` (EV-0008): unlock the AVP, then re-run
  `xcodebuild -allowProvisioningUpdates` so automatic signing registers it and creates the profile. **Divergence note:** if D1's JIT26 behavior differs from the
  macOS host (no TXM trap, different failure), record it for S1b. Start the AVP provisioning-profile
  update before this work lands; the current free-team profile covers only the iPad.
- **S1b (target, 1.5–3 weeks).** Native visionOS harness with the relabelled+re-signed JRE; request
  JIT through the on-device enabler (poll `CS_DEBUGGED`, then `JLI_Launch`). A **custom** script is
  required because the JVM's `0x69` request is allocation-style (`x0 = size`), unlike the enabler's
  default serve. Do not copy AGPL-3.0 StikDebug script text; Amethyst is GPL-3.0, Apparition MIT.
- JVM args: `-XX:+UnlockExperimentalVMOptions -XX:+MirrorMappedCodeCache -XX:+PrintCompilation
  -XX:ReservedCodeCacheSize=64m -XX:-UseCompressedClassPointers`; provide the TXM signal the build
  expects (environment/exported symbol).
- Control run: the same app without JIT enablement (interpreter), to measure the speedup.

**Pass criteria (all four required).**
1. JIT-compiled methods are actually **executed**, not merely compiled.
2. No `brk #0x69` trap occurs during execution.
3. After the enabler detaches, the JIT code cache remains executable.
4. A **cold relaunch** reproduces the result, or a persistence mechanism is proven.

Criterion 4 decides A2's final hardness (MEDIUM vs LOW). A host-only run is `PARTIAL` (EV-0004);
simulator runs are not evidence.

**Artifacts.** Device log, `PrintCompilation` excerpt, enabler script log, app build SHA-256, launch
procedure, video of the device run, manifest.

**Fallback.** A different JVM candidate; if no JVM can JIT, pivot to AOT (ADR-0001 fallback) and
re-baseline M1.

**Timebox.** 3–4 weeks total: S1a ~1 week, S1b 1.5–3 weeks, evidence 2–3 days.

## S2 — Minecraft 26.2 Vulkan via MoltenVK

**Question.** Does MC 26.2's experimental Vulkan renderer run through MoltenVK on macOS, and then on
visionOS?

**Pre-spike findings (2026-10-31).**

- MC 26.2's Vulkan backend requires 5 device extensions (`VK_KHR_dynamic_rendering`,
  `VK_KHR_push_descriptor`, `VK_KHR_synchronization2`, `VK_EXT_vertex_attribute_divisor`,
  `VK_KHR_swapchain`) and 9 features (timeline semaphores, dynamic rendering, sync2, vertex-divisor,
  multiDrawIndirect, fillModeNonSolid, samplerAnisotropy, shaderDrawParameters, hostQueryReset).
  Optional: `VK_EXT_multi_draw`, checkpoint extensions, portability subset. Missing required items
  flip MC to its GL backend.
- Measured against the exact `libMoltenVK.dylib` bundled with LWJGL 3.4.1 (MoltenVK 1.4.2,
  Vulkan 1.2.334): all 5 extensions and all 9 features are present; `maxPushDescriptors=287`.
  MoltenVK officially builds for visionOS but release artifacts omit it (build from source).
- Host pre-test EV-0005: MC 26.2 boots with `--graphicsBackend vulkan` on macOS 27.0.1 and logs
  `Using graphics backend Vulkan, using drivers: 1.2.334 MoltenVK 1.4.2` with the required
  extensions; no GL fallback. Menu only; no world render or soak yet.
- Known risks: push descriptors ride Metal argument buffers (MoltenVK issues #2827/#2888/#1839); the
  official visionOS Cube demo currently fails to find the Vulkan runtime (#2665); visionOS release
  artifacts omit the xros slice (#2385); visionOS has no validation layers.
- visionOS deltas are stack-level, not MoltenVK-level: xros MoltenVK build, xros LWJGL 3.4.1 natives
  (not published), Java GLFW replacement + `MacosUtil` shadow + `CAMetalLayer` handoff
  (`GLFWVulkan.glfwCreateWindowSurface` via `vkCreateMetalSurfaceEXT`), and `-rdynamic` symbol export.

**Plan.**
1. macOS pre-test (boot done, EV-0005): force Vulkan, capture backend lines; extend to a world render
   and a 30-minute soak on host (both still `NOT RUN`).
2. Pin MoltenVK (match LWJGL's `f79c6c5` or 1.4.2) and build the xros slice; record commit + log.
3. Run the capability probe on D1 (same 5 extensions + 9 features) and record the JSON.
4. Build/retag LWJGL 3.4.1 xros natives (liblwjgl, shaderc, spvc, vma, freetype, stb, tinyfd, openal);
   load test.
5. GLFW stub + `MacosUtil` shadow + CAMetalLayer + `org.lwjgl.vulkan.libname`; boot to title on D1
   (requires the S1/C3 JVM).
6. World render, F3 screenshot, 30-minute stability -> S2 EV; otherwise document the blocker and
   invoke the fallback ADR.

**Prerequisites.** MC 26.2 client/libraries/assets (user-owned), Temurin 25 for the host stage,
MoltenVK pinned build, xros LWJGL natives, `versions.env` hashes.

**Pass criteria.**
- Host stage: backend Vulkan + MoltenVK with no GL fallback (EV-0005 covers boot; a world render and
  soak are still required for a full host pass).
- Host scope note: the host stage de-risks MC's Vulkan backend against MoltenVK; it is **not** S2
  device evidence. The xros work is limited to the MoltenVK-xros port, LWJGL-xros natives, and the
  GLFW/CAMetalLayer shim.
- Device stage: world renders via Vulkan (F3 + log) for 30 minutes; required extensions present on
  xros; no fallback; MoltenVK gaps documented.

**Fallback.** GL/LTW → ANGLE path; ADR update and S4 re-plan. Patch MoltenVK only for a specific
missing feature, with the patch and reason recorded.

**Timebox.** 2–3 weeks: host pre-test 0.5 d; MoltenVK xros build 1–2 d; xros natives 3–5 d;
GLFW/MacosUtil parity 2–3 d; CAMetalLayer/window 2–3 d; device debug 3–5 d (overlaps S1/C3).

## S3 — Provider injection

**Question.** Is there a real, stable injection point for a `VisionVR` provider in Vivecraft
26.2-1.3.15, without forking?

**Pre-spike findings (2026-10-31, EV-0006, static).**

- `VRState` is public; `initializeVR()` is `public static`. Provider selection is a branch on
  `VRSettings.stereoProviderPluginID == VRProvider.OPENVR`, constructing `MCOpenVR` (ordinal-0
  `PUTFIELD ClientDataHolderVR.vr`) or `NullVR` (ordinal-1). No public provider API exists.
- `initializeVR` bytecode is byte-identical across 26.2‑1.3.14 and 26.2‑1.3.15 (19,772 bytes,
  sha256 `dcde94f…`), so the injection point is stable across the two available patch builds.
- `MCOpenVR`'s constructor allocates LWJGL structs but makes no `org.lwjgl.openvr` `VR_*` calls, so a
  redirect that discards it is safe (one small discarded allocation).
- Recommended injection: `@Redirect` the ordinal-0 `PUTFIELD`, signature
  `(ClientDataHolderVR, MCVR) -> MCVR`, returning `VisionVR`; set the provider setting to OPENVR in
  `vrsettings.json`. Runtime Mixin test is still required — the fork path is **not** triggered yet.

**Steps.**
1. Obtain the Vivecraft jar from the official source; record its hash (done: EV-0006).
2. Decompile `VRState.initializeVR`, `MCVR`, `VRRenderer`, and the provider factory path; capture the
   target and descriptor (done: EV-0006).
3. Build the minimal LGPL companion mod with the redirect Mixin and a stub `VisionVR`.
4. Run on desktop JVM (Fabric, MC 26.2) to prove the Mixin applies and the stub is instantiated;
   capture logs. This is the remaining S3 gate.
5. Re-check the injection against any newer 26.2.x patch; note drift.
6. Record the decompiled excerpts and runtime log (with the mod's LGPL notice) as evidence.

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
