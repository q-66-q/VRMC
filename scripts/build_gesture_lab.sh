#!/bin/bash
# Build + manually sign the separate Gesture Lab visionOS app (dev.vrmc.s2probe), then copy it to
# /tmp/VRMC-GestureLab.app. Deliberately NEVER installs (free-profile slot handling is manual).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/runtime/gesture-lab"
IDENTITY="${IDENTITY:-$VRMC_SIGN_IDENTITY}"
PROFILE="${PROFILE:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/d8b4c05d-5448-4977-85e0-49bd41ff371f.mobileprovision}"
BUNDLE_ID="dev.vrmc.s2probe"
DEST="${DEST_APP:-/tmp/VRMC-GestureLab.app}"
cd "$DIR"
xcodegen generate >/dev/null
xcodebuild -project VRMCGestureLab.xcodeproj -scheme VRMCGestureLab -configuration Debug \
  -destination 'generic/platform=visionOS' build > /tmp/vrmc-gesturelab-build.log 2>&1 || {
    echo "[gesture-lab] build FAILED; see /tmp/vrmc-gesturelab-build.log" >&2; tail -20 /tmp/vrmc-gesturelab-build.log >&2; exit 1; }
APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*VRMCGestureLab*/Build/Products/Debug-xros/VRMCGestureLab.app" | head -1)
[ -n "$APP" ] && [ -d "$APP" ] || { echo "[gesture-lab] built app not found" >&2; exit 1; }
[ -f "$PROFILE" ] || { echo "[gesture-lab] profile not found: $PROFILE" >&2; exit 1; }
TMP=$(mktemp -d /tmp/vrmc-lab-sign.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
security cms -D -i "$PROFILE" > "$TMP/profile.plist"
APPID=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$TMP/profile.plist")
[ "$APPID" = "$VRMC_TEAM_ID.$BUNDLE_ID" ] || { echo "[gesture-lab] profile app id mismatch: $APPID" >&2; exit 1; }
plutil -extract Entitlements xml1 -o "$TMP/entitlements.plist" "$TMP/profile.plist"
cp "$PROFILE" "$APP/embedded.mobileprovision"
# sign every Mach-O file, then the bundle
find "$APP" -type f -print0 | while IFS= read -r -d '' f; do
  if file "$f" | grep -q "Mach-O"; then
    codesign --force --sign "$IDENTITY" --timestamp=none --entitlements "$TMP/entitlements.plist" "$f" >/dev/null 2>&1 \
      || { echo "[gesture-lab] codesign failed: $f" >&2; exit 1; }
  fi
done
codesign --force --sign "$IDENTITY" --timestamp=none --entitlements "$TMP/entitlements.plist" "$APP" >/dev/null 2>&1 \
  || { echo "[gesture-lab] bundle codesign failed" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "[gesture-lab] built/signed: $DEST"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Info.plist"
echo "[gesture-lab] install (after freeing a free-profile app slot):"
echo "  xcrun devicectl device install app --device "${VRMC_DEVICE_UDID:-<device-udid>}" $DEST"
