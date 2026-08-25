#!/usr/bin/env bats
# test_necessity: ninja_monitorは一次runtime/task状態が進行中のagentをstallと誤判定しない
# test_ninja_monitor_stall.bats - ninja_monitor stall recovery + misc behavior tests
# Merged: auto_deploy_done + snapshot_idle tests

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # Bats already provisions an isolated directory per test. Reuse it instead
    # of spawning mktemp 65 times across this suite.
    export NINJA_MONITOR_TEST_ROOT="$BATS_TEST_TMPDIR/ninja-monitor"
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_BIN"
    if ! command -v sqlite3 >/dev/null 2>&1; then
        cat > "$TEST_BIN/sqlite3" <<'EOF'
#!/usr/bin/env python3
import sqlite3
import sys

if len(sys.argv) < 2:
    sys.exit(1)

db_path = sys.argv[1]
sql = sys.argv[2] if len(sys.argv) > 2 else sys.stdin.read()
conn = sqlite3.connect(db_path)
try:
    stripped = sql.strip()
    if stripped.lower().startswith("select"):
        cur = conn.execute(stripped.rstrip(";"))
    else:
        cur = conn.executescript(sql)
    if getattr(cur, "description", None):
        for row in cur.fetchall():
            print("|".join("" if value is None else str(value) for value in row))
    conn.commit()
finally:
    conn.close()
EOF
        chmod +x "$TEST_BIN/sqlite3"
    fi
    export PATH="$TEST_BIN:$PATH"
}

# test_necessity: a completed report with durable Gunshi LGTM is terminal
# evidence for its parent_cmd even after the worker lease points at a later cmd.
@test "old reviewed parent cmd is not reported as undeployed after worker redeploy" {
    DELEGATED_AT=$(date -d "20 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
DELEGATED_AT="'"$DELEGATED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT/reviewed-parent"
SCRIPT_DIR="$TMP_ROOT"; PROJECT_ROOT="$TMP_ROOT"; LOG="$TMP_ROOT/monitor.log"; STATE_DIR="$TMP_ROOT/state"
mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/queue/reports" "$TMP_ROOT/queue/gates/cmd_4274/review_approvals/reports" "$TMP_ROOT/scripts" "$TMP_ROOT/logs" "$STATE_DIR"
cat > "$TMP_ROOT/queue/shogun_to_karo.yaml" <<EOF
commands:
  cmd_4274:
    status: delegated
    timestamp: "2026-04-03T01:12:00"
    delegated_at: "$DELEGATED_AT"
EOF
cat > "$TMP_ROOT/queue/tasks/saizo.yaml" <<EOF
task:
  parent_cmd: cmd_4277
  task_id: cmd_4277_full
  ac_version: cf5a1428
  status: acknowledged
EOF
cat > "$TMP_ROOT/queue/reports/saizo_report_cmd_4274.yaml" <<EOF
worker_id: saizo
parent_cmd: cmd_4274
task_id: cmd_4274_full
ac_version_read: b4003b4b
status: completed
verdict: PASS
EOF
key=$(printf "%s" "queue/reports/saizo_report_cmd_4274.yaml" | sha256sum | awk "{print \$1}")
mkdir -p "$TMP_ROOT/queue/gates/cmd_4274/review_approvals/reports/$key"
printf "result: LGTM\\n" > "$TMP_ROOT/queue/gates/cmd_4274/review_approvals/reports/$key/gunshi.yaml"
cat > "$TMP_ROOT/scripts/ntfy.sh" <<EOF
#!/usr/bin/env bash
printf "%s\\n" "\${1:-}" >> "$TMP_ROOT/ntfy.log"
EOF
cat > "$TMP_ROOT/scripts/inbox_write.sh" <<EOF
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "$TMP_ROOT/inbox.log"
EOF
chmod +x "$TMP_ROOT/scripts/ntfy.sh" "$TMP_ROOT/scripts/inbox_write.sh"
before=$(sha256sum "$TMP_ROOT/queue/tasks/saizo.yaml")
log(){ printf "%s\\n" "$1" >> "$LOG"; }
declare -A UNDEPLOYED_CMD_NOTIFIED STALE_CMD_NOTIFIED
cycle=1
check_undeployed_cmds
STALE_CMD_THRESHOLD=1
check_stale_cmds
after=$(sha256sum "$TMP_ROOT/queue/tasks/saizo.yaml")
test "$before" = "$after"
test ! -s "$TMP_ROOT/ntfy.log"
test ! -s "$TMP_ROOT/inbox.log"
grep -q "completed report/review evidence" "$LOG"
printf "reviewed_parent_suppressed=true task_unchanged=true\\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"reviewed_parent_suppressed=true task_unchanged=true"* ]]
}

# test_necessity: active taskがpane静止・子処理なし・確認promptなしで長時間BUSY化した
# ときだけ家老へ一度通知し、pane変化/子処理/prompt/重複では通知しない不変量を守る。
@test "check_stall: stale active pane notifies karo once without self action" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="'"$BATS_TEST_TMPDIR"'/active-busy-stall"
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  task_id: cmd_active_stall_001
EOF

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
declare -A ACTIVE_STALL_FIRST_SEEN ACTIVE_STALL_PANE_FP ACTIVE_STALL_NOTIFIED
TEST_MESSAGES="$TMP_ROOT/messages.log"
TEST_LOG="$TMP_ROOT/monitor.log"
PANE_CONTENT=stable
CHILD_RC=1
PROMPT_RC=1
PANE_TARGETS[kagemaru]="shogun:2.4"

log() { printf "%s\n" "$1" >> "$TEST_LOG"; }
send_inbox_message() { printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$TEST_MESSAGES"; }
recover_dead_active_pane() { return 1; }
find_matching_report_file() { return 1; }
check_idle() { return 1; }
_pane_has_active_background_compute() { return "$CHILD_RC"; }
_pane_has_confirmation_prompt() { return "$PROMPT_RC"; }
tmux() {
    case "$*" in
        *"#{@agent_state}"*) printf "active\n" ;;
        *capture-pane*) printf "%s\n" "$PANE_CONTENT" ;;
        *) return 0 ;;
    esac
}

# First observation establishes the generation; the second crosses 25 minutes.
check_stall kagemaru
ACTIVE_STALL_FIRST_SEEN[kagemaru:cmd_active_stall_001]=$((EPOCHSECONDS - 1501))
check_stall kagemaru
check_stall kagemaru

# A pane change resets the generation and must not create a second alert.
PANE_CONTENT=changed
check_stall kagemaru

# Child compute and confirmation prompt each reset tracking without notifying.
PANE_CONTENT=child
CHILD_RC=0
check_stall kagemaru
PANE_CONTENT=prompt
CHILD_RC=1
PROMPT_RC=0
check_stall kagemaru

alerts=$(grep -c "^karo|stall_alert|" "$TEST_MESSAGES" || true)
self_actions=$(grep -c "^kagemaru|" "$TEST_MESSAGES" || true)
pane_watches=$(grep -c "pane_changed=1" "$TEST_LOG" || true)
child_resets=$(grep -c "child_compute=1" "$TEST_LOG" || true)
prompt_resets=$(grep -c "confirmation_prompt=1" "$TEST_LOG" || true)
dedupe=$(grep -c "ACTIVE-STALL-DEDUPE" "$TEST_LOG" || true)
printf "alerts=%s self_actions=%s pane_watches=%s child_resets=%s prompt_resets=%s dedupe=%s\n" \
  "$alerts" "$self_actions" "$pane_watches" "$child_resets" "$prompt_resets" "$dedupe"
test "$alerts" -eq 1
test "$self_actions" -eq 0
test "$pane_watches" -eq 2
test "$child_resets" -eq 1
test "$prompt_resets" -eq 1
test "$dedupe" -eq 1
'
    [ "$status" -eq 0 ]
    [ "$output" = "alerts=1 self_actions=0 pane_watches=2 child_resets=1 prompt_resets=1 dedupe=1" ]
}

# test_necessity: dependency待機のfailed workerは接続cmd CLEAR前0回/CLEAR後ちょうど1回だけ再配備される
@test "dependency continuation consumer releases failed task exactly once after GATE CLEAR" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

SCRIPT_DIR="'"$BATS_TEST_TMPDIR"'/dependency-continuation"
LOG="$SCRIPT_DIR/logs/ninja_monitor.log"
DEPENDENCY_CONTINUATION_GATE_LOG="$SCRIPT_DIR/logs/gate_fire_log.yaml"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/gates/cmd_dependency" "$SCRIPT_DIR/scripts/lib" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"
ln -s "'"$PROJECT_ROOT"'/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" "$5" >> "$SCRIPT_DIR/logs/deployments.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"
export SCRIPT_DIR

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  task_id: continuation_001
  status: failed
  wait_reason: dependency
  wait_connected_cmd: cmd_dependency
  continuation_task_id: continuation_001
EOF

declare -A PREV_STATE
PREV_STATE[saizo]=idle
log() { printf "%s\n" "$1" >> "$LOG"; }

# CLEAR前: waitのまま、配備0。
_handle_dependency_continuation saizo
test "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" status)" = failed
test ! -s "$SCRIPT_DIR/logs/deployments.log"

# CLEAR後: assignedへ1回だけ遷移。同cycle再試行でも重複0。
printf "GATE CLEAR: cmd_dependency\n" > "$SCRIPT_DIR/queue/gates/cmd_dependency/cmd_complete_gate.trigger.log"
_handle_dependency_continuation saizo
_handle_dependency_continuation saizo || true
test "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" status)" = assigned
test "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" wait_reason)" = dependency
test "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" wait_connected_cmd)" = cmd_dependency
test "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" continuation_task_id)" = continuation_001
test "$(wc -l < "$SCRIPT_DIR/logs/deployments.log")" -eq 1
grep -q "deploy_count=1 duplicate_count=0 release_latency_sec=" "$DEPENDENCY_CONTINUATION_GATE_LOG"
test "$(grep -c "result: BLOCK" "$DEPENDENCY_CONTINUATION_GATE_LOG" || true)" -eq 0

# unrelated failed taskは誤配備しない。
cat > "$SCRIPT_DIR/queue/tasks/hanzo.yaml" <<'"'"'EOF'"'"'
task:
  task_id: unrelated_001
  status: failed
EOF
_handle_dependency_continuation hanzo || true
test "$(wc -l < "$SCRIPT_DIR/logs/deployments.log")" -eq 1
printf "pre_clear=0 post_clear=1 duplicate=0 false_positive=0\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"pre_clear=0 post_clear=1 duplicate=0 false_positive=0"* ]]
}

# test_necessity: malformed dependency continuationは同一task+reasonをrestart後も1件だけdurable記録する
@test "dependency continuation invalid registration is durably deduped and terminal repair emits zero new actions" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

SCRIPT_DIR="'"$BATS_TEST_TMPDIR"'/dependency-invalid-dedupe"
LOG="$SCRIPT_DIR/logs/ninja_monitor.log"
DEPENDENCY_CONTINUATION_GATE_LOG="$SCRIPT_DIR/logs/gate_fire_log.yaml"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
cat > "$SCRIPT_DIR/queue/tasks/tobisaru.yaml" <<'"'"'EOF'"'"'
task:
  task_id: continuation_invalid_001
  status: failed
  wait_reason: dependency
  wait_connected_cmd: cmd_dependency
EOF
log() { printf "%s\n" "$1" >> "$LOG"; }

for _ in $(seq 1 24); do _handle_dependency_continuation tobisaru; done
before=$(grep -c "durable_fields=invalid" "$DEPENDENCY_CONTINUATION_GATE_LOG")

# Process memoryを使わず、新しいbash processがtask YAML上のfenceだけでdedupeする。
TEST_SCRIPT_DIR="$SCRIPT_DIR" TEST_GATE_LOG="$DEPENDENCY_CONTINUATION_GATE_LOG" PROJECT_ROOT="'"$PROJECT_ROOT"'" bash -lc '"'"'
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$TEST_SCRIPT_DIR"
LOG="$SCRIPT_DIR/logs/ninja_monitor.log"
DEPENDENCY_CONTINUATION_GATE_LOG="$TEST_GATE_LOG"
log() { printf "%s\\n" "$1" >> "$LOG"; }
_handle_dependency_continuation tobisaru
'"'"'
after_restart=$(grep -c "durable_fields=invalid" "$DEPENDENCY_CONTINUATION_GATE_LOG")

yaml_field_set "$SCRIPT_DIR/queue/tasks/tobisaru.yaml" task status done
for _ in $(seq 1 5); do _handle_dependency_continuation tobisaru || true; done
after_terminal=$(grep -c "durable_fields=invalid" "$DEPENDENCY_CONTINUATION_GATE_LOG")
printf "before=%s after_restart=%s after_terminal=%s\n" "$before" "$after_restart" "$after_terminal"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"before=1 after_restart=1 after_terminal=1"* ]]
}

@test "C4-07 report state cohort separates awaiting evidence and PASS terminal" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
tmp="'"$BATS_TEST_TMPDIR"'/c4-07"; mkdir -p "$tmp"
awaiting=0; terminal=0; pending=0; started=$(date +%s%3N)
for i in $(seq 1 12); do
  report="$tmp/r$i.yaml"
  case $((i % 3)) in
    1) printf "status: completed\nverdict: PASS\npost_deploy_evidence:\n  required: true\n  run_completed: false\n" > "$report" ;;
    2) printf "status: completed\nverdict: PASS\npost_deploy_evidence:\n  required: false\n  run_completed: false\n" > "$report" ;;
    0) printf "status: pending\nverdict: empty\npost_deploy_evidence:\n  required: false\n  run_completed: false\n" > "$report" ;;
  esac
  state=$(report_monitor_state "$report")
  case "$state" in awaiting_evidence) awaiting=$((awaiting+1));; pass_terminal) terminal=$((terminal+1));; report_pending) pending=$((pending+1));; *) exit 1;; esac
done
elapsed=$(( $(date +%s%3N) - started ))
printf "awaiting=%s terminal=%s pending=%s wall_ms=%s\n" "$awaiting" "$terminal" "$pending" "$elapsed"
[ "$awaiting" -eq 4 ] && [ "$terminal" -eq 4 ] && [ "$pending" -eq 4 ] && [ "$elapsed" -lt 5000 ]
'
    [ "$status" -eq 0 ]
    [[ "$output" == awaiting=4\ terminal=4\ pending=4* ]]
}

@test "fast path returns before maintenance job" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
NINJA_NAMES=(hanzo)
MARK="'"$BATS_TEST_TMPDIR"'/detected"
check_and_update_done_task() {
    printf detected > "$MARK"
    # Keep a real asynchronous maintenance child, but avoid a fixed ten-second
    # drain in this focused test.  The fast-path contract is return-before-child,
    # not the duration of the synthetic maintenance job.
    (sleep 1) &
    maintenance_pid=$!
}
start=$EPOCHREALTIME
monitor_task_state_fast_path
elapsed=$(awk -v s="$start" -v e="$EPOCHREALTIME" "BEGIN { print e-s }")
test -f "$MARK"
awk -v e="$elapsed" "BEGIN { exit !(e < 0.5) }"
# The latency assertion above must observe the asynchronous return, while the
# fixture itself must still own and reap its synthetic maintenance child.
# Otherwise bats can PASS and orphan the ten-second sleep into the aggregate
# runner process group and race the finite maintenance drain.
wait "$maintenance_pid"
'
    [ "$status" -eq 0 ]
}

# test_necessity: done-report探索がnested process-substitutionのpipe/FDを継承せず、cycle内で有限時間に収束する不変量を守る。
@test "done-report matching is pipe-safe and bounded" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -lc '
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY

        root="$BATS_TEST_TMPDIR/pipe-safe"
        SCRIPT_DIR="$root"
        mkdir -p "$root/queue/tasks" "$root/queue/reports" "$root/queue/locks"
        printf "task:\n  parent_cmd: cmd_pipe_safe\n  task_id: task_pipe_safe\n  status: in_progress\n" >"$root/queue/tasks/alpha.yaml"
        for i in $(seq -w 1 24); do
            printf "parent_cmd: cmd_other_%s\ntask_id: task_%s\nstatus: pending\n" "$i" "$i" >"$root/queue/reports/alpha_report_cmd_${i}.yaml"
        done
        printf "parent_cmd: cmd_pipe_safe\ntask_id: task_pipe_safe\nstatus: pending\n" >"$root/queue/reports/alpha_report_cmd_pipe_safe.yaml"

        exec 63< <(sleep 10)
        close_inherited_non_stdio_fds
        test ! -e /proc/$$/fd/63

        report=$(timeout 3 bash -c '\''
            export NINJA_MONITOR_LIB_ONLY=1
            source "$1/scripts/ninja_monitor.sh"
            unset NINJA_MONITOR_LIB_ONLY
            SCRIPT_DIR="$2"
            find_matching_report_file alpha
        '\'' _ "$PROJECT_ROOT" "$root")
        test "$(basename "$report")" = alpha_report_cmd_pipe_safe.yaml
        printf "report_match=1 inherited_fd_closed=1 timeout=3s\n"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "report_match=1 inherited_fd_closed=1 timeout=3s" ]
}

# test_necessity: cycle本体がpipe_read等で停止しても、更新scriptは20秒以内に既存generation fence経由で後継を起動する不変量を守る。
# regression_justification: cycle境界だけのmtime確認は本番PID878492で42秒超HOT-RELOAD 0件を再現したため、独立watcherの契約を固定する。
@test "hot-reload watcher launches a fenced successor without terminating the old generation" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -lc '
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY

        root="$BATS_TEST_TMPDIR/hot-reload-watch"
        STATE_DIR="$root/state"
        LOG="$root/monitor.log"
        NINJA_MONITOR_OWNER_FILE="$STATE_DIR/ninja_monitor.owner"
        script_path="$root/ninja_monitor.sh"
        capture="$root/launch.capture"
        generation="generation-live"
        mkdir -p "$STATE_DIR"
        printf "#!/bin/bash\n" > "$script_path"
        start_mtime=$(stat -c %Y "$script_path")
        printf "%s %s %s\n" "$$" "$generation" "$EPOCHSECONDS" > "$STATE_DIR/ninja_monitor.owner"
        NINJA_MONITOR_HOT_RELOAD_POLL_SEC=0.05
        # The fixture shell is not named ninja_monitor.sh; production uses the
        # real monitor PID and therefore does not need this override.
        NINJA_MONITOR_LIVENESS_OVERRIDE_PID="$$"
        export NINJA_MONITOR_LIVENESS_OVERRIDE_PID
        _NM_SCRIPT_PATH="$script_path"
        _NM_START_MTIME="$start_mtime"
        NINJA_MONITOR_GENERATION="$generation"

        _ninja_monitor_launch_hot_reload_successor() {
            printf "path=%s generation=%s mtime=%s\n" "$1" "$2" "$3" > "$capture"
        }
        export capture

        started=$(date +%s%3N)
        start_ninja_monitor_hot_reload_watch
        watcher_pid="$NINJA_MONITOR_HOT_RELOAD_WATCH_PID"
        watcher_cmd=$(tr "\0" " " < "/proc/$watcher_pid/cmdline")
        [[ "$watcher_cmd" == *"shogun-hot-reload-watch"* ]]
        [[ "$watcher_cmd" != *"ninja_monitor.sh"* ]]
        sleep 0.1
        touch -d "@$((start_mtime + 1))" "$script_path"
        for _ in $(seq 1 100); do
            [ -s "$capture" ] && break
            sleep 0.05
        done
        elapsed=$(( $(date +%s%3N) - started ))

        test -s "$capture"
        grep -q "generation=$generation" "$capture"
        awk -v elapsed="$elapsed" "BEGIN { exit !(elapsed < 20000) }"
        test -d "/proc/$$"
        printf "successor=1 old_generation_alive=1 elapsed_ms=%s\n" "$elapsed"
    '
    if [ "$status" -ne 0 ]; then
        printf 'HOT_RELOAD_FAILURE_OUTPUT_BEGIN\n%s\nHOT_RELOAD_FAILURE_OUTPUT_END\n' "$output" >&3
        log_path="$BATS_TEST_TMPDIR/hot-reload-watch/monitor.log"
        if [ -f "$log_path" ]; then
            printf 'HOT_RELOAD_FAILURE_LOG_BEGIN\n' >&3
            cat "$log_path" >&3
            printf 'HOT_RELOAD_FAILURE_LOG_END\n' >&3
        else
            printf 'HOT_RELOAD_FAILURE_LOG_MISSING path=%s\n' "$log_path" >&3
        fi
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == successor=1\ old_generation_alive=1\ elapsed_ms=* ]]
}

# test_necessity: owner/pid is one generation-fenced lease; three consecutive
# heartbeats must preserve the same live PID and stale generations must not
# rewrite either file.
@test "owner pid SSOT survives three heartbeats and fences stale writers" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
STATE_DIR="'"$BATS_TEST_TMPDIR"'/owner-ssot/state"
LOG="'"$BATS_TEST_TMPDIR"'/owner-ssot/monitor.log"
NINJA_MONITOR_OWNER_FILE="$STATE_DIR/ninja_monitor.owner"
NINJA_MONITOR_HEARTBEAT_STALE_SECONDS=5
mkdir -p "$STATE_DIR"
acquire_singleton_lock
read -r owner generation heartbeat < "$NINJA_MONITOR_OWNER_FILE"
test "$owner" = "$$"
test "$(cat "$STATE_DIR/ninja_monitor.pid")" = "$owner"
for cycle in 1 2 3; do
  sleep 1
  ninja_monitor_owner_heartbeat
  read -r owner_after generation_after heartbeat_after < "$NINJA_MONITOR_OWNER_FILE"
  test "$owner_after" = "$owner"
  test "$generation_after" = "$generation"
  test "$heartbeat_after" -gt "$heartbeat"
  test "$(cat "$STATE_DIR/ninja_monitor.pid")" = "$owner"
  heartbeat="$heartbeat_after"
done
before_owner=$(cat "$NINJA_MONITOR_OWNER_FILE")
before_pid=$(cat "$STATE_DIR/ninja_monitor.pid")
NINJA_MONITOR_GENERATION=stale-generation
export NINJA_MONITOR_GENERATION
if ninja_monitor_owner_heartbeat; then exit 41; fi
test "$(cat "$NINJA_MONITOR_OWNER_FILE")" = "$before_owner"
test "$(cat "$STATE_DIR/ninja_monitor.pid")" = "$before_pid"
printf "owner_pid=%s heartbeat_cycles=3 stale_rewrite=0\n" "$owner"
'
    [ "$status" -eq 0 ]
    [[ "$output" == "owner_pid="*" heartbeat_cycles=3 stale_rewrite=0" ]]
}

