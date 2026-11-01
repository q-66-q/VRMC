#!/bin/bash
# log_evidence.sh — create an evidence bundle (manifest + hashes + entry template).
#
# This tool allocates the next EV-#### ID, copies artifacts into evidence/EV-####/,
# hashes them, and writes manifest.json plus an entry.md template. It does not edit
# VERIFY.md: the operator pastes the entry and updates the next-ID header (VERIFY §5).
#
# Usage:
#   scripts/log_evidence.sh --title "S1 JIT probe" --status PASS \
#       --device "D1 Apple Vision Pro" --procedure "boot app" --procedure "run hot loop" \
#       --expected "JIT compiles" --actual "compiled 12 methods" \
#       --artifact /tmp/jit.log [--notes "limitations"] [--dry-run]
#
# Options: --root DIR, --verify FILE, --commit SHA, --app-sha256 HEX
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$ROOT/VERIFY.md"
EVIDENCE_ROOT="$ROOT/evidence"
TITLE=""
STATUS="PARTIAL"
DEVICE=""
NOTES=""
EXPECTED=""
ACTUAL=""
APP_SHA=""
COMMIT_OVERRIDE=""
DRY_RUN=0
ARTIFACTS=""
PROCEDURE=""

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() { echo "error: $*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --title)       TITLE="${2:-}"; shift 2 ;;
    --status)      STATUS="${2:-}"; shift 2 ;;
    --device)      DEVICE="${2:-}"; shift 2 ;;
    --notes)       NOTES="${2:-}"; shift 2 ;;
    --expected)    EXPECTED="${2:-}"; shift 2 ;;
    --actual)      ACTUAL="${2:-}"; shift 2 ;;
    --procedure)   PROCEDURE="${PROCEDURE}${2:-}"$'\n'; shift 2 ;;
    --artifact)    ARTIFACTS="${ARTIFACTS}${2:-}"$'\n'; shift 2 ;;
    --app-sha256)  APP_SHA="${2:-}"; shift 2 ;;
    --commit)      COMMIT_OVERRIDE="${2:-}"; shift 2 ;;
    --root)        ROOT="${2:-}"; shift 2 ;;
    --verify)      VERIFY="${2:-}"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "unknown argument: $1" ;;
  esac
done

[ -n "$TITLE" ] || die "--title is required"
case "$STATUS" in
  PASS|PARTIAL|FAIL|BLOCKED|DEFERRED|"NOT RUN") ;;
  *) die "invalid --status '$STATUS' (PASS|PARTIAL|FAIL|BLOCKED|DEFERRED|'NOT RUN')" ;;
esac
[ -d "$ROOT" ] || die "root does not exist: $ROOT"
EVIDENCE_ROOT="${EVIDENCE_ROOT_OVERRIDE:-$ROOT/evidence}"

if [ -n "$ARTIFACTS" ]; then
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    [ -f "$a" ] || die "artifact not found: $a"
  done <<EOF
$ARTIFACTS
EOF
fi

EV_ID="$(python3 - "$VERIFY" "$EVIDENCE_ROOT" <<'PY'
import os, re, sys
verify, evroot = sys.argv[1], sys.argv[2]
text = open(verify, encoding="utf-8").read() if os.path.exists(verify) else ""
ids = [int(m) for m in re.findall(r'^### EV-(\d{4})', text, re.M)]
cand = max(ids + [0]) + 1
while True:
    eid = "EV-%04d" % cand
    if not os.path.isdir(os.path.join(evroot, eid)) and ("### " + eid) not in text:
        print(eid)
        break
    cand += 1
PY
)"

EV_DIR="$EVIDENCE_ROOT/$EV_ID"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run: would allocate $EV_ID"
  echo "  dir:       $EV_DIR"
  echo "  title:     $TITLE"
  echo "  status:    $STATUS"
  echo "  device:    ${DEVICE:-<none>}"
  echo "  artifacts: $(printf '%s' "$ARTIFACTS" | grep -c . || true)"
  echo "  procedure: $(printf '%s' "$PROCEDURE" | grep -c . || true) step(s)"
  exit 0
fi

mkdir -p "$EV_DIR"
: > "$EV_DIR/artifacts_src.txt"

if [ -n "$ARTIFACTS" ]; then
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    base="$(basename "$src")"
    idx="$(wc -l < "$EV_DIR/artifacts_src.txt" | tr -d ' ')"
    dest="$base"
    if [ -e "$EV_DIR/$dest" ]; then
      dest="$(printf '%03d' "$idx")-$base"
    fi
    cp "$src" "$EV_DIR/$dest"
    printf '%s\t%s\n' "$dest" "$src" >> "$EV_DIR/artifacts_src.txt"
  done <<EOF
$ARTIFACTS
EOF
fi

