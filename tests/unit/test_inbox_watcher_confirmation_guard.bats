#!/usr/bin/env bats

# test_necessity: nudgeがCLI確認プロンプトの選択肢へ誤入力されず、通常paneだけが
# 一度配送され、確認promptでは未読メッセージと保留状態が保持される不変量を守る。

setup_file() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export WATCHER_SCRIPT="$PROJECT_ROOT/scripts/inbox_watcher.sh"
}

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export WATCHER_SCRIPT="$PROJECT_ROOT/scripts/inbox_watcher.sh"
}

run_fixture() {
    local confirmation="$1"
    CONFIRMATION_PROMPT="$confirmation" bash -c '
set -euo pipefail
root="'"$PROJECT_ROOT"'"
tmp="$(mktemp -d)"
trap "rm -rf \"$tmp\"" EXIT
mkdir -p "$tmp/queue/inbox" "$tmp/state"
cat > "$tmp/queue/inbox/fixture.yaml" <<YAML
messages:
- {id: msg_fixture, type: report_received, read: false, content: fixture}
YAML
export SHOGUN_STATE_DIR="$tmp/state" INBOX_WATCHER_LIB_ONLY=1
source "$root/scripts/inbox_watcher.sh" fixture dummy-pane
unset INBOX_WATCHER_LIB_ONLY
INBOX="$tmp/queue/inbox/fixture.yaml"

ensure_current_pane_target() { return 0; }
get_effective_cli_type() { printf "codex\n"; }
agent_has_self_watch() { return 1; }
check_agent_busy() { return 1; }
respawn_recovery_generation() { printf "generation-1\n"; }
pane_input_line_has_text() { return 1; }
sleep() { :; }
timeout() { shift; "$@"; }
TMUX_LOG="$tmp/tmux.log"
: > "$TMUX_LOG"
tmux() {
    case "$1" in
        show-options) printf "codex\n" ;;
        display-message)
            case "$*" in
                *pane_in_mode*) printf "0\n" ;;
                *agent_id*) printf "fixture\n" ;;
                *) printf "active\n" ;;
            esac
            ;;
        capture-pane)
            if [ "$CONFIRMATION_PROMPT" = "1" ]; then
                printf "Do you want to proceed?\n1. Yes\n2. No\n"
            fi
            ;;
        paste-buffer) printf "paste-buffer\n" >> "$TMUX_LOG" ;;
        send-keys) printf "send-keys\n" >> "$TMUX_LOG" ;;
        set-buffer|set-option) : ;;
    esac
}

rc=0
send_wakeup 1 false fixture-fp high false false || rc=$?
nudge_count="$(awk "/^paste-buffer$/ {n++} END {print n+0}" "$TMUX_LOG")"
unread_count="$(awk "/read: false/ {n++} END {print n+0}" "$INBOX")"
held=0
[ -s "$DEFERRED_NUDGE_FILE" ] && held=1
printf "prompt=%s rc=%s nudge=%s unread=%s held=%s reason=%s\n" \
    "$CONFIRMATION_PROMPT" "$rc" "$nudge_count" "$unread_count" "$held" \
    "$(awk -F= "/^reason=/ {print \$2}" "$DEFERRED_NUDGE_FILE" 2>/dev/null || true)"
'
}

@test "通常paneはnudge 1件、確認promptはnudge 0件かつ未読保持" {
    normal_output="$(run_fixture 0)"
    prompt_output="$(run_fixture 1)"
    [[ "$normal_output" == *"prompt=0 rc=0 nudge=1 unread=1 held=0"* ]]
    [[ "$prompt_output" == *"prompt=1 rc=2 nudge=0 unread=1 held=1 reason=confirmation_prompt"* ]]
}

@test "shared guardは確認promptを検知し通常paneを通す" {
    run bash -c '
set -euo pipefail
source "$1/scripts/lib/pane_confirmation_guard.sh"
tmux() { [ "$1" = capture-pane ] && printf "%s\n" "$PROMPT"; }
PROMPT="Do you want to proceed?"; _pane_has_confirmation_prompt pane
PROMPT="ordinary idle prompt"; ! _pane_has_confirmation_prompt pane
printf "confirmation_guard=2_patterns_checked\n"
' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = "confirmation_guard=2_patterns_checked" ]
}
