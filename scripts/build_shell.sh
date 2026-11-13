#!/bin/bash
# Build the visionOS SwiftUI shell framework (M3-W2) and place it in runtime/native-shell/build/.
# The Amethyst native app embeds it under Frameworks/VRMCShell.framework and main.m dlopens it.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/runtime/native-shell"
DEVICE_UDID="${DEVICE_UDID:-$VRMC_DEVICE_UDID}"
cd "$DIR"
xcodegen generate >/dev/null
xcodebuild -project VRMCShell.xcodeproj -scheme VRMCShell -configuration Debug \
  -destination "platform=visionOS,id=$DEVICE_UDID" -allowProvisioningUpdates build >/tmp/vrmc-shell-build.log 2>&1
FRAMEWORK=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*VRMCShell*/Build/Products/Debug-xros/VRMCShell.framework" | head -1)
[ -n "$FRAMEWORK" ] && [ -d "$FRAMEWORK" ] || { echo "shell framework not found; see /tmp/vrmc-shell-build.log" >&2; exit 1; }
rm -rf "$DIR/build"
mkdir -p "$DIR/build"
cp -R "$FRAMEWORK" "$DIR/build/"
echo "[shell] built: $DIR/build/VRMCShell.framework"
