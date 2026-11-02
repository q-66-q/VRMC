# VRMC hands controls (as installed in the current build)

Status: **implemented/host-verified; real-hands tuning on D1 still NOT RUN.** Gesture thresholds are
tunable from the launcher (Input tuning) or `vrmc-input-tune.properties`; apply live with **Reload input**
or at the next launch. **Controls help** in the launcher prints this summary into Minecraft chat.

## Core (W1, device-accepted EV-0096)

| Gesture | Action |
|---|---|
| Right thumb–index pinch (hold) | Attack / click; GUI left click while a screen is open |
| Right fist tap | GUI right click (menus) |
| Right fist hold | Continuous use (bow draw/fire) |
| Left thumb–index pinch (hold) | Teleport |
| Left fist tap | Escape/menu |
| Both fists tap | Inventory |
| Both hands pinch / climb-grab | Climb grab while touching a climbable |
| Both fists tap chord | Inventory (chord priority: no simultaneous use/menu) |

## Locomotion / core (W3/W4)

| Gesture | Action |
|---|---|
| Left **thumb–middle** pinch hold + move left hand forward/back/left/right | Free-move virtual stick (walk/strafe) |
| Right thumb–middle pinch hold | Sneak |
| Right thumb–middle pinch tap | Jump |
| Left thumb–middle pinch tap / double-tap | Snap turn left / right |
| Right thumb–middle pinch double-tap | Radial menu |
| Both thumb–middle pinch tap | Climb jump |
| Both thumb–middle pinch double-tap | Recenter room origin |
| Both thumbs + ring-finger pinch (chord), move left hand left/right, release | Direct hotbar slot 1–9 (action-bar feedback) |
| Left thumb–index pinch while right fist held | Teleport suppressed during use/bow draw |

## Optional open-hand swipes (`swipe.enabled`, default OFF)

Right hand: swipe left/right = hotbar previous/next; swipe up/down = mouse wheel.
Left hand: swipe up/down = keyboard / chat; swipe left/right = swap offhand / drop item.

## Safety/release invariants

- tracking loss/stale input releases every gesture source and both-hand chords immediately;
- a bow/use hold suppresses teleport until the fist opens;
- ring/trackpad/middle chords cannot trigger their single-hand actions simultaneously;
- no action is latched: releasing the source releases the action (except action-bar feedback).

## Known gaps (device-only)

- Real-hands feel/latency/thresholds, two-hand bow nuance, visible-hands/held-item appearance.
- Collision/occlusion cases and the full AC-4 P0 checklist need D1.
