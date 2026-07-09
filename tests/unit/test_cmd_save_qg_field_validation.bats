#!/usr/bin/env bats
# test_cmd_save_qg_field_validation.bats — quality_gateフィールド名バリデーションテスト (cmd_3245)
#
# AC1: 正しいフィールド名のみ → BLOCKなし(フィールド名検証通過)
# AC2: 不正フィールド名 → BLOCK + 正しいフィールド名が表示される

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
    eval "$(sed -n '/^is_gate_or_hook_addition_cmd()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^_is_gate_or_hook_addition_cmd_uncached()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_existing_alternative_verification()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_assumption_source_files()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^extract_guard_list_from_files()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_guard_duplicate_check()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_q11_guard_list()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_gate_hook_action_conversion()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_block_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^abort_if_block_immediate()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar load_cmd_block load_cmd_block_cache cmd_block_has_field cmd_block_get_field \
        is_gate_or_hook_addition_cmd _is_gate_or_hook_addition_cmd_uncached q11_has_existing_alternative_verification \
        collect_assumption_source_files extract_guard_list_from_files q11_has_guard_duplicate_check \
        collect_q11_guard_list check_gate_hook_action_conversion record_block_reason abort_if_block_immediate

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
    export CMD_ID="cmd_qgfv_test"
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_LOADED=0
    export CMD_BLOCK_FOUND=0
    export CMD_BLOCK_CACHE_LOADED=0
    export CMD_SAVE_ACCUMULATE_BLOCKS=0
    export BLOCK_COUNT=0
    declare -ga BLOCK_REASONS=()
    declare -gA CMD_BLOCK_CACHE=()
    export TEST_PER_TMP="$BATS_TEST_TMPDIR"
    mkdir -p "${TEST_PER_TMP}/queue/archive/cmds"
    export QUEUE_FILE="${TEST_PER_TMP}/queue/shogun_to_karo.yaml"
}

teardown() { true; }

_make_cmd_with_fields() {
    # $1 = quality_gate YAML block (indented 6 spaces under quality_gate:)
    local qg_body="$1"
    cat > "$QUEUE_FILE" <<YAML
commands:
  cmd_qgfv_test:
    id: cmd_qgfv_test
    command: "フィールド名バリデーションテスト用cmd"
    status: pending
    project: infra
    quality_gate:
${qg_body}
    assumptions:
      - claim: "テスト対象はフィールド名バリデーション"
        source: "scripts/cmd_save.sh code_reading + isolated_test"
        trust: "verified"
    diagnosis:
      root_cause: "テスト不在"
      evidence: "テストファイルなし"
      fix_direction: "テスト追加"
YAML
    CMD_BLOCK=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
    CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
    export CMD_ID CMD_BLOCK CMD_BLOCK_NC
}

# ---- AC1: 正しいフィールド名のみ → フィールド名バリデーションBLOCKなし ----

@test "QGFV-T001: 全フィールド名が正しい → フィールド名BLOCKなし" {
    _make_cmd_with_fields "$(cat <<'EOF'
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "隠さない"
      q7_definition_verified: "確認済み"
      q8_why_what: "WHY: テスト → WHAT: 検証"
      q9_firefighting_root_cause: "該当なし"
      q10_knowledge_boundary: "cmd_save.sh内"
      q11_not_already_done: "未達成。新規テスト作成"
      q12_lord_30min_cost: "30分以内"
EOF
)"
    run check_quality_gate
    echo "$output" >&2
    [[ "$output" != *"不正フィールド名"* ]]
}

@test "QGFV-T002: q5フィールド(短縮名)も正しいフィールド → BLOCKなし" {
    _make_cmd_with_fields "$(cat <<'EOF'
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5: "確認済み"
      q8_why_what: "WHY: テスト → WHAT: 検証"
      q11_not_already_done: "未達成。新規テスト作成"
EOF
)"
    run check_quality_gate
    echo "$output" >&2
    [[ "$output" != *"不正フィールド名"* ]]
}

@test "QGFV-T003: q_ambiguityも正しいフィールド → BLOCKなし" {
    _make_cmd_with_fields "$(cat <<'EOF'
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q8_why_what: "WHY: テスト → WHAT: 検証"
      q11_not_already_done: "未達成。新規テスト作成"
      q_ambiguity: "曖昧さなし"
EOF
)"
    run check_quality_gate
    echo "$output" >&2
    [[ "$output" != *"不正フィールド名"* ]]
}

# ---- AC2: 不正フィールド名 → BLOCK + 正しい名前表示 ----

@test "QGFV-T004: q5_assumptions(不正名) → BLOCK + 不正名表示" {
    _make_cmd_with_fields "$(cat <<'EOF'
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_assumptions: "確認した"
      q8_why_what: "WHY: テスト → WHAT: 検証"
      q11_not_already_done: "未達成"
EOF
)"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"不正フィールド名"* ]]
    [[ "$output" == *"q5_assumptions"* ]]
    [[ "$output" == *"正しいフィールド名"* ]]
}

@test "QGFV-T005: q13_nonexistent(不正名) → BLOCK" {
    _make_cmd_with_fields "$(cat <<'EOF'
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q8_why_what: "WHY: テスト → WHAT: 検証"
      q11_not_already_done: "未達成"
      q13_nonexistent: "架空のフィールド"
EOF
)"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"不正フィールド名"* ]]
    [[ "$output" == *"q13_nonexistent"* ]]
}

@test "QGFV-T006: 複数の不正名 → BLOCK + 件数表示" {
    _make_cmd_with_fields "$(cat <<'EOF'
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_assumptions: "不正1"
      q6_hiding: "不正2"
      q8_why_what: "WHY: テスト → WHAT: 検証"
      q11_not_already_done: "未達成"
EOF
)"
    run check_quality_gate
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"不正フィールド名"* ]]
    [[ "$output" == *"2件検出"* ]]
}

@test "QGFV-T007: assumptions/diagnosisは正しいフィールド名 → BLOCKなし" {
    _make_cmd_with_fields "$(cat <<'EOF'
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q8_why_what: "WHY: テスト → WHAT: 検証"
      q11_not_already_done: "未達成"
      assumptions: "前提確認済み"
      diagnosis: "根因特定済み"
EOF
)"
    run check_quality_gate
    echo "$output" >&2
    [[ "$output" != *"不正フィールド名"* ]]
}
