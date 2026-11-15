#!/bin/bash
# Guard: the Vivecraft pin compiled into the shell (SetupManager in ShellSetup.swift) must equal
# versions.env (VIVECRAFT_VERSION / VIVECRAFT_JAR_SHA256). The shell only installs a Vivecraft jar
# whose SHA-256 matches this pin, so drift here means setup would reject the release build.
# Read-only; exit 1 on drift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/versions.env"
SRC="$ROOT/runtime/native-shell/Sources/ShellSetup.swift"

swift_ver=$(sed -n 's/.*static let vivecraftVersion = "\([^"]*\)".*/\1/p' "$SRC" | head -1)
swift_name=$(sed -n 's/.*static let vivecraftFileName = "\([^"]*\)".*/\1/p' "$SRC" | head -1)
swift_sha=$(sed -n 's/.*static let vivecraftSHA256 = "\([0-9a-f]\{64\}\)".*/\1/p' "$SRC" | head -1)
want_name="vivecraft-${VIVECRAFT_VERSION}-fabric.jar"
rc=0
check() {  # label shell-value wanted-value
  if [ "$2" = "$3" ]; then echo "[pins] vivecraft $1: ${2:0:40} OK"
  else echo "[pins] vivecraft $1 drift: shell=${2:-<none>} versions.env=$3"; rc=1; fi
}
check version "$swift_ver" "$VIVECRAFT_VERSION"
check "file name" "$swift_name" "$want_name"
check sha256 "$swift_sha" "$VIVECRAFT_JAR_SHA256"
exit $rc
