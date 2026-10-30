# ADR-0005 — CompositorServices stereo rendering with rotation-only late reprojection in v1

- **Status:** Accepted
- **Date:** 2026-10-29
- **Related:** ADR-0001, ADR-0002, `docs/architecture/STREAMING.md`
- **Verification:** S-04, S-05, S-12 (NOT RUN)

## Context

The visionOS client receives a side-by-side stereo frame produced by Vivecraft's virtual HMD.
To be comfortable, it must present each eye with the correct projection at the display's
refresh rate, and reduce the visible effect of network/decode latency. Options:

- Display the SBS frame on a flat/world-anchored screen (simple, but not immersive VR and
  wrong scale).
- Render each eye texture full-screen with the capture projection, optionally reprojecting
  for head motion since capture.
- Render with per-pixel depth and full pose reprojection (best latency hiding, but requires a
  depth buffer from the PC, which the mirror does not provide).

The PC mirror does not contain depth or motion vectors. Shipping a depth channel would require
a second render target/capture path and more bandwidth/complexity, and would still be an
estimate due to transparency and disocclusion.

## Decision

Use **CompositorServices + Metal** to render each eye's half of the decoded SBS texture
full-screen in a dedicated `LayerRenderer` immersive space.

- The host sends `StreamConfig` with per-eye projection (left/right/top/bottom tangents), eye
  offsets/IPD, capture resolution, display frequency, and eye order.
- The renderer reconstructs the capture view rays and maps them to the current eye drawable's
  projection. A full-screen triangle/mesh samples the eye texture; no world-anchored screen.
- For frames older than the present time, apply **rotation-only reprojection**: rotate the
  capture-time head orientation to the predicted present orientation around the eye, then
  project through the drawable's projection. Translation is not reprojected in v1.
- The client uses the newest decoded frame (late latching) and requests an IDR when the
  frame is incomplete/invalid. It does not wait for a perfect frame.
- Foveation is disabled initially for predictable sampling; it may be enabled after visual
  verification. Color format is `rgba16Float` (or the validated drawable format); video is
  decoded to a color-managed texture with correct sRGB handling.
- A diagnostic mode can show the raw SBS frame, eye boundaries, and metadata overlay to
  validate orientation/order.

Depth-based reprojection is deferred. It requires a depth/motion channel from the PC, new
protocol fields, and additional GPU/bandwidth budget. It is an optimization, not a v1
prerequisite, provided rotation-only reprojection meets the comfort and latency targets.

## Consequences

### Positive

- True per-eye immersive rendering with correct scale/FOV, unlike a virtual monitor.
- Rotation-only reprojection removes most head-rotation latency without depth data.
- Simple, robust render path; no depth disocclusion artifacts.
- Works with the existing DUAL mirror and avoids a second capture channel.
- Easier to validate: projection math and eye mapping are unit-testable.

### Negative

- Head **translation** is not reprojected; fast positional movement or walking can show
  latency/parallax error. Vision Pro users often move their head within a small volume; the
  error is bounded but must be measured.
- Late frames near the edge of the FOV may show stretching/occlusion when reprojected.
- Requires accurate capture-time head pose and projection metadata from the PC; errors cause
  discomfort.
- Rotation-only reprojection cannot hide game-render latency for moving objects; only view
  latency improves.
- FOV/IPD mismatch between the virtual HMD and Vision Pro optics can cause scale discomfort;
  S-12 must calibrate.

### Neutral

- The client does not try to reproduce SteamVR lens distortion; it maps raw eye images to the
  Vision Pro display projection.
- If depth reprojection is added later, the protocol can add an optional depth stream without
  breaking v1 clients.

## Implementation requirements

- Validate `StreamConfig` on every connect and on change; reject mismatched resolution/aspect.
- Use `LayerRenderer.Drawable` per-eye transforms and projections; never assume a fixed
  orientation.
- Handle vertical flip, eye swap, sRGB/linear, and alpha correctly; test with asymmetric
  content (left half red, right half blue) plus real gameplay.
- Clamp reprojection angles and timestamps; never extrapolate beyond 100 ms; on invalid pose,
  fall back to the capture pose (no crash).
- Unit-test projection/reprojection math at identity, yaw/pitch/roll extremes, and FOV edges.
- Measure view M2P with and without reprojection; report both.

## Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| World-anchored stereo screen | Not immersive VR; wrong scale/parallax; fails acceptance. |
| Mono screen | Fails stereo/VR requirement. |
| Full depth reprojection | Requires depth/motion data not present in DUAL mirror; adds protocol/bandwidth/complexity; defer. |
| Timewarp with mesh warp per eye and no projection metadata | Cannot guarantee geometry; discomfort risk. |
| SteamVR-style lens distortion | Vision Pro compositor handles optics; applying PC distortion would be wrong. |

## Verification

- AT-RENDER-01/02 math tests.
- S-04 decode/render benchmark on D1.
- MT-03 visual geometry, MT-09 latency with/without reprojection, MT-07 comfort.
- If rotation-only reprojection is insufficient, evaluate depth channel in a new ADR.
