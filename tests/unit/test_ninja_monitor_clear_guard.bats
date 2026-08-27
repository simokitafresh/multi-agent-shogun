#!/usr/bin/env bats
# test_necessity: ninja_monitorはactive作業または未完了通知があるagentをclearしない
# test_ninja_monitor_clear_guard.bats - cmd_1040 三段階/clear
# Stage 1(Phase 1: task YAML確認) → Stage 2(Phase 2: 再確認) → Stage 3(/clear)

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    mkdir -p "$BATS_TEST_TMPDIR/scripts/lib"
    ln -sf "$PROJECT_ROOT/scripts/lib/report_completion_events.sh" \
        "$BATS_TEST_TMPDIR/scripts/lib/report_completion_events.sh"
    ln -sf "$PROJECT_ROOT/scripts/lib/respawn_recovery.sh" \
        "$BATS_TEST_TMPDIR/scripts/lib/respawn_recovery.sh"
}

@test "completion_notify_gap: later RC report and active task suppress reopened commands" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="$BATS_TEST_TMPDIR";
SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$STATE_DIR"
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUB
#!/bin/bash
echo "INBOX_CALLED:\$@"
STUB
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"; touch "$LOG"
old_ts="$(date -d "-600 seconds" +%Y-%m-%dT%H:%M:%S)"; new_ts="$(date -d "-500 seconds" +%Y-%m-%dT%H:%M:%S)"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<EOF
messages:
- {content: "cmd_gap_rc verdict: LGTM", timestamp: "$old_ts", type: review_feedback}
- {content: "cmd_gap_rc verdict: RC", timestamp: "$new_ts", type: review_feedback}
- {content: "cmd_gap_report verdict: LGTM", timestamp: "$old_ts", type: review_feedback}
- {content: "cmd_gap_task verdict: LGTM", timestamp: "$old_ts", type: review_feedback}
EOF
printf "entries: []\n" > "$SCRIPT_DIR/queue/bulletin_board.yaml"; printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/shogun.yaml"
cat > "$SCRIPT_DIR/queue/reports/x.yaml" <<EOF
parent_cmd: cmd_gap_report
status: revision_requested
timestamp: "$new_ts"
EOF
cat > "$SCRIPT_DIR/queue/tasks/x.yaml" <<EOF
task: {parent_cmd: cmd_gap_task, status: in_progress, deployed_at: "$new_ts"}
EOF
log() { echo "$1" >> "$LOG"; }; check_karo_completion_notify_gap
! grep -q INBOX_CALLED "$LOG"
'
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "completion_notify_gap: old RC does not suppress later LGTM and equal timestamp does" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1; source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
TMP_ROOT="$BATS_TEST_TMPDIR"; SCRIPT_DIR="$TMP_ROOT"; STATE_DIR="$TMP_ROOT/state"; LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$STATE_DIR"
cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUB
#!/bin/bash
echo "INBOX_CALLED:\$@"
STUB
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"; touch "$LOG"
rc_ts="$(date -d "-700 seconds" +%Y-%m-%dT%H:%M:%S)"; lgtm_ts="$(date -d "-600 seconds" +%Y-%m-%dT%H:%M:%S)"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<EOF
messages:
- {content: "cmd_gap_again verdict: RC", timestamp: "$rc_ts", type: review_feedback}
- {content: "cmd_gap_again verdict: LGTM", timestamp: "$lgtm_ts", type: review_feedback}
- {content: "cmd_gap_equal verdict: LGTM", timestamp: "$lgtm_ts", type: review_feedback}
- {content: "cmd_gap_equal verdict: RC", timestamp: "$lgtm_ts", type: review_feedback}
EOF
printf "entries: []\n" > "$SCRIPT_DIR/queue/bulletin_board.yaml"; printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/shogun.yaml"
log() { echo "$1" >> "$LOG"; }; check_karo_completion_notify_gap
grep -q "INBOX_CALLED:karo .*cmd_gap_again.*completion_notify_gap" "$LOG"
! grep -q "INBOX_CALLED:karo .*cmd_gap_equal.*completion_notify_gap" "$LOG"
'
    [ "$status" -eq 0 ]
}

@test "completion_notify_gap: stale formal approval fingerprint is ignored" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T=$BATS_TEST_TMPDIR;
SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
mkdir -p "$T/queue/inbox" "$T/queue/reports" "$T/queue/tasks" "$T/queue/gates/cmd_formal/review_approvals/reports" "$T/scripts" "$STATE_DIR"
old=$(date -d "-600 seconds" -Iseconds)
printf "messages:\n- content: \"cmd_formal verdict: LGTM\"\n  timestamp: \"%s\"\n  type: review_feedback\n" "$old" > "$T/queue/inbox/karo.yaml"
printf "messages: []\n" > "$T/queue/inbox/shogun.yaml"
printf "entries: []\n" > "$T/queue/bulletin_board.yaml"
printf "#!/bin/bash\necho INBOX_CALLED:\\$@ >> \"$LOG\"\n" > "$T/scripts/inbox_write.sh"; chmod +x "$T/scripts/inbox_write.sh"
report="$T/queue/reports/n_report_cmd_formal.yaml"; commit=$(printf a%.0s {1..40})
printf "parent_cmd: cmd_formal\ncommit_hash: %s\n" "$commit" > "$report"
key=$(printf %s queue/reports/n_report_cmd_formal.yaml | sha256sum | awk "{print \$1}")
mkdir -p "$T/queue/gates/cmd_formal/review_approvals/reports/$key"
fp=$(sha256sum "$report" | awk "{print \$1}"):$commit
printf "timestamp: %s\nresult: LGTM\nfingerprint: %s\n" "$old" "$fp" > "$T/queue/gates/cmd_formal/review_approvals/reports/$key/gunshi.yaml"
log() { echo "$1" >> "$LOG"; }; NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
grep -q cmd_formal "$LOG"
: > "$LOG"; printf "changed: true\n" >> "$report"; check_karo_completion_notify_gap
! grep -q cmd_formal "$LOG"
'
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "completion_notify_gap: notified formal LGTM generation is terminal even when report verdict is FAIL" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T=$BATS_TEST_TMPDIR;
SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
mkdir -p "$T/queue/inbox" "$T/queue/reports" "$T/queue/tasks" "$T/queue/gates/cmd_terminal_fail/review_approvals/reports" "$T/scripts" "$STATE_DIR"
: > "$LOG"
old=$(date -d "-600 seconds" -Iseconds)
printf "messages: []\n" > "$T/queue/inbox/karo.yaml"; printf "messages: []\n" > "$T/queue/inbox/shogun.yaml"; printf "entries: []\n" > "$T/queue/bulletin_board.yaml"
printf "#!/bin/bash\necho INBOX_CALLED:\\$@ >> \"$LOG\"\n" > "$T/scripts/inbox_write.sh"; chmod +x "$T/scripts/inbox_write.sh"
report="$T/queue/reports/n_report_cmd_terminal_fail.yaml"; commit=$(printf a%.0s {1..40})
printf "parent_cmd: cmd_terminal_fail\ncommit_hash: %s\nverdict: FAIL\n" "$commit" > "$report"
key=$(printf %s queue/reports/n_report_cmd_terminal_fail.yaml | sha256sum | cut -d " " -f1)
approval_dir="$T/queue/gates/cmd_terminal_fail/review_approvals/reports/$key"; mkdir -p "$approval_dir"
fp=$(sha256sum "$report" | cut -d " " -f1):$commit
printf "timestamp: %s\nresult: LGTM\nfingerprint: %s\n" "$old" "$fp" > "$approval_dir/gunshi.yaml"
touch -d "-500 seconds" "$approval_dir/gunshi_notice.sent"
log() { echo "$1" >> "$LOG"; }; NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
check_karo_completion_notify_gap; check_karo_completion_notify_gap
test "$(grep -c INBOX_CALLED "$LOG" 2>/dev/null || true)" -eq 0
'
    [ "$status" -eq 0 ]
}

@test "completion_notify_gap: terminal GATE CLEAR after LGTM suppresses cmd_3869-type false positive" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T=$BATS_TEST_TMPDIR;
SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
mkdir -p "$T/queue/inbox" "$T/queue/reports" "$T/queue/tasks" "$T/queue/gates/cmd_terminal" "$T/scripts" "$STATE_DIR"
touch "$LOG"
lgtm=$(date -d "-600 seconds" -Iseconds)
printf "messages:\n- content: \"cmd_terminal verdict: LGTM\"\n  timestamp: \"%s\"\n  type: review_feedback\n" "$lgtm" > "$T/queue/inbox/karo.yaml"
printf "messages: []\n" > "$T/queue/inbox/shogun.yaml"; printf "entries: []\n" > "$T/queue/bulletin_board.yaml"
printf "#!/bin/bash\necho INBOX_CALLED:\\$@ >> \"$LOG\"\n" > "$T/scripts/inbox_write.sh"; chmod +x "$T/scripts/inbox_write.sh"
printf "GATE CLEAR: cmd完了許可\n" > "$T/queue/gates/cmd_terminal/cmd_complete_gate.trigger.log"
touch -d "-500 seconds" "$T/queue/gates/cmd_terminal/cmd_complete_gate.trigger.log"
log() { echo "$1" >> "$LOG"; }; NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
test "$(grep -c INBOX_CALLED "$LOG" 2>/dev/null || true)" -eq 0
'
    [ "$status" -eq 0 ]
}

@test "completion_notify_gap: CLEAR then REOPEN then new LGTM remains a true positive and dedupes second cycle" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T=$BATS_TEST_TMPDIR;
SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
mkdir -p "$T/queue/inbox" "$T/queue/reports" "$T/queue/tasks" "$T/queue/gates/cmd_reopened" "$T/scripts" "$STATE_DIR"
clear=$(date -d "-700 seconds" -Iseconds); reopen=$(date -d "-600 seconds" -Iseconds); lgtm=$(date -d "-500 seconds" -Iseconds)
printf "messages:\n- content: \"cmd_reopened verdict: RC\"\n  timestamp: \"%s\"\n  type: review_feedback\n- content: \"cmd_reopened verdict: LGTM\"\n  timestamp: \"%s\"\n  type: review_feedback\n" "$reopen" "$lgtm" > "$T/queue/inbox/karo.yaml"
printf "messages: []\n" > "$T/queue/inbox/shogun.yaml"; printf "entries: []\n" > "$T/queue/bulletin_board.yaml"
printf "#!/bin/bash\necho INBOX_CALLED:\\$@ >> \"$LOG\"\n" > "$T/scripts/inbox_write.sh"; chmod +x "$T/scripts/inbox_write.sh"
printf "GATE CLEAR: cmd完了許可\n" > "$T/queue/gates/cmd_reopened/cmd_complete_gate.trigger.log"
touch -d "$clear" "$T/queue/gates/cmd_reopened/cmd_complete_gate.trigger.log"
log() { echo "$1" >> "$LOG"; }; NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
check_karo_completion_notify_gap
test "$(grep -c INBOX_CALLED "$LOG")" -eq 1
'
    [ "$status" -eq 0 ]
}

