#!/bin/bash
# Build libvrmc_bridge.dylib from bridge/src/vrmc_stub.c + bridge/src/vrmc_jni.c.
#
# MODE=device (default)  arm64 iOS build (iphoneos SDK, minos 14.0) retagged to the visionOS
#                       platform (11 / minos 1.0 / sdk 1.0) with vtool. That retag is exactly what
#                       the Amethyst payload Makefile does to every Mach-O it embeds for
#                       PLATFORM=11 (METHOD_CHANGE_PLAT), and dyld on visionOS rejects non-
#                       visionOS images, so the retag is mandatory for the device app.
# MODE=host             arm64 macOS dylib for the desktop Fabric harness (provider/HOST_HARNESS.md).
# MODE=both             build both (device dylib is reported last as the primary artifact).
#
# Usage:  scripts/build_bridge.sh
# Output: ${OUT_DIR:-/tmp/vrmc-bridge-build}/libvrmc_bridge.dylib          (device, MODE=device|both)
#         ${OUT_DIR:-/tmp/vrmc-bridge-build}/libvrmc_bridge_host.dylib     (host,   MODE=host|both)
#
# Env overrides (all optional):
#   MODE          device | host | both            (default device)
#   OUT_DIR       build dir                       (default /tmp/vrmc-bridge-build)
#   JAVA_HOME     JDK home containing include/jni.h (default: temurin-25, then java_home -v 25)
#   CC            clang binary                    (default: xcrun --sdk <sdk> --find clang)
#   INSTALL_NAME  LC_ID_DYLIB value               (default @rpath/libvrmc_bridge.dylib)
#   IOS_MIN       iPhoneOS deployment target      (default 14.0; retag makes it visionOS 1.0)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${MODE:-device}"
OUT_DIR="${OUT_DIR:-/tmp/vrmc-bridge-build}"
INSTALL_NAME="${INSTALL_NAME:-@rpath/libvrmc_bridge.dylib}"
IOS_MIN="${IOS_MIN:-14.0}"
SOURCES=("$ROOT/bridge/src/vrmc_stub.c" "$ROOT/bridge/src/vrmc_jni.c")

die() { echo "[bridge] ERROR: $*" >&2; exit 1; }
note() { echo "[bridge] $*"; }

case "$MODE" in device|host|both) ;; *) die "MODE must be device, host or both (got: $MODE)" ;; esac
for f in "${SOURCES[@]}"; do [ -f "$f" ] || die "missing source: $f"; done
[ -f "$ROOT/bridge/abi/vrmc_abi.h" ] || die "missing bridge/abi/vrmc_abi.h"

# --- JDK headers (jni.h + include/darwin/jni_md.h) -------------------------
if [ -n "${JDK_HOME:-}" ]; then
  :
elif [ -n "${JAVA_HOME:-}" ] && [ -f "$JAVA_HOME/include/jni.h" ]; then
  JDK_HOME="$JAVA_HOME"
elif [ -f /Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/include/jni.h ]; then
  JDK_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home
elif [ -f /Library/Java/JavaVirtualMachines/jdk-25.jdk/Contents/Home/include/jni.h ]; then
  JDK_HOME=/Library/Java/JavaVirtualMachines/jdk-25.jdk/Contents/Home
else
  JDK_HOME=$(/usr/libexec/java_home -v 25 2>/dev/null || true)
  [ -n "$JDK_HOME" ] && [ -f "$JDK_HOME/include/jni.h" ] || die "JDK headers not found (set JDK_HOME/JAVA_HOME)"
fi
[ -f "$JDK_HOME/include/darwin/jni_md.h" ] || die "darwin/jni_md.h not found under $JDK_HOME/include"

# --- verification ----------------------------------------------------------
verify_dylib() { # verify_dylib <path> <expected-platform> <expected-minos>
  local lib="$1" want_plat="$2" want_min="$3"
  local out; out=$(file "$lib")
  echo "$out" | grep -q "Mach-O 64-bit dynamically linked shared library arm64" \
    || die "not a Mach-O arm64 dynamic library: $out"
  lipo -info "$lib" 2>&1 | grep -q "arm64" || die "lipo -info does not report arm64: $lib"
  local plat mino sdk
  plat=$(otool -l "$lib" | awk "/LC_BUILD_VERSION/{f=1} f&&/platform/{print \$2; exit}")
  mino=$(otool -l "$lib" | awk "/LC_BUILD_VERSION/{f=1} f&&/minos/{print \$2; exit}")
  sdk=$(otool -l "$lib"  | awk "/LC_BUILD_VERSION/{f=1} f&&/sdk /{print \$2; exit}")
  [ "$plat" = "$want_plat" ] || die "LC_BUILD_VERSION platform=$plat (want $want_plat): dyld will refuse to load it"
  [ "$mino" = "$want_min" ] || die "LC_BUILD_VERSION minos=$mino (want $want_min)"
  local sym
  for sym in _vrmc_init _vrmc_last_error _vrmc_abi_version _vrmc_get_tracking _vrmc_shared_eye_textures \
             _vrmc_shared_set_tracking _vrmc_shared_clear_tracking _vrmc_export_mtl_texture \
             _vrmc_submit_eyes _vrmc_frame_timing _vrmc_recenter _vrmc_haptic \
             _vrmc_shared_publish_eyes _vrmc_shared_acquire_eyes _vrmc_shared_get_frame_sync \
             _vrmc_shared_set_display_views _vrmc_shared_get_display_views \
             _Java_dev_vrmc_provider_bridge_VrmcBridge_nativeInit \
             _Java_dev_vrmc_provider_bridge_VrmcBridge_nativeAbiVersion \
             _Java_dev_vrmc_provider_bridge_VrmcBridge_nativeSubmitEyes \
             _Java_dev_vrmc_provider_bridge_VrmcBridge_nativeSubmitEyesSynced \
             _Java_dev_vrmc_provider_bridge_VrmcBridge_nativeExportMTLTexture; do
    nm -gU "$lib" 2>/dev/null | awk "{print \$3}" | grep -qx "$sym" || die "missing exported symbol $sym"
  done
  note "verified: file/lipo arm64, platform=$plat minos=$mino sdk=$sdk, install name $(otool -D "$lib" | tail -1)"
  note "symbols: $(nm -gU "$lib" | wc -l | tr -d " ") exported; vrmc_* + JNI_* present"
}

