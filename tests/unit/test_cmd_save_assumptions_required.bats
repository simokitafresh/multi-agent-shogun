#!/usr/bin/env bats
# test_cmd_save_assumptions_required.bats — Check 3: assumptions全cmd必須化
# AC1: cmd_save.shのassumptions必須チェック閾値をAC≥3→全cmdに変更
# AC2: assumptions未記入の任意cmdでBLOCKされることを確認

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    # helper関数を抽出
    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_block_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^abort_if_block_immediate()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar load_cmd_block load_cmd_block_cache cmd_block_has_field cmd_block_get_field record_block_reason abort_if_block_immediate

    # check_quality_gate: Check 3インラインセクション(質問ゲートブロック)を関数化 + 成功時OK出力
    local _qg_start _qg_end
    _qg_start=$(grep -n '# --- Check 3: quality_gate' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$(grep -n '# --- Check 4:' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$((_qg_end - 1))
    eval "check_quality_gate() {
local WARN_COUNT=0
$(sed -n "${_qg_start},${_qg_end}p" "$SRC_SAVE_SCRIPT")
if [[ \"\${BLOCK_COUNT:-0}\" -gt 0 ]]; then
    return 1
fi
echo \"保存確認OK: \${CMD_ID}\"
}"
    export -f check_quality_gate

    export TEST_SHARED_TMP
    TEST_SHARED_TMP="$(mktemp -d)"
    mkdir -p "${TEST_SHARED_TMP}/queue/archive/cmds"
    export QUEUE_FILE="${TEST_SHARED_TMP}/queue/shogun_to_karo.yaml"
}

teardown_file() {
    rm -rf "$TEST_SHARED_TMP"
}

setup() {
    export CMD_ID="cmd_assump_test"
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_LOADED=0
    export CMD_BLOCK_FOUND=0
    export CMD_BLOCK_CACHE_LOADED=0
    export CMD_SAVE_ACCUMULATE_BLOCKS=0
    export BLOCK_COUNT=0
    declare -ga BLOCK_REASONS=()
    declare -gA CMD_BLOCK_CACHE=()
    export QUEUE_FILE="${TEST_SHARED_TMP}/queue/shogun_to_karo_assump_${BATS_TEST_NUMBER}.yaml"
}

teardown() { true; }

create_queue_file() {
    cat > "$QUEUE_FILE"
}

# --- AC2: assumptions未記入の任意cmdでBLOCK ---

@test "AC2: AC数1のcmdでassumptions未記入→BLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_assump_test:
    id: cmd_assump_test
    command: "AC1個のcmdでassumptions必須テスト"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
      q8_why_what: "WHY: assumptions必須化確認 → WHAT: AC1個cmdでBLOCKを確認"
      q11_not_already_done: "未達成。AC1個でのassumptions必須化ケースを新規作成"
YAML

    CMD_ID="cmd_assump_test"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"assumptions"* ]]
}

@test "AC2: AC数2のcmdでassumptions未記入→BLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_assump_test:
    id: cmd_assump_test
    command: "AC2個のcmdでassumptions必須テスト"
    status: pending
    acceptance_criteria:
      - description: "AC1: 処理1実装"
      - description: "AC2: 処理2実装"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
      q8_why_what: "WHY: assumptions必須化確認 → WHAT: AC2個cmdでBLOCKを確認"
      q11_not_already_done: "未達成。AC2個でのassumptions必須化ケースを新規作成"
YAML

    CMD_ID="cmd_assump_test"; export CMD_ID
    run check_quality_gate
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"assumptions"* ]]
}

# AC2補はtest_cmd_save.batsのcmd_9999テストで代替証明済み（assumptions記入済み→PASS）
