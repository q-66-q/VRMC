# visionOS Client

## Layout

```text
Package.swift              VRMCore + VRMCVideo libraries and tests
Sources/VRMCore/           pure Swift: protocol, math, clock, prediction, hands,
                           gestures, mapping, session, telemetry, sockets
Sources/VRMCVideo/         Annex-B parser + VideoToolbox decoder
Sources/VRMCApp/           SwiftUI shell, CompositorServices/Metal renderer,
                           ARKit tracking, session coordinator, simulator demo
Tests/                     XCTest + conformance vectors + H.264 decode fixture
project.yml                XcodeGen app definition (the source of truth)
VRMC.xcodeproj             generated; commit when project.yml changes
```

## Build

```bash
swift build
swift test
xcodegen generate
xcodebuild -project VRMC.xcodeproj -scheme VRMC -configuration Debug \
  -destination 'platform=visionOS Simulator,name=VRMC-VP' build
```

Or from the repository root: `./scripts/build_client.sh --simulator` / `--device`.

## Runtime data flow

`ARKitSession(HandTracking + WorldTracking)` → `HandSnapshot` → `TrackingCalibration` →
`GestureRecognizer` → `ControllerMapper` → timestamped UDP INTENT/HAND/HEAD datagrams.
Video: UDP fragments → `FrameAssembler` → `VideoDecoder` → `CVMetalTexture` →
CompositorServices per-eye drawable with rotation-only reprojection.

## Permissions

The app requires Hand Tracking, World Sensing, and Local Network usage strings (see
`Sources/VRMCApp/Info.plist`). Denial is handled without a crash; the UI explains what is
missing. The simulator uses synthetic hands and does not exercise ARKit.

## Current limitations

The development build uses an insecure transport and has no device evidence. See
[`../docs/user/LIMITATIONS.md`](../docs/user/LIMITATIONS.md) and
[`../VERIFY.md`](../VERIFY.md). Do not treat a simulator run as device acceptance.
