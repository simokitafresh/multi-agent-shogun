#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    FIXTURE_ROOT="$(mktemp -d)"
    BASE_LEDGER="$FIXTURE_ROOT/script_speed_training_ledger.yaml"
    export PROJECT_ROOT FIXTURE_ROOT BASE_LEDGER

    bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$BASE_LEDGER"
}

setup() {
    # setup_file already owns an isolated suite root. A deterministic per-test
    # directory avoids one mktemp process per case while preserving isolation.
    TMP_ROOT="$FIXTURE_ROOT/test_$BATS_TEST_NUMBER"
    mkdir -p "$TMP_ROOT"
    LEDGER="$TMP_ROOT/script_speed_training_ledger.yaml"
    cp "$BASE_LEDGER" "$LEDGER"
    export SPEED_TRAINING_LEDGER="$LEDGER"
    export SHOGUN_STATE_DIR="$TMP_ROOT/state"
    export SPEED_TRAINING_TASK_DIR="$TMP_ROOT/tasks"
    mkdir -p "$SPEED_TRAINING_TASK_DIR"

    # Source the CLI once per test so repeated subcommand assertions exercise
    # the same functions without paying a fresh Bash startup for every call.
    source "$PROJECT_ROOT/tools/bash_speed_training.sh"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

teardown_file() {
    rm -rf "$FIXTURE_ROOT"
}

@test "init-ledger records every scripts/*.sh file with non-destructive bash -n syntax baseline and real timing columns" {
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

    # Mutation regression: deterministic ordering must not hide syntax failures.
    fixture_project="$TMP_ROOT/mutated-project"
    mkdir -p "$fixture_project/tools" "$fixture_project/scripts"
    cp "$PROJECT_ROOT/tools/bash_speed_training.sh" "$fixture_project/tools/"
    printf '#!/usr/bin/env bash\nprintf ok\n' > "$fixture_project/scripts/a_valid.sh"
    printf '#!/usr/bin/env bash\nif then\n' > "$fixture_project/scripts/b_invalid.sh"

    run bash "$fixture_project/tools/bash_speed_training.sh" init-ledger "$TMP_ROOT/mutated-ledger.yaml"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'script_path:' "$TMP_ROOT/mutated-ledger.yaml")" -eq 2 ]
    awk '
        /script_path: "scripts\/a_valid.sh"/ { target = "valid" }
        /script_path: "scripts\/b_invalid.sh"/ { target = "invalid" }
        target == "valid" && /test_result: "baseline_bash_n_exit_0"/ { valid = 1; target = "" }
        target == "invalid" && /test_result: "baseline_bash_n_exit_[1-9][0-9]*"/ { invalid = 1; target = "" }
        END { exit !(valid && invalid) }
    ' "$TMP_ROOT/mutated-ledger.yaml"
}

@test "paused ledger prevents auto-deploy" {
    cmd_set_global_status paused "$LEDGER"

    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "paused" ]
    ! grep -Fq 'status: assigned' "$LEDGER"
}

@test "auto-deploy dry-run assigns exactly one pending script and emits deploy_task command" {
    export SPEED_TRAINING_DRY_RUN=1
    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]
    [[ "$output" == DRY_RUN\ deploy_task* ]]
    [[ "$output" == *" hayate cmd_training_speed_"* ]]

    assigned_count=$(grep -c 'status: assigned' "$LEDGER")
    [ "$assigned_count" = "1" ]
    grep -Fq 'assigned_to: "hayate"' "$LEDGER"
}

@test "auto-deploy skips scripts already active in task yaml" {
    first=$(cmd_next "$LEDGER")
    cat > "$SPEED_TRAINING_TASK_DIR/hayate.yaml" <<EOF
task:
  status: in_progress
  target_path: $first
EOF

    export SPEED_TRAINING_DRY_RUN=1
    run cmd_auto_deploy kagemaru "$LEDGER"
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
    first=$(cmd_next "$LEDGER")
    cmd_record_after "$first" no_improvement 12 "no improvement" no_change "$LEDGER"

    export SPEED_TRAINING_DRY_RUN=1
    run cmd_auto_deploy hayate "$LEDGER"
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
    export SPEED_TRAINING_DRY_RUN=1
    run cmd_auto_deploy hayate "$LEDGER"
    [ "$status" -eq 0 ]

    generated_task=$(find "$SHOGUN_STATE_DIR" -type f -name 'speed_training_hayate.*.yaml' | head -n 1)
    [ -n "$generated_task" ]
    grep -Fq 'task_type: speed_training' "$generated_task"
    grep -Fq 'purpose: "Speed-train ' "$generated_task"
    grep -Fq 'before_real_ms is measured with a safe runtime command chosen for this script' "$generated_task"
    grep -Fq 'after_real_ms is measured with the same command as before_real_ms' "$generated_task"
    grep -Fq 'bash tools/bash_speed_training.sh record-after' "$generated_task"
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
    grep -Fq 'bash tools/bash_speed_training.sh record-after' "$generated_task"
    ! grep -Fq 'L4修行:' "$generated_task"
}

