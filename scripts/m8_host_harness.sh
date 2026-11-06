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

# ---- 2. patch the reference project's client run config ---------------------------------------
# Idempotent AND re-pointed at THIS run's test dylib/provider jar every time: earlier harness versions
# only patched once, so a later run could silently reuse a stale dylib path (and a stale publisher).
BUILD_GRADLE="$REF/fabric/build.gradle"
say "patching $BUILD_GRADLE client run with the VRMC M8 vmArgs"
python3 - "$BUILD_GRADLE" "$DYLIB" "$PROVIDER_JAR" <<'PY' >> "$LOG" 2>&1
import re
import sys
path, dylib, provider = sys.argv[1:4]
text = open(path).read()
args = ("            vmArgs '-Dvrmc.hostHarness=true',\n"
        "                   '-Dvrmc.bridge.lib=%s',\n"
        "                   '-Dfabric.addMods=%s'") % (dylib, provider)
pattern = re.compile(r"            vmArgs '-Dvrmc\.hostHarness=true',.*?\n                   '-Dfabric\.addMods=[^']*'", re.S)
if pattern.search(text):
    text = pattern.sub(args, text, count=1)
else:
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
""" + args + "\n        }"
    if old not in text:
        raise SystemExit("client run block not found (reference tree layout changed)")
    text = text.replace(old, new)
open(path, "w").write(text)
PY
[ $? -eq 0 ] || { say "ERROR: could not patch fabric/build.gradle"; exit 2; }

# ---- 3. enable Vivecraft VR in the dev run dir ------------------------------------------------
RUNDIR="$REF/fabric/runs/client"
mkdir -p "$RUNDIR/config" "$RUNDIR/logs"
cat > "$RUNDIR/config/vivecraft-client-config.json" <<'EOF'
{
  "vrEnabled": true,
  "stereoProviderPluginID": "OPENVR"
}
EOF
# Optional M8 target-cadence knob: TARGET_HZ=auto|60..120 writes the game-dir file the provider
# re-reads every ~300 frames, so the harness can prove the override is honoured in a real client.
if [ -n "${TARGET_HZ:-}" ]; then
  case "$TARGET_HZ" in
    auto) ;;
    *[!0-9]*) say "ERROR: TARGET_HZ must be auto or 60..120 (got '$TARGET_HZ')"; exit 2 ;;
    *) [ "$TARGET_HZ" -ge 60 ] && [ "$TARGET_HZ" -le 120 ] \
         || { say "ERROR: TARGET_HZ must be 60..120 (got '$TARGET_HZ')"; exit 2; } ;;
  esac
  printf '%s\n' "$TARGET_HZ" > "$RUNDIR/vrmc-target-hz.txt"
  say "target cadence knob: $TARGET_HZ -> $RUNDIR/vrmc-target-hz.txt"
else
  rm -f "$RUNDIR/vrmc-target-hz.txt"
fi
# Optional M8 content-first knob (CONTENT_FIRST=on|off): the provider must log the mode it read.
if [ -n "${CONTENT_FIRST:-}" ]; then
  case "$CONTENT_FIRST" in
    on|off) printf '%s\n' "$CONTENT_FIRST" > "$RUNDIR/vrmc-content-first.txt"
            say "content-first knob: $CONTENT_FIRST -> $RUNDIR/vrmc-content-first.txt" ;;
    *) say "ERROR: CONTENT_FIRST must be on or off (got '$CONTENT_FIRST')"; exit 2 ;;
  esac
else
  rm -f "$RUNDIR/vrmc-content-first.txt"
fi
# Optional M8 display-cadence simulation (DISPLAY_HZ=60..240): the host test publisher reports this
# as the measured display cadence instead of 120 Hz. With TARGET_HZ higher it exercises the provider's
# "target cadence unreachable" guardrail (revert to the measured cadence after 8 windows).
if [ -n "${DISPLAY_HZ:-}" ]; then
  case "$DISPLAY_HZ" in
    *[!0-9]*) say "ERROR: DISPLAY_HZ must be 60..240 (got '$DISPLAY_HZ')"; exit 2 ;;
    *) [ "$DISPLAY_HZ" -ge 60 ] && [ "$DISPLAY_HZ" -le 240 ] \
         || { say "ERROR: DISPLAY_HZ must be 60..240 (got '$DISPLAY_HZ')"; exit 2; } ;;
  esac
  printf '%s\n' "$DISPLAY_HZ" > "$RUNDIR/vrmc-host-display-hz.txt"
  say "display cadence simulation: $DISPLAY_HZ Hz (host test publisher, $RUNDIR/vrmc-host-display-hz.txt)"
else
  rm -f "$RUNDIR/vrmc-host-display-hz.txt"
fi
# Optional M8 world-supersample knob (SUPERSAMPLE=off|1.0..2.0): startup-only SSAA via Vivecraft's
# renderScaleFactor (world render target = eye target * sqrt(factor)); the provider logs the mode it read.
if [ -n "${SUPERSAMPLE:-}" ]; then
  case "$SUPERSAMPLE" in
    off) ;;
    *[!0-9.]*) say "ERROR: SUPERSAMPLE must be off or 1.0..2.0 (got '$SUPERSAMPLE')"; exit 2 ;;
    *) awk -v v="$SUPERSAMPLE" 'BEGIN { exit !(v >= 1.0 && v <= 2.0) }' \
         || { say "ERROR: SUPERSAMPLE must be off or 1.0..2.0 (got '$SUPERSAMPLE')"; exit 2; } ;;
  esac
  printf '%s\n' "$SUPERSAMPLE" > "$RUNDIR/vrmc-world-supersample.txt"
  say "world-supersample knob: $SUPERSAMPLE -> $RUNDIR/vrmc-world-supersample.txt"
else
  rm -f "$RUNDIR/vrmc-world-supersample.txt"
fi
rm -f "$RUNDIR/logs/latest.log" "$RUNDIR/vrmc-m8-trace.csv"
say "run dir: $RUNDIR (Vivecraft vrEnabled=true, fresh M8 trace)"

# ---- 4. launch the real Minecraft dev client with the fake display feedback --------------------
say "launching :fabric:runClient (timeout ${TIMEOUT}s)"
DISPLAY_ENV=""
if [ -n "${DISPLAY_HZ:-}" ]; then DISPLAY_ENV="VRMC_HOST_TEST_DISPLAY_HZ=$DISPLAY_HZ"; fi
( cd "$REF" && env JAVA_HOME="$JAVA_HOME" VRMC_HOST_TEST_RENDER_SETTINGS=1 $DISPLAY_ENV \
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
  # Guardrail expectation: a target cadence above the simulated display cadence must revert to auto.
  REVERT_EXPECT=0
  if [ -n "${TARGET_HZ:-}" ] && [ -n "${DISPLAY_HZ:-}" ]; then
    case "$TARGET_HZ" in
      *[!0-9]*) ;;
      *) [ "$TARGET_HZ" -gt "$DISPLAY_HZ" ] && REVERT_EXPECT=1 ;;
    esac
  fi
  REVERT=""
  if [ "$REVERT_EXPECT" = "1" ]; then
    for _ in $(seq 1 20); do
      REVERT=$(grep -m1 '\[VRMC-M8\] target cadence: .* unreachable' "$LATEST" 2>/dev/null || true)
      [ -n "$REVERT" ] && break
      sleep 1
    done
  else
    REVERT=$(grep -m1 '\[VRMC-M8\] target cadence: .* unreachable' "$LATEST" 2>/dev/null || true)
  fi
  INIT=$(grep -m1 'VisionVR.init() succeeded' "$LATEST" || true)
  BRIDGE=$(grep -m1 'bridge handshake ok' "$LATEST" || true)
  SETTINGS=$(grep -m1 '\[VRMC-M8\] render settings:' "$LATEST" || true)
  RESIZE_CONFIG=$(grep -m1 'Reinit Render: VRMC M8 eye target' "$LATEST" || true)
  NEW_TARGET=$(grep -m1 '\[VRMC-M2\] eye target L 1832x1600' "$LATEST" || true)
  HANDSHAKE=$(grep -m1 'VR Provider supplied texture resolution: 1832 x 1600' "$LATEST" || true)
  STATE=$(grep -m1 '\[VRMC-M8\] render state' "$LATEST" || true)
  TARGET=$(grep -m1 '\[VRMC-M8\] target cadence:' "$LATEST" || true)
  CONTENT=$(grep -m1 '\[VRMC-M8\] content governor:' "$LATEST" || true)
  SUPERSAMPLE_LINE=$(grep -m1 '\[VRMC-M8\] world supersample:' "$LATEST" || true)
  TRACE_LINE=$(grep -m1 '\[VRMC-M8\] trace:' "$LATEST" || true)
  TRACE_FILE="$RUNDIR/vrmc-m8-trace.csv"
  TRACE_ROWS=0
  if [ -f "$TRACE_FILE" ]; then
    TRACE_ROWS=$(tail -n +2 "$TRACE_FILE" 2>/dev/null | wc -l | tr -d ' ')
  fi
  ERRORS=$(grep -cE '\[VRMC-M8\].*(ERROR|Exception)' "$LATEST" || true)
  echo "=== evidence lines ===" | tee -a "$LOG"
  for line in "$INIT" "$BRIDGE" "$SETTINGS" "$RESIZE_LINE" "$RESIZE_CONFIG" "$NEW_TARGET" "$HANDSHAKE" "$STATE" "$TARGET" "$CONTENT" "$REVERT" "$SUPERSAMPLE_LINE" "$TRACE_LINE"; do
    [ -n "$line" ] && echo "  $line" | tee -a "$LOG"
  done
  say "frame trace: rows=$TRACE_ROWS file=$TRACE_FILE"
  if [ -f "$TRACE_FILE" ]; then
    cp -f "$TRACE_FILE" "$OUT/vrmc-m8-trace.csv" 2>/dev/null || true
    echo "  trace first: $(head -2 "$TRACE_FILE" | tail -1)" | tee -a "$LOG"
    echo "  trace last:  $(tail -1 "$TRACE_FILE")" | tee -a "$LOG"
  fi
  if [ -n "$INIT" ] && [ -n "$RESIZE_LINE" ] && [ -n "$NEW_TARGET" ] && [ -n "$HANDSHAKE" ]; then
    PASS=1
  fi
  if [ -n "${TARGET_HZ:-}" ] && [ "$TARGET_HZ" != "auto" ] && [ -z "$TARGET" ]; then
    say "target-cadence knob was set but no '[VRMC-M8] target cadence:' line appeared"
    PASS=0
  fi
  if [ -n "${CONTENT_FIRST:-}" ] && [ -z "$CONTENT" ]; then
    say "content-first knob was set but no '[VRMC-M8] content governor:' line appeared"
    PASS=0
  fi
  if [ "$REVERT_EXPECT" = "1" ] && [ -z "$REVERT" ]; then
    say "target cadence above the simulated display cadence but no 'unreachable ... reverting to auto' line appeared"
    PASS=0
  fi
  if [ -n "${SUPERSAMPLE:-}" ] && [ "$SUPERSAMPLE" != "off" ] && [ -z "$SUPERSAMPLE_LINE" ]; then
    say "world-supersample knob was set but no '[VRMC-M8] world supersample:' line appeared"
    PASS=0
  fi
  if [ -z "$TRACE_LINE" ] || [ "${TRACE_ROWS:-0}" -lt 1 ] 2>/dev/null; then
    say "M8 frame trace missing ('$TRACE_FILE' rows=$TRACE_ROWS): the provider did not write vrmc-m8-trace.csv"
    PASS=0
  fi
  # Optional soak with all knobs enabled: keep the real client running and re-check the M8 invariants.
  if [ -n "${SOAK_SECONDS:-}" ] && [ "$SOAK_SECONDS" -gt 0 ] 2>/dev/null; then
    say "soaking ${SOAK_SECONDS}s with the client running (knobs stay active) ..."
    sleep "$SOAK_SECONDS"
    SOAK_RESIZES=$(grep -c '\[VRMC-M8\] eye target resize' "$LATEST" 2>/dev/null || true)
    SOAK_ERRORS=$(grep -cE '\[VRMC-M8\].*(ERROR|Exception)' "$LATEST" 2>/dev/null || true)
    SOAK_STATE=$(grep '\[VRMC-M8\] render state' "$LATEST" 2>/dev/null | tail -1 || true)
    echo "  soak after ${SOAK_SECONDS}s: resizes=${SOAK_RESIZES} M8-exceptions=${SOAK_ERRORS}" | tee -a "$LOG"
    [ -n "$SOAK_STATE" ] && echo "  $SOAK_STATE" | tee -a "$LOG"
    if [ "${SOAK_ERRORS:-0}" != "0" ]; then
      say "soak found ${SOAK_ERRORS} M8 exception line(s)"
      PASS=0
    fi
    if [ "${SOAK_RESIZES:-0}" -lt 1 ] 2>/dev/null; then
      say "soak expected at least one eye-target resize"
      PASS=0
    fi
    # Re-copy the trace after the soak: it gains one row per auto-policy window (~2 s), so the
    # pre-soak copy would only show warm-up.
    TRACE_ROWS=$(tail -n +2 "$TRACE_FILE" 2>/dev/null | wc -l | tr -d ' ')
    cp -f "$TRACE_FILE" "$OUT/vrmc-m8-trace.csv" 2>/dev/null || true
    say "soak frame trace: rows=$TRACE_ROWS (copied to OUT)"
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
  KNOB_NOTE=""
if [ -n "${TARGET_HZ:-}" ]; then KNOB_NOTE="; target-cadence knob $TARGET_HZ honoured"; fi
if [ -n "${DISPLAY_HZ:-}" ]; then
  KNOB_NOTE="$KNOB_NOTE; simulated display $DISPLAY_HZ Hz"
  if [ -n "$REVERT" ]; then KNOB_NOTE="$KNOB_NOTE (guardrail reverted)"; fi
fi
if [ -n "${SUPERSAMPLE:-}" ]; then KNOB_NOTE="$KNOB_NOTE; world supersample $SUPERSAMPLE"; fi
say "RESULT: PASS (host GL: provider resized 1024x1024 -> 1832x1600 from fake 3660x3200 foveated display feedback$KNOB_NOTE; NOT device evidence)"
  exit 0
fi
say "RESULT: FAIL"
exit 1
