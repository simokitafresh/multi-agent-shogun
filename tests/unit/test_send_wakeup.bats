#!/usr/bin/env bats
# test_necessity: wakeupはself-watch時の重複nudgeを避けfallback時もpayloadとEnterを確実に配送する
# test_send_wakeup.bats — send_wakeup() replacement unit tests
# send-keys撲滅: paste-buffer fallback + pgrep self-watch detection
#
# テスト構成:
#   T-SW-001: send_wakeup — active self-watch → skip nudge
#   T-SW-002: send_wakeup — no self-watch → fallback nudge
#   T-SW-003: send_wakeup — paste-buffer used instead of send-keys
#   T-SW-004: send_wakeup — fallback nudge includes Enter keystroke
#   T-SW-005: send_wakeup — timeout on paste-buffer
#   T-SW-006: agent_has_self_watch — detects inotifywait process
#   T-SW-007: agent_has_self_watch — watcher自身の子プロセスは除外
#   T-SW-008: agent_has_self_watch — no inotifywait → returns 1
#   T-SW-009: send_cli_command — /clear still uses send-keys (kept)
#   T-SW-010: send_cli_command — /model still uses send-keys (kept)
#   T-SW-011: process_unread — integration: self-watch skips nudge
#   T-SW-012: backward compat — no inotifywait installed → fallback works

# --- セットアップ ---

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export WATCHER_SCRIPT="$PROJECT_ROOT/scripts/inbox_watcher.sh"
    [ -f "$WATCHER_SCRIPT" ] || return 1
    python3 -c "import yaml" 2>/dev/null || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/send_wakeup_test.XXXXXX")"

    # Extract send_wakeup and helper functions for isolated testing
    # Create a mock environment with the functions but mock tmux commands
    export MOCK_LOG="$TEST_TMPDIR/tmux_calls.log"
    > "$MOCK_LOG"

    # Create mock tmux that logs calls
    export MOCK_TMUX="$TEST_TMPDIR/mock_tmux"
    cat > "$MOCK_TMUX" << 'MOCK'
#!/bin/bash
# Log all tmux calls
echo "tmux $*" >> "$MOCK_LOG"
# Simulate success
exit 0
MOCK
    chmod +x "$MOCK_TMUX"

    # Create mock timeout
    export MOCK_TIMEOUT="$TEST_TMPDIR/mock_timeout"
    cat > "$MOCK_TIMEOUT" << 'MOCK'
#!/bin/bash
# Strip timeout args, execute the rest
shift  # remove timeout duration
"$@"
MOCK
    chmod +x "$MOCK_TIMEOUT"

    # Create mock pgrep
    export MOCK_PGREP="$TEST_TMPDIR/mock_pgrep"
    # Default: no self-watch found
    cat > "$MOCK_PGREP" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_PGREP"

    # Create mock ps
    export MOCK_PS="$TEST_TMPDIR/mock_ps"
    cat > "$MOCK_PS" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_PS"

    # Create test inbox
    export TEST_INBOX_DIR="$TEST_TMPDIR/queue/inbox"
    mkdir -p "$TEST_INBOX_DIR"

    # Test harness: source functions from inbox_watcher.sh with mocked externals
    export TEST_HARNESS="$TEST_TMPDIR/test_harness.sh"
    cat > "$TEST_HARNESS" << HARNESS
#!/bin/bash
# Test harness with mocked tmux/pgrep
AGENT_ID="test_agent"
PANE_TARGET="test:0.0"
CLI_TYPE="claude"
INBOX="$TEST_INBOX_DIR/test_agent.yaml"
LOCKFILE="\${INBOX}.lock"
SEND_KEYS_TIMEOUT=5
SCRIPT_DIR="$PROJECT_ROOT"
ASW_SELF_PID=4242

# Override commands with mocks
tmux() { "$MOCK_TMUX" "\$@"; }
timeout() { "$MOCK_TIMEOUT" "\$@"; }
pgrep() { "$MOCK_PGREP" "\$@"; }
ps() { "$MOCK_PS" "\$@"; }
export -f tmux timeout pgrep ps

