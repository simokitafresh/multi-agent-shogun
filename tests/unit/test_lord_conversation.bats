#!/usr/bin/env bats
# test_lord_conversation.bats — lord_conversation.sh JSONL 単体テスト

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export LORD_CONV_LIB="$PROJECT_ROOT/lib/lord_conversation.sh"
    [ -f "$LORD_CONV_LIB" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/lord_conv_test.XXXXXX")"
    export LORD_CONVERSATION="$TEST_TMPDIR/lord_conversation.jsonl"
    export LORD_CONVERSATION_LOCK="$TEST_TMPDIR/lord_conversation.jsonl.lock"
    source "$LORD_CONV_LIB"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "T-LC-001: append_lord_conversation adds outbound entry with agent" {
    run append_lord_conversation "test outbound msg" "outbound" "shogun"
    [ "$status" -eq 0 ]
    [ -f "$LORD_CONVERSATION" ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("direction", ""))
print(obj.get("agent", ""))
print(obj.get("source", ""))
print(obj.get("detail", ""))
print(obj.get("summary", ""))
print("ts" in obj)
PY
)
    [ "${result[0]}" = "outbound" ]
    [ "${result[1]}" = "shogun" ]
    [ "${result[2]}" = "ntfy" ]
    [ "${result[3]}" = "test outbound msg" ]
    [ "${result[4]}" = "test outbound msg" ]
    [ "${result[5]}" = "True" ]
}

@test "T-LC-002: append_lord_conversation adds inbound entry without agent" {
    run append_lord_conversation "test inbound msg" "inbound"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("direction", ""))
print(obj.get("detail", ""))
print("agent" in obj)
PY
)
    [ "${result[0]}" = "inbound" ]
    [ "${result[1]}" = "test inbound msg" ]
    [ "${result[2]}" = "False" ]
}

@test "T-LC-003: append_lord_conversation fails when lock is held" {
    export LORD_CONVERSATION_LOCK_WAIT_SEC=0.2
    (
        flock -x 200
        sleep 0.4
    ) 200>"$LORD_CONVERSATION_LOCK" &
    local lock_pid=$!
    sleep 0.05

    run timeout 2 bash -c "
        source '$LORD_CONV_LIB'
        export LORD_CONVERSATION='$LORD_CONVERSATION'
        export LORD_CONVERSATION_LOCK='$LORD_CONVERSATION_LOCK'
        export LORD_CONVERSATION_LOCK_WAIT_SEC='$LORD_CONVERSATION_LOCK_WAIT_SEC'
        append_lord_conversation 'blocked msg' 'outbound' 'karo'
    "
    [ "$status" -ne 0 ]

    kill "$lock_pid" 2>/dev/null || true
    wait "$lock_pid" 2>/dev/null || true
}

@test "T-LC-004: append_lord_conversation rejects invalid direction" {
    run append_lord_conversation "test msg" "invalid-direction"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "snake_case"
}

@test "T-LC-005: append_lord_conversation fails when LORD_CONVERSATION is unset" {
    unset LORD_CONVERSATION
    run append_lord_conversation "test msg" "outbound"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "LORD_CONVERSATION"
}

@test "T-LC-006: append_lord_conversation preserves existing entries" {
    append_lord_conversation "first msg" "outbound" "shogun"
    append_lord_conversation "second msg" "inbound"

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[0].get("detail", ""))
print(rows[1].get("detail", ""))
PY
)
    [ "${result[0]}" -eq 2 ]
    [ "${result[1]}" = "first msg" ]
    [ "${result[2]}" = "second msg" ]
}

@test "T-LC-007: append_lord_conversation recovers from corrupted JSONL line" {
    printf 'not-json-line\n' > "$LORD_CONVERSATION"
    run append_lord_conversation "recovery msg" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[-1].get("detail", ""))
print(rows[0].get("direction", ""))
PY
)
    [ "${result[0]}" -eq 2 ]
    [ "${result[1]}" = "recovery msg" ]
    [ "${result[2]}" = "invalid" ]
}

@test "T-LC-008: append_lord_conversation trims oldest entry when adding 501st" {
    python3 - <<PY
import json
with open("$LORD_CONVERSATION", "w", encoding="utf-8") as f:
    for i in range(1, 501):
        row = {
            "ts": f"2026-03-01T00:00:{i%60:02d}+09:00",
            "source": "ntfy",
            "direction": "outbound",
            "summary": f"seed-{i:03d}",
            "detail": f"seed-{i:03d}",
        }
        f.write(json.dumps(row, ensure_ascii=False) + "\\n")
PY

    run append_lord_conversation "seed-501" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[0].get("detail", ""))
