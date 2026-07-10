#!/usr/bin/env bats
# T7 loop_ledger_update.sh 検証 (cmd_3720)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/loop_ledger_update.sh"
    [ -x "$SRC_SCRIPT" ] || return 1
}

setup() {
    # naive fixture timestamps are interpreted as local time; pin TZ so
    # assertions hold on both JST dev machines and UTC CI
    export TZ=UTC
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/loop_ledger.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/queue/archive/reports" "$TEST_TMPDIR/data"
    export LOOP_LEDGER_ROOT="$TEST_TMPDIR"
    export LOOP_LEDGER_LESSON_IMPACT="$TEST_TMPDIR/logs/lesson_impact.tsv"
    export LOOP_LEDGER_INSIGHTS_FILE="$TEST_TMPDIR/queue/insights.yaml"
    export LOOP_LEDGER_DB="$TEST_TMPDIR/data/memory.db"
    export LOOP_LEDGER_SKILL_RECOMMEND_LOG="$TEST_TMPDIR/logs/skill_recommend_log.yaml"
    export LOOP_LEDGER_SKILL_EXECUTION_LOG="$TEST_TMPDIR/logs/skill_execution_log.yaml"
    export LOOP_LEDGER_REPORT_DIRS="$TEST_TMPDIR/queue/reports:$TEST_TMPDIR/queue/archive/reports"
    export LOOP_LEDGER_REPORT_MAX_FILES="500"
    export LOOP_LEDGER_OUT="$TEST_TMPDIR/logs/loop_ledger.yaml"
    export LOOP_LEDGER_NOW="2026-06-20T00:00:00Z"
    export LOOP_LEDGER_WINDOW_DAYS="14"
    export LOOP_LEDGER_STARTUP_ALERT_HISTORY="$TEST_TMPDIR/logs/shogun_startup_alert_history.tsv"
    export LOOP_LEDGER_GATE_METRICS_LOG="$TEST_TMPDIR/logs/gate_metrics.log"
}

teardown() {
    unset LOOP_LEDGER_ROOT LOOP_LEDGER_LESSON_IMPACT LOOP_LEDGER_INSIGHTS_FILE LOOP_LEDGER_DB \
        LOOP_LEDGER_SKILL_RECOMMEND_LOG LOOP_LEDGER_SKILL_EXECUTION_LOG \
        LOOP_LEDGER_REPORT_DIRS LOOP_LEDGER_REPORT_MAX_FILES LOOP_LEDGER_OUT LOOP_LEDGER_NOW LOOP_LEDGER_WINDOW_DAYS \
        LOOP_LEDGER_STARTUP_ALERT_HISTORY LOOP_LEDGER_GATE_METRICS_LOG
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

make_obsidian_db() {
    python3 - "$LOOP_LEDGER_DB" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, ts TEXT, agent TEXT, summary TEXT, detail TEXT, state TEXT)")
conn.execute("CREATE TABLE event_state_transitions (id INTEGER PRIMARY KEY, event_id TEXT, from_state TEXT, to_state TEXT, reason TEXT, actor TEXT, transitioned_at TEXT)")
conn.execute("INSERT INTO events (id, state) VALUES ('e1', 'obsidian_candidate')")
conn.execute("INSERT INTO events (id, state) VALUES ('e2', 'obsidian_promoted')")
conn.execute("INSERT INTO event_state_transitions (event_id, from_state, to_state, reason, actor, transitioned_at) VALUES ('e2','raw','obsidian_candidate','x','y','2026-06-14T00:00:00')")
conn.execute("INSERT INTO event_state_transitions (event_id, from_state, to_state, reason, actor, transitioned_at) VALUES ('e2','obsidian_candidate','obsidian_promoted','x','y','2026-06-16T00:00:00')")
conn.execute("INSERT INTO event_state_transitions (event_id, from_state, to_state, reason, actor, transitioned_at) VALUES ('e1','raw','obsidian_candidate','x','y','2026-06-17T00:00:00')")
conn.commit()
conn.close()
PY
}

