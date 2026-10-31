# ADR-0001 — Native JIT launcher on visionOS

**Status:** Accepted (2026-10-31)
**Supersedes:** the retired remote-streaming architecture (`c0ea23b`…`a96e13b` history)
**Related:** ADR-0002, ADR-0003, ADR-0006; `VERIFY.md` EV-0001, EV-0002; AGENT §1, §3

## Context

The goal is to run Minecraft: Java Edition + Vivecraft on Apple Vision Pro with no PC. visionOS
has no JIT entitlement (`com.apple.security.cs.allow-jit` is macOS-only), no usable OpenGL, no
OpenXR runtime, and no SteamVR/OpenVR runtime. A public prior-art app exists
(`rebelancap/vivecraft-visionos`) that AOT-compiles MC 26.2 + Vivecraft with GraalVM native-image
and sideloads it. The previous VRMC attempt streamed from a Windows PC; it was deleted because the
product goal is local execution and the streaming stack was large and latency-bound.

The user selected the JIT-launcher strategy for the MVP: an Amethyst-derived launcher that keeps
runtime version/mod flexibility, accepting sideload-only distribution and GPL-3.0 obligations.

## Decision

Build a **native, local** visionOS app that:

1. bundles/runs an OpenJDK 25 JVM on visionOS (JIT through the debugger-prepared-memory JIT26
   protocol, since there is no JIT entitlement);
2. installs and launches Minecraft 26.2 + Fabric + Vivecraft on-device;
3. presents VR through CompositorServices with input from ARKit hands and spatial controllers;
4. distributes via sideload (SideStore/iloader + a JIT-enablement path), GPL-3.0 source published.

## Consequences

**Positive:** no PC or network in the loop; user-managed versions/mods; reuses Amethyst's
launcher/auth/download logic; VR gameplay logic stays in Vivecraft.

**Negative / accepted:** JIT depends on an external debugger-prepared-memory step per launch
(EV-0002) and on an unbuilt OpenJDK 25 xros runtime (S1, C3); the app must be GPL-3.0; no App
Store/Ad Hoc path; performance and thermals are the dominant product risks (K2/K5).

**Fallback:** if S1 cannot reproduce JIT internally, pivot to an AOT build (GraalVM/prior-art
style) and reduce the MVP to account/play/settings; runtime mod/version management moves out of
scope.

## Alternatives considered

- **Remote streaming (previous architecture).** Rejected: contradicts the no-PC goal, adds latency
  and a Windows/SteamVR dependency, and the stack was already retired.
- **AOT desktop-native for the MVP.** Rejected for now: loses the launcher's differentiator and
  requires a large build pipeline; retained as the S1 fallback.
- **Native Metal rewrite of Minecraft.** Rejected: out of scope for any MVP.
