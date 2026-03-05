#!/usr/bin/env bats
# test_log_terminal.bats — log_terminal_input.sh / log_terminal_response.sh 単体テスト

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export INPUT_SCRIPT="$PROJECT_ROOT/scripts/log_terminal_input.sh"
    export RESPONSE_SCRIPT="$PROJECT_ROOT/scripts/log_terminal_response.sh"
    export LORD_CONV_LIB="$PROJECT_ROOT/lib/lord_conversation.sh"
    [ -f "$INPUT_SCRIPT" ] || return 1
    [ -f "$RESPONSE_SCRIPT" ] || return 1
    [ -f "$LORD_CONV_LIB" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/log_terminal_test.XXXXXX")"

    mkdir -p "$TEST_TMPDIR/scripts"
    mkdir -p "$TEST_TMPDIR/lib"
    mkdir -p "$TEST_TMPDIR/queue"
    ln -s "$INPUT_SCRIPT" "$TEST_TMPDIR/scripts/log_terminal_input.sh"
    ln -s "$RESPONSE_SCRIPT" "$TEST_TMPDIR/scripts/log_terminal_response.sh"
    ln -s "$LORD_CONV_LIB" "$TEST_TMPDIR/lib/lord_conversation.sh"

    export TEST_LORD_CONV="$TEST_TMPDIR/queue/lord_conversation.jsonl"
    export TEST_TRANSCRIPT="$TEST_TMPDIR/transcript.jsonl"

    export MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/tmux" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"display-message"* ]]; then
    echo "shogun"
    exit 0
fi
if [[ "$*" == *"capture-pane"* ]]; then
    echo "${MOCK_CAPTURE_OUTPUT:-}"
    exit 0
fi
exit 0
STUB
    chmod +x "$MOCK_BIN/tmux"

    export TMUX_PANE="%0"
    export PATH="$MOCK_BIN:$PATH"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "T-TL-001: slash commands are filtered out by log_terminal_input.sh" {
    export CLAUDE_USER_PROMPT="/clear"
    run bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_LORD_CONV" ]
}

@test "T-TL-002: inbox nudge messages are filtered out by log_terminal_input.sh" {
    export CLAUDE_USER_PROMPT="inbox3"
    run bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_LORD_CONV" ]
}

@test "T-TL-003: normal input is recorded in lord_conversation.jsonl" {
    export CLAUDE_USER_PROMPT="dm-signalの進捗を教えてくれ"
    run bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"
    [ "$status" -eq 0 ]

    [ -f "$TEST_LORD_CONV" ]
    readarray -t result < <(python3 - <<PY
import json
with open("$TEST_LORD_CONV", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("direction", ""))
print(obj.get("source", ""))
print(obj.get("detail", "").replace("\\n", "\\\\n"))
PY
)
    [ "${result[0]}" = "prompt" ]
    [ "${result[1]}" = "terminal" ]
    echo "${result[2]}" | grep -q "dm-signal"
}

@test "T-TL-004: response uses transcript_path payload as primary source" {
    cat > "$TEST_TRANSCRIPT" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"transcript based response"}],"stop_reason":"end_turn"}}
JSONL
    export MOCK_CAPTURE_OUTPUT="pane_noise_should_not_be_used"

    run bash -c "python3 - <<'PY' | bash '$TEST_TMPDIR/scripts/log_terminal_response.sh'
import json
import os
print(json.dumps({
  'transcript_path': os.environ['TEST_TRANSCRIPT'],
  'stop_reason': 'end_turn'
}))
PY"
    [ "$status" -eq 0 ]
    [ -f "$TEST_LORD_CONV" ]

    readarray -t result < <(python3 - <<PY
import json
with open("$TEST_LORD_CONV", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("direction", ""))
print(obj.get("source", ""))
print(obj.get("detail", "").replace("\\n", "\\\\n"))
PY
)
    [ "${result[0]}" = "response" ]
    [ "${result[1]}" = "terminal" ]
    echo "${result[2]}" | grep -q "transcript based response"
    echo "${result[2]}" | grep -q "stop_reason=end_turn"
    ! echo "${result[2]}" | grep -q "pane_noise_should_not_be_used"
}