_pid_is_descendant_of_self() {
    local candidate_pid="\$1"
    local self_pid="\${ASW_SELF_PID:-\$\$}"
    local parent_pid=""

    while [[ "\$candidate_pid" =~ ^[0-9]+$ ]] && [ "\$candidate_pid" -gt 1 ]; do
        if [ "\$candidate_pid" = "\$self_pid" ]; then
            return 0
        fi

        parent_pid=\$(ps -p "\$candidate_pid" -o ppid= 2>/dev/null | awk 'NR==1 {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')
        if ! [[ "\$parent_pid" =~ ^[0-9]+$ ]] || [ "\$parent_pid" = "\$candidate_pid" ]; then
            break
        fi

        candidate_pid="\$parent_pid"
    done

    return 1
}

_pid_has_live_parent() {
    local candidate_pid="\$1"
    local parent_pid=""

    [[ "\$candidate_pid" =~ ^[0-9]+$ ]] || return 1

    parent_pid=\$(ps -p "\$candidate_pid" -o ppid= 2>/dev/null | awk 'NR==1 {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')
    [[ "\$parent_pid" =~ ^[0-9]+$ ]] || return 1
    [ "\$parent_pid" -gt 1 ] || return 1

    ps -p "\$parent_pid" >/dev/null 2>&1
}

agent_has_self_watch() {
    local watch_pids pid
    watch_pids=\$(pgrep -f "inotifywait.*inbox/\${AGENT_ID}.yaml" 2>/dev/null || true)
    [ -n "\$watch_pids" ] || return 1

    for pid in \$watch_pids; do
        if _pid_has_live_parent "\$pid" && ! _pid_is_descendant_of_self "\$pid"; then
            return 0
        fi
    done

    return 1
}

# New send_wakeup with fallback logic
send_wakeup() {
    local unread_count="\$1"
    local nudge="inbox\${unread_count}"

    # Check if agent is self-watching (has inotifywait on its inbox)
    if agent_has_self_watch; then
        echo "[SKIP] Agent \$AGENT_ID has active self-watch" >&2
        return 0
    fi

    # Fallback: paste-buffer instead of send-keys
    echo "[FALLBACK] Sending paste-buffer nudge to \$AGENT_ID" >&2

    tmux set-buffer -b "nudge_\${AGENT_ID}" "\$nudge"
    if ! timeout "\$SEND_KEYS_TIMEOUT" tmux paste-buffer -t "\$PANE_TARGET" -b "nudge_\${AGENT_ID}" -d 2>/dev/null; then
        echo "[WARN] paste-buffer timed out" >&2
        return 1
    fi
    sleep 0.02
    if ! timeout "\$SEND_KEYS_TIMEOUT" tmux send-keys -t "\$PANE_TARGET" Enter 2>/dev/null; then
        echo "[WARN] send-keys Enter timed out" >&2
        return 1
    fi

    echo "[OK] Fallback nudge sent to \$AGENT_ID (\${unread_count} unread)" >&2
    return 0
}