mkdir -p "$OUT_DIR"
DEV_LIB=""
HOST_LIB=""

if [ "$MODE" = device ] || [ "$MODE" = both ]; then
  IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)
  [ -n "$IOS_SDK" ] && [ -d "$IOS_SDK" ] || die "iPhoneOS SDK not found (xcode-select / Xcode install?)"
  CC_DEV="${CC:-$(xcrun --sdk iphoneos --find clang 2>/dev/null || echo clang)}"
  VTOOL=$(xcrun -f vtool 2>/dev/null || true)
  [ -n "$VTOOL" ] || die "vtool not found (xcrun -f vtool)"
  DEV_LIB="$OUT_DIR/libvrmc_bridge.dylib"
  note "compiling device bridge: $CC_DEV -target arm64-apple-ios$IOS_MIN (sdk $IOS_SDK)"
  "$CC_DEV" -target "arm64-apple-ios$IOS_MIN" -isysroot "$IOS_SDK" \
    -I "$ROOT/bridge/abi" -I "$JDK_HOME/include" -I "$JDK_HOME/include/darwin" \
    -dynamiclib -fPIC -O2 -Wl,-install_name,"$INSTALL_NAME" \
    -o "$DEV_LIB" "${SOURCES[@]}" || die "clang device build failed"
  # Retag iOS -> visionOS exactly like the Amethyst payload Makefile METHOD_CHANGE_PLAT rule.
  local_before=$(otool -l "$DEV_LIB" | awk "/LC_BUILD_VERSION/{f=1} f&&/platform/{print \$2; exit}")
  "$VTOOL" -arch arm64 -set-build-version 11 1.0 1.0 -replace -output "$DEV_LIB" "$DEV_LIB" \
    || die "vtool retag to visionOS failed"
  note "retagged platform $local_before -> 11 (visionOS 1.0/1.0) with vtool"
  verify_dylib "$DEV_LIB" 11 1.0
  # libSystem comes from the iPhoneOS SDK; dyld on visionOS only checks LC_BUILD_VERSION platform,
  # and the EV-0086 device build used the same pipeline (see evidence/EV-0066, METHOD_CHANGE_PLAT).
  SHA=$(shasum -a 256 "$DEV_LIB" | awk "{print \$1}")
  note "device dylib: $DEV_LIB ($(wc -c < "$DEV_LIB" | tr -d " ") bytes)"
  note "device sha256: $SHA"
fi

if [ "$MODE" = host ] || [ "$MODE" = both ]; then
  MAC_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
  [ -n "$MAC_SDK" ] && [ -d "$MAC_SDK" ] || die "macOS SDK not found"
  CC_HOST="${CC:-$(xcrun --sdk macosx --find clang 2>/dev/null || echo clang)}"
  HOST_LIB="$OUT_DIR/libvrmc_bridge_host.dylib"
  note "compiling host bridge: $CC_HOST -target arm64-apple-macos27.0 (sdk $MAC_SDK)"
  "$CC_HOST" -target arm64-apple-macos27.0 -isysroot "$MAC_SDK" \
    -I "$ROOT/bridge/abi" -I "$JDK_HOME/include" -I "$JDK_HOME/include/darwin" \
    -dynamiclib -fPIC -O2 -Wl,-install_name,"$INSTALL_NAME" \
    -o "$HOST_LIB" "${SOURCES[@]}" || die "clang host build failed"
  verify_dylib "$HOST_LIB" 1 27.0
  SHA_HOST=$(shasum -a 256 "$HOST_LIB" | awk "{print \$1}")
  note "host dylib: $HOST_LIB ($(wc -c < "$HOST_LIB" | tr -d " ") bytes)"
  note "host sha256: $SHA_HOST"
fi

if [ "$MODE" = both ]; then echo "$HOST_LIB"; echo "$DEV_LIB"; elif [ "$MODE" = host ]; then echo "$HOST_LIB"; else echo "$DEV_LIB"; fi
