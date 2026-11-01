# OpenJDK JIT on visionOS 27.2 — blocked on JIT26 / debugger-prepared code memory

**Status:** open problem, need help from people familiar with StikDebug / Apparition / iOS-26-style JIT
(and with OpenJDK `MirrorMappedCodeCache`).

**Bundle contents:** `logs/` (app log, crash reports, StikDebug packet excerpt), `code/` (the harness),
`scripts/` (our allocation-style `0x69` patches to StikDebug's scripts, for diagnosis only), `evidence/`.

---

## 1. What we are trying to do

Run Minecraft: Java Edition's OpenJDK 25 VM on an Apple Vision Pro (visionOS 27.2), inside an
iOS-compatibility app, with **JIT enabled**.

The JRE is Amethyst's prebuilt iOS arm64 OpenJDK 25 (`25.0.4-internal`, from the Pojav/angelauramc
mobile-OpenJDK lineage). It carries the `MirrorMappedCodeCache` patch, so at VM init it requests
executable code memory from a debugger:

```
brk #0x69        with x0 = requested size (allocation style)
```

On iOS 26+/TXM, only memory that an **attached debugger has prepared** can execute, so a normal launch
always traps. The harness is a console-style app (`main()` calls `JLI_Launch`; no UI), installed as
`dev.vrmc.s1a` with `get-task-allow`.

## 2. Current state

- The JVM **does initialize** on device (its `OpenJDK 64-Bit Server VM warning...` line is printed).
- It then traps at:
  `libjvm.dylib BreakGetJITMapping → get_debug_jit_mapping → os::pd_reserve_memory →
  MemoryReserver::reserve → CodeCache::initialize` (`EXC_BREAKPOINT`, `Trace/BPT trap: 5`).
- With **StikDebug 3.1.15** "Enable JIT" on the app, StikDebug launches it suspended, sends
  `$vAttach`, then sends `$D` (detach) about 1 s later — **no `$c` (continue), no breakpoint/script
  activity**. The app then traps as usual.
- We patched all four scripts in StikDebug's `Documents/scripts/` (`universal.js`, `maciOS.js`,
  `legacy.js`, `Geode.js`) to handle allocation-style `0x69` (allocate via `_M<size>,rx`, prepare the
  pages, write the address to `x0`, continue). Verified the files on device. No change.
- StikDebug prefs confirm it targeted our app: `bundleID = dev.vrmc.s1a`,
  `overrideTXMForScripts = true`.

## 3. Environment

| Item | Value |
|---|---|
| Device | Apple Vision Pro `RealityDevice14,1` (M2), visionOS **27.2** (24N120) |
| Host | MacBook Pro M4 Pro, macOS 27.0.1, Xcode 27.2 (27B52), visionOS 27.2 SDK |
| App | `dev.vrmc.s1a`, console-style iOS app (iOS-compat on visionOS), free-team profile, `get-task-allow` |
| JRE | OpenJDK 25.0.4 iOS arm64 (`libjvm.dylib` platform IOS, relabelled/re-signed as needed) |
| Enabler | StikDebug 3.1.15 (installed from its release); pairing file + LocalDevVPN configured |
| Host-side test | same JRE relabelled to macOS works: `[JIT26] mapping at RW=…`, tiers 3/4 |

## 4. What the enabler has to do

Two equivalent options, from the JRE's JIT26 patch and the universal JIT script protocol:

