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

When the provider has to render below the logical size (the normal case for 120 Hz at a 4K-class
drawable), the compositor's flat sampling pass switches to **M8.6 foveated sharpening**: a CAS-lite
5-tap filter whose strength scales with the upscale ratio (auto, capped 0.45), is weighted towards the
view centre (the fovea) and tapers off in the periphery, and is soft-clamped to the local neighbourhood
to limit halos. It is compositing-only work (no game cost), controlled live by
`Documents/vrmc-sharpening.txt` (`auto` default / `off` / fixed strength).

When the target cadence cannot be met, the default policy lowers the eye-target resolution. With
`Documents/instances/default/vrmc-content-first.txt` = `on` (default off) the provider instead cuts
**scene cost first** — render distance, then simulation distance, then a second render-distance step
(two consecutive struggling windows, one step per window, at most three per session, never below the
6-chunk minimums) — and only then lowers the eye-target resolution. That preserves the 4K-class image
while making frames cheaper, which is the right trade for the "4K at 120 Hz" objective.

The auto eye-scale policy normally aims at the cadence the compositor measured, so at 90 Hz it would
fill the 11.1 ms budget rather than pursuing 120 Hz. `Documents/instances/default/vrmc-target-hz.txt`
lets the operator aim at a higher rate (`auto` default, or 60..120 Hz): the provider then holds frames
inside the shorter deadline (8.33 ms at 120 Hz) and the system can promote the display; the achieved
rate is still measured (never assumed). Target-cadence overrides are logged and reported in the status
JSON and the device checker.

During an eye-target resize the provider clears the shared eye frame before rebuilding (safety, see
§8). The compositor keeps its last sampled MTLTexture pair retained and **reuses it for up to 30
frames** of the gap, so a resize presents one stale frame instead of flashing the procedural test
pattern; after 30 frames it falls back to the pattern and logs the grace expiry. This is exercised by
the simulator `eyedrop` scenario (fake provider withholds the eye frame for 60 acquires, then resumes).

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
| M8.6 | Compositor foveated sharpening (CAS-lite, fovea-weighted, anti-halo clamp) for the sub-native provider render that 120 Hz at a 4K-class drawable implies; `Documents/vrmc-sharpening.txt` (auto/off/fixed), cadence-summary `sharpen=…`; host Metal probe upscale metrics; simulator regression. | DONE (host/sim) |
| M8.5 | Device verification on D1 (physical device unavailable during implementation): foveation/rate maps present, logical per-eye resolution at max quality, provider eye target/resizes, measured displayHz, frame pacing, operator visual report. | **TOOLING READY, DEVICE NOT RUN** — one-command classifier `scripts/m8_device_check.sh` (+ host test) and operator runbook [M8_DEVICE_RUN.md](M8_DEVICE_RUN.md) |

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
- A5b host foveation pass: `runtime/probes/m8-foveation/run.sh` runs the compositor's full-screen flat
  sampling math into a real macOS Metal variable-rasterization-rate pass (0.5 periphery / 1.0 centre;
  1920×1080 logical → 1488×848 physical, 60.9 % of screen pixels). The logical centre maps to the
  pattern's white centre cross and the logical upper-left quarter to the red quadrant (NDC→UV stays
  logical under VRR); the negative control with a physical-size viewport corrupts the foveal centre,
  proving the viewport convention the compositor uses. **PASS (host Metal; 6 checks)** — *not
  device/visionOS optics or eye-tracked foveation evidence*.
- A7b host Fabric harness: `scripts/m8_host_harness.sh` (docs: [M8_HOST_HARNESS.md](M8_HOST_HARNESS.md))
  runs the real M8 provider inside a real Minecraft 26.2 + Fabric + Vivecraft desktop client and feeds
  it fake 3660×3200 / foveation=1 / 120 Hz display feedback through the real bridge channel. The
  provider starts at 1024×1024 with no feedback, then polls, parses and resizes its stereo eye targets
  **1024×1024 → 1832×1600** through Vivecraft's reinit path; with headroom the auto controller then ramps
  0.60 (2200×1928) and 0.70 (2568×2248) at the 240-frame cadence, with no M8 exceptions.
  **PASS (host GL; EV-0272)** — *not device/Vulkan/optics evidence; display feedback is fabricated and
  the menu-room branch only*.

Device (D1, NOT RUN; one operator session):
- A5c compositor foveated sharpening (host Metal probe + simulator): 4× upscale of a low-resolution
  checkerboard with the sharp shader raises edge acutance **1.17×** vs bilinear, mean absolute luma
  change stays at 0.016 (anti-halo clamp), and the centre gain (1.27) exceeds the corner gain (1.00) —
  the foveal taper works. The simulator `render` scenario runs the real shader/pipeline end-to-end
  (`foveated sharpening: auto strength=0.45 … upscale=3.75`, `sharpen=0.45` in the cadence summary) and
  still matches the known pattern. **PASS (host Metal + simulator)** — *not device visual evidence*.
