#!/bin/bash
# M6 soak/stability harness (device monitoring; host dry-run safe).
#
# The device launch flow needs StikDebug + a manually enabled JIT per launch, so this harness does NOT
# automate Play. It monitors an operator-started VRMC session and records crash/hang evidence:
#   * host dry-run (default without --device): verifies tooling and prints the exact plan, exit 0
#   * device mode: requires DEVICE_UDID, polls shell/compositor/latestlog + vrmc-shutdown.log,
#     flags SIGSEGV/command-buffer failures/game-not-stopping and enforces a minimum soak duration.
#
# Usage:
#   scripts/m6_soak_harness.sh --dry-run
#   DEVICE_UDID=... SOAK_SECONDS=900 scripts/m6_soak_harness.sh --device
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=dry
[ "${1:-}" = "--device" ] && MODE=device
DEVICE_UDID="${DEVICE_UDID:-}"
BUNDLE_ID="${BUNDLE_ID:-dev.vrmc.vrmc}"
SOAK_SECONDS="${SOAK_SECONDS:-60}"
POLL_SECONDS="${POLL_SECONDS:-15}"
# AC-5 expects a clean quit at/after the soak window. Set to 0 only for an intentional still-running probe.
REQUIRE_CLEAN_SHUTDOWN="${REQUIRE_CLEAN_SHUTDOWN:-1}"
OUT="${OUT:-$ROOT/export/soak-$(date +%Y%m%d-%H%M%S)}"
if [ "$MODE" = dry ]; then
  echo "[m6-soak] dry-run: device=$([ -n "$DEVICE_UDID" ] && echo yes || echo 'not configured (set DEVICE_UDID)') bundle=$BUNDLE_ID soak=${SOAK_SECONDS}s poll=${POLL_SECONDS}s out=$OUT"
  command -v xcrun >/dev/null || { echo "[m6-soak] ERROR: xcrun missing"; exit 1; }
  command -v xcrun >/dev/null && xcrun devicectl --version >/dev/null 2>&1 || true
  echo "[m6-soak] device mode plan: operator starts the game with StikDebug JIT; harness polls logs, records every artifact, fails on SIGSEGV/command-buffer/FAILED/panic or game-stop without shutdown-complete."
  echo "[m6-soak] dry-run PASS"
  exit 0
fi
[ -n "$DEVICE_UDID" ] || { echo "[m6-soak] ERROR: DEVICE_UDID is required for --device" >&2; exit 2; }
mkdir -p "$OUT"
pull() { xcrun devicectl device copy from --device "$DEVICE_UDID" --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" --source "$1" --destination "$2" >/dev/null 2>&1 || true; }
# Snapshot the journal before monitoring so historical sessions cannot satisfy the clean-shutdown check.
pull Documents/instances/default/vrmc-shutdown.log "$OUT/shutdown-initial.log"
INITIAL_LINES=$(wc -l < "$OUT/shutdown-initial.log" 2>/dev/null | tr -d ' ' || echo 0)
echo "[m6-soak] shutdown baseline lines=${INITIAL_LINES:-0}"
echo "[m6-soak] monitoring $BUNDLE_ID on $DEVICE_UDID for ${SOAK_SECONDS}s; artifacts $OUT"
fail=0
start=$(date +%s)
while :; do
  now=$(date +%s); elapsed=$((now - start))
  stamp=$(date +%H%M%S)
  pull Documents/vrmc-shell.log "$OUT/shell-$stamp.log"
  pull Documents/vrmc-compositor.log "$OUT/compositor-$stamp.log"
  pull Documents/latestlog.txt "$OUT/game-$stamp.log"
  pull Documents/instances/default/logs/latest.log "$OUT/game-real-$stamp.log"
  pull Documents/instances/default/vrmc-shutdown.log "$OUT/shutdown-$stamp.log"
  pull Documents/vrmc-heartbeat.txt "$OUT/heartbeat-$stamp.txt"
  pull Documents/instances/default/vrmc-status.json "$OUT/status-$stamp.json"
  for log in "$OUT"/*-"$stamp".log; do
    [ -f "$log" ] || continue
    if grep -aqE "SIGSEGV|command buffer FAILED|__BUG_IN_CLIENT__|panic|VRMC_BUG|OutOfMemoryError|watchdog" "$log"; then
      echo "[m6-soak] FAIL marker in $log"; fail=1
    fi
  done
  echo "[m6-soak] t=${elapsed}s"
  [ "$elapsed" -ge "$SOAK_SECONDS" ] && break
  sleep "$POLL_SECONDS"
done
latest_shutdown=$(ls -t "$OUT"/shutdown-*.log 2>/dev/null | head -1 || true)
if [ -n "$latest_shutdown" ]; then
  new_events=$(tail -n +$((INITIAL_LINES + 1)) "$latest_shutdown" 2>/dev/null || true)
  last_event=$(printf '%s\n' "$new_events" | grep -E "event=(init|destroy-start|destroy-complete)" | tail -1 || true)
  init_count=$(printf '%s\n' "$new_events" | grep -c "event=init" || true)
  echo "[m6-soak] shutdown journal last new event: ${last_event:-<none>}"
  if [ "$REQUIRE_CLEAN_SHUTDOWN" = "1" ]; then
    if ! printf '%s' "$last_event" | grep -q "event=destroy-complete"; then
      echo "[m6-soak] FAIL: last new shutdown event is not destroy-complete (crash/force-kill or still running)"
      fail=1
    fi
    if [ "${init_count:-0}" -ne 1 ]; then
      echo "[m6-soak] FAIL: $init_count provider init events in soak window (expected exactly 1 continuous session)"
      fail=1
    fi
  else
    echo "[m6-soak] WARN: REQUIRE_CLEAN_SHUTDOWN=0; not enforcing last event/one-init"
  fi
else
  if [ "$REQUIRE_CLEAN_SHUTDOWN" = "1" ]; then
    echo "[m6-soak] FAIL: no shutdown journal captured (no session, game still running, or teardown crash)"
    fail=1
  else
    echo "[m6-soak] WARN: no shutdown journal captured"
  fi
fi
latest_status=$(ls -t "$OUT"/status-*.json 2>/dev/null | head -1 || true)
if [ -n "$latest_status" ] && grep -q '"abi"' "$latest_status"; then
  echo "[m6-soak] status snapshot captured: $(basename "$latest_status")"
else
  echo "[m6-soak] WARN: no vrmc-status.json captured"
fi
if [ "$fail" != "0" ]; then echo "[m6-soak] RESULT: FAIL (see $OUT)"; exit 1; fi
echo "[m6-soak] RESULT: PASS (no crash markers in monitored window; $OUT)"
