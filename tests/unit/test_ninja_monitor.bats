#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

run_recovery_case() {
    local fixture_dead="$1" fixture_status="$2" recovery_result="${3:-pass}"
    run env PROJECT_ROOT="$PROJECT_ROOT" FIXTURE_DEAD="$fixture_dead" \
        FIXTURE_STATUS="$fixture_status" RECOVERY_RESULT="$recovery_result" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        LOG="$BATS_TEST_TMPDIR/monitor.log"; : > "$LOG"
        calls=0
        log() { printf "%s\n" "$1" >> "$LOG"; }
        tmux() {
            if [ "$1" = display-message ]; then
                if [ "$calls" -gt 0 ] && [ "$RECOVERY_RESULT" = pass ]; then printf "0\n"; else printf "%s\n" "$FIXTURE_DEAD"; fi
            fi
        }
        _run_dead_pane_recovery() { calls=$((calls + 1)); [ "$RECOVERY_RESULT" = pass ]; }
        rc=0
        recover_dead_active_pane alpha "$FIXTURE_STATUS" pane || rc=$?
        printf "rc=%s calls=%s\n" "$rc" "$calls"
        cat "$LOG"
    '
}

@test "dead active pane is recovered once before grace" {
    run_recovery_case 1 in_progress
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0 calls=1"* ]]
    [[ "$output" == *"ACTIVE-DEAD-RECOVERY-PASS: alpha status=in_progress pane_dead=0"* ]]
}

@test "dead assigned pane is recovered once" {
    run_recovery_case 1 assigned
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0 calls=1"* ]]
}

@test "live active pane is never respawned" {
    run_recovery_case 0 in_progress
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=1 calls=0"* ]]
}

@test "dead idle pane is outside active-task recovery" {
    run_recovery_case 1 idle
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=1 calls=0"* ]]
}

@test "failed dead active recovery blocks instead of reaching grace" {
    run_recovery_case 1 in_progress fail
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=2 calls=1"* ]]
    [[ "$output" == *"ACTIVE-DEAD-RECOVERY-BLOCK"* ]]
}

run_check_stall_order_case() {
    local fixture_dead="$1"
    run env PROJECT_ROOT="$PROJECT_ROOT" FIXTURE_DEAD="$fixture_dead" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; mkdir -p "$SCRIPT_DIR/queue/tasks"
        LOG="$BATS_TEST_TMPDIR/monitor.log"; : > "$LOG"
        cat > "$SCRIPT_DIR/queue/tasks/alpha.yaml" <<EOF
task:
  task_id: fixture_active
  status: in_progress
  deployed_at: "$(date -Iseconds)"
EOF
        calls=0
        log() { printf "%s\n" "$1" >> "$LOG"; }
        tmux() {
            if [ "$1" = display-message ]; then
                if [ "$calls" -gt 0 ]; then printf "0\n"; else printf "%s\n" "$FIXTURE_DEAD"; fi
            fi
        }
        _run_dead_pane_recovery() { calls=$((calls + 1)); return 0; }
        unset PANE_TARGETS STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT
        declare -A PANE_TARGETS=([alpha]=pane) STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT
        rc=0; check_stall alpha || rc=$?
        grace_count=$(grep -c "STALL-DEPLOY-GRACE" "$LOG" || true)
        printf "rc=%s calls=%s grace=%s\n" "$rc" "$calls" "$grace_count"
        cat "$LOG"
    '
}

@test "check_stall recovers dead active pane before deploy grace" {
    run_check_stall_order_case 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0 calls=1 grace=0"* ]]
}

@test "check_stall preserves deploy grace for live active pane" {
    run_check_stall_order_case 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0 calls=0 grace=1"* ]]
}
