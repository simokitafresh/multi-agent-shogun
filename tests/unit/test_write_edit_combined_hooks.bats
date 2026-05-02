#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PRE_HOOK="$PROJECT_ROOT/.claude/hooks/pre-write-edit-combined.sh"
    export POST_HOOK="$PROJECT_ROOT/.claude/hooks/post-write-edit-combined.sh"
    [ -f "$PRE_HOOK" ] || return 1
    [ -f "$POST_HOOK" ] || return 1
}

setup() {
    export TMP_DIR TMP_REPORT TMP_STK TMP_AUTOLEARN
    TMP_DIR="$(mktemp -d)"
    mkdir -p "$TMP_DIR/queue/reports"
    TMP_REPORT="$TMP_DIR/queue/reports/hanzo_report_cmd_100.yaml"
    TMP_STK="$TMP_DIR/queue/shogun_to_karo.yaml"
    TMP_AUTOLEARN="$TMP_DIR/preflight_autolearn.txt"
    printf 'result: ok\n' > "$TMP_REPORT"
    printf 'commands: {}\n' > "$TMP_STK"
}

teardown() {
    rm -rf "$TMP_DIR"
}

_run_pre() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | PREFLIGHT_AUTOLEARN_FILE="$3" bash "$2"' _ "$payload" "$PRE_HOOK" "$TMP_AUTOLEARN"
}

_run_post() {
    local payload="$1"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$POST_HOOK"
}

@test "pre combined hook denies report yaml writes" {
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP_REPORT"'"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'queue/reports/*.yamlはWrite/Editで直接書くな。report_field_set.shを使え。'* ]]
}

@test "pre combined hook allows non-report new file" {
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"/tmp/combined_new_file.txt"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "pre combined hook shows shogun_to_karo edit checklist" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"hookEventName"'* ]]
    [[ "$output" == *'"PreToolUse"'* ]]
    [[ "$output" == *'対象現物を確認したか'* ]]
    [[ "$output" == *'既存代替で足りないことを確認したか'* ]]
    [[ "$output" == *'cmd_save.sh関連チェック名を確認したか'* ]]
}

@test "pre combined hook shows dynamic preflight autolearn items" {
    printf '%s\n' '2026-05-02T00:00:00Z check=quality_gate_q8_compound_question count=3 warn=q8_複利の問い cmd=cmd_test' > "$TMP_AUTOLEARN"
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_STK"'"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'動的追加確認(preflight_autolearn)'* ]]
    [[ "$output" == *'quality_gate_q8_compound_question'* ]]
    [[ "$output" == *'count=3'* ]]
}

@test "pre combined hook does not show checklist for other edit targets" {
    _run_pre '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/combined_other_file.txt"}}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'対象現物を確認したか'* ]]
    [[ "$output" != *'既存代替で足りないことを確認したか'* ]]
    [[ "$output" != *'cmd_save.sh関連チェック名を確認したか'* ]]
}

@test "post combined hook exits cleanly for unrelated payload" {
    _run_post '{"tool_name":"Write","tool_input":{"file_path":"/tmp/combined_new_file.txt"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "post combined hook warns on report yaml edits" {
    _run_post '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP_REPORT"'"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"hookEventName":"PostToolUse"'* ]]
    [[ "$output" == *'報告YAMLへの直接Edit/Write検出'* ]]
}
