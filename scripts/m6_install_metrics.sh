#!/bin/bash
# M6 K6 install-size / artifact metrics (host; read-only). Prints app bundle size, signed file count,
# provider jar size/hash, and package size/hash when available. Device install measurement is noted as
# a separate acceptance step (devicectl app info cannot report on-disk size).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${APP_BUNDLE:-/tmp/VRMC-native-pacingjson.app}"
PROVIDER="${PROVIDER_JAR:-/tmp/vrmc-current/vrmc-provider.jar}"
PACKAGE="${PACKAGE_ZIP:-/tmp/VRMC-dev-release.zip}"
OUT="${OUT:-}"
[ -d "$APP" ] || { echo "[install-metrics] ERROR: app bundle missing: $APP" >&2; exit 3; }
[ -f "$PROVIDER" ] || { echo "[install-metrics] ERROR: provider jar missing: $PROVIDER" >&2; exit 4; }
APP_BYTES=$(du -sk "$APP" | awk '{print $1 * 1024}')
APP_FILES=$(find "$APP" -type f | wc -l | tr -d ' ')
MACHO=0
while IFS= read -r -d '' f; do
  if file "$f" 2>/dev/null | grep -q 'Mach-O'; then MACHO=$((MACHO + 1)); fi
done < <(find "$APP" -type f -print0)
PROVIDER_BYTES=$(stat -f%z "$PROVIDER")
PROVIDER_SHA=$(shasum -a 256 "$PROVIDER" | awk '{print $1}')
META=$(mktemp -t vrmc-install-metrics.XXXXXX)
{
  echo "VRMC install metrics (host measurement; device install size still a K6 acceptance step)"
  echo "generated: $(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "app_path=$APP"
  echo "app_bytes=$APP_BYTES"
  echo "app_files=$APP_FILES"
  echo "app_macho_files=$MACHO"
  echo "provider_bytes=$PROVIDER_BYTES"
  echo "provider_sha256=$PROVIDER_SHA"
  if [ -f "$PACKAGE" ]; then
    echo "package_path=$PACKAGE"
    echo "package_bytes=$(stat -f%z "$PACKAGE")"
    echo "package_sha256=$(shasum -a 256 "$PACKAGE" | awk '{print $1}')"
  fi
} > "$META"
if [ -n "$OUT" ]; then cp "$META" "$OUT"; fi
cat "$META"
rm -f "$META"
