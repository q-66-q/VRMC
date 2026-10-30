# VRMC Feasibility Audit

**Status:** Completed for architecture selection; runtime spikes pending.
**Date:** 2026-10-29.
**Author:** Lead architect.
**Decision:** ADR-0001 — remote, unmodified Vivecraft runtime + custom stereo stream + virtual
SteamVR devices + visionOS hand-tracking client.

---

## 1. Executive summary

It is **not feasible within a reasonable budget** to run Vivecraft natively inside visionOS:
visionOS exposes no OpenXR or OpenVR runtime, and Vivecraft's client is built on LWJGL's
OpenVR bindings and SteamVR Input. A native port would require replacing Vivecraft's entire
VR backend, Minecraft's rendering path, and the OpenVR input system, while retaining
Vivecraft's gameplay logic — a large, fragile fork of two GPL/LGPL/proprietary codebases.

It **is feasible** to run the real, unmodified Vivecraft on a Windows PC and stream a
low-latency stereo view to Vision Pro, while synthesising two SteamVR controllers from fully
articulated hand tracking. The critical enabler is Vivecraft's **DUAL mirror mode**, which
renders the left and right eye side by side into the game's desktop window. This avoids
having to implement an OpenVR direct-mode frame-capture driver. A small virtual HMD driver
is still required to give SteamVR a display and to inject head/controller poses.

The chosen path has meaningful but bounded risks: OpenVR driver registration (S-01), mirror
capture quality (S-02), on-device hand tracking rate/accuracy (S-03), and end-to-end latency
(S-05). Each has a concrete spike and an explicit failure fallback. No hardware evidence
exists in this workspace; all runtime assumptions are marked UNVERIFIED in `AGENT.md` §11.

---

## 2. Method and evidence

This audit used:

