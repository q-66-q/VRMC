# Known Limitations and Current Status

**Last updated:** 2026-10-29 (M0/M1 development build).
**Acceptance status is in [`VERIFY.md`](../../VERIFY.md); this page is not a claim of completion.**

## Not yet verified / blocked

- **Physical Vision Pro:** no hand-tracking or immersive-device evidence exists in this
  workspace. The simulator proves transport/decoder/render plumbing only.
- **Windows + SteamVR + Vivecraft:** the virtual-driver and host sources are present but have
  not been compiled/run on a Windows VR rig here. The driver/SteamVR/Vivecraft session is
  blocked (EV-0005).
- **End-to-end gameplay/latency/failure campaign:** blocked by the two items above.
- **Secure transport:** the app/host currently use an explicitly marked insecure development
  transport. Pairing, AEAD, replay protection, and key storage are designed (protocol/ADR) but
  not implemented/validated. This is a release blocker and a privacy limitation; use only on a
  trusted LAN.
- **Audio:** not implemented (v1.1).
- **Direct-mode capture:** not implemented; the v1 path depends on Vivecraft's DUAL mirror and
  Windows Graphics Capture. If capture is unacceptable on the target PC, a direct-mode driver
  is the planned fallback (new ADR).
- **Depth reprojection:** rotation-only reprojection; head translation is not compensated.
  This can be noticeable during fast positional movement.
- **NVIDIA/Windows only:** NVENC + Windows Graphics Capture are baseline; AMD/Intel encoding,
  Linux/macOS hosts, and other GPUs are out of scope for v1.
- **App Store:** not submitted/approved. TestFlight/Ad Hoc is the v1 path. Local-network and
  remote-rendering policy review is pending.
- **Window in immersive space:** the SwiftUI window currently remains visible with the
  immersive scene; auto-hide/reopen UX is incomplete. Close it manually for an unobstructed view.
- **Gesture tuning:** thresholds are baseline defaults; no human-factors study has been run.
  Palm-normal sign/height calibration needs device validation; profiles may need adjustment.
- **Hand skeleton in SteamVR:** full 27-joint data is captured, transported, and used for gesture
  recognition; the driver does not yet publish a SteamVR skeletal component. Gameplay uses
  controller intent/pose.
- **Input mapping coverage:** core interactions are implemented in the mapping/gesture logic and
  unit-tested, but each must be proven in real Vivecraft on device (AC-3).
- **Vivecraft version pin:** 1.21.11-1.3.15 Fabric. Other versions may change mirror/bindings
  behavior and are not supported without a verification run.
- **Error recovery:** state machines and release paths exist/test locally, but the full NF/HT
  failure matrix is not hardware-verified.
- **Performance:** no device measurement. The simulator runs a 1280×720 30 fps test stream; it
  says nothing about 3840×1080 90 Hz on Vision Pro.
- **Security threat model:** a compromised LAN host can inject video/input; pair only with a
  trusted PC. No cloud relay or remote internet play in v1.
- **Minecraft EULA:** user must own Minecraft; no assets/game binaries are distributed.
- **Vivecraft LGPL:** used unmodified; no companion mod/fork. Driver/host integrate through
  public SteamVR/OpenVR interfaces and the network.

## What is implemented and locally verified

- Protocol v1 spec, Python reference codec, Swift codec, C++ core, conformance vectors.
- Swift unit tests: math/projection, control/media/input framing, reassembly, clock sync,
  prediction, hand features, gestures, mapping/locomotion/menu, tracking loss, session state.
- C++ core tests: byte order, headers, config, media, frame meta, intent, IPC seqlock.
- Swift VideoToolbox H.264 decode of a committed fixture (macOS).
- visionOS simulator app: connects to mock host, decodes H.264 SBS, renders in
  CompositorServices immersive space, sends synthetic head/hand/intent datagrams; mock host
  receives intents. Evidence: EV-0003 (to be recorded).
- Mock host and generated, non-copyrighted stereo test pattern.
- Windows driver/host source (unverified): virtual HMD/controllers, display component, input
  mapping, shared-memory IPC, WGC capture, NVENC, control/UDP/media loops.

## Safety

VR can cause discomfort. Use short sessions, a clear space, and stop on symptoms. This is not a
medical device. Do not use the insecure development transport on untrusted networks.
