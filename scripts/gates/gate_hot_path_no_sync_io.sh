#!/usr/bin/env bash
# gate_hot_path_no_sync_io.sh — block heavy synchronous work in agent hot paths.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - "$repo_root" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
hot_paths = [
    "scripts/inbox_watcher.sh",
    "scripts/inbox_write.sh",
    "scripts/bulletin_write.sh",
    "scripts/report_field_set.sh",
    "scripts/gates/gate_report_format.sh",
    "scripts/gates/gate_gunshi_report_precheck.sh",
    "scripts/cmd_save.sh",
    "scripts/cmd_complete_gate.sh",
    "scripts/deploy_task.sh",
    "scripts/ninja_monitor.sh",
]

violations: list[str] = []

def is_comment_or_doc(line: str) -> bool:
    stripped = line.strip()
    return (
        not stripped
        or stripped.startswith("#")
        or stripped.startswith("echo ")
        or stripped.startswith("printf ")
        or "必須:" in stripped
        or "reason:" in stripped
        or "cause_checked:" in stripped
        or "evidence:" in stripped
    )

for rel in hot_paths:
    path = root / rel
    if not path.exists():
        continue
    for lineno, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if is_comment_or_doc(line):
            continue
        stripped = line.strip()
        if "memory_db_live_insert.py" in stripped and "memory_db_live_insert_async.py" not in stripped:
            violations.append(f"{rel}:{lineno}: direct memory_db_live_insert.py in hot path")
        if ("semantic_search.sh" in stripped or "causal_backlinks.sh" in stripped) and "timeout " not in stripped and "&" not in stripped:
            if re.search(r"(local|readonly)?\s*[A-Za-z_][A-Za-z0-9_]*=.*(semantic_search|causal_backlinks)\.sh", stripped):
                continue
            violations.append(f"{rel}:{lineno}: semantic/causal call without timeout/background")
        if "prompt_state_inject.sh" in stripped and rel == "scripts/inbox_watcher.sh":
            violations.append(f"{rel}:{lineno}: prompt_state_inject must not run synchronously in inbox_watcher")
        if re.search(r"\bgit (log|diff-tree|status)\b", stripped) and "timeout " not in stripped:
            if rel.endswith("ninja_monitor.sh") and "git status --porcelain -uno" in stripped:
                continue
            if "grep -q" in stripped or stripped.startswith("emit("):
                continue
            violations.append(f"{rel}:{lineno}: git heavy command without timeout")

if violations:
    print("BLOCK: heavy synchronous I/O detected in agent hot paths.", file=sys.stderr)
    print("Use async queue, bounded timeout, cached read, or move work to a non-hot gate/daemon.", file=sys.stderr)
    for item in violations:
        print(item, file=sys.stderr)
    raise SystemExit(1)

print("OK: hot paths have no unbounded heavy synchronous I/O")
PY
