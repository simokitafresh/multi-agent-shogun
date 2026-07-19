#!/usr/bin/env bats
# test_necessity: ninja_monitorはrestart/clear/pane-dead/respawnを跨ぐevent exactly-onceとlost0を守る。

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

@test "throughput ready event is claimed exactly once and resumes the same task" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"
        THROUGHPUT_READY_DIR="$SCRIPT_DIR/ready"
        LOG="$SCRIPT_DIR/monitor.log"
        mkdir -p "$SCRIPT_DIR/scripts" "$THROUGHPUT_READY_DIR"
        printf "#!/usr/bin/env bash\nprintf \"%%s\\n\" \"\$*\" >>\"%s\"\n" "$SCRIPT_DIR/calls" >"$SCRIPT_DIR/scripts/throughput_growth_loop.sh"
        printf "%s\n" "--event-id" "real-task-3" >"$THROUGHPUT_READY_DIR/wave3.args"
        check_throughput_ready_events
        check_throughput_ready_events
        test -f "$THROUGHPUT_READY_DIR/wave3.done"
        test "$(wc -l <"$SCRIPT_DIR/calls")" -eq 1
        grep -Fx -- "--event-id real-task-3" "$SCRIPT_DIR/calls"
    '
    [ "$status" -eq 0 ]
}

# test_necessity: AUTO-DONEとdeployが同一agent lockで直列化され、旧parent/archive reportでtaskを書換えない不変量を守る。
@test "AUTO-DONE deploy lock boundary is retryable and archive symlinks are inactive" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1; source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"; LOG="$BATS_TEST_TMPDIR/log"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/locks" "$STATE_DIR"; : >"$LOG"
        log() { printf "%s\n" "$1" >>"$LOG"; }; write_karo_snapshot() { :; }
        _reflux_promotion_record_completion() { :; }; report_monitor_state() { printf "pass_terminal\n"; }
        yaml_field_set() { bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$@"; }
        task="$SCRIPT_DIR/queue/tasks/alpha.yaml"; report="$SCRIPT_DIR/queue/reports/alpha_report_cmd_new.yaml"
        printf "task:\n  parent_cmd: cmd_new\n  task_id: task_new\n  status: in_progress\n" >"$task"
        printf "parent_cmd: cmd_new\ntask_id: task_new\nstatus: completed\ntimestamp: 2026-07-19T12:00:39+09:00\n" >"$report"
        find_matching_report_file() { printf "%s\n" "$report"; }
        flock "$SCRIPT_DIR/queue/locks/deploy_ninja_alpha.lock" -c "sleep 1" & holder=$!; sleep 0.1
        check_and_update_done_task alpha && exit 91 || true; grep -q "status: in_progress" "$task"; wait "$holder"
        check_and_update_done_task alpha; [ "$(grep -c "status: done" "$task")" -eq 1 ]
        check_and_update_done_task alpha; [ "$(grep -c "status: done" "$task")" -eq 1 ]
        bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$task" task status in_progress
        bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$task" task parent_cmd cmd_changed
        check_and_update_done_task alpha && exit 92 || true; grep -q "status: in_progress" "$task"
        archive="$BATS_TEST_TMPDIR/archive.yaml"; cp "$report" "$archive"; ln -s "$archive" "$SCRIPT_DIR/queue/reports/archive-link.yaml"
        report="$SCRIPT_DIR/queue/reports/archive-link.yaml"; bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$task" task parent_cmd cmd_new
        check_and_update_done_task alpha && exit 93 || true; grep -q "status: in_progress" "$task"
        python3 -c "import yaml; yaml.safe_load(open(\"$task\"))"
        [ "$(grep -c AUTO-DONE-SKIP-DEPLOY-LOCK-BUSY "$LOG")" -eq 1 ]
        [ "$(grep -c AUTO-DONE-SKIP-ARCHIVE-SYMLINK "$LOG")" -eq 1 ]
    '
    [ "$status" -eq 0 ]
}

# test_necessity: idle snapshot後のdeployと家老通知を同一agent lock境界で直列化し、active task存在時の偽idle通知を防ぐ不変量を守る。
@test "karo idle-cycle revalidates live tasks under every deploy lock before notifying" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1; source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; LOG="$BATS_TEST_TMPDIR/monitor.log"
        NINJA_NAMES=(alpha beta); LAST_KARO_IDLE_NUDGE=0; KARO_IDLE_COOLDOWN=0
        mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/locks" "$SCRIPT_DIR/scripts"
        printf "idle_cycle: on\n" >"$SCRIPT_DIR/config/settings.yaml"; : >"$LOG"
        printf "task:\n  status: idle\n" >"$SCRIPT_DIR/queue/tasks/alpha.yaml"
        printf "task:\n  status: idle\n" >"$SCRIPT_DIR/queue/tasks/beta.yaml"
        get_idle_pipeline_state() { printf "2|0|0\n"; }
        cat >"$SCRIPT_DIR/scripts/inbox_write.sh" <<"SH"
#!/usr/bin/env bash
printf "notify\n" >>"$SCRIPT_DIR/notifications"
SH
        export SCRIPT_DIR; chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

        # snapshot取得後に配備が成立した敵対ケース: 修正前は1通知、修正後は0通知。
        bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/queue/tasks/beta.yaml" task status assigned
        check_karo_idle_cycle
        [ ! -e "$SCRIPT_DIR/notifications" ]

        # 真の全idleは1通知。次cycle再評価でlost=0、1 cycle内duplicate=0。
        bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/queue/tasks/beta.yaml" task status idle
        check_karo_idle_cycle
        [ "$(wc -l <"$SCRIPT_DIR/notifications")" -eq 1 ]
        python3 -c "import yaml; [yaml.safe_load(open(p)) for p in [\"$SCRIPT_DIR/queue/tasks/alpha.yaml\", \"$SCRIPT_DIR/queue/tasks/beta.yaml\"]]"
    '
    [ "$status" -eq 0 ]
}
