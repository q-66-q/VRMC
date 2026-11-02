#!/bin/bash
# Build/install/launch the M3b reprojection probe on the booted visionOS simulator and pull its
# artefacts into runtime/probes/m3b-reproj/results/. Simulator-only code/convention evidence.
set -euo pipefail
UDID="${1:-F025E133-019D-4811-944F-F3C8226E14CB}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED=/tmp/m3b-build
APP="$DERIVED/Build/Products/Debug-xrsimulator/M3BProbe.app"

cd "$HERE"
xcodegen generate
xcodebuild -project M3BProbe.xcodeproj -scheme M3BProbe -configuration Debug \
  -destination "platform=visionOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build

xcrun simctl terminate "$UDID" dev.vrmc.m3b 2>/dev/null || true
xcrun simctl uninstall "$UDID" dev.vrmc.m3b 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" dev.vrmc.m3b

CONTAINER=$(xcrun simctl get_app_container "$UDID" dev.vrmc.m3b data)
echo "waiting for probe run to finish (m3b-done.txt)…"
for _ in $(seq -w 1 120); do
  [ -f "$CONTAINER/Documents/m3b-done.txt" ] && break
  sleep 1
done
echo "done: $(cat "$CONTAINER/Documents/m3b-done.txt" 2>/dev/null || echo MISSING)"
mkdir -p results
cp "$CONTAINER/Documents/m3b.log" results/m3b.log
cp "$CONTAINER/Documents/results/"*.png results/
cp "$CONTAINER/Documents/results/summary.txt" results/summary.txt
echo "artefacts in $HERE/results"
