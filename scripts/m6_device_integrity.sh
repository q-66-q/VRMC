#!/bin/bash
# M6 device integrity check (read-only): confirm the provider jar in the installed app's data container
# matches the locally built jar, and that the app bundle is installed. Does NOT launch the game or
# require the device to be unlocked. Behavior/acceptance gates remain separate.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE_ID:-$VRMC_DEVICE_UDID}"
BUNDLE="${BUNDLE_ID:-dev.vrmc.vrmc}"
LOCAL="${PROVIDER_JAR:-/tmp/vrmc-current/vrmc-provider.jar}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --local) LOCAL="$2"; shift 2 ;;
    *) echo "[device-integrity] unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -f "$LOCAL" ] || { echo "[device-integrity] local provider jar missing: $LOCAL" >&2; exit 3; }
TMP="$(mktemp -d /tmp/vrmc-device-int.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
echo "[device-integrity] device=$DEVICE bundle=$BUNDLE"
echo "[device-integrity] installed apps:"
xcrun devicectl device info apps --device "$DEVICE" 2>/dev/null | grep -E "VRMC|Bundle Identifier|Name" | head -5 || true
echo "[device-integrity] copying provider jar out of the app data container (read-only)"
xcrun devicectl device copy from --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "Documents/instances/default/mods/vrmc-provider.jar" \
  --destination "$TMP/vrmc-provider.jar" >/dev/null
LOCAL_SHA=$(shasum -a 256 "$LOCAL" | awk '{print $1}')
DEVICE_SHA=$(shasum -a 256 "$TMP/vrmc-provider.jar" | awk '{print $1}')
echo "[device-integrity] local  sha256=$LOCAL_SHA bytes=$(stat -f%z "$LOCAL")"
echo "[device-integrity] device sha256=$DEVICE_SHA bytes=$(stat -f%z "$TMP/vrmc-provider.jar")"
if [ "$LOCAL_SHA" = "$DEVICE_SHA" ]; then
  echo "[device-integrity] RESULT: PASS (device provider jar matches local build)"
  exit 0
fi
echo "[device-integrity] RESULT: FAIL (provider jar mismatch; push again)" >&2
exit 4
