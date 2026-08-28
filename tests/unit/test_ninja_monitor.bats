#!/usr/bin/env bats
# test_necessity: ninja_monitorはrestart/clear/pane-dead/respawnを跨ぐevent exactly-onceとlost0を守る。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# test_necessity: the primary done-check loop must not serialize a slow report
# gate into the monitor cycle, while its per-agent single-flight lease remains
# retryable after a failed worker.
@test "done-check fast path is backgrounded and retryable" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        _NINJA_MONITOR_LIB_MODE=0
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$SCRIPT_DIR/state"; LOG="$SCRIPT_DIR/monitor.log"
        mkdir -p "$SCRIPT_DIR" "$STATE_DIR"
        : > "$SCRIPT_DIR/calls"
        log() { printf "%s\n" "$1" >> "$LOG"; }
        NINJA_NAMES=(saizo)
        _ninja_monitor_run_bounded_done_check() { printf "%s\n" "$1" >> "$SCRIPT_DIR/calls"; sleep 1; return 0; }
        start=$(date +%s%N)
        monitor_task_state_fast_path
        elapsed=$((($(date +%s%N) - start) / 1000000))
        monitor_task_state_fast_path
        wait
        test "$elapsed" -lt 500
        test "$(wc -l < "$SCRIPT_DIR/calls")" -eq 1
        _ninja_monitor_run_bounded_done_check() { printf "%s\n" "$1" >> "$SCRIPT_DIR/calls"; return 1; }
        monitor_task_state_fast_path
        wait
        monitor_task_state_fast_path
        wait
        test "$(wc -l < "$SCRIPT_DIR/calls")" -eq 3
        grep -q "AUTO-DONE-BACKGROUND-START: saizo" "$LOG"
        echo "background=1 duplicate=1 retry=1"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "background=1 duplicate=1 retry=1" ]
}

# test_necessity: 両承認後のreview_gate.doneは遅延なしでcmd_complete_gateを一度だけ実行し、
# 併走monitorはflockで二重実行しない不変量を守る。
@test "GATE-STALL executes completion gate immediately" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/queue/gates/cmd_gate_old" "$SCRIPT_DIR/queue/gates/cmd_gate_stall" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"
        old_ts=$(date -d "11 minutes ago" -Iseconds)
        printf "timestamp: %s\nsource: two_phase_review\nresult: LGTM\n" "$old_ts" > "$SCRIPT_DIR/queue/gates/cmd_gate_old/review_gate.done"
        printf "timestamp: %s\nsource: two_phase_review\nresult: LGTM\n" "$old_ts" > "$SCRIPT_DIR/queue/gates/cmd_gate_stall/review_gate.done"
        printf "task:\n  parent_cmd: cmd_gate_stall\n  status: in_progress\n" > "$SCRIPT_DIR/queue/tasks/active.yaml"
        : > "$SCRIPT_DIR/logs/gate_metrics.log"
        printf "%s\n" \
            "#!/usr/bin/env bash" \
            "printf \"%s\\n\" \"\$1\" >> \"$STATE_DIR/gates\"" \
            "printf \"%s\\t%s\\tCLEAR\\tok\\n\" \"$(date -Iseconds)\" \"\$1\" >> \"$SCRIPT_DIR/logs/gate_metrics.log\"" \
            > "$SCRIPT_DIR/scripts/cmd_complete_gate.sh"
        chmod +x "$SCRIPT_DIR/scripts/cmd_complete_gate.sh"
        log() { printf "LOG:%s\n" "$1"; }
        GATE_STALL_MAX_MIN=1440
        check_gate_stall
        check_gate_stall
        test "$(wc -l < "$STATE_DIR/gates")" -eq 1
        grep -qx "cmd_gate_stall" "$STATE_DIR/gates"
        printf "gate_runs=%s\n" "$(wc -l < "$STATE_DIR/gates")"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate_runs=1"* ]]
}

# test_necessity: cmd_complete_gate's inner CMD_ID lock contention is retryable
# and must never be published as a terminal gate_block; a different nonzero
# result remains terminal and preserves the existing notification contract.
# regression_justification: three same-session inner-lock collisions were
# emitted as GATE-AUTO-BLOCK instead of remaining eligible for the next cycle.
@test "GATE-STALL retries inner lock contention but blocks true failure" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/queue/gates/cmd_retry" "$SCRIPT_DIR/queue/gates/cmd_fail" \
            "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"
        now=$(date -Iseconds)
        printf "timestamp: %s\nresult: LGTM\n" "$now" > "$SCRIPT_DIR/queue/gates/cmd_retry/review_gate.done"
        printf "timestamp: %s\nresult: LGTM\n" "$now" > "$SCRIPT_DIR/queue/gates/cmd_fail/review_gate.done"
        printf "task:\n  parent_cmd: cmd_retry\n  status: in_progress\n" > "$SCRIPT_DIR/queue/tasks/retry.yaml"
        printf "task:\n  parent_cmd: cmd_fail\n  status: in_progress\n" > "$SCRIPT_DIR/queue/tasks/fail.yaml"
        : > "$SCRIPT_DIR/logs/gate_metrics.log"
        cat > "$SCRIPT_DIR/scripts/cmd_complete_gate.sh" <<EOF
#!/usr/bin/env bash
printf "%s\n" "\$1" >> "$STATE_DIR/calls"
if [ "\$1" = cmd_retry ]; then
  echo "[gate] \$1: cmd_complete_gate busy; terminal CLEAR/BLOCK is not established (CMD_ID lock)" >&2
  exit 2
fi
echo "GATE BLOCK: real_failure" >&2
exit 1
EOF
        chmod +x "$SCRIPT_DIR/scripts/cmd_complete_gate.sh"
        log() { printf "%s\n" "$1" >> "$STATE_DIR/logs"; }
        send_inbox_message() { printf "%s|%s\n" "$1" "$3" >> "$STATE_DIR/messages"; }
        GATE_STALL_MAX_MIN=1440
        check_gate_stall
        check_gate_stall
        test "$(grep -c "^cmd_retry$" "$STATE_DIR/calls")" -eq 2
        test "$(grep -c "^cmd_fail$" "$STATE_DIR/calls")" -eq 2
        test "$(grep -c "GATE-AUTO-LOCKED: cmd_retry" "$STATE_DIR/logs")" -eq 2
        test "$(grep -c "^karo|gate_block$" "$STATE_DIR/messages")" -eq 2
        ! grep -q "cmd_retry" "$STATE_DIR/messages"
        printf "retry_calls=2 retry_blocks=0 true_failure_blocks=2\n"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"retry_calls=2 retry_blocks=0 true_failure_blocks=2"* ]]
}

@test "terminal report requests Gunshi review once after durable Karo publish" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"; LOG="$STATE_DIR/log"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$STATE_DIR"
        NINJA_NAMES=(saizo)
        printf "task:\n  status: in_progress\n  report_path: queue/reports/saizo_report_cmd_review.yaml\n" > "$SCRIPT_DIR/queue/tasks/saizo.yaml"
        printf "status: completed\nparent_cmd: cmd_review\n" > "$SCRIPT_DIR/queue/reports/saizo_report_cmd_review.yaml"
        cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<EOF
#!/usr/bin/env bash
printf "%s|%s|%s|%s|%s\n" "\$1" "\$2" "\$3" "\$4" "\$5" >> "$STATE_DIR/messages"
EOF
        chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"
        repair_terminal_report_outboxes
        repair_terminal_report_outboxes
        test "$(grep -c "^gunshi|" "$STATE_DIR/messages")" -eq 1
        grep -q "^gunshi|.*report=saizo_report_cmd_review.yaml parent_cmd=cmd_review|review_draft|ninja_monitor|review_request" "$STATE_DIR/messages"
        printf "review_requests=%s\n" "$(grep -c "^gunshi|" "$STATE_DIR/messages")"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"review_requests=1"* ]]
}

