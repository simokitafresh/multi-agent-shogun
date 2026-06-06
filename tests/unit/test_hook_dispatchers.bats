#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PRE_DISPATCH="$PROJECT_ROOT/.claude/hooks/pretool-dispatch.sh"
    export POST_DISPATCH="$PROJECT_ROOT/.claude/hooks/posttool-dispatch.sh"
    [ -x "$PRE_DISPATCH" ] || return 1
    [ -x "$POST_DISPATCH" ] || return 1
}

setup() {
    export MOCK_AGENT_ID="dispatcher_test_$$"
    export LOG_FILE="/tmp/claude_read_log_${MOCK_AGENT_ID}.txt"
    export PRE_BASH_LORD_CONVERSATION_FILE="$BATS_TEST_TMPDIR/lord_conversation.jsonl"
    : > "$PRE_BASH_LORD_CONVERSATION_FILE"
    rm -f "$LOG_FILE"
    export EXISTING_FILE="$BATS_TEST_TMPDIR/existing.txt"
    printf 'existing\n' > "$EXISTING_FILE"
}

teardown() {
    rm -f "$LOG_FILE"
}

_run_pre() {
    local payload="$1"
    run env MOCK_AGENT_ID="$MOCK_AGENT_ID" \
        PRE_BASH_LORD_CONVERSATION_FILE="$PRE_BASH_LORD_CONVERSATION_FILE" \
        TMUX_PANE="" bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$PRE_DISPATCH"
}

_run_post() {
    local payload="$1"
    run env TMUX_PANE="" bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$POST_DISPATCH"
}

@test "pre dispatcher preserves Bash destructive deny output and status" {
    _run_pre '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"destructive git operation"* ]]
}

@test "pre dispatcher preserves Read tracking before Edit" {
    local payload_read='{"tool_name":"Read","tool_input":{"file_path":"'"$EXISTING_FILE"'"}}'
    local payload_edit='{"tool_name":"Edit","tool_input":{"file_path":"'"$EXISTING_FILE"'"}}'
    rm -f /tmp/claude_read_log_unknown.txt
    run env -u MOCK_AGENT_ID -u AGENT_ID TMUX_PANE="" \
        PAYLOAD_READ="$payload_read" PAYLOAD_EDIT="$payload_edit" PRE_DISPATCH="$PRE_DISPATCH" bash -c '
        printf "%s" "$PAYLOAD_READ" | "$PRE_DISPATCH"
        printf "%s" "$PAYLOAD_EDIT" | "$PRE_DISPATCH"
    '
    [ "$status" -eq 0 ]
    rm -f /tmp/claude_read_log_unknown.txt
}

@test "pre dispatcher preserves report YAML Write deny" {
    _run_pre '{"tool_name":"Write","tool_input":{"file_path":"/tmp/queue/reports/saizo_report_cmd_1.yaml"}}'
    [ "$status" -ne 0 ]
    [[ "$output" == *'"permissionDecision":"deny"'* ]]
    [[ "$output" == *"report_field_set.sh"* ]]
}

@test "pre dispatcher mirrors stdout-only deny reason to stderr on exit 2" {
    local out_file="$BATS_TEST_TMPDIR/stdout.txt"
    local err_file="$BATS_TEST_TMPDIR/stderr.txt"
    run env PRE_DISPATCH="$PRE_DISPATCH" OUT_FILE="$out_file" ERR_FILE="$err_file" bash -c '
        printf "%s" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/queue/reports/saizo_report_cmd_1.yaml\"}}" \
            | "$PRE_DISPATCH" >"$OUT_FILE" 2>"$ERR_FILE"
        rc=$?
        printf "stdout:\n"
        cat "$OUT_FILE"
        printf "\nstderr:\n"
        cat "$ERR_FILE"
        exit "$rc"
    '
    [ "$status" -eq 2 ]
    [[ "$output" == *'stdout:'*'"permissionDecision":"deny"'* ]]
    [[ "$output" == *'stderr:'*'report_field_set.sh'* ]]
}

@test "post dispatcher preserves test omitted-case detection" {
    _run_post '{"tool_name":"Bash","tool_input":{"command":"bats tests/unit/example.bats"},"tool_result":{"stdout":"ok 1 sample # skip reason\n1 skipped","stderr":"","exit_code":0}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED"* ]]
    [[ "$output" == *"SKIP=FAIL"* ]]
}

@test "post dispatcher preserves Grep completeness warning" {
    _run_post '{"tool_name":"Grep","tool_input":{"pattern":"foo"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"網羅的ではない可能性"* ]]
}

@test "post dispatcher preserves report YAML edit warning" {
    _run_post '{"tool_name":"Edit","tool_input":{"file_path":"queue/reports/saizo_report_cmd_1.yaml"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"報告YAMLへの直接Edit/Write検出"* ]]
}
