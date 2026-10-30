# Hand Tracking and Mapping Specification (`handmap-v1`)

**Status:** Baseline design; implementation and device tuning in progress.
**Related:** ADR-0003, `protocol/PROTOCOL.md` §5, `VERIFY.md` HT-01..HT-20.
**Scope:** visionOS client. The PC receives controller INTENT and poses; it does not perform
gesture recognition.

---

## 1. Goals and principles

1. Both hands, 27 joints, positions and orientations, timestamped and tracked independently.
2. Hands drive **real Vivecraft gameplay** through two virtual Index controllers, not just a
   visual overlay.
3. No stuck inputs: any loss, occlusion, link failure, or profile change releases every
   button/axis derived from that hand within one sample or 120 ms at most.
4. Deliberate gestures with hysteresis/dwell; no accidental attack, menu, or locomotion.
5. Comfortable for long sessions; locomotion is opt-in and exits cleanly.
6. Tunable via a versioned profile; defaults are documented and testable.

---

## 2. Joint model

ARKit `HandSkeleton` provides 27 joints per hand. VRMC uses this order and names:

| ID | Joint | ID | Joint | ID | Joint |
| --- | --- | --- | --- | --- | --- |
| 0 | wrist | 9 | indexTip | 18 | ringIntermediateTip |
| 1 | thumbKnuckle | 10 | middleMetacarpal | 19 | ringTip |
| 2 | thumbIntermediateBase | 11 | middleKnuckle | 20 | littleMetacarpal |
| 3 | thumbIntermediateTip | 12 | middleIntermediateBase | 21 | littleKnuckle |
| 4 | thumbTip | 13 | middleIntermediateTip | 22 | littleIntermediateBase |
| 5 | indexMetacarpal | 14 | middleTip | 23 | littleIntermediateTip |
| 6 | indexKnuckle | 15 | ringMetacarpal | 24 | littleTip |
| 7 | indexIntermediateBase | 16 | ringKnuckle | 25 | forearmWrist |
| 8 | indexIntermediateTip | 17 | ringIntermediateBase | 26 | forearmArm |

Each joint carries `position` (m, world space), `orientation` (unit quaternion), and `radius`
(m). If ARKit does not expose a joint, the adapter emits position 0, identity rotation, radius
0; consumers treat radius 0 as unavailable. `jointCount` is always 27 on the wire.

**Handedness:** `HandAnchor.chirality` is authoritative. Never infer from position. Left/right
must never swap on reacquisition; a swap is a P0 defect.

**Timestamps:** use `HandAnchor.timestamp` (seconds since boot) converted to a monotonic
nanosecond domain, plus the local sample time. Do not use wall clock. A snapshot older than
120 ms is stale and must not drive buttons.

---

## 3. Per-hand features

All distances are normalised by palm size to handle hand-size variation.

- `palmCenter = (wrist + middleKnuckle + ringKnuckle) / 3` (or wrist/middleKnuckle midpoint
  if ring unavailable).
- `palmWidth = max(0.02, |indexKnuckle - littleKnuckle|)`.
- `palmLength = max(0.02, |middleKnuckle - wrist|)`.
- `palmNormal = normalize(cross(indexKnuckle - wrist, littleKnuckle - wrist))`, sign-corrected
  per chirality during calibration so that `palmNormal.y > 0` means palm up. The calibrated
  sign is stored per user/profile.
- `forward = normalize(middleKnuckle - wrist)` (hand forward in world space).
- `indexRay = normalize(indexTip - indexKnuckle)` when the index is extended; otherwise
  `forward`.
- `pinchIndex = |thumbTip - indexTip| / palmWidth`.
- `pinchMiddle = |thumbTip - middleTip| / palmWidth`.
- `pinchRing = |thumbTip - ringTip| / palmWidth`.
- `fingerCurl[i] = 1 - clamp(|tip[i] - wrist| / (palmLength * 1.8), 0, 1)` for index,
  middle, ring, little; `curl = mean(fingerCurl)`.
- `roll = signed angle of palmNormal around the hand forward axis relative to world up`.
- `speed = |palmCenter - previousPalmCenter| / dt`, clamped.
- `facingHead = dot(palmNormal, normalize(headPosition - palmCenter))`; `palmDistance =
  |headPosition - palmCenter|`.

---

## 4. Controller pose synthesis

VRMC sends one controller pose per hand (the grip pose). Vivecraft derives its aim ray from
the controller's `-Z` axis and its item/arm transform from the pose.

- **Grip position:** `palmCenter + forward * 0.02 + palmNormal * 0.00` (metres).
- **Aim direction:** `indexRay` when index extended, else `forward`.
- **Up:** `palmNormal` (orthogonalised). If degenerate, use world up.
- **Orientation:** right-handed basis with `-Z = aimDirection`, `+Y = up`, `+X = up × (-Z)`.
  Quaternion is normalised. The same orientation is used for grip and aim in v1.
- **Position/rotation filtering:** one-euro filter (position min cutoff 1.5 Hz, beta 0.05;
  rotation slerp with alpha 0.35–0.7). Raw skeleton is preserved for diagnostics/skeleton
  transport; the filtered pose drives INTENT.
