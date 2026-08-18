#!/usr/bin/env bats

# test_necessity: Codexの明示idle promptは背景端末表示に関係なくdelivery
# boundaryとなり、既存busy claimを解放して後続nudgeを1回だけ配信する。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "Codex idle prompt releases a busy claim despite background terminals" {
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
- {id: msg_idle, type: report_received, read: false, content: idle}
YAML
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$tmp/root/scripts/inbox_watcher.sh" fixture dummy-pane
unset INBOX_WATCHER_LIB_ONLY
get_effective_cli_type() { echo codex; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 1; }
respawn_recovery_generation() { echo generation-1; }
sleep() { :; }
timeout() { shift; "$@"; }
tmux() {
  case "$1" in
    capture-pane)
      case " $* " in
        *" -e "*) printf "\\033[1m›\\033[0m \\033[2mWrite tests for @filename\\033[0m\\n" ;;
        *) printf "› Write tests for @filename\\n" ;;
      esac
      ;;
    display-message)
      case "${*: -1}" in
        *agent_id*) echo fixture ;;
        *pane_in_mode*) echo 0 ;;
        *) echo active ;;
      esac
      ;;
    *) : ;;
  esac
}
printf "generation-1\\told-fingerprint\\t%s\\n" "$EPOCHSECONDS" > "$BUSY_QUEUE_CLAIM_FILE"
send_wakeup 1 false new-fingerprint high false false
[ ! -e "$BUSY_QUEUE_CLAIM_FILE" ]
' 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"[SEND-RESULT] pasted"* ]]
    [[ "$output" != *"[BUSY-QUEUE-COALESCE]"* ]]
}

@test "Codex working prompt keeps singleflight busy claim" {
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
- {id: msg_busy, type: report_received, read: false, content: busy}
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
    capture-pane) printf "› typed work\\n" ;;
    display-message)
      case "${*: -1}" in
        *agent_id*) echo fixture ;;
        *pane_in_mode*) echo 0 ;;
        *) echo active ;;
      esac
      ;;
    *) : ;;
  esac
}
send_wakeup 1 false fp-one high false false
send_wakeup 1 false fp-one high false false || second_rc=$?
[ "${second_rc:-0}" -eq 2 ]
[ -e "$BUSY_QUEUE_CLAIM_FILE" ]
' 2>&1
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '\[SEND-RESULT\] pasted')" -eq 1 ]
    [[ "$output" == *"[BUSY-QUEUE-COALESCE]"* ]]
}
