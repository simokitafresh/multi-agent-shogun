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
    if [[ "$*" == *"client_activity"* ]]; then
        echo "${MOCK_CLIENT_ACTIVITY:-1700000000}"
    else
        echo "${MOCK_AGENT_ID:-shogun}"
    fi
    exit 0
fi
if [[ "$*" == *"list-clients"* ]]; then
    if [ -n "${MOCK_CLIENT_ROWS:-}" ]; then
        printf '%b\n' "$MOCK_CLIENT_ROWS"
    else
        printf '%s|%s\n' "${MOCK_CLIENT_ACTIVITY:-1700000000}" "${MOCK_SELECTED_AGENT:-${MOCK_AGENT_ID:-shogun}}"
    fi
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
    run bash -c 'echo "{\"prompt\":\"/clear\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_LORD_CONV" ]
}

@test "T-TL-002: inbox nudge messages are filtered out by log_terminal_input.sh" {
    run bash -c 'echo "{\"prompt\":\"inbox3\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_LORD_CONV" ]
}

@test "T-TL-003: normal input is recorded in lord_conversation.jsonl" {
    run bash -c 'echo "{\"prompt\":\"dm-signalの進捗を教えてくれ\",\"target_agent\":\"shogun\",\"source_event_id\":\"evt-normal-1\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
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
    [ "${result[0]}" = "inbound" ]
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

@test "T-TL-007: response skips assistant tool_use-only transcript tail and records last text" {
    cat > "$TEST_TRANSCRIPT" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"text before tool use"}],"stop_reason":null}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"true"}}],"stop_reason":"tool_use"}}
JSONL
    export MOCK_CAPTURE_OUTPUT="pane_noise_should_not_be_used"

    run bash -c "python3 - <<'PY' | bash '$TEST_TMPDIR/scripts/log_terminal_response.sh'
import json
import os
print(json.dumps({
  'transcript_path': os.environ['TEST_TRANSCRIPT'],
  'stop_reason': 'tool_use'
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
    echo "${result[2]}" | grep -q "text before tool use"
    echo "${result[2]}" | grep -q "stop_reason=tool_use"
    ! echo "${result[2]}" | grep -q "pane_noise_should_not_be_used"
}

@test "T-TL-008: response script live-inserts recorded response into memory DB FTS" {
    cat > "$TEST_TRANSCRIPT" <<'JSONL'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"cmd_3451 response fts searchable sentinel"}],"stop_reason":"end_turn"}}
JSONL
    mkdir -p "$TEST_TMPDIR/data"
    export LORD_CONVERSATION_DB="$TEST_TMPDIR/data/multi_agent_shogun_memory.db"
    python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$LORD_CONVERSATION_DB" >/dev/null

    run bash -c "python3 - <<'PY' | bash '$TEST_TMPDIR/scripts/log_terminal_response.sh'
import json
import os
print(json.dumps({'transcript_path': os.environ['TEST_TRANSCRIPT']}))
PY"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$LORD_CONVERSATION_DB" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    """
    SELECT e.agent, e.target, e.direction, e.detail
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.detail LIKE '%cmd_3451 response fts searchable sentinel%'
    ORDER BY e.rowid DESC
    LIMIT 1
    """
).fetchone()
print(row[0] if row else "")
print(row[1] if row else "")
print(row[2] if row else "")
print("sentinel" in row[3] if row else False)
PY
)
    [ "${result[0]}" = "shogun" ]
    [ "${result[1]}" = "lord" ]
    [ "${result[2]}" = "response" ]
    [ "${result[3]}" = "True" ]
}

@test "T-TL-005: lord input to karo pane is recorded with target and live inserted into events" {
    export MOCK_AGENT_ID="karo"
    mkdir -p "$TEST_TMPDIR/archive" "$TEST_TMPDIR/data"
    python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/multi_agent_shogun_memory.db" >/dev/null

    run bash -c 'echo "{\"prompt\":\"家老に直接確認する\",\"target_agent\":\"karo\",\"source_event_id\":\"evt-karo-1\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_LORD_CONV" "$TEST_TMPDIR/data/multi_agent_shogun_memory.db" <<'PY'
import json
import sqlite3
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    row = json.loads(f.read().strip().splitlines()[-1])
conn = sqlite3.connect(sys.argv[2])
event = conn.execute(
    "SELECT agent, target, direction, summary FROM events ORDER BY rowid DESC LIMIT 1"
).fetchone()
print(row.get("agent", ""))
print(row.get("target", ""))
print(event[0])
print(event[1])
print(event[2])
print("家老" in event[3])
PY
)
    [ "${result[0]}" = "lord" ]
    [ "${result[1]}" = "karo" ]
    [ "${result[2]}" = "lord" ]
    [ "${result[3]}" = "karo" ]
    [ "${result[4]}" = "inbound" ]
    [ "${result[5]}" = "True" ]
}