add_memory_loop_data() {
    python3 - "$LOOP_LEDGER_DB" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
conn.execute("CREATE TABLE IF NOT EXISTS search_logs (id INTEGER PRIMARY KEY, ts TEXT NOT NULL, caller TEXT NOT NULL, agent_id TEXT, query TEXT NOT NULL, hit_count INTEGER NOT NULL, no_match INTEGER NOT NULL, elapsed_ms INTEGER NOT NULL, exit_code INTEGER)")
conn.execute("INSERT INTO search_logs (ts, caller, agent_id, query, hit_count, no_match, elapsed_ms, exit_code) VALUES ('2026-06-15T00:00:00','semantic_search','shogun','alpha',3,0,10,0)")
conn.execute("INSERT INTO search_logs (ts, caller, agent_id, query, hit_count, no_match, elapsed_ms, exit_code) VALUES ('2026-06-16T00:00:00','memory_db_query','shogun','beta',1,0,11,0)")
conn.execute("INSERT INTO search_logs (ts, caller, agent_id, query, hit_count, no_match, elapsed_ms, exit_code) VALUES ('2026-05-01T00:00:00','memory_db_query','shogun','old',1,0,12,0)")
conn.execute("INSERT INTO events (id, ts, agent, summary, detail, state) VALUES ('m1','2026-06-17T00:00:00','shogun','回答 [memory:search_logs:alpha]','引用タグあり','raw')")
conn.execute("INSERT INTO events (id, ts, agent, summary, detail, state) VALUES ('m2','2026-06-18T00:00:00','shogun','三層記憶について通常言及','タグなし通常文は消費扱いしない','raw')")
conn.execute("INSERT INTO events (id, ts, agent, summary, detail, state) VALUES ('m3','2026-06-17T00:00:00','karo','回答 [memory:ignored]','将軍以外は消費扱いしない','raw')")
conn.commit()
conn.close()
PY
}

add_memory_reference_reports() {
    cat > "$TEST_TMPDIR/queue/reports/kagemaru_report_cmd_memory.yaml" <<'EOF'
worker_id: kagemaru
parent_cmd: cmd_memory
memory_references:
- id: MEM001
  source: semantic_search
  query: useful query
  used: true
  useful: true
  reason: 実装対象の接続点特定に使った
- id: MEM002
  source: semantic_search
  query: unrelated semantic query
  used: false
  useful: false
  reason: 対象cmdと無関係だった
- id: MEM003
  source: memory_db
  query: unrelated db query
  used: false
  useful: false
  reason: 古い別cmdの記録だった
EOF
}

@test "loop_ledger_update records throughput daily medians from gate_metrics stage durations" {
    cat > "$LOOP_LEDGER_GATE_METRICS_LOG" <<'EOF'
2026-06-19T00:00:00	cmd_1	CLEAR	all_gates_passed	full	GPT	unknown	L001	title	duration_sec=300	deploy_sec=60 work_sec=300 finalize_sec=120 e2e_sec=600 missing=none	ctx_pct=10	first_model=GPT
2026-06-19T01:00:00	cmd_2	CLEAR	all_gates_passed	full	GPT	unknown	L001	title	duration_sec=500	deploy_sec=180 work_sec=500 finalize_sec=180 e2e_sec=1000 missing=none	ctx_pct=10	first_model=GPT
2026-06-19T02:00:00	cmd_3	BLOCK	report_format	full	GPT	unknown	L001	title	first_model=GPT
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"throughput: produced=2 consumed=2 stock=0"* ]]
    [[ "$output" == *"daily: completed_cmds=2 e2e_median_sec=800.0 overhead_rate_median_pct=50.0 deploy_median_sec=120.0 work_median_sec=400.0 finalize_median_sec=150.0"* ]]

    grep -q 'throughput:' "$LOOP_LEDGER_OUT"
    grep -q 'completed_cmds: 2' "$LOOP_LEDGER_OUT"
    grep -q 'e2e_median_sec: "800.0"' "$LOOP_LEDGER_OUT"
    grep -q 'overhead_rate_median_pct: "50.0"' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update alerts when throughput e2e or overhead median worsens" {
    cat > "$LOOP_LEDGER_OUT" <<'EOF'
snapshots:
- generated_at: "2026-06-19T00:00:00Z"
  window_days: 14
  loops:
    lesson: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    insight: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    semantic: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    promotion: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    obsidian: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    memory: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    skill: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
    throughput: {produced: 1, consumed: 1, stock: 0, last_consumption_ts: "2026-06-19T00:00:00Z", stalled: false, e2e_median_sec: "500.0", overhead_rate_median_pct: "20.0"}
alerts: []
EOF
    cat > "$LOOP_LEDGER_GATE_METRICS_LOG" <<'EOF'
