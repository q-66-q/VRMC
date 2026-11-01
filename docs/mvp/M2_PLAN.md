# M2 plan — Provider + Vulkan VR (started 2026-11-01)

Status: **in progress — HOST only so far**. M1 closed (EV-0057). **M2-W4/W5 = host PASS (EV-0060)**; **M2-W6 = NOT RUN** (device bring-up); **M3 = NOT RUN**; **S4a-host/S4a-device = NOT RUN**. Host progress is not device completion: device stereo, head tracking, hands, and thermal/frame-rate remain unproven. macstream reference mapping: `docs/mvp/MACSTREAM_REFERENCE.md` (LGPL-3.0, upstream `ec5a851c…`); S4a static findings: `docs/mvp/S4A_FINDINGS.md`. This plan turns the S3 evidence (EV-0006 static + EV-0009
desktop runtime) into a device-buildable provider that renders Minecraft's two eyes through
Vulkan/MoltenVK without SteamVR or any OpenVR runtime.

## 1. Scope and exit criteria

**Goal:** with the VRMC launcher and Vivecraft 26.2-1.3.15 installed, the provider initializes as
`VisionVR`, Minecraft renders **two eye targets** through its Vulkan backend, and the native bridge
receives both eye images at a stable frame cadence — with **no SteamVR, no OpenVR runtime, no
OpenXR runtime**.

M2 exit criteria (all evidenced):
1. Provider init: Mixin redirect → `VisionVR.init()` returns success; MC logs the provider name.
2. Stereo eye targets: both eyes rendered (log + per-eye image hashes differ correctly, or exported
   texture handles recorded).
3. Native bridge handshake: `vrmc_init` version check passes; fail-closed on mismatch.
4. Eye handoff: the bridge receives per-eye texture handles/IDs (Metal object export or GPU blit;
   path decided by S4a).
5. No VR runtime dependency: no SteamVR/OpenVR/OpenXR DLL/dylib loaded; Vivecraft logs no
   "OpenVR not found" failure.
6. Host harness reproducible: the provider can run on desktop Fabric with a stub bridge before device.

## 1a. Scope status (2026-11-01 review)

| Item | Status | Evidence |
|---|---|---|
| M2-W4/W5 bridge + provider + stereo host integration | **PASS (host)** | EV-0060 |
| M2-W6 device bring-up | **NOT RUN** | — |
| S4a-host (macOS MoltenVK export/shared-event) | **PASS** | EV-0063: MTLTexture export + Metal pixel readback + timeline MTLSharedEvent sync |
| S4a-device (visionOS MoltenVK/Metal) | **PASS** | EV-0065: bundled MoltenVK 1.4.3 on D1 — MTLDevice/MTLTexture export, Metal readback, timeline MTLSharedEvent sync |
| M3 compositor stereo + head tracking | **NOT RUN** | — |
| PSVR2 controllers (F1–F3) | **DEFERRED (out of MVP scope)** | P1 register; not BLOCKED |
| Hands-only P0 input (G2/G3/G4) | **HIGH** | sole input path, no controller fallback |

**Identity fallback is host-only.** The provider returns identity controller component transforms only
in the desktop harness (`-Dvrmc.hostHarness=true`). On device, a null controller/hand transform must
**fail loudly** (log + visible error), never silently fall back to identity — otherwise missing
tracking data looks like "hands in the wrong place" and hides the actual defect.

## 1b. macstream compliance (tracked external reference)

`/Volumes/Untitled/Projects/macstream` is an **LGPL-3.0** external project (Vivecraft fork with a
proven no-OpenVR `RemoteVR` backend). Upstream commit
`ec5a851c066856b0a3ca3eadc530d5ea18e88930` is recorded in ADR-0009. **Our `VisionVR`/`VisionRenderer`
and bridge wiring contain code/design derived from macstream's `RemoteVR`/`RemoteVRStereoRenderer`
(LGPL-3.0).** This is compatible with our LGPL provider; the derived code stays inside the separate
LGPL provider artifact — **no macstream code enters the GPL launcher**. Provider needs no additional
license change; notices/ADR-0009 record the derivation.

