# VRMC — MC 26.2 on Apple Vision Pro: Amethyst launcher problem export

**Date:** 2026-10-31
**Status:** blocked — Minecraft 26.2 starts its JVM on the Vision Pro, but the launcher build we can obtain
(Amethyst release 1.0 and the current nightly artifact) embeds **LWJGL 3.3.3**, while MC 26.2 requires
**LWJGL 3.4.1**. File-level grafting of 3.4.1 Java classes then crashes inside the app's embedded
3.3.3 `JNI_OnLoadGLFW`.

This folder is the full problem dossier: logs, JVM crash report, evidence IDs, and our patch/signing
scripts.

---

## 1. Goal

Run Minecraft: Java Edition **26.2** (later + Vivecraft) natively on **Apple Vision Pro**, no PC.
Current milestone: get the MC 26.2 client to boot on the headset with Vulkan/MoltenVK.

## 2. Environment

| Item | Value |
|---|---|
| Device | Apple Vision Pro `RealityDevice14,1` (M2), visionOS **27.2** (24N120), Developer Mode |
| Host | MacBook Pro M4 Pro, macOS 27.0.1, Xcode 27.2 |
| App | Amethyst iOS launcher, re-signed by us as `dev.vrmc.amethyst` (free-team profile `<TEAM_ID>`) |
| JIT | StikDebug 3.1.15 on the headset; `amethyst.js` assigned (UniversalJIT26 + Extension) |
| Java | external runtime `Documents/java_runtimes/java-25-openjdk` = OpenJDK **25.0.4** (iOS arm64) |
| Amethyst | release IPA 1.0 (`org.angelauramc.amethyst.95J8WZ4TN8`, Oct 17) and the nightly artifact from nightly.link; both bundle LWJGL 3.3.3 |

## 3. What already works on the headset

- StikDebug JIT26 handshake for the launcher: `[JIT26] Requesting 240 MB` → mapping granted.
- Dyld library-validation bypass (requires Amethyst pref `debug_always_attached_jit = true`).
- External Java 25 runtime loads (needed because MC 26.2 class files are version 69; bundled Java 21
  gave `UnsupportedClassVersionError`).
- Amethyst sets `RENDERER` to MoltenVK automatically for versions with a Vulkan backend.
- MC 26.2 reaches `Launching Minecraft 26.2` → `net.minecraft.client.main.Main.main` →
  `NativeLibrariesBootstrap.loadLibraries`.

## 4. Failure A (release IPA, original)

`Loading library spvc` → `java.lang.NoClassDefFoundError: org/lwjgl/util/spvc/Spvc`.
Log says `Backend library: LWJGL version 3.3.3-snapshot`. The release IPA has
`libs/lwjgl.jar` (3.3.3) only — no `lwjgl_versions.txt`, no `Frameworks/lwjgl34`.

## 5. Failure B (after grafting 3.4.1 Java + natives into the app)

We merged all `JavaApp/libs/lwjgl-3.4.1/*.jar` into `libs/lwjgl.jar`, copied the current source's
`Natives/resources/Frameworks/lwjgl34/*.dylib` into `Frameworks/`, re-signed and reinstalled.
The spvc class error disappeared; the client now crashes with a JVM SIGSEGV:

```
#  SIGSEGV (0xb) at pc=...  pid=2278, tid=83971
# JRE version: OpenJDK Runtime Environment (25.0.4)
# Problematic frame:
# V  [libjvm.dylib+0x57eecc]  jni_GetStaticObjectField+0xe0
#
# Native frames:
# V  [libjvm.dylib]  jni_GetStaticObjectField
# C  [AngelAuraAmethyst+0xa8bb8]  JNI_OnLoadGLFW+0xfc
# C  [AngelAuraAmethyst+0xa8c64]  JNI_OnLoad+0x74
# C  [libjava.dylib]  Java_jdk_internal_loader_NativeLibraries_load
```

