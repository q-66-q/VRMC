# M2 acceptance matrix — Provider + Vulkan VR (CLOSED 2026-11-01)

Status: **M2 CLOSED** (EV-0070). M1 closed earlier (EV-0057). This matrix records every M2 exit
criterion with its evidence and the explicitly deferred M3/M4 work. M2 is about **provider
initialization and eye handoff**, not immersive presentation or input.

## Exit criteria

| # | Criterion (M2_PLAN §1) | Status | Evidence / note |
|---|---|---|---|
| 1 | Provider init: Mixin redirect → `VisionVR.init()` success; MC logs the provider | **PASS** | Device: EV-0068 (`[VRMC-M2] VisionVR.init() succeeded`); host: EV-0059/EV-0060 |
| 2 | Stereo eye targets: both eyes rendered/created | **PASS** | Device: `eye target L/R 1024x1024`, `Active RenderPasses: LEFT, RIGHT` (EV-0068) |
| 3 | Native bridge handshake ABI v1/v2, fail-closed | **PASS** | Device: `[vrmc-stub] init ok, abi=2`, `bridge handshake ok (ABI 2)` (EV-0068/EV-0069) |
| 4 | Eye handoff: bridge receives per-eye texture handles | **PASS** | Host: GL id submit (EV-0060); substrate: S4a-host (EV-0063) and S4a-device (EV-0065); **device product renderer: `vulkan eye export: VkImage=0x… -> MTLTexture=0x…`** (EV-0069) |
| 5 | No SteamVR/OpenVR/OpenXR runtime | **PASS** | No runtime failure in any device/host run; provider substitution path only (EV-0068/EV-0069) |
| 6 | Host harness reproducible | **PASS** | Desktop Fabric + stub bridge end-to-end (EV-0060); provider source committed |

## Workstreams

| ID | Status | Note |
|---|---|---|
| M2-W1 provider skeleton | **DONE** | `VisionVR`, `VisionRenderer`, mixin; desktop + device |
| M2-W2 native bridge v1 | **DONE** | ABI v1 stub compiled/tested (EV-0058); evolved to v2 for MTLTexture export (EV-0069) |
| M2-W3/S4a eye interop | **DONE (both gates)** | S4a-host PASS (EV-0063), S4a-device PASS (EV-0065); timeline MTLSharedEvent requirement recorded |
| M2-W4 provider→bridge JNI | **DONE** | Handshake, tracking poll, submit path; device-verified |
| M2-W5 stereo render path | **DONE** | Eye targets, LEFT/RIGHT passes, device Vulkan→Metal export/submit (EV-0069) |
| M2-W6 device bring-up | **DONE** | Fabric 0.20.1 + Vivecraft 26.2-1.3.15 + provider + bridge dylib on D1 (EV-0067/EV-0068/EV-0069) |

## Explicitly NOT part of M2 / NOT RUN

- **M3 compositor stereo + head tracking**: NOT RUN. This is why the device view is still raw/low and
  not presented immersively, and why "VR mode" does not look enabled to the user.
- **M4 input**: NOT RUN. This is why clicking/selecting does not work.
- XR runtime, hand/controller input mapping, frame pacing/thermal targets: later milestones.

## Notes / carry-overs

- **Fabric loader drift:** device used **0.20.1**, repo pin is **0.19.3**. The provider loaded and
  initialized correctly on 0.20.1 — recorded as a compatibility candidate; pin/ADR decision is a
  carry-over to M3 (do not silently change the pin).
- **Bridge dylib** is built for arm64-ios and embedded in the app; `-Dvrmc.bridge.lib` is injected by
  the launcher (EV-0066).
- ABI v2 is now the contract (v1 was never shipped externally); provider + bridge ship together.
