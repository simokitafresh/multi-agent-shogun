#!/usr/bin/env bash
# semantic-links: [[リンク密度計測不在]], [[殿指示_偏り修正]], [[training-cycle]]
# causal_backlink_counts.sh — file-level backlink density for knowledge files.
#
# Usage:
#   bash scripts/causal_backlink_counts.sh [--zero] [--limit N]
#
# Counts incoming references to each knowledge file using both path references
# and Obsidian-style [[stem]] links. Self-references are excluded.

set -euo pipefail

ROOT_DIR="${CAUSAL_BACKLINK_COUNTS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MODE="all"
LIMIT=0

usage() {
    echo "Usage: causal_backlink_counts.sh [--zero] [--limit N]" >&2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --zero)
            MODE="zero"
            shift
            ;;
        --limit)
            LIMIT="${2:-}"
            if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
                usage
                exit 2
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

cd "$ROOT_DIR"

python3 - "$MODE" "$LIMIT" <<'PY'
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

mode = sys.argv[1]
limit = int(sys.argv[2])

path_pattern = re.compile(r"(?:context|docs/research)/[A-Za-z0-9._/-]+\.md|skills/[A-Za-z0-9._/-]+/SKILL\.md")
wiki_pattern = re.compile(r"\[\[([^\]\n]+)\]\]")
combined_pattern = r"\[\[[^]\n]+\]\]|(?:context|docs/research)/[A-Za-z0-9._/-]+\.md|skills/[A-Za-z0-9._/-]+/SKILL\.md"
combined_re = re.compile(combined_pattern)

# rg may be absent on a bare WSL2 host (no ripgrep installed). Detect availability up
# front so a missing binary degrades to a deterministic Pure Python path instead of
# silently emitting zero rows (CAUSAL_BACKLINK_COUNTS_FORCE_FALLBACK lets tests pin
# the fallback path even where rg happens to be installed).
RG_AVAILABLE = (
    shutil.which("rg") is not None
    and os.environ.get("CAUSAL_BACKLINK_COUNTS_FORCE_FALLBACK") != "1"
)


def _collect(proc) -> list[str]:
    if proc is None:
        return []
    out, _ = proc.communicate()
    return [l for l in out.splitlines() if l]


def _grep_file(path: str) -> list[str]:
    """Pure Python equivalent of `rg -n -o <pattern> <path>`: one 'path:line:match' per match."""
    try:
        text = Path(path).read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return []
    lines = []
    for lineno, line in enumerate(text.splitlines(), start=1):
        for m in combined_re.finditer(line):
            lines.append(f"{path}:{lineno}:{m.group(0)}")
    return lines


def _walk_files(dir_path: str) -> list[str]:
    """Pure Python equivalent of `rg --no-ignore --files <dir_path>`: every file on disk."""
    base = Path(dir_path)
    if not base.is_dir():
        return []
    return sorted(str(p) for p in base.rglob("*") if p.is_file())


def _list_files_gitignore_aware(dir_path: str) -> list[str]:
    """Pure Python equivalent of `rg --files <dir_path>` (gitignore respected): tracked
    files plus untracked-but-not-ignored files, via git (present in this repo). Falls
    back to an unfiltered walk only if git itself is unavailable or errors."""
    try:
        result = subprocess.run(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--", dir_path],
            text=True, capture_output=True, check=False,
        )
    except OSError:
        return _walk_files(dir_path)
    if result.returncode != 0:
        return _walk_files(dir_path)
    return sorted(dict.fromkeys(l for l in result.stdout.splitlines() if l))


if RG_AVAILABLE:
    # Launch all subprocesses concurrently
    RG_SEARCH_ARGS = ["rg", "-n", "-o", combined_pattern]
    try:
        p_ctx    = subprocess.Popen(["rg", "--files", "context",      "-g", "*.md"],      text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p_docs   = subprocess.Popen(["rg", "--files", "docs/research", "-g", "*.md"],     text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p_skills = subprocess.Popen(["rg", "--files", "skills",        "-g", "SKILL.md"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p_srch_ctx    = subprocess.Popen(RG_SEARCH_ARGS + ["context"],           text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p_srch_docs   = subprocess.Popen(RG_SEARCH_ARGS + ["docs/research"],    text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p_srch_skills = subprocess.Popen(RG_SEARCH_ARGS + ["skills"],           text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p_srch_semidx = subprocess.Popen(RG_SEARCH_ARGS + ["--no-ignore", "docs/semantic-index"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p_srch_mem    = subprocess.Popen(RG_SEARCH_ARGS + ["--no-ignore", "memory"],             text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        p_srch_inst   = subprocess.Popen(RG_SEARCH_ARGS + ["--no-ignore", "instructions"],       text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        p_ctx = p_docs = p_skills = p_srch_ctx = p_srch_docs = p_srch_skills = None
        p_srch_semidx = p_srch_mem = p_srch_inst = None

    # Gather rg_files results
    out_ctx    = _collect(p_ctx)
    out_docs   = _collect(p_docs)
    out_skills = _collect(p_skills)
    targets = sorted(dict.fromkeys(out_ctx + out_docs + out_skills))

    # Gather search results (merge from 6 parallel searches)
    search_lines = (_collect(p_srch_ctx) + _collect(p_srch_docs) + _collect(p_srch_skills)
                    + _collect(p_srch_semidx) + _collect(p_srch_mem) + _collect(p_srch_inst))
else:
    # Pure Python fallback: git-aware listing for the gitignore-respecting dirs,
    # unfiltered filesystem walk for the --no-ignore dirs. Same targets/search_lines
    # shape as the rg branch so the merge logic below is untouched.
    git_dirs = ["context", "docs/research", "skills"]
    noignore_dirs = ["docs/semantic-index", "memory", "instructions"]

    git_dir_files = {d: _list_files_gitignore_aware(d) for d in git_dirs}

    out_ctx    = [f for f in git_dir_files["context"] if f.endswith(".md")]
    out_docs   = [f for f in git_dir_files["docs/research"] if f.endswith(".md")]
    out_skills = [f for f in git_dir_files["skills"] if f.endswith("SKILL.md")]
    targets = sorted(dict.fromkeys(out_ctx + out_docs + out_skills))

    search_lines = []
    for d in git_dirs:
        for f in git_dir_files[d]:
            search_lines.extend(_grep_file(f))
    for d in noignore_dirs:
        for f in _walk_files(d):
            search_lines.extend(_grep_file(f))

wiki_sources: dict[str, set[str]] = defaultdict(set)
path_sources: dict[str, set[str]] = defaultdict(set)

for raw in search_lines:
    parts = raw.split(":", 2)
    if len(parts) != 3:
        continue
    src, _line_no, token = parts
    wiki_match = wiki_pattern.fullmatch(token)
    if wiki_match:
        wiki_sources[wiki_match.group(1)].add(src)
    elif path_pattern.fullmatch(token):
        path_sources[token].add(src)

emitted = 0
for rel in targets:
    path = Path(rel)
    if path.name == "SKILL.md" and len(path.parts) >= 2:
        link_id = path.parts[1]
    else:
        link_id = path.stem
    sources = set(wiki_sources.get(link_id, set()))
    sources.update(path_sources.get(rel, set()))
    sources.discard(rel)
    count = len(sources)
    if mode == "zero" and count != 0:
        continue
    print(f"{count}\t{rel}\t{link_id}")
    emitted += 1
    if limit > 0 and emitted >= limit:
        break
PY
