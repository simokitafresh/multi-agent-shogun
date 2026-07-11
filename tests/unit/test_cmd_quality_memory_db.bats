#!/usr/bin/env bats
# test_cmd_quality_memory_db.bats — cmd_design_quality live DB insert tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_quality_memory_db.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/archive" "$TEST_TMPDIR/data"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

init_memory_db() {
    cat > "$TEST_TMPDIR/archive/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","direction":"inbound","summary":"会話","detail":"通常ログ"}
EOF
    python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$TEST_TMPDIR/archive" \
        --db "$TEST_TMPDIR/data/memory.db" >/dev/null
}

init_empty_memory_db() {
    python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
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
""")
conn.commit()
PY
}

@test "memory_db_live_insert appends cmd_quality events with event_type cmd_quality" {
    init_memory_db

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        cmd_quality \
        --cmd-id "cmd_2991" \
        --ts "2026-05-22T18:20:00Z" \
        --gate-result "BLOCK" \
        --karo-rework "no" \
        --gunshi-verdict "APPROVE" \
        --ninja-blockers "0" \
        --ac-count "3" \
        --supplementary-cmds "0" \
        --project "infra" \
        --source "cmd_complete_gate" \
        --diagnosis "quality diagnosis" \
        --notes "quality notes" \
        --source-file "logs/cmd_design_quality.yaml"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    """
    SELECT event_type, agent, target, direction, summary, replace(detail, char(10), '|'), cmd_id, importance, source_file
    FROM events
    WHERE id='cmd_quality:cmd_2991:BLOCK:cmd_complete_gate:2026-05-22T18:20:00Z'
    """
).fetchone()
print("|".join(row))
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'diagnosis'
      AND e.event_type='cmd_quality'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "cmd_quality|shogun|cmd_2991|BLOCK|cmd_2991 quality: BLOCK|gate_result: BLOCK|karo_rework: no|gunshi_verdict: APPROVE|ninja_blockers: 0|ac_count: 3|supplementary_cmds: 0|project: infra|source: cmd_complete_gate|diagnosis: quality diagnosis|notes: quality notes|cmd_2991|high|logs/cmd_design_quality.yaml" ]
    [ "${result[1]}" = "1" ]
}

@test "memory_db_live_insert adds raw_content column and stores original inbox content" {
    init_empty_memory_db

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        inbox \
        --message-id "msg_raw_content" \
        --ts "2026-06-03T19:30:00Z" \
        --target-agent "hayate" \
        --from-agent "karo" \
        --content "cmd_3159 原文をraw_contentへ保存する" \
        --message-type "task_assigned" \
        --source-file "queue/inbox/hayate.yaml"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
print(conn.execute("SELECT COUNT(*) FROM pragma_table_info('events') WHERE name='raw_content'").fetchone()[0])
print(conn.execute("SELECT raw_content FROM events WHERE id='inbox:msg_raw_content'").fetchone()[0])
PY
)
    [ "${result[0]}" = "1" ]
    [ "${result[1]}" = "cmd_3159 原文をraw_contentへ保存する" ]
}

@test "memory_db_live_insert ext4 cache removes rollback journal sidecar" {
    init_empty_memory_db
    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/cache/memory.db"
    mkdir -p "$TEST_TMPDIR/cache"
    touch "$SHOGUN_MEMORY_DB_CACHE_PATH-journal" "$SHOGUN_MEMORY_DB_CACHE_PATH-wal" "$SHOGUN_MEMORY_DB_CACHE_PATH-shm"

    run python3 - "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/data/memory.db" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("memory_db_live_insert", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.create_memory_db_ext4_cache(sys.argv[2]))
PY
    [ "$status" -eq 0 ]
    [ -s "$SHOGUN_MEMORY_DB_CACHE_PATH" ]
    [ ! -e "$SHOGUN_MEMORY_DB_CACHE_PATH-journal" ]
    [ ! -e "$SHOGUN_MEMORY_DB_CACHE_PATH-wal" ]
    [ ! -e "$SHOGUN_MEMORY_DB_CACHE_PATH-shm" ]
    unset SHOGUN_MEMORY_DB_CACHE_PATH
}

isolate_three_layer_chain() {
    mkdir -p "$TEST_TMPDIR/docs/semantic-index" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/context"
    export THREE_LAYER_CHAIN_SYNC=1
    export THREE_LAYER_CHAIN_LOG="$TEST_TMPDIR/three_layer_chain_async.log"
    export SEMANTIC_INDEX_PATH="$TEST_TMPDIR/docs/semantic-index/index.md"
    export SEMANTIC_MAP_PATH="$TEST_TMPDIR/context/semantic-map.md"
    export SEMANTIC_MAP_GENERATE="$PROJECT_ROOT/scripts/semantic_map_generate.sh"
    export SEMANTIC_INSIGHT_WRITE="$TEST_TMPDIR/scripts/insight_write.sh"
    export SEMANTIC_MEMORY_DB_PATH="$TEST_TMPDIR/nonexistent_memory.db"
    export SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION=1
    export SEMANTIC_NEW_FILE_LIST="__three_layer_chain_test_no_new_files__"
    unset SEMANTIC_CMD_HISTORY_FILES SEMANTIC_INSIGHTS_PATH SEMANTIC_PROJECTS_CONFIG

    # gate_three_layer_health.shはSHOGUN_MEMORY_DB_CACHE_PATH未指定だと本番キャッシュ
    # (/tmp/shogun_memory_db_cache/...)を参照する。CI等キャッシュ未生成環境では
    # "WARN: 三層記憶DBが存在しない"→STATUS: WARNになり、chain_log起因のPASS/WARN判定と
    # 無関係にテストが環境依存で揺れる。健全な最小fixtureで隔離する。
    export SHOGUN_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/data/three_layer_health_cache.db"
    python3 - "$SHOGUN_MEMORY_DB_CACHE_PATH" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, state TEXT DEFAULT 'raw', raw_content TEXT)")
conn.execute("CREATE TABLE search_logs (ts TEXT, created_at TEXT)")
conn.executemany(
    "INSERT INTO events (id, state, raw_content) VALUES (?, ?, ?)",
    [
        ("event:raw", "raw", "raw content"),
        ("event:verified", "verified", "verified content"),
        ("event:candidate", "obsidian_candidate", "candidate content"),
    ],
)
conn.execute("INSERT INTO search_logs (ts, created_at) VALUES (datetime('now'), datetime('now'))")
conn.commit()
conn.close()
PY

    cat > "$SEMANTIC_INSIGHT_WRITE" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$SEMANTIC_INSIGHT_WRITE"

    cat > "$SEMANTIC_INDEX_PATH" <<'EOF'
# セマンティクスインデックス SSOT

## semantic_dictionary_design — セマンティック辞書構想

| 属性 | 値 |
|------|---|
| id | semantic_dictionary_design |
| label | セマンティック辞書構想 |
| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索 |

| 種別 | パス/参照 |
|------|----------|
| file | `docs/research/semantic_index_design.md` |
EOF
}

@test "memory_db_knowledge_write inserts knowledge directly without communication side effects" {
    init_memory_db
    isolate_three_layer_chain

    run bash "$PROJECT_ROOT/scripts/memory_db_knowledge_write.sh" \
        "Layer1直接パス不在を解消する [[三層貫通設計ギャップ]]" \
        "cmd_3455_test_source" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --cmd-id "cmd_3455"
    [ "$status" -eq 0 ]
    [[ "$output" == OK:\ knowledge:* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    """
    SELECT event_type, direction, summary, cmd_id, source_file, raw_content
    FROM events
    WHERE event_type='knowledge'
    """
).fetchone()
print("|".join(row))
print(conn.execute("SELECT COUNT(*) FROM events WHERE event_type IN ('bulletin','inbox','insight')").fetchone()[0])
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'Layer1'
      AND e.event_type='knowledge'
    """
).fetchone()[0])
print(conn.execute(
    """
    SELECT COUNT(*)
    FROM event_links
    WHERE target_concept='三層貫通設計ギャップ'
    """
).fetchone()[0])
PY
)
    [ "${result[0]}" = "knowledge|direct_insert|Layer1直接パス不在を解消する [[三層貫通設計ギャップ]]|cmd_3455|cmd_3455_test_source|Layer1直接パス不在を解消する [[三層貫通設計ギャップ]]" ]
    [ "${result[1]}" = "0" ]
    [ "${result[2]}" = "1" ]
    [ "${result[3]}" = "1" ]

    # AC1: Layer3 obsidian link candidate is logged from the knowledge text
    run grep -F "CANDIDATE layer3_obsidian_link_candidate" "$THREE_LAYER_CHAIN_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"target=三層貫通設計ギャップ"* ]]

    # AC1: Layer2 semantic_index_update.sh discussion ran without error
    run grep -F "ERROR" "$THREE_LAYER_CHAIN_LOG"
    [ "$status" -ne 0 ]
}