# send_cli_command (unchanged — still uses send-keys)
send_cli_command() {
    local cmd="\$1"
    local actual_cmd="\$cmd"
    echo "[CLI] Sending CLI command: \$actual_cmd" >&2
    timeout "\$SEND_KEYS_TIMEOUT" tmux send-keys -t "\$PANE_TARGET" "\$actual_cmd" 2>/dev/null || return 1
    sleep 0.02
    timeout "\$SEND_KEYS_TIMEOUT" tmux send-keys -t "\$PANE_TARGET" Enter 2>/dev/null || return 1
    return 0
}
HARNESS
    chmod +x "$TEST_HARNESS"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "T-SW-013: inbox_watcher resolves queue/inbox symlink to real file" {
    local root="$TEST_TMPDIR/root"
    local real_inbox="$TEST_TMPDIR/real_inbox"
    mkdir -p "$root/scripts/lib" "$root/lib" "$root/queue" "$real_inbox"
    ln -s "$real_inbox" "$root/queue/inbox"
    ln -s "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$root/scripts/lib/lock_path.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/cli_lookup.sh" "$root/scripts/lib/cli_lookup.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/tmux_utils.sh" "$root/scripts/lib/tmux_utils.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/script_update.sh" "$root/scripts/lib/script_update.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/respawn_recovery.sh" "$root/scripts/lib/respawn_recovery.sh"
    ln -s "$PROJECT_ROOT/lib/agent_state.sh" "$root/lib/agent_state.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/inbox_nudge_policy.sh" "$root/scripts/lib/inbox_nudge_policy.sh"
    ln -s "$PROJECT_ROOT/scripts/inbox_watcher.sh" "$root/scripts/inbox_watcher.sh"
    cat > "$real_inbox/test_agent.yaml" <<'YAML'
messages:
- content: 'symlink'
  from: 'karo'
  id: 'msg_symlink'
  read: false
  timestamp: '2026-06-19T00:00:00'
  type: 'task_assigned'
YAML

    run bash -c "INBOX_WATCHER_LIB_ONLY=1 source '$root/scripts/inbox_watcher.sh' test_agent dummy-pane; printf '%s\n' \"\$INBOX\"; get_unread_info"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$real_inbox/test_agent.yaml"* ]]
    [[ "$output" == *$'1\tfalse\t'* ]]
}

@test "T-SW-014: inbox_watcher alerts and exits on broken queue/inbox symlink" {
    local root="$TEST_TMPDIR/root_broken"
    mkdir -p "$root/scripts/lib" "$root/lib" "$root/queue"
    ln -s "$TEST_TMPDIR/missing_inbox_target" "$root/queue/inbox"
    ln -s "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$root/scripts/lib/lock_path.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/cli_lookup.sh" "$root/scripts/lib/cli_lookup.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/tmux_utils.sh" "$root/scripts/lib/tmux_utils.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/script_update.sh" "$root/scripts/lib/script_update.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/respawn_recovery.sh" "$root/scripts/lib/respawn_recovery.sh"
    ln -s "$PROJECT_ROOT/lib/agent_state.sh" "$root/lib/agent_state.sh"
    ln -s "$PROJECT_ROOT/scripts/lib/inbox_nudge_policy.sh" "$root/scripts/lib/inbox_nudge_policy.sh"
    ln -s "$PROJECT_ROOT/scripts/inbox_watcher.sh" "$root/scripts/inbox_watcher.sh"

    run bash -c "INBOX_WATCHER_LIB_ONLY=1 source '$root/scripts/inbox_watcher.sh' test_agent dummy-pane"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: queue/inbox symlink is broken"* ]]
}

@test "T-SW-015: bulletin_notify unread set is classified as batchable" {
    cat > "$TEST_INBOX_DIR/test_agent.yaml" <<'YAML'
messages:
- content: first
  from: karo
  id: msg_batch_1
  read: false
  timestamp: '2026-07-20T00:00:00'
  type: bulletin_notify
- content: second
  from: gunshi
  id: msg_batch_2
  read: false
  timestamp: '2026-07-20T00:00:01'
  type: bulletin_notify
YAML

    run bash -c "SHOGUN_STATE_DIR='$TEST_TMPDIR' INBOX_WATCHER_LIB_ONLY=1 source '$WATCHER_SCRIPT' test_agent dummy-pane; INBOX='$TEST_INBOX_DIR/test_agent.yaml'; get_unread_info"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\tnormal\ttrue' ]]
}

@test "T-SW-016: escalation is high priority and never batchable" {
    cat > "$TEST_INBOX_DIR/test_agent.yaml" <<'YAML'
messages:
- content: urgent
  from: karo
  id: msg_urgent_1
  read: false
  timestamp: '2026-07-20T00:00:00'
  type: escalation
YAML

    run bash -c "SHOGUN_STATE_DIR='$TEST_TMPDIR' INBOX_WATCHER_LIB_ONLY=1 source '$WATCHER_SCRIPT' test_agent dummy-pane; INBOX='$TEST_INBOX_DIR/test_agent.yaml'; get_unread_info"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\thigh\tfalse' ]]
}

