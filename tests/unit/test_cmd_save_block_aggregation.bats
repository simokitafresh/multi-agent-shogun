#!/usr/bin/env bats
# test_cmd_save_block_aggregation.bats — cmd_save.sh が複数BLOCK理由を1回で表示するか

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
    mkdir -p "$TEST_ARCHIVE_DIR" "$TEST_Q11_RESEARCH_DIR" "$(dirname "$TEST_GUNSHI_LOG")"
    printf '%s\n' '[]' > "$TEST_INSIGHTS"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

run_cmd_save() {
    run env \
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
        CMD_SAVE_SYNC_QUALITY_LOG=1 \
        CMD_SAVE_DISABLE_QUALITY_LOG=1 \
        MEMORY_DB_LIVE_INSERT="$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SAVE_SCRIPT" cmd_multi_block
}

run_cmd_save_pass() {
    run env \
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
        CMD_SAVE_FORCE_LORD_CONVERSATION="${CMD_SAVE_FORCE_LORD_CONVERSATION:-0}" \
        SHOGUN_MEMORY_DB="$TEST_MEMORY_DB" \
        CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/no_semantic_search.sh" \
        CMD_SAVE_Q11_RESEARCH_DIR="$TEST_Q11_RESEARCH_DIR" \
        CMD_SAVE_SYNC_QUALITY_LOG=1 \
        MEMORY_DB_LIVE_INSERT="$PROJECT_ROOT/scripts/memory_db_live_insert.py" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SAVE_SCRIPT" cmd_pass
}

