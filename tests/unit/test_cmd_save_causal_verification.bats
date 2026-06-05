#!/usr/bin/env bats
# test_cmd_save_causal_verification.bats — causal_verification q5 template tests

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PROJECT_ROOT
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_causal.XXXXXX")"

    cat > "$TEST_TMPDIR/test_func.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
CMD_BLOCK="$1"
CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
CMD_BLOCK_FOUND=1
CMD_BLOCK_CACHE_LOADED=0
declare -A CMD_BLOCK_CACHE=()
WARN_COUNT=0
declare -a WARN_REASONS=()
WRAPPER

    sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^extract_acceptance_criteria_block()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^cmd_save_is_causal_verification_scope()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^show_causal_verification_q5_template()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^check_causal_verification_requirement()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    cat >> "$TEST_TMPDIR/test_func.sh" <<'CALL'
record_warn_reason() {
    WARN_REASONS+=("$1")
    echo "WARN_RECORDED: $1" >&2
}
check_causal_verification_requirement 2>&1
CALL
    chmod +x "$TEST_TMPDIR/test_func.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "causal scope emits q5 git log placeholder template" {
    local CMD_BLOCK='    project: infra
    title: "改善 — cmd_save causal_verification表示"
    purpose: "cmd_save.shで因果確認漏れを防ぐ"
    target_path: scripts/cmd_save.sh
    command: |
      scripts/cmd_save.sh の causal_verification 表示を改善する
    acceptance_criteria:
      - id: AC1
        description: "scope対象でq5テンプレートが表示される"
    quality_gate:
      q5_verified_source: "structure_verified — 現物確認"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [CAUSAL_VERIFICATION]"* ]]
    [[ "$output" == *"q5テンプレート: q5_verified_source"* ]]
    [[ "$output" == *"git log確認:"* ]]
    [[ "$output" == *"git blame確認:"* ]]
    [[ "$output" == *"semantic/causal確認:"* ]]
}

@test "non causal scope does not emit q5 template" {
    local CMD_BLOCK='    project: infra
    title: "文言整理"
    purpose: "通常の説明文を整理する"
    command: |
      READMEの表現を整える
    acceptance_criteria:
      - id: AC1
        description: "説明文が更新される"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"q5テンプレート"* ]]
    [[ "$output" != *"git log確認:"* ]]
}