Full stack in `logs/hs_err_pid2278.log`. The app binary itself exports/embeds the LWJGL **3.3.3**
JNI code; our 3.4.1 Java classes call it and the JNI static-field lookup fails. This cannot be fixed by
grafting files — the app **must be rebuilt with 3.4.1 natives**.

## 6. What we tried (with results)

1. Amethyst release 1.0 IPA, re-signed for our team → launcher runs; setup/JIT/Java 25 works; MC 26.2
   fails at `spvc` class load (LWJGL 3.3.3).
2. Current nightly artifact from
   `nightly.link/AngelAuraMC/Amethyst-iOS/workflows/development/main/...ipa.zip` → **also LWJGL 3.3.3**
   (no `lwjgl_versions.txt`, `libs/lwjgl.jar` has no spvc).
3. Graft 3.4.1 Java + natives into the installed app → spvc fixed, then JNI_OnLoadGLFW SIGSEGV.
4. External Java 25 runtime + `debug_always_attached_jit=true` + StikDebug assigned script were all
   required to get this far; each is documented in the evidence entries.

## 7. Root cause

The Amethyst binaries we can obtain were built before the current source's multi-LWJGL support.
The **current source tree** (`Amethyst-iOS-main`, commit `c1f3aea`, staging) does support 3.4.1:
`Natives/resources/lwjgl_versions.txt` lists `3.4.1 lwjgl34 sdl`,
`Natives/resources/Frameworks/lwjgl34/` has the 3.4.1 natives, `JavaApp/libs/lwjgl-3.4.1/` has the
jars, and `Natives/JavaLauncher.m` selects the right LWJGL for 26.x. But the zip we have contains
**no git submodules** (`Natives/external/MobileGlues`, `MobileGL`, `AFNetworking`, `fishhook`,
`DBNumberedSlider`, … are empty), so `make payload` cannot build as-is.

## 8. What we need

1. An Amethyst **IPA built from current source** (with LWJGL 3.4.1 support), or
2. A reproducible list/commit to build it: `git clone --recursive` submodules + `make payload` recipe for
   iOS (BOOTJDK path, signing/ldid), or
3. Confirmation whether MC 26.2 is expected to work on any published Amethyst iOS build today.

Questions for the Amethyst maintainers:

- Is the development workflow artifact supposed to include `lwjgl_versions.txt` and
  `Frameworks/lwjgl34`? Ours does not (checked on 2026-10-31), and its `libs/lwjgl.jar` has no
  `org.lwjgl.util.spvc` classes.
- Which build/commit is the first that supports MC 26.x (LWJGL 3.4.1 + SDL) on iOS?
- With the current source, does `make payload` work with the standard submodule set, and what
  `BOOTJDK`/signing variables are expected on a Mac with a free Apple team?
- Any known issue with running MC 26.2 on **visionOS** compatibility (MoltenVK + CAMetalLayer),
  beyond the JIT/Java 25/LWJGL prerequisites?

## 9. Contents

| Path | What |
|---|---|
| `logs/latestlog.txt` | Amethyst launcher log of the grafted-3.4.1 run (JIT, Java 25, MC start, SIGSEGV) |
| `logs/hs_err_pid2278.log` | Full JVM crash report: native frames `JNI_OnLoadGLFW` etc. |
| `logs/crash-2026-10-31_*.txt` | Minecraft client crash reports (`spvc` class error) |
| `logs/summary.log` | Short analysis of the JNI failure |
| `evidence/EV-0029…EV-0032` | Evidence entries: launcher install, StikDebug startup crash, JIT+Java25 progress, JNI mismatch |
| `patches/resign-amethyst.sh` | Our re-sign helper (bundle id / team / profile / 120–157 Mach-O signing) |
| `ENVIRONMENT.txt` | Condensed environment + command line |

## 10. Licensing

Amethyst is GPL-3.0; StikDebug scripts are AGPL-3.0. This dossier is for diagnosis and contains no
product code, no Minecraft assets, and no mod jars. The JRE is GPLv2+CE; our harness code is part of a
GPL-3.0 project.
