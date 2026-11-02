#!/bin/bash
# Host tests for the VRMC native bridge (no device, no headset).
#
#   1.  stub-test               - ABI v3 stub self-test (v3 accept / v2 reject handshake, submit,
#                                 shared eye frame, display views, input publish/poll/acquire/
#                                 sequence/release snapshot)
#   2.  sync-test               - eye-frame publish/acquire protocol + generation/sync + concurrency
#   2b. sync-test-tsan          - same test under ThreadSanitizer (-fsanitize=thread); skipped in
#                                 --skip-tsan fast mode. Proves the shared eye handoff is race-free.
#   3.  input-test              - ABI v3 input channel: layout static asserts (hand 368 B / input
#                                 752 B / all offsets + 12-byte joint stride), publish/poll/acquire
#                                 round-trip, monotonic sequence, safe pre-publish zero snapshot,
#                                 NULL/short/uninitialized rejection, release snapshot, and 500k
#                                 publish x 4 reader torn-snapshot detection
#   3b. input-test-tsan         - same test under ThreadSanitizer; skipped in --skip-tsan fast mode
#   4.  input-fixture           - bridge/tests/make_input_fixture.c: documented deterministic
#                                 10-record (150 ms spacing) hand scenario published through the
#                                 bridge -> 752-byte contract snapshot (argv[1]) + 7520-byte 10-record
#                                 .frames timeline sidecar;
#                                 artifact sizes + self-reported sha256 checked against shasum
#   5.  display-views-layout    - JNI display-view byte layout vs VisionVR.pollDisplayViews() offsets
#   6.  build-bridge            - scripts/build_bridge.sh MODE=both (host+device dylib, platform/
#                                 minos retag) + exported symbol verification incl. ABI v3 input
#                                 (vrmc_poll_input, vrmc_shared_publish_input/acquire/sequence,
#                                 JNI nativePollInput)
#   7.  metal-host-probe        - (optional) real MoltenVK+Metal host probe: exported MTLTexture
#                                 ShaderRead usage + timeline MTLSharedEvent wait ordering across a
#                                 separate compositor thread/queue. Needs a MoltenVK macOS SDK:
#                                   curl -LO https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-macos.tar
#                                   mkdir -p /tmp/vrmc-host-mvk && tar -xf MoltenVK-macos.tar -C /tmp/vrmc-host-mvk
#                                 (MVK_ROOT overrides the location; skipped with a message if absent)
#
# Usage: bridge/tests/run_tests.sh [--skip-metal] [--skip-tsan]
#   --skip-metal  skip step 7 (no MoltenVK macOS SDK / fast local loop)
#   --skip-tsan   skip steps 2b/3b (fast local loop; the full run is the default and is what the
#                 M4-W1 acceptance/selfcheck uses)
# Logs go to $OUT_DIR (default /tmp/vrmc-bridge-tests).
# Exit code: 0 only when every non-skipped step passes; 1 on any test failure; 2 on bad usage.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-/tmp/vrmc-bridge-tests}"
MVK_ROOT="${MVK_ROOT:-/tmp/vrmc-host-mvk/MoltenVK/MoltenVK}"
CC_HOST="${CC:-clang}"
CXX_HOST="${CXX:-clang++}"
SKIP_METAL=0
SKIP_TSAN=0
for arg in "$@"; do
  case "$arg" in
    --skip-metal) SKIP_METAL=1 ;;
    --skip-tsan)  SKIP_TSAN=1 ;;
    *) echo "[bridge-tests] unknown argument: $arg (usage: run_tests.sh [--skip-metal] [--skip-tsan])" >&2
       exit 2 ;;
  esac
done

mkdir -p "$OUT_DIR"
echo "[bridge-tests] root=$ROOT out=$OUT_DIR skip_metal=$SKIP_METAL skip_tsan=$SKIP_TSAN"
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
compile() { # compile <name> <command...>; a failed compile is a failure, never a stale binary
  local name="$1"; shift
  echo "=== $name (build) ==="
  if "$@" 2>&1 | tee "$OUT_DIR/$name-build.log"; then
    echo "[bridge-tests] $name (build): PASS"
    return 0
  fi
  echo "[bridge-tests] $name (build): FAIL"
  FAILED=1
  return 1
}
skip() { echo "[bridge-tests] $1: SKIP ($2)"; }

# 1. Stub self-test (ABI v3: v2 caps must be rejected, v3 accepted).
if compile stub-test $CC_HOST -O2 -I "$ROOT/bridge/abi" -DVRMC_STUB_TEST \
    "$ROOT/bridge/src/vrmc_stub.c" -lpthread -o "$OUT_DIR/vrmc_stub_test"; then
  run stub-test "$OUT_DIR/vrmc_stub_test"
fi

# 2. Eye-frame handoff protocol + concurrency (normal build).
if compile sync-test $CC_HOST -O2 -I "$ROOT/bridge/abi" \
    "$ROOT/bridge/tests/bridge_sync_test.c" "$ROOT/bridge/src/vrmc_stub.c" -lpthread \
    -o "$OUT_DIR/bridge_sync_test"; then
  run sync-test "$OUT_DIR/bridge_sync_test"
fi

# 2b. Same eye-frame test under ThreadSanitizer: any data race in the shared handoff is fatal.
if [ "$SKIP_TSAN" = "1" ]; then
  skip sync-test-tsan "--skip-tsan"
