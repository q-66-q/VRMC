#!/bin/bash
# One-command M8 device session: validate the staged candidate, install it on D1, push the matching
# provider jar, print the operator checklist, and classify the session afterwards (A6-A9).
#
# This wraps the existing, separately-tested tools:
#   scripts/install_device.sh / scripts/push_provider_jar.sh   (prepare)
#   scripts/m8_device_check.sh                                  (pull + A6-A9 classifier)
#
# Usage:
#   scripts/m8_device_session.sh prepare            # validate local candidate, install app, push provider
#   scripts/m8_device_session.sh collect            # pull the latest session logs and classify A6-A9
#   scripts/m8_device_session.sh all                # prepare now; collect must be run after the play session
#   scripts/m8_device_session.sh --from <dir>       # classify an existing pull (no device)
#
# Options/env:
#   --dry-run            validate + print the exact device commands, change nothing
#   --report             collect also writes export/m8-device-session-report.md (+ report script)
#   --evidence           with --report: also create an evidence bundle for the session
#   --from <dir>         classify an existing pull directory (implies collect)
#   APP                  app bundle (default /tmp/VRMC-native-m8.app)
#   PROVIDER_JAR         provider jar (default /tmp/vrmc-provider-build/vrmc-provider.jar)
#   DEVICE / BUNDLE_ID   device UDID / app bundle id (defaults D1 / dev.vrmc.vrmc)
#   ALLOW_HASH_MISMATCH=1 skip the local-artifact hash checks against export/m8-device-candidate.txt
#   PUSH_JIT=1           also push runtime/jit/amethyst.js into StikDebug (if its bundle id is set)
#
# Exit: 0 ok / 2 usage or local-artifact error / 5 device unavailable / classifier codes (0/2/3/4)
#       from collect (0 PASS A6-A9, 2 PARTIAL, 3 NOT RUN, 4 FAIL).
#
# Session procedure/acceptance: docs/mvp/M8_DEVICE_RUN.md. Evidence: VERIFY.md.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-$VRMC_DEVICE_UDID}"
BUNDLE_ID="${BUNDLE_ID:-dev.vrmc.vrmc}"
APP="${APP:-/tmp/VRMC-native-m8.app}"
PROVIDER_JAR="${PROVIDER_JAR:-/tmp/vrmc-provider-build/vrmc-provider.jar}"
OUTDIR="${OUTDIR:-/tmp/vrmc-m8-device}"
MANIFEST="${MANIFEST:-$ROOT/export/m8-device-candidate.txt}"
DRY_RUN=0
FROM=""
REPORT=0
EVIDENCE=0
MODE="${1:-}"

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { echo "[m8-session] ERROR: $*" >&2; exit 2; }
note() { echo "[m8-session] $*"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    prepare|collect|all) MODE="$1"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --report) REPORT=1; shift ;;
    --evidence) EVIDENCE=1; shift ;;
    --from) FROM="${2:?--from needs a directory}"; MODE="collect"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    "") shift ;;
    *) die "unknown argument '$1' (see --help)" ;;
  esac
done
[ -n "$MODE" ] || { usage; exit 2; }

run() { if [ "$DRY_RUN" = "1" ]; then echo "  DRY-RUN: $*"; else "$@"; fi; }

# ---- shared: classify (collect) ---------------------------------------------------------------
collect() {
  local rc
  if [ -n "$FROM" ]; then
    note "classifying existing pull: $FROM"
    "$ROOT/scripts/m8_device_check.sh" --from "$FROM"
    rc=$?
  elif [ "$DRY_RUN" = "1" ]; then
    echo "  DRY-RUN: OUTDIR=$OUTDIR scripts/m8_device_check.sh"
    rc=0
  else
    note "pulling the latest session logs and classifying A6-A9 -> $OUTDIR"
    OUTDIR="$OUTDIR" "$ROOT/scripts/m8_device_check.sh"
    rc=$?
  fi
  if [ "$REPORT" = "1" ] && [ "$DRY_RUN" != "1" ]; then
    local report_args=(--from "${FROM:-$OUTDIR}")
    if [ "$EVIDENCE" = "1" ]; then report_args+=(--evidence); fi
    "$ROOT/scripts/m8_device_report.sh" "${report_args[@]}" || note "WARN: report generation failed (classifier rc=$rc preserved)"
  fi
  return "$rc"
}

