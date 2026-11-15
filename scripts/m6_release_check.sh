#!/bin/bash
# M6 release readiness check (host-only; no device). Fails closed on missing legal/source artifacts,
# tracked Minecraft binaries, or an unusable release manifest.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0
ok() { echo "[release-check] OK   $*"; }
bad() { echo "[release-check] FAIL $*"; fail=1; }

# 1. Required artifacts.
for f in LICENSE provider/LICENSE THIRD_PARTY_NOTICES.md PRIVACY.md versions.env README.md \
         SOURCE_OFFER.md docs/mvp/M6_ACCEPTANCE.md docs/mvp/M6_PLAN.md docs/mvp/M5_PLAN.md; do
  [ -e "$f" ] && ok "present: $f" || bad "missing: $f"
done

# 2. Source publication / replaceable provider.
for d in provider/src runtime/native-shell/Sources bridge/src launcher; do
  [ -d "$d" ] && ok "source dir: $d" || bad "missing source dir: $d"
done
[ -f provider/LICENSE ] && ok "provider license present" || bad "provider license missing"

# 3. No Minecraft binaries/assets in git.
tracked_bad=$(git ls-files | grep -Ei '\.(jar|ipa|minecraft|mcassets|assets)$' \
  | grep -Ev '^provider/tests/fixtures/' || true)
if [ -z "$tracked_bad" ]; then ok "no tracked Minecraft jars/IPA/assets"; else bad "tracked binaries: $tracked_bad"; fi

# 4. Privacy usage strings in the native app plist generation.
if grep -q "NSHandsTrackingUsageDescription" scripts/build_launcher.sh \
   && grep -q "NSWorldSensingUsageDescription" scripts/build_launcher.sh; then
  ok "hand/world tracking usage strings generated"
else
  bad "tracking usage strings missing from scripts/build_launcher.sh"
fi

# 4b. Soak harness dry-run (tooling/plan present; device soak remains an acceptance gate).
if scripts/m6_soak_harness.sh --dry-run >/dev/null 2>&1; then
  ok "soak harness dry-run"
else
  bad "soak harness dry-run failed"
fi

# 4c. Provider jar reproducibility (two independent builds must be byte-identical).
REPRO_LOG=$(mktemp -t vrmc-repro-check).log
if scripts/m6_reproducibility_check.sh > "$REPRO_LOG" 2>&1; then
  ok "provider jar reproducible ($(grep -o 'provider_sha256=[0-9a-f]*' "$REPRO_LOG" | head -1))"
else
  bad "provider jar is not reproducible (see $REPRO_LOG)"
fi
rm -f "$REPRO_LOG"

# 4d. Launcher settings keys must all be recognized by provider source (UI/provider drift guard).
if scripts/check_settings_keys.sh >/tmp/vrmc-settings-keys.log 2>&1; then
  ok "launcher settings keys recognized ($(grep -o 'checked=[0-9]*' /tmp/vrmc-settings-keys.log || true))"
else
  cat /tmp/vrmc-settings-keys.log; bad "launcher/provider settings key drift"
fi

# 4e. Launcher status reads must all be written by the provider status builder.
if scripts/check_status_fields.sh >/tmp/vrmc-status-fields.log 2>&1; then
  ok "launcher status fields written by provider ($(grep -o 'checked=[0-9]*' /tmp/vrmc-status-fields.log || true))"
else
  cat /tmp/vrmc-status-fields.log; bad "launcher/provider status field drift"
fi

# 4f. Launcher auto-provisioning Vivecraft pin (shell built-in) must match versions.env.
if scripts/check_provisioning_pins.sh >/tmp/vrmc-provisioning-pins.log 2>&1; then
  ok "provisioning Vivecraft pin matches versions.env"
else
  cat /tmp/vrmc-provisioning-pins.log; bad "launcher Vivecraft pin drift (ShellSetup.swift vs versions.env)"
fi

# 5. Release manifest can be generated (dirty tree is reported, not a release-blocker for this check).
manifest=$(mktemp -t vrmc-manifest).txt
if scripts/m6_release_manifest.sh "$manifest" >/dev/null 2>&1 || [ -s "$manifest" ]; then
  for field in source_commit source_branch product platform mc_version fabric_loader vivecraft \
               provider_jar_sha256 bridge_dylib_sha256 license_app license_provider third_party_notices privacy; do
    grep -q "^${field}=" "$manifest" && ok "manifest field: $field" || bad "manifest missing field: $field"
  done
  if grep -q '^dirty_tree=YES' "$manifest"; then
    echo "[release-check] NOTE working tree is dirty; regenerate the final manifest from a clean release commit"
  else
    ok "working tree clean for manifest"
  fi
else
  bad "release manifest generation failed"
fi
rm -f "$manifest"

# 6. Docs/evidence gate reminder (not machine-checkable here).
echo "[release-check] NOTE AC-1..AC-6/K1..K6 device evidence and VERIFY sign-off are separate gates."

if [ "$fail" != "0" ]; then echo "[release-check] RESULT: FAIL"; exit 1; fi
echo "[release-check] RESULT: PASS (host readiness; device acceptance still required)"
