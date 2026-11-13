#!/bin/bash
# Push a StikDebug script into the app's Documents/scripts directory.
# Usage: DEVICE=<udid> ./scripts/push_jit_script.sh [script] [destination-name]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)

SCRIPT=${1:-runtime/jit/amethyst.js}
NAME=${2:-$(basename "$SCRIPT")}
: "${DEVICE:?set DEVICE to the device UDID}"
STIKDEBUG_BUNDLE_ID=${STIKDEBUG_BUNDLE_ID:-com.stik.stikdebug.$VRMC_TEAM_ID}

[ -f "$SCRIPT" ] || { echo "script not found: $SCRIPT" >&2; exit 1; }
xcrun devicectl device copy to \
  --device "$DEVICE" \
  --domain-type appDataContainer \
  --domain-identifier "$STIKDEBUG_BUNDLE_ID" \
  --source "$SCRIPT" \
  --destination "Documents/scripts/$NAME"
echo "[jit] pushed $SCRIPT -> $NAME"