@test "record-after writes after measurement, test result, commit, and terminal status" {
    first=$(cmd_next "$LEDGER")

    cmd_record_after "$first" completed 12 "bats target PASS SKIP=0" abc123 "$LEDGER"

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
    first=$(cmd_next "$LEDGER")

    cmd_record_real "$first" completed 101 72 "time bash $first --help" "bats target PASS SKIP=0" abc123 "$LEDGER"

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
    first=$(cmd_next "$LEDGER")

    run cmd_record_real "$first" completed 101 101 "time bash $first --help" "bats target PASS SKIP=0" abc123 "$LEDGER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"after_real_ms < before_real_ms"* ]]
}

@test "re-enqueue returns top completed entries to pending and carries after_real_ms into next before_real_ms" {
    first=$(cmd_next "$LEDGER")
    cmd_record_real "$first" completed 200 50 "time bash $first --help" "PASS SKIP=0" abc123 "$LEDGER"
    second=$(cmd_next "$LEDGER")
    cmd_record_real "$second" completed 300 100 "time bash $second --help" "PASS SKIP=0" def456 "$LEDGER"

    run cmd_re_enqueue 1 "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    awk -v first="$first" -v second="$second" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; in_second = 0; next }
        $0 ~ "script_path: \"" second "\"" { in_second = 1; in_first = 0; next }
        in_first && /status: completed/ { first_completed = 1 }
        in_second && /status: pending/ { second_pending = 1 }
        in_second && /before_real_ms: 100/ { second_before = 1 }
        in_second && /after_real_ms: ""/ { second_after_cleared = 1 }
        in_second && /iteration: 1/ { second_iteration = 1 }
        END { exit !(first_completed && second_pending && second_before && second_after_cleared && second_iteration) }
    ' "$LEDGER"
}

@test "re-enqueue preserves decimal after_real_ms values" {
    first=$(cmd_next "$LEDGER")
    cmd_record_real "$first" completed 24.565 16.634 "time bash $first --help" "PASS SKIP=0" abc123 "$LEDGER"

    run cmd_re_enqueue 1 "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    awk -v first="$first" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; next }
        in_first && /status: pending/ { pending = 1 }
        in_first && /before_real_ms: 16.634/ { before_decimal = 1 }
        in_first && /after_real_ms: ""/ { after_cleared = 1 }
        END { exit !(pending && before_decimal && after_cleared) }
    ' "$LEDGER"
}

@test "re-enqueue stops at max iteration" {
    first=$(cmd_next "$LEDGER")
    cmd_record_real "$first" completed 200 100 "time bash $first --help" "PASS SKIP=0" abc123 "$LEDGER"
    cmd_re_enqueue 1 "$LEDGER" 1
    cmd_record_real "$first" completed 100 80 "time bash $first --help" "PASS SKIP=0" def456 "$LEDGER"

    run cmd_re_enqueue 1 "$LEDGER" 1
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]

    awk -v first="$first" '
        $0 ~ "script_path: \"" first "\"" { in_first = 1; next }
        in_first && /status: completed/ { completed = 1 }
        in_first && /iteration: 1/ { iteration = 1 }
        END { exit !(completed && iteration) }
    ' "$LEDGER"
}

@test "re-enqueue default max iteration is 3 and excludes iteration 3 completed entries" {
    cat > "$LEDGER" <<EOF
global_status: running
entries:
  - script_path: "scripts/iteration_three.sh"
    status: completed
    before_real_ms: 80
    after_real_ms: 40
    iteration: 3
    assigned_to: ""
    updated_at: ""
EOF

    run cmd_re_enqueue 20 "$LEDGER"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]

    awk '
        /script_path: "scripts\/iteration_three.sh"/ { in_target = 1; next }
        in_target && /status: completed/ { completed = 1 }
        in_target && /iteration: 3/ { iteration = 1 }
        END { exit !(completed && iteration) }
    ' "$LEDGER"
}

@test "ninja_monitor re-enqueues completed speed training when no pending or assigned work remains" {
    cat > "$LEDGER" <<EOF
global_status: running
entries:
  - script_path: "scripts/sample_slow.sh"
    status: completed
    before_real_ms: 200
    after_real_ms: 100
    iteration: 0
    assigned_to: ""
    updated_at: ""
EOF

    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export SPEED_TRAINING_LEDGER="'"$LEDGER"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
log() { :; }
if _speed_training_pipeline_has_work; then
    printf "work"
else
    printf "none"
fi
'
    [ "$status" -eq 0 ]
    [ "$output" = "work" ]
    grep -Fq 'status: pending' "$LEDGER"
    grep -Fq 'before_real_ms: 100' "$LEDGER"
    grep -Fq 'iteration: 1' "$LEDGER"
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
_trigger_training_completion_check() { :; }
_handle_reflux_auto_deploy() { return 1; }
_handle_test_speed_auto_deploy() { return 1; }
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