@test "owner heartbeat watcher keeps three live SSOT cycles independent of main loop" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
STATE_DIR="'"$BATS_TEST_TMPDIR"'/owner-heartbeat/state"
LOG="'"$BATS_TEST_TMPDIR"'/owner-heartbeat/monitor.log"
NINJA_MONITOR_OWNER_FILE="$STATE_DIR/ninja_monitor.owner"
NINJA_MONITOR_LIVENESS_OVERRIDE_PID="$$"
NINJA_MONITOR_OWNER_HEARTBEAT_POLL_SEC=0.1
mkdir -p "$STATE_DIR"
acquire_singleton_lock
read -r owner generation previous < "$NINJA_MONITOR_OWNER_FILE"
NINJA_MONITOR_OWNER_WATCH_OWNER_PID="$$"
NINJA_MONITOR_OWNER_WATCH_PARENT_PID="$$"
start_ninja_monitor_owner_heartbeat_watch
for cycle in 1 2 3; do
  sleep 1
  read -r owner_after generation_after heartbeat_after < "$NINJA_MONITOR_OWNER_FILE"
  test "$owner_after" = "$owner"
  test "$generation_after" = "$generation"
  test "$heartbeat_after" -gt "$previous"
  test "$(cat "$STATE_DIR/ninja_monitor.pid")" = "$owner"
  previous="$heartbeat_after"
done
printf "owner_pid=%s heartbeat_cycles=3 pid_match=1\n" "$owner"
'
    [ "$status" -eq 0 ]
    [[ "$output" == "owner_pid="*" heartbeat_cycles=3 pid_match=1" ]]
}

# test_necessity(cmd_karo_hotfix_ninja_monitor_live_generation_202608191233):
# check_gate_stall was the only business-judgment routine in the main loop
# without the ninja_monitor_business_owner_is_current() fence that
# check_idle_backlog_alert/check_undeployed_cmds/check_karo_pending_cmd already
# carry. A superseded (stale-owner) process therefore kept firing real
# GATE-AUTO-BLOCK/CLEAR notifications after a hot-reload successor took
# ownership (2026-08-19 12:31:28 cmd_reflux_insight_202608191219_saizo).
# regression_justification: reproduces the stale-owner incident directly
# against check_gate_stall; a stale generation must produce zero gate calls
# and zero notifications, while the current owner clears normally.
@test "check_gate_stall: stale generation performs zero business side effects and current generation clears" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        _NINJA_MONITOR_LIB_MODE=0

        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/queue/gates/cmd_stale_owner" "$SCRIPT_DIR/queue/tasks" \
            "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"
        now_ts=$(date -Iseconds)
        printf "timestamp: %s\nresult: LGTM\n" "$now_ts" > "$SCRIPT_DIR/queue/gates/cmd_stale_owner/review_gate.done"
        printf "task:\n  parent_cmd: cmd_stale_owner\n  status: in_progress\n" > "$SCRIPT_DIR/queue/tasks/active.yaml"
        : > "$SCRIPT_DIR/logs/gate_metrics.log"
        printf "%s\n" \
            "#!/usr/bin/env bash" \
            "printf \"%s\\n\" \"\$1\" >> \"$STATE_DIR/calls\"" \
            > "$SCRIPT_DIR/scripts/cmd_complete_gate.sh"
        chmod +x "$SCRIPT_DIR/scripts/cmd_complete_gate.sh"
        LOG="$STATE_DIR/monitor.log"
        NINJA_MONITOR_OWNER_FILE="$STATE_DIR/ninja_monitor.owner"
        send_inbox_message() { printf "%s|%s\n" "$1" "$3" >> "$STATE_DIR/messages"; }
        GATE_STALL_MAX_MIN=1440

        # Old (superseded) generation: owner record names a different live pid
        # and generation -> the fence must skip before any flock/gate call.
        printf "%s old-generation %s\n" "$$" "$EPOCHSECONDS" > "$NINJA_MONITOR_OWNER_FILE"
        NINJA_MONITOR_GENERATION=stale-generation-not-in-owner-file
        check_gate_stall
        old_calls=$(test -f "$STATE_DIR/calls" && wc -l < "$STATE_DIR/calls" || printf 0)
        old_fence=$(grep -c "SINGLETON-FENCE-SKIP: check_gate_stall" "$LOG")
        old_messages=$(test -f "$STATE_DIR/messages" && wc -l < "$STATE_DIR/messages" || printf 0)

        # Current generation: owner record now names this pid/generation ->
        # the fence must pass and the real gate call must execute exactly once.
        NINJA_MONITOR_GENERATION=current-generation
        printf "%s current-generation %s\n" "$$" "$EPOCHSECONDS" > "$NINJA_MONITOR_OWNER_FILE"
        check_gate_stall
        new_calls=$(wc -l < "$STATE_DIR/calls")

        test "$old_calls" -eq 0
        test "$old_fence" -eq 1
        test "$old_messages" -eq 0
        test "$new_calls" -eq 1
        grep -qx "cmd_stale_owner" "$STATE_DIR/calls"
        printf "old_calls=%s old_fence=%s old_messages=%s new_calls=%s\n" \
            "$old_calls" "$old_fence" "$old_messages" "$new_calls"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"old_calls=0 old_fence=1 old_messages=0 new_calls=1"* ]]
}

# test_necessity: the incident involved two live ninja_monitor.sh main loops
# (a pre-hot-reload process and its successor) both able to reach
# check_gate_stall for the same review_gate.done marker at the same time.
# Concurrent execution must still converge to exactly one gate judgment with
# zero false GATE-AUTO-BLOCK entries and zero stale-generation side effects.
@test "check_gate_stall: concurrent old and new generation converge to exactly one gate judgment" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        _NINJA_MONITOR_LIB_MODE=0

        SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$SCRIPT_DIR/queue/gates/cmd_concurrent_gen" "$SCRIPT_DIR/queue/tasks" \
            "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"
        now_ts=$(date -Iseconds)
        printf "timestamp: %s\nresult: LGTM\n" "$now_ts" > "$SCRIPT_DIR/queue/gates/cmd_concurrent_gen/review_gate.done"
        printf "task:\n  parent_cmd: cmd_concurrent_gen\n  status: in_progress\n" > "$SCRIPT_DIR/queue/tasks/active.yaml"
        : > "$SCRIPT_DIR/logs/gate_metrics.log"
        printf "%s\n" \
            "#!/usr/bin/env bash" \
            "flock \"$STATE_DIR/calls.lock\" printf \"%s\\n\" \"\$1\" >> \"$STATE_DIR/calls\"" \
            > "$SCRIPT_DIR/scripts/cmd_complete_gate.sh"
        chmod +x "$SCRIPT_DIR/scripts/cmd_complete_gate.sh"
        NINJA_MONITOR_OWNER_FILE="$STATE_DIR/ninja_monitor.owner"
        printf "%s current-generation %s\n" "$$" "$EPOCHSECONDS" > "$NINJA_MONITOR_OWNER_FILE"
        GATE_STALL_MAX_MIN=1440
        send_inbox_message() { printf "%s|%s\n" "$1" "$3" >> "$STATE_DIR/messages"; }

        (
          LOG="$STATE_DIR/old.log"
          NINJA_MONITOR_GENERATION=old-generation-not-in-owner-file
          check_gate_stall
        ) &
        old_pid=$!
        (
          LOG="$STATE_DIR/new.log"
          NINJA_MONITOR_GENERATION=current-generation
          check_gate_stall
        ) &
        new_pid=$!
        wait "$old_pid"
        wait "$new_pid"

        total_calls=$(test -f "$STATE_DIR/calls" && wc -l < "$STATE_DIR/calls" || printf 0)
        old_fence=$(grep -c "SINGLETON-FENCE-SKIP: check_gate_stall" "$STATE_DIR/old.log" 2>/dev/null || printf 0)
        false_blocks=0
        for f in "$STATE_DIR/old.log" "$STATE_DIR/new.log"; do
            [ -f "$f" ] || continue
            n=$(grep -c "GATE-AUTO-BLOCK" "$f" || printf 0)
            false_blocks=$((false_blocks + n))
        done
        old_messages=$(test -f "$STATE_DIR/messages" && wc -l < "$STATE_DIR/messages" || printf 0)

        test "$total_calls" -eq 1
        test "$old_fence" -eq 1
        test "$false_blocks" -eq 0
        test "$old_messages" -eq 0
        printf "total_calls=%s old_fence=%s false_blocks=%s old_messages=%s\n" \
            "$total_calls" "$old_fence" "$false_blocks" "$old_messages"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"total_calls=1 old_fence=1 false_blocks=0 old_messages=0"* ]]
}

@test "snapshot keeps task done while publishing runtime busy separately" {
    run bash -lc '
set -euo pipefail
src="'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
grep -q "TASK:\${status:-idle}|RUNTIME:\${runtime_state}" "$src"
! sed -n "/local runtime_state=/,/snapshot_status/p" "$src" | grep -q "status=\"in_progress\""
'
    [ "$status" -eq 0 ]
}

@test "background terminal classifier distinguishes active compute, residue, and no marker" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
STALL_CPU_SAMPLE_SEC=0
tmux() { case "$*" in *"#{pane_pid}"*) echo 100;; *"#{pane_tty}"*) echo /dev/pts/9;; *capture-pane*) echo "${PANE_CAPTURE:-Waited for background terminal}";; esac; }
sleep() { :; }
PS_CALL_FILE=$(mktemp)
ps() {
  local n=0; [ -s "$PS_CALL_FILE" ] && n=$(cat "$PS_CALL_FILE")
  if [ "$n" -eq 0 ]; then printf "%s\n" "$PS_FIXTURE"; else printf "%s\n" "$PS_FIXTURE_NEXT"; fi
  echo $((n + 1)) > "$PS_CALL_FILE"
}
check_case() {
  : > "$PS_CALL_FILE"
  PS_FIXTURE="$1" PS_FIXTURE_NEXT="$2"
  local rc
  if _pane_has_active_background_compute pane; then rc=0; else rc=$?; fi
  case "$rc" in 0) echo active;; 1) echo residue;; 2) echo none;; esac
}
check_case $'"'"'100 1 pts/9 S 00:00:00\n200 100 ? R 00:00:01'"'"' $'"'"'100 1 pts/9 S 00:00:00\n200 100 ? R 00:00:02'"'"'
check_case $'"'"'100 1 pts/9 S 00:00:00\n201 100 ? D 00:00:01'"'"' $'"'"'100 1 pts/9 S 00:00:00\n201 100 ? D 00:00:01'"'"'
check_case $'"'"'100 1 pts/9 S 00:00:00\n202 100 ? S 00:00:01'"'"' $'"'"'100 1 pts/9 S 00:00:00\n202 100 ? S 00:00:01'"'"'
check_case $'"'"'100 1 pts/9 S 00:00:00\n203 100 ? Z 00:00:01'"'"' $'"'"'100 1 pts/9 S 00:00:00\n203 100 ? Z 00:00:02'"'"'
check_case $'"'"'100 1 pts/9 S 00:00:00\n204 100 ? R 00:00:01'"'"' $'"'"'100 1 pts/9 S 00:00:00'"'"'
check_case $'"'"'100 1 pts/9 S 00:00:00\n300 1 pts/8 R 00:00:01'"'"' $'"'"'100 1 pts/9 S 00:00:00\n300 1 pts/8 R 00:00:02'"'"'
PANE_CAPTURE="idle prompt only"
check_case $'"'"'100 1 pts/9 S 00:00:00'"'"' $'"'"'100 1 pts/9 S 00:00:00'"'"'
'
    [ "$status" -eq 0 ]
    [ "$output" = $'active\nactive\nresidue\nresidue\nresidue\nresidue\nnone' ]
}

@test "stale background residue is corrected to idle for agent respawn path" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="'"$BATS_TEST_TMPDIR"'/stale-residue"
mkdir -p "$TMP_ROOT"
STATE_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
EPOCHSECONDS=1000
tmux() {
  case "$*" in
    *"#{@agent_state}"*) echo active;;
    *"#{@last_active}"*) echo 1;;
    *"set-option"*) echo "SET_OPTION $*" >> "$LOG";;
  esac
}
check_agent_busy() { return 1; }
_pane_has_active_background_compute() { return 1; }
log() { echo "$1" >> "$LOG"; }
if check_idle pane hanzo; then echo idle; else echo busy; fi
cat "$LOG"
test -f "$STATE_DIR/shogun_idle_hanzo"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"idle"* ]]
    [[ "$output" == *"HOOK-STALE-BACKGROUND-RESIDUE:"* ]]
    [[ "$output" == *"agent_respawn path"* ]]
    [[ "$output" == *"SET_OPTION set-option -p -t pane @agent_state idle"* ]]
}

@test "check_undeployed_cmds: pending+delegated_at 10分超でntfy送信し重複通知しない" {
    DELEGATED_AT=$(date -d "11 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
DELEGATED_AT="'"$DELEGATED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"

TEST_LOG="$(mktemp)"
TEST_NTFY="$(mktemp)"
export TEST_NTFY

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<EOF
commands:
  cmd_undeployed:
    status: pending
    timestamp: "2026-04-03T01:12:00"
    delegated_at: "\"$DELEGATED_AT\""
EOF

cat > "$SCRIPT_DIR/scripts/ntfy.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$1" >> "$TEST_NTFY"
EOF
chmod +x "$SCRIPT_DIR/scripts/ntfy.sh"

log() { echo "$1" >> "$TEST_LOG"; }
declare -A UNDEPLOYED_CMD_NOTIFIED

check_undeployed_cmds
check_undeployed_cmds

echo "NTFY_COUNT=$(wc -l < "$TEST_NTFY" | tr -d " ")"
cat "$TEST_NTFY"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NTFY_COUNT=1"* ]]
    [[ "$output" == *"未配備cmd: cmd_undeployed"* ]]
    [[ "$output" == *"UNDEPLOYED-CMD: cmd_undeployed"* ]]
}

@test "check_undeployed_cmds: 配備済み(status=in_progress)なら通知しない" {
    # GA-IA2(2026-08-04): 旧契約「delegated=配備済み」は誤前提(cmd_4228が
    # delegatedのままidle忍者4名で35分停滞しても無通知だった実証事故)。
    # 新契約: pending/delegatedとも未配備=通知対象。配備の証跡はin_progress遷移のみ。
    DELEGATED_AT=$(date -d "20 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
DELEGATED_AT="'"$DELEGATED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"

TEST_LOG="$(mktemp)"
TEST_NTFY="$(mktemp)"
export TEST_NTFY

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<EOF
commands:
  cmd_deployed:
    status: in_progress
    timestamp: "2026-04-03T01:12:00"
    delegated_at: "\"$DELEGATED_AT\""
EOF

cat > "$SCRIPT_DIR/scripts/ntfy.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$1" >> "$TEST_NTFY"
EOF
chmod +x "$SCRIPT_DIR/scripts/ntfy.sh"

log() { echo "$1" >> "$TEST_LOG"; }
declare -A UNDEPLOYED_CMD_NOTIFIED

check_undeployed_cmds

echo "NTFY_COUNT=$(wc -l < "$TEST_NTFY" | tr -d " ")"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NTFY_COUNT=0"* ]]
}

@test "check_undeployed_cmds: task親一致の配備済み6状態を抑止し真の未配備3条件を通知する" {
    DELEGATED_AT=$(date -d "20 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
DELEGATED_AT="'"$DELEGATED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/scripts" "$TMP_ROOT/logs"
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
TEST_NTFY="$TMP_ROOT/ntfy.log"; : > "$TEST_NTFY"
export TEST_NTFY

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<EOF
commands:
  cmd_matrix:
    status: pending
    timestamp: "2026-04-03T01:12:00"
    delegated_at: "$DELEGATED_AT"
EOF
cat > "$SCRIPT_DIR/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "${1:-}" >> "$TEST_NTFY"
EOF
chmod +x "$SCRIPT_DIR/scripts/ntfy.sh"
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

log() { echo "$1" >> "$LOG"; }
cycle=0
active_statuses=(assigned acknowledged in_progress done completed failed)
for task_status in "${active_statuses[@]}"; do
    cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  parent_cmd: cmd_matrix
  status: $task_status
EOF
    unset UNDEPLOYED_CMD_NOTIFIED
    declare -A UNDEPLOYED_CMD_NOTIFIED
    cycle=$((cycle + 1))
    check_undeployed_cmds
done
active_count=$(wc -l < "$TEST_NTFY" | tr -d " ")

# 親不一致: taskは存在するが、対象cmdのexact parent_cmdではない。
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  parent_cmd: cmd_other
  status: acknowledged
EOF
unset UNDEPLOYED_CMD_NOTIFIED; declare -A UNDEPLOYED_CMD_NOTIFIED
cycle=$((cycle + 1)); check_undeployed_cmds

# idle: exact parent_cmdでも配備済みstatus集合外。
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  parent_cmd: cmd_matrix
  status: idle
EOF
unset UNDEPLOYED_CMD_NOTIFIED; declare -A UNDEPLOYED_CMD_NOTIFIED
cycle=$((cycle + 1)); check_undeployed_cmds

# task不在: taskファイルを退避して照合対象から外す。
mv "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" "$SCRIPT_DIR/queue/tasks/kagemaru.yaml.absent"
unset UNDEPLOYED_CMD_NOTIFIED; declare -A UNDEPLOYED_CMD_NOTIFIED
cycle=$((cycle + 1)); check_undeployed_cmds

echo "ACTIVE_FP_NTFY=$active_count"
echo "TRUE_UNDEPLOYED_NTFY=$(wc -l < "$TEST_NTFY" | tr -d " ")"
cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE_FP_NTFY=0"* ]]
    [[ "$output" == *"TRUE_UNDEPLOYED_NTFY=3"* ]]
}

# test_necessity: exact parent_cmdのterminal FAIL reportは配備済み終端証跡として
# undeployed/cmd_pending/idle-backlogの全経路を閉じ、真の未配備cmdだけを3経路で通知する。
@test "terminal FAIL report is deployment evidence across undeployed pending and idle backlog" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

run_case() {
    local case_name="$1" fixture="$2" root="$NINJA_MONITOR_TEST_ROOT/$1"
    local delegated_at
    delegated_at=$(date -d "20 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    SCRIPT_DIR="$root"; STATE_DIR="$root/state"; LOG="$root/monitor.log"
    mkdir -p "$root/queue/tasks" "$root/queue/reports" "$root/queue/gates/cmd_case" \
        "$root/scripts" "$root/logs" "$STATE_DIR"
    printf "commands:\n  cmd_case:\n    status: pending\n    timestamp: \"2026-08-17T19:00:00\"\n    delegated_at: \"%s\"\n" "$delegated_at" > "$root/queue/shogun_to_karo.yaml"
    printf "messages: []\n" > "$root/queue/inbox.yaml"
    case "$fixture" in
        pass)
            printf "status: completed\nverdict: PASS\nparent_cmd: cmd_case\ntask_id: cmd_case_full\n" > "$root/queue/reports/kagemaru_report_cmd_case.yaml"
            : > "$root/queue/gates/cmd_case/archive.done"
            ;;
        active)
            printf "task:\n  parent_cmd: cmd_case\n  status: in_progress\n  task_id: cmd_case_full\n" > "$root/queue/tasks/kagemaru.yaml"
            ;;
        failed)
            printf "status: failed\nverdict: FAIL\nparent_cmd: cmd_case\ntask_id: cmd_case_full\n" > "$root/queue/reports/kagemaru_report_cmd_case.yaml"
            ;;
        stale_owner) ;;
        undeployed) ;;
        *) return 1 ;;
    esac

    printf "#!/usr/bin/env bash\nprintf \"%s\\n\" \"\${1:-}\" >> \"\$TEST_NTFY\"\n" > "$root/scripts/ntfy.sh"
    chmod +x "$root/scripts/ntfy.sh"
    printf "#!/usr/bin/env bash\nprintf \"%s|%s|%s\\n\" \"\$1\" \"\$3\" \"\$2\" >> \"\$TEST_INBOX\"\n" > "$root/scripts/inbox_write.sh"
    chmod +x "$root/scripts/inbox_write.sh"

    TEST_NTFY="$root/ntfy.log"; TEST_INBOX="$root/inbox.log"
    : > "$TEST_NTFY"; : > "$TEST_INBOX"
    TEST_DELEGATED_AT="$delegated_at"
    export TEST_NTFY TEST_INBOX TEST_DELEGATED_AT
    NINJA_NAMES=(n1); declare -gA PANE_TARGETS=([n1]=pane-n1)
    KARO_PANE=karo-pane
    check_idle() { return 0; }
    ninja_monitor_business_owner_is_current() { [ "$fixture" != stale_owner ]; }
    notify_karo_durable() { printf "%s|%s\n" "$1" "$3" >> "$TEST_INBOX"; return 0; }
    list_pending_cmds_cached() { printf "cmd_case|2026-08-17T19:00:00|%s||\n" "$TEST_DELEGATED_AT"; }
    log() { printf "%s\n" "$1" >> "$LOG"; }
    declare -gA UNDEPLOYED_CMD_NOTIFIED=() PREV_PENDING_SET=()

    check_undeployed_cmds
    check_karo_pending_cmd
    IDLE_BACKLOG_ALERT_NOW=1000; check_idle_backlog_alert
    IDLE_BACKLOG_ALERT_NOW=1180; check_idle_backlog_alert
    IDLE_BACKLOG_ALERT_NOW=1181; check_idle_backlog_alert

    local ntfy_count cmd_pending_count pending_work_count
    ntfy_count=$(wc -l < "$TEST_NTFY" | tr -d " ")
    cmd_pending_count=$(grep -c "PENDING-CMD-NEW" "$LOG" || true)
    pending_work_count=$(grep -c "^pending_work|" "$TEST_INBOX" || true)
    printf "CASE=%s fixture=%s undeployed=%s cmd_pending=%s pending_work=%s\n" \
        "$case_name" "$fixture" "$ntfy_count" "$cmd_pending_count" "$pending_work_count"
}

run_case pass_case pass
run_case active_case active
run_case failed_case failed
run_case stale_owner_case stale_owner
run_case true_undeployed_case undeployed
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CASE=pass_case fixture=pass undeployed=0 cmd_pending=0 pending_work=0"* ]]
    [[ "$output" == *"CASE=active_case fixture=active undeployed=0 cmd_pending=0 pending_work=0"* ]]
    [[ "$output" == *"CASE=failed_case fixture=failed undeployed=0 cmd_pending=0 pending_work=0"* ]]
    [[ "$output" == *"CASE=stale_owner_case fixture=stale_owner undeployed=0 cmd_pending=0 pending_work=0"* ]]
    [[ "$output" == *"CASE=true_undeployed_case fixture=undeployed undeployed=1 cmd_pending=1 pending_work=1"* ]]
}

