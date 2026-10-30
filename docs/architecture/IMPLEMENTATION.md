# Implementation Map

This is the as-built map for the current repository. Architecture decisions and acceptance
criteria remain in the ADRs, `AGENT.md`, and `VERIFY.md`.

## Runtime

```text
D1 visionOS
  ARKitSession(HandTrackingProvider, WorldTrackingProvider)
    └─ HandTrackingService ──▶ HandSnapshot (27 joints, world space)
          └─ TrackingCalibration ──▶ SteamVR-like standing frame
                └─ GestureRecognizer ──▶ HandSignals
                      └─ ControllerMapper ──▶ IntentInput L/R
  FrameAssembler ◀─ UDP video/meta ─ FrameStore ──▶ VideoDecoder ──▶ CVMetalTexture
       └─ request NACK/IDR ──▶ UDP
  TCP control (HELLO/WELCOME/config/clock/telemetry)
  CompositorServices StereoRenderer (rotation-only reprojection)

P1 Windows
  vrmc_host
    TCP control + UDP input ◀── client
    IpcWriter ──▶ driver_vrmc (seqlock shared memory)
    WGC capture ──▶ NVENC ──▶ fragmenter ──▶ UDP video/meta
  SteamVR
    driver_vrmc: VRMC Virtual HMD + 2 knuckles controllers
    Minecraft/Fabric/Vivecraft (unmodified): DUAL mirror window
```

## Client files

| File | Responsibility |
| --- | --- |
| `client/Sources/VRMCore/ProtocolBase.swift` | Magic/version/header/flags/enums |
| `ControlMessages.swift` | control payload structs, encode/decode, validation |
| `MediaProtocol.swift` | media headers, frame meta, NACK/IDR, reassembly |
| `InputProtocol.swift` | head/hand/intent payloads, datagram parse |
| `Time.swift` | monotonic timestamps, clock offset/RTT estimator |
| `Math.swift` | vectors/quaternions/projection/reprojection math |
| `HandModel.swift` | 27-joint skeleton, features, controller pose |
| `GestureRecognizer.swift` | pinch/fist/palm/dwell hysteresis, rearm |
| `ControllerMapping.swift` | intent, sticks, buttons, menu, locomotion |
| `TrackingCalibration.swift` | ARKit world → standing frame |
| `Prediction.swift` | one-euro, velocity, bounded prediction |
| `SessionStateMachine.swift` | connect/degrade/reconnect/stop transitions |
| `Telemetry.swift` | latency percentiles, counters, CSV |
| `Transport.swift` | TCP control and single-socket UDP |
| `VRMCVideo/` | Annex-B parser + VideoToolbox decoder |
| `VRMCApp/` | SwiftUI shell, ARKit adapter, session coordinator, mock demo, Metal renderer |
| `VRMCApp/StereoReproject.metal` | full-screen per-eye sampling/reprojection |

## Bridge files

| File | Responsibility |
| --- | --- |
| `bridge/core/include/vrmc/protocol.hpp` + `src/protocol.cpp` | portable wire codec |
| `bridge/core/include/vrmc/clock.hpp` | C++ clock estimator parity |
| `bridge/core/include/vrmc/pose.hpp` | quaternion/prediction math |
| `bridge/core/include/vrmc/ipc.hpp` + `src/ipc.cpp` | seqlock shared-memory snapshot |
| `bridge/driver/src/driver.cpp` | OpenVR provider, virtual HMD/display, controllers/input |
| `bridge/host/src/main.cpp` | Windows control/input/IPC/video orchestration |
| `bridge/host/src/win_capture.*` | WGC window capture |
| `bridge/host/src/nvenc_encoder.*` | NVENC HEVC/H.264 low-latency encode |
| `bridge/host/src/file_source.*` | pre-encoded test source for control-path tests |
| `bridge/driver/resources/` | manifest + knuckles input profile |

## Tooling

| File | Responsibility |
| --- | --- |
| `protocol/tools/reference_codec.py` | authoritative Python codec |
| `protocol/tools/generate_vectors.py` | committed conformance vectors |
| `tools/mock_host/mock_host.py` | insecure simulator host + input audit |
| `tools/diagnostics/latency_report.py` | telemetry CSV percentiles |
| `scripts/*` | build/test/demo/evidence/release |
