# M2 plan — Provider + Vulkan VR (started 2026-11-01)

Status: **in progress**. M1 closed (EV-0057); M2-W1 host harness PASS (EV-0059) — provider Mixin substitutes `VisionVR` on desktop Fabric and fails closed. S4a static findings in `docs/mvp/S4A_FINDINGS.md`. This plan turns the S3 evidence (EV-0006 static + EV-0009
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

Pass: documented path + working prototype on host (MoltenVK on macOS) exporting/sampling an eye image,
with the same code path expected on visionOS; no tearing/undefined memory; frame timing recorded.
Fallback: single GPU blit per eye into app-owned `MTLTexture` (cost noted; acceptable for M2).
Timebox: 3–5 days. Evidence: EV with artifacts (spike code, hashes, screenshots/logs).

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
4. **M2-W4** bridge JNI binding: load `libvrmc_bridge.dylib` from the provider, `vrmc_init` handshake,
   then make `VisionVR.init()` return success against the stub.
5. **M2-W5** stereo eye targets on host; then **M2-W6** device bring-up.

## 7. Test harness

- Host: MC 26.2 + Fabric 0.19.3 + Vivecraft 26.2-1.3.15 + provider mod (same setup as EV-0009) with a
  stub bridge returning fixed poses; screenshots/log assertions.
- Device: VRMC launcher instance; provider jar installed via the launcher's mod install path; bridge
  dylib in the app bundle; log capture with `scripts/capture_device_logs.sh`.
- Evidence: every milestone step gets an EV; no pass without a log/artifact.
