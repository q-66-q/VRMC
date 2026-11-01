# ADR-0005 — Input model: hands-only MVP; PSVR2 Sense deferred to P1

**Status:** **Amended 2026-11-01 — hands-only MVP; PSVR2 Sense is P1 (out of MVP scope).**
Originally accepted 2026-10-31 as "PSVR2 first-class, hands as fallback"; superseded by the 2026-11-01
scope decision (not a temporary constraint).
**Related:** S5-hands/S5-controllers; AGENT §1.1/§1.2/§4.2/§4.3 G/§4.4/§4.5/§7 M4; `VERIFY.md` §4.2/§4.4/§4.5

## Context

Vivecraft expects two tracked controllers with poses and a large action set (~105 actions). Vision Pro
offers two input families: spatial accessories (PSVR2 Sense via `GCSpatialAccessory` +
`AccessoryTrackingProvider`) and ARKit hand tracking (27 joints, no buttons). No PSVR2 Sense hardware
will be purchased for this project; that is a **permanent scope decision**, so controller support is
not merely BLOCKED.

## Decision

1. **Hands-only is the MVP input path.** ARKit hand tracking (27 joints) synthesizes Vivecraft actions
   through a versioned gesture profile (pinch variants, fist, palm) with hysteresis, tap/hold/drag
   disambiguation, and a virtual stick.
2. **PSVR2 Sense controller support is P1 (post-MVP).** F1–F3 (detect/mapping/takeover) are moved to
   the P1 register; **no F-group code is written until P1** (unverified code is a liability).
3. Hand gestures are the **sole P0 input path, with no controller fallback** — therefore G2 (gesture
   recognition), G3 (locomotion gestures), and G4 (tracking-loss safety) are raised to **HIGH**.
4. Input profiles remain data-driven (`provider.json`) and tunable; hands-only positioning replaces
   the previous "input parity" claim.
5. Out of MVP scope: full-body trackers, custom spatial accessories, keyboard-only VR workflows.

## Consequences

- M4 exit criterion becomes "P0 action checklist passes **from hands**"; M4 can close on schedule.
- M6/AC-4 verification is hands-only; PSVR2 is not checked at MVP exit.
- **Risk:** if hands-only gesture recognition is unstable, M4 blocks with no fallback — this is why
  G2/G3/G4 are HIGH and S5-hands is the only P0 S5 scope.
- Product positioning changes from "two input paths" to "hands-only, deeply optimized hand
  interaction"; no input-parity claim in MVP marketing/docs.
- P1 re-entry requires a new scope decision (not automatic).

## Alternatives considered

- **Buy PSVR2 and ship controller input in MVP.** Rejected 2026-11-01: hardware not purchased; scope
  decision is permanent, not a temporary blocker.
- **Custom OpenVR/SteamVR input emulation.** Rejected: no SteamVR on visionOS.
- **Keyboard/mouse as fallback input.** Out of MVP input scope (flat-window debugging only).
