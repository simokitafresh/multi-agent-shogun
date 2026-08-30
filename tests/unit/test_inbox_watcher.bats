#!/usr/bin/env bats

# test_necessity: normal inbox nudgeは未読fingerprintではなくCLI generation
# 単位で一件だけ outstandingにし、ACKまたは世代変更後だけ再送できる。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

run_normal_fixture() {
    bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"
tmp="$(mktemp -d)"
trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/root/scripts/lib" "$tmp/root/lib" "$tmp/root/queue/inbox" "$tmp/state"
for f in lock_path.sh cli_lookup.sh tmux_utils.sh script_update.sh inbox_nudge_policy.sh respawn_recovery.sh pane_confirmation_guard.sh; do
  ln -s "$root/scripts/lib/$f" "$tmp/root/scripts/lib/$f"
done
ln -s "$root/lib/agent_state.sh" "$tmp/root/lib/agent_state.sh"
ln -s "$root/scripts/inbox_watcher.sh" "$tmp/root/scripts/inbox_watcher.sh"
cat > "$tmp/root/queue/inbox/fixture.yaml" <<YAML
messages:
- {id: msg_fixture, type: bulletin_notify, read: false, content: fixture}
YAML
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$tmp/root/scripts/inbox_watcher.sh" fixture dummy-pane
unset INBOX_WATCHER_LIB_ONLY
get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 0; }
respawn_recovery_generation() { echo "$GENERATION"; }
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
      esac
      ;;
    show-options) echo codex ;;
    set-buffer) printf "%s\n" "$4" >> "$tmp/nudges" ;;
    paste-buffer) printf "paste\n" >> "$tmp/events" ;;
    send-keys) printf "enter\n" >> "$tmp/events" ;;
    set-option) : ;;
  esac
}

CURRENT_CLI_GENERATION="$GENERATION"
for event in 2:fp-two 3:fp-three 4:fp-four 4:fp-four 4:fp-four; do
  count="${event%%:*}"
  fp="${event#*:}"
  send_wakeup "$count" false "$fp" normal false false
done
printf "baseline_send=5 actual_send=%s\n" "$(grep -c "^paste$" "$tmp/events")"
printf "lease_files=%s\n" "$(find "$tmp/state" -maxdepth 1 -name "*outstanding_lease*" -type f | wc -l)"

# A read transition (unread 4 -> 1) is an ACK; the next normal nudge is then
# allowed within the same generation even though one unread message remains.
send_wakeup 1 false fp-after-ack normal false false
printf "after_ack_send=%s\n" "$(grep -c "^paste$" "$tmp/events")"

# A generation change invalidates the current-generation lease and permits
# the same unread fingerprint to reach the replacement CLI.
GENERATION=generation-2
invalidate_leases_on_generation_change
send_wakeup 4 false fp-after-ack normal false false
printf "after_generation_send=%s\n" "$(grep -c "^paste$" "$tmp/events")"
'
}

@test "normal unread changes claim one generation lease (5 attempted, 1 delivered)" {
    export GENERATION=generation-1
    run run_normal_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"baseline_send=5 actual_send=1"* ]]
    [[ "$output" == *"lease_files=1"* ]]
    [[ "$output" == *"after_ack_send=2"* ]]
    [[ "$output" == *"after_generation_send=3"* ]]
}

@test "normal lease is generation keyed rather than fingerprint keyed" {
    run grep -n "outstanding_lease_file_for_generation\|OUTSTANDING-LEASE" "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
    [ "$(printf "%s\n" "$output" | grep -c "outstanding_lease_file_for_generation")" -ge 2 ]
    [[ "$output" == *"OUTSTANDING-LEASE"* ]]
}
