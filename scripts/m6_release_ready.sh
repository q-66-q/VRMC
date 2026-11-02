#!/bin/bash
# M6 single-command release-readiness gate.
#
# Runs: release check (licenses/source/reproducibility/manifest), package verifier (when a zip is given),
# device provider-integrity check (read-only; can run locked), and the acceptance readiness gate.
# Exit 0 only when every REQUIRED gate passes; the acceptance gate requires explicit PASS on all
# AC/K/H rows (device evidence), so this is expected to fail until D1 acceptance is complete.
#
# Usage: scripts/m6_release_ready.sh [--zip PATH] [--report-only] [--skip-device]
#   --report-only   run every gate but exit 0 even if acceptance is NOT READY (informational)
#   --skip-device   skip the read-only device integrity check
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ZIP="${RELEASE_ZIP:-/tmp/VRMC-dev-release.zip}"
REPORT_ONLY=0
SKIP_DEVICE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --zip) ZIP="$2"; shift 2 ;;
    --report-only) REPORT_ONLY=1 ;;
    --skip-device) SKIP_DEVICE=1 ;;
    *) echo "[release-ready] unknown argument: $1" >&2; exit 2 ;;
  esac
done
fail=0; acceptance_ready=0
step() { echo; echo "===== $* ====="; }

step "host release check"
if scripts/m6_release_check.sh; then echo "[release-ready] OK release check"; else echo "[release-ready] FAIL release check"; fail=1; fi

step "package freshness vs current build"
if scripts/m6_check_release_current.sh "$ZIP" "${RELEASE_APP_BUNDLE:-}" "${RELEASE_PROVIDER_JAR:-/tmp/vrmc-current/vrmc-provider.jar}"; then
  echo "[release-ready] OK package pins current build"
else
  echo "[release-ready] FAIL package is stale relative to current build"; fail=1
fi

step "package verification ($ZIP)"
if [ -f "$ZIP" ]; then
  if scripts/m6_verify_release_package.sh "$ZIP"; then echo "[release-ready] OK package"; else echo "[release-ready] FAIL package"; fail=1; fi
else
  echo "[release-ready] FAIL package missing: $ZIP"; fail=1
fi

if [ "$SKIP_DEVICE" = "0" ]; then
  step "device provider integrity (read-only)"
  if scripts/m6_device_integrity.sh; then echo "[release-ready] OK device integrity"; else echo "[release-ready] FAIL device integrity"; fail=1; fi
fi

step "acceptance gate"
if scripts/m6_acceptance_report.sh --require-pass; then
  acceptance_ready=1; echo "[release-ready] OK acceptance"
else
  echo "[release-ready] NOT READY acceptance (device AC/K/H gates incomplete)"
fi

if [ "$fail" = "0" ] && [ "$acceptance_ready" = "1" ]; then
  echo "[release-ready] RESULT: RELEASE READY"
  exit 0
fi
echo "[release-ready] RESULT: NOT RELEASE READY (host_fail=$fail acceptance_ready=$acceptance_ready)"
if [ "$REPORT_ONLY" = "1" ]; then exit 0; fi
exit 1