- **Prediction:** use palm velocity and angular velocity to extrapolate to the host's
  estimated driver time, clamped to 50 ms; prediction decays when tracking is lost. The newest
  ARKit sample is sent immediately; the host may extrapolate further by ≤30 ms.
- **Calibration:** at session start and on "Recenter", define the SteamVR origin from the
  current head yaw/position. Hand poses are transformed by the same rigid transform; no scale.
  A user height calibration adjusts Y only. Store offsets per host profile.

---

## 5. Gestures and thresholds

Defaults below. Thresholds are constants in `MappingProfile` and can be tuned via JSON; each
has hysteresis and a timestamped state machine.

### 5.1 Continuous inputs

| Signal | Press | Release | Output | Notes |
| --- | --- | --- | --- | --- |
| Index pinch | `pinchIndex < 0.25` | `> 0.45` | trigger analog | 80 ms debounce; analog `1 - smoothstep(0.45,0.25)` |
| Middle pinch | `pinchMiddle < 0.30` | `> 0.50` | trackpad click / use | edge + 60 ms debounce |
| Ring pinch | `pinchRing < 0.32` | `> 0.52` | jump (locomotion) | edge only |
| Fist | `curl > 0.75` | `< 0.55` | grip analog/click | edge + 120 ms debounce |
| Palm up | normal.y > 0.55 | < 0.35 | locomotion engage | 150 ms dwell |
| Palm to face | `facingHead > 0.60` and distance 0.15–0.60 m | < 0.4 or distance out | menu dwell | 350/900 ms |
| Palm down low | normal.y < −0.5 and hand.y < head.y − 0.25 | normal.y > −0.2 | sneak while held | 250 ms dwell |
| Index extended | `indexCurl < 0.3` | > 0.5 | aim quality | hysteresis |

`triggerClick`/`gripClick` are separate booleans set at the press threshold; `trigger`/`grip`
remain analog for Vivecraft. A release always clears both.

### 5.2 Locomotion ("palm joystick")

- Engaged by holding the **left** palm up (right in left-handed mode) for 150 ms while not
  palm-to-face and not in a menu. A subtle wrist HUD shows the mode.
- Anchor at the palm position at engagement. While engaged, transform hand displacement into
  head-yaw-relative axes:
  - `stickX = deadzone(dx / 0.15 m, 0.08)`, `stickY = deadzone(-dz / 0.15 m, 0.08)`.
  - Full deflection at 15 cm; clamp to ±1. Smooth with a 60 ms low-pass.
- **Turn:** hand roll around the forward axis (or yaw relative to head) maps to right-stick X:
  `turn = clamp(handYaw - headYaw, -60°, +60°) / 45°`, deadzone 0.12. Do not turn while
  palm-to-face/menu.
