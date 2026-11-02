# M3b — CompositorServices reprojection validation (visionOS simulator) — findings

**Run:** 2026-11-01, booted visionOS 27.0 simulator `VRMC-VP`
(`F025E133-019D-4811-944F-F3C8226E14CB`), Xcode 27.2, probe bundle `dev.vrmc.m3b`.
**Purpose:** determine whether the EV-0086 device symptom (immersive completely black although
`eyes=1`, `anchor=1`) can be explained by the compositor's reprojection math / Metal pass setup,
or whether it points at the provider eye textures.

**Status: simulator code/convention evidence, NOT product/device evidence (AGENT.md §9).**

Question: **is the black (a) wrong projection/view conventions or UV math, or (b) invalid/black
provider eye textures (or compositing/alpha)?**

Answer from this probe: **(a) is refuted.** The exact VRMCCompositor.mm math, shader, and drawable
pass reproduce/validate correctly on the simulator, and with the EV-0086 device view matrices
reconstructed from the device log the same math maps **87.88 % of each eye's pixels inside** the
provider ±55° frustum with **0 rays behind the camera, 0 NaN** and only a ~12 % outer-edge border
outside. A valid non-black provider texture would therefore show a mostly-visible image, not black.
The remaining candidates are on the provider/compositing side: (b1) black/empty eye textures at
sampling time (not yet synced / not the image actually rendered / wrong image), or (b2) compositing
(tested here only in the simulator: alpha and pass parameters do not cause black there).
See "Recommended device instrumentation" for the one-run discriminator.

---

## Environment measured (simulator drawable)

| Item | Value |
|---|---|
| views | **1** (Apple: "you typically render only one view in Simulator") |
| drawable color textures | 1, **3840×2160**, MTLPixelFormat 115 = `RGBA16Float`, type 2D |
| depth textures | 1, format 252 = `Depth32Float`, depth range far=`inf` near=`0.1` |
| rasterization-rate maps | **0** (foveation disabled, same as the production shell config) |
| `cp_view_texture_map` | texIndex=0, slice=0, viewport=(0,0,3840,2160) — full texture |
| `cp_view_get_transform`, rows [right; up; back; pos] | `(1 0 0 0) (0 1 0 0) (0 0 1 0) (0 0 0 1)` (identity) |
| `cp_drawable_compute_projection(right_up_back)`, rows | `(1 0 0 0) (0 1.777778 0 0) (0 0 0 0.1) (0 0 -1 0)` |
| derived tangents from `simd_inverse(P)` (l/r/d/u) | `(-1.0000, 1.0000, -0.5625, 0.5625)` (symmetric 16:9) |
| `cp_view_get_tangents` (deprecated, cross-check) | `(1.0000, 1.0000, 0.5625, 0.5625)` → matches derived exactly |

Convention consequences (verified numerically): `right_up_back` NDC has **+x = right**, **+y = up**,
forward = **−z**, and `cp_view_get_transform` is **view→device** (matches Apple's header:
"a transform matrix to the device coordinate space from the view coordinate space"). Inverting the
projection at NDC z=0.5 is safe (z=0 would divide by w=0 when far=∞). The reconstructed
view-transform check against the real matrix gave `max|R_recon − R_real| = 0.000000` on the
simulator (the simulator transform is identity, so this only validates the method).

## CPU ray→UV diagnostics — exact VRMCCompositor.mm math

Grid = 33×33 NDC samples; `st` = provider tangents `±tan(55°) = ±1.4281` (EV-0086 L=R).

| Case | behind | OOB | inside | NaN | t.x range | uv.x range | uv.y range |
|---|---|---|---|---|---|---|---|
| simulator live view 0 | 0 % | 0 % | **100.00 %** | 0 % | [-1.000, 1.000] | [0.150, 0.850] | [0.303, 0.697] |
| EV-0086 **L** (reconstructed) | **0 %** | 12.12 % | **87.88 %** | **0 %** | [-1.753, 1.016] | [-0.114, 0.856] | [0.140, 0.906] |
| EV-0086 **R** (reconstructed) | **0 %** | 12.12 % | **87.88 %** | **0 %** | [-1.010, 1.773] | [0.146, 1.121] | [0.137, 0.906] |

