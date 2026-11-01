#!/bin/bash
# Reproducible native visionOS VRMC launcher build (M3-W1 PASS, EV-0079).
# Prereqs:
#   AME_SRC       patched-source Amethyst 1.2.0 tree (e.g. vendor/amethyst-build)
#   BOOTJDK       JDK 8 bin directory
#   PROFILE       visionOS provisioning profile for dev.vrmc.vrmc
#   XCENT         matching .xcent entitlements file
#   IDENTITY      signing identity (default: Apple Development: ... <cert-id>)
#   DEVICE        device UDID for install
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
AME_SRC=${AME_SRC:?set AME_SRC to the patched Amethyst 1.2.0 source tree}
BOOTJDK=${BOOTJDK:?set BOOTJDK to the JDK 8 bin directory}
PROFILE=${PROFILE:?set PROFILE to the dev.vrmc.vrmc visionOS provisioning profile}
XCENT=${XCENT:?set XCENT to the matching .xcent}
IDENTITY=${IDENTITY:-"${VRMC_SIGN_IDENTITY:-}"}
DEVICE=${DEVICE:?set DEVICE to the Vision Pro UDID}
BUILD_DIR=${BUILD_DIR:-/tmp/vrmc-native-build}
APP=/tmp/VRMC-native.app

AME_SRC="$AME_SRC" BOOTJDK="$BOOTJDK" PLATFORM=11 BUILD_DIR="$BUILD_DIR" \
  "$ROOT/scripts/build_launcher.sh"

rm -rf "$APP"
cp -R "$BUILD_DIR/artifacts/Payload/AngelAuraAmethyst.app" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.vrmc.vrmc" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName VRMC" "$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName VRMC" "$APP/Info.plist"

while IFS= read -r f; do
  if file "$f" | grep -q "Mach-O"; then codesign --force --sign "$IDENTITY" "$f" >/dev/null 2>&1; fi
done < <(find "$APP" -type f)
cp "$PROFILE" "$APP/embedded.mobileprovision"
codesign --force --sign "$IDENTITY" --entitlements "$XCENT" "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP"

xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "[native] installed. Enable JIT in StikDebug -> VRMC; Play should launch MC with no autolaunch."