@test "memory_db_knowledge_write logs Layer2 chain failure and gate_three_layer_health detects it" {
    init_memory_db
    isolate_three_layer_chain
    export THREE_LAYER_CHAIN_RETRIES=1
    export THREE_LAYER_SEMANTIC_UPDATE_CMD="$TEST_TMPDIR/scripts/semantic_always_fail.sh"
    cat > "$THREE_LAYER_SEMANTIC_UPDATE_CMD" <<'EOF'
#!/usr/bin/env bash
echo "semantic boom: missing alias source" >&2
exit 7
EOF
    chmod +x "$THREE_LAYER_SEMANTIC_UPDATE_CMD"

    run bash "$PROJECT_ROOT/scripts/memory_db_knowledge_write.sh" \
        "AC2失敗検知テスト用の知識テキスト" \
        "cmd_3715_test_source" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --cmd-id "cmd_3715"
    [ "$status" -eq 0 ]
    [[ "$output" == OK:\ knowledge:* ]]

    run grep -F "ERROR layer2_semantic_index_update_failed" "$THREE_LAYER_CHAIN_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == *'detail="semantic boom: missing alias source"'* ]]
    [[ "$output" == *"payload_b64="* ]]

    run bash "$PROJECT_ROOT/scripts/gates/gate_three_layer_health.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"未貫通件数=1"* ]]
    [[ "$output" == *"STATUS: WARN"* ]]
}

