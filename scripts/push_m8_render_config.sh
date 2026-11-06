#!/bin/bash
# Push M8 rendering knobs to the installed VRMC app's data container (or print what would be pushed).
#
# These are the on-device tuning knobs from docs/mvp/M8_DEVICE_RUN.md §4:
#   --max-quality      Documents/vrmc-max-render-quality.txt      (shell; upper bound, next immersive open)
#   --runtime-quality  Documents/vrmc-render-quality.txt          (compositor; fixed/auto, next launch)
#   --eye-scale        Documents/instances/default/vrmc-eye-scale.txt (provider; live, re-read ~600 frames)
#   --foveation-off    Documents/vrmc-foveation-off.flag          (A/B: uniform rasterization)
#
# devicectl has no delete command, so every knob has an "effective default" content instead:
#   max-quality default -> 1.0, runtime-quality default -> 1.0 (fixed max), eye-scale default -> auto.
# The foveation flag is one-way on device (remove it with Documents/vrmc-clear-diagnostics.flag or an
# app-data reset if you need foveation back on; the M8 default is ON).
#
# Usage:
#   DEVICE=<udid> scripts/push_m8_render_config.sh --eye-scale 0.5
#   DEVICE=<udid> scripts/push_m8_render_config.sh --max-quality 0.75 --runtime-quality auto
#   scripts/push_m8_render_config.sh --print --eye-scale auto        # no device contact
#   scripts/push_m8_render_config.sh --self-test                     # offline validation only
#
# Env: DEVICE (default D1 UDID), BUNDLE_ID (dev.vrmc.vrmc), GAME_DIR (Documents/instances/default),
#      DRY_RUN=1 (same as --print), MAX_ATTEMPTS (default 3).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-${VRMC_DEVICE_UDID:-}}"
BUNDLE_ID="${BUNDLE_ID:-dev.vrmc.vrmc}"
GAME_DIR="${GAME_DIR:-Documents/instances/default}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
PRINT="${DRY_RUN:-0}"
SELF_TEST=0

die() { echo "[m8config] ERROR: $*" >&2; exit 2; }
note() { echo "[m8config] $*"; }

# ---- argument validation (pure; also used by --self-test) -------------------------------------
validate_max_quality() {
  case "$1" in default) return 0 ;; esac
  awk -v v="$1" 'BEGIN { exit !(v ~ /^[0-9]+([.][0-9]+)?$/ && v >= 0.05 && v <= 1.0) }'
}
validate_runtime_quality() {
  case "$1" in default|auto) return 0 ;; esac
  awk -v v="$1" 'BEGIN { exit !(v ~ /^[0-9]+([.][0-9]+)?$/ && v >= 0.0 && v <= 1.0) }'
}
validate_eye_scale() {
  case "$1" in auto) return 0 ;; esac
  awk -v v="$1" 'BEGIN { exit !(v ~ /^[0-9]+([.][0-9]+)?$/ && v >= 0.25 && v <= 1.0) }'
}

max_quality_content() {
  case "$1" in default) echo "1.0" ;; *) echo "$1" ;; esac
}
runtime_quality_content() {
  case "$1" in default) echo "1.0" ;; *) echo "$1" ;; esac
}
eye_scale_content() {
  case "$1" in auto) echo "auto" ;; *) echo "$1" ;; esac
}

# ---- --self-test: offline assertions, no device -------------------------------------------------
self_test() {
  local fails=0
  t() { local name="$1" expected="$2"; shift 2; if "$@" >/dev/null 2>&1; then got=0; else got=1; fi
        if [ "$got" = "$expected" ]; then echo "  PASS $name"; else echo "  FAIL $name (exit $got, expected $expected)"; fails=$((fails+1)); fi; }
  echo "[m8config] self-test (offline)"
  t "max-quality 1.0 accepted" 0 validate_max_quality 1.0
  t "max-quality 0.05 accepted" 0 validate_max_quality 0.05
  t "max-quality 0.04 rejected" 1 validate_max_quality 0.04
  t "max-quality 1.5 rejected" 1 validate_max_quality 1.5
  t "max-quality default accepted" 0 validate_max_quality default
  t "runtime-quality auto accepted" 0 validate_runtime_quality auto
  t "runtime-quality 0.0 accepted" 0 validate_runtime_quality 0.0
  t "runtime-quality 1.1 rejected" 1 validate_runtime_quality 1.1
  t "runtime-quality junk rejected" 1 validate_runtime_quality junk
  t "eye-scale auto accepted" 0 validate_eye_scale auto
  t "eye-scale 0.25 accepted" 0 validate_eye_scale 0.25
  t "eye-scale 0.2 rejected" 1 validate_eye_scale 0.2
  t "eye-scale 1.01 rejected" 1 validate_eye_scale 1.01
  local c
  c=$(max_quality_content default);   [ "$c" = "1.0" ]  || { echo "  FAIL max-quality default content"; fails=$((fails+1)); }
  c=$(runtime_quality_content default); [ "$c" = "1.0" ] || { echo "  FAIL runtime-quality default content"; fails=$((fails+1)); }
  c=$(eye_scale_content auto);        [ "$c" = "auto" ] || { echo "  FAIL eye-scale auto content"; fails=$((fails+1)); }
  [ "$fails" = "0" ] && { echo "[m8config] SELF-TEST PASS (15 checks)"; return 0; }
  echo "[m8config] SELF-TEST FAIL ($fails)"; return 1
}

