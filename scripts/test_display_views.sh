#!/bin/bash
# Offline validation of the macstream-style display-view frustum plumbing (no device required).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JAR="${JOML_JAR:-$HOME/Library/Application Support/minecraft/libraries/org/joml/joml/1.10.8/joml-1.10.8.jar}"
[ -f "$JAR" ] || { echo "JOML jar not found: $JAR" >&2; exit 1; }
OUT=$(mktemp -d)
/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/javac -cp "$JAR" -d "$OUT" \
  "$ROOT/scripts/tests/DisplayViewsTest.java"
/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home/bin/java -cp "$JAR:$OUT" DisplayViewsTest
