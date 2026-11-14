#!/bin/bash
# Install an .app on the paired device (optionally replacing an existing app).
# Usage (one line): DEVICE=<udid> scripts/install_device.sh /path/App.app [bundle-id-to-uninstall]
# Environment: DEVICE (default $VRMC_DEVICE_UDID from scripts/local.env), DRY_RUN=1 to print the commands instead of running them.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)
APP=${1:?usage: install_device.sh <App.app> [bundle-id-to-uninstall]}
UNINSTALL_BUNDLE_ID=${2:-}
DEVICE="${DEVICE:-$VRMC_DEVICE_UDID}"
: "${DEVICE:?set DEVICE or VRMC_DEVICE_UDID (scripts/local.env) to the device UDID}"

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "[install] dry-run: xcrun devicectl device install app --device $DEVICE $APP"
  [ -n "$UNINSTALL_BUNDLE_ID" ] && echo "[install] dry-run: uninstall $UNINSTALL_BUNDLE_ID first"
  exit 0
fi
for i in 1 2 3; do
  if [ -n "$UNINSTALL_BUNDLE_ID" ]; then
    xcrun devicectl device uninstall app --device "$DEVICE" "$UNINSTALL_BUNDLE_ID" >/dev/null 2>&1 || true
    sleep 2
  fi
  if xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -qE "App installed|bundleIdentifier"; then
    echo "[install] ok: $APP"
    exit 0
  fi
  echo "[install] attempt $i failed; retrying" >&2
  sleep 8
done
echo "[install] failed after 3 attempts" >&2
exit 1
