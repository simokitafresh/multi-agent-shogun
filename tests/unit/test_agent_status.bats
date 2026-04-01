#!/usr/bin/env bats
# test_agent_status.bats - unit tests for scripts/agent_status.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "agent_status labels missing pane as missing" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/scripts/lib/pane_lookup.sh"
missing_pane="$(pane_lookup hayate)"

tmux() {
    local target="" format=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -p) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [ "$format" = "#{pane_id}|#{@agent_id}|#{@agent_state}|#{@last_active}|#{@context_pct}" ] || return 1

    if [ "$target" = "$missing_pane" ]; then
        return 1
    fi

    printf "%%1|mock|idle||\n"
}

source "$PROJECT_ROOT/scripts/agent_status.sh"
'

    [ "$status" -eq 0 ]
    [[ "$output" =~ hayate[[:space:]]+missing[[:space:]]+—[[:space:]]+—[[:space:]]+— ]]
}

@test "agent_status keeps stale labeling for old active panes" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/scripts/lib/pane_lookup.sh"
stale_pane="$(pane_lookup karo)"
now="$(date +%s)"
stale_last_active="$((now - 601))"

tmux() {
    local target="" format=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -p) format="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [ "$format" = "#{pane_id}|#{@agent_id}|#{@agent_state}|#{@last_active}|#{@context_pct}" ] || return 1

    if [ "$target" = "$stale_pane" ]; then
        printf "%%1|karo|active|%s|24%%%%\n" "$stale_last_active"
        return 0
    fi

    printf "%%1|mock|idle||\n"
}

source "$PROJECT_ROOT/scripts/agent_status.sh"
'

    [ "$status" -eq 0 ]
    [[ "$output" =~ karo[[:space:]]+⚠[[:space:]]stale ]]
}
