#!/usr/bin/env bash
# gate_hot_path_no_sync_io.sh — block heavy synchronous work in agent hot paths.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Fast path: mtime cache — skip Python when hot_paths are unchanged.
# Caches both OK and BLOCK results; invalidated on any hot_path file change.
_HPNSI_CACHE="${TMPDIR:-/tmp}/gate_hpnsi_cache"
_hot_paths=(
    "scripts/inbox_watcher.sh"
    "scripts/inbox_write.sh"
    "scripts/bulletin_write.sh"
    "scripts/report_field_set.sh"
    "scripts/gates/gate_report_format.sh"
    "scripts/gates/gate_gunshi_report_precheck.sh"
    "scripts/cmd_save.sh"
    "scripts/cmd_complete_gate.sh"
    "scripts/deploy_task.sh"
    "scripts/ninja_monitor.sh"
)

_existing_paths=()
for _rel in "${_hot_paths[@]}"; do
    [[ -f "$repo_root/$_rel" ]] && _existing_paths+=("$repo_root/$_rel")
done

_max_mtime=""
if [[ ${#_existing_paths[@]} -gt 0 ]]; then
    _max_mtime=$(stat -c '%Y' "${_existing_paths[@]}" 2>/dev/null | sort -rn | head -1)
    if [[ -f "$_HPNSI_CACHE" ]]; then
        IFS=' ' read -r _c_mtime _c_exit <<<"$(head -1 "$_HPNSI_CACHE" 2>/dev/null)" || true
        if [[ "${_c_mtime:-}" == "$_max_mtime" && -n "${_c_exit:-}" ]]; then
            if [[ "${_c_exit}" -eq 0 ]]; then
                tail -n +2 "$_HPNSI_CACHE"
            else
                tail -n +2 "$_HPNSI_CACHE" >&2
            fi
            exit "${_c_exit}"
        fi
    fi
fi

# Full Python check: capture stderr to replay and cache.
_py_err_tmp=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$_py_err_tmp'" EXIT

_py_exit=0
_py_stdout=$(python3 - "$repo_root" 2>"$_py_err_tmp" <<'PY'
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
) || _py_exit=$?

# Write cache atomically.
if [[ -n "${_max_mtime}" ]]; then
    {
        printf '%s %s\n' "$_max_mtime" "$_py_exit"
        if [[ $_py_exit -eq 0 ]]; then
            printf '%s\n' "$_py_stdout"
        else
            cat "$_py_err_tmp"
        fi
    } > "${_HPNSI_CACHE}.$$" 2>/dev/null && mv "${_HPNSI_CACHE}.$$" "$_HPNSI_CACHE" 2>/dev/null || true
fi

# Output results to correct streams.
if [[ $_py_exit -eq 0 ]]; then
    printf '%s\n' "$_py_stdout"
else
    cat "$_py_err_tmp" >&2
fi

exit $_py_exit
