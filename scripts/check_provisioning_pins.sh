#!/bin/bash
# Guard: the Vivecraft pin compiled into the shell (ModProvisioningManifest.builtIn) must equal
# versions.env (VIVECRAFT_VERSION / VIVECRAFT_JAR_SHA256). Read-only; exit 1 on drift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/versions.env"
SRC="$ROOT/runtime/native-shell/Sources/ModProvisioner.swift"

swift_name=$(sed -n 's/.*vivecraftFileName: "\([^"]*\)".*/\1/p' "$SRC" | head -1)
swift_sha=$(sed -n 's/.*vivecraftSha256: "\([0-9a-f]\{64\}\)".*/\1/p' "$SRC" | head -1)
want_name="vivecraft-${VIVECRAFT_VERSION}-fabric.jar"
rc=0
if [ "$swift_name" = "$want_name" ]; then
  echo "[pins] vivecraft file name: $swift_name OK"
else
  echo "[pins] vivecraft file name drift: shell=$swift_name versions.env=$want_name"; rc=1
fi
if [ "$swift_sha" = "$VIVECRAFT_JAR_SHA256" ]; then
  echo "[pins] vivecraft sha256: ${swift_sha:0:12}… OK"
else
  echo "[pins] vivecraft sha256 drift: shell=${swift_sha:-<none>} versions.env=$VIVECRAFT_JAR_SHA256"; rc=1
fi
exit $rc
