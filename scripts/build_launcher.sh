#!/bin/bash
# Build the VRMC launcher (branded Amethyst 1.2.0) reproducibly from a prepared Amethyst 1.2.0 tree.
# Usage (one line): AME_SRC=/path/to/Amethyst-iOS-main BOOTJDK=/path/to/jdk8/bin [PLATFORM=2|11] [DEPENDS_DIR=/path/to/depends] scripts/build_launcher.sh
# PLATFORM=2  -> iOS-compatibility app (default, current product launcher)
# PLATFORM=11 -> native visionOS app (required for immersive spaces; M3/M3-W1 testing)
# Requirements: AME_SRC must be the Amethyst 1.2.0 source tree with the four submodules populated
# (Natives/external/{AFNetworking,DBNumberedSlider,MobileGlues,fishhook}); a JDK 8 boot JDK; Xcode.
# The script applies patches/*.patch, drops MobileGlues/MobileGL from payload (Vulkan/MoltenVK path)
# and produces artifacts/Payload/AngelAuraAmethyst.app. Signing/branding is a separate step (sign_ipa.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AME_SRC=${AME_SRC:?set AME_SRC to the Amethyst 1.2.0 source tree}
BOOTJDK=${BOOTJDK:?set BOOTJDK to the JDK 8 bin directory}
BUILD_DIR=${BUILD_DIR:-$ROOT/.build/launcher}
JOBS=${JOBS:-$(sysctl -n hw.logicalcpu)}
PLATFORM=${PLATFORM:-2}
DEPENDS_DIR=${DEPENDS_DIR:-}

[ -f "$AME_SRC/Makefile" ] || { echo "AME_SRC has no Makefile: $AME_SRC" >&2; exit 1; }
grep -q 'VERSION     := 1.2.0' "$AME_SRC/Makefile" || { echo "AME_SRC is not Amethyst 1.2.0 (VERSION != 1.2.0)" >&2; exit 1; }
[ -f "$AME_SRC/Natives/resources/lwjgl_versions.txt" ] || { echo "AME_SRC lacks Natives/resources/lwjgl_versions.txt (wrong tree)" >&2; exit 1; }
[ -d "$AME_SRC/Natives/resources/Frameworks/lwjgl34" ] || { echo "AME_SRC lacks Frameworks/lwjgl34 (wrong tree)" >&2; exit 1; }
for m in AFNetworking DBNumberedSlider MobileGlues fishhook; do
  [ -n "$(ls -A "$AME_SRC/Natives/external/$m" 2>/dev/null)" ] || { echo "submodule not populated: Natives/external/$m" >&2; exit 1; }
done
[ -x "$BOOTJDK/javac" ] || { echo "no javac in BOOTJDK: $BOOTJDK" >&2; exit 1; }
case "$PLATFORM" in
  2|11) ;;
  *) echo "PLATFORM must be 2 (iOS-compat) or 11 (native visionOS), got: $PLATFORM" >&2; exit 1 ;;
esac
echo "[build] PLATFORM=$PLATFORM"

echo "[build] staging $AME_SRC -> $BUILD_DIR"
rm -rf "$BUILD_DIR"
rsync -a --exclude build --exclude artifacts --exclude depends "$AME_SRC/" "$BUILD_DIR/"
if [ -d "$ROOT/assets/branding" ]; then
  echo "[build] installing VRMC branding assets"
  rsync -a "$ROOT/assets/branding/" "$BUILD_DIR/Natives/Assets.xcassets/"
fi
if [ -d "$ROOT/assets/vulkan_include" ]; then
  echo "[build] installing Vulkan headers (S4a-device probe)"
  rsync -a "$ROOT/assets/vulkan_include/" "$BUILD_DIR/Natives/vulkan_include/"
fi
if [ -f "$ROOT/bridge/src/vrmc_stub.c" ] && command -v xcrun >/dev/null 2>&1; then
  IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
  JAVAHOME=${JAVAHOME:-$(/usr/libexec/java_home -v 25 2>/dev/null || true)}
  if [ -n "$IOS_SDK" ] && [ -n "$JAVAHOME" ] && [ -f "$JAVAHOME/include/jni.h" ]; then
    echo "[build] building VRMC bridge dylib (arm64 ios)"
    cc -target arm64-apple-ios14.0 -isysroot "$IOS_SDK"       -I"$ROOT/bridge/abi" -I"$JAVAHOME/include" -I"$JAVAHOME/include/darwin"       -shared -fPIC -o "$BUILD_DIR/Natives/resources/Frameworks/libvrmc_bridge.dylib"       "$ROOT/bridge/src/vrmc_stub.c" "$ROOT/bridge/src/vrmc_jni.c" || exit 1
  else
    echo "[build] warning: iOS bridge dylib not built (missing SDK/JDK)"
  fi
