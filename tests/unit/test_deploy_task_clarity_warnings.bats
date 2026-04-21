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
    [[ "$output" == *"has 1 ACs for a 10-line command"* ]]
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
    [[ "$output" == *"ACs do not include confirm/verify wording"* ]]
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
        description: "Confirm the behavior"
      - id: AC2
        description: "Verify the existing tests"
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_9004
EOF

    run_clarity_check
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
