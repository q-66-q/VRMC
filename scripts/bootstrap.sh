#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source versions.env

if [[ "${1:-}" == "--pc" ]]; then
  cat <<'EOF'
Windows PC prerequisites (run PowerShell as needed):
  - Windows 11 24H2+, NVIDIA RTX 4070+ with current driver
  - Steam + SteamVR, Minecraft Java 1.21.11, Fabric Loader 0.20.1, Vivecraft 1.21.11-1.3.15
  - Visual Studio 2022 (Desktop C++), Windows SDK 10.0.26100+
  - CMake 3.24+ and Git
  - A 5 GHz/6E LAN and a wired PC connection are strongly recommended
Install SteamVR and the Minecraft/Vivecraft profile manually; VRMC never bundles them.
EOF
  exit 0
fi

fail=0
check() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "MISSING: $1 ($2)" >&2
    fail=1
  else
    echo "OK: $1"
  fi
}

check swift "Xcode command line tools"
check xcodebuild "Xcode 27.1"
check xcodegen "brew install xcodegen"
check cmake "brew install cmake"
check python3 "Python 3"
check git "Git"
check ffmpeg "brew install ffmpeg (mock fixture generation)"

if [[ $fail -ne 0 ]]; then
  echo "Install the missing tools, then rerun scripts/bootstrap.sh" >&2
  exit 1
fi

echo "Toolchain:"
swift --version | head -1
xcodebuild -version | head -2
cmake --version | head -1
python3 --version

if ! xcrun simctl list runtimes 2>/dev/null | grep -q "visionOS 27"; then
  echo "WARNING: visionOS 27 simulator runtime not found; install it in Xcode Settings." >&2
fi

echo "Bootstrap checks passed."
echo "Next: ./scripts/test_all.sh"
