#!/bin/bash
# M8 host Fabric harness: validate the provider's render-feedback -> eye-target resize path in a real
# Minecraft client on the Mac (desktop GL backend). No headset, no CompositorServices: a host-only test
# dylib publishes fake 4K-class foveated display geometry at 120 Hz through the real native-shared
# channel, and the provider must poll it, size its stereo eye targets from it and rebuild its render
# targets exactly once (Vivecraft "Reinit Render" path).
#
# This is HOST evidence: it does not prove device optics, eye-tracked foveation, Vulkan/MoltenVK or
# refresh rate. It validates the provider-side resize code path in a real Minecraft client.
#
# Requirements:
#   * VIVECRAFT_REF: the external Vivecraft 26.2 multiloader reference tree (not committed):
#       VIVECRAFT_REF=/private/tmp/.../VivecraftMod-Multiloader-26.2
#   * JDK 25 (temurin-25), Xcode command line tools, and a built provider jar
#       /tmp/vrmc-provider-build/vrmc-provider.jar (scripts/build_provider.sh)
#   * Gradle caches/network for the reference project (first run may download)
#
# Usage: VIVECRAFT_REF=<tree> scripts/m8_host_harness.sh [--timeout seconds] [--keep-running]
# Exit: 0 PASS (init + feedback + one resize + stable), 1 FAIL/timeout, 2 usage/setup error.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="${VIVECRAFT_REF:-}"
TIMEOUT="${M8_HARNESS_TIMEOUT:-240}"
KEEP=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2:?}"; shift 2 ;;
    --keep-running) KEEP=1; shift ;;
    *) echo "[m8-harness] unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REF" ] && [ -d "$REF" ] || { echo "[m8-harness] ERROR: set VIVECRAFT_REF to the external Vivecraft 26.2 reference tree" >&2; exit 2; }
[ -x "$REF/gradlew" ] || { echo "[m8-harness] ERROR: $REF/gradlew missing" >&2; exit 2; }
JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home}"
[ -x "$JAVA_HOME/bin/java" ] || { echo "[m8-harness] ERROR: JDK 25 not found at $JAVA_HOME" >&2; exit 2; }
OUT="${OUT:-/tmp/vrmc-m8-host-harness}"
mkdir -p "$OUT"
LOG="$OUT/harness.log"
: > "$LOG"
say() { echo "[m8-harness] $*" | tee -a "$LOG"; }

PROVIDER_JAR="${PROVIDER_JAR:-/tmp/vrmc-provider-build/vrmc-provider.jar}"
[ -f "$PROVIDER_JAR" ] || { say "ERROR: provider jar missing: $PROVIDER_JAR (run scripts/build_provider.sh)"; exit 2; }

# ---- 1. host test bridge dylib (real bridge stub + M8 publisher) -------------------------------
say "building host test bridge dylib (real bridge + render-feedback publisher)"
JDK="$JAVA_HOME"
SDK=$(xcrun --sdk macosx --show-sdk-path)
DYLIB="$OUT/libvrmc_bridge_host_test.dylib"
xcrun --sdk macosx clang -target arm64-apple-macos27.0 -isysroot "$SDK" -dynamiclib -fPIC -O2 \
  -I "$ROOT/bridge/abi" -I "$JDK/include" -I "$JDK/include/darwin" \
  -o "$DYLIB" "$ROOT/bridge/src/vrmc_stub.c" "$ROOT/bridge/src/vrmc_jni.c" \
  "$ROOT/bridge/tests/host_render_settings_publisher.c" -lpthread >> "$LOG" 2>&1 \
  || { say "ERROR: host test dylib build failed (see $LOG)"; exit 2; }
say "host test dylib: $DYLIB"

# ---- 2. patch the reference project's client run config (idempotent) ---------------------------
BUILD_GRADLE="$REF/fabric/build.gradle"
if ! grep -q 'vrmc.bridge.lib=' "$BUILD_GRADLE"; then
  say "patching $BUILD_GRADLE client run with the VRMC M8 vmArgs"
  python3 - "$BUILD_GRADLE" "$DYLIB" "$PROVIDER_JAR" <<'PY' >> "$LOG" 2>&1
import sys
path, dylib, provider = sys.argv[1:4]
text = open(path).read()
old = """        client {
            client()
            setConfigName('Fabric Client')
            ideConfigGenerated(true)
            runDir('runs/client')
        }"""
new = """        client {
            client()
            setConfigName('Fabric Client')
            ideConfigGenerated(true)
            runDir('runs/client')
            // VRMC M8 host harness (scripts/m8_host_harness.sh): provider jar + host test bridge
            // whose render-feedback publisher feeds fake 4K-class display geometry at 120 Hz.
            vmArgs '-Dvrmc.hostHarness=true',
                   '-Dvrmc.bridge.lib=%s',
                   '-Dfabric.addMods=%s'
        }""" % (dylib, provider)
