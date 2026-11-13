#!/bin/bash
# Build a durable device-session handoff package from the staged M8 candidate.
#
# The staged app and provider jar live in /tmp (volatile). This script validates them against
# export/m8-device-candidate.txt and copies them into the workspace (export/m8-device-package/) with
# checksums, the candidate manifest and a README, optionally as a zip, so a later session or a human
# operator can install without depending on /tmp.
#
# Usage:
#   scripts/m8_device_package.sh --check            # validate only, no writes
#   scripts/m8_device_package.sh                    # build export/m8-device-package/
#   scripts/m8_device_package.sh --replace          # rebuild an existing package
#   scripts/m8_device_package.sh --zip              # also create export/m8-device-package.zip
#
# Env: APP (default /tmp/VRMC-native-m8.app), PROVIDER_JAR (default /tmp/vrmc-provider-build/vrmc-provider.jar),
#      OUT (default <repo>/export/m8-device-package), MANIFEST (default <repo>/export/m8-device-candidate.txt)
#
# Exit: 0 PASS / 2 usage or validation error / 3 package exists without --replace.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/local_env.sh"   # per-developer device/team/identity (scripts/local.env)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${APP:-/tmp/VRMC-native-m8.app}"
PROVIDER_JAR="${PROVIDER_JAR:-/tmp/vrmc-provider-build/vrmc-provider.jar}"
OUT="${OUT:-$ROOT/export/m8-device-package}"
MANIFEST="${MANIFEST:-$ROOT/export/m8-device-candidate.txt}"
ZIP="${OUT}.zip"
CHECK=0
ZIPIT=0
REPLACE=0
say() { echo "[m8-package] $*"; }
die() { echo "[m8-package] ERROR: $*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --zip) ZIPIT=1; shift ;;
    --replace) REPLACE=1; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument '$1' (see --help)" ;;
  esac
done

[ -d "$APP" ] || die "app bundle not found: $APP (stage it first; see export/m8-device-candidate.txt)"
[ -f "$PROVIDER_JAR" ] || die "provider jar not found: $PROVIDER_JAR (scripts/build_provider.sh)"
[ -f "$MANIFEST" ] || die "candidate manifest not found: $MANIFEST"

want_app=$(grep -m1 '^app_tree_sha256=' "$MANIFEST" | cut -d= -f2)
want_provider=$(grep -m1 '^provider_jar_sha256=' "$MANIFEST" | cut -d= -f2)
want_provider_bytes=$(grep -m1 '^provider_jar_bytes=' "$MANIFEST" | cut -d= -f2)

say "app:          $APP"
say "provider jar: $PROVIDER_JAR"
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || die "codesign --verify --deep --strict FAILED for $APP"
say "codesign:     deep/strict PASS"
PROFILE_INFO=""
if [ -x "$ROOT/scripts/profile_expiry.sh" ]; then
  profile_warn=$(mktemp /tmp/vrmc-profile-warn.XXXXXX)
  PROFILE_INFO=$("$ROOT/scripts/profile_expiry.sh" "$APP" --warn-days 7 2>"$profile_warn") || {
    cat "$profile_warn" >&2; rm -f "$profile_warn"
    die "the embedded provisioning profile is expired/unreadable; re-sign with a fresh profile first (see docs/mvp/M8_DEVICE_RUN.md)"
  }
  rm -f "$profile_warn"
  say "$PROFILE_INFO"
fi
have_app=$("$ROOT/scripts/app_tree_sha256.sh" "$APP" 2>/dev/null || true)
have_provider=$(shasum -a 256 "$PROVIDER_JAR" | awk '{print $1}')
have_provider_bytes=$(stat -f%z "$PROVIDER_JAR")
say "app tree sha: $have_app (manifest: ${want_app:-none})"
say "provider sha: $have_provider (manifest: ${want_provider:-none})"
[ -n "$want_app" ] && [ "$have_app" = "$want_app" ] || die "app tree hash != recorded candidate (rebuild/re-stage or update the manifest)"
[ -n "$want_provider" ] && [ "$have_provider" = "$want_provider" ] || die "provider jar hash != recorded candidate"
[ -n "$want_provider_bytes" ] && [ "$have_provider_bytes" = "$want_provider_bytes" ] || die "provider jar size != recorded candidate"
say "validation:   PASS (matches export/m8-device-candidate.txt)"
if [ "$CHECK" = "1" ]; then say "check-only:   nothing written"; exit 0; fi

if [ -e "$OUT" ] && [ "$REPLACE" != "1" ]; then
  die "$OUT exists (use --replace to rebuild it)"
fi
rm -rf "$OUT"; mkdir -p "$OUT"

