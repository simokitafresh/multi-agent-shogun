#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "claude settings skips dangerous mode permission prompt" {
    run jq -r '.skipDangerousModePermissionPrompt' "$PROJECT_ROOT/.claude/settings.json"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "ninja_monitor toggles Claude bypass permissions after clear" {
    run bash -lc "grep -A8 -Ei 'shift.*tab|bypass.*perm' '$PROJECT_ROOT/scripts/ninja_monitor.sh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *'shift+tab twice restores bypass permissions'* ]]
    [[ "$(grep -c 'safe_send_keys "$pane" S-Tab' "$PROJECT_ROOT/scripts/ninja_monitor.sh")" -ge 2 ]]
}
