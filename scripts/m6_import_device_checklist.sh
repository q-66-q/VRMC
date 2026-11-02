#!/bin/bash
# M6: import the in-headset acceptance checklist (JSON) into a Markdown/machine report.
# Either pull Documents/vrmc-acceptance-checklist.json from the installed app data container, or use a
# local file (--input) for offline/host validation. Writes:
#   export/device-acceptance-report.md
#   export/device-acceptance-status.txt
# Never claims device PASS by itself; results must be reviewed and recorded in VERIFY.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE_ID:-${VRMC_DEVICE_UDID:-}}"
BUNDLE="${BUNDLE_ID:-dev.vrmc.vrmc}"
INPUT=""
REQUIRE_NO_FAIL=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --input) INPUT="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --require-no-fail) REQUIRE_NO_FAIL=1; shift ;;
    *) echo "[checklist-import] unknown argument: $1" >&2; exit 2 ;;
  esac
done
TMP=""
if [ -z "$INPUT" ]; then
  TMP="$(mktemp -d /tmp/vrmc-checklist.XXXXXX)"
  trap 'rm -rf "$TMP"' EXIT
  INPUT="$TMP/checklist.json"
  echo "[checklist-import] pulling Documents/vrmc-acceptance-checklist.json from $DEVICE"
  if ! xcrun devicectl device copy from --device "$DEVICE" \
       --domain-type appDataContainer --domain-identifier "$BUNDLE" \
       --source "Documents/vrmc-acceptance-checklist.json" --destination "$INPUT" >/dev/null 2>&1; then
    echo "[checklist-import] ERROR: checklist not found on device (open the launcher checklist and Save first)" >&2
    exit 3
  fi
fi
[ -f "$INPUT" ] || { echo "[checklist-import] ERROR: input missing: $INPUT" >&2; exit 4; }
mkdir -p "$ROOT/export"
python3 - "$INPUT" "$ROOT/export/device-acceptance-report.md" "$ROOT/export/device-acceptance-status.txt" <<'PY'
import json, sys, datetime
src, md_path, txt_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, "r", encoding="utf-8") as f:
    items = json.load(f)
if not isinstance(items, list) or not all(isinstance(i, dict) for i in items):
    raise SystemExit("[checklist-import] ERROR: checklist JSON must be an array of objects")
allowed = {"NOT RUN", "PARTIAL", "PASS", "FAIL"}
counts = {k: 0 for k in allowed}
rows = []
for item in items:
    iid = str(item.get("id", "?"))
    title = str(item.get("title", ""))
    status = str(item.get("status", "NOT RUN"))
    if status not in allowed:
        raise SystemExit(f"[checklist-import] ERROR: bad status '{status}' for {iid}")
    counts[status] += 1
    rows.append((iid, title, status))
md = ["# VRMC device acceptance checklist (imported)", ""]
md.append(f"source: `{src}`")
md.append(f"imported: {datetime.datetime.now().isoformat(timespec='seconds')}")
md.append("")
md.append(f"PASS={counts['PASS']} PARTIAL={counts['PARTIAL']} FAIL={counts['FAIL']} NOT RUN={counts['NOT RUN']}")
md.append("")
md.append("| ID | Check | Status |")
md.append("|---|---|---|")
for iid, title, status in rows:
    md.append(f"| {iid} | {title} | {status} |")
md.append("")
md.append("Review these results and record them in VERIFY with device evidence (`M6_DEVICE_RUN.md`).")
with open(md_path, "w", encoding="utf-8") as f:
    f.write("\n".join(md) + "\n")
with open(txt_path, "w", encoding="utf-8") as f:
    for iid, _, status in rows:
        f.write(f"{iid}={status}\n")
print(f"[checklist-import] rows={len(rows)} PASS={counts['PASS']} PARTIAL={counts['PARTIAL']} "
      f"FAIL={counts['FAIL']} NOT RUN={counts['NOT RUN']}")
print(f"[checklist-import] wrote {md_path}")
print(f"[checklist-import] wrote {txt_path}")
if counts["FAIL"] > 0:
    print(f"[checklist-import] WARNING: {counts['FAIL']} failing checklist item(s)")
    sys.exit(10)
PY
if [ "$REQUIRE_NO_FAIL" = "1" ] && grep -q "FAIL" "$ROOT/export/device-acceptance-status.txt"; then
  echo "[checklist-import] RESULT: FAIL (failing items present)" >&2
  exit 10
fi
echo "[checklist-import] RESULT: report written (device evidence still requires review)"
