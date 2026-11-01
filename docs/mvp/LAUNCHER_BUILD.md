# Launcher build — reproducible recipe (W1, ADR-0008)

The VRMC launcher is a branded, patched build of **Amethyst 1.2.0** (GPL-3.0). This document records
how the current device build was produced and how to reproduce it.

## 1. Source provenance

- **Base tree:** Amethyst 1.2.0 source distribution (`VERSION := 1.2.0`), i.e. the tree that owns
  `Natives/resources/lwjgl_versions.txt` and `Natives/resources/Frameworks/lwjgl34`. The public
  `AngelAuraMC/Amethyst-iOS` branches checked on 2026-10-31 (`main` f98c413 = v1.0, `staging` c1f3aea)
  do **not** contain the multi-LWJGL files, so this tree is the 1.2.0 source snapshot, not a branch tip.
  - Base-tree file hash (excluding `Natives/external/*` and `.DS_Store`):
    `sha256 213e505e90c93a6d99623528cc0652e3702f381f4529ef5ad73e8e72170694ce`
- **Submodules populated:** `Natives/external/{AFNetworking, DBNumberedSlider, MobileGlues, fishhook}`.
  (`MobileGL`/renderer deps are not used in this build; see §3.)
- **VRMC patches:** `patches/vrmc-m1-amethyst-1.2.0.patch` (9 files: Makefile build deps; launcher
  Java-25/25-runtime defaults; forced Vulkan + crash-marker; visionOS mouse grab path; TXM
  always-attached JIT; scene lifecycle + audio reactivation; diagnostics).
- **Toolchain:** Xcode 27.2 / visionOS SDK 27.2; Zulu JDK 8 (boot JDK), macOS arm64:
  `https://cdn.azul.com/zulu/bin/zulu8.98.0.107-ca-jdk8.0.512-macosx_aarch64.tar.gz`
  (`sha256 f26e2a91062542cf22ef2171b2556e1c3f42cf87cf174258b3df7840365892aa`).
- **Versions:** see `versions.env` (MC 26.2, LWJGL 3.4.1, OpenJDK 25.0.4, MoltenVK 1.4.3,
  StikDebug 3.2.0, amethyst.js).

## 2. Build

```bash
AME_SRC=/path/to/Amethyst-1.2.0-tree \
BOOTJDK=/path/to/zulu8/Contents/Home/bin \
DEPENDS_DIR=/path/to/cached/depends \   # optional: reuse downloaded JRE zips
scripts/build_launcher.sh
```

The script validates the tree/submodules, rsyncs it to `BUILD_DIR` (default `.build/launcher`), applies
`patches/*.patch`, and runs:

```bash
make PLATFORM=2 RELEASE=0 BOOTJDK=<jdk8/bin> JOBS=<n> payload
```

Output: `artifacts/Payload/AngelAuraAmethyst.app` (bundled `java_runtimes/java-{8,17,21,25}-openjdk`,
`Frameworks/lwjgl33` + `lwjgl34`, `libs/lwjgl33` + `lwjgl34`, `libMoltenVK.dylib`).

## 3. Deviations from upstream, by design

- Payload deps are `native`, `dep_mcmetal`, `dep_ame_vulkan`, `java`, `jre`, `assets`. `dep_mg`
  (MobileGlues) and `dep_mobilegl` (MobileGL) are dropped because the M1 target renders through
  Vulkan/MoltenVK; re-add them when the MobileGL renderer path is needed.
- `debug.debug_always_attached_jit` is forced ON on TXM (visionOS) in `JavaLauncher.m`; without it the
  dyld-validation bypass is disabled and JNA/temp native dylibs fail to load.
- `MinecraftOptionUtils` forces the launcher-decided backend and `startedCleanly:true`; Minecraft's
  crash recovery would otherwise reset to OpenGL/ANGLE, which crashes on 26.2 cloud shaders.

## 3a. Branding assets

`assets/branding/` contains the VRMC app-icon PNGs; `scripts/build_launcher.sh` copies them into
`Natives/Assets.xcassets/` before the build (regenerate with `scripts/make_icon.py <Amethyst tree>`).
The app is branded as `dev.vrmc.vrmc` / display name VRMC in the signing step below.

## 4. Branding and signing

The built app is `org.angelauramc.amethyst` by default. The device build is branded as
`dev.vrmc.vrmc` (CFBundleIdentifier/DisplayName/Name = VRMC) and re-signed for our team:

```bash
BUNDLE_ID=dev.vrmc.vrmc TEAM_ID=<TEAM_ID> IDENTITY="Apple Development: ..." \
XCENT=/path/DummyProfile.app.xcent PROFILE=/path/embedded.mobileprovision \
scripts/sign_ipa.sh /path/AngelAuraAmethyst.app
```

then installed with `scripts/install_device.sh`. The StikDebug script assignment (`amethyst.js`) is
per bundle id and is an on-device step.