# test_necessity: a new task wake-up must never authorize a ninja to apply a
# read or different-task RC/supplement; doing so can turn a fresh implementation
# assignment into a false fixed-HEAD/code-change prohibition.
@test "T-SW-025: task wake-up scopes supplements to unread current task identity" {
    local deploy_source watcher_source
    deploy_source="$(<"$PROJECT_ROOT/scripts/deploy_task.sh")"
    watcher_source="$(<"$WATCHER_SCRIPT")"

    [[ "$deploy_source" == *"read:falseかつ現task_id一致"* ]]
    [ "$(grep -o 'read:falseかつ現task_id一致' "$WATCHER_SCRIPT" | wc -l)" -eq 2 ]
    [[ "$deploy_source$watcher_source" != *"既存成果の再利用可否はinbox本文とRC指示に従え"* ]]
}

@test "T114: both watcher task-assigned nudge branches include current task_id" {
    run bash -c "grep -F -c 'nudge=\"\${nudge} — task_id=\${task_id} 現task YAML' '$WATCHER_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}

# --- T-SW-001: self-watch active → skip nudge ---

@test "T-SW-001: send_wakeup skips nudge when agent has active self-watch" {
    # Mock pgrep to find inotifywait
    cat > "$MOCK_PGREP" << 'MOCK'
#!/bin/bash
echo "12345 inotifywait -q -t 120 -e modify inbox/test_agent.yaml"
exit 0
MOCK
    chmod +x "$MOCK_PGREP"

    cat > "$MOCK_PS" << 'MOCK'
#!/bin/bash
if [ "$1" = "-p" ] && [ "$2" = "12345" ]; then
    echo " 54321"
    exit 0
fi
if [ "$1" = "-p" ] && [ "$2" = "54321" ]; then
    echo " 2222"
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_PS"

    run bash -c "source '$TEST_HARNESS' && send_wakeup 3"
    [ "$status" -eq 0 ]

    # Verify no tmux calls were made (nudge was skipped)
    [ ! -s "$MOCK_LOG" ]

    # Verify skip message in stderr
    echo "$output" | grep -q "SKIP"
}

# --- T-SW-002: no self-watch → fallback nudge ---

@test "T-SW-002: send_wakeup sends fallback nudge when no self-watch" {
    # Default mock_pgrep returns 1 (no self-watch)
    run bash -c "source '$TEST_HARNESS' && send_wakeup 5"
    [ "$status" -eq 0 ]

    # Verify tmux calls were made
    [ -s "$MOCK_LOG" ]
    grep -q "set-buffer" "$MOCK_LOG"
    grep -q "paste-buffer" "$MOCK_LOG"

    # Verify fallback message
    echo "$output" | grep -q "FALLBACK"
}

# --- T-SW-003: paste-buffer used instead of send-keys for nudge ---

@test "T-SW-003: fallback nudge uses paste-buffer not send-keys for content" {
    run bash -c "source '$TEST_HARNESS' && send_wakeup 3"
    [ "$status" -eq 0 ]

    # paste-buffer should be used for the nudge content
    grep -q "set-buffer -b nudge_test_agent inbox3" "$MOCK_LOG"
    grep -q "paste-buffer -t test:0.0 -b nudge_test_agent -d" "$MOCK_LOG"

    # send-keys should ONLY be used for Enter (not for the nudge text itself)
    local sendkeys_count
    sendkeys_count=$(grep -c "send-keys" "$MOCK_LOG")
    [ "$sendkeys_count" -eq 1 ]  # Only the Enter keystroke

    grep -q "send-keys -t test:0.0 Enter" "$MOCK_LOG"
}

# --- T-SW-004: fallback nudge includes Enter ---

@test "T-SW-004: fallback nudge sends Enter after paste-buffer" {
    run bash -c "source '$TEST_HARNESS' && send_wakeup 1"
    [ "$status" -eq 0 ]

    # Verify order: set-buffer → paste-buffer → send-keys Enter
    local log_content
    log_content=$(cat "$MOCK_LOG")

    local line1 line2 line3
    line1=$(sed -n '1p' "$MOCK_LOG")
    line2=$(sed -n '2p' "$MOCK_LOG")
    line3=$(sed -n '3p' "$MOCK_LOG")

    echo "$line1" | grep -q "set-buffer"
    echo "$line2" | grep -q "paste-buffer"
    echo "$line3" | grep -q "send-keys.*Enter"
}

# --- T-SW-005: timeout on paste-buffer ---

@test "T-SW-005: send_wakeup handles paste-buffer timeout gracefully" {
    # Mock tmux to fail on paste-buffer
    cat > "$MOCK_TMUX" << 'MOCK'
#!/bin/bash
echo "tmux $*" >> "$MOCK_LOG"
if echo "$*" | grep -q "paste-buffer"; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_TMUX"

    run bash -c "source '$TEST_HARNESS' && send_wakeup 2"
    [ "$status" -eq 1 ]  # Should fail

    echo "$output" | grep -qi "timed out\|WARN"
}

# --- T-SW-006: agent_has_self_watch — detects inotifywait ---

@test "T-SW-006: agent_has_self_watch returns 0 when inotifywait running" {
    cat > "$MOCK_PGREP" << 'MOCK'
#!/bin/bash
echo "99999 inotifywait -q -t 120 -e modify inbox/test_agent.yaml"
exit 0
MOCK
    chmod +x "$MOCK_PGREP"

    cat > "$MOCK_PS" << 'MOCK'
#!/bin/bash
if [ "$1" = "-p" ] && [ "$2" = "99999" ]; then
    echo " 54321"
    exit 0
fi
if [ "$1" = "-p" ] && [ "$2" = "54321" ]; then
    echo " 2222"
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_PS"

    run bash -c "source '$TEST_HARNESS' && agent_has_self_watch"
    [ "$status" -eq 0 ]
}

# --- T-SW-007: agent_has_self_watch — no inotifywait ---

@test "T-SW-007: agent_has_self_watch ignores watcher-owned inotifywait child" {
    cat > "$MOCK_PGREP" << 'MOCK'
#!/bin/bash
echo "99999"
exit 0
MOCK
    chmod +x "$MOCK_PGREP"

    cat > "$MOCK_PS" << 'MOCK'
#!/bin/bash
if [ "$1" = "-p" ] && [ "$2" = "99999" ]; then
    echo " 4242"
    exit 0
fi
if [ "$1" = "-p" ] && [ "$2" = "4242" ]; then
    echo " 1"
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_PS"

    run bash -c "source '$TEST_HARNESS' && agent_has_self_watch"
    [ "$status" -eq 1 ]
}

# --- T-SW-008: agent_has_self_watch — no inotifywait ---

@test "T-SW-008: agent_has_self_watch returns 1 when no inotifywait" {
    # Default mock returns 1
    run bash -c "source '$TEST_HARNESS' && agent_has_self_watch"
    [ "$status" -eq 1 ]
}

@test "T-SW-008b: agent_has_self_watch ignores orphaned stale inotifywait" {
    cat > "$MOCK_PGREP" << 'MOCK'
#!/bin/bash
echo "99999"
exit 0
MOCK
    chmod +x "$MOCK_PGREP"

    cat > "$MOCK_PS" << 'MOCK'
#!/bin/bash
if [ "$1" = "-p" ] && [ "$2" = "99999" ]; then
    echo " 1"
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_PS"

    run bash -c "source '$TEST_HARNESS' && agent_has_self_watch"
    [ "$status" -eq 1 ]
}

# --- T-SW-009: /clear still uses send-keys ---

@test "T-SW-009: send_cli_command /clear still uses send-keys (kept)" {
    run bash -c "source '$TEST_HARNESS' && send_cli_command /clear"
    [ "$status" -eq 0 ]

    # CLI commands use send-keys directly (not paste-buffer)
    grep -q "send-keys -t test:0.0 /clear" "$MOCK_LOG"
    grep -q "send-keys -t test:0.0 Enter" "$MOCK_LOG"

    # No paste-buffer for CLI commands
    ! grep -q "paste-buffer" "$MOCK_LOG"
}

# --- T-SW-010: /model still uses send-keys ---

@test "T-SW-010: send_cli_command /model still uses send-keys (kept)" {
    run bash -c "source '$TEST_HARNESS' && send_cli_command '/model opus'"
    [ "$status" -eq 0 ]

    grep -q "send-keys -t test:0.0 /model opus" "$MOCK_LOG"
    ! grep -q "paste-buffer" "$MOCK_LOG"
}

# --- T-SW-011: nudge content format ---

@test "T-SW-011: nudge content format is inboxN (backward compatible)" {
    run bash -c "source '$TEST_HARNESS' && send_wakeup 7"
    [ "$status" -eq 0 ]

    # The nudge text should be "inbox7"
    grep -q "set-buffer -b nudge_test_agent inbox7" "$MOCK_LOG"
}

# --- T-SW-012: backward compat — functions exist ---

@test "T-SW-012: inbox_watcher.sh contains send_wakeup and agent_has_self_watch functions" {
    # After implementation, verify the new functions exist in the script
    grep -q "send_wakeup()" "$WATCHER_SCRIPT"
    grep -q "agent_has_self_watch\|pgrep.*inotifywait\|paste-buffer" "$WATCHER_SCRIPT"
}

# test_necessity: Claudeのdim表示されたidle提案を実入力と誤認して未読配送を永久延期せず、実入力は引き続き保護する不変量を守る。
@test "T-SW-017: Claude dim idle suggestion is not treated as typed input" {
    run bash -c "INBOX_WATCHER_LIB_ONLY=1 source '$WATCHER_SCRIPT' test_agent dummy-pane; tmux() { if [[ \" \$* \" == *' -e '* ]]; then printf '\\033[39m❯ \\033[7mT\\033[0;2mry\\033[0m \\033[2m\"fix typecheck errors\"\\033[0m\\n'; else printf '❯ Try \"fix typecheck errors\"\\n'; fi; }; pane_input_line_has_text test:0.0 claude"
    [ "$status" -eq 1 ]
}

@test "T-SW-018: Claude non-dim typed input remains protected" {
    run bash -c "INBOX_WATCHER_LIB_ONLY=1 source '$WATCHER_SCRIPT' test_agent dummy-pane; tmux() { printf '❯ deploy now\\n'; }; pane_input_line_has_text test:0.0 claude"
    [ "$status" -eq 0 ]
}

# test_necessity: CLI世代変更時に旧delivery leaseが失効し、同一fingerprintの再配送が偽dedupされない不変量を守る。
@test "T-SW-019: generation change invalidates sent_token delivery leases" {
    local state_dir="$TEST_TMPDIR/gen_state"
    mkdir -p "$state_dir"

    # Create sent_token and fingerprint files simulating previous generation delivery
    touch "${state_dir}/inbox_watcher_sent_test_agent_abc123"
    touch "${state_dir}/inbox_watcher_sent_test_agent_def456"
    echo "old_fp" > "${state_dir}/inbox_watcher_fingerprint_test_agent"
    echo "1000" > "${state_dir}/inbox_watcher_last_nudge_test_agent"

    [ -f "${state_dir}/inbox_watcher_sent_test_agent_abc123" ]

    run bash -c "
        SHOGUN_STATE_DIR='$state_dir' INBOX_WATCHER_LIB_ONLY=1 source '$WATCHER_SCRIPT' test_agent dummy-pane
        STATE_DIR='$state_dir'
        FINGERPRINT_FILE='${state_dir}/inbox_watcher_fingerprint_test_agent'
        DEBOUNCE_FILE='${state_dir}/inbox_watcher_last_nudge_test_agent'
        CURRENT_CLI_GENERATION='100:5000'
        respawn_recovery_generation() { echo '200:6000'; }
        invalidate_leases_on_generation_change
        ls '${state_dir}/inbox_watcher_sent_test_agent_'* 2>/dev/null && echo 'TOKENS_EXIST' || echo 'TOKENS_CLEARED'
        [ -f '${state_dir}/inbox_watcher_fingerprint_test_agent' ] && echo 'FP_EXISTS' || echo 'FP_CLEARED'
        [ -f '${state_dir}/inbox_watcher_last_nudge_test_agent' ] && echo 'DEBOUNCE_EXISTS' || echo 'DEBOUNCE_CLEARED'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"TOKENS_CLEARED"* ]]
    [[ "$output" == *"FP_CLEARED"* ]]
    [[ "$output" == *"DEBOUNCE_CLEARED"* ]]
    [[ "$output" == *"GENERATION-CHANGE"* ]]
}

