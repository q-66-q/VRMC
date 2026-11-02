# CompositorServices presentation path + shell lifecycle audit (M3-W3/W4 black immersive)

**Author:** compositor (task-3) · **Date:** 2026-11-01 · **Scope:** `runtime/native-shell/Sources/VRMCCompositor.mm`,
`runtime/native-shell/Sources/Shell.swift`, `Bridging.h` · **Device access:** none (build/static only;
device runs are Lead-only).

**Bottom line.** The 15:28 and 16:39 device sessions presented continuous frames (6360 / 1080), the
command buffer completed and the provider eye textures measured bright — yet the operator reported a
pure black immersive. The most probable causes are (1) the compositor rendering/presenting only the
**deprecated singular drawable** while visionOS 26+ can hand out several target-tagged drawables, and
(2) a **silently invalid render pass** (nil colour/depth attachment, format mismatch or nil render
encoder), which drops even the load-action clears, so the presented buffer stays black while the
command buffer still reports `completed`. Both classes are now fixed/logged, and the build writes the
**drawn drawable's pixels** to `Documents/vrmc-drawable-*.raw` so the next run proves what was
presented without an operator judgement call.

---

## 0. Evidence timeline correction (important for interpreting the old logs)

The most informative lifecycle logs (`VRMCCompositorRunning`, `NO-FRAME`, "waiting for the first
compositor frame before parking") were produced by an **uncommitted** build: `/tmp/VRMC-native-m3b.app`
(14:29). `git log -S` shows those strings were never committed; `git HEAD f4d0617` and the current
tree carry the *older* `Shell.swift` (sha `08a17f4…`) and an older compositor with no
`VRMCCompositorRunning` notification. All builds after 15:07 (`VRMC-native-displayviews/align/layoutfix.app`)
are **OLD-SHELL**, including the currently installed layoutfix build. Consequence:

| Session (local HST) | Shell build | What the logs really show |
|---|---|---|
| 14:33 / 14:41 | M3b uncommitted (NEW shell) | 24 s `wait_until_running` delay, 2 presented frames, then parking → `UIScene.willDeactivate` in the same second |
| 15:28 (frames 6360) | align build (OLD shell) | windows parked with `isHidden=true` + `alpha=0` immediately on open; operator backgrounded **2 min later** (after black was observed) |
| 16:39 (frames 1080) | layoutfix build (OLD shell) | same immediate hide-parking; `UIScene.willDeactivate` **5 s** after open, `didEnterBackground` 8 s later — i.e. the operator gave up because the immersive was black |

The `willResignActive`/`didEnterBackground` events are therefore largely **operator actions after the
black was observed**, not the cause of it (the 14:41 session is the one case where parking and scene
deactivation are correlated to the same second). The black must be explained on the presentation path.

---

## 1. CompositorServices semantics audit (XROS 27.2 headers)

Sources consulted: the shipping `CompositorServices.framework/Headers` in `XROS.sdk`
(`drawable.h`, `frame.h`, `view.h`, `layer_renderer_configuration.h`, `layer_renderer_capabilities.h`),
`runtime/probes/m3a-immersive/Sources/ProbeRenderer.mm` (EV-0074 — the probe that DID show red/green on
this device, clear-only + deprecated single drawable + depth + rate map), Apple's
`metal-by-example/spatial-rendering` Vision Pro sample (per-view drawable passes,
`queryDrawable`/`encodePresent`/`endSubmission` ordering, rate-map per pass) and Klepton's production
CompositorServices compositor (`visionos/Sources/KleptonCompositor.swift`, device-proven notes on the
drawable array, `__BUG_IN_CLIENT__` on end-submission-without-present, and render-quality crossfades).

### Verified correct in the old code (kept)

- Drawable colour/depth selection through `cp_view_get_view_texture_map` → `texture_index` /
  `slice_index` / `viewport`; one render pass per view for `.dedicated` layout. Correct per `view.h`
  ("if the layer dedicates a separate texture to each view, the texture bounds and view bounds match").
- `rgba16Float` configured via `CompositorLayerConfiguration` and matched by the render pipelines.
- Reverse-Z: `clearDepth = 0.0` with an always/no-write depth-stencil state and a depth attachment —
  `drawable.h` documents reverse-Z ("value 1 for near, 0 for far") and EV-0074 proved the device needs
  the depth attachment.
- `cp_frame_predict_timing` → `start_update`/`end_update` → `cp_time_wait_until(optimalInputTime)` →
  `start_submission` → render → `cp_drawable_encode_present` → `commit` → `end_submission`, and the
  device anchor queried at `cp_drawable_get_frame_timing(drawable).presentationTime` then set with
  `cp_drawable_set_device_anchor`. This matches both the Apple sample and the EV-0074 probe.
- Command-buffer completed/failed status was already logged (no failures in any black run).

### Defects / diagnostic gaps found (ranked, all fixed or instrumented)

**F1 — only ONE, deprecated drawable is rendered/presented (highest suspect).**
`frame.h`: `cp_frame_query_drawable` is `API_DEPRECATED("Use cp_frame_query_drawables instead",
visionos(1.0, 26.0))`; the replacement returns a `cp_drawable_array_t` and
`cp_drawable_get_target()` tags each element `built_in` (what the user sees) or `capture`; the header
says "Renderer should always prioritize built_in target type". The array can contain **more than one**
drawable (built_in + capture, and render-quality crossfades — Klepton documents that a loop rendering
only `drawables[0]` shows a half-empty frame during such a transition). The old compositor never
queried the array, never logged the target, and presented exactly one drawable. If the drawable it got
was not the buffer the system composites to the built-in display (or a second drawable was in play),
the display would show an untouched/black buffer **while every command buffer completes and the sampled
provider texture is bright** — the exact symptom set of EV-0090/EV-0091. The old logs' viewport
(1888×1792) and `textureCount=2` are consistent with a single dedicated-layout drawable, but there is
no evidence in the log that it was the built_in one.
*Fix:* `cp_frame_query_drawables()` → render **and present every drawable**, log count/target and
per-drawable views/textures/rate-maps once (and whenever the count > 1), and use the built_in drawable
only for ARKit tracking and display-view publication. An explicit warning is logged if no built_in
drawable is in the array.

**F2 — an invalid render pass / nil render encoder presents black while the command buffer completes.**
The old code never checked `cp_drawable_get_color_texture()` / `cp_drawable_get_depth_texture()` for
nil, never compared the pipeline's colour format with the drawable texture's real format, and never
logged `[cb renderCommandEncoderWithDescriptor:]` returning nil. If any of those fail, the load-action
clear (bright red left / green right) does not execute either — the drawable is presented exactly as
the compositor recycled it (**black**) while the command buffer completes (completed ≠ drew anything).
This is the only mechanism consistent with the operator never seeing the red/green clears or the forced
test pattern. The pipeline format was hardcoded to `rgba16Float` and the log printed that constant, so
a mismatch was invisible.
*Fix:* pipelines are built from `cp_layer_renderer_configuration_get_color_format()` /
`get_depth_format()` and **lazily rebuilt from the actual drawable attachment formats** if they differ
(logged); nil colour texture, nil depth texture, nil render encoder and format/size/type/arrayLength of
every attachment are logged once with full context. The first presented frame also logs
`VRMCCompositorRunning` so the shell no longer parks windows for a session that never presented.

**F3 — no ground truth of what was presented.** Provider-texture readbacks prove only what was
*sampled*, not what reached the drawable/display. A bright sampled texture plus a black display is
exactly the ambiguity that blocked the last three runs.
*Fix:* after the render passes and before `cp_drawable_encode_present`, blit 64 strided full-width rows
of each eye's **drawable colour texture** into a shared buffer inside the frame command buffer, decode
to a 64×64 RGBA8 image in the completion handler, log mean/max/luma/top-strip/centre luminance, and
write `Documents/vrmc-drawable-L.raw` / `-R.raw` (+ `.meta`) for the first 3 frames and every ~300
frames (and whenever `vrmc-drawable-dump.flag` is set). This is the decisive evidence: a non-black
drawable readback with a black display proves the presentation/composition step, not the render step.

**F4 — `cp_frame_end_submission` after a non-presented frame aborts the process.**
`frame.h`'s submit/end-submission contract plus Klepton's device note (`__BUG_IN_CLIENT__` inside
`cp_frame_end_submission` when a submission never presented a drawable). The old nil-drawable path
called exactly that. *Fix:* drawables are queried before the submission is opened; an empty array
abandons the frame without `start_submission`/`end_submission`; a frame that somehow presents zero
drawables is logged and its submission is left un-ended.

**F5 — rasterization-rate-map index treated as texture index.**
`cp_drawable_get_rasterization_rate_map(drawable, textureIndex)` was called without checking
`cp_drawable_get_rasterization_rate_map_count()` (texture count and rate-map count are independent
queries). With foveation disabled the count can be 0 and the old code still called the getter; a bogus
map on the pass can blank or distort the render. *Fix:* index bounded by the rate-map count, logged; no
map is attached when the count is 0.

**F6 — device-anchor failures not counted.**
`cp_drawable_set_device_anchor` is only called on a successful ARKit query; the old log printed
`anchor=0/1` per 120 frames but never counted failures. If the anchor is never set the compositor
cannot reproject the frame. *Fix:* `anchorFails` is counted and printed in the per-120-frame line and
in the exit summary, and tracking is only pushed when the anchor is valid.

**F7 — window parking hid every window (`isHidden=true` + `alpha=0`) immediately on open.**
The 14:41 log shows parking followed by `UIScene.willDeactivate` in the *same second* (and earlier
runs show the same pattern delayed). Hiding the app's only windows is a plausible trigger for the
window-scene deactivation that then backgrounded the app. *Fix (shell):* parking is **alpha-only**
(`alpha=0`, `isUserInteractionEnabled=false`; `isHidden` is never set by default), happens **only after
`VRMCCompositorRunning`** (first presented frame), and can be disabled with
`vrmc-no-parking.flag` / restored to the old hide behaviour with `vrmc-hide-windows.flag` for A/B.
`NO-FRAME` now logs heartbeats and **leaves the immersive space open** (no dismiss, no retry).

### Kept-but-not-changed risks (for the next run to measure)

- Colour management: the drawable is `rgba16Float` linear-ish and the sampled provider texture is
  `RGBA8Unorm` (`fmt=70`), so the game's dark menu world (readback luma ~14–60 in EV-0090) lands in the
  display through a linear→display conversion. A very dark scene can read as "black" to the operator on
  an OLED HMD. The drawable readback dump compares like-for-like with the provider readback and settles
  this: if `vrmc-drawable-L.meta` `meanLuma ≈ provider tex luma` then the compositor pipeline is
  faithful and the remaining question is content brightness.
- `cp_view_get_tangents` is deprecated (visionOS 2.0) but still used for display-view publication; the
  derived tangents are logged next to it for cross-checking. Not a present-path issue.
- ARKit authorization is not explicitly requested (world tracking has been returning success —
  `anchor=1` — so it is granted in this app's configuration); failures are now counted.

---

## 2. What the new diagnostics will prove (truth table)

Ordered from cheapest to run to most decisive. All are device flags in `Documents/`; no rebuild needed
after the framework is staged.

| Flag / artefact | What it proves |
|---|---|
| `vrmc-drawable-L.raw` / `-R.raw` + `.meta` (automatic: frames 0–2 and every ~300) | **Exactly what was rendered into the presented drawable.** Non-black image → the render/present encode works; black → the render pass did not execute (see `RENDER ENCODER IS NIL` / `DRAWABLE COLOR TEXTURE IS NIL` log lines) or a format mismatch was logged. View it as 64×64 RGBA8 (`raw` 16 KiB, little-endian RGBA). |
| `[vrmc-comp] drawable proof … mean=… topStripLuma=… centreLuma=…` | Same, numeric. `topStripLuma` high = mode badge reached the drawable; a mode badge is drawn by every path (red=reproj, green=flat, blue=test). |
| `[vrmc-comp] drawable topology: count=… mainTarget=…` + per-drawable lines | F1: how many drawables the frame had and whether a `built_in` one was among them. |
| `[vrmc-comp] view N attachments: color=… fmt=… type=… arrayLength=… depth=…` | F2: real attachment presence/format/type/slice; mismatch with `pipelines color=…` would explain a dropped draw. |
| `vrmc-clear-probe.flag` | Clear-only magenta (left) / cyan (right), **no draws**. If the operator still reports black → no drawable reaches the display (presentation-layer/system issue, not our shader). If magenta/cyan appear → the readback/`present` path is sound. |
| `vrmc-present-proof.flag` | Bright 8 px white/cyan checker border + magenta centre cross drawn per view on top of the normal content. Operator reports "border visible" → unambiguous presentation proof; "black" → present path. |
| `vrmc-immersive-selftest.flag` | Opens the immersive space **without the game/JIT** ~4 s after launch (shell-side), compositor draws the test pattern + proof overlay and dumps the drawables. Isolates "is device presentation broken?" from the game, Vulkan/MoltenVK, the provider and the JVM. |
| `vrmc-present-wait.flag` | Replicates the EV-0074 probe exactly (`[cb waitUntilCompleted]` before `end_submission`); A/B for the "no-wait" difference if the selftest is still black. |
| `[shell] VRMCCompositorRunning …`, `NO-FRAME …`, `window parked … mode=alpha-only (never isHidden)` | F7: parking now happens only after a presented frame and never hides windows; a NO-FRAME session leaves the space open with heartbeats so logs can be pulled. |

**Diagnosis matrix for the next run**

| Drawable readback | Screen | Conclusion |
|---|---|---|
| non-black | content visible | fixed / content brightness is the only remaining question |
| non-black | black | render+encode correct, **presentation/composition is broken** — the drawable topology log says whether `built_in` existed; escalate to system-level (clear-probe + selftest confirm) |
| black (uniform clear colour missing) | black | render pass did not execute — the log names nil texture / nil encoder / format mismatch |

---

## 3. Implemented changes

### `runtime/native-shell/Sources/VRMCCompositor.mm` (+~600 lines net)

1. `cp_frame_query_drawables()` → render **and present every** drawable; log topology
   count/target/views/textures/rate-maps (once, and whenever count > 1); prefer `built_in` for ARKit
   tracking and display-view publication; warn when no `built_in` is present.
2. Pipelines built from the layer configuration, then lazily rebuilt from the actual drawable
   attachment formats; nil colour texture, nil depth texture, nil render encoder, attachment
   format/type/arrayLength/slice all logged with context.
3. Drawn-drawable readback/dump (`encodeDrawableProbe`) with 64 strided full-width rows per eye,
   64×64 RGBA8 decode, stats + `vrmc-drawable-L/R.raw` + `.meta`; supports `RGBA16Float` and
   8-bit RGBA/BGRA (any other format logs a skip instead of silently doing nothing).
4. Shader: new `fmain_proof` fragment (8 px checker border + magenta centre cross, interior
   discarded); new `pipelineProof`; flag `vrmc-present-proof.flag` / `vrmc-immersive-selftest.flag`.
5. `vrmc-clear-probe.flag` (clear-only magenta/cyan), `vrmc-drawable-dump.flag`,
   `vrmc-present-wait.flag`; all flags logged at startup.
6. Never `cp_frame_end_submission` without a presented drawable; empty drawable arrays abandon the
   frame before opening the submission; rate-map index bounded by `cp_drawable_get_rasterization_rate_map_count`.
7. Device-anchor failure counting + exit summary (`presentedFrames`, `framesWithoutDrawable`,
   `framesWithoutEncoder`, `anchorFails`).
8. Posts `VRMCCompositorRunning` (with generation) on the first presented frame — the shell's parking
   trigger.
9. Wire the additive bridge eye-frame API (bridge-sync, `bridge/abi/vrmc_native_shared.h`):
   `vrmc_shared_acquire_eyes()` every frame (atomic struct, never cache handles), `texture_generation`
   change logging, eye-texture `usage`/`shaderRead` logging, and `[cb encodeWaitForEvent:value:]` once
   per command buffer before the first sampling pass when `sync.valid != 0` (no-op otherwise), with a
   TODO hook for a future `waitForEvent`-only API shape. Legacy `vrmc_shared_eye_textures` fallback is
   kept for older bridge builds.

### `runtime/native-shell/Sources/Shell.swift`

1. **Startup flag neutralisation** (before `VRMCShellApp.main()`, i.e. before any autolaunch flag can be
   consumed): `Documents/vrmc-clear-diagnostics.flag` deletes `vrmc-test-pattern.flag`,
   `vrmc-reproj-off/on/debug.flag`, `vrmc-no-sampling.flag`, `vrmc-legacy-root-swap.flag`,
   `vrmc-immersive-on-launch.flag`, `autolaunch.flag` and itself, logging one line per deletion
   (`clear-diagnostics: deleted <name>`; failures are logged too).
2. **Safe window parking**: alpha-only (never `isHidden`), non-interactive, performed only after the
   `VRMCCompositorRunning` notification (first presented frame). `vrmc-no-parking.flag` disables it;
   `vrmc-hide-windows.flag` restores the old hide behaviour for A/B. Window state
   (`hidden/alpha/level`) is logged on every lifecycle transition.
3. **NO-FRAME**: after open, an 8 s watchdog waits for a presented frame; on timeout it logs
   `NO-FRAME … leaving the immersive space OPEN (no dismiss, no retry)` plus 3 heartbeats, and never
   dismisses the space.
4. **Immersive self-test** (`vrmc-immersive-selftest.flag`): opens the immersive space ~4 s after app
   launch without `VRMCGameStarted`, without the JVM/JIT, without parking; retries for up to 15 s while
   the scene activates. Fresh-process capable: the shell is `dlopen`ed from Amethyst's `main.m` before
   `UIApplicationMain`, so no game/JIT is required to reach it.
5. Kept: epoch-guarded open/dismiss, foreground-active gating, confirmed dismiss+settle, stale
   generation filtering, bounded auto-retry on real layer invalidation (now also allowed in selftest),
   chrome mode logging.
6. **willResignActive grace period (1.8 s)**: a transient scene deactivation no longer ends the
   session. `willResignActive` only cancels `appActive`/`windowSceneActive` and arms a grace timer;
   `didBecomeActive` within 1.8 s cancels it (logged `willResignActive cancelled by didBecomeActive
   (compositor not stopped, grace 1.8 s)`), and only `didEnterBackground` or the timer expiry
   (`willResignActive grace expired; stopping the compositor`) calls `VRMCCompositor_RequestStop()`.
   This implements the sim-lifecycle recommendation: parking was lifecycle-safe in the simulator matrix
   and the device pattern is better explained by a transient scene deactivation than by parking.

### Decisive log lines (the four the Lead asked to confirm)

1. **`forceTestPattern`** — logged at startup per session in
   `diagnostics: reprojMode=… debugShading=… samplingDisabled=… forceTestPattern=… presentProof=… clearProbe=… dumpRaw=… presentWait=… selfTest=…`,
   and again on every active-state change as
   `TEST PATTERN state changed: active=%d haveEyes=%d samplingDisabled=%d forceTestPattern=%d autoTestPattern=%d selfTest=%d`
   (so a frame that switches into/out of the forced pattern is visible in the log).
2. **Drawable array count / target** — every 120th frame:
   `frame %d … arrayCount=%zu targets=[b,c] presented=%zu encNil=%d nilColor=%d …` (b = built_in,
   c = capture), plus a distinct per-frame line while count > 1:
   `MULTI-DRAWABLE frame=%d count=%zu: the frame hands out more than one drawable; all are rendered and
   presented, built_in drives tracking/display views`. The full per-drawable topology
   (`drawable topology: count=… mainTarget=… views=… textures=… rateMaps=…` plus one line per drawable)
   is logged on the first frame and whenever the count changes.
3. **`enc == nil`** — logged once with full context
   (`RENDER ENCODER IS NIL (drawable=… target=… view=… color=…x… fmt=… type=… depth=… viewport=…) -
   no clear and no draw reaches this drawable`); the counter is printed as `encNil=%d` in the per-120
   frame line and in the exit summary (`framesWithoutEncoder`).
4. **Drawable colour/depth attachment nil/format/type/slice before encoding** — per view on the first
   frame: `view %d attachments: color=%p %lux%lu fmt=%lu type=%lu arrayLength=%lu slice=%zu | depth=%p
   %lux%lu fmt=%lu type=%lu | rateMapCount=%zu`, plus `DRAWABLE COLOR TEXTURE IS NIL (drawable=…
   target=… view=… texIndex=… textureCount=…)` when a colour texture is nil and `nilColor=%d` in the
   per-120 frame line. The pipeline formats actually used are logged as `pipelines color=… depth=…`
   (and a rebuild is logged if they differ from the drawable attachments).

### Files changed
- `runtime/native-shell/Sources/VRMCCompositor.mm`
- `runtime/native-shell/Sources/Shell.swift`
- (`Bridging.h` unchanged — no new C entry points needed; notifications are ObjC.)

### New Documents flags (all optional, all logged)

| Flag | Side | Effect |
|---|---|---|
| `vrmc-present-proof.flag` | compositor | bright checker border + magenta centre cross per view |
| `vrmc-clear-probe.flag` | compositor | clear-only magenta left / cyan right (no draws) |
| `vrmc-drawable-dump.flag` | compositor | always write `vrmc-drawable-L/R.raw` on probe frames |
| `vrmc-present-wait.flag` | compositor | wait for GPU completion before `end_submission` (EV-0074 parity) |
| `vrmc-immersive-selftest.flag` | shell+compositor | open immersive without the game; force test pattern + proof + dumps |
| `vrmc-no-parking.flag` | shell | never touch the windows |
| `vrmc-hide-windows.flag` | shell | old `isHidden=true` parking (A/B only) |
| `vrmc-clear-diagnostics.flag` | shell | startup deletion of the diagnostic flags listed above |

Flag read at startup only: pushing/removing these flags requires an app relaunch (not a reboot), except
`vrmc-clear-diagnostics.flag`, which is processed on the next launch.

---

## 4. Verification performed (host only)

- Build: `xcodebuild -project runtime/native-shell/VRMCShell.xcodeproj -scheme VRMCShell -configuration
  Debug -destination 'generic/platform=visionOS' CODE_SIGNING_ALLOWED=NO -derivedDataPath
  /tmp/vrmc-shell-dd build` → `** BUILD SUCCEEDED **` (framework product:
  `/tmp/vrmc-shell-dd/Build/Products/Debug-xros/VRMCShell.framework`, 498192 B; the checked-in
  `runtime/native-shell/build/VRMCShell.framework` staging copy was not touched).
- MSL: the shipping `kShaderSource` (including the new proof fragment) extracted and compiled with the
  host Metal runtime (`newLibraryWithSource`) → `SHADER COMPILE OK: functions=fmain_test fmain_proof
  fmain_reproj fmain_flat vmain`.
- Warnings: only the pre-existing `cp_view_get_tangents` deprecation remains in the compositor; no
  warnings in `Shell.swift`.
- Not run: device execution (Lead-only), simulator (CompositorServices layer lifetime differs on the
  simulator; not evidence for the black-presentation question).

## 5. Residual risks / next-run notes

1. If the next run is still black **and** the drawable readback is non-black, the remaining fault is
   above Metal: the system is not compositing the drawable we wrote. Run
   `vrmc-clear-probe.flag` + `vrmc-immersive-selftest.flag` (no game/JIT) and pull
   `vrmc-drawable-L/R.raw`: this separates "our encode is wrong" from "CompositorServices display is
   wrong" in one session, and the `drawable topology` line names how many drawables/targets the system
   offered.
2. `isFoveationEnabled=false` with `layout=.dedicated` produced viewport (0,0,1888,1792); the new
   rate-map count log will confirm whether any rate map is attached at all. If one is present, the
   pass is now guaranteed to use a bounded index.
3. Colour/brightness: the 16:39 provider textures were bright (luma ~105) while EV-0090's were dark
   (luma ~14–60). Compare `vrmc-drawable-L.meta` `meanLuma` with the `provider tex L` log line of the
   same run to tell "dark content" from "pipeline darkening".
4. The shell flag neutralisation covers `autolaunch.flag`/`vrmc-immersive-on-launch.flag`; for a
   selftest run push `vrmc-clear-diagnostics.flag` + `vrmc-immersive-selftest.flag` together if the
   container may still hold an old on-launch flag.
5. The bridge eye-frame API requires the rebuilt `libvrmc_bridge.dylib` (bridge-sync) to be staged
   together with this framework; without it the compositor falls back to `vrmc_shared_eye_textures`
   (no GPU timeline wait).

---

## 6. RESOLVED (2026-11-01 late): the black immersive was the drawable depth clear value

The hypotheses in §4/§5 were superseded by a device A/B (EV-0093):

- The M3b commit `1b3b73c` changed the drawable depth clear from **1.0** to **0.0**
  (`rp.depthAttachment.clearDepth = 0.0`, "flat image at infinity"). The known-good M3A probe
  (EV-0074) clears to 1.0.
- On D1, depth clear **0.0 -> black layer** (even with a bright drawable readback, valid encoder and a
  completed command buffer), depth clear **1.0 -> magenta/cyan visible** immediately (operator
  confirmed), same shell/compositor/app.
- Fix: default is 1.0 again; `vrmc-depth-zero.flag` keeps the old value for A/B. Regression guard:
  `scripts/tests/DepthClearRegressionTest.sh`.
- Consequence for verification: the **simulator does not reproduce** this failure (it displayed fine
  with 0.0), so simulator output is not evidence for the CompositorServices presentation path. The
  active controls are (a) the known-good M3A probe and (b) the drawable readback + scene-activation
  logs, with the operator's observation as the decisive report.
- The F1/F2 candidates in §4 (multi-drawable handling, nil encoder) were ruled out for this bug: the
  deprecated/array API and the clear/pattern paths all behaved identically under the depth A/B.