say "copying app bundle (ditto) ..."
ditto "$APP" "$OUT/VRMC-native-m8.app" || die "ditto failed"
codesign --verify --deep --strict "$OUT/VRMC-native-m8.app" >/dev/null 2>&1 \
  || die "copied app failed codesign verify"
copy_app=$("$ROOT/scripts/app_tree_sha256.sh" "$OUT/VRMC-native-m8.app" 2>/dev/null || true)
[ "$copy_app" = "$have_app" ] || die "copied app tree hash mismatch ($copy_app != $have_app)"
say "copied app:   codesign PASS, tree sha matches"

cp "$PROVIDER_JAR" "$OUT/vrmc-provider.jar"
cp "$MANIFEST" "$OUT/m8-device-candidate.txt"
copy_provider=$(shasum -a 256 "$OUT/vrmc-provider.jar" | awk '{print $1}')
[ "$copy_provider" = "$have_provider" ] || die "copied provider jar hash mismatch"
say "copied jar:   sha matches"

cat > "$OUT/SHA256SUMS" <<EOF
# M8 durable device-session package - $(date -u +%Y-%m-%dT%H:%M:%SZ)
provider_jar $have_provider vrmc-provider.jar
app_tree $have_app VRMC-native-m8.app
EOF

cat > "$OUT/README.md" <<'README_EOF'
# M8 device-session package

Durable copy of the staged M8 device candidate (the originals lived in `/tmp`). Not device-verified:
A6–A9 are still NOT RUN.

| item | value |
|---|---|
| bundle id | `dev.vrmc.vrmc` (version 1.2.0) |
| app tree sha256 | `__APP_TREE__` |
| provider jar sha256 | `__PROVIDER_SHA__` (`__PROVIDER_BYTES__` bytes) |
| built | see `m8-device-candidate.txt` (build date/hashes + install/tuning/rollback) |
| codesign | `codesign --verify --deep --strict` PASS (Apple Development, D1 provisioned) |
| profile | __PROFILE_INFO__ |

## Install / run (from the repository checkout)

```bash
DEVICE=<device-udid> APP="$(pwd)/export/m8-device-package/VRMC-native-m8.app" \
  scripts/install_device.sh "$APP" dev.vrmc.vrmc
DEVICE=<device-udid> BUNDLE_ID=dev.vrmc.vrmc \
  scripts/push_provider_jar.sh "$(pwd)/export/m8-device-package/vrmc-provider.jar"
# or, in one command (validates this manifest, installs and pushes):
APP="$(pwd)/export/m8-device-package/VRMC-native-m8.app" \
PROVIDER_JAR="$(pwd)/export/m8-device-package/vrmc-provider.jar" \
  scripts/m8_device_session.sh prepare
```

Then: StikDebug JIT → launch VRMC → Play → immersive → play 3–5 min (menus + distant geometry) →
Quit Game → `scripts/m8_device_session.sh collect`.

Tuning without relaunch: `scripts/push_m8_render_config.sh --eye-scale … --target-hz 120 --sharpening … --content-first on`
(next launch: `--world-supersample 1.44`). Full runbook: `docs/mvp/M8_DEVICE_RUN.md`.

## Records

- `m8-device-candidate.txt` — build identity, install/tuning/rollback commands.
- `SHA256SUMS` — checksums of this package.
- Evidence: VERIFY.md M8 evidence (EV-0268…EV-0283) and `docs/mvp/M8_PLAN.md`.
README_EOF
python3 - "$OUT/README.md" "$have_app" "$have_provider" "$have_provider_bytes" <<'PY' || die "README placeholder substitution failed"
import sys
path, app_tree, provider, provider_bytes = sys.argv[1:5]
text = open(path).read()
text = text.replace("__APP_TREE__", app_tree).replace("__PROVIDER_SHA__", provider).replace("__PROVIDER_BYTES__", provider_bytes)
open(path, "w").write(text)
PY
python3 - "$OUT/README.md" "$PROFILE_INFO" <<'PY' || die "README profile substitution failed"
import sys
path, info = sys.argv[1], sys.argv[2] or "unknown (no profile check)"
text = open(path).read().replace("__PROFILE_INFO__", info)
open(path, "w").write(text)
PY
say "wrote README.md and SHA256SUMS"

if [ "$ZIPIT" = "1" ]; then
  say "creating zip (this can take a minute) ..."
  rm -f "$ZIP"
  ditto -c -k --keepParent "$OUT" "$ZIP" || die "ditto zip failed"
  zip_sha=$(shasum -a 256 "$ZIP" | awk '{print $1}')
  zip_bytes=$(stat -f%z "$ZIP")
  say "zip:          $ZIP ($zip_bytes bytes, sha256 $zip_sha)"
fi

say "PACKAGE PASS: $OUT"
say "next: install from the package (see $OUT/README.md), then scripts/m8_device_session.sh collect"
