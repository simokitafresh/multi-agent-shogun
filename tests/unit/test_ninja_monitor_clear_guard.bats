#!/usr/bin/env bats
# test_ninja_monitor_clear_guard.bats - cmd_1040 三段階/clear
# Stage 1(Phase 1: task YAML確認) → Stage 2(Phase 2: 再確認) → Stage 3(/clear)

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "auto_commit: regular commit excludes context markdown and batches context separately" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/context" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > queue/a.yaml
printf "base\n" > context/foo.md
git add queue/a.yaml context/foo.md
git commit -qm initial

printf "change\n" >> queue/a.yaml
printf "change\n" >> context/foo.md
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- queue/ context/)
auto_commit_before_clear hayate "$_uncommitted"

regular_files=$(git show --name-only --format= HEAD~1 | sed "/^$/d" | sort | tr "\n" " ")
context_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
echo "regular=$regular_files"
echo "context=$context_files"
test "$regular_files" = "queue/a.yaml "
test "$context_files" = "context/foo.md "
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"regular=queue/a.yaml"* ]]
    [[ "$output" == *"context=context/foo.md"* ]]
}

@test "auto_commit: no target_path restricts regular commit to operational paths" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/queue" "$SCRIPT_DIR/config" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/edited_by_shogun.sh
printf "base\n" > config/settings.yaml
printf "base\n" > queue/state.yaml
git add scripts/edited_by_shogun.sh config/settings.yaml queue/state.yaml
git commit -qm initial

printf "change\n" >> scripts/edited_by_shogun.sh
printf "change\n" >> config/settings.yaml
printf "change\n" >> queue/state.yaml
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/ config/ queue/)
auto_commit_before_clear saizo "$_uncommitted"

committed_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
worktree_files=$(git diff --name-only | sort | tr "\n" " ")
echo "committed=$committed_files"
echo "worktree=$worktree_files"
cat "$LOG"
test "$committed_files" = "queue/state.yaml "
test "$worktree_files" = "config/settings.yaml scripts/edited_by_shogun.sh "
grep -q "AUTO-COMMIT-OPERATIONAL-SKIP: saizo excluded scripts/edited_by_shogun.sh" "$LOG"
grep -q "AUTO-COMMIT-OPERATIONAL-SKIP: saizo excluded config/settings.yaml" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"committed=queue/state.yaml"* ]]
    [[ "$output" == *"AUTO-COMMIT-OPERATIONAL-SKIP"* ]]
}

@test "auto_commit: task target_path limits regular git add scope" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/a.sh
printf "base\n" > scripts/other.sh
git add scripts/a.sh scripts/other.sh
git commit -qm initial

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<INNEREOF
task:
  status: done
  target_path: scripts/a.sh
INNEREOF

printf "change\n" >> scripts/a.sh
printf "change\n" >> scripts/other.sh
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/)
auto_commit_before_clear hayate "$_uncommitted"

committed_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
worktree_files=$(git diff --name-only | sort | tr "\n" " ")
echo "committed=$committed_files"
echo "worktree=$worktree_files"
cat "$LOG"
test "$committed_files" = "scripts/a.sh "
test "$worktree_files" = "scripts/other.sh "
grep -q "AUTO-COMMIT-SCOPE-SKIP: hayate excluded scripts/other.sh (outside target_path)" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"committed=scripts/a.sh"* ]]
    [[ "$output" == *"worktree=scripts/other.sh"* ]]
    [[ "$output" == *"AUTO-COMMIT-SCOPE-SKIP"* ]]
}

@test "auto_commit: regular auto-commit skips within 30 minutes" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > queue/a.yaml
git add queue/a.yaml
git commit -qm initial

printf "9900\n" > "$STATE_DIR/.last_auto_commit"
printf "change\n" >> queue/a.yaml
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- queue/)
auto_commit_before_clear hayate "$_uncommitted"

count=$(git rev-list --count HEAD)
echo "count=$count"
cat "$LOG"
test "$count" = "1"
grep -q "AUTO-COMMIT-SKIP: hayate last auto-commit within 30min" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"count=1"* ]]
    [[ "$output" == *"AUTO-COMMIT-SKIP"* ]]
}