1. **Legacy allocation request**: `brk #0x69`, `x0 = size`. Debugger should allocate RX memory
   (e.g. StikDebug's `_M<size>,rx`), prepare every 16 KiB page as executable
   (`prepare_memory_region`), write the allocated address into `x0`, and continue.
2. **Universal JIT26 request**: `brk #0xf00d`, `x16 = 1` (prepare region), `x0 = 0`, `x1 = size`;
   debugger allocates, prepares, writes address to `x0`, continues.

The JVM in our JRE uses option 1. StikDebug's stock `universal.js` **refuses** `0x69`
(`legacyCommands[0x69]` returns `0xE0000069`), and `maciOS.js`/`legacy.js`/`Geode.js` treat `0x69`
as *in-place* preparation (`x0 = address`, `x1 = size`), which is wrong for the JVM.

## 5. What we tried

1. UIKit, then SwiftUI, then console-style harness. The first two crashed by re-entering UI `main`
   via `libjli apple_main`; the console harness (included) is the one that starts the JVM cleanly.
2. StikDebug Enable JIT with stock scripts → trap at `BreakGetJITMapping`.
3. Patched all four on-device scripts for allocation-style `0x69` and pushed them with
   `devicectl copy to` into `Documents/scripts/`; verified content on device → still trap.
4. Inspected StikDebug `idevice_log.txt`: launch-suspended → `vAttach` → `$D`; no `$c`, no
   breakpoint or script log lines.
5. Confirmed app prefs: StikDebug knows the bundle id; the app is listed and launched.

## 6. Hypotheses

- StikDebug 3.1.15's JIT flow on visionOS 27.2 may only attach/detach to grant `CS_DEBUGGED`, without
  running JIT26 preparation (TXM needs preparation while attached).
- `Documents/scripts/` may be an export/import location rather than the active script set; StikDebug
  may use bundled scripts internally, so our patches are ignored.
- Compatibility-mode (iOS app on visionOS) may be handled differently from native visionOS apps.

## 7. Questions for the community

1. **StikDebug**: Does Enable JIT on visionOS 27.2 support JIT26 preparation for iOS-compatibility
   apps? Which script does it run, where is it loaded from, and how can a user select/import a custom
   script? (We see attach → detach with no continue.)
2. Is there a known-working JIT script for an **allocation-style** `0x69` request
   (`x0 = size`), as opposed to the in-place convention in the shipped scripts?
3. **Apparition**: its blog documents `apparition://enable-jit?...&script-data=…` with a custom
   script. Can the `script-data` flow be used for this JVM request, and can it be triggered without
   on-device UI (e.g. from a Mac / another app)? Any known OpenJDK usage?
4. **Amethyst-iOS / Pojav**: how do you drive `UniversalJIT26.js` on iOS 26+ (StikDebug, Apparition, or
   your own debugger)? Has OpenJDK `MirrorMappedCodeCache` been run on **visionOS 27** anywhere?
5. Is there a documented CoreDevice/debugserver sequence for the private prepare-memory operation
   (`_M`/`prepare_memory_region` equivalents) that we could implement directly?
6. Would a **native visionOS app** (not iOS-compatible) change JIT26 handling on this OS?

## 8. Reproduction

Files included: console harness (`code/main.c`, `code/project.yml`, `code/HelloJit.java`), app log,
crash reports, StikDebug packet excerpt, StikDebug prefs, and our script patches.

Build/launch outline:

```bash
# build: Xcode project with the iOS JRE embedded in Frameworks/jre, HelloJit.class in s1a/
xcodebuild -project S1AProbe.xcodeproj -scheme S1AProbe -configuration Debug \
  -destination 'platform=visionOS,id=…' -allowProvisioningUpdates JRE_DIR=/path/to/jre build
# sign nested JRE dylibs with the development identity, re-sign the app with its .xcent
xcrun devicectl device install app --device … S1AProbe.app
# then, on the headset: StikDebug → Enable JIT → S1AProbe
```

Expected when it works: the app log shows `[JIT26] … mapping at RW=…,RX=…`, then
`HELLOJIT iterations=200000000 …` and `JLI_Launch returned 0`.

## 9. Licensing

- The JRE is GPLv2+CE; the harness is part of an internal GPL-3.0 project.
- StikDebug is AGPL-3.0. The files in `scripts/` are **diff excerpts of StikDebug's scripts, included
  only for diagnosis**; they are not part of our product and must not be redistributed as part of a
  non-AGPL product.
- No Minecraft assets, binaries, or mod jars are included in this bundle.
