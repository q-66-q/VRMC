# Short post (community/Discord/GitHub)

**Need help: OpenJDK JIT on visionOS 27.2 — JIT26 code-memory request always traps**

I'm trying to run an OpenJDK 25 VM (Amethyst/Pojav iOS build with `MirrorMappedCodeCache`) inside an
iOS-compatibility app on Apple Vision Pro (visionOS 27.2). The JVM starts, then asks for executable
code memory with `brk #0x69` (`x0 = size`, allocation style) and traps in
`libjvm BreakGetJITMapping` because no debugger prepares the memory.

With **StikDebug 3.1.15 → Enable JIT → select app**, StikDebug launches it suspended, attaches
(`$vAttach`), then detaches (`$D`) ~1 s later — no continue, no breakpoint/script activity. I patched
all four `Documents/scripts/` scripts (`universal`, `maciOS`, `legacy`, `Geode`) to handle
allocation-style `0x69` (allocate with `_M<size>,rx`, prepare pages, put address in `x0`), verified
they are on the device, and it still traps.

Questions:
1. Does StikDebug's visionOS 27.2 JIT flow support JIT26 preparation, and where does it load the
   script from? How do you select/import a custom script?
2. Is there a known script for allocation-style `0x69` (x0 = size) rather than the in-place convention?
3. For **Apparition**: can `apparition://enable-jit?...&script-data=…` be used for this, and can it be
   triggered without on-device UI?
4. Anyone run OpenJDK `MirrorMappedCodeCache` under JIT26 on visionOS 26/27? How does Amethyst drive
   `UniversalJIT26.js` on iOS 26+?

Full report + logs (app log, crash `.ips`, StikDebug packet excerpt, harness code, script diffs) in the
bundle. Environment: AVP `RealityDevice14,1` (M2), visionOS 27.2 (24N120); Xcode 27.2; JRE
25.0.4-internal iOS arm64.

---

## Files to attach/mention

- `logs/s1a-jit.log` — app log from enabler run (JVM init, no JIT mapping).
- `logs/S1AProbe-2026-10-31-1458*.ips` — crash reports: `BreakGetJITMapping` SIGTRAP.
- `logs/crash-control-run-no-enabler.ips` — clean control-run backtrace.
- `logs/stikdebug-excerpt.log` — launchSuspended → vAttach → $D packet sequence.
- `evidence/stikdebug-prefs.plist` — `bundleID=dev.vrmc.s1a`, `overrideTXMForScripts=true`.
- `code/main.c` — console harness calling `JLI_Launch`.
- `scripts/*.patch` — our allocation-style `0x69` changes to StikDebug scripts (AGPL-3.0; diagnosis
  only).
