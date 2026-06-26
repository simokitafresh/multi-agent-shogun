#!/usr/bin/env bats
# test_ninja_monitor_stall.bats - ninja_monitor stall recovery + misc behavior tests
# Merged: auto_deploy_done + snapshot_idle tests

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
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

@test "check_undeployed_cmds: pending+delegated_at 10分超でntfy送信し重複通知しない" {
    DELEGATED_AT=$(date -d "11 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
DELEGATED_AT="'"$DELEGATED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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

@test "check_undeployed_cmds: 配備済み(status=delegated)なら通知しない" {
    DELEGATED_AT=$(date -d "20 minutes ago" "+%Y-%m-%dT%H:%M:%S")
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
DELEGATED_AT="'"$DELEGATED_AT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"

TEST_LOG="$(mktemp)"
TEST_NTFY="$(mktemp)"
export TEST_NTFY

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<EOF
commands:
  cmd_deployed:
    status: delegated
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

@test "speed training auto-pause when retrospective recurrence rate exceeds 10 percent" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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

@test "check_stall: same ninja x task re-notifies after 5-minute debounce" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

@test "count_unread_messages_cached: same cycle reuses count and next cycle refreshes" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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

@test "check_lesson_deprecation_candidates posts shogun bulletin and logs metrics" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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
printf "  SKIP: candidates-only mode (approval required before lesson_write.sh --retire)\n"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

@test "run_lock_cleanup deletes stale shogun locks with one configurable scan" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
LOG="$TMP_ROOT/monitor.log"
LOCK_CLEANUP_DIR="$TMP_ROOT/locks"
LOCK_CLEANUP_INTERVAL=3600
LAST_LOCK_CLEANUP=0
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

TMP_ROOT="$(mktemp -d)"
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

@test "build_pane_head_tail_excerpt filters blanks and keeps head tail in one pass" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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
    [[ "$output" == *"KARO-IDLE-CYCLE: All 2 ninjas idle/completed/done + pipeline empty"* ]]
    [[ "$output" == *"karo|karo_idle_cycle|全忍者idle+パイプライン空。改善サイクルを回せ。"* ]]
}

@test "check_shogun_idle_analysis_trigger sends after all idle and pipeline empty for 10 minutes" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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
    [[ "$output" == *"shogun_to_karo.yaml is 7 lines"* ]]
    [[ "$output" == *"ALERT: 2 completed cmds"* ]]
    [[ "$output" == *"AWK_CALLS=1"* ]]
}

@test "notify_idle_batch compacts pane evidence with one awk pass" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/scripts"

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

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() {
    echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"
    return 0
}
send_inbox_message() {
    printf "%s|%s|%s|%s\n" "$1" "$3" "$2" "${4:-ninja_monitor}" >> "$TMP_ROOT/inbox_messages.log"
    return 0
}

check_inbox_renudge

cat "$LOG"
cat "$TMP_ROOT/inbox_messages.log"
if [ -f "$TMP_ROOT/direct_nudge.log" ]; then
    cat "$TMP_ROOT/direct_nudge.log"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-INBOX"* ]]
    [[ "$output" == *"karo|pending_work|未処理の忍者done/failed報告"* ]]
    [[ "$output" != *"DIRECT_NUDGE:inbox0"* ]]
}

@test "check_inbox_renudge: reviewed done report does not create duplicate karo pending inbox" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"

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

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() {
    echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"
    return 0
}
send_inbox_message() {
    printf "%s|%s|%s|%s\n" "$1" "$3" "$2" "${4:-ninja_monitor}" >> "$TMP_ROOT/inbox_messages.log"
    return 0
}

check_inbox_renudge

cat "$LOG"
if [ -f "$TMP_ROOT/inbox_messages.log" ]; then
    cat "$TMP_ROOT/inbox_messages.log"
fi
if [ -f "$TMP_ROOT/direct_nudge.log" ]; then
    cat "$TMP_ROOT/direct_nudge.log"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-SKIP-REVIEWED: cmd_reviewed_done already has gunshi report review"* ]]
    [[ "$output" != *"KARO-PENDING-INBOX"* ]]
    [[ "$output" != *"pending_work"* ]]
    [[ "$output" != *"DIRECT_NUDGE:inbox0"* ]]
}

@test "check_inbox_renudge: gate CLEAR done task does not create duplicate karo pending inbox" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"

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

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() {
    echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"
    return 0
}
send_inbox_message() {
    printf "%s|%s|%s|%s\n" "$1" "$3" "$2" "${4:-ninja_monitor}" >> "$TMP_ROOT/inbox_messages.log"
    return 0
}

check_inbox_renudge

cat "$LOG"
if [ -f "$TMP_ROOT/inbox_messages.log" ]; then
    cat "$TMP_ROOT/inbox_messages.log"
fi
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

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/logs"

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

NINJA_NAMES=()
KARO_PANE="shogun:agents.1"
declare -A RENUDGE_FINGERPRINT RENDUDGE_COUNT RENUDGE_COUNT RENUDGE_LAST_SEND
log() { echo "$1" >> "$LOG"; }
check_idle() { return 0; }
safe_send_keys_atomic() {
    echo "DIRECT_NUDGE:$2" >> "$TMP_ROOT/direct_nudge.log"
    return 0
}
send_inbox_message() {
    printf "%s|%s|%s|%s\n" "$1" "$3" "$2" "${4:-ninja_monitor}" >> "$TMP_ROOT/inbox_messages.log"
    return 0
}

check_inbox_renudge

cat "$LOG"
if [ -f "$TMP_ROOT/inbox_messages.log" ]; then
    cat "$TMP_ROOT/inbox_messages.log"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"KARO-PENDING-SKIP-NO-PARENT-CMD"* ]]
    [[ "$output" != *"KARO-PENDING-INBOX"* ]]
    [[ "$output" != *"pending_work"* ]]
}

@test "check_stall: repeated same-task stalls trigger stall_escalate with mandatory replacement" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
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

@test "check_and_update_done_task: flat task YAML uses yaml_field_set root fallback for completed_at" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
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

TMP_ROOT="$(mktemp -d)"
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

# 2回目: 閾値超過→auto-promote
check_obsidian_candidate_promotion
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

TMP_ROOT="$(mktemp -d)"
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

# 1回目: 実行される
check_obsidian_candidate_promotion
count1=$(grep -c "finalize_called" "$OBSIDIAN_PROMOTE_LOG" 2>/dev/null || echo 0)
[ "$count1" -eq 1 ]

# 2回目: interval内→skip（finalize呼ばれない）
check_obsidian_candidate_promotion
count2=$(grep -c "finalize_called" "$OBSIDIAN_PROMOTE_LOG" 2>/dev/null || echo 0)
[ "$count2" -eq 1 ]
'
    [ "$status" -eq 0 ]
}
