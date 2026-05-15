#!/usr/bin/env bats
# test_ninja_monitor_stall.bats - ninja_monitor stall recovery + misc behavior tests
# Merged: auto_deploy_done + snapshot_idle tests

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
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
task_id: cmd_2682_first
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
cat "$TEST_MESSAGES"
cat "$TEST_LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS=idle"* ]]
    [[ "$output" == *"REPORT_PATH="* ]]
    [[ "$output" == *"REPORT_FILENAME="* ]]
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
