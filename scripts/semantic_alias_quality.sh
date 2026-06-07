#!/usr/bin/env bash
# semantic_alias_quality.sh — Rank semantic concepts with thin aliases.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_alias_quality.sh [--top N] [--select-file]

Ranks docs/semantic-index concepts by alias thinness and prints the weakest
concepts first. --select-file prints the first existing script path from the
highest-priority weak concept.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
index_path="${SEMANTIC_INDEX_PATH:-$script_dir/docs/semantic-index/index.md}"
top_n=10
select_file=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --top)
            top_n="${2:?--top requires a value}"
            shift 2
            ;;
        --select-file)
            select_file=true
            shift
            ;;
        *)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! [[ "$top_n" =~ ^[0-9]+$ ]] || [ "$top_n" -lt 1 ]; then
    echo "ERROR: --top must be a positive integer: $top_n" >&2
    exit 2
fi
if [ ! -f "$index_path" ]; then
    echo "ERROR: semantic index not found: $index_path" >&2
    exit 1
fi

python3 - "$index_path" "$script_dir" "$top_n" "$select_file" <<'PY'
import re
import sys
from pathlib import Path

import os as _os

index_path = Path(sys.argv[1])
root = Path(sys.argv[2])
top_n = int(sys.argv[3])
select_file = sys.argv[4].lower() == "true"

# scripts/下の存在ファイルをset化(is_file() x113 → scandir 1回)
_scripts_dir = root / "scripts"
_scripts_files: set = set()
try:
    for _e in _os.scandir(_scripts_dir):
        if _e.is_file(follow_symlinks=False):
            _scripts_files.add("scripts/" + _e.name)
        elif _e.is_dir(follow_symlinks=False):
            for _sub in _os.scandir(_e.path):
                if _sub.is_file(follow_symlinks=False):
                    _scripts_files.add("scripts/" + _e.name + "/" + _sub.name)
except OSError:
    pass

text = index_path.read_text(encoding="utf-8", errors="replace")
sections = re.split(r"(?m)^##\s+", text)[1:]
rows = []

def cells(line):
    parts = line.strip().split("|")
    if len(parts) < 4:
        return None, None
    return parts[1].strip(), "|".join(parts[2:-1]).strip()

for raw in sections:
    lines = raw.splitlines()
    if not lines:
        continue
    heading = lines[0].strip()
    concept_id, _, heading_label = heading.partition(" — ")
    attrs = {"id": concept_id.strip(), "label": heading_label.strip()}
    files = []
    for line in lines[1:]:
        if not line.strip().startswith("|") or not line.strip().endswith("|"):
            continue
        left, right = cells(line)
        if not left or left in {"属性", "------", "種別"} or right in {"値", "----------"}:
            continue
        if left in {"id", "label", "aliases"}:
            attrs[left] = right
        elif left == "file":
            files.append(right.strip().strip("`"))

    aliases = [item.strip() for item in attrs.get("aliases", "").split(",") if item.strip()]
    probes = [attrs.get("label", ""), *aliases]
    # Alias-layer self coverage: empty aliases have no way to match natural wording,
    # while non-empty rows are expected to be hit by their own label/aliases.
    hit_rate = 0.0 if not aliases else 100.0
    existing_scripts = []
    for file_ref in files:
        path = file_ref
        if " " in path:
            path = path.split(" ", 1)[0]
        path = path.strip()
        if not path:
            continue
        candidate = Path(path)
        if not candidate.is_absolute():
            candidate = root / path
        try:
            rel = candidate.relative_to(root)
        except ValueError:
            continue
        if rel.parts and rel.parts[0] == "scripts" and str(rel) in _scripts_files:
            existing_scripts.append(str(rel))

    rows.append(
        {
            "id": attrs.get("id", "").strip(),
            "label": attrs.get("label", "").strip(),
            "alias_count": len(aliases),
            "hit_rate": hit_rate,
            "script": existing_scripts[0] if existing_scripts else "",
        }
    )

rows.sort(key=lambda r: (r["alias_count"], r["hit_rate"], 0 if r["script"] else 1, r["id"]))

if select_file:
    for row in rows:
        if row["script"]:
            print(row["script"])
            sys.exit(0)
    sys.exit(1)

print("aliases薄概念Top10")
print("rank\tconcept_id\taliases\thit_rate\ttarget_path")
for idx, row in enumerate(rows[:top_n], 1):
    print(
        f"{idx}\t{row['id']}\t{row['alias_count']}\t"
        f"{row['hit_rate']:.1f}%\t{row['script'] or '-'}"
    )
PY