@test "check_karo_pending_cmd: 新規pendingが猶予内ならcmd_pending通知しない" {
    RECENT_TS=$(date -d "10 seconds ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
RECENT_TS="'"$RECENT_TS"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
KARO_PENDING_CMD_GRACE_SEC=30
KARO_PANE="karo-pane"
export SCRIPT_DIR
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts"

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<EOF
commands:
  cmd_recent:
    status: pending
    timestamp: "$RECENT_TS"
EOF

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
declare -A PREV_PENDING_SET STALE_CMD_NOTIFIED

check_karo_pending_cmd

test ! -f "$SCRIPT_DIR/inbox.log"
grep -q "PENDING-CMD-GRACE: cmd_recent" "$LOG"
'
    [ "$status" -eq 0 ]
}

@test "check_karo_pending_cmd: 猶予後もpendingならcmd_pending通知する" {
    OLD_TS=$(date -d "45 seconds ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
OLD_TS="'"$OLD_TS"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
KARO_PENDING_CMD_GRACE_SEC=30
KARO_PANE="karo-pane"
export SCRIPT_DIR
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts"

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<EOF
commands:
  cmd_old:
    status: pending
    timestamp: "$OLD_TS"
EOF

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
declare -A PREV_PENDING_SET STALE_CMD_NOTIFIED

check_karo_pending_cmd

grep -q "karo|cmd_pending|cmd_pending cmd_old" "$SCRIPT_DIR/inbox.log"
grep -q "PENDING-CMD-NEW: cmd_old" "$LOG"
'
    [ "$status" -eq 0 ]
}

# test_necessity: pending正本と配備済みtaskが並存しても家老へ偽の配備漏れ通知を送らない不変量
# overlaps_existing: true
# regression_justification: 既存猶予テストは時刻だけを覆い、exact parent_cmdのacknowledged/in_progress taskを照合しない欠落がcmd_4255/cmd_4256で同時発火したため
@test "check_karo_pending_cmd: exact parent taskが配備済みなら通知しない" {
    OLD_TS=$(date -d "45 seconds ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
OLD_TS="'"$OLD_TS"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
KARO_PENDING_CMD_GRACE_SEC=30
KARO_PANE="karo-pane"
export SCRIPT_DIR
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts"

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<EOF
commands:
  cmd_deployed:
    status: pending
    timestamp: "$OLD_TS"
EOF
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  parent_cmd: cmd_deployed
  status: acknowledged
EOF
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
declare -A PREV_PENDING_SET STALE_CMD_NOTIFIED

check_karo_pending_cmd

test ! -f "$SCRIPT_DIR/inbox.log"
grep -q "PENDING-CMD-DEPLOYED: cmd_deployed task_status=acknowledged" "$LOG"
'
    [ "$status" -eq 0 ]
}

@test "speed training auto-pause when retrospective recurrence rate exceeds 10 percent" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
SPEED_TRAINING_LEDGER="$TMP_ROOT/logs/script_speed_training_ledger.yaml"
mkdir -p "$SCRIPT_DIR/logs" "$SCRIPT_DIR/tools"
cp "$PROJECT_ROOT/tools/bash_speed_training.sh" "$SCRIPT_DIR/tools/bash_speed_training.sh"
cat > "$SPEED_TRAINING_LEDGER" <<EOF
global_status: running
entries: []
EOF
cat > "$SCRIPT_DIR/logs/cmd_design_quality.yaml" <<EOF
- cmd_id: cmd_prev_1
  gate_result: WARN
  timestamp: "2026-06-01T00:00:00"
  notes: "alpha_issue"
- cmd_id: cmd_prev_2
  gate_result: WARN
  timestamp: "2026-06-01T00:01:00"
  notes: "beta_issue"
EOF
for i in $(seq 1 50); do
    if [ "$i" -eq 50 ]; then note="alpha_issue"; else note="recent_unique_$i"; fi
    cat >> "$SCRIPT_DIR/logs/cmd_design_quality.yaml" <<EOF
- cmd_id: cmd_recent_$i
  gate_result: WARN
  timestamp: "2026-06-02T00:$i:00"
  notes: "$note"
EOF
done

LOG="$TMP_ROOT/monitor.log"
log() { echo "$1" >> "$LOG"; }

_pause_speed_training_if_recurrence_high
grep -q "global_status: paused" "$SPEED_TRAINING_LEDGER"
grep -q "SPEED-TRAINING-AUTO-PAUSE: recurrence_rate=50%" "$LOG"
cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SPEED-TRAINING-AUTO-PAUSE"* ]]
}

@test "speed training auto-deploy never calls helper for in_progress or failed task" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT/idle-guard"; mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/tools"
SCRIPT_DIR="$TMP_ROOT"
SPEED_TRAINING_LEDGER="$TMP_ROOT/ledger.yaml"
printf "#!/usr/bin/env bash\\necho called >> %s/helper.calls\\n" "$TMP_ROOT" > "$TMP_ROOT/tools/bash_speed_training.sh"
chmod +x "$TMP_ROOT/tools/bash_speed_training.sh"
log() { :; }
yaml_field_get() { awk "/^[[:space:]]*status:/ {print \\$2; exit}" "$1"; }
for state in in_progress failed; do
  printf "task:\\n  status: %s\\n" "$state" > "$TMP_ROOT/queue/tasks/hayate.yaml"
  ! _handle_speed_training_auto_deploy hayate 0
done
[ ! -e "$TMP_ROOT/helper.calls" ]
'
    [ "$status" -eq 0 ]
}

@test "check_stall: same ninja x task re-notifies after 5-minute debounce" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: assigned
  subtask_id: subtask_500_impl_stall_enforcement
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "assigned" ;;
        subtask_id) echo "subtask_500_impl_stall_enforcement" ;;
        task_id) echo "" ;;
        progress_updated_at) echo "" ;;
        *) echo "${3:-}" ;;
    esac
}
cli_profile_get() { echo ""; }

PANE_TARGETS[kagemaru]="shogun:2.5"
now=$(date +%s)
stall_key="kagemaru:subtask_500_impl_stall_enforcement"

STALL_FIRST_SEEN[kagemaru]=$((now - 16 * 60))
STALL_NOTIFIED["$stall_key"]=$((now - 120))
check_stall kagemaru

STALL_FIRST_SEEN[kagemaru]=$((now - 16 * 60))
STALL_NOTIFIED["$stall_key"]=$((now - 301))
check_stall kagemaru

echo "ALERT_COUNT=$(grep -c "|stall_alert|" "$TEST_MESSAGES" || true)"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT_COUNT=1"* ]]
}

@test "check_stall: deployed_at within 5 minutes bypasses stall detection" {
    DEPLOYED_AT=$(date -d "2 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
DEPLOYED_AT="'"$DEPLOYED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  status: assigned
  subtask_id: subtask_2640_startup_grace
  deployed_at: "$DEPLOYED_AT"
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "assigned" ;;
        subtask_id) echo "subtask_2640_startup_grace" ;;
        task_id) echo "" ;;
        _ac_task_id) echo "" ;;
        deployed_at) echo "$DEPLOYED_AT" ;;
        progress_updated_at) echo "" ;;
        *) echo "${3:-}" ;;
    esac
}
cli_profile_get() { echo ""; }

PANE_TARGETS[kagemaru]="shogun:2.5"
now=$(date +%s)
STALL_FIRST_SEEN[kagemaru]=$((now - 16 * 60))
check_stall kagemaru

echo "ALERT_COUNT=$(grep -c "|stall_alert|" "$TEST_MESSAGES" || true)"
echo "FIRST_SEEN=${STALL_FIRST_SEEN[kagemaru]:-missing}"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT_COUNT=0"* ]]
    [[ "$output" == *"FIRST_SEEN=missing"* ]]
    [[ "$output" == *"STALL-DEPLOY-GRACE: kagemaru deployed"* ]]
    [[ "$output" == *"within grace period"* ]]
}

@test "check_stall: cmd_id fallback prevents STALL-GHOST for karo_direct task" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: assigned
  cmd_id: cmd_2939
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
cli_profile_get() { echo ""; }

PANE_TARGETS[kagemaru]="shogun:2.5"
now=$(date +%s)
STALL_FIRST_SEEN[kagemaru]=$((now - 16 * 60))
check_stall kagemaru

echo "ALERT_COUNT=$(grep -c "|stall_alert|" "$TEST_MESSAGES" || true)"
cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT_COUNT=1"* ]]
    [[ "$output" == *"kagemaruがcmd_2939"* ]]
    [[ "$output" != *"STALL-GHOST"* ]]
}

@test "check_stall: in_progress stall sends task_assigned recovery and log" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  subtask_id: subtask_500_impl_stall_enforcement
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "in_progress" ;;
        subtask_id) echo "subtask_500_impl_stall_enforcement" ;;
        task_id) echo "" ;;
        progress_updated_at) echo "" ;;
        *) echo "${3:-}" ;;
    esac
}

cli_profile_get() {
    case "$2" in
        in_progress_stall_min) echo "1" ;;
        *) echo "" ;;
    esac
}

PANE_TARGETS[kagemaru]="shogun:2.5"
STALL_THRESHOLD_MIN=1
now=$(date +%s)
STALL_FIRST_SEEN[kagemaru]=$((now - 2 * 60))
check_stall kagemaru

cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo|stall_alert|"* ]]
    [[ "$output" == *"kagemaru|task_assigned|"* ]]
    [[ "$output" == *"STALL-RECOVERY-SEND:"* ]]
}

# test_necessity: assigned/acknowledged初回idleを即時復旧し、同一taskの反復・busy復帰後を重複通知しない不変量を守る
@test "check_stall: assigned and acknowledged initial idle recover once per task" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

SCRIPT_DIR="'"$BATS_TEST_TMPDIR"'/initial-idle-recovery"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
TEST_LOG="$SCRIPT_DIR/logs/monitor.log"
TEST_MESSAGES="$SCRIPT_DIR/logs/messages.log"
log() { printf "%s\n" "$1" >> "$TEST_LOG"; }
send_inbox_message() { printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$TEST_MESSAGES"; }
check_idle() { [ "${PANE_IDLE:-0}" = 0 ]; }
_pane_has_active_background_compute() { return 1; }
_pane_has_confirmation_prompt() { return 1; }
PANE_TARGETS[kagemaru]="shogun:2.4"
STALL_THRESHOLD_MIN=999
declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT

for task_status in assigned acknowledged; do
    task_id="cmd_initial_${task_status}"
    cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  status: $task_status
  task_id: $task_id
  parent_cmd: cmd_initial_idle
EOF
    STALL_FIRST_SEEN[kagemaru]=$EPOCHSECONDS
    PANE_IDLE=0
    check_stall kagemaru
    check_stall kagemaru
    PANE_IDLE=1
    check_stall kagemaru
    STALL_FIRST_SEEN[kagemaru]=$EPOCHSECONDS
    PANE_IDLE=0
    check_stall kagemaru
done

test "$(grep -c "|task_assigned|" "$TEST_MESSAGES")" -eq 2
test "$(grep -c "STALL-INITIAL-IDLE-RECOVERY: .* sent=1" "$TEST_LOG")" -eq 2
test "$(grep -c "STALL-INITIAL-IDLE-RECOVERY-SKIP: .* duplicate=1" "$TEST_LOG")" -ge 4
printf "initial_idle_recovery=2 duplicate=0 busy_recovery_duplicate=0 false_positive=0\n"
'
    [ "$status" -eq 0 ]
    [ "$output" = "initial_idle_recovery=2 duplicate=0 busy_recovery_duplicate=0 false_positive=0" ]
}

# test_necessity: acknowledged_atから5分経過してもbusy paneが一次事実なら
# statusをin_progressへ自動整合し、旧状態の将軍WARNを抑止する不変量を守る。
# regression_justification: 32348fc1bでbusy autoheal契約が導入され、e46e06016で
# idle観測2周期デバウンスが追加されたため、旧SHOGUN_ALERTS=1期待を現行契約へ更新する。
@test "check_stall: acknowledged busy status autoheals without shogun warning" {
    ACK_AT=$(date -d "6 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    DEPLOYED_AT=$(date -d "20 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
ACK_AT="'"$ACK_AT"'"
DEPLOYED_AT="'"$DEPLOYED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

SCRIPT_DIR="'"$BATS_TEST_TMPDIR"'/ack-to-progress-warn"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
TEST_LOG="$SCRIPT_DIR/logs/monitor.log"
TEST_MESSAGES="$SCRIPT_DIR/logs/messages.log"
: > "$TEST_LOG"
: > "$TEST_MESSAGES"
log() { printf "%s\n" "$1" >> "$TEST_LOG"; }
send_inbox_message() { printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$TEST_MESSAGES"; }
check_idle() { return 1; }
_pane_has_active_background_compute() { return 1; }
_pane_has_confirmation_prompt() { return 1; }
PANE_TARGETS[kagemaru]="shogun:2.4"
declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT ACK_STALL_WARNED

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  status: acknowledged
  task_id: cmd_ack_stall_001
  deployed_at: "$DEPLOYED_AT"
  acknowledged_at: "$ACK_AT"
EOF

check_stall kagemaru
check_stall kagemaru

echo "SHOGUN_ALERTS=$(grep -c "^shogun|stall_alert|" "$TEST_MESSAGES" || true)"
grep "^shogun|stall_alert|" "$TEST_MESSAGES" || true
echo "NOTIFIED_LOG=$(grep -c "ACK-TO-PROGRESS-STALL-NOTIFIED" "$TEST_LOG" || true)"
echo "DEDUPE_LOG=$(grep -c "ACK-TO-PROGRESS-STALL-DEDUPE" "$TEST_LOG" || true)"
echo "AUTOHEAL_LOG=$(grep -c "ACK-TO-PROGRESS-AUTOHEAL: kagemaru task=cmd_ack_stall_001" "$TEST_LOG" || true)"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHOGUN_ALERTS=0"* ]]
    [[ "$output" == *"NOTIFIED_LOG=0"* ]]
    [[ "$output" == *"DEDUPE_LOG=0"* ]]
    [[ "$output" == *"AUTOHEAL_LOG=1"* ]]
}

# test_necessity: 5分未満のacknowledged、およびin_progress遷移後はWARNを送らず
# dedupeフラグも解放される不変量を守る（誤検知/リーク防止）。
@test "check_stall: ack-to-progress warn stays silent before threshold and clears after in_progress transition" {
    ACK_AT=$(date -d "2 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    DEPLOYED_AT=$(date -d "20 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    NOW_TS=$(date "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
ACK_AT="'"$ACK_AT"'"
DEPLOYED_AT="'"$DEPLOYED_AT"'"
NOW_TS="'"$NOW_TS"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

SCRIPT_DIR="'"$BATS_TEST_TMPDIR"'/ack-to-progress-grace"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
TEST_LOG="$SCRIPT_DIR/logs/monitor.log"
TEST_MESSAGES="$SCRIPT_DIR/logs/messages.log"
: > "$TEST_LOG"
: > "$TEST_MESSAGES"
log() { printf "%s\n" "$1" >> "$TEST_LOG"; }
send_inbox_message() { printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$TEST_MESSAGES"; }
check_idle() { return 1; }
_pane_has_active_background_compute() { return 1; }
_pane_has_confirmation_prompt() { return 1; }
PANE_TARGETS[kagemaru]="shogun:2.4"
declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT ACK_STALL_WARNED

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  status: acknowledged
  task_id: cmd_ack_stall_002
  deployed_at: "$DEPLOYED_AT"
  acknowledged_at: "$ACK_AT"
EOF
check_stall kagemaru
echo "PRE_TRANSITION_ALERTS=$(grep -c "^shogun|stall_alert|" "$TEST_MESSAGES" || true)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<EOF
task:
  status: in_progress
  task_id: cmd_ack_stall_002
  deployed_at: "$DEPLOYED_AT"
  acknowledged_at: "$ACK_AT"
  progress_updated_at: "$NOW_TS"
EOF
check_stall kagemaru
echo "WARN_KEY_AFTER=${ACK_STALL_WARNED[kagemaru:cmd_ack_stall_002]:-unset}"
echo "POST_TRANSITION_ALERTS=$(grep -c "^shogun|stall_alert|" "$TEST_MESSAGES" || true)"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRE_TRANSITION_ALERTS=0"* ]]
    [[ "$output" == *"WARN_KEY_AFTER=unset"* ]]
    [[ "$output" == *"POST_TRANSITION_ALERTS=0"* ]]
}

# test_necessity: confirmation prompt中のnudgeは選択肢入力になり得るため送出を禁止する
@test "check_stall: confirmation prompt suppresses in_progress recovery nudge" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

SCRIPT_DIR="'"$BATS_TEST_TMPDIR"'/confirmation-prompt"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  task_id: cmd_4213_full
EOF

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT
TEST_LOG="$SCRIPT_DIR/logs/monitor.log"
TEST_MESSAGES="$SCRIPT_DIR/logs/messages.log"
log() { printf "%s\n" "$1" >> "$TEST_LOG"; }
send_inbox_message() { printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
tmux() {
  case "$*" in
    *capture-pane*) printf "Do you want to proceed?\n1. Yes\n2. No\n" ;;
    *"#{pane_dead}"*) printf "0\n" ;;
  esac
}
PANE_TARGETS[kagemaru]="shogun:2.4"
STALL_FIRST_SEEN[kagemaru]=$((EPOCHSECONDS - 30 * 60))
check_stall kagemaru
test ! -s "$TEST_MESSAGES"
grep -q "STALL-CONFIRMATION-PROMPT-SKIP: kagemaru task=cmd_4213_full pane=shogun:2.4 nudge=0" "$TEST_LOG"
printf "messages=0 confirmation_skip=1\n"
'
    [ "$status" -eq 0 ]
    [ "$output" = "messages=0 confirmation_skip=1" ]
}

# test_necessity: fresh progress timestampとprofile 20分の二重猶予で16分idleを見逃さない
@test "check_stall: in_progress runtime idle uses common threshold despite fresh progress and profile" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

SCRIPT_DIR="'"$BATS_TEST_TMPDIR"'/runtime-idle-threshold"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
progress_at=$(date -d "16 minutes ago" -Iseconds)
cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<EOF
task:
  status: in_progress
  task_id: cmd_4211_full
  progress_updated_at: "$progress_at"
EOF

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT
TEST_LOG="$SCRIPT_DIR/logs/monitor.log"
TEST_MESSAGES="$SCRIPT_DIR/logs/messages.log"
log() { printf "%s\n" "$1" >> "$TEST_LOG"; }
send_inbox_message() { printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
_pane_has_confirmation_prompt() { return 1; }
cli_profile_get() { [ "$2" = in_progress_stall_min ] && printf "20\n" || true; }
PANE_TARGETS[saizo]="shogun:2.6"
STALL_THRESHOLD_MIN=10
STALL_FIRST_SEEN[saizo]=$((EPOCHSECONDS - 11 * 60))
check_stall saizo
grep -q "karo|stall_alert|" "$TEST_MESSAGES"
grep -q "saizo|task_assigned|" "$TEST_MESSAGES"
grep -q "STALL-DETECTED: saizo stalled on cmd_4211_full for 11min" "$TEST_LOG"
printf "elapsed=11 threshold=10 profile=20 alert=1 nudge=1\n"
'
    [ "$status" -eq 0 ]
    [ "$output" = "elapsed=11 threshold=10 profile=20 alert=1 nudge=1" ]
}

# test_necessity: fresh progress内の明示BLOCKER/STOPは同cycleに家老へ通知され同一理由だけdurable dedupeされる
@test "check_stall: explicit stop bypasses freshness, dedupes across restart, and reason change re-notifies" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

SCRIPT_DIR="'"$BATS_TEST_TMPDIR"'/explicit-stop"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
LOG="$SCRIPT_DIR/logs/ninja_monitor.log"
TEST_MESSAGES="$SCRIPT_DIR/logs/messages.log"
cat > "$SCRIPT_DIR/queue/tasks/kotaro.yaml" <<EOF
task:
  status: in_progress
  task_id: task_explicit_stop_001
  progress_updated_at: "$(date -Iseconds)"
  progress: |
    AC1 PASS
    BLOCKER: fourth path authority required
EOF

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT
log() { printf "%s\n" "$1" >> "$LOG"; }
send_inbox_message() { printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }

check_stall kotaro
check_stall kotaro
first=$(wc -l < "$TEST_MESSAGES")

# restart相当: process-local stateを全消去してもtask YAML fenceが残る。
unset STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT
declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT
check_stall kotaro
after_restart=$(wc -l < "$TEST_MESSAGES")

yaml_field_set "$SCRIPT_DIR/queue/tasks/kotaro.yaml" task progress "STOP: dependency evidence missing"
check_stall kotaro
after_change=$(wc -l < "$TEST_MESSAGES")
printf "first=%s after_restart=%s after_change=%s\n" "$first" "$after_restart" "$after_change"
cat "$TEST_MESSAGES"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"first=1 after_restart=1 after_change=2"* ]]
    [[ "$output" == *"karo|stall_alert|【TASK-STOP】worker=kotaro task=task_explicit_stop_001 reason=BLOCKER: fourth path authority required path="* ]]
    [[ "$output" == *"reason=STOP: dependency evidence missing"* ]]
}

# test_necessity: stop通知のdelivery失敗はdedupeせず可視ログを残し次cycleで再送する
@test "check_stall: explicit stop delivery failure stays visible and retries" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="'"$BATS_TEST_TMPDIR"'/explicit-stop-retry"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
LOG="$SCRIPT_DIR/logs/ninja_monitor.log"
TEST_MESSAGES="$SCRIPT_DIR/logs/messages.log"
cat > "$SCRIPT_DIR/queue/tasks/hanzo.yaml" <<EOF
task:
  status: in_progress
  task_id: task_explicit_stop_retry
  blocked_reason: external evidence unavailable
  progress_updated_at: "$(date -Iseconds)"
EOF
declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT
log() { printf "%s\n" "$1" >> "$LOG"; }
attempt=0
send_inbox_message() {
  attempt=$((attempt + 1))
  if [ "$attempt" -eq 1 ]; then return 1; fi
  printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$TEST_MESSAGES"
}
check_stall hanzo
test -z "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/hanzo.yaml" silent_stop_notified_fingerprint "")"
check_stall hanzo
printf "attempts=%s delivered=%s\n" "$attempt" "$(wc -l < "$TEST_MESSAGES")"
grep "SILENT-STOP-NOTIFY-BLOCK" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"attempts=2 delivered=1"* ]]
    [[ "$output" == *"SILENT-STOP-NOTIFY-BLOCK: hanzo task=task_explicit_stop_retry"* ]]
}

@test "check_stall: intentional pause with reason and blocking cmd suppresses false stall" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  subtask_id: cmd_3827_full
  stall_detection_paused: true
  pause_reason: production DB exclusive operation
  paused_by_cmd: cmd_3832
  progress: "BLOCKER: intentionally serialized behind cmd_3832"
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
PANE_TARGETS[saizo]="shogun:2.6"
now=$(date +%s)
STALL_FIRST_SEEN[saizo]=$((now - 60 * 60))
STALL_NOTIFIED[saizo:cmd_3827_full]=$((now - 60 * 60))
STALL_COUNT[saizo:cmd_3827_full]=2

