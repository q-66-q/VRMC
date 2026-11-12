#!/bin/bash
# Build the visionOS SwiftUI shell framework (M3-W2) and place it in runtime/native-shell/build/.
# The Amethyst native app embeds it under Frameworks/VRMCShell.framework and main.m dlopens it.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/runtime/native-shell"
DEVICE_UDID="${DEVICE_UDID:-${VRMC_DEVICE_UDID:-}}"
# The reviewer sandbox cannot write ~/Library/Developer/Xcode/DerivedData, so build into /tmp by
# default (override with DERIVED_DATA=... to reuse a cache).
DERIVED_DATA="${DERIVED_DATA:-/tmp/vrmc-shell-derived}"
BUILD_LOG="${BUILD_LOG:-/tmp/vrmc-shell-build.log}"
# The shell bundles the provider mod and installs it into the game instance at launch (automatic
# setup). Build it first unless PROVIDER_JAR points at a prebuilt jar.
mkdir -p "$DIR/Resources"
if [ -z "${PROVIDER_JAR:-}" ]; then
  OUT_DIR="${PROVIDER_OUT:-/tmp/vrmc-provider-build}" "$ROOT/scripts/build_provider.sh" >/tmp/vrmc-shell-provider.log 2>&1 \
    || { cat /tmp/vrmc-shell-provider.log >&2; echo "[shell] provider build failed" >&2; exit 1; }
  PROVIDER_JAR="${PROVIDER_OUT:-/tmp/vrmc-provider-build}/vrmc-provider.jar"
fi
[ -f "$PROVIDER_JAR" ] || { echo "[shell] provider jar not found: $PROVIDER_JAR" >&2; exit 1; }
cp "$PROVIDER_JAR" "$DIR/Resources/vrmc-provider.jar"
echo "[shell] bundled provider: $(shasum -a 256 "$DIR/Resources/vrmc-provider.jar" | cut -c1-16)…"
# The Swift macro plugin host runs its own sandbox-exec; under a harness/CI file sandbox that nested
# sandbox is denied and every @Observable macro fails ("swift-plugin-server produced malformed
# response"). Disable the plugin sandbox for this build unless the caller already supplies an
# xcconfig. Harmless for normal local builds.
if [ -z "${XCODE_XCCONFIG_FILE:-}" ]; then
  EXTRA_XCCONFIG="${EXTRA_XCCONFIG:-/tmp/vrmc-shell-extra.xcconfig}"
  printf 'OTHER_SWIFT_FLAGS = -disable-sandbox\n' > "$EXTRA_XCCONFIG"
  export XCODE_XCCONFIG_FILE="$EXTRA_XCCONFIG"
fi
cd "$DIR"
xcodegen generate >/dev/null
xcodebuild -project VRMCShell.xcodeproj -scheme VRMCShell -configuration Debug \
  -destination "platform=visionOS,id=$DEVICE_UDID" -allowProvisioningUpdates \
  -derivedDataPath "$DERIVED_DATA" build >"$BUILD_LOG" 2>&1
FRAMEWORK="$DERIVED_DATA/Build/Products/Debug-xros/VRMCShell.framework"
if [ ! -d "$FRAMEWORK" ]; then
  FRAMEWORK=$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/VRMCShell-*/Build/Products/Debug-xros/VRMCShell.framework 2>/dev/null | head -1)
fi
[ -n "$FRAMEWORK" ] && [ -d "$FRAMEWORK" ] || { echo "shell framework not found; see $BUILD_LOG" >&2; exit 1; }
rm -rf "$DIR/build"
mkdir -p "$DIR/build"
cp -R "$FRAMEWORK" "$DIR/build/"
echo "[shell] built: $DIR/build/VRMCShell.framework"
