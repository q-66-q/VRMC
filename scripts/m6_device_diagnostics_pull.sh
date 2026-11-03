#!/bin/bash
# M6 read-only device diagnostics pull: copy the app's local logs/status/VRMC config out of the
# installed app data container for offline review. Does NOT launch the game or require unlock.
# Usage: scripts/m6_device_diagnostics_pull.sh [OUT_DIR]
set -euo pipefail
DEVICE="${DEVICE_ID:-${VRMC_DEVICE_UDID:-}}"
BUNDLE="${BUNDLE_ID:-dev.vrmc.vrmc}"
OUT="${1:-/tmp/vrmc-device-diag-$(date +%s)}"
mkdir -p "$OUT"
FILES=(
  "Documents/vrmc-shell.log" "Documents/vrmc-shell.prev.log"
  "Documents/vrmc-compositor.log" "Documents/vrmc-compositor.prev.log"
  "Documents/vrmc-thermal.log" "Documents/vrmc-thermal-state.txt"
  "Documents/vrmc-heartbeat.txt" "Documents/vrmc-shutdown.log"
  "Documents/vrmc-command-result.txt" "Documents/vrmc-vignette.flag"
  "Documents/latestlog.txt" "Documents/latestlog.old.txt"
  "Documents/vrmc-acceptance-checklist.json" "Documents/vrmc-acceptance-summary.md"
  "Documents/instances/default/vrmc-hand-calibration.txt"
  "Documents/vrmc-gaze.flag" "Documents/vrmc-open-on-launch.flag"
  "Documents/instances/default/vrmc-status.json"
  "Documents/instances/default/vrmc-runtime.properties"
  "Documents/instances/default/vrmc-input-tune.properties"
  "Documents/instances/default/vrmc-command.txt"
  "Documents/instances/default/vrmc-shutdown.log"
  "Documents/instances/default/logs/latest.log"
)
pulled=0; missing=0
for f in "${FILES[@]}"; do
  name=$(echo "$f" | tr '/' '_')
  if xcrun devicectl device copy from --device "$DEVICE" \
       --domain-type appDataContainer --domain-identifier "$BUNDLE" \
       --source "$f" --destination "$OUT/$name" >/dev/null 2>&1; then
    pulled=$((pulled + 1))
  else
    missing=$((missing + 1))
  fi
done
echo "[device-diagnostics] device=$DEVICE out=$OUT pulled=$pulled missing=$missing"
for f in "$OUT"/*; do
  [ -f "$f" ] || continue
  echo "[device-diagnostics]   $(basename "$f") bytes=$(stat -f%z "$f") modified=$(stat -f%Sm -t '%Y-%m-%dT%H:%M:%S%z' "$f")"
done
shasum -a 256 "$OUT"/* > "$OUT/SHA256SUMS.txt" 2>/dev/null || true
echo "[device-diagnostics] wrote $OUT/SHA256SUMS.txt"