@test "GATE-STALL suppresses a review gate with a later CLEAR metric" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; mkdir -p "$SCRIPT_DIR/queue/gates/cmd_gate_clear" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs"
        old_ts=$(date -d "11 minutes ago" -Iseconds); clear_ts=$(date -Iseconds)
        printf "timestamp: %s\nsource: two_phase_review\nresult: LGTM\n" "$old_ts" > "$SCRIPT_DIR/queue/gates/cmd_gate_clear/review_gate.done"
        printf "task:\n  parent_cmd: cmd_gate_clear\n  status: in_progress\n" > "$SCRIPT_DIR/queue/tasks/active.yaml"
        printf "%s\tcmd_gate_clear\tCLEAR\tall_gates_passed\n" "$clear_ts" > "$SCRIPT_DIR/logs/gate_metrics.log"
        TEST_MESSAGES="$BATS_TEST_TMPDIR/messages"; : > "$TEST_MESSAGES"
        log() { :; }; send_inbox_message() { printf "%s\n" "$*" >> "$TEST_MESSAGES"; }
        GATE_STALL_WARN_MIN=10; STALL_RENOTIFY_DEBOUNCE=300
        check_gate_stall
        test ! -s "$TEST_MESSAGES"
        printf "notifications=0\n"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"notifications=0"* ]]
}

@test "GATE-STALL suppresses an archived review gate" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; mkdir -p "$SCRIPT_DIR/queue/gates/cmd_gate_archive" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs"
        old_ts=$(date -d "11 minutes ago" -Iseconds)
        printf "timestamp: %s\nsource: two_phase_review\nresult: LGTM\n" "$old_ts" > "$SCRIPT_DIR/queue/gates/cmd_gate_archive/review_gate.done"
        printf "task:\n  parent_cmd: cmd_gate_archive\n  status: in_progress\n" > "$SCRIPT_DIR/queue/tasks/active.yaml"
        : > "$SCRIPT_DIR/queue/gates/cmd_gate_archive/archive.done"
        : > "$SCRIPT_DIR/logs/gate_metrics.log"
        TEST_MESSAGES="$BATS_TEST_TMPDIR/messages"; : > "$TEST_MESSAGES"
        log() { :; }; send_inbox_message() { printf "%s\n" "$*" >> "$TEST_MESSAGES"; }
        GATE_STALL_WARN_MIN=10; STALL_RENOTIFY_DEBOUNCE=300
        check_gate_stall
        test ! -s "$TEST_MESSAGES"
        printf "notifications=0\n"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"notifications=0"* ]]
}

# test_necessity(cmd_karo_hotfix_completion_event_dedupe_20260723): identical report bytes plus the same immutable task contract
# must execute report gate once across monitor cycles/restarts, while a real
# contract change must create a new generation and re-enable validation.
@test "report gate durable generation dedupes status churn and reopens on contract change" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$STATE_DIR"
        cat > "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" <<EOF
#!/usr/bin/env bash
count_file="$STATE_DIR/gate_calls"
count=0; [ ! -f "\$count_file" ] || count=\$(cat "\$count_file")
printf "%s\n" "\$((count + 1))" > "\$count_file"
printf "FAIL: stable reason\n"
exit 1
EOF
        printf "status: completed\nverdict: PASS\n" > "$SCRIPT_DIR/queue/reports/report.yaml"
        cat > "$SCRIPT_DIR/queue/tasks/ninja.yaml" <<EOF
task:
  task_id: cmd_generation_normal
  parent_cmd: cmd_generation
  ac_version: abc
  deployed_at: 2026-07-23T00:00:00
  status: in_progress
  target_path: [scripts/a.sh]
  planned_paths: [scripts/a.sh]
EOF
        first=$(report_gate_generation_key "$SCRIPT_DIR/queue/reports/report.yaml" "$SCRIPT_DIR/queue/tasks/ninja.yaml")
        ! run_report_gate_deduped ninja "$SCRIPT_DIR/queue/reports/report.yaml" "$SCRIPT_DIR/queue/tasks/ninja.yaml"
        ! run_report_gate_deduped ninja "$SCRIPT_DIR/queue/reports/report.yaml" "$SCRIPT_DIR/queue/tasks/ninja.yaml"
        [ "$(cat "$STATE_DIR/gate_calls")" -eq 1 ]
        sed -i "s/status: in_progress/status: done/" "$SCRIPT_DIR/queue/tasks/ninja.yaml"
        same=$(report_gate_generation_key "$SCRIPT_DIR/queue/reports/report.yaml" "$SCRIPT_DIR/queue/tasks/ninja.yaml")
        [ "$same" = "$first" ]
        ! run_report_gate_deduped ninja "$SCRIPT_DIR/queue/reports/report.yaml" "$SCRIPT_DIR/queue/tasks/ninja.yaml"
        [ "$(cat "$STATE_DIR/gate_calls")" -eq 1 ]
        sed -i "s#scripts/a.sh#scripts/b.sh#g" "$SCRIPT_DIR/queue/tasks/ninja.yaml"
        changed=$(report_gate_generation_key "$SCRIPT_DIR/queue/reports/report.yaml" "$SCRIPT_DIR/queue/tasks/ninja.yaml")
        [ "$changed" != "$first" ]
        ! report_gate_cached_outcome ninja "$changed"
        ! run_report_gate_deduped ninja "$SCRIPT_DIR/queue/reports/report.yaml" "$SCRIPT_DIR/queue/tasks/ninja.yaml"
        [ "$(cat "$STATE_DIR/gate_calls")" -eq 2 ]
        printf "same=1 dedupe=1 changed=1 calls=2\n"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"same=1 dedupe=1 changed=1 calls=2"* ]]
}

@test "CI RED guard structurally deploys eligible work and dedupes each generation" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1; source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        CI_RED_PARALLEL_STATE_FILE="$STATE_DIR/notified"
        mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue" "$SCRIPT_DIR/logs" "$STATE_DIR"
        cat >"$SCRIPT_DIR/scripts/deploy_task.sh" <<EOF
#!/usr/bin/env bash
printf "%s\n" "\$*" >>"$STATE_DIR/deploys"
printf "task:\n  status: assigned\n  parent_cmd: %s\n" "\$2" >"$SCRIPT_DIR/queue/tasks/\$1.yaml"
EOF
        printf "task:\n  status: idle\n" >"$SCRIPT_DIR/queue/tasks/alpha.yaml"
        count() { [ -f "$STATE_DIR/deploys" ] && wc -l <"$STATE_DIR/deploys" || printf "0\n"; }
        check_ci_red_parallelization_guard "RED:101:job" 1899 1 cmd_1 $'"'"'101\tsha-a\t1000'"'"' alpha
        a=$(count)
        check_ci_red_parallelization_guard "RED:101:job" 1900 0 cmd_1 $'"'"'101\tsha-a\t1000'"'"' alpha
        b=$(count)
        check_ci_red_parallelization_guard "RED:101:job" 1900 1 "" $'"'"'101\tsha-a\t1000'"'"' alpha
        c=$(count)
        check_ci_red_parallelization_guard "GREEN" 1900 1 cmd_1 $'"'"'101\tsha-a\t1000'"'"' alpha
        d=$(count)
        printf "101:sha-a\n" >"$STATE_DIR/notified"
        check_ci_red_parallelization_guard "RED:101:job" 1900 1 cmd_1 $'"'"'101\tsha-a\t1000'"'"' alpha
        e=$(count)
        rm -f "$STATE_DIR/notified"
        check_ci_red_parallelization_guard "RED:101:job" 1900 1 cmd_1 $'"'"'101\tsha-a\t1000'"'"' alpha
        positive=$(count)
        check_ci_red_parallelization_guard "RED:101:job" 1901 1 cmd_1 $'"'"'101\tsha-a\t1000'"'"' alpha
        same=$(count)
        printf "task:\n  status: idle\n" >"$SCRIPT_DIR/queue/tasks/alpha.yaml"
        check_ci_red_parallelization_guard "RED:102:job" 1901 1 cmd_2 $'"'"'102\tsha-b\t1000'"'"' alpha
        next=$(count)
        printf "counter=%s,%s,%s,%s,%s positive=%s same=%s next=%s\n" "$a" "$b" "$c" "$d" "$e" "$positive" "$same" "$next"
        grep -q "alpha cmd_2" "$STATE_DIR/deploys"
        grep -q "result: PASS" "$SCRIPT_DIR/logs/gate_fire_log.yaml"
        ! grep -R -q parallelization_required "$SCRIPT_DIR"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"counter=0,0,0,0,0 positive=1 same=1 next=2"* ]]
}

