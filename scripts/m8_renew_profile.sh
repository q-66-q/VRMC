#!/bin/bash
# Refresh the M8 development provisioning profile for dev.vrmc.vrmc.
#
# Development profiles expire (Xcode team/free profiles: days). The signed M8 candidate cannot
# install/launch on D1 after the embedded profile expires. Xcode can only refresh it while signed into
# the Apple ID account (Xcode > Settings > Accounts), so this script builds a throw-away visionOS app
# with the same bundle id using automatic signing and -allowProvisioningUpdates; Xcode updates the
# team profile in its profile cache. Then re-sign the candidate:
#
#   scripts/m8_renew_profile.sh && scripts/m8_resign_candidate.sh --update
#
# Usage: scripts/m8_renew_profile.sh [--keep]
# Exit: 0 a matching profile now exists (path printed) / 2 usage / 3 Xcode could not provision
#       (usually: not signed into an Apple ID account, or no network to the developer portal).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="${BUNDLE_ID:-dev.vrmc.vrmc}"
TEAM="${TEAM:-$VRMC_TEAM_ID}"
DIR="/tmp/vrmc-profile-renew"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1
say() { echo "[m8-renew] $*"; }
die() { echo "[m8-renew] ERROR: $*" >&2; exit 2; }
command -v xcodegen >/dev/null 2>&1 || die "xcodegen is required (brew install xcodegen)"
[ -n "$TEAM" ] || die "TEAM is empty"

rm -rf "$DIR"; mkdir -p "$DIR/Sources"
cat > "$DIR/project.yml" <<EOF
name: ProfileRenew
options:
  bundleIdPrefix: dev.vrmc
  deploymentTarget:
    visionOS: "27.0"
settings:
  base:
    DEVELOPMENT_TEAM: $TEAM
    CODE_SIGN_STYLE: Automatic
    PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE_ID
    TARGETED_DEVICE_FAMILY: "7"
    SWIFT_VERSION: "5.9"
targets:
  ProfileRenew:
    type: application
    platform: visionOS
    sources:
      - Sources
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_IDENTITY: "Apple Development"
EOF
cat > "$DIR/Sources/App.swift" <<EOF
import SwiftUI

@main
struct ProfileRenewApp: App {
    var body: some Scene {
        WindowGroup { Text("profile renew") }
    }
}
EOF
say "building a throw-away signed app for $BUNDLE_ID (automatic signing) ..."
if ! ( cd "$DIR" && xcodegen generate && xcodebuild -project ProfileRenew.xcodeproj -scheme ProfileRenew \
        -configuration Debug -destination 'generic/platform=visionOS' -allowProvisioningUpdates \
        -derivedDataPath "$DIR/dd" build ) > "$DIR/build.log" 2>&1; then
  tail -25 "$DIR/build.log" >&2
  die "Xcode could not provision $BUNDLE_ID - sign in via Xcode > Settings > Accounts (or check the developer portal network access), then retry"
fi
EMBEDDED="$DIR/dd/Build/Products/Debug-xros/ProfileRenew.app/embedded.mobileprovision"
[ -f "$EMBEDDED" ] || die "Xcode build succeeded but produced no embedded profile (unexpected)"
cp "$EMBEDDED" "$DIR/fresh.mobileprovision"
say "fresh profile: $DIR/fresh.mobileprovision"
FRESH_INFO=$("$ROOT/scripts/profile_expiry.sh" "$DIR/fresh.mobileprovision" --warn-days 7) || die "the refreshed profile is expired"
say "$FRESH_INFO"
FRESH_DAYS=$(printf '%s' "$FRESH_INFO" | sed -n 's/.*days_left=\([0-9.]*\).*/\1/p')
APP="${APP:-/tmp/VRMC-native-m8.app}"
if [ -d "$APP" ] && [ -x "$ROOT/scripts/profile_expiry.sh" ]; then
  CURRENT_INFO=$("$ROOT/scripts/profile_expiry.sh" "$APP" --warn-days 7 2>/dev/null || true)
  CURRENT_DAYS=$(printf '%s' "$CURRENT_INFO" | sed -n 's/.*days_left=\([0-9.]*\).*/\1/p')
  if [ -n "$CURRENT_DAYS" ] && [ -n "$FRESH_DAYS" ] && \
     python3 -c "import sys; sys.exit(0 if float('$FRESH_DAYS') <= float('$CURRENT_DAYS') + 0.05 else 1)"; then
    echo "[m8-renew] ERROR: Xcode reused the existing profile instead of renewing it (same expiry)." >&2
    echo "[m8-renew]        Sign in via Xcode > Settings > Accounts, then retry (renewal needs the Apple ID account)." >&2
    echo "[m8-renew]        The embedded profile expires in $CURRENT_DAYS day(s); the D1 session must happen before that or after a successful renewal." >&2
    exit 3
  fi
fi
say "now re-sign the candidate: PROFILE=$DIR/fresh.mobileprovision scripts/m8_resign_candidate.sh --update"
if [ "$KEEP" = "0" ]; then :; fi
exit 0
