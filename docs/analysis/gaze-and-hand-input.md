# Gaze + hand input (M4-W2) — operator requirements, API findings, and plan

Status: **IMPLEMENTED OFFLINE (EV-0098); smooth hands implemented (EV-0097). Runtime/device NOT RUN.** (2026-11-01, after the EV-0096 on-device input acceptance).
Owner: Lead. This note records the operator's requested interaction model and the exact visionOS
APIs available to build it. It is the design input for the M4-W2 work; nothing here is implemented or
verified yet.

## 1. Operator requirements (2026-11-01 device session)

1. **Hands move smoothly.** The current W1 slice maps the wrist/aim pose once per frame from the real
   27-joint tracking (verified on device, EV-0096); the operator wants continuous hand motion and a
   stable pointer. (Note: the earlier "only up/down" observation was the deliberately scripted
   synthetic Step-1 input, not real tracking.)
2. **Eyes select — with pinch confirming.** The chosen model is **gaze highlight + pinch**: the system
   highlights what the user is *looking at* (true eye gaze), and a pinch confirms the selection. No
   click-free dwell is required.

## 2. Verified API inventory (Xcode 27.2 / visionOS 27.2 SDK)

### 2.1 What exists (CompositorServices, visionOS 26+)

These are the official gaze-interaction APIs for **custom CompositorServices content** — exactly our
case (our immersive content is a compositor layer, not SwiftUI/UIKit views):

| API | Where | Meaning |
|---|---|---|
| `LayerRenderer.Configuration.trackingAreasFormat` / `.trackingAreasUsage` | CompositorServices | Configure the per-drawable tracking-area textures (MTLTexture format + usage). |
| `Drawable.trackingAreasTextures` | CompositorServices | Per-frame texture(s) where the app renders **tracking-area IDs**; pixel value = `TrackingArea.RenderValue` (0 = no area). |
| `Drawable.addTrackingArea(identifier:)` | CompositorServices | Registers one interactive region for this frame; identifiers must be unique per frame and stable across frames. |
| `TrackingArea.addHoverEffect(.automatic)` | CompositorServices (visionOS 26) | The system renders the **gaze hover effect** over the region after our render pass, using its true-gaze knowledge. |
| `LayerRenderer.onSpatialEvent` + `SpatialEventCollection.Event.trackingAreaIdentifier` | `_CompositorServices_SwiftUI` cross-import overlay (visionOS 26) | Spatial activation events (indirect gestures) arrive on the compositor layer **tagged with the tracking area the user was gazing at** — this is the pinch-confirm signal. |
| `TrackingArea.RenderValue.invalid`, `TrackingArea.Identifier.invalid`, `Properties.trackingAreasMaxValue` | CompositorServices | Bookkeeping for the mask texture. |

Related but not sufficient: SwiftUI `SpatialEventGesture` / `SpatialTapGesture` (gesture locations on
SwiftUI content), `hoverEffect` / visionOS-26 `CustomHoverEffect` with an `isHovered` closure (gaze
hover for SwiftUI views only).

### 2.2 What does NOT exist

- **No public raw eye-gaze ray.** ARKit exposes no eye-tracking provider; `visual_fidelity.h` only
  reports eye-position/device-fit diagnostics for medical/therapeutic compliance. Apps cannot read the
  gaze direction — but the system *does* apply gaze targeting/hover for the APIs above.
- Therefore our aiming/pointer math cannot be derived from eye data; it must come from hand/head pose
  (W1) or from system tracking-area events (W2).

## 3. Chosen design (W2)

### 3.1 Gaze highlight + pinch selection (primary)

Data flow:

~~~
 provider (game) publishes GUI world pose + pixel size + button/tile layout
         |  (new native-shared channel; additive, ABI v3 unchanged or v4 if structs change)
         v
 compositor: build tracking-area mask for the game GUI quad
   - addTrackingArea(identifier = tileId) per interactive tile
   - render tileId render-values into Drawable.trackingAreasTextures (same pass as the sampled eyes)
   - TrackingArea.addHoverEffect(.automatic) -> system draws true-gaze hover highlight
   - LayerRenderer.onSpatialEvent receives pinch events with trackingAreaIdentifier
         |  (bridge: compositor publishes "tile activated" event; provider polls it)
         v
 provider: tile -> GUI pixel coordinate -> InputSimulator mouse click at that pixel
   (the same path GUI clicks already use; the hand-ray gesture path stays as fallback/flag)