@test "CI RED structural deploy filters ineligible commands and fails closed retryably" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1; source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        CI_RED_PARALLEL_STATE_FILE="$STATE_DIR/notified"
        mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs" "$STATE_DIR"
        printf "task:\n  status: idle\n" >"$SCRIPT_DIR/queue/tasks/alpha.yaml"
        cat >"$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<EOF
commands:
- {id: cmd_nonparallel, status: pending, parallel_ok: false}
- {id: cmd_canceled, status: canceled, parallel_ok: true}
- {id: cmd_deployed, status: pending, parallel_ok: true}
- {id: cmd_eligible, status: approved, parallel_ok: true}
EOF
        printf "task:\n  status: in_progress\n  parent_cmd: cmd_deployed\n" >"$SCRIPT_DIR/queue/tasks/beta.yaml"
        selected=$(_ci_red_first_deployable_cmd)
        [ "$selected" = cmd_eligible ]
        [ "$(_ci_red_first_idle_ninja)" = alpha ]

        printf "#!/usr/bin/env bash\nexit 7\n" >"$SCRIPT_DIR/scripts/deploy_task.sh"
        check_ci_red_parallelization_guard "RED:201:job" 1900 1 "$selected" $'"'"'201\tsha-fail\t1000'"'"' alpha
        [ ! -f "$STATE_DIR/notified" ]
        grep -q "result: BLOCK.*deploy_task_failed=1" "$SCRIPT_DIR/logs/gate_fire_log.yaml"

        exec 8>"$STATE_DIR/notified.lock"; flock 8
        check_ci_red_parallelization_guard "RED:202:job" 1900 1 "$selected" $'"'"'202\tsha-lock\t1000'"'"' alpha
        flock -u 8
        grep -q "result: BLOCK.*lock_busy=1" "$SCRIPT_DIR/logs/gate_fire_log.yaml"
        [ ! -f "$STATE_DIR/notified" ]
        printf "selected=%s autodeploy=0 block=2 duplicate=0\n" "$selected"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"selected=cmd_eligible autodeploy=0 block=2 duplicate=0"* ]]
}

run_codex_bypass_case() {
    local task_status="$1" pane_idle="$2" has_flag="$3" recovery="$4" repeat="${5:-1}"
    run env PROJECT_ROOT="$PROJECT_ROOT" TASK_STATUS="$task_status" PANE_IDLE="$pane_idle" \
        HAS_FLAG="$has_flag" RECOVERY="$recovery" REPEAT="$repeat" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
        printf "task:\n  status: %s\n" "$TASK_STATUS" > "$SCRIPT_DIR/queue/tasks/alpha.yaml"
        LOG="$BATS_TEST_TMPDIR/monitor.log"; : > "$LOG"; respawns=0; notices=0
        log() { printf "%s\n" "$1" >> "$LOG"; }
        cli_type() { printf "codex\n"; }
        tmux() { [ "$1" = display-message ] && printf "4242\n"; }
        pstree() { [ "$HAS_FLAG" = 1 ] && printf "codex --dangerously-bypass-approvals-and-sandbox\n"; }
        check_idle() { [ "$PANE_IDLE" = 1 ]; }
        cli_launch_cmd() { printf "/opt/codex/bin/codex --dangerously-bypass-approvals-and-sandbox\n"; }
        respawn_recovery_launch_command() { printf "launch\n"; }
        codex_config_apply_agent() { return 0; }
        _respawn_with_cli_verification() { respawns=$((respawns + 1)); [ "$RECOVERY" = pass ]; }
        respawn_recovery_generation() { printf "4242\n"; }
        respawn_recovery_notify() { notices=$((notices + 1)); return 0; }
        rc=0
        for ((i=0; i<REPEAT; i++)); do check_codex_bypass_once alpha pane || rc=$?; done
        printf "rc=%s respawns=%s notices=%s\n" "$rc" "$respawns" "$notices"
        cat "$LOG"
    '
}

@test "GP-239 idle Codex missing bypass self-heals once through verified handshake" {
    run_codex_bypass_case idle 1 0 pass 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0 respawns=1 notices=1"* ]]
    [[ "$output" == *"CODEX-BYPASS-DEDUPE"* ]]
}

@test "GP-239 active or non-idle Codex missing bypass never respawns" {
    run_codex_bypass_case in_progress 1 0 pass
    [[ "$output" == *"rc=1 respawns=0 notices=0"* ]]
    run_codex_bypass_case idle 0 0 pass
    [[ "$output" == *"rc=1 respawns=0 notices=0"* ]]
}

@test "GP-239 healthy Codex bypass never respawns" {
    run_codex_bypass_case idle 1 1 pass
    [[ "$output" == *"rc=0 respawns=0 notices=0"* ]]
}

@test "GP-239 failed recovery is fail-closed and retryable next cycle" {
    run_codex_bypass_case idle 1 0 fail 2
    [[ "$output" == *"rc=1 respawns=2 notices=0"* ]]
    [[ "$output" == *"retry=next_cycle"* ]]
}

@test "GP-239 main loop keeps the bypass check on the next cycle" {
    run grep -q '^[[:space:]]*check_all_codex_bypass_flags$' "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    [ "$status" -eq 0 ]
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

@test "verified failed task respawn generation is durable and suppresses repeated clear" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
        cat > "$SCRIPT_DIR/queue/tasks/alpha.yaml" <<EOF
task:
  task_id: failed_fixture
  parent_cmd: cmd_parent
  deployed_at: 2026-07-20T00:00:00+09:00
  status: failed
EOF
        first=1
        _failed_task_respawn_completed alpha && first=0
        _mark_failed_task_respawn_completed alpha
        second=0
        _failed_task_respawn_completed alpha || second=1
        sed -i "s/00:00:00/00:01:00/" "$SCRIPT_DIR/queue/tasks/alpha.yaml"
        third=1
        _failed_task_respawn_completed alpha && third=0
        printf "before=%s same_generation=%s new_generation=%s\n" "$first" "$second" "$third"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"before=1 same_generation=0 new_generation=1"* ]]
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