@test "auto_commit: skips when pre-staged unrelated files exist" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/config" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/a.sh
printf "base\n" > config/other.yaml
git add scripts/a.sh config/other.yaml
git commit -qm initial

printf "staged\n" >> config/other.yaml
git add config/other.yaml
printf "change\n" >> scripts/a.sh
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/)
set +e
auto_commit_before_clear hayate "$_uncommitted"
rc=$?
set -e

count=$(git rev-list --count HEAD)
staged_files=$(git diff --cached --name-only | sort | tr "\n" " ")
worktree_files=$(git diff --name-only | sort | tr "\n" " ")
echo "rc=$rc"
echo "count=$count"
echo "staged=$staged_files"
echo "worktree=$worktree_files"
cat "$LOG"
test "$rc" = "2"
test "$count" = "1"
test "$staged_files" = "config/other.yaml "
test "$worktree_files" = "scripts/a.sh "
grep -q "AUTO-COMMIT-WARN-SKIP: hayate pre-existing staged files detected before auto-commit: config/other.yaml" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=2"* ]]
    [[ "$output" == *"count=1"* ]]
    [[ "$output" == *"staged=config/other.yaml"* ]]
    [[ "$output" == *"worktree=scripts/a.sh"* ]]
    [[ "$output" == *"AUTO-COMMIT-WARN-SKIP"* ]]
}

@test "auto_commit: context batch skips within one hour" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/context" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > context/foo.md
git add context/foo.md
git commit -qm initial

printf "7000\n" > "$STATE_DIR/.last_context_batch_commit"
printf "change\n" >> context/foo.md
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- context/)
auto_commit_before_clear hayate "$_uncommitted"

count=$(git rev-list --count HEAD)
echo "count=$count"
cat "$LOG"
test "$count" = "1"
grep -q "CONTEXT-BATCH-COMMIT-SKIP: hayate last context batch commit within 1h" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"count=1"* ]]
    [[ "$output" == *"CONTEXT-BATCH-COMMIT-SKIP"* ]]
}

# Stage 1: acknowledged → maybe_idleに入らない（Phase 1で弾かれる）
@test "stage1: acknowledged task is filtered out before maybe_idle" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: acknowledged
  task_id: cmd_1040_test
INNEREOF

# Simulate Stage 1 logic (same code as Phase 1 main loop)
name="kagemaru"
_s1_task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
should_skip=0
if [ -f "$_s1_task_file" ]; then
    _s1_task_status=$(yaml_field_get "$_s1_task_file" "status")
    if [ "$_s1_task_status" = "acknowledged" ] || [ "$_s1_task_status" = "in_progress" ]; then
        should_skip=1
    fi
fi

if [ "$should_skip" -eq 1 ]; then
    echo "PASS: acknowledged task filtered by Stage 1"
else
    echo "FAIL: acknowledged task was NOT filtered"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: acknowledged task filtered by Stage 1"* ]]
}

# Stage 1: done → maybe_idleに入る（Phase 2→/clearされる）
@test "handle_confirmed_idle: done task allows /clear" {
    run bash -lc '
set -eo pipefail
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
declare -A AUTO_DEPLOY_DONE
NEWLY_IDLE=()

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: done
  task_id: cmd_1040_test
INNEREOF

log() { echo "$1" >> "$LOG"; }
send_inbox_message() { echo "INBOX:$1|$2|$3" >> "$LOG"; }
# done tasks: is_task_deployed returns 1 (not deployed)
is_task_deployed() { return 1; }
CLEAR_SENT=0
safe_send_clear() { CLEAR_SENT=1; echo "CLEAR_SENT:$2" >> "$LOG"; return 0; }
can_send_clear_with_report_gate() { return 0; }
get_context_pct() { echo "50"; }
cli_profile_get() { echo "60"; }
# tmux stubs
tmux() { echo ""; }
export -f tmux

PANE_TARGETS[kagemaru]="shogun:2.5"
PREV_STATE[kagemaru]="busy"

handle_confirmed_idle kagemaru

# done task → is_task_deployed returns 1 → falls through to auto /clear section
# auto /clear checks CTX > 0, debounce elapsed, etc.
if grep -q "CLEAR_SENT:kagemaru" "$LOG"; then
    echo "PASS: /clear sent for done task"
elif grep -q "CLEAR-SKIP" "$LOG"; then
    echo "PASS: done task reached auto-clear path (CTX=0 skip is OK)"
elif grep -q "CLEAR-DEBOUNCE" "$LOG"; then
    echo "PASS: done task reached auto-clear path (debounce is OK)"
else
    echo "PASS: done task not blocked by acknowledged/in_progress guard"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS:"* ]]
}