if old not in text:
    raise SystemExit("client run block not found (reference tree layout changed)")
open(path, "w").write(text.replace(old, new))
PY
  [ $? -eq 0 ] || { say "ERROR: could not patch fabric/build.gradle"; exit 2; }
else
  say "fabric/build.gradle already carries the M8 harness vmArgs (idempotent)"
fi

# ---- 3. enable Vivecraft VR in the dev run dir ------------------------------------------------
RUNDIR="$REF/fabric/runs/client"
mkdir -p "$RUNDIR/config" "$RUNDIR/logs"
cat > "$RUNDIR/config/vivecraft-client-config.json" <<'EOF'
{
  "vrEnabled": true,
  "stereoProviderPluginID": "OPENVR"
}
EOF
rm -f "$RUNDIR/logs/latest.log"
say "run dir: $RUNDIR (Vivecraft vrEnabled=true)"

# ---- 4. launch the real Minecraft dev client with the fake display feedback --------------------
say "launching :fabric:runClient (timeout ${TIMEOUT}s)"
( cd "$REF" && JAVA_HOME="$JAVA_HOME" VRMC_HOST_TEST_RENDER_SETTINGS=1 \
    ./gradlew :fabric:runClient --offline --console=plain >> "$LOG" 2>&1 ) &
GRADLE_PID=$!

LATEST="$RUNDIR/logs/latest.log"
DEADLINE=$((SECONDS + TIMEOUT))
RESIZE_LINE=""
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  if [ -f "$LATEST" ]; then
    RESIZE_LINE=$(grep -m1 '\[VRMC-M8\] eye target resize #1:' "$LATEST" 2>/dev/null || true)
    if [ -n "$RESIZE_LINE" ]; then break; fi
  fi
  sleep 2
done

PASS=0
if [ -n "$RESIZE_LINE" ]; then
  sleep 8   # let the reinit and a few render-state lines land
  INIT=$(grep -m1 'VisionVR.init() succeeded' "$LATEST" || true)
  BRIDGE=$(grep -m1 'bridge handshake ok' "$LATEST" || true)
  SETTINGS=$(grep -m1 '\[VRMC-M8\] render settings:' "$LATEST" || true)
  RESIZE_CONFIG=$(grep -m1 'Reinit Render: VRMC M8 eye target' "$LATEST" || true)
  NEW_TARGET=$(grep -m1 '\[VRMC-M2\] eye target L 1832x1600' "$LATEST" || true)
  HANDSHAKE=$(grep -m1 'VR Provider supplied texture resolution: 1832 x 1600' "$LATEST" || true)
  STATE=$(grep -m1 '\[VRMC-M8\] render state' "$LATEST" || true)
  ERRORS=$(grep -cE '\[VRMC-M8\].*(ERROR|Exception)' "$LATEST" || true)
  echo "=== evidence lines ===" | tee -a "$LOG"
  for line in "$INIT" "$BRIDGE" "$SETTINGS" "$RESIZE_LINE" "$RESIZE_CONFIG" "$NEW_TARGET" "$HANDSHAKE" "$STATE"; do
    [ -n "$line" ] && echo "  $line" | tee -a "$LOG"
  done
  if [ -n "$INIT" ] && [ -n "$RESIZE_LINE" ] && [ -n "$NEW_TARGET" ] && [ -n "$HANDSHAKE" ]; then
    PASS=1
  fi
  say "M8 renderer resize path: $([ "$PASS" = "1" ] && echo PASS || echo FAIL)"
else
  say "TIMEOUT: no '[VRMC-M8] eye target resize #1:' line within ${TIMEOUT}s (see $LOG / $LATEST)"
  tail -20 "$LATEST" 2>/dev/null | tee -a "$LOG"
fi

# ---- 5. stop the dev client (unless asked to keep it) -----------------------------------------
if [ "$KEEP" != "1" ]; then
  pkill -f 'net.fabricmc.loader.impl.launch.knot.KnotClient' 2>/dev/null || true
  sleep 2
  if [ -n "${GRADLE_PID:-}" ] && kill -0 "$GRADLE_PID" 2>/dev/null; then kill "$GRADLE_PID" 2>/dev/null || true; fi
  pkill -f 'gradlew :fabric:runClient' 2>/dev/null || true
fi
cp -f "$LATEST" "$OUT/latest.log" 2>/dev/null || true
say "harness log: $LOG ; minecraft log: $OUT/latest.log"
if [ "$PASS" = "1" ]; then
  say "RESULT: PASS (host GL: provider resized 1024x1024 -> 1832x1600 from fake 3660x3200 foveated display feedback; NOT device evidence)"
  exit 0
fi
say "RESULT: FAIL"
exit 1
