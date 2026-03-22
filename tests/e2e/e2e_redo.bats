#!/usr/bin/env bats
# ═══════════════════════════════════════════════════════════════
# E2E-005: Redo Test
# ═══════════════════════════════════════════════════════════════
# Validates the redo protocol:
#   1. Initial task completes (status: done, report written)
#   2. New task YAML written with redo_of field
#   3. /clear sent directly to agent (simulates inbox_watcher clear_command)
#   4. Agent resets, reads new task YAML, processes redo task
#   5. New report written with new task_id
#   6. redo_of field preserved in task YAML
#
# Adapted from yohey-w/multi-agent-shogun for local layout.
# Uses direct /clear via send_to_pane (no inbox_watcher needed).
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
# E2E-005-A: Complete redo flow — initial task → redo → new task processed
# ═══════════════════════════════════════════════════════════════

@test "E2E-005-A: redo via /clear replaces task and produces new report" {
    local sasuke_pane
    sasuke_pane=$(pane_target 1)

    # ─── Phase 1: Complete initial task ───

    # 1. Place initial task and process via direct nudge
    cp "$PROJECT_ROOT/tests/e2e/fixtures/task_sasuke_basic.yaml" \
       "$E2E_QUEUE/queue/tasks/sasuke.yaml"

    bash "$E2E_QUEUE/scripts/inbox_write.sh" "sasuke" \
        "初回タスク開始。" "task_assigned" "karo"
    send_to_pane "$sasuke_pane" "inbox1"

    # 2. Wait for initial task to complete
    run wait_for_yaml_value "$E2E_QUEUE/queue/tasks/sasuke.yaml" "task.status" "done" 30
    [ "$status" -eq 0 ]

    # 3. Verify initial report
    run wait_for_file "$E2E_QUEUE/queue/reports/sasuke_report.yaml" 10
    [ "$status" -eq 0 ]
    assert_yaml_field "$E2E_QUEUE/queue/reports/sasuke_report.yaml" "task_id" "subtask_test_001a"

    # ─── Phase 2: Redo ───

    # 4. Write redo task YAML (new task_id, redo_of field, status: assigned)
    cat > "$E2E_QUEUE/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: subtask_test_001a2
  parent_cmd: cmd_test_001
  type: implementation
  redo_of: subtask_test_001a
  description: |
    Redo task: re-execute with corrections.
  status: assigned
  timestamp: "2026-01-01T01:00:00"
EOF

    # 5. Send /clear directly (simulates inbox_watcher clear_command delivery)
    send_to_pane "$sasuke_pane" "/clear"

    # 6. Wait for redo task to complete
    run wait_for_yaml_value "$E2E_QUEUE/queue/tasks/sasuke.yaml" "task.status" "done" 30
    [ "$status" -eq 0 ]

    # 7. Verify new report has new task_id
    assert_yaml_field "$E2E_QUEUE/queue/reports/sasuke_report.yaml" "task_id" "subtask_test_001a2"
    assert_yaml_field "$E2E_QUEUE/queue/reports/sasuke_report.yaml" "status" "done"

    # 8. Verify redo_of field is preserved in task YAML
    assert_yaml_field "$E2E_QUEUE/queue/tasks/sasuke.yaml" "task.redo_of" "subtask_test_001a"
}

# ═══════════════════════════════════════════════════════════════
# E2E-005-B: Redo does not corrupt inbox — all messages processed
# ═══════════════════════════════════════════════════════════════

@test "E2E-005-B: redo preserves task history — redo_of field intact" {
    local sasuke_pane
    sasuke_pane=$(pane_target 1)

    # 1. Complete initial task via direct nudge
    cp "$PROJECT_ROOT/tests/e2e/fixtures/task_sasuke_basic.yaml" \
       "$E2E_QUEUE/queue/tasks/sasuke.yaml"

    bash "$E2E_QUEUE/scripts/inbox_write.sh" "sasuke" \
        "初回タスク開始。" "task_assigned" "karo"
    send_to_pane "$sasuke_pane" "inbox1"

    run wait_for_yaml_value "$E2E_QUEUE/queue/tasks/sasuke.yaml" "task.status" "done" 30
    [ "$status" -eq 0 ]

    # 2. Save initial report task_id
    assert_yaml_field "$E2E_QUEUE/queue/reports/sasuke_report.yaml" "task_id" "subtask_test_001a"

    # 3. Write redo task YAML
    cat > "$E2E_QUEUE/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: subtask_test_001a2
  parent_cmd: cmd_test_001
  type: implementation
  redo_of: subtask_test_001a
  description: |
    Redo task for history test.
  status: assigned
  timestamp: "2026-01-01T01:00:00"
EOF

    # 4. Send /clear directly (simulates inbox_watcher clear_command delivery)
    send_to_pane "$sasuke_pane" "/clear"

    # 5. Wait for redo task to complete
    run wait_for_yaml_value "$E2E_QUEUE/queue/tasks/sasuke.yaml" "task.status" "done" 30
    [ "$status" -eq 0 ]

    # 6. Report now has the NEW task_id (overwritten)
    assert_yaml_field "$E2E_QUEUE/queue/reports/sasuke_report.yaml" "task_id" "subtask_test_001a2"

    # 7. redo_of field preserved in task YAML
    assert_yaml_field "$E2E_QUEUE/queue/tasks/sasuke.yaml" "task.redo_of" "subtask_test_001a"
}
