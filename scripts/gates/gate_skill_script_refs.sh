#!/usr/bin/env bash
# gate_skill_script_refs.sh — SKILL.md script reference freshness gate
#
# Usage:
#   bash scripts/gates/gate_skill_script_refs.sh [repo_root]
#   SKILL_REF_DIRS="skills:.claude/skills" bash scripts/gates/gate_skill_script_refs.sh
#
# Checks:
#   (A) Extract script references from all SKILL.md files.
#   (B) Verify referenced script paths exist.
#   (C) List SKILL.md files that may need updates because a referenced script is newer.
#
# Exit code: 0=PASS, 2=WARN (missing or stale references)
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

SKILL_REF_REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

repo_root = Path(os.environ["SKILL_REF_REPO_ROOT"]).resolve()

command_ref_re = re.compile(
    r"(?:^|[\s`(])(?:bash|sh|python3?|node|ruby|perl)\s+"
    r"([~./A-Za-z0-9_-][^\s`'\"|;&)]*)"
)
inline_ref_re = re.compile(
    r"`((?:scripts|skills|\.claude/skills|~/.claude/skills|~/.codex/skills)"
    r"/[^`\s]+?\.(?:sh|py|js))`"
)
script_ext_re = re.compile(r"\.(?:sh|py|js)$")


def iter_skill_files(root: Path):
    skip_dirs = {".git", ".mypy_cache", ".pytest_cache", "node_modules", "__pycache__"}
    for current, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        if "SKILL.md" in files:
            yield Path(current) / "SKILL.md"


def clean_ref(raw: str) -> str:
    return raw.strip().strip("'\"").rstrip(".,:;")


def resolve_ref(raw: str) -> Path:
    ref = clean_ref(raw)
    if ref.startswith("~/"):
        return Path(os.path.expanduser(ref)).resolve()
    path = Path(ref)
    if path.is_absolute():
        return path
    return (repo_root / path).resolve()


def extract_refs(text: str) -> list[str]:
    refs: list[str] = []
    for match in command_ref_re.finditer(text):
        ref = clean_ref(match.group(1))
        if script_ext_re.search(ref):
            refs.append(ref)
    for match in inline_ref_re.finditer(text):
        refs.append(clean_ref(match.group(1)))
    return sorted(set(refs))


raw_roots = os.environ.get("SKILL_REF_DIRS", "skills:.claude/skills:.codex/skills")
scan_roots: list[Path] = []
for raw in raw_roots.split(":"):
    raw = raw.strip()
    if not raw:
        continue
    candidate = Path(os.path.expanduser(raw))
    if not candidate.is_absolute():
        candidate = repo_root / candidate
    if candidate.exists():
        scan_roots.append(candidate.resolve())

skill_files = sorted(
    {skill_file for root in scan_roots for skill_file in iter_skill_files(root)}
)
missing: list[tuple[str, str, str]] = []
stale: list[tuple[str, str, str]] = []
total_refs = 0
skills_with_refs = 0

for skill_file in skill_files:
    try:
        text = skill_file.read_text(encoding="utf-8", errors="ignore")
    except OSError as exc:
        missing.append((str(skill_file.relative_to(repo_root)), "(read error)", str(exc)))
        continue

    refs = extract_refs(text)
    if refs:
        skills_with_refs += 1
    total_refs += len(refs)
    skill_mtime = skill_file.stat().st_mtime

    for ref in refs:
        resolved = resolve_ref(ref)
        display_skill = str(skill_file.relative_to(repo_root))
        if not resolved.exists():
            missing.append((display_skill, ref, str(resolved)))
            continue
        if resolved.is_file() and resolved.stat().st_mtime > skill_mtime + 1:
            stale.append((display_skill, ref, str(resolved.relative_to(repo_root)) if resolved.is_relative_to(repo_root) else str(resolved)))

print("=== SKILL.md script reference check ===")
print(
    f"走査: {len(skill_files)} SKILL.md / script参照 {total_refs}件 / "
    f"参照あり {skills_with_refs}件 / roots={','.join(str(p.relative_to(repo_root)) if p.is_relative_to(repo_root) else str(p) for p in scan_roots)}"
)

if missing:
    print("=== 参照先不在 ===")
    for skill, ref, resolved in missing[:30]:
        print(f"  WARN: {skill} -> {ref} (resolved: {resolved})")
    if len(missing) > 30:
        print(f"  ... {len(missing) - 30} more")
else:
    print("OK: 全script参照先が実在")

if stale:
    print("=== 要更新スキル一覧 (script newer than SKILL.md) ===")
    for skill, ref, resolved in stale[:30]:
        print(f"  WARN: {skill} <- {ref} (newer: {resolved})")
    if len(stale) > 30:
        print(f"  ... {len(stale) - 30} more")
else:
    print("OK: SKILL.md更新日がscript参照先以上に新しい")

if missing or stale:
    print("--- 総合判定: WARN ---")
    sys.exit(2)

print("--- 総合判定: PASS ---")
PY
