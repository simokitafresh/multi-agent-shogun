#!/usr/bin/env bats
# ═══════════════════════════════════════════════════════════════
# E2E-004: Escalation / Busy State Test
# ═══════════════════════════════════════════════════════════════
# Validates busy state behavior:
#   1. Agent in busy_hold state cannot process inbox immediately
#   2. After busy_hold ends, queued input is processed
#   3. Task eventually completes
#
# Adapted from yohey-w/multi-agent-shogun for local layout.
# Uses mock_cli.sh busy_hold command (no inbox_watcher needed).
# ═══════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════
# E2E-004-A: Busy agent defers processing, completes after idle
# ═══════════════════════════════════════════════════════════════

@test "E2E-004-A: busy agent defers inbox processing until idle" {
    local sasuke_pane
    sasuke_pane=$(pane_target 1)

    # 1. Place task YAML
    cp "$PROJECT_ROOT/tests/e2e/fixtures/task_sasuke_basic.yaml" \
       "$E2E_QUEUE/queue/tasks/sasuke.yaml"

    # 2. Write task_assigned to inbox
    bash "$E2E_QUEUE/scripts/inbox_write.sh" "sasuke" \
        "タスクYAMLを読んで作業開始せよ。" "task_assigned" "karo"

    # 3. Put agent into busy state for 6 seconds BEFORE sending nudge
    send_to_pane "$sasuke_pane" "busy_hold 6"
    sleep 2  # Ensure busy state is active

    # 4. Verify agent is busy (pane shows Working)
    run wait_for_pane_text "$sasuke_pane" "esc to interrupt" 5
    [ "$status" -eq 0 ]

    # 5. Send nudge — will queue in terminal input buffer
    send_to_pane "$sasuke_pane" "inbox1"

    # 6. Task should NOT be done yet (agent is busy)
    sleep 1
    local task_status
    task_status=$(python3 -c "
import yaml
try:
    with open('$E2E_QUEUE/queue/tasks/sasuke.yaml') as f:
        data = yaml.safe_load(f)
    print(data.get('task',{}).get('status',''))
except: print('')
" 2>/dev/null)
    [ "$task_status" = "assigned" ]

    # 7. Wait for busy_hold to end + inbox processing
    run wait_for_yaml_value "$E2E_QUEUE/queue/tasks/sasuke.yaml" "task.status" "done" 30
    [ "$status" -eq 0 ]

    # 8. Report should exist
    run wait_for_file "$E2E_QUEUE/queue/reports/sasuke_report.yaml" 10
    [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# E2E-004-B: busy_hold correctly transitions idle → busy → idle
# ═══════════════════════════════════════════════════════════════

@test "E2E-004-B: busy_hold shows correct state transitions" {
    local sasuke_pane
    sasuke_pane=$(pane_target 1)

    # 1. Send busy_hold for 4 seconds
    send_to_pane "$sasuke_pane" "busy_hold 4"

    # 2. Verify busy state appears
    run wait_for_pane_text "$sasuke_pane" "esc to interrupt" 5
    [ "$status" -eq 0 ]

    # 3. Wait for busy_hold to finish
    sleep 5

    # 4. Send a health check to verify agent is responsive again
    send_to_pane "$sasuke_pane" "health_check"
    run wait_for_pane_text "$sasuke_pane" "Processed input: health_check" 10
    [ "$status" -eq 0 ]
}
