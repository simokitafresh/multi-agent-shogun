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

@test "stop_session_alerts gives tool-less escape guidance without asking lord for operations" {
    local alerts_file="$TEST_TMPDIR/queue/session_alerts_karo.txt"
    printf '[TODO] report_yaml_format cumulative failure\n' > "$alerts_file"

    rm -f /tmp/stop_session_alerts_karo_toolless_escape_fail_hash 2>/dev/null || true
    TMUX_PANE="" MOCK_AGENT_ID="karo_toolless_escape" run bash "$TEST_TMPDIR/scripts/hooks/stop_session_alerts.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" == *"通常経路:"* ]]
    [[ "$output" == *"ファイル操作ツールが無い場合:"* ]]
    [[ "$output" == *"成果物本文へ依頼文や /clear 依頼を書かず"* ]]
    [[ "$output" == *"tool unavailable: session_alerts未処理"* ]]
    [[ "$output" == *"現在1/5"* ]]
    [[ "$output" == *"殿へCLI操作を依頼するな"* ]]
}

@test "stop_session_alerts auto-passes repeated identical block at threshold" {
    local alerts_file="$TEST_TMPDIR/queue/session_alerts_karo.txt"
    printf '[TODO] report_yaml_format cumulative failure\n' > "$alerts_file"

    rm -f /tmp/stop_session_alerts_karo_toolless_threshold_fail_hash 2>/dev/null || true
    for i in 1 2 3 4; do
        TMUX_PANE="" MOCK_AGENT_ID="karo_toolless_threshold" run bash "$TEST_TMPDIR/scripts/hooks/stop_session_alerts.sh"
        [ "$status" -eq 0 ]
        [[ "$output" == *'"decision": "block"'* ]]
        [[ "$output" == *"現在${i}/5"* ]]
    done

    TMUX_PANE="" MOCK_AGENT_ID="karo_toolless_threshold" run bash "$TEST_TMPDIR/scripts/hooks/stop_session_alerts.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]
}
