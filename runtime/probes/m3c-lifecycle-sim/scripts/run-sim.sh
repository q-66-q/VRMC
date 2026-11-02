#!/bin/bash
# M3C lifecycle probe driver (visionOS simulator only).
#
# Builds runtime/probes/m3c-lifecycle-sim for the booted visionOS simulator, installs it, and runs
# the window-parking variant matrix. For every variant it captures a Documents/sim-shell.log +
# console log + timed simulator screenshots (downscaled JPEGs) under results/<variant>/.
#
# Usage:
#   scripts/run-sim.sh                 # build + run all variants
#   scripts/run-sim.sh build           # build + install only
#   scripts/run-sim.sh 03-hidden-open 04-hidden-firstframe   # build + run selected variants
set -uo pipefail

UDID="${UDID:-F025E133-019D-4811-944F-F3C8226E14CB}"
BUNDLE="dev.vrmc.m3c"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED:-/tmp/m3c-build}"
APP="$DERIVED/Build/Products/Debug-xrsimulator/M3CProbe.app"
RESULTS="$HERE/results"

cd "$HERE" || exit 1

build() {
  xcodegen generate >/dev/null || exit 1
  xcodebuild -project M3CProbe.xcodeproj -scheme M3CProbe -configuration Debug \
    -destination "platform=visionOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build 2>&1 | \
    grep -E 'error:|BUILD (SUCCEEDED|FAILED)' || exit 1
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl install "$UDID" "$APP" || exit 1
  echo "installed $APP on $UDID"
}

variant_args() {
  case "$1" in
    01-nopark-open)            ARGS=(-M3CPark none -M3CParkWhen open -M3COpenDelay 1.0) ;;
    02-alpha-open)             ARGS=(-M3CPark alpha -M3CParkWhen open -M3COpenDelay 1.0) ;;
    03-hidden-open)            ARGS=(-M3CPark hidden -M3CParkWhen open -M3COpenDelay 1.0) ;;
    04-hidden-firstframe)      ARGS=(-M3CPark hidden -M3CParkWhen firstframe -M3COpenDelay 1.0) ;;
    05-alpha-firstframe)       ARGS=(-M3CPark alpha -M3CParkWhen firstframe -M3COpenDelay 1.0) ;;
    06-tinyalpha-firstframe)   ARGS=(-M3CPark tinyalpha -M3CParkWhen firstframe -M3COpenDelay 1.0) ;;
    07-contentalpha-firstframe) ARGS=(-M3CPark contentalpha -M3CParkWhen firstframe -M3COpenDelay 1.0) ;;
    08-contenthidden-firstframe) ARGS=(-M3CPark contenthidden -M3CParkWhen firstframe -M3COpenDelay 1.0) ;;
    09-nopark-launch)          ARGS=(-M3CPark none -M3CParkWhen open -M3COpenDelay 0.0) ;;
    10-hidden-restore)         ARGS=(-M3CPark hidden -M3CParkWhen firstframe -M3COpenDelay 1.0 -M3CRestoreAfter 6.0) ;;
    11-alpha-reopen)           ARGS=(-M3CPark alpha -M3CParkWhen firstframe -M3COpenDelay 1.0 -M3CReopen 1 -M3CReopenAfter 8.0) ;;
    12-hidden-secondwindow)    ARGS=(-M3CPark hidden -M3CParkWhen firstframe -M3COpenDelay 1.0 -M3CSecondWindow 1 -M3CParkScope main) ;;
    *) echo "unknown variant $1"; ARGS=() ;;
  esac
}

run_variant() {
  local tag="$1"
  local -a ARGS
  variant_args "$tag"
  if [ "${#ARGS[@]}" -eq 0 ]; then
    echo "skip $tag (no args)"
    return
  fi
  local out="$RESULTS/$tag"
  rm -rf "$out"
  mkdir -p "$out"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  sleep 1
  local container
  container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null)
  rm -f "$container/Documents/sim-shell.log"
  echo "=== $tag : ${ARGS[*]}"
  printf '%s\n' "${ARGS[@]}" > "$out/args.txt"
  xcrun simctl launch "$UDID" "$BUNDLE" "${ARGS[@]}" > "$out/launch.txt" 2>&1
  local prev=0 d
  for d in 3 8 14 20 26; do
    sleep $((d - prev))
    prev=$d
    xcrun simctl io "$UDID" screenshot "/tmp/m3c-$tag-t$d.png" >/dev/null 2>&1
    sips -Z 1024 -s format jpeg -s formatOptions 78 "/tmp/m3c-$tag-t$d.png" --out "$out/shot-t$d.jpg" >/dev/null 2>&1
    rm -f "/tmp/m3c-$tag-t$d.png"
  done
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  sleep 1
  if [ -f "$container/Documents/sim-shell.log" ]; then
    cp "$container/Documents/sim-shell.log" "$out/sim-shell.log"
  else
    echo "MISSING sim-shell.log" > "$out/sim-shell.log"
  fi
  xcrun simctl spawn "$UDID" log show --last 2m --style compact \
    --predicate 'process == "M3CProbe"' > "$out/console.log" 2>/dev/null
  echo "  -> $out : $(wc -l < "$out/sim-shell.log") log lines, $(ls "$out"/shot-*.jpg 2>/dev/null | wc -l | tr -d ' ') screenshots"
}

if [ "${1:-}" = "build" ]; then
  build
  exit 0
fi

build || exit 1
mkdir -p "$RESULTS"

if [ "$#" -gt 0 ]; then
  for v in "$@"; do run_variant "$v"; done
else
  for v in 01-nopark-open 02-alpha-open 03-hidden-open 04-hidden-firstframe \
           05-alpha-firstframe 06-tinyalpha-firstframe 07-contentalpha-firstframe \
           08-contenthidden-firstframe 09-nopark-launch 10-hidden-restore \
           11-alpha-reopen 12-hidden-secondwindow; do
    run_variant "$v"
  done
fi

echo "=== summary of key lines ==="
for dir in "$RESULTS"/*/; do
  [ -f "$dir/sim-shell.log" ] || continue
  tag=$(basename "$dir")
  park=$(grep -m1 'PARK begin' "$dir/sim-shell.log" | sed 's/.*PARK begin //')
  deact=$(grep -c 'UIScene.willDeactivate' "$dir/sim-shell.log")
  resign=$(grep -c 'UIApplication.willResignActive' "$dir/sim-shell.log")
  bg=$(grep -c 'UIApplication.didEnterBackground' "$dir/sim-shell.log")
  inval=$(grep -c 'INVALIDATED' "$dir/sim-shell.log")
  end=$(grep -c 'VRMCImmersiveEnded' "$dir/sim-shell.log")
  lastframe=$(grep 'TICK' "$dir/sim-shell.log" | tail -1 | sed -E 's/.*comp\(frames=([0-9]+).*/\1/')
  echo "$tag | willDeactivate=$deact willResignActive=$resign didEnterBackground=$bg inval=$inval immersiveEnded=$end lastFrames=$lastframe"
done