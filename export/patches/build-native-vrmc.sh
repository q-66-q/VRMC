#!/bin/bash
# Build, brand, sign and install the native visionOS VRMC launcher (source tree: Amethyst 1.2.0).
# Prereqs: patched source tree at $AME_SRC, zulu8 boot JDK, visionOS dev profile/xcent for dev.vrmc.vrmc.
set -euo pipefail
AME_SRC="${AME_SRC:-/tmp/amethyst-refbuild}"
BOOTJDK="${BOOTJDK:-/tmp/zulu8/zulu8.98.0.107-ca-jdk8.0.512-macosx_aarch64/Contents/Home/bin}"
DEV="${DEVICE_UDID:-${VRMC_DEVICE_UDID:-}}"
PROFILE="${VISIONOS_PROFILE:?path to dev.vrmc.vrmc visionOS provisioning profile}"
XCENT="${VISIONOS_XCENT:?path to the matching .xcent}"
IDENT="${SIGN_IDENTITY:-${VRMC_SIGN_IDENTITY:-}}"
APP=/tmp/VRMC-native.app

cd "$AME_SRC"
make PLATFORM=11 RELEASE=0 BOOTJDK="$BOOTJDK" JOBS="$(sysctl -n hw.logicalcpu)" payload

rm -rf "$APP"
cp -R artifacts/Payload/AngelAuraAmethyst.app "$APP"
PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleIdentifier dev.vrmc.vrmc" "$APP/Info.plist"
$PB -c "Set :CFBundleDisplayName VRMC" "$APP/Info.plist"
$PB -c "Set :CFBundleName VRMC" "$APP/Info.plist"
$PB -c "Set :MinimumOSVersion 1.0" "$APP/Info.plist" || true
$PB -c "Delete :LSRequiresIPhoneOS" "$APP/Info.plist" || true
$PB -c "Delete :UIDeviceFamily" "$APP/Info.plist" || true
$PB -c "Add :UIDeviceFamily array" "$APP/Info.plist"
$PB -c "Add :UIDeviceFamily:0 integer 7" "$APP/Info.plist"
$PB -c "Add :VRMCNativeBuild bool true" "$APP/Info.plist"

while IFS= read -r f; do
  if file "$f" | grep -q "Mach-O"; then codesign --force --sign "$IDENT" "$f" >/dev/null 2>&1; fi
done < <(find "$APP" -type f)
cp "$PROFILE" "$APP/embedded.mobileprovision"
codesign --force --sign "$IDENT" --entitlements "$XCENT" "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP"

xcrun devicectl device install app --device "$DEV" "$APP"
