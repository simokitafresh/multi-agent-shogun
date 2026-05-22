#!/usr/bin/env bats
# test_memory_db.bats — SQLite memory DB import tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/memory_db.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/archive" "$TEST_TMPDIR/data"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "memory_db_import creates conversations view and events table with required columns" {
    cat > "$TEST_TMPDIR/archive/2026-05-01.jsonl" <<'EOF'
{"ts":"2026-05-01T00:00:00+09:00","agent":"lord","direction":"inbound","summary":"sum1","detail":"detail1"}
{"ts":"2026-05-01T00:01:00+09:00","agent":"shogun","direction":"response","summary":"sum2","detail":"detail2","session_id":"explicit-session"}
EOF

    run bash "$PROJECT_ROOT/scripts/memory_db_init.sh" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"files=1 rows=2"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
conversation_cols = [row[1] for row in conn.execute("PRAGMA table_info(conversations)")]
event_cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
conversation_type = conn.execute(
    "SELECT type FROM sqlite_master WHERE name='conversations'"
).fetchone()[0]
print(",".join(conversation_cols))
print(",".join(event_cols))
print(conversation_type)
print(conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0])
print(conn.execute("SELECT session_id FROM conversations ORDER BY ts LIMIT 1").fetchone()[0])
print(conn.execute("SELECT session_id FROM conversations ORDER BY ts DESC LIMIT 1").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events").fetchone()[0])
print(conn.execute("SELECT event_type FROM events ORDER BY ts LIMIT 1").fetchone()[0])
PY
)
    [ "${result[0]}" = "ts,agent,direction,summary,detail,session_id" ]
    [ "${result[1]}" = "id,ts,event_type,agent,target,direction,summary,detail,session_id,cmd_id,concepts,source_file,parent_event_id,importance" ]
    [ "${result[2]}" = "view" ]
    [ "${result[3]}" = "2" ]
    [ "${result[4]}" = "2026-05-01" ]
    [ "${result[5]}" = "explicit-session" ]
    [ "${result[6]}" = "2" ]
    [ "${result[7]}" = "conversation" ]
}

@test "memory_db_import creates FTS5 index and searches summary detail through MATCH" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"高速化相談","detail":"events detail LIKE scan を FTS5 に置き換える"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"shogun","direction":"response","summary":"別件","detail":"通常の返答"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
fts_sql = conn.execute(
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='events_fts'"
).fetchone()[0]
plan = " ".join(
    row[3]
    for row in conn.execute(
        """
        EXPLAIN QUERY PLAN
        SELECT e.id
        FROM events_fts
        JOIN events AS e ON e.rowid = events_fts.rowid
        WHERE events_fts MATCH 'FTS5'
        """
    )
)
rows = conn.execute(
    """
    SELECT e.summary, e.detail
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'FTS5'
    """
).fetchall()
print("USING fts5" in fts_sql)
print("VIRTUAL TABLE INDEX" in plan)
print(len(rows))
print(rows[0][0])
print("LIKE" in plan)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "True" ]
    [ "${result[2]}" = "1" ]
    [ "${result[3]}" = "高速化相談" ]
    [ "${result[4]}" = "False" ]
}

@test "memory_db_import search CLI returns FTS5 matches only" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"検索対象","detail":"parent_event_id と importance を検索品質に使う"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"shogun","direction":"response","summary":"無関係","detail":"通常の返答"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --search "importance"
    [ "$status" -eq 0 ]
    [[ "$output" == *"検索対象"* ]]
    [[ "$output" != *"無関係"* ]]
}

@test "memory_db_import search tokenizes long Japanese queries for FTS5" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"日本語FTS改善","detail":"FTS5検索がタイムアウトする問題を改善する"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"shogun","direction":"response","summary":"無関係","detail":"通常の返答"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --search "日本語の長いクエリでFTS5検索がタイムアウトする問題を改善する"
    [ "$status" -eq 0 ]
    [[ "$output" == *"日本語FTS改善"* ]]
    [[ "$output" != *"無関係"* ]]
}

@test "memory_db_query runs SQL through Python sqlite3 with sqlite3 CLI-style output" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"query wrapper","detail":"Python sqlite3 wrapper output check"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "SELECT summary, target, parent_event_id FROM events ORDER BY ts"
    [ "$status" -eq 0 ]
    [ "$output" = "query wrapper|lord|" ]
}

