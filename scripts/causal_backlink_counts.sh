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

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

mode = sys.argv[1]
limit = int(sys.argv[2])


def rg_files(*args: str) -> list[str]:
    try:
        proc = subprocess.run(["rg", "--files", *args], text=True, capture_output=True, check=False)
    except OSError:
        return []
    return [line for line in proc.stdout.splitlines() if line]

targets = []
targets.extend(rg_files("context", "-g", "*.md"))
targets.extend(rg_files("docs/research", "-g", "*.md"))
targets.extend(rg_files("skills", "-g", "SKILL.md"))
targets = sorted(dict.fromkeys(targets))

wiki_sources: dict[str, set[str]] = defaultdict(set)
path_sources: dict[str, set[str]] = defaultdict(set)
path_pattern = re.compile(r"(?:context|docs/research)/[A-Za-z0-9._/-]+\.md|skills/[A-Za-z0-9._/-]+/SKILL\.md")
wiki_pattern = re.compile(r"\[\[([^\]\n]+)\]\]")

combined_pattern = r"\[\[[^]\n]+\]\]|(?:context|docs/research)/[A-Za-z0-9._/-]+\.md|skills/[A-Za-z0-9._/-]+/SKILL\.md"
try:
    proc = subprocess.run(
        ["rg", "-n", "-o", combined_pattern, "context", "docs/research", "skills"],
        text=True,
        capture_output=True,
        check=False,
    )
except OSError:
    proc = subprocess.CompletedProcess([], 1, "", "")

for raw in proc.stdout.splitlines():
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