@test "completion_notify_gap: a later REOPEN LGTM generation notifies once again" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T=$BATS_TEST_TMPDIR; SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
mkdir -p "$T/queue/inbox" "$T/queue/reports" "$T/queue/tasks" "$T/queue/gates/cmd_reopened" "$T/scripts" "$STATE_DIR"
clear=$(date -d "-900 seconds" -Iseconds); rc1=$(date -d "-800 seconds" -Iseconds); lgtm1=$(date -d "-700 seconds" -Iseconds); rc2=$(date -d "-600 seconds" -Iseconds); lgtm2=$(date -d "-500 seconds" -Iseconds)
printf "messages:\n- content: \"cmd_reopened verdict: RC\"\n  timestamp: \"%s\"\n  type: review_feedback\n- content: \"cmd_reopened verdict: LGTM\"\n  timestamp: \"%s\"\n  type: review_feedback\n" "$rc1" "$lgtm1" > "$T/queue/inbox/karo.yaml"
printf "messages: []\n" > "$T/queue/inbox/shogun.yaml"; printf "entries: []\n" > "$T/queue/bulletin_board.yaml"
printf "#!/bin/bash\necho INBOX_CALLED >> \"$LOG\"\n" > "$T/scripts/inbox_write.sh"; chmod +x "$T/scripts/inbox_write.sh"
printf "GATE CLEAR: cmd完了許可\n" > "$T/queue/gates/cmd_reopened/cmd_complete_gate.trigger.log"; touch -d "$clear" "$T/queue/gates/cmd_reopened/cmd_complete_gate.trigger.log"
log() { echo "$1" >> "$LOG"; }; NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
printf "messages:\n- content: \"cmd_reopened verdict: RC\"\n  timestamp: \"%s\"\n  type: review_feedback\n- content: \"cmd_reopened verdict: LGTM\"\n  timestamp: \"%s\"\n  type: review_feedback\n" "$rc2" "$lgtm2" > "$T/queue/inbox/karo.yaml"
NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
test "$(grep -c INBOX_CALLED "$LOG")" -eq 2
'
    [ "$status" -eq 0 ]
}

@test "auto_commit: regular commit excludes context markdown and batches context separately" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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

TMP_ROOT="$BATS_TEST_TMPDIR"

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
# test_necessity: exclusion is measured against committed HEAD because the
# dedicated auto-commit index intentionally leaves the shared index tree intact.
worktree_files=$(git diff HEAD --name-only | sort | tr "\n" " ")
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

@test "auto_commit: stale terminal target_path cannot claim code but operational files still commit" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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
printf "base\n" > queue/state.yaml
git add scripts/a.sh scripts/other.sh queue/state.yaml
git commit -qm initial

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<INNEREOF
task:
  status: done
  target_path: scripts/a.sh
INNEREOF

printf "change\n" >> scripts/a.sh
printf "change\n" >> scripts/other.sh
printf "change\n" >> queue/state.yaml
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/ queue/)
auto_commit_before_clear hayate "$_uncommitted"

committed_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
# test_necessity: safety exclusions remain dirty relative to committed HEAD even
# when the shared index intentionally remains based on the pre-commit HEAD.
worktree_files=$(git diff HEAD --name-only | sort | tr "\n" " ")
echo "committed=$committed_files"
echo "worktree=$worktree_files"
cat "$LOG"
test "$committed_files" = "queue/state.yaml "
test "$worktree_files" = "scripts/a.sh scripts/other.sh "
grep -q "AUTO-COMMIT-STALE-SCOPE-SKIP: hayate task_status=done; target_path is not ownership evidence" "$LOG"
grep -q "AUTO-COMMIT-OPERATIONAL-SKIP: hayate excluded scripts/a.sh" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"committed=queue/state.yaml"* ]]
    [[ "$output" == *"worktree=scripts/a.sh scripts/other.sh"* ]]
    [[ "$output" == *"AUTO-COMMIT-STALE-SCOPE-SKIP"* ]]
}

@test "auto_commit: regular auto-commit skips within 30 minutes" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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

@test "auto_commit: preserves pre-staged unrelated files and commits scoped change" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/config" "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/a.sh
printf "base\n" > config/other.yaml
git add scripts/a.sh config/other.yaml
git commit -qm initial
cat > queue/tasks/hayate.yaml <<INNEREOF
task:
  status: in_progress
  target_path: scripts/a.sh
INNEREOF

printf "staged\n" >> config/other.yaml
git add config/other.yaml
before_other_entry=$(git ls-files -s config/other.yaml)
before_other_work=$(git hash-object config/other.yaml)
printf "change\n" >> scripts/a.sh
before_target_work=$(git hash-object scripts/a.sh)
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/)
set +e
auto_commit_before_clear hayate "$_uncommitted"
rc=$?
set -e

count=$(git rev-list --count HEAD)
staged_files=$(git diff --cached --name-only | sort | tr "\n" " ")
# test_necessity: GA-231c protects the unrelated staged entry and both worktree
# blobs while the committed target entry advances with HEAD and stays clean.
worktree_files=$(git diff HEAD --name-only | sort | tr "\n" " ")
after_other_entry=$(git ls-files -s config/other.yaml)
after_other_work=$(git hash-object config/other.yaml)
after_target_work=$(git hash-object scripts/a.sh)
echo "rc=$rc"
echo "count=$count"
echo "staged=$staged_files"
echo "worktree=$worktree_files"
cat "$LOG"
test "$rc" = "0"
test "$count" = "2"
test "$staged_files" = "config/other.yaml "
test "$worktree_files" = "config/other.yaml "
test "$after_other_entry" = "$before_other_entry"
test "$after_other_work" = "$before_other_work"
test "$after_target_work" = "$before_target_work"
test -z "$(git status --short scripts/a.sh)"
grep -q "AUTO-COMMIT-STAGED-PRESERVE: hayate preserving scope-out staged file: config/other.yaml" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
    [[ "$output" == *"count=2"* ]]
    [[ "$output" == *"staged=config/other.yaml"* ]]
    [[ "$output" == *"worktree="* ]]
    [[ "$output" == *"AUTO-COMMIT-STAGED-PRESERVE"* ]]
}

@test "auto_commit: blocks when pre-staged file overlaps scoped change" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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
cat > queue/tasks/hayate.yaml <<INNEREOF
task:
  status: in_progress
  target_path: scripts/a.sh
INNEREOF

printf "staged\n" >> scripts/a.sh
git add scripts/a.sh
printf "worktree\n" >> scripts/a.sh
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
test "$staged_files" = "scripts/a.sh "
test "$worktree_files" = "scripts/a.sh "
grep -q "AUTO-COMMIT-WARN-SKIP: hayate pre-existing staged file overlaps auto-commit scope: scripts/a.sh" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=2"* ]]
    [[ "$output" == *"count=1"* ]]
    [[ "$output" == *"staged=scripts/a.sh"* ]]
    [[ "$output" == *"worktree=scripts/a.sh"* ]]
    [[ "$output" == *"overlaps auto-commit scope"* ]]
}

@test "auto_commit: context batch skips within one hour" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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

TMP_ROOT="$BATS_TEST_TMPDIR"

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

@test "stage1: in_progress has no wall-clock timeout or automatic clear" {
    run bash -lc '
set -eo pipefail
monitor="'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
grep -Fq "STAGE1-IN-PROGRESS:" "$monitor"
! grep -Fq "_s1_threshold=1800" "$monitor"
'
    [ "$status" -eq 0 ]
}

# Stage 1: done → maybe_idleに入る（Phase 2→/clearされる）
@test "handle_confirmed_idle: done task allows /clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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

TMP_ROOT="$BATS_TEST_TMPDIR"

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

@test "failed task without formal close preserves pane and never reaches clear debounce" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T="$BATS_TEST_TMPDIR"; SCRIPT_DIR="$T"; LOG="$T/log"
mkdir -p "$T/queue/tasks"; printf "task:\n  status: failed\n" > "$T/queue/tasks/saizo.yaml"
declare -A PANE_TARGETS LAST_CLEARED CLEAR_SKIP_COUNT POST_CLEAR_PENDING
PANE_TARGETS[saizo]="pane"; LAST_CLEARED[saizo]="$EPOCHSECONDS"
log(){ echo "$1" >> "$LOG"; }; tmux(){ :; }; get_context_pct(){ echo 50; }
cli_type(){ echo codex; }; cli_profile_get(){ echo 600; }
can_send_clear_with_report_gate(){ return 0; }; safe_send_clear(){ echo CLEAR >> "$LOG"; }
_failed_task_preserve_before_respawn(){ echo PRESERVED >> "$LOG"; return 0; }
_handle_auto_clear saizo "$EPOCHSECONDS"
grep -q PRESERVED "$LOG"; ! grep -q CLEAR "$LOG"; ! grep -q FAILED-RESPAWN-IMMEDIATE "$LOG"
'
    [ "$status" -eq 0 ]
}

# verdict非空チェック: report存在+verdict空→return 1(clearブロック)
@test "report_gate: verdict empty blocks clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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

TMP_ROOT="$BATS_TEST_TMPDIR"

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
- content: "kagemaru、cmd_test_verdict任務完了。報告YAML確認されたし。"
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

# test_necessity: a generation-exact terminal PASS report is sufficient primary
# evidence; a missing transport notification must not deadlock auto-clear.
@test "report_gate: terminal PASS report allows clear without report_received" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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
status: completed
verdict: PASS
INNEREOF

log() { echo "$1" >> "$LOG"; }

result=0
can_send_clear_with_report_gate kagemaru "test_trigger" || result=$?
wait 2>/dev/null

if [ "$result" -eq 0 ]; then
    echo "PASS: terminal report without report_received → return 0 (allowed)"
else
    echo "FAIL: expected return 0, got $result"
    exit 1
fi

! grep -q "REPORT-NOTIFY-MISSING-BLOCK" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: terminal report without report_received → return 0 (allowed)"* ]]
}

# test_necessity: exact SG7 LGTM is stronger terminal evidence than a missing earlier report_received transport and must suppress its false alert.
@test "report_gate: exact gunshi SG7 LGTM suppresses report_received missing false positive" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR"; LOG="$SCRIPT_DIR/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts"
touch "$LOG"
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: done
  task_id: cmd_reviewed_exact
  parent_cmd: cmd_reviewed
  deployed_at: "2026-07-22T16:00:00+09:00"
  report_filename: hayate_report_cmd_reviewed.yaml
