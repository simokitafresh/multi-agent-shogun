#!/usr/bin/env bats
# test_cmd_save_q8_tool_readiness.bats — cmd_save.sh q8_tool_readiness BLOCKテスト (cmd_1742)
#
# AC1: 道具関数名あり + q8_tool_readinessなし → BLOCK
# AC2: 道具関数名なし → スキップ
# AC3: 道具関数名あり + q8_tool_readinessあり → PASS

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
    mkdir -p "${TEST_SHARED_TMP}/dm-signal/docs/research"
    export QUEUE_FILE="${TEST_SHARED_TMP}/queue/shogun_to_karo.yaml"
    export CMD_SAVE_DM_SIGNAL_ROOT="${TEST_SHARED_TMP}/dm-signal"

    cat > "${CMD_SAVE_DM_SIGNAL_ROOT}/docs/research/metrics-engine-runbook.md" <<'RUNBOOK'
# Metrics Engine Runbook

## Scope

- Constraint: production MetricsCalculator は直接編集禁止

## 注意事項

1. score_fnよりscore_wide優先
2. benchmark未指定時は一部metricsがNaN
RUNBOOK
}

teardown_file() {
    rm -rf "$TEST_SHARED_TMP"
}

setup() {
    export CMD_ID="cmd_q8test"
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
}

_write_cmd() {
    local command_body="$1"
    local q8_line="$2"
    cat > "$QUEUE_FILE" <<YAML
commands:
  cmd_q8test:
    id: cmd_q8test
    project: dm-signal
    task_type: impl
    command: |
${command_body}
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "structure_verified"
${q8_line}
YAML
    CMD_BLOCK=$(awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found{print}" "$QUEUE_FILE")
    CMD_BLOCK_NC=$(echo "$CMD_BLOCK" | grep -v '^\s*#' || true)
    export CMD_ID CMD_BLOCK CMD_BLOCK_NC
}

@test "Q8-T001: 道具関数名あり + q8_tool_readinessなし → BLOCK" {
    _write_cmd '      metrics_research_engine.py で simulate_selection と build_return_wide を使う' ''

    run check_quality_gate
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"INFO: 研究道具runbook候補"* ]]
    [[ "$output" == *"docs/research/metrics-engine-runbook.md"* ]]
    [[ "$output" == *"q8_tool_readiness未記入"* ]]
}

@test "Q8-T002: 道具関数名なし → スキップ" {
    _write_cmd '      inbox_watcher.sh のログ整形を行う' ''

    run check_quality_gate
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"q8_tool_readiness未記入"* ]]
    [[ "$output" != *"研究道具runbook候補"* ]]
}

@test "Q8-T003: 道具関数名あり + q8_tool_readinessあり → PASS" {
    _write_cmd '      research_engine.py の simulate_selection を使う' '      q8_tool_readiness: "metrics-engine-runbook.md確認。score_wide前提を確認済み"'

    run check_quality_gate
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/research/metrics-engine-runbook.md"* ]]
    [[ "$output" != *"q8_tool_readiness未記入"* ]]
}
