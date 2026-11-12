#!/bin/bash
# Stage a fresh device app bundle for the next Vision Pro run (build + sign only; NEVER installs).
#
# Copies the last device bundle, swaps in a freshly built VRMCShell.framework and optionally a
# freshly built libvrmc_bridge.dylib, embeds the visionOS dev provisioning profile, re-signs every
# Mach-O file plus every nested framework bundle plus the app itself, then runs
# 'codesign --verify --deep --strict'. Nothing is written outside /tmp and no device is touched.
#
# Usage:  scripts/stage_native_app.sh <VRMCShell.framework> [libvrmc_bridge.dylib]
#
# Env overrides (all optional):
#   SRC_APP     app bundle to copy              (default /tmp/VRMC-native-v14-auditfix.app)
#   DEST_APP    staged output bundle            (default /tmp/VRMC-native-next.app)
#   IDENTITY    codesigning identity            (default ${VRMC_SIGN_IDENTITY:-})
#   PROFILE     provisioning profile            (default: SRC_APP/embedded.mobileprovision, else the
#                                                newest matching profile under Xcode's profile dir)
#   XCENT       entitlements plist              (default: extracted from SRC_APP's signature, else
#                                                generated with get-task-allow=true for JIT)
#   BUNDLE_ID   expected/forced bundle id       (default dev.vrmc.vrmc)
#   DISPLAY_NAME  set CFBundleDisplayName/CFBundleName (default: leave whatever SRC_APP has)
#   DEVICE      UDID expected in the profile    (default ${VRMC_DEVICE_UDID:-}; '' to skip)
#   ALLOW_PLATFORM_MISMATCH=1   skip the visionOS (platform 11) check on framework/dylib
#   DRY_RUN=1   print the plan, change nothing
#   VRMC_KEEP_JRE=25  optional experimental: prune other bundled java-*-openjdk runtimes from the
#                     staged app (reduces bundle size; device launch behavior NOT yet validated)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW_SRC="${1:-}"
BRIDGE_SRC="${2:-}"
SRC_APP="${SRC_APP:-/tmp/VRMC-native-v14-auditfix.app}"
DEST_APP="${DEST_APP:-/tmp/VRMC-native-next.app}"
IDENTITY="${IDENTITY:-${VRMC_SIGN_IDENTITY:-}}"
BUNDLE_ID="${BUNDLE_ID:-dev.vrmc.vrmc}"
DEVICE="${DEVICE:-${VRMC_DEVICE_UDID:-}}"
ALLOW_PLATFORM_MISMATCH="${ALLOW_PLATFORM_MISMATCH:-0}"
DRY_RUN="${DRY_RUN:-0}"
TMP="$(mktemp -d /tmp/vrmc-stage.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

die() { echo "[stage] ERROR: $*" >&2; exit 1; }
note() { echo "[stage] $*"; }
run() { if [ "$DRY_RUN" = "1" ]; then echo "  DRY-RUN: $*"; else "$@"; fi; }
platform_of() { otool -l "$1" 2>/dev/null | awk "/LC_BUILD_VERSION/{f=1} f&&/platform/{print \$2; exit}"; }
minos_of()    { otool -l "$1" 2>/dev/null | awk "/LC_BUILD_VERSION/{f=1} f&&/minos/{print \$2; exit}"; }

[ -n "$FW_SRC" ] || die "usage: stage_native_app.sh <VRMCShell.framework> [libvrmc_bridge.dylib]"
[ -d "$FW_SRC" ] || die "framework not found: $FW_SRC"
[ -f "$FW_SRC/Info.plist" ] || die "not a framework (no Info.plist): $FW_SRC"
FW_BIN_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$FW_SRC/Info.plist" 2>/dev/null || true)
[ -n "$FW_BIN_NAME" ] || die "framework Info.plist has no CFBundleExecutable: $FW_SRC"
FW_BIN="$FW_SRC/$FW_BIN_NAME"
[ -f "$FW_BIN" ] || die "framework executable not found: $FW_BIN"
FW_DEST_NAME="$(basename "$FW_SRC")"
case "$FW_DEST_NAME" in *.framework) ;; *) die "first argument must be a .framework directory: $FW_SRC" ;; esac
[ -d "$SRC_APP" ] || die "source app bundle not found: $SRC_APP"
[ -f "$SRC_APP/Info.plist" ] || die "source app has no Info.plist: $SRC_APP"
APP_BIN_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$SRC_APP/Info.plist" 2>/dev/null || true)
[ -n "$APP_BIN_NAME" ] || die "source app Info.plist has no CFBundleExecutable"
[ -f "$SRC_APP/$APP_BIN_NAME" ] || die "source app executable missing: $SRC_APP/$APP_BIN_NAME"

