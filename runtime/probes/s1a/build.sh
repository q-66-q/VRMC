#!/bin/bash
# build.sh — S1a probe: build (and optionally sign/install) the iOS JIT probe.
#
# S1a proves the JIT26 mechanism on the paired Vision Pro in iOS compatibility mode.
# It is a probe, not product code. See docs/mvp/SPIKES.md §S1.
#
# Usage:
#   ./build.sh --check                  # syntax-check only (no JRE needed)
#   JRE_DIR=/path/to/jre ./build.sh     # assemble .app bundle
#   IDENTITY="Apple Development: ..." PROFILE=/path/to.mobileprovision \
#     DEVICE_ID=<udid> JRE_DIR=... ./build.sh
#   BUNDLE_ID=dev.vrmc.s1a (default)
#
# The JRE must be an extracted iOS arm64 JRE (lib/libjli.dylib, lib/server/libjvm.dylib).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="S1AProbe"
BUNDLE_ID="${BUNDLE_ID:-dev.vrmc.s1a}"
MIN_IOS="14.0"
BUILD_DIR="$HERE/build"
APP="$BUILD_DIR/$APP_NAME.app"
CHECK=0

[ "${1:-}" = "--check" ] && CHECK=1

if [ "$CHECK" -eq 0 ] && [ -z "${JRE_DIR:-}" ]; then
  echo "error: set JRE_DIR to an extracted iOS arm64 JRE (or pass --check)" >&2
  exit 2
fi
if [ "$CHECK" -eq 0 ] && [ ! -f "$JRE_DIR/lib/libjli.dylib" ]; then
  echo "error: $JRE_DIR/lib/libjli.dylib not found" >&2
  exit 3
fi

echo "== syntax check main.m =="
xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min="$MIN_IOS" -fobjc-arc \
  -fsyntax-only "$HERE/main.m"
echo "ok"
[ "$CHECK" -eq 1 ] && exit 0

rm -rf "$BUILD_DIR"
mkdir -p "$APP/Resources/s1a" "$APP/Frameworks"

echo "== compile HelloJit =="
javac -d "$APP/Resources/s1a" "$HERE/HelloJit.java"
echo "== compile app =="
xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min="$MIN_IOS" -fobjc-arc -O2 \
  -o "$APP/$APP_NAME" "$HERE/main.m" -framework UIKit -framework Foundation
echo "== copy Info.plist =="
sed "s/VRMC_BUNDLE_ID/$BUNDLE_ID/g" "$HERE/Info.plist" > "$APP/Info.plist"
plutil -lint "$APP/Info.plist" >/dev/null
echo "== embed JRE =="
rsync -a --exclude 'bin' --exclude 'include' --exclude 'legal' "$JRE_DIR/" "$APP/Frameworks/jre/"
if [ ! -f "$APP/Frameworks/jre/lib/server/libjvm.dylib" ]; then
  echo "error: embedded JRE has no lib/server/libjvm.dylib" >&2
  exit 4
fi

if [ -z "${IDENTITY:-}" ]; then
  echo ""
  echo "Bundle assembled: $APP"
  echo "Signing not requested. Set IDENTITY (and PROFILE) to sign, then:"
  echo "  xcrun devicectl device install app --device <udid> \"$APP\""
  echo "The device must have Developer Mode enabled and the profile must include its UDID."
  exit 0
fi

echo "== sign =="
SIGN_ARGS=(--force --sign "$IDENTITY" --entitlements "$HERE/s1a.entitlements" --timestamp=none)
if [ -n "${PROFILE:-}" ]; then
  cp "$PROFILE" "$APP/embedded.mobileprovision"
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if [ -n "${DEVICE_ID:-}" ]; then
  echo "== install =="
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
  echo "Installed $BUNDLE_ID. Launch it with the JIT enabler (Apparition/StikDebug-style), not from Home,"
  echo "so the debugger prepares the code cache; then read Documents/s1a-jit.log from the app container."
fi
