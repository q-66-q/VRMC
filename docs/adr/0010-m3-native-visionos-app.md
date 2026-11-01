# ADR-0010 — M3 requires a native visionOS app shell (CompositorServices immersive space)

**Status:** Accepted (2026-11-01)
**Related:** M3_PLAN.md; ADR-0008 (build-from-source shell); S4a (EV-0063/EV-0065); M2 closure (EV-0070)

## Context

M2 proved provider init, stereo eye targets, and zero-copy Vulkan→Metal eye export on device. The
current VRMC launcher is an **iOS-compatibility app** (`PLATFORM=2`). visionOS compatibility apps cannot
declare/open immersive spaces or use CompositorServices, so immersive stereo + head tracking (M3) is
impossible in that shell.

Options: (A) native visionOS app (`PLATFORM=11`) with launcher window + immersive space in one process;
(B) separate native companion app for immersive presentation with IPC/shared textures; (C) keep compat
— ruled out by platform limitation.

## Decision

1. **Route (A) is the product path:** rebuild the launcher as a **native visionOS app**
   (`PLATFORM=11`, `dev.vrmc.vrmc`) hosting the existing launcher window, the JVM/MC, the provider,
   the bridge, and a CompositorServices immersive space in **one process**.
2. The M2 iOS-compatibility build remains only as the M2 test vehicle/fallback; it cannot deliver M3.
3. **M3a spike is the gate:** native build/launch, a minimal CompositorServices immersive space with a
   test pattern and ARKit poses, and — highest risk — hosting MC/JVM/JIT/Vulkan inside the native app.
4. **Fallback (B)** (native companion app + IPC) is approved only if M3a's MC-hosting gate fails; it
   requires a free-team app-slot plan and a new ADR before implementation.

## Consequences

- Build/sign pipeline gains a `PLATFORM=11` variant; bundle id stays `dev.vrmc.vrmc`; JIT is still
  provided by StikDebug/`amethyst.js` (S1b proved native visionOS JIT).
- Re-labelling the bundled JRE/LWJGL/MoltenVK to VISIONOS is done by the existing Amethyst platform
  step (verified approach in S1b; MC retest is the M3a risk).
- The iOS-compat shell will not be developed further for VR presentation; it stays for regression
  coverage of the M2 path.
- M3 planning doc: `docs/mvp/M3_PLAN.md`.