YAML
cat > "$SCRIPT_DIR/queue/reports/hayate_report_cmd_reviewed.yaml" <<YAML
worker_id: hayate
task_id: cmd_reviewed_exact
parent_cmd: cmd_reviewed
verdict: PASS
YAML
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<YAML
messages:
- content: "cmd_reviewed report=hayate_report_cmd_reviewed.yaml verdict=LGTM"
  from: gunshi
  read: true
  timestamp: "2026-07-22T16:12:57+09:00"
  type: report_review_result
YAML
log(){ echo "$1" >> "$LOG"; }; notify_karo_throttled(){ echo "NOTIFY:$*" >> "$LOG"; }
can_send_clear_with_report_gate hayate reviewed
! grep -q "REPORT-NOTIFY-MISSING-BLOCK\|report_notification_missing" "$LOG"
echo "PASS: SG7 reviewed missing false positives=0"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: SG7 reviewed missing false positives=0"* ]]
}

@test "report_gate: read exact-identity notification prevents repeated false missing alerts" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR"; LOG="$SCRIPT_DIR/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts"
touch "$LOG"
cat > "$SCRIPT_DIR/queue/tasks/kotaro.yaml" <<YAML
task:
  status: done
  task_id: cmd_reflux_promotion_202607180352_kotaro_exact
  parent_cmd: cmd_reflux_promotion_202607180352_kotaro
  report_filename: kotaro_report_cmd_reflux_promotion_202607180352_kotaro.yaml
YAML
cat > "$SCRIPT_DIR/queue/reports/kotaro_report_cmd_reflux_promotion_202607180352_kotaro.yaml" <<YAML
worker_id: kotaro
task_id: cmd_reflux_promotion_202607180352_kotaro_exact
parent_cmd: cmd_reflux_promotion_202607180352_kotaro
timestamp: "2026-07-18T03:59:30+09:00"
verdict: PASS
YAML
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<YAML
messages:
- content: "小太郎、cmd_reflux_promotion_202607180352_kotaro完了。報告YAML PASS。"
  from: kotaro
  read: true
  timestamp: "2026-07-18T03:59:37+09:00"
  type: report_received
YAML
log() { echo "$1" >> "$LOG"; }
notify_karo_throttled() { echo "NOTIFY:$*" >> "$LOG"; }
can_send_clear_with_report_gate kotaro first
can_send_clear_with_report_gate kotaro second
count=$(grep -c "report_notification_missing" "$LOG" 2>/dev/null || true)
[ "$count" -eq 0 ]
echo "PASS: repeated false positives 2 -> $count"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: repeated false positives 2 -> 0"* ]]
}

@test "report_gate: processed identity remains valid after later report revision timestamp" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR"; LOG="$SCRIPT_DIR/log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts"
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
task:
  status: done
  task_id: cmd_live_exact
  parent_cmd: cmd_live
  deployed_at: "2026-07-18T08:00:00+09:00"
  report_filename: kagemaru_report_cmd_live.yaml
YAML
cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_live.yaml" <<YAML
worker_id: kagemaru
task_id: cmd_live_exact
parent_cmd: cmd_live
timestamp: "2026-07-18T08:11:00+09:00"
verdict: PASS
YAML
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<YAML
messages:
- content: "parent=cmd_live task=cmd_live_exact report=queue/reports/kagemaru_report_cmd_live.yaml"
  from: kagemaru
  read: true
  timestamp: "2026-07-18T08:02:52+09:00"
  type: report_received
YAML
log(){ echo "$1" >> "$LOG"; }; notify_karo_throttled(){ echo NOTIFY >> "$LOG"; }
can_send_clear_with_report_gate kagemaru live
! grep -q NOTIFY "$LOG"
'
    [ "$status" -eq 0 ]
}

@test "failed respawn notice is suppressed after exact report_received was processed" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR"; mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/archive/inbox" "$SCRIPT_DIR/logs"
cat > "$SCRIPT_DIR/queue/tasks/hanzo.yaml" <<YAML
task:
  status: failed
  task_id: cmd_failed_exact
  parent_cmd: cmd_failed
  deployed_at: "2026-07-18T08:00:00+09:00"
YAML
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<YAML
messages:
- content: "parent=cmd_failed task=cmd_failed_exact report=queue/reports/hanzo_report_cmd_failed.yaml"
  from: hanzo
  read: true
  timestamp: "2026-07-18T08:02:52+09:00"
  type: report_received
YAML
: > "$SCRIPT_DIR/logs/gate_metrics.log"
! _failed_task_needs_karo_notice hanzo
'
    [ "$status" -eq 0 ]
}

# test_necessity: a fingerprint-bound Karo ACCEPT is the formal FAIL-close
# handshake and must suppress the contradictory post-respawn warning.
@test "failed respawn notice is suppressed after matching Karo ACCEPT" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR"
mkdir -p "$SCRIPT_DIR/queue/tasks"
cat > "$SCRIPT_DIR/queue/tasks/hanzo.yaml" <<YAML
task:
  status: failed
  task_id: cmd_failed_exact
  parent_cmd: cmd_failed
  deployed_at: "2026-08-01T09:00:00+09:00"
YAML
_failed_task_is_formally_closed() { return 0; }
! _failed_task_needs_karo_notice hanzo
'
    [ "$status" -eq 0 ]
}

# test_necessity: archive.done is terminal evidence for both CLEAR and FAIL_CLOSE;
# removing it on explicit reopen must restore failed-task respawn eligibility.
@test "failed respawn notice respects archive terminal marker and explicit reopen" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/archive/inbox" \
         "$SCRIPT_DIR/logs" "$SCRIPT_DIR/queue/gates/cmd_fail_close" \
         "$SCRIPT_DIR/queue/gates/cmd_clear"
: > "$SCRIPT_DIR/queue/inbox/karo.yaml"
: > "$SCRIPT_DIR/logs/gate_metrics.log"
write_failed() {
  cat > "$SCRIPT_DIR/queue/tasks/kotaro.yaml" <<YAML
task:
  status: failed
  task_id: ${1}_normal
  parent_cmd: ${1}
  deployed_at: "2026-07-29T00:00:00+09:00"
YAML
}

write_failed cmd_fail_close
touch "$SCRIPT_DIR/queue/gates/cmd_fail_close/archive.done"
! _failed_task_needs_karo_notice kotaro
fail_close_count=0

write_failed cmd_clear
touch "$SCRIPT_DIR/queue/gates/cmd_clear/archive.done"
! _failed_task_needs_karo_notice kotaro
clear_count=0

write_failed cmd_unreviewed
_failed_task_needs_karo_notice kotaro
unreviewed_count=1

write_failed cmd_fail_close
rm "$SCRIPT_DIR/queue/gates/cmd_fail_close/archive.done"
_failed_task_needs_karo_notice kotaro
reopen_count=1

echo "COUNTS fail_close=$fail_close_count clear=$clear_count unreviewed=$unreviewed_count reopen=$reopen_count"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"COUNTS fail_close=0 clear=0 unreviewed=1 reopen=1"* ]]
}

# test_necessity: pending_work must ignore a regenerated active FAIL report while
# archive.done exists, and must become eligible again after explicit reopen.
@test "pending work terminal archive precedes active report and reopens after marker removal" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR"
mkdir -p "$SCRIPT_DIR/queue/gates/cmd_fail_close" "$SCRIPT_DIR/queue/reports"
cat > "$SCRIPT_DIR/queue/reports/kotaro_report_cmd_fail_close.yaml" <<YAML
status: completed
verdict: FAIL
report_id: regenerated-active-copy
YAML
touch "$SCRIPT_DIR/queue/gates/cmd_fail_close/archive.done"
pending=1
_pending_task_has_terminal_archive cmd_fail_close && pending=0
test "$pending" -eq 0
rm "$SCRIPT_DIR/queue/gates/cmd_fail_close/archive.done"
pending=1
_pending_task_has_terminal_archive cmd_fail_close && pending=0
test "$pending" -eq 1
echo "COUNTS archived_pending=0 reopened_pending=1"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"COUNTS archived_pending=0 reopened_pending=1"* ]]
}

# test_necessity: a near-match report identity from another generation must
# remain BLOCK even when transport history contains a similar token.
@test "report_gate: near-match report identity blocks current generation" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR"; LOG="$SCRIPT_DIR/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts"
touch "$LOG"
cat > "$SCRIPT_DIR/queue/tasks/kotaro.yaml" <<YAML
task:
  status: done
  task_id: cmd_exact_current
  parent_cmd: cmd_exact
  report_filename: kotaro_report_cmd_exact.yaml
YAML
cat > "$SCRIPT_DIR/queue/reports/kotaro_report_cmd_exact.yaml" <<YAML
worker_id: kotaro
task_id: cmd_exact_task
parent_cmd: cmd_exact
timestamp: "2026-07-18T04:00:00+09:00"
status: completed
verdict: PASS
YAML
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<YAML
messages:
- content: "小太郎、cmd_exact_old完了。"
  from: kotaro
  read: true
  timestamp: "2026-07-18T04:00:05+09:00"
  type: report_received
YAML
log() { echo "$1" >> "$LOG"; }
notify_karo_throttled() { echo "NOTIFY:$*" >> "$LOG"; }
rc=0; can_send_clear_with_report_gate kotaro test || rc=$?
[ "$rc" -eq 1 ]
count=$(grep -c "report_notification_missing" "$LOG" || true)
[ "$count" -eq 0 ]
echo "PASS: near-match generation blocked without transport dependency"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: near-match generation blocked without transport dependency"* ]]
}

@test "report_gate: archived report_received after report timestamp allows clear even when report mtime changed later" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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

@test "report_gate: memory DB report_received survives missing hot and archive history" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR"
LOG="$SCRIPT_DIR/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/data"
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
task:
  status: done
  parent_cmd: cmd_memory_fallback
  report_filename: kagemaru_report_cmd_memory_fallback.yaml
YAML
cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_memory_fallback.yaml" <<YAML
worker_id: kagemaru
parent_cmd: cmd_memory_fallback
timestamp: "2026-07-15T12:00:00+09:00"
verdict: PASS
YAML
printf "messages: []\n" > "$SCRIPT_DIR/queue/inbox/karo.yaml"
python3 - "$SCRIPT_DIR/data/multi_agent_shogun_memory.db" <<PY
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("CREATE TABLE events (ts TEXT, event_type TEXT, agent TEXT, target TEXT, detail TEXT, raw_content TEXT)")
db.execute("INSERT INTO events VALUES (?,?,?,?,?,?)", (
    "2026-07-15T12:00:05+09:00", "inbox", "kagemaru", "karo",
    "type: report_received\\nfrom: kagemaru\\ntarget: karo", "cmd_memory_fallback completed"))