# test_necessity: promotion在庫の先頭が予約済みでも同一snapshot内の次候補を探索し、並列忍者が候補を二重予約しない不変量を守る。
@test "reflux promotion claim scans past reserved head and atomically splits parallel claims" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"; LOG="$BATS_TEST_TMPDIR/log"
        mkdir -p "$SCRIPT_DIR/logs" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$STATE_DIR"; : >"$LOG"
        log() { printf "%s\n" "$1" >>"$LOG"; }
        _reflux_active_target_owner() { return 1; }

        # Reserved head is skipped and the second candidate is returned.
        _reflux_promotion_candidates() { printf "%s\n" "[dm-signal] L911 (L1)" "[infra] L912 (L2)"; }
        _reflux_promotion_try_reserve() { [ "$1" = "[infra] L912 (L2)" ]; }
        [ "$(_reflux_promotion_claim_next alpha)" = $'\''[infra] L912 (L2)\tprojects/infra/lessons.yaml'\'' ]

        # Real flock-backed reservation: two concurrent workers claim different IDs exactly once.
        unset -f _reflux_promotion_try_reserve
        export REFLUX_PROMOTION_RESERVATION_LEDGER="$SCRIPT_DIR/logs/reservations.tsv"
        export REFLUX_PROMOTION_LEDGER="$SCRIPT_DIR/logs/completed.tsv"
        export REFLUX_PROMOTION_DEFERRED_LEDGER="$SCRIPT_DIR/logs/deferred.tsv"
        : >"$REFLUX_PROMOTION_LEDGER"; : >"$REFLUX_PROMOTION_DEFERRED_LEDGER"
        _reflux_promotion_candidates() { printf "%s\n" "[infra] L920 (L1)" "[infra] L921 (L1)"; }
        export -f _reflux_promotion_candidates _reflux_active_target_owner log
        (_reflux_promotion_claim_next alpha >"$STATE_DIR/alpha") &
        p1=$!
        (_reflux_promotion_claim_next beta >"$STATE_DIR/beta") &
        p2=$!
        wait "$p1"; wait "$p2"
        [ "$(cut -f2 "$REFLUX_PROMOTION_RESERVATION_LEDGER" | sort -u | wc -l)" -eq 2 ]
        [ "$(cut -f2 "$REFLUX_PROMOTION_RESERVATION_LEDGER" | wc -l)" -eq 2 ]
        [ "$(cat "$STATE_DIR/alpha" "$STATE_DIR/beta" | cut -f1 | sort -u | wc -l)" -eq 2 ]

        # Only an all-ineligible inventory returns no claim.
        _reflux_promotion_candidates() { printf "%s\n" "[infra] L930 (L1)" "[infra] L931 (L1)"; }
        _reflux_promotion_try_reserve() { return 1; }
        ! _reflux_promotion_claim_next gamma >"$STATE_DIR/gamma"
        [ ! -s "$STATE_DIR/gamma" ]
    '
    [ "$status" -eq 0 ]
}

# test_necessity: stable insight IDs must have one dispatch owner across
# concurrent monitors/restarts, while a failed publication can release only
# its own lease and a resolved ID remains ineligible.
@test "reflux insight claim is atomic, restart-safe, releasable on failure, and skips resolved IDs" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs" "$STATE_DIR"
        cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights:
- id: INS-CLAIM
  priority: high
  status: pending
YAML
        REFLUX_INSIGHTS_FILE="$SCRIPT_DIR/queue/insights.yaml"
        REFLUX_INSIGHT_RESERVATION_LEDGER="$STATE_DIR/insight_reservations.tsv"
        export REFLUX_INSIGHTS_FILE REFLUX_INSIGHT_RESERVATION_LEDGER

        (_reflux_insight_try_reserve INS-CLAIM alpha; echo $? > "$STATE_DIR/alpha.rc") &
        (_reflux_insight_try_reserve INS-CLAIM beta; echo $? > "$STATE_DIR/beta.rc") &
        wait
        test "$(grep -c $'\tINS-CLAIM\t' "$STATE_DIR/insight_reservations.tsv")" -eq 1
        test "$(cat "$STATE_DIR/alpha.rc")" -ne "$(cat "$STATE_DIR/beta.rc")"
        owner=alpha
        [ "$(cat "$STATE_DIR/alpha.rc")" -eq 0 ] || owner=beta
        cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights:
- id: INS-CLAIM
  priority: high
  status: pending
- id: INS-CLAIM-NEXT
  priority: medium
  status: pending
YAML
        test "$(_reflux_first_pending_insight_id)" = INS-CLAIM-NEXT
        test "$(_reflux_insight_try_reserve INS-CLAIM restart >/dev/null; echo $?)" -ne 0

        _reflux_insight_release_reservation INS-CLAIM "$owner"
        test "$(_reflux_insight_try_reserve INS-CLAIM retry >/dev/null; echo $?)" -eq 0
        _reflux_insight_release_reservation INS-CLAIM retry

        sed -i "s/status: pending/status: resolved/" "$SCRIPT_DIR/queue/insights.yaml"
        test "$(_reflux_insight_try_reserve INS-CLAIM resolved >/dev/null; echo $?)" -ne 0
        echo "INSIGHT_CLAIM_OK concurrent_winners=1 restart_block=1 failure_release=1 resolved_block=1"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"INSIGHT_CLAIM_OK concurrent_winners=1 restart_block=1 failure_release=1 resolved_block=1"* ]]
}

# test_necessity: pickerはreservation ledgerだけでなくactive/terminal task・reportも
# 候補から除外し、先頭候補の状態に関係なく次のpending insightを選ぶ不変量を守る。
@test "reflux insight picker skips reserved active and terminal candidates" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs" "$STATE_DIR"
        cat > "$SCRIPT_DIR/queue/insights.yaml" <<YAML
insights:
- id: INS-RESERVED
  priority: high
  status: pending
- id: INS-ACTIVE
  priority: medium
  status: pending
- id: INS-TERMINAL
  priority: low
  status: pending
- id: INS-ELIGIBLE
  priority: low
  status: pending
YAML
        printf "2026-08-27T00:00:00+09:00\tINS-RESERVED\talpha\n" > "$STATE_DIR/insight_reservations.tsv"
        cat > "$SCRIPT_DIR/queue/tasks/alpha.yaml" <<YAML
task:
  parent_cmd: cmd_reflux_insight_active
  status: in_progress
  purpose: process INS-ACTIVE
YAML
        cat > "$SCRIPT_DIR/queue/reports/terminal_report.yaml" <<YAML
parent_cmd: cmd_reflux_insight_terminal
status: completed
result:
  summary: INS-TERMINAL resolved
YAML
        REFLUX_INSIGHTS_FILE="$SCRIPT_DIR/queue/insights.yaml"
        REFLUX_INSIGHT_RESERVATION_LEDGER="$STATE_DIR/insight_reservations.tsv"
        export REFLUX_INSIGHTS_FILE REFLUX_INSIGHT_RESERVATION_LEDGER
        test "$(_reflux_first_pending_insight_id)" = INS-ELIGIBLE
        echo "INSIGHT_PICKER_OK reserved=1 active=1 terminal=1 selected=INS-ELIGIBLE"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"INSIGHT_PICKER_OK reserved=1 active=1 terminal=1 selected=INS-ELIGIBLE"* ]]
}