export ROOT EV_DIR EV_ID EV_TITLE="$TITLE" EV_STATUS="$STATUS" EV_DEVICE="$DEVICE" \
       EV_NOTES="$NOTES" EV_EXPECTED="$EXPECTED" EV_ACTUAL="$ACTUAL" \
       EV_APP_SHA="$APP_SHA" EV_COMMIT_OVERRIDE="$COMMIT_OVERRIDE" \
       EV_PROCEDURE="$PROCEDURE"

python3 - <<'PY'
import datetime, hashlib, json, os, re, subprocess, sys

root = os.environ["ROOT"]
evdir = os.environ["EV_DIR"]
eid = os.environ["EV_ID"]

def sh(cmd, default=""):
    try:
        return subprocess.check_output(cmd, cwd=root, text=True,
                                       stderr=subprocess.DEVNULL).strip()
    except Exception:
        return default

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

versions = {}
vf = os.path.join(root, "versions.env")
if os.path.isfile(vf):
    for line in open(vf, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        versions[k.strip()] = v.strip().strip('"')

commit = os.environ.get("EV_COMMIT_OVERRIDE") or sh(["git", "rev-parse", "HEAD"], "unknown")
dirty_raw = sh(["git", "status", "--porcelain"], "")
dirty = [line[3:] for line in dirty_raw.splitlines() if line.strip()]

xcode = sh(["xcodebuild", "-version"], "")
xcode_version = ""
xcode_build = ""
for line in xcode.splitlines():
    if line.startswith("Xcode "):
        xcode_version = line.split()[1]
    elif line.startswith("Build version "):
        xcode_build = line.split()[-1]

host = {
    "model": sh(["sysctl", "-n", "hw.model"]),
    "macos": sh(["sw_vers", "-productVersion"]),
    "xcode": xcode_version,
    "xcode_build": xcode_build,
}

procedure = [s for s in os.environ.get("EV_PROCEDURE", "").splitlines() if s.strip()]
if not procedure:
    procedure = ["(not recorded)"]

artifacts = []
src_map = os.path.join(evdir, "artifacts_src.txt")
if os.path.isfile(src_map):
    for line in open(src_map, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line:
            continue
        dest, source = line.split("\t", 1)
        artifacts.append({
            "path": "evidence/%s/%s" % (eid, dest),
            "sha256": sha256(os.path.join(evdir, dest)),
            "source": source,
        })

manifest = {
    "id": eid,
    "title": os.environ["EV_TITLE"],
    "date": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    "commit": commit,
    "dirty": dirty,
    "app_build_sha256": os.environ.get("EV_APP_SHA") or None,
    "device": os.environ.get("EV_DEVICE") or None,
    "host": host,
    "versions": versions,
    "procedure": procedure,
    "expected": os.environ.get("EV_EXPECTED") or "",
    "actual": os.environ.get("EV_ACTUAL") or "",
    "status": os.environ["EV_STATUS"],
    "artifacts": artifacts,
    "limitations": os.environ.get("EV_NOTES") or "",
}

with open(os.path.join(evdir, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, sort_keys=False)
    f.write("\n")

def esc(s):
    return s.replace("|", "\\|")

lines = []
lines.append("### %s — %s" % (eid, manifest["title"]))
lines.append("")
lines.append("| Field | Value |")
lines.append("|---|---|")
lines.append("| Date | %s |" % manifest["date"])
lines.append("| Commit | `%s` |" % manifest["commit"])
lines.append("| Dirty state | %s |" % (", ".join(dirty) if dirty else "clean"))
lines.append("| Device | %s |" % esc(manifest["device"] or "not recorded"))
lines.append("| Host | %s / macOS %s / Xcode %s |" % (host["model"] or "?", host["macos"] or "?", host["xcode"] or "?"))
lines.append("| Status | `%s` |" % manifest["status"])
lines.append("")
lines.append("**Procedure:**")
lines.append("")
for i, step in enumerate(procedure, 1):
    lines.append("%d. %s" % (i, step))
lines.append("")
lines.append("**Expected:** %s" % (manifest["expected"] or "(not recorded)"))
lines.append("")
lines.append("**Actual:** %s" % (manifest["actual"] or "(not recorded)"))
lines.append("")
lines.append("**Artifacts:** %s" % ("; ".join("%s (%s)" % (a["path"], a["sha256"][:12]) for a in artifacts) or "none"))
lines.append("")
if manifest["limitations"]:
    lines.append("**Limitations:** %s" % manifest["limitations"])
    lines.append("")

with open(os.path.join(evdir, "entry.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print("wrote %s/manifest.json" % evdir)
print("wrote %s/entry.md" % evdir)
print("artifacts: %d" % len(artifacts))
PY

echo ""
echo "Evidence bundle: $EV_DIR"
echo "Next: paste $EV_DIR/entry.md into VERIFY.md §6, update the header next ID, dashboard, and change log."
