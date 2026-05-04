#!/usr/bin/env bash
# semantic_search.sh — Two-layer semantic-index search.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_search.sh [--llm] <query>

Search docs/semantic-index/index.md by concept label and aliases. If the
first layer has no match, fall back to LLM semantic matching. Use --llm to
skip the alias layer and run semantic matching directly.

Environment:
  SEMANTIC_INDEX_PATH  Override docs/semantic-index/index.md
  SEMANTIC_LLM_CMD     Override LLM command (default: claude --print)
EOF
}

force_llm=false
query_parts=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --llm)
            force_llm=true
            shift
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do
                query_parts+=("$1")
                shift
            done
            ;;
        -*)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            query_parts+=("$1")
            shift
            ;;
    esac
done

if [ "${#query_parts[@]}" -lt 1 ]; then
    usage >&2
    exit 2
fi

query="${query_parts[*]}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
index_path="${SEMANTIC_INDEX_PATH:-$script_dir/docs/semantic-index/index.md}"

if [ ! -f "$index_path" ]; then
    echo "ERROR: semantic index not found: $index_path" >&2
    exit 1
fi

first_layer_search() {
    local no_match_mode="${1:-print}"
    python3 - "$index_path" "$query" "$no_match_mode" <<'PY'
import re
import sys
from pathlib import Path

index_path = Path(sys.argv[1])
query = sys.argv[2].strip()
no_match_mode = sys.argv[3]

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
    if no_match_mode != "silent":
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
}

render_llm_resources() {
    local llm_output_file="$1"
    python3 - "$index_path" "$llm_output_file" <<'PY'
import re
import sys
from pathlib import Path

index_path = Path(sys.argv[1])
llm_output_path = Path(sys.argv[2])
raw_output = llm_output_path.read_text(encoding="utf-8", errors="replace")
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

    concepts.append(
        {
            "id": attrs.get("id") or concept_id.strip(),
            "label": attrs.get("label") or heading_label,
            "aliases": [
                item.strip()
                for item in attrs.get("aliases", "").split(",")
                if item.strip()
            ],
            "resources": resources,
        }
    )

matched = []
for concept in concepts:
    concept_id = concept["id"]
    if re.search(rf"(?<![A-Za-z0-9_.-]){re.escape(concept_id)}(?![A-Za-z0-9_.-])", raw_output):
        matched.append(concept)

if not matched:
    print("resources: LLM output did not contain known concept ids")
    sys.exit(0)

print("resolved resources:")
for idx, concept in enumerate(matched[:3], 1):
    if idx > 1:
        print("")
    print(f"## {concept['id']} — {concept['label']}")
    print(f"aliases: {', '.join(concept['aliases'])}")
    print("resources:")
    if concept["resources"]:
        for resource_type, ref in concept["resources"]:
            print(f"- {resource_type}: {ref}")
    else:
        print("- none")
PY
}

llm_search() {
    local llm_cmd="${SEMANTIC_LLM_CMD:-claude --print}"
    local prompt_file
    local output_file
    prompt_file="$(mktemp)"
    output_file="$(mktemp)"
    trap 'rm -f "$prompt_file" "$output_file"' RETURN

    {
        cat <<EOF
You are matching a user query to a semantic index.

Query:
$query

Instructions:
- Choose up to 3 most related concepts from the index.
- Output each selected concept id on a line beginning with "MATCH: ".
- Add one short reason per match.
- Suggest alias candidates if the query uses wording that is missing from aliases.
- Use only concept ids that appear in the index.

Semantic index:
EOF
        cat "$index_path"
    } > "$prompt_file"

    if bash -c "$llm_cmd" < "$prompt_file" > "$output_file"; then
        :
    else
        local rc=$?
        echo "ERROR: LLM semantic search failed with exit code $rc" >&2
        echo "command: $llm_cmd" >&2
        return "$rc"
    fi

    echo "LLM_MATCH: $query"
    echo ""
    cat "$output_file"
    echo ""
    render_llm_resources "$output_file"
}

if [ "$force_llm" = false ]; then
    if first_layer_search silent; then
        exit 0
    else
        rc=$?
        if [ "$rc" -ne 1 ]; then
            exit "$rc"
        fi
    fi
fi

llm_search