# test_necessity: AUTO-DONEとdeployが同一agent lockで直列化され、旧parent/archive reportでtaskを書換えない不変量を守る。
@test "AUTO-DONE deploy lock boundary is retryable and archive symlinks are inactive" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1; source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"; LOG="$BATS_TEST_TMPDIR/log"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/gates/cmd_new" "$SCRIPT_DIR/queue/locks" "$STATE_DIR"; : >"$LOG"
        log() { printf "%s\n" "$1" >>"$LOG"; }; write_karo_snapshot() { :; }
        _reflux_promotion_record_completion() { :; }; report_monitor_state() { printf "pass_terminal\n"; }
        run_report_gate_deduped() { printf "PASS\n"; return 0; }
        yaml_field_set() { bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$@"; }
        task="$SCRIPT_DIR/queue/tasks/alpha.yaml"; report="$SCRIPT_DIR/queue/reports/alpha_report_cmd_new.yaml"
        printf "task:\n  parent_cmd: cmd_new\n  task_id: task_new\n  status: in_progress\n" >"$task"
        printf "parent_cmd: cmd_new\ntask_id: task_new\nstatus: completed\ntimestamp: 2026-07-19T12:00:39+09:00\n" >"$report"
        python3 -c "import json,sys; json.dump({\"version\":1,\"state\":\"clear\",\"cmd_id\":\"cmd_new\",\"completion_generation\":\"a\"*64,\"persisted_at_ns\":1},open(sys.argv[1],\"w\"))" "$SCRIPT_DIR/queue/gates/cmd_new/gate_worker.clear.json"
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

# test_necessity: report完了をtask doneへ反映する前にcommit/report gateとtask-owned
# dirtyを検証し、done後のdirty再発も検知し続ける不変量を守る。
@test "AUTO-DONE blocks uncommitted or ungated reports before and after done" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"; LOG="$BATS_TEST_TMPDIR/log"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/locks" "$SCRIPT_DIR/scripts/lib" "$STATE_DIR"
        cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
        git -C "$SCRIPT_DIR" init -q
        git -C "$SCRIPT_DIR" config user.email test@example.invalid
        git -C "$SCRIPT_DIR" config user.name fixture
        printf "clean\n" > "$SCRIPT_DIR/scripts/a.sh"
        git -C "$SCRIPT_DIR" add scripts/a.sh
        git -C "$SCRIPT_DIR" commit -q -m fixture
        log() { printf "%s\n" "$1" >> "$LOG"; }
        send_inbox_message() { printf "%s|%s\n" "$1" "$3" >> "$BATS_TEST_TMPDIR/messages"; }
        _reflux_promotion_record_completion_detached() { return 0; }
        refresh_karo_snapshot_task_assignment() { return 0; }
        report_monitor_state() { printf "pass_terminal\n"; }
        yaml_field_set() { bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$@"; }
        make_fixture() {
            local name="$1" task_id="$2" report_name="$3"
            printf "task:\n  parent_cmd: cmd_%s\n  task_id: %s\n  report_id: rpt-%s\n  report_identity_version: 2\n  status: in_progress\n  target_path:\n    - scripts/a.sh\n  planned_paths:\n    - scripts/a.sh\n" "$name" "$task_id" "$name" > "$SCRIPT_DIR/queue/tasks/${name}.yaml"
            printf "parent_cmd: cmd_%s\ntask_id: %s\nreport_id: rpt-%s\nreport_identity_version: 2\nstatus: completed\ntimestamp: 2026-08-18T07:00:00+09:00\n" "$name" "$task_id" "$name" > "$SCRIPT_DIR/queue/reports/${report_name}.yaml"
        }
        find_matching_report_file() { printf "%s/queue/reports/%s_report.yaml\n" "$SCRIPT_DIR" "$1"; }
        run_report_gate_deduped() { printf "PASS\n"; return 0; }
        review_two_phase_ready() { return 0; }

        make_fixture dirty dirty_task dirty_report
        printf "dirty\n" > "$SCRIPT_DIR/scripts/a.sh"
        mkdir -p "$SCRIPT_DIR/queue/gates/cmd_dirty"
        python3 -c "import json,sys; json.dump({\"version\":1,\"state\":\"clear\",\"cmd_id\":\"cmd_dirty\",\"completion_generation\":\"a\"*64,\"persisted_at_ns\":1},open(sys.argv[1],\"w\"))" "$SCRIPT_DIR/queue/gates/cmd_dirty/gate_worker.clear.json"
        dirty_to_done=0
        check_and_update_done_task dirty && dirty_to_done=1 || true
        [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/dirty.yaml" status)" = in_progress ]

        printf "clean\n" > "$SCRIPT_DIR/scripts/a.sh"
        mkdir -p "$SCRIPT_DIR/queue/gates/cmd_clean"
        python3 -c "import json,sys; json.dump({\"version\":1,\"state\":\"clear\",\"cmd_id\":\"cmd_clean\",\"completion_generation\":\"a\"*64,\"persisted_at_ns\":1},open(sys.argv[1],\"w\"))" "$SCRIPT_DIR/queue/gates/cmd_clean/gate_worker.clear.json"
        make_fixture clean clean_task clean_report
        clean_to_done=0
        check_and_update_done_task clean && clean_to_done=1 || true
        [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/clean.yaml" status)" = done ]

        printf "dirty-again\n" > "$SCRIPT_DIR/scripts/a.sh"
        done_dirty_block=0
        check_and_update_done_task clean && true || done_dirty_block=1
        [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/clean.yaml" status)" = done ]

        make_fixture ungated ungated_task ungated_report
        mkdir -p "$SCRIPT_DIR/queue/gates/cmd_ungated"
        python3 -c "import json,sys; json.dump({\"version\":1,\"state\":\"clear\",\"cmd_id\":\"cmd_ungated\",\"completion_generation\":\"a\"*64,\"persisted_at_ns\":1},open(sys.argv[1],\"w\"))" "$SCRIPT_DIR/queue/gates/cmd_ungated/gate_worker.clear.json"
        run_report_gate_deduped() { printf "FAIL: fixture gate\n"; return 1; }
        ungated_to_done=0
        check_and_update_done_task ungated && ungated_to_done=1 || true
        [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/ungated.yaml" status)" = in_progress ]

        printf "dirty_to_done=%s clean_to_done=%s done_dirty_block=%s ungated_to_done=%s\n" \
            "$dirty_to_done" "$clean_to_done" "$done_dirty_block" "$ungated_to_done"
        grep -q AUTO-DONE-BLOCK-UNCOMMITTED "$LOG"
        grep -q AUTO-DONE-BLOCK-REPORT-GATE "$LOG"
        test "$(grep -c uncommitted_block "$BATS_TEST_TMPDIR/messages")" -ge 2
        test "$(grep -c report_format_fix "$BATS_TEST_TMPDIR/messages")" -ge 1
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"dirty_to_done=0 clean_to_done=1 done_dirty_block=1 ungated_to_done=0"* ]]
}

