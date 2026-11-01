# VRMC — native visionOS launcher (M3-W1) — **RESOLVED**

**Date:** 2026-11-01
**Status:** **native launcher UI works on D1** — the previously blocking blank window was fixed by the
UIKit idiom patch; Play launches Minecraft from the native app with no autolaunch bypass.

> The earlier `export/` blocker dossier (native UIKit content blank / split-view crash) is resolved.
> Prior logs are kept under `logs/history/`; the current success evidence is
> `logs/latestlog-native-m3w1-pass.txt` (EV-0079).

## 1. Root cause (confirmed)

`Natives/UIKit+hook.m:init_hookUIKitConstructor()` spoofed the UIKit idiom:

```objc
UIUserInterfaceIdiom idiom = getPrefBool(@"debug.debug_ipad_ui") ? Pad : Phone;
[UIDevice.currentDevice _setActiveUserInterfaceIdiom:idiom];
[UIScreen.mainScreen _setUserInterfaceIdiom:idiom];
```

In the iOS-compat app this is harmless (device already reports iPad). In a **native visionOS app** the
real idiom is `Vision` (6); spoofing it to Phone/Pad makes the UIKit window content invisible (blank
window; process alive). A minimal split-view sample on the visionOS simulator reproduced it exactly:
real idiom → renders; forced Phone/Pad → blank.

## 2. Fix

`patches/vrmc-m3w1-visionos-idiom.patch` (applies after `vrmc-m1-amethyst-1.2.0.patch`):

```objc
if (realUIIdiom != 6) {   // never spoof in the native visionOS app
    ...existing Phone/Pad override...
}
```

Compat app behavior is unchanged. Popups (alerts/share sheets) set anchor views as iPad requires, so
the Vision idiom path is safe.

## 3. Verified result (EV-0079)

Operator-confirmed on D1:

- native launcher **UI renders** after StikDebug Enable JIT → VRMC;
- pressing **Play** on `fabric-loader-0.20.1-26.2` starts the game **without** `autolaunch.flag`;
- log: JIT enabled (`isJITEnabled=1`, always-attached TXM), MC 26.2 + Fabric 0.20.1, Vulkan/MoltenVK
  1.4.3, `VisionVR` provider init/bridge ABI 2, LEFT/RIGHT render passes, `VkImage→MTLTexture` eye
  export, 901+ tracking frames, Vivecraft MenuWorlds built.

Evidence: `evidence/EV-0079.md`, `logs/latestlog-native-m3w1-pass.txt`.

## 4. Reproduce — native build + install

Prereqs: Xcode 27.2 + visionOS SDK, JDK 8 boot JDK, patched Amethyst 1.2.0 source tree
(`AME_SRC`, e.g. `vendor/amethyst-build`), visionOS dev profile + `.xcent` for `dev.vrmc.vrmc`.

```bash
AME_SRC=/path/to/amethyst-1.2.0-source \
BOOTJDK=/path/to/jdk8/bin \
PLATFORM=11 \
BUILD_DIR=/tmp/vrmc-native-build \
scripts/build_launcher.sh
```

The script applies `patches/*.patch` in order, builds `PLATFORM=11`, and adjusts the app Info.plist for
native visionOS (`MinimumOSVersion 1.0`, `UIDeviceFamily [7]`). Then brand and sign:

```bash
APP=/tmp/vrmc-native-build/artifacts/Payload/AngelAuraAmethyst.app
cp -R "$APP" /tmp/VRMC-native.app
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.vrmc.vrmc" /tmp/VRMC-native.app/Info.plist
# sign every Mach-O, copy the visionOS profile to embedded.mobileprovision,
# codesign the app with the matching .xcent, then:
xcrun devicectl device install app --device <UDID> /tmp/VRMC-native.app
```

`patches/build-native-vrmc.sh` wraps this flow (edit the profile/xcent paths).

## 5. Remaining M3 work

- **M3-W2/W3**: CompositorServices layer consumes the provider's eye `MTLTexture`s (timeline
  `MTLSharedEvent` sync) instead of the test pattern.
- **M3-W4**: ARKit pose → bridge → provider `hmdPose`; recenter.
- **M3-W5/W6**: pacing/thermal and device acceptance (10-min immersive run).
