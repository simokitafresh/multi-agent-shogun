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
    [[ "$output" == *$'claim=generation-1\tfp-one'* ]]
    [[ "$output" == *"fingerprint=fp-two"* ]]
    [[ "$output" == *"unread=2"* ]]
}

@test "CLI generation変更はstale claimを回収できる" {
    run grep -n 'stored_generation.*claim_generation' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BUSY-QUEUE-STALE"* ]]
}

@test "idleまたはunreadゼロ境界はclaimを解放する" {
    run grep -c 'rm -f "$BUSY_QUEUE_CLAIM_FILE"' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}
