#!/bin/bash
# Push the VRMC provider mod jar into the installed VRMC app's data container on the Vision Pro.
# Uses devicectl appDataContainer file transfer (no install, no app restart).
#
# Usage:  scripts/push_provider_jar.sh [jar]
# Default jar: ${OUT_DIR:-/tmp/vrmc-provider-build}/vrmc-provider.jar (output of build_provider.sh),
# falling back to /tmp/vrmc-provider.jar.
#
# Env overrides (all optional):
#   DEVICE      device UDID / name            (default ${VRMC_DEVICE_UDID:-})
#   BUNDLE_ID   target app bundle id          (default dev.vrmc.vrmc)
#   DEST_REL    destination inside the app data container
#               (default Documents/instances/default/mods/vrmc-provider.jar)
#   VERIFY=0    skip the copy-from + sha256 round-trip verification
#   SKIP_DEVICE_CHECK=1  skip the 'is the device connected' pre-flight
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-${VRMC_DEVICE_UDID:-}}"
BUNDLE_ID="${BUNDLE_ID:-dev.vrmc.vrmc}"
DEST_REL="${DEST_REL:-Documents/instances/default/mods/vrmc-provider.jar}"
VERIFY="${VERIFY:-1}"
JAR="${1:-${JAR:-/tmp/vrmc-provider-build/vrmc-provider.jar}}"

die() { echo "[push] ERROR: $*" >&2; exit 1; }
note() { echo "[push] $*"; }

[ -f "$JAR" ] || JAR=/tmp/vrmc-provider.jar
[ -f "$JAR" ] || die "provider jar not found (build it with scripts/build_provider.sh, or pass a path)"
[ -s "$JAR" ] || die "provider jar is empty: $JAR"
command -v xcrun >/dev/null 2>&1 || die "xcrun not found (Xcode command line tools required)"
xcrun devicectl device copy to --help >/dev/null 2>&1 \
  || die "this devicectl has no 'device copy to' subcommand (need Xcode 15.1+ devicectl)"

SHA_LOCAL=$(shasum -a 256 "$JAR" | awk "{print \$1}")
note "jar:      $JAR"
note "sha256:   $SHA_LOCAL"
note "device:   $DEVICE"
note "container: $BUNDLE_ID  ($DEST_REL)"

if [ "${SKIP_DEVICE_CHECK:-0}" != "1" ]; then
  # Capture first: piping devicectl directly into 'grep -q' can make devicectl die of SIGPIPE,
  # which under 'set -o pipefail' would look like "device not found".
  DEVICES=$(xcrun devicectl list devices 2>/dev/null || true)
  if ! printf '%s\n' "$DEVICES" | grep -q -- "$DEVICE"; then
    die "device $DEVICE not listed by devicectl (connect/unlock it, or set DEVICE=...; SKIP_DEVICE_CHECK=1 to bypass); devicectl said: $(printf '%s' "$DEVICES" | head -2 | tr '\n' ' ')"
  fi
  note "device listed by devicectl"
fi

# devicectl 'device copy to' syntax (verified against devicectl 651.32):
#   xcrun devicectl device copy to --device <UDID> --domain-type appDataContainer \
#     --domain-identifier <bundle-id> --source <local-file> --destination <path-in-container>
# The destination directory (Documents/instances/default/mods) must already exist; it is created by
# the launcher when the instance is set up. There is no mkdir/rm subcommand in devicectl, so a
# missing directory fails with a device-side error.
# devicectl over local-network transport is flaky in practice: observed transient failures are
# "Failed to allocate RSD device" and "The connection to the remote device is no longer valid"
# (CoreDeviceError 7000). Retry like scripts/install_device.sh does.
MAX_ATTEMPTS=${MAX_ATTEMPTS:-4}
ATTEMPT=1
while :; do
  set +e
  OUT=$(xcrun devicectl device copy to \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "$JAR" \
    --destination "$DEST_REL" 2>&1)
  RC=$?
  set -e
  echo "$OUT" | sed "s/^/[push]   /"
  [ "$RC" -eq 0 ] && break
  if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
    note "copy to failed on attempt $ATTEMPT/$MAX_ATTEMPTS (transient device-tunnel error); retrying in 5s"
    ATTEMPT=$((ATTEMPT+1))
    sleep 5
    continue
  fi
  break
done
[ "$RC" -eq 0 ] || die "devicectl copy to failed (exit $RC) after $ATTEMPT attempts; if this is a missing-directory error, launch the instance once so Documents/instances/default/mods exists"
echo "$OUT" | grep -qiE "File on Device|file (copied|sent|transferred)|copied|success|Command Completed" \
  || note "WARNING: devicectl did not print an explicit success line; relying on exit code + round-trip"

if [ "$VERIFY" = "1" ]; then
  TMP="$(mktemp -d /tmp/vrmc-push.XXXXXX)"
  trap 'rm -rf "$TMP"' EXIT
  note "verifying with device copy from -> $TMP/roundtrip.jar"
  FROM_ATTEMPT=1
  while :; do
    rm -f "$TMP/roundtrip.jar"
    set +e
    FROM_OUT=$(xcrun devicectl device copy from \
      --device "$DEVICE" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --source "$DEST_REL" \
      --destination "$TMP/roundtrip.jar" 2>&1)
    FROM_RC=$?
    set -e
    echo "$FROM_OUT" | sed "s/^/[push]   /"
    [ "$FROM_RC" -eq 0 ] && [ -f "$TMP/roundtrip.jar" ] && break
    if [ "$FROM_ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
      note "copy from failed on attempt $FROM_ATTEMPT/$MAX_ATTEMPTS; retrying in 5s"
      FROM_ATTEMPT=$((FROM_ATTEMPT+1))
      sleep 5
      continue
    fi
    die "device copy from failed after $FROM_ATTEMPT attempts; cannot verify the upload"
  done
  SHA_REMOTE=$(shasum -a 256 "$TMP/roundtrip.jar" | awk "{print \$1}")
  note "remote sha256: $SHA_REMOTE"
  if [ "$SHA_REMOTE" = "$SHA_LOCAL" ]; then
    note "round-trip verification: PASS (device jar == local jar)"
  else
    die "round-trip verification FAILED: device jar sha256 $SHA_REMOTE != local $SHA_LOCAL (copy to may have been skipped: devicectl skips unmodified files)"
  fi
fi
note "done: $DEST_REL on $DEVICE"
