#!/bin/bash
# Host tests for the VRMC native bridge (no device).
#
#   1. vrmc_stub_test         - ABI v2 stub self-test (handshake, submit, shared frame, display views)
#   2. bridge_sync_test       - eye-frame publish/acquire protocol + generation/sync + concurrency
#   2b. same test under ThreadSanitizer (-fsanitize=thread) - proves the shared handoff is race-free
#   3. DisplayViewsLayoutTest - JNI display-view byte layout vs VisionVR.pollDisplayViews() offsets
#   4. scripts/build_bridge.sh MODE=both - host+device dylib build and symbol verification
#   5. bridge_metal_sync_host - (optional) real MoltenVK+Metal host probe: exported MTLTexture
#                               ShaderRead usage + timeline MTLSharedEvent wait ordering across a
#                               separate compositor thread/queue. Needs a MoltenVK macOS SDK:
#                                 curl -LO https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-macos.tar
#                                 mkdir -p /tmp/vrmc-host-mvk && tar -xf MoltenVK-macos.tar -C /tmp/vrmc-host-mvk
#                               (MVK_ROOT overrides the location; skipped with a message if absent)
#
# Usage: bridge/tests/run_tests.sh [--skip-metal]   (logs to $OUT_DIR, default /tmp/vrmc-bridge-tests)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-/tmp/vrmc-bridge-tests}"
MVK_ROOT="${MVK_ROOT:-/tmp/vrmc-host-mvk/MoltenVK/MoltenVK}"
CC_HOST="${CC:-clang}"
CXX_HOST="${CXX:-clang++}"
SKIP_METAL=0
[ "${1:-}" = "--skip-metal" ] && SKIP_METAL=1

mkdir -p "$OUT_DIR"
echo "[bridge-tests] root=$ROOT out=$OUT_DIR"
FAILED=0
run() { # run <name> <command...>
  local name="$1"; shift
  echo "=== $name ==="
  if "$@" 2>&1 | tee "$OUT_DIR/$name.log"; then
    echo "[bridge-tests] $name: PASS"
  else
    echo "[bridge-tests] $name: FAIL"
    FAILED=1
  fi
}

# 1. Stub self-test (ABI v2).
$CC_HOST -O2 -I "$ROOT/bridge/abi" -DVRMC_STUB_TEST \
  "$ROOT/bridge/src/vrmc_stub.c" -lpthread -o "$OUT_DIR/vrmc_stub_test"
run stub-test "$OUT_DIR/vrmc_stub_test"

# 2. Frame handoff protocol + concurrency (normal build).
$CC_HOST -O2 -I "$ROOT/bridge/abi" \
  "$ROOT/bridge/tests/bridge_sync_test.c" "$ROOT/bridge/src/vrmc_stub.c" -lpthread \
  -o "$OUT_DIR/bridge_sync_test"
run sync-test "$OUT_DIR/bridge_sync_test"

# 2b. Same test under ThreadSanitizer: any data race in the shared handoff is fatal.
$CC_HOST -O1 -g -fsanitize=thread -fno-omit-frame-pointer -I "$ROOT/bridge/abi" \
  "$ROOT/bridge/tests/bridge_sync_test.c" "$ROOT/bridge/src/vrmc_stub.c" -lpthread \
  -o "$OUT_DIR/bridge_sync_test_tsan"
TSAN_OPTIONS="halt_on_error=1" run sync-test-tsan "$OUT_DIR/bridge_sync_test_tsan"

# 3. Display-view JNI byte layout (regression from EV-0090).
$CC_HOST -O2 "$ROOT/scripts/tests/DisplayViewsLayoutTest.c" -o "$OUT_DIR/display_views_layout_test"
run display-views-layout "$OUT_DIR/display_views_layout_test"

# 4. Bridge dylib build (host + device) with the symbol verification in scripts/build_bridge.sh.
BRIDGE_BUILD_DIR="$OUT_DIR/bridge-build"
mkdir -p "$BRIDGE_BUILD_DIR"
run build-bridge env OUT_DIR="$BRIDGE_BUILD_DIR" "$ROOT/scripts/build_bridge.sh" MODE=both

# 5. Optional real MoltenVK/Metal host probe.
MVK_LIB="$MVK_ROOT/dynamic/dylib/macOS"
MVK_INC="$MVK_ROOT/include"
if [ "$SKIP_METAL" = "1" ]; then
  echo "[bridge-tests] metal-host-probe: SKIP (--skip-metal)"
elif [ -f "$MVK_LIB/libMoltenVK.dylib" ] && [ -f "$MVK_INC/vulkan/vulkan.h" ]; then
  $CC_HOST -O2 -I "$ROOT/bridge/abi" -c "$ROOT/bridge/src/vrmc_stub.c" -o "$OUT_DIR/vrmc_stub_for_probe.o"
  $CXX_HOST -O2 -fobjc-arc -x objective-c++ -std=c++17 \
    -I "$ROOT/bridge/abi" -I "$MVK_INC" -c "$ROOT/bridge/tests/bridge_metal_sync_host.mm" \
    -o "$OUT_DIR/bridge_metal_sync_host.o"
  $CXX_HOST -O2 "$OUT_DIR/bridge_metal_sync_host.o" "$OUT_DIR/vrmc_stub_for_probe.o" \
    -L "$MVK_LIB" -lMoltenVK -framework Metal -framework Foundation -lpthread \
    -Wl,-rpath,"$MVK_LIB" -o "$OUT_DIR/bridge_metal_sync_host"
  BUNDLE_PATH="$MVK_LIB" DYLD_LIBRARY_PATH="$MVK_LIB" MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 \
    run metal-host-probe "$OUT_DIR/bridge_metal_sync_host"
  if grep -qiE "validation error|failed assertion|metal api validation: error" "$OUT_DIR/metal-host-probe.log" 2>/dev/null; then
    echo "[bridge-tests] metal-host-probe: Metal validation errors present -> FAIL"
    FAILED=1
  fi
else
  echo "[bridge-tests] metal-host-probe: SKIP (no MoltenVK macOS SDK at $MVK_ROOT; see header)"
fi

if [ "$FAILED" != "0" ]; then
  echo "[bridge-tests] FAILED"
  exit 1
fi
echo "[bridge-tests] ALL PASS"
