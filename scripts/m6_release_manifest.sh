#!/bin/bash
# M6 release manifest: collect the exact build identity and licensing files into one text artifact.
# Host-only; no device needed. Usage:
#   scripts/m6_release_manifest.sh [OUTFILE]
# Env: APP_BUNDLE (default: newest /tmp/VRMC-native-*.app), PROVIDER_JAR (default
#      /tmp/vrmc-provider-build/../vrmc-provider.jar if present), BRIDGE_DYLIB optional.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/export/release-manifest.txt}"
mkdir -p "$(dirname "$OUT")"
cd "$ROOT"
# shellcheck disable=SC1091
. ./versions.env
APP_BUNDLE="${APP_BUNDLE:-$(ls -dt /tmp/VRMC-native-*.app 2>/dev/null | head -1 || true)}"
PROVIDER_JAR="${PROVIDER_JAR:-}"
if [ -z "$PROVIDER_JAR" ]; then
  PROVIDER_JAR="$(ls -t /tmp/vrmc-*/vrmc-provider.jar 2>/dev/null | head -1 || true)"
fi
BRIDGE_DYLIB="${BRIDGE_DYLIB:-$(ls -t /tmp/vrmc-*/libvrmc_bridge.dylib 2>/dev/null | head -1 || true)}"
hash() { [ -e "$1" ] && shasum -a 256 "$1" | awk '{print $1}' || echo "missing"; }
{
  echo "# VRMC release manifest"
  echo "# generated: $(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "source_commit=$(git rev-parse HEAD)"
  echo "source_branch=$(git rev-parse --abbrev-ref HEAD)"
  if [ -n "$(git status --porcelain)" ]; then
    echo "dirty_tree=YES (manifest must be regenerated from a clean release commit)"
    git status --porcelain | head -20 | sed 's/^/dirty_entry=/'
  else
    echo "dirty_tree=no"
  fi
  echo "product=${VRMC_PRODUCT}"
  echo "platform=${VRMC_PLATFORM}"
  echo "min_visionos=${VRMC_MIN_VISIONOS}"
  echo "mc_version=${MC_VERSION}"
  echo "mc_version_type=${MC_VERSION_TYPE}"
  echo "mc_version_json_sha256=${MC_VERSION_JSON_SHA256}"
  echo "java_major=${MC_JAVA_MAJOR} (${MC_JAVA_COMPONENT})"
  echo "lwjgl=${MC_LWJGL}"
  echo "fabric_loader=${FABRIC_LOADER}"
  echo "vivecraft=${VIVECRAFT_VERSION} (${VIVECRAFT_LICENSE})"
  echo "graphics=${MC_GRAPHICS_API}"
  echo "moltenvk=${MOLTENVK_VERSION} (${MOLTENVK_PIN})"
  echo "xcode=${XCODE_VERSION} (${XCODE_BUILD})"
  echo "visionos_sdk=${VISIONOS_SDK}"
  echo "visionos_sim_runtime=${VISIONOS_SIM_RUNTIME}"
  echo "app_bundle=${APP_BUNDLE:-none}"
  echo "app_bundle_sha256=$( [ -n "$APP_BUNDLE" ] && [ -d "$APP_BUNDLE" ] && "$ROOT/scripts/app_tree_sha256.sh" "$APP_BUNDLE" || echo missing )"
  echo "bridge_dylib=${BRIDGE_DYLIB:-none}"
  echo "bridge_dylib_sha256=$(hash "${BRIDGE_DYLIB:-/nonexistent}")"
  echo "provider_jar=${PROVIDER_JAR:-none}"
  echo "provider_jar_sha256=$(hash "${PROVIDER_JAR:-/nonexistent}")"
  echo "license_app=LICENSE:$( [ -f LICENSE ] && echo present || echo missing )"
  echo "license_provider=provider/LICENSE:$( [ -f provider/LICENSE ] && echo present || echo missing )"
  echo "third_party_notices=THIRD_PARTY_NOTICES.md:$( [ -f THIRD_PARTY_NOTICES.md ] && echo present || echo missing )"
  echo "privacy=PRIVACY.md:$( [ -f PRIVACY.md ] && echo present || echo missing )"
  echo "no_minecraft_binaries_in_git=$([ -z "$(git ls-files | grep -Ei '\.(jar|minecraft|mcassets)$' | grep -v '^provider/.*tests' || true)" ] && echo yes || echo REVIEW)"
  echo "m6_acceptance=docs/mvp/M6_ACCEPTANCE.md:$( [ -f docs/mvp/M6_ACCEPTANCE.md ] && echo present || echo missing )"
} > "$OUT"
echo "[m6-manifest] wrote $OUT"
if grep -q 'dirty_tree=YES' "$OUT"; then
  echo "[m6-manifest] WARNING: working tree is dirty; regenerate from a clean release commit" >&2
  exit 2
fi
