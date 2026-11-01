# ADR-0008 — M1 app shell: build Amethyst 1.2.0 from source and brand it as `dev.vrmc.vrmc`

**Status:** Accepted (2026-10-31)
**Related:** Sprint-1 T3; M1_PLAN §5a/W1; EV-0036 (source build boots MC world), EV-0037 (app-side
defaults), EV-0039 (build/install tooling); ADR-0006 (GPL-3.0, source publication); ADR-0007 (M1 stack pins)

## Context

Sprint-1 T3 required a final app-shell decision: (a) build Amethyst 1.2.0 from source with our branding
and patches, or (b) pin/re-sign the tested 1.2.0 binary. The product wedge is the launcher itself —
branding, first-run provisioning, JIT readiness UX, input fixes — and ADR-0006 already commits us to
publishing corresponding source for every distributed build. A pin-only route can deliver neither our
UI/provisioning changes nor clean GPL provenance.

The build path is proven, not hypothetical: the 1.2.0 reference tree (with submodules) built a payload
that launched MC 26.2's Vulkan world on D1 (EV-0036), and our first two product patches — forced Vulkan
/ crash-marker defaults (EV-0037) and the visionOS mouse-delta fix (EV-0040) — are native-source edits
that a binary pin cannot carry.

## Decision

1. **Route (a) is the M1 product shell: build Amethyst 1.2.0 from source** (reference tree + submodules
   AFNetworking, DBNumberedSlider, MobileGlues, fishhook), apply VRMC patches, and **brand the app as
   `dev.vrmc.vrmc`** with our display name/icon and first-run layer.
2. **Route (b) — pin/re-sign the tested 1.2.0 binary — is an emergency fallback only.** If the source
   build hits a hard blocker, record the blocker and a transition deadline for the pin route in
   `M1_PLAN.md`; do not silently switch.
3. The pinned build recipe is the one proven in Sprint-1: JDK 8 boot JDK, `make PLATFORM=2 payload`
   with payload deps `native`, `dep_mcmetal`, `dep_ame_vulkan`, `java`, `jre`, `assets`; MobileGlues/
   MobileGL renderer deps are dropped for the Vulkan/MoltenVK path (re-add when non-Vulkan renderers
   are needed). Artifacts: unsigned payload tree `sha256 3d3a7c18…`, signed/test app tree
   `sha256 b1955fac…`, 167 Mach-O, bundle `dev.vrmc.amethyst` for the test phase.

## Status update (2026-11-01)

- Branded `dev.vrmc.vrmc` app installed and accepted from a fresh container (EV-0042/EV-0043).
- Reproducible build committed and tested: `scripts/build_launcher.sh` + `patches/vrmc-m1-amethyst-1.2.0.patch` + `docs/mvp/LAUNCHER_BUILD.md` (EV-0049).
- Remaining W1 items: app icon, first-run layer + JIT readiness checklist.

## Consequences

- W1 becomes: (i) brand `dev.vrmc.vrmc` (Info.plist display name/icon/bundle id, entitlements/profile),
  (ii) first-run layer + JIT readiness (T4/W3), (iii) a repo-committed reproducible build script
  (`scripts/build_launcher.sh`) replacing the manual `/tmp/amethyst-refbuild` steps, (iv) clean-container
  acceptance.
- GPL-3.0 source publication is straightforward: publish the Amethyst 1.2.0 source tree + our patches
  (`Natives/MinecraftOptionUtils.m`, `Natives/SurfaceViewController.m`, build-script deltas).
- The pin route would forfeit our branding/provisioning/input work; it is retained only as a
  one-sprint fallback with an explicit blocker/deadline record.
- M1_PLAN §5a/W1 route text is updated to this decision; T3 closes with EV-0041.
