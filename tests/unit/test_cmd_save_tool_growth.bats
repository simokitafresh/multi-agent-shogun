#!/usr/bin/env bats
# test_cmd_save_tool_growth.bats — Check 11.5: 研究cmdの道具成長AC WARNINGテスト
#
# AC1: 研究cmd + engine統合ACなし → WARNING
# AC2: 研究cmd + engine統合ACあり → WARNINGなし

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    [ -f "$PROJECT_ROOT/scripts/cmd_save.sh" ] || return 1

    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_tool_growth.XXXXXX")"

    cat > "$TEST_TMPDIR/test_func.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
CMD_BLOCK="$1"
CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
WRAPPER

    sed -n '/^check_research_tool_growth_ac()/,/^}/p' "$PROJECT_ROOT/scripts/cmd_save.sh" >> "$TEST_TMPDIR/test_func.sh"
    cat >> "$TEST_TMPDIR/test_func.sh" <<'CALL'
check_research_tool_growth_ac 2>&1
CALL
    chmod +x "$TEST_TMPDIR/test_func.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "TG-T001: research cmd with no engine AC emits WARNING" {
    local CMD_BLOCK="    project: dm-signal
    task_type: impl
    command: |
      scripts/analysis/run_research.py で simulate_signals の比較を行う
    acceptance_criteria:
      - \"AC1: 分析スクリプトを追加\"
      - \"AC2: テスト実行+commit\""

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"research_engine.py"* ]]
    [[ "$output" == *"SG10"* ]]
}

@test "TG-T002: research cmd with engine integration AC emits no WARNING" {
    local CMD_BLOCK="  project: dm-signal
  task_type: impl
  command: |
    research_engine を使う analysis runner を追加する
  acceptance_criteria:
    - id: AC1
      description: \"新規関数をresearch_engine.pyへ統合\"
    - id: AC2
      description: \"呼び出し側を移設してテスト+commit\""

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"SG10"* ]]
}

@test "TG-T003: non-research impl cmd is skipped" {
    local CMD_BLOCK="    project: dm-signal
    task_type: impl
    command: \"inbox_watcher.sh のログ整形\"
    acceptance_criteria:
      - \"AC1: ログ文言修正\"
      - \"AC2: テスト+commit\""

    run bash "$TEST_TMPDIR/test_func.sh" "$CMD_BLOCK"
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"SG10"* ]]
}