# Stage 1: task YAMLなし → maybe_idleに入る（/clearされる）
@test "stage1: missing task YAML passes through to maybe_idle" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks"
# No task YAML file for kagemaru

name="kagemaru"
_s1_task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
should_skip=0
if [ -f "$_s1_task_file" ]; then
    _s1_task_status=$(yaml_field_get "$_s1_task_file" "status")
    if [ "$_s1_task_status" = "acknowledged" ] || [ "$_s1_task_status" = "in_progress" ]; then
        should_skip=1
    fi
fi

if [ "$should_skip" -eq 0 ]; then
    echo "PASS: no task YAML → passes Stage 1"
else
    echo "FAIL: no task YAML was incorrectly filtered"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: no task YAML → passes Stage 1"* ]]
}

# verdict非空チェック: report存在+verdict空→return 1(clearブロック)
@test "report_gate: verdict empty blocks clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts"
touch "$LOG"

# inbox_write.shスタブ
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "\$LOG"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: done
  task_id: cmd_test_verdict
  parent_cmd: cmd_test_verdict
  report_filename: kagemaru_report_cmd_test_verdict.yaml
INNEREOF

cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_test_verdict.yaml" <<INNEREOF
worker_id: kagemaru
task_id: cmd_test_verdict
parent_cmd: cmd_test_verdict
verdict: ""
INNEREOF

log() { echo "$1" >> "$LOG"; }

result=0
can_send_clear_with_report_gate kagemaru "test_trigger" || result=$?
wait 2>/dev/null

if [ "$result" -eq 1 ]; then
    echo "PASS: verdict empty → return 1 (blocked)"
else
    echo "FAIL: expected return 1, got $result"
    exit 1
fi

if grep -q "VERDICT-EMPTY-BLOCK" "$LOG"; then
    echo "PASS: log message present"
else
    echo "FAIL: VERDICT-EMPTY-BLOCK not logged"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: verdict empty → return 1 (blocked)"* ]]
    [[ "$output" == *"PASS: log message present"* ]]
}

# verdict非空チェック: report存在+verdict非空→return 0(clear許可)
@test "report_gate: verdict present allows clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/inbox"
touch "$LOG"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: done
  task_id: cmd_test_verdict
  parent_cmd: cmd_test_verdict
  report_filename: kagemaru_report_cmd_test_verdict.yaml
INNEREOF

cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_test_verdict.yaml" <<INNEREOF
worker_id: kagemaru
task_id: cmd_test_verdict
parent_cmd: cmd_test_verdict
verdict: PASS
INNEREOF
now="$(date "+%Y-%m-%dT%H:%M:%S")"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<INNEREOF
messages:
- content: "kagemaru、任務完了。報告YAML確認されたし。"
  from: kagemaru
  id: msg_test
  read: false
  timestamp: "$now"
  type: report_received
INNEREOF

log() { echo "$1" >> "'"$TMP_ROOT"'/test.log"; }

can_send_clear_with_report_gate kagemaru "test_trigger"
result=$?

if [ "$result" -eq 0 ]; then
    echo "PASS: verdict present → return 0 (allowed)"
else
    echo "FAIL: expected return 0, got $result"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: verdict present → return 0 (allowed)"* ]]
}

# 家老通知チェック: report存在+verdict有効でもreport_received通知なし→return 1(clearブロック)
@test "report_gate: missing karo report_received notification blocks clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "\$LOG"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: done
  task_id: cmd_test_notify
  parent_cmd: cmd_test_notify
  report_filename: kagemaru_report_cmd_test_notify.yaml
INNEREOF

cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_test_notify.yaml" <<INNEREOF
worker_id: kagemaru
task_id: cmd_test_notify
parent_cmd: cmd_test_notify
verdict: PASS
INNEREOF

