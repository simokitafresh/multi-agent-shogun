#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export E2E_SETUP="$PROJECT_ROOT/tests/e2e/helpers/setup.bash"
    export E2E_ASSERT="$PROJECT_ROOT/tests/e2e/helpers/assertions.bash"
    export E2E_TMUX="$PROJECT_ROOT/tests/e2e/helpers/tmux_helpers.bash"
    export MOCK_CLI="$PROJECT_ROOT/tests/e2e/mock_cli.sh"
    [ -f "$E2E_SETUP" ] || return 1
    [ -f "$E2E_ASSERT" ] || return 1
    [ -f "$E2E_TMUX" ] || return 1
}

setup() {
    source "$E2E_SETUP"
    source "$E2E_ASSERT"
    source "$E2E_TMUX"

    export E2E_MOCK_CLI_PATH="$MOCK_CLI"
    export E2E_MOCK_DELAY=1
    setup_e2e_session 3
}

teardown() {
    source "$E2E_SETUP"
    teardown_e2e_session
}

@test "basic flow: watcher nudge completes sasuke task" {
    local task_file="$E2E_QUEUE/queue/tasks/sasuke.yaml"
    cat > "$task_file" <<'YAML'
task:
  assigned_to: sasuke
  parent_cmd: cmd_e2e_basic
  subtask_id: subtask_e2e_basic
  report_filename: sasuke_report_cmd_e2e_basic.yaml
  status: assigned
YAML

    run bash "$E2E_QUEUE/scripts/inbox_write.sh" "sasuke" "basic flow" "task_assigned" "karo"
    [ "$status" -eq 0 ]

    send_to_pane "$(pane_target 1)" "inbox1"
    wait_for_yaml_value "$task_file" "task.status" "done" 30
    wait_for_file "$E2E_QUEUE/queue/reports/sasuke_report_cmd_e2e_basic.yaml" 15
    assert_inbox_unread_count "$E2E_QUEUE/queue/inbox/sasuke.yaml" 0
    wait_for_pane_text "$(pane_target 1)" "EVENT inbox1" 15
}
