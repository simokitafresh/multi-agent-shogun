#!/usr/bin/env bash
set -euo pipefail

# Hook comments may keep provenance such as cmd IDs, lesson IDs, and dates.
# Runtime hook code/output must state invariants, not incident-specific patches.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK_DIR="$ROOT_DIR/.claude/hooks"

if [ ! -d "$HOOK_DIR" ]; then
    echo "OK: hook directory not found"
    exit 0
fi

violations="$(
python3 - "$HOOK_DIR" <<'PY'
from pathlib import Path
import re
import sys

hook_dir = Path(sys.argv[1])
pattern = re.compile(r"(cmd_[0-9]{3,}|20[0-9]{2}-[0-9]{2}-[0-9]{2}|LS-A[0-9]+|LS[0-9]+|LG[0-9]+|LK[0-9]+|GP-[0-9]+)")

for path in sorted(hook_dir.glob("*.sh")):
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        continue
    for lineno, line in enumerate(lines, 1):
        stripped = line.lstrip()
        if not stripped or stripped.startswith("#"):
            continue
        if pattern.search(line):
            rel = path.relative_to(hook_dir.parents[1])
            print(f"{rel}:{lineno}:{line}")
PY
)"

if [ -n "$violations" ]; then
    echo "BLOCK: runtime hook code contains incident IDs/dates. Keep provenance in comments; keep runtime output invariant-based." >&2
    printf '%s\n' "$violations" >&2
    exit 1
fi

echo "OK: runtime hook incident ID/date hits = 0"
