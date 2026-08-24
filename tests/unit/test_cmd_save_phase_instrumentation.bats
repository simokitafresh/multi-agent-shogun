#!/usr/bin/env bats
# test_necessity: cmd_save.sh実行時、主要内部フェーズ(checks_pre_session/session_state/checks_main)の
# wall_msと非加算子区間checks_main.*がdefense_overhead_writer.sh経由で台帳へ出力される不変量、
# preflightの段別ログが恒久ログへ同期追記される不変量、および計装がPASS/BLOCKの判定結果(exit code)
# を変化させない不変量を守るcontract test(cmd_4169/cmd_4399)。

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
    export TEST_LEDGER="$TEST_TMPDIR/defense_overhead.jsonl"
    export TEST_PHASE_LOG="$TEST_TMPDIR/cmd_save_preflight_phases.log"
    mkdir -p "$TEST_ARCHIVE_DIR" "$TEST_Q11_RESEARCH_DIR" "$(dirname "$TEST_GUNSHI_LOG")" "$(dirname "$TEST_MEMORY_DB")"
    printf '%s\n' '[]' > "$TEST_INSIGHTS"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

run_cmd_save_instrumented() {
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
        CMD_SAVE_MEMORY_DB_QUERY_SCRIPT="$TEST_TMPDIR/no_memory_db_query.sh" \
        SHOGUN_MEMORY_DB="$TEST_MEMORY_DB" \
        SHOGUN_MEMORY_DB_QUERY_DISABLE_CACHE=1 \
        CMD_SAVE_SYNC_QUALITY_LOG=1 \
        CMD_SAVE_DISABLE_QUALITY_LOG=1 \
        MEMORY_DB_LIVE_INSERT="$TEST_TMPDIR/no_memory_db_live_insert.py" \
        DEFENSE_OVERHEAD_LEDGER="$TEST_LEDGER" \
        CMD_SAVE_PHASE_LOG="$TEST_PHASE_LOG" \
        bash "$SAVE_SCRIPT" "$1"
}

run_cmd_save_preflight_instrumented() {
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
        CMD_SAVE_MEMORY_DB_QUERY_SCRIPT="$TEST_TMPDIR/no_memory_db_query.sh" \
        SHOGUN_MEMORY_DB="$TEST_MEMORY_DB" \
        SHOGUN_MEMORY_DB_QUERY_DISABLE_CACHE=1 \
        CMD_SAVE_SYNC_QUALITY_LOG=1 \
        CMD_SAVE_DISABLE_QUALITY_LOG=1 \
        MEMORY_DB_LIVE_INSERT="$TEST_TMPDIR/no_memory_db_live_insert.py" \
        DEFENSE_OVERHEAD_LEDGER="$TEST_LEDGER" \
        CMD_SAVE_PHASE_LOG="$TEST_PHASE_LOG" \
        bash "$SAVE_SCRIPT" --preflight "$1"
}

wait_for_ledger_check_id() {
    local check_id="$1" tries=0
    while [ "$tries" -lt 100 ]; do
        [ -f "$TEST_LEDGER" ] && grep -Fq "\"check_id\":\"${check_id}\"" "$TEST_LEDGER" && return 0
        sleep 0.05
        tries=$((tries + 1))
    done
    return 1
}