@test "memory_db_query supports FTS5 MATCH queries" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"FTS wrapper","detail":"uniqueftsneedle works through MATCH"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"shogun","direction":"response","summary":"miss","detail":"ordinary response"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run bash "$PROJECT_ROOT/scripts/memory_db_query.sh" \
        --db "$TEST_TMPDIR/data/memory.db" \
        "SELECT e.summary FROM events_fts JOIN events AS e ON e.rowid = events_fts.rowid WHERE events_fts MATCH 'uniqueftsneedle'"
    [ "$status" -eq 0 ]
    [ "$output" = "FTS wrapper" ]
}

@test "memory_db_import row count matches non-empty archive JSONL lines" {
    cat > "$TEST_TMPDIR/archive/2026-05-01.jsonl" <<'EOF'
{"ts":"2026-05-01T00:00:00+09:00","direction":"inbound","summary":"a","detail":"a"}

{"ts":"2026-05-01T00:01:00+09:00","direction":"response","summary":"b","detail":"b"}
EOF
    cat > "$TEST_TMPDIR/archive/2026-05-02.jsonl" <<'EOF'
not-json
{"ts":"2026-05-02T00:00:00+09:00","direction":"outbound","summary":"c","detail":"c"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/archive" "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
from pathlib import Path
archive = Path(sys.argv[1])
expected = sum(
    1
    for path in archive.glob("*.jsonl")
    for line in path.read_text(encoding="utf-8").splitlines()
    if line.strip()
)
conn = sqlite3.connect(sys.argv[2])
actual = conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0]
events = conn.execute("SELECT COUNT(*) FROM events").fetchone()[0]
invalid = conn.execute("SELECT COUNT(*) FROM conversations WHERE direction='invalid'").fetchone()[0]
print(expected)
print(actual)
print(events)
print(invalid)
PY
)
    [ "${result[0]}" = "${result[1]}" ]
    [ "${result[0]}" = "${result[2]}" ]
    [ "${result[3]}" = "1" ]
}

@test "memory_db_import migrates existing conversations into events with cmd and concepts" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:56:54+09:00","agent":"shogun","direction":"response","summary":"cmd_2966 eventsテーブル拡張","detail":"multi_agent_shogun_memory.db とセマンティクスインデックスを連携する"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import json
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "SELECT event_type, target, cmd_id, concepts FROM events"
).fetchone()
print(row[0])
print(row[1])
print(row[2])
print("local_memory_db" in json.loads(row[3]))
print("semantic_dictionary_design" in json.loads(row[3]))
print(conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events").fetchone()[0])
PY
)
    [ "${result[0]}" = "conversation" ]
    [ "${result[1]}" = "lord" ]
    [ "${result[2]}" = "cmd_2966" ]
    [ "${result[3]}" = "True" ]
    [ "${result[4]}" = "True" ]
    [ "${result[5]}" = "${result[6]}" ]
}

