# M3b compositor shader unit test (EV-0086 follow-up)

Purpose: prove, without a headset, that the reprojection shader in
`runtime/native-shell/Sources/VRMCCompositor.mm` is correct on Metal with a CompositorServices-like
per-eye frustum, so the black immersive from EV-0086 is narrowed to either (a) runtime matrices whose
conventions differ from the logged tangent-derived assumption (now printed CPU-side by the compositor)
or (b) a black/never-rendered provider eye texture (now measured by the compositor's 32x32 centre
readback).

The test extracts the shader **from the shipping .mm file** (no copy that can drift), compiles it with
the macOS Metal runtime compiler, builds the reprojection/flat/test pipelines, renders into an
offscreen RGBA8Unorm target sampled from a synthetic "provider eye" texture that encodes its own UV in
R/G, and compares 81 on-screen samples against a CPU port of the same ray->UV math. It also checks the
flat control and the procedural test pattern are not black.

Synthetic per-eye frustum uses the EV-0086 device log tangents
(left/right/down/up = -1.732 / +1.000 / -1.192 / +1.000), a 110 deg symmetric provider frustum
(±tan 55 deg = ±1.428) and an eye offset from the logged view transform.

Run: `runtime/probes/m3b-shader-test/run.sh`

Result at EV-0087 (2026-11-01, M4 Pro, Xcode 27.2): MSL compiles, all pipelines build, 81/81 CPU-vs-GPU
samples match (max error 0.0022, linear-filter tolerance), flat control centre = (128,128,0), test
pattern centre = (255,51,51). This is **code validation, not device evidence** (AGENT.md §9): the
simulator/macOS cannot prove visionOS presentation, stereo optics or tracking.

Note: the offline `metal` compiler is not installed on this host (`xcodebuild -downloadComponent
MetalToolchain`); the test uses the runtime compiler (`newLibraryWithSource`), which is the same
compiler the compositor uses on device.
