#!/usr/bin/env bash
# semantic_map_generate.sh — Generate context/semantic-map.md from semantic index SSOT.
# Usage:
#   bash scripts/semantic_map_generate.sh
#   bash scripts/semantic_map_generate.sh --body-only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
index_path="${SEMANTIC_INDEX_PATH:-$repo_root/docs/semantic-index/index.md}"
map_path="${SEMANTIC_MAP_PATH:-$repo_root/context/semantic-map.md}"
body_only=false

if [ "${1:-}" = "--body-only" ]; then
    body_only=true
elif [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    sed -n '2,6p' "$0"
    exit 0
elif [ "$#" -gt 0 ]; then
    echo "ERROR: unknown argument: $1" >&2
    exit 2
fi

if [ ! -f "$index_path" ]; then
    echo "ERROR: semantic index not found: $index_path" >&2
    exit 1
fi

python3 - "$index_path" "$map_path" "$body_only" <<'PY'
import re
import sys
from pathlib import Path

index_path = Path(sys.argv[1])
map_path = Path(sys.argv[2])
body_only = sys.argv[3] == "true"

def parse_concepts(text):
    matches = list(re.finditer(r"(?m)^##\s+(.+)$", text))
    concepts = []
    for i, match in enumerate(matches):
        start = match.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        block = text[start:end]
        heading = match.group(1).strip()
        attrs = {}
        resources = []
        for raw in block.splitlines():
            line = raw.strip()
            row = re.match(r"^\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|$", line)
            if not row:
                continue
            left, right = row.group(1).strip(), row.group(2).strip()
            if left in {"属性", "------", "種別"}:
                continue
            if left in {"id", "label", "aliases", "skills"}:
                attrs[left] = right
            elif left and right and left != "------":
                resources.append((left, right))
        aliases = attrs.get("aliases", "").strip()
        label = attrs.get("label") or heading.split(" — ", 1)[-1].strip()
        files = [value for kind, value in resources if kind == "file"][:3]
        lessons = [
            value for kind, value in resources
            if kind in {"lesson", "deepdive"} or value.lstrip("`").startswith(("L", "LS", "PI-"))
        ][:3]
        concepts.append({
            "label": label,
            "aliases": aliases,
            "skills": attrs.get("skills", "").strip(),
            "files": files,
            "lessons": lessons,
        })
    return concepts

def cell(values, default="なし"):
    if isinstance(values, str):
        return values or default
    return ", ".join(values) if values else default

concepts = parse_concepts(index_path.read_text(encoding="utf-8"))
lines = [
    "# セマンティクスマップ",
    "",
    "<!-- auto-generated from docs/semantic-index/index.md -->",
    "<!-- do not edit directly; update docs/semantic-index/index.md and run codd propagate --update -->",
    "",
    "| 概念 | 別名 | 主要ファイル | 教訓 | skills |",
    "|------|------|------------|------|--------|",
]
for concept in concepts:
    lines.append(
        f"| {concept['label']} | {cell(concept['aliases'])} | "
        f"{cell(concept['files'])} | {cell(concept['lessons'])} | {cell(concept['skills'])} |"
    )

body = "\n".join(lines) + "\n"
if body_only:
    sys.stdout.write(body)
else:
    frontmatter = """---
codd:
  node_id: design:semantic-map
  type: generated-index
  title: セマンティクスマップ
  modules:
    - semantic-index
---

"""
    map_path.parent.mkdir(parents=True, exist_ok=True)
    map_path.write_text(frontmatter + body, encoding="utf-8")
    print(f"generated: {map_path}")
PY
