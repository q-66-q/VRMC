#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="--simulator"
SIM_NAME="${VRMC_SIM_NAME:-VRMC-VP}"
CLEAN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --simulator) MODE="--simulator" ;;
    --device) MODE="--device" ;;
    --clean) CLEAN=1 ;;
    --name) SIM_NAME="$2"; shift ;;
    *) echo "usage: $0 [--simulator|--device] [--clean] [--name SIM]" >&2; exit 2 ;;
  esac
  shift
done

command -v xcodegen >/dev/null || { echo "xcodegen is required" >&2; exit 1; }
(cd client && xcodegen generate >/dev/null)

DERIVED="$ROOT/build/client"
if [[ "$CLEAN" == "1" ]]; then rm -rf "$DERIVED"; fi

if [[ "$MODE" == "--simulator" ]]; then
  DEST="platform=visionOS Simulator,name=$SIM_NAME"
else
  DEST="generic/platform=visionOS"
fi

xcodebuild -project client/VRMC.xcodeproj -scheme VRMC -configuration Debug \
  -destination "$DEST" -derivedDataPath "$DERIVED" build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

APP="$DERIVED/Build/Products/Debug-xrsimulator/VRMC.app"
[[ -d "$APP" ]] || APP="$DERIVED/Build/Products/Debug-xros/VRMC.app"
echo "APP=$APP"