@test "T-SW-020: same generation preserves sent_token delivery leases" {
    local state_dir="$TEST_TMPDIR/gen_state"
    mkdir -p "$state_dir"

    touch "${state_dir}/inbox_watcher_sent_test_agent_abc123"
    echo "same_fp" > "${state_dir}/inbox_watcher_fingerprint_test_agent"

    run bash -c "
        SHOGUN_STATE_DIR='$state_dir' INBOX_WATCHER_LIB_ONLY=1 source '$WATCHER_SCRIPT' test_agent dummy-pane
        STATE_DIR='$state_dir'
        FINGERPRINT_FILE='${state_dir}/inbox_watcher_fingerprint_test_agent'
        CURRENT_CLI_GENERATION='100:5000'
        respawn_recovery_generation() { echo '100:5000'; }
        invalidate_leases_on_generation_change
        ls '${state_dir}/inbox_watcher_sent_test_agent_'* 2>/dev/null && echo 'TOKENS_EXIST' || echo 'TOKENS_CLEARED'
        [ -f '${state_dir}/inbox_watcher_fingerprint_test_agent' ] && echo 'FP_EXISTS' || echo 'FP_CLEARED'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"TOKENS_EXIST"* ]]
    [[ "$output" == *"FP_EXISTS"* ]]
    # No GENERATION-CHANGE log should appear
    [[ "$output" != *"GENERATION-CHANGE"* ]]
}

