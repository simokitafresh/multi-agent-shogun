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
    [[ "$output" == *"same-ninja redeploy detected (cmd_9005 -> sasuke)"* ]]
    [[ "$output" == *"session_state still present"* ]]
    [[ "$output" == *"existing report for the same ninja"* ]]
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
