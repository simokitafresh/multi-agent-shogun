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

@test "memory_db_knowledge_write inserts knowledge directly without communication side effects" {
    init_memory_db

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

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        report \
        --report-path "queue/reports/hayate_report_cmd_3116.yaml" \
        --ts "2026-06-02T09:31:00Z" \
        --dot-key "report_field_set.result.summary" \
        --agent "hayate" \
        --parent-cmd "cmd_3116" \
        --source-file "queue/reports/hayate_report_cmd_3116.yaml"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
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

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        --db-path "$TEST_TMPDIR/data/memory.db" \
        gate \
        --gate-name "gate_report_format" \
        --result "PASS" \
        --cmd-id "cmd_3116" \
        --detail "report YAML quality_gate framework PASS" \
        --ts "2026-06-02T09:31:02Z" \
        --source-file "scripts/gates/gate_report_format.sh"
    [ "$status" -eq 0 ]

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
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

    run python3 "$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
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
