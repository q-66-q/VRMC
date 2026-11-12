#!/bin/bash
# Build the VRMC Vision provider Fabric mod jar (Java 25) without Gradle.
# Reconstructed from provider/HOST_HARNESS.md; the compile classpath is discovered from the local
# Gradle caches + the prebuilt Vivecraft 26.2 tree, so no network access and no Gradle run is needed.
#
# Usage:  scripts/build_provider.sh
# Output: ${OUT_DIR:-/tmp/vrmc-provider-build}/vrmc-provider.jar (prints size + sha256)
#
# Env overrides (all optional):
#   JAVAC                   javac binary (default: JAVA_HOME, then temurin-25, then /usr/libexec/java_home -v 25)
#   JAVA_HOME               JDK home dir
#   OUT_DIR                 build dir (default /tmp/vrmc-provider-build)
#   MC_JAR                  Minecraft 26.2 official-mapped client jar
#   VIVECRAFT_CLASSES       Vivecraft common compiled classes dir
#   VIVECRAFT_STUBS_JAR     Vivecraft stubs jar
#   JOML_JAR / MIXIN_JAR / ASM_JAR / SLF4J_JAR   explicit dependency jars
#   GRADLE_CACHE            Gradle cache root (default ~/.gradle/caches)
#   EXTRA_CP                extra compile-only classpath entries appended last
#   VERBOSE=1               echo the resolved classpath entries and javac version
#
# Reproducible jar: entry timestamps are fixed via jar --date, so the sha256 below is a content hash
# across rebuilds with the same JDK/payload (release manifests/integrity checks rely on this).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-/tmp/vrmc-provider-build}"
GRADLE_CACHE="${GRADLE_CACHE:-$HOME/.gradle/caches}"

die() { echo "[provider] ERROR: $*" >&2; exit 1; }
note() { echo "[provider] $*"; }

# --- resolve the JDK -------------------------------------------------------
if [ -n "${JAVAC:-}" ]; then
  :
