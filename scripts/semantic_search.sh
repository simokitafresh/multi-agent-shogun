#!/usr/bin/env bash
# semantic_search.sh — First-layer semantic-index search by label and aliases.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_search.sh <query>

Search docs/semantic-index/index.md by concept label and aliases, then print
matched concepts with their registered resources.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ "$#" -lt 1 ]; then
    usage >&2
    exit 2
fi

query="$*"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
index_path="${SEMANTIC_INDEX_PATH:-$script_dir/docs/semantic-index/index.md}"

if [ ! -f "$index_path" ]; then
    echo "ERROR: semantic index not found: $index_path" >&2
    exit 1
fi

python3 - "$index_path" "$query" <<'PY'
import re
import sys
from pathlib import Path

index_path = Path(sys.argv[1])
query = sys.argv[2].strip()

if not query:
    print("ERROR: query is empty", file=sys.stderr)
    sys.exit(2)

text = index_path.read_text(encoding="utf-8")
sections = re.split(r"(?m)^##\s+", text)
concepts = []

for raw in sections[1:]:
    lines = raw.splitlines()
    if not lines:
        continue
    heading = lines[0].strip()
    if " — " in heading:
        concept_id, heading_label = heading.split(" — ", 1)
    else:
        concept_id, heading_label = heading, ""

    attrs = {}
    resources = []
    for line in lines[1:]:
        stripped = line.strip()
        m = re.match(r"^\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|$", stripped)
        if not m:
            continue
        left = m.group(1).strip()
        right = m.group(2).strip()
        if left in {"属性", "------", "種別"} or right in {"値", "----------"}:
            continue
        if left in {"id", "label", "aliases"}:
            attrs[left] = right
        elif right:
            resources.append((left, right))

    label = attrs.get("label") or heading_label
    aliases = [
        item.strip()
        for item in attrs.get("aliases", "").split(",")
        if item.strip()
    ]
    concepts.append(
        {
            "id": attrs.get("id") or concept_id.strip(),
            "label": label,
            "aliases": aliases,
            "resources": resources,
        }
    )

query_fold = query.casefold()
matches = []
for concept in concepts:
    terms = [concept["label"], *concept["aliases"]]
    matched_terms = []
    for term in terms:
        term_fold = term.casefold()
        if query_fold in term_fold or term_fold in query_fold:
            matched_terms.append(term)
    if matched_terms:
        matches.append((concept, matched_terms))

if not matches:
    print(f"NO_MATCH: {query}")
    sys.exit(1)

for idx, (concept, matched_terms) in enumerate(matches, 1):
    if idx > 1:
        print("")
    print(f"## {concept['id']} — {concept['label']}")
    print(f"matched: {', '.join(matched_terms)}")
    print(f"aliases: {', '.join(concept['aliases'])}")
    print("resources:")
    if concept["resources"]:
        for resource_type, ref in concept["resources"]:
            print(f"- {resource_type}: {ref}")
    else:
        print("- none")
PY