## 2. Architecture decisions carried from M0/S3

- **No forking Vivecraft.** Separate LGPL-3.0 Fabric mod (`provider/`) Mixins provider selection.
  Injection: `@Redirect` on the ordinal-0 `PUTFIELD ClientDataHolderVR.vr` inside
  `VRState.initializeVR`; works across 26.2-1.3.14/1.3.15 (EV-0006), proven on desktop (EV-0009).
- Provider setting: `vrsettings.json` provider = OPENVR so the branch is taken; `MCOpenVR` is
  constructed and discarded (harmless).
- **Native bridge ABI v1** from `bridge/abi/` (AGENT §3.4): versioned C ABI, fail-closed.
- JVM runs in the launcher process; the bridge dylib is loaded via JNI from the mod and links the
  same process's ObjC/Metal code. No IPC for M2 (revisit only if memory/isolation forces it).
- Graphics: MC `Prefer Vulkan` → MoltenVK. Eye textures must be exported from Vulkan to Metal for the
  bridge (S4a spike) — either `VK_EXT_metal_objects`/external-memory export or a GPU blit into
  app-owned `MTLTexture`s. Fallback is always a blit; do not block the provider on zero-copy.
- Stereo presentation to CompositorServices is **M3**, not M2: M2 only has to produce and hand off the
  two eye images and validate timing telemetry.

## 3. Workstreams

| ID | Workstream | Deliverable |
|---|---|---|
| M2-W1 | Provider skeleton | `provider/` Fabric mod: `VisionVR` (init/poses/IPD/play area/actions stubs), `VisionRenderer` (VRRenderer subclass), mixin config, version lock to Vivecraft 26.2-1.3.15 |
| M2-W2 | Native bridge v1 | `bridge/abi/vrmc_abi.h` + `bridge/src/vrmc_stub.c` (`vrmc_init`, head pose stub, input zeros, submit_eyes counters, frame timing, recenter, haptics); host compile + unit print test |
| M2-W3 | Eye-texture interop (S4a) | Spike: determine the MoltenVK→Metal eye-texture path on visionOS, zero-copy vs blit, sync (shared events); go/no-go + fallback decision |
| M2-W4 | Provider→bridge JNI binding | Mod JNI class loading the bridge dylib; `vrmc_init` handshake; head pose/input poll; eye submit calls |
| M2-W5 | Stereo render path in MC | `VisionRenderer` creates eye targets via MC's Vulkan backend and submits them per frame; log markers + per-eye hashes; host harness first |
| M2-W6 | Device bring-up | Install provider jar + bridge dylib into the VRMC instance; launch MC 26.2 + Vivecraft with `vrEnabled=true`; capture provider/stereo/no-runtime log evidence |

## 4. Spike S4a — Vulkan→Metal eye handoff (HIGH)

**Question:** can the bridge obtain both eye images rendered by MC's Vulkan backend (MoltenVK) without
a full GPU copy, and what synchronization is required?

**Two separate gates — do not collapse them (host PASS ≠ device PASS):**

- **S4a-host: PASS (EV-0063); S4a-device: PASS (EV-0065)** — `MTLTexture` export + Metal readback pixel-correct +
  timeline `MTLSharedEvent` sync on both macOS and D1. Caveat: shared-event export requires a **timeline**
  `VkSemaphore` (binary exports nil).
- **S4a-device:** the same path works on visionOS (visionOS Metal may differ; shared events may have
  different semantics). Separate EV required.

Pass (per gate): documented path + working prototype, no tearing/undefined memory, frame timing
recorded. Fallback: single GPU blit per eye into an app-owned `MTLTexture` (cost noted; acceptable for
M2). Timebox: 3–5 days per gate. Host MoltenVK is macOS Metal; do **not** cite host results as device
evidence (same class of error as S2 substrate vs render).

