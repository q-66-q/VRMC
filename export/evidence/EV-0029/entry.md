### EV-0029 — Amethyst re-signed for <TEAM_ID> installs and launches on D1 (MC boot pending)

| Field | Value |
|---|---|
| Date | 2026-10-31T16:54:26-10:00 |
| Commit | `fcfdd2fbe2eefcc6b9c27900d8e370cae6a296b0` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. take the release Amethyst IPA (arm64, unsigned), change bundle id to dev.vrmc.amethyst, sign 22 nested Mach-O + the app with the free-team profile and get-task-allow entitlements
2. install via devicectl; launch the launcher normally; pull crash logs

**Expected:** the re-signed launcher installs and reaches its UI on D1

**Actual:** install and launch succeed; the AngelAuraAmethyst process remains alive after launch. The only crash log present is an older 12:46 entry, not this run.

**Artifacts:** evidence/EV-0029/summary.log (3f8925e3aaa4); evidence/EV-0029/amethyst-install.log (73c17929df81)

**Limitations:** Launcher only. Minecraft setup, Vulkan world and JIT are still pending; Amethyst bundles UniversalJIT26/Extension and MoltenVK, and needs universal.js assigned in StikDebug before the game JVM starts.
