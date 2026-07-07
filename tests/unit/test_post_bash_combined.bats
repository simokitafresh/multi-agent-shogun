#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/post-bash-combined.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/post_bash_combined.XXXXXX")"
    mkdir -p "$TEST_ROOT/.claude/hooks" "$TEST_ROOT/queue/tasks" "$TEST_ROOT/config" "$TEST_ROOT/mock_bin"
    cp "$HOOK_SCRIPT" "$TEST_ROOT/.claude/hooks/post-bash-combined.sh"
    chmod +x "$TEST_ROOT/.claude/hooks/post-bash-combined.sh"

    cat > "$TEST_ROOT/mock_bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "saizo"
EOF
    chmod +x "$TEST_ROOT/mock_bin/tmux"

    export PATH="$TEST_ROOT/mock_bin:$PATH"
    export TMUX_PANE="%1"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

run_hook() {
    local payload="$1"
    run bash -lc 'cd "$1" && printf "%s" "$2" | .claude/hooks/post-bash-combined.sh' _ "$TEST_ROOT" "$payload"
}

@test "test-result path emits additionalContext on skipped bats output" {
    local payload
    payload="$(jq -cn --arg cmd "bats tests/unit/test_example.bats" --arg result $'1..2\nok 1 first\nok 2 second # skip reason' '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    hook_name="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
    context="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [ "$hook_name" = "PostToolUse" ]
    [[ "$context" == *'ERROR: 1 test(s) SKIPPED'* ]]
}

@test "cmd_save BLOCK emits rerun guidance" {
    local payload
    payload="$(jq -cn --arg cmd "bash scripts/cmd_save.sh cmd_100" --arg result "BLOCK: mock failure" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:{exit_code:1, stderr:$result}}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    hook_name="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
    context="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [ "$hook_name" = "PostToolUse" ]
    [[ "$context" == *'cmd_save.sh BLOCK'* ]]
    [[ "$context" == *'再実行'* ]]
}

@test "cmd_save BLOCK detects Claude Code toolUseResult exitCode payload" {
    local payload
    payload="$(jq -cn --arg cmd "bash scripts/cmd_save.sh cmd_100" --arg result "BLOCK: actual payload failure" '{tool_name:"Bash", tool_input:{command:$cmd}, toolUseResult:{exitCode:1, stderr:$result}}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    hook_name="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
    context="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [ "$hook_name" = "PostToolUse" ]
    [[ "$context" == *'cmd_save.sh BLOCK'* ]]
    [[ "$context" == *'actual payload failure'* ]]
}

@test "cmd_save BLOCK detects BLOCK output when exit code field is unavailable" {
    local payload
    payload="$(jq -cn --arg cmd "bash scripts/cmd_save.sh cmd_100" --arg result "BLOCK: output-only failure" '{tool_name:"Bash", tool_input:{command:$cmd}, toolUseResult:{stderr:$result}}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    hook_name="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
    context="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [ "$hook_name" = "PostToolUse" ]
    [[ "$context" == *'cmd_save.sh BLOCK'* ]]
    [[ "$context" == *'output-only failure'* ]]
}

@test "cmd_save PASS stays silent" {
    local payload
    payload="$(jq -cn --arg cmd "bash scripts/cmd_save.sh cmd_100" --arg result "CMD_SAVE PASS" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:{exit_code:0, stdout:$result}}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "commit-reminder path warns when project has uncommitted changes" {
    cat > "$TEST_ROOT/queue/tasks/saizo.yaml" <<'YAML'
task:
  project: demo
YAML
    cat > "$TEST_ROOT/config/projects.yaml" <<EOF
projects:
  - id: demo
    path: "$TEST_ROOT/demo_project"
EOF
    mkdir -p "$TEST_ROOT/demo_project"
    (
        cd "$TEST_ROOT/demo_project"
        git init -q
        git config user.email test@example.com
        git config user.name "Test User"
        printf 'tracked\n' > tracked.txt
        git add tracked.txt
        git commit -qm "init"
        printf 'dirty\n' >> tracked.txt
    )

    local payload
    payload="$(jq -cn --arg cmd "bash scripts/inbox_write.sh karo \"報告完了\" report_received saizo" --arg result "ok" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    hook_name="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
    context="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [ "$hook_name" = "PostToolUse" ]
    [[ "$context" == *'COMMIT MISSING 警告'* ]]
    [[ "$context" == *'tracked.txt'* ]]
    [[ "$context" == *'任務scope内ファイルだけをcommitせよ'* ]]
    [[ "$context" == *'git add <scope内file...>'* ]]
    [[ "$context" == *'scope外/他忍者担当の変更はstageせず'* ]]
    [[ "$context" != *'git add -A'* ]]
}

@test "LS-A16 parity reminder fires on recalculate-sync curl command" {
    local payload
    payload="$(jq -cn --arg cmd 'curl -X POST https://dm-signal-backend.onrender.com/admin/recalculate-sync -u "$ADMIN_USER:$ADMIN_PASS"' --arg result "ok" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    hook_name="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
    context="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [ "$hook_name" = "PostToolUse" ]
    [[ "$context" == *'LS-A16'* ]]
    [[ "$context" == *'parity_check.sh'* ]]
}

@test "LS-A16 parity reminder stays silent on unrelated recalculate-sync mention" {
    local payload
    payload="$(jq -cn --arg cmd 'grep -rn "recalculate-sync" docs/' --arg result "docs/x.md: recalculate-sync usage" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "LS-A16 parity reminder stays silent when curl and recalculate-sync co-occur in non-curl command text" {
    local payload
    payload="$(jq -cn --arg cmd 'bash scripts/report_field_set.sh report.yaml result.details "curl経由のadmin/recalculate-sync実行を検知した直後に警告を出す"' --arg result "ok" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "commit-reminder path stays silent when project is clean" {
    cat > "$TEST_ROOT/queue/tasks/saizo.yaml" <<'YAML'
task:
  project: demo
YAML
    cat > "$TEST_ROOT/config/projects.yaml" <<EOF
projects:
  - id: demo
    path: "$TEST_ROOT/demo_project"
EOF
    mkdir -p "$TEST_ROOT/demo_project"
    (
        cd "$TEST_ROOT/demo_project"
        git init -q
        git config user.email test@example.com
        git config user.name "Test User"
        printf 'tracked\n' > tracked.txt
        git add tracked.txt
        git commit -qm "init"
    )

    local payload
    payload="$(jq -cn --arg cmd "bash scripts/inbox_write.sh karo \"報告完了\" report_received saizo" --arg result "ok" '{tool_name:"Bash", tool_input:{command:$cmd}, tool_result:$result}')"

    run_hook "$payload"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
