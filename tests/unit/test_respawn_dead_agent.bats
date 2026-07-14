#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "configured ninja validation follows get_ninja_names SSOT" {
    run bash -c '
        RESPAWN_DEAD_AGENT_LIB_ONLY=1 source "$1/scripts/respawn_dead_agent.sh"
        get_ninja_names() { printf "%s\n" "alpha beta"; }
        is_configured_ninja beta
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
}

@test "agent absent from get_ninja_names is rejected" {
    run bash -c '
        RESPAWN_DEAD_AGENT_LIB_ONLY=1 source "$1/scripts/respawn_dead_agent.sh"
        get_ninja_names() { printf "%s\n" "alpha beta"; }
        is_configured_ninja hayate
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 1 ]
}