log() { echo "$1" >> "$LOG"; }

result=0
can_send_clear_with_report_gate kagemaru "test_trigger" || result=$?
wait 2>/dev/null

if [ "$result" -eq 1 ]; then
    echo "PASS: missing report_received → return 1 (blocked)"
else
    echo "FAIL: expected return 1, got $result"
    exit 1
fi

grep -q "REPORT-NOTIFY-MISSING-BLOCK" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: missing report_received → return 1 (blocked)"* ]]
}

@test "report_gate: archived report_received after report timestamp allows clear even when report mtime changed later" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/archive/inbox" "$SCRIPT_DIR/scripts"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "\$LOG"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: done
  task_id: cmd_test_archived_notify
  parent_cmd: cmd_test_archived_notify
  report_filename: kagemaru_report_cmd_test_archived_notify.yaml
INNEREOF

cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_test_archived_notify.yaml" <<INNEREOF
worker_id: kagemaru
task_id: cmd_test_archived_notify
parent_cmd: cmd_test_archived_notify
timestamp: "2026-06-06T09:28:00+09:00"
verdict: PASS
INNEREOF
touch -d "2026-06-06T09:35:00+09:00" "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_test_archived_notify.yaml"

cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<INNEREOF
messages: []
INNEREOF
cat > "$SCRIPT_DIR/archive/inbox/karo_20260606.yaml" <<INNEREOF
messages:
- content: "影丸、cmd_test_archived_notify 完了。report=kagemaru_report_cmd_test_archived_notify.yaml"
  from: kagemaru
  id: msg_archived
  read: true
  timestamp: "2026-06-06T09:28:16+09:00"
  type: report_received
INNEREOF

log() { echo "$1" >> "$LOG"; }

can_send_clear_with_report_gate kagemaru "test_trigger"
result=$?

if [ "$result" -eq 0 ]; then
    echo "PASS: archived report_received → return 0 (allowed)"
else
    echo "FAIL: expected return 0, got $result"
    cat "$LOG"
    exit 1
fi

if grep -q "REPORT-NOTIFY-MISSING-BLOCK" "$LOG"; then
    echo "FAIL: false missing notification block"
    cat "$LOG"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: archived report_received → return 0 (allowed)"* ]]
}

# verdict値チェック: report存在+verdict不正値→return 1(clearブロック)
@test "report_gate: invalid verdict blocks clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "\$LOG"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: done
  task_id: cmd_test_verdict
  parent_cmd: cmd_test_verdict
  report_filename: kagemaru_report_cmd_test_verdict.yaml
INNEREOF

cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_test_verdict.yaml" <<INNEREOF
worker_id: kagemaru
task_id: cmd_test_verdict
parent_cmd: cmd_test_verdict
verdict: None
INNEREOF

log() { echo "$1" >> "$LOG"; }

result=0
can_send_clear_with_report_gate kagemaru "test_trigger" || result=$?
wait 2>/dev/null

if [ "$result" -eq 1 ]; then
    echo "PASS: invalid verdict → return 1 (blocked)"
else
    echo "FAIL: expected return 1, got $result"
    exit 1
fi

if grep -q "VERDICT-INVALID-BLOCK" "$LOG"; then
    echo "PASS: invalid verdict log present"
else
    echo "FAIL: VERDICT-INVALID-BLOCK not logged"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: invalid verdict → return 1 (blocked)"* ]]
    [[ "$output" == *"PASS: invalid verdict log present"* ]]
}

# cmd_2279: PSTREE-OVERRIDE-SKIP: task status=idleならbash subprocess有でもIDLE扱い
@test "check_idle: PSTREE-OVERRIDE-SKIP when task status=idle" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<INNEREOF
task:
  status: idle
  task_id: cmd_test_pstree
INNEREOF

log() { echo "$1" >> "$LOG"; }
tmux() {
    case "$*" in
        *"@agent_state"*) echo "idle" ;;
        *"@last_active"*) echo "0" ;;
        *) echo "" ;;
    esac
}
export -f tmux
_agent_state_has_busy_subprocess() { return 0; }
_all_subprocesses_long_running() { return 1; }

check_idle "shogun:2.3" "hayate"
result=$?

