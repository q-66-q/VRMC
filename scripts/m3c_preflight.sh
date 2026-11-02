#!/bin/bash
# M3c pre-flight: verify what is actually installed on the device BEFORE the operator run.
#
# Reports: device lock state, installed VRMC app bundle URL, provider jar hash (round-trip from the
# device), Documents + game-dir flags, and optional expectations.
#
# Usage:
#   DEVICE=<udid> scripts/m3c_preflight.sh [--expect-app v14] [--expect-provider-sha <sha256>]
# Exit: 0 = expectations satisfied; 2 = mismatch/missing; 3 = device not reachable/unlocked.
set -uo pipefail
DEVICE="${DEVICE:-${VRMC_DEVICE_UDID:-}}"
EXPECT_APP=""
EXPECT_SHA=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --expect-app) EXPECT_APP="${2:-}"; shift 2 ;;
    --expect-provider-sha) EXPECT_SHA="${2:-}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
fail=0
echo "== device =="
lock=$(xcrun devicectl device info lockState --device "$DEVICE" 2>&1 | grep passcodeRequired || true)
echo "  $lock"
case "$lock" in *"passcodeRequired: false"*) ;; *) echo "  WARN: device is locked (install/launch will fail until the operator unlocks it)";; esac

echo "== installed app =="
appurl=$(xcrun devicectl device info apps --device "$DEVICE" --json-output - 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print(next((a.get('url','') for a in d.get('result',{}).get('apps',[]) if a.get('bundleIdentifier')=='dev.vrmc.vrmc'),''))" 2>/dev/null)
echo "  $appurl"
[ -n "$appurl" ] || { echo "  FAIL: VRMC app not installed/listed"; fail=2; }
if [ -n "$EXPECT_APP" ] && ! printf '%s' "$appurl" | grep -q "$EXPECT_APP"; then
  echo "  FAIL: installed app does not match expected '$EXPECT_APP'"; fail=2
fi

echo "== provider jar on device (round-trip sha256) =="
tmp=$(mktemp -d /tmp/vrmc-preflight.XXXXXX)
if xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc --source Documents/instances/default/mods/vrmc-provider.jar --destination "$tmp/vrmc-provider.jar" >/dev/null 2>&1 && [ -f "$tmp/vrmc-provider.jar" ]; then
  sha=$(shasum -a 256 "$tmp/vrmc-provider.jar" | awk '{print $1}')
  echo "  $sha"
  if [ -n "$EXPECT_SHA" ] && [ "$sha" != "$EXPECT_SHA" ]; then
    echo "  FAIL: provider jar sha does not match expected $EXPECT_SHA"; fail=2
  fi
else
  echo "  FAIL: could not pull the provider jar"; fail=2
fi
rm -rf "$tmp"

echo "== Documents flags =="
xcrun devicectl device info files --device "$DEVICE" --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc --subdirectory Documents --no-recurse 2>/dev/null | grep -E 'flag' || echo "  (none)"
echo "== game-dir flags (Documents/instances/default) =="
xcrun devicectl device info files --device "$DEVICE" --domain-type appDataContainer --domain-identifier dev.vrmc.vrmc --subdirectory Documents/instances/default --no-recurse 2>/dev/null | grep -E 'flag' || echo "  (none)"

echo "== expected log check after the run =="
echo "  DEVICE=$DEVICE scripts/m3c_pull_and_check.sh"
if [ "$fail" != "0" ]; then echo "[preflight] RESULT: FAIL ($fail)"; exit "$fail"; fi
echo "[preflight] RESULT: PASS"
