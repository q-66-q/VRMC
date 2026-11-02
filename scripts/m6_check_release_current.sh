#!/bin/bash
# M6 release-gate helper: prove a package's embedded manifest pins the CURRENT local app/provider builds.
# Prevents shipping a self-consistent but stale package after rebuilding/staging.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP="${1:?usage: m6_check_release_current.sh ZIP [APP_BUNDLE] [PROVIDER_JAR]}"
APP="${2:-${RELEASE_APP_BUNDLE:-}}"
PROV="${3:-${RELEASE_PROVIDER_JAR:-/tmp/vrmc-current/vrmc-provider.jar}}"
[ -f "$ZIP" ] || { echo "[release-current] ERROR: zip missing: $ZIP" >&2; exit 3; }
TMP="$(mktemp -d /tmp/vrmc-release-current.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$ZIP" release-manifest.txt -d "$TMP"
MAN="$TMP/release-manifest.txt"
val() { sed -n "s/^$1=//p" "$MAN" | head -1; }
fail=0
if [ -n "$APP" ]; then
  if [ -d "$APP" ]; then
    actual=$("$ROOT/scripts/app_tree_sha256.sh" "$APP")
    expected=$(val app_bundle_sha256)
    echo "[release-current] app actual=$actual manifest=$expected"
    [ "$actual" = "$expected" ] || { echo "[release-current] FAIL app differs from package" >&2; fail=1; }
  else
    echo "[release-current] FAIL app bundle missing: $APP" >&2; fail=1
  fi
else
  echo "[release-current] SKIP app check (set RELEASE_APP_BUNDLE/arg2 to enforce)"
fi
if [ -n "$PROV" ]; then
  if [ -f "$PROV" ]; then
    actual=$(shasum -a 256 "$PROV" | awk '{print $1}')
    expected=$(val provider_jar_sha256)
    echo "[release-current] provider actual=$actual manifest=$expected"
    [ "$actual" = "$expected" ] || { echo "[release-current] FAIL provider differs from package" >&2; fail=1; }
  else
    echo "[release-current] FAIL provider jar missing: $PROV" >&2; fail=1
  fi
fi
if [ "$fail" != "0" ]; then echo "[release-current] RESULT: FAIL (stale package)" >&2; exit 1; fi
echo "[release-current] RESULT: PASS (package pins current local app/provider)"
