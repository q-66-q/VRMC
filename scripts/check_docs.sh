#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required=(
  AGENT.md VERIFY.md README.md LICENSE THIRD_PARTY_NOTICES.md versions.env
  docs/feasibility/FEASIBILITY_AUDIT.md
  docs/plan/PROJECT_PLAN.md
  docs/adr/0001-remote-vivecraft-runtime.md
  docs/adr/0002-video-path-vivecraft-dual-mirror.md
  docs/adr/0003-hand-input-as-virtual-knuckles.md
  docs/adr/0004-transport-and-time.md
  docs/adr/0005-compositor-and-reprojection.md
  docs/adr/0006-licensing-and-distribution.md
  docs/architecture/HAND_MAPPING.md
  docs/architecture/STREAMING.md
  protocol/PROTOCOL.md
  client/Package.swift
  bridge/CMakeLists.txt
  tools/mock_host/mock_host.py
)
for file in "${required[@]}"; do
  [[ -f "$file" ]] || { echo "MISSING required file: $file" >&2; exit 1; }
done

python3 - <<'PY'
from pathlib import Path
import re

root = Path('.')
missing = []
for path in list(root.glob('*.md')) + list((root / 'docs').rglob('*.md')) + list((root / 'protocol').rglob('*.md')):
    text = path.read_text(encoding='utf-8')
    for match in re.finditer(r'\[[^\]]+\]\(([^)]+)\)', text):
        target = match.group(1).split('#')[0]
        if not target or '://' in target or target.startswith('mailto:'):
            continue
        candidate = (path.parent / target).resolve()
        if not candidate.exists():
            missing.append(f"{path}: {target}")
if missing:
    print("Broken local markdown links:")
    print("\n".join(missing))
    raise SystemExit(1)
print("required files and local links OK")
PY

if grep -R "NOT RUN" VERIFY.md >/dev/null; then
  echo "NOTE: VERIFY.md still contains NOT RUN acceptance items (expected until hardware evidence)."
fi
echo "Docs checks passed."
