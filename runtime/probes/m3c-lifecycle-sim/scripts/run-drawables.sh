#!/bin/bash
# M3C drawable-array / capture-target probe driver (visionOS simulator only).
#
# Answers: does cp_frame_query_drawables() return more than one drawable (builtIn + capture)?
# Does a capture target appear while the simulator is being recorded/screenshotted? What does the
# deprecated cp_frame_query_drawable() return when a capture target exists? And does drawing only
# some drawables produce a partial/black capture?
#
# Runs are named d1..d5 (-M3CDrawablesMode all|first|builtin|legacy, capture on/off) plus the
# transparent-window parking variant 13.
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
  echo "installed $APP"
}

shrink() {
  local src="$1" dst="$2"
  sips -Z 1024 -s format jpeg -s formatOptions 78 "$src" --out "$dst" >/dev/null 2>&1
  rm -f "$src"
}

run_probe() {
  local tag="$1"
  local recording="$2"
  shift 2
  local out="$RESULTS/$tag"
  rm -rf "$out"
  mkdir -p "$out"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  sleep 1
  local container
  container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null)
  rm -f "$container/Documents/sim-shell.log"
  echo "=== $tag : $* (recording=$recording)"
  printf '%s\n' "$@" > "$out/args.txt"
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" > "$out/launch.txt" 2>&1
  sleep 4
  xcrun simctl io "$UDID" screenshot "/tmp/$tag-t4.png" >/dev/null 2>&1
  shrink "/tmp/$tag-t4.png" "$out/shot-t04.jpg"
  sleep 2
  local recpid=""
  if [ "$recording" = "1" ]; then
    xcrun simctl io "$UDID" recordVideo --codec=h264 --force "/tmp/$tag.mp4" > "$out/record.log" 2>&1 &
    recpid=$!
    echo "$recpid" > "$out/rec.pid"
    sleep 2
    xcrun simctl io "$UDID" screenshot "/tmp/$tag-t8.png" >/dev/null 2>&1
    shrink "/tmp/$tag-t8.png" "$out/shot-t08-recording.jpg"
    sleep 8
    kill -INT "$recpid" >/dev/null 2>&1
    sleep 2
  else
    sleep 2
    xcrun simctl io "$UDID" screenshot "/tmp/$tag-t8.png" >/dev/null 2>&1
    shrink "/tmp/$tag-t8.png" "$out/shot-t08.jpg"
    sleep 6
  fi
  xcrun simctl io "$UDID" screenshot "/tmp/$tag-t16.png" >/dev/null 2>&1
  shrink "/tmp/$tag-t16.png" "$out/shot-t16.jpg"
  if [ -f "/tmp/$tag.mp4" ]; then
    cp "/tmp/$tag.mp4" "$out/recording.mp4" 2>/dev/null
    ffmpeg -y -ss 3 -i "/tmp/$tag.mp4" -frames:v 1 "$out/rec-frame.jpg" >/dev/null 2>&1
    echo "recording: $(ls -la "/tmp/$tag.mp4" | awk '{print $5}') bytes"
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  sleep 1
  if [ -f "$container/Documents/sim-shell.log" ]; then
    cp "$container/Documents/sim-shell.log" "$out/sim-shell.log"
  else
    echo "MISSING sim-shell.log" > "$out/sim-shell.log"
  fi
  xcrun simctl spawn "$UDID" log show --last 2m --style compact \
    --predicate 'process == "M3CProbe"' > "$out/console.log" 2>/dev/null
  echo "  -> $out"
}

if [ "${1:-}" = "build" ]; then
  build
  exit 0
fi
if [ "${1:-}" != "--no-build" ]; then
  build || exit 1
else
  shift
fi
mkdir -p "$RESULTS"

if [ "$#" -gt 0 ]; then
  for tag in "$@"; do
    case "$tag" in
      d1-all-capture)        run_probe "$tag" 1 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode all ;;
      d2-first-capture)      run_probe "$tag" 1 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode first ;;
      d3-builtin-capture)    run_probe "$tag" 1 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode builtin ;;
      d4-legacy-capture)     run_probe "$tag" 1 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode legacy ;;
      d5-all-nocapture)      run_probe "$tag" 0 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode all ;;
      13-transparent-firstframe) run_probe "$tag" 0 -M3CPark transparent -M3CParkWhen firstframe -M3COpenDelay 1.0 ;;
      *) echo "unknown probe tag $tag" ;;
    esac
  done
else
  for tag in d1-all-capture d2-first-capture d3-builtin-capture d4-legacy-capture d5-all-nocapture 13-transparent-firstframe; do
    case "$tag" in
      d1-all-capture)        run_probe "$tag" 1 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode all ;;
      d2-first-capture)      run_probe "$tag" 1 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode first ;;
      d3-builtin-capture)    run_probe "$tag" 1 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode builtin ;;
      d4-legacy-capture)     run_probe "$tag" 1 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode legacy ;;
      d5-all-nocapture)      run_probe "$tag" 0 -M3CPark none -M3COpenDelay 1.0 -M3CDrawablesMode all ;;
      13-transparent-firstframe) run_probe "$tag" 0 -M3CPark transparent -M3CParkWhen firstframe -M3COpenDelay 1.0 ;;
    esac
  done
fi
echo "done"
