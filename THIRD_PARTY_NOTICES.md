# Third-Party Notices

VRMC distributes **no** Minecraft binaries, assets, mod jars, IPA payloads, or emulator/runtime
binaries. This file records the components VRMC uses, links against, or interoperates with, and
their licenses. It is informational, not legal advice.

## Bundled or linked at build time (VRMC code and distributions)

| Component | Version / pin | License | Role | Notes |
|---|---|---|---|---|
| Amethyst-iOS | upstream `f98c413` | GPL-3.0 | Launcher reference base | VRMC app code is GPL-3.0 as a derivative. Source published with releases. |
| Amethyst JIT scripts (`runtime/jit/amethyst.js`) | Amethyst `UniversalJIT26.js` + `UniversalJIT26Extension.js` | GPL-3.0 | JIT26 enabler script assigned via StikDebug | Concatenated verbatim; deployed with `scripts/push_jit_script.sh`. Source available in the upstream Amethyst repo. |
| VRMC provider mod | in-tree (`provider/`) | LGPL-3.0 | Vivecraft integration | Separate, replaceable artifact; source published. |
| OpenJDK | 25 (xros build, TBD) | GPL-2.0 with Classpath Exception | JVM runtime | Build provenance recorded in `versions.env` when built. |
| LWJGL | 3.4.1 | BSD-3-Clause | Java bindings (GLFW/Vulkan/OpenAL) | visionOS natives built from source. |
| MoltenVK | pinned (TBD) | Apache-2.0 | Vulkan → Metal | visionOS XCFramework. |
| OpenAL Soft | pinned (TBD) | LGPL-2.0-or-later | Audio | Dynamically linked; relinkable. |
| ANGLE | pinned (TBD) | BSD-3-Clause | GLES → Metal fallback | Only if the GL/LTW path is used. |
| LTW (PojavLauncher) | pinned (TBD) | LGPL-3.0 | Desktop GL → GLES shim | Fallback graphics path only. |
| Fabric Loader | 0.19.3 | Apache-2.0 | Mod loader | Installed by the launcher from official metadata. |

## User-installed or user-owned (not distributed by VRMC)

| Component | License / terms | Notes |
|---|---|---|
| Minecraft: Java Edition | Proprietary (Minecraft EULA, Microsoft Services Agreement) | User must own it. Assets/client downloaded from Mojang endpoints. Ownership gate enforced. |
| Vivecraft | LGPL-3.0 | Downloaded/installed by the user from the official source, used unmodified. |
| Other Fabric mods | Per-mod | User-installed; not bundled. |
| SideStore / iloader | Per-project | Sideload tooling; not bundled. |
| Apparition / StikDebug (optional) | MIT (Apparition per its project page); verify per release | Optional JIT-enablement tooling used outside VRMC; not bundled, not linked. |
| macOS / Xcode / visionOS SDK | Apple SDK terms | Build host only. |

## Referenced as prior art (no code copied)

| Project | License | Use |
|---|---|---|
| `rebelancap/vivecraft-visionos` | See upstream | Feature/behavior benchmark only. |
| Klepton | MIT | Prior-art reference for composition of ANGLE/MoltenVK/CompositorServices. |
| Apparition write-up (blog.illixion.com) | CC BY 4.0 | External evidence EV-0002 citation. |

## Obligations VRMC enforces

1. No Minecraft jars, assets, or derived binaries in git or release payloads.
2. GPL-3.0 corresponding source published for every distributed VRMC app build.
3. LGPL-3.0 provider source published; the product must remain able to replace it.
4. Third-party notices shipped with releases; `versions.env` pins recorded per build.
5. No redistribution of Vivecraft; users install it themselves.