# test_necessity: CLEAR receipt is the sole terminal boundary for report
# completion; missing/invalid receipts must keep tasks non-terminal and notify Karo.
@test "AUTO-DONE requires generation-bound CLEAR receipt for four ninja fixtures" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"; LOG="$BATS_TEST_TMPDIR/log"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/gates" "$SCRIPT_DIR/queue/locks" "$SCRIPT_DIR/scripts/lib" "$STATE_DIR"
        cp "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
        log() { printf "%s\n" "$1" >> "$LOG"; }
        send_inbox_message() { printf "%s|%s\n" "$1" "$3" >> "$BATS_TEST_TMPDIR/messages"; }
        _reflux_promotion_record_completion_detached() { return 0; }
        refresh_karo_snapshot_task_assignment() { return 0; }
        report_monitor_state() { printf "pass_terminal\n"; }
        run_report_gate_deduped() { printf "PASS\n"; return 0; }
        review_two_phase_ready() { return 0; }
        yaml_field_set() { bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$@"; }
        make_fixture() {
            local name="$1" status="$2"
            printf "task:\n  parent_cmd: cmd_%s\n  task_id: task_%s\n  report_id: rpt-%s\n  report_identity_version: 2\n  status: %s\n" "$name" "$name" "$name" "$status" > "$SCRIPT_DIR/queue/tasks/${name}.yaml"
            printf "parent_cmd: cmd_%s\ntask_id: task_%s\nreport_id: rpt-%s\nreport_identity_version: 2\nstatus: completed\ntimestamp: 2026-08-18T09:00:00+09:00\n" "$name" "$name" "$name" > "$SCRIPT_DIR/queue/reports/${name}_report.yaml"
        }
        write_clear() {
            local name="$1"; mkdir -p "$SCRIPT_DIR/queue/gates/cmd_${name}"
            python3 -c "import json,sys; json.dump({\"version\":1,\"state\":\"clear\",\"cmd_id\":\"cmd_\"+sys.argv[2],\"completion_generation\":\"a\"*64,\"persisted_at_ns\":1},open(sys.argv[1],\"w\"))" \
                "$SCRIPT_DIR/queue/gates/cmd_${name}/gate_worker.clear.json" "$name"
        }
        find_matching_report_file() { printf "%s/queue/reports/%s_report.yaml\n" "$SCRIPT_DIR" "$1"; }

        # Four pre-fix cases: report completed/PASS or terminal task state without CLEAR.
        make_fixture hayate done; make_fixture saizo idle; make_fixture kotaro done; make_fixture hanzo idle
        blocked_without_clear=0
        for name in hayate saizo kotaro hanzo; do
            check_and_update_done_task "$name" || blocked_without_clear=$((blocked_without_clear + 1))
        done
        done_without_clear=0
        for name in hayate saizo kotaro hanzo; do
            [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${name}.yaml" status)" = done ] && done_without_clear=$((done_without_clear + 1))
            [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${name}.yaml" status)" = in_progress ]
        done

        clear_to_done=0
        for name in hayate saizo kotaro hanzo; do
            write_clear "$name"
            check_and_update_done_task "$name" && clear_to_done=$((clear_to_done + 1))
        done
        clear_reentry=0
        for name in hayate saizo kotaro hanzo; do
            check_and_update_done_task "$name" && clear_reentry=$((clear_reentry + 1))
        done

        # A retained old report must not satisfy the current task generation,
        # even when parent_cmd/task_id and CLEAR are otherwise present.
        make_fixture retained in_progress
        printf "task:\n  parent_cmd: cmd_retained\n  task_id: task_retained\n  report_id: rpt-current\n  report_identity_version: 2\n  status: in_progress\n" > "$SCRIPT_DIR/queue/tasks/retained.yaml"
        printf "parent_cmd: cmd_retained\ntask_id: task_retained\nreport_id: rpt-old\nreport_identity_version: 2\nstatus: completed\ntimestamp: 2026-08-18T09:00:00+09:00\n" > "$SCRIPT_DIR/queue/reports/retained_report.yaml"
        write_clear retained
        old_report_done=0
        check_and_update_done_task retained && old_report_done=1 || true
        [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/retained.yaml" status)" = in_progress ]
        printf "parent_cmd: cmd_retained\ntask_id: task_retained\nreport_id: rpt-current\nreport_identity_version: 2\nstatus: completed\ntimestamp: 2026-08-18T09:00:00+09:00\n" > "$SCRIPT_DIR/queue/reports/retained_report.yaml"
        retained_clear_done=0
        check_and_update_done_task retained && retained_clear_done=1 || true
        [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/retained.yaml" status)" = done ]

        yaml_field_set "$SCRIPT_DIR/queue/tasks/hayate.yaml" task status in_progress
        run_report_gate_deduped() { printf "FAIL: fixture gate\n"; return 1; }
        gate_fail_done=0
        check_and_update_done_task hayate && gate_fail_done=1 || true
        [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/hayate.yaml" status)" = in_progress ]
        notifications=$(grep -c "^karo|gate_clear_required$" "$BATS_TEST_TMPDIR/messages" || true)
        printf "pre_fix_done_without_clear=4 blocked_without_clear=%s done_without_clear=%s clear_to_done=%s clear_reentry=%s old_report_done=%s retained_clear_done=%s gate_fail_done=%s normal_false_block=0 notifications=%s\n" \
            "$blocked_without_clear" "$done_without_clear" "$clear_to_done" "$clear_reentry" "$old_report_done" "$retained_clear_done" "$gate_fail_done" "$notifications"
        [ "$blocked_without_clear" -eq 4 ]
        [ "$done_without_clear" -eq 0 ]
        [ "$clear_to_done" -eq 4 ]
        [ "$clear_reentry" -eq 4 ]
        [ "$old_report_done" -eq 0 ]
        [ "$retained_clear_done" -eq 1 ]
        [ "$gate_fail_done" -eq 0 ]
        [ "$notifications" -eq 4 ]
        grep -q AUTO-DONE-BLOCK-NO-CLEAR "$LOG"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"pre_fix_done_without_clear=4 blocked_without_clear=4 done_without_clear=0 clear_to_done=4 clear_reentry=4 old_report_done=0 retained_clear_done=1 gate_fail_done=0 normal_false_block=0 notifications=4"* ]]
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
if find "/proc/$$/fd" -type l -lname "*/deploy_ninja_*.lock" -print -quit | grep -q .; then
    printf "leaked-fd\n" >>"$SCRIPT_DIR/child_fd_leaks"
fi
printf "notify\n" >>"$SCRIPT_DIR/notifications"
SH
        export SCRIPT_DIR; chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

        # snapshot取得後に配備が成立した敵対ケース: 修正前は1通知、修正後は0通知。
        bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/queue/tasks/beta.yaml" task status assigned
        check_karo_idle_cycle
        [ ! -e "$SCRIPT_DIR/notifications" ]

        # 途中のlock取得失敗でも、それ以前に取得したFDを全て解放する。
        bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/queue/tasks/beta.yaml" task status idle
        flock "$SCRIPT_DIR/queue/locks/deploy_ninja_beta.lock" -c "sleep 1" & holder=$!; sleep 0.1
        check_karo_idle_cycle
        flock -n "$SCRIPT_DIR/queue/locks/deploy_ninja_alpha.lock" -c true
        wait "$holder"

        # 真の全idleは1通知。初回後の3 cycleはcooldownで配送も送信成功ログも0。
        KARO_IDLE_COOLDOWN=1800
        check_karo_idle_cycle
        check_karo_idle_cycle
        check_karo_idle_cycle
        check_karo_idle_cycle
        [ "$(wc -l <"$SCRIPT_DIR/notifications")" -eq 1 ]
        [ "$(grep -c "Sent improvement cycle nudge to karo" "$LOG")" -eq 1 ]
        [ "$(grep -c "nudging karo" "$LOG" || true)" -eq 0 ]
        [ ! -e "$SCRIPT_DIR/child_fd_leaks" ]
        for agent in alpha beta; do
            flock -n "$SCRIPT_DIR/queue/locks/deploy_ninja_${agent}.lock" -c true
        done
        python3 -c "import yaml; [yaml.safe_load(open(p)) for p in [\"$SCRIPT_DIR/queue/tasks/alpha.yaml\", \"$SCRIPT_DIR/queue/tasks/beta.yaml\"]]"
    '
    [ "$status" -eq 0 ]
}

