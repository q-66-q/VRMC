# ADR-0003 — Emulate two Index controllers from tracked hands

- **Status:** Accepted
- **Date:** 2026-10-29
- **Related:** ADR-0001, `docs/architecture/HAND_MAPPING.md`
- **Verification:** S-01, S-06, S-08 (all NOT RUN)

## Context

Vivecraft consumes SteamVR Input actions and controller poses. Its default Index bindings use
trigger, grip, thumbstick (x/y and click), A/B, trackpad click, and haptics. It also uses
controller poses for aiming, two-handed interactions, and arm rendering. Vivecraft has no
first-class hand-tracking input API on the OpenVR path.

Two broad approaches exist:

1. Emulate two SteamVR controllers from hand tracking.
2. Write a Vivecraft companion mod that injects hands/trackers via its public API or mixins.

## Decision

Emulate **two Index (`knuckles`) controllers** in the virtual SteamVR driver. The visionOS
client converts each hand's 27-joint skeleton into:

- a controller **aim pose** (palm/index-ray) and a **grip pose** (palm centre);
- continuous **trigger** (index pinch), **grip** (fist/curl), and **trackpad/use** (middle
  pinch) values;
- a virtual **left thumbstick** for movement and **right thumbstick** for turning, plus
  click;
- A/B/buttons via explicit, debounced gestures/chords;
- haptic feedback routed back to the hand as a visual/audio cue (no haptic hardware on Vision
  Pro).

The host forwards the resulting controller state and poses to `driver_vrmc` over shared
memory. SteamVR Input maps them through Vivecraft's existing `knuckles` bindings. The full
skeleton is retained in the client for gesture recognition and debug visualisation; the driver
may optionally publish it as an Index skeleton component for future use, but gameplay does
not depend on Vivecraft consuming finger bones in v1.

## Consequences

### Positive

- Vivecraft runs unmodified, with its default bindings and two-handed gameplay.
- Input mapping is testable pure Swift; the PC stays policy-free.
- The controller abstraction is well understood by SteamVR and Vivecraft.
- A controller fallback can use the same driver/host path.
- No LGPL companion mod is required for v1.

### Negative

- Hand gestures must be translated into controller semantics; some actions are indirect and
  may feel less natural than native hand interactions.
- The default Vivecraft bindings use **right trackpad click for use**, not trigger; users may
  need our mapping profile or a custom binding.
- Controller poses are an approximation of hand pose; arm rendering and aim may need offsets.
- SteamVR's action system adds indirection; debugging requires action traces.
- Haptics cannot be felt on Vision Pro; feedback is visual/audio only.

### Neutral

- Finger skeleton data is not required for the core actions, but it is captured end-to-end and
  used for gestures.
- A future companion mod can add native hand interactions (e.g., direct item grabbing) without
  changing the transport.

## Mapping principles

- **Never leave a button held** when tracking is lost, a hand disappears, or the link degrades.
- Hysteresis and dwell prevent chatter; every transition is timestamped.
- Trigger/grip/use are analog where Vivecraft supports it, with click thresholds matching the
  binding profile.
- Locomotion is opt-in (palm-up) and exits cleanly; it must not fire while aiming.
- Menu gestures require a deliberate dwell and are suppressed during active attack/use.
- Left-handed mode mirrors hands and poses but not world axes; tested explicitly.
- Profiles are versioned; the baseline is `handmap-v1` in `HAND_MAPPING.md`.

## Alternatives considered

| Alternative | Why rejected |
| --- | --- |
| Vivecraft companion mod + Mod API | Public API exposes poses/trackers/interact modules but not the full input/render path; still needs SteamVR for the HMD; LGPL derivative and version coupling. |
| Patch Vivecraft to accept hands natively | Unmodified-Vivecraft constraint; LGPL fork; high maintenance. |
| Use OpenXR hand tracking with the WIP Vivecraft OpenXR branch | Branch unmerged/incomplete; would also require an OpenXR runtime on the PC and a visionOS client; far more risk. |
| Controllers only | Fails hand-tracking acceptance. |
| Direct Minecraft input injection (keyboard/mouse emulation) | Cannot express 6DoF aiming, two-handed bow, VR UI, or Vivecraft semantics. |

## Verification

- Unit tests for gestures/mapping (AT-GEST-*, AT-MAP-*).
- Manual HT-02..HT-19 on D1.
- SteamVR action trace (S-08) and in-game interaction tests MT-05/06/07.
- If false positives or stuck inputs occur, fix thresholds/state machine before acceptance.

## Revisit triggers

- S-06 shows the controller abstraction cannot deliver acceptable usability.
- S-08 shows SteamVR rejects synthetic `knuckles` components.
- Vivecraft adds native hand tracking that materially improves the experience.
- A required two-handed interaction cannot be expressed through controller emulation.