fi
for p in "$ROOT"/patches/*.patch; do
  echo "[build] applying $(basename "$p")"
  patch -p1 -d "$BUILD_DIR" < "$p"
done
if [ -n "$DEPENDS_DIR" ]; then
  echo "[build] reusing cached depends from $DEPENDS_DIR"
  rsync -a "$DEPENDS_DIR/" "$BUILD_DIR/depends/"
fi
echo "[build] make payload (JOBS=$JOBS)"
make -C "$BUILD_DIR" PLATFORM="$PLATFORM" RELEASE=0 BOOTJDK="$BOOTJDK" JOBS="$JOBS" payload
APP="$BUILD_DIR/artifacts/Payload/AngelAuraAmethyst.app"
[ -d "$APP" ] || { echo "payload missing: $APP" >&2; exit 1; }
SHELL_FRAMEWORK="$ROOT/runtime/native-shell/build/VRMCShell.framework"
if [ "$PLATFORM" = "11" ]; then
  if [ -d "$SHELL_FRAMEWORK" ]; then
    echo "[build] embedding SwiftUI shell framework"
    mkdir -p "$APP/Frameworks"
    rm -rf "$APP/Frameworks/VRMCShell.framework"
    rsync -a "$SHELL_FRAMEWORK" "$APP/Frameworks/"
  else
    echo "[build] warning: VRMCShell.framework missing (run scripts/build_shell.sh); native app will fall back to UIKit lifecycle" >&2
  fi
fi
plutil -p "$APP/Info.plist" | grep -E 'CFBundleShortVersionString.*1\.2\.0' >/dev/null || { echo "unexpected app version" >&2; exit 1; }
if [ "$PLATFORM" = "11" ]; then
  echo "[build] adjusting Info.plist for native visionOS"
  PB=/usr/libexec/PlistBuddy
  $PB -c "Set :MinimumOSVersion 1.0" "$APP/Info.plist" 2>/dev/null || true
  $PB -c "Delete :LSRequiresIPhoneOS" "$APP/Info.plist" 2>/dev/null || true
  $PB -c "Delete :UIDeviceFamily" "$APP/Info.plist" 2>/dev/null || true
  $PB -c "Add :UIDeviceFamily array" "$APP/Info.plist"
  $PB -c "Add :UIDeviceFamily:0 integer 7" "$APP/Info.plist"
  # SwiftUI lifecycle (VRMCShell.framework) needs a SwiftUI-shaped scene manifest: no SceneDelegate,
  # multiple scenes allowed. Keep the AppDelegate/SceneDelegate classes compiled in for the fallback.
  $PB -c "Delete :UIApplicationSceneManifest" "$APP/Info.plist" 2>/dev/null || true
  $PB -c "Add :UIApplicationSceneManifest dict" "$APP/Info.plist"
  $PB -c "Add :UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes bool true" "$APP/Info.plist"
  $PB -c "Add :UIApplicationSceneManifest:UISceneConfigurations dict" "$APP/Info.plist"
  # Immersive space / ARKit world tracking privacy strings (required before opening the space).
  $PB -c "Add :NSWorldSensingUsageDescription string 'VRMC uses world sensing for immersive Minecraft.'" "$APP/Info.plist" 2>/dev/null || true
  $PB -c "Add :NSHandsTrackingUsageDescription string 'VRMC uses hand tracking for input.'" "$APP/Info.plist" 2>/dev/null || true
  echo "[build] native payload ready; brand/sign with the visionOS dev.vrmc.vrmc profile and install (see docs)"
fi
echo "[build] ok: $APP"
# hash best-effort: pipefail is disabled because a transient per-file read error must not fail the build
set +o pipefail
HASH=$(cd "$APP" && find . -type f | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}')
set -o pipefail
if [ -n "${HASH:-}" ]; then echo "[build] unsigned payload tree sha256: $HASH"; else echo "[build] warning: could not compute payload tree hash" >&2; fi