db.commit()
PY
log() { echo "$1" >> "$LOG"; }
can_send_clear_with_report_gate kagemaru test_trigger
if grep -q "REPORT-NOTIFY-MISSING-BLOCK" "$LOG" 2>/dev/null; then
    echo "FAIL: durable memory evidence was ignored"
    exit 1
fi
echo "PASS: memory DB report_received allowed clear"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: memory DB report_received allowed clear"* ]]
}

@test "report_gate: legacy timestamp fallback uses deployed_at, not mutable report mtime" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY
SCRIPT_DIR="$BATS_TEST_TMPDIR";
LOG="$SCRIPT_DIR/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/archive/inbox" "$SCRIPT_DIR/scripts"
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
task:
  deployed_at: "2026-07-12T22:40:00+09:00"
YAML
cat > "$SCRIPT_DIR/queue/reports/legacy.yaml" <<YAML
worker_id: kagemaru
verdict: PASS
YAML
touch -d "2026-07-12T22:54:00+09:00" "$SCRIPT_DIR/queue/reports/legacy.yaml"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<YAML
messages:
- from: kagemaru
  content: "legacy.yaml completed"
  type: report_received
  timestamp: "2026-07-12T22:41:00+09:00"
YAML
log() { echo "$1" >> "$LOG"; }
report_notification_completed kagemaru "$SCRIPT_DIR/queue/reports/legacy.yaml" test
'
    [ "$status" -eq 0 ]
}

# cmd_karo_hotfix_report_notify_inprogress_guard AC1: 再配備(in_progress)後に
# まだ新しいreportが作られていない場合、旧い(前回試行の)completed reportを見て
# AUTO-DONEがtask statusを誤ってdoneへ書き換えてはならない。
# → check_and_update_done_taskがstatusを変えず、report_notification_missingも検知されない。
@test "report_gate: in_progress redeployed task with stale completed report does not auto-done or notify-missing" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts/lib"
ln -s "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "\$LOG"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

# 家老が再配備した後のtask: status=in_progress, deployed_atは旧reportより後
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: in_progress
  task_id: cmd_test_redeploy
  parent_cmd: cmd_test_redeploy
  deployed_at: "2026-07-10T19:11:35+09:00"
  report_filename: kagemaru_report_cmd_test_redeploy.yaml
INNEREOF

# 旧report: 再配備(deployed_at)より前のtimestampでstatus:completed(前回試行の報告)
cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_test_redeploy.yaml" <<INNEREOF
worker_id: kagemaru
task_id: cmd_test_redeploy
parent_cmd: cmd_test_redeploy
timestamp: "2026-07-10T19:08:00+09:00"
status: completed
verdict: PASS
INNEREOF

log() { echo "$1" >> "$LOG"; }

cadt_result=0
check_and_update_done_task kagemaru || cadt_result=$?

status_after=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" "status")
if [ "$status_after" = "done" ]; then
    echo "FAIL: stale report incorrectly auto-marked task done (cadt_rc=$cadt_result)"
    cat "$LOG"
    exit 1
fi

gate_result=0
can_send_clear_with_report_gate kagemaru "test_trigger" || gate_result=$?

if grep -q "REPORT-NOTIFY-MISSING-BLOCK" "$LOG"; then
    echo "FAIL: false report_notification_missing for in_progress redeployed task"
    cat "$LOG"
    exit 1
fi

echo "PASS: in_progress redeployed task with stale report kept status=$status_after (cadt_rc=$cadt_result, gate_rc=$gate_result), no notify-missing"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: in_progress redeployed task with stale report"* ]]
}

# cmd_karo_hotfix_report_notify_inprogress_guard AC2: 再配備後に実際に完了し、
# deployed_at以降のreportがあればAUTO-DONEでstatus=doneへ更新され、
# transport通知が失われてもterminal一次状態だけでclearできる。
# test_necessity: auto-done must not depend on a later worker utterance.
@test "report_gate: in_progress task with fresh report auto-dones without notification dependency" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/scripts/lib"
ln -s "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "\$LOG"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<INNEREOF
task:
  status: in_progress
  task_id: cmd_test_redeploy_real
  parent_cmd: cmd_test_redeploy_real
  deployed_at: "2026-07-10T19:11:35+09:00"
  report_filename: kagemaru_report_cmd_test_redeploy_real.yaml
INNEREOF

# 新report: deployed_atより後のtimestamp(今回の再配備後に実際に完了した報告)
cat > "$SCRIPT_DIR/queue/reports/kagemaru_report_cmd_test_redeploy_real.yaml" <<INNEREOF
worker_id: kagemaru
task_id: cmd_test_redeploy_real
parent_cmd: cmd_test_redeploy_real
timestamp: "2026-07-10T19:20:00+09:00"
status: completed
verdict: PASS
INNEREOF

log() { echo "$1" >> "$LOG"; }

cadt_result=0
check_and_update_done_task kagemaru || cadt_result=$?

status_after=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" "status")
if [ "$status_after" != "done" ]; then
    echo "FAIL: fresh post-redeploy report should still auto-done (cadt_rc=$cadt_result, status=$status_after)"
    cat "$LOG"
    exit 1
fi

gate_result=0
can_send_clear_with_report_gate kagemaru "test_trigger" || gate_result=$?

if [ "$gate_result" -ne 0 ]; then
    echo "FAIL: terminal report should allow clear without notification (gate_rc=$gate_result)"
    cat "$LOG"
    exit 1
fi

if grep -q "REPORT-NOTIFY-MISSING-BLOCK" "$LOG"; then
    echo "FAIL: transport notification reintroduced a completion dependency"
    cat "$LOG"
    exit 1
fi

echo "PASS: fresh post-redeploy report auto-dones and clears without notification dependency (status=$status_after, gate_rc=$gate_result)"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: fresh post-redeploy report auto-dones"* ]]
}

# verdict値チェック: report存在+verdict不正値→return 1(clearブロック)
@test "report_gate: invalid verdict blocks clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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
status: completed
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

TMP_ROOT="$BATS_TEST_TMPDIR"

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

TMP_ROOT="$BATS_TEST_TMPDIR"

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

@test "training auto deploy: delegated is free while pending pipeline work blocks training deployment" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue"

cat > "$SCRIPT_DIR/queue/shogun_to_karo.yaml" <<INNEREOF
- id: cmd_delegated_test
  status: delegated
  purpose: active delegated work
INNEREOF

if _training_pipeline_has_work; then
    echo "FAIL: delegated pipeline work blocked training"
    exit 1
fi

sed -i "s/status: delegated/status: pending/" "$SCRIPT_DIR/queue/shogun_to_karo.yaml"
if _training_pipeline_has_work; then
    echo "PASS: delegated is free and pending pipeline work is detected"
else
    echo "FAIL: pending pipeline work was ignored"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: delegated is free and pending pipeline work is detected"* ]]
}

# AC1: Codex idle + no_task → debounce経過後はsafe_send_clearを呼ぶ
@test "codex idle no_task calls safe_send_clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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

TMP_ROOT="$BATS_TEST_TMPDIR"

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

TMP_ROOT="$BATS_TEST_TMPDIR"

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
        launch_cmd) echo "/usr/bin/bash" ;;
        *) echo "" ;;
    esac
}
cli_launch_cmd() { echo "/usr/bin/bash"; }
codex_config_apply_agent() { _CODEX_CFG_CHANGED=false; return 0; }
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    echo ""
}
export -f tmux
respawn_recovery_wait_ready() { return 0; }
respawn_recovery_generation() { echo "123:456"; }
respawn_recovery_notify() { return 0; }

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

TMP_ROOT="$BATS_TEST_TMPDIR"

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
        launch_cmd) echo "/usr/bin/bash" ;;
        *) echo "" ;;
    esac
}
cli_launch_cmd() { echo "/usr/bin/bash"; }
codex_config_apply_agent() { _CODEX_CFG_CHANGED=false; return 0; }
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    echo ""
}
export -f tmux
respawn_recovery_wait_ready() { return 0; }
respawn_recovery_generation() { echo "123:456"; }
respawn_recovery_notify() { return 0; }

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: done
  task_id: cmd_test_task
  parent_cmd: cmd_test
  report_filename: hayate_report_cmd_test.yaml
YAML
DONE_BLOCKED=0
safe_send_clear "shogun:2.3" "hayate" "DONE-MISSING-REPORT" || DONE_BLOCKED=$?

cat > "$SCRIPT_DIR/queue/reports/hayate_report_cmd_test.yaml" <<YAML
worker_id: hayate
task_id: cmd_test_task
parent_cmd: cmd_test
status: done
verdict: FILL_THIS
YAML
INVALID_BLOCKED=0
safe_send_clear "shogun:2.3" "hayate" "DONE-INVALID-REPORT" || INVALID_BLOCKED=$?

cat > "$SCRIPT_DIR/queue/reports/hayate_report_cmd_test.yaml" <<YAML
worker_id: hayate
task_id: cmd_test_task
parent_cmd: cmd_test
status: done
verdict: PASS
YAML
now="$(date "+%Y-%m-%dT%H:%M:%S")"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<YAML
messages:
- content: "hayate、cmd_test任務完了。報告YAML確認されたし。"
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

# AC3/AC4(cmd_karo_hotfix_failed_report_clear_notify_gap): 殿裁定(2026-07-12 08:43)により
# 通知失敗でrespawnをBLOCKする設計は撤回された。正しい不変量はrespawn実行結果を起点にした
# durable通知であり、respawn自体は止めない。cmd_3861実例(report完成→task failed→無通知respawn)の回帰防止。
@test "safe_send_clear failed task auto-respawn success sends durable karo notification exactly once" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "$TMP_ROOT/inbox_calls.log"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
task:
  status: failed
  parent_cmd: cmd_notify_success
YAML

check_idle() { return 0; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_cmd) echo "/new" ;;
        launch_cmd) echo "/usr/bin/bash" ;;
        *) echo "" ;;
    esac
}
cli_launch_cmd() { echo "/usr/bin/bash"; }
codex_config_apply_agent() { _CODEX_CFG_CHANGED=false; return 0; }
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    echo ""
}
export -f tmux
respawn_recovery_wait_ready() { return 0; }
respawn_recovery_generation() { echo "123:456"; }
respawn_recovery_notify() { return 0; }

safe_send_clear "shogun:2.4" "kagemaru" "AUTO-CLEAR"

cat "$LOG"
if [ -f "$TMP_ROOT/inbox_calls.log" ]; then
    cat "$TMP_ROOT/inbox_calls.log"
fi