elif compile sync-test-tsan $CC_HOST -O1 -g -fsanitize=thread -fno-omit-frame-pointer \
    -I "$ROOT/bridge/abi" "$ROOT/bridge/tests/bridge_sync_test.c" \
    "$ROOT/bridge/src/vrmc_stub.c" -lpthread -o "$OUT_DIR/bridge_sync_test_tsan"; then
  TSAN_OPTIONS="halt_on_error=1" run sync-test-tsan "$OUT_DIR/bridge_sync_test_tsan"
fi

# 3. ABI v3 input channel: layout/round-trip/sequence/safe-zero/rejection + torn-read detection.
if compile input-test $CC_HOST -O2 -I "$ROOT/bridge/abi" \
    "$ROOT/bridge/tests/bridge_input_test.c" "$ROOT/bridge/src/vrmc_stub.c" -lpthread \
    -o "$OUT_DIR/bridge_input_test"; then
  run input-test "$OUT_DIR/bridge_input_test"
fi

# 3b. Same input test under ThreadSanitizer (500k publishes x 4 readers): races are fatal.
if [ "$SKIP_TSAN" = "1" ]; then
  skip input-test-tsan "--skip-tsan"
elif compile input-test-tsan $CC_HOST -O1 -g -fsanitize=thread -fno-omit-frame-pointer \
    -I "$ROOT/bridge/abi" "$ROOT/bridge/tests/bridge_input_test.c" \
    "$ROOT/bridge/src/vrmc_stub.c" -lpthread -o "$OUT_DIR/bridge_input_test_tsan"; then
  TSAN_OPTIONS="halt_on_error=1" run input-test-tsan "$OUT_DIR/bridge_input_test_tsan"
fi

# 4. Cross-language contract fixture generator (the exact build shape scripts/m4_input_selfcheck.sh uses).
if compile input-fixture $CC_HOST -O2 -I "$ROOT/bridge/abi" \
    "$ROOT/bridge/tests/make_input_fixture.c" "$ROOT/bridge/src/vrmc_stub.c" -lpthread \
    -o "$OUT_DIR/make_input_fixture"; then
  FIXTURE="$OUT_DIR/input_fixture.bin"
  run input-fixture "$OUT_DIR/make_input_fixture" "$FIXTURE"
  if [ -f "$FIXTURE" ] && [ -f "$FIXTURE.frames" ] && [ -f "$OUT_DIR/input-fixture.log" ]; then
    PRIMARY_BYTES=$(wc -c < "$FIXTURE" | tr -d ' ')
    FRAMES_BYTES=$(wc -c < "$FIXTURE.frames" | tr -d ' ')
    PRIMARY_SHA=$(shasum -a 256 "$FIXTURE" | awk '{print $1}')
    FRAMES_SHA=$(shasum -a 256 "$FIXTURE.frames" | awk '{print $1}')
    PRINTED_PRIMARY_SHA=$(grep -E '^fixture path=.* sha256=[0-9a-f]{64}$' "$OUT_DIR/input-fixture.log" \
      | sed -E 's/.*sha256=//' | tail -1)
    PRINTED_FRAMES_SHA=$(grep -E '^fixture\.frames path=.* sha256=[0-9a-f]{64}$' "$OUT_DIR/input-fixture.log" \
      | sed -E 's/.*sha256=//' | tail -1)
    if [ "$PRIMARY_BYTES" = "752" ] && [ "$FRAMES_BYTES" = "7520" ] \
       && [ "$PRIMARY_SHA" = "$PRINTED_PRIMARY_SHA" ] && [ "$FRAMES_SHA" = "$PRINTED_FRAMES_SHA" ]; then
      echo "[bridge-tests] input-fixture-artifacts: PASS (752 B sha256=$PRIMARY_SHA; 7520 B sha256=$FRAMES_SHA)"
    else
      echo "[bridge-tests] input-fixture-artifacts: FAIL (bytes primary=${PRIMARY_BYTES} frames=${FRAMES_BYTES}; sha primary='$PRIMARY_SHA' vs '$PRINTED_PRIMARY_SHA', frames='$FRAMES_SHA' vs '$PRINTED_FRAMES_SHA')"
      FAILED=1
    fi
  else
    echo "[bridge-tests] input-fixture-artifacts: FAIL (missing fixture artifacts)"
    FAILED=1
  fi
fi

# 5. Display-view JNI byte layout (regression from EV-0090).
if compile display-views-layout $CC_HOST -O2 "$ROOT/scripts/tests/DisplayViewsLayoutTest.c" \
    -o "$OUT_DIR/display_views_layout_test"; then
  run display-views-layout "$OUT_DIR/display_views_layout_test"
fi

# 6. Bridge dylib build (host + device) with the symbol verification in scripts/build_bridge.sh.
BRIDGE_BUILD_DIR="$OUT_DIR/bridge-build"
mkdir -p "$BRIDGE_BUILD_DIR"
run build-bridge env MODE=both OUT_DIR="$BRIDGE_BUILD_DIR" "$ROOT/scripts/build_bridge.sh"

# 7. Optional real MoltenVK/Metal host probe.
MVK_LIB="$MVK_ROOT/dynamic/dylib/macOS"
MVK_INC="$MVK_ROOT/include"
if [ "$SKIP_METAL" = "1" ]; then
  skip metal-host-probe "--skip-metal"
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
  skip metal-host-probe "no MoltenVK macOS SDK at $MVK_ROOT; see header"
fi

if [ "$FAILED" != "0" ]; then
  echo "[bridge-tests] FAILED"
  exit 1
fi
echo "[bridge-tests] ALL PASS"
