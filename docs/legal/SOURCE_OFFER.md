# Corresponding-source offer (GPL-3.0 / AGPL-3.0) — VRMC launcher

The distributed VRMC launcher (`dev.vrmc.vrmc`) is a modified copy of **Amethyst iOS 1.2.0**
(GPL-3.0). Under GPL-3.0 (and ADR-0006) we must make the complete corresponding source available to
everyone who receives the binary.

## What is distributed

- Our build of Amethyst 1.2.0 (`payload` produced by `scripts/build_launcher.sh`)
- VRMC patches: `patches/vrmc-m1-amethyst-1.2.0.patch` (10 files; also in git history)
- `runtime/jit/amethyst.js` (AGPL-3.0, derived from Amethyst/StikDebug JIT26 scripts; notices updated)

## Where to get the corresponding source

1. **Base:** Amethyst iOS **1.2.0** source tree (GPL-3.0), the tree whose `Makefile` has
   `VERSION := 1.2.0` and which ships `Natives/resources/lwjgl_versions.txt` +
   `Natives/resources/Frameworks/lwjgl34`. Provenance hash (excluding `Natives/external/*`):
   `sha256 213e505e90c93a6d99623528cc0652e3702f381f4529ef5ad73e8e72170694ce`.
2. **Our modifications:** `patches/vrmc-m1-amethyst-1.2.0.patch` (`sha256` recorded in `versions.env`
   as `VRMC_PATCH_SHA256`), plus `scripts/build_launcher.sh` and `docs/mvp/LAUNCHER_BUILD.md`.
3. **Build:** `AME_SRC=<Amethyst-1.2.0-tree> BOOTJDK=<jdk8/bin> scripts/build_launcher.sh` — the same
   recipe used for the distributed build (EV-0036/EV-0049).

## Third-party components (not modified by VRMC)

| Component | License | Source |
|---|---|---|
| Amethyst iOS 1.2.0 | GPL-3.0 | upstream project |
| StikDebug 3.2.0 | AGPL-3.0 | upstream project; the distributed launcher does not bundle StikDebug |
| `amethyst.js` (JIT26 script) | AGPL-3.0 | derived from Amethyst/StikDebug; `runtime/jit/amethyst.js` |
| MoltenVK 1.4.3 | Apache-2.0 | upstream |
| LWJGL 3.4.1 / 3.3.3 | BSD-3-Clause | upstream |
| OpenJDK 25.0.4 (iOS build) | GPL-2.0 with Classpath Exception | PojavLauncherTeam/android-openjdk-build-multiarch |
| Minecraft Java 26.2 | Mojang EULA | **not distributed**; downloaded by the user through the launcher |
| Vazkii/Vivecraft, Fabric | LGPL-3.0 / Apache-2.0 | not modified yet; source published upstream |

## Offer

For any distributed VRMC launcher binary, the corresponding source is available as (1) the upstream
Amethyst 1.2.0 tree, (2) the VRMC patch file, and (3) the build script/instructions above. A packaged
source bundle can be produced on request by running the recipe in `docs/mvp/LAUNCHER_BUILD.md` against
the pinned base tree; the repository history contains every VRMC change.

No Minecraft assets or proprietary Apple SDK content are included.