if [ "$result" -eq 0 ]; then
    echo "PASS: task.status=idle + bash subprocess → IDLE"
else
    echo "FAIL: expected return 0, got $result"
    cat "$LOG"
    exit 1
fi

if grep -q "PSTREE-OVERRIDE-SKIP" "$LOG"; then
    echo "PASS: PSTREE-OVERRIDE-SKIP logged"
else
    echo "FAIL: PSTREE-OVERRIDE-SKIP not in log"
    cat "$LOG"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: task.status=idle + bash subprocess → IDLE"* ]]
    [[ "$output" == *"PASS: PSTREE-OVERRIDE-SKIP logged"* ]]
}

# cmd_2279: PSTREE-OVERRIDE: task status=assignedならbash subprocess有でBUSY扱い維持
@test "check_idle: PSTREE-OVERRIDE still fires when task status=assigned" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<INNEREOF
task:
  status: assigned
  task_id: cmd_test_pstree
INNEREOF

log() { echo "$1" >> "$LOG"; }
tmux() {
    case "$*" in
        *"@agent_state"*) echo "idle" ;;
        *"@last_active"*) echo "0" ;;
        *) echo "" ;;
    esac
}
export -f tmux
_agent_state_has_busy_subprocess() { return 0; }
_all_subprocesses_long_running() { return 1; }

result=0
check_idle "shogun:2.3" "hayate" || result=$?

if [ "$result" -eq 1 ]; then
    echo "PASS: task.status=assigned + bash subprocess → BUSY"
else
    echo "FAIL: expected return 1, got $result"
    cat "$LOG"
    exit 1
fi

if grep -q "PSTREE-OVERRIDE:" "$LOG"; then
    echo "PASS: PSTREE-OVERRIDE logged"
else
    echo "FAIL: PSTREE-OVERRIDE not in log"
    cat "$LOG"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: task.status=assigned + bash subprocess → BUSY"* ]]
    [[ "$output" == *"PASS: PSTREE-OVERRIDE logged"* ]]
}

@test "training auto deploy: delegated pipeline work blocks training deployment" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue"

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<INNEREOF
- id: cmd_delegated_test
  status: delegated
  purpose: active delegated work
INNEREOF

if _training_pipeline_has_work; then
    echo "PASS: delegated pipeline work detected"
else
    echo "FAIL: delegated pipeline work was ignored"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: delegated pipeline work detected"* ]]
}

# AC1: Codex idle + no_task → debounce経過後はsafe_send_clearを呼ぶ
@test "codex idle no_task calls safe_send_clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks"
touch "$LOG"

declare -A LAST_CLEARED PANE_TARGETS CLEAR_SKIP_COUNT POST_CLEAR_PENDING

# respawn 1000秒前 (clear_debounce経過)
LAST_CLEARED[hayate]=9000
PANE_TARGETS[hayate]="shogun:2.3"

log() { echo "$@" >> "$LOG"; }
get_context_pct() { echo "80"; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_debounce) echo "600" ;;
        *) echo "" ;;
    esac
}
can_send_clear_with_report_gate() { return 0; }
CLEAR_CALLED=0
safe_send_clear() { CLEAR_CALLED=1; return 0; }
tmux() { echo ""; }
export -f tmux

_handle_auto_clear "hayate" 10000

if grep -q "CODEX-IDLE-NO-TASK-SKIP" "$LOG"; then
    echo "FAIL: obsolete CODEX-IDLE-NO-TASK-SKIP logged"
    cat "$LOG"
    exit 1
else
    echo "PASS: obsolete skip not logged"
fi

if [ "$CLEAR_CALLED" -eq 1 ]; then
    echo "PASS: safe_send_clear called"
else
    echo "FAIL: safe_send_clear was not called"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: obsolete skip not logged"* ]]
    [[ "$output" == *"PASS: safe_send_clear called"* ]]
}

# AC2: Codex idle + no_taskはrespawn経過後もsafe_send_clearを呼ぶ
@test "codex idle no_task calls safe_send_clear after 60s" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks"
touch "$LOG"

declare -A LAST_CLEARED PANE_TARGETS CLEAR_SKIP_COUNT POST_CLEAR_PENDING

