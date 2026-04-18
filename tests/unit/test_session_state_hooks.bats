#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SESSION_START_SCRIPT="$PROJECT_ROOT/scripts/hooks/session_start_inject.sh"
    export PROMPT_STATE_SCRIPT="$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh"
    export SESSION_END_SCRIPT="$PROJECT_ROOT/scripts/hooks/session_end_clear_check.sh"
    [ -f "$SESSION_START_SCRIPT" ] || return 1
    [ -f "$PROMPT_STATE_SCRIPT" ] || return 1
    [ -f "$SESSION_END_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/session_hooks.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/hooks" "$TEST_TMPDIR/queue/inbox" "$TEST_TMPDIR/queue/compact_state"

    ln -s "$SESSION_START_SCRIPT" "$TEST_TMPDIR/scripts/hooks/session_start_inject.sh"
    ln -s "$PROMPT_STATE_SCRIPT" "$TEST_TMPDIR/scripts/hooks/prompt_state_inject.sh"
    ln -s "$SESSION_END_SCRIPT" "$TEST_TMPDIR/scripts/hooks/session_end_clear_check.sh"

    export MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"display-message"* ]]; then
    echo "${MOCK_AGENT_ID:-unknown}"
    exit 0
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/tmux"

    export PATH="$MOCK_BIN:$PATH"
    export TMUX_PANE="%0"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "SSH-001: session_start_inject injects agent, unread count, and snapshot" {
    export MOCK_AGENT_ID="saizo"
    cat > "$TEST_TMPDIR/queue/inbox/saizo.yaml" <<'YAML'
messages:
  - content: one
    read: false
  - content: two
    read: true
YAML
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
snapshot line
EOF
    cat > "$TEST_TMPDIR/queue/compact_state/saizo.yaml" <<'YAML'
timestamp: '2026-04-18T11:00:00+09:00'
summary: compact ok
YAML

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"type\":\"startup\"}' | scripts/hooks/session_start_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("agent: saizo" in ctx)
print("inbox_unread: 1" in ctx)
print("snapshot line" in ctx)
print("source: startup" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "True" ]
}

@test "SSH-002: prompt_state_inject returns nothing for non-shogun" {
    export MOCK_AGENT_ID="saizo"
    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"通常入力\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "SSH-003: prompt_state_inject warns shogun about unread inbox" {
    export MOCK_AGENT_ID="shogun"
    cat > "$TEST_TMPDIR/queue/inbox/shogun.yaml" <<'YAML'
messages:
  - content: one
    read: false
YAML
    cat > "$TEST_TMPDIR/queue/karo_snapshot.txt" <<'EOF'
snapshot line
EOF

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{\"prompt\":\"通常入力\"}' | scripts/hooks/prompt_state_inject.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(OUTPUT_JSON="$output" python3 - <<'PY'
import json
import os
obj = json.loads(os.environ["OUTPUT_JSON"])
ctx = obj["hookSpecificOutput"]["additionalContext"]
print("agent: shogun" in ctx)
print("⚠️ INBOX 1件未読" in ctx)
print("snapshot line" in ctx)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "True" ]
}

@test "SSH-004: session_end_clear_check is silent for non-shogun" {
    export MOCK_AGENT_ID="saizo"
    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{}' | scripts/hooks/session_end_clear_check.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "SSH-005: session_end_clear_check reports OK for shogun when checks pass" {
    export MOCK_AGENT_ID="shogun"
    cat > "$TEST_TMPDIR/queue/lord_conversation.jsonl" <<'EOF'
{"direction":"inbound"}
EOF
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/clear_prep_check.sh" <<'EOF'
#!/usr/bin/env bash
echo "[STATUS] OK"
echo "[INFO] clean"
EOF
    cat > "$TEST_TMPDIR/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${NTFY_LOG:?}"
EOF
    chmod +x "$TEST_TMPDIR/scripts/clear_prep_check.sh" "$TEST_TMPDIR/scripts/ntfy.sh"
    export NTFY_LOG="$TEST_TMPDIR/ntfy.log"

    run bash -c "cd '$TEST_TMPDIR' && printf '%s' '{}' | SESSION_END_LORD_CONVERSATION_FILE='$TEST_TMPDIR/queue/lord_conversation.jsonl' SESSION_END_CLEAR_PREP_CMD='$TEST_TMPDIR/scripts/clear_prep_check.sh' SESSION_END_NTFY_CMD='$TEST_TMPDIR/scripts/ntfy.sh' scripts/hooks/session_end_clear_check.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "OK: session_end_clear_check (shogun)" ]
    run cat "$NTFY_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"【SessionEnd 報告】/clear前確認"* ]]
}
