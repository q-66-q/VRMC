### EV-0031 — MC 26.2 on D1: Amethyst JIT + Java 25 work; boot aborts on missing LWJGL 3.4.1 spvc

| Field | Value |
|---|---|
| Date | 2026-10-31T18:00:12-10:00 |
| Commit | `b772c7938a783acbe8f7648c69e7eb86f9332d38` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `PARTIAL` |

**Procedure:**

1. install Java 25 as Amethyst external runtime; enable debug_always_attached_jit so its dyld bypass loads the external JRE
2. launch Amethyst via StikDebug with amethyst.js assigned, press Play on MC 26.2
3. pull Amethyst latestlog and the Minecraft crash report

**Expected:** MC 26.2 loads LWJGL 3.4.1 and reaches the client bootstrap

**Actual:** JIT26 grants a 240 MB mapping; DyldLVBypass hooks active; Java 25 selected; 'Launching Minecraft 26.2' and NativeLibrariesBootstrap run. Crash: 'Loading library spvc' NoClassDefFoundError org/lwjgl/util/spvc/Spvc. Log shows LWJGL 3.3.3-snapshot; the release IPA has no lwjgl_versions.txt/3.4.1 assets.

**Artifacts:** evidence/EV-0031/latestlog.txt (5f22324596c1); evidence/EV-0031/crash.txt (3581ff88acc1); evidence/EV-0031/summary.log (8f2231e3dcdf)

**Limitations:** The launch stack is otherwise proven on D1 (JIT, external Java 25, dyld bypass, MC main). Unblock options: newer Amethyst build with LWJGL 3.4.1, full source build (submodules missing in this checkout), or a different launcher/runtime path.
