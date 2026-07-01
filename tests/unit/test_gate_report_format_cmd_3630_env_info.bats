#!/usr/bin/env bats
# test_gate_report_format_cmd_3630_env_info.bats — cmd_3630: report YAML ENV名INFO表示

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    [ -f "$GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/env_info.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/logs"
    cp "$GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_main.py" "$TEST_TMPDIR/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_format_combined.py" "$TEST_TMPDIR/scripts/gates/"
    cp "$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py" "$TEST_TMPDIR/scripts/gates/"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

_write_env_report() {
    local rpath="$1"
    local details="$2"
    cat > "$rpath" <<EOF
worker_id: hayate
parent_cmd: cmd_3630
ac_version_read: abc12345
status: completed
verdict: PASS
result:
  summary: "テスト"
  details: "$details"
purpose_validation:
  cmd_purpose: "precheck ENV変数検出"
  fit: true
  purpose_gap: ""
files_modified:
  - scripts/gates/gate_report_format_combined.py
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用のため新規教訓なし"
lessons_useful:
  - id: L625
    useful: true
    reason: "報告YAML gate確認に有用"
causal_verification:
  cause_checked: "git logとsemantic_search確認"
  design_intent_checked: "INFOのみでBLOCKしない"
  evidence: "bounded test"
  origin: "[[GA-154]] -> [[ENV変数計測条件]] -> [[precheck INFO表示]]"
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
binary_checks:
  AC1:
    - check: "ENV名INFO表示"
      result: "yes"
EOF
}

@test "ENV INFO: report values with DISABLE_CACHE/GIT_TIMEOUT emit non-blocking INFO" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_cmd_3630.yaml"
    _write_env_report "$rpath" "CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 CFC_GIT_TIMEOUT=3で再計測"

    GATE_FAST_EXIT=1 run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: report ENV variables detected:"* ]]
    [[ "$output" == *"CONTEXT_FRESHNESS_GATE_DISABLE_CACHE"* ]]
    [[ "$output" == *"CFC_GIT_TIMEOUT"* ]]
}

@test "ENV INFO: no ENV-like token emits no ENV INFO" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_cmd_3630.yaml"
    _write_env_report "$rpath" "通常条件で再計測"

    GATE_FAST_EXIT=1 run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" != *"INFO: report ENV variables detected:"* ]]
}

@test "ENV INFO: GATE_REPORT_ENV_INFO_DISABLE suppresses ENV INFO" {
    local rpath="$TEST_TMPDIR/queue/reports/hayate_report_cmd_3630.yaml"
    _write_env_report "$rpath" "CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 CFC_GIT_TIMEOUT=3で再計測"

    GATE_FAST_EXIT=1 GATE_REPORT_ENV_INFO_DISABLE=1 run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" != *"INFO: report ENV variables detected:"* ]]
}