## 4a. M2-W6 preconditions (device bring-up)

W6 does **not** start with the provider jar. The device instance must already have the mod stack:

1. Install **Fabric 0.19.3** via the launcher (the vanilla 26.2 install alone cannot load Vivecraft).
2. Install **Vivecraft 26.2-1.3.15** via the launcher (pinned jar).
3. Then install the **VRMC provider jar** and place the **bridge dylib** in the app bundle.
4. Launch MC 26.2 with `vrEnabled=true`, `stereoProviderPluginID=OPENVR`; capture provider init and
   no-SteamVR evidence.

If steps 1–2 are missing, W6 is blocked before any provider work — the W6 estimate must include this
setup path (or the launcher must automate it; that is W2/W4 scope).

## 5. Risks

- **Mixin fragility** (internal Vivecraft API): version-locked; if a 26.2.x patch breaks it, fork
  fallback requires ADR + LGPL source release (ADR-0004/0006).
- **Vulkan/Metal interop on visionOS**: least-proven piece; S4a must decide before the renderer
  hardens. Mitigation: blit fallback.
- **Vivecraft renderer internals**: `VRRenderer` expects GL-era hooks; MC 26.2's Vulkan path may need
  provider-side abstraction. Estimate from S3 follow-up: inspect `VRRenderer`/`MCOpenVR` render flow.
- **JNI lifecycle in the launcher process**: dylib load order vs Metal device creation; fail closed.
- **LGPL**: provider remains a separate published artifact; no refactoring into GPL launcher.

## 6. Ordered next actions

1. ~~M2-W2 bridge ABI/stub + host compile test~~ **done** (EV-0058).
2. ~~M2-W1 host harness provider scaffold~~ **done** (EV-0059).
3. **S4a** runtime interop spike on host with MoltenVK (capability check → export/sample test) then visionOS; write note; go/no-go.
4. ~~M2-W4 bridge JNI binding~~ **done (EV-0060)**.
5. ~~M2-W5 stereo eye targets on host~~ **done (EV-0060)**; the GL id handoff is host-only — on visionOS Vulkan the S4a Metal-handle path applies.
6. **S4a runtime** capability check + export/sample prototype (host then visionOS).
7. **M2-W6** device bring-up: provider jar + bridge dylib in the VRMC app, MC+Vivecraft VR, capture evidence.

## 9. ABI evolution policy (v1 → v2)

The ABI just completed its first end-to-end run (host). These rules are binding before M3/M4 need new
fields:

1. **Any layout/field/function change bumps the major version** (`VRMC_ABI_VERSION`), even an additive
   field. No "optional field inside v1" — struct sizes are part of the contract.
2. **Unknown major = fail closed.** Provider and bridge reject any mismatch; `vrmc_init` returns an
   error and the provider aborts VR init with a visible message. `vrmc_init(caps_json)` version
   mismatch is a **reject, never warn-and-continue**.
3. **No cross-version compatibility window.** v1 provider + v2 bridge and v2 provider + v1 bridge both
   fail. A v1→v2 transition ships provider + bridge together in the same app build.
4. **Capabilities** are advertised in `caps_json`; missing required capabilities fail closed. Adding a
   capability string is not a version bump only if the struct/layout is unchanged.
5. **Deprecation:** a field/function may be removed only in the next major bump; one major version of
   overlap is allowed by keeping both symbols but the old one must be documented deprecated.

The same policy is embedded in `bridge/abi/vrmc_abi.h`.

## 7. Test harness

- Host: MC 26.2 + Fabric 0.19.3 + Vivecraft 26.2-1.3.15 + provider mod (same setup as EV-0009) with a
  stub bridge returning fixed poses; screenshots/log assertions.
- Device: VRMC launcher instance; provider jar installed via the launcher's mod install path; bridge
  dylib in the app bundle; log capture with `scripts/capture_device_logs.sh`.
- Evidence: every milestone step gets an EV; no pass without a log/artifact.