# ---- parse arguments ----------------------------------------------------------------------------
PUSH_FILES=()   # "local-content|dest-relative-path" pairs
while [ "$#" -gt 0 ]; do
  case "$1" in
    --max-quality)
      v="${2:-}"; [ -n "$v" ] || die "--max-quality needs a value"
      validate_max_quality "$v" || die "invalid --max-quality '$v' (default|0.05..1.0)"
      PUSH_FILES+=("$(max_quality_content "$v")|Documents/vrmc-max-render-quality.txt"); shift 2 ;;
    --runtime-quality)
      v="${2:-}"; [ -n "$v" ] || die "--runtime-quality needs a value"
      validate_runtime_quality "$v" || die "invalid --runtime-quality '$v' (default|auto|0.0..1.0)"
      PUSH_FILES+=("$(runtime_quality_content "$v")|Documents/vrmc-render-quality.txt"); shift 2 ;;
    --eye-scale)
      v="${2:-}"; [ -n "$v" ] || die "--eye-scale needs a value"
      validate_eye_scale "$v" || die "invalid --eye-scale '$v' (auto|0.25..1.0)"
      PUSH_FILES+=("$(eye_scale_content "$v")|$GAME_DIR/vrmc-eye-scale.txt"); shift 2 ;;
    --foveation-off)
      PUSH_FILES+=("off|Documents/vrmc-foveation-off.flag"); shift ;;
    --print) PRINT=1; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# {0,1}//'; exit 0 ;;
    *) die "unknown option '$1' (see --help)" ;;
  esac
done

[ "$SELF_TEST" = "1" ] && self_test && exit 0
[ "${#PUSH_FILES[@]}" -gt 0 ] || die "nothing to push (use --max-quality/--runtime-quality/--eye-scale/--foveation-off)"

note "device:   $DEVICE"
note "container: $BUNDLE_ID"
TMP="$(mktemp -d /tmp/vrmc-m8config.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

INDEX=0
for entry in "${PUSH_FILES[@]}"; do
  content="${entry%%|*}"
  dest="${entry#*|}"
  local_file="$TMP/f$INDEX"
  printf '%s\n' "$content" > "$local_file"
  INDEX=$((INDEX+1))
  note "plan: $dest <= '$content'"
  if [ "$PRINT" = "1" ]; then
    echo "  DRY-RUN: xcrun devicectl device copy to --device $DEVICE --domain-type appDataContainer --domain-identifier $BUNDLE_ID --source $local_file --destination $dest"
    continue
  fi
  attempt=1
  while :; do
    set +e
    OUT=$(xcrun devicectl device copy to --device "$DEVICE" \
      --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
      --source "$local_file" --destination "$dest" 2>&1)
    RC=$?
    set -e
    echo "$OUT" | sed 's/^/[m8config]   /'
    [ "$RC" -eq 0 ] && break
    if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
      note "copy failed (attempt $attempt/$MAX_ATTEMPTS); retrying in 5s"
      attempt=$((attempt+1)); sleep 5; continue
    fi
    die "devicectl copy to failed for $dest (device unavailable? connect/unlock D1 and retry)"
  done
  note "pushed: $dest"
done

if [ "$PRINT" = "1" ]; then
  note "dry-run complete (no device contact)"
  exit 0
fi
note "done. Apply notes: max-quality needs the immersive space reopened; runtime-quality needs an app relaunch;"
note "eye-scale is re-read by the provider every ~600 frames (no relaunch)."
