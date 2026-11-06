# m8-foveation — host Metal probe for the compositor foveation path

Objective, headset-free verification that the VRMC compositor's **full-screen flat sampling pass**
renders correctly when the render pass carries a **variable rasterization rate map** — the mechanism
CompositorServices foveation uses (the system creates the maps; the app renders normally into the
rate-mapped drawable and the system expands the physical texture to the display).

Why this exists: the visionOS **simulator reports `supportsFoveation=false`**, so the device foveation
path cannot be exercised there, and D1 was unavailable during M8 implementation. macOS Apple Silicon
supports `MTLRasterizationRateMap` for real, so this probe proves the two properties M8 depends on:

1. **The shader's NDC→UV mapping stays logical under VRR.** A physical target pixel that the rate map
   expands to a given logical position samples the eye texture at that logical position. The probe
   renders the compositor's `vmain` + `fmain_flat` math (full-screen triangle strip, NDC → `(u, 1-v)`
   sampling) into a 1920×1080 logical target whose rate map is 0.5 at the periphery and 1.0 in the
   centre (the system's eye-tracked maps have the same shape), then decodes the physical image:
   the logical centre must show the pattern's white centre cross and the logical upper-left quarter
   must show the red quadrant.
2. **The render-pass viewport is the rate map's SCREEN (logical) size**, not the physical texture size.
   A negative control renders with the physical-size viewport and must corrupt the foveal centre
   (it does), which proves the probe distinguishes the convention.

The compositor itself uses `cp_view_texture_map_get_viewport` for the pass viewport (the
CompositorServices-blessed way; the public *Drawing Graphics on Apple Vision* article also says never to
hardcode viewport sizes). The device log already prints the viewport and the physical texture extent
side by side (`view N attachments` + `foveation rate map` lines), so the first D1 M8 session verifies
the convention end-to-end; this probe verifies that the shader/pass behaviour is correct for it.

## M8.6 foveated-sharpening upscale test

The probe also renders a **480×270 checkerboard upscaled 4×** to 1920×1080 twice — plain bilinear
(`fmain_flat`) and the compositor's fovea-weighted CAS-lite (`fmain_flat_sharp`, strength 0.45,
texel = source pixels) — and measures the decoded images:

| Metric | Result (Apple M4 Pro) | Meaning |
|---|---|---|
| Edge acutance ratio (sharp / bilinear) | **1.17×** | the upscale is genuinely sharpened, not just resampled |
| Mean absolute luma change | **0.0158** (bound 0.15) | anti-halo/clamp keeps the correction bounded |
| Centre edge gain vs corner edge gain | **1.27× vs 1.00×** | the foveal taper works: periphery is not over-sharpened |

The shader code in this probe mirrors `VRMCCompositor.mm`'s `FlatFx`/`fmain_flat_sharp`; the simulator
`render` scenario then runs the real pipeline end-to-end (`foveated sharpening: auto strength=0.45 …
upscale=3.75`, `sharpen=0.45`). Device visual judgement (halos/comfort) is part of the operator
statement in [M8_DEVICE_RUN.md](../docs/mvp/M8_DEVICE_RUN.md), with `vrmc-sharpening.txt=off` as rollback.

## Run

```bash
runtime/probes/m8-foveation/run.sh
```

Requires macOS on Apple Silicon (Metal rasterization rate maps). Exit 0 PASS, 1 FAIL, 2 SKIP (no Metal
device / no rate-map support). Artifacts: /tmp/vrmc-m8-foveation-probe/probe.log.

**Evidence class:** host-only. This is not device/visionOS evidence for optics, eye-tracked foveation,
latency or refresh rate; it validates the compositor sampling pass + viewport convention under a real
Metal variable-rasterization-rate map.

## Provenance

The rendering model was cross-checked against public sources (2026-11-05): Apple's *Scaling variable
rasterization rate content* (rate map pass + screen/physical coordinate conversion is done by the GPU
for a rate-mapped render pass; a separate scaling pass is only needed when the rate-mapped texture is
an intermediate), the public *Drawing Graphics on Apple Vision with the Metal Rendering API* article
(foveation "for free": enable `isFoveationEnabled`, set `renderPassDescriptor.rasterizationRateMap`
from the drawable, use `drawable.views[].textureMap.viewport` and never hardcode viewports), and Qt's
visionOS Metal fix (`qrhimetal.mm`: use the rate map's `screenSize` for the viewport when a rate map is
attached).
