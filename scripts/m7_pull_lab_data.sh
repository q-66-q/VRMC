#!/bin/bash
# Pull Gesture Lab recordings/logs from the separate app container (dev.vrmc.s2probe) and analyze.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE_ID:-${VRMC_DEVICE_UDID:-}}"
OUT="${1:-$ROOT/export/gesturelab-data}"
mkdir -p "$OUT"
TMP=$(mktemp -d /tmp/vrmc-lab-list.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
xcrun devicectl device info files --device "$DEVICE" --domain-type appDataContainer \
  --domain-identifier dev.vrmc.s2probe --subdirectory Documents --no-recurse \
  --json-output "$TMP/files.json" >/dev/null 2>&1 || {
    echo "[m7-lab] could not list Gesture Lab Documents (is the app installed?)" >&2; exit 2; }
python3 - "$TMP/files.json" > "$TMP/names.txt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for f in d.get("result", {}).get("files", []):
    name = f.get("name") or f.get("fileName") or f.get("url", "").rstrip("/").split("/")[-1]
    if name.startswith("gesturelab-") and (name.endswith(".jsonl") or name == "gesturelab.log"):
        print(name)
PY
COUNT=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
       --domain-identifier dev.vrmc.s2probe --source "Documents/$name" --destination "$OUT/$name" >/dev/null 2>&1; then
    echo "[m7-lab] pulled $name ($(stat -f%z "$OUT/$name") bytes)"
    COUNT=$((COUNT+1))
  else
    echo "[m7-lab] WARN could not pull $name" >&2
  fi
done < "$TMP/names.txt"
echo "[m7-lab] pulled $COUNT file(s) -> $OUT"
if [ "$COUNT" = 0 ]; then
  echo "[m7-lab] no recordings yet; open Gesture Lab -> Open Hand Lab -> Start Recording/Guided Capture first"
fi
if command -v python3 >/dev/null; then
  python3 "$ROOT/scripts/m7_analyze_lab_data.py" "$OUT" >/dev/null 2>&1 || true
fi
