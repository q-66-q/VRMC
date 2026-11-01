#!/bin/bash
# Set the M1-required Minecraft option defaults on the device:
#   preferredGraphicsBackend:"vulkan"  (prevents the ANGLE fallback)
#   startedCleanly:true                (clears the crash-recovery reset)
# Usage: DEVICE=<udid> ./scripts/set_mc_options.sh
set -euo pipefail
: "${DEVICE:?set DEVICE to the device UDID}"
AMETHYST_BUNDLE_ID=${AMETHYST_BUNDLE_ID:-dev.vrmc.amethyst}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

xcrun devicectl device copy from --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$AMETHYST_BUNDLE_ID" \
  --source "Documents/instances/default/options.txt" \
  --destination "$TMP/options.txt" >/dev/null

python3 - "$TMP/options.txt" <<'PY'
import sys
path = sys.argv[1]
lines = open(path).read().splitlines()
out = []
for line in lines:
    if line.startswith("preferredGraphicsBackend:"):
        out.append('preferredGraphicsBackend:"vulkan"')
    elif line.startswith("startedCleanly:"):
        out.append("startedCleanly:true")
    else:
        out.append(line)
open(path, "w").write("\n".join(out) + "\n")
PY

xcrun devicectl device copy to --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$AMETHYST_BUNDLE_ID" \
  --source "$TMP/options.txt" --destination "Documents/instances/default/options.txt"
echo "[mc-options] pushed preferredGraphicsBackend=vulkan, startedCleanly=true"