- `d.z` is **negative for every sample** in every case (simulator −0.200; device reconstruction
  −0.0196…−0.0204, i.e. in front of the camera). The `d.z > -1e-4` behind-camera early-out is never
  taken. **The EV-0086 "all rays outside the provider frustum or behind the camera" hypothesis is
  refuted.**
- Device-eye centres map to provider UV L=(0.372, 0.529), R=(0.629, 0.528): correct per-eye mapping of a
  head-aligned symmetric provider render (no mirror / no eye swap implied by the math).
- The ~12 % out-of-frustum region is at each eye's outer edge (each drawable view's frustum is wider
  than the provider's 110° FOV there), i.e. a black border at the frame edges — not a black frame.
- Roll sensitivity (device log has no roll; view rebuilt from pos/fwd): coverage 88.52 % / 87.88 % /
  89.72 % (L) and 89.35 % / 87.88 % / 87.88 % (R) for roll −20°/0°/+20°. The opposite
  view-transform convention (device→view) gives the **same** 87.88 % because the device view rotations
  are ≈ identity (fwd ≈ (0.001, 0.014, −1.000)); the convention question is not discriminative here,
  but the derived-tangent/x-sign cross-checks above are consistent with Apple's documented convention.

Reconstructed EV-0086 matrices (used for the off-screen render; the Lead can reuse them):

    L: projection rows (0.732064 0.000000 -0.267936 0.000000) (0.000000 0.912409 -0.087591 0.000000)
                       (0.000000 0.000000 0.000010 0.010000) (0.000000 0.000000 -1.000000 0.000000)
       transform rows  (0.999999 -0.000014 -0.001000 -0.034900) (0.000000 0.999902 -0.013999 -0.027200)
                       (0.001000 0.013999 0.999901 0.004500) (0.000000 0.000000 0.000000 1.000000)
    R: projection rows (0.732064 0.000000 0.267936 0.000000) (0.000000 0.912409 -0.087591 0.000000)
                       (0.000000 0.000000 0.000010 0.010000) (0.000000 0.000000 -1.000000 0.000000)
       transform rows  (0.999996 -0.000048 -0.003000 0.030000) (0.000000 0.999872 -0.015998 -0.025100)
                       (0.003000 0.015998 0.999868 0.002500) (0.000000 0.000000 0.000000 1.000000)
    (projection rebuilt from the logged tangents with near=0.01/far=1000; ray directions are
     independent of near/far, so this does not affect the UV results.)

## GPU: does the exact shader reproduce the synthetic provider image?

The fragment shader in the probe is a **verbatim copy** of `VRMCCompositor.mm`'s `fmain` (same
`ViewParams` layout, same `invProjection`/`viewToDevice`/`sourceTangents`, same math and early-outs).
Every image below was blit-read back and compared against an independent CPU reference of the same math
at 25 probe pixels (bilinear texture sample; branch colours for the debug variant).