2026-06-19T01:00:00	cmd_2	CLEAR	all_gates_passed	full	GPT	unknown	L001	title	duration_sec=500	deploy_sec=200 work_sec=500 finalize_sec=300 e2e_sec=1200 missing=none	ctx_pct=10	first_model=GPT
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: throughput: E2E中央値悪化(前回500.0→今回1200.0秒)"* ]]
    [[ "$output" == *"ALERT: throughput: オーバーヘッド率悪化(前回20.0→今回58.3%)"* ]]
    grep -q 'throughput: E2E中央値悪化' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update computes produced/consumed/stock across all 6 loops and detects semantic stall" {
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
  resolved_reason: "implemented"
  action_artifact: "cmd_implemented"
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
  resolved_reason: "alias exists"
  action_artifact: "context/semantic-map.md"
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
    add_memory_loop_data
    add_memory_reference_reports

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 1 ]

    [[ "$output" == *"lesson: produced=2 consumed=1 stock=1"* ]]
    [[ "$output" == *"insight: produced=3 consumed=1 stock=2"* ]]
    [[ "$output" == *"semantic: produced=1 consumed=0 stock=1"* ]]
    [[ "$output" == *"obsidian: produced=2 consumed=1 stock=1"* ]]
    [[ "$output" == *"memory: produced=2 consumed=1 stock=1"* ]]
    [[ "$output" == *"effectiveness: evaluated=3 useful=1 useful_rate_pct=33.3 reflux_targets=2"* ]]
    [[ "$output" == *"skill: produced=2 consumed=1 stock=2"* ]]
    [[ "$output" == *"ALERT: semantic: 空転(produced=1, consumed=0, window=14d)"* ]]

    # W6(cmd_3748): 気づき在庫(insight/semantic)の初回検出からの経過時間
    [[ "$output" == *"aging: oldest_pending_ts=2026-06-14T15:00:00Z oldest_pending_age_hours=129.0"* ]]
    [[ "$output" == *"aging: oldest_pending_ts=2026-06-17T15:00:00Z oldest_pending_age_hours=57.0"* ]]

    grep -q 'generated_at: "2026-06-20T00:00:00Z"' "$LOOP_LEDGER_OUT"
    grep -q 'semantic:' "$LOOP_LEDGER_OUT"
    grep -q 'memory:' "$LOOP_LEDGER_OUT"
    grep -q 'oldest_pending_ts: "2026-06-14T15:00:00Z"' "$LOOP_LEDGER_OUT"
    grep -q 'oldest_pending_age_hours: 129.0' "$LOOP_LEDGER_OUT"
    grep -q 'oldest_pending_ts: "2026-06-17T15:00:00Z"' "$LOOP_LEDGER_OUT"
    grep -q 'oldest_pending_age_hours: 57.0' "$LOOP_LEDGER_OUT"
    grep -q 'evaluated: 3' "$LOOP_LEDGER_OUT"
    grep -q 'useful: 1' "$LOOP_LEDGER_OUT"
    grep -q 'useful_rate_pct: 33.3' "$LOOP_LEDGER_OUT"
    grep -q '"memory_db": 1' "$LOOP_LEDGER_OUT"
    grep -q '"semantic_search": 1' "$LOOP_LEDGER_OUT"
    grep -q 'reflux_targets:' "$LOOP_LEDGER_OUT"
    grep -q 'stalled: true' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update reports memory reference effectiveness without requiring search logs" {
    make_obsidian_db
    add_memory_reference_reports

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"memory: produced=2 consumed=1 stock=1"* ]]
    [[ "$output" == *"effectiveness: evaluated=3 useful=1 useful_rate_pct=33.3 reflux_targets=2"* ]]
    grep -q 'report_count: 1' "$LOOP_LEDGER_OUT"
    grep -q 'sample_query: "unrelated db query"' "$LOOP_LEDGER_OUT"
    grep -q 'sample_reason: "古い別cmdの記録だった"' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update does not treat append-only searches as actionable memory stock" {
    make_obsidian_db
    python3 - "$LOOP_LEDGER_DB" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
