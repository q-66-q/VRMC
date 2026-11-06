# M8 — Foveated 4K/120 rendering

**Status:** implemented (M8.1–M8.3 host/simulator); device verification NOT RUN (physical D1 unavailable
at implementation time).
**Started:** 2026-11-05.
**Baseline:** `7216a63` (release-ready M6/M7 build).
**Authority:** [`VERIFY.md`](../../VERIFY.md) for evidence; this plan records design and acceptance.

## 1. Problem statement

The operator reported, on the release-ready build: **"the resolution is too low and there is significant
jaggedness"**, and asked for **foveated rendering to achieve 4K in both eyes and 120 Hz**.

Measured facts in the accepted build (device logs, EV-0091/EV-0265/EV-0266):

| Fact | Value | Consequence |
|---|---|---|
| Provider eye render target (Vivecraft) | **1024x1024 per eye**, fixed (`VisionRenderer.EYE_WIDTH/HEIGHT`) | The compositor samples a 1024² image into a ~1888x1792 per-eye viewport → **~1.84x upscale blur**; fine geometry aliases. |
| Compositor drawable viewport (default quality) | 1888x1792 per eye | System render quality default (~half of the panel's native per-eye density). |
| Layer foveation | **disabled** (`isFoveationEnabled = false`) | No rasterization rate maps; no foveal high-density region; drawable memory at uniform resolution. |
| Frame pacing target | 90 Hz (p50 8.34 ms, p95 9.24 ms, missed90 0–1) | No 120 Hz path attempted. |
| Eye texture format | BGRA/RGBA8 UNORM, no MSAA | Edges alias when upscaled. |

So the visible defect is structural: the game renders far below the display, and the display path is
configured for the lowest acceptable quality. M8 fixes both ends.

## 2. Platform capability research (visionOS 27.2 SDK)

Verified against the shipping XROS 27.2 SDK headers and Apple docs (not assumed):

1. **Foveated rendering is a CompositorServices layer feature.**
   `cp_layer_renderer_configuration_set_foveation_enabled` (visionOS 1.0+,
   `layer_renderer_configuration.h`): *"When foveation is enabled, the drawable resource for each frame
   reduces the size of the texture you use for rendering. The drawable also provides rasterization rate
   maps that specify the amount of rasterization to apply to different parts of the texture. When
   rendering your scene, the GPU generates fewer pixels in areas with low rasterization rates, and then
   scales up those areas before displaying them onscreen."*
   Apple's *Drawing fully immersive content using Metal* sample uses exactly:
   `let supportsFoveation = capabilities.supportsFoveation;
     configuration.isFoveationEnabled = supportsFoveation` and picks the layout from
   `supportedLayouts(options: supportsFoveation ? [.foveationEnabled] : [])`.
2. **Dynamic render quality is a visionOS 26+ layer feature.**
   `cp_layer_renderer_configuration_set_max_render_quality` sets the upper bound (and therefore the
   allocated drawable memory); `cp_layer_renderer_set_render_quality` moves the runtime quality inside
   `[0, max]`. WWDC25 session 294: *"As you boost the render quality, the high relevance area in your
   texture expands, leading to a larger overall texture size"* — i.e. higher quality = larger foveal
   high-density region and larger drawable.
3. **The display supports 90/96/100/120 Hz.** Apple Vision Pro (M5) tech specs: *"Supported refresh
   rates: 90Hz, 96Hz, 100Hz, 120Hz"*. `cp_layer_renderer_set_minimum_frame_repeat_count(0)` forbids the
   layer from repeating our frames, so the app can present every display frame when it sustains the
   cadence.
4. **There is no public "set refresh rate" API for a CompositorServices renderer.** The frame timing
   object exposes deadlines/presentation times, not a rate selector; the only lever is frame repeat
   count. Therefore M8 **measures** the cadence the system actually presents at (from consecutive
   presentation times) and targets it; it does not claim a rate it cannot request.
5. **Engine-side fragment shading rate is not available on this stack.** The shipped visionOS
   `libMoltenVK.dylib` (MoltenVK 1.4.3) exports `VK_EXT_metal_objects`, `VK_KHR_fragment_shader_barycentric`
   etc. but **not** `VK_KHR_fragment_shading_rate`, so Minecraft's Vulkan pass cannot consume a Metal
   rasterization rate map. Real engine-side VRS would need a MoltenVK feature addition or a split
   foveal/peripheral render pass; both are deferred (see §6).

## 3. Architecture

```
CompositorServices layer (shell)                      Provider (JVM, Vivecraft)
  foveation ON (if supported)                          VisionRenderer
  maxRenderQuality = 1.0  ── runtime quality ──┐         eye targets = logical_size x eyeScale
  drawable: physical (foveated) + logical size │         eyeScale: auto (default) or fixed file knob
  presentation times → displayHz/variance      │         resize with hysteresis via reinitFrameBuffers
                                               ▼
        vrmc_render_settings (68 B, native-shared channel, mutex-copied, no Java ABI bump)
        left/right logical size, drawable size, foveation/rate-map count,
        render quality/max, measured displayHz + frame interval
```

The compositor publishes the payload from its frame loop (at most every 10 frames, immediately on
geometry/quality change). The provider polls it once per rendered frame through
`VrmcBridge.pollRenderSettings` (JNI `nativePollRenderSettings`, one preallocated direct
`ByteBuffer`, no per-frame allocation), then:

- `eyeScale = auto` (default): start at 0.50 of the logical size, evaluate every 240 frames (≈2 s at
  120 Hz) against the **provider's own** measured frame intervals vs the display interval; step
  0.10 down on repeated frames/slow p50, 0.05 up only after two consecutive headroom windows, hold
  after a down-step. Bounded 0.25..1.0.
- `vrmc-eye-scale.txt` in the game dir (or `-Dvrmc.eyeScale=`) pins `auto` or `0.25..1.0` for on-device
  tuning without a rebuild; re-read every 600 frames.
- Eye target = logical size × scale, rounded up to 8 px, clamped 512..4096 per dimension. A resize
  calls Vivecraft's `reinitFrameBuffers`, which recreates both eye VkImages and every render target on
  the next frame; resizes are rate-limited to one per 240 frames and never in the first 60 frames.

On a device panel whose max-quality logical view is ~3660x3200 per eye, the default auto policy starts
at ~1832x1600 per eye (2.8x the pixels of the accepted 1024² target) and ramps toward the logical size
while the display cadence is held. This is the direct fix for the upscale blur/jaggedness; the display
path at the same time is foveated and at maximum render quality.

### Honest limitation

The provider renders a **uniform** eye image. CompositorServices foveation reduces the **system's**
drawable memory/final compositing cost and gives the fovea native density; it does **not** reduce
Minecraft's own fill cost. Therefore:
- "4K in both eyes" = the display path is allocated at the device's maximum render quality and the
  provider renders as close to the logical per-eye size as its measured frame budget allows.
- "120 Hz" = the layer never repeats frames and the app measures/targets the system-selected cadence;
  whether a session presents at 120 Hz is **measured on device** (compositor `displayHz=` line), not
  assumed.
- True engine-side foveation (peripheral shading reduction) is deferred because MoltenVK 1.4.3 lacks
  `VK_KHR_fragment_shading_rate`; options are recorded in §6.

## 4. Implementation phases

| Phase | Scope | State |
|---|---|---|
| M8.1 | Shell layer configuration: foveation ON when supported (capability-logged, `vrmc-foveation-off.flag` A/B), `maxRenderQuality` from `vrmc-max-render-quality.txt` (default 1.0), layout chosen from supported layouts for the foveation mode. | DONE (host/sim build) |
| M8.2 | Bridge render-feedback channel: `vrmc_render_settings` (68 B) + `vrmc_shared_publish_render_settings`/`acquire` + JNI `nativePollRenderSettings`; C static-assert layout; C concurrency test; Java layout/parse/policy test; fake-provider capture; simulator harness scenario `render`. | DONE (host/sim) |
| M8.3 | Compositor: foveation/quality/rate-map logging, presentation-cadence statistics, render-quality control (fixed from `vrmc-render-quality.txt`; `auto` opt-in via content "auto"/`vrmc-quality-auto.flag`), `minimumFrameRepeatCount=0`, per-frame render-feedback publication. | DONE (host/sim) |
| M8.4 | Provider: poll render feedback, adaptive eye scale, eye-target resize + logs, actual-size eye submission, frame-stats target-interval scoring (90/120 Hz). | DONE (host compile+tests) |
| M8.5 | Device verification on D1 (physical device unavailable during implementation): foveation/rate maps present, logical per-eye resolution at max quality, provider eye target/resizes, measured displayHz, frame pacing, operator visual report. | NOT RUN |

## 5. Acceptance

Host/simulator (this change):
- A1 bridge channel: `bridge/tests/bridge_shared_test.c` publishes/acquires 20k payloads with readers;
  layout static asserts; validation rejects wrong version/short/out-of-range payloads; retention across
  `vrmc_init`; TSan clean. **PASS**
- A2 Java contract/policy: `VisionRenderSettingsTest` (43 checks: wire layout, fail-safe parse, eye-target
  rounding/clamps, 90/120 Hz cadence scoring, auto-scale bounds/hysteresis, resize threshold) and
  `VisionFrameStatsTest` (13 checks incl. 120 Hz target-interval scoring). **PASS**
- A3 provider builds with the new class and renderer integration (33 classes / 25 sources). **PASS**
- A4 shell builds for xros simulator (and device build in the release gate) with the new layer
  configuration. **PASS** (simulator; device build check follows)
- A5 simulator scenario `render`: real compositor publishes sane display geometry/cadence, logs
  layer configuration/foveation/quality/frame-pacing/render-feedback lines, and the sampled drawable
  still matches the known pattern. **PASS/FAIL recorded in VERIFY.md** — *simulator only, not device
  optics/refresh evidence*.

Device (D1, NOT RUN; one operator session):
- A6 `vrmc-compositor.log` shows `layer configuration ... foveation=1 ... maxRenderQuality=1.00` and
  `foveation rate map ...` geometry (screen vs physical size) — foveated rendering actually active.
- A7 `display geometry: logical L=...` reports the max-quality per-eye view (expected ~4K-class);
  provider log shows eye targets sized from it (`[VRMC-M8] eye target resize ...`) and no repeated
  resize thrash.
- A8 `render feedback: displayHz=...` — the actual presented cadence (90 or 120 Hz) with
  `repeats=...`; the 120 Hz claim requires `displayHz≈120` with acceptable repeats.
- A9 Frame pacing within budget at the chosen scale (p50/p95 consistent with 90 or 120 Hz; no
  crash/watchdog), operator visual confirmation that upscale blur/jaggedness is reduced.

## 6. Deferred / future work

1. **Engine-side foveation**: add `VK_KHR_fragment_shading_rate` (Metal rasterization rate map) support
   to the visionOS MoltenVK build, or a split foveal/peripheral pass inside the provider, so the game
   renders fewer peripheral pixels instead of relying on adaptive uniform resolution. Requires a
   vendor build change (new artifact, ADR + licensing review).
2. **Provider-side sharpening/anti-aliasing** in the compositor sampling pass (foveal CAS/unsharp) to
   further reduce upscale softness when the game renders below the foveal logical size.
3. **Dynamic per-eye resolution** if the display views become asymmetric (currently both eyes share one
   target size in Vivecraft).
4. **Temporal reprojection / depth export** so the compositor can reproject game frames for cadence
   headroom at 120 Hz.

## 7. Device runbook (M8.5)

1. Build/stage the app + provider jar and install on D1 (`scripts/install_device.sh`,
   `scripts/push_provider_jar.sh`).
2. (Optional A/B) push Documents flags/files: `vrmc-foveation-off.flag`, `vrmc-render-quality.txt`
   (e.g. `1.0`, `0.75`, `auto`), `vrmc-max-render-quality.txt` (e.g. `1.0`/`0.75`); provider-side
   `Documents/instances/default/vrmc-eye-scale.txt` (`auto` or a number) for eye-target tuning.
3. Launch, enter immersive, play ~2 minutes in a world (include turning, a menu, and distant geometry).
4. Pull `Documents/vrmc-compositor.log`, `vrmc-shell.log`, `latestlog.txt`; record operator visual
   report (blur/jaggies/comfort) and the A6–A9 lines in `VERIFY.md` as a new evidence id.
5. Rollback: delete the override files, or push `vrmc-foveation-off.flag` + `vrmc-render-quality.txt=0.5`
   + `vrmc-eye-scale.txt=0.25` for the pre-M8 rendering cost profile.

## 8. Risks

- **Drawable memory**: rgba16Float at max render quality (two drawables) is large; if the app approaches
  the memory limit, use `vrmc-max-render-quality.txt=0.75` (memory is fixed by the max quality setting,
  runtime quality changes do not change memory).
- **Resize hitch**: a provider eye-target resize rebuilds every render target; the first one happens
  after the first display feedback (~frame 60+) and is rate-limited. If it is visible, pin
  `vrmc-eye-scale.txt` so no resizes happen.
- **Layout change**: if foveation only supports a layout other than `.dedicated`, the shell selects it
  from `supportedLayouts`; the compositor already handles sliced/array textures and viewports.
- **Simulator is not evidence** for optics, refresh rate, thermals or latency; only the plumbing
  (channel, parsing, logging, shader sampling) is verified there.