- **Jump:** a quick upward flick (>8 cm in 120 ms) or ring pinch (one edge), mapped to left
  stick click (jump in Vivecraft's knuckles defaults). Cooldown 250 ms.
- **Sprint:** hold fist + forward stick >0.9 for 300 ms (optional; mapped to double-tap W if
  the profile enables it).
- **Exit:** palm not up for 100 ms, fist, menu, tracking loss, or session loss → all sticks 0
  and jump released within one sample. No inertia.
- **Safety:** locomotion is disabled while palm-to-face is detected and for 200 ms after a
  menu closes. The debug HUD shows the stick vector and turn rate.

### 5.3 Buttons and menus

| Action | Default gesture | Virtual controller input | Vivecraft default binding |
| --- | --- | --- | --- |
| Attack / break | Right index pinch (hold) | `trigger` + trigger click | `key.attack` (right trigger) |
| Use / place / consume | Right middle pinch | trackpad click | `key.use` (right trackpad click) |
| Grab/release | Right fist | grip click/analog | contextual/grip actions |
| Hotbar previous/next | Left/right fist click | grip click L/R | hotbar prev/next |
| Inventory | Left palm-to-face 350 ms | left A | `key.inventory` |
| Game menu | Left palm-to-face 900 ms | left B | menu / long-press keyboard |
| Radial menu | Right palm-to-face 700 ms (optional) | right B | radial menu |
| Sneak | Right palm-down low, hold | right A | `key.sneak` |
| Jump | Locomotion flick / left ring pinch | left stick click | `key.jump` |
| UI select | Either index pinch | trigger click | GUI left click |
| UI scroll | Right palm-up hand roll while inventory | right stick scroll | GUI scroll |
| Keyboard/chat | Game menu + point/pinch | left B + trigger | Vivecraft keyboard |

**Dwell rules:** a palm-to-face dwell timer starts only when the palm is stable and facing the
head; it resets if the condition breaks for >150 ms. Short vs long is decided at release:
<700 ms → inventory; ≥900 ms → menu. The 700–900 ms band triggers inventory only and shows a
"hold for menu" hint; it must not trigger both. Menus are suppressed during active
attack/use/locomotion to avoid accidents.

### 5.4 Two-handed interactions

Controller states are independent; Vivecraft handles the semantics:

- **Bow:** main-hand trigger held while offhand grip/trigger nocks/draws. Both hands' poses
  are sent; no special chord needed. Verify arrow release and no stuck trigger.
- **Shield/food:** offhand grip/use while main hand attacks; independent.
- **Climbing:** both hands' grip/trigger states; Vivecraft contextual module handles it.
- **Menu pointing:** either hand can point; the last hand to pinch owns the UI pointer until
  release.

No gesture requires both hands to be tracked simultaneously except the interaction itself; if
one hand is lost, the other remains functional and the lost hand releases.

---

## 6. Left-handed mode

- The profile mirrors roles: dominant hand = left; locomotion hand = right; menu hand = right.
- The driver swaps left/right controller poses and intents so Vivecraft's left-handed setting
  sees the main hand on the correct side. Mirroring is applied consistently to buttons,
  trackpad, and skeleton.
- World axes are **not** mirrored; forward remains the user's gaze direction.
- Test HT-19 explicitly; a broken mirror is a P1 defect.

---

## 7. Tracking loss, occlusion, and recovery

Per hand:

```text
searching ──tracked──▶ tracking ──stale/lost──▶ degraded (hold ≤120 ms) ──▶ lost
     ▲                    │                                               │
     └────3 good samples──┴──────────────── reacquire ────────────────────┘
```

- `tracked`: emit at sensor rate.
- `degraded`: hold the last pose for up to 120 ms while ARKit reports not-tracked/stale; keep
  analog values but mark INTENT trackingState=degraded; do not start new button presses.
- `lost`: release all buttons/axes, send one invalid INTENT, stop skeleton/pose updates as
  valid, show a ghost hand. Do not close the session.
- Reacquire: require 3 consecutive tracked samples, re-anchor pose offsets, re-arm gestures;
  do not fire a menu/attack from the reacquisition motion.
- Occlusion by torso/hair typically produces `lost` quickly; recovery target ≤1 s.
- Both hands lost → session stays alive; locomotion and inputs released; HUD prompts.

Link loss (UDP/control) uses the same release path even if hands are tracked; the client stops
sending INTENT and the host releases after its stale timeout (≤250 ms).

---

## 8. Profile and calibration

`MappingProfile` fields (JSON, versioned):

```json
{
  "id": "handmap-v1",
  "pinchIndexPress": 0.25, "pinchIndexRelease": 0.45,
  "pinchMiddlePress": 0.30, "pinchMiddleRelease": 0.50,
  "pinchRingPress": 0.32, "pinchRingRelease": 0.52,
  "fistPress": 0.75, "fistRelease": 0.55,
  "palmUpPress": 0.55, "palmUpRelease": 0.35,
  "locomotionDwellMs": 150, "locomotionRangeMeters": 0.15,
  "turnRangeDegrees": 45, "jumpFlickMeters": 0.08,
  "menuShortMs": 350, "menuLongMs": 900,
  "predictionMaxMs": 50, "staleMs": 120,
  "leftHanded": false,
  "palmNormalSignLeft": 1, "palmNormalSignRight": 1
}
```

Calibration procedure:

1. Hold both palms up at chest height; capture palm normal sign per hand.
2. Look forward; recenter head yaw and set SteamVR origin.
3. Set height; confirm 1 block ≈ 1 m at eye level.
4. Test pinch/fist thresholds with the HUD; adjust if the user cannot reach them.
5. Persist profile per host/user. Never silently change thresholds between sessions.

---

## 9. Failure/edge cases

| Case | Required behavior |
| --- | --- |
| Hand leaves FOV | degraded→lost; release all; ghost; reacquire ≤1 s |
| Hand behind torso/head | same; no pose marked valid after 120 ms |
| Hands touch/cross | no chirality swap; independent states |
| Pinch jitter near threshold | hysteresis prevents chatter; debounce 60–80 ms |
| Fist during locomotion | exit locomotion; release sticks; grip click per profile |
| Palm-to-face during attack | menu suppressed; attack continues until release |
| Fast slash/bow | prediction clamped; no stuck trigger; INTENT at sensor rate |
| Tracking permission denied | UI explains; settings link; no session claim of hand input |
| Left-handed switch | all roles mirrored; no stale buttons |
| Profile change mid-session | release all first, then apply |
| Link loss | release all; host invalid after 250 ms |
| System menu/interruption | app resigns active → release all; on resume recalibrate |

---

## 10. Verification

- Unit tests with synthetic joints: thresholds, hysteresis, dwell, mirroring, loss.
- Manual HT-01..HT-20 and MT-04..MT-07; false positives/negatives recorded.
- Device measurement: joint rate, pinch false-positive rate (target <1 per 5 min idle), menu
  accidental activation (<1 per 10 min play), recovery time.
- Usability target: a new user can move, look, mine, place, open inventory, and turn within
  10 minutes of guided onboarding. Record actual times; tune the profile if not met.
- This document describes the baseline; any threshold change must update the profile version
  and `VERIFY.md` evidence.