@test "memory_db_knowledge_write repairs unresolved Layer2 chain failure on next write" {
    init_memory_db
    isolate_three_layer_chain
    export THREE_LAYER_CHAIN_RETRIES=1
    export THREE_LAYER_SEMANTIC_UPDATE_CMD="$TEST_TMPDIR/scripts/semantic_repairable.sh"
    payload="$(jq -cn --arg ts "2026-07-07T23:00:00+09:00" --arg summary "過去未貫通知識" --arg detail "source: old_source" '{"timestamp":$ts,"summary":$summary,"detail":$detail}')"
    payload_b64="$(printf '%s' "$payload" | base64 | tr -d '\n')"
    cat > "$THREE_LAYER_CHAIN_LOG" <<EOF
2026-07-07T23:00:01+09:00 ERROR layer2_semantic_index_update_failed event=knowledge:old source=old_source detail="semantic boom" payload_b64=$payload_b64
EOF
    cat > "$THREE_LAYER_SEMANTIC_UPDATE_CMD" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "${TEST_TMPDIR}/semantic_repair_payloads.jsonl"
exit 0
EOF
    chmod +x "$THREE_LAYER_SEMANTIC_UPDATE_CMD"

    run bash "$PROJECT_ROOT/scripts/memory_db_knowledge_write.sh" \
        "新しいwriteが過去未貫通を自己修復する" \
        "cmd_3742_repair_source" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --cmd-id "cmd_3742"
    [ "$status" -eq 0 ]

    run grep -F "OK layer2_semantic_index_update event=knowledge:old source=old_source repair=1" "$THREE_LAYER_CHAIN_LOG"
    [ "$status" -eq 0 ]
    run bash "$PROJECT_ROOT/scripts/gates/gate_three_layer_health.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"未貫通件数=0"* ]]
    [[ "$output" == *"STATUS: PASS"* ]]
}

