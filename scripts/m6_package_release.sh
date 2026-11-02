#!/bin/bash
# M6 release packaging (host-only): package the signed app + provider jar + legal/docs + manifest.
#
# This is a DEVELOPMENT/sideload package, not an App Store submission. It refuses to run on a dirty
# tree unless ALLOW_DIRTY=1 (then the manifest is marked as dirty and cannot be a release artifact).
#
# Usage:
#   scripts/m6_package_release.sh [--app PATH] [--provider PATH] [--out PATH]
# Env:
#   ALLOW_DIRTY=1  permit packaging a dirty tree (development only)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${APP_BUNDLE:-/tmp/VRMC-native-ring.app}"
PROVIDER="${PROVIDER_JAR:-/tmp/vrmc-current/vrmc-provider.jar}"
OUT="${OUT:-/tmp/VRMC-dev-release.zip}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "[release-package] unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT"
if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-0}" != "1" ]; then
  echo "[release-package] ERROR: working tree is dirty; commit first or set ALLOW_DIRTY=1 for a dev package" >&2
  git status --porcelain | head -20 >&2
  exit 3
fi
[ -d "$APP" ] || { echo "[release-package] ERROR: app bundle missing: $APP" >&2; exit 4; }
[ -f "$PROVIDER" ] || { echo "[release-package] ERROR: provider jar missing: $PROVIDER" >&2; exit 5; }
STAGE="$(mktemp -d /tmp/vrmc-release.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/payload"
echo "[release-package] staging app + provider + legal/docs"
ditto "$APP" "$STAGE/payload/$(basename "$APP")"
cp "$PROVIDER" "$STAGE/payload/vrmc-provider.jar"
for f in LICENSE provider/LICENSE THIRD_PARTY_NOTICES.md PRIVACY.md README.md versions.env; do
  mkdir -p "$STAGE/payload/$(dirname "$f")"
  cp "$f" "$STAGE/payload/$f"
done
APP_BUNDLE="$APP" PROVIDER_JAR="$PROVIDER" scripts/m6_release_manifest.sh "$STAGE/payload/release-manifest.txt"
{
  echo "VRMC development sideload package"
  echo "generated: $(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "source commit: $(git rev-parse HEAD)"
  echo "NOT an App Store distribution and NOT a final release sign-off."
  echo
  echo "Contents:"
  echo "  payload/$(basename "$APP")  signed visionOS app (development profile)"
  echo "  payload/vrmc-provider.jar LGPL-3.0 companion provider"
  echo "  payload/release-manifest.txt pins/hashes/licensing/matrix"
  echo "  payload/LICENSE, provider/LICENSE, THIRD_PARTY_NOTICES.md, PRIVACY.md, README.md, versions.env"
  echo
  echo "Minecraft, Vivecraft and other user-installed components are NOT included."
  echo "Install: follow docs/mvp/DEVICE_STACK.md / README; the app must be re-signed for the target device/profile."
  echo "Evidence/acceptance: see VERIFY.md; device gates are NOT satisfied by this package."
} > "$STAGE/payload/INSTALL.txt"
rm -f "$OUT"
( cd "$STAGE/payload" && zip -q -r "$OUT" . )
SHA=$(shasum -a 256 "$OUT" | awk '{print $1}')
SIZE=$(stat -f%z "$OUT")
echo "[release-package] wrote $OUT bytes=$SIZE sha256=$SHA"
echo "[release-package] NOTE: development package only; final release requires clean manifest + AC/K device evidence"