# --- visionOS platform checks (dyld refuses non-visionOS images in a visionOS process) ----------
check_platform() { # check_platform <mach-o> <label>
  local path="$1" label="$2" plat mino
  plat=$(platform_of "$path"); mino=$(minos_of "$path")
  if [ "$plat" != "11" ] && [ "$ALLOW_PLATFORM_MISMATCH" != "1" ]; then
    die "$label is not a visionOS binary (LC_BUILD_VERSION platform=$plat, minos=$mino; want 11). dyld will refuse it on device. Set ALLOW_PLATFORM_MISMATCH=1 to override."
  fi
  file "$path" | grep -q "Mach-O 64-bit dynamically linked shared library arm64" \
    || file "$path" | grep -q "Mach-O 64-bit arm64" \
    || die "$label is not an arm64 Mach-O: $(file "$path")"
  note "$label: platform=$plat minos=$mino OK"
}
check_platform "$FW_BIN" "shell framework"
if [ -n "$BRIDGE_SRC" ]; then
  [ -f "$BRIDGE_SRC" ] || die "bridge dylib not found: $BRIDGE_SRC"
  check_platform "$BRIDGE_SRC" "bridge dylib"
  for sym in _vrmc_init _vrmc_shared_eye_textures _vrmc_export_mtl_texture \
             _Java_dev_vrmc_provider_bridge_VrmcBridge_nativeInit; do
    nm -gU "$BRIDGE_SRC" 2>/dev/null | awk "{print \$3}" | grep -qx "$sym" \
      || die "bridge dylib is missing exported symbol $sym ($BRIDGE_SRC)"
  done
  note "bridge symbols OK"
fi

