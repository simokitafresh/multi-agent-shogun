#!/usr/bin/env bats
# test_necessity: Codex must persist per-task Skill receipts and block only explicitly-required recommendations before actionable tools.

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/codex_skill_guard.XXXXXX")"
    mkdir -p "$TEST_ROOT/queue/tasks" "$TEST_ROOT/logs" "$TEST_ROOT/scripts/hooks" "$TEST_ROOT/scripts"
    cp "$PROJECT_ROOT/scripts/hooks/codex_skill_execution_guard.sh" "$TEST_ROOT/scripts/hooks/"
    cp "$PROJECT_ROOT/scripts/skill_execution_log.sh" "$TEST_ROOT/scripts/"
    cat > "$TEST_ROOT/scripts/hooks/three_layer_preflight.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PREFLIGHT_CALL_LOG"
[[ "${PREFLIGHT_RESULT:-0}" == 0 ]]
SH
    chmod +x "$TEST_ROOT/scripts/hooks/three_layer_preflight.sh"
    export PREFLIGHT_CALL_LOG="$TEST_ROOT/preflight.log"
    chmod +x "$TEST_ROOT/scripts/hooks/codex_skill_execution_guard.sh" "$TEST_ROOT/scripts/skill_execution_log.sh"
    export SHOGUN_REPO_ROOT="$TEST_ROOT"
    export SHOGUN_AGENT_ID="tobisaru"
    export SHOGUN_TASK_FILE="$TEST_ROOT/queue/tasks/tobisaru.yaml"
    export SKILL_EXECUTION_LOG_FILE="$TEST_ROOT/logs/skill_execution_log.yaml"
}

teardown() {
    [[ -d "${TEST_ROOT:-}" ]] && rm -rf "$TEST_ROOT"
}

write_task() {
    printf '%s\n' "$1" >"$SHOGUN_TASK_FILE"
}

run_guard() {
    run bash "$TEST_ROOT/scripts/hooks/codex_skill_execution_guard.sh"
}

@test "explicitly required recommendation blocks action until Skill receipt then passes" {
    write_task 'task:
  task_id: cmd_guard
  status: in_progress
  recommended_skills: [db-check]
  recommended_skills_required: true'

    run_guard <<<'{"tool_name":"exec_command","tool_input":{"cmd":"true"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *"skills=db-check"* ]]

    run_guard <<<'{"tool_name":"Skill","tool_input":{"skill":"db-check"}}'
    [ "$status" -eq 0 ]
    grep -q 'skill: "db-check"' "$SKILL_EXECUTION_LOG_FILE"
    grep -q 'executor: "tobisaru"' "$SKILL_EXECUTION_LOG_FILE"
    grep -q 'source: "cmd_guard"' "$SKILL_EXECUTION_LOG_FILE"
    grep -Eq 'ts: "[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$SKILL_EXECUTION_LOG_FILE"

    run_guard <<<'{"tool_name":"Write","tool_input":{"file_path":"x"}}'
    [ "$status" -eq 0 ]
}

@test "no skill optional recommendation and existing receipt have zero false positives" {
    write_task 'task:
  task_id: cmd_none
  status: in_progress'
    run_guard <<<'{"tool_name":"apply_patch","tool_input":{}}'
    [ "$status" -eq 0 ]

    write_task 'task:
  task_id: cmd_optional
  status: in_progress
  recommended_skills: [db-check]'
    run_guard <<<'{"tool_name":"exec_command","tool_input":{"cmd":"true"}}'
    [ "$status" -eq 0 ]

    write_task 'task:
  task_id: cmd_existing
  status: in_progress
  required_recommended_skills: [db-check]'
    bash "$TEST_ROOT/scripts/skill_execution_log.sh" db-check tobisaru PASS "" test cmd_existing "" true
    run_guard <<<'{"tool_name":"Edit","tool_input":{"file_path":"x"}}'
    [ "$status" -eq 0 ]
}

@test "receipt remains valid after a fresh guard process" {
    write_task 'task:
  task_id: cmd_restart
  status: in_progress
  required_recommended_skills: [report-write]'
    bash "$TEST_ROOT/scripts/skill_execution_log.sh" report-write tobisaru PASS "" test cmd_restart "" true

    run env -i PATH="$PATH" SHOGUN_REPO_ROOT="$TEST_ROOT" SHOGUN_AGENT_ID=tobisaru \
        SHOGUN_TASK_FILE="$SHOGUN_TASK_FILE" SKILL_EXECUTION_LOG_FILE="$SKILL_EXECUTION_LOG_FILE" \
        bash "$TEST_ROOT/scripts/hooks/codex_skill_execution_guard.sh" \
        <<<'{"tool_name":"unified_exec","tool_input":{"cmd":"true"}}'
    [ "$status" -eq 0 ]
}

@test "非shell PreToolUseも三層preflight証跡なしではBLOCK" {
    write_task 'task:
  task_id: cmd_web
  status: in_progress'
    run env PREFLIGHT_RESULT=1 bash "$TEST_ROOT/scripts/hooks/codex_skill_execution_guard.sh" <<< '{"tool_name":"web","tool_input":{"query":"probe"}}'
    [ "$status" -eq 2 ]
    [[ "$output" == *"三層preflight証跡なし"* ]]
    grep -q '^verify web ' "$PREFLIGHT_CALL_LOG"
}

@test "Readを含む全toolは三層preflightPASS後に通過" {
    write_task 'task:
  task_id: cmd_read
  status: in_progress'
    run_guard <<< '{"tool_name":"Read","tool_input":{"file_path":"context/infrastructure.md"}}'
    [ "$status" -eq 0 ]
    grep -q '^verify Read context/infrastructure.md ' "$PREFLIGHT_CALL_LOG"
}
