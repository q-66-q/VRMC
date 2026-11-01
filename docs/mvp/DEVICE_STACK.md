# Device stack under M1 — pinned components and provenance

Status: **T1 (Sprint 1) in progress**, 2026-10-31. Pins backed by ADR-0007; `versions.env` is the
machine-readable source of truth.

## Pinned components

| Component | Pin | Provenance | Hash | Evidence |
|---|---|---|---|---|
| Amethyst (launcher app) | **1.2.0** | Device-installed IPA provenance pending. **Our source build:** Amethyst 1.2.0 reference tree + submodules (AFNetworking, DBNumberedSlider, MobileGlues, fishhook); remote `main` (`f98c413`, v1.0) and `staging` (`c1f3aea`) lack the multi-LWJGL files present in the reference tree. Payload deps: native, mcmetal, ame_vulkan, java, jre, assets (MobileGlues/MobileGL dropped for Vulkan) | source-build app tree (EV-0036) `sha256 4b1f959a3ead6ad8cc8d08f3c1c672da1484de1764ba738fa5d74d46347cc20a`; T4 patched build `sha256 d8e7a6f6f95d1b4f5a77e70cae2e64a2ed816a32488070d4b36efd3d9a7c1156` (558 MB, signed as `dev.vrmc.amethyst`) | EV-0029, EV-0031, EV-0034, **EV-0036** |
| MoltenVK | **1.4.3** | Bundled in the source-built app (and the 1.2.0 device build); our own xros build is 1.4.2 (EV-0010) | dylib `sha256 031986062f238d250155f814061e45f7bab03a94f0c7e20de70dd5f16c46e5ee` (platform IOS, minos 15.0, version string 1.4.3) | EV-0034, EV-0036/EV-0037 (device log) |
| StikDebug | **3.2.0** | Official IPA: `StikDebug-3.2.0.ipa` (GitHub release 3.2.0), re-signed as `com.stik.stikdebug.<TEAM_ID>` | IPA `sha256 f3b4e1ea39a0b84ced25158c21be8f9c08965bbbe525daf5a18f199b1fc3aced` | EV-0033 |
| StikDebug script | **`amethyst.js`** | Concatenation of Amethyst `UniversalJIT26.js` + `UniversalJIT26Extension.js` | `sha256 7fb4b14b7a9caa6e4723b9a41125030b15db6e4f7e8fb1d9be41f8be9f0fa9b9` | EV-0021 (mechanism), EV-0034 (device) |
| JVM | **OpenJDK 25.0.4** iOS arm64 (`MirrorMappedCodeCache`) | Relabelled to VISIONOS and deployed as external runtime `Documents/java_runtimes/java-25-openjdk` | tree `sha256 06ff09cf2d06cd3d9b0d713f147a56b8c1723c0e7fffc573c7ef3241af055409` (as-deployed flat, signed tree) | EV-0022/EV-0024, EV-0031/EV-0034 |
| LWJGL | **3.4.1** (Java + iOS natives) | Amethyst source `JavaApp/libs/lwjgl-3.4.1` jars; natives `Natives/resources/Frameworks/lwjgl34` | jars tree `sha256 f6601d2ad9edf975529b7871a21b3ba0297974e43d576980f46f70eaf855ae6e` | EV-0031/EV-0032 (learning), EV-0034 (1.2.0 ships it natively) |
| VRMC app (branded source build) | **dev.vrmc.vrmc / 1.2.0** | Source-built payload branded as VRMC (display/name), 167 Mach-O re-signed with the `<TEAM_ID>.dev.vrmc.vrmc` profile; test app `dev.vrmc.amethyst` removed (fresh container) | signed app tree `sha256 446862ef3c13a37ec95c8e12d3546ec3dc5ed593eb4fb492b1f2b9f4be91f884` | EV-0042 |
| Fabric Loader (device test) | **0.20.1** | Device test 2026-11-01: provider loads/initializes; pin remains **0.19.3** pending pin/ADR decision | — | EV-0068 |
| Minecraft Java | **26.2** | Mojang; installed on device by Amethyst | version JSON `sha256 267d4b17134667235223525d3151b8126b066a3347c372d7a0d2474a9f0970f4` | EV-0005, EV-0014, EV-0034 |

Hash method: “tree sha256” = `find . -type f | sort | xargs shasum -a 256 | shasum -a 256` over the
exact deployed tree (paths relative to its root). IPA hash = `shasum -a 256 <file>`.

## Pending hashes / provenance (T1 remainder)

1. **Amethyst 1.2.0 IPA hash.** The app was installed by the user through SideStore/AltStore; we do not
   yet have the IPA file on the Mac. Obtain it (SideStore cache or the Amethyst AltSource) and record
   the hash. No build-provenance guarantee can be made before this.
2. **MoltenVK 1.4.3 dylib hash.** Recorded above from the source-built app; optionally produce/rebuild an xros 1.4.3 slice later.
3. **MC 26.2 version JSON hash** recorded above from the device install.
4. **BundleScriptMap persistence re-check** (Decision 36): confirm `dev.vrmc.amethyst → amethyst.js`
   survives app updates, and that a missing/incorrect mapping is detectable (W3).

## Evidence notes

- **EV-0010 / EV-0016** were measured on **MoltenVK 1.4.2**. Under the 1.4.3 pin, the required 5
  extensions + 9 features must be re-verified at first M1 device use, or ADR-0007's “1.4.2 stands in
  unless a behavioral difference is found” clause applies. EV-0034 selecting Vulkan on 1.4.3 is
  implicit evidence only.
- **EV-0021** used `universal.js`; its PASS is not invalidated (JIT26 mechanism), but the script
  identity is historical. M1 uses `amethyst.js`.
- **EV-0032** JNI crash was caused by mixing 3.4.1 Java with the old app's 3.3.3 JNI; Amethyst 1.2.0
  ships matching 3.4.1 JNI, so the fault is not expected on the pinned build (see ADR-0007).