@test "T-TL-006: lord input to gunshi pane is recorded with target" {
    export MOCK_AGENT_ID="gunshi"

    run bash -c 'echo "{\"prompt\":\"軍師に直接確認する\",\"target_agent\":\"gunshi\",\"source_event_id\":\"evt-gunshi-1\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$TEST_LORD_CONV", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("agent", ""))
print(obj.get("target", ""))
print(obj.get("direction", ""))
print(obj.get("detail", ""))
PY
)
    [ "${result[0]}" = "lord" ]
    [ "${result[1]}" = "gunshi" ]
    [ "${result[2]}" = "inbound" ]
    echo "${result[3]}" | grep -q "軍師"
}

@test "T-TL-009: explicit target mismatch is quarantined and not recorded" {
    export MOCK_AGENT_ID="shogun"
    run bash -c 'echo "{\"prompt\":\"家老だけへ\",\"target_agent\":\"karo\",\"source_event_id\":\"evt-route-1\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_LORD_CONV" ]
    grep -q 'cross_pane_target_mismatch' "$TEST_TMPDIR/logs/lord_conversation_route_rejects.jsonl"
}

@test "T-TL-010: conflicting payload identity is quarantined" {
    run bash -c 'echo "{\"prompt\":\"identity conflict\",\"target_agent\":\"shogun\",\"pane_agent_id\":\"karo\",\"source_event_id\":\"evt-route-2\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_LORD_CONV" ]
    grep -q 'missing_or_conflicting_payload_target' "$TEST_TMPDIR/logs/lord_conversation_route_rejects.jsonl"
}

@test "T-TL-011: one source event is durably consumed by one target only" {
    export MOCK_AGENT_ID="karo"
    run bash -c 'echo "{\"prompt\":\"once only\",\"target_agent\":\"karo\",\"source_event_id\":\"evt-once\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]
    export MOCK_AGENT_ID="shogun"
    run bash -c 'echo "{\"prompt\":\"once only\",\"target_agent\":\"shogun\",\"source_event_id\":\"evt-once\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TEST_LORD_CONV")" -eq 1 ]
    [ "$(awk -F '\t' '$1=="evt-once"{n++} END{print n+0}' "$TEST_TMPDIR/queue/lord_conversation_consumed.tsv")" -eq 1 ]
}

@test "T-TL-012: three-agent concurrent adversarial delivery records exactly one event" {
    export MOCK_SELECTED_AGENT="karo"
    run bash -c '
      for agent in shogun karo gunshi; do
        (export MOCK_AGENT_ID="$agent"; printf "{\"prompt\":\"concurrent once\"}\n" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh") &
      done
      wait
    '
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TEST_LORD_CONV")" -eq 1 ]
    [ "$(wc -l < "$TEST_TMPDIR/queue/lord_conversation_consumed.tsv")" -eq 1 ]
    run python3 - "$TEST_LORD_CONV" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
assert len(rows) == 1
assert rows[0]["target"] == "karo"
assert rows[0]["source_event_id"].startswith("terminal:")
PY
    [ "$status" -eq 0 ]
}

@test "T-TL-014: minimal payload routes once to each executing pane without reject" {
    for agent in karo shogun gunshi; do
        export MOCK_AGENT_ID="$agent"
        export MOCK_SELECTED_AGENT="$agent"
        export MOCK_CLIENT_ACTIVITY="170000000${#agent}"
        run bash -c 'printf "{\"prompt\":\"minimal %s\"}\n" "$MOCK_AGENT_ID" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
        [ "$status" -eq 0 ]
    done
    run python3 - "$TEST_LORD_CONV" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
assert len(rows) == 3
assert {row["target"] for row in rows} == {"karo", "shogun", "gunshi"}
assert len({row["source_event_id"] for row in rows}) == 3
PY
    [ "$status" -eq 0 ]
    [ ! -s "$TEST_TMPDIR/logs/lord_conversation_route_rejects.jsonl" ]
}

@test "T-TL-015: conflicting newest clients quarantine minimal payload" {
    export MOCK_AGENT_ID="karo"
    export MOCK_CLIENT_ROWS='1700000100|karo\n1700000100|shogun'
    run bash -c 'echo "{\"prompt\":\"ambiguous client\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_LORD_CONV" ]
    grep -q 'missing_or_conflicting_active_client' "$TEST_TMPDIR/logs/lord_conversation_route_rejects.jsonl"
}

@test "T-TL-013: real minimal Codex payload records selected pane exactly once" {
    export MOCK_AGENT_ID="karo"
    export MOCK_ACTIVE_AGENT_ID="karo"
    run bash -c 'echo "{\"prompt\":\"実戦shadow入力\"}" | bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"'
    [ "$status" -eq 0 ]
    run python3 - "$TEST_LORD_CONV" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
assert len(rows) == 1
assert rows[0]["target"] == "karo"
assert rows[0]["detail"] == "実戦shadow入力"
PY
    [ "$status" -eq 0 ]
}