@test "T-SW-021: unknown generation does not invalidate leases" {
    local state_dir="$TEST_TMPDIR/gen_state"
    mkdir -p "$state_dir"

    touch "${state_dir}/inbox_watcher_sent_test_agent_xyz789"

    run bash -c "
        SHOGUN_STATE_DIR='$state_dir' INBOX_WATCHER_LIB_ONLY=1 source '$WATCHER_SCRIPT' test_agent dummy-pane
        STATE_DIR='$state_dir'
        CURRENT_CLI_GENERATION='100:5000'
        respawn_recovery_generation() { return 1; }
        invalidate_leases_on_generation_change
        ls '${state_dir}/inbox_watcher_sent_test_agent_'* 2>/dev/null && echo 'TOKENS_EXIST' || echo 'TOKENS_CLEARED'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"TOKENS_EXIST"* ]]
}

# test_necessity: bulletin_notify複数未読が窓内(300s)でPRIORITY-DEADLINEを無視して集約される不変量を守る。
# batchable=trueの場合、unread_ageがNORMAL_PRIORITY_NUDGE_DEADLINE_SEC(120s)を超えても
# NORMAL_BATCH_WINDOW_SEC(300s)内はSKIPとなることを保証する。
@test "T-SW-022: batchable window suppresses nudge even past priority deadline (elapsed=130s, unread_age=130s)" {
    cat > "$TEST_INBOX_DIR/test_agent.yaml" <<'YAML'
messages:
- content: first post
  from: karo
  id: msg_bn_a
  read: false
  timestamp: '2026-07-20T00:00:00'
  type: bulletin_notify
- content: second post
  from: gunshi
  id: msg_bn_b
  read: false
  timestamp: '2026-07-20T00:02:00'
  type: bulletin_notify
YAML

    local state_dir="$TEST_TMPDIR/state22"
    mkdir -p "$state_dir"

    # Simulate: nudge sent 130s ago (past 120s NORMAL deadline but within 300s batch window)
    local last_nudge
    last_nudge=$(( $(date +%s) - 130 ))
    printf '%s' "$last_nudge" > "${state_dir}/inbox_watcher_last_nudge_test_agent"

    run bash -c "
        export SHOGUN_STATE_DIR='$state_dir'
        export INBOX_WATCHER_LIB_ONLY=1
        source '$WATCHER_SCRIPT' test_agent dummy-pane

        INBOX='$TEST_INBOX_DIR/test_agent.yaml'

        raw_info=\$(get_unread_info)
        IFS=\$'\t' read -r _count _specials _fp _sb64 _htask priority batchable <<< \"\$raw_info\"

        _now=\$(date +%s)
        _last=''
        IFS= read -r _last < \"\$DEBOUNCE_FILE\" 2>/dev/null || true
        [[ \"\$_last\" =~ ^[0-9]+$ ]] || _last=0
        _elapsed=\$((_now - _last))
        _unread_age=130
        _window=\"\$DEBOUNCE_SEC\"
        [ \"\$batchable\" = 'true' ] && _window=\"\$NORMAL_BATCH_WINDOW_SEC\"

        decision='send'
        if [ \"\$_elapsed\" -lt \"\$_window\" ]; then
            if [ \"\$batchable\" = 'true' ] || ! priority_deadline_reached \"\$priority\" \"\$_unread_age\"; then
                decision='skip'
            fi
        fi

        printf 'batchable=%s priority=%s elapsed=%s window=%s decision=%s\n' \"\$batchable\" \"\$priority\" \"\$_elapsed\" \"\$_window\" \"\$decision\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"batchable=true"* ]]
    [[ "$output" == *"priority=normal"* ]]
    [[ "$output" == *"window=300"* ]]
    [[ "$output" == *"decision=skip"* ]]
}

# test_necessity: batch windowは同一unread集合の再通知だけを抑止し、別message追加で
# fingerprintが変わった配送義務を最大300秒隠さない不変量を守る。
@test "T-SW-024: fingerprint change is decided before bulletin batch window" {
    run python3 - "$WATCHER_SCRIPT" <<'PY'
import pathlib, sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start = text.index("# Tier 1.5: Debounce repeated nudge storms")
end = text.index("# Tier 2:", start)
block = text[start:end]
fp_change = block.index('if [ "$current_fp" != "$_prev_fp" ]')
batch_window = block.index('if [ -f "$DEBOUNCE_FILE" ]')
assert fp_change < batch_window, (fp_change, batch_window)
print("FP_CHANGE_BEFORE_BATCH_WINDOW")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"FP_CHANGE_BEFORE_BATCH_WINDOW"* ]]
}

# test_necessity: escalation/CRITICAL型は高優先度に分類されdebounceブロックの
# priority!=highガードをスキップし即時配送される不変量を守る。
@test "T-SW-023: escalation classified as high priority bypasses debounce block guard" {
    cat > "$TEST_INBOX_DIR/test_agent.yaml" <<'YAML'
messages:
- content: urgent escalation
  from: karo
  id: msg_esc_1
  read: false
  timestamp: '2026-07-20T00:00:00'
  type: escalation
YAML

    local state_dir="$TEST_TMPDIR/state23"
    mkdir -p "$state_dir"

    # Even if a nudge was recently sent (10s ago), escalation bypasses debounce
    local last_nudge
    last_nudge=$(( $(date +%s) - 10 ))
    printf '%s' "$last_nudge" > "${state_dir}/inbox_watcher_last_nudge_test_agent"

    run bash -c "
        export SHOGUN_STATE_DIR='$state_dir'
        export INBOX_WATCHER_LIB_ONLY=1
        source '$WATCHER_SCRIPT' test_agent dummy-pane
        INBOX='$TEST_INBOX_DIR/test_agent.yaml'

        raw_info=\$(get_unread_info)
        IFS=\$'\t' read -r _count _specials _fp _sb64 _htask priority batchable <<< \"\$raw_info\"

        # The debounce block guard in inbox_watcher.sh: [ \"\$priority\" != 'high' ]
        # For escalation, priority=high → condition is false → debounce block skipped → immediate delivery
        debounce_bypassed='false'
        [ \"\$priority\" != 'high' ] || debounce_bypassed='true'

        printf 'priority=%s batchable=%s debounce_bypassed=%s\n' \"\$priority\" \"\$batchable\" \"\$debounce_bypassed\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"priority=high"* ]]
    [[ "$output" == *"batchable=false"* ]]
    [[ "$output" == *"debounce_bypassed=true"* ]]
}
