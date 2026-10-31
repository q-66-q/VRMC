# MVP Scope

**Status:** Accepted 2026-10-31. Register of record: [`AGENT.md`](../../AGENT.md) §4.3.
This file records scope decisions and boundaries; it does not duplicate feature rows.

## MVP statement

A user installs VRMC on Apple Vision Pro, signs in with Microsoft (or uses Offline), installs
Minecraft 26.2 + Fabric + Vivecraft from the launcher, enters a world, and plays in head-tracked
stereo with hands — and with PlayStation VR2 Sense controllers when present — for an hour, with no
PC involved.

## In scope (P0 count: 65 features, rated in AGENT §4.3)

| Area | Boundary for MVP |
|---|---|
| Install/launch | Sideload install, first-run wizard, JIT readiness, permissions, launch/exit, suspend/resume, crash capture, storage |
| Accounts | Microsoft device-code sign-in, offline profile, ownership gate, account list/switch |
| Game install | Pinned 26.2, verified/resumable downloads, Java 25 runtime, memory config, Fabric 0.19.3, Vivecraft 26.2-1.3.15, provider jar, Files import/export |
| Graphics | MC Vulkan via MoltenVK, flat window mode, immersive stereo, head tracking, frame pacing + 45 Hz fallback, resolution presets, debug overlay |
| VR provider | `VisionVR` selection without SteamVR, stereo renderer, action data for all API-visible actions, haptics, IPD/eye offsets/play area |
| Controllers | PSVR2 Sense when available: poses, buttons/sticks/triggers/grips, Touch-style mapping, per-hand takeover |
| Hands | 27-joint skeleton, gesture profile with hysteresis, virtual stick/snap turn/teleport, tracking-loss release, calibration |
| Gameplay | Continue/title/create, locomotion + teleport, seated/standing, interactions, inventory/crafting/chests, pause/options/death, visible hands/items, bow, climbing, save/reload |
| Launcher UX | Home, settings, progress/errors, diagnostics/log export |
| Platform/compliance | Audio, haptics, Files, privacy manifest, GPL/LGPL/EULA obligations |
| Quality | K1–K6 budgets (boot time, frame rate, latency, stability, thermals, footprint) |

## Out of scope (MVP)

App Store/TestFlight/Ad Hoc distribution; AOT builds; PC/cloud streaming; SteamVR/OpenVR/OpenXR
runtime; mod marketplace/CurseForge; shaders/Iris; multiplayer hosting; video streaming; MC 26.3+
until Vivecraft supports it; full-body trackers; pass-through/mixed reality; custom spatial
accessories; localization; cloud save.

## P1 (post-MVP, designed for but not built)

Mod manager UI + Modrinth install; multiple MC versions; join multiplayer servers; voice chat;
system-keyboard chat; controller remap/left-handed UI; mirror window/screenshots/recording;
foveation and dynamic quality tuning; multiple instances; shaders/Iris; pass-through/MR; FBT;
custom spatial accessories; localization; cloud save; App Store feasibility study.

## Key scope decisions

1. **One pinned stack** (26.2 / Fabric 0.19.3 / Vivecraft 26.2-1.3.15) — ADR-0002.
2. **Vulkan/MoltenVK is the primary graphics path** — ADR-0003.
3. **Vivecraft stays unmodified by default; provider via LGPL Mixin mod** — ADR-0004.
4. **PSVR2 Sense first-class; hands-only is the accepted degradation** — ADR-0005.
5. **Sideload-only, GPL-3.0 app, ownership gate** — ADR-0006.
6. **One default instance**; multiple instances are P1.
7. **Hands-only MVP is acceptable** if no PSVR2 Sense hardware is available for testing; F1–F3 then
   move to P1.

## Success criteria

AC-1…AC-6 in [`VERIFY.md`](../../VERIFY.md) §1. The MVP is not "done" because features exist; it is
done when those criteria and budgets K1–K6 have evidence on device.

## Open scope questions

- Does the JIT launch step remain per-launch, and does that require a companion launcher UI outside
  the app? (S1, A2 boundaries)
- Does MC's Vulkan backend hold up under MoltenVK on visionOS? (S2)
- Is Mixin injection stable enough to avoid a Vivecraft fork? (S3, M0 decision)
