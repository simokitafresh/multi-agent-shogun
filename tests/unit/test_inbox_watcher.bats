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
for event in 3:fp-three 2:fp-two 4:fp-four 4:fp-four 4:fp-four; do
  count="${event%%:*}"
  fp="${event#*:}"
  send_wakeup "$count" false "$fp" normal false false
done
printf "baseline_send=5 actual_send=%s\n" "$(grep -c "^paste$" "$tmp/events")"
printf "lease_files=%s\n" "$(find "$tmp/state" -maxdepth 1 -name "*outstanding_lease*" -type f | wc -l)"

# A read transition (unread 3 -> 2) is not an ACK; the same generation lease
# remains outstanding even though unread messages remain.
send_wakeup 2 false fp-after-decrease normal false false
send_wakeup 4 false fp-after-decrease normal false false
printf "after_decrease_send=%s\n" "$(grep -c "^paste$" "$tmp/events")"

# The empty-inbox boundary releases the lease, allowing the next unread set
# to claim one delivery in the same CLI generation.
get_unread_info() { printf "0\tfalse\t-\t-\tfalse\tnormal\tfalse\n"; }
process_unread
printf "after_empty_lease_files=%s\n" "$(find "$tmp/state" -maxdepth 1 -name "*outstanding_lease*" -type f | wc -l)"
send_wakeup 1 false fp-after-empty normal false false
printf "after_empty_send=%s\n" "$(grep -c "^paste$" "$tmp/events")"

# A generation change invalidates the current-generation lease and permits
# the same unread fingerprint to reach the replacement CLI.
GENERATION=generation-2
invalidate_leases_on_generation_change
send_wakeup 4 false fp-after-empty normal false false
printf "after_generation_send=%s\n" "$(grep -c "^paste$" "$tmp/events")"

# High-priority task_assigned nudges share the same generation lease.  A
# delivery-verification rearm/retry and an unread decrease must not create a
# second nudge while unread messages remain.
get_unread_info() { printf "0\tfalse\t-\t-\tfalse\tnormal\tfalse\n"; }
process_unread
send_wakeup 4 true fp-high-four high false false msg-high-four
send_wakeup 2 true fp-high-two high false false msg-high-two
printf "high_after_decrease_send=%s\n" "$(grep -c "^paste$" "$tmp/events")"
printf "high_lease_files=%s\n" "$(find "$tmp/state" -maxdepth 1 -name "*outstanding_lease*" -type f | wc -l)"
get_unread_info() { printf "0\tfalse\t-\t-\tfalse\tnormal\tfalse\n"; }
process_unread
send_wakeup 1 true fp-high-after-empty high false false msg-high-after-empty
printf "high_after_empty_send=%s\n" "$(grep -c "^paste$" "$tmp/events")"
'
}

@test "normal lease survives unread decrease and clears only at empty or generation change" {
    export GENERATION=generation-1
    run run_normal_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"baseline_send=5 actual_send=1"* ]]
    [[ "$output" == *"lease_files=1"* ]]
    [[ "$output" == *"after_decrease_send=1"* ]]
    [[ "$output" == *"after_empty_lease_files=0"* ]]
    [[ "$output" == *"after_empty_send=2"* ]]
    [[ "$output" == *"after_generation_send=3"* ]]
    [[ "$output" == *"high_after_decrease_send=4"* ]]
    [[ "$output" == *"high_lease_files=1"* ]]
    [[ "$output" == *"high_after_empty_send=5"* ]]
}

@test "normal lease is generation keyed rather than fingerprint keyed" {
    run grep -n "outstanding_lease_file_for_generation\|OUTSTANDING-LEASE" "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ "$status" -eq 0 ]
    [ "$(printf "%s\n" "$output" | grep -c "outstanding_lease_file_for_generation")" -ge 2 ]
    [[ "$output" == *"OUTSTANDING-LEASE"* ]]
}

# test_necessity: same-generation unrelated unread rows cannot suppress a new
# current-task assignment, while the same current-task ID set remains deduped
# and the confirmation guard never pastes the nudge into a prompt.
@test "current-task assignment ID expires only its bounded generation lease" {
    run bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"
tmp="$(mktemp -d)"
trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/root/scripts/lib" "$tmp/root/lib" "$tmp/root/queue/inbox" "$tmp/root/queue/tasks" "$tmp/state"
for f in lock_path.sh cli_lookup.sh tmux_utils.sh script_update.sh inbox_nudge_policy.sh respawn_recovery.sh pane_confirmation_guard.sh; do
  ln -s "$root/scripts/lib/$f" "$tmp/root/scripts/lib/$f"
done
ln -s "$root/lib/agent_state.sh" "$tmp/root/lib/agent_state.sh"
ln -s "$root/scripts/inbox_watcher.sh" "$tmp/root/scripts/inbox_watcher.sh"
cat > "$tmp/root/queue/tasks/fixture.yaml" <<YAML
task_id: current-task
parent_cmd: cmd_current
YAML
cat > "$tmp/root/queue/inbox/fixture.yaml" <<YAML
messages:
- id: msg-current-1
  type: task_assigned
  read: false
  task_id: current-task
  parent_cmd: cmd_current
- id: msg-other-1
  type: task_assigned
  read: false
  task_id: other-task
  parent_cmd: cmd_other
- id: msg-empty-1
  type: task_assigned
  read: false
  task_id: ""
  parent_cmd: ""
YAML
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$tmp/root/scripts/inbox_watcher.sh" fixture dummy-pane
unset INBOX_WATCHER_LIB_ONLY
get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 0; }
respawn_recovery_generation() { echo generation-1; }
CURRENT_CLI_GENERATION=generation-1
pane_input_line_has_text() { return 1; }
sleep() { :; }
timeout() { shift; "$@"; }
_pane_has_confirmation_prompt() { return 1; }
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
    set-buffer) : ;;
    paste-buffer) printf "paste\n" >> "$tmp/events" ;;
    send-keys) printf "enter\n" >> "$tmp/events" ;;
    set-option) : ;;
  esac
}
paste_count() { [ -f "$tmp/events" ] && grep -c "^paste$" "$tmp/events" || echo 0; }

