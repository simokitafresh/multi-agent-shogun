#!/usr/bin/env bats
# T7 loop_ledger_update.sh 検証 (cmd_3720)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/loop_ledger_update.sh"
    [ -x "$SRC_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/loop_ledger.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/data"
    export LOOP_LEDGER_LESSON_IMPACT="$TEST_TMPDIR/logs/lesson_impact.tsv"
    export LOOP_LEDGER_INSIGHTS_FILE="$TEST_TMPDIR/queue/insights.yaml"
    export LOOP_LEDGER_DB="$TEST_TMPDIR/data/memory.db"
    export LOOP_LEDGER_SKILL_RECOMMEND_LOG="$TEST_TMPDIR/logs/skill_recommend_log.yaml"
    export LOOP_LEDGER_SKILL_EXECUTION_LOG="$TEST_TMPDIR/logs/skill_execution_log.yaml"
    export LOOP_LEDGER_OUT="$TEST_TMPDIR/logs/loop_ledger.yaml"
    export LOOP_LEDGER_NOW="2026-06-20T00:00:00Z"
    export LOOP_LEDGER_WINDOW_DAYS="14"
}

teardown() {
    unset LOOP_LEDGER_LESSON_IMPACT LOOP_LEDGER_INSIGHTS_FILE LOOP_LEDGER_DB \
        LOOP_LEDGER_SKILL_RECOMMEND_LOG LOOP_LEDGER_SKILL_EXECUTION_LOG \
        LOOP_LEDGER_OUT LOOP_LEDGER_NOW LOOP_LEDGER_WINDOW_DAYS
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

make_obsidian_db() {
    python3 - "$LOOP_LEDGER_DB" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, state TEXT)")
conn.execute("CREATE TABLE event_state_transitions (id INTEGER PRIMARY KEY, event_id TEXT, from_state TEXT, to_state TEXT, reason TEXT, actor TEXT, transitioned_at TEXT)")
conn.execute("INSERT INTO events VALUES ('e1', 'obsidian_candidate')")
conn.execute("INSERT INTO events VALUES ('e2', 'obsidian_promoted')")
conn.execute("INSERT INTO event_state_transitions (event_id, from_state, to_state, reason, actor, transitioned_at) VALUES ('e2','raw','obsidian_candidate','x','y','2026-06-14T00:00:00')")
conn.execute("INSERT INTO event_state_transitions (event_id, from_state, to_state, reason, actor, transitioned_at) VALUES ('e2','obsidian_candidate','obsidian_promoted','x','y','2026-06-16T00:00:00')")
conn.execute("INSERT INTO event_state_transitions (event_id, from_state, to_state, reason, actor, transitioned_at) VALUES ('e1','raw','obsidian_candidate','x','y','2026-06-17T00:00:00')")
conn.commit()
conn.close()
PY
}

@test "loop_ledger_update computes produced/consumed/stock across all 5 loops and detects semantic stall" {
    cat > "$LOOP_LEDGER_LESSON_IMPACT" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-06-15T00:00:00	cmd_1	hayate	L001	injected	USEFUL	yes	infra	full	unknown	0	0
2026-06-15T00:00:00	cmd_1	hayate	L001	feedback	USEFUL	yes	infra	full	unknown	0	0
2026-06-15T00:00:00	cmd_1	hayate	L002	injected	NOT_USEFUL	yes	infra	full	unknown	0	0
EOF

    cat > "$LOOP_LEDGER_INSIGHTS_FILE" <<'EOF'
insights:
- id: INS-1
  ts: "2026-06-15T00:00:00+09:00"
  insight: "manual note candidate"
  priority: "low"
  source: "manual"
  status: pending
- id: INS-2
  ts: "2026-06-16T00:00:00+09:00"
  insight: "manual note resolved"
  priority: "low"
  source: "manual"
  resolved_at: "2026-06-17T00:00:00+09:00"
  status: resolved
- id: INS-3
  ts: "2026-06-18T00:00:00+09:00"
  insight: "semantic_stress_test candidate_aliases NO_MATCH query=foo"
  priority: "low"
  source: "semantic_stress_test"
  status: pending
- id: INS-4
  ts: "2026-05-01T00:00:00+09:00"
  insight: "semantic_index_update新概念候補: discussion:old query"
  priority: "low"
  source: "semantic_index_update"
  resolved_at: "2026-05-02T00:00:00+09:00"
  status: resolved
EOF

    cat > "$LOOP_LEDGER_SKILL_RECOMMEND_LOG" <<'EOF'
recommendations:
- ts: "2026-06-15T00:00:00+09:00"
  agent_id: "hayate"
  prompt_hash: "abc"
  recommended_skills:
  - "report-write"
  - "verdict-check"
- ts: "2026-05-01T00:00:00+09:00"
  agent_id: "hayate"
  prompt_hash: "def"
  recommended_skills:
  - "ninja-commit"
EOF

    cat > "$LOOP_LEDGER_SKILL_EXECUTION_LOG" <<'EOF'
executions:
- ts: "2026-06-16T00:00:00+0900"
  skill: "report-write"
  executor: "hayate"
  result: "PASS"
  used: "true"
EOF

    make_obsidian_db

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 1 ]

    [[ "$output" == *"lesson: produced=2 consumed=1 stock=1"* ]]
    [[ "$output" == *"insight: produced=3 consumed=1 stock=2"* ]]
    [[ "$output" == *"semantic: produced=1 consumed=0 stock=1"* ]]
    [[ "$output" == *"obsidian: produced=2 consumed=1 stock=1"* ]]
    [[ "$output" == *"skill: produced=2 consumed=1 stock=2"* ]]
    [[ "$output" == *"ALERT: semantic: 空転(produced=1, consumed=0, window=14d)"* ]]

    grep -q 'generated_at: "2026-06-20T00:00:00Z"' "$LOOP_LEDGER_OUT"
    grep -q 'semantic:' "$LOOP_LEDGER_OUT"
    grep -q 'stalled: true' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update alerts on stock increase vs previous snapshot" {
    cat > "$LOOP_LEDGER_OUT" <<'EOF'
snapshots:
- generated_at: "2026-06-01T00:00:00Z"
  window_days: 14
  loops:
    lesson: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    insight: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    semantic: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    obsidian: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    skill: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
alerts: []
EOF

    cat > "$LOOP_LEDGER_LESSON_IMPACT" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-06-15T00:00:00	cmd_1	hayate	L001	injected	USEFUL	yes	infra	full	unknown	0	0
2026-06-15T00:00:00	cmd_1	hayate	L001	feedback	USEFUL	yes	infra	full	unknown	0	0
2026-06-15T00:00:00	cmd_1	hayate	L002	injected	NOT_USEFUL	yes	infra	full	unknown	0	0
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: lesson: 在庫超過(前回0→今回1)"* ]]
    grep -q '在庫超過(前回0→今回1)' "$LOOP_LEDGER_OUT"
    grep -c '^- generated_at:' "$LOOP_LEDGER_OUT" | grep -q '^2$'
}

@test "loop_ledger_update handles missing source files gracefully" {
    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lesson: produced=0 consumed=0 stock=0"* ]]
    [[ "$output" == *"note=lesson_impact.tsv not found"* ]]
    [[ "$output" == *"note=memory db not found"* ]]
    [[ "$output" == *"OK: loop ledger updated"* ]]
    [ -f "$LOOP_LEDGER_OUT" ]
}