@test "AC1: PASSしたcmdはsource:cmd_saveのフェーズ別wall_msがverdict PASSで台帳へ出力される" {
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_phase_pass:
    id: cmd_phase_pass
    title: "verify — phase instrumentation PASS確認"
    purpose: "cmd_4169の内部フェーズ計装がPASS判定を維持したまま台帳へ出力されることを確認する"
    project: infra
    depends_on: none
    origin: "[[cmd_4169]] [[cmd_save内部フェーズ未計装]]"
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
      q2_learning: "内部フェーズ計装の台帳出力を確認する"
      q3_next_quality: "台帳集計による次高速化cmdの標的確定"
      q4_depth: "shallow"
      q5_verified_source: "tests/unit/test_cmd_save_phase_instrumentation.bats structure_verified"
      q6_not_hiding: "no — 計装行をfixtureで固定し隠さない"
      q7_definition_verified: "yes — defense_overhead.jsonl出力を本テストで固定する"
      q8_why_what: "WHY: source:cmd_saveの内部フェーズ別記録が欠如し支配項が不明 → WHAT: 主要フェーズのwall_msを台帳出力する → WHEN: cmd_save実行時 → WHERE: scripts/cmd_save.sh → WHO: 将軍cmd保存ゲート → HOW: DEFENSE_OVERHEAD_LEDGER overrideで台帳出力を検証する。複利: 正の複利"
      q10_knowledge_boundary: "空間内。根拠: scripts/cmd_save.sh と本テストのみ"
      q11_not_already_done: "未達成。rg -n 'cmd_save_phase_mark' scripts/cmd_save.sh で今回追加対象を確認"
      q_ambiguity: "none"
    assumptions:
      - claim: "cmd_saveの主要内部フェーズがsource:cmd_saveで台帳出力される"
        source: "tests/unit/test_cmd_save_phase_instrumentation.bats"
        trust: "verified"
        verified_at: "2026-07-25"
        detail: "DEFENSE_OVERHEAD_LEDGER override + grepで検証"
YAML

    run_cmd_save_instrumented cmd_phase_pass
    echo "$output" >&2

    [ "$status" -eq 0 ]
    wait_for_ledger_check_id "checks_main"

    run python3 - "$TEST_LEDGER" <<'PY'
import json, sys
rows = [json.loads(x) for x in open(sys.argv[1]) if x.strip()]
cmd_save_rows = [r for r in rows if r["source"] == "cmd_save"]
phases = {r["check_id"] for r in cmd_save_rows}
assert {"checks_pre_session", "session_state", "checks_main"} <= phases, phases
children = [r for r in cmd_save_rows if r["check_id"].startswith("checks_main.")]
expected_children = {
    "checks_main.quality_gate", "checks_main.workspace_state",
    "checks_main.reference_guards", "checks_main.memory_context",
    "checks_main.content_and_ac", "checks_main.parameter_space",
    "checks_main.contracts", "checks_main.final_guards",
}
assert expected_children <= {r["check_id"] for r in children}, children
parent = next(r for r in cmd_save_rows if r["check_id"] == "checks_main")
assert sum(r["wall_ms"] for r in children) <= parent["wall_ms"] + len(children), (parent, children)
print("checks_main_profile", parent["wall_ms"],
      " ".join(f'{r["check_id"]}={r["wall_ms"]}' for r in children))
assert all(r["verdict"] == "PASS" for r in cmd_save_rows), cmd_save_rows
assert all(isinstance(r["wall_ms"], int) and r["wall_ms"] >= 0 for r in cmd_save_rows), cmd_save_rows
assert len({r["event_id"] for r in cmd_save_rows}) == len(cmd_save_rows), cmd_save_rows
PY
    echo "$output" >&2
    [ "$status" -eq 0 ]
}

@test "AC1: BLOCKしたcmdでも判定(exit 1)は不変のままverdict BLOCKで台帳へ出力される" {
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_phase_block:
    id: cmd_phase_block
    title: "verify — phase instrumentation BLOCK確認"
    purpose: "quality_gate未記入BLOCKでも計装が判定ロジックを変えないことを確認する"
    project: infra
    depends_on: none
    origin: "[[cmd_4169]] [[cmd_save内部フェーズ未計装]]"
    task_type: docs
    command: |
      1. quality_gate未記入で保存確認NGになることを確認する
YAML

    run_cmd_save_instrumented cmd_phase_block
    echo "$output" >&2

    [ "$status" -eq 1 ]
    [[ "$output" == *"quality_gate未記入"* ]]
    wait_for_ledger_check_id "session_state"

    run python3 - "$TEST_LEDGER" <<'PY'
import json, sys
rows = [json.loads(x) for x in open(sys.argv[1]) if x.strip()]
# checks_pre_session/session_state/checks_mainは区間計測(cmd_save_phase_mark)で
# 最終確定verdict(BLOCK_COUNT>0=BLOCK)を反映する。q11_semantic等の非同期INFO計測は
# gate判定と無関係な自己計測でありPASS固定のため対象外とする。
checkpoint_rows = [r for r in rows if r["source"] == "cmd_save"
                    and r["check_id"] in {"checks_pre_session", "session_state", "checks_main"}]
assert checkpoint_rows, "no cmd_save checkpoint phase events recorded"
assert all(r["verdict"] == "BLOCK" for r in checkpoint_rows), checkpoint_rows
PY
    [ "$status" -eq 0 ]
}