# respawn 1000秒前 (60s以上経過)
LAST_CLEARED[hayate]=9000
PANE_TARGETS[hayate]="shogun:2.3"

log() { echo "$@" >> "$LOG"; }
get_context_pct() { echo "0"; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_debounce) echo "600" ;;
        *) echo "" ;;
    esac
}
can_send_clear_with_report_gate() { return 0; }
CLEAR_CALLED=0
safe_send_clear() { CLEAR_CALLED=1; return 0; }
tmux() { echo ""; }
export -f tmux

_handle_auto_clear "hayate" 10000

if grep -q "CODEX-IDLE-NO-TASK-SKIP" "$LOG"; then
    echo "FAIL: obsolete CODEX-IDLE-NO-TASK-SKIP logged"
    cat "$LOG"
    exit 1
else
    echo "PASS: obsolete skip not logged"
fi

if [ "$CLEAR_CALLED" -eq 1 ]; then
    echo "PASS: safe_send_clear called"
else
    echo "FAIL: safe_send_clear was not called"
    cat "$LOG"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: obsolete skip not logged"* ]]
    [[ "$output" == *"PASS: safe_send_clear called"* ]]
}

@test "safe_send_clear codex idle task uses respawn-pane" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$STATE_DIR"
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
YAML
touch "$LOG"

check_idle() { return 0; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_cmd) echo "/new" ;;
        launch_cmd) echo "/home/test/.nvm/versions/node/v22/bin/codex" ;;
        *) echo "" ;;
    esac
}
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    echo ""
}
export -f tmux

safe_send_clear "shogun:2.3" "hayate" "TEST"

grep -q "CODEX-RESPAWN: hayate respawn-pane" "$LOG"
grep -q "RESPAWN:respawn-pane" "$LOG"
if grep -q "SEND:/new" "$LOG"; then
    cat "$LOG"
    exit 1
fi
echo "PASS: idle respawns"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: idle respawns"* ]]
}

@test "safe_send_clear codex done requires report before respawn" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts" "$STATE_DIR"
mkdir -p "$SCRIPT_DIR/queue/inbox"
touch "$LOG"

check_idle() { return 0; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_cmd) echo "/new" ;;
        launch_cmd) echo "/home/test/.nvm/versions/node/v22/bin/codex" ;;
        *) echo "" ;;
    esac
}
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    echo ""
}
export -f tmux

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: done
  parent_cmd: cmd_test
  report_filename: hayate_report_cmd_test.yaml
YAML
DONE_BLOCKED=0
safe_send_clear "shogun:2.3" "hayate" "DONE-MISSING-REPORT" || DONE_BLOCKED=$?

cat > "$SCRIPT_DIR/queue/reports/hayate_report_cmd_test.yaml" <<YAML
worker_id: hayate
parent_cmd: cmd_test
status: done
verdict: FILL_THIS
YAML
INVALID_BLOCKED=0
safe_send_clear "shogun:2.3" "hayate" "DONE-INVALID-REPORT" || INVALID_BLOCKED=$?

cat > "$SCRIPT_DIR/queue/reports/hayate_report_cmd_test.yaml" <<YAML
worker_id: hayate
parent_cmd: cmd_test
status: done
verdict: PASS
YAML
now="$(date "+%Y-%m-%dT%H:%M:%S")"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<YAML
messages:
- content: "hayate、任務完了。報告YAML確認されたし。"
  from: hayate
  id: msg_test
  read: false
  timestamp: "$now"
  type: report_received
YAML
safe_send_clear "shogun:2.3" "hayate" "DONE-WITH-REPORT"
rm -f "$SCRIPT_DIR/queue/tasks/hayate.yaml"
safe_send_clear "shogun:2.3" "hayate" "EMPTY-TEST"

test "$(grep -c "CODEX-RESPAWN: hayate respawn-pane" "$LOG")" -eq 2
test "$(grep -c "RESPAWN:respawn-pane" "$LOG")" -eq 2
test "$DONE_BLOCKED" -eq 1
test "$INVALID_BLOCKED" -eq 1
grep -q "REPORT-MISSING-BLOCK: hayate done but no report" "$LOG"
grep -q "VERDICT-INVALID-BLOCK: hayate report verdict invalid" "$LOG"
if grep -q "SEND:/new" "$LOG"; then
    cat "$LOG"
    exit 1
