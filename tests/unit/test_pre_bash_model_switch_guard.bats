#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
}

run_hook() {
    local command="$1" payload
    payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")"
    run env BATS_TEST_FILENAME=fixture TMUX_AGENT_ID=karo bash "$HOOK_SCRIPT" <<< "$payload"
}

@test "review approval permits model_switch substring inside cmd id" {
    run_hook "bash scripts/review_approval.sh cmd_training_speed_model_switch_preflight_20260717025215 karo ACCEPT report.yaml auto"
    [ "$status" -eq 0 ]
}

@test "read-only search permits model_switch substring" {
    run_hook "rg -n model_switch scripts tests"
    [ "$status" -eq 0 ]
}

@test "inbox type token model_switch remains blocked" {
    run_hook "bash scripts/inbox_write.sh hayate '/model opus' model_switch karo switch_model"
    [ "$status" -ne 0 ]
    [[ "$output" == *"model_switchはスキル経由"* ]]
}

@test "inbox message substring without type token is allowed" {
    run_hook "bash scripts/inbox_write.sh karo 'model_switch task reviewed' report_review gunshi review"
    [ "$status" -eq 0 ]
}