create_memory_db_fixture() {
    mkdir -p "$(dirname "$TEST_MEMORY_DB")"
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

@test "AC2: 1回の実行で複数BLOCK理由を一括表示する" {
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_multi_block:
    id: cmd_multi_block
    title: "fix — cmd_save集約テスト"
    project: infra
    command: "複数BLOCK理由を1回で露出させる"
    status: pending
    acceptance_criteria:
      - id: AC1
        description: "集約表示を確認"
      - id: AC2
        description: "追加BLOCKを混在させる"
      - id: AC3
        description: "assumptionsも検証"
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "medium"
      q5_verified_source: "code_reading"
      q8_why_what: "WHY: 「集約表示を壊すな」 → WHAT: 意図的にBLOCKを4種類混在させる → WHEN: cmd_saveのBLOCK集約回帰を検証する時 → WHERE: tests/unit/test_cmd_save_block_aggregation.bats → WHO: 将軍cmd保存ゲートを使う将軍 → HOW: 複数BLOCK理由を1回の出力で検証する。複利: 正の複利"
      q_ambiguity: "none"
    assumptions:
      - source: "nonexistent/path.sh code_reading"
        trust: "verified"
        detail: "存在しないパス"
YAML

    run_cmd_save
    echo "$output" >&2

    [ "$status" -eq 1 ]
    [[ "$(printf '%s\n' "$output" | grep -m1 '^止まるな、修正して再実行せよ$')" == "止まるな、修正して再実行せよ" ]]
    [[ "$(printf '%s\n' "$output" | grep -c '^止まるな、修正して再実行せよ$')" -eq 1 ]]
    [[ "$output" == *"BLOCK: 必須項目 1件 未記入。全て記入してからcmd_save.shを再実行せよ"* ]]
    [[ "$output" == *"未記入: q11_not_already_done"* ]]
    [[ "$output" == *"BLOCK: q5=code_readingのみ。コード読みだけでは前提未検証。isolated_test/structure_verified/production_verifiedのいずれかで実確認せよ"* ]]
    [[ "$output" == *"BLOCK: 消火cmdなのにq9_firefighting_root_cause未記入。真因と再発防止を記載してからcmd_save.shを実行せよ"* ]]
    [[ "$output" == *"保存確認NG: cmd_multi_block"* ]]
}

@test "AC1: PASS時はBLOCKナッジを表示しない" {
    create_memory_db_fixture
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_pass:
    id: cmd_pass
    title: "verify — cmd_save pass output"
    purpose: "cmd_save PASS時の出力静粛性を検証する"
    project: infra
    depends_on: none
    origin: "[[cmd_2902]] [[origin_none_passthrough]]"
    task_type: impl
    command: |
      1. scripts/cmd_save.sh の出力条件を確認する
      2. PASS時に余計なBLOCKナッジが混入しないことを確認する
    acceptance_criteria:
      - id: AC1
        description: "PASS時にBLOCKナッジが出ない"
      - id: AC2
        description: "保存確認OKが表示される"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "既存のBLOCK出力経路にだけ手を入れる"
      q3_next_quality: "PASS経路の静粛性を維持する"
      q4_depth: "shallow"
      q5_verified_source: "tests/unit/test_cmd_save_block_aggregation.bats structure_verified + git log d05873c0 causal verification gate導入理由確認"
      q6_not_hiding: "no — BLOCK専用ナッジの出し分け確認であり、根因を隠す変更ではない"
      q7_definition_verified: "yes — PASS=exit 0かつ保存確認OK出力を本テストで固定する"
      q8_why_what: "WHY: PASS経路に余計なノイズを混ぜない → WHAT: BLOCK専用ナッジの非表示を確認する → WHEN: cmd_saveのPASS経路を検証する時 → WHERE: tests/unit/test_cmd_save_block_aggregation.bats → WHO: 将軍cmd保存ゲートを使う将軍 → HOW: exit 0と保存確認OKを固定し、この選択を10回繰り返しても正の複利になる形にする"
      q10_knowledge_boundary: "空間内。根拠: cmd_save.sh の既存出力経路と本Batsのみを使う"
      q11_not_already_done: "未達成。これからPASS経路の出力を確認する"
      q_ambiguity: "none"
    assumptions:
      - claim: "2026-04-25 テスト用QUEUE_FILEだけを参照する"
        source: "tests/unit/test_cmd_save_block_aggregation.bats"
        trust: "verified"
        verified_at: "2026-04-25"
        detail: "CMD_SAVE_QUEUE_FILEで差し替える"
YAML

    run_cmd_save_pass
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_pass"* ]]
    [[ "$output" != *"止まるな、修正して再実行せよ"* ]]
}

@test "AC2c: BLOCK SUMMARY shows recent pattern unique cmd counts" {
    cat > "$TEST_QUALITY_LOG" <<'YAML'
entries:
  - cmd_id: cmd_a
    gate_result: BLOCK
    source: cmd_save
    notes: command_files_modified_mismatch|detail=a
  - cmd_id: cmd_a
    gate_result: BLOCK
    source: cmd_save
    notes: command_files_modified_mismatch|detail=retry
  - cmd_id: cmd_b
    gate_result: BLOCK
    source: cmd_save
    notes: missing_q11
YAML
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_multi_block:
    id: cmd_multi_block
    title: "fix — cmd_save集約テスト"
    project: infra
    command: "複数BLOCK理由を1回で露出させる"
    status: pending
    acceptance_criteria:
      - id: AC1
        description: "集約表示を確認"
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "medium"
      q5_verified_source: "code_reading"
      q8_why_what: "WHY: BLOCK集計を固定する → WHAT: 意図的にBLOCKさせる → WHEN: cmd_saveのBLOCK集計回帰を検証する時 → WHERE: tests/unit/test_cmd_save_block_aggregation.bats → WHO: 将軍cmd保存ゲートを使う将軍 → HOW: 直近10件のnotes先頭を分類し、unique cmd数を表示する。複利: 正の複利"
      q_ambiguity: "none"
YAML

    run_cmd_save
    echo "$output" >&2

    [ "$status" -eq 1 ]
    [[ "$output" == *"★ BLOCK SUMMARY: recent 10 pattern unique cmd counts"* ]]
    [[ "$output" == *"command_files_modified_mismatch: unique_cmds=1 cmd_ids=cmd_a"* ]]
    [[ "$output" == *"missing_q11: unique_cmds=1 cmd_ids=cmd_b"* ]]
}

@test "AC3: extract_command_files keeps SG-PRE25 readonly heuristics" {
    run bash "$PROJECT_ROOT/scripts/lib/extract_command_files.sh" \
        --repo "$PROJECT_ROOT" \
        --command-text "scripts/semantic_search.shを呼び出し、チェックを追加。scripts/cmd_save.shを修正する"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_save.sh"* ]]
    [[ "$output" == *"READONLY_EXCLUDED: semantic_search.sh"* ]]
    [[ "$output" != *"WARN: semantic_search.sh"* ]]
}

@test "AC2b: 殿発言検索はtarget=karoのinboundを除外する" {
    create_memory_db_fixture
    cat > "$TEST_LORD_CONVERSATION" <<'JSONL'
{"ts":"2026-05-23T03:00:00","direction":"inbound","target":"karo","summary":"target filter regression uniquehayate karo-only","detail":"cmd_save target filtering"}
{"ts":"2026-05-23T03:01:00","direction":"inbound","target":"shogun","summary":"target filter regression uniquehayate shogun-visible","detail":"cmd_save target filtering"}
{"ts":"2026-05-23T03:02:00","direction":"inbound","summary":"target filter regression uniquehayate legacy-visible","detail":"cmd_save target filtering"}
JSONL
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_pass:
    id: cmd_pass
    title: "target filter regression uniquehayate"
    purpose: "cmd_save target filtering regression"
    project: infra
    depends_on: none
    origin: "[[cmd_3017]] [[lord_conversation_target_filter]]"
    task_type: impl
    command: |
      1. scripts/cmd_save.sh の殿発言検索target条件を確認する
      2. target=karoのinboundが検索結果に出ないことを確認する
    acceptance_criteria:
      - id: AC1
        description: "target条件が存在する"
      - id: AC2
        description: "target=karoのinboundが検索結果に含まれない"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "殿発言検索の宛先スコープをテストで固定する"
      q3_next_quality: "将軍cmd設計時に家老・軍師宛の発言を混入させない"
      q4_depth: "shallow"
      q5_verified_source: "tests/unit/test_cmd_save_block_aggregation.bats isolated_test + git log d05873c0 causal verification gate導入理由確認"
      q6_not_hiding: "no — 対象外targetの除外であり、対象内の殿発言検索は維持する"
      q7_definition_verified: "yes — target=karo除外とtarget=shogun/未設定許可を本テストで固定する"
      q8_why_what: "WHY: 家老宛発言が将軍cmd設計に混入する → WHAT: targetフィルタをcmd_saveの殿発言検索へ追加する → WHEN: cmd_save実行時 → WHERE: scripts/cmd_save.sh → WHO: 将軍cmd保存ゲート → HOW: target=karoのJSONL fixtureをフル実行で除外検証する。複利: 正の複利"
      q10_knowledge_boundary: "空間内。根拠: scripts/cmd_save.sh と tests/unit/test_cmd_save_block_aggregation.bats のみ"
      q11_not_already_done: "未達成。cmd_3008/3009の同構造をcmd_save.shへ横展開する"
      q12_lord_30min_cost: "no — 自動回帰テストで宛先混入を防ぎ、殿の確認コストを増やさない"
      q_ambiguity: "none"
    assumptions:
      - claim: "2026-05-23 cmd_save.sh のshow_lord_conversation_matchesはdirection=inboundを検索対象にする"
        source: "scripts/cmd_save.sh"
        trust: "verified"
        verified_at: "2026-05-23"
        detail: "target条件の回帰テストfixtureで検証する"
YAML

    CMD_SAVE_FORCE_LORD_CONVERSATION=1 run_cmd_save_pass
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_pass"* ]]
    [[ "$output" == *"shogun-visible"* ]]
    [[ "$output" == *"legacy-visible"* ]]
    [[ "$output" != *"karo-only"* ]]
}

@test "AC1b: PASS時にcmd_save eventを記憶DBへINSERTする" {
    create_memory_db_fixture
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_pass:
    id: cmd_pass
    title: "verify — cmd_save searchable insert"
    purpose: "cmd_save PASS時に記憶DBへ投入される"
    project: infra
    depends_on: none
    origin: "[[cmd_2986]] [[cmd_save_insert]]"
    task_type: impl
    command: |
      1. scripts/cmd_save.sh のPASS経路からmemory_db_live_insert.pyを呼ぶ
      2. events.event_type=cmd_saveを確認する
    acceptance_criteria:
      - id: AC1
        description: "cmd_save eventがINSERTされる"
      - id: AC2
        description: "FTS検索できる"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "cmd_save成功イベントを検索可能にする"
      q3_next_quality: "将軍判断のDB検索性が上がる"
      q4_depth: "shallow"
      q5_verified_source: "tests/unit/test_cmd_save_block_aggregation.bats structure_verified + git log d05873c0 causal verification gate導入理由確認"
      q6_not_hiding: "no — 成功後の非破壊INSERTでありgate結果を隠さない"
      q7_definition_verified: "yes — events.event_type=cmd_save と FTS hit を本テストで固定する"
      q8_why_what: "WHY: cmd起票を記憶DBへ入れる必要がある → WHAT: cmd_save PASS後INSERTを検証 → WHEN: cmd_save成功時 → WHERE: scripts/cmd_save.sh → WHO: 将軍cmd保存ゲート → HOW: SQLite fixtureでeventとFTSを確認する。複利: 正の複利"
      q10_knowledge_boundary: "空間内。根拠: scripts/cmd_save.sh と tests/unit/test_cmd_save_block_aggregation.bats のみ"
      q11_not_already_done: "未達成。rg -n 'event_type.*cmd_save|cmd_save:' scripts/memory_db_live_insert.py scripts/cmd_save.sh で今回追加対象を確認"
      q_ambiguity: "none"
    assumptions:
      - claim: "2026-05-22 テスト用DBだけへINSERTする"
        source: "tests/unit/test_cmd_save_block_aggregation.bats"
        trust: "verified"
        verified_at: "2026-05-22"
        detail: "SHOGUN_MEMORY_DBで差し替える"
YAML

    run_cmd_save_pass
    echo "$output" >&2

    [ "$status" -eq 0 ]
    readarray -t result < <(python3 - "$TEST_MEMORY_DB" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "SELECT event_type, agent, direction, cmd_id, importance FROM events WHERE event_type='cmd_save'"
).fetchone()
fts_count = conn.execute(
    """
    SELECT COUNT(*)
    FROM events_fts
    JOIN events AS e ON e.rowid = events_fts.rowid
    WHERE events_fts MATCH 'searchable'
      AND e.event_type = 'cmd_save'
    """
).fetchone()[0]
print("|".join(row))
print(fts_count)
PY
)
    [ "${result[0]}" = "cmd_save|shogun|save|cmd_pass|high" ]
    [ "${result[1]}" = "1" ]
}

