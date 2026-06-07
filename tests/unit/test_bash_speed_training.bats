#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_ROOT="$(mktemp -d)"
    LEDGER="$TMP_ROOT/script_speed_training_ledger.yaml"
    export SPEED_TRAINING_LEDGER="$LEDGER"
    export SHOGUN_STATE_DIR="$TMP_ROOT/state"
    export SPEED_TRAINING_TASK_DIR="$TMP_ROOT/tasks"
    mkdir -p "$SPEED_TRAINING_TASK_DIR"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

@test "init-ledger records every scripts/*.sh file with non-destructive bash -n syntax baseline and real timing columns" {
    run bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"
    [ "$status" -eq 0 ]

    expected=$(find "$PROJECT_ROOT/scripts" -type f -name '*.sh' | wc -l | tr -d ' ')
    entry_count=$(grep -c 'script_path:' "$LEDGER")

    [ "$entry_count" = "$expected" ]
    grep -Fq "script_count: $expected" "$LEDGER"
    grep -Fq 'measurement_command: "timeout 5 bash -n <script_path> (syntax baseline only; not runtime speed)"' "$LEDGER"
    grep -Fq 'real_measurement_policy: "Ninja must choose a safe runtime command per script:' "$LEDGER"
    grep -Eq 'before_ms: [0-9]+' "$LEDGER"
    grep -Fq 'before_real_ms: ""' "$LEDGER"
    grep -Fq 'after_real_ms: ""' "$LEDGER"
    grep -Fq 'real_measurement_command: ""' "$LEDGER"
    grep -Fq 'global_status: running' "$LEDGER"
}

@test "paused ledger prevents auto-deploy" {
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" set-global-status paused "$LEDGER"

    run bash "$PROJECT_ROOT/tools/bash_speed_training.sh" auto-deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "paused" ]
    ! grep -Fq 'status: assigned' "$LEDGER"
}

@test "auto-deploy dry-run assigns exactly one pending script and emits deploy_task command" {
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"

    run env SPEED_TRAINING_DRY_RUN=1 bash "$PROJECT_ROOT/tools/bash_speed_training.sh" auto-deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]
    [[ "$output" == DRY_RUN\ deploy_task* ]]
    [[ "$output" == *" hayate cmd_training_speed_"* ]]

    assigned_count=$(grep -c 'status: assigned' "$LEDGER")
    [ "$assigned_count" = "1" ]
    grep -Fq 'assigned_to: "hayate"' "$LEDGER"
}

@test "auto-deploy skips scripts already active in task yaml" {
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"
    first=$(bash "$PROJECT_ROOT/tools/bash_speed_training.sh" next "$LEDGER")
    cat > "$SPEED_TRAINING_TASK_DIR/hayate.yaml" <<EOF
task:
  status: in_progress
  target_path: $first
EOF

    run env SPEED_TRAINING_DRY_RUN=1 bash "$PROJECT_ROOT/tools/bash_speed_training.sh" auto-deploy kagemaru "$LEDGER"
    [ "$status" -eq 0 ]
    [[ "$output" == DRY_RUN\ deploy_task* ]]

    awk -v first="$first" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; next }
        in_first && /status:/ { first_status = $2; in_first = 0 }
        /status: assigned/ { assigned_count++ }
        END { exit !(first_status == "pending" && assigned_count == 1) }
    ' "$LEDGER"
}

@test "auto-deploy reassigns no_improvement entries for rework" {
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"
    first=$(bash "$PROJECT_ROOT/tools/bash_speed_training.sh" next "$LEDGER")
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" record-after "$first" no_improvement 12 "no improvement" no_change "$LEDGER"

    run env SPEED_TRAINING_DRY_RUN=1 bash "$PROJECT_ROOT/tools/bash_speed_training.sh" auto-deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]

    awk -v first="$first" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; next }
        in_first && /status: assigned/ { status_seen = 1 }
        in_first && /assigned_to: "hayate"/ { assignee_seen = 1 }
        in_first && /^[[:space:]]*-[[:space:]]+script_path:/ { in_first = 0 }
        END { exit !(status_seen && assignee_seen) }
    ' "$LEDGER"
}