print(rows[-1].get("detail", ""))
PY
)
    [ "${result[0]}" -eq 500 ]
    [ "${result[1]}" = "seed-002" ]
    [ "${result[2]}" = "seed-501" ]
}

@test "T-LC-009: append_lord_conversation keeps all entries when total is 500" {
    python3 - <<PY
import json
with open("$LORD_CONVERSATION", "w", encoding="utf-8") as f:
    for i in range(1, 500):
        row = {
            "ts": f"2026-03-01T00:00:{i%60:02d}+09:00",
            "source": "ntfy",
            "direction": "outbound",
            "summary": f"seed-{i:03d}",
            "detail": f"seed-{i:03d}",
        }
        f.write(json.dumps(row, ensure_ascii=False) + "\\n")
PY

    run append_lord_conversation "seed-500" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[0].get("detail", ""))
print(rows[-1].get("detail", ""))
PY
)
    [ "${result[0]}" -eq 500 ]
    [ "${result[1]}" = "seed-001" ]
    [ "${result[2]}" = "seed-500" ]
}

@test "T-LC-010: append_lord_conversation records explicit source" {
    run append_lord_conversation "terminal msg" "response" "shogun" "terminal"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("source", ""))
print(obj.get("direction", ""))
print(obj.get("detail", ""))
PY
)
    [ "${result[0]}" = "terminal" ]
    [ "${result[1]}" = "response" ]
    [ "${result[2]}" = "terminal msg" ]
}

@test "T-LC-011: append_lord_conversation defaults source to ntfy when omitted" {
    run append_lord_conversation "ntfy msg" "outbound" "shogun"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("source", ""))
print(obj.get("detail", ""))
PY
)
    [ "${result[0]}" = "ntfy" ]
    [ "${result[1]}" = "ntfy msg" ]
}

@test "T-LC-012: append_lord_conversation migrates legacy YAML when JSONL is empty" {
    cat > "$TEST_TMPDIR/lord_conversation.yaml" <<'YAML'
entries:
  - timestamp: "2026-03-05T20:00:00+09:00"
    direction: outbound
    channel: terminal
    agent: shogun
    message: legacy message
YAML
    : > "$LORD_CONVERSATION"

    run append_lord_conversation "new message" "response" "shogun" "terminal"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[0].get("detail", ""))
print(rows[1].get("detail", ""))
PY
)
    [ "${result[0]}" -eq 2 ]
    [ "${result[1]}" = "legacy message" ]
    [ "${result[2]}" = "new message" ]
}

