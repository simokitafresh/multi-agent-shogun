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

python3 - "$index_path" "$map_path" "$body_only" "$repo_root" <<'PY'
import glob
import re
import sys
from pathlib import Path

index_path = Path(sys.argv[1])
map_path = Path(sys.argv[2])
body_only = sys.argv[3] == "true"
repo_root = Path(sys.argv[4]) if len(sys.argv) > 4 else index_path.parent.parent.parent

def load_lesson_origins(repo_root):
    """projects/*/lessons*.yaml（archive除く）からlesson_id→originマップを作成"""
    origins = {}
    pattern = str(repo_root / "projects" / "*" / "lessons*.yaml")
    for yaml_path in sorted(glob.glob(pattern)):
        if "archive" in Path(yaml_path).name:
            continue
        try:
            text = Path(yaml_path).read_text(encoding="utf-8")
        except Exception:
            continue
        current_id = None
        for raw_line in text.splitlines():
            line = raw_line.strip()
            if line.startswith("- id:"):
                current_id = line[len("- id:"):].strip()
            elif line.startswith("origin:") and current_id:
                val = line[len("origin:"):].strip().strip("'\"")
                if "[[" in val:
                    origins[current_id] = val
                current_id = None
    return origins

def inject_causal_chains(index_path, origins):
    """index.mdの各概念のlesson参照からoriginを取得しcausal_chainを注入（冪等）"""
    if not origins:
        return 0
    text = index_path.read_text(encoding="utf-8")
    parts = re.split(r"(?m)(?=^## )", text)
    new_parts = []
    injected = 0
    for part in parts:
        if not part.startswith("## "):
            new_parts.append(part)
            continue
        # 既存causal_chainを削除（冪等）
        part = re.sub(r"\| causal_chain \|[^\n]*\n?", "", part)
        # lesson idを抽出（`Lxxx` 形式）
        lesson_ids = re.findall(r"\|\s*lesson\s*\|\s*`(L\w+)`", part)
        chains = []
        for lid in lesson_ids:
            if lid in origins:
                chains.append(f"| causal_chain | `{origins[lid]}` ({lid}) |")
        if chains:
            lines = part.splitlines(keepends=True)
            last_pipe_idx = -1
            for i, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith("|") and not stripped.startswith("|---") and stripped != "|":
                    last_pipe_idx = i
            if last_pipe_idx >= 0:
                for chain in reversed(chains):
                    lines.insert(last_pipe_idx + 1, chain + "\n")
                part = "".join(lines)
                injected += len(chains)
        new_parts.append(part)
    new_text = "".join(new_parts)
    if new_text != text:
        index_path.write_text(new_text, encoding="utf-8")
    return injected

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
            if left in {"id", "label", "aliases", "skills", "related_concepts"}:
                attrs[left] = right
            elif left and right and left != "------":
                resources.append((left, right))
        aliases = attrs.get("aliases", "").strip()
        label = attrs.get("label") or heading.split(" — ", 1)[-1].strip()
        files = [value for kind, value in resources if kind == "file"][:3]
        urls = [value for kind, value in resources if kind == "url"][:3]
        lessons = [
            value for kind, value in resources
            if kind in {"lesson", "deepdive", "cmd", "causal"} or value.lstrip("`").startswith(("L", "LS", "PI-", "cmd_"))
        ][:3]
        concepts.append({
            "label": label,
            "aliases": aliases,
            "skills": attrs.get("skills", "").strip(),
            "files": files,
            "urls": urls,
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
    "| 概念 | 別名 | 主要ファイル | 外部URL | 教訓 | skills |",
    "|------|------|------------|---------|------|--------|",
]
for concept in concepts:
    lines.append(
        f"| {concept['label']} | {cell(concept['aliases'])} | "
        f"{cell(concept['files'])} | {cell(concept['urls'])} | "
        f"{cell(concept['lessons'])} | {cell(concept['skills'])} |"
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
    origins = load_lesson_origins(repo_root)
    injected = inject_causal_chains(index_path, origins)
    if injected:
        print(f"causal_chain entries injected: {injected}")
PY

auto_resolve_semantic_index_insights() {
    local insight_script="$repo_root/scripts/insight_write.sh"
    local insights_file="${SEMANTIC_INSIGHTS_PATH:-$repo_root/queue/insights.yaml}"
    local default_map="$repo_root/context/semantic-map.md"

    [ "$body_only" = false ] || return 0
    if [ "${SEMANTIC_INSIGHT_AUTO_RESOLVE:-0}" != "1" ] && [ "$map_path" != "$default_map" ]; then
        return 0
    fi
    [ -f "$insight_script" ] || return 0
    [ -s "$insights_file" ] || return 0

    local ids
    ids=$(INSIGHTS_FILE_ENV="$insights_file" python3 - <<'PY' 2>/dev/null || true
import json
import os

path = os.environ["INSIGHTS_FILE_ENV"]

def parse_scalar(raw):
    value = raw.strip()
    if value.startswith('"'):
        try:
            return json.loads(value)
        except Exception:
            return value.strip('"')
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value

entries = []
current = None
with open(path, encoding="utf-8") as f:
    for line in f:
        if line.startswith("- id: "):
            if current:
                entries.append(current)
            current = {"id": line[len("- id: "):].strip()}
            continue
        if current is None or not line.startswith("  ") or ":" not in line:
            continue
        key, raw = line.strip().split(":", 1)
        current[key] = parse_scalar(raw)
if current:
    entries.append(current)

for entry in entries:
    if entry.get("status") == "pending" and entry.get("source") == "semantic_index_update":
        print(entry["id"])
PY
    )

    local count=0 id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if bash "$insight_script" --resolve "$id" >/dev/null 2>&1; then
            count=$((count + 1))
        else
            echo "WARN: semantic insight auto-resolve failed: $id" >&2
        fi
    done <<< "$ids"

    [ "$count" -eq 0 ] || echo "semantic insights auto-resolved: $count"
}

auto_resolve_semantic_index_insights || true