| Image (artefact) | Result |
|---|---|
| `offscreen-live-view0-reproj` | 25/25 probes PASS, maxAbsErr 0.0005 |
| `offscreen-live-view0-fullpattern-reproj` (source tangents = view's own → whole pattern) | 25/25 PASS, maxAbsErr 0.0004 — all corner colours, T marker and crosshair reproduce |
| `offscreen-device-L-reproj`, `-R-reproj` | 25/25 PASS, maxAbsErr 0.0011 / 0.0014 |
| `offscreen-device-L-flat`, `-R-flat` (control) | 25/25 PASS, maxAbsErr 0.0004 |
| `drawable-01-reproj-depth` (**presented drawable**, EV-0086 pass variant) | 25/25 PASS, maxAbsErr **0.0002** |
| `drawable-03-flat-depth` (control) | 25/25 PASS, maxAbsErr 0.0009 |

The off-screen EV-0086 images show the expected result of the current shader given a valid provider
texture: ~88 % of the frame sampling the image, a black band only on the outer edge
(`offscreen-device-L-reproj.png`; the debug variant paints that band magenta:
`offscreen-device-L-debug.png` — magenta 10.95 % L / 11.38 % R, **cyan (behind-camera) 0 %**).
No eye-swap/vertical-flip is visible: the pattern's red top-left block is at the top-left of the
mapped region, and the reconstructed L/R images sample the expected left/right parts of the image.

The exact shader with an **all-black provider texture** outputs opaque black over 100 % of the
frame (`offscreen-live-view0-black-texture-reproj-alpha1.png`), i.e. the shader faithfully reproduces
the EV-0086 symptom when the input image is black. This is why device-side texture readback is the
discriminator (below), not more shader review.

## Drawable pass setup — what matters (EV-0086 attachment variant)

The presented drawable was rendered with the exact EV-0086 pass: rgba16Float colour +
depth32Float attachment (`loadAction=clear`, `storeAction=store`, `clearDepth = 0.0` = reverse-Z ∞),
foveation off (no rasterization-rate map; the simulator reports 0 rate maps), clear colours red/green
(as VRMCCompositor does), then `cp_drawable_encode_present` + commit.

Readback of that drawable is **byte-identical** (md5 `ff51178ed97a605fd38353f91e89cfd1`) across
`drawable-01-reproj-depth`, `drawable-04-reproj-nodepth`, `drawable-07-reproj-norrm`,
`drawable-08-reproj-final`: **the depth attachment (and its clearDepth=0.0), the missing
rasterization-rate map, and the pass ordering make no difference to the rendered colour.** The
reproj path with the EV-0086 attachment variant renders and presents correctly. (The drawable colour
texture is what the compositor consumes; this is not a claim about the device lens pipeline.)

## Presented vs off-screen (explicit)

The presented screen was captured from the host with
`xcrun simctl io F025E133-019D-4811-944F-F3C8226E14CB screenshot <file>.png` during known phases
(the app logs `PHASE <n> name=... frame=... t=<CFAbsoluteTime>`; host screenshots are timestamped and
mapped to phases by converting `CFAbsoluteTime + 978307200` to unix time).

- The presented immersive view is the **drawable content 1:1**: measured grid-line spacing in the
  720×405 capture is 64.4 px (uniform, square) → 343.5 px at 3840, which equals the drawable's checker
  period (343 px); 11.2 columns × 6.3 rows visible, which matches the reproj crop exactly
  (uv.x span 0.7002 × 16 cells, uv.y span 0.394 × 16 cells).
- Brightness matches a linear→sRGB display transform of the drawable values: drawable checker
  luminance 0.157/0.314 → sRGB 111/152; measured capture cell luminance 152 and line 254.
- The presented drawable for the depth-attachment reproj path therefore matches the synthetic pattern
  (grid + centre crosshair) exactly as read back. The app's SwiftUI window remains visible in the
  centre (simulator window chrome, not part of the drawable).
- The early capture sequence shows room/window → dark transition → pattern at ~5 s, i.e. the
  CompositorLayer/immersive/present path works in the simulator.

## Alpha / compositing experiment (does the compositor honour drawable alpha?)

**Method:** the probe cycles three phases (150 frames ≈ 3 s each) while the host takes a screenshot
every ~0.45 s:
- phase 0 `normal-alpha255` — exact reproj shader on an alpha=255 synthetic eye texture
  → drawable alpha = 1.0 (readback shows alphaLow 0 %);
- phase 1 `alpha0-texture` — same RGB, eye texture alpha=0
  → exact reproj shader forwards alpha → drawable alpha = 0.0 (readback alphaLow **100 %**);
- phase 2 `alpha1-forced` — alpha=0 texture but `f_reproj_alpha1` forces alpha=1 (readback alpha 1.0).

**Result:** full-resolution 3840×2160 captures of phase 0 and phase 1 are **pixel-identical**
(`PIL.ImageChops.difference` bbox = `None`, per-channel extrema `(0,0)`); phase 2 is identical as
well. The presented immersive image is unchanged when the drawable alpha is 0.

**Conclusion:** in the **simulator** full-immersion compositor, drawable alpha is **not** used — an
alpha=0 provider eye texture would show the RGB content, not a transparent/black layer. Forcing
alpha=1 (already done in the new compositor) is therefore **not load-bearing in the simulator**, and
this particular mechanism cannot explain EV-0086 *if* the device compositor follows the same
CompositorServices contract. This is a simulator-only conclusion; the device compositor is a
different implementation, so a cheap device-side re-test is still worthwhile (a flag that forces
alpha=1 vs forwards it, one run). Note the readback proves the drawable alpha *does* follow the
provider texture alpha, so the provider's alpha channel is worth logging on device.

## Recommended device instrumentation (concrete, one run discriminates (a) vs (b))

The compositor math is validated; the missing evidence is entirely on the device. Suggested patch to
`runtime/native-shell/Sources/VRMCCompositor.mm` (all behind a Documents flag file so the shipping
path is unchanged):

1. **Eye-texture probe (answers b immediately).** Once per second, blit-read a few tiles
   (e.g. 4×4 at centre, one per quadrant) of each provider `MTLTexture` into a shared `MTLBuffer`
   and log mean RGB(A) + a few raw texels, plus `tex.width/height/pixelFormat/usage/storageMode/
   textureType`. If the tiles are near-black/empty → provider image is black/unwritten (b1) →
   provider-side sync/write problem. If they contain a real image but the immersive is black →
   compositing/presentation problem on the compositor side.
2. **Fallback test pattern (separates "black texture" from "black presentation").** When the eye
   texture probe reports mean luminance < ~1/255 for N consecutive frames, draw a procedural
   checkerboard/gradient instead of sampling. Operator sees content ⇒ compositor presentation is
   alive and the provider image is the problem; still black ⇒ presentation/compositing is the problem.
   Also run a single-frame mode that always draws the test pattern, selected by a flag file.
3. **Branch-colour debug shader** (copy from this probe): magenta = provider-UV outside [0,1],
   cyan = ray behind camera, sampled = texture. Today the per-frame branch distribution is invisible
   on device; this one line makes it visible.
4. **Force alpha=1** in `fmain`: `return float4(tex.sample(s, uv).rgb, 1.0);` — cheap hygiene; the
   simulator says it is not load-bearing, the device is unverified.
5. **Use `cp_view_texture_map`** (`textureIndex`/`viewport`) instead of assuming view index ==
   texture index (correct for dedicated layout; makes shared/layered layouts safe).
6. **Provider-side check** (out of this probe's scope): verify that the exact `VkImage` exported via
   `vrmc_export_mtl_texture` is the image the provider actually renders into, and add the
   MoltenVK/Vulkan↔Metal shared-event/timeline sync before the compositor samples it (a known
   remaining M3 item). Log a provider-side mean of the eye target (e.g. one pixel/region) to confirm
   non-black content independently of the compositor.

## Artefacts

| File | Content |
|---|---|
| `m3b.log` | full probe log (config, matrices, CPU diagnostics, readbacks, validations) |
| `summary.txt` | condensed one-line-per-check summary |
| `drawable-01-reproj-depth.png` | presented drawable readback, exact reproj shader, EV-0086 pass variant (depth attachment, clearDepth 0.0) |
| `drawable-02-debug-depth.png` | same, branch-colour variant (no magenta/cyan ⇒ no early-outs) |
| `drawable-03-flat-depth.png` | old flat-sampler control |
| `drawable-04/05/06/07/08…` | no-depth, alpha1-forced, alpha0-texture, no-rate-map, final variants (byte-identical to 01) |
| `offscreen-live-view0-*.png` | offscreen shader variants incl. full-pattern proof and black-texture case |
| `offscreen-device-L-*.png`, `offscreen-device-R-*.png` | EV-0086 reconstructed eyes through the exact shader (reproj / debug / flat / alpha1) |
| `simulator-immersive-phase0-alpha255.png`, `…phase1-alpha0-texture.png` | presented immersive screenshots of the alpha phases (pixel-identical) |
| `simulator-before-immersive-room.png` | simulator room/window state before the immersive space takes over |

## Confidence and limits

- **What is solid:** projection/view convention behaviour of `cp_drawable_compute_projection`
  (right_up_back) + `cp_view_get_transform`; the exact ray→UV formula; the shader/texture/pipeline
  path; drawable readback == CPU reference; presented screen == drawable content; alpha behaviour in
  the simulator compositor; the EV-0086 reconstruction and the "no black frame from the math" result
  (coverage 87.88 %, 0 behind/nan, roll-insensitive ±20°).
- **Not device evidence:** one simulator view and identity view transform; no asymmetric stereo pass on
  the simulator; the simulator compositor is not the device compositor (alpha, lens reprojection,
  passthrough). Provider textures were synthetic, not the provider's real ones.
- **Reconstruction assumption:** the EV-0086 device view rotation is rebuilt from the logged
  `fwd`/translation with zero roll; the coverage is stable across ±20° roll (87.9–89.7 %), so the
  conclusion is not sensitive to that assumption. The logged device data itself is unchanged from
  EV-0086.
