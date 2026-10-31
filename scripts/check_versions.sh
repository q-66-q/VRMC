#!/bin/bash
# check_versions.sh — verify the local toolchain and reference pins against versions.env.
# Read-only. Safe to run at any time.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/versions.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "FAIL: missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

FAILURES=0
PASSES=0

pass() { printf '  PASS  %s\n' "$1"; PASSES=$((PASSES + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
warn() { printf '  WARN  %s\n' "$1"; }
note() { printf '%s\n' "$1"; }

note "VRMC environment check ($(date '+%Y-%m-%d %H:%M:%S %z'))"
note "  root: $ROOT"
note ""

note "Toolchain"
if command -v xcodebuild >/dev/null 2>&1; then
  XCODE_ACTUAL="$(xcodebuild -version 2>/dev/null | awk '/^Xcode /{print $2}')"
  if [ "$XCODE_ACTUAL" = "$XCODE_VERSION" ]; then
    pass "Xcode $XCODE_ACTUAL (expected $XCODE_VERSION)"
  else
    fail "Xcode $XCODE_ACTUAL (expected $XCODE_VERSION)"
  fi
else
  fail "xcodebuild not found"
fi

if command -v xcrun >/dev/null 2>&1; then
  SDK_ACTUAL="$(xcrun --sdk xros --show-sdk-version 2>/dev/null || true)"
  if [ "$SDK_ACTUAL" = "$VISIONOS_SDK" ]; then
    pass "visionOS SDK $SDK_ACTUAL"
  else
    fail "visionOS SDK ${SDK_ACTUAL:-<none>} (expected $VISIONOS_SDK)"
  fi
else
  fail "xcrun not found"
fi

if command -v python3 >/dev/null 2>&1; then
  pass "python3 $(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
else
  fail "python3 not found"
fi

note ""
note "Reference pins (optional trees; skip if absent)"
VIVECRAFT_TREE="$ROOT/VivecraftMod-Multiloader-26.2"
if [ -d "$VIVECRAFT_TREE" ]; then
  check_pin() {
    local key="$1" expected="$2" file="$VIVECRAFT_TREE/gradle.properties"
    local actual
    actual="$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- || true)"
    if [ "$actual" = "$expected" ]; then
      pass "Vivecraft $key=$actual"
    else
      fail "Vivecraft $key=${actual:-<missing>} (expected $expected)"
    fi
  }
  check_pin minecraft_version "$MC_VERSION"
  check_pin mod_version "1.3.15"
  check_pin java_version "$MC_JAVA_MAJOR"
  check_pin fabric_loader_version "$FABRIC_LOADER"
else
  warn "reference tree not present: $VIVECRAFT_TREE"
fi

AMETHYST_TREE="$ROOT/Amethyst-iOS-main"
if [ -d "$AMETHYST_TREE" ]; then
  if [ -f "$AMETHYST_TREE/Natives/JavaLauncher.m" ]; then
    pass "Amethyst reference tree present (JavaLauncher.m)"
  else
    warn "Amethyst tree present but JavaLauncher.m missing (incomplete extraction?)"
  fi
else
  warn "reference tree not present: $AMETHYST_TREE"
fi

note ""
note "Status"
note "  JRE build:      $JRE_BUILD_STATUS (target OpenJDK $OPENJDK_VERSION)"
note "  JIT protocol:   $JIT_PROTOCOL"
note "  Graphics path:  $GRAPHICS_NOTE"
note ""
note "Summary: $PASSES passed, $FAILURES failed"

if [ "$FAILURES" -gt 0 ]; then
  exit 1
fi
