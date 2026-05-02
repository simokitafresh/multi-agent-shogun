#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_same_ninja"
}

teardown() {
    deploy_task_teardown
}

run_same_ninja_warn() {
    local ninja_name="${1:-sasuke}"
    local parent_cmd="${2:-cmd_9005}"
    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        _DEPLOY_PREV_PARENT_CMD="'"$parent_cmd"'"
        _DEPLOY_PREV_SESSION_STATE="{\"attempt\": 1}"
        warn_same_ninja_redeploy "'"$TEST_PROJECT/queue/tasks/$ninja_name.yaml"'" "'"$ninja_name"'" "'"$parent_cmd"'"
    '
}

@test "same ninja redeploy: previous session state and report emit WARNING" {
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_9005
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_9005.yaml" <<'EOF'
worker_id: sasuke
task_id: cmd_9005_impl
status: pending
verdict: ""
EOF

    run_same_ninja_warn sasuke cmd_9005
    [ "$status" -eq 0 ]
    [[ "$output" == *"same-ninja redeploy (cmd_9005 → sasuke)"* ]]
    [[ "$output" == *"session_state残存"* ]]
    [[ "$output" == *"同忍者の既存報告あり"* ]]
}

@test "same ninja redeploy: fresh deploy stays quiet" {
    mkdir -p "$TEST_PROJECT/queue/tasks"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_9006
EOF

    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        unset _DEPLOY_PREV_PARENT_CMD
        unset _DEPLOY_PREV_SESSION_STATE
        warn_same_ninja_redeploy "'"$TEST_PROJECT/queue/tasks/sasuke.yaml"'" sasuke cmd_9006
    '
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "done redeploy: completed report path is reused and diff-only note is injected" {
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  parent_cmd: cmd_9007
  task_id: cmd_9007_impl
  status: done
  report_path: queue/reports/sasuke_report_cmd_9007.yaml
  report_filename: sasuke_report_cmd_9007.yaml
  description: old description
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_9007.yaml" <<'EOF'
worker_id: sasuke
task_id: cmd_9007_impl
parent_cmd: cmd_9007
status: completed
files_modified:
  - scripts/deploy_task.sh
binary_checks:
  AC3:
    - check: "done report carried"
      result: "yes"
verdict: PASS
EOF

    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        capture_done_redeploy_context "'"$TEST_PROJECT/queue/tasks/sasuke.yaml"'" cmd_9007
        cat > "'"$TEST_PROJECT/queue/tasks/sasuke.yaml"'" <<'"'"'EOF'"'"'
task:
  parent_cmd: cmd_9007
  task_id: cmd_9007_impl
  status: assigned
  description: rerun deploy
EOF
        inject_done_redeploy_hints "'"$TEST_PROJECT/queue/tasks/sasuke.yaml"'"
        printf "reuse=%s report=%s\n" "${_DEPLOY_DONE_REUSE:-0}" "${_DEPLOY_DONE_REPORT_PATH:-}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"reuse=1 report=queue/reports/sasuke_report_cmd_9007.yaml"* ]]

    run grep -q "【再配備引継ぎ】" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    run grep -q "差分のみ再検証せよ" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    run grep -q "description: .* | rerun deploy" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]

    run grep -q "report_path: queue/reports/sasuke_report_cmd_9007.yaml" "$TEST_PROJECT/queue/tasks/sasuke.yaml"
    [ "$status" -eq 0 ]
}
