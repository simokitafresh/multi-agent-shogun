#!/usr/bin/env bats
# test_necessity: cmd_save.shはAC/command本文の実行コマンド系トークン(scripts/配下のコマンド名・
# run系方式語)を検知したときのみ記憶DB自動検索を発火し、ヒットknowledgeを判定出力へ注入する
# (cmd_4164)。トークンなしcmdでは非発火であることも同時に固定する。
# test_cmd_save_memory_db_token_gate.bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SAVE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export TEST_QUEUE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export TEST_ARCHIVE_DIR="$TEST_TMPDIR/archive"
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
    export TEST_LOCK="$TEST_TMPDIR/shogun_to_karo.lock"
    export TEST_LAST_CMD="$TEST_TMPDIR/cmd_save_last_cmd.txt"
    export TEST_SHOGUN_LESSONS="$TEST_TMPDIR/lessons_shogun.yaml"
    export TEST_PREFLIGHT_AUTOLEARN="$TEST_TMPDIR/preflight_autolearn.txt"
    export TEST_LORD_CONVERSATION="$TEST_TMPDIR/lord_conversation.jsonl"
    export TEST_CMD_CHRONICLE="$TEST_TMPDIR/cmd-chronicle.md"
    export TEST_BULLETIN="$TEST_TMPDIR/bulletin_board.yaml"
    export TEST_GUNSHI_LOG="$TEST_TMPDIR/logs/gunshi_review_log.yaml"
    export TEST_MEMORY_DB="$TEST_TMPDIR/data/memory.db"
    export TEST_Q11_RESEARCH_DIR="$TEST_TMPDIR/docs/research"
    export TEST_INSIGHTS="$TEST_TMPDIR/insights.yaml"
    mkdir -p "$TEST_ARCHIVE_DIR" "$TEST_Q11_RESEARCH_DIR" "$(dirname "$TEST_GUNSHI_LOG")" "$(dirname "$TEST_MEMORY_DB")"
    printf '%s\n' '[]' > "$TEST_INSIGHTS"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

