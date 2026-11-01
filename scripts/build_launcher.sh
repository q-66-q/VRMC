#!/bin/bash
# Build the VRMC launcher (branded Amethyst 1.2.0) reproducibly from a prepared Amethyst 1.2.0 tree.
# Usage (one line): AME_SRC=/path/to/Amethyst-iOS-main BOOTJDK=/path/to/jdk8/bin [DEPENDS_DIR=/path/to/depends] scripts/build_launcher.sh
# Requirements: AME_SRC must be the Amethyst 1.2.0 source tree with the four submodules populated
# (Natives/external/{AFNetworking,DBNumberedSlider,MobileGlues,fishhook}); a JDK 8 boot JDK; Xcode.
# The script applies patches/*.patch, drops MobileGlues/MobileGL from payload (Vulkan/MoltenVK path)
# and produces artifacts/Payload/AngelAuraAmethyst.app. Signing/branding is a separate step (sign_ipa.sh).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AME_SRC=${AME_SRC:?set AME_SRC to the Amethyst 1.2.0 source tree}
BOOTJDK=${BOOTJDK:?set BOOTJDK to the JDK 8 bin directory}
BUILD_DIR=${BUILD_DIR:-$ROOT/.build/launcher}
JOBS=${JOBS:-$(sysctl -n hw.logicalcpu)}
DEPENDS_DIR=${DEPENDS_DIR:-}

[ -f "$AME_SRC/Makefile" ] || { echo "AME_SRC has no Makefile: $AME_SRC" >&2; exit 1; }
grep -q 'VERSION     := 1.2.0' "$AME_SRC/Makefile" || { echo "AME_SRC is not Amethyst 1.2.0 (VERSION != 1.2.0)" >&2; exit 1; }
[ -f "$AME_SRC/Natives/resources/lwjgl_versions.txt" ] || { echo "AME_SRC lacks Natives/resources/lwjgl_versions.txt (wrong tree)" >&2; exit 1; }
[ -d "$AME_SRC/Natives/resources/Frameworks/lwjgl34" ] || { echo "AME_SRC lacks Frameworks/lwjgl34 (wrong tree)" >&2; exit 1; }
for m in AFNetworking DBNumberedSlider MobileGlues fishhook; do
  [ -n "$(ls -A "$AME_SRC/Natives/external/$m" 2>/dev/null)" ] || { echo "submodule not populated: Natives/external/$m" >&2; exit 1; }
done
[ -x "$BOOTJDK/javac" ] || { echo "no javac in BOOTJDK: $BOOTJDK" >&2; exit 1; }

echo "[build] staging $AME_SRC -> $BUILD_DIR"
rm -rf "$BUILD_DIR"
rsync -a --exclude build --exclude artifacts --exclude depends "$AME_SRC/" "$BUILD_DIR/"
if [ -d "$ROOT/assets/branding" ]; then
  echo "[build] installing VRMC branding assets"
  rsync -a "$ROOT/assets/branding/" "$BUILD_DIR/Natives/Assets.xcassets/"
fi
if [ -d "$ROOT/assets/vulkan_include" ]; then
  echo "[build] installing Vulkan headers (S4a-device probe)"
  rsync -a "$ROOT/assets/vulkan_include/" "$BUILD_DIR/Natives/vulkan_include/"
fi
for p in "$ROOT"/patches/*.patch; do
  echo "[build] applying $(basename "$p")"
  patch -p1 -d "$BUILD_DIR" < "$p"
done
if [ -n "$DEPENDS_DIR" ]; then
  echo "[build] reusing cached depends from $DEPENDS_DIR"
  rsync -a "$DEPENDS_DIR/" "$BUILD_DIR/depends/"
fi
echo "[build] make payload (JOBS=$JOBS)"
make -C "$BUILD_DIR" PLATFORM=2 RELEASE=0 BOOTJDK="$BOOTJDK" JOBS="$JOBS" payload
APP="$BUILD_DIR/artifacts/Payload/AngelAuraAmethyst.app"
[ -d "$APP" ] || { echo "payload missing: $APP" >&2; exit 1; }
plutil -p "$APP/Info.plist" | grep -E 'CFBundleShortVersionString.*1\.2\.0' >/dev/null || { echo "unexpected app version" >&2; exit 1; }
echo "[build] ok: $APP"
# hash best-effort: pipefail is disabled because a transient per-file read error must not fail the build
set +o pipefail
HASH=$(cd "$APP" && find . -type f | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}')
set -o pipefail
if [ -n "${HASH:-}" ]; then echo "[build] unsigned payload tree sha256: $HASH"; else echo "[build] warning: could not compute payload tree hash" >&2; fi
