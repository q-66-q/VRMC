#!/bin/bash
# M6 release-package verifier: unpack a development/release zip and prove content integrity.
# Checks required entries, provider_jar_sha256 and path-independent app_bundle_sha256 against the
# embedded release-manifest.txt, and prints the zip sha256/size. No device access.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP="${1:-/tmp/VRMC-dev-release.zip}"
[ -f "$ZIP" ] || { echo "[verify-package] ERROR: zip missing: $ZIP" >&2; exit 3; }
TMP="$(mktemp -d /tmp/vrmc-verify-pkg.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
unzip -q "$ZIP" -d "$TMP"
MAN="$TMP/release-manifest.txt"
[ -f "$MAN" ] || { echo "[verify-package] ERROR: release-manifest.txt missing" >&2; exit 4; }
fail=0
ok() { echo "[verify-package] OK   $*"; }
bad() { echo "[verify-package] FAIL $*"; fail=1; }
val() { sed -n "s/^$1=//p" "$MAN" | head -1; }
for f in LICENSE provider/LICENSE THIRD_PARTY_NOTICES.md PRIVACY.md SOURCE_OFFER.md README.md INSTALL.txt \
         versions.env docs/mvp/M4_CONTROLS.md docs/mvp/M5_ACCEPTANCE.md docs/mvp/M5_DEVICE_RUN.md \
         docs/mvp/M6_ACCEPTANCE.md docs/mvp/M6_PLAN.md; do
  [ -e "$TMP/$f" ] && ok "present: $f" || bad "missing: $f"
done
APP=$(find "$TMP" -maxdepth 1 -type d -name '*.app' | head -1)
[ -n "$APP" ] && ok "app bundle present: $(basename "$APP")" || bad "app bundle missing"
if [ -n "$APP" ]; then
  ACTUAL_APP=$("$ROOT/scripts/app_tree_sha256.sh" "$APP")
  WANT_APP=$(val app_bundle_sha256)
  echo "[verify-package] app bundle sha256 actual=$ACTUAL_APP manifest=$WANT_APP"
  [ "$ACTUAL_APP" = "$WANT_APP" ] && ok "app tree hash matches manifest" || bad "app tree hash mismatch"
fi
PROV="$TMP/vrmc-provider.jar"
if [ -f "$PROV" ]; then
  ACTUAL_PROV=$(shasum -a 256 "$PROV" | awk '{print $1}')
  WANT_PROV=$(val provider_jar_sha256)
  echo "[verify-package] provider sha256 actual=$ACTUAL_PROV manifest=$WANT_PROV"
  [ "$ACTUAL_PROV" = "$WANT_PROV" ] && ok "provider jar hash matches manifest" || bad "provider jar hash mismatch"
else
  bad "vrmc-provider.jar missing"
fi
[ "$(val dirty_tree)" = "no" ] && ok "manifest dirty_tree=no" || bad "manifest dirty_tree=$(val dirty_tree)"
echo "[verify-package] zip bytes=$(stat -f%z "$ZIP") sha256=$(shasum -a 256 "$ZIP" | awk '{print $1}')"
if [ "$fail" != "0" ]; then echo "[verify-package] RESULT: FAIL" >&2; exit 1; fi
echo "[verify-package] RESULT: PASS"