send_wakeup 3 true initial-fp normal false false msg-current-1
send_wakeup 3 true initial-fp normal false false msg-current-1
printf "same_set_pastes=%s\n" "$(paste_count)"

cat >> "$tmp/root/queue/inbox/fixture.yaml" <<YAML
- id: msg-current-2
  type: task_assigned
  read: false
  task_id: current-task
  parent_cmd: cmd_current
YAML
send_wakeup 4 true changed-fp normal false false msg-current-2
printf "new_current_id_pastes=%s\n" "$(paste_count)"

cat >> "$tmp/root/queue/inbox/fixture.yaml" <<YAML
- id: msg-current-3
  type: task_assigned
  read: false
  task_id: current-task
  parent_cmd: cmd_current
YAML
_pane_has_confirmation_prompt() { return 0; }
if send_wakeup 5 true changed-again normal false false msg-current-3; then
  guard_rc=0
else
  guard_rc=$?
fi
printf "confirmation_rc=%s\n" "$guard_rc"
printf "confirmation_pastes=%s\n" "$(paste_count)"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"same_set_pastes=1"* ]]
    [[ "$output" == *"new_current_id_pastes=2"* ]]
    [[ "$output" == *"confirmation_rc=2"* ]]
    [[ "$output" == *"confirmation_pastes=2"* ]]
}

# test_necessity: watcher自己再起動時、同一CLI世代の旧fingerprint tokenを
# generation leaseへ引き継ぎ、旧paste直後の重複pasteを防ぐ契約を守る。
@test "legacy fingerprint lease migrates across watcher restart without duplicate paste" {
    export GENERATION=generation-1
    run bash -c '
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
    set-buffer) : ;;
    paste-buffer) printf "paste\n" >> "$tmp/events" ;;
    send-keys) printf "enter\n" >> "$tmp/events" ;;
    set-option) : ;;
  esac
}

CURRENT_CLI_GENERATION="$GENERATION"
paste_count() { [ -f "$tmp/events" ] && grep -c "^paste$" "$tmp/events" || echo 0; }
fingerprint="restart-fingerprint"
legacy="$tmp/state/inbox_watcher_sent_fixture_${fingerprint}"
: > "$legacy"
printf "%s\n" "$fingerprint" > "$tmp/state/inbox_watcher_fingerprint_fixture"

# 19:32:30 old watcher paste already happened; AUTO-RESTART keeps the same
# CLI generation and the new watcher now observes the same unread set.
send_wakeup 1 false "$fingerprint" normal false false
printf "restart_paste=%s\n" "$(paste_count)"
printf "legacy_exists=%s\n" "$(test -e "$legacy" && echo 1 || echo 0)"
lease="$tmp/state/inbox_watcher_sent_fixture_outstanding_lease_${GENERATION}"
printf "generation_lease=%s\n" "$(test -e "$lease" && echo 1 || echo 0)"

# A different unread set remains suppressed by the migrated generation lease.
send_wakeup 1 false new-fingerprint normal false false
printf "different_fp_paste=%s\n" "$(paste_count)"

# A real CLI generation change invalidates all inherited legacy state and
# allows the replacement CLI to receive the same unread set once.
GENERATION=generation-2
invalidate_leases_on_generation_change
send_wakeup 1 false new-fingerprint normal false false
printf "new_generation_paste=%s\n" "$(paste_count)"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"restart_paste=0"* ]]
    [[ "$output" == *"legacy_exists=0"* ]]
    [[ "$output" == *"generation_lease=1"* ]]
    [[ "$output" == *"different_fp_paste=0"* ]]
    [[ "$output" == *"new_generation_paste=1"* ]]
}

# test_necessity: 旧tokenが現fingerprintと一致しない場合、同一世代でも
# generation leaseへ誤移行せず、新しい未読集合を配送する契約を守る。
@test "stale legacy fingerprint token does not suppress a different unread set" {
    export GENERATION=generation-stale
    run bash -c '
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
    set-buffer) : ;;
    paste-buffer) printf "paste\n" >> "$tmp/events" ;;
    send-keys) printf "enter\n" >> "$tmp/events" ;;
    set-option) : ;;
  esac
}
paste_count() { [ -f "$tmp/events" ] && grep -c "^paste$" "$tmp/events" || echo 0; }

CURRENT_CLI_GENERATION="$GENERATION"
legacy="$tmp/state/inbox_watcher_sent_fixture_stale-fingerprint"
: > "$legacy"
send_wakeup 1 false new-fingerprint normal false false
printf "stale_paste=%s\n" "$(grep -c "^paste$" "$tmp/events")"
printf "stale_token_remains=%s\n" "$(test -e "$legacy" && echo 1 || echo 0)"
printf "generation_lease=%s\n" "$(find "$tmp/state" -maxdepth 1 -name "*outstanding_lease*" -type f | wc -l)"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale_paste=1"* ]]
    [[ "$output" == *"stale_token_remains=1"* ]]
    [[ "$output" == *"generation_lease=1"* ]]
}
