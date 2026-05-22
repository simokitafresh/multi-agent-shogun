#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_clarity"
}

teardown() {
    deploy_task_teardown
}

run_clarity_check() {
    local ninja_name="${1:-sasuke}"
    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        warn_task_clarity "'"$TEST_PROJECT/queue/tasks/$ninja_name.yaml"'"
    '
}

run_q11_recheck() {
    local ninja_name="${1:-sasuke}"
    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        warn_q11_not_already_done_drift "'"$TEST_PROJECT/queue/tasks/$ninja_name.yaml"'"
    '
}

@test "task clarity: warns when command is long and AC count is too small" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9001:
    command: |
      1行目
      2行目
      3行目
      4行目
      5行目
      6行目
      7行目
      8行目
      9行目
      10行目
    acceptance_criteria:
      - id: AC1
        description: "実装する"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_9001
EOF

    run_clarity_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"command 10行に対してAC 1件"* ]]
}

@test "task clarity: warns when command references missing file paths" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9002:
    command: |
      scripts/missing_file.sh を更新せよ
      queue/tasks/sasuke.yaml を読め
    acceptance_criteria:
      - id: AC1
        description: "確認する"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_9002
EOF

    mkdir -p "$TEST_PROJECT/queue/tasks"
    touch "$TEST_PROJECT/queue/tasks/sasuke.yaml"

    run_clarity_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"scripts/missing_file.sh"* ]]
}

@test "task clarity: warns when AC lacks 確認 and 検証" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9003:
    command: |
      scripts/deploy_task.sh を修正せよ
    acceptance_criteria:
      - id: AC1
        description: "実装する"
      - id: AC2
        description: "commit+push"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_9003
EOF

    run_clarity_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACに「確認」「検証」が含まれない"* ]]
}

@test "task clarity: stays quiet when command is concise, paths exist, and AC includes 確認" {
    mkdir -p "$TEST_PROJECT/scripts"
    touch "$TEST_PROJECT/scripts/deploy_task.sh"

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9004:
    command: |
      scripts/deploy_task.sh を確認せよ
    acceptance_criteria:
      - id: AC1
        description: "動作確認を実施する"
      - id: AC2
        description: "既存テストを確認する"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_9004
EOF

    run_clarity_check
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "q11 recheck: warns when target_path grep hits increased" {
    mkdir -p "$TEST_PROJECT/testdata"
    cat > "$TEST_PROJECT/testdata/q11_target.sh" <<'EOF'
q11_not_already_done
EOF

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9005:
    quality_gate:
      q11_not_already_done: "grep -n 'q11_not_already_done' testdata/q11_target.sh — 0件。配備時q11再チェック機能は未実装"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: cmd_9005
  target_path: $TEST_PROJECT/testdata/q11_target.sh
EOF

    run_q11_recheck
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: q11_not_already_done drift (cmd_9005)"* ]]
    [[ "$output" == *"起票時 0件 → 配備時 1件"* ]]
}

@test "q11 recheck: stays quiet when target_path grep hits are unchanged" {
    mkdir -p "$TEST_PROJECT/testdata"
    : > "$TEST_PROJECT/testdata/q11_target.sh"

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_9006:
    quality_gate:
      q11_not_already_done: "grep -n 'q11_not_already_done' testdata/q11_target.sh — 0件。配備時q11再チェック機能は未実装"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: cmd_9006
  target_path: $TEST_PROJECT/testdata/q11_target.sh
EOF

    run_q11_recheck
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
