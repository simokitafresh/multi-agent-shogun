#!/usr/bin/env bats
# test_cmd_save_diagnosis_quality.bats — cmd_2159: diagnosis質検査 + WARN累計昇格
# AC1: 低品質diagnosis(「BLOCK理由:」「対策:」2部構成なし)で再BLOCK
# AC2: 同一WARNパターンが3回以上でBLOCK昇格

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
    export TEST_PREFLIGHT_AUTOLEARN="$TEST_TMPDIR/preflight_autolearn.txt"
    mkdir -p "$TEST_ARCHIVE_DIR"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# --- ヘルパー ---

write_diag_cmd() {
    local diagnosis="${1:-}"
    local diag_yaml=""
    if [[ -n "$diagnosis" ]]; then
        diag_yaml="      diagnosis: \"${diagnosis}\""
    fi
    cat > "$TEST_QUEUE" <<YAML
commands:
  cmd_diagqtest:
    id: cmd_diagqtest
    title: "infra — diagnosis質検査テスト"
    project: infra
    depends_on: none
    command: "テスト用cmd"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no — diagnosis質検査であり表面的対処ではない"
      q7_definition_verified: "yes — diagnosisは「BLOCK理由:」「対策:」の2部構成を必須とする"
      q8_why_what: "WHY: 殿指摘「diagnosis質検査を実装せよ」 → WHAT: Check 3.5追加。正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_diagnosis_quality.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。fixture範囲でdiagnosis質検査の動作を確認"
      q_ambiguity: "none"
${diag_yaml}
    assumptions:
      - claim: "2026-04-24時点でdiagnosis質検査の動作を確認済み"
        source: "tests/unit/test_cmd_save_diagnosis_quality.bats"
        trust: "verified"
YAML
}

run_diag_save() {
    run env \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_SAVE_PREFLIGHT_AUTOLEARN_FILE="$TEST_PREFLIGHT_AUTOLEARN" \
        CMD_SAVE_LAST_CMD_FILE="$TEST_TMPDIR/last_cmd.txt" \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_TMPDIR/lessons_shogun.yaml" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SAVE_SCRIPT" cmd_diagqtest
}

# WARN累計テスト用: q8に複利の問いが欠落したcmd（毎回WARNを出す）
write_warn_cmd() {
    cat > "$TEST_QUEUE" <<YAML
commands:
  cmd_warntest:
    id: cmd_warntest
    title: "infra — WARN累計テスト"
    project: infra
    depends_on: none
    command: "テスト用cmd"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no — WARN累計挙動の確認であり問題の隠蔽ではない"
      q7_definition_verified: "yes — q8に複利文言がないとWARNになることを確認"
      q8_why_what: "WHY: 殿指摘「WARN累計昇格を実装せよ」 → WHAT: WARN累計チェック追加"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_diagnosis_quality.bats のWARN累計fixture範囲のみ使用"
      q11_not_already_done: "未達成。fixture範囲でWARN累計の動作を確認"
      q_ambiguity: "none"
    environment_change: "type=gate; file=tests/unit/test_cmd_save_diagnosis_quality.bats; pattern=warn_seed_log"
    assumptions:
      - claim: "2026-04-24時点でWARN累計の動作を確認済み"
        source: "tests/unit/test_cmd_save_diagnosis_quality.bats"
        trust: "verified"
YAML
# q8に「複利」が含まれないため毎回q8_複利の問いWARNが出る
}

warn_seed_log() {
    local count="${1:-1}"
    {
        echo "entries:"
        local i
        for ((i = 1; i <= count; i++)); do
            cat <<'YAML'
  - cmd_id: "cmd_warntest"
    ac_count: 0
    gate_result: "WARN"
    karo_rework: "no"
    gunshi_verdict: "unknown"
    ninja_blockers: 0
    supplementary_cmds: 0
    source: "cmd_save_warn"
    timestamp: "2026-04-24T00:00:00Z"
    notes: "q8_複利の問い|check=quality_gate_q8_compound_question"
YAML
        done
    } > "$TEST_QUALITY_LOG"
}

run_warn_save() {
    run env \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_SAVE_PREFLIGHT_AUTOLEARN_FILE="$TEST_PREFLIGHT_AUTOLEARN" \
        CMD_SAVE_LAST_CMD_FILE="$TEST_TMPDIR/last_cmd.txt" \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_TMPDIR/lessons_shogun.yaml" \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SAVE_SCRIPT" cmd_warntest
}

# --- AC1: 低品質diagnosis再BLOCK ---

@test "AC1-1: diagnosisなしはPASS(通常のBLOCKあり→通常ブロック)" {
    write_diag_cmd ""
    run_diag_save
    echo "$output" >&2

    # diagnosis未記入自体ではBLOCKされない。通常WARNの有無は別要因に依存する。
    [[ "$output" != *"diagnosisの形式不正"* ]]
    [[ "$output" != *"2部構成"* ]]
}

@test "AC1-2: diagnosisに「BLOCK理由:」「対策:」両方あればPASS" {
    write_diag_cmd "BLOCK理由: q11が未記入だった 対策: q11に確認内容を追記"
    run_diag_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
}

@test "AC1-3: diagnosisに「BLOCK理由:」がないとBLOCK" {
    write_diag_cmd "単なるメモ。対策: q11を記入した"
    run_diag_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"diagnosisの形式不正"* ]]
    [[ "$output" == *"2部構成"* ]]
}

@test "AC1-4: diagnosisに「対策:」がないとBLOCK" {
    write_diag_cmd "BLOCK理由: q11が未記入だった。次回は気をつける"
    run_diag_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"diagnosisの形式不正"* ]]
}

# --- AC2: WARN累計昇格 ---

@test "AC2-1: 同一WARNが1回目はWARNのまま(BLOCKなし)" {
    write_warn_cmd
    run_warn_save
    echo "$output" >&2

    # q8_複利の問いWARNが出るが1回目(過去0件)はBLOCKなし
    [ "$status" -ne 0 ]   # WARNがあるのでNG
    [[ "$output" != *"WARN累計昇格"* ]]
    [[ "$output" == *"WARN: q8に複利の問いがありません"* ]]
}

@test "AC2-2: 同一WARNが2回目でBLOCK昇格(閾値1)" {
    write_warn_cmd
    # 1回目実行済み相当のWARN履歴を直接fixture化する。
    warn_seed_log 1

    # 2回目実行 — 過去1件あるのでBLOCK昇格
    write_warn_cmd
    run_warn_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"WARN累計昇格"* ]]
    [ -f "$TEST_PREFLIGHT_AUTOLEARN" ]
    [[ "$(cat "$TEST_PREFLIGHT_AUTOLEARN")" == *"check=quality_gate_q8_compound_question"* ]]
    [[ "$(cat "$TEST_PREFLIGHT_AUTOLEARN")" == *"count=1"* ]]
}

@test "AC2-3: 同一WARNが3回目でBLOCK昇格" {
    # 1回目・2回目実行済み相当のWARN履歴を直接fixture化する。
    write_warn_cmd
    warn_seed_log 2

    # 3回目: BLOCK昇格
    write_warn_cmd
    run_warn_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"WARN累計昇格"* ]]
    [[ "$output" == *"q8_複利の問い"* ]]
    [[ "$output" == *"BLOCK"* ]]
}
