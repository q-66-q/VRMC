#!/bin/bash
# Re-sign the staged M8 device candidate with a fresh provisioning profile.
#
# Development provisioning profiles expire (free/team profiles in days). When that happens the app can
# no longer install/launch on D1; this wrapper re-runs the normal staging path against the existing
# app's own framework + bridge with the newest matching profile (or PROFILE=...), verifies the result,
# and with --update replaces the staged candidate and refreshes the durable package + manifest hashes.
#
# Prerequisite for a NEW profile: Xcode must be signed into the Apple ID account (Xcode > Settings >
# Accounts) and the profile must have been refreshed (e.g. open a project with bundle id dev.vrmc.vrmc
# and let automatic signing update, or use scripts/m8_renew_profile.sh). This script cannot talk to
# Apple by itself.
#
# Usage:
#   scripts/m8_resign_candidate.sh                 # re-sign to /tmp/VRMC-native-m8-resigned.app
#   scripts/m8_resign_candidate.sh --update        # replace the candidate + manifest + package
#   PROFILE=/path/to/new.mobileprovision scripts/m8_resign_candidate.sh --update
#
# Env: APP (staged app), OUT_APP (default /tmp/VRMC-native-m8-resigned.app), PROFILE, IDENTITY.
# Exit: 0 re-signed (and updated) / 2 usage or validation error.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${APP:-/tmp/VRMC-native-m8.app}"
OUT_APP="${OUT_APP:-/tmp/VRMC-native-m8-resigned.app}"
UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=1 ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "[m8-resign] ERROR: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done
say() { echo "[m8-resign] $*"; }
die() { echo "[m8-resign] ERROR: $*" >&2; exit 2; }

[ -d "$APP" ] || die "staged app not found: $APP"
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || die "source app fails codesign verify: $APP"
FW_SRC="$APP/Frameworks/VRMCShell.framework/VRMCShell"
BRIDGE_SRC="$APP/Frameworks/libvrmc_bridge.dylib"
[ -f "$FW_SRC" ] || die "source app has no VRMCShell framework"

TMP="$(mktemp -d /tmp/vrmc-resign.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cp -R "$APP/Frameworks/VRMCShell.framework" "$TMP/VRMCShell.framework"
cp "$BRIDGE_SRC" "$TMP/libvrmc_bridge.dylib" 2>/dev/null || true
chmod 755 "$TMP/libvrmc_bridge.dylib" 2>/dev/null || true

[ -n "${PROFILE:-}" ] && export PROFILE
say "re-signing $APP -> $OUT_APP"
# stage_native_app.sh reads SRC_APP/DEST_APP/PROFILE/IDENTITY from the environment.
SRC_APP="$APP" DEST_APP="$OUT_APP" "$ROOT/scripts/stage_native_app.sh" \
  "$TMP/VRMCShell.framework" "$TMP/libvrmc_bridge.dylib" > "$TMP/stage.log" 2>&1
RC=$?
if [ "$RC" != "0" ]; then
  tail -30 "$TMP/stage.log" >&2
  die "stage_native_app.sh failed (see above)"
fi
if [ "$RC" != "0" ]; then
  tail -30 "$TMP/stage2.log" >&2
  die "stage_native_app.sh failed (see above)"
fi
say "staged: $OUT_APP"
codesign --verify --deep --strict "$OUT_APP" >/dev/null 2>&1 || die "re-signed app fails codesign verify"
PROFILE_INFO=$("$ROOT/scripts/profile_expiry.sh" "$OUT_APP" --warn-days 7 2>&1) || {
  echo "$PROFILE_INFO" >&2; die "re-signed app has an expired/unreadable profile"
}
say "$PROFILE_INFO"
NEW_APP_TREE=$("$ROOT/scripts/app_tree_sha256.sh" "$OUT_APP" 2>/dev/null || true)
NEW_FW=$(shasum -a 256 "$OUT_APP/Frameworks/VRMCShell.framework/VRMCShell" | awk '{print $1}')
NEW_BRIDGE=$(shasum -a 256 "$OUT_APP/Frameworks/libvrmc_bridge.dylib" | awk '{print $1}')
say "app tree sha256: $NEW_APP_TREE"
say "framework sha256: $NEW_FW"
say "bridge sha256:   $NEW_BRIDGE"

if [ "$UPDATE" = "1" ]; then
  MANIFEST="$ROOT/export/m8-device-candidate.txt"
  [ -f "$MANIFEST" ] || die "missing manifest: $MANIFEST"
  rm -rf "$APP"
  ditto "$OUT_APP" "$APP" || die "could not replace staged app"
  python3 - "$MANIFEST" "$NEW_APP_TREE" "$NEW_FW" "$NEW_BRIDGE" <<'PY'
import sys
path, app_tree, fw, bridge = sys.argv[1:5]
lines = open(path).read().split(chr(10))
out = []
for line in lines:
    if line.startswith("app_tree_sha256="):
        line = "app_tree_sha256=" + app_tree
    elif line.startswith("framework_sha256="):
        line = "framework_sha256=" + fw
    elif line.startswith("bridge_sha256="):
        line = "bridge_sha256=" + bridge
    out.append(line)
open(path, "w").write(chr(10).join(out))
print("manifest updated")
PY
  say "staged candidate replaced and manifest hashes updated"
  "$ROOT/scripts/m8_device_package.sh" --replace --zip \
    && say "durable package rebuilt with the re-signed candidate" \
    || die "package rebuild failed"
fi
say "DONE: $OUT_APP"