~~~

First iteration (lowest risk): tile the GUI quad into a small grid (e.g. 12x8) rather than reading
Vivecraft's widget layout; the system hover highlight then shows a grid cell under the gaze (acceptable
first feedback) and a pinch maps the cell centre to GUI pixel coordinates. A second iteration can use
the real widget/button rectangles (the provider owns the GUI framebuffer and already computes GUI
cursor coordinates in `GuiHandler`), giving button-accurate hover masks.

Fallbacks / flags: keep the W1 hand-ray + hand-pinch path as the default until the tracking-area path
passes an A/B on device; add a flag (`vrmc-gaze-tracking-areas.flag` proposal) and log the activated
tile ids so the device run is triageable. If the layer capability query reports no supported
tracking-areas format, log once and fall back to W1 silently (fail-safe).

### 3.2 Smooth hands (secondary)

- Real 27-joint tracking is already live (EV-0096). Add a smoothing filter (One-Euro) on the derived
  aim/wrist pose, tuned for the ~90 Hz compositor rate.
- Tune gesture thresholds from device data: EV-0096 showed a right-fist engage at ratio 1.24 against
  the current 1.25 threshold (tiny margin) — widen to ~1.30/1.60 or normalise per-hand by palm length.
- Optionally render hands/held item from the joint data (Vivecraft already draws arms from
  `controllerPose`; a full-skeleton visual is a later polish step).

## 4. Verification plan

| Check | Method | Evidence class |
|---|---|---|
| Tracking-area mask geometry (quad -> tile ids -> GUI pixel mapping) | pure JVM unit test (provider) + compositor debug dump of one frame's mask | host |
| Tracking-area layer configuration accepted on device | device log: configured format/usage + per-frame mask texture present | device |
| System hover highlight on true gaze | operator confirmation on D1 (look around the menu; highlight follows gaze) | device (operator) |
| Pinch-confirm activation -> correct GUI click | device log `[VRMC-M4] gaze tile=<id> -> pixel=(x,y) click` + operator sees the menu react | device (operator) |
| No double-activation with the hand-pinch path | A/B flag run: only one action per pinch (`action ... press` once) | device |
| Hand smoothing / fist thresholds | device logs + operator smoothness report | device (operator) |

Note: the visionOS simulator cannot exercise system gaze (same reason the simulator is not hands
evidence, VERIFY §0.7); tracking-area work therefore needs a D1 operator session, while the geometry
and mapping stay headless-testable.

## 5. Risks

- Tracking-area textures add a render pass + a texture per drawable: measure cost and pacing.
- `addHoverEffect(.automatic)` compositing vs our flat sampled image: verify the highlight appears over
  the game image and not behind it (depth-layer interaction).
- Event-to-provider latency and double-press semantics (system indirect gesture + our hand pinch).
- Mapping must account for the GUI's world pose and the eye/image transform; reuse the display-view
  matrices and the `GuiHandler` cursor math instead of inventing a second convention.
- visionOS 26+ runtime requirement: the app deployment target is 27.0 and D1 is 27.2, so this is fine;
  still fail-safe if the capability is missing.

## 6. References

- `docs/analysis/immersive-input.md` (M4-W1 ABI/design).
- `docs/mvp/M4_PLAN.md` §6b (W2 list).
- Apple SDK headers: `CompositorServices.framework/Headers/tracking_area.h`, `drawable.h`,
  `layer_renderer_configuration.h`, `layer_renderer_properties.h`; `_CompositorServices_SwiftUI`
  cross-import overlay (`onSpatialEvent`, `trackingAreaIdentifier`); SwiftUI `hoverEffect`/
  `SpatialEventGesture`. ARKit `visual_fidelity.h` (eye fit only, no gaze ray).