@test "AC2: preflightは段別wall_msを恒久ログへ同期追記し最長段を集計できる" {
    # test_necessity: preflight 1回の段別実測を後続の短縮cmdが再利用する
    # append-only boundaryへ固定する。JSONLの非同期到着だけでは実行直後の
    # 集計が不安定になるため、専用ログの同期追記を契約化する。
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_phase_preflight:
    id: cmd_phase_preflight
    title: "verify — preflight phase log"
    purpose: "preflightが段別実測を恒久ログへ記録することを確認する"
    project: infra
    depends_on: none
    origin: "[[cmd_4399]] [[cmd_save_preflight_phase_log]]"
    task_type: docs
    command: |
      1. preflightの段別実測を確認する
    acceptance_criteria:
      - id: AC1
        description: "preflightの段別実測を記録する"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "支配段を次cmdの短縮対象へ接続する"
      q3_next_quality: "実測に基づく短縮で上がる"
      q4_depth: "shallow"
      q5_verified_source: "tests/unit/test_cmd_save_phase_instrumentation.bats fixture"
      q6_not_hiding: "no — 計装ログへ全段を残す"
      q7_definition_verified: "yes — 専用phase logの列をテストで固定する"
      q8_why_what: "WHY: preflightの支配段が不明 → WHAT: 段別wall_msを恒久ログへ記録 → WHEN: preflight実行時 → WHERE: scripts/cmd_save.sh → WHO: cmd起票ゲート → HOW: 専用ログをPython集計する。複利: 正の複利"
      q10_knowledge_boundary: "空間内。根拠: scripts/cmd_save.sh と本テスト"
      q11_not_already_done: "既存JSONL計装は確認済み。preflight専用ログの同期追記を追加する"
      q_ambiguity: "none"
    assumptions:
      - claim: "preflight phase logはtab区切り7列である"
        source: "tests/unit/test_cmd_save_phase_instrumentation.bats"
        trust: "verified"
        verified_at: "2026-08-25"
        detail: "専用ログをPythonで構文・集計確認"
YAML

    run_cmd_save_preflight_instrumented cmd_phase_preflight
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [ -s "$TEST_PHASE_LOG" ]

    run python3 - "$TEST_PHASE_LOG" <<'PY'
import sys
rows=[]
for line in open(sys.argv[1], encoding="utf-8"):
    fields=line.rstrip("\n").split("\t")
    assert len(fields) == 7, fields
    timestamp, cmd_id, mode, phase, wall_ms, verdict, run_id = fields
    assert cmd_id == "cmd_phase_preflight" and mode == "preflight", fields
    assert verdict == "PASS" and int(wall_ms) >= 0, fields
    rows.append((phase, int(wall_ms)))
assert len(rows) >= 3, rows
dominant, elapsed = max(rows, key=lambda item: item[1])
total = sum(ms for _, ms in rows)
share = elapsed / total if total else 0
assert dominant and 0 <= share <= 1, (dominant, elapsed, total, share)
print(f"dominant={dominant} elapsed_ms={elapsed} total_ms={total} share={share:.4f}")
PY
    [ "$status" -eq 0 ]
}
