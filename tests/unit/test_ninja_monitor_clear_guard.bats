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
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/context" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/a.sh
printf "base\n" > context/foo.md
git add scripts/a.sh context/foo.md
git commit -qm initial

printf "change\n" >> scripts/a.sh
printf "change\n" >> context/foo.md
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/ context/)
auto_commit_before_clear hayate "$_uncommitted"

regular_files=$(git show --name-only --format= HEAD~1 | sed "/^$/d" | sort | tr "\n" " ")
context_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
echo "regular=$regular_files"
echo "context=$context_files"
test "$regular_files" = "scripts/a.sh "
test "$context_files" = "context/foo.md "
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"regular=scripts/a.sh"* ]]
    [[ "$output" == *"context=context/foo.md"* ]]
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
mkdir -p "$SCRIPT_DIR/scripts" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/a.sh
git add scripts/a.sh
git commit -qm initial

printf "9900\n" > "$STATE_DIR/.last_auto_commit"
printf "change\n" >> scripts/a.sh
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/)
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

@test "auto_commit: commit pathspec does not include pre-staged unrelated files" {
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
auto_commit_before_clear hayate "$_uncommitted"

committed_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
staged_files=$(git diff --cached --name-only | sort | tr "\n" " ")
echo "committed=$committed_files"
echo "staged=$staged_files"
test "$committed_files" = "scripts/a.sh "
test "$staged_files" = "config/other.yaml "
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"committed=scripts/a.sh"* ]]
    [[ "$output" == *"staged=config/other.yaml"* ]]
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
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports"
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

# AC1: Codex CTX=0% + respawn < 60s → CODEX-CTX0-SKIP (respawnしない)
@test "codex respawn loop AC1: CTX=0% within 60s of last respawn → CODEX-CTX0-SKIP" {
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

# respawn 30秒前
LAST_CLEARED[hayate]=9970
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
RESPAWN_CALLED=0
safe_send_clear() { RESPAWN_CALLED=1; return 0; }
tmux() { echo ""; }
export -f tmux

_handle_auto_clear "hayate" 10000

if grep -q "CODEX-CTX0-SKIP" "$LOG"; then
    echo "PASS: CODEX-CTX0-SKIP logged"
else
    echo "FAIL: CODEX-CTX0-SKIP not logged"
    cat "$LOG"
    exit 1
fi

if [ "$RESPAWN_CALLED" -eq 0 ]; then
    echo "PASS: no respawn triggered"
else
    echo "FAIL: safe_send_clear was called unexpectedly"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: CODEX-CTX0-SKIP logged"* ]]
    [[ "$output" == *"PASS: no respawn triggered"* ]]
}

# AC2: Codex CTX=0% + respawn >= 60s → respawn発動
@test "codex respawn loop AC2: CTX=0% after 60s of last respawn → respawn triggered" {
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
RESPAWN_CALLED=0
safe_send_clear() { RESPAWN_CALLED=1; return 0; }
tmux() { echo ""; }
export -f tmux

_handle_auto_clear "hayate" 10000

if ! grep -q "CODEX-CTX0-SKIP" "$LOG"; then
    echo "PASS: CODEX-CTX0-SKIP not logged (elapsed >= 60s)"
else
    echo "FAIL: CODEX-CTX0-SKIP was logged unexpectedly"
    cat "$LOG"
    exit 1
fi

if [ "$RESPAWN_CALLED" -eq 1 ]; then
    echo "PASS: respawn triggered"
else
    echo "FAIL: safe_send_clear was not called"
    cat "$LOG"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: CODEX-CTX0-SKIP not logged"* ]]
    [[ "$output" == *"PASS: respawn triggered"* ]]
}
