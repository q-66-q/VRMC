#!/bin/bash
# Re-sign an .app bundle for a development team / provisioning profile.
# Used for Amethyst, StikDebug and our own M1 app builds.
#
# Usage: IDENTITY="Apple Development: ..." XCENT=/path/app.xcent PROFILE=/path/profile \
#        BUNDLE_ID=dev.vrmc.vrmc ./scripts/sign_ipa.sh /path/App.app
set -euo pipefail

APP=${1:?usage: sign_ipa.sh <App.app>}
BUNDLE_ID=${BUNDLE_ID:-dev.vrmc.vrmc}
IDENTITY=${IDENTITY:?set IDENTITY to a codesigning identity}
XCENT=${XCENT:?set XCENT to the Xcode-generated .xcent}
PROFILE=${PROFILE:?set PROFILE to the .mobileprovision}

[ -d "$APP" ] || { echo "not an app bundle: $APP" >&2; exit 1; }

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP/Info.plist"

echo "[sign] signing Mach-O files under $APP"
n=0
while IFS= read -r f; do
  if file "$f" | grep -q "Mach-O"; then
    codesign --force --sign "$IDENTITY" "$f" >/dev/null 2>&1 && n=$((n+1))
  fi
done < <(find "$APP" -type f)

cp "$PROFILE" "$APP/embedded.mobileprovision"
codesign --force --sign "$IDENTITY" --entitlements "$XCENT" "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP"
echo "[sign] ok: $n Mach-O files; bundle=$BUNDLE_ID"