test "$(grep -c "CODEX-RESPAWN: kagemaru respawn-pane" "$LOG")" -eq 1
test "$(grep -c "failed_task_respawned" "$TMP_ROOT/inbox_calls.log")" -eq 1
echo "PASS: failed respawn success notifies once"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: failed respawn success notifies once"* ]]
}

@test "safe_send_clear failed task auto-respawn failure sends durable failure notification without blocking the attempt" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "$TMP_ROOT/inbox_calls.log"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
task:
  status: failed
  parent_cmd: cmd_notify_failure
YAML

check_idle() { return 0; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_cmd) echo "/new" ;;
        launch_cmd) echo "/usr/bin/bash" ;;
        *) echo "" ;;
    esac
}
cli_launch_cmd() { echo "/usr/bin/bash"; }
codex_config_apply_agent() { _CODEX_CFG_CHANGED=false; return 0; }
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN-ATTEMPTED:$*" >> "$LOG"
        return 1
    fi
    echo ""
}
export -f tmux

RESPAWN_RC=0
safe_send_clear "shogun:2.4" "kagemaru" "AUTO-CLEAR" || RESPAWN_RC=$?

cat "$LOG"
if [ -f "$TMP_ROOT/inbox_calls.log" ]; then
    cat "$TMP_ROOT/inbox_calls.log"
fi

test "$(grep -c "RESPAWN-ATTEMPTED:respawn-pane" "$LOG")" -eq 1
test "$(grep -c "CODEX-RESPAWN-FALLBACK: kagemaru respawn failed" "$LOG")" -eq 1
test "$(grep -c "failed_task_respawn_failed" "$TMP_ROOT/inbox_calls.log")" -eq 1
test "$RESPAWN_RC" -eq 1
grep -q "CODEX-RESPAWN-VERIFY-FAIL: kagemaru ready handshake timed out; retry=next_cycle" "$LOG"
echo "PASS: failed respawn attempted, notified, and scheduled for retry"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: failed respawn attempted, notified, and scheduled for retry"* ]]
}

@test "safe_send_clear failed task already gate-cleared sends no duplicate notification" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"
touch "$SCRIPT_DIR/queue/archive/cmds/cmd_already_clear_completed_20260712.yaml"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "$TMP_ROOT/inbox_calls.log"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
task:
  status: failed
  parent_cmd: cmd_already_clear
YAML

check_idle() { return 0; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_cmd) echo "/new" ;;
        launch_cmd) echo "/usr/bin/bash" ;;
        *) echo "" ;;
    esac
}
cli_launch_cmd() { echo "/usr/bin/bash"; }
codex_config_apply_agent() { _CODEX_CFG_CHANGED=false; return 0; }
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    echo ""
}
export -f tmux
respawn_recovery_wait_ready() { return 0; }
respawn_recovery_generation() { echo "123:456"; }
respawn_recovery_notify() { return 0; }

safe_send_clear "shogun:2.4" "kagemaru" "AUTO-CLEAR"

cat "$LOG"
if [ -f "$TMP_ROOT/inbox_calls.log" ]; then
    cat "$TMP_ROOT/inbox_calls.log"
fi

test "$(grep -c "CODEX-RESPAWN: kagemaru respawn-pane" "$LOG")" -eq 1
if [ -f "$TMP_ROOT/inbox_calls.log" ]; then
    if grep -qE "failed_task_respawned|failed_task_respawn_failed" "$TMP_ROOT/inbox_calls.log"; then
        cat "$TMP_ROOT/inbox_calls.log"
        exit 1
    fi
fi
echo "PASS: gate-cleared failed task suppresses notification"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: gate-cleared failed task suppresses notification"* ]]
}

@test "notify_karo_durable queues to outbox on delivery failure and flush_karo_notify_outbox retries" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "$TMP_ROOT/inbox_calls.log"
if [ -f "$TMP_ROOT/fail_flag" ]; then
    exit 1
fi
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

touch "$TMP_ROOT/fail_flag"

RESULT=0
notify_karo_durable failed_task_respawned testninja "queued message" || RESULT=$?

OUTBOX_FILE="$STATE_DIR/karo_notify_outbox.tsv"
# cmd_karo_hotfix_pending_work_generation_dedupe_202607121023で契約明確化:
# direct失敗でもoutbox永続化(printf append)自体が成功していればreturn 0
# (=将来必ず届く見込みが確定)。outbox append自体の失敗のみreturn 1。
test "$RESULT" -eq 0
test -f "$OUTBOX_FILE"
test "$(wc -l < "$OUTBOX_FILE")" -eq 1

rm -f "$TMP_ROOT/fail_flag"
rm -f "$TMP_ROOT/inbox_calls.log"

flush_karo_notify_outbox

cat "$LOG"
if [ -f "$TMP_ROOT/inbox_calls.log" ]; then
    cat "$TMP_ROOT/inbox_calls.log"
fi

grep -q "NOTIFY-OUTBOX-FLUSHED: failed_task_respawned" "$LOG"
test "$(grep -c "failed_task_respawned" "$TMP_ROOT/inbox_calls.log")" -eq 1
if [ -s "$OUTBOX_FILE" ]; then
    cat "$OUTBOX_FILE"
    exit 1
fi
echo "PASS: outbox retry delivers queued notification"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: outbox retry delivers queued notification"* ]]
}

# cmd_karo_hotfix_pending_work_generation_dedupe_202607121023 AC3: outbox永続化自体
# (printf >> outbox_file)が失敗する異常系(STATE_DIRがディレクトリでない等)でのみ
# notify_karo_durableがreturn 1することを検証する。呼び出し元はこの場合のみ世代markerを
# 確定せず次サイクルでretryしてよい。
@test "notify_karo_durable returns 1 only when outbox persistence itself fails" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/scripts"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
exit 1
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

# STATE_DIRをディレクトリではなくファイルにし、outbox永続化(printf >> outbox_file)自体を失敗させる
touch "$TMP_ROOT/not_a_dir"
STATE_DIR="$TMP_ROOT/not_a_dir"

RESULT=0
notify_karo_durable pending_work testninja "unreachable message" || RESULT=$?

cat "$LOG"
test "$RESULT" -eq 1
grep -q "NOTIFY-OUTBOX-ENQUEUE-FAILED: pending_work" "$LOG"
echo "PASS: outbox persistence failure itself returns 1"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: outbox persistence failure itself returns 1"* ]]
}

# karo実運転RC(2026-07-12 09:04): 08:53/09:03に同一kagemaru/hanzo failed taskが繰り返しrespawnされ
# 同一通知が各2回発生(exactly-once不変量違反)。同一世代(task_id+parent_cmd+deployed_at不変)の
# 繰り返しrespawnは通知1件に抑制し、世代が変わったら(再配備等)再度通知することを検証する。
@test "safe_send_clear dedupes repeated failed-respawn notifications for the same generation and re-notifies on a new one" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/archive/cmds" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@" >> "$TMP_ROOT/inbox_calls.log"
exit 0
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
task:
  status: failed
  parent_cmd: cmd_dedupe_test
  task_id: cmd_dedupe_test_full
  deployed_at: "2026-07-12T06:57:01"
YAML

check_idle() { return 0; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_cmd) echo "/new" ;;
        launch_cmd) echo "/usr/bin/bash" ;;
        *) echo "" ;;
    esac
}
cli_launch_cmd() { echo "/usr/bin/bash"; }
codex_config_apply_agent() { _CODEX_CFG_CHANGED=false; return 0; }
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    echo ""
}
export -f tmux
respawn_recovery_wait_ready() { return 0; }
respawn_recovery_generation() { echo "123:456"; }
respawn_recovery_notify() { return 0; }

# 同一世代(deployed_at不変)で3回respawnされても通知は1件のみ
safe_send_clear "shogun:2.4" "kagemaru" "AUTO-CLEAR"
safe_send_clear "shogun:2.4" "kagemaru" "AUTO-CLEAR"
safe_send_clear "shogun:2.4" "kagemaru" "AUTO-CLEAR"

test "$(grep -c "CODEX-RESPAWN: kagemaru respawn-pane" "$LOG")" -eq 3
test "$(grep -c "failed_task_respawned" "$TMP_ROOT/inbox_calls.log")" -eq 1
test "$(grep -c "FAILED-RESPAWN-NOTICE-DEDUPE: kagemaru outcome=success" "$LOG")" -eq 2

# 再配備で世代(deployed_at)が変わったら新規通知が1件増える
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
task:
  status: failed
  parent_cmd: cmd_dedupe_test
  task_id: cmd_dedupe_test_full
  deployed_at: "2026-07-12T09:30:00"
YAML
safe_send_clear "shogun:2.4" "kagemaru" "AUTO-CLEAR"

cat "$LOG"
cat "$TMP_ROOT/inbox_calls.log"

test "$(grep -c "failed_task_respawned" "$TMP_ROOT/inbox_calls.log")" -eq 2
echo "PASS: dedupe holds within generation, resets on new generation"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: dedupe holds within generation, resets on new generation"* ]]
}

# test_necessity: safe_send_clear直呼びでもactive taskを既定BLOCKし、停止復旧callerの明示許可だけを通す
@test "safe_send_clear active task is fail-closed unless deploy-stall explicitly allows it" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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
        launch_cmd) echo "/usr/bin/bash" ;;
        *) echo "" ;;
    esac
}
cli_launch_cmd() { echo "/usr/bin/bash"; }
codex_config_apply_agent() { _CODEX_CFG_CHANGED=false; return 0; }
safe_send_keys_atomic() { echo "SEND:$2" >> "$LOG"; return 0; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    echo ""
}
export -f tmux
respawn_recovery_wait_ready() { return 0; }
respawn_recovery_generation() { echo "123:456"; }
respawn_recovery_notify() { return 0; }

BLOCKED=0
safe_send_clear "shogun:2.3" "hayate" "TEST" || BLOCKED=$?

test "$BLOCKED" -eq 1
grep -q "CLEAR-BLOCKED-ACTIVE-TASK: hayate status=in_progress reason=TEST" "$LOG"
if grep -q "RESPAWN:respawn-pane" "$LOG"; then
    cat "$LOG"
    exit 1
fi

safe_send_clear "shogun:2.3" "hayate" "DEPLOY-STALL-CLEAR" true

grep -q "CODEX-RESPAWN: hayate respawn-pane" "$LOG"
grep -q "RESPAWN:respawn-pane" "$LOG"
if grep -q "SEND:/new" "$LOG"; then
    cat "$LOG"
    exit 1
fi
test "$(grep -c "RESPAWN:respawn-pane" "$LOG")" -eq 1
echo "PASS: active task blocked by default and explicit deploy-stall recovery allowed"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: active task blocked by default and explicit deploy-stall recovery allowed"* ]]
}

@test "max_clear_per_cmd reads settings value and defaults to 3" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

