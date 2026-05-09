#!/usr/bin/env bats
# test_cmd_save_research_tool_explicit.bats — Check 18: GS/WF道具明示境界テスト

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_research_tool_explicit.XXXXXX")"

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
    sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^build_warn_note()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^warn_note_key()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^warn_note_message()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    sed -n '/^check_research_tool_explicit()/,/^}/p' "$SRC_SAVE_SCRIPT" >> "$TEST_TMPDIR/test_func.sh"
    cat >> "$TEST_TMPDIR/test_func.sh" <<'CALL'
check_research_tool_explicit 2>&1
CALL
    chmod +x "$TEST_TMPDIR/test_func.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "RTE-T001: outputs/grid_search CSV参照だけではGS警告しない" {
    local CMD_BLOCK='    project: dm-signal
    title: "検証 — 既存CSV確認"
    command: |
      outputs/grid_search/okugi/cmd_2103_okugi_grid_monthly.csv を確認して差分分析する
    acceptance_criteria:
      - id: AC1
        description: "CSV差分を確認する"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"GS道具"* ]]
    [[ "$output" != *"Check 18"* ]]
}

@test "RTE-T002: run_077スクリプト参照cmdは従来通りGS警告する" {
    local CMD_BLOCK='    project: dm-signal
    title: "検証 — GS忍法の再計測"
    command: |
      scripts/analysis/grid_search/run_077_oikaze.py を使って再計測する
    acceptance_criteria:
      - id: AC1
        description: "結果CSVを比較する"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"GS道具"* ]]
    [[ "$output" == *"run_077_oikaze.py"* ]]
    [[ "$output" == *"ACパス候補: scripts/analysis/grid_search/run_077_oikaze.py"* ]]
}

@test "RTE-T002b: outputs/grid_searchを参照する偵察cmdはGS警告しない" {
    local CMD_BLOCK='    project: dm-signal
    title: "偵察 — グリッドサーチ成果物の差分確認"
    command: |
      outputs/grid_search/okugi/cmd_2103_okugi_grid_monthly.csv を確認して差分分析する
    acceptance_criteria:
      - id: AC1
        description: "CSV差分を確認する"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"GS道具"* ]]
    [[ "$output" != *"Check 18"* ]]
}

@test "RTE-T003: WF四神とWF選別の説明文だけではWF警告しない" {
    local CMD_BLOCK='    project: dm-signal
    title: "設計 — WF四神の説明整理"
    command: |
      WF四神 と WF選別 の違いを説明文として整理する
    acceptance_criteria:
      - id: AC1
        description: "説明文を更新する"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"WF道具"* ]]
    [[ "$output" != *"Check 18"* ]]
}

@test "RTE-T004: wf_engine参照は従来通りWF警告する" {
    local CMD_BLOCK='    project: dm-signal
    title: "検証 — WF engine再実行"
    command: |
      outputs/scripts/l1_alm_wf_engine.py を使って再計測する
    acceptance_criteria:
      - id: AC1
        description: "結果CSVを比較する"'

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"WF道具"* ]]
    [[ "$output" == *"l1_alm_wf_engine.py"* ]]
    [[ "$output" == *"ACパス候補: outputs/scripts/l1_alm_wf_engine.py"* ]]
}