@test "auto-deploy generated task preserves speed purpose and real runtime ACs" {
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"

    run env SPEED_TRAINING_DRY_RUN=1 bash "$PROJECT_ROOT/tools/bash_speed_training.sh" auto-deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]

    generated_task=$(find "$SHOGUN_STATE_DIR" -type f -name 'speed_training_hayate.*.yaml' | head -n 1)
    [ -n "$generated_task" ]
    grep -Fq 'task_type: speed_training' "$generated_task"
    grep -Fq 'purpose: "Speed-train ' "$generated_task"
    grep -Fq 'before_real_ms is measured with a safe runtime command chosen for this script' "$generated_task"
    grep -Fq 'after_real_ms is measured with the same command as before_real_ms' "$generated_task"
    grep -Fq 'real_measurement_command/test_result/commit are written back to script_speed_training_ledger' "$generated_task"
    ! grep -Fq 'L4修行:' "$generated_task"

    run env FIELD_GET_NO_LOG=1 bash -c '
        source "$1/scripts/lib/field_get.sh"
        printf "%s %s" "$(field_get "$2" task_type "")" "$(field_get "$2" scout_exempt "")"
    ' _ "$PROJECT_ROOT" "$generated_task"
    [ "$status" -eq 0 ]
    [ "$output" = "speed_training true" ]

    run env DEPLOY_TASK_LIB_ONLY=1 bash -c '
        set -euo pipefail
        source "$1/scripts/deploy_task.sh"
        log() { :; }
        inject_direct_training_template "$2" cmd_training_speed_sample_20260606213918
    ' _ "$PROJECT_ROOT" "$generated_task"
    [ "$status" -eq 0 ]
    grep -Fq 'task_type: speed_training' "$generated_task"
    grep -Fq 'purpose: "Speed-train ' "$generated_task"
    grep -Fq 'before_real_ms is measured with a safe runtime command chosen for this script' "$generated_task"
    grep -Fq 'after_real_ms is measured with the same command as before_real_ms' "$generated_task"
    grep -Fq 'real_measurement_command/test_result/commit are written back to script_speed_training_ledger' "$generated_task"
    ! grep -Fq 'L4修行:' "$generated_task"
}

@test "record-after writes after measurement, test result, commit, and terminal status" {
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"
    first=$(bash "$PROJECT_ROOT/tools/bash_speed_training.sh" next "$LEDGER")

    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" record-after "$first" completed 12 "bats target PASS SKIP=0" abc123 "$LEDGER"

    awk -v script="$first" '
        $0 ~ "script_path: \"" script "\"" { in_target = 1 }
        in_target && /status: completed/ { status_seen = 1 }
        in_target && /after_ms: 12/ { after_seen = 1 }
        in_target && /test_result: "bats target PASS SKIP=0"/ { test_seen = 1 }
        in_target && /commit: "abc123"/ { commit_seen = 1 }
        END { exit !(status_seen && after_seen && test_seen && commit_seen) }
    ' "$LEDGER"
}

@test "record-real writes runtime before and after with measurement command" {
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"
    first=$(bash "$PROJECT_ROOT/tools/bash_speed_training.sh" next "$LEDGER")

    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" record-real "$first" completed 101 72 "time bash $first --help" "bats target PASS SKIP=0" abc123 "$LEDGER"

    awk -v script="$first" '
        $0 ~ "script_path: \"" script "\"" { in_target = 1 }
        in_target && /status: completed/ { status_seen = 1 }
        in_target && /before_real_ms: 101/ { before_seen = 1 }
        in_target && /after_real_ms: 72/ { after_seen = 1 }
        in_target && /real_measurement_command: "time bash / { command_seen = 1 }
        in_target && /test_result: "bats target PASS SKIP=0"/ { test_seen = 1 }
        in_target && /commit: "abc123"/ { commit_seen = 1 }
        END { exit !(status_seen && before_seen && after_seen && command_seen && test_seen && commit_seen) }
    ' "$LEDGER"
}

@test "record-real completed rejects non-improving runtime" {
    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"
    first=$(bash "$PROJECT_ROOT/tools/bash_speed_training.sh" next "$LEDGER")

    run bash "$PROJECT_ROOT/tools/bash_speed_training.sh" record-real "$first" completed 101 101 "time bash $first --help" "bats target PASS SKIP=0" abc123 "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"after_real_ms < before_real_ms"* ]]
}

@test "ninja_monitor handles speed training before legacy training auto-deploy" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

calls=""
_handle_post_clear_pending() { return 1; }
_handle_deploy_stall() { return 1; }
_clear_stall_tracking_for_completed_idle() { :; }
_handle_idle_notify() { :; }
_record_training_effect() { :; }
_handle_speed_training_auto_deploy() { calls="${calls}speed "; return 0; }
_handle_training_auto_deploy() { calls="${calls}legacy "; return 0; }
_handle_auto_clear() { calls="${calls}clear "; return 0; }

declare -gA PREV_STATE
handle_confirmed_idle hayate
printf "%s" "$calls"
'
    [ "$status" -eq 0 ]
    [ "$output" = "speed " ]
}