@test "AC3: PASS時に参照されたaction_required掲示板へactioned_byを自動記録する" {
    cat > "$TEST_BULLETIN" <<'YAML'
entries:
- id: 'blt_action_trace'
  content: |-
    CMD起票要請: actioned_by更新テスト
  posted_by: 'karo'
  posted_at: '2026-05-15T11:00:00'
  requires_confirmation: false
  action_type: 'action_required'
  actioned_by: ''
  confirmed_by: []
  status: 'open'
YAML

    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_pass:
    id: cmd_pass
    title: "verify — bulletin actioned_by"
    purpose: "blt_action_trace に対応するcmd保存時にactioned_byが自動更新される"
    project: infra
    depends_on: none
    origin: "[[cmd_2902]] [[causal_edge_zero]]"
    task_type: impl
    command: |
      blt_action_trace に対応するcmdを起票し、cmd_save PASS時に掲示板のactioned_byを更新する
    acceptance_criteria:
      - id: AC1
        description: "blt_action_trace に対応するcmdを起票する"
      - id: AC2
        description: "blt_action_trace のactioned_byがcmd_passになる"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "通知からcmd起票までを追跡可能にする"
      q3_next_quality: "action_required掲示板の未対応を自動で閉じる"
      q4_depth: "shallow"
      q5_verified_source: "tests/unit/test_cmd_save_block_aggregation.bats isolated_test"
      q6_not_hiding: "no — 対応cmdを記録するだけで未対応を隠さない"
      q7_definition_verified: "yes — actioned_byは対応cmd_id"
      q8_why_what: "WHY: blt_action_trace のような昇格通知がfire-and-forgetになる → WHAT: cmd_save PASS時にactioned_byを更新する → WHEN: 対応cmdが起票される時 → WHERE: scripts/cmd_save.sh → WHO: 将軍cmd保存ゲートを使う将軍 → HOW: cmd本文のblt IDを掲示板へ照合する。複利: 対応追跡が自動で閉じる"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_block_aggregation.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。actioned_by自動更新は本テストで初確認"
      q_ambiguity: "none"
    assumptions:
      - claim: "2026-05-15 rg 'blt_action_trace' tests/unit/test_cmd_save_block_aggregation.bats → 1件"
        source: "tests/unit/test_cmd_save_block_aggregation.bats"
        trust: "verified"
        verified_at: "2026-05-15"
YAML

    run_cmd_save_pass
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"bulletin actioned_by更新: blt_action_trace → cmd_pass"* ]]
    run grep -n "actioned_by: 'cmd_pass'" "$TEST_BULLETIN"
    [ "$status" -eq 0 ]
}