@test "T-LC-013: append_lord_conversation inserts appended entry into memory DB events and FTS" {
    export LORD_CONVERSATION_DB="$TEST_TMPDIR/data/memory.db"
    export SEMANTIC_INDEX_PATH="$TEST_TMPDIR/docs/semantic-index/index.md"
    mkdir -p "$TEST_TMPDIR/data"
    mkdir -p "$TEST_TMPDIR/docs/semantic-index"
    cat > "$SEMANTIC_INDEX_PATH" <<'EOF'
# セマンティクスインデックス SSOT

## local_memory_db — ローカル記憶DB

| 属性 | 値 |
|------|---|
| id | local_memory_db |
| label | ローカル記憶DB |
| aliases | multi_agent_shogun_memory.db, SQLite記憶DB |
EOF
    python3 - "$LORD_CONVERSATION_DB" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conn.executescript("""
	CREATE TABLE events (
	    id TEXT PRIMARY KEY,
	    ts TEXT,
    event_type TEXT,
    agent TEXT,
    target TEXT,
    direction TEXT,
    summary TEXT,
    detail TEXT,
    session_id TEXT,
    cmd_id TEXT,
    concepts TEXT,
    source_file TEXT,
    parent_event_id INTEGER,
    importance TEXT
);
CREATE VIRTUAL TABLE events_fts USING fts5(
    summary,
    detail,
	    content='events',
	    content_rowid='rowid'
	);
	CREATE VIEW conversations AS
	SELECT ts, agent, direction, summary, detail, session_id
	FROM events
	WHERE event_type = 'conversation';
	""")
conn.commit()
PY

    run append_lord_conversation "cmd_2982 realtime sqlite insert multi_agent_shogun_memory.db" "response" "shogun" "terminal"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$LORD_CONVERSATION_DB" <<'PY'
import json
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
event = conn.execute(
    """
    SELECT event_type, agent, target, direction, cmd_id, concepts
    FROM events
    WHERE detail='cmd_2982 realtime sqlite insert multi_agent_shogun_memory.db'
    """
).fetchone()
fts_count = conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'realtime'
      AND e.detail='cmd_2982 realtime sqlite insert multi_agent_shogun_memory.db'
    """
).fetchone()[0]
conversation_count = conn.execute(
    "SELECT COUNT(*) FROM conversations WHERE detail='cmd_2982 realtime sqlite insert multi_agent_shogun_memory.db'"
).fetchone()[0]
concept = conn.execute(
    """
    SELECT concept_name, relevance_score
    FROM event_concepts
    WHERE event_id = (
        SELECT id FROM events
        WHERE detail='cmd_2982 realtime sqlite insert multi_agent_shogun_memory.db'
    )
    """
).fetchone()
print(event[0])
print(event[1])
print(event[2])
print(event[3])
print(event[4])
print(json.loads(event[5]))
print(fts_count)
print(conversation_count)
print(concept[0])
print(concept[1] > 0)
PY
)
    [ "${result[0]}" = "conversation" ]
    [ "${result[1]}" = "shogun" ]
    [ "${result[2]}" = "lord" ]
    [ "${result[3]}" = "response" ]
    [ "${result[4]}" = "cmd_2982" ]
    [ "${result[5]}" = "['local_memory_db']" ]
    [ "${result[6]}" = "1" ]
    [ "${result[7]}" = "1" ]
    [ "${result[8]}" = "local_memory_db" ]
    [ "${result[9]}" = "True" ]
}

@test "T-LC-014: append_lord_conversation keeps JSONL success when DB insert fails" {
    export LORD_CONVERSATION_DB="$TEST_TMPDIR/broken_memory.db"
    printf 'not sqlite\n' > "$LORD_CONVERSATION_DB"

    run append_lord_conversation "jsonl survives db failure" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[-1].get("detail", ""))
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "jsonl survives db failure" ]
    [[ "$output" == *"DB INSERT skipped"* ]]
}

@test "T-LC-015: lord_conversation_read filters by target or agent and keeps unscoped entries" {
    cat > "$LORD_CONVERSATION" <<'EOF'
{"agent":"lord","target":"shogun","summary":"to shogun"}
{"agent":"shogun","target":"lord","summary":"from shogun"}
{"agent":"lord","target":"karo","summary":"to karo"}
{"agent":"lord","summary":"no target"}
{"agent":"lord","target":"","summary":"empty target"}
EOF

    run env LORD_CONVERSATION_FILE="$LORD_CONVERSATION" bash "$PROJECT_ROOT/scripts/lord_conversation_read.sh" shogun 10
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "to shogun"
    echo "$output" | grep -q "from shogun"
    echo "$output" | grep -q "no target"
    echo "$output" | grep -q "empty target"
    ! echo "$output" | grep -q "to karo"
}

@test "T-LC-016: lord_conversation_read applies limit after filtering" {
    cat > "$LORD_CONVERSATION" <<'EOF'
{"agent":"lord","target":"shogun","summary":"first"}
{"agent":"lord","target":"karo","summary":"excluded"}
{"agent":"lord","target":"shogun","summary":"second"}
{"agent":"lord","summary":"third"}
EOF

    run env LORD_CONVERSATION_FILE="$LORD_CONVERSATION" bash "$PROJECT_ROOT/scripts/lord_conversation_read.sh" shogun 2
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "first"
    ! echo "$output" | grep -q "excluded"
    echo "$output" | grep -q "second"
    echo "$output" | grep -q "third"
}

@test "T-LC-017: conversation_retention renders lord decisions from inbound entries only" {
    local index_path="$TEST_TMPDIR/lord-conversation-index.md"
    local archive_dir="$TEST_TMPDIR/archive"
    cat > "$LORD_CONVERSATION" <<'EOF'
{"ts":"2099-01-01T00:00:00+00:00","source":"terminal","direction":"response","summary":"軍師D0承認。進める。","detail":"軍師D0承認。進める。"}
{"ts":"2099-01-01T00:01:00+00:00","source":"terminal","direction":"outbound","summary":"方針を共有した。","detail":"方針を共有した。"}
{"ts":"2099-01-01T00:02:00+00:00","source":"terminal","direction":"inbound","summary":"殿裁定: inboundのみ採用せよ。","detail":"殿裁定: inboundのみ採用せよ。"}
EOF

    run bash "$PROJECT_ROOT/scripts/conversation_retention.sh" "$LORD_CONVERSATION" "$index_path" "$archive_dir"
    [ "$status" -eq 0 ]

    decisions_section="$(sed -n '/^## 殿の直近裁定・方針/,/^## 参照cmd/p' "$index_path")"
    echo "$decisions_section" | grep -q "殿裁定: inboundのみ採用せよ。"
    ! echo "$decisions_section" | grep -q "軍師D0承認"
    ! echo "$decisions_section" | grep -q "方針を共有"
}