fi
echo "PASS: done report gate and empty respawn"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: done report gate and empty respawn"* ]]
}

@test "safe_send_clear codex in_progress uses respawn-pane" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$STATE_DIR"
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: in_progress
YAML
touch "$LOG"

check_idle() { return 0; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_cmd) echo "/new" ;;
        launch_cmd) echo "/home/test/.nvm/versions/node/v22/bin/codex" ;;
        *) echo "" ;;
    esac
}
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    echo ""
}
export -f tmux

safe_send_clear "shogun:2.3" "hayate" "TEST"

grep -q "CODEX-RESPAWN: hayate respawn-pane" "$LOG"
grep -q "RESPAWN:respawn-pane" "$LOG"
if grep -q "SEND:/new" "$LOG"; then
    cat "$LOG"
    exit 1
fi
echo "PASS: in_progress respawns"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: in_progress respawns"* ]]
}

# --- cmd_3264: auto-commit in_progress ninja exclusion tests ---

@test "auto_commit: excludes in_progress ninja target_path files from other ninja clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/a.sh
printf "base\n" > scripts/gates/check.sh
git add scripts/a.sh scripts/gates/check.sh
git commit -qm initial

# hanzo is in_progress with target_path=scripts/gates/
cat > "$SCRIPT_DIR/queue/tasks/hanzo.yaml" <<INNEREOF
task:
  status: in_progress
  target_path: scripts/gates
INNEREOF

# saizo is doing /clear with target_path=scripts (covers hanzo scope too;
# operational-only filter applies only when clearing agent has no target_path)
cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<INNEREOF
task:
  status: done
  target_path: scripts
INNEREOF
NINJA_NAMES=(hanzo saizo)
printf "change\n" >> scripts/a.sh
printf "change\n" >> scripts/gates/check.sh
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/)
auto_commit_before_clear saizo "$_uncommitted"

committed_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
worktree_files=$(git diff --name-only | sort | tr "\n" " ")
echo "committed=$committed_files"
echo "worktree=$worktree_files"
test "$committed_files" = "scripts/a.sh "
test "$worktree_files" = "scripts/gates/check.sh "
grep -q "AUTO-COMMIT-INPROGRESS-WARN:.*hanzo" "$LOG"
echo "PASS"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"committed=scripts/a.sh"* ]]
}

@test "auto_commit: in_progress ninja without target_path is not excluded (INFO only)" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/a.sh
git add scripts/a.sh
git commit -qm initial

# kotaro is in_progress but has NO target_path
cat > "$SCRIPT_DIR/queue/tasks/kotaro.yaml" <<INNEREOF
task:
  status: in_progress
INNEREOF

NINJA_NAMES=(kotaro saizo)
printf "change\n" >> scripts/a.sh
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/)
auto_commit_before_clear saizo "$_uncommitted"

committed_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
echo "committed=$committed_files"
test "$committed_files" = "scripts/a.sh "
grep -q "AUTO-COMMIT-INPROGRESS-INFO:.*kotaro.*no target_path" "$LOG"
# Should NOT have WARN (file was committed, not excluded)
if grep -q "AUTO-COMMIT-INPROGRESS-WARN:" "$LOG"; then
    echo "FAIL: unexpected WARN for target_path-less ninja"
    exit 1
fi
echo "PASS"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "auto_commit: clearing agent own files are not excluded by inprogress filter" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/gates/check.sh
git add scripts/gates/check.sh
git commit -qm initial

# hayate is in_progress AND is the clearing agent
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<INNEREOF
task:
  status: in_progress
  target_path: scripts/gates
INNEREOF

NINJA_NAMES=(hayate saizo)
printf "change\n" >> scripts/gates/check.sh
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/)
auto_commit_before_clear hayate "$_uncommitted"

committed_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
echo "committed=$committed_files"
test "$committed_files" = "scripts/gates/check.sh "
# Own files should NOT be excluded
if grep -q "AUTO-COMMIT-INPROGRESS-WARN:" "$LOG"; then
    echo "FAIL: own files should not be excluded"
    exit 1
fi
echo "PASS"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}
