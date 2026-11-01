#!/bin/bash
# Re-sign an Amethyst .app for the VRMC free-team profile.
set -e
APP="$1"
IDENT="${VRMC_SIGN_IDENTITY:-}"
XCENT=~/Library/Developer/Xcode/DerivedData/DummyProfile-ejolatnvjqxcijbbbhjfkbzgkhat/Build/Intermediates.noindex/DummyProfile.build/Debug-iphoneos/DummyProfile.build/DummyProfile.app.xcent
PROFILE=~/Library/Developer/Xcode/DerivedData/DummyProfile-ejolatnvjqxcijbbbhjfkbzgkhat/Build/Products/Debug-iphoneos/DummyProfile.app/embedded.mobileprovision
PLIST="$APP/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.vrmc.amethyst" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string dev.vrmc.amethyst" "$PLIST"
n=0
while IFS= read -r f; do
  if file "$f" | grep -q "Mach-O"; then
    codesign --force --sign "$IDENT" "$f" >/dev/null 2>&1 && n=$((n+1)) || echo "sign failed: $f"
  fi
done < <(find "$APP" -type f)
cp "$PROFILE" "$APP/embedded.mobileprovision"
codesign --force --sign "$IDENT" --entitlements "$XCENT" "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP"
echo "resigned $n binaries; verify OK; bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