check_stall saizo

echo "MESSAGE_COUNT=$(wc -l < "$TEST_MESSAGES" | tr -d " ")"
echo "FIRST_SEEN=${STALL_FIRST_SEEN[saizo]-cleared}"
echo "NOTIFIED=${STALL_NOTIFIED[saizo:cmd_3827_full]-cleared}"
echo "COUNT=${STALL_COUNT[saizo:cmd_3827_full]-cleared}"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MESSAGE_COUNT=0"* ]]
    [[ "$output" == *"FIRST_SEEN=cleared"* ]]
    [[ "$output" == *"NOTIFIED=cleared"* ]]
    [[ "$output" == *"COUNT=cleared"* ]]
    [[ "$output" == *"STALL-PAUSED: saizo task=cmd_3827_full blocked_by=cmd_3832"* ]]
}

@test "check_stall: pause flag without contract metadata remains monitored" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  subtask_id: cmd_3827_full
  stall_detection_paused: true
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
cli_profile_get() { echo "1"; }
PANE_TARGETS[saizo]="shogun:2.6"
STALL_THRESHOLD_MIN=1
now=$(date +%s)
STALL_FIRST_SEEN[saizo]=$((now - 2 * 60))

check_stall saizo

cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo|stall_alert|"* ]]
    [[ "$output" == *"STALL-PAUSE-INVALID:"* ]]
    [[ "$output" == *"STALL-DETECTED:"* ]]
}

@test "check_stall: active idle task evaluates non-done report and re-notifies once" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"
LOG="$TEST_LOG"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  task_id: cmd_3751_full
  parent_cmd: cmd_3751
EOF

cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_3751.yaml" <<'"'"'EOF'"'"'
worker_id: kagemaru
task_id: cmd_3751_full
parent_cmd: cmd_3751
status: pending
verdict: ""
EOF

cat > "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" <<'"'"'EOF'"'"'
#!/bin/bash
echo "FAIL forced active report gate"
exit 1
EOF
chmod +x "$SCRIPT_DIR/scripts/gates/gate_report_format.sh"

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
cli_profile_get() {
    case "$2" in
        in_progress_stall_min) echo "1" ;;
        *) echo "" ;;
    esac
}

PANE_TARGETS[kagemaru]="shogun:2.5"
STALL_THRESHOLD_MIN=1
now=$(date +%s)
STALL_FIRST_SEEN[kagemaru]=$((now - 2 * 60))
check_stall kagemaru
STALL_FIRST_SEEN[kagemaru]=$((now - 2 * 60))
check_stall kagemaru

echo "REPORT_FIX_COUNT=$(grep -F -c "kagemaru|report_format_fix|" "$TEST_MESSAGES" || true)"
grep -q "ACTIVE-IDLE-REPORT-EVAL: kagemaru task=cmd_3751_full status=in_progress report=kagemaru_report_cmd_3751.yaml result=FAIL" "$TEST_LOG"
grep -q "ACTIVE-IDLE-REPORT-RENOTIFY: kagemaru task=cmd_3751_full" "$TEST_LOG"
grep -q "ACTIVE-IDLE-REPORT-RENOTIFY-SKIP: kagemaru task=cmd_3751_full duplicate" "$TEST_LOG"
cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"REPORT_FIX_COUNT=1"* ]]
    [[ "$output" == *"FAIL forced active report gate"* ]]
}

@test "check_stall: active idle task re-notifies once for uncommitted files" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/logs"
git -C "$SCRIPT_DIR" init -q
git -C "$SCRIPT_DIR" config user.email test@example.invalid
git -C "$SCRIPT_DIR" config user.name test
touch "$SCRIPT_DIR/base.txt"
git -C "$SCRIPT_DIR" add base.txt
git -C "$SCRIPT_DIR" commit -q -m init
printf "changed\n" > "$SCRIPT_DIR/base.txt"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS ACTIVE_IDLE_RECOVERY_SENT
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"
LOG="$TEST_LOG"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: assigned
  task_id: cmd_3751_full
  parent_cmd: cmd_3751
  planned_paths:
    - base.txt
EOF

cat > "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" <<'"'"'EOF'"'"'
#!/bin/bash
echo "PASS"
EOF
chmod +x "$SCRIPT_DIR/scripts/gates/gate_report_format.sh"

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
cli_profile_get() { echo ""; }

PANE_TARGETS[kagemaru]="shogun:2.5"
STALL_THRESHOLD_MIN=1
now=$(date +%s)
STALL_FIRST_SEEN[kagemaru]=$((now - 16 * 60))
check_stall kagemaru
STALL_FIRST_SEEN[kagemaru]=$((now - 16 * 60))
check_stall kagemaru

echo "COMMIT_BLOCK_COUNT=$(grep -F -c "kagemaru|uncommitted_block|" "$TEST_MESSAGES" || true)"
grep -q "ACTIVE-IDLE-COMMIT-RENOTIFY: kagemaru task=cmd_3751_full files=base.txt" "$TEST_LOG"
grep -q "ACTIVE-IDLE-COMMIT-RENOTIFY-SKIP: kagemaru task=cmd_3751_full duplicate" "$TEST_LOG"
cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"COMMIT_BLOCK_COUNT=1"* ]]
    [[ "$output" == *"未commitファイルあり: base.txt"* ]]
}

@test "uncommitted notification scope excludes repo-dirty files outside task path" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT/scope-filter"
mkdir -p "$TMP_ROOT/queue/tasks"
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/filter.log"
cat > "$TMP_ROOT/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  target_path: scripts/ninja_monitor.sh
  planned_paths:
    - tests/unit/test_ninja_monitor_stall.bats
EOF
log() { printf "%s\n" "$1" >> "$LOG"; }
outside=$(printf "repo-dirty-%02d.md\n" $(seq 1 38))
paths=$(printf "%s\n%s\n%s\n" "scripts/ninja_monitor.sh" "tests/unit/test_ninja_monitor_stall.bats" "$outside")
scoped=$(printf "%s" "$paths" | filter_auto_commit_paths_by_task_scope kagemaru)
test "$(printf "%s\n" "$scoped" | sed "/^$/d" | wc -l)" -eq 2
grep -qx "scripts/ninja_monitor.sh" <<< "$scoped"
grep -qx "tests/unit/test_ninja_monitor_stall.bats" <<< "$scoped"
test "$(grep -c "AUTO-COMMIT-SCOPE-SKIP: kagemaru" "$LOG")" -eq 38
printf "repo_dirty=40 scope_selected=2 scope_excluded=38\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"repo_dirty=40 scope_selected=2 scope_excluded=38"* ]]
}

@test "count_unread_messages_cached: same cycle reuses count and next cycle refreshes" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
INBOX_FILE="$TMP_ROOT/hayate.yaml"
cat > "$INBOX_FILE" <<EOF
messages:
- id: msg_1
  read: false
EOF

cycle=41
count_unread_messages_cached "$INBOX_FILE" first
cat >> "$INBOX_FILE" <<EOF
- id: msg_2
  read: false
EOF
count_unread_messages_cached "$INBOX_FILE" second
cycle=42
count_unread_messages_cached "$INBOX_FILE" third

printf "%s,%s,%s\n" "$first" "$second" "$third"
'
    [ "$status" -eq 0 ]
    [ "$output" = "1,1,2" ]
}

@test "count_unread_messages_cached: ignores read false text inside content block" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
INBOX_FILE="$TMP_ROOT/hayate.yaml"
cat > "$INBOX_FILE" <<EOF
messages:
- id: msg_literal
  content: |-
    診断ログ:
    read: false
  read: true
- id: msg_real
  content: 実未読
  read: false
EOF

cycle=91
count_unread_messages_cached "$INBOX_FILE" unread_count

printf "%s\n" "$unread_count"
'
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "check_lesson_deprecation_candidates posts shogun bulletin and logs metrics" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
export SCRIPT_DIR
LOG="$TMP_ROOT/monitor.log"
STATE_DIR="$TMP_ROOT/state"
TEST_BULLETIN="$TMP_ROOT/bulletin.log"
export TEST_BULLETIN
LESSON_DEPRECATION_STATE_FILE="$STATE_DIR/lesson_deprecation.last"
LESSON_DEPRECATION_LOG="$TMP_ROOT/logs/lesson_deprecation_candidates.log"
LESSON_DEPRECATION_INTERVAL=86400
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "METRICS: total_lessons=12 active_lessons=9 deprecated_lessons=3\n\n"
printf "=== 有効率0%% 確定candidate (注入N≥5) ===\n"
printf "  [infra] L001: stale lesson (injected=10, helpful=0)\n"
printf "\n=== 自動退役実行 ===\n"
printf "  DRY-RUN: candidates-only mode (approval required before lesson_write.sh --retire)\n"
printf "  合計: 0件 自動退役\n"
EOF
chmod +x "$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh"

cat > "$SCRIPT_DIR/scripts/bulletin_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "notify=%s posted_by=%s action=%s\n" "${BULLETIN_NOTIFY:-}" "$1" "${4:-}" >> "$TEST_BULLETIN"
printf "%s\n" "$2" >> "$TEST_BULLETIN"
EOF
chmod +x "$SCRIPT_DIR/scripts/bulletin_write.sh"

log() { echo "$1" >> "$LOG"; }

check_lesson_deprecation_candidates

cat "$LOG"
cat "$TEST_BULLETIN"
cat "$LESSON_DEPRECATION_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LESSON-DEPRECATION-METRICS: total_lessons=12 active_lessons=9 deprecated_lessons=3"* ]]
    [[ "$output" == *"LESSON-DEPRECATION: posted 1 candidates to shogun bulletin"* ]]
    [[ "$output" == *"notify=shogun posted_by=ninja_monitor action=action_required"* ]]
    [[ "$output" == *"lesson_write.sh <project> --retire <lesson_id>"* ]]
    [[ "$output" == *"METRICS: total_lessons=12 active_lessons=9 deprecated_lessons=3"* ]]
}

@test "check_script_size_thresholds logs trend and posts refactor request" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
export SCRIPT_DIR
LOG="$TMP_ROOT/monitor.log"
STATE_DIR="$TMP_ROOT/state"
TEST_BULLETIN="$TMP_ROOT/bulletin.log"
export TEST_BULLETIN
SCRIPT_SIZE_CHECK_STATE_FILE="$STATE_DIR/script_size.last"
SCRIPT_SIZE_TREND_LOG="$TMP_ROOT/logs/script_size_trend.log"
SCRIPT_SIZE_CHECK_INTERVAL=86400
SCRIPT_SIZE_LINE_THRESHOLD=3
SCRIPT_SIZE_COMPLEXITY_THRESHOLD=50
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/scripts/big_script.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
big_func() {
  if true; then
    echo ok
  fi
}
EOF

cat > "$SCRIPT_DIR/scripts/small_script.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
echo small
EOF

cat > "$SCRIPT_DIR/scripts/bulletin_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "notify=%s posted_by=%s action=%s\n" "${BULLETIN_NOTIFY:-}" "$1" "${4:-}" >> "$TEST_BULLETIN"
printf "%s\n" "$2" >> "$TEST_BULLETIN"
EOF
chmod +x "$SCRIPT_DIR/scripts/"*.sh

log() { echo "$1" >> "$LOG"; }

check_script_size_thresholds

cat "$LOG"
cat "$TEST_BULLETIN"
cat "$SCRIPT_SIZE_TREND_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SCRIPT-SIZE-ALERT: scripts/big_script.sh lines=6/3"* ]]
    [[ "$output" == *"SCRIPT-SIZE: posted"* ]]
    [[ "$output" == *"notify=shogun posted_by=ninja_monitor action=action_required"* ]]
    [[ "$output" == *"script_size_alert: scripts/配下の主要スクリプト"* ]]
    [[ "$output" == *"scripts/big_script.sh"* ]]
    [[ "$output" == *"timestamp"$'\t'"file"$'\t'"lines"$'\t'"functions"* ]]
}

@test "check_lesson_and_loop_health detect alerts after here-string grep conversion" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
export SCRIPT_DIR
mkdir -p "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/scripts"

cat > "$SCRIPT_DIR/scripts/gates/gate_lesson_health.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "OK: first line\n"
printf "ALERT: lesson drift\n"
printf "ALERT: lesson missing\n"
EOF
cat > "$SCRIPT_DIR/scripts/gates/gate_loop_health.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "OK: first line\n"
printf "WARNING: loop slow\n"
EOF
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
cat > "$SCRIPT_DIR/scripts/ntfy.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$1" >> "$SCRIPT_DIR/ntfy.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/gates/"*.sh "$SCRIPT_DIR/scripts/"*.sh

LESSON_CHECK_INTERVAL=0
LESSON_ALERT_DEBOUNCE=0
LAST_LESSON_CHECK=0
LAST_LESSON_ALERT=0
LOOP_HEALTH_CHECK_INTERVAL=0
LOOP_HEALTH_ALERT_DEBOUNCE=0
LAST_LOOP_HEALTH_CHECK=0
LAST_LOOP_HEALTH_ALERT=0
log() { echo "$1" >> "$LOG"; }

check_lesson_health
check_loop_health

cat "$LOG"
cat "$SCRIPT_DIR/inbox.log"
cat "$SCRIPT_DIR/ntfy.log"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LESSON-HEALTH: ALERT: lesson drift ALERT: lesson missing"* ]]
    [[ "$output" == *"karo|lesson_health|lesson健全性ALERT: ALERT: lesson drift ALERT: lesson missing"* ]]
    [[ "$output" == *"LOOP-HEALTH: WARNING: loop slow"* ]]
    [[ "$output" == *"【三層ループALERT】WARNING: loop slow"* ]]
}

@test "check_lesson_health notifies karo for early-route lesson backlog warnings" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
export SCRIPT_DIR
mkdir -p "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/scripts"

cat > "$SCRIPT_DIR/scripts/gates/gate_lesson_health.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "OK: dm-signalのlesson統合状況は健全(未合流0件,total:796,synced:L825)\n"
printf "WARN: dm-signalの未振り分け教訓8件(早期導線, ALERT閾値10未満, ids: L818,L819,L820,L821,L822,L823,L824,L825)\n"
printf "action: ALERT閾値(10件)に達する前に /lesson-sort を実行し、dm-signalの未振り分け教訓の蓄積を防げ。\n"
printf "WARN: 新規教訓+174件(前回審査: L814, 現在最新: L988)。\n"
EOF
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
cat > "$SCRIPT_DIR/scripts/ntfy.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$1" >> "$SCRIPT_DIR/ntfy.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/gates/"*.sh "$SCRIPT_DIR/scripts/"*.sh

LESSON_CHECK_INTERVAL=0
LESSON_ALERT_DEBOUNCE=0
LAST_LESSON_CHECK=0
LAST_LESSON_ALERT=0
log() { echo "$1" >> "$LOG"; }

check_lesson_health

cat "$LOG"
cat "$SCRIPT_DIR/inbox.log"
cat "$SCRIPT_DIR/ntfy.log"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LESSON-HEALTH: WARN: dm-signalの未振り分け教訓8件"* ]]
    [[ "$output" == *"WARN: 新規教訓+174件"* ]]
    [[ "$output" == *"karo|lesson_health|lesson健全性ALERT: WARN: dm-signalの未振り分け教訓8件"* ]]
    [[ "$output" == *"【教訓ALERT】WARN: dm-signalの未振り分け教訓8件"* ]]
}

@test "run_lock_cleanup deletes stale shogun locks with one configurable scan" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
LOG="$TMP_ROOT/monitor.log"
LOCK_CLEANUP_DIR="$TMP_ROOT/locks"
LOCK_CLEANUP_INTERVAL=3600
LAST_LOCK_CLEANUP=0
# run_lock_cleanupが呼ぶrun_scratch_retentionは未指定だとSCRATCH_RETENTION_REPO=$SCRIPT_DIR
# (実リポジトリ)へフォールバックし、実repoに対するgit worktree list --porcelaneが
# drvfs上で約2.1秒かかる(実測)。このテストはlock file 4件のみを検査対象とするため
# scratch retentionの走査範囲を隔離tmpへ限定し、実repoに触れないようにする。
# git worktree listはgit repo以外だとpipefail+errexitでnon-zero終了するため
# TMP_ROOT自体を空repo化し、run_scratch_retention内部の想定(有効なgit repo)を満たす。
SCRATCH_RETENTION_REPO="$TMP_ROOT"
SCRATCH_QUARANTINE_DIR="$TMP_ROOT/scratch_quarantine"
git init -q "$TMP_ROOT"
mkdir -p "$LOCK_CLEANUP_DIR"

touch "$LOCK_CLEANUP_DIR/shogun_lock_old.lock"
touch "$LOCK_CLEANUP_DIR/auto_deploy_old.lock"
touch "$LOCK_CLEANUP_DIR/shogun_lock_new.lock"
touch "$LOCK_CLEANUP_DIR/unrelated.lock"
touch -d "2 hours ago" "$LOCK_CLEANUP_DIR/shogun_lock_old.lock" "$LOCK_CLEANUP_DIR/auto_deploy_old.lock"

log() { echo "$1" >> "$LOG"; }

run_lock_cleanup

test ! -e "$LOCK_CLEANUP_DIR/shogun_lock_old.lock"
test ! -e "$LOCK_CLEANUP_DIR/auto_deploy_old.lock"
test -e "$LOCK_CLEANUP_DIR/shogun_lock_new.lock"
test -e "$LOCK_CLEANUP_DIR/unrelated.lock"
cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOCK-CLEANUP: Removed 2 stale lock files"* ]]
}

@test "check_three_layer_maintenance runs cleanup, recall, and promote apply once per interval" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
THREE_LAYER_MAINTENANCE_INTERVAL=3600
THREE_LAYER_MAINTENANCE_STATE_FILE="$STATE_DIR/shogun_three_layer_maintenance.last"
THREE_LAYER_MAINTENANCE_LOG="$TMP_ROOT/logs/three_layer_maintenance.log"
export THREE_LAYER_MAINTENANCE_LOG
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/scripts/cleanup_three_layer_tmp.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "cleanup:%s\n" "$*" >> "$THREE_LAYER_MAINTENANCE_LOG"
EOF
cat > "$SCRIPT_DIR/scripts/memory_recall_control.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "recall:%s\n" "$*" >> "$THREE_LAYER_MAINTENANCE_LOG"
EOF
cat > "$SCRIPT_DIR/scripts/obsidian_promote_candidate.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "promote:%s\n" "$*" >> "$THREE_LAYER_MAINTENANCE_LOG"
EOF
chmod +x "$SCRIPT_DIR/scripts/"*.sh

log() { echo "$1" >> "$LOG"; }

check_three_layer_maintenance
check_three_layer_maintenance

for _ in {1..100}; do
    [ -e "$THREE_LAYER_MAINTENANCE_STATE_FILE" ] && ! flock -n "$STATE_DIR/shogun_three_layer_maintenance.lock" -c : 2>/dev/null && { sleep 0.01; continue; }
    [ -e "$THREE_LAYER_MAINTENANCE_STATE_FILE" ] && break
    sleep 0.01
done

cat "$THREE_LAYER_MAINTENANCE_LOG"
cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"cleanup:--apply --ttl-hours 4"* ]]
    [[ "$output" == *"recall:"* ]]
    [[ "$output" != *"recall:--dry-run"* ]]
    [[ "$output" == *"promote:"* ]]
    [[ "$output" != *"promote:--dry-run"* ]]
    [[ "$(printf '%s\n' "$output" | grep -c '^cleanup:')" -eq 1 ]]
    [[ "$(printf '%s\n' "$output" | grep -c '^recall:')" -eq 1 ]]
    [[ "$(printf '%s\n' "$output" | grep -c '^promote:')" -eq 1 ]]
    [[ "$output" == *"THREE-LAYER-MAINTENANCE: tmp cleanup done"* ]]
    [[ "$output" == *"THREE-LAYER-MAINTENANCE: recall_control apply done"* ]]
    [[ "$output" == *"THREE-LAYER-MAINTENANCE: obsidian_promote apply done"* ]]
}

@test "check_three_layer_maintenance returns immediately and enforces single-flight while child stalls" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
THREE_LAYER_MAINTENANCE_INTERVAL=0
THREE_LAYER_MAINTENANCE_TIMEOUT=1
THREE_LAYER_MAINTENANCE_STATE_FILE="$STATE_DIR/last"
THREE_LAYER_MAINTENANCE_LOG="$TMP_ROOT/maintenance.log"
mkdir -p "$SCRIPT_DIR/scripts" "$STATE_DIR"
printf %s\\n "#!/usr/bin/env bash" "sleep 120" > "$SCRIPT_DIR/scripts/cleanup_three_layer_tmp.sh"
chmod +x "$SCRIPT_DIR/scripts/cleanup_three_layer_tmp.sh"
log() { printf "%s\n" "$1" >> "$LOG"; }
start=$EPOCHREALTIME
check_three_layer_maintenance
check_three_layer_maintenance
elapsed=$(awk -v a="$start" -v b="$EPOCHREALTIME" "BEGIN {print b-a}")
awk -v e="$elapsed" "BEGIN {exit !(e < 0.5)}"
grep -q "already running, skip" "$LOG"
wait
'
    [ "$status" -eq 0 ]
}

@test "check_three_layer_maintenance flock has no stale block after holder exits abnormally" {
    run bash -lc '
set -euo pipefail
export NINJA_MONITOR_LIB_ONLY=1
source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
THREE_LAYER_MAINTENANCE_INTERVAL=0
THREE_LAYER_MAINTENANCE_TIMEOUT=1
THREE_LAYER_MAINTENANCE_STATE_FILE="$STATE_DIR/last"
THREE_LAYER_MAINTENANCE_LOG="$TMP_ROOT/maintenance.log"
mkdir -p "$SCRIPT_DIR/scripts" "$STATE_DIR"
printf %s\\n "#!/usr/bin/env bash" "exit 137" > "$SCRIPT_DIR/scripts/cleanup_three_layer_tmp.sh"
chmod +x "$SCRIPT_DIR/scripts/cleanup_three_layer_tmp.sh"
log() { printf "%s\n" "$1" >> "$LOG"; }
check_three_layer_maintenance
for _ in {1..100}; do
    flock -n "$STATE_DIR/shogun_three_layer_maintenance.lock" -c : 2>/dev/null && break
    sleep 0.01
done
check_three_layer_maintenance
wait
starts=$(grep -c "tmp cleanup start" "$LOG")
skips=$(grep -c "already running, skip" "$LOG" || true)
test "$starts" -eq 2
test "$skips" -eq 0
printf "maintenance_started=%s duplicates=0 stale_blocks=%s\n" "$starts" "$skips"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"maintenance_started=2 duplicates=0 stale_blocks=0"* ]]
}

