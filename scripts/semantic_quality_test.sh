#!/usr/bin/env bash
# semantic_quality_test.sh — Run the fixed semantic-index quality fixture.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_quality_test.sh [--fixture path] [--min-score pct]

Runs tests/fixtures/semantic_quality_test_set.json against semantic_search.sh with
LLM, causal expansion, and memory DB disabled. The score denominator is entries
with expected_concept set.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_path="$script_dir/tests/fixtures/semantic_quality_test_set.json"
min_score="${SEMANTIC_QUALITY_MIN_SCORE:-63}"
semantic_search="${SEMANTIC_SEARCH_CMD:-$script_dir/scripts/semantic_search.sh}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --fixture)
            fixture_path="${2:?--fixture requires a path}"
            shift 2
            ;;
        --min-score)
            min_score="${2:?--min-score requires a value}"
            shift 2
            ;;
        *)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ ! -f "$fixture_path" ]; then
    echo "ERROR: fixture not found: $fixture_path" >&2
    exit 1
fi
if [ ! -f "$semantic_search" ]; then
    echo "ERROR: semantic_search not found: $semantic_search" >&2
    exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
results_jsonl="$tmp_dir/results.jsonl"

python3 - "$fixture_path" <<'PY' > "$tmp_dir/queries.tsv"
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for entry in data.get("entries", []):
    print(f"{entry.get('query', '')}\t{entry.get('expected_concept') or ''}")
PY

while IFS=$'\t' read -r query expected; do
    [ -n "$query" ] || continue
    output_file="$tmp_dir/search.out"
    status="hit"
    if SEMANTIC_DISABLE_LLM=1 SEMANTIC_DISABLE_CAUSAL=1 SEMANTIC_DISABLE_MEMORY_DB=1 \
        bash "$semantic_search" "$query" >"$output_file" 2>&1; then
        status="hit"
    else
        rc=$?
        if [ "$rc" -eq 1 ]; then
            status="no_match"
        else
            status="error"
        fi
    fi
    python3 - "$query" "$expected" "$status" "$output_file" >> "$results_jsonl" <<'PY'
import json
import re
import sys
from pathlib import Path

query, expected, status, output_path = sys.argv[1:5]
output = Path(output_path).read_text(encoding="utf-8", errors="replace")
match = re.search(r"(?m)^##\s+([A-Za-z0-9_-]+)\s+—", output)
actual = match.group(1) if match else ""
print(json.dumps(
    {"query": query, "expected": expected, "actual": actual, "status": status},
    ensure_ascii=False,
))
PY
done < "$tmp_dir/queries.tsv"

python3 - "$results_jsonl" "$min_score" <<'PY'
import json
import sys
from pathlib import Path

rows = [json.loads(line) for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
min_score = float(sys.argv[2])
expected_rows = [row for row in rows if row["expected"]]
null_rows = [row for row in rows if not row["expected"]]
correct = [row for row in expected_rows if row["actual"] == row["expected"]]
unexpected = [row for row in null_rows if row["actual"]]
wrong = [row for row in expected_rows if row["actual"] != row["expected"]]
score = (len(correct) / len(expected_rows) * 100.0) if expected_rows else 0.0

print(f"semantic_quality_score: {score:.1f}% ({len(correct)}/{len(expected_rows)})")
print(f"unexpected_null_hits: {len(unexpected)}/{len(null_rows)}")
if wrong:
    print("wrong_expected:")
    for row in wrong[:20]:
        actual = row["actual"] or row["status"]
        print(f"- {row['query']}: expected={row['expected']} actual={actual}")
if unexpected:
    print("unexpected_null_hit_examples:")
    for row in unexpected[:10]:
        print(f"- {row['query']}: actual={row['actual']}")
if score < min_score:
    print(f"ERROR: semantic quality score below threshold: {score:.1f}% < {min_score:.1f}%", file=sys.stderr)
    sys.exit(1)
PY
