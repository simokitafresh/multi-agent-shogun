#!/usr/bin/env bats
# Guard D010: destructive git operations require explicit inbound Lord approval.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
}

setup() {
    export PRE_BASH_LORD_CONVERSATION_FILE="$BATS_TEST_TMPDIR/lord_conversation.jsonl"
    : > "$PRE_BASH_LORD_CONVERSATION_FILE"
}

_run_hook() {
    local cmd="$1"
    local payload
    payload="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")"
    run bash -c 'printf "%s" "$1" | PRE_BASH_LORD_CONVERSATION_FILE="$2" bash "$3"' _ "$payload" "$PRE_BASH_LORD_CONVERSATION_FILE" "$HOOK_SCRIPT"
}

_write_approval() {
    printf '%s\n' '{"direction":"inbound","detail":"git push --force-with-lease を承認。実行してよい。"}' > "$PRE_BASH_LORD_CONVERSATION_FILE"
}

@test "git push --force-with-lease is blocked without inbound Lord approval" {
    _run_hook "git push --force-with-lease origin feature"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
    [[ "$output" == *"D010"* ]]
}

@test "git push --force-with-lease is allowed with matching inbound Lord approval" {
    _write_approval
    _run_hook "git push --force-with-lease origin feature"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "outbound approval-looking text does not authorize destructive git operations" {
    printf '%s\n' '{"direction":"outbound","detail":"git push --force-with-lease を承認。実行してよい。"}' > "$PRE_BASH_LORD_CONVERSATION_FILE"
    _run_hook "git push --force-with-lease origin feature"
    [ "$status" -ne 0 ]
    [[ "$output" == *"D010"* ]]
}

@test "absolute ban remains blocked even when Lord approval exists" {
    printf '%s\n' '{"direction":"inbound","detail":"git reset --hard を承認。実行してよい。"}' > "$PRE_BASH_LORD_CONVERSATION_FILE"
    _run_hook "git reset --hard HEAD"
    [ "$status" -ne 0 ]
    [[ "$output" == *"D004"* ]]
}
