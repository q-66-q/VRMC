# M3b — CompositorServices reprojection validation probe (visionOS simulator)

Standalone visionOS SwiftUI app (WindowGroup + immersive `CompositorLayer`, dedicated layout,
rgba16Float, foveation off) that reproduces the **exact** reprojection pipeline of
`runtime/native-shell/Sources/VRMCCompositor.mm` and measures whether its math can explain the
EV-0086 device symptom ("immersive completely black although the compositor samples both provider
eye textures").

**Status: run 2026-11-01 on the booted visionOS 27.0 simulator (`VRMC-VP`, UDID
F025E133-019D-4811-944F-F3C8226E14CB). This is simulator code/convention evidence only — NOT
product/device evidence (AGENT.md §9).** Findings: [`results/report.md`](results/report.md).

## What it does

1. Dedicated render `NSThread` (Apple CompositorServices C-sample pattern): predict timing →
   start/end update → wait optimal input time → start submission → query drawable → render →
   `cp_drawable_encode_present` → commit → end submission.
2. First frame, logs:
   - `cp_layer_renderer` configuration (color/depth format, layout, foveation, default depth range),
   - drawable view/texture/rate-map counts, depth range,
   - `cp_view_texture_map` (texture index, slice, viewport), color/depth texture properties,
   - `cp_view_get_transform` and `cp_drawable_compute_projection(drawable, right_up_back, i)` (all rows),
   - derived `(left,right,down,up)` tangents from `simd_inverse(projection)` and a cross-check
     against the deprecated `cp_view_get_tangents`,
   - the exact CPU ray→UV math of `VRMCCompositor.mm` for NDC centre, 4 corners and a 33×33 grid:
     `d.z` histogram, behind-camera count, provider-UV min/max, in-range %, NaN count,
   - the same diagnostics again for the **EV-0086 device views**, reconstructed from the device log
     (`tangents + pos + fwd`; roll assumed 0 with ±20° sensitivity reported).
3. Builds a synthetic 1024×1024 provider eye texture (checker + distinct corner colours + centre
   crosshair + asymmetric "T" marker; rgba8unorm) and renders it through the **verbatim** fragment
   shader copied from `VRMCCompositor.mm`, plus:
   - `f_reproj_debug` — early-outs colour-coded (magenta = provider-UV outside [0,1], cyan = ray
     behind camera, sampled = texture),
   - `f_reproj_alpha1` — identical maths but forces alpha=1,
   - `f_flat` — the old flat fullscreen sampler as a control.
4. Renders these variants offscreen (512×512) **and** into the real drawable (3840×2160 simulator),
   blit-reads the colour texture back, validates 25 probe pixels per image against an independent
   CPU reference of the same math (bilinear pattern sample, branch colours), and writes small PNGs +
   `results/summary.txt` to the app `Documents/`.
5. Tests claimed contributing factors: depth attachment on/off, rasterization-rate-map on/off,
   `cp_view_texture_map` index/viewport, forced alpha=1, alpha=0 provider texture (with periodic
   phase cycling so simulator screenshots can be compared), black provider texture.
6. Also reconstructs the EV-0086 two-eye case on the GPU (off-screen) so the device reprojection
   result is observable without the device.

## Build / run

Prereqs: Xcode 27.x with the visionOS 27 simulator, `xcodegen`, booted simulator.

```bash
cd runtime/probes/m3b-reproj
xcodegen generate

# build (full build output goes to /tmp, not the repo)
xcodebuild -project M3BProbe.xcodeproj -scheme M3BProbe -configuration Debug \
  -destination 'platform=visionOS Simulator,id=F025E133-019D-4811-944F-F3C8226E14CB' \
  -derivedDataPath /tmp/m3b-build CODE_SIGNING_ALLOWED=NO build

# install + launch (the app auto-opens the immersive space; no interaction needed)
UDID=F025E133-019D-4811-944F-F3C8226E14CB
APP=/tmp/m3b-build/Build/Products/Debug-xrsimulator/M3BProbe.app
xcrun simctl uninstall $UDID dev.vrmc.m3b 2>/dev/null || true
xcrun simctl install $UDID "$APP"
xcrun simctl launch $UDID dev.vrmc.m3b

# wait for Documents/m3b-done.txt (run takes ~25 s), then pull artifacts
C=$(xcrun simctl get_app_container $UDID dev.vrmc.m3b data)
cp "$C/Documents/m3b.log" results/m3b.log
cp "$C/Documents/results/"*.png "$C/Documents/results/summary.txt" results/
```

`scripts/run-sim.sh` wraps the build/install/run/pull cycle.

## Files

| Path | Contents |
|---|---|
| `project.yml` | xcodegen project (bundle `dev.vrmc.m3b`, deployment visionOS 27.0) |
| `Sources/M3BProbeApp.swift` | SwiftUI shell: `WindowGroup` + `ImmersiveSpace` + `CompositorLayer`, auto-opens the space |
| `Sources/ReprojRenderer.mm` | render thread, MSL shaders (verbatim `fmain` copy), CPU-ray diagnostics, EV-0086 reconstruction, offscreen/drawable tests, readback + PNG writer |
| `Sources/Bridging.h` | C bridge declaration |
| `results/report.md` | findings, numbers, interpretation, recommended device instrumentation |
| `results/m3b.log` | full probe log of the run |
| `results/*.png` | small readback images (offscreen + drawable) and simulator screenshots |

## Limitations

- The simulator drawable has **one view** (Apple: "you typically render only one view in
  Simulator"), with an **identity view transform** and a symmetric 16:9 projection. It validates the
  projection/NDC conventions, ray→UV formula, shader/texture sampling, drawable/present mechanics and
  the EV-0086 reconstruction, but it does not exercise the device's stereo asymmetric views.
- Device-case numbers are reconstructed from the EV-0086 log (tangents + pos + fwd); the view roll is
  unknown. Coverage is stable at 87.9–89.7 % for roll in [-20°, +20°]; the reconstruction assumption
  is stated in the report.
- The simulator's compositor is not the device compositor: alpha handling, lens reprojection and
  passthrough compositing can differ. Do not claim device status from this probe.
