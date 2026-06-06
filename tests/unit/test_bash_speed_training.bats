#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_ROOT="$(mktemp -d)"
    LEDGER="$TMP_ROOT/script_speed_training_ledger.yaml"
    export SPEED_TRAINING_LEDGER="$LEDGER"
    export SHOGUN_STATE_DIR="$TMP_ROOT/state"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

@test "init-ledger records every scripts/*.sh file with non-destructive bash -n baseline" {
    run bash "$PROJECT_ROOT/tools/bash_speed_training.sh" init-ledger "$LEDGER"
    [ "$status" -eq 0 ]

    expected=$(find "$PROJECT_ROOT/scripts" -type f -name '*.sh' | wc -l | tr -d ' ')
    entry_count=$(grep -c 'script_path:' "$LEDGER")

    [ "$entry_count" = "$expected" ]
    grep -Fq "script_count: $expected" "$LEDGER"
    grep -Fq 'measurement_command: "timeout 5 bash -n <script_path>"' "$LEDGER"
    grep -Eq 'before_ms: [0-9]+' "$LEDGER"
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