@test "memory_db_knowledge_write retries transient Layer2 semantic update failure" {
    init_memory_db
    isolate_three_layer_chain
    export THREE_LAYER_CHAIN_RETRIES=2
    export THREE_LAYER_CHAIN_RETRY_SLEEP=0
    export THREE_LAYER_SEMANTIC_UPDATE_CMD="$TEST_TMPDIR/scripts/semantic_once.sh"
    cat > "$THREE_LAYER_SEMANTIC_UPDATE_CMD" <<'EOF'
#!/usr/bin/env bash
count_file="${TEST_TMPDIR}/semantic_once.count"
count=0
[ -f "$count_file" ] && count="$(cat "$count_file")"
count=$((count + 1))
printf '%s' "$count" > "$count_file"
[ "$count" -ge 2 ]
EOF
    chmod +x "$THREE_LAYER_SEMANTIC_UPDATE_CMD"

    run bash "$PROJECT_ROOT/scripts/memory_db_knowledge_write.sh" \
        "一時的なLayer2失敗はretryで解消する" \
        "cmd_3715_retry_test_source" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --cmd-id "cmd_3715"
    [ "$status" -eq 0 ]

    [ "$(cat "$TEST_TMPDIR/semantic_once.count")" = "2" ]
    run grep -F "ERROR layer2_semantic_index_update_failed" "$THREE_LAYER_CHAIN_LOG"
    [ "$status" -ne 0 ]
    run grep -F "OK layer2_semantic_index_update" "$THREE_LAYER_CHAIN_LOG"
    [ "$status" -eq 0 ]
}

@test "memory_db_knowledge_write skips Layer3 candidate log when knowledge has no [[link]]" {
    init_memory_db
    isolate_three_layer_chain

    run bash "$PROJECT_ROOT/scripts/memory_db_knowledge_write.sh" \
        "リンクを含まない普通の知識テキスト" \
        "cmd_3715_test_source" \
        --db "$TEST_TMPDIR/data/memory.db" \
        --cmd-id "cmd_3715"
    [ "$status" -eq 0 ]

    run grep -F "CANDIDATE layer3_obsidian_link_candidate" "$THREE_LAYER_CHAIN_LOG"
    [ "$status" -ne 0 ]
}

@test "cmd_quality_log keeps YAML success when live DB insert fails" {
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/bad-db"

    run env \
        CMD_QUALITY_LOG_FILE="$TEST_TMPDIR/logs/cmd_design_quality.yaml" \
        CMD_QUALITY_FAST_METADATA=1 \
        CMD_QUALITY_SOURCE="test" \
        CMD_QUALITY_PROJECT="infra" \
        SHOGUN_MEMORY_DB="$TEST_TMPDIR/bad-db" \
        bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" \
        cmd_2991 PASS no 0 "db failure must not break yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[cmd_quality_log] Logged: cmd_2991"* ]]

    readarray -t result < <(python3 - "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'PY'
import sys
import yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
entry = data["entries"][0]
print(entry["cmd_id"])
print(entry["gate_result"])
print(entry["source"])
print(entry["notes"])
PY
)
    [ "${result[0]}" = "cmd_2991" ]
    [ "${result[1]}" = "PASS" ]
    [ "${result[2]}" = "test" ]
    [ "${result[3]}" = "db failure must not break yaml" ]
}

@test "cmd_quality_log appends cmd_quality event to live DB after YAML write" {
    init_memory_db
    mkdir -p "$TEST_TMPDIR/logs"

    run env \
        CMD_QUALITY_LOG_FILE="$TEST_TMPDIR/logs/cmd_design_quality.yaml" \
        CMD_QUALITY_FAST_METADATA=1 \
        CMD_QUALITY_SOURCE="cmd_save" \
        CMD_QUALITY_PROJECT="infra" \
        SHOGUN_MEMORY_DB="$TEST_TMPDIR/data/memory.db" \
        bash "$PROJECT_ROOT/scripts/cmd_quality_log.sh" \
        cmd_2991 PASS no 0
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" "$TEST_TMPDIR/logs/cmd_design_quality.yaml" <<'PY'
import sqlite3
import sys
import yaml
conn = sqlite3.connect(sys.argv[1])
entry = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))["entries"][0]
row = conn.execute(
    """
    SELECT event_type, target, direction, cmd_id
    FROM events
    WHERE event_type='cmd_quality'
      AND cmd_id='cmd_2991'
      AND direction='PASS'
    """
).fetchone()
print(entry["cmd_id"])
print(entry["gate_result"])
print("|".join(row))
PY
)
    [ "${result[0]}" = "cmd_2991" ]
    [ "${result[1]}" = "PASS" ]
    [ "${result[2]}" = "cmd_quality|cmd_2991|PASS|cmd_2991" ]
}

