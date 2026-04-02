#!/usr/bin/env bats
# test_cmd_save_q5.bats — cmd_save.sh q5=code_readingのみBLOCKテスト (cmd_1692)
#
# AC1: q5にcode_readingのみ(isolated_test/structure_verified/production_verified不在) → BLOCK
# AC2: q5にcode_reading+structure_verified等を含む → BLOCKなし

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    local _qg_start _qg_end
    _qg_start=$(grep -n '# --- Check 3: quality_gate' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$(grep -n '# --- Check 4:' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$((_qg_end - 1))
    eval "check_quality_gate() {
local WARN_COUNT=0
$(sed -n "${_qg_start},${_qg_end}p" "$SRC_SAVE_SCRIPT")
echo \"OK: \${CMD_ID}\"
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
    export CMD_ID="cmd_q5test"
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
}

teardown() { true; }

_make_cmd() {
    local q5_val="$1"
    cat > "$QUEUE_FILE" <<YAML
commands:
  cmd_q5test:
    id: cmd_q5test
    command: "q5テスト用cmd"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "${q5_val}"
YAML
    CMD_BLOCK=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
    CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
    export CMD_ID CMD_BLOCK CMD_BLOCK_NC
}

# ---- AC1: code_readingのみ → BLOCK ----

@test "Q5-T001: q5=code_readingのみ → BLOCK" {
    _make_cmd "code_reading"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"code_readingのみ"* ]]
}

@test "Q5-T002: q5=コード読みのみ → BLOCK" {
    _make_cmd "コード読みで確認した"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "Q5-T003: q5=読んだだけ → BLOCK" {
    _make_cmd "読んだだけ"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
}

# ---- AC2: code_reading + 追加検証 → BLOCKなし ----

@test "Q5-T004: q5=code_reading+structure_verified → BLOCKなし" {
    _make_cmd "code_reading + structure_verified"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK: q5=code_readingのみ"* ]]
}

@test "Q5-T005: q5=code_reading+isolated_test → BLOCKなし" {
    _make_cmd "code_reading + isolated_test実行済み"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK: q5=code_readingのみ"* ]]
}

@test "Q5-T006: q5=code_reading+production_verified → BLOCKなし" {
    _make_cmd "code_reading + production_verified"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK: q5=code_readingのみ"* ]]
}

@test "Q5-T007: q5=code_reading+pipeline_test → BLOCKなし" {
    _make_cmd "code_reading + pipeline_test通過"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK: q5=code_readingのみ"* ]]
}

# ---- 既存動作維持確認 ----

@test "Q5-T008: q5=コード確認(code_readingキーワードなし) → BLOCKなし" {
    _make_cmd "コード確認"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK: q5=code_readingのみ"* ]]
}
