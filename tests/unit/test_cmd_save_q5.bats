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

    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/scripts/lib/firefighting_keywords.sh"
    export FIREFIGHTING_PATTERN

    local _qg_start _qg_end
    _qg_start=$(grep -n '# --- Check 3: quality_gate' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$(grep -n '# --- Check 4:' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$((_qg_end - 1))

    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_block_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^abort_if_block_immediate()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar load_cmd_block load_cmd_block_cache cmd_block_has_field cmd_block_get_field record_block_reason abort_if_block_immediate

    eval "check_quality_gate() {
local WARN_COUNT=0
$(sed -n "${_qg_start},${_qg_end}p" "$SRC_SAVE_SCRIPT")
if [[ \"\${BLOCK_COUNT:-0}\" -gt 0 ]]; then
    return 1
fi
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
    export CMD_BLOCK_LOADED=0
    export CMD_BLOCK_FOUND=0
    export CMD_BLOCK_CACHE_LOADED=0
    export CMD_SAVE_ACCUMULATE_BLOCKS=0
    export BLOCK_COUNT=0
    declare -ga BLOCK_REASONS=()
    declare -gA CMD_BLOCK_CACHE=()
    # per-test tmpでCI並列競合回避 (LK477)
    export TEST_PER_TMP="$BATS_TEST_TMPDIR"
    mkdir -p "${TEST_PER_TMP}/queue/archive/cmds"
    export QUEUE_FILE="${TEST_PER_TMP}/queue/shogun_to_karo.yaml"
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
      q8_why_what: "WHY: q5テスト用 → WHAT: q5検証1件実施"
      q11_not_already_done: "未達成。q5検証ケースを新規作成し、既存達成ではないことを確認"
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

# ---- 除外条件: scope_mode=SCOUT OR scout_exempt=true ----

_make_cmd_exempt() {
    local q5_val="$1"
    local extra_field="$2"  # "scope_mode: SCOUT" or "scout_exempt: true"
    cat > "$QUEUE_FILE" <<YAML
commands:
  cmd_q5test:
    id: cmd_q5test
    command: "q5除外条件テスト用cmd"
    status: pending
    ${extra_field}
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "${q5_val}"
      q8_why_what: "WHY: q5除外条件テスト用 → WHAT: 除外条件検証1件"
      q11_not_already_done: "未達成。q5除外条件ケースを新規作成し、既存達成ではないことを確認"
YAML
    CMD_BLOCK=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
    CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
    export CMD_ID CMD_BLOCK CMD_BLOCK_NC
}

_make_cmd_project_depth() {
    local project_val="$1"
    local depth_val="$2"
    local q5_val="$3"
    cat > "$QUEUE_FILE" <<YAML
commands:
  cmd_q5test:
    id: cmd_q5test
    command: "q5 project/depth テスト用cmd"
    status: pending
    project: ${project_val}
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "${depth_val}"
      q5_verified_source: "${q5_val}"
      q8_why_what: "WHY: q5 project/depthテスト → WHAT: 条件分岐1件確認"
      q11_not_already_done: "未達成。project/depth分岐ケースを新規作成し、既存達成ではないことを確認"
YAML
    CMD_BLOCK=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
    CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
    export CMD_ID CMD_BLOCK CMD_BLOCK_NC
}

@test "Q5-T009: scope_mode=SCOUT + code_readingのみ → BLOCKなし(除外)" {
    _make_cmd_exempt "code_reading" "scope_mode: SCOUT"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK: q5=code_readingのみ"* ]]
}

@test "Q5-T010: scout_exempt=true + code_readingのみ → BLOCKなし(除外)" {
    _make_cmd_exempt "code_reading" "scout_exempt: true"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK: q5=code_readingのみ"* ]]
}

@test "Q5-T011: project=infra + q4_depth=shallow + code_readingのみ → INFOでBLOCKなし" {
    _make_cmd_project_depth "infra" "shallow" "code_reading"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: q5=code_reading。project=infra かつ q4_depth=shallow のためINFO扱い。OK"* ]]
    [[ "$output" != *"BLOCK: q5=code_readingのみ"* ]]
}

@test "Q5-T012: project=dm-signal + q4_depth=shallow + code_readingのみ → 従来通りBLOCK" {
    _make_cmd_project_depth "dm-signal" "shallow" "code_reading"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: q5=code_readingのみ"* ]]
}

@test "Q5-T013: project=infra + q4_depth=deep + code_readingのみ → 従来通りBLOCK" {
    _make_cmd_project_depth "infra" "deep" "code_reading"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: q5=code_readingのみ"* ]]
}