@test "memory_db_live_insert attaches semantic concepts for report lesson gate workaround and cmd_quality" {
    init_memory_db
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/docs/semantic-index"
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/scripts/memory_db_live_insert.py"
    cat > "$TEST_TMPDIR/docs/semantic-index/index.md" <<'EOF'
## report_quality_protocol — Report quality protocol
| aliases | report_field_set |

## lesson_lifecycle — Lesson lifecycle
| aliases | lesson lifecycle |

## gate_quality_framework — Gate quality framework
| aliases | quality_gate framework |

## yaml_safe_write — YAML safe write
| aliases | yaml_field_set, report_field_set protected YAML safe write |

## semantic_dictionary_design — Semantic dictionary design
| aliases | セマンティック辞書構想 |
EOF

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        report \
        --report-path "queue/reports/hayate_report_cmd_3116.yaml" \
        --ts "2026-06-02T09:31:00Z" \
        --dot-key "report_field_set.result.summary" \
        --agent "hayate" \
        --parent-cmd "cmd_3116" \
        --source-file "queue/reports/hayate_report_cmd_3116.yaml"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        lesson \
        --lesson-id "L999" \
        --title "semantic index growth and lesson lifecycle" \
        --detail "lesson_candidate origin links semantic index to lesson lifecycle" \
        --source-cmd "cmd_3116" \
        --project "infra" \
        --ts "2026-06-02T09:31:01Z" \
        --source-file "projects/infra/lessons_karo.yaml"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        gate \
        --gate-name "gate_report_format" \
        --result "PASS" \
        --cmd-id "cmd_3116" \
        --detail "report YAML quality_gate framework PASS" \
        --ts "2026-06-02T09:31:02Z" \
        --source-file "scripts/gates/gate_report_format.sh"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        workaround \
        --cmd-id "cmd_3116" \
        --ts "2026-06-02T09:31:03Z" \
        --ninja "hayate" \
        --category "report_yaml_format" \
        --issue "yaml_field_set and report_field_set protected YAML safe write" \
        --root-cause "YAML safe write rule" \
        --source-file "logs/karo_workarounds.yaml"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        cmd_quality \
        --cmd-id "cmd_3116" \
        --ts "2026-06-02T09:31:04Z" \
        --gate-result "PASS" \
        --karo-rework "no" \
        --gunshi-verdict "APPROVE" \
        --ninja-blockers "0" \
        --ac-count "3" \
        --supplementary-cmds "0" \
        --project "infra" \
        --source "cmd_complete_gate" \
        --diagnosis "セマンティック辞書構想 quality gate" \
        --notes "growth loop concept check" \
        --source-file "logs/cmd_design_quality.yaml"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import json
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
expected = {
    "report:hayate_report_cmd_3116.yaml:report_field_set.result.summary:2026-06-02T09:31:00Z": "report_quality_protocol",
    "lesson:L999": "lesson_lifecycle",
    "gate:gate_report_format:cmd_3116:2026-06-02T09:31:02Z": "gate_quality_framework",
    "workaround:cmd_3116:hayate:2026-06-02T09:31:03Z": "yaml_safe_write",
    "cmd_quality:cmd_3116:PASS:cmd_complete_gate:2026-06-02T09:31:04Z": "semantic_dictionary_design",
}
for event_id, concept in expected.items():
    row = conn.execute("SELECT concepts FROM events WHERE id = ?", (event_id,)).fetchone()
    concepts = json.loads(row[0]) if row else []
    junction = conn.execute(
        "SELECT COUNT(*) FROM event_concepts WHERE event_id = ? AND concept_name = ?",
        (event_id, concept),
    ).fetchone()[0]
    print(f"{event_id}|{concept in concepts}|{junction}")
PY
)
    [ "${#result[@]}" -eq 5 ]
    for line in "${result[@]}"; do
        [[ "$line" == *"|True|1" ]]
    done
}