@test "build_pane_head_tail_excerpt filters blanks and keeps head tail in one pass" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
TEST_BIN="$TMP_ROOT/bin"
mkdir -p "$TEST_BIN"
export PATH="$TEST_BIN:$PATH"
cat > "$TEST_BIN/tmux" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
if [ "$1" = "capture-pane" ]; then
  printf "\nline01\nline02\nline03\nline04\nline05\nline06\nline07\nline08\nline09\nline10\nline11\nline12\n\n"
fi
EOF
chmod +x "$TEST_BIN/tmux"

build_pane_head_tail_excerpt "dummy"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[pane head 5]"* ]]
    [[ "$output" == *"line01"$'\n'"line02"$'\n'"line03"$'\n'"line04"$'\n'"line05"* ]]
    [[ "$output" == *"[pane tail 5]"* ]]
    [[ "$output" == *"line08"$'\n'"line09"$'\n'"line10"$'\n'"line11"$'\n'"line12"* ]]
    [[ "$output" != *"line06"$'\n'"line07"* ]]
}

@test "check_karo_idle_cycle counts snapshot and pipeline with numeric awk results" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
export SCRIPT_DIR
LAST_KARO_IDLE_NUDGE=0
KARO_IDLE_COOLDOWN=0
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/config" "$SCRIPT_DIR/scripts"

cat > "$SCRIPT_DIR/config/settings.yaml" <<'"'"'EOF'"'"'
idle_cycle: on
EOF
cat > "$SCRIPT_DIR/queue/karo_snapshot.txt" <<'"'"'EOF'"'"'
ninja|hayate|cmd_a|idle
ninja|kagemaru|cmd_b|done
EOF
cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<'"'"'EOF'"'"'
commands:
EOF
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

log() { echo "$1" >> "$LOG"; }

check_karo_idle_cycle

cat "$LOG"
cat "$SCRIPT_DIR/inbox.log"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-IDLE-CYCLE: Sent improvement cycle nudge to karo"* ]]
    [[ "$output" == *"karo|karo_idle_cycle|全忍者idle+パイプライン空。改善サイクルを回せ。"* ]]
}

@test "check_shogun_idle_analysis_trigger sends after all idle and pipeline empty for 10 minutes" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
export SCRIPT_DIR
LAST_SHOGUN_IDLE_ANALYSIS_TRIGGER=0
SHOGUN_IDLE_ANALYSIS_COOLDOWN=3600
SHOGUN_IDLE_ANALYSIS_ALL_IDLE_SINCE=$((EPOCHSECONDS - 660))
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/config" "$SCRIPT_DIR/scripts"

cat > "$SCRIPT_DIR/config/settings.yaml" <<'"'"'EOF'"'"'
idle_cycle: on
EOF
cat > "$SCRIPT_DIR/queue/karo_snapshot.txt" <<'"'"'EOF'"'"'
ninja|hayate|cmd_a|idle
ninja|kagemaru|cmd_b|done
EOF
cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<'"'"'EOF'"'"'
commands:
EOF
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

log() { echo "$1" >> "$LOG"; }

check_shogun_idle_analysis_trigger

cat "$LOG"
cat "$SCRIPT_DIR/inbox.log"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHOGUN-IDLE-ANALYSIS: All 2 ninjas idle/completed/done + pipeline empty"* ]]
    [[ "$output" == *"shogun|idle_analysis_trigger|全忍者idle+パイプライン空が10分以上継続。idle時自己分析 Step 1-7 を開始せよ。"* ]]
}

@test "check_shogun_idle_analysis_trigger debounces duplicate sends within 60 minutes" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
export SCRIPT_DIR
LAST_SHOGUN_IDLE_ANALYSIS_TRIGGER=$((EPOCHSECONDS - 300))
SHOGUN_IDLE_ANALYSIS_COOLDOWN=3600
SHOGUN_IDLE_ANALYSIS_ALL_IDLE_SINCE=$((EPOCHSECONDS - 660))
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/config" "$SCRIPT_DIR/scripts"

printf "idle_cycle: on\n" > "$SCRIPT_DIR/config/settings.yaml"
printf "ninja|hayate|cmd_a|idle\nninja|kagemaru|cmd_b|done\n" > "$SCRIPT_DIR/queue/karo_snapshot.txt"
printf "commands:\n" > "$SCRIPT_DIR/queue/shogun_to_karo.yaml"
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

log() { echo "$1" >> "$LOG"; }

check_shogun_idle_analysis_trigger
test ! -f "$SCRIPT_DIR/inbox.log"
'
    [ "$status" -eq 0 ]
}

@test "check_shogun_idle_analysis_trigger skips while pipeline has pending command" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
export SCRIPT_DIR
LAST_SHOGUN_IDLE_ANALYSIS_TRIGGER=0
SHOGUN_IDLE_ANALYSIS_COOLDOWN=3600
SHOGUN_IDLE_ANALYSIS_ALL_IDLE_SINCE=$((EPOCHSECONDS - 660))
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/config" "$SCRIPT_DIR/scripts"

printf "idle_cycle: on\n" > "$SCRIPT_DIR/config/settings.yaml"
printf "ninja|hayate|cmd_a|idle\nninja|kagemaru|cmd_b|done\n" > "$SCRIPT_DIR/queue/karo_snapshot.txt"
cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<'"'"'EOF'"'"'
commands:
- id: cmd_pending
  status: pending
EOF
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

log() { echo "$1" >> "$LOG"; }

check_shogun_idle_analysis_trigger
test ! -f "$SCRIPT_DIR/inbox.log"
'
    [ "$status" -eq 0 ]
}

@test "check_ninja_cli_dead covers karo pane through unified agent map" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
TMUX_LOG="$TMP_ROOT/tmux.log"
export SCRIPT_DIR TMUX_LOG
mkdir -p "$SCRIPT_DIR/scripts" "$TMP_ROOT/bin"

cat > "$SCRIPT_DIR/scripts/ntfy.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$1" >> "$SCRIPT_DIR/ntfy.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/ntfy.sh"

cat > "$TMP_ROOT/bin/tmux" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) printf "shogun:agents.7\n" ;;
  display-message)
    case "$*" in
      *@lord_active*) printf "0\n" ;;
      *) printf "1\n" ;;
    esac
    ;;
  respawn-pane) exit 0 ;;
esac
EOF
chmod +x "$TMP_ROOT/bin/tmux"
PATH="$TMP_ROOT/bin:$PATH"

log() { echo "$1" >> "$LOG"; }
build_cli_command() { printf "/home/simokitafresh/bin/claude --effort high --dangerously-skip-permissions\n"; }
sleep() { :; }
NINJA_NAMES=()
unset PANE_TARGETS CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
declare -A PANE_TARGETS CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
PANE_TARGETS[karo]="shogun:agents.7"
CLI_DEAD_LOOP_WINDOW=300
CLI_DEAD_LOOP_THRESHOLD=2

check_ninja_cli_dead
sleep 1
wait

cat "$TMUX_LOG"
cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"display-message -t shogun:agents.7"* ]]
    [[ "$output" == *"CLI-DEAD: karo@shogun:agents.7"* ]]
}

@test "check_ninja_cli_dead covers gunshi pane through unified agent map" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
TMUX_LOG="$TMP_ROOT/tmux.log"
export SCRIPT_DIR TMUX_LOG
mkdir -p "$SCRIPT_DIR/scripts" "$TMP_ROOT/bin"

cat > "$SCRIPT_DIR/scripts/ntfy.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$SCRIPT_DIR/scripts/ntfy.sh"

cat > "$TMP_ROOT/bin/tmux" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$TMUX_LOG"
case "$1" in
  display-message)
    case "$*" in
      *@lord_active*) printf "0\n" ;;
      *) printf "1\n" ;;
    esac
    ;;
  respawn-pane) exit 0 ;;
esac
EOF
chmod +x "$TMP_ROOT/bin/tmux"
PATH="$TMP_ROOT/bin:$PATH"

log() { echo "$1" >> "$LOG"; }
build_cli_command() { printf "/home/simokitafresh/.local/share/codex/bin/codex --full-auto\n"; }
sleep() { :; }
NINJA_NAMES=()
unset PANE_TARGETS CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
declare -A PANE_TARGETS CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
PANE_TARGETS[gunshi]="shogun:agents.9"
CLI_DEAD_LOOP_WINDOW=300
CLI_DEAD_LOOP_THRESHOLD=2

check_ninja_cli_dead
sleep 1

cat "$TMUX_LOG"
cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"display-message -t shogun:agents.9"* ]]
    [[ "$output" == *"CLI-DEAD: gunshi@shogun:agents.9"* ]]
}

@test "check_ninja_cli_dead skips shell parent when Claude child is alive" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
TMUX_LOG="$TMP_ROOT/tmux.log"
export SCRIPT_DIR TMUX_LOG
mkdir -p "$SCRIPT_DIR/scripts" "$TMP_ROOT/bin"

cat > "$SCRIPT_DIR/scripts/ntfy.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$SCRIPT_DIR/scripts/ntfy.sh"

cat > "$TMP_ROOT/bin/tmux" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$TMUX_LOG"
case "$1" in
  display-message)
    case "$*" in
      *pane_dead*) printf "0\n" ;;
      *pane_current_command*) printf "bash\n" ;;
      *pane_pid*) printf "4242\n" ;;
      *) printf "\n" ;;
    esac
    ;;
  respawn-pane|send-keys) printf "UNEXPECTED %s\n" "$*" >> "$TMUX_LOG"; exit 1 ;;
esac
EOF
chmod +x "$TMP_ROOT/bin/tmux"
PATH="$TMP_ROOT/bin:$PATH"

ps() { printf "bash\nclaude\n"; }
log() { echo "$1" >> "$LOG"; }
sleep() { :; }
NINJA_NAMES=()
unset PANE_TARGETS CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
declare -A PANE_TARGETS CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
PANE_TARGETS[gunshi]="shogun:agents.2"
CLI_DEAD_LOOP_WINDOW=300
CLI_DEAD_LOOP_THRESHOLD=2

check_ninja_cli_dead

cat "$TMUX_LOG"
cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI-DEAD-SKIP: gunshi@shogun:agents.2 pane_current_command=bash but live CLI child=claude"* ]]
    [[ "$output" != *"UNEXPECTED"* ]]
    [[ "$output" != *"再起動実行"* ]]
}

@test "check_ninja_cli_dead uses respawn-pane instead of send-keys for live shell recovery" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
TMUX_LOG="$TMP_ROOT/tmux.log"
export SCRIPT_DIR TMUX_LOG
mkdir -p "$SCRIPT_DIR/scripts" "$TMP_ROOT/bin"

cat > "$SCRIPT_DIR/scripts/ntfy.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$SCRIPT_DIR/scripts/ntfy.sh"

cat > "$TMP_ROOT/bin/tmux" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$TMUX_LOG"
case "$1" in
  display-message)
    case "$*" in
      *pane_dead*) printf "0\n" ;;
      *pane_current_command*) printf "bash\n" ;;
      *pane_pid*) printf "4242\n" ;;
      *@agent_id*) printf "gunshi\n" ;;
      *) printf "\n" ;;
    esac
    ;;
  respawn-pane) exit 0 ;;
  send-keys) printf "UNEXPECTED_SEND_KEYS %s\n" "$*" >> "$TMUX_LOG"; exit 1 ;;
esac
EOF
chmod +x "$TMP_ROOT/bin/tmux"
PATH="$TMP_ROOT/bin:$PATH"

ps() { printf "bash\n"; }
log() { echo "$1" >> "$LOG"; }
build_cli_command() { printf "/home/simokitafresh/bin/claude --dangerously-skip-permissions\n"; }
sleep() { :; }
NINJA_NAMES=()
unset PANE_TARGETS CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
declare -A PANE_TARGETS CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
PANE_TARGETS[gunshi]="shogun:agents.2"
CLI_DEAD_LOOP_WINDOW=300
CLI_DEAD_LOOP_THRESHOLD=2

check_ninja_cli_dead
sleep 1
wait

cat "$TMUX_LOG"
cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"respawn-pane -k -t shogun:agents.2"* ]]
    [[ "$output" == *"CLI-DEAD: gunshi pane_dead=0 → respawn-pane使用"* ]]
    [[ "$output" != *"UNEXPECTED_SEND_KEYS"* ]]
}

@test "check_yaml_size counts lines and completed statuses with one awk pass" {
    # test_necessity: canceled/cancelledの両綴りを終端statusとして数えないと、
    # 監視がarchive不全を見逃してcommand queueが無制限に肥大化するため。
    # regression_justification: 既存のcompleted/done集計契約を、実運用で使われる
    # canceledと旧来cancelledの互換境界へ拡張する回帰固定。
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
export SCRIPT_DIR
mkdir -p "$SCRIPT_DIR/queue" "$TMP_ROOT/bin"

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<'"'"'EOF'"'"'
commands:
  cmd_a:
    status: completed
  cmd_b:
    status: done
  cmd_c:
    status: pending
  cmd_d:
    status: canceled
  cmd_e:
    status: cancelled
EOF

cat > "$TMP_ROOT/bin/awk" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "awk\n" >> "$AWK_CALLS_FILE"
exec /usr/bin/awk "$@"
EOF
chmod +x "$TMP_ROOT/bin/awk"
export AWK_CALLS_FILE="$TMP_ROOT/awk_calls"
PATH="$TMP_ROOT/bin:$PATH"

YAML_SIZE_WARN_THRESHOLD=3
YAML_COMPLETED_ALERT_THRESHOLD=1
log() { echo "$1" >> "$LOG"; }

check_yaml_size

cat "$LOG"
printf "AWK_CALLS=%s\n" "$(wc -l < "$AWK_CALLS_FILE")"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"shogun_to_karo.yaml is 11 lines"* ]]
    [[ "$output" == *"ALERT: 4 completed cmds"* ]]
    [[ "$output" == *"AWK_CALLS=1"* ]]
}

@test "notify_idle_batch compacts pane evidence with one awk pass" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
export SCRIPT_DIR
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_123_exact
EOF
cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<'"'"'EOF'"'"'
commands: {}
EOF
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s|%s|%s\n" "$1" "$3" "$2" >> "$SCRIPT_DIR/inbox.log"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

declare -A PANE_TARGETS LAST_NOTIFIED
PANE_TARGETS[kagemaru]="shogun:2.4"

get_context_pct() { echo 42; }
tmux() {
    case "$1" in
        capture-pane)
            printf "\nline one\n\nline two\nline three\nline four\n"
            ;;
        *) return 1 ;;
    esac
}
log() { echo "$1" >> "$LOG"; }

notify_idle_batch kagemaru

cat "$SCRIPT_DIR/inbox.log"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"kagemaru(CTX:42%,last:cmd_123_exact)"* ]]
    [[ "$output" == *"pane証拠: [pane:kagemaru] line two|line three|line four"* ]]
}

@test "check_inbox_renudge: karo pending work creates inbox message, never inbox0 direct nudge" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/tasks/hanzo.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  parent_cmd: cmd_pending_review
EOF

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s from=%s msg=%s\n" "\$1" "\$3" "\$4" "\$2"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() {
    echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"
    return 0
}

check_inbox_renudge

cat "$LOG"
if [ -f "$TMP_ROOT/direct_nudge.log" ]; then
    cat "$TMP_ROOT/direct_nudge.log"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-INBOX"* ]]
    [[ "$output" == *"INBOX-WRITE-CALLED: to=karo type=pending_work"* ]]
    [[ "$output" == *"未処理の忍者done/failed報告"* ]]
    [[ "$output" != *"DIRECT_NUDGE:inbox0"* ]]
}

# test_necessity: terminal pending work must be persisted while Karo is busy;
# watcher-owned wake-up must not depend on pane idleness or direct input.
@test "check_inbox_renudge: busy karo still receives exactly-once pending mailbox notice" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$STATE_DIR"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/karo.yaml"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/gunshi.yaml"
printf "task:\n  status: done\n  task_id: busy_pending\n  parent_cmd: cmd_busy_pending\n" > "$SCRIPT_DIR/queue/tasks/hanzo.yaml"
printf "status: completed\nverdict: PASS\n" > "$SCRIPT_DIR/queue/reports/hanzo_report_cmd_busy_pending.yaml"
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s from=%s msg=%s\\n" "\$1" "\$3" "\$4" "\$2" >> "$TMP_ROOT/inbox.log"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=(); KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 1; }
safe_send_keys_atomic() { echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"; return 0; }

check_inbox_renudge
check_inbox_renudge
test "$(grep -c "INBOX-WRITE-CALLED: to=karo type=pending_work" "$TMP_ROOT/inbox.log")" -eq 1
test ! -e "$TMP_ROOT/direct_nudge.log"
grep -q "KARO-PENDING-INBOX" "$LOG"
printf "%s\\n" "busy_notice=1 direct_nudge=0"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"busy_notice=1 direct_nudge=0"* ]]
}

# test_necessity: 軍師LGTM済みdoneを処理不要SKIPせず、既存世代dedupeで家老完了処理要求を一度だけ送る不変量。
@test "check_inbox_renudge: reviewed done report requests karo completion exactly once" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  parent_cmd: cmd_reviewed_done
EOF
cat > "$SCRIPT_DIR/logs/gunshi_review_log.yaml" <<'"'"'EOF'"'"'
- cmd_id: cmd_reviewed_done
  review_type: report
  verdict: LGTM
  report_ninja: kagemaru
  report_task_id: cmd_reviewed_done_focused
EOF

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s from=%s msg=%s\n" "\$1" "\$3" "\$4" "\$2"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() {
    echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"
    return 0
}

check_inbox_renudge
check_inbox_renudge

cat "$LOG"
if [ -f "$TMP_ROOT/direct_nudge.log" ]; then
    cat "$TMP_ROOT/direct_nudge.log"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-REVIEWED-COMPLETION: cmd_reviewed_done has gunshi report review; requesting cmd completion"* ]]
    [[ "$output" == *"KARO-PENDING-INBOX"* ]]
    [[ "$output" == *"KARO-PENDING-DEDUPE"* ]]
    [[ "$output" == *"INBOX-WRITE-CALLED: to=karo type=pending_work"* ]]
    [ "$(grep -c 'INBOX-WRITE-CALLED: to=karo type=pending_work' <<< "$output")" -eq 1 ]
    [[ "$output" != *"DIRECT_NUDGE:inbox0"* ]]
}

# test_necessity: canonical fingerprint-bound review progress is not a pending
# completion event; audit-log-only review evidence remains visible to Karo.
@test "check_inbox_renudge: canonical review in progress is excluded without hiding audit-only review" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"; trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" \
    "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/gates/cmd_canonical/review_approvals/reports" \
    "$SCRIPT_DIR/scripts" "$STATE_DIR"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/karo.yaml"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/gunshi.yaml"
printf "task:\n  status: done\n  parent_cmd: cmd_canonical\n  report_filename: kagemaru_report_cmd_canonical.yaml\n" > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml"
cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_canonical.yaml" <<'EOF'
worker_id: kagemaru
task_id: cmd_canonical_full
parent_cmd: cmd_canonical
task_type: scout
status: completed
verdict: PASS
files_modified: []
binary_checks: {}
EOF
report="$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_canonical.yaml"
fp=$(review_report_fingerprint "$report")
key=$(review_report_key "queue/reports/kagemaru_report_cmd_canonical.yaml")
mkdir -p "$SCRIPT_DIR/queue/gates/cmd_canonical/review_approvals/reports/$key"
cat > "$SCRIPT_DIR/queue/gates/cmd_canonical/review_approvals/reports/$key/gunshi.yaml" <<EOF
result: LGTM
fingerprint: $fp
report: queue/reports/kagemaru_report_cmd_canonical.yaml
EOF
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s msg=%s\n" "\$1" "\$3" "\$2" >> "$TMP_ROOT/inbox.log"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=(); KARO_PANE=karo
declare -A RENUDGE_FINGERPRINT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() { return 0; }
check_inbox_renudge

grep -q "KARO-PENDING-SKIP-CANONICAL-REVIEW: cmd_canonical state=gunshi_lgtm_pending_karo_accept" "$LOG"
test ! -e "$TMP_ROOT/inbox.log"
printf "canonical_review=0 false_positive=0\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"canonical_review=0 false_positive=0"* ]]
}

# test_necessity: a true completed_unarchived notification carries the latest
# gate BLOCK reason so Karo can act without reconstructing historical state.
@test "check_inbox_renudge: true pending notice includes latest gate BLOCK reason" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"; trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" \
    "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/karo.yaml"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/gunshi.yaml"
printf "task:\n  status: done\n  parent_cmd: cmd_blocked_notice\n" > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml"
printf "2026-08-09T00:00:00\tcmd_blocked_notice\tCLEAR\told_clear\n2026-08-09T00:01:00\tcmd_blocked_notice\tBLOCK\tcanonical_review_missing\n" > "$SCRIPT_DIR/logs/gate_metrics.log"
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s msg=%s\n" "\$1" "\$3" "\$2" >> "$TMP_ROOT/inbox.log"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=(); KARO_PANE=karo
declare -A RENUDGE_FINGERPRINT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() { return 0; }
check_inbox_renudge

grep -q "latest_gate_BLOCK=canonical_review_missing" "$TMP_ROOT/inbox.log"
test "$(grep -c "INBOX-WRITE-CALLED: to=karo type=pending_work" "$TMP_ROOT/inbox.log")" -eq 1
printf "gate_block_notice=1 reason_attached=1\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate_block_notice=1 reason_attached=1"* ]]
}

@test "check_inbox_renudge: gate CLEAR done task does not create duplicate karo pending inbox" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/tasks/kotaro.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  parent_cmd: cmd_gate_clear_done
EOF
cat > "$SCRIPT_DIR/logs/gate_metrics.log" <<'"'"'EOF'"'"'
2026-06-20T01:00:00	cmd_gate_clear_done	CLEAR	all_gates_passed	impl	unknown	unknown	none
EOF

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s from=%s msg=%s\n" "\$1" "\$3" "\$4" "\$2"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() {
    echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"
    return 0
}

check_inbox_renudge

cat "$LOG"
if [ -f "$TMP_ROOT/direct_nudge.log" ]; then
    cat "$TMP_ROOT/direct_nudge.log"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-SKIP-GATE-CLEAR: cmd_gate_clear_done already has gate CLEAR"* ]]
    [[ "$output" != *"KARO-PENDING-INBOX"* ]]
    [[ "$output" != *"pending_work"* ]]
    [[ "$output" != *"DIRECT_NUDGE:inbox0"* ]]
}

@test "check_inbox_renudge: done task without parent_cmd does not create pending inbox" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/tasks/tobisaru.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  parent_cmd: none
EOF

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s from=%s msg=%s\n" "\$1" "\$3" "\$4" "\$2"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() {
    echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"
    return 0
}

check_inbox_renudge

cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-SKIP-NO-PARENT-CMD"* ]]
    [[ "$output" != *"KARO-PENDING-INBOX"* ]]
    [[ "$output" != *"pending_work"* ]]
}

# AC2/AC4(cmd_karo_hotfix_failed_report_clear_notify_gap): 修正前はstatus=doneのみ許可し
# failed報告はpending work検知から漏れていた(cmd_3861実例: report完成後にtask failedとなり
# 家老inboxが07:06以降更新されないままCodex respawnが発生)。修正後は1件のKARO-PENDING-INBOXを送る。
@test "check_inbox_renudge: failed report creates karo pending inbox (cmd_3861 regression)" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: failed
  parent_cmd: cmd_3861
EOF

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s from=%s msg=%s\n" "\$1" "\$3" "\$4" "\$2" >> "$TMP_ROOT/inbox_calls.log"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() {
    echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"
    return 0
}

check_inbox_renudge

cat "$LOG"
cat "$TMP_ROOT/inbox_calls.log"

MSG_COUNT=$(wc -l < "$TMP_ROOT/inbox_calls.log")
echo "MSG_COUNT=$MSG_COUNT"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-INBOX"* ]]
    [[ "$output" == *"INBOX-WRITE-CALLED: to=karo type=pending_work"* ]]
    [[ "$output" == *"MSG_COUNT=1"* ]]
}

@test "check_inbox_renudge: active terminal FAIL remains pending until archived" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"; trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$STATE_DIR"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/karo.yaml"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/gunshi.yaml"
printf "task:\n  status: failed\n  parent_cmd: cmd_terminal_fail\n  report_filename: kagemaru_report_cmd_terminal_fail.yaml\n" > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml"
printf "status: completed\nverdict: FAIL\n" > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_terminal_fail.yaml"
printf "#!/bin/bash\necho CALLED >> %q\n" "$TMP_ROOT/inbox_calls.log" > "$SCRIPT_DIR/scripts/inbox_write.sh"
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"
NINJA_NAMES=(); KARO_PANE="karo"; declare -A RENUDGE_FINGERPRINT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }; check_idle() { return 0; }; safe_send_keys_atomic() { return 0; }
check_inbox_renudge
cat "$LOG"
test -e "$TMP_ROOT/inbox_calls.log"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-INBOX"* ]]
}

# test_necessity: pending_workはarchive済みFAILだけを閉じ、active・未archive・RC/reopen新世代を通知する。
@test "check_inbox_renudge: archived FAIL generation matrix has zero false positives and negatives" {
    # cmd_karo_hotfix_fail_close_respawn_notice_20260729(_pending_task_has_terminal_archive)以降、
    # 世代判定の一次証跡はtask YAML mtimeの前後関係ではなくarchive.doneマーカーの有無そのものになった。
    # cmd_reopen.shの実装(明示reopenは4マーカーをinvalidatedへmvしてarchive.doneを除去する)に合わせ、
    # 「reopen」はmtime touchではなくマーカー除去でシミュレートする(fixture契約修正。コード変更なし)。
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

run_case() {
    local case_name="$1" status="$2" placement="$3" marker_state="$4" expected="$5"
    local root="$NINJA_MONITOR_TEST_ROOT/$case_name"
    SCRIPT_DIR="$root"; STATE_DIR="$root/state"; LOG="$root/monitor.log"
    mkdir -p "$root/queue/tasks" "$root/queue/inbox" "$root/queue/archive/cmds" \
        "$root/queue/archive/reports" "$root/queue/reports" "$root/queue/gates/cmd_matrix" \
        "$root/scripts" "$STATE_DIR"
    printf "messages: []\n" > "$root/queue/inbox/karo.yaml"
    printf "messages: []\n" > "$root/queue/inbox/gunshi.yaml"
    printf "task:\n  status: %s\n  parent_cmd: cmd_matrix\n  report_filename: kotaro_report_cmd_matrix.yaml\n" "$status" > "$root/queue/tasks/kotaro.yaml"
    printf "status: failed\nverdict: FAIL\n" > "$root/$placement/kotaro_report_cmd_matrix.yaml"
    : > "$root/queue/gates/cmd_matrix/archive.done"
    if [ "$marker_state" = reopened ]; then
        # cmd_reopen.shはarchive.doneをstate/へmvして除去する(marker removal = 明示reopenの合図)
        rm -f "$root/queue/gates/cmd_matrix/archive.done"
    fi
    printf "#!/bin/bash\necho CALLED\n" > "$root/scripts/inbox_write.sh"
    chmod +x "$root/scripts/inbox_write.sh"
    NINJA_NAMES=(); KARO_PANE=karo
    declare -gA RENUDGE_FINGERPRINT=() RENUDGE_COUNT=() RENUDGE_LAST_SEND=()
    check_idle() { return 0; }
    log() { echo "$1" >> "$LOG"; }
    check_inbox_renudge
    local actual=0
    grep -q "KARO-PENDING-INBOX" "$LOG" && actual=1
    printf "CASE=%s expected=%s actual=%s\n" "$case_name" "$expected" "$actual"
    [ "$actual" -eq "$expected" ]
}

run_case archived_failed failed queue/archive/reports present 0
run_case regenerated_active_failed failed queue/reports present 0
run_case regenerated_active_done done queue/reports present 0
run_case reopened_failed failed queue/archive/reports reopened 1
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CASE=archived_failed expected=0 actual=0"* ]]
    [[ "$output" == *"CASE=regenerated_active_failed expected=0 actual=0"* ]]
    [[ "$output" == *"CASE=regenerated_active_done expected=0 actual=0"* ]]
    [[ "$output" == *"CASE=reopened_failed expected=1 actual=1"* ]]
}

@test "check_inbox_renudge: completed PASS BLOCKED report is closed" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"; trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$STATE_DIR"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/karo.yaml"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/gunshi.yaml"
printf "task:\n  status: failed\n  parent_cmd: cmd_terminal_blocked\n  report_filename: hanzo_report_cmd_terminal_blocked.yaml\n" > "$SCRIPT_DIR/queue/tasks/hanzo.yaml"
printf "status: completed\nverdict: PASS\nstatus_detail: BLOCKED\n" > "$SCRIPT_DIR/queue/reports/hanzo_report_cmd_terminal_blocked.yaml"
printf "#!/bin/bash\necho CALLED >> %q\n" "$TMP_ROOT/inbox_calls.log" > "$SCRIPT_DIR/scripts/inbox_write.sh"
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"
NINJA_NAMES=(); KARO_PANE="karo"; declare -A RENUDGE_FINGERPRINT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }; check_idle() { return 0; }; safe_send_keys_atomic() { return 0; }
check_inbox_renudge
cat "$LOG"
test ! -e "$TMP_ROOT/inbox_calls.log"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-SKIP-CLOSED-BLOCKED: cmd_terminal_blocked"* ]]
}

@test "check_inbox_renudge: failed completed report with non-FAIL verdict remains pending" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"; trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$STATE_DIR"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/karo.yaml"
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/gunshi.yaml"
printf "task:\n  status: failed\n  parent_cmd: cmd_failed_nonfail\n  report_filename: kagemaru_report_cmd_failed_nonfail.yaml\n" > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml"
printf "status: completed\nverdict: PASS\n" > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_failed_nonfail.yaml"
printf "#!/bin/bash\necho CALLED >> %q\n" "$TMP_ROOT/inbox_calls.log" > "$SCRIPT_DIR/scripts/inbox_write.sh"
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"
NINJA_NAMES=(); KARO_PANE="karo"; declare -A RENUDGE_FINGERPRINT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }; check_idle() { return 0; }; safe_send_keys_atomic() { return 0; }
check_inbox_renudge
cat "$LOG"
test "$(wc -l < "$TMP_ROOT/inbox_calls.log")" -eq 1
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-INBOX"* ]]
}

# cmd_karo_hotfix_pending_work_generation_dedupe_202607121023 AC4: 同一pending集合(worker+
# task_id+parent_cmd+status+report内容が全て不変)が3サイクル続いても通知は1件のみ。
# monitor state再生成(=同一TMP_ROOT/STATE_DIRを保った再sourcing)を跨いでも1件のまま。
@test "check_inbox_renudge: same pending generation across 3 cycles and monitor state regeneration sends exactly 1 notification" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
export SHOGUN_STATE_DIR="$TMP_ROOT/state"
mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/queue/inbox" "$TMP_ROOT/queue/archive/cmds" "$TMP_ROOT/queue/reports" "$TMP_ROOT/scripts" "$SHOGUN_STATE_DIR"

cat > "$TMP_ROOT/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$TMP_ROOT/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$TMP_ROOT/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: failed
  parent_cmd: cmd_gen_stable
  task_id: cmd_gen_stable_full
EOF

cat > "$TMP_ROOT/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s from=%s msg=%s\n" "\$1" "\$3" "\$4" "\$2" >> "$TMP_ROOT/inbox_calls.log"
exit 0
STUBEOF
chmod +x "$TMP_ROOT/scripts/inbox_write.sh"

run_one_cycle() {
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    unset NINJA_MONITOR_LIB_ONLY
    SCRIPT_DIR="$TMP_ROOT"
    LOG="$TMP_ROOT/monitor.log"
    NINJA_NAMES=()
    KARO_PANE="shogun:agents.1"
    declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
    log() { echo "$1" >> "$LOG"; }
    check_idle() { return 0; }
    safe_send_keys_atomic() { return 0; }
    check_inbox_renudge
}

# サイクル1-3: 同一pending集合。各呼出しをサブシェルで独立実行し、in-memory連想配列を
# 都度使い捨てることで「monitor再起動」相当(durable markerファイルのみが記憶を持つ)を再現する
for i in 1 2 3; do
    ( run_one_cycle )
done

cat "$TMP_ROOT/monitor.log"
cat "$TMP_ROOT/inbox_calls.log"
MSG_COUNT=$(wc -l < "$TMP_ROOT/inbox_calls.log")
echo "MSG_COUNT=$MSG_COUNT"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MSG_COUNT=1"* ]]
    [[ "$(echo "$output" | grep -c "KARO-PENDING-DEDUPE:")" -eq 2 ]]
}

@test "check_inbox_renudge: a previously notified generation stays deduped across A to A+B to A vibration" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
export SHOGUN_STATE_DIR="$TMP_ROOT/state"
mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/queue/inbox" "$TMP_ROOT/queue/archive/cmds" "$TMP_ROOT/queue/reports" "$TMP_ROOT/scripts" "$SHOGUN_STATE_DIR"
printf "messages: []\n" > "$TMP_ROOT/queue/inbox/karo.yaml"
printf "messages: []\n" > "$TMP_ROOT/queue/inbox/gunshi.yaml"
cat > "$TMP_ROOT/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo CALLED >> "$TMP_ROOT/inbox_calls.log"
exit 0
STUBEOF
chmod +x "$TMP_ROOT/scripts/inbox_write.sh"

run_one_cycle() {
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    unset NINJA_MONITOR_LIB_ONLY
    SCRIPT_DIR="$TMP_ROOT"
    LOG="$TMP_ROOT/monitor.log"
    NINJA_NAMES=()
    KARO_PANE="shogun:agents.1"
    declare -A RENUDGE_FINGERPRINT RENUDGE_COUNT RENUDGE_LAST_SEND
    log() { echo "$1" >> "$LOG"; }
    check_idle() { return 0; }
    safe_send_keys_atomic() { return 0; }
    check_inbox_renudge
}

# A: kotaro pending
cat > "$TMP_ROOT/queue/tasks/kotaro.yaml" <<EOF
task:
  status: failed
  parent_cmd: cmd_vibration_a
  task_id: cmd_vibration_a_full
EOF
( run_one_cycle )

# A+B: kagemaru pending追加
cat > "$TMP_ROOT/queue/tasks/kagemaru.yaml" <<EOF
task:
  status: done
  parent_cmd: cmd_vibration_b
  task_id: cmd_vibration_b_full
EOF
( run_one_cycle )

# Aへ復帰: kagemaru review完了
rm -f "$TMP_ROOT/queue/tasks/kagemaru.yaml"
( run_one_cycle )

MSG_COUNT=$(wc -l < "$TMP_ROOT/inbox_calls.log")
MARKER_LINES=$(wc -l < "$SHOGUN_STATE_DIR/karo_pending_work_notice.tsv")
echo "MSG_COUNT=$MSG_COUNT"
echo "MARKER_LINES=$MARKER_LINES"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MSG_COUNT=2"* ]]
    [[ "$output" == *"MARKER_LINES=2"* ]]
}

# cmd_karo_hotfix_pending_work_generation_dedupe_202607121023 AC4: pending集合が変化(新規failed
# taskの追加)すれば新世代として即時再通知する。2種の新世代でそれぞれ1件、合計2件。
@test "check_inbox_renudge: a new pending generation (changed set) sends a fresh notification" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
export SHOGUN_STATE_DIR="$TMP_ROOT/state"
mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/queue/inbox" "$TMP_ROOT/queue/archive/cmds" "$TMP_ROOT/queue/reports" "$TMP_ROOT/scripts" "$SHOGUN_STATE_DIR"

cat > "$TMP_ROOT/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$TMP_ROOT/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$TMP_ROOT/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: failed
  parent_cmd: cmd_gen_a
  task_id: cmd_gen_a_full
EOF

cat > "$TMP_ROOT/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
printf "INBOX-WRITE-CALLED: to=%s type=%s from=%s msg=%s\n" "\$1" "\$3" "\$4" "\$2" >> "$TMP_ROOT/inbox_calls.log"
exit 0
STUBEOF
chmod +x "$TMP_ROOT/scripts/inbox_write.sh"

run_one_cycle() {
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    unset NINJA_MONITOR_LIB_ONLY
    SCRIPT_DIR="$TMP_ROOT"
    LOG="$TMP_ROOT/monitor.log"
    NINJA_NAMES=()
    KARO_PANE="shogun:agents.1"
    declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
    log() { echo "$1" >> "$LOG"; }
    check_idle() { return 0; }
    safe_send_keys_atomic() { return 0; }
    check_inbox_renudge
}

# 世代A(kagemaru failedのみ)
( run_one_cycle )

# 世代B: hanzoのfailedも追加(集合変化=新世代その1)
cat > "$TMP_ROOT/queue/tasks/hanzo.yaml" <<'"'"'EOF'"'"'
task:
  status: failed
  parent_cmd: cmd_gen_b
  task_id: cmd_gen_b_full
EOF
echo "initial report" > "$TMP_ROOT/queue/reports/hanzo_report_cmd_gen_b.yaml"
( run_one_cycle )

# 世代C: 集合(worker/task_id/parent_cmd/status)は不変のままreport内容だけ変化(新世代その2)
echo "updated report after further investigation" > "$TMP_ROOT/queue/reports/hanzo_report_cmd_gen_b.yaml"
( run_one_cycle )

cat "$TMP_ROOT/monitor.log"
cat "$TMP_ROOT/inbox_calls.log"
MSG_COUNT=$(wc -l < "$TMP_ROOT/inbox_calls.log")
echo "MSG_COUNT=$MSG_COUNT"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MSG_COUNT=3"* ]]
}

# 集合世代RC(2026-07-12 10:46家老指摘): pending集合が一度0件になった時にmarkerを残すと、
# 後で同一fingerprintの集合が再出現しても旧世代扱いされ通知が漏れる。0件も集合変化として扱い、
# markerをatomicにclearすることで、A通知→集合0→同じA再出現→2回目通知となることを検証する。
# 軍師review/GATE CLEARで一度解消した後にRC/reopenする実運用を守る。
@test "check_inbox_renudge: same fingerprint reappearing after the pending set goes empty notifies again" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
export SHOGUN_STATE_DIR="$TMP_ROOT/state"
mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/queue/inbox" "$TMP_ROOT/queue/archive/cmds" "$TMP_ROOT/queue/reports" "$TMP_ROOT/scripts" "$SHOGUN_STATE_DIR"

cat > "$TMP_ROOT/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$TMP_ROOT/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF

cat > "$TMP_ROOT/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "CALLED" >> "$TMP_ROOT/inbox_calls.log"
exit 0
STUBEOF
chmod +x "$TMP_ROOT/scripts/inbox_write.sh"

run_one_cycle() {
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    unset NINJA_MONITOR_LIB_ONLY
    SCRIPT_DIR="$TMP_ROOT"
    LOG="$TMP_ROOT/monitor.log"
    NINJA_NAMES=()
    KARO_PANE="shogun:agents.1"
    declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
    log() { echo "$1" >> "$LOG"; }
    check_idle() { return 0; }
    safe_send_keys_atomic() { return 0; }
    check_inbox_renudge
}

TASK_CONTENT=$(cat <<'"'"'EOF'"'"'
task:
  status: failed
  parent_cmd: cmd_reopen_a
  task_id: cmd_reopen_a_full
EOF
)

# 世代A登場 → 通知1件目
echo "$TASK_CONTENT" > "$TMP_ROOT/queue/tasks/kagemaru.yaml"
( run_one_cycle )

# 集合が0件になる(解消=軍師review/GATE CLEAR相当)
rm -f "$TMP_ROOT/queue/tasks/kagemaru.yaml"
( run_one_cycle )

# 同一世代Aが再出現(RC/reopen相当)→ markerがclearされていれば2回目の通知が飛ぶはず
echo "$TASK_CONTENT" > "$TMP_ROOT/queue/tasks/kagemaru.yaml"
( run_one_cycle )

cat "$TMP_ROOT/monitor.log"
cat "$TMP_ROOT/inbox_calls.log"
MSG_COUNT=$(wc -l < "$TMP_ROOT/inbox_calls.log")
echo "MSG_COUNT=$MSG_COUNT"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MSG_COUNT=2"* ]]
}

# cmd_karo_hotfix_pending_work_generation_dedupe_202607121023 AC3/AC4: 通知(inbox_write直接呼出)が
# 失敗してもoutbox永続化には成功する場合、世代markerは確定し重複enqueueは起きない。
# outbox自体は既存のflush_karo_notify_outboxが後続サイクルでretryする(exactly-once)。
@test "check_inbox_renudge: direct send failure with successful outbox enqueue marks the generation once" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$STATE_DIR"

cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: failed
  parent_cmd: cmd_direct_fail
  task_id: cmd_direct_fail_full
EOF

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
exit 1
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() { return 0; }

check_inbox_renudge
check_inbox_renudge
check_inbox_renudge

cat "$LOG"
OUTBOX_FILE="$STATE_DIR/karo_notify_outbox.tsv"
test -f "$OUTBOX_FILE"
OUTBOX_LINES=$(wc -l < "$OUTBOX_FILE")
echo "OUTBOX_LINES=$OUTBOX_LINES"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-INBOX"* ]]
    [[ "$output" == *"OUTBOX_LINES=1"* ]]
    [[ "$(echo "$output" | grep -c "KARO-PENDING-DEDUPE:")" -eq 2 ]]
    [[ "$output" != *"KARO-PENDING-INBOX-RETRY"* ]]
}

# cmd_karo_hotfix_pending_work_generation_dedupe_202607121023 AC3: direct送達失敗かつoutbox
# 永続化自体も失敗(STATE_DIRがディレクトリでない等)する異常系では世代markerを確定せず、
# 次サイクルで同一fpのまま再試行することを検証する。
@test "check_inbox_renudge: total notify failure (direct and outbox both fail) does not mark the generation and retries next cycle" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts"

# STATE_DIRをディレクトリではなくファイルにし、outbox永続化自体を失敗させる
touch "$TMP_ROOT/not_a_dir"
STATE_DIR="$TMP_ROOT/not_a_dir"

cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: failed
  parent_cmd: cmd_total_fail
  task_id: cmd_total_fail_full
EOF

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
exit 1
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() { return 0; }

check_inbox_renudge
check_inbox_renudge

cat "$LOG"
MARKER_FILE="$TMP_ROOT/not_a_dir/karo_pending_work_notice.tsv"
if [ -f "$MARKER_FILE" ]; then
    echo "MARKER_EXISTS"
else
    echo "MARKER_ABSENT"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-INBOX-RETRY"* ]]
    [[ "$(echo "$output" | grep -c "KARO-PENDING-INBOX:")" -eq 2 ]]
    [[ "$output" != *"KARO-PENDING-DEDUPE:"* ]]
    [[ "$output" == *"MARKER_ABSENT"* ]]
}

# karo実運転RC(2026-07-12 10:55): benchmark/repro scriptがSTATE_DIRをsource前に設定しており、
# ninja_monitor.sh L38のSTATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"がsource時に上書きして本物の
# /tmp/karo_pending_work_notice.tsv(稼働中monitorの実運用ファイル)を書換え/clearしてしまい、
# 実運転karoへ同一世代の重複通知を発生させた。STATE_DIRの上書きは「source前にexport
# SHOGUN_STATE_DIR、source後に反映確認」でのみ安全に隔離できることを恒久的にgateする。
@test "check_inbox_renudge: pending_work marker isolation never touches the real default STATE_DIR" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
LIVE_MARKER="/tmp/karo_pending_work_notice.tsv"
LIVE_BEFORE=$(md5sum "$LIVE_MARKER" 2>/dev/null || echo "ABSENT")

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
export SHOGUN_STATE_DIR="$TMP_ROOT/state"
mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/queue/inbox" "$TMP_ROOT/queue/archive/cmds" "$TMP_ROOT/queue/reports" "$TMP_ROOT/scripts" "$SHOGUN_STATE_DIR"

cat > "$TMP_ROOT/queue/inbox/karo.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$TMP_ROOT/queue/inbox/gunshi.yaml" <<'"'"'EOF'"'"'
messages: []
EOF
cat > "$TMP_ROOT/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: failed
  parent_cmd: cmd_isolation_guard
  task_id: cmd_isolation_guard_full
EOF

cat > "$TMP_ROOT/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
exit 0
STUBEOF
chmod +x "$TMP_ROOT/scripts/inbox_write.sh"

export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

# source後、実際に隔離先へ反映されていることをassert(本テストの存在意義)
test "$STATE_DIR" = "$SHOGUN_STATE_DIR"

SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() { return 0; }

check_inbox_renudge
check_inbox_renudge

# 集合0件化 → markerクリア相当のcode pathも隔離下で実行
rm -f "$TMP_ROOT/queue/tasks/kagemaru.yaml"
check_inbox_renudge

cat "$LOG"
test -f "$SHOGUN_STATE_DIR/karo_pending_work_notice.tsv" && echo "ISOLATED_MARKER_TOUCHED" || echo "ISOLATED_MARKER_ABSENT_OR_CLEARED"

LIVE_AFTER=$(md5sum "$LIVE_MARKER" 2>/dev/null || echo "ABSENT")
if [ "$LIVE_BEFORE" = "$LIVE_AFTER" ]; then
    echo "LIVE_MARKER_UNCHANGED"
