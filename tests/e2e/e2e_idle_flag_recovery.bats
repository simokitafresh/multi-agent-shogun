#!/usr/bin/env bats
# ═══════════════════════════════════════════════════════════════
# E2E-010: /clear delivery + idle state recovery
# ═══════════════════════════════════════════════════════════════
# Adapted from yohey-w/multi-agent-shogun E2E-010 (idle flag recovery).
# yohey-w版はIDLE_FLAG_DIR/forcing idle flag機能を検証。
# ローカル版は同等の意味を持つ動作を検証:
#   A) claude agent: idle flag → clear_command delivered → task completes
#   B) busy agent: clear_command deferred → busy_hold ends → delivered
# ═══════════════════════════════════════════════════════════════

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
    setup_e2e_session 3
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

# ═══ E2E-010-A: claude agent /clear recovery via idle flag ═══

@test "E2E-010-A: claude clear_command delivery restores idle state" {
    local pane
    pane="$(pane_target 0)"
    local task_file="$E2E_QUEUE/queue/tasks/karo.yaml"
    local log_file="$E2E_ROOT/inbox_watcher_karo.log"

    cat > "$task_file" <<'YAML'
task:
  assigned_to: karo
  parent_cmd: cmd_e2e_idle_010a
  subtask_id: subtask_e2e_idle_010a
  report_filename: karo_report_cmd_e2e_idle_010a.yaml
  status: assigned
YAML

    # karo is claude type — idle flag is created by mock_cli on startup
    local watcher_pid
    watcher_pid="$(start_inbox_watcher "karo" 0 "claude")"

    run bash "$E2E_QUEUE/scripts/inbox_write.sh" "karo" "/clear" "clear_command" "karo"
    [ "$status" -eq 0 ]

    wait_for_yaml_value "$task_file" "task.status" "done" 45
    wait_for_file "$E2E_QUEUE/queue/reports/karo_report_cmd_e2e_idle_010a.yaml" 15

    # Agent should be back to idle state
    run tmux display-message -t "$pane" -p '#{@agent_state}'
    [ "$status" -eq 0 ]
    [ "$output" = "idle" ]

    # Idle flag should be restored (mock_cli creates it on idle for claude)
    [ -f "$SHOGUN_STATE_DIR/shogun_idle_karo" ]

    stop_inbox_watcher "$watcher_pid"
}

# ═══ E2E-010-B: busy agent defers clear_command ═══

@test "E2E-010-B: busy codex agent defers clear_command until idle" {
    local pane
    pane="$(pane_target 1)"
    local task_file="$E2E_QUEUE/queue/tasks/sasuke.yaml"
    local log_file="$E2E_ROOT/inbox_watcher_sasuke.log"

    cat > "$task_file" <<'YAML'
task:
  assigned_to: sasuke
  parent_cmd: cmd_e2e_idle_010b
  subtask_id: subtask_e2e_idle_010b
  report_filename: sasuke_report_cmd_e2e_idle_010b.yaml
  status: assigned
YAML

    tmux set-option -p -t "$pane" @agent_cli codex

    # Put agent into busy state BEFORE starting watcher
    send_to_pane "$pane" "busy_hold 6"
    sleep 1

    local watcher_pid
    watcher_pid="$(start_inbox_watcher "sasuke" 1 "codex")"

    run bash "$E2E_QUEUE/scripts/inbox_write.sh" "sasuke" "/clear" "clear_command" "karo"
    [ "$status" -eq 0 ]

    # busy_hold中はclear_commandが即時実行されず、taskはまだ未完了のはず
    sleep 2
    run python3 -c "
import yaml
with open('$task_file') as f:
    data = yaml.safe_load(f) or {}
print(data.get('task', {}).get('status', ''))
"
    [ "$status" -eq 0 ]
    [ "$output" = "assigned" ]

    # After busy_hold ends, task should complete
    wait_for_yaml_value "$task_file" "task.status" "done" 45

    # Agent should return to idle
    run tmux display-message -t "$pane" -p '#{@agent_state}'
    [ "$status" -eq 0 ]
    [ "$output" = "idle" ]

    stop_inbox_watcher "$watcher_pid"
}