elif [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javac" ]; then
  JAVAC="$JAVA_HOME/bin/javac"
elif [ -x /Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac ]; then
  JAVAC=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac
elif [ -x /Library/Java/JavaVirtualMachines/jdk-25.jdk/Contents/Home/bin/javac ]; then
  JAVAC=/Library/Java/JavaVirtualMachines/jdk-25.jdk/Contents/Home/bin/javac
else
  JHOME=$(/usr/libexec/java_home -v 25 2>/dev/null || true)
  [ -n "$JHOME" ] && [ -x "$JHOME/bin/javac" ] || die "no JDK 25 javac found (set JAVAC or JAVA_HOME)"
  JAVAC="$JHOME/bin/javac"
fi
JAVA_HOME="$(cd "$(dirname "$JAVAC")/.." && pwd)"
JAR_TOOL="$(dirname "$JAVAC")/jar"
[ -x "$JAR_TOOL" ] || die "jar tool not found next to javac: $JAR_TOOL"

# --- resolve dependencies --------------------------------------------------
MC_JAR="${MC_JAR:-}"
if [ -z "$MC_JAR" ]; then
  for c in "$GRADLE_CACHE/neoformruntime/artifacts/minecraft_26.2_client.jar" $GRADLE_CACHE/neoformruntime/artifacts/minecraft_*_client.jar; do
    [ -f "$c" ] && { MC_JAR="$c"; break; }
  done
fi
[ -n "$MC_JAR" ] && [ -f "$MC_JAR" ] || die "Minecraft 26.2 official-mapped client jar not found (set MC_JAR); expected $GRADLE_CACHE/neoformruntime/artifacts/minecraft_26.2_client.jar"

VIVECRAFT_CLASSES="${VIVECRAFT_CLASSES:-$ROOT/VivecraftMod-Multiloader-26.2/common/build/classes/java/main}"
[ -d "$VIVECRAFT_CLASSES/org/vivecraft" ] || die "Vivecraft compiled classes missing: $VIVECRAFT_CLASSES (run: cd VivecraftMod-Multiloader-26.2 && ./gradlew :common:classes)"
VIVECRAFT_STUBS_JAR="${VIVECRAFT_STUBS_JAR:-$ROOT/VivecraftMod-Multiloader-26.2/stubs/build/libs/vivecraft-1.0-stubs.jar}"

JOML_JAR="${JOML_JAR:-}"
[ -n "$JOML_JAR" ] || JOML_JAR=$(find "$GRADLE_CACHE/modules-2" -path "*org.joml/joml/1.10.8/*" -name "joml-1.10.8.jar" -type f 2>/dev/null | grep -v sources | head -1 || true)
[ -n "$JOML_JAR" ] || JOML_JAR=$(find "$GRADLE_CACHE/modules-2" -path "*org.joml/joml/*" -name "joml-*.jar" -type f 2>/dev/null | grep -v sources | sort | tail -1 || true)
[ -n "$JOML_JAR" ] && [ -f "$JOML_JAR" ] || die "joml jar not found in $GRADLE_CACHE/modules-2 (set JOML_JAR)"

# Mixin: the reference jar (/tmp/vrmc-provider.jar, proven on device in EV-0086) was compiled against
# a Mixin whose @Redirect.at() returns a single At (org.spongepowered:mixin:0.8.7 or
# sponge-mixin:0.17.3). sponge-mixin 0.17.5 (what Fabric Loader 0.20.1 runs on-device) declares
# At[] at(); compiling against it changes only the annotation encoding of VRStateMixin.class, which
# is why 0.8.7 is preferred here. Override MIXIN_JAR if the provider source starts using multi-@At.
MIXIN_JAR="${MIXIN_JAR:-}"
if [ -z "$MIXIN_JAR" ]; then
  MIXIN_JAR=$(find "$GRADLE_CACHE/modules-2" -path "*org.spongepowered/mixin/0.8.7/*" -name "mixin-0.8.7.jar" -type f 2>/dev/null | grep -v sources | head -1 || true)
  [ -n "$MIXIN_JAR" ] || MIXIN_JAR=$(find "$GRADLE_CACHE/modules-2" -path "*net.fabricmc/sponge-mixin/0.17.3*" -name "sponge-mixin-*.jar" -type f 2>/dev/null | grep -v sources | head -1 || true)
  [ -n "$MIXIN_JAR" ] || MIXIN_JAR=$(find "$GRADLE_CACHE/modules-2" -path "*net.fabricmc/sponge-mixin/*" -name "sponge-mixin-*.jar" -type f 2>/dev/null | grep -v sources | sort | tail -1 || true)
fi
[ -n "$MIXIN_JAR" ] && [ -f "$MIXIN_JAR" ] || die "mixin jar not found in $GRADLE_CACHE/modules-2 (set MIXIN_JAR)"

ASM_JAR="${ASM_JAR:-}"
[ -n "$ASM_JAR" ] || ASM_JAR=$(find "$GRADLE_CACHE/modules-2" -path "*org.ow2.asm/asm/*" -name "asm-9*.jar" -type f 2>/dev/null | grep -v sources | sort -V | tail -1 || true)
[ -n "$ASM_JAR" ] && [ -f "$ASM_JAR" ] || die "asm jar not found in $GRADLE_CACHE/modules-2 (set ASM_JAR)"

SLF4J_JAR="${SLF4J_JAR:-}"
[ -n "$SLF4J_JAR" ] || SLF4J_JAR=$(find "$GRADLE_CACHE/modules-2" -path "*org.slf4j/slf4j-api/2.0.17/*" -name "slf4j-api-2.0.17.jar" -type f 2>/dev/null | grep -v sources | head -1 || true)
[ -n "$SLF4J_JAR" ] || SLF4J_JAR=$(find "$GRADLE_CACHE/modules-2" -path "*org.slf4j/slf4j-api/*" -name "slf4j-api-*.jar" -type f 2>/dev/null | grep -v sources | sort -V | tail -1 || true)
[ -n "$SLF4J_JAR" ] && [ -f "$SLF4J_JAR" ] || die "slf4j-api jar not found in $GRADLE_CACHE/modules-2 (set SLF4J_JAR)"

CP="$MC_JAR:$VIVECRAFT_CLASSES:$JOML_JAR:$MIXIN_JAR:$ASM_JAR:$SLF4J_JAR"
[ -f "$VIVECRAFT_STUBS_JAR" ] && CP="$CP:$VIVECRAFT_STUBS_JAR"
# EXTRA_CP: extra compile-only entries (e.g. Fabric API interface stubs when MC_JAR is a Loom
# merged jar with injected interfaces instead of the plain NeoForm client jar).
[ -n "${EXTRA_CP:-}" ] && CP="$CP:$EXTRA_CP"

# --- compile + package -----------------------------------------------------
SOURCES=$(find "$ROOT/provider/src/main/java" -name "*.java" | sort)
[ -n "$SOURCES" ] || die "no provider sources under $ROOT/provider/src/main/java"

note "javac:   $JAVAC"
note "out:     $OUT_DIR"
note "mixin:   $MIXIN_JAR"
note "mc:      $MC_JAR"
note "vivecraft classes: $VIVECRAFT_CLASSES"
if [ "${VERBOSE:-0}" = "1" ]; then
  note "classpath:"
  printf "%s\n" "$CP" | tr ":" "\n" | sed "s/^/  - /"
  "$JAVAC" -version 2>&1 | sed "s/^/  /"
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/classes" "$OUT_DIR/stage"
"$JAVAC" -cp "$CP" -d "$OUT_DIR/classes" $SOURCES || die "javac failed (see errors above)"

# Package exactly like provider/HOST_HARNESS.md: resources at the jar root, then the class tree,
# then 'jar cf <jar> .' from the staged directory.
mkdir -p "$OUT_DIR/stage"
cp -R "$ROOT/provider/src/main/resources/." "$OUT_DIR/stage/"
cp -R "$OUT_DIR/classes/." "$OUT_DIR/stage/"

JAR="$OUT_DIR/vrmc-provider.jar"
REPRO_TIMESTAMP="${REPRO_TIMESTAMP:-2024-01-01T00:00:00Z}"
rm -f "$JAR"
( cd "$OUT_DIR/stage" && "$JAR_TOOL" --create --file "$JAR" --date="$REPRO_TIMESTAMP" -C . . ) \
  || die "jar packaging failed"

# --- verify ----------------------------------------------------------------
for entry in fabric.mod.json vrmc.mixins.json dev/vrmc/provider/VisionVR.class \
             dev/vrmc/provider/VisionRenderer.class dev/vrmc/provider/bridge/VrmcBridge.class \
             dev/vrmc/provider/mixin/VRStateMixin.class; do
  "$JAR_TOOL" tf "$JAR" | grep -qx "$entry" || die "jar is missing $entry"
done
JAR_SIZE=$(wc -c < "$JAR" | tr -d " ")
NCLASS=$(find "$OUT_DIR/classes" -name "*.class" | wc -l | tr -d " ")
SHA=$(shasum -a 256 "$JAR" | awk "{print \$1}")
printf "%s" "$CP" > "$OUT_DIR/classpath.txt"

note "compiled $NCLASS class files from $(printf "%s\n" "$SOURCES" | wc -l | tr -d " ") sources"
note "jar:     $JAR"
note "size:    $JAR_SIZE bytes"
note "sha256:  $SHA"
note "classpath recorded in $OUT_DIR/classpath.txt"
echo "$JAR"
