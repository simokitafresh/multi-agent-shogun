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
COMMANDER_NAMES=$(get_commander_names 2>/dev/null) || COMMANDER_NAMES="shogun karo gunshi"
read -ra names_arr <<< "$NINJA_NAMES"
read -ra commander_arr <<< "$COMMANDER_NAMES"

# Build grep pattern: any line with 3+ ninja names
# Use rg for speed (>10x faster than python3 on WSL2 NTFS)
_pattern="$(IFS='|'; echo "${names_arr[*]}")"
_commander_pattern="$(IFS='|'; echo "${commander_arr[*]}")"
_scan_pattern="${_pattern}|queue/inbox/(${_commander_pattern})\\.yaml|shogun\\|karo\\|gunshi|shogun[[:space:]]+karo[[:space:]]+gunshi"

violations=""
commander_warnings=""
while IFS= read -r match; do
    [ -z "$match" ] && continue
    file="${match%%:*}"
    rest="${match#*:}"
    lineno="${rest%%:*}"
    line="${rest#*:}"

    # Skip comments
    stripped="${line#"${line%%[![:space:]]*}"}"
    [[ "$stripped" == "#"* ]] && continue

    # Self-exclusion
    [[ "$file" == *gate_no_hardcoded_ninja_list* ]] && continue

    if [[ "$line" != *get_ninja_names* && "$line" != *get_all_agents* \
        && "$line" != *os.environ.get* && "$line" != *'${'*':-'* \
        && !( "$file" == *pre-write-edit-combined* && "$line" == *"Guard 16"* ) ]]; then
        count=0
        for n in "${names_arr[@]}"; do
            [[ "$line" == *"$n"* ]] && ((count++)) || true
        done
        [ "$count" -ge 3 ] && violations="${violations}${file}:${lineno}: ${stripped}
"
    fi

    if [[ "$line" != *get_commander_names* && "$line" != *is_commander_role* \
        && "$line" != *get_commander_inbox_path* ]] \
        && { [[ "$line" =~ queue/inbox/(${_commander_pattern})\.yaml ]] \
        || [[ "$line" =~ (shogun\|karo\|gunshi|shogun[[:space:]]+karo[[:space:]]+gunshi) ]]; }; then
        commander_warnings="${commander_warnings}${file}:${lineno}: ${stripped}
"
    fi
done < <(rg -n "$_scan_pattern" \
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
    if [ -n "$commander_warnings" ]; then
        {
            echo "WARN: hardcoded commander inbox path / role checks detected. Use get_commander_inbox_path(), is_commander_role(), or get_commander_names() from scripts/lib/agent_config.sh."
            echo "Commander ontology: shogun/karo/gunshi must share the same SSOT as other agent roles."
            echo ""
            printf '%s' "$commander_warnings"
        } >&2
    fi
    echo "OK: no hardcoded ninja name lists (ontology intact)"
    exit 0
fi