# --- profile + entitlements --------------------------------------------------------------------
find_profile_for() { # find_profile_for <bundle-id> <team-id> [device-udid]
  local want_id="$1" want_team="$2" want_device="${3:-}" dir f best="" decoded appid team devices
  for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" \
             "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.mobileprovision; do
      [ -f "$f" ] || continue
      decoded="$TMP/profile-candidate.plist"
      security cms -D -i "$f" > "$decoded" 2>/dev/null || continue
      appid=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$decoded" 2>/dev/null || true)
      team=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$decoded" 2>/dev/null || true)
      [ "$appid" = "$want_team.$want_id" ] || continue
      [ "$team" = "$want_team" ] || continue
      if [ -n "$want_device" ]; then
        devices=$(/usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$decoded" 2>/dev/null || true)
        printf '%s\n' "$devices" | grep -q -- "$want_device" || continue
      fi
      best="$f"   # last match wins; Xcode rewrites profiles in place so newest mtime is last
    done
  done
  [ -n "$best" ] && echo "$best"
}
if [ -z "${PROFILE:-}" ]; then
  if [ -f "$SRC_APP/embedded.mobileprovision" ]; then
    PROFILE="$SRC_APP/embedded.mobileprovision"
  else
    PROFILE=$(find_profile_for "$BUNDLE_ID" "${VRMC_TEAM_ID:-}" "$DEVICE" || true)
  fi
fi
[ -n "${PROFILE:-}" ] && [ -f "$PROFILE" ] || die "provisioning profile not found (set PROFILE=...; no matching profile for $BUNDLE_ID in Xcode profile dirs)"
note "using profile: $PROFILE"
cp "$PROFILE" "$TMP/profile.mobileprovision"
security cms -D -i "$TMP/profile.mobileprovision" > "$TMP/profile.plist" 2>/dev/null \
  || die "cannot decode provisioning profile: $PROFILE"
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" "$TMP/profile.plist" 2>/dev/null || true)
PROFILE_EXP=$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$TMP/profile.plist" 2>/dev/null || true)
PROFILE_APPID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$TMP/profile.plist" 2>/dev/null || true)
note "profile: $PROFILE_NAME (expires $PROFILE_EXP, app-id $PROFILE_APPID)"
if [ -n "$DEVICE" ]; then
  if /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$TMP/profile.plist" 2>/dev/null | grep -q "$DEVICE"; then
    note "profile provisions device $DEVICE OK"
  else
    echo "[stage] WARNING: profile does not list device $DEVICE; install will fail (set PROFILE=...)" >&2
  fi
fi
if [ -n "${XCENT:-}" ] && [ -f "${XCENT:-}" ]; then
  note "entitlements: $XCENT (XCENT override)"
else
  XCENT="$TMP/entitlements.plist"
  # ":-" prints the entitlements as an XML plist on stdout (bare "-" prints a human-readable dict).
  if codesign -d --entitlements :- "$SRC_APP" > "$XCENT" 2>/dev/null && [ -s "$XCENT" ]; then
    note "entitlements: extracted from $SRC_APP signature"
  else
    cat > "$XCENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>${VRMC_TEAM_ID:-}.$BUNDLE_ID</string>
  <key>com.apple.developer.team-identifier</key><string>${VRMC_TEAM_ID:-}</string>
  <key>get-task-allow</key><true/>
</dict></plist>
PLIST
    note "entitlements: generated dev entitlements (get-task-allow=true, needed for JIT)"
  fi
fi
if ! /usr/libexec/PlistBuddy -c "Print :get-task-allow" "$XCENT" 2>/dev/null | grep -qi true; then
  /usr/libexec/PlistBuddy -c "Add :get-task-allow bool true" "$XCENT" >/dev/null 2>&1 \
    || die "staged entitlements lack get-task-allow (JIT will not attach); set XCENT explicitly"
  note "added get-task-allow to entitlements (JIT)"
fi

note "source app:  $SRC_APP"
note "staged app:  $DEST_APP"
note "framework:   $FW_SRC -> Frameworks/$FW_DEST_NAME"
[ -n "$BRIDGE_SRC" ] && note "bridge dylib: $BRIDGE_SRC -> Frameworks/libvrmc_bridge.dylib"
note "identity:    $IDENTITY"
if [ "$DRY_RUN" = "1" ]; then note "DRY_RUN=1 - no bundle will be written"; fi

# --- 1. fresh copy of the last device bundle ---------------------------------------------------
run rm -rf "$DEST_APP"
run cp -R "$SRC_APP" "$DEST_APP"

# Optional K6 experiment: prune bundled JREs other than the requested major. The game uses the JRE
# selected by the launcher/installer; this variant must be device-validated before it becomes default.
KEEP_JRE="${VRMC_KEEP_JRE:-}"
if [ -n "$KEEP_JRE" ]; then
  note "pruning bundled java runtimes except java-${KEEP_JRE}-openjdk (experimental; device validation required)"
  for jre in "$DEST_APP"/java_runtimes/java-*-openjdk; do
    [ -d "$jre" ] || continue
    name="$(basename "$jre")"
    case "$name" in
      "java-${KEEP_JRE}-openjdk") ;;
      *) run rm -rf "$jre"; note "  pruned $name" ;;
    esac
  done
fi

# --- 2. swap in the freshly built framework + bridge dylib -------------------------------------
run rm -rf "$DEST_APP/Frameworks/$FW_DEST_NAME"
run cp -R "$FW_SRC" "$DEST_APP/Frameworks/$FW_DEST_NAME"
if [ -n "$BRIDGE_SRC" ]; then
  run cp "$BRIDGE_SRC" "$DEST_APP/Frameworks/libvrmc_bridge.dylib"
  if [ "$DRY_RUN" != "1" ]; then chmod 755 "$DEST_APP/Frameworks/libvrmc_bridge.dylib"; fi