- (robustness) the pull classifier also reads `vrmc-status.json`'s M8 `render` summary and pacing
  counters, so rotated compositor/provider logs still classify A6–A9 (host-tested status-only pull);
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
2. **Provider-side sharpening/anti-aliasing** — superseded by M8.6: foveated sharpening now runs in the
   compositor sampling pass (M8_PLAN §4 M8.6, host probe EV-0273); deeper options are temporal upscaling
   / TAA (§6.4).
3. **Dynamic per-eye resolution** if the display views become asymmetric (currently both eyes share one
   target size in Vivecraft).
4. **Temporal upscaling / TAA** in the compositor (history + reprojection) to raise the foveal image
   further when the provider has to run well below the logical size for 120 Hz; the M8 sharpening pass
   is the first (single-frame) step.
4. **Temporal reprojection / depth export** so the compositor can reproject game frames for cadence
   headroom at 120 Hz.

## 7. Device runbook (M8.5)

Full operator procedure: [M8_DEVICE_RUN.md](M8_DEVICE_RUN.md).

1. Stage the M8 app + provider jar; then one command runs validate → install → provider push and
   prints the operator checklist: `scripts/m8_device_session.sh prepare` (underlying scripts:
   `scripts/install_device.sh`, `scripts/push_provider_jar.sh`).
2. Launch with JIT, enter immersive, play 3–5 minutes (world + menu + distant geometry), quit cleanly.
3. Pull and classify in one command: `scripts/m8_device_session.sh collect` (wraps
   `scripts/m8_device_check.sh`; exit 0 PASS / 2 PARTIAL / 3 NOT RUN / 4 FAIL). It checks A6
   (foveation/rate maps), A7 (4K-class logical size + provider eye targets), A8 (measured 90/120 Hz
   cadence, sharpening state, target-cadence override), A9 (pacing/regressions).
4. Record the result + operator visual statement as a new `VERIFY.md` §6 evidence id (hashed bundle
   via `scripts/log_evidence.sh`).
5. Tuning/A-B and rollback knobs: see M8_DEVICE_RUN.md §4/§6.

## 8. Confirmation of the foveation rendering model (public sources + host probe)

- Apple's *Scaling variable rasterization rate content*: for a render pass that carries a rate map the
  GPU does the screen↔physical conversion; a separate scaling pass is only needed when the rate-mapped
  texture is an *intermediate*, not the final drawable. CompositorServices' drawable is the final
  target, so the compositor's job is to attach the map and draw normally.
- The public *Drawing Graphics on Apple Vision with the Metal Rendering API* article: foveation is
  effectively "for free" — enable `isFoveationEnabled`, set the render pass's `rasterizationRateMap`
  from the drawable's maps, and use `drawable.views[].textureMap.viewport` (never hardcode viewports);
  rendering to a smaller-than-rate-map viewport is invalid when foveation is on.
- Qt's visionOS Metal fix (`qrhimetal.mm`): when a rate map is attached the render-pass viewport is in
  screen (logical) coordinates; a physical-size viewport is wrong.
- **M8 host probe PASS** (`runtime/probes/m8-foveation`, EV-0270): on real Metal the compositor's
  sampling math keeps the logical UV mapping under a 0.5/1.0 foveated rate map, and the physical-size
  viewport negative control fails exactly as predicted. Device eye-tracked foveation, optics and cadence
  remain device-only (A6–A9).

- **M8.6 sharpening** was validated objectively on host Metal (edge acutance, anti-halo bound,
  foveal weighting) and end-to-end in the simulator; the device visual judgement (halos? comfort?) is
  part of the operator statement in A9, with `vrmc-sharpening.txt=off` as the immediate rollback.

## 9. Risks

- **Drawable memory**: rgba16Float at max render quality (two drawables) is large; if the app approaches
  the memory limit, use `vrmc-max-render-quality.txt=0.75` (memory is fixed by the max quality setting,
  runtime quality changes do not change memory).
- **Resize hitch / texture lifetime**: a provider eye-target resize rebuilds every render target; the
  first one happens after the first display feedback (~frame 60+) and is rate-limited (240 frames). Before
  the rebuild the provider now **clears the shared eye frame**, so the compositor cannot acquire a
  destroyed eye VkImage in the window between `destroyBuffers` and the next submit (it presents its
  fallback pattern for the one or two frames instead; the compositor already retains in-flight textures
  for an encoded command buffer). If the brief fallback is objectionable, pin `vrmc-eye-scale.txt` so
  no resizes happen.
- **Layout change**: if foveation only supports a layout other than `.dedicated`, the shell selects it
  from `supportedLayouts`; the compositor already handles sliced/array textures and viewports.
- **Simulator is not evidence** for optics, refresh rate, thermals or latency; only the plumbing
  (channel, parsing, logging, shader sampling) is verified there.
