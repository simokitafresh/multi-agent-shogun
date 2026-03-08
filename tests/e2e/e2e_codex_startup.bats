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

@test "codex startup: /new replays banner and processes assigned task" {
    local pane
    pane="$(pane_target 1)"
    local task_file="$E2E_QUEUE/queue/tasks/sasuke.yaml"

    cat > "$task_file" <<'YAML'
task:
  assigned_to: sasuke
  parent_cmd: cmd_e2e_startup
  subtask_id: subtask_e2e_startup
  report_filename: sasuke_report_cmd_e2e_startup.yaml
  status: assigned
YAML

    tmux respawn-pane -k -t "$pane" \
        "MOCK_CLI_TYPE=codex MOCK_AGENT_ID=sasuke MOCK_PROCESSING_DELAY=1 MOCK_PROJECT_ROOT=$E2E_QUEUE bash $MOCK_CLI"
    sleep 2
    tmux set-option -p -t "$pane" @agent_cli codex

    wait_for_pane_text "$pane" "Codex CLI \\(mock\\)" 10

    run tmux send-keys -t "$pane" "/new" Enter
    [ "$status" -eq 0 ]

    wait_for_yaml_value "$task_file" "task.status" "done" 30
    wait_for_file "$E2E_QUEUE/queue/reports/sasuke_report_cmd_e2e_startup.yaml" 15
    wait_for_pane_text "$pane" "/new received" 10
}