fi
if [ "$DRY_RUN" != "1" ]; then
  CUR_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$DEST_APP/Info.plist" 2>/dev/null || true)
  if [ "$CUR_ID" != "$BUNDLE_ID" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$DEST_APP/Info.plist" \
      || die "could not set CFBundleIdentifier"
    note "bundle id $CUR_ID -> $BUNDLE_ID"
  fi
  if [ -n "${DISPLAY_NAME:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$DEST_APP/Info.plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $DISPLAY_NAME" "$DEST_APP/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" "$DEST_APP/Info.plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleName string $DISPLAY_NAME" "$DEST_APP/Info.plist"
    note "display name -> $DISPLAY_NAME"
  fi
fi
run cp "$PROFILE" "$DEST_APP/embedded.mobileprovision"

# --- 3. re-sign: every Mach-O file, then every nested framework bundle, then the app bundle ----
if [ "$DRY_RUN" = "1" ]; then
  note "would test $(find "$DEST_APP" -type f 2>/dev/null | wc -l | tr -d " ") files for Mach-O signatures, sign $(find "$DEST_APP" -type d -name "*.framework" 2>/dev/null | wc -l | tr -d " ") framework bundles + app bundle"
  note "DRY-RUN: no codesign executed"
  exit 0
fi
note "checking codesigning identity"
security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY" \
  || die "codesigning identity not found in the login keychain: $IDENTITY (open Xcode > Settings > Accounts, or set IDENTITY=...)"
note "signing Mach-O files under $DEST_APP"
N_SIGNED=0
while IFS= read -r f; do
  if file "$f" | grep -q "Mach-O"; then
    codesign --force --sign "$IDENTITY" --timestamp=none "$f" >/dev/null 2>&1 \
      || die "codesign failed for $f"
    N_SIGNED=$((N_SIGNED+1))
  fi
done < <(find "$DEST_APP" -type f)
note "signed $N_SIGNED Mach-O files"

note "signing nested framework bundles"
N_FW=0
while IFS= read -r fw; do
  codesign --force --sign "$IDENTITY" --timestamp=none "$fw" >/dev/null 2>&1 \
    || die "codesign failed for framework bundle $fw"
  N_FW=$((N_FW+1))
done < <(find "$DEST_APP" -type d -name "*.framework" | awk "{ print length(\$0) \" \" \$0 }" | sort -rn | cut -d" " -f2-)
note "signed $N_FW framework bundles"

note "signing app bundle with entitlements + embedded profile"
codesign --force --sign "$IDENTITY" --timestamp=none --entitlements "$XCENT" "$DEST_APP" >/dev/null 2>&1 \
  || die "codesign failed for app bundle $DEST_APP"

# --- 4. verify + report ------------------------------------------------------------------------
VERIFY_LOG="$TMP/verify.log"
if codesign --verify --deep --strict --verbose=2 "$DEST_APP" >"$VERIFY_LOG" 2>&1; then
  note "codesign --verify --deep --strict: PASS"
  tail -3 "$VERIFY_LOG" | sed "s/^/[stage]   /"
else
  echo "[stage] codesign --verify --deep --strict: FAIL" >&2
  cat "$VERIFY_LOG" >&2
  exit 1
fi
if ! codesign --verify --strict --verbose=2 "$DEST_APP/$APP_BIN_NAME" >/dev/null 2>&1; then
  die "app executable does not verify after signing"
fi
if ! codesign -d --entitlements - "$DEST_APP" 2>/dev/null | grep -q "get-task-allow"; then
  echo "[stage] WARNING: staged app signature has no get-task-allow entitlement; JIT will not attach" >&2
fi

note "artifact hashes:"
for f in "$DEST_APP/Frameworks/$FW_DEST_NAME/$FW_BIN_NAME" \
         "$DEST_APP/Frameworks/libvrmc_bridge.dylib" "$DEST_APP/$APP_BIN_NAME"; do
  [ -f "$f" ] && note "  $(shasum -a 256 "$f" | awk "{print \$1}")  ${f#$DEST_APP/}  ($(wc -c < "$f" | tr -d " ") bytes)"
done
note "app bundle: $DEST_APP"
codesign -dv --verbose=2 "$DEST_APP" 2>&1 | grep -E "^(Identifier|Authority|TeamIdentifier|CDHash)=" | sed "s/^/[stage]   /"
note "NOT installed (deliberate): install with: xcrun devicectl device install app --device $DEVICE $DEST_APP"
echo "$DEST_APP"