# test_necessity: ninja_monitor変更を次cycleの業務処理前に反映し、旧processのdeploy lock FDを新processへ継承しない不変量を守る。
@test "hot reload runs every cycle and closes inherited deploy lock fds before exec" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1; source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        root="$BATS_TEST_TMPDIR/root"; mkdir -p "$root/queue/locks"; LOG="$root/log"
        _NM_SCRIPT_PATH="$root/ninja_monitor.sh"; printf "old\n" >"$_NM_SCRIPT_PATH"
        _NM_START_MTIME=1
        exec {fd_a}>"$root/queue/locks/deploy_ninja_alpha.lock"; flock -n "$fd_a"
        exec {fd_b}>"$root/queue/locks/deploy_ninja_beta.lock"; flock -n "$fd_b"
        _ninja_monitor_hot_reload_exec() { printf "exec:%s\n" "$1" >"$root/reloaded"; }
        reload_ninja_monitor_if_updated
        [ "$(cat "$root/reloaded")" = "exec:$_NM_SCRIPT_PATH" ]
        flock -n "$root/queue/locks/deploy_ninja_alpha.lock" -c true
        flock -n "$root/queue/locks/deploy_ninja_beta.lock" -c true
        [ "$(grep -c HOT-RELOAD "$LOG")" -eq 1 ]
    '
    [ "$status" -eq 0 ]
}

# test_necessity: 旧monitorのexecからlock FDを継承しても、mtime一致の新process startupで無条件解放する不変量を守る。
@test "startup closes deploy lock fds inherited from stale monitor even when mtime is current" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1; source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        root="$BATS_TEST_TMPDIR/root"; mkdir -p "$root/queue/locks"
        exec {fd_a}>"$root/queue/locks/deploy_ninja_alpha.lock"; flock -n "$fd_a"
        exec {fd_b}>"$root/queue/locks/deploy_ninja_beta.lock"; flock -n "$fd_b"
        _NM_SCRIPT_PATH="$PROJECT_ROOT/scripts/ninja_monitor.sh"
        _NM_START_MTIME="$(stat -c %Y "$_NM_SCRIPT_PATH")"
        close_inherited_deploy_lock_fds
        reload_ninja_monitor_if_updated
        flock -n "$root/queue/locks/deploy_ninja_alpha.lock" -c true
        flock -n "$root/queue/locks/deploy_ninja_beta.lock" -c true
    '
    [ "$status" -eq 0 ]
}

# test_necessity: stale monitorからinbox_watcherへ継承したdeploy lock FDをstartupで閉じ、inotify/sleep子孫へ伝播させない不変量を守る。
@test "inbox watcher startup closes inherited deploy lock before spawning descendants" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        root="$BATS_TEST_TMPDIR/root"; mkdir -p "$root/queue/locks"
        lock="$root/queue/locks/deploy_ninja_hayate.lock"
        exec {fd}>"$lock"; flock -n "$fd"
        exec env PROJECT_ROOT="$PROJECT_ROOT" LOCK_PATH="$lock" INBOX_WATCHER_LIB_ONLY=1 bash -c '\''
            set -- hayate dummy-pane
            source "$PROJECT_ROOT/scripts/inbox_watcher.sh"
            ! find "/proc/$$/fd" -type l -lname "*/deploy_ninja_*.lock" -print -quit | grep -q .
            sleep 0.2 & child=$!
            ! find "/proc/$child/fd" -type l -lname "*/deploy_ninja_*.lock" -print -quit | grep -q .
            flock -n "$LOCK_PATH" -c true
            wait "$child"
        '\''
    '
    [ "$status" -eq 0 ]
}
# test_necessity: checkpoint成果物ready後の10cycleでreview通知をexactly-once配送し、既読後reviewedへ閉じる不変量を守る。
@test "checkpoint manifest promotes ready and delivers review exactly once" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1; source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; LOG="$BATS_TEST_TMPDIR/log"; mkdir -p "$SCRIPT_DIR/queue/checkpoint_manifests" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/docs/research" "$SCRIPT_DIR/scripts"
        cp "$PROJECT_ROOT/scripts/inbox_write.sh" "$SCRIPT_DIR/scripts/inbox_write.sh"; ln -s "$PROJECT_ROOT/scripts/lib" "$SCRIPT_DIR/scripts/lib"; : >"$LOG"
        content="cmd_fixture worker=alpha artifact docs/research/later.md"; b64=$(printf %s "$content" | base64 -w0)
        printf "%s\n" state=awaiting_artifact task_id=cmd_fixture worker=alpha reviewer=gunshi artifact_path=docs/research/later.md artifact_hash=- requested_at_epoch=1 ready_at_epoch=0 reviewed_at_epoch=0 delivery_count=0 last_wake_epoch=0 request_type=verify_request request_from=karo request_action=review content_b64="$b64" fingerprint=f1 >"$SCRIPT_DIR/queue/checkpoint_manifests/f1.manifest"
        printf artifact >"$SCRIPT_DIR/docs/research/later.md"
        for _ in {1..10}; do INBOX_WRITE_TEST=1 process_checkpoint_manifests; done
        [ "$(grep -c "type: .verify_request" "$SCRIPT_DIR/queue/inbox/gunshi.yaml")" -eq 1 ]
        grep -q "^delivery_count=1$" "$SCRIPT_DIR/queue/checkpoint_manifests/f1.manifest"
        [ "$(grep -c CHECKPOINT-READY-DELIVER "$LOG")" -eq 1 ]
    '
    [ "$status" -eq 0 ]
}

# test_necessity: reflux insight配備は共有queueのdirty世代をscope限定checkpointで保存し、checkpoint失敗時だけ同一世代通知を重複せずBLOCKする不変量を守る。
@test "reflux insight dirty target checkpoints before publication and fails closed" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY

        root="$(mktemp -d)"
        trap '\''rm -r "$root"'\'' EXIT
        SCRIPT_DIR="$root"
        STATE_DIR="$root/state"
        mkdir -p "$root/queue/tasks" "$root/queue" "$root/scripts" "$root/logs" "$STATE_DIR"
        cat > "$root/queue/insights.yaml" <<YAML
insights:
- id: INS-DIRTY-1
  source: self_retro
  status: pending
YAML
        cp "$root/queue/insights.yaml" "$root/clean-insights.yaml"
        cat > "$root/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML
        cat > "$root/scripts/deploy_task.sh" <<SH
#!/usr/bin/env bash
printf "%s\\n" "DEPLOY_CALLED:\$*" >> "$root/deploy.log"
cp "\$3" "$root/deployed.yaml"
SH
        chmod +x "$root/scripts/deploy_task.sh"
        cat > "$root/scripts/inbox_write.sh" <<SH
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "$root/notifications.log"
SH
        chmod +x "$root/scripts/inbox_write.sh"
        cat > "$root/scripts/ninja_scope_commit.sh" <<SH
#!/usr/bin/env bash
printf "%s\\n" checkpoint >> "$root/checkpoint.calls"
if [ -e "$root/checkpoint.fail" ]; then exit 1; fi
git -C "$root" add -- queue/insights.yaml
git -C "$root" commit -qm checkpoint
SH
        chmod +x "$root/scripts/ninja_scope_commit.sh"

        git -C "$root" init -q
        git -C "$root" config user.email test@example.com
        git -C "$root" config user.name test
        git -C "$root" add queue/insights.yaml queue/tasks/hayate.yaml
        git -C "$root" commit -qm baseline

        log() { printf "%s\\n" "$1" >> "$root/test.log"; }
        yaml_field_get() {
            grep -m1 -E "^[[:space:]]*$2:" "$1" | sed "s/.*:[[:space:]]*//; s/[\\\"'"'"' ]//g" || true
        }
        _training_pipeline_has_work() { return 1; }
        _reflux_zero_backlink_inventory() { printf "0\\t-\\tok\\n"; }
        _reflux_promotion_inventory() { printf "0\\t-\\tok\\n"; }
        declare -gA REFLUX_IDLE_FIRST_SEEN
        REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD=1
        REFLUX_AUTO_DEPLOY_COOLDOWN=1
        REFLUX_AUTO_DEPLOY_STATE_PREFIX="$root/state/reflux_auto"
        REFLUX_DIRTY_NOTICE_STATE_PREFIX="$root/state/reflux_dirty_notice"

        run_reflux() {
            REFLUX_IDLE_FIRST_SEEN[hayate]=0
            (cd / && _handle_reflux_auto_deploy hayate "$1") || true
        }
        run_reflux 100
        [ "$(grep -c DEPLOY_CALLED "$root/deploy.log")" -eq 1 ]

        cat >> "$root/queue/insights.yaml" <<YAML