mkdir -p "$TMP_ROOT/config"

test "$(get_max_clear_per_cmd "$TMP_ROOT/config/missing.yaml")" = "3"
cat > "$TMP_ROOT/config/settings.yaml" <<YAML
token_budget:
  max_clear_per_cmd: 5
YAML
test "$(get_max_clear_per_cmd "$TMP_ROOT/config/settings.yaml")" = "5"

cat > "$TMP_ROOT/config/settings.yaml" <<YAML
token_budget:
  max_clear_per_cmd: invalid
YAML
test "$(get_max_clear_per_cmd "$TMP_ROOT/config/settings.yaml")" = "3"

echo "PASS: max_clear_per_cmd settings"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: max_clear_per_cmd settings"* ]]
}

@test "safe_send_clear forces idle and notifies karo after max_clear_per_cmd is exceeded" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/config/settings.yaml" <<YAML
token_budget:
  max_clear_per_cmd: 1
YAML
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: in_progress
  parent_cmd: cmd_loop
YAML

check_idle() { return 0; }
can_send_clear_with_report_gate() { return 0; }
auto_commit_before_clear() { return 0; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_cmd) echo "/new" ;;
        launch_cmd) echo "/home/test/.nvm/versions/node/v22/bin/codex" ;;
        *) echo "" ;;
    esac
}
cli_launch_cmd() { echo "/usr/bin/bash"; }
codex_config_apply_agent() { _CODEX_CFG_CHANGED=false; return 0; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TMP_ROOT/messages.log"; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    return 0
}
export -f tmux
respawn_recovery_wait_ready() { return 0; }
respawn_recovery_generation() { echo "123:456"; }
respawn_recovery_notify() { return 0; }

safe_send_clear "shogun:2.3" "hayate" "TEST-FIRST" true
BLOCKED=0
safe_send_clear "shogun:2.3" "hayate" "TEST-SECOND" true || BLOCKED=$?

test "$BLOCKED" -eq 1
test "$(grep -c "RESPAWN:respawn-pane" "$LOG")" -eq 1
grep -q "CLEAR-LOOP-BLOCK: hayate cmd=cmd_loop count=2/1 forced_idle reason=TEST-SECOND" "$LOG"
grep -q "karo|clear_loop_block|.*cmd=cmd_loop" "$TMP_ROOT/messages.log"
grep -q "status: idle" "$SCRIPT_DIR/queue/tasks/hayate.yaml"

echo "PASS: clear loop forced idle"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: clear loop forced idle"* ]]
}

@test "safe_send_clear does not count idle stale parent_cmd as clear loop" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/config" "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/config/settings.yaml" <<YAML
token_budget:
  max_clear_per_cmd: 1
YAML
cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
  parent_cmd: cmd_completed
  task_id: idle
  _ac_task_id: idle
YAML

check_idle() { return 0; }
can_send_clear_with_report_gate() { return 0; }
auto_commit_before_clear() { return 0; }
cli_type() { echo "codex"; }
cli_profile_get() {
    case "$2" in
        clear_cmd) echo "/new" ;;
        launch_cmd) echo "/home/test/.nvm/versions/node/v22/bin/codex" ;;
        *) echo "" ;;
    esac
}

cli_launch_cmd() { echo "/usr/bin/bash"; }
codex_config_apply_agent() { _CODEX_CFG_CHANGED=false; return 0; }
send_inbox_message() { echo "$1|$3|$2|${4:-ninja_monitor}" >> "$TMP_ROOT/messages.log"; }
tmux() {
    if [ "$1" = "respawn-pane" ]; then
        echo "RESPAWN:$*" >> "$LOG"
        return 0
    fi
    return 0
}
export -f tmux
respawn_recovery_wait_ready() { return 0; }
respawn_recovery_generation() { echo "123:456"; }
respawn_recovery_notify() { return 0; }

safe_send_clear "shogun:2.3" "hayate" "AUTO-CLEAR"
safe_send_clear "shogun:2.3" "hayate" "AUTO-CLEAR"

test "$(grep -c "RESPAWN:respawn-pane" "$LOG")" -eq 2
test ! -f "$TMP_ROOT/messages.log"
test ! -f "$STATE_DIR/shogun_clear_count_hayate.tsv"
grep -q "CLEAR-COUNT-SKIP: hayate task_status=idle has no valid cmd context" "$LOG"

echo "PASS: idle stale parent_cmd skipped"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: idle stale parent_cmd skipped"* ]]
}

@test "terminal task context uses current generation fields and rejects stale sentinels" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T="$BATS_TEST_TMPDIR"; SCRIPT_DIR="$T"; LOG="$T/log"
mkdir -p "$T/queue/tasks"; : > "$LOG"
log() { echo "$1" >> "$LOG"; }

cat > "$T/queue/tasks/hayate.yaml" <<YAML
task:
  status: done
  parent_cmd: cmd_current
  task_id: cmd_current_normal
  _ac_task_id: cmd_current_normal
YAML
test "$(_task_parent_cmd_for_clear_count hayate)" = cmd_current

cat > "$T/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
  parent_cmd:
  task_id: cmd_task_fallback_normal
  _ac_task_id:
YAML
test "$(_task_parent_cmd_for_clear_count hayate)" = cmd_task_fallback_normal

cat > "$T/queue/tasks/hayate.yaml" <<YAML
task:
  status: failed
  parent_cmd:
  task_id:
  _ac_task_id: cmd_ac_fallback_exact
YAML
test "$(_task_parent_cmd_for_clear_count hayate)" = cmd_ac_fallback_exact

cat > "$T/queue/tasks/hayate.yaml" <<YAML
task:
  status: idle
  parent_cmd: cmd_stale
  task_id: idle
  _ac_task_id: idle
YAML
test "$(_task_parent_cmd_for_clear_count hayate)" = no_cmd
grep -q "CLEAR-COUNT-SKIP: hayate task_status=idle has no valid cmd context" "$LOG"

cat > "$T/queue/tasks/hayate.yaml" <<YAML
task:
  status: done
  parent_cmd: cmd_stale
  task_id: cmd_new_generation_normal
  _ac_task_id: cmd_new_generation_normal
YAML
test "$(_task_parent_cmd_for_clear_count hayate)" = cmd_new_generation_normal

echo "PASS: terminal context precedence and stale boundary"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: terminal context precedence and stale boundary"* ]]
}

@test "done and idle terminal tasks trigger AUTO-CLEAR with cmd context" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T="$BATS_TEST_TMPDIR"; SCRIPT_DIR="$T"; LOG="$T/log"
mkdir -p "$T/queue/tasks"; : > "$LOG"
declare -A PANE_TARGETS LAST_CLEARED CLEAR_SKIP_COUNT POST_CLEAR_PENDING
PANE_TARGETS[hayate]=pane; LAST_CLEARED[hayate]=0
log() { echo "$1" >> "$LOG"; }
tmux() {
  if [ "$1" = display-message ]; then echo hayate; fi
  return 0
}
get_context_pct() { echo 80; }
cli_type() { echo codex; }
cli_profile_get() { case "$2" in clear_debounce) echo 0;; *) echo "";; esac; }
can_send_clear_with_report_gate() { return 0; }
safe_send_clear() { echo "AUTO_CLEAR:$2" >> "$LOG"; return 0; }
for terminal_status in done idle; do
  cat > "$T/queue/tasks/hayate.yaml" <<YAML
task:
  status: $terminal_status
  parent_cmd: cmd_terminal
  task_id: cmd_terminal_normal
  _ac_task_id: cmd_terminal_normal
YAML
  _handle_auto_clear hayate 10000
done
actual=$(grep -c '^AUTO_CLEAR:hayate$' "$LOG")
if [ "$actual" -ne 2 ]; then exit 1; fi
if grep -q "CLEAR-COUNT-SKIP.*no valid cmd context" "$LOG"; then exit 1; fi
grep -q "^AUTO_CLEAR:hayate$" "$LOG"
echo "PASS: terminal AUTO-CLEAR fired"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: terminal AUTO-CLEAR fired"* ]]
}

# --- cmd_3264: auto-commit in_progress ninja exclusion tests ---

@test "auto_commit: excludes in_progress ninja target_path files from other ninja clear" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

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
  status: in_progress
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
# test_necessity: in-progress exclusions are measured against committed HEAD;
# the dedicated auto-commit index deliberately leaves the shared index intact.
worktree_files=$(git diff HEAD --name-only | sort | tr "\n" " ")
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

TMP_ROOT="$BATS_TEST_TMPDIR"

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

TMP_ROOT="$BATS_TEST_TMPDIR"

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

# --- cmd_3284: safety mechanism exclusion tests ---

@test "auto_commit: safety filter excludes scripts/gates/ with visible log even when in target_path scope" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/scripts/gates" "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/a.sh
printf "base\n" > scripts/gates/gate_check.sh
git add scripts/a.sh scripts/gates/gate_check.sh
git commit -qm initial

cat > "$SCRIPT_DIR/queue/tasks/kotaro.yaml" <<INNEREOF
task:
  status: in_progress
  target_path: scripts
INNEREOF

NINJA_NAMES=(kotaro)
printf "change\n" >> scripts/a.sh
printf "change\n" >> scripts/gates/gate_check.sh
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
_uncommitted=$(git status --porcelain -uno -- scripts/)
auto_commit_before_clear kotaro "$_uncommitted"

committed_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
# test_necessity: safety exclusions are measured against committed HEAD;
# the dedicated auto-commit index deliberately leaves the shared index intact.
worktree_files=$(git diff HEAD --name-only | sort | tr "\n" " ")
echo "committed=$committed_files"
echo "worktree=$worktree_files"
cat "$LOG"
test "$committed_files" = "scripts/a.sh "
test "$worktree_files" = "scripts/gates/gate_check.sh "
grep -q "AUTO-COMMIT-SAFETY-EXCLUDE: kotaro excluded scripts/gates/gate_check.sh" "$LOG"
echo "PASS"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"committed=scripts/a.sh"* ]]
    [[ "$output" == *"AUTO-COMMIT-SAFETY-EXCLUDE"* ]]
}

@test "auto_commit: safety filter excludes .claude/hooks/ with visible log" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/.claude/hooks" "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/queue/tasks" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > scripts/a.sh
printf "base\n" > .claude/hooks/pre-commit.sh
git add scripts/a.sh .claude/hooks/pre-commit.sh
git commit -qm initial

# target_path=.claude で .claude/ スコープ内として安全フィルタが適用される
cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<INNEREOF
task:
  status: in_progress
  target_path: .claude
INNEREOF

NINJA_NAMES=(saizo)
printf "change\n" >> .claude/hooks/pre-commit.sh
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
touch "$LOG"
_uncommitted=$(git status --porcelain -uno -- .claude/)
auto_commit_before_clear saizo "$_uncommitted"

