#!/usr/bin/env bats
# test_pane_lookup.bats - pane_lookup source/init regression tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

extract_function() {
    local name="$1"
    local file="$2"
    local start end

    start=$(awk -v name="$name" '$0 ~ "^" name "\\(\\) \\{" { print NR; exit }' "$file")
    [ -n "$start" ] || return 1

    end=$(awk -v start="$start" '
        NR > start && /^[A-Za-z0-9_]+\(\) \{/ { print NR - 1; found = 1; exit }
        END { if (!found) print NR }
    ' "$file")
    sed -n "${start},${end}p" "$file"
}

@test "pane_lookup initializes agent order on source" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/scripts/lib/pane_lookup.sh"
printf "len=%s\n" "${#PANE_LOOKUP_AGENT_ORDER[@]}"
printf "order=%s\n" "${PANE_LOOKUP_AGENT_ORDER[*]}"
'

    [ "$status" -eq 0 ]
    [[ "$output" == *"len=8"* ]]
    [[ "$output" == *"order=karo gunshi hayate kagemaru hanzo saizo kotaro tobisaru"* ]]
}

@test "pane_lookup returns static pane fallback without ninja_states" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/scripts/lib/pane_lookup.sh"
rm -f "$PROJECT_ROOT/logs/ninja_states.yaml"
pane_lookup saizo
'

    [ "$status" -eq 0 ]
    [ "$output" = "shogun:agents.6" ]
}

@test "deploy_task resolve_pane works with pane_lookup source-time init" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/scripts/lib/agent_config.sh"
source "$PROJECT_ROOT/scripts/lib/pane_lookup.sh"
eval "$(awk '\''$0 ~ /^resolve_pane\(\) \{/ {flag=1} flag {print} flag && /^}$/ {exit}'\'' "$PROJECT_ROOT/scripts/deploy_task.sh")"
resolve_pane saizo
'

    [ "$status" -eq 0 ]
    [ "$output" = "shogun:agents.6" ]
}
