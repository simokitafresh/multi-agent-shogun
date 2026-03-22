#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export E2E_SETUP="$PROJECT_ROOT/tests/e2e/helpers/setup.bash"
    export E2E_ASSERT="$PROJECT_ROOT/tests/e2e/helpers/assertions.bash"
    export E2E_TMUX="$PROJECT_ROOT/tests/e2e/helpers/tmux_helpers.bash"
    export MOCK_CLI="$PROJECT_ROOT/tests/e2e/mock_cli.sh"
}

setup() {
    source "$E2E_SETUP"
    source "$E2E_ASSERT"
    source "$E2E_TMUX"
    export E2E_MOCK_CLI_PATH="$MOCK_CLI"
    export E2E_MOCK_DELAY=1
    setup_e2e_session 2
}

teardown() {
    source "$E2E_SETUP"
    teardown_e2e_session
}

@test "busy guard: clear_command does not complete while codex pane is still busy" {
    local pane
    pane="$(pane_target 1)"
    local task_file="$E2E_QUEUE/queue/tasks/sasuke.yaml"

    send_to_pane "$pane" "busy_hold 4"
    sleep 1

    cat > "$task_file" <<'YAML'
task:
  assigned_to: sasuke
  parent_cmd: cmd_e2e_busy
  subtask_id: subtask_e2e_busy
  report_filename: sasuke_report_cmd_e2e_busy.yaml
  status: assigned
YAML

    local watcher_pid
    watcher_pid="$(start_inbox_watcher "sasuke" 1 "codex")"

    run bash "$E2E_QUEUE/scripts/inbox_write.sh" "sasuke" "/clear" "clear_command" "karo"
    [ "$status" -eq 0 ]

    sleep 2
    assert_yaml_field "$task_file" "task.status" "assigned"
    [ ! -f "$E2E_QUEUE/queue/reports/sasuke_report_cmd_e2e_busy.yaml" ]

    wait_for_yaml_value "$task_file" "task.status" "done" 30
    wait_for_file "$E2E_QUEUE/queue/reports/sasuke_report_cmd_e2e_busy.yaml" 15

    stop_inbox_watcher "$watcher_pid"
}
