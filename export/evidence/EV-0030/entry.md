### EV-0030 — Amethyst launched via StikDebug dies immediately (attach→continue→detach, no crash report); normal launch works

| Field | Value |
|---|---|
| Date | 2026-10-31T16:59:44-10:00 |
| Commit | `e5ef08c2ae4bfd89e60cdacfcee9dd44bd676e87` |
| Dirty state | clean |
| Device | D1 Apple Vision Pro RealityDevice14,1 (visionOS 27.2) |
| Host | Mac16,7 / macOS 27.0.1 / Xcode 27.2 |
| Status | `FAIL` |

**Procedure:**

1. user launched the re-signed Amethyst via StikDebug Enable JIT to set up Minecraft
2. inspect StikDebug idevice_log, Amethyst latestlog.txt, process list and system crash logs

**Expected:** Amethyst UI stays up under the JIT enabler so Minecraft can be configured

**Actual:** StikDebug sends vAttach, continue and detach within ~28 ms; the Amethyst process is gone afterwards. No new crash report in systemCrashLogs (only the older 12:46 one). A normal devicectl launch keeps the process alive (pid 1889). Amethyst's latestlog stops at version-list startup and shows no account/version installed.

**Artifacts:** evidence/EV-0030/summary.log (277122d69347); evidence/EV-0030/latestlog.txt (563618c7ee51)

**Limitations:** Likely the JIT script/launch path kills the app before setup, or Amethyst aborts at startup when no script is assigned. Workaround to test next: set up Minecraft with a normal launch, then relaunch under StikDebug only for the game JVM.
