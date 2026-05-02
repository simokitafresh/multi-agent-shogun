#!/usr/bin/env bats
# test_cmd_save_diagnose.bats — cmd_save.sh Diagnose MANDATORY / Session State / DIVERGENT

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    export QUALITY_LOG_SCRIPT="$PROJECT_ROOT/scripts/cmd_quality_log.sh"
    [ -f "$SAVE_SCRIPT" ] || return 1
    [ -f "$QUALITY_LOG_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export TEST_QUEUE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export TEST_ARCHIVE_DIR="$TEST_TMPDIR/archive"
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
    mkdir -p "$TEST_ARCHIVE_DIR"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

write_cmd_yaml() {
    local extra_quality_gate="${1:-}"
    cat > "$TEST_QUEUE" <<YAML
commands:
  cmd_diagtest:
    id: cmd_diagtest
    title: "infra — 診断テスト"
    project: infra
    command: "診断挙動のテスト"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no — diagnose挙動確認であり問題の隠蔽ではない"
      q7_definition_verified: "yes — テスト用定義を確認"
      q8_why_what: "WHY: 「診断強制を入れよ」 → WHAT: 同一cmd 1件をBLOCKさせる。正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_diagnose.bats のfixture範囲のみ使用"
      q_ambiguity: "none"
${extra_quality_gate}
    assumptions:
      - claim: "2026-04-24時点で cmd_save.sh はこのテスト環境で実行可能"
        source: "diagnose test fixture review"
        trust: "verified"
YAML
}

run_cmd_save() {
    run env \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SAVE_SCRIPT" cmd_diagtest
}

@test "AC1: BLOCK時に診断メッセージが表示される" {
    write_cmd_yaml ""

    run_cmd_save
    echo "$output" >&2

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: 必須項目 "* ]]
    [[ "$output" == *"未記入: q11_not_already_done"* ]]
    [[ "$output" == *"★ 診断せよ:"* ]]
    [[ "$output" == *'quality_gateに diagnosis: "根本原因の1行記述"'* ]]
}

@test "AC2: 同一cmd再実行時にPrior attemptsとdiagnosisが表示される" {
    write_cmd_yaml ""
    run_cmd_save
    [ "$status" -eq 1 ]

    write_cmd_yaml '      diagnosis: "q11未記入のまま再実行した。未実装確認をquality_gateへ残していない"
'
    run_cmd_save
    echo "$output" >&2

    [ "$status" -eq 1 ]
    [[ "$output" == *"★ Prior attempts (同じcmd):"* ]]
    [[ "$output" == *"Attempt 1:"* ]]
    [[ "$output" == *"診断: q11未記入のまま再実行した。未実装確認をquality_gateへ残していない"* ]]

    run python3 - <<'PY'
import os
import yaml

with open(os.environ["TEST_QUALITY_LOG"], encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = data.get("entries", [])
matching = [
    e for e in entries
    if e.get("cmd_id") == "cmd_diagtest" and e.get("source") == "cmd_save"
]
assert len(matching) >= 2, matching
assert matching[-1].get("diagnosis", "").startswith("q11未記入"), matching[-1]
PY
    [ "$status" -eq 0 ]
}

@test "AC3: 同じチェックで2回連続BLOCKするとDIVERGENTが表示される" {
    write_cmd_yaml ""
    run_cmd_save
    [ "$status" -eq 1 ]

    write_cmd_yaml '    environment_change: "type=gate; file=scripts/cmd_save.sh; pattern=q11_not_already_done"
'
    run_cmd_save
    echo "$output" >&2

    [ "$status" -eq 1 ]
    [[ "$output" == *"★ DIVERGENT: 同じチェック(必須項目 "* ]]
}