@test "cmd_3123: memory_db_live_insert short aliases match only as complete standalone text" {
    readarray -t result < <(python3 - "$PROJECT_ROOT/scripts/memory_db_live_insert.py" <<'PY'
import importlib.util
import json
import sys

spec = importlib.util.spec_from_file_location("memory_db_live_insert", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

concepts = [
    {"id": "apt_concept", "terms": ["apt"]},
    {"id": "hmm_concept", "terms": ["HMM"]},
    {"id": "mvo_concept", "terms": ["MVO"]},
]
cases = [
    ("apt", ["apt_concept"]),
    ("apt-get", []),
    ("apt install", []),
    ("HMM", ["hmm_concept"]),
    ("HMM model", []),
    ("MVO", ["mvo_concept"]),
    ("MVO optimization", []),
]
for text, expected in cases:
    actual = json.loads(module.concepts_for_text(text, concepts))
    print(f"{text}|{actual == expected}|{actual}")
PY
)
    [ "${#result[@]}" -eq 7 ]
    for line in "${result[@]}"; do
        [[ "$line" == *"|True|"* ]]
    done
}

@test "memory_db_live_insert enriches low-density events with command title and purpose" {
    init_empty_memory_db
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/context"
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/scripts/memory_db_live_insert.py"

    cat > "$TEST_TMPDIR/context/semantic-map.md" <<'EOF'
| 概念 | aliases | docs |
|------|---------|------|
| Command Context Target | dragon needle | test |
EOF
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  cmd_context_demo:
    title: "Improve live insert dragon needle matching"
    purpose: "Inject dragon needle command context into low density live events"
EOF

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        report \
        --report-path "queue/reports/hayate_report_cmd_context_demo.yaml" \
        --ts "2026-06-02T12:00:00Z" \
        --dot-key "result.summary" \
        --agent "hayate" \
        --parent-cmd "cmd_context_demo" \
        --source-file "queue/reports/hayate_report_cmd_context_demo.yaml"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        cmd_save \
        --cmd-id "cmd_context_demo" \
        --ts "2026-06-02T12:00:01Z" \
        --source-file "queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        cmd_delegate \
        --cmd-id "cmd_context_demo" \
        --ts "2026-06-02T12:00:02Z" \
        --message "cmd_context_demoを配備せよ" \
        --source-file "queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        inbox \
        --message-id "msg_context_demo" \
        --ts "2026-06-02T12:00:03Z" \
        --target-agent "hayate" \
        --from-agent "karo" \
        --content "cmd_context_demo task assigned" \
        --message-type "task_assigned" \
        --source-file "queue/inbox/hayate.yaml"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import json
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
event_ids = [
    "report:hayate_report_cmd_context_demo.yaml:result.summary:2026-06-02T12:00:00Z",
    "cmd_save:cmd_context_demo:2026-06-02T12:00:01Z",
    "cmd_delegate:cmd_context_demo:2026-06-02T12:00:02Z",
    "inbox:msg_context_demo",
]
for event_id in event_ids:
    row = conn.execute("SELECT concepts, summary, detail FROM events WHERE id = ?", (event_id,)).fetchone()
    concepts = json.loads(row[0]) if row else []
    stored_text = f"{row[1]}\n{row[2]}" if row else ""
    junction = conn.execute(
        "SELECT COUNT(*) FROM event_concepts WHERE event_id = ? AND concept_name = 'Command Context Target'",
        (event_id,),
    ).fetchone()[0]
    print(f"{event_id}|{'Command Context Target' in concepts}|{junction}|{'dragon needle' in stored_text}")
PY
)
    [ "${#result[@]}" -eq 4 ]
    for line in "${result[@]}"; do
        [[ "$line" == *"|True|1|False" ]]
    done
}

