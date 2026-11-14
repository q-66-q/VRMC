# VRMC — Minecraft VR on Apple Vision Pro

## Introduction

VRMC runs **Minecraft: Java Edition with Fabric and the unmodified Vivecraft mod natively on Apple
Vision Pro**: no PC, no streaming. The Java game runs on the headset with a JIT-enabled JVM and
renders through Vulkan (MoltenVK) into a CompositorServices immersive space, with head-tracked stereo
and ARKit hand tracking as the controller.

- **Stereo VR:** per-eye rendering with foveation and display-sized eye targets, presented at the
  headset's 90 Hz.
- **Hands as controllers:** pinch, fist and hand-motion gestures drive Vivecraft's actions (see
  [Hand controls](#hand-controls)); actions release safely when tracking drops.
- **Launcher:** a branded build of the Amethyst launcher with a VRMC shell for accounts, the game
  instance, mod setup, comfort settings and diagnostics.
- **Comfort:** vignette, snap or smooth turn, seated mode and recenter are always reachable.

| Component | Version |
|---|---|
| Minecraft: Java Edition | 26.2 |
| Fabric loader | 0.20.1 |
| Vivecraft | 26.2-1.3.15 |
| Java runtime | OpenJDK 25 (bundled) |
| visionOS | 27.x |

Exact pins live in [`versions.env`](versions.env). VRMC is a development, sideloaded app, not an App
Store product, and it is not affiliated with Mojang, Microsoft, Vivecraft, Valve, Sony or Apple.

## Instructions

### Requirements

- Apple Vision Pro on visionOS 27.x.
- A Mac with Xcode 27.2 to build, sign and install the app.
- An Apple developer account (a free personal team works; its profiles expire after 7 days and the
  app must be re-signed).
- [StikDebug](https://github.com/StephenDev0/StikDebug) on the headset to enable JIT.
- A Minecraft: Java Edition account (you must own the game).
- The official `vivecraft-26.2-1.3.15-fabric.jar`, downloaded by you (VRMC does not redistribute it).

### Install and run

1. **Set your identity once.** Device and signing scripts read your headset UDID, team ID and
   signing identity from `scripts/local.env`, which git ignores:

   ```bash
   cp scripts/local.env.example scripts/local.env   # then edit the three values
   ```

2. **Build and stage the app** (see [Build from source](#build-from-source)), then install it on the
   headset:

   ```bash
   scripts/install_device.sh /tmp/VRMC-native-next.app
   ```

3. **Enable JIT:** open StikDebug, enable JIT for VRMC, then launch VRMC.
4. **Sign in** with your Microsoft account; the launcher creates the Minecraft/Fabric instance.
5. **Add Vivecraft:** save the official Vivecraft jar to *Files › On My Apple Vision Pro › VRMC* (or
   AirDrop it to the headset) and tap **Re-check mods** in the launcher's **Mods** panel. VRMC
   installs it only if its SHA-256 matches the pin in `versions.env`
   (`e63aeed1a6b36a55fc38c7633acbbac2cdf8b46f546382c6a2cd9348440b58bb`); any other file is rejected
   and left in place. The VRMC provider mod ships inside the app and is installed automatically.
6. **Play:** launch the Fabric instance, create or load a world, and choose **Enter VR**.

If the Mods panel reports a problem, the manual fallback is to copy both jars into
`Documents/instances/default/mods/` (`vrmc-provider.jar` and the Vivecraft jar).

### Hand controls

| Gesture | Action |
|---|---|
| Look | Moves the menu cursor (head ray, slightly below centre) |
| Short right pinch | Menu click; in the world, attack an entity or use/place on a block |
| Hold right pinch | Break/mine; release to stop |
| Left pinch held + move left hand | Walk and strafe |
| Raise / lower head | Jump / sneak |
| Left fist tap | Open or close the pause menu |
| Both fists tap | Inventory (right pinch picks up and places stacks) |
| Right fingertip on the hotbar | Select a slot (air tap as fallback) |
| Right-hand swing | Alternate attack |
| Hands apart with a bow | Draw; open the back fist or bring hands together to fire |
| Right hand near head | Eat or drink |
| Alternating closed hands | Climb |

### Build from source

Third-party trees are not committed: you need the Amethyst 1.2.0 source tree (with its submodules) to
build the launcher, and the Minecraft 26.2 client jar plus Vivecraft classes to compile the provider
mod. [`docs/mvp/LAUNCHER_BUILD.md`](docs/mvp/LAUNCHER_BUILD.md) has the full recipe.

```bash
# 1. Launcher app (native visionOS build of the patched Amethyst tree)
AME_SRC=/path/to/Amethyst-1.2.0 BOOTJDK=/path/to/jdk8/bin PLATFORM=11 scripts/build_launcher.sh
# 2. VRMC components
scripts/build_provider.sh        # provider mod jar      -> /tmp/vrmc-provider-build/vrmc-provider.jar
scripts/build_bridge.sh          # native bridge dylib   -> /tmp/vrmc-bridge-build/libvrmc_bridge.dylib
scripts/build_shell.sh           # visionOS shell        -> runtime/native-shell/build/VRMCShell.framework
# 3. Combine, embed the provider, sign for your headset -> /tmp/VRMC-native-next.app
SRC_APP=.build/launcher/artifacts/Payload/AngelAuraAmethyst.app DISPLAY_NAME=VRMC \
  scripts/stage_native_app.sh runtime/native-shell/build/VRMCShell.framework /tmp/vrmc-bridge-build/libvrmc_bridge.dylib
```

Host test suites (no headset needed):

```bash
provider/tests/run_tests.sh              # provider mod (runs a pure-Java subset without the MC jar)
bridge/tests/run_tests.sh                # native bridge
runtime/native-shell/tests/run_tests.sh  # shell: mod provisioning policy
scripts/m6_release_check.sh              # licensing, source and release checks
```

Host tests are not device evidence; device results are recorded in [`VERIFY.md`](VERIFY.md).

## Known issues

- **90 Hz, not 120 Hz:** visionOS caps custom immersive Metal rendering at 90 frames per second, so
  the 120 Hz target is not reachable. Engine-side foveation is also unavailable, because the shipped
  MoltenVK lacks `VK_KHR_fragment_shading_rate`.
- **Menu flash:** a brief (under one second) purple-ish flash can appear on immersive menu and pause
  screens.
- **Bow orientation:** the bow model renders parallel to the hand; drawing and firing work.
- **Hand tracking range:** tracking drops when hands leave the headset cameras' view; held actions
  release safely.
- **Teleport** is not part of the hand control scheme.
- **Automatic mod setup** has passed host tests only; the fresh-install flow has not yet been re-run
  on a headset. Vivecraft must always be downloaded by the user.
- **Sideloading:** JIT must be enabled through StikDebug for each launch, and free developer profiles
  expire after 7 days.

## Repository structure

| Path | Contents |
|---|---|
| [`provider/`](provider/) | VRMC provider: the LGPL-3.0 Fabric mod that plugs Vision Pro into Vivecraft (head pose, eye images, hand gesture engine) |
| [`runtime/`](runtime/) | visionOS shell and CompositorServices compositor (`native-shell/`), Gesture Lab app, JIT script, spikes and probes |
| [`bridge/`](bridge/) | Native VR bridge (C ABI v3 + JNI) between the compositor and the provider |
| [`patches/`](patches/) | VRMC patches applied to the Amethyst 1.2.0 launcher source |
| [`launcher/`](launcher/) | Notes for the planned SwiftUI launcher |
| [`scripts/`](scripts/) | Build, sign, install, device diagnostics, test and release tooling |
| [`assets/`](assets/) | App icon set and Vulkan headers |
| [`docs/`](docs/) | Architecture decisions (`adr/`), milestone plans and runbooks (`mvp/`), analyses |
| [`export/`](export/) | Tracked release metadata, build identity and acceptance summaries |
| [`AGENT.md`](AGENT.md) | Project operating manual and architecture |
| [`VERIFY.md`](VERIFY.md) | Requirements, test suites and the evidence log |
| [`versions.env`](versions.env) | Pinned versions and artifact hashes |

## License

- VRMC application code is **GPL-3.0** ([`LICENSE`](LICENSE)); the launcher is derived from Amethyst.
- The provider mod in `provider/` is **LGPL-3.0** ([`provider/LICENSE`](provider/LICENSE)) and ships
  as a separate, replaceable jar with source.
- Minecraft is proprietary: you must own it, and no Minecraft binaries or assets are distributed.
  Vivecraft is installed by the user and used unmodified.
- See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), [`SOURCE_OFFER.md`](SOURCE_OFFER.md) and
  [`PRIVACY.md`](PRIVACY.md).