conn.execute("CREATE TABLE search_logs (id INTEGER PRIMARY KEY, ts TEXT NOT NULL, caller TEXT NOT NULL, agent_id TEXT, query TEXT NOT NULL, hit_count INTEGER NOT NULL, no_match INTEGER NOT NULL, elapsed_ms INTEGER NOT NULL, exit_code INTEGER)")
conn.execute("INSERT INTO search_logs (ts, caller, agent_id, query, hit_count, no_match, elapsed_ms, exit_code) VALUES ('2026-06-15T00:00:00','semantic_search','shogun','alpha',3,0,10,0)")
conn.execute("INSERT INTO events (id, ts, agent, summary, detail, state) VALUES ('m1','2026-06-17T00:00:00','shogun','三層記憶について通常言及','タグなし通常文','raw')")
conn.commit()
conn.close()
PY

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"memory: produced=2 consumed=1 stock=1"* ]]
    grep -q 'search_count: 1' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update rejects unproved insight resolution and counts memory candidate states" {
    cat > "$LOOP_LEDGER_INSIGHTS_FILE" <<'EOF'
insights:
- id: INS-BAD
  ts: "2026-06-18T00:00:00Z"
  source: manual
  status: resolved
  resolved_reason: "claimed fixed"
EOF
    make_obsidian_db

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"insight: produced=1 consumed=0 stock=0"* ]]
    [[ "$output" == *"memory: produced=2 consumed=1 stock=1"* ]]
    grep -q 'invalid_resolution_count: 1' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update records promotion candidate aging from first detection" {
    mkdir -p "$TEST_TMPDIR/scripts/gates"
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_enforcement_level.sh" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
=== 昇格候補一覧(L4未満、恒久防御未到達) 2件 ===
  - [lessons_karo.yaml] L901 (L2:事前予防(doc)): doc-only lesson
  - [lessons_gunshi.yaml] L902 (L3:事前強制(auto-gen)): weak lesson
##ENFORCEMENT_LEVEL_BELOW4_COUNT##
2
OUT
SH
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_enforcement_level.sh"

    export LOOP_LEDGER_NOW="2026-06-20T00:00:00Z"
    run bash "$SRC_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"promotion: produced=2 consumed=0 stock=2"* ]]
    [[ "$output" == *"aging: stock_started_at=2026-06-20T00:00:00Z age_hours=0.0"* ]]
    grep -q 'stock_started_at: "2026-06-20T00:00:00Z"' "$LOOP_LEDGER_OUT"
    grep -q 'age_hours: 0.0' "$LOOP_LEDGER_OUT"
    grep -q 'first_candidate: "\[lessons_karo.yaml\] L901' "$LOOP_LEDGER_OUT"

    export LOOP_LEDGER_NOW="2026-06-21T12:00:00Z"
    run bash "$SRC_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"promotion: produced=2 consumed=0 stock=2"* ]]
    [[ "$output" == *"aging: stock_started_at=2026-06-20T00:00:00Z age_hours=36.0"* ]]
    grep -q 'age_hours: 36.0' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update counts completed reflux promotion commands as consumption" {
    mkdir -p "$TEST_TMPDIR/scripts/gates"
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_enforcement_level.sh" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
=== 昇格候補一覧(L4未満、恒久防御未到達) 2件 ===
  - [lessons_karo.yaml] L901 (L2:事前予防(doc)): doc-only lesson
  - [lessons_gunshi.yaml] L902 (L3:事前強制(auto-gen)): weak lesson
##ENFORCEMENT_LEVEL_BELOW4_COUNT##
2
OUT
SH
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_enforcement_level.sh"

    cat > "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'EOF'
entries:
- cmd_id: "cmd_reflux_promotion_202606190001_hanzo"
  gate_result: "CLEAR"
  timestamp: "2026-06-19T00:01:00Z"
- cmd_id: "cmd_reflux_promotion_202606190001_hanzo"
  gate_result: "CLEAR"
  timestamp: "2026-06-19T00:02:00Z"
- cmd_id: "cmd_reflux_promotion_202606190002_kotaro"
  gate_result: "CLEAR"
  timestamp: "2026-06-19T00:03:00Z"
- cmd_id: "cmd_reflux_promotion_202606190003_saizo"
  gate_result: "BLOCK"
  timestamp: "2026-06-19T00:04:00Z"
- cmd_id: "cmd_reflux_promotion_202605010001_old"
  gate_result: "CLEAR"
  timestamp: "2026-05-01T00:01:00Z"
