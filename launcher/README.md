# Launcher (visionOS app)

**Status:** not started. M1 scope.

SwiftUI visionOS app that owns the user experience around the JVM game: first run, accounts,
installs, settings, diagnostics, JIT readiness, and immersive-space handoff.

Planned contents:

- `App/` — SwiftUI scenes, launcher window, immersive-space entry (CompositorServices bridge).
- `Accounts/` — Microsoft device-code auth, Keychain storage, offline profile, ownership gate.
- `Install/` — version manifest, verified/resumable downloads, Fabric/Vivecraft/provider install.
- `Settings/` — graphics presets, comfort, controls, memory, diagnostics.
- `Diagnostics/` — log capture, export, frame graph, version panel.

Constraints:

- GPL-3.0 (ADR-0006).
- No auto-immersion on launch (HIG); one immersive space at a time.
- Never claim device behavior without a `VERIFY.md` EV.
- UI must always expose exit/recenter and comfort controls.

Depends on: `runtime/` (JVM launch), `provider/` (VR actions), `bridge/` (tracking/compositor).
