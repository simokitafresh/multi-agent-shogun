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

wait_for_log_text() {
    local log_file="$1"
    local pattern="$2"
    local timeout="${3:-20}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        if grep -qF "$pattern" "$log_file" 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "TIMEOUT: '$pattern' not found in $log_file" >&2
    return 1
}

@test "clear recovery: codex clear_command maps to /new and completes task" {
    local pane
    pane="$(pane_target 1)"
    local task_file="$E2E_QUEUE/queue/tasks/sasuke.yaml"
    local log_file="$E2E_ROOT/inbox_watcher_sasuke.log"

    cat > "$task_file" <<'YAML'
task:
  assigned_to: sasuke
  parent_cmd: cmd_e2e_clear
  subtask_id: subtask_e2e_clear
  report_filename: sasuke_report_cmd_e2e_clear.yaml
  status: assigned
YAML

    tmux set-option -p -t "$pane" @agent_cli codex

    local watcher_pid
    watcher_pid="$(start_inbox_watcher "sasuke" 1 "codex")"

    run bash "$E2E_QUEUE/scripts/inbox_write.sh" "sasuke" "/clear" "clear_command" "karo"
    [ "$status" -eq 0 ]

    wait_for_yaml_value "$task_file" "task.status" "done" 45
    wait_for_file "$E2E_QUEUE/queue/reports/sasuke_report_cmd_e2e_clear.yaml" 15
    wait_for_log_text "$log_file" "Sending CLI command to sasuke (codex): /new" 15
    wait_for_pane_text "$pane" "/new received" 15

    stop_inbox_watcher "$watcher_pid"
}
