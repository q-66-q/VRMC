#!/bin/bash
# Collect M1 device evidence into a directory:
#  - Amethyst latestlog.txt
#  - system crash logs (newest .ips)
#  - StikDebug idevice_log.txt
# Usage: DEVICE=<udid> OUTDIR=/tmp/vrmc-logs ./scripts/capture_device_logs.sh
set -euo pipefail
: "${DEVICE:?set DEVICE to the device UDID}"
OUTDIR=${OUTDIR:-/tmp/vrmc-device-logs}
AMETHYST_BUNDLE_ID=${AMETHYST_BUNDLE_ID:-dev.vrmc.amethyst}
STIKDEBUG_BUNDLE_ID=${STIKDEBUG_BUNDLE_ID:-com.stik.stikdebug.${VRMC_TEAM_ID:-}}
mkdir -p "$OUTDIR"

xcrun devicectl device copy from --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$AMETHYST_BUNDLE_ID" \
  --source Documents/latestlog.txt --destination "$OUTDIR/latestlog.txt" >/dev/null 2>&1 \
  || echo "[logs] no Amethyst latestlog yet"
xcrun devicectl device copy from --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$STIKDEBUG_BUNDLE_ID" \
  --source Documents/idevice_log.txt --destination "$OUTDIR/idevice_log.txt" >/dev/null 2>&1 \
  || echo "[logs] no StikDebug log yet"
xcrun devicectl device copy from --device "$DEVICE" \
  --domain-type systemCrashLogs --source . --destination "$OUTDIR/systemCrashLogs" >/dev/null 2>&1 \
  || echo "[logs] no system crash logs"
echo "[logs] collected into $OUTDIR"
