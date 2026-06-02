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
