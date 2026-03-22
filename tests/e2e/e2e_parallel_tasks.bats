#!/usr/bin/env bats
# ═══════════════════════════════════════════════════════════════
# E2E-006: Parallel Tasks Test
# ═══════════════════════════════════════════════════════════════
# Validates that multiple agents can process tasks simultaneously:
#   1. Two tasks assigned to sasuke and kirimaru
#   2. Both receive inbox nudges
#   3. Both complete independently
#   4. Both reports are written
#
# Adapted from yohey-w/multi-agent-shogun for local layout.
# Uses 3-pane setup (karo + sasuke + kirimaru).
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
# E2E-006-A: Two agents process tasks in parallel
# ═══════════════════════════════════════════════════════════════

@test "E2E-006-A: sasuke and kirimaru complete tasks in parallel" {
    # 1. Place tasks for both agents
    cp "$PROJECT_ROOT/tests/e2e/fixtures/task_sasuke_basic.yaml" \
       "$E2E_QUEUE/queue/tasks/sasuke.yaml"
    cp "$PROJECT_ROOT/tests/e2e/fixtures/task_kirimaru_basic.yaml" \
       "$E2E_QUEUE/queue/tasks/kirimaru.yaml"

    # 2. Send task_assigned to both inboxes
    bash "$E2E_QUEUE/scripts/inbox_write.sh" "sasuke" \
        "タスクYAMLを読んで作業開始せよ。" "task_assigned" "karo"
    bash "$E2E_QUEUE/scripts/inbox_write.sh" "kirimaru" \
        "タスクYAMLを読んで作業開始せよ。" "task_assigned" "karo"

    # 3. Nudge both simultaneously
    local sasuke_pane kirimaru_pane
    sasuke_pane=$(pane_target 1)
    kirimaru_pane=$(pane_target 2)

    send_to_pane "$sasuke_pane" "inbox1"
    send_to_pane "$kirimaru_pane" "inbox1"

    # 4. Both should complete
    run wait_for_yaml_value "$E2E_QUEUE/queue/tasks/sasuke.yaml" "task.status" "done" 30
    [ "$status" -eq 0 ]
    run wait_for_yaml_value "$E2E_QUEUE/queue/tasks/kirimaru.yaml" "task.status" "done" 30
    [ "$status" -eq 0 ]

    # 5. Both reports should exist
    run wait_for_file "$E2E_QUEUE/queue/reports/sasuke_report.yaml" 10
    [ "$status" -eq 0 ]
    run wait_for_file "$E2E_QUEUE/queue/reports/kirimaru_report.yaml" 10
    [ "$status" -eq 0 ]

    # 6. Reports should have correct agent IDs
    assert_yaml_field "$E2E_QUEUE/queue/reports/sasuke_report.yaml" "worker_id" "sasuke"
    assert_yaml_field "$E2E_QUEUE/queue/reports/kirimaru_report.yaml" "worker_id" "kirimaru"
}

# ═══════════════════════════════════════════════════════════════
# E2E-006-B: Parallel tasks don't interfere with each other's inbox
# ═══════════════════════════════════════════════════════════════

@test "E2E-006-B: parallel tasks maintain inbox isolation" {
    # 1. Place tasks and send notifications
    cp "$PROJECT_ROOT/tests/e2e/fixtures/task_sasuke_basic.yaml" \
       "$E2E_QUEUE/queue/tasks/sasuke.yaml"
    cp "$PROJECT_ROOT/tests/e2e/fixtures/task_kirimaru_basic.yaml" \
       "$E2E_QUEUE/queue/tasks/kirimaru.yaml"

    bash "$E2E_QUEUE/scripts/inbox_write.sh" "sasuke" \
        "タスクYAMLを読んで作業開始せよ。" "task_assigned" "karo"
    bash "$E2E_QUEUE/scripts/inbox_write.sh" "kirimaru" \
        "タスクYAMLを読んで作業開始せよ。" "task_assigned" "karo"

    local sasuke_pane kirimaru_pane
    sasuke_pane=$(pane_target 1)
    kirimaru_pane=$(pane_target 2)

    send_to_pane "$sasuke_pane" "inbox1"
    send_to_pane "$kirimaru_pane" "inbox1"

    # 2. Wait for both to complete
    run wait_for_yaml_value "$E2E_QUEUE/queue/tasks/sasuke.yaml" "task.status" "done" 30
    [ "$status" -eq 0 ]
    run wait_for_yaml_value "$E2E_QUEUE/queue/tasks/kirimaru.yaml" "task.status" "done" 30
    [ "$status" -eq 0 ]

    # 3. Each inbox should have its own messages (no cross-contamination)
    # sasuke's inbox should NOT have kirimaru's messages
    run python3 -c "
import yaml
with open('$E2E_QUEUE/queue/inbox/sasuke.yaml') as f:
    data = yaml.safe_load(f) or {}
msgs = data.get('messages', [])
for m in msgs:
    if m.get('type') == 'task_assigned' and 'kirimaru' in str(m.get('content', '')):
        print('CROSS-CONTAMINATION DETECTED')
        exit(1)
"
    [ "$status" -eq 0 ]
}
