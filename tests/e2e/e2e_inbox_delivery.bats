#!/usr/bin/env bats
# MVP E2E: inbox_write -> inbox_watcher nudge -> mock_cli processing.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    export E2E_SETUP="$PROJECT_ROOT/tests/helpers/setup.bash"
    export E2E_ASSERT="$PROJECT_ROOT/tests/helpers/assertions.bash"
    export MOCK_CLI="$PROJECT_ROOT/tests/e2e/mock_cli.sh"

    [ -f "$E2E_SETUP" ] || return 1
    [ -f "$E2E_ASSERT" ] || return 1
    [ -f "$MOCK_CLI" ] || return 1
}

setup() {
    source "$E2E_SETUP"
    source "$E2E_ASSERT"

    export E2E_MOCK_CLI_PATH="$MOCK_CLI"
    export E2E_MOCK_DELAY=1
    export E2E_INOTIFY_TIMEOUT=5
    export E2E_BACKOFF_SEC=5

    setup_e2e_session 3

    # E2E isolation: inbox_watcher self-watch detection uses pgrep.
    # In this harness, pgrep would match watcher's own inotifywait process and skip nudge.
    # Override pgrep to always return "not found" so nudge path is exercised.
    mkdir -p "$E2E_ROOT/bin"
    cat > "$E2E_ROOT/bin/pgrep" <<'SH'
#!/usr/bin/env bash
exit 1
SH
    chmod +x "$E2E_ROOT/bin/pgrep"

    WATCHER_LOG="$E2E_ROOT/inbox_watcher_kirimaru.log"
    PATH="$E2E_ROOT/bin:$PATH" \
    INOTIFY_TIMEOUT="$E2E_INOTIFY_TIMEOUT" \
    BACKOFF_SEC="$E2E_BACKOFF_SEC" \
    bash "$E2E_QUEUE/scripts/inbox_watcher.sh" "kirimaru" "$(pane_target 2)" "codex" >"$WATCHER_LOG" 2>&1 &
    WATCHER_PID="$!"
}

teardown() {
    source "$E2E_SETUP"
    stop_inbox_watcher "${WATCHER_PID:-}"
    teardown_e2e_session
}

wait_for_unread_zero() {
    local inbox_file="$1"
    local timeout="${2:-20}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        if assert_inbox_unread_count "$inbox_file" 0 >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "TIMEOUT: unread count did not reach zero: $inbox_file" >&2
    return 1
}

@test "E2E inbox delivery: nudge reaches mock_cli and task completes" {
    local task_file="$E2E_QUEUE/queue/tasks/kirimaru.yaml"
    cat > "$task_file" <<'YAML'
task:
  assigned_to: kirimaru
  parent_cmd: cmd_438
  subtask_id: subtask_438_impl_b
  report_filename: kirimaru_report_cmd_438.yaml
  status: assigned
YAML

    run bash "$E2E_QUEUE/scripts/inbox_write.sh" "kirimaru" "task assigned for e2e" "task_assigned" "karo"
    [ "$status" -eq 0 ]

    local pane
    pane="$(pane_target 2)"

    wait_for_pane_text "$pane" "EVENT inbox1" 30
    wait_for_pane_text "$pane" "STATE BUSY" 30
    wait_for_pane_text "$pane" "STATE IDLE" 30

    wait_for_yaml_value "$task_file" "task.status" "done" 30
    wait_for_unread_zero "$E2E_QUEUE/queue/inbox/kirimaru.yaml" 30

    local report_file="$E2E_QUEUE/queue/reports/kirimaru_report_cmd_438.yaml"
    wait_for_file "$report_file" 30
    assert_file_contains "$report_file" "status: done"

    run tmux display-message -t "$pane" -p '#{@agent_state}'
    [ "$status" -eq 0 ]
    [ "$output" = "idle" ]

    run tmux send-keys -t "$pane" "/clear" Enter
    [ "$status" -eq 0 ]
    wait_for_pane_text "$pane" "CLEAR" 10
}