1. **Source inspection** of the pinned Vivecraft tag
   [`1.21.11-1.3.15`](https://github.com/Vivecraft/VivecraftMod/tree/1.21.11-1.3.15)
   (commit `9f0a285123c8b53cd4f40d1a6f53b19ee0c8fc5f`).
2. **Source inspection** of current Vivecraft main (`Multiloader-26.2`) to check whether
   OpenXR support had landed; it has not.
3. **OpenVR SDK inspection** at v2.15.6 and the `simplehmd` driver sample, to confirm a
   virtual HMD can provide an `IVRDisplayComponent` and tracked controllers without direct
   mode.
4. **Platform capability check** with the installed Xcode 27.1 / visionOS 27 SDK:
   CompositorServices, ARKit hand/world tracking, VideoToolbox, Network.framework, and
   CryptoKit are available; no OpenXR/OpenVR runtime is present.
5. **Prior prototype review**: a native visionOS Minecraft prototype (Amethyst + custom
   Fabric stereo mod) exists in the archived repository history. It proved that Minecraft
   Java can be retargeted/run on visionOS with substantial JIT/framework work, but it is
   **not Vivecraft**, has no OpenVR, and does not satisfy the acceptance criteria. It is
   excluded from the new architecture.
6. **Documentation review** of Vivecraft/Vivecraft FAQ and the OpenVR driver API. No
   second-hand claim is used as acceptance evidence.

Source references that fixed the decision:

- Vivecraft OpenVR usage:
  `common/src/main/java/org/vivecraft/mixin/client_vr/lwjgl/OpenVRMixin.java` imports and
  initialises `org.lwjgl.openvr` interfaces (`VRSystem`, `VRCompositor`, `VRInput`, etc.).
- DUAL mirror: `common/src/main/java/org/vivecraft/client_vr/render/helpers/ShaderHelper.java`
  (pinned tag, lines ~377–398) blits `framebufferEye[0]` to the left half and
  `framebufferEye[1]` to the right half of `MC.mainRenderTarget` when
  `MirrorMode.DUAL` is selected. A source comment states "show both eyes side by side".
- Mirror modes: `VRSettings.MirrorMode` includes `DUAL` and `MIRROR_DUAL_SWAP`/crop settings.
- Default Index bindings:
  `common/src/main/resources/assets/vivecraft/input/knuckles_defaults.json` maps:
  right trigger → `key.attack`; right trackpad click → `key.use`; left thumbstick →
  `freemovestrafe`/jump; right thumbstick → `rotateaxis`; left A → inventory; left B →
  game menu/keyboard; grips → hotbar previous/next; right A → sneak; right B → radial menu.
- OpenVR `IVRDisplayComponent` (`openvr_driver.h`, v2.15.6) exposes
  `GetWindowBounds`, `GetRecommendedRenderTargetSize`, `GetEyeOutputViewport`,
  `GetProjectionRaw`, and distortion callbacks. The `simplehmd` sample shows a virtual HMD
  using this component and `TrackedDevicePoseUpdated`.
- SteamVR Input driver API exposes `CreateBooleanComponent`, `CreateScalarComponent`,
  `CreateSkeletonComponent`, and `UpdateSkeletonComponent` (`openvr_driver.h`).

**What the source inspection does not prove:** that SteamVR will accept our particular
driver, that Vivecraft's DUAL mirror is frame-complete in practice, that capture/encode
latency meets budget, or that hand gestures are usable. Those are spikes S-01/S-02/S-05/S-06.

---

## 3. What Vivecraft actually requires at runtime

### 3.1 Runtime stack

| Requirement | Evidence | Consequence for VRMC |
| --- | --- | --- |
| Minecraft Java Edition, pinned version, legally owned | Vivecraft downloads/README | User supplies; never bundled |
| Fabric/Forge/NeoForge loader matching the build | Vivecraft 1.3.15 supports fabric/forge/neoforge | Pin Fabric 1.21.11 profile |
| Java 21 (for 1.21.11) | `gradle.properties` `java_version=21` | User runtime |
| SteamVR installed and running | Vivecraft FAQ: "uses SteamVR to communicate with all hardware" | PC required |
| OpenVR runtime with HMD and controllers | `OpenVRMixin`, `MCOpenVR`, LuaJGL OpenVR natives | Virtual HMD + 2 controllers required |
| SteamVR Input action manifest/bindings | `knuckles_defaults.json`, `MCOpenVR` action sets | Synthetic components must map to these actions |
| GPU capable of PC VR; OpenGL renderer | Vivecraft FAQ | RTX-class GPU baseline |
| A display/mirror for debugging | Mirror modes (OFF/CROPPED/SINGLE/DUAL/...) | DUAL mirror is our video source |
| No OpenXR requirement | OpenXR PR is WIP/unmerged; README has unchecked OpenXR | Cannot rely on OpenXR on visionOS |

### 3.2 Why a native visionOS Vivecraft is infeasible for this project

visionOS:

- has **no OpenXR runtime** and no OpenVR/SteamVR runtime;
- does not allow loading the Windows OpenVR native library;
- does not provide a desktop OpenGL context (Metal only);
- restricts JIT and background execution;
- has no SteamVR Input action system.

A native path would therefore require:

1. Running Minecraft Java (JVM, LWJGL, OpenGL→Metal translation or a renderer rewrite) on
   visionOS — the archived prototype showed this is possible only with a large, fragile
   launcher/framework retargeting effort.
2. Replacing Vivecraft's OpenVR provider with a visionOS-native provider: HMD pose from
   ARKit/CompositorServices, controller input from hands, stereo rendering through
   CompositorServices, and reimplementing SteamVR Input action semantics.
3. Maintaining a fork of Vivecraft (LGPL) and integrating with Minecraft (proprietary) on an
   unsupported platform, across Minecraft/Vivecraft updates.

This is effectively a new VR backend plus a platform port. Effort is multi-engineer-quarter,
risk is extreme, and the result would no longer be "Vivecraft as shipped". It also conflicts
with Apple's JIT/platform constraints for a reproducible, release-quality app. **Rejected.**

### 3.3 Why remote streaming is feasible

- The PC runs the exact pinned Minecraft/Fabric/Vivecraft stack that millions of users run.
- SteamVR is designed to support third-party drivers; a virtual HMD with a display component
  and two controllers is a documented extension point.
- Vivecraft already renders both eyes into its desktop window in DUAL mode; no game patch is
  needed.
- visionOS has everything the client needs: ARKit hand/world tracking, CompositorServices
  stereo presentation, Metal, VideoToolbox hardware decode, Network.framework, CryptoKit.
- The network path is LAN-only; 70–100 Mbps HEVC at 90 Hz is routine on Wi‑Fi 6E.

The cost is latency and operational complexity (PC + SteamVR + network), which VRMC addresses
with timestamped input, prediction, late reprojection, and explicit failure recovery.

---

## 4. Architecture comparison

Scoring: 1 (worst) – 5 (best). Effort is rough engineer-months (EM) to a verified v1,
including tests/docs, assuming a small experienced team.

| Option | Description | Effort | Risk | Latency | Maintainability | Licensing | Score |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **A. Remote Vivecraft + DUAL mirror + virtual devices (chosen)** | Unmodified PC stack; virtual HMD/controllers; capture game window; hand-derived inputs | **8–12 EM** | Medium | 35–60 ms view (with reprojection) | Good: small, isolated driver; version-pinned | Clean arm's-length; no game/Vivecraft binaries | **23/25** |
| B. Remote Vivecraft + direct-mode driver frame capture (ALVR-style) | Driver owns eye textures and encodes them; no mirror capture | 14–20 EM | High | 25–45 ms (potentially best) | Hard: D3D11/OpenGL interop, direct mode, frame pacing, vendor quirks | Clean, but more complex | 16/25 |
| C. Native visionOS OpenXR runtime + OpenComposite + Vivecraft | Implement OpenXR runtime/loader on visionOS; translate OpenVR→OpenXR; port renderer | 30–60 EM | Extreme | Potentially excellent | Very poor: two huge compatibility layers, unmerged OpenXR Vivecraft | Contaminated/complex | 6/25 |
| D. Adapt ALVR/WiVRn client to visionOS | Reuse mature server/driver/protocol; write visionOS client + hand bridge | 10–16 EM | High | 35–60 ms | Mixed: inherit undocumented protocol/version churn; still need hand mapping | Apache/MIT mostly, but large third-party surface | 14/25 |
| E. Native Minecraft + custom stereo mod (archived prototype) | Run Minecraft locally via Amethyst; two-pass stereo; no Vivecraft | 6–10 EM (already partly built) | High (JIT, GPU, no Vivecraft) | Excellent | Poor: platform port, unsupported, no Vivecraft updates | GPL + Apple constraints | 10/25 and **fails requirement** |
| F. Remote desktop / virtual monitor | Stream a mono or SBS desktop; no head tracking or hands | 2–4 EM | Low | 40–80 ms | Good | Clean | Fails VR/hand acceptance |

### 4.1 Why option A beats B

Direct-mode capture would remove the desktop mirror and potentially save 1–2 frames. But it
requires a D3D11/OpenGL swapchain driver, correct eye texture submission, frame pacing, and
vendor-specific behaviour, and it risks breaking on SteamVR updates. Option A's DUAL mirror is
already implemented by Vivecraft, has "no performance penalty" per its documentation, and can
be captured with Windows Graphics Capture. The mirror adds desktop composition/capture
overhead, which we will measure; if it proves to be the dominant latency, option B is the
documented upgrade path (new ADR), not a prerequisite. This is the shortest viable path.

### 4.2 Why option A beats D

ALVR/WiVRn already solve streaming, but neither has a visionOS client. A client is the
largest single piece of work either way, and adapting an undocumented/evolving protocol plus
its server/driver would add a large dependency and obscure hand-input semantics. VRMC keeps
its own narrow protocol, driver, and mapping, which are testable and version-pinned. ALVR's
driver remains a useful reference for a future direct-mode option B.

### 4.3 Rejected alternatives: concrete triggers to revisit

- If S-01 shows a custom display-component driver cannot make Vivecraft render reliably,
  evaluate option B (direct mode) or a patched Vivecraft fork (LGPL, separate process).
- If S-02/S-07 shows DUAL mirror capture is unusable (tearing, missing eye, <60 fps), switch
  to option B or capture SteamVR's per-eye mirror via a supported API.
- If S-04/S-05 shows decode/render/latency cannot meet budgets at 90 Hz, reduce resolution or
  target 72 Hz; if still unacceptable, pivot to native OpenXR + a custom Vivecraft backend
  only with a new, fully funded plan.

---

## 5. Hand tracking feasibility

### 5.1 Platform capabilities (to be proven on device)

- ARKit `HandTrackingProvider` on visionOS provides hand anchors and a skeleton with 27 named
  joints, including wrist, thumb, index, middle, ring, and little finger chains, with
  transforms and tracked state. Both hands are supported simultaneously.
- `WorldTrackingProvider`/device anchor provides head pose in the same world space.
- `HandTrackingProvider` requires user authorisation; the app must handle denial and
  revocation.
- Update cadence is expected at display rate, but actual rate, jitter, latency, and accuracy
  must be measured on D1 (S-03). Simulator does not provide hand tracking.

### 5.2 Why virtual Index controllers

Vivecraft consumes SteamVR Input actions and controller poses. Emulating two `knuckles`
controllers:

- preserves Vivecraft's default bindings and two-handed gameplay without patching it;
- gives us trigger, grip, thumbstick, A/B, and trackpad components (the default mapping uses
  all of them);
- lets the client map hand gestures to controls while the PC remains policy-free;
- supports a future skeleton path: SteamVR's driver API can publish Index finger bones from
  ARKit joints, though Vivecraft 1.3.15 may not consume finger data. The client still uses the
  full skeleton for gesture recognition and future visual hands.

A companion Vivecraft mod was considered and rejected for v1: it would couple to Vivecraft
internals, require an LGPL derivative, and still need SteamVR for the HMD. It remains a
fallback for interactions the controller model cannot express.

### 5.3 Gesture mapping feasibility

The default mapping uses:

- right trigger: attack;
- right trackpad click: use;
- right thumbstick: turning;
- left thumbstick: movement + click jump;
- grips: hotbar previous/next;
- left A: inventory; left B: game menu/keyboard; right A: sneak; right B: radial menu.

Hand-derived mapping (detailed in `docs/architecture/HAND_MAPPING.md`):

- index-thumb pinch with hysteresis → trigger (attack/teleport/interact);
- middle-thumb pinch → trackpad click (use/place);
- full-hand fist/curl → grip (hotbar/grab context);
- palm-up left hand + thumb position/tilt → left stick (movement); closed hand exits;
- right palm-up/tilt → right stick (turning), or head-relative comfort turning;
- palm-to-face dwell → A/B chords for inventory/menu;
- index/offhand sequences → bow/shield.

This is feasible but human-factors risk is real (A-06). The mapping is a versioned profile
with tunable thresholds, a debug overlay, and a controller fallback. Manual tests HT-02..HT-19
decide acceptance.

---

## 6. Video and transport feasibility

### 6.1 Source and geometry

- DUAL mirror writes left eye to the left half and right eye to the right half of Minecraft's
  main render target. With the game window at 3840×1080, each eye is 1920×1080.
- The mirror is a blit of the eye framebuffers, not a lens-distorted compositor output. The
  client can present it with the virtual HMD's projection.
- Eye order can be swapped by `dualMirrorSwap`; the host must verify and normalise. Crop
  (`dualMirrorCrop`) must be 0 for full-FOV capture.
- If the game window is resized, the host detects and rejects or reconfigures; the client's
  `StreamConfig` must match the actual capture.

### 6.2 Latency chain (design estimate, not evidence)

| Stage | Budget | Notes |
| --- | --- | --- |
| Game render + mirror | 11.1 ms | 90 Hz frame; mirror blit |
| WGC capture + copy | 2–6 ms | GPU capture, NV12 conversion |
| NVENC | 4–8 ms | HEVC low-latency, no B-frames |
| Network | 2–10 ms | Wi‑Fi 6E, LAN |
| Decode | 3–8 ms | VideoToolbox |
| Compositor/display | 11.1 ms | 90 Hz scan-out |
| **View total** | **35–55 ms** | Before reprojection; late reprojection reduces perceived rotation latency |
| Input sample→driver | 5–25 ms | ARKit + UDP + prediction |
| Game tick/action | 0–50 ms | Minecraft 20 TPS; not controllable |
| Action feedback | 50–150 ms | Round trip; target P50 ≤150 ms |

These are engineering estimates to be replaced by measurements. A-05 and AC-4 explicitly
require measurement; the project may not claim latency compliance from this table.

### 6.3 Transport

- Control: reliable TCP (TLS-like authenticated session) for pairing, config, state, and
  keyframe requests.
- Media/input: UDP with ChaCha20-Poly1305, sequence numbers, replay window, MTU-safe
  fragmentation, NACK for incomplete frames, and IDR requests. Media is never retransmitted
  wholesale; only missing fragments are NACKed within a short window.
- Clock sync: NTP-style four-timestamp exchanges on the control channel, robust median filter,
  drift estimation, periodic refresh. Timestamps are captured as close to the sensor and
  display as possible.
- Prediction: constant-velocity/angular-velocity with damping and clamping; late-latching on
  the client for intent; driver extrapolation bounded to 30 ms.
- Jitter buffer: target 1 frame, max 3; drop oldest under pressure; never block the decode
  thread.
- Bandwidth: 70–100 Mbps HEVC baseline; ABR floor 30 Mbps; quality reduction before frame
  drops.

### 6.4 Codec/client feasibility

- VideoToolbox hardware HEVC/H.264 decode is available on visionOS; Annex-B NALs must be
  converted to `CMSampleBuffer`s with parameter sets. The simulator can validate the plumbing
  but not device performance.
- CompositorServices provides per-eye drawables and projections; Metal can sample the decoded
  eye textures. Rotation-only reprojection is feasible with a screen-space mesh; depth-based
  reprojection is deferred (ADR-0005).
- A 3840×1080 SBS stream at 90 Hz is within Vision Pro decode capability on paper; S-04 must
  prove it, including thermal behaviour.

---

## 7. Operational and platform feasibility

- **PC requirement:** Windows 11, SteamVR, NVIDIA RTX-class GPU, 32 GB RAM. This is a
  specialized but reasonable setup for PC VR users. The host is a normal user application;
  the driver is installed into SteamVR's `drivers` directory and can be removed cleanly.
- **Network:** LAN only by default; no cloud relay in v1. A 5 GHz/6E AP with the PC wired is
  the recommended topology. Wired headset is not possible on Vision Pro, so Wi‑Fi quality is
  the main environmental risk.
- **Setup complexity:** the user must install Minecraft/Fabric/Vivecraft/SteamVR themselves.
  Scripts and docs must make this reproducible without redistributing software. First-session
  target ≤60 minutes excluding downloads.
- **Distribution:** TestFlight/Ad Hoc for v1. App Store review is not assumed. The app uses
  only public APIs and declared permissions. Local-network and hand-tracking usage strings are
  mandatory.
- **Audio:** not required for acceptance; add Opus in v1.1 if latency allows.
- **Multiplayer:** works through Vivecraft/Minecraft servers; VRMC is transparent to
  networking. A local test server is part of the test plan.

---

## 8. Licensing, EULA, and compliance feasibility

| Component | License / terms | VRMC stance |
| --- | --- | --- |
| Minecraft Java | Proprietary EULA; user must own | No files/assets distributed; install guide uses official launcher/profile |
| Vivecraft | LGPL-3.0 | Unmodified, user-installed; integration via SteamVR public interfaces only; no linking/derivative |
| SteamVR/OpenVR | SteamVR EULA; OpenVR SDK BSD-3 | Driver uses public SDK; notices; user installs SteamVR |
| Fabric | Apache-2.0 | User installs loader; not bundled |
| NVIDIA NVENC | NVIDIA SDK license (redistributable headers/runtime via driver) | Dynamic load; notices; no NVIDIA binaries bundled |
| FFmpeg (if used) | LGPL/GPL depending on build | Prefer NVENC direct or LGPL dynamic build; notices; no GPL binaries in repo |
| visionOS SDK/Apple frameworks | Apple terms | Public APIs only; no private entitlements/JIT |
| VRMC code | Apache-2.0 | Our original code and docs |

No blocker found. Two obligations to enforce in release: (1) never commit Minecraft/Vivecraft
JARs or assets, (2) keep the driver/host at arm's length from Vivecraft code. A companion mod,
if ever added, must be LGPL-3.0 in a separate artifact and requires a new ADR.

---

## 9. Feasibility verdict and go/no-go

**Go** on option A, conditional on four spikes:

| Spike | Question | Go criterion | No-go / fallback |
| --- | --- | --- | --- |
| S-01 | Does SteamVR register our virtual HMD + controllers and does Vivecraft enter VR? | SteamVR device report shows devices; Vivecraft log shows VR init; rendered frame | Direct-mode driver (option B) or patched backend |
| S-02 | Is DUAL mirror capture complete/correct at target fps? | Both eyes present, correct order, no tearing, ≥72 fps, 10-min stable | Direct-mode capture or SteamVR mirror API |
| S-03 | Does Vision Pro hand tracking meet rate/accuracy/recovery targets? | ≥72 Hz/hand, 27 joints, no swaps, recovery ≤1 s | Controller fallback for v1, redesign input |
| S-05 | Can view M2P meet N1 target with reprojection? | P50 ≤50 ms, P95 ≤70 ms | Reduce resolution/fps, optimize, or quantified waiver |

S-04 (decode/render), S-06 (gesture usability), S-07 (capture), S-08 (SteamVR Input), S-09
(crypto), S-10 (display), S-11 (clock), S-12 (FOV/IPD) are secondary go/no-go items for their
phases.

**This audit does not constitute acceptance evidence.** It supports the architecture decision
only. Hardware/runtime spikes must be recorded in `VERIFY.md` §9 before M3/M4 can pass.

---

## 10. Estimated plan impact

- **M0–M1 (docs, client core, simulator):** 3–5 EM. Largely verifiable in this workspace.
- **M2 (device hand tracking/gestures):** 2–3 EM, requires D1.
- **M3 (driver/host/capture/Vivecraft):** 3–4 EM, requires P1/SteamVR.
- **M4 (end-to-end gameplay/latency/recovery):** 2–3 EM, requires D1+P1+N1.
- **M5 (hardening/release):** 2 EM.
- **Total:** 12–17 EM with hardware access; 8–12 EM if much of M1/M3 is reused from mature
  components. The estimate excludes Minecraft/Vivecraft installation and legal review.

The critical path is S-01/S-02 on the PC, because they determine whether the video path is
viable. They must be run before investing in M3 polish or M4 tuning.

---

## 11. Assumptions that remain unverified

See `AGENT.md` §11.1 for the canonical list. The most important are:

- A-01 SteamVR accepts the virtual HMD/controller driver and Vivecraft enters VR.
- A-02 DUAL mirror is frame-complete and correctly ordered in practice.
- A-03 Vision Pro hand tracking meets rate/accuracy targets in immersive apps.
- A-04 HEVC decode + CompositorServices sustains 90 Hz at target resolution.
- A-05 View M2P target is achievable with rotation-only reprojection.
- A-06 Gesture mapping is usable and comfortable.
- A-11 Clock sync within ±2 ms on Wi‑Fi 6E.

No acceptance claim may rely on these assumptions until the corresponding evidence is in
`VERIFY.md`.

---

## 12. References

- Vivecraft repository, tag `1.21.11-1.3.15`, commit
  `9f0a285123c8b53cd4f40d1a6f53b19ee0c8fc5f`:
  - `common/src/main/java/org/vivecraft/mixin/client_vr/lwjgl/OpenVRMixin.java`
  - `common/src/main/java/org/vivecraft/client_vr/render/helpers/ShaderHelper.java`
  - `common/src/main/java/org/vivecraft/client_vr/settings/VRSettings.java`
  - `common/src/main/resources/assets/vivecraft/input/knuckles_defaults.json`
  - `gradle.properties`, `LICENSE.md`, `README.md`
- Vivecraft FAQ: <https://www.vivecraft.org/faq/> (SteamVR requirement, mirror modes).
- OpenVR SDK v2.15.6: `headers/openvr_driver.h` (`IVRDisplayComponent`,
  `IVRServerDriverHost::TrackedDevicePoseUpdated`, input component APIs) and
  `samples/drivers/drivers/simplehmd`.
- Apple visionOS 27 SDK: ARKit `HandTrackingProvider`, `WorldTrackingProvider`,
  CompositorServices `LayerRenderer`, VideoToolbox, Network.framework, CryptoKit.
- Prior native prototype: archived Git history (`docs/ARCHITECTURE.md` on the pre-VRMC
  branch); not part of the selected architecture.
