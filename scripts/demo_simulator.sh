#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SIM_NAME="${VRMC_SIM_NAME:-VRMC-VP}"
FIXTURE="tools/mock_host/fixtures/stereo_test.h264"
if [[ ! -f "$FIXTURE" ]]; then
  mkdir -p "$(dirname "$FIXTURE")"
  ffmpeg -hide_banner -loglevel error \
    -f lavfi -i 'testsrc2=size=640x720:rate=30:duration=4' \
    -f lavfi -i 'testsrc2=size=640x720:rate=30:duration=4' \
    -filter_complex '[1:v]hue=h=120[r];[0:v][r]hstack=inputs=2' \
    -t 4 -c:v libx264 -preset ultrafast -tune zerolatency -g 30 \
    -x264-params aud=1 -pix_fmt yuv420p -f h264 "$FIXTURE" -y
fi

./scripts/build_client.sh --simulator --name "$SIM_NAME" >/dev/null
APP="$ROOT/build/client/Build/Products/Debug-xrsimulator/VRMC.app"
[[ -d "$APP" ]] || { echo "app not found at $APP" >&2; exit 1; }
xcrun simctl bootstatus "$SIM_NAME" -b >/dev/null

mkdir -p artifacts/demo
LOG="artifacts/demo/mock_host.log"
rm -f "$LOG"
python3 tools/mock_host/mock_host.py --host 127.0.0.1 --fps 30 --log-file artifacts/demo/input.jsonl >"$LOG" 2>&1 &
MOCK_PID=$!
trap 'kill "$MOCK_PID" 2>/dev/null || true' EXIT
sleep 1

xcrun simctl install "$SIM_NAME" "$APP"
xcrun simctl terminate "$SIM_NAME" dev.vrmc.app 2>/dev/null || true
xcrun simctl launch "$SIM_NAME" dev.vrmc.app -VRMCDemoMode >/dev/null
sleep 8
xcrun simctl io "$SIM_NAME" screenshot artifacts/demo/simulator.png >/dev/null 2>&1 || true
echo "Simulator demo running (mock host PID $MOCK_PID)."
echo "Screenshot: artifacts/demo/simulator.png; logs: $LOG"
echo "Press Ctrl-C to stop the mock host."
wait "$MOCK_PID"
