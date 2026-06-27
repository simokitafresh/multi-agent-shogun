#!/usr/bin/env bash
# semantic_alias_absorb_pending.sh — Promote pending semantic_stress candidate aliases.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_alias_absorb_pending.sh

Promote accumulated semantic_stress_test candidate_aliases from insights.yaml
into existing semantic-index concept aliases through semantic_index_update.sh
absorb_pending. Prints pending_before, aliases_added, and pending_after.

Environment:
  SEMANTIC_INDEX_UPDATE   Override semantic_index_update.sh path
  SEMANTIC_INSIGHTS_PATH  Override queue/insights.yaml
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi
if [ "$#" -gt 0 ]; then
    usage >&2
    exit 2
fi

self="${BASH_SOURCE[0]}"
[[ "$self" != /* ]] && self="$PWD/$self"
repo_root="${self%/scripts/semantic_alias_absorb_pending.sh}"
semantic_index_update="${SEMANTIC_INDEX_UPDATE:-$repo_root/scripts/semantic_index_update.sh}"
insights_path="${SEMANTIC_INSIGHTS_PATH:-$repo_root/queue/insights.yaml}"

if [ ! -f "$semantic_index_update" ]; then
    echo "ERROR: semantic_index_update not found: $semantic_index_update" >&2
    exit 1
fi

pending_count() {
    python3 - "$insights_path" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists() or not path.stat().st_size:
    print(0)
    raise SystemExit

try:
    import yaml
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
except Exception:
    print(0)
    raise SystemExit

count = 0
for entry in data.get("insights") or []:
    if not isinstance(entry, dict):
        continue
    if str(entry.get("status", "")).strip() != "pending":
        continue
    if "semantic_stress_test candidate_aliases" in str(entry.get("insight", "")):
        count += 1
print(count)
PY
}

pending_before="$(pending_count)"
output="$(
    SEMANTIC_STRESS_AFTER_ALIAS_CHANGE=0 \
    SEMANTIC_QUALITY_AFTER_ALIAS_CHANGE=0 \
    SEMANTIC_INSIGHTS_PATH="$insights_path" \
    bash "$semantic_index_update" absorb_pending '{}'
)"

printf '%s\n' "$output"

aliases_added="$(
    python3 - "$output" <<'PY'
import re
import sys

output = sys.argv[1]
total = 0
for match in re.finditer(r"aliases_added=([^\n]+)", output):
    value = match.group(1).strip()
    if value == "none":
        continue
    total += len([item for item in re.split(r"[,、，]", value) if item.strip()])
print(total)
PY
)"
pending_after="$(pending_count)"

echo "pending_before=$pending_before"
echo "aliases_added=$aliases_added"
echo "pending_after=$pending_after"