- id: INS-DIRTY-2
  source: self_retro
  status: pending
YAML
        run_reflux 200
        [ "$(grep -c DEPLOY_CALLED "$root/deploy.log")" -eq 2 ]
        [ ! -s "$root/notifications.log" ]
        grep -q "REFLUX-AUTO-CHECKPOINT:.*result=clean" "$root/test.log"
        [ "$(wc -l < "$root/checkpoint.calls")" -eq 1 ]

        git -C "$root" checkout HEAD -- queue/insights.yaml
        cat >> "$root/queue/insights.yaml" <<YAML
- id: INS-DIRTY-ACTIVE
  source: self_retro
  status: pending
YAML
        cat > "$root/queue/tasks/kagemaru.yaml" <<YAML
task:
  status: in_progress
  target_path: queue/insights.yaml
YAML
        run_reflux 250
        [ "$(grep -c DEPLOY_CALLED "$root/deploy.log")" -eq 2 ]
        [ ! -s "$root/notifications.log" ]
        [ "$(wc -l < "$root/checkpoint.calls")" -eq 1 ]
        rm "$root/queue/tasks/kagemaru.yaml"

        git -C "$root" checkout HEAD -- queue/insights.yaml
        sed -i "0,/source: self_retro/s//source: manual/" "$root/queue/insights.yaml"
        run_reflux 300
        [ "$(wc -l < "$root/notifications.log")" -eq 1 ]
        [ "$(grep -c DEPLOY_CALLED "$root/deploy.log")" -eq 2 ]
        grep -q "target=queue/insights.yaml" "$root/notifications.log"
        grep -q "task_publication=0" "$root/test.log"

        run_reflux 400
        [ "$(wc -l < "$root/notifications.log")" -eq 1 ]
        [ "$(grep -c DEPLOY_CALLED "$root/deploy.log")" -eq 2 ]

        git -C "$root" checkout HEAD -- queue/insights.yaml
        cat >> "$root/queue/insights.yaml" <<YAML
- id: INS-DIRTY-MALFORMED
  source: self_retro
  status: pending
YAML
        echo '  broken: [' >> "$root/queue/insights.yaml"
        run_reflux 500
        [ "$(grep -c DEPLOY_CALLED "$root/deploy.log")" -eq 2 ]
        [ "$(wc -l < "$root/notifications.log")" -eq 2 ]

        git -C "$root" checkout HEAD -- queue/insights.yaml
        cat >> "$root/queue/insights.yaml" <<YAML
- id: INS-DIRTY-COMMIT-FAIL
  source: self_retro
  status: pending
YAML
        touch "$root/checkpoint.fail"
        run_reflux 600
        [ "$(grep -c DEPLOY_CALLED "$root/deploy.log")" -eq 2 ]
        [ "$(wc -l < "$root/notifications.log")" -eq 3 ]
        grep -q 'INS-DIRTY-COMMIT-FAIL' "$root/queue/insights.yaml"
        echo "REFLUX_DIRTY_GENERATIONS_OK deploys=2 notifications=3 checkpoints=1"
    '
    [ "$status" -eq 0 ]
}

# test_necessity: formally reviewed terminal reports keep gate ownership but do
# not cause repeated Codex respawn or remove the worker from idle availability.
@test "formally reviewed done task skips repeated CTX0 respawn" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" \
            "$SCRIPT_DIR/queue/gates/cmd_reviewed" "$STATE_DIR"
        printf "task:\n  status: done\n  parent_cmd: cmd_reviewed\n" > "$SCRIPT_DIR/queue/tasks/hayate.yaml"
        printf "status: completed\nparent_cmd: cmd_reviewed\nverdict: PASS\n" > "$SCRIPT_DIR/queue/reports/hayate_report_cmd_reviewed.yaml"
        printf "source: two_phase_review\nresult: LGTM\n" > "$SCRIPT_DIR/queue/gates/cmd_reviewed/review_gate.done"
        PANE_TARGETS[hayate]=pane
        tmux() { [ "$1" = display-message ] && printf "hayate\n"; }
        cli_type() { printf "codex\n"; }
        get_context_pct() { printf "0\n"; }
        safe_send_clear() { printf "RESPAWN_CALLED\n"; return 0; }
        log() { printf "%s\n" "$1"; }
        _handle_auto_clear hayate 1000
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-CLEAR-SKIP-FORMAL-REVIEW"* ]]
    [[ "$output" != *"RESPAWN_CALLED"* ]]
}

# test_necessity: run_lock_cleanup must prune only linked-worktree metadata
# whose gitdir target is absent, while retaining a live worktree entry.
@test "run_lock_cleanup prunes stale linked-worktree metadata after one interval" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY

        TMP_ROOT="$BATS_TEST_TMPDIR/root"
        REPO="$TMP_ROOT/repo"
        SCRIPT_DIR="$TMP_ROOT/runtime"
        STATE_DIR="$TMP_ROOT/state"
        LOG="$TMP_ROOT/monitor.log"
        mkdir -p "$TMP_ROOT" "$SCRIPT_DIR" "$STATE_DIR"
        git init -q "$REPO"
        git -C "$REPO" config user.email test@example.invalid
        git -C "$REPO" config user.name test
        printf "base\n" > "$REPO/README"
        git -C "$REPO" add README
        git -C "$REPO" commit -q -m base
        git -C "$REPO" worktree add -q "$TMP_ROOT/live" HEAD
        git -C "$REPO" worktree add -q "$TMP_ROOT/stale" HEAD
        rm -rf "$TMP_ROOT/stale"

        LOCK_CLEANUP_DIR="$TMP_ROOT/locks"
        WORKTREE_METADATA_REPO="$REPO"
        SCRATCH_RETENTION_REPO="$REPO"
        SCRATCH_QUARANTINE_DIR="$TMP_ROOT/scratch-quarantine"
        LOCK_CLEANUP_INTERVAL=3600
        LAST_LOCK_CLEANUP=0
        mkdir -p "$LOCK_CLEANUP_DIR"
        log() { printf "%s\n" "$1" >> "$LOG"; }

        before=$(worktree_metadata_entry_count "$REPO")
        missing_before=$(worktree_metadata_missing_gitdir_count "$REPO")
        run_lock_cleanup
        after=$(worktree_metadata_entry_count "$REPO")
        missing_after=$(worktree_metadata_missing_gitdir_count "$REPO")
        test "$before" -eq 2
        test "$missing_before" -eq 1
        test "$after" -eq 1
        test "$missing_after" -eq 0
        test -d "$TMP_ROOT/live"
        grep -q "WORKTREE-METADATA: repo=$REPO entries_before=2 missing_before=1 pruned=1 entries_after=1 missing_after=0" "$LOG"
        printf "worktree_entries=%s->%s missing_gitdir=%s->%s pruned=1\n" "$before" "$after" "$missing_before" "$missing_after"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"worktree_entries=2->1 missing_gitdir=1->0 pruned=1"* ]]
}
