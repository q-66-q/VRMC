#!/bin/bash
# Report the embedded development provisioning profile's expiry for a signed app (or a raw profile).
#
# Development-signed builds stop installing/launching when the embedded profile expires (Xcode's team
# profiles are typically valid for a few days). The M8 device candidate must be re-signed with a fresh
# profile before that date (or the device session happens before it).
#
# Usage:
#   scripts/profile_expiry.sh <app.app|profile.mobileprovision> [--warn-days N]
# Exit: 0 profile valid / 1 missing or expired / 2 usage / 3 cannot decode.
# Output line: "profile=<name> expires=<UTC> days_left=<n> provisions=<udid|...>"
set -uo pipefail
TARGET="${1:-}"
WARN_DAYS=7
shift || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --warn-days) WARN_DAYS="${2:?--warn-days needs N}"; shift 2 ;;
    *) echo "[profile] ERROR: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$TARGET" ] || { echo "[profile] usage: $0 <app.app|profile.mobileprovision> [--warn-days N]" >&2; exit 2; }

PROFILE="$TARGET"
if [ -d "$TARGET" ]; then
  PROFILE="$TARGET/embedded.mobileprovision"
fi
if [ ! -f "$PROFILE" ]; then
  echo "[profile] ERROR: no provisioning profile at $PROFILE" >&2
  exit 1
fi
PLIST="$(mktemp /tmp/vrmc-profile.XXXXXX)"
trap 'rm -f "$PLIST"' EXIT
security cms -D -i "$PROFILE" > "$PLIST" 2>/dev/null || { echo "[profile] ERROR: cannot decode $PROFILE" >&2; exit 3; }

# Parse the decoded plist with Python (plistlib turns <date> into a tz-aware datetime, unlike
# PlistBuddy's human-readable "Sat Nov 07 22:53:50 HST 2026" output).
python3 - "$PLIST" "$WARN_DAYS" <<'PY'
import plistlib, sys, datetime
path, warn = sys.argv[1], int(sys.argv[2])
try:
    with open(path, "rb") as handle:
        doc = plistlib.load(handle)
except Exception as error:
    print("[profile] ERROR: cannot parse decoded profile: " + str(error), file=sys.stderr)
    sys.exit(3)
name = str(doc.get("Name", "unknown"))
exp = doc.get("ExpirationDate")
devices = doc.get("ProvisionedDevices") or []
has_d1 = "yes" if "${VRMC_DEVICE_UDID:-}" in devices else "no"
if not isinstance(exp, datetime.datetime):
    print("[profile] ERROR: profile has no usable ExpirationDate", file=sys.stderr)
    sys.exit(3)
# plistlib returns <date> values as naive UTC datetimes; astimezone() on naive values would
# assume local time, so attach UTC explicitly for those.
if exp.tzinfo is None:
    exp_utc = exp.replace(tzinfo=datetime.timezone.utc)
else:
    exp_utc = exp.astimezone(datetime.timezone.utc)
now = datetime.datetime.now(datetime.timezone.utc)
days = (exp_utc - now).total_seconds() / 86400.0
print("[profile] profile=" + name + " expires=" + exp_utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      + " days_left=%.1f" % days + " provisions_d1=" + has_d1)
if days <= 0:
    print("[profile] ERROR: provisioning profile EXPIRED - re-sign with a fresh profile before installing", file=sys.stderr)
    sys.exit(1)
if days <= warn:
    print("[profile] WARNING: provisioning profile expires in %.1f day(s); renew/re-sign before the device session" % days, file=sys.stderr)
sys.exit(0)
PY