@test "memory_db_import normalizes concepts into event_concepts junction table" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:56:54+09:00","agent":"shogun","direction":"response","summary":"cmd_2966 eventsテーブル拡張","detail":"multi_agent_shogun_memory.db とセマンティクスインデックスを連携する"}
{"ts":"2026-05-22T12:57:54+09:00","agent":"shogun","direction":"response","summary":"cmd_2970 FTS5","detail":"SQLite記憶DBをFTS5対応にする"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
tables = {
    row[0]
    for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    )
}
cols = [row[1] for row in conn.execute("PRAGMA table_info(event_concepts)")]
print("event_concepts" in tables)
print(",".join(cols))
print(conn.execute("SELECT COUNT(*) FROM event_concepts").fetchone()[0] > 0)
print(conn.execute(
    "SELECT COUNT(*) FROM event_concepts WHERE concept_name='local_memory_db'"
).fetchone()[0] > 0)
print(conn.execute(
    """
    SELECT concept_name, COUNT(*)
    FROM event_concepts
    GROUP BY concept_name
    HAVING concept_name='local_memory_db'
    """
).fetchone()[1])
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM event_concepts AS ec
    JOIN events AS e ON e.id = ec.event_id
    WHERE ec.concept_name='local_memory_db'
      AND e.event_type='conversation'
    """
).fetchone()[0] > 0)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "event_id,concept_name" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "True" ]
    [ "${result[4]}" -ge 1 ]
    [ "${result[5]}" = "True" ]
}

@test "memory_db_import imports bulletin_board entries as bulletin events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/queue/archive"
    cat > "$TEST_TMPDIR/queue/bulletin_board.yaml" <<'EOF'
entries:
- id: 'blt_test_open'
  content: |-
    GATE CLEAR cmd_2977: bulletin投入確認
  posted_by: 'karo'
  posted_at: '2026-05-22T15:00:00'
  requires_confirmation: false
  action_type: 'info'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
EOF
    cat > "$TEST_TMPDIR/queue/archive/bulletin_20260521.yaml" <<'EOF'
entries:
- id: 'blt_test_archive'
  content: |-
    INSIGHT_REPEAT: source=semantic_stress_test pending_count=3
  posted_by: 'saizo'
  posted_at: '2026-05-21T15:00:00'
  requires_confirmation:
    - 'shogun'
  action_type: 'action_required'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bulletins=2"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='conversation'").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='bulletin'").fetchone()[0])
row = conn.execute(
    "SELECT agent, direction, summary, cmd_id, importance FROM events WHERE id='bulletin:blt_test_open'"
).fetchone()
print("|".join(row))
print(conn.execute(
    "SELECT importance FROM events WHERE id='bulletin:blt_test_archive'"
).fetchone()[0])
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "2" ]
    [ "${result[2]}" = "karo|info|GATE CLEAR cmd_2977: bulletin投入確認|cmd_2977|normal" ]
    [ "${result[3]}" = "high" ]
}

@test "memory_db_import imports insights.yaml entries as insight events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/queue"
    cat > "$TEST_TMPDIR/queue/insights.yaml" <<'EOF'
insights:
- id: INS-test-pending
  ts: "2026-05-22T15:10:00+09:00"
  insight: "cmd_2978 insight投入テスト pending"
  priority: "medium"
  source: "manual"
  status: pending
- id: INS-test-resolved
  ts: "2026-05-22T15:11:00+09:00"
  insight: "resolved insight should remain searchable"
  priority: "low"
  source: "semantic_stress_test"
  status: resolved
  resolved_reason: "noise"
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"insights=2"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='conversation'").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='insight'").fetchone()[0])
row = conn.execute(
    "SELECT agent, direction, summary, cmd_id, importance FROM events WHERE id='insight:INS-test-pending'"
).fetchone()
print("|".join(row))
print(conn.execute(
    "SELECT detail FROM events WHERE id='insight:INS-test-resolved'"
).fetchone()[0].replace("\n", "|"))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.event_type = 'insight'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "2" ]
    [ "${result[2]}" = "manual|pending|cmd_2978 insight投入テスト pending|cmd_2978|high" ]
    [[ "${result[3]}" == *"resolved_reason: noise"* ]]
    [ "${result[4]}" = "1" ]
}

@test "memory_db_import imports skill execution log entries as skill_execution events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/logs"
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'EOF'
executions:
- ts: "2026-05-22T18:00:00+0900"
  skill: "report-write"
  executor: "saizo"
  result: "PASS"
  used: "true"
  stumbling_points: "cmd_2992 report gate searchable"
  gate: "gate_report_format"
  source: "queue/reports/saizo_report_cmd_2992.yaml"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/report-write/SKILL.md"
- ts: "2026-05-22T18:01:00+0900"
  skill: "verdict-check"
  executor: "saizo"
  result: "FAIL"
  stumbling_points: "binary check mismatch"
  gate: "gate_report_format"
  source: "queue/reports/saizo_report_cmd_2992.yaml"
  skill_path: "/mnt/c/tools/multi-agent-shogun/skills/verdict-check/SKILL.md"
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skill_executions=2"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type='skill_execution'").fetchone()[0])
row = conn.execute(
    "SELECT agent, target, direction, cmd_id, importance FROM events WHERE event_type='skill_execution' AND target='report-write'"
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.event_type='skill_execution'
    """
).fetchone()[0])
print(conn.execute(
    "SELECT importance FROM events WHERE event_type='skill_execution' AND target='verdict-check'"
).fetchone()[0])
PY
)
    [ "${result[0]}" = "2" ]
    [ "${result[1]}" = "saizo|report-write|PASS|cmd_2992|normal" ]
    [ "${result[2]}" = "1" ]
    [ "${result[3]}" = "high" ]
}

@test "memory_db_import imports completed cmd archive entries as cmd_archive events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/queue/archive/cmds"
    cat > "$TEST_TMPDIR/queue/archive/cmds/cmd_2992_done_20260522.yaml" <<'EOF'
commands:
  cmd_2992:
    id: cmd_2992
    title: "memory DB archive import"
    project: infra
    type: impl
    purpose: "completed cmd archive searchable purpose"
    acceptance_criteria:
    - "AC1: cmd archive imported"
    timestamp: "2026-05-22T18:05:00+09:00"
    status: done
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_archives=1"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "SELECT event_type, agent, target, direction, summary, cmd_id, importance FROM events WHERE event_type='cmd_archive'"
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.event_type='cmd_archive'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "cmd_archive|shogun|infra|done|memory DB archive import|cmd_2992|normal" ]
    [ "${result[1]}" = "1" ]
}

