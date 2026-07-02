#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/session_alerts.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/queue" "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/scripts/hooks"
    cp "$PROJECT_ROOT/scripts/gates/session_alerts_render.sh" "$TEST_TMPDIR/scripts/gates/session_alerts_render.sh"
    cp "$PROJECT_ROOT/scripts/hooks/stop_session_alerts.sh" "$TEST_TMPDIR/scripts/hooks/stop_session_alerts.sh"
    chmod +x "$TEST_TMPDIR/scripts/hooks/stop_session_alerts.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "session_alerts render preserves DONE and drops resolved-away alerts for all roles" {
    source "$TEST_TMPDIR/scripts/gates/session_alerts_render.sh"

    for role in shogun karo gunshi; do
        local alerts_file="$TEST_TMPDIR/queue/session_alerts_${role}.txt"
        printf '# old\n[DONE] keep alert\n[TODO] stale alert\n' > "$alerts_file"

        render_session_alerts_file "$alerts_file" "session_alerts_${role}" "2099-01-01T00:00:00+0900" \
            "keep alert" \
            "new alert"

        grep -Fxq "[DONE] keep alert" "$alerts_file"
        grep -Fxq "[TODO] new alert" "$alerts_file"
        ! grep -Fq "stale alert" "$alerts_file"
    done
}

@test "stop_session_alerts allows preserved DONE-only file and blocks remaining TODO" {
    source "$TEST_TMPDIR/scripts/gates/session_alerts_render.sh"

    local alerts_file="$TEST_TMPDIR/queue/session_alerts_shogun.txt"
    printf '# old\n[DONE] keep alert\n[TODO] stale alert\n' > "$alerts_file"
    render_session_alerts_file "$alerts_file" "session_alerts_shogun" "2099-01-01T00:00:00+0900" "keep alert"

    TMUX_PANE="" MOCK_AGENT_ID="shogun_test_done" run bash "$TEST_TMPDIR/scripts/hooks/stop_session_alerts.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]

    render_session_alerts_file "$alerts_file" "session_alerts_shogun" "2099-01-01T00:01:00+0900" \
        "keep alert" \
        "new alert"

    rm -f /tmp/stop_session_alerts_shogun_test_todo_fail_hash 2>/dev/null || true
    TMUX_PANE="" MOCK_AGENT_ID="shogun_test_todo" run bash "$TEST_TMPDIR/scripts/hooks/stop_session_alerts.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" == *"[TODO] new alert"* ]]
}