create_memory_db_fixture_with_hit() {
    python3 - "$TEST_MEMORY_DB" <<'PY'
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
    importance TEXT,
    raw_content TEXT
);
CREATE VIRTUAL TABLE events_fts USING fts5(
    summary,
    detail,
    content='events',
    content_rowid='rowid'
);
""")
conn.execute(
    "INSERT INTO events (id, ts, event_type, agent, target, direction, summary, detail, cmd_id, importance)"
    " VALUES ('evt_run_tests_hit', '2026-07-20T10:00:00', 'knowledge', 'karo', '', 'save',"
    " 'run_tests.sh task modeの既知の落とし穴', 'run_tests.sh task modeはselected testsが欠落するとFAILする', 'cmd_9001', 'high')"
)
rowid = conn.execute("SELECT rowid FROM events WHERE id='evt_run_tests_hit'").fetchone()[0]
conn.execute(
    "INSERT INTO events_fts(rowid, summary, detail) VALUES (?, ?, ?)",
    (rowid, 'run_tests.sh task modeの既知の落とし穴', 'run_tests.sh task modeはselected testsが欠落するとFAILする'),
)
conn.commit()
PY
}

run_cmd_save_token_gate() {
    run env \
        TMPDIR="$TEST_TMPDIR" \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_SAVE_LOCK_FILE="$TEST_LOCK" \
        CMD_SAVE_LAST_CMD_FILE="$TEST_LAST_CMD" \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_SHOGUN_LESSONS" \
        CMD_SAVE_PREFLIGHT_AUTOLEARN_FILE="$TEST_PREFLIGHT_AUTOLEARN" \
        CMD_SAVE_LORD_CONVERSATION_FILE="$TEST_LORD_CONVERSATION" \
        CMD_SAVE_CMD_CHRONICLE_FILE="$TEST_CMD_CHRONICLE" \
        CMD_SAVE_BULLETIN_FILE="$TEST_BULLETIN" \
        CMD_SAVE_GUNSHI_REVIEW_LOG_FILE="$TEST_GUNSHI_LOG" \
        CMD_SAVE_INSIGHTS_FILE="$TEST_INSIGHTS" \
        CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/no_semantic_search.sh" \
        CMD_SAVE_Q11_RESEARCH_DIR="$TEST_Q11_RESEARCH_DIR" \
        CMD_SAVE_MEMORY_DB_QUERY_SCRIPT="$PROJECT_ROOT/scripts/memory_db_query.sh" \
        SHOGUN_MEMORY_DB="$TEST_MEMORY_DB" \
        SHOGUN_MEMORY_DB_QUERY_DISABLE_CACHE=1 \
        CMD_SAVE_SYNC_QUALITY_LOG=1 \
        CMD_SAVE_DISABLE_QUALITY_LOG=1 \
        MEMORY_DB_LIVE_INSERT="$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        bash "$SAVE_SCRIPT" "$1"
}

@test "AC1: scripts/配下の実行コマンド名トークンを含むcmdでmemory-db自動検索が発火する" {
    create_memory_db_fixture_with_hit
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_token_present:
    id: cmd_token_present
    title: "verify — memory-db token gate発火確認"
    purpose: "cmd_4164の記憶DB自動検索発火を確認する"
    project: infra
    depends_on: none
    origin: "[[cmd_4164]] [[memory_db_token_gate]]"
    task_type: impl
    command: |
      1. bash scripts/run_tests.sh task queue/tasks/saizo.yaml でFAIL0を確認する
      2. 結果をreportへ記録する
    acceptance_criteria:
      - id: AC1
        description: "run_tests.sh実行結果を確認する"
      - id: AC2
        description: "報告へ記録する"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "記憶DB自動検索の発火を確認する"
      q3_next_quality: "起票分岐点の三層記憶接続"
      q4_depth: "shallow"
      q5_verified_source: "tests/unit/test_cmd_save_memory_db_token_gate.bats structure_verified"
      q6_not_hiding: "no — 検索INFO表示でgate結果を隠さない"
      q7_definition_verified: "yes — memory-db自動検索INFO出力を本テストで固定する"
      q8_why_what: "WHY: 起票時に記憶DB検索が発火しないと過去知見が参照されない → WHAT: run_tests.shトークン検知時の自動検索を検証 → WHEN: cmd_save実行時 → WHERE: scripts/cmd_save.sh → WHO: 将軍cmd保存ゲート → HOW: fixture DBに既知knowledgeを仕込み検索一致を確認する。複利: 正の複利"
      q10_knowledge_boundary: "空間内。根拠: scripts/cmd_save.sh と本テストのみ"
      q11_not_already_done: "未達成。rg -n 'show_memory_db_command_token_matches' scripts/cmd_save.sh で今回追加対象を確認"
      q_ambiguity: "none"
    assumptions:
      - claim: "run_tests.shトークンで記憶DB検索が発火する"
        source: "tests/unit/test_cmd_save_memory_db_token_gate.bats"
        trust: "verified"
        verified_at: "2026-07-24"
        detail: "fixture DBに既知knowledgeを仕込み確認"
YAML

    run_cmd_save_token_gate cmd_token_present
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: memory-db自動検索(方式トークン検知)"* ]]
    [[ "$output" == *"run_tests.sh"* ]]
    [[ "$output" == *"run_tests.sh task modeの既知の落とし穴"* ]]
}

@test "AC1: 実行コマンド系トークンを含まないcmdではmemory-db自動検索が非発火である" {
    create_memory_db_fixture_with_hit
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_token_absent:
    id: cmd_token_absent
    title: "verify — token gate非発火確認"
    purpose: "cmd_4164の記憶DB自動検索が無関係cmdで発火しないことを確認する"
    project: infra
    depends_on: none
    origin: "[[cmd_4164]] [[memory_db_token_gate]]"
    task_type: docs
    command: |
      1. 用語辞書のtypoを1件修正する
      2. 修正箇所をreportへ記録する
    acceptance_criteria:
      - id: AC1
        description: "typo修正を確認する"
      - id: AC2
        description: "報告へ記録する"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "トークンなしcmdでの非発火を確認する"
      q3_next_quality: "誤検索の抑止"
      q4_depth: "shallow"
      q5_verified_source: "tests/unit/test_cmd_save_memory_db_token_gate.bats structure_verified"
      q6_not_hiding: "no — 非発火自体を隠さずテストで固定する"
      q7_definition_verified: "yes — memory-db自動検索INFO出力が出ないことを本テストで固定する"
      q8_why_what: "WHY: トークンなしで検索が発火すると無関係な知識露出とレイテンシが発生する → WHAT: scripts/*.sh|py参照もrun_トークンもないcmdで非発火を検証 → WHEN: cmd_save実行時 → WHERE: scripts/cmd_save.sh → WHO: 将軍cmd保存ゲート → HOW: token非含有cmdでINFO行が出ないことを確認する。複利: 正の複利"
      q10_knowledge_boundary: "空間内。根拠: scripts/cmd_save.sh と本テストのみ"
      q11_not_already_done: "未達成。rg -n 'show_memory_db_command_token_matches' scripts/cmd_save.sh で今回追加対象を確認"
      q_ambiguity: "none"
    assumptions:
      - claim: "実行コマンド系トークンなしでは記憶DB検索が非発火"
        source: "tests/unit/test_cmd_save_memory_db_token_gate.bats"
        trust: "verified"
        verified_at: "2026-07-24"
        detail: "command本文にscripts/*.sh|pyもrun_トークンも含まない"
YAML

    run_cmd_save_token_gate cmd_token_absent
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"INFO: memory-db自動検索(方式トークン検知)"* ]]
}