@test "memory_db_import imports pending_decisions.yaml entries as pending_decision events" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    mkdir -p "$TEST_TMPDIR/queue"
    cat > "$TEST_TMPDIR/queue/pending_decisions.yaml" <<'EOF'
summary:
  total: 1
  resolved: 0
  pending: 1
decisions:
- id: PD-999
  type: lord_decision
  summary: "cmd_2992 pending decision searchable"
  source_cmd: cmd_2992
  status: pending
  created_at: "2026-05-22T18:06:00+09:00"
  created_by: shogun
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pending_decisions=1"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "SELECT event_type, agent, target, direction, summary, cmd_id, importance FROM events WHERE id='pending_decision:PD-999'"
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.event_type='pending_decision'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "pending_decision|shogun|cmd_2992|pending|cmd_2992 pending decision searchable|cmd_2992|high" ]
    [ "${result[1]}" = "1" ]
}

@test "memory_db_import uses WAL and preserves live inserts across rebuilds" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        bulletin \
        --entry-id "live-test" \
        --ts "2026-05-22T17:05:00" \
        --agent "hayate" \
        --content "cmd_2984 live insert during import test" \
        --source-file "queue/inbox/hayate.yaml"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("PRAGMA journal_mode").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM conversations").fetchone()[0])
print(conn.execute("SELECT COUNT(*) FROM events WHERE id='bulletin:live-test'").fetchone()[0])
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'cmd_2984'
      AND e.id='bulletin:live-test'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "wal" ]
    [ "${result[1]}" = "1" ]
    [ "${result[2]}" = "1" ]
    [ "${result[3]}" = "1" ]
}

@test "memory_db_live_insert appends workaround events with event_type workaround" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        workaround \
        --cmd-id "cmd_2990" \
        --ts "2026-05-22T18:10:00Z" \
        --ninja "hayate" \
        --category "report_yaml_format" \
        --issue "manual workaround recorded" \
        --root-cause "manual fix applied" \
        --source-file "logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    """
    SELECT event_type, agent, target, direction, summary, replace(detail, char(10), '|'), cmd_id, importance, source_file
    FROM events
    WHERE id='workaround:cmd_2990:hayate:2026-05-22T18:10:00Z'
    """
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'workaround'
      AND e.event_type='workaround'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "workaround|karo|hayate|report_yaml_format|manual workaround recorded|manual workaround recorded|root_cause: manual fix applied|category: report_yaml_format|ninja: hayate|cmd_2990|high|logs/karo_workarounds.yaml" ]
    [ "${result[1]}" = "1" ]
}

@test "memory_db_import extracts obsidian links into event_links table" {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"shogun","direction":"response","summary":"[[3層記憶モデル]]の設計","detail":"[[Obsidianリンク未連携]]と[[event_links因果辺]]を接続する。[[3層記憶モデル]]参照。"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"lord","direction":"inbound","summary":"確認","detail":"[[event_links因果辺]]のクエリ動作確認"}
{"ts":"2026-05-22T12:02:00+09:00","agent":"shogun","direction":"response","summary":"リンクなし","detail":"通常のテキストのみ"}
EOF

    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
# AC1: event_links table exists with correct columns
tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
cols = [row[1] for row in conn.execute("PRAGMA table_info(event_links)")]
print("event_links" in tables)
print(",".join(cols))
# AC2: obsidian links extracted
total = conn.execute("SELECT COUNT(*) FROM event_links").fetchone()[0]
print(total > 0)
row3 = conn.execute(
    "SELECT COUNT(*) FROM event_links WHERE target_concept='3層記憶モデル'"
).fetchone()[0]
print(row3)
link_type = conn.execute("SELECT DISTINCT link_type FROM event_links").fetchone()[0]
print(link_type)
# AC3: top-concept aggregation query
rows = conn.execute(
    "SELECT target_concept, COUNT(*) FROM event_links GROUP BY target_concept ORDER BY COUNT(*) DESC LIMIT 5"
).fetchall()
top_concept = rows[0][0]
top_count = rows[0][1]
print(top_concept)
print(top_count >= 2)
# no links for plain-text event
no_links_event_count = conn.execute(
    """
    SELECT COUNT(*) FROM events e
    WHERE e.summary='リンクなし'
      AND EXISTS (SELECT 1 FROM event_links el WHERE el.source_event_id = e.id)
    """
).fetchone()[0]
print(no_links_event_count == 0)
PY
)
    [ "${result[0]}" = "True" ]
    [ "${result[1]}" = "source_event_id,target_concept,link_type" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" -ge 1 ]
    [ "${result[4]}" = "obsidian" ]
    [ "${result[5]}" = "event_links因果辺" ]
    [ "${result[6]}" = "True" ]
    [ "${result[7]}" = "True" ]
}