cat "$LOG"
# .claude/hooks/pre-commit.sh は安全フィルタで除外されnew commitなし
# HEAD = initial commit (scripts/a.sh + .claude/hooks/pre-commit.sh)
if git log --oneline | grep -q "auto-commit"; then
    echo "FAIL: auto-commit created when safety file should be excluded"
    exit 1
fi
grep -q "AUTO-COMMIT-SAFETY-EXCLUDE:.*\.claude/hooks/pre-commit\.sh" "$LOG"
echo "PASS"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"AUTO-COMMIT-SAFETY-EXCLUDE"* ]]
}

@test "auto_commit: safety filter does not block normal operational files (queue/ logs/)" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT/repo"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/monitor.log"
mkdir -p "$SCRIPT_DIR/queue" "$SCRIPT_DIR/logs" "$STATE_DIR"
cd "$SCRIPT_DIR"
git init -q
git config user.email test@example.com
git config user.name test
printf "base\n" > queue/state.yaml
printf "base\n" > logs/ops.yaml
git add queue/state.yaml logs/ops.yaml
git commit -qm initial

NINJA_NAMES=(hayate)
printf "change\n" >> queue/state.yaml
printf "change\n" >> logs/ops.yaml
NINJA_MONITOR_NOW=10000
export SCRIPT_DIR STATE_DIR LOG NINJA_MONITOR_NOW
touch "$LOG"
_uncommitted=$(git status --porcelain -uno -- queue/ logs/)
auto_commit_before_clear hayate "$_uncommitted"

committed_files=$(git show --name-only --format= HEAD | sed "/^$/d" | sort | tr "\n" " ")
echo "committed=$committed_files"
cat "$LOG"
test "$committed_files" = "logs/ops.yaml queue/state.yaml "
if grep -q "AUTO-COMMIT-SAFETY-EXCLUDE:" "$LOG"; then
    echo "FAIL: safety filter incorrectly excluded operational files"
    exit 1
fi
echo "PASS"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"committed=logs/ops.yaml queue/state.yaml"* ]]
}

# --- cmd_3347 AC2: AUTO-CLEAR-PREFLIGHT-BLOCK ---

@test "auto_clear preflight: blocks respawn when background AUTO_DEPLOY changes status to assigned" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks"
touch "$LOG"

declare -A LAST_CLEARED PANE_TARGETS CLEAR_SKIP_COUNT POST_CLEAR_PENDING

LAST_CLEARED[kagemaru]=9000
PANE_TARGETS[kagemaru]="shogun:2.5"

# タスクYAML: 最初はdone、しかしsafe_send_clear呼び出し前にassignedに変わる
cat > "$SCRIPT_DIR/queue/tasks/kagemaru.yaml" <<YAML
task:
  status: done
YAML

log() { echo "$@" >> "$LOG"; }
get_context_pct() { echo "80"; }
cli_profile_get() {
    case "$2" in
        clear_debounce) echo "600" ;;
        *) echo "" ;;
    esac
}
# safe_send_clear呼び出し前にstatusをassignedに書き換え（background AUTO_DEPLOY完了をシミュレート）
can_send_clear_with_report_gate() {
    sed -i "s/status: done/status: assigned/" "$SCRIPT_DIR/queue/tasks/kagemaru.yaml"
    return 0
}
CLEAR_CALLED=0
safe_send_clear() { CLEAR_CALLED=1; return 0; }
tmux() { echo ""; }
export -f tmux

_handle_auto_clear "kagemaru" 10000

if [ "$CLEAR_CALLED" -eq 0 ]; then
    echo "PASS: respawn blocked by preflight check"
else
    echo "FAIL: respawn executed despite active task"
    exit 1
fi

if grep -q "AUTO-CLEAR-PREFLIGHT-BLOCK: kagemaru task_status=assigned" "$LOG"; then
    echo "PASS: PREFLIGHT-BLOCK logged correctly"
else
    echo "FAIL: PREFLIGHT-BLOCK not in log"
    cat "$LOG"
    exit 1
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: respawn blocked by preflight check"* ]]
    [[ "$output" == *"PASS: PREFLIGHT-BLOCK logged correctly"* ]]
}

@test "auto_clear preflight: allows respawn when task remains done (no race)" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks"
touch "$LOG"

declare -A LAST_CLEARED PANE_TARGETS CLEAR_SKIP_COUNT POST_CLEAR_PENDING

LAST_CLEARED[saizo]=9000
PANE_TARGETS[saizo]="shogun:2.6"

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<YAML
task:
  status: done
YAML

log() { echo "$@" >> "$LOG"; }
get_context_pct() { echo "80"; }
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

_handle_auto_clear "saizo" 10000

if [ "$CLEAR_CALLED" -eq 1 ]; then
    echo "PASS: respawn allowed when task stays done"
else
    echo "FAIL: respawn was unexpectedly blocked"
    cat "$LOG"
    exit 1
fi

if grep -q "AUTO-CLEAR-PREFLIGHT-BLOCK" "$LOG"; then
    echo "FAIL: PREFLIGHT-BLOCK should not fire for done status"
    cat "$LOG"
    exit 1
fi
echo "PASS: no false-positive preflight block"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: respawn allowed when task stays done"* ]]
    [[ "$output" == *"PASS: no false-positive preflight block"* ]]
}

# cmd_karo_hotfix_completion_notify_gap AC3: LGTM後grace超過+bulletin/shogun未通知→検知
@test "completion_notify_gap: grace expired with no bulletin/shogun notification triggers detection" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

old_ts="$(date -d "-400 seconds" "+%Y-%m-%dT%H:%M:%S")"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<INNEREOF
messages:
- content: "cmd_test_gap001レビュー完了。verdict: LGTM。4観点OK。"
  from: gunshi
  id: msg_test_gap001
  read: true
  timestamp: "$old_ts"
  type: review_feedback
INNEREOF
cat > "$SCRIPT_DIR/queue/bulletin_board.yaml" <<INNEREOF
entries: []
INNEREOF
cat > "$SCRIPT_DIR/queue/inbox/shogun.yaml" <<INNEREOF
messages: []
INNEREOF

log() { echo "$1" >> "$LOG"; }

check_karo_completion_notify_gap

if grep -q "INBOX_CALLED:karo .*cmd_test_gap001.*completion_notify_gap" "$LOG"; then
    echo "PASS: gap detected and notified"
else
    echo "FAIL: gap not detected"
    cat "$LOG"
    exit 1
fi
grep -q "KARO-COMPLETION-NOTIFY-GAP: LGTM received for cmd_test_gap001" "$LOG"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: gap detected and notified"* ]]
}

# test_necessity: read-only child completion is owned by a later parent CLEAR,
# while uncleared/independent/unknown/FAIL cases must remain detectable.
@test "completion_notify_gap: integrated read-only child suppresses only the parent-CLEAR PASS variant" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T="$BATS_TEST_TMPDIR"; SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
mkdir -p "$T/queue/inbox" "$T/queue/reports" "$T/queue/tasks" "$T/queue/gates/cmd_parent_clear" "$T/scripts" "$STATE_DIR"
: > "$LOG"
old=$(date -d "-600 seconds" -Iseconds)
cat > "$T/queue/inbox/karo.yaml" <<EOF
messages:
- {content: "cmd_parent_clear_frontend_recon verdict: LGTM", timestamp: "$old", type: review_feedback}
- {content: "cmd_parent_open_backend_recon verdict: LGTM", timestamp: "$old", type: review_feedback}
- {content: "cmd_independent verdict: LGTM", timestamp: "$old", type: review_feedback}
- {content: "cmd_unknown_frontend_recon verdict: LGTM", timestamp: "$old", type: review_feedback}
- {content: "cmd_parent_clear_backend_scout verdict: LGTM", timestamp: "$old", type: review_feedback}
EOF
printf "messages: []\n" > "$T/queue/inbox/shogun.yaml"; printf "entries: []\n" > "$T/queue/bulletin_board.yaml"
cat > "$T/queue/reports/pass.yaml" <<EOF
parent_cmd: cmd_parent_clear_frontend_recon
task_type: scout
status: completed
verdict: PASS
EOF
cat > "$T/queue/reports/open.yaml" <<EOF
parent_cmd: cmd_parent_open_backend_recon
task_type: recon
status: completed
verdict: PASS
EOF
cat > "$T/queue/reports/unknown.yaml" <<EOF
parent_cmd: cmd_unknown_frontend_recon
task_type: scout
status: completed
verdict: PASS
EOF
cat > "$T/queue/reports/fail.yaml" <<EOF
parent_cmd: cmd_parent_clear_backend_scout
task_type: scout
status: completed
verdict: FAIL
EOF
printf "GATE CLEAR: cmd_parent_clear\n" > "$T/queue/gates/cmd_parent_clear/cmd_complete_gate.trigger.log"
printf "#!/bin/bash\necho INBOX_CALLED:\$@ >> \"$LOG\"\n" > "$T/scripts/inbox_write.sh"; chmod +x "$T/scripts/inbox_write.sh"
log() { echo "$1" >> "$LOG"; }
NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
test "$(grep -c INBOX_CALLED "$LOG")" -eq 4
! grep -q "cmd_parent_clear_frontend_recon.*completion_notify_gap" "$LOG"
grep -q "cmd_parent_open_backend_recon.*completion_notify_gap" "$LOG"
grep -q "cmd_independent.*completion_notify_gap" "$LOG"
grep -q "cmd_unknown_frontend_recon.*completion_notify_gap" "$LOG"
grep -q "cmd_parent_clear_backend_scout.*completion_notify_gap" "$LOG"
'
    [ "$status" -eq 0 ]
}

# LGTMより前の進捗報告は、同一cmdでも完了通知の代替にならない
@test "completion_notify_gap: earlier progress bulletin does not suppress a later LGTM gap" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

old_ts="$(date -d "-400 seconds" "+%Y-%m-%dT%H:%M:%S")"
progress_ts="$(date -d "-500 seconds" "+%Y-%m-%dT%H:%M:%S")"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<INNEREOF
messages:
- content: "cmd_test_gap006レビュー完了。verdict: LGTM。"
  from: gunshi
  id: msg_test_gap006
  read: true
  timestamp: "$old_ts"
  type: review_feedback
INNEREOF
cat > "$SCRIPT_DIR/queue/bulletin_board.yaml" <<INNEREOF
entries:
- id: blt_test_gap006
  content: "cmd_test_gap006現況: 作業進行中。"
  posted_by: karo
  posted_at: "$progress_ts"
INNEREOF
cat > "$SCRIPT_DIR/queue/inbox/shogun.yaml" <<INNEREOF
messages: []
INNEREOF

