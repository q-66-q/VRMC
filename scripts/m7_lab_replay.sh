#!/bin/bash
# M7 gesture-accuracy replay gate (host analysis; NOT device evidence).
#
# Regenerates compact replay fixtures from the labelled Gesture Lab recordings (raw JSONL stays local
# and gitignored), replays them through the real VisionM7Gesture at the recorded ~18 Hz cadence and
# at the game's ~90 Hz cadence, then scores the detected events against an independent ground-truth
# extractor (scripts/m7_eval_replay.py).
#
# Usage:
#   scripts/m7_lab_replay.sh [--skip-build] [--no-eval]
# Env:
#   PROVIDER_OUT   provider build dir (default /tmp/vrmc-provider-build)
#   LAB_DATA       recording dir (default export/gesturelab-data)
#   LAB_FIXTURES   fixture dir root (default export/m7-lab-fixtures{,-90})
#   LAB_OUT        replay output dir (default export/m7-replay{,-90})
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PROVIDER_OUT="${PROVIDER_OUT:-/tmp/vrmc-provider-build}"
LAB_DATA="${LAB_DATA:-export/gesturelab-data}"
SKIP_BUILD=0
NO_EVAL=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    --no-eval) NO_EVAL=1 ;;
    *) echo "[m7-replay] unknown arg: $arg" >&2; exit 2 ;;
  esac
done
[ -d "$LAB_DATA/accepted" ] || { echo "[m7-replay] SKIP: no recordings at $LAB_DATA/accepted"; exit 0; }

JAVAC=${JAVAC:-}
JAVA=${JAVA:-}
if [ -z "$JAVAC" ] || [ -z "$JAVA" ]; then
  JH=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home
  if [ -x "$JH/bin/javac" ]; then JAVAC="$JH/bin/javac"; JAVA="$JH/bin/java"; fi
fi
[ -n "$JAVAC" ] || JAVAC=$(command -v javac || true)
[ -n "$JAVA" ] || JAVA=$(command -v java || true)
[ -x "$JAVAC" ] && [ -x "$JAVA" ] || { echo "[m7-replay] ERROR: no JDK 25 found" >&2; exit 1; }

if [ "$SKIP_BUILD" = "0" ]; then
  echo "=== build provider ==="
  OUT_DIR="$PROVIDER_OUT" scripts/build_provider.sh | tail -4
fi
CP="$(cat "$PROVIDER_OUT/classpath.txt"):$PROVIDER_OUT/classes"
HARNESS_OUT="${HARNESS_OUT:-$PROVIDER_OUT/m7-replay-classes}"
mkdir -p "$HARNESS_OUT"
"$JAVAC" -cp "$CP" -d "$HARNESS_OUT" \
  provider/tests/dev/vrmc/provider/M7LabReplay.java

echo "=== fixtures (literal recorded samples) ==="
python3 scripts/m7_lab_fixture.py --data "$LAB_DATA" --out export/m7-lab-fixtures --rate 0 | tail -1
echo "=== fixtures (90 Hz interpolation) ==="
python3 scripts/m7_lab_fixture.py --data "$LAB_DATA" --out export/m7-lab-fixtures-90 --rate 90 | tail -1

run_replay() { # $1 fixtures, $2 out, $3 context
  echo "=== replay $2 (context=$3) ==="
  "$JAVA" -cp "$CP:$HARNESS_OUT" dev.vrmc.provider.M7LabReplay \
    --fixtures "$1" --out "$2" --context "$3" | tail -2
}
run_replay export/m7-lab-fixtures-90 "${LAB_OUT_90:-export/m7-replay-90}" auto
run_replay export/m7-lab-fixtures-90 export/m7-replay-90-nocontext none
run_replay export/m7-lab-fixtures export/m7-replay auto

if [ "$NO_EVAL" = "0" ]; then
  echo "=== evaluator self-check (regression-gate robustness; no raw data needed) ==="
  python3 scripts/m7_eval_replay.py --self-check
  echo "=== evaluation ==="
  python3 scripts/m7_eval_replay.py --events export/m7-replay-90/events.jsonl \
    --events-raw export/m7-replay/events.jsonl --data "$LAB_DATA"
fi
echo "[m7-replay] DONE"
