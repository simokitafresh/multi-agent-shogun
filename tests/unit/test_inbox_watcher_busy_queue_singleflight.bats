#!/usr/bin/env bats
# test_necessity: Codex busy中はagent単位でqueued nudgeを一件だけ許し、
# unread fingerprintの変化は永続inboxを変更せずdeferred状態へ集約する。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

run_busy_sequence() {
    bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"
tmp="$(mktemp -d)"
trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/root/scripts/lib" "$tmp/root/lib" "$tmp/root/queue/inbox" "$tmp/state"
for f in lock_path.sh cli_lookup.sh tmux_utils.sh script_update.sh inbox_nudge_policy.sh respawn_recovery.sh; do
  ln -s "$root/scripts/lib/$f" "$tmp/root/scripts/lib/$f"
done
ln -s "$root/lib/agent_state.sh" "$tmp/root/lib/agent_state.sh"
ln -s "$root/scripts/inbox_watcher.sh" "$tmp/root/scripts/inbox_watcher.sh"
cat > "$tmp/root/queue/inbox/fixture.yaml" <<YAML
messages:
- {id: msg_one, type: report_received, read: false, content: one}
- {id: msg_two, type: report_received, read: false, content: two}
YAML
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$tmp/root/scripts/inbox_watcher.sh" fixture dummy-pane
unset INBOX_WATCHER_LIB_ONLY
get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 1; }
respawn_recovery_generation() { echo generation-1; }
pane_input_line_has_text() { return 0; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
  case "$1" in
    display-message)
      case "${*: -1}" in
        *agent_id*) echo fixture ;;
        *pane_in_mode*) echo 0 ;;
        *) echo active ;;
      esac ;;
    *) : ;;
  esac
}
send_wakeup 1 false fp-one high false false
send_wakeup 2 false fp-two high false false || second_rc=$?
printf "second_rc=%s\n" "${second_rc:-0}"
printf "claim=%s\n" "$(cat "$BUSY_QUEUE_CLAIM_FILE")"
printf "deferred=%s\n" "$(cat "$DEFERRED_NUDGE_FILE")"
printf "unread=%s\n" "$(grep -c "read: false" "$INBOX")"
' 2>&1
}

@test "busy fingerprint変更はpaste一回・全message永続・deferred統合" {
    run run_busy_sequence
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '\[SEND-RESULT\] pasted')" -eq 1 ]
    [[ "$output" == *"[BUSY-QUEUE-COALESCE]"* ]]
    [[ "$output" == *"second_rc=2"* ]]
    [[ "$output" == *$'claim=generation-1\tfp-one\t'* ]]
    [[ "$output" == *"fingerprint=fp-two"* ]]
    [[ "$output" == *"unread=2"* ]]
}

@test "単一未読task_assignedのwatcher nudgeはdelivery identityを保持する" {
    run bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"
tmp="$(mktemp -d)"
trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/root/scripts/lib" "$tmp/root/lib" "$tmp/root/queue/inbox" "$tmp/root/queue/tasks" "$tmp/state"
for f in lock_path.sh cli_lookup.sh tmux_utils.sh script_update.sh inbox_nudge_policy.sh respawn_recovery.sh; do
  ln -s "$root/scripts/lib/$f" "$tmp/root/scripts/lib/$f"
done
ln -s "$root/lib/agent_state.sh" "$tmp/root/lib/agent_state.sh"
ln -s "$root/scripts/inbox_watcher.sh" "$tmp/root/scripts/inbox_watcher.sh"
cat > "$tmp/root/queue/inbox/fixture.yaml" <<YAML
messages:
- id: msg_task_identity
  type: task_assigned
  read: false
  content: task
YAML
cat > "$tmp/root/queue/tasks/fixture.yaml" <<YAML
task:
  status: assigned
  task_id: cmd_watcher_identity_001_normal
YAML
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$tmp/root/scripts/inbox_watcher.sh" fixture dummy-pane
unset INBOX_WATCHER_LIB_ONLY
get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 1; }
respawn_recovery_generation() { echo generation-1; }
pane_input_line_has_text() { return 1; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
  case "$1" in
    display-message)
      case "${*: -1}" in
        *agent_id*) echo fixture ;;
        *pane_in_mode*) echo 0 ;;
        *) echo active ;;
      esac ;;
    set-buffer) printf "%s\n" "$4" > "$tmp/nudge" ;;
    *) : ;;
  esac
}
send_wakeup 1 true fp-task high false false
grep -q "task_id=cmd_watcher_identity_001_normal" "$tmp/nudge"
grep -q "delivery_msg=msg_task_identity" "$tmp/nudge"
printf "delivery_identity=1 task_id=1\n"
' 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"delivery_identity=1"* ]]
}

@test "CLI generation変更はstale claimを回収できる" {
    run grep -n 'stored_generation.*claim_generation' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BUSY-QUEUE-STALE"* ]]
}

