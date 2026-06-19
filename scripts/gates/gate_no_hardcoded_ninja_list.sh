#!/usr/bin/env bash
# semantic-links: [[操作的オントロジー]], [[インフラ不変量]]
# Detect hardcoded ninja name lists in scripts/gates/ and .claude/hooks/.
# Ninja names must come from get_ninja_names()/get_all_agents() (agent_config.sh).
# Hardcoded lists break when ninjas are added/removed — operational ontology violation.
# 殿裁定 2026-06-20: オントロジーが動いていない証拠を根絶

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT_DIR/scripts/lib/agent_config.sh" 2>/dev/null || true
NINJA_NAMES=$(get_ninja_names 2>/dev/null) || NINJA_NAMES="hayate kagemaru hanzo saizo kotaro tobisaru"
read -ra names_arr <<< "$NINJA_NAMES"

# Build grep pattern: any line with 3+ ninja names
# Use rg for speed (>10x faster than python3 on WSL2 NTFS)
_pattern="$(IFS='|'; echo "${names_arr[*]}")"

violations=""
while IFS= read -r match; do
    [ -z "$match" ] && continue
    file="${match%%:*}"
    rest="${match#*:}"
    lineno="${rest%%:*}"
    line="${rest#*:}"

    # Skip comments
    stripped="${line#"${line%%[![:space:]]*}"}"
    [[ "$stripped" == "#"* ]] && continue

    # Skip correct usage patterns
    [[ "$line" == *get_ninja_names* ]] && continue
    [[ "$line" == *get_all_agents* ]] && continue
    [[ "$line" == *os.environ.get* ]] && continue
    [[ "$line" == *'${'*':-'* ]] && continue

    # Self-exclusion
    [[ "$file" == *gate_no_hardcoded_ninja_list* ]] && continue
    [[ "$file" == *pre-write-edit-combined* && "$line" == *"Guard 16"* ]] && continue

    # Count names on this line
    count=0
    for n in "${names_arr[@]}"; do
        [[ "$line" == *"$n"* ]] && ((count++)) || true
    done
    [ "$count" -ge 3 ] && violations="${violations}${file}:${lineno}: ${stripped}
"
done < <(rg -n "$_pattern" \
    --glob '*.sh' --glob '*.py' \
    "$ROOT_DIR/scripts/gates" "$ROOT_DIR/.claude/hooks" \
    "$ROOT_DIR/scripts/"*.sh "$ROOT_DIR/scripts/"*.py 2>/dev/null || true)

if [ -n "$violations" ]; then
    {
        echo "BLOCK: hardcoded ninja name lists detected. Use get_ninja_names() from scripts/lib/agent_config.sh."
        echo "Operational ontology: changing ninja roster must propagate automatically."
        echo ""
        printf '%s' "$violations"
    } >&2
    exit 1
else
    echo "OK: no hardcoded ninja name lists (ontology intact)"
    exit 0
fi
