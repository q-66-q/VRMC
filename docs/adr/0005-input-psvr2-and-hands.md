# ADR-0005 — Input model: PSVR2 Sense first-class, hands as fallback

**Status:** Accepted (2026-10-31); takeover behavior pending S5 verification
**Related:** S5; AGENT §4.3 F/G; `VERIFY.md` §4.4/§4.5

## Context

Vivecraft expects two tracked controllers with poses and a large action set (~105 actions across
two hands, digital/analog, action sets). Vision Pro offers two input families:

- **Spatial accessories** (visionOS 26+): PlayStation VR2 Sense via GameController
  `GCSpatialAccessory`, tracked by ARKit `AccessoryTrackingProvider`; buttons/sticks/triggers/grips
  and haptics available.
- **Hand tracking**: ARKit `HandTrackingProvider`, 27 joints per hand; no buttons, so gestures must
  synthesize actions.

visionOS documents that hand tracking for a held hand stops when a controller is in use; that
behavior is an **assumption pending S5** for our device/OS combination.

## Decision

1. **PSVR2 Sense is the primary input when present**: poses + digital/analog actions + haptics,
   mapped to Vivecraft's Touch-style profile.
2. **Hand tracking is the fallback for hands without controllers**, using a versioned gesture
   profile (pinch variants, fist, palm), with hysteresis, tap/hold/drag disambiguation, and a
   virtual stick.
3. **Per-hand takeover:** each hand uses a controller if one is active, otherwise hand tracking;
   switching must release inputs cleanly and never double-fire.
4. Input profiles are data (`provider.json`), tunable; a debug overlay and gesture tuning screen
   ship in dev builds.
5. Out of MVP scope: full-body trackers, custom spatial accessories, keyboard-only VR workflows.

## Consequences

- The MVP is playable without controllers (hands-only), but the best experience requires PSVR2
  Sense hardware; if none is available for testing, F1–F3 move to P1 and hands-only is the accepted
  MVP.
- The action mapping is the largest usability risk (not feasibility risk); S5 owns the P0 action
  checklist and the ≥90% gesture recognition bar.
- Tracking loss must release inputs; this is an acceptance criterion, not polish.

## Alternatives considered

- **Hands-only MVP.** Kept as the documented degradation path, not the default.
- **Custom OpenVR/SteamVR input emulation.** Rejected: no SteamVR on visionOS; direct action-data
  injection into Vivecraft is simpler.