EOF

    export LOOP_LEDGER_NOW="2026-06-20T00:00:00Z"
    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"promotion: produced=2 consumed=2 stock=2 last_consumption=2026-06-19T00:03:00Z"* ]]
    [[ "$output" != *"ALERT: promotion: 空転"* ]]
    grep -q 'consumed: 2' "$LOOP_LEDGER_OUT"
    grep -q 'last_consumption_ts: "2026-06-19T00:03:00Z"' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update counts reflux promotion consumption from gate_metrics.log" {
    mkdir -p "$TEST_TMPDIR/scripts/gates"
    cat > "$TEST_TMPDIR/scripts/gates/gate_lesson_enforcement_level.sh" <<'SH'
#!/usr/bin/env bash
cat <<'OUT'
=== 昇格候補一覧(L4未満、恒久防御未到達) 2件 ===
  - [lessons_karo.yaml] L901 (L2:事前予防(doc)): doc-only lesson
  - [lessons_gunshi.yaml] L902 (L3:事前強制(auto-gen)): weak lesson
##ENFORCEMENT_LEVEL_BELOW4_COUNT##
2
OUT
SH
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_enforcement_level.sh"

    # reflux cmds skip cmd_save: they appear only in gate_metrics.log, never in cmd_design_quality.yaml
    cat > "$LOOP_LEDGER_GATE_METRICS_LOG" <<'EOF'
2026-06-19T00:01:00	cmd_reflux_promotion_202606190001_hanzo	CLEAR	all_gates_passed	exact	unknown	unknown	L901
2026-06-19T00:02:00	cmd_reflux_promotion_202606190001_hanzo	CLEAR	all_gates_passed	exact	unknown	unknown	L901
2026-06-19T00:03:00	cmd_reflux_promotion_202606190002_kotaro	CLEAR	all_gates_passed	exact	unknown	unknown	L902
2026-06-19T00:04:00	cmd_reflux_promotion_202606190003_saizo	BLOCK	report_missing	exact	unknown	unknown	L902
2026-05-01T00:01:00	cmd_reflux_promotion_202605010001_old	CLEAR	all_gates_passed	exact	unknown	unknown	L900
EOF

    export LOOP_LEDGER_NOW="2026-06-20T00:00:00Z"
    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"promotion: produced=2 consumed=2 stock=2 last_consumption=2026-06-19T00:03:00Z"* ]]
    [[ "$output" != *"ALERT: promotion: 空転"* ]]
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
    memory: {produced: 0, consumed: 0, stock: 0, last_consumption_ts: null, stalled: false}
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

@test "loop_ledger_update records warn backlog aging from first detection, resolved keys drop off" {
    cat > "$LOOP_LEDGER_STARTUP_ALERT_HISTORY" <<'EOF'
2026-06-15T10:00:00+0900	未push滞留: 40件(RED先送り。CI GREEN確認後にpush)
2026-06-18T10:00:00+0900	未push滞留: 60件(RED先送り。CI GREEN確認後にpush)
2026-06-18T10:00:00+0900	三層記憶DB健全性: WARN
2026-06-19T22:00:00+0900	未push滞留: 70件(RED先送り。CI GREEN確認後にpush)
EOF

    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]

    # W6(cmd_3748): 未解消WARN(直近runにも出現中のキー)のみ在庫としてage計測。
    # 三層記憶DB健全性は直近runで解消済みのため在庫から除外される。
    [[ "$output" == *"warn_backlog: produced=2 consumed=0 stock=1"* ]]
    [[ "$output" == *"aging: key=未push滞留 first_seen=2026-06-15T01:00:00Z age_hours=119.0"* ]]

    grep -q 'warn_backlog:' "$LOOP_LEDGER_OUT"
    grep -q 'stock: 1' "$LOOP_LEDGER_OUT"
    grep -q 'key: "未push滞留"' "$LOOP_LEDGER_OUT"
    grep -q 'first_seen: "2026-06-15T01:00:00Z"' "$LOOP_LEDGER_OUT"
    grep -q 'age_hours: 119.0' "$LOOP_LEDGER_OUT"
    grep -q 'sample: "未push滞留: 70件(RED先送り。CI GREEN確認後にpush)"' "$LOOP_LEDGER_OUT"
    ! grep -q '三層記憶DB健全性' "$LOOP_LEDGER_OUT"
}

@test "loop_ledger_update warn backlog is empty when history file is missing" {
    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn_backlog: produced=0 consumed=0 stock=0"* ]]
    grep -q 'warn_backlog:' "$LOOP_LEDGER_OUT"
    grep -q 'items: \[\]' "$LOOP_LEDGER_OUT"
}