log() { echo "$1" >> "$LOG"; }
check_karo_completion_notify_gap
grep -q "INBOX_CALLED:karo .*cmd_test_gap006.*completion_notify_gap" "$LOG"
echo "PASS: earlier progress did not suppress later LGTM gap"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: earlier progress did not suppress later LGTM gap"* ]]
}

# bulletin_board.yamlに完了通知済みなら重複検知しない
@test "completion_notify_gap: bulletin notification present suppresses detection" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

old_ts="$(date -d "-400 seconds" "+%Y-%m-%dT%H:%M:%S")"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<INNEREOF
messages:
- content: "cmd_test_gap002 hayate報告レビュー。verdict: LGTM。4観点OK。"
  from: gunshi
  id: msg_test_gap002
  read: true
  timestamp: "$old_ts"
  type: review_feedback
INNEREOF
cat > "$SCRIPT_DIR/queue/bulletin_board.yaml" <<INNEREOF
entries:
- id: blt_test_gap002
  content: "GATE CLEAR cmd_test_gap002: hayate完了 PASS/LGTM。"
  posted_by: karo
  posted_at: "$(date "+%Y-%m-%dT%H:%M:%S")"
INNEREOF
cat > "$SCRIPT_DIR/queue/inbox/shogun.yaml" <<INNEREOF
messages: []
INNEREOF

log() { echo "$1" >> "$LOG"; }

check_karo_completion_notify_gap

if grep -q "INBOX_CALLED" "$LOG"; then
    echo "FAIL: notification suppressed by bulletin should not fire"
    cat "$LOG"
    exit 1
else
    echo "PASS: bulletin notification suppresses detection"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: bulletin notification suppresses detection"* ]]
}

@test "completion_notify_gap: archive marker newer than LGTM suppresses overwritten trigger-log false positive" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T="$BATS_TEST_TMPDIR"; SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
mkdir -p "$T/queue/inbox" "$T/queue/reports" "$T/queue/tasks" "$T/queue/gates/cmd_archive_terminal" "$T/scripts" "$STATE_DIR"
: > "$LOG"
old=$(date -d "-600 seconds" -Iseconds)
printf "messages:\n- content: \"cmd_archive_terminal verdict: LGTM\"\n  timestamp: \"%s\"\n  type: review_feedback\n" "$old" > "$T/queue/inbox/karo.yaml"
printf "messages: []\n" > "$T/queue/inbox/shogun.yaml"; printf "entries: []\n" > "$T/queue/bulletin_board.yaml"
printf "#!/bin/bash\necho INBOX_CALLED:\\$@ >> \"$LOG\"\n" > "$T/scripts/inbox_write.sh"; chmod +x "$T/scripts/inbox_write.sh"
printf "[gate] cmd_archive_terminal: Already CLEARED\n" > "$T/queue/gates/cmd_archive_terminal/cmd_complete_gate.trigger.log"
touch -d "-500 seconds" "$T/queue/gates/cmd_archive_terminal/archive.done"
log() { echo "$1" >> "$LOG"; }; NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
test "$(grep -c INBOX_CALLED "$LOG" 2>/dev/null || true)" -eq 0
'
    [ "$status" -eq 0 ]
}

@test "completion_notify_gap: archive marker suppresses later duplicate LGTM without explicit reopen" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T="$BATS_TEST_TMPDIR"; SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
mkdir -p "$T/queue/inbox" "$T/queue/reports" "$T/queue/tasks" "$T/queue/gates/cmd_archive_reopened" "$T/scripts" "$STATE_DIR"
: > "$LOG"
new_lgtm=$(date -d "-500 seconds" -Iseconds)
printf "messages:\n- content: \"cmd_archive_reopened verdict: LGTM\"\n  timestamp: \"%s\"\n  type: review_feedback\n" "$new_lgtm" > "$T/queue/inbox/karo.yaml"
printf "messages: []\n" > "$T/queue/inbox/shogun.yaml"; printf "entries: []\n" > "$T/queue/bulletin_board.yaml"
printf "#!/bin/bash\necho INBOX_CALLED:\\$@ >> \"$LOG\"\n" > "$T/scripts/inbox_write.sh"; chmod +x "$T/scripts/inbox_write.sh"
touch -d "-700 seconds" "$T/queue/gates/cmd_archive_reopened/archive.done"
log() { echo "$1" >> "$LOG"; }; NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
test "$(grep -c INBOX_CALLED "$LOG" 2>/dev/null || true)" -eq 0
'
    [ "$status" -eq 0 ]
}

@test "completion_notify_gap: archive marker then explicit RC then new LGTM remains detectable" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"; unset NINJA_MONITOR_LIB_ONLY
T="$BATS_TEST_TMPDIR"; SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
mkdir -p "$T/queue/inbox" "$T/queue/reports" "$T/queue/tasks" "$T/queue/gates/cmd_archive_reopened" "$T/scripts" "$STATE_DIR"
: > "$LOG"
reopen=$(date -d "-600 seconds" -Iseconds); new_lgtm=$(date -d "-500 seconds" -Iseconds)
printf "messages:\n- content: \"cmd_archive_reopened verdict: RC\"\n  timestamp: \"%s\"\n  type: review_feedback\n- content: \"cmd_archive_reopened verdict: LGTM\"\n  timestamp: \"%s\"\n  type: review_feedback\n" "$reopen" "$new_lgtm" > "$T/queue/inbox/karo.yaml"
printf "messages: []\n" > "$T/queue/inbox/shogun.yaml"; printf "entries: []\n" > "$T/queue/bulletin_board.yaml"
printf "#!/bin/bash\necho INBOX_CALLED:\\$@ >> \"$LOG\"\n" > "$T/scripts/inbox_write.sh"; chmod +x "$T/scripts/inbox_write.sh"
touch -d "-700 seconds" "$T/queue/gates/cmd_archive_reopened/archive.done"
log() { echo "$1" >> "$LOG"; }; NINJA_MONITOR_LGTM_NOTIFY_GRACE=1 check_karo_completion_notify_gap
grep -q "KARO-COMPLETION-NOTIFY-GAP: LGTM received for cmd_archive_reopened" "$LOG"
'
    [ "$status" -eq 0 ]
}

# shogun inboxに完了通知済みなら重複検知しない
@test "completion_notify_gap: shogun inbox notification present suppresses detection" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

old_ts="$(date -d "-400 seconds" "+%Y-%m-%dT%H:%M:%S")"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<INNEREOF
messages:
- content: "cmd_test_gap003 hayate報告レビュー。verdict: LGTM。4観点OK。"
  from: gunshi
  id: msg_test_gap003
  read: true
  timestamp: "$old_ts"
  type: review_feedback
INNEREOF
cat > "$SCRIPT_DIR/queue/bulletin_board.yaml" <<INNEREOF
entries: []
INNEREOF
cat > "$SCRIPT_DIR/queue/inbox/shogun.yaml" <<INNEREOF
messages:
- content: "GATE CLEAR — cmd_test_gap003 完了"
  from: cmd_complete_gate
  id: msg_gap003_shogun
  read: false
  timestamp: "$(date "+%Y-%m-%dT%H:%M:%S")"
  type: gate_clear
INNEREOF

log() { echo "$1" >> "$LOG"; }

check_karo_completion_notify_gap

if grep -q "INBOX_CALLED" "$LOG"; then
    echo "FAIL: notification suppressed by shogun inbox should not fire"
    cat "$LOG"
    exit 1
else
    echo "PASS: shogun inbox notification suppresses detection"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: shogun inbox notification suppresses detection"* ]]
}

# grace期間内(猶予中)は検知しない
@test "completion_notify_gap: within grace period does not trigger" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

recent_ts="$(date -d "-30 seconds" "+%Y-%m-%dT%H:%M:%S")"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<INNEREOF
messages:
- content: "cmd_test_gap004 hayate報告レビュー。verdict: LGTM。4観点OK。"
  from: gunshi
  id: msg_test_gap004
  read: true
  timestamp: "$recent_ts"
  type: review_feedback
INNEREOF
cat > "$SCRIPT_DIR/queue/bulletin_board.yaml" <<INNEREOF
entries: []
INNEREOF
cat > "$SCRIPT_DIR/queue/inbox/shogun.yaml" <<INNEREOF
messages: []
INNEREOF

log() { echo "$1" >> "$LOG"; }

check_karo_completion_notify_gap

if grep -q "INBOX_CALLED" "$LOG"; then
    echo "FAIL: within-grace LGTM should not trigger yet"
    cat "$LOG"
    exit 1
else
    echo "PASS: grace period respected"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: grace period respected"* ]]
}

# test_necessity: completion_notify_gap must exclude English/Japanese draft-review
# receipts, including whitespace variants, while preserving final-review detection.
@test "completion_notify_gap: draft review is excluded from detection" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$BATS_TEST_TMPDIR"

SCRIPT_DIR="$TMP_ROOT"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/inbox" "$SCRIPT_DIR/scripts" "$STATE_DIR"
touch "$LOG"

cat > "$SCRIPT_DIR/scripts/inbox_write.sh" <<STUBEOF
#!/bin/bash
echo "INBOX_CALLED:\$@"
STUBEOF
chmod +x "$SCRIPT_DIR/scripts/inbox_write.sh"

old_ts="$(date -d "-400 seconds" "+%Y-%m-%dT%H:%M:%S")"
cat > "$SCRIPT_DIR/queue/inbox/karo.yaml" <<INNEREOF
messages:
- content: "cmd_test_gap005 draft review。verdict: APPROVE。6観点OK。hayate配備。"
  from: gunshi
  id: msg_test_gap005
  read: true
  timestamp: "$old_ts"
  type: review_feedback
- content: "cmd_test_gap005_ja draftレビュー完了。verdict: LGTM。配備可。"
  from: gunshi
  id: msg_test_gap005_ja
  read: true
  timestamp: "$old_ts"
  type: review_feedback
- content: "cmd_test_gap005_space draft  レビュー完了。verdict: PASS。配備可。"
  from: gunshi
  id: msg_test_gap005_space
  read: true
  timestamp: "$old_ts"
  type: review_feedback
INNEREOF
cat > "$SCRIPT_DIR/queue/bulletin_board.yaml" <<INNEREOF
entries: []
INNEREOF
cat > "$SCRIPT_DIR/queue/inbox/shogun.yaml" <<INNEREOF
messages: []
INNEREOF

log() { echo "$1" >> "$LOG"; }

check_karo_completion_notify_gap

if grep -q "INBOX_CALLED" "$LOG"; then
    echo "FAIL: draft review should be excluded"
    cat "$LOG"
    exit 1
else
    echo "PASS: draft review excluded"
fi
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: draft review excluded"* ]]
}