@test "同一generationでもBACKOFF経過claimは回収する" {
    run grep -n 'claim_age.*BACKOFF_SEC' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claim_age"* ]]
    [[ "$output" == *"BACKOFF_SEC"* ]]
}

@test "idleまたはunreadゼロ境界はclaimを解放する" {
    run grep -c 'rm -f "$BUSY_QUEUE_CLAIM_FILE"' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "忍者の報告到着と調査結果はhigh priorityでdebounceを迂回する" {
    run bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"
tmp="$(mktemp -d)"
trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/root/scripts/lib" "$tmp/root/lib" "$tmp/root/queue/inbox" "$tmp/state"
for f in lock_path.sh cli_lookup.sh tmux_utils.sh script_update.sh inbox_nudge_policy.sh respawn_recovery.sh; do
  ln -s "$root/scripts/lib/$f" "$tmp/root/scripts/lib/$f"
done
ln -s "$root/lib/agent_state.sh" "$tmp/root/lib/agent_state.sh"
ln -s "$root/scripts/inbox_watcher.sh" "$tmp/root/scripts/inbox_watcher.sh"
cat > "$tmp/root/queue/inbox/fixture.yaml" <<YAML
messages:
- id: msg_report
  type: report_received
  read: false
  content: report
- id: msg_investigation
  type: investigation_result
  read: false
  content: investigation
YAML
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$tmp/root/scripts/inbox_watcher.sh" fixture dummy-pane
get_unread_info
' 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\thigh\t'* ]]
}

@test "Claudeの欠落flagはlive idle stateから再調整しRECOVERYを発火しない" {
    run bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"
tmp="$(mktemp -d)"
trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/root/scripts/lib" "$tmp/root/lib" "$tmp/root/queue/inbox" "$tmp/state"
for f in lock_path.sh cli_lookup.sh tmux_utils.sh script_update.sh inbox_nudge_policy.sh respawn_recovery.sh; do
  ln -s "$root/scripts/lib/$f" "$tmp/root/scripts/lib/$f"
done
ln -s "$root/lib/agent_state.sh" "$tmp/root/lib/agent_state.sh"
ln -s "$root/scripts/inbox_watcher.sh" "$tmp/root/scripts/inbox_watcher.sh"
cat > "$tmp/root/queue/inbox/fixture.yaml" <<YAML
messages:
- {id: msg_idle_reconcile, type: report_received, read: false, content: report}
YAML
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$tmp/root/scripts/inbox_watcher.sh" fixture dummy-pane
unset INBOX_WATCHER_LIB_ONLY
ensure_current_pane_target() { return 0; }
_agent_state_has_busy_subprocess() { return 1; }
tmux() {
  case "$1" in
    display-message)
      case "${*: -1}" in
        *agent_id*) echo fixture ;;
        *agent_state*) echo idle ;;
        *) echo active ;;
      esac ;;
    *) : ;;
  esac
}
rm -f "$idle_flag"
FORCE_IDLE_AFTER_SEC=0 BUSY_TIMEOUT_SEC=0
if ! maybe_force_idle_flag claude 2>"$tmp/stderr"; then
  echo "reconcile_failed"
  exit 1
fi
test -f "$idle_flag"
! grep -q "RECOVERY" "$tmp/stderr"
grep -q "IDLE-RECONCILED" "$tmp/stderr"
printf "reconciled=1 recovery=0\n"
' 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled=1 recovery=0"* ]]
}

@test "Claudeのactive stateは欠落flagを再調整せずfail-closedする" {
    run bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"
tmp="$(mktemp -d)"
trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/root/scripts/lib" "$tmp/root/lib" "$tmp/root/queue/inbox" "$tmp/state"
for f in lock_path.sh cli_lookup.sh tmux_utils.sh script_update.sh inbox_nudge_policy.sh respawn_recovery.sh; do
  ln -s "$root/scripts/lib/$f" "$tmp/root/scripts/lib/$f"
done
ln -s "$root/lib/agent_state.sh" "$tmp/root/lib/agent_state.sh"
ln -s "$root/scripts/inbox_watcher.sh" "$tmp/root/scripts/inbox_watcher.sh"
printf "messages:\n" > "$tmp/root/queue/inbox/fixture.yaml"
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$tmp/root/scripts/inbox_watcher.sh" fixture dummy-pane
unset INBOX_WATCHER_LIB_ONLY
ensure_current_pane_target() { return 0; }
_agent_state_has_busy_subprocess() { return 1; }
tmux() {
  case "$1" in
    display-message)
      case "${*: -1}" in
        *agent_id*) echo fixture ;;
        *agent_state*) echo active ;;
        *) echo active ;;
      esac ;;
    *) : ;;
  esac
}
rm -f "$idle_flag"
if maybe_force_idle_flag claude 2>"$tmp/stderr"; then
  echo "unexpected_reconcile"
  exit 1
fi
test ! -e "$idle_flag"
! grep -q "RECOVERY" "$tmp/stderr"
printf "active_deferred=1 recovery=0\n"
' 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"active_deferred=1 recovery=0"* ]]
}
