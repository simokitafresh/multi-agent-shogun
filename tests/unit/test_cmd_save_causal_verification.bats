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

@test "causal scope debug output includes extracted q5_verified_source" {
    local CMD_BLOCK='    project: infra
    title: "改善 — cmd_save causal_verification q5抽出"
    purpose: "cmd_save.shでq5抽出値をcombinedへ渡す"
    target_path: scripts/cmd_save.sh
    command: |
      scripts/cmd_save.sh の q5抽出を検証する
    acceptance_criteria:
      - id: AC1
        description: "DEBUG出力にq5抽出値が表示される"
    quality_gate:
      q5_verified_source: "structure_verified — git log確認: c5273891c; git blame確認: scripts/cmd_save.sh; semantic/causal確認: causal-verification"
      q8_why_what: "WHY: q5がcombinedに入らないと因果確認済みcmdがWARNになる → WHAT: q5抽出を確認する"'

    run env CMD_SAVE_DEBUG=1 bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG: [CAUSAL_VERIFICATION] q5_value=structure_verified — git log確認: c5273891c; git blame確認: scripts/cmd_save.sh; semantic/causal確認: causal-verification"* ]]
    [[ "$output" != *"WARNING: 因果確認不足"* ]]
}

@test "cmd_3326: causal scope accepts structured evidence without magic words" {
    local CMD_BLOCK='    project: infra
    title: "改善 — cmd_save structured evidence"
    purpose: "cmd_save.shの検査誤反応を分類結果に沿って修理する"
    target_path: scripts/cmd_save.sh
    command: |
      scripts/cmd_save.sh を修正する
    acceptance_criteria:
      - id: AC1
        description: "scripts/cmd_save.sh と docs/research/cmd_3323_cmd_design_quality_fp_classification_20260612.md と a990a5c39 の整合を確認する"
    quality_gate:
      q5_verified_source: "structure_verified — scripts/cmd_save.sh; docs/research/cmd_3323_cmd_design_quality_fp_classification_20260612.md; commit a990a5c39"
      q8_why_what: "WHY: magic word依存だと証跡済みcmdもWARNになる → WHAT: 構造化証跡を確認する"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [CAUSAL_VERIFICATION]"* ]]
    [[ "$output" != *"WARNING: 因果確認不足"* ]]
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

@test "cmd_3520: generic report format wording is not causal scope" {
    local CMD_BLOCK='    project: infra
    title: "報告書生成"
    purpose: "L1検証結果をfixed report formatでMarkdown報告書へ整形する"
    command: |
      docs/research/report_generator.sh で固定report formatの出力を生成する
    acceptance_criteria:
      - id: AC1
        description: "固定report formatのMarkdown報告書が生成される"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"INFO: [CAUSAL_VERIFICATION]"* ]]
    [[ "$output" != *"q5テンプレート"* ]]
}

@test "cmd_3520: report_field_set and gate_report_format remain causal scope" {
    local CMD_BLOCK='    project: infra
    title: "報告YAML gate改善"
    purpose: "report_field_set.shとgate_report_format.shの連携を修正する"
    command: |
      report_field_set.sh と gate_report_format.sh の回帰を修正する
    acceptance_criteria:
      - id: AC1
        description: "report_field_set.sh経由の報告YAML更新がgate_report_format.shをPASSする"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [CAUSAL_VERIFICATION]"* ]]
    [[ "$output" == *"q5テンプレート"* ]]
}
