# ADR-0001 — Run unmodified Vivecraft on a remote PC and stream to Vision Pro

- **Status:** Accepted
- **Date:** 2026-10-29
- **Deciders:** Lead architect, integration owner
- **Supersedes:** Archived native visionOS Minecraft prototype (not an ADR)
- **Related:** ADR-0002..0006, `docs/feasibility/FEASIBILITY_AUDIT.md`

## Context

Vivecraft is a Minecraft Java modification that uses SteamVR/OpenVR and SteamVR Input. It
must actually run and be playable on Apple Vision Pro with hand tracking. visionOS has no
OpenXR or OpenVR runtime, no desktop OpenGL, and no SteamVR Input. Running Vivecraft natively
would require porting Minecraft, LWJGL, the VR renderer, and replacing Vivecraft's OpenVR
provider — a large fork with poor maintainability and platform-policy risk.

The archived prototype ran Minecraft Java natively on visionOS through Amethyst, a retargeted
JVM/MetalANGLE stack, and a custom two-pass stereo Fabric mod. It did not run Vivecraft, had no
OpenVR, no head-tracked camera, no hand input, and was not hardware-verified. It is evidence
that a native port is *possible*, not that it is a viable route to the acceptance criteria.

## Decision

Run the **real, unmodified** Minecraft + Fabric + Vivecraft stack on a Windows PC with
SteamVR. Provide:

1. A small OpenVR virtual-device driver (`driver_vrmc`) exposing a virtual HMD and two
   Index-style controllers, fed by VRMC.
2. A Windows host that captures Vivecraft's DUAL mirror, encodes it, and streams it over the
   LAN.
3. A native visionOS client that decodes and renders stereo via CompositorServices/Metal,
   tracks both hands with ARKit, and sends timestamped hand/head data back.
4. A protocol and hand-mapping layer that turn articulated hands into SteamVR controller
   state and poses.

No Minecraft, Vivecraft, or SteamVR binaries are bundled or modified. Integration is at
arm's length through documented OpenVR and network interfaces.

## Consequences

### Positive

- Real Vivecraft gameplay, bindings, mod compatibility, and updates.
- No JIT, no game engine port, no OpenGL-on-visionOS work.
- Client and driver are small, testable, and replaceable.
- Clear licensing boundary: original VRMC code is Apache-2.0; Vivecraft remains user-installed
  LGPL-3.0.
- Head/hand input, latency, and recovery are fully under VRMC's control.

### Negative

- Requires a VR-capable Windows PC, SteamVR, and a high-quality LAN.
- Adds network and encode/decode latency; acceptance depends on meeting the M2P budget.
- PC setup is more complex than a native app; documentation must be excellent.
- Windows/NVIDIA is the v1 baseline; Linux/AMD/Intel are out of scope.
- The session is unavailable when the PC is off or the network fails (degraded, not native).

### Neutral

- The headset is a thin client; the PC remains the source of truth for game simulation.
- Hand tracking is client-side; the PC receives controller intent, not raw hand video.

## Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Native visionOS Vivecraft backend | Requires replacing OpenVR, OpenGL, SteamVR Input and the JVM platform layer; multi-quarter, high risk, large LGPL fork; no hardware proof. |
| Native OpenXR runtime on visionOS + OpenComposite | Implementing an OpenXR runtime plus an OpenGL→Metal path and an unmerged Vivecraft OpenXR port is larger and riskier than the remote path. |
| Adapt ALVR/WiVRn server and write a visionOS client | Large third-party protocol/driver dependency; no visionOS client exists; hand semantics still need mapping; less control over capture/recovery. |
| Virtual desktop only (mono/SBS screen) | Does not provide immersive head tracking or hand-driven VR gameplay; fails acceptance. |
| Controllers only / gamepad fallback | Fails the hand-tracking requirement. |

## Verification

Architecture selection is supported by source inspection (Vivecraft OpenVR dependency, DUAL
mirror, knuckles bindings) and platform capability checks. Runtime feasibility is conditional
on spikes S-01/S-02/S-03/S-05, recorded in `VERIFY.md`. This ADR does not claim acceptance.

## Revisit triggers

- S-01 cannot make SteamVR/Vivecraft initialise with the virtual devices.
- S-02/S-07 shows mirror capture is not viable at target quality/fps.
- S-05 cannot meet the latency floor after optimization and reasonable hardware.
- Apple policy or App Review blocks local-network streaming in the target distribution.

If any trigger fires, stop, record evidence, and evaluate ADR-0002's direct-mode alternative
or a new architecture. Do not silently patch around it.