else
    echo "LIVE_MARKER_CHANGED: before=$LIVE_BEFORE after=$LIVE_AFTER"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LIVE_MARKER_UNCHANGED"* ]]
    [[ "$output" != *"LIVE_MARKER_CHANGED"* ]]
}

# 正確性RC(2026-07-12 11:11家老指摘): 世代fingerprintの並びがqueue/tasks/*.yamlのglob順
# (localeのLC_COLLATE依存)に左右されると、同一の実pending集合でもtask作成順やlocale差で
# fpが変わりcanonical不変量が壊れる。同一の2件pending集合をtask作成順を入れ替えた2回の
# 独立run(各々別STATE_DIR)で比較し、fpが完全一致し通知が各回1件ずつ(重複判定にならない)
# ことを検証する。
@test "check_inbox_renudge: same pending set with reversed task-file creation order yields the identical canonical fingerprint" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"

run_with_creation_order() {
    local create_kagemaru_first="$1" out_var="$2"
    local TMP_ROOT
    TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
    export SHOGUN_STATE_DIR="$TMP_ROOT/state"
    mkdir -p "$TMP_ROOT/queue/tasks" "$TMP_ROOT/queue/inbox" "$TMP_ROOT/queue/archive/cmds" "$TMP_ROOT/queue/reports" "$TMP_ROOT/scripts" "$SHOGUN_STATE_DIR"

    cat > "$TMP_ROOT/queue/inbox/karo.yaml" <<EOF
messages: []
EOF
    cat > "$TMP_ROOT/queue/inbox/gunshi.yaml" <<EOF
messages: []
EOF
    cat > "$TMP_ROOT/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
exit 0
STUBEOF
    chmod +x "$TMP_ROOT/scripts/inbox_write.sh"

    # worker→内容の対応は固定(kagemaru=failed/cmd_order_stable、tobisaru=done/cmd_order_stable_2)。
    # 呼出し順だけを入れ替えて「task作成順」の影響有無を検証する(同一集合を保証するため)。
    write_kagemaru() {
        cat > "$TMP_ROOT/queue/tasks/kagemaru.yaml" <<EOF
task:
  status: failed
  parent_cmd: cmd_order_stable
  task_id: cmd_order_stable_full
EOF
    }
    write_tobisaru() {
        cat > "$TMP_ROOT/queue/tasks/tobisaru.yaml" <<EOF
task:
  status: done
  parent_cmd: cmd_order_stable_2
  task_id: cmd_order_stable_2_full
EOF
    }
    if [ "$create_kagemaru_first" = "1" ]; then
        write_kagemaru
        write_tobisaru
    else
        write_tobisaru
        write_kagemaru
    fi

    (
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        SCRIPT_DIR="$TMP_ROOT"
        LOG="$TMP_ROOT/monitor.log"
        NINJA_NAMES=()
        KARO_PANE="shogun:agents.1"
        declare -A RENUDGE_FINGERPRINT RENUDGE_COUNT RENUDGE_LAST_SEND
        log() { :; }
        check_idle() { return 0; }
        safe_send_keys_atomic() { return 0; }
        check_inbox_renudge
    )

    printf -v "$out_var" "%s" "$(cat "$SHOGUN_STATE_DIR/karo_pending_work_notice.tsv" 2>/dev/null || echo MISSING)"
    rm -rf "$TMP_ROOT"
}

FP_A=""
FP_B=""
run_with_creation_order 1 FP_A
run_with_creation_order 0 FP_B

echo "FP_A=$FP_A"
echo "FP_B=$FP_B"
if [ "$FP_A" = "$FP_B" ] && [ "$FP_A" != "MISSING" ]; then
    echo "CANONICAL_FP_MATCH"
else
    echo "CANONICAL_FP_MISMATCH"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CANONICAL_FP_MATCH"* ]]
    [[ "$output" != *"CANONICAL_FP_MISMATCH"* ]]
}

@test "check_stall: repeated same-task stalls trigger stall_escalate with mandatory replacement" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"
export TEST_MESSAGES

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"
EOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: in_progress
  subtask_id: subtask_500_impl_stall_enforcement
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "in_progress" ;;
        subtask_id) echo "subtask_500_impl_stall_enforcement" ;;
        task_id) echo "" ;;
        progress_updated_at) echo "" ;;
        *) echo "${3:-}" ;;
    esac
}
cli_profile_get() {
    case "$2" in
        in_progress_stall_min) echo "1" ;;
        *) echo "" ;;
    esac
}

PANE_TARGETS[kagemaru]="shogun:2.5"
now=$(date +%s)
stall_key="kagemaru:subtask_500_impl_stall_enforcement"
STALL_THRESHOLD_MIN=1
STALL_COUNT["$stall_key"]=1
STALL_NOTIFIED["$stall_key"]=$((now - 301))
STALL_FIRST_SEEN[kagemaru]=$((now - 2 * 60))
check_stall kagemaru

cat "$TEST_MESSAGES"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo|stall_escalate|"* ]]
    [[ "$output" == *"差し替え必須"* ]]
}

@test "check_stall: stall alert includes pane head/tail excerpt" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A STALL_FIRST_SEEN STALL_NOTIFIED STALL_COUNT PANE_TARGETS
TEST_MESSAGES="$(mktemp)"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  status: assigned
  subtask_id: subtask_500_impl_stall_enforcement
EOF

log() { :; }
send_inbox_message() {
    local flattened="${2//$'\''\n'\''/<NL>}"
    echo "$1|$3|$flattened|${4:-ninja_monitor}" >> "$TEST_MESSAGES"
}
check_idle() { return 0; }
_pane_has_active_background_compute() { return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "assigned" ;;
        subtask_id) echo "subtask_500_impl_stall_enforcement" ;;
        task_id) echo "" ;;
        progress_updated_at) echo "" ;;
        *) echo "${3:-}" ;;
    esac
}
tmux() {
    case "$1" in
        capture-pane)
            printf "l1\nl2\nl3\nl4\nl5\nmid1\nmid2\nl8\nl9\nl10\nl11\nl12\n"
            ;;
        *) return 0 ;;
    esac
}
cli_profile_get() { echo ""; }

PANE_TARGETS[kagemaru]="shogun:2.5"
now=$(date +%s)
STALL_FIRST_SEEN[kagemaru]=$((now - 16 * 60))
check_stall kagemaru

cat "$TEST_MESSAGES"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"karo|stall_alert|"* ]]
    [[ "$output" == *"[pane head 5]<NL>l1<NL>l2<NL>l3<NL>l4<NL>l5"* ]]
    [[ "$output" == *"[pane tail 5]<NL>l8<NL>l9<NL>l10<NL>l11<NL>l12"* ]]
}

@test "handle_confirmed_idle: completed task clears matching stall tracking keys" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A PREV_STATE LAST_NOTIFIED LAST_CLEARED STALL_FIRST_SEEN STALL_NOTIFIED
declare -A STALL_COUNT PANE_TARGETS CLEAR_SKIP_COUNT POST_CLEAR_PENDING
declare -A AUTO_DEPLOY_DONE IDLE_NOTIFY_SENT
NEWLY_IDLE=()

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  task_id: cmd_2341_normal
  subtask_id: cmd_2341_normal
EOF

log() { echo "$1" >> "$LOG"; }
is_task_deployed() { return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "done" ;;
        task_id) echo "cmd_2341_normal" ;;
        subtask_id) echo "cmd_2341_normal" ;;
        *) echo "${3:-}" ;;
    esac
}
cli_profile_get() { echo "60"; }
get_context_pct() { echo "0"; }
cli_type() { echo "codex"; }
tmux() { echo ""; }
safe_send_clear() { return 0; }
can_send_clear_with_report_gate() { return 0; }

PANE_TARGETS[saizo]="shogun:2.6"
PREV_STATE[saizo]="busy"
STALL_FIRST_SEEN[saizo]=100
STALL_FIRST_SEEN[deploy_stall_saizo]=101
STALL_FIRST_SEEN["saizo:old_task"]=102
STALL_FIRST_SEEN[kagemaru]=200
STALL_COUNT["saizo:old_task"]=2
STALL_COUNT["saizo:cmd_2341_normal"]=1
STALL_COUNT["kagemaru:old_task"]=3

handle_confirmed_idle saizo

echo "FIRST_SAIZO=${STALL_FIRST_SEEN[saizo]:-missing}"
echo "FIRST_DEPLOY=${STALL_FIRST_SEEN[deploy_stall_saizo]:-missing}"
echo "FIRST_COMPOUND=${STALL_FIRST_SEEN[saizo:old_task]:-missing}"
echo "FIRST_OTHER=${STALL_FIRST_SEEN[kagemaru]:-missing}"
echo "COUNT_OLD=${STALL_COUNT[saizo:old_task]:-missing}"
echo "COUNT_CURRENT=${STALL_COUNT[saizo:cmd_2341_normal]:-missing}"
echo "COUNT_OTHER=${STALL_COUNT[kagemaru:old_task]:-missing}"
cat "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"FIRST_SAIZO=missing"* ]]
    [[ "$output" == *"FIRST_DEPLOY=missing"* ]]
    [[ "$output" == *"FIRST_COMPOUND=missing"* ]]
    [[ "$output" == *"FIRST_OTHER=200"* ]]
    [[ "$output" == *"COUNT_OLD=missing"* ]]
    [[ "$output" == *"COUNT_CURRENT=missing"* ]]
    [[ "$output" == *"COUNT_OTHER=3"* ]]
    [[ "$output" == *"STALL-TRACKING-CLEAR: saizo status=done first_seen=3 count=2"* ]]
}

# =============================================================================
# auto_deploy_done tests (merged from test_ninja_monitor_auto_deploy_done.bats)
# =============================================================================

@test "is_task_deployed: status=doneでもcheck_and_update_done_task経由でauto_deploy発火" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts"

declare -A AUTO_DEPLOY_DONE PANE_TARGETS UNCOMMITTED_BLOCK_SENT REPORT_GATE_SENT
TEST_LOG="$(mktemp)"
LOG="$TEST_LOG"
CALLED=0
PANE_TARGETS[saizo]=""
AUTO_DEPLOY_DONE["saizo:subtask_575_impl_a"]=""
UNCOMMITTED_BLOCK_SENT["saizo:cmd_575"]=""
REPORT_GATE_SENT["saizo:cmd_575"]=""

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  task_id: subtask_575_impl_a
  parent_cmd: cmd_575
EOF

log() { echo "$1" >> "$TEST_LOG"; }
check_and_update_done_task() { CALLED=$((CALLED + 1)); return 0; }
find_matching_report_file() { echo ""; return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "done" ;;
        task_id) echo "subtask_575_impl_a" ;;
        parent_cmd) echo "cmd_575" ;;
        *) echo "${3:-}" ;;
    esac
}
timeout() { echo "TIMEOUT:$*" >> "$TEST_LOG"; return 0; }

if is_task_deployed saizo; then
    echo "DEPLOYED=1"
else
    echo "DEPLOYED=0"
fi
sleep 0.05

if grep -q "TIMEOUT:30 bash $SCRIPT_DIR/scripts/auto_deploy_next.sh cmd_575 subtask_575_impl_a" "$TEST_LOG"; then
    echo "AUTO_DEPLOY_CALL=1"
else
    echo "AUTO_DEPLOY_CALL=0"
fi

echo "CALLED=$CALLED"
echo "AUTO_DEPLOY_KEY=${AUTO_DEPLOY_DONE[saizo:subtask_575_impl_a]:-0}"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPLOYED=0"* ]]
    [[ "$output" == *"AUTO_DEPLOY_CALL=1"* ]]
    [[ "$output" == *"CALLED=1"* ]]
    [[ "$output" == *"AUTO_DEPLOY_KEY=1"* ]]
}

@test "is_task_deployed: report gate notification sent still rechecks FAIL and blocks auto_deploy" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts/gates"

declare -A AUTO_DEPLOY_DONE PANE_TARGETS UNCOMMITTED_BLOCK_SENT REPORT_GATE_SENT
TEST_LOG="$(mktemp)"
LOG="$TEST_LOG"
PANE_TARGETS[saizo]=""
AUTO_DEPLOY_DONE["saizo:subtask_575_impl_a"]=""
UNCOMMITTED_BLOCK_SENT["saizo:cmd_575"]=""
REPORT_GATE_SENT["saizo:cmd_575"]="1"

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  task_id: subtask_575_impl_a
  parent_cmd: cmd_575
EOF

cat > "$SCRIPT_DIR/queue/reports/saizo_report_cmd_575.yaml" <<'"'"'EOF'"'"'
worker_id: saizo
task_id: subtask_575_impl_a
parent_cmd: cmd_575
status: done
verdict: ""
EOF

cat > "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" <<'"'"'EOF'"'"'
#!/bin/bash
echo "FAIL forced report gate"
exit 1
EOF
chmod +x "$SCRIPT_DIR/scripts/gates/gate_report_format.sh"

log() { echo "$1" >> "$TEST_LOG"; }
check_and_update_done_task() { return 0; }
yaml_field_get() {
    case "$2" in
        status) echo "done" ;;
        task_id) echo "subtask_575_impl_a" ;;
        parent_cmd) echo "cmd_575" ;;
        *) echo "${3:-}" ;;
    esac
}
timeout() { echo "TIMEOUT:$*" >> "$TEST_LOG"; return 0; }

if is_task_deployed saizo; then
    echo "DEPLOYED=1"
else
    echo "DEPLOYED=0"
fi
sleep 0.05

if grep -q "^TIMEOUT:" "$TEST_LOG"; then
    echo "AUTO_DEPLOY_CALL=1"
else
    echo "AUTO_DEPLOY_CALL=0"
fi
grep -q "REPORT-FORMAT-FAIL-RECHECK" "$TEST_LOG"
echo "RECHECK_LOG=1"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPLOYED=0"* ]]
    [[ "$output" == *"AUTO_DEPLOY_CALL=0"* ]]
    [[ "$output" == *"RECHECK_LOG=1"* ]]
}

@test "is_task_deployed: status=doneかつ未完了判定ならauto_deploy発火しない" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

declare -A AUTO_DEPLOY_DONE PANE_TARGETS
TEST_LOG="$(mktemp)"
LOG="$TEST_LOG"
CALLED=0
PANE_TARGETS[saizo]=""

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: done
  task_id: subtask_575_impl_a
  parent_cmd: cmd_575
EOF

log() { echo "$1" >> "$TEST_LOG"; }
check_and_update_done_task() { CALLED=$((CALLED + 1)); return 1; }
yaml_field_get() {
    case "$2" in
        status) echo "done" ;;
        *) echo "${3:-}" ;;
    esac
}
timeout() { echo "TIMEOUT:$*" >> "$TEST_LOG"; return 0; }

if is_task_deployed saizo; then
    echo "DEPLOYED=1"
else
    echo "DEPLOYED=0"
fi

if grep -q "^TIMEOUT:" "$TEST_LOG"; then
    echo "AUTO_DEPLOY_CALL=1"
else
    echo "AUTO_DEPLOY_CALL=0"
fi

echo "CALLED=$CALLED"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPLOYED=0"* ]]
    [[ "$output" == *"AUTO_DEPLOY_CALL=0"* ]]
    [[ "$output" == *"CALLED=1"* ]]
}

@test "auto_void_if_parent_cmd_completed: other ninja completed same parent_cmd resets task and notifies karo" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs"

declare -A PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"
LOG="$TEST_LOG"
PANE_TARGETS[saizo]="shogun:2.6"

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: assigned
  task_id: cmd_2682_exact
  parent_cmd: cmd_2682
  report_path: queue/reports/saizo_report_cmd_2682.yaml
  report_filename: saizo_report_cmd_2682.yaml
EOF

cat > "$SCRIPT_DIR/queue/reports/hayate_report_cmd_2682.yaml" <<'"'"'EOF'"'"'
worker_id: hayate
task_id: cmd_2682_exact
parent_cmd: cmd_2682
status: completed
verdict: PASS
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
safe_send_clear() { echo "CLEAR:$2:$3" >> "$TEST_LOG"; return 0; }
tmux() { return 0; }

auto_void_if_parent_cmd_completed saizo "${PANE_TARGETS[saizo]}" "TEST"

echo "STATUS=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" status)"
echo "REPORT_PATH=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" report_path)"
echo "REPORT_FILENAME=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" report_filename)"
if grep -qE "^[[:space:]]+parent_cmd:|^[[:space:]]+task_id:" "$SCRIPT_DIR/queue/tasks/saizo.yaml"; then
    echo "IDENTIFIERS_PRESENT=1"
else
    echo "IDENTIFIERS_PRESENT=0"
fi
cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=idle"* ]]
    [[ "$output" == *"REPORT_PATH="* ]]
    [[ "$output" == *"REPORT_FILENAME="* ]]
    [[ "$output" == *"IDENTIFIERS_PRESENT=0"* ]]
    [[ "$output" == *"karo|auto_void|"* ]]
    [[ "$output" == *"hayate_report_cmd_2682.yaml"* ]]
    [[ "$output" == *"CLEAR:saizo:AUTO-VOID(TEST)"* ]]
}

@test "auto_void_if_parent_cmd_completed: different task_id under same parent_cmd does not void split task" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs"

declare -A PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"
LOG="$TEST_LOG"
PANE_TARGETS[saizo]="shogun:2.6"

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: assigned
  task_id: cmd_2682_AC2
  parent_cmd: cmd_2682
  report_path: queue/reports/saizo_report_cmd_2682.yaml
  report_filename: saizo_report_cmd_2682.yaml
EOF

cat > "$SCRIPT_DIR/queue/reports/hayate_report_cmd_2682.yaml" <<'"'"'EOF'"'"'
worker_id: hayate
task_id: cmd_2682_AC1
parent_cmd: cmd_2682
status: completed
verdict: PASS
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
safe_send_clear() { echo "CLEAR:$2:$3" >> "$TEST_LOG"; return 0; }
tmux() { return 0; }

if auto_void_if_parent_cmd_completed saizo "${PANE_TARGETS[saizo]}" "TEST"; then
    echo "UNEXPECTED_VOID"
fi

echo "STATUS=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" status)"
echo "REPORT_PATH=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" report_path)"
cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"UNEXPECTED_VOID"* ]]
    [[ "$output" == *"STATUS=assigned"* ]]
    [[ "$output" == *"REPORT_PATH=queue/reports/saizo_report_cmd_2682.yaml"* ]]
    [[ "$output" != *"karo|auto_void|"* ]]
    [[ "$output" != *"CLEAR:saizo:AUTO-VOID(TEST)"* ]]
}

@test "auto_void_if_parent_cmd_completed: subtask_id is preferred over task_id for split task matching" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs"

declare -A PANE_TARGETS
TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"
LOG="$TEST_LOG"
PANE_TARGETS[saizo]="shogun:2.6"

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: assigned
  task_id: cmd_2682
  subtask_id: cmd_2682_AC1
  parent_cmd: cmd_2682
  report_path: queue/reports/saizo_report_cmd_2682.yaml
  report_filename: saizo_report_cmd_2682.yaml
EOF

cat > "$SCRIPT_DIR/queue/reports/hayate_report_cmd_2682.yaml" <<'"'"'EOF'"'"'
worker_id: hayate
task_id: cmd_2682_AC1
parent_cmd: cmd_2682
status: completed
verdict: PASS
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
safe_send_clear() { echo "CLEAR:$2:$3" >> "$TEST_LOG"; return 0; }
tmux() { return 0; }

auto_void_if_parent_cmd_completed saizo "${PANE_TARGETS[saizo]}" "TEST"

echo "STATUS=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" status)"
cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=idle"* ]]
    [[ "$output" == *"karo|auto_void|"* ]]
    [[ "$output" == *"hayate_report_cmd_2682.yaml"* ]]
    [[ "$output" == *"CLEAR:saizo:AUTO-VOID(TEST)"* ]]
}

@test "auto_void_if_parent_cmd_completed: own completed report does not void current task" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs"

TEST_LOG="$(mktemp)"
TEST_MESSAGES="$(mktemp)"
LOG="$TEST_LOG"

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  status: assigned
  task_id: cmd_2682_exact
  parent_cmd: cmd_2682
EOF

cat > "$SCRIPT_DIR/queue/reports/saizo_report_cmd_2682.yaml" <<'"'"'EOF'"'"'
worker_id: saizo
task_id: cmd_2682_exact
parent_cmd: cmd_2682
status: completed
verdict: PASS
EOF

log() { echo "$1" >> "$TEST_LOG"; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TEST_MESSAGES"; }
safe_send_clear() { echo "CLEAR:$2:$3" >> "$TEST_LOG"; return 0; }

if auto_void_if_parent_cmd_completed saizo "shogun:2.6" "TEST"; then
    echo "VOIDED=1"
else
    echo "VOIDED=0"
fi
echo "STATUS=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/saizo.yaml" status)"
cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"VOIDED=0"* ]]
    [[ "$output" == *"STATUS=assigned"* ]]
    [[ "$output" != *"auto_void"* ]]
    [[ "$output" != *"CLEAR:"* ]]
}

# =============================================================================
# snapshot_idle tests (merged from test_ninja_monitor_snapshot_idle.bats)
# =============================================================================

@test "write_karo_snapshot: assigned系タスクはidle行から除外し done/未配備のみ残す" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
KARO_SNAPSHOT_LOCK_FILE="$TMP_ROOT/karo_snapshot.lock"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

NINJA_NAMES=(sasuke kirimaru hayate saizo kagemaru)
declare -A PREV_STATE
PREV_STATE[sasuke]="idle"
PREV_STATE[kirimaru]="idle"
PREV_STATE[hayate]="idle"
PREV_STATE[saizo]="idle"
PREV_STATE[kagemaru]="idle"

get_latest_report_file() { return 1; }
log() { :; }

cat > "$SCRIPT_DIR/queue/tasks/sasuke.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_634
  status: in_progress
  project: infra
EOF

cat > "$SCRIPT_DIR/queue/tasks/kirimaru.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_635
  status: acknowledged
  project: infra
EOF

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_636
  status: assigned
  project: infra
EOF

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_637
  status: done
  project: infra
EOF

write_karo_snapshot

snapshot="$SCRIPT_DIR/queue/karo_snapshot.txt"
grep "^ninja|sasuke|cmd_634|in_progress|infra|CTX:" "$snapshot"
grep "^ninja|kirimaru|cmd_635|acknowledged|infra|CTX:" "$snapshot"
grep "^ninja|hayate|cmd_636|assigned|infra|CTX:" "$snapshot"
grep "^ninja|saizo|cmd_637|done|infra|CTX:" "$snapshot"
grep "^ninja|kagemaru|none|idle|none|CTX:" "$snapshot"
grep "^idle|saizo,kagemaru$" "$snapshot"
'
    [ "$status" -eq 0 ]
}

