# ADR-0006 — Licensing, ownership gate, and sideload-only distribution

**Status:** Accepted (2026-10-31)
**Related:** AGENT §10.4–§10.6; `THIRD_PARTY_NOTICES.md`; `LICENSE`; `provider/LICENSE`

## Context

The app derives from Amethyst-iOS (**GPL-3.0**), a fork of PojavLauncher_iOS. It runs Minecraft
(proprietary, EULA-governed), loads Vivecraft (**LGPL-3.0**), and ships on a platform where a game
launcher conflicts with App Store guideline 2.5.2 (downloading/executing code) and where Ad Hoc
distribution does not exist. The prior-art app is sideload-only with an ownership gate.

## Decision

1. **VRMC app code is GPL-3.0.** Corresponding source is published for every distributed build.
2. **`provider/` is LGPL-3.0**, shipped as a separate, replaceable artifact with source.
3. **Vivecraft is unmodified** by default (ADR-0004); users install it from the official source.
4. **No Minecraft binaries or assets are committed or redistributed.** The launcher downloads them
   from Mojang endpoints and enforces an ownership gate: the device unlocks for play only after an
   account that owns Java Edition has signed in once. Offline profiles are single-player only.
5. **Distribution is sideload-only for the MVP** (SideStore/iloader, plus the JIT-enablement path).
   No App Store, TestFlight, or Ad Hoc claim is made.
6. Notices and pins ship with releases; `versions.env` records the exact components per build.

## Consequences

- The product is fully open source and cannot be closed-source without replacing the Amethyst-derived
  code.
- App Store distribution is treated as a separate, legally-gated future workstream (guideline 4.7
  emulator carve-out + EULA strategy), not an MVP objective.
- Sideload friction (free-account re-signing, JIT enablement) is a product constraint and must be
  handled in onboarding and docs.
- GPL/LGPL obligations are release blockers, tracked as AC-6.

## Alternatives considered

- **Clean-room launcher to avoid GPL.** Rejected for MVP speed: re-implements auth/download/install
  plumbing that Amethyst already proves.
- **Bundle Vivecraft and Minecraft to simplify install.** Rejected: EULA and licensing violations.
- **App Store first.** Rejected: guideline 2.5.2 and GPL conflict; would force an AOT, no-mods
  product.
