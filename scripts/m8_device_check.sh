#!/bin/bash
# M8 device verification: pull the D1 logs that decide A6-A9 (foveation active, 4K-class display path,
# provider eye targets, measured 90/120 Hz cadence, pacing) and classify them.
#
# Usage:
#   DEVICE=<udid> scripts/m8_device_check.sh                 # pull from D1 into OUTDIR + analyse
#   scripts/m8_device_check.sh --from <dir>                  # analyse an existing pull / simulator case
#
# Options/env: DEVICE (default $VRMC_DEVICE_UDID), BUNDLE (default dev.vrmc.vrmc),
#              OUTDIR (default /tmp/vrmc-m8-device).
# Exit: 0 = PASS (A6-A9), 2 = PARTIAL (M8 running, a row not satisfied e.g. 90 Hz/no foveation),
#       3 = NOT RUN (no M8 evidence / old build / logs not pulled), 4 = FAIL (hard regression),
#       5 = device pull failed (device unavailable).
#
# Device procedure and what counts as evidence: docs/mvp/M8_DEVICE_RUN.md (M8_PLAN.md §5/§7).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-$VRMC_DEVICE_UDID}"
BUNDLE="${BUNDLE:-dev.vrmc.vrmc}"
OUTDIR="${OUTDIR:-/tmp/vrmc-m8-device}"
FROM=""
if [ "${1:-}" = "--from" ]; then
  FROM="${2:?--from needs a directory}"
  OUTDIR="$FROM"
fi

pull() { # pull <relative-source> <local-name>
  local src="$1" dst="$2"
  xcrun devicectl device copy from --device "$DEVICE" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "$src" --destination "$OUTDIR/$dst" >/dev/null 2>&1
}

if [ -z "$FROM" ]; then
  mkdir -p "$OUTDIR"
  echo "[m8-device] pulling session logs from $DEVICE ($BUNDLE) into $OUTDIR"
  pull "Documents/vrmc-compositor.log" "vrmc-compositor.log" || true
  pull "Documents/vrmc-compositor.prev.log" "vrmc-compositor.prev.log" || true
  pull "Documents/vrmc-shell.log" "vrmc-shell.log" || true
  pull "Documents/vrmc-shell.prev.log" "vrmc-shell.prev.log" || true
  pull "Documents/instances/default/latestlog.txt" "latestlog.txt" || true
  pull "Documents/instances/default/vrmc-status.json" "vrmc-status.json" || true
  pull "Documents/instances/default/vrmc-m8-trace.csv" "vrmc-m8-trace.csv" || true
  pull "Documents/vrmc-heartbeat.txt" "vrmc-heartbeat.txt" || true
  pulled=$(find "$OUTDIR" -maxdepth 1 -type f ! -path '*/session/*' 2>/dev/null | wc -l | tr -d ' ')
  echo "[m8-device] pulled $pulled file(s)"
  if [ "${pulled:-0}" = "0" ]; then
    echo "[m8-device] RESULT: NOT RUN (no files pulled: device locked/unavailable or wrong bundle)"
    exit 5
  fi
fi

if [ ! -d "$OUTDIR" ]; then
  echo "[m8-device] RESULT: NOT RUN (directory missing: $OUTDIR)"
  exit 3
fi

python3 "$ROOT/scripts/m8_device_check.py" "$OUTDIR"
rc=$?
echo "[m8-device] logs in $OUTDIR"
exit $rc
