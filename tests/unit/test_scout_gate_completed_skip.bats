#!/usr/bin/env bats
# test_scout_gate_completed_skip.bats - 完了済みタスクのscout_gate再検査スキップ

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "scout_gate_skip"

    # shogun_to_karo.yaml (scout_exempt無し)
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_test_scout:
    id: cmd_test_scout
    scout_exempt: false
EOF
}

teardown() {
    deploy_task_teardown
}

# Helper: check_scout_gateだけを実行するラッパー
run_scout_gate() {
    local task_file="$1"
    run bash -c "
        export SCRIPT_DIR='$TEST_PROJECT'
        source '$TEST_PROJECT/scripts/lib/field_get.sh'
        source '$TEST_PROJECT/scripts/lib/yaml_field_set.sh'
        log() { echo \"\$*\"; }
        FIELD_GET_NO_LOG=1

        $(sed -n '/^check_scout_gate()/,/^}/p' "$TEST_PROJECT/scripts/deploy_task.sh")

        check_scout_gate '$task_file'
    "
}

# --- AC3: status=assigned + implタスク + 偵察なし → BLOCK ---
@test "scout_gate BLOCKs assigned impl task without scouts" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_scout_sasuke_impl
  parent_cmd: cmd_test_scout
  status: assigned
  task_type: impl
  acceptance_criteria:
    - id: AC1
      description: "test"
EOF

    run_scout_gate "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(scout_gate)"* ]]
}

# --- AC1+AC3: status=done + implタスク → PASS (再検査スキップ) ---
@test "scout_gate PASSes done impl task (skip re-check)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_scout_sasuke_impl
  parent_cmd: cmd_test_scout
  status: done
  task_type: impl
  acceptance_criteria:
    - id: AC1
      description: "test"
EOF

    run_scout_gate "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"scout_gate: PASS: status=done (completed task, skip re-check)"* ]]
}

# --- status=idle → PASS ---
@test "scout_gate PASSes idle task (skip re-check)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_scout_sasuke_impl
  parent_cmd: cmd_test_scout
  status: idle
  task_type: impl
  acceptance_criteria:
    - id: AC1
      description: "test"
EOF

    run_scout_gate "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"scout_gate: PASS: status=idle (completed task, skip re-check)"* ]]
}

# --- status=completed → PASS ---
@test "scout_gate PASSes completed task (skip re-check)" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_scout_sasuke_impl
  parent_cmd: cmd_test_scout
  status: completed
  task_type: impl
  acceptance_criteria:
    - id: AC1
      description: "test"
EOF

    run_scout_gate "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"scout_gate: PASS: status=completed (completed task, skip re-check)"* ]]
}

# --- status=acknowledged (作業中) → BLOCKのまま ---
@test "scout_gate still BLOCKs acknowledged impl task without scouts" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_test_scout_sasuke_impl
  parent_cmd: cmd_test_scout
  status: acknowledged
  task_type: impl
  acceptance_criteria:
    - id: AC1
      description: "test"
EOF

    run_scout_gate "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(scout_gate)"* ]]
}

@test "scout_gate PASSes karo_direct impl task with task-local scout_exempt" {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: cmd_karo_direct_sasuke_impl
  parent_cmd: cmd_karo_direct_missing_from_stk
  status: assigned
  task_type: impl
  scout_exempt: true
  acceptance_criteria:
    - id: AC1
      description: "test"
EOF

    run_scout_gate "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"scout_gate: PASS: scout_exempt=true in task YAML for cmd_karo_direct_missing_from_stk"* ]]
}