# ---- shared: local artifact validation --------------------------------------------------------
validate_local() {
  [ -d "$APP" ] || die "app bundle not found: $APP (build/stage it first; see export/m8-device-candidate.txt)"
  [ -f "$PROVIDER_JAR" ] || die "provider jar not found: $PROVIDER_JAR (scripts/build_provider.sh)"
  note "app:          $APP"
  note "provider jar: $PROVIDER_JAR"
  if command -v codesign >/dev/null 2>&1; then
    if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
      note "codesign:     deep/strict PASS"
    else
      die "codesign --verify --deep --strict FAILED for $APP"
    fi
  fi
  if [ -x "$ROOT/scripts/profile_expiry.sh" ]; then
    profile_warn=$(mktemp /tmp/vrmc-profile-warn.XXXXXX)
    profile_info=$("$ROOT/scripts/profile_expiry.sh" "$APP" --warn-days 7 2>"$profile_warn") || {
      cat "$profile_warn" >&2; rm -f "$profile_warn"
      die "the embedded provisioning profile is expired; re-sign with a fresh profile before the device session (see docs/mvp/M8_DEVICE_RUN.md)"
    }
    cat "$profile_warn" >&2; rm -f "$profile_warn"
    note "profile:      $profile_info"
  fi
  if [ "${ALLOW_HASH_MISMATCH:-0}" != "1" ] && [ -f "$MANIFEST" ]; then
    local want_app want_provider have_app have_provider
    want_app=$(grep -m1 '^app_tree_sha256=' "$MANIFEST" | cut -d= -f2)
    want_provider=$(grep -m1 '^provider_jar_sha256=' "$MANIFEST" | cut -d= -f2)
    have_app=$("$ROOT/scripts/app_tree_sha256.sh" "$APP" 2>/dev/null || true)
    have_provider=$(shasum -a 256 "$PROVIDER_JAR" | awk '{print $1}')
    note "app tree sha: $have_app (manifest: ${want_app:-none})"
    note "provider sha: $have_provider (manifest: ${want_provider:-none})"
    if [ -n "$want_app" ] && [ "$have_app" != "$want_app" ]; then
      note "WARNING: app tree hash differs from the recorded candidate (re-signed/rebuilt? set ALLOW_HASH_MISMATCH=1 to proceed)"
      [ "${ALLOW_HASH_MISMATCH:-0}" = "1" ] || die "refusing to install an unrecorded app tree"
    fi
    if [ -n "$want_provider" ] && [ "$have_provider" != "$want_provider" ]; then
      die "provider jar hash $have_provider != recorded $want_provider (build it with scripts/build_provider.sh)"
    fi
  fi
  if [ "${PUSH_JIT:-0}" = "1" ] && [ -n "${STIKDEBUG_BUNDLE_ID:-}" ]; then
    note "JIT script:   runtime/jit/amethyst.js -> $STIKDEBUG_BUNDLE_ID Documents/scripts/"
  fi
}

# ---- prepare ----------------------------------------------------------------------------------
prepare() {
  note "M8 device session prepare (device $DEVICE, bundle $BUNDLE_ID)"
  validate_local
  if [ "$DRY_RUN" = "1" ]; then
    echo "  DRY-RUN: DEVICE=$DEVICE scripts/install_device.sh $APP $BUNDLE_ID"
    echo "  DRY-RUN: DEVICE=$DEVICE scripts/push_provider_jar.sh $PROVIDER_JAR"
    if [ "${PUSH_JIT:-0}" = "1" ]; then
      echo "  DRY-RUN: DEVICE=$DEVICE scripts/push_jit_script.sh runtime/jit/amethyst.js"
    fi
    note "dry-run complete (nothing installed)"
    return 0
  fi
  local devices
  devices=$(xcrun devicectl list devices 2>/dev/null || true)
  if ! printf '%s\n' "$devices" | grep -q -- "$DEVICE"; then
    note "device $DEVICE not listed by devicectl (connect/unlock D1)"; exit 5
  fi
  note "installing app (replaces an existing $BUNDLE_ID) ..."
  DEVICE="$DEVICE" "$ROOT/scripts/install_device.sh" "$APP" "$BUNDLE_ID" || { note "install failed (device busy/locked?)"; exit 5; }
  note "pushing provider jar ..."
  DEVICE="$DEVICE" BUNDLE_ID="$BUNDLE_ID" "$ROOT/scripts/push_provider_jar.sh" "$PROVIDER_JAR" || { note "provider push failed"; exit 5; }
  if [ "${PUSH_JIT:-0}" = "1" ] && [ -n "${STIKDEBUG_BUNDLE_ID:-}" ]; then
    DEVICE="$DEVICE" "$ROOT/scripts/push_jit_script.sh" "$ROOT/runtime/jit/amethyst.js" || note "WARN: JIT script push failed (configure StikDebug manually)"
  fi
  cat <<'EOF'

[m8-session] ================= OPERATOR CHECKLIST (M8 device run) =================
  1. Confirm the M8 build is installed and the provider jar is in
     Documents/instances/default/mods/vrmc-provider.jar (plus Vivecraft 26.2-1.3.15).
  2. Open StikDebug, enable JIT for dev.vrmc.vrmc, launch VRMC.
  3. In the launcher: Play -> let Minecraft boot -> enter the immersive space.
  4. Play 3-5 minutes: walk/turn, look at distant geometry, open/close a menu.
  5. Optional tuning during the session (Mac side, live):
       scripts/push_m8_render_config.sh --eye-scale 0.5
       scripts/push_m8_render_config.sh --sharpening off     (A/B halos)
     (max-quality changes apply on the next immersive open; runtime-quality on relaunch.)
  6. Quit Minecraft with its own Quit Game (clean destroy-complete).
  7. Back on the Mac run: scripts/m8_device_session.sh collect
==================================================================================
EOF
  return 0
}

case "$MODE" in
  prepare) prepare ;;
  collect) collect ;;
  all)
    prepare || exit $?
    note "prepare done. After the play session run: scripts/m8_device_session.sh collect --report"
    ;;
esac