@test "main loop: snapshot fast path runs before slow maintenance checks" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
python3 - "$PROJECT_ROOT/scripts/ninja_monitor.sh" <<'"'"'PY'"'"'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
main = text[text.index("while true; do"):]
fast = main.index("refresh_karo_snapshot_fast_path")
slow = main.index("check_gate_improvement")
assert fast < slow, (fast, slow)
PY
'
    [ "$status" -eq 0 ]
}

@test "dashboard context warning signature is bounded by timeout" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
python3 - "$PROJECT_ROOT/scripts/ninja_monitor.sh" <<'"'"'PY'"'"'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
assert "CONTEXT_WARN_SIG_TIMEOUT=${CONTEXT_WARN_SIG_TIMEOUT:-20}" in text
assert "timeout \"$CONTEXT_WARN_SIG_TIMEOUT\" bash \"$SCRIPT_DIR/scripts/context_freshness_check.sh\" --dashboard-warnings" in text
PY
'
    [ "$status" -eq 0 ]
}

@test "write_karo_snapshot publishes atomically via temp file and mv" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
python3 - "$PROJECT_ROOT/scripts/ninja_monitor.sh" <<'"'"'PY'"'"'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
start = text.index("write_karo_snapshot() {")
end = text.index("refresh_karo_snapshot_fast_path() {")
body = text[start:end]
assert "mktemp \"${snapshot_file}.tmp.XXXXXX\"" in body
assert "} > \"$tmp_file\"; then" in body
assert "mv \"$tmp_file\" \"$snapshot_file\"" in body
assert "} > \"$snapshot_file\"" not in body
PY
'
    [ "$status" -eq 0 ]
}

@test "write_karo_snapshot initializes ninja names in lib-only mode" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

cat > "$SCRIPT_DIR/config/settings.yaml" <<'"'"'EOF'"'"'
cli:
  agents:
    hanzo:
      role: ninja
      japanese_name: 半蔵
EOF

cat > "$SCRIPT_DIR/queue/tasks/hanzo.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_700
  status: in_progress
  project: infra
EOF

unset NINJA_NAMES
get_latest_report_file() { return 1; }
log() { :; }

write_karo_snapshot
grep "^ninja|hanzo|cmd_700|in_progress|infra|CTX:" "$SCRIPT_DIR/queue/karo_snapshot.txt"
'
    [ "$status" -eq 0 ]
}

@test "write_karo_snapshot uses task status before nested training status" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

NINJA_NAMES=(kagemaru)
declare -A PREV_STATE
PREV_STATE[kagemaru]="idle"

get_latest_report_file() { return 1; }
log() { :; }

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_training_fixture_normal
  status: idle
  project: infra
training_proposal:
  status: completed
EOF

write_karo_snapshot
grep "^ninja|kagemaru|cmd_training_fixture_normal|idle|infra|CTX:" "$SCRIPT_DIR/queue/karo_snapshot.txt"
! grep "^ninja|kagemaru|cmd_training_fixture_normal|completed|" "$SCRIPT_DIR/queue/karo_snapshot.txt"
'
    [ "$status" -eq 0 ]
}

# test_necessity: done tasks with active reports are excluded from every idle
# availability view until the ordered archive terminal checkpoint is present.
@test "done task with unarchived report is unavailable until archive terminal checkpoint" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/gates" "$SCRIPT_DIR/logs" "$STATE_DIR"
printf "commands: []\n" > "$SCRIPT_DIR/queue/shogun_to_karo.yaml"

cat > "$SCRIPT_DIR/queue/tasks/blocked.yaml" <<'EOF'
task:
  task_id: task_blocked
  parent_cmd: cmd_blocked
  status: done
EOF
cat > "$SCRIPT_DIR/queue/tasks/archived.yaml" <<'EOF'
task:
  task_id: task_archived
  parent_cmd: cmd_archived
  status: done
EOF
cat > "$SCRIPT_DIR/queue/tasks/idle.yaml" <<'EOF'
task:
  task_id: task_idle
  status: idle
EOF
printf "status: completed\n" > "$SCRIPT_DIR/queue/reports/blocked_report_cmd_blocked.yaml"
printf "status: completed\n" > "$SCRIPT_DIR/queue/reports/archived_report_cmd_archived.yaml"
mkdir -p "$SCRIPT_DIR/queue/gates/cmd_archived"
: > "$SCRIPT_DIR/queue/gates/cmd_archived/archive.done"
printf "%s\n" "[cmd_complete] COMPLETE cmd_archived" > "$SCRIPT_DIR/queue/gates/cmd_archived/completion_tail.log"

NINJA_NAMES=(blocked archived idle)
declare -A PREV_STATE
PREV_STATE[blocked]=idle; PREV_STATE[archived]=idle; PREV_STATE[idle]=idle
get_context_pct() { echo 0; }
get_model_display_name() { echo GPT; }
get_latest_report_file() { return 1; }
log() { :; }

write_karo_snapshot
grep -q "^idle|archived,idle$" "$SCRIPT_DIR/queue/karo_snapshot.txt"
! grep -q "^idle|.*blocked" "$SCRIPT_DIR/queue/karo_snapshot.txt"

pipeline=$(get_idle_pipeline_state)
[ "$pipeline" = "3|1|0" ]
printf "snapshot_idle=archived,idle pipeline=%s blocked=1 archived=0\n" "$pipeline"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"snapshot_idle=archived,idle pipeline=3|1|0 blocked=1 archived=0"* ]]
}

@test "check_and_update_done_task: flat task YAML uses yaml_field_set root fallback for completed_at" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts/lib"
ln -s "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<'"'"'EOF'"'"'
parent_cmd: cmd_flat_done
task_id: task_flat_done
status: in_progress
EOF

cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_flat_done.yaml" <<'"'"'EOF'"'"'
parent_cmd: cmd_flat_done
task_id: task_flat_done
status: done
EOF

log() { echo "$1" >> "$LOG"; }

check_and_update_done_task kagemaru

grep -q "^status: done$" "$SCRIPT_DIR/queue/tasks/kagemaru.yaml"
grep -q "^completed_at:" "$SCRIPT_DIR/queue/tasks/kagemaru.yaml"
! grep -q "^task:" "$SCRIPT_DIR/queue/tasks/kagemaru.yaml"
! grep -q "FLAT-YAML-FALLBACK" "$LOG"
'
    [ "$status" -eq 0 ]
}

@test "check_obsidian_candidate_promotion: threshold超過で自動昇格、未満でskip" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
OBSIDIAN_PROMOTE_INTERVAL=60
OBSIDIAN_PROMOTE_THRESHOLD=5
OBSIDIAN_PROMOTE_STATE_FILE="$STATE_DIR/shogun_obsidian_promote.last"
OBSIDIAN_PROMOTE_LOG="$TMP_ROOT/logs/obsidian_promote.log"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/data" "$STATE_DIR"

# SQLiteテストDB作成: candidate=3 (閾値5未満)
sqlite3 "$SCRIPT_DIR/data/multi_agent_shogun_memory.db" "
CREATE TABLE events (id TEXT PRIMARY KEY, state TEXT);
INSERT INTO events VALUES ('"'"'e1'"'"', '"'"'obsidian_candidate'"'"');
INSERT INTO events VALUES ('"'"'e2'"'"', '"'"'obsidian_candidate'"'"');
INSERT INTO events VALUES ('"'"'e3'"'"', '"'"'obsidian_candidate'"'"');
"

cat > "$SCRIPT_DIR/scripts/obsidian_promote_finalize.sh" <<'"'"'FEOF'"'"'
#!/usr/bin/env bash
echo "finalize_called" >> "$OBSIDIAN_PROMOTE_LOG"
FEOF
chmod +x "$SCRIPT_DIR/scripts/obsidian_promote_finalize.sh"
export OBSIDIAN_PROMOTE_LOG

log() { echo "$1" >> "$LOG"; }

# 1回目: 閾値未満→skip
check_obsidian_candidate_promotion
echo "--- after first call (below threshold) ---"
cat "$LOG"
grep -q "OBSIDIAN-PROMOTE: candidates=3 (threshold=5), skip" "$LOG"
[ ! -f "$OBSIDIAN_PROMOTE_LOG" ]

# state_fileリセット(interval bypass)
rm -f "$OBSIDIAN_PROMOTE_STATE_FILE"

# candidate追加→閾値超過(5件)
sqlite3 "$SCRIPT_DIR/data/multi_agent_shogun_memory.db" "
INSERT INTO events VALUES ('"'"'e4'"'"', '"'"'obsidian_candidate'"'"');
INSERT INTO events VALUES ('"'"'e5'"'"', '"'"'obsidian_candidate'"'"');
"

# 2回目: 閾値超過→auto-promote(バックグラウンド実行のため完了をwaitで待つ)
check_obsidian_candidate_promotion
wait
echo "--- after second call (above threshold) ---"
cat "$LOG"
grep -q "OBSIDIAN-PROMOTE: candidates=5 >= threshold=5, auto-promoting" "$LOG"
grep -q "OBSIDIAN-PROMOTE: auto-promote done" "$LOG"
grep -q "finalize_called" "$OBSIDIAN_PROMOTE_LOG"
'
    [ "$status" -eq 0 ]
}

@test "check_obsidian_candidate_promotion: interval内は2回目skip" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
OBSIDIAN_PROMOTE_INTERVAL=86400
OBSIDIAN_PROMOTE_THRESHOLD=1
OBSIDIAN_PROMOTE_STATE_FILE="$STATE_DIR/shogun_obsidian_promote.last"
OBSIDIAN_PROMOTE_LOG="$TMP_ROOT/logs/obsidian_promote.log"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/data" "$STATE_DIR"

sqlite3 "$SCRIPT_DIR/data/multi_agent_shogun_memory.db" "
CREATE TABLE events (id TEXT PRIMARY KEY, state TEXT);
INSERT INTO events VALUES ('"'"'e1'"'"', '"'"'obsidian_candidate'"'"');
INSERT INTO events VALUES ('"'"'e2'"'"', '"'"'obsidian_candidate'"'"');
"

cat > "$SCRIPT_DIR/scripts/obsidian_promote_finalize.sh" <<'"'"'FEOF'"'"'
#!/usr/bin/env bash
echo "finalize_called" >> "$OBSIDIAN_PROMOTE_LOG"
FEOF
chmod +x "$SCRIPT_DIR/scripts/obsidian_promote_finalize.sh"
export OBSIDIAN_PROMOTE_LOG

log() { echo "$1" >> "$LOG"; }

# 1回目: 実行される(バックグラウンド実行のため完了をwaitで待つ)
check_obsidian_candidate_promotion
wait
count1=$(grep -c "finalize_called" "$OBSIDIAN_PROMOTE_LOG" 2>/dev/null || echo 0)
[ "$count1" -eq 1 ]

# 2回目: interval内→skip（finalize呼ばれない）
check_obsidian_candidate_promotion
wait
count2=$(grep -c "finalize_called" "$OBSIDIAN_PROMOTE_LOG" 2>/dev/null || echo 0)
[ "$count2" -eq 1 ]
'
    [ "$status" -eq 0 ]
}

# test_necessity: obsidian昇格の同期実行が監視ループを最大promote_timeout秒ブロックし、
# dead-pane検知等の後続監視サイクルを遅延させない不変量を守る。同期timeout 120により
# 2026-07-28 16:12:22の忍者6名dead検知が16:15まで(124秒)遅延した実障害の再発防止。
@test "check_obsidian_candidate_promotion returns immediately and enforces single-flight while finalize stalls" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT"; mkdir -p "$TMP_ROOT"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
OBSIDIAN_PROMOTE_INTERVAL=0
OBSIDIAN_PROMOTE_THRESHOLD=1
OBSIDIAN_PROMOTE_TIMEOUT=1
OBSIDIAN_PROMOTE_STATE_FILE="$STATE_DIR/last"
OBSIDIAN_PROMOTE_LOG="$TMP_ROOT/logs/obsidian_promote.log"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/data" "$STATE_DIR"

sqlite3 "$SCRIPT_DIR/data/multi_agent_shogun_memory.db" "
CREATE TABLE events (id TEXT PRIMARY KEY, state TEXT);
INSERT INTO events VALUES ('"'"'e1'"'"', '"'"'obsidian_candidate'"'"');
"

# finalizeが120秒スリープしても、check_obsidian_candidate_promotion自体は
# 即座に戻り、後続のdead-pane検知等の監視サイクルをブロックしないことを検証する
# (cmd_karo_hotfix_reflux_backlink_external_source_20260728 追加指示: 16:12:22の
# 忍者6名dead検知が124秒遅延した根因の再現・恒久防止)。
printf %s\\n "#!/usr/bin/env bash" "sleep 120" > "$SCRIPT_DIR/scripts/obsidian_promote_finalize.sh"
chmod +x "$SCRIPT_DIR/scripts/obsidian_promote_finalize.sh"
export OBSIDIAN_PROMOTE_LOG

log() { printf "%s\n" "$1" >> "$LOG"; }

start=$EPOCHREALTIME
check_obsidian_candidate_promotion
check_obsidian_candidate_promotion
elapsed=$(awk -v a="$start" -v b="$EPOCHREALTIME" "BEGIN {print b-a}")
awk -v e="$elapsed" "BEGIN {exit !(e < 0.5)}"
grep -q "already running, skip" "$LOG"
wait
printf "elapsed_under_0.5s=true single_flight_skip=confirmed\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"elapsed_under_0.5s=true single_flight_skip=confirmed"* ]]
}

# test_necessity: idle継続の一次判定、明示的次標的のOPEN集合、掲示板宣言を同一世代へ
# 固定し、3分到達後のpending_work ALERTを一世代一回にする不変量を守る。
@test "check_idle_backlog_alert: stale idle属性でもWorking 3/3は警告せず真idleは1通" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT/idle-backlog-pane-reconcile"
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
cat > "$SCRIPT_DIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: newest
  content: "次標的: cmd_open"
EOF

NINJA_NAMES=(kagemaru hanzo kotaro); declare -A PANE_TARGETS
PANE_TARGETS[kagemaru]=pane-kagemaru
PANE_TARGETS[hanzo]=pane-hanzo
PANE_TARGETS[kotaro]=pane-kotaro
PANE_MODE=busy
_agent_state_has_busy_subprocess() { return 1; }
tmux() {
    local command="${1:-}" target="" format=""
    shift || true
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -t) target="$2"; shift 2 ;;
            -p)
                if [ "$command" = display-message ]; then
                    format="$2"; shift 2
                else
                    shift
                fi
                ;;
            *) shift ;;
        esac
    done
    case "$command:$format" in
        display-message:\#\{@agent_state\}) printf "idle\\n" ;;
        display-message:\#\{@last_active\}) printf "\\n" ;;
        display-message:\#\{pane_id\}) printf "%s\\n" "$target" ;;
        *)
            if [ "$command" = capture-pane ]; then
                if [ "$PANE_MODE" = busy ]; then printf "• Working (test)\\n"; else printf "❯\\n"; fi
            fi
            ;;
    esac
}
list_pending_cmds_cached() { printf "%s\\n" "cmd_open|2026-08-10T22:00:00||"; }
find_deployed_task_status() { return 1; }
find_closed_parent_cmd_status() { return 1; }
notify_karo_durable() { printf "%s\\n" "$3" >> "$TMP_ROOT/messages.log"; return 0; }
log() { printf "%s\\n" "$1" >> "$LOG"; }

# AC2 busy fixture: all 3 panes render Working despite stale idle attributes.
IDLE_BACKLOG_ALERT_NOW=1000; check_idle_backlog_alert
IDLE_BACKLOG_ALERT_NOW=1180; check_idle_backlog_alert
busy_alerts=$(test -f "$TMP_ROOT/messages.log" && wc -l < "$TMP_ROOT/messages.log" || printf "0")
test "$(printf "%s" "$busy_alerts" | tr -d " ")" -eq 0
busy_false_positives=0

# AC2 true-idle fixture: one alert at threshold and no duplicate next cycle.
PANE_MODE=idle
rm -f "$STATE_DIR"/karo_idle_backlog_since.tsv "$STATE_DIR"/karo_idle_backlog_generation.tsv "$STATE_DIR"/karo_idle_backlog_last_alert.epoch "$TMP_ROOT/messages.log"
IDLE_BACKLOG_ALERT_NOW=2000; check_idle_backlog_alert
IDLE_BACKLOG_ALERT_NOW=2180; check_idle_backlog_alert
IDLE_BACKLOG_ALERT_NOW=2181; check_idle_backlog_alert
test "$(wc -l < "$TMP_ROOT/messages.log" | tr -d " ")" -eq 1
true_idle_alerts=1
duplicate_alerts=0
failures=0
skips=0
printf "busy3of3=%s busy_false_positives=%s true_idle_alerts=%s duplicate_alerts=%s failures=%s skips=%s\\n" \
    3 "$busy_false_positives" "$true_idle_alerts" "$duplicate_alerts" "$failures" "$skips"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"busy3of3=3 busy_false_positives=0 true_idle_alerts=1 duplicate_alerts=0 failures=0 skips=0"* ]]
}

@test "check_idle_backlog_alert: 3分継続後にOPEN次標的を一世代一回だけ通知する" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT/idle-backlog-generation"
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
cat > "$SCRIPT_DIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: newest
  content: "次標的: cmd_open"
EOF

NINJA_NAMES=(n1); declare -A PANE_TARGETS
PANE_TARGETS[n1]=pane-n1
POLL_INTERVAL=20
check_idle() { return 0; }
list_pending_cmds_cached() {
    printf "%s\n" "cmd_open|2026-08-10T22:00:00||" "cmd_closed|2026-08-10T21:00:00||"
}
find_deployed_task_status() {
    [ "$1" = cmd_closed ] && printf "completed\n"
}
find_closed_parent_cmd_status() { return 1; }
notify_karo_durable() { printf "%s\n" "$3" >> "$TMP_ROOT/messages.log"; return 0; }
log() { printf "%s\n" "$1" >> "$LOG"; }

IDLE_BACKLOG_ALERT_NOW=1000; check_idle_backlog_alert
IDLE_BACKLOG_ALERT_NOW=1179; check_idle_backlog_alert
IDLE_BACKLOG_ALERT_NOW=1180; check_idle_backlog_alert
IDLE_BACKLOG_ALERT_NOW=1181; check_idle_backlog_alert

test "$(wc -l < "$TMP_ROOT/messages.log" | tr -d " ")" -eq 1
grep -q "掲示板宣言=cmd_open" "$TMP_ROOT/messages.log"
! grep -q "cmd_closed" "$TMP_ROOT/messages.log"
grep -q "poll_interval=20" "$LOG"
printf "alerts=1 threshold=180 poll=20 closed_suppressed=1\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"alerts=1 threshold=180 poll=20 closed_suppressed=1"* ]]
}

# test_necessity: idle不在・backlog不在・既配備taskを通知候補から除外し、条件が揃った
# 世代だけを通知することで、既配備済み誤警報を0件に固定する。
@test "check_idle_backlog_alert: idleなし・backlogなし・既配備は0通" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT/idle-backlog-filters"
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
NINJA_NAMES=(n1); declare -A PANE_TARGETS
PANE_TARGETS[n1]=pane-n1
IDLE_MODE=0; TASK_STATUS=in_progress; PENDING_MODE=open; DEPLOYED_MODE=0
check_idle() { [ "$IDLE_MODE" -eq 1 ]; }
yaml_field_get() { [ "$2" = status ] && printf "%s\n" "$TASK_STATUS"; }
list_pending_cmds_cached() {
    [ "$PENDING_MODE" = empty ] && return 0
    [ "$PENDING_MODE" = deployed ] && printf "%s\n" "cmd_deployed|2026-08-10T22:00:00||" ||
        printf "%s\n" "cmd_open|2026-08-10T22:00:00||"
}
find_deployed_task_status() {
    [ "$DEPLOYED_MODE" -eq 1 ] && printf "in_progress\n"
}
find_closed_parent_cmd_status() { return 1; }
notify_karo_durable() { printf "%s\n" "$3" >> "$TMP_ROOT/messages.log"; return 0; }
log() { printf "%s\n" "$1" >> "$LOG"; }

# idleなし、active task、backlogなし、既配備を各々1回ずつ確認する。
IDLE_BACKLOG_ALERT_NOW=1000; check_idle_backlog_alert
IDLE_MODE=1; check_idle_backlog_alert
TASK_STATUS=done; PENDING_MODE=empty; IDLE_BACKLOG_ALERT_NOW=1200; check_idle_backlog_alert
PENDING_MODE=deployed; DEPLOYED_MODE=1; IDLE_BACKLOG_ALERT_NOW=1300; check_idle_backlog_alert

# 最後にOPENかつ未配備だけを成立させ、idle継続180秒で1通だけ送る。
PENDING_MODE=open; DEPLOYED_MODE=0; IDLE_BACKLOG_ALERT_NOW=1480; check_idle_backlog_alert
test "$(wc -l < "$TMP_ROOT/messages.log" | tr -d " ")" -eq 1
grep -q "IDLE-BACKLOG-ALERT" "$LOG"
printf "alerts=1 idle_absent=0 backlog_absent=0 deployed_false_alert=0\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"alerts=1 idle_absent=0 backlog_absent=0 deployed_false_alert=0"* ]]
}

# test_necessity: backlog世代が変わっても直前通知からcooldown内は0通、cooldown後に
# 新世代だけを通知し、monitor周期内の重複通知を防ぐ不変量を守る。
@test "check_idle_backlog_alert: backlog新世代はcooldown後だけ通知する" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$NINJA_MONITOR_TEST_ROOT/idle-backlog-cooldown"
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; mkdir -p "$SCRIPT_DIR/queue" "$STATE_DIR"
NINJA_NAMES=(n1); declare -A PANE_TARGETS; PANE_TARGETS[n1]=pane-n1
PENDING_MODE=a
check_idle() { return 0; }
list_pending_cmds_cached() {
    if [ "$PENDING_MODE" = a ]; then printf "%s\n" "cmd_a|2026-08-10T22:00:00||"; else printf "%s\n" "cmd_b|2026-08-10T22:01:00||"; fi
}
find_deployed_task_status() { return 0; }
find_closed_parent_cmd_status() { return 1; }
notify_karo_durable() { printf "%s\n" "$3" >> "$TMP_ROOT/messages.log"; return 0; }
log() { :; }

IDLE_BACKLOG_ALERT_NOW=1000; check_idle_backlog_alert
IDLE_BACKLOG_ALERT_NOW=1180; check_idle_backlog_alert
PENDING_MODE=b; IDLE_BACKLOG_ALERT_NOW=1181; check_idle_backlog_alert
IDLE_BACKLOG_ALERT_NOW=1479; check_idle_backlog_alert
IDLE_BACKLOG_ALERT_NOW=1480; check_idle_backlog_alert
test "$(wc -l < "$TMP_ROOT/messages.log" | tr -d " ")" -eq 2
printf "alerts=2 same_generation=1 cooldown_suppressed=1\n"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"alerts=2 same_generation=1 cooldown_suppressed=1"* ]]
}