@test "memory_db_live_insert skips report metadata concepts and uses meaningful report values" {
    init_empty_memory_db
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/context" "$TEST_TMPDIR/queue/reports"
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/scripts/memory_db_live_insert.py"

    cat > "$TEST_TMPDIR/context/semantic-map.md" <<'EOF'
| 概念 | aliases | docs |
|------|---------|------|
| Report Value Target | dragon needle | test |
EOF
    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_report_values.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_report_values
status: completed
result:
  summary: "dragon needle summary value"
EOF

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        report \
        --report-path "queue/reports/hayate_report_cmd_report_values.yaml" \
        --ts "2026-06-02T13:00:00Z" \
        --dot-key "status" \
        --agent "hayate" \
        --parent-cmd "cmd_report_values" \
        --source-file "queue/reports/hayate_report_cmd_report_values.yaml"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        report \
        --report-path "queue/reports/hayate_report_cmd_report_values.yaml" \
        --ts "2026-06-02T13:00:01Z" \
        --dot-key "result.summary" \
        --agent "hayate" \
        --parent-cmd "cmd_report_values" \
        --source-file "queue/reports/hayate_report_cmd_report_values.yaml"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import json
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
for event_id in [
    "report:hayate_report_cmd_report_values.yaml:status:2026-06-02T13:00:00Z",
    "report:hayate_report_cmd_report_values.yaml:result.summary:2026-06-02T13:00:01Z",
]:
    row = conn.execute("SELECT concepts FROM events WHERE id = ?", (event_id,)).fetchone()
    concepts = json.loads(row[0]) if row else []
    junction = conn.execute(
        "SELECT COUNT(*) FROM event_concepts WHERE event_id = ?",
        (event_id,),
    ).fetchone()[0]
    print(f"{event_id}|{concepts}|{junction}")
PY
)
    [ "${#result[@]}" -eq 2 ]
    [[ "${result[0]}" == *"|[]|0" ]]
    [[ "${result[1]}" == *"Report Value Target"* ]]
    [[ "${result[1]}" == *"|1" ]]
}

@test "cmd_3128: memory_db_live_insert extracts event_links from report lesson and gate inserts" {
    init_empty_memory_db
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/reports"
    cp "$PROJECT_ROOT/scripts/memory_db_live_insert.py" "$TEST_TMPDIR/scripts/memory_db_live_insert.py"

    cat > "$TEST_TMPDIR/queue/reports/hayate_report_cmd_links.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_links
lesson_candidate:
  origin: "[[cmd_links]] -> [[因果層空白]] -> [[event_links_1.2%]]"
EOF

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        report \
        --report-path "queue/reports/hayate_report_cmd_links.yaml" \
        --ts "2026-06-02T14:12:00Z" \
        --dot-key "lesson_candidate.origin" \
        --agent "hayate" \
        --parent-cmd "cmd_links" \
        --source-file "queue/reports/hayate_report_cmd_links.yaml"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        lesson \
        --lesson-id "L1234" \
        --title "event links live insert" \
        --detail "origin: [[cmd_links]] -> [[軍師断裂2]] -> [[因果層空白]]" \
        --source-cmd "cmd_links" \
        --project "infra" \
        --ts "2026-06-02T14:12:01Z" \
        --source-file "projects/infra/lessons_karo.yaml"
    [ "$status" -eq 0 ]

    run python3 "$TEST_TMPDIR/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        gate \
        --gate-name "gate_report_format" \
        --result "PASS" \
        --cmd-id "cmd_links" \
        --detail "[[event_links_1.2%]] linked from live gate insert" \
        --ts "2026-06-02T14:12:02Z" \
        --source-file "scripts/gates/gate_report_format.sh"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - "$TEST_TMPDIR/data/memory.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
expected = {
    "report:hayate_report_cmd_links.yaml:lesson_candidate.origin:2026-06-02T14:12:00Z": {
        "cmd_links",
        "因果層空白",
        "event_links_1.2%",
    },
    "lesson:L1234": {
        "cmd_links",
        "軍師断裂2",
        "因果層空白",
    },
    "gate:gate_report_format:cmd_links:2026-06-02T14:12:02Z": {
        "event_links_1.2%",
    },
}
cols = [row[1] for row in conn.execute("PRAGMA table_info(event_links)")]
print(",".join(cols))
for event_id, targets in expected.items():
    rows = {
        row[0]
        for row in conn.execute(
            "SELECT target_concept FROM event_links WHERE source_event_id = ? AND link_type = 'obsidian'",
            (event_id,),
        )
    }
    print(f"{event_id}|{targets.issubset(rows)}|{len(rows)}")
PY
)
    [ "${result[0]}" = "source_event_id,target_concept,link_type" ]
    [ "${#result[@]}" -eq 4 ]
    for line in "${result[@]:1}"; do
        [[ "$line" == *"|True|"* ]]
    done
}
