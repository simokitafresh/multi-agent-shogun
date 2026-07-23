#!/usr/bin/env bats
# test_necessity: Commit reminders, Karo edit conflict checks, and gate/hook quality classification must preserve task-owned scope without widening to unrelated repository dirt or English substring false positives.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "commit reminder resolves planned_paths when owned_paths is absent" {
    run env FIXTURE_ROOT="$BATS_TEST_TMPDIR/system" PROJECT_ROOT="$BATS_TEST_TMPDIR/project" \
        SOURCE_HOOK="$REPO_ROOT/.claude/hooks/post-bash-commit-reminder.sh" bash -c '
            mkdir -p "$FIXTURE_ROOT/.claude/hooks" "$FIXTURE_ROOT/queue/tasks" \
                "$FIXTURE_ROOT/queue/reports" "$FIXTURE_ROOT/config" "$PROJECT_ROOT"
            cp "$SOURCE_HOOK" "$FIXTURE_ROOT/.claude/hooks/post-bash-commit-reminder.sh"
            git -C "$PROJECT_ROOT" init -q
            git -C "$PROJECT_ROOT" config user.email fixture@example.com
            git -C "$PROJECT_ROOT" config user.name fixture
            printf "owned\n" > "$PROJECT_ROOT/owned.txt"
            printf "unrelated\n" > "$PROJECT_ROOT/unrelated.txt"
            git -C "$PROJECT_ROOT" add owned.txt unrelated.txt
            git -C "$PROJECT_ROOT" commit -qm initial
            printf "dirty\n" >> "$PROJECT_ROOT/unrelated.txt"
            head=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
            printf "projects:\n  - id: fixture\n    path: %s\n" "$PROJECT_ROOT" > "$FIXTURE_ROOT/config/projects.yaml"
            printf "task:\n  project: fixture\n  planned_paths:\n    - owned.txt\n  report_path: queue/reports/kotaro.yaml\n" > "$FIXTURE_ROOT/queue/tasks/kotaro.yaml"
            printf "commit_hash: %s\n" "$head" > "$FIXTURE_ROOT/queue/reports/kotaro.yaml"
            HOOK_PAYLOAD="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"bash scripts/inbox_write.sh karo done report_received kotaro notify_karo\"}}" \
                bash "$FIXTURE_ROOT/.claude/hooks/post-bash-commit-reminder.sh"
        '
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "pre-karo edit guard distinguishes identical basenames in different paths" {
    run env AGENT_ID=karo PRE_KARO_EDIT_PROJ_DIR="$BATS_TEST_TMPDIR/project" \
        bash -c '
            mkdir -p "$PRE_KARO_EDIT_PROJ_DIR/queue/tasks"
            printf "%s\n" \
                "task:" \
                "  status: in_progress" \
                "  parent_cmd: cmd_fixture" \
                > "$PRE_KARO_EDIT_PROJ_DIR/queue/tasks/hayate.yaml"
            printf "%s\n" \
                "commands:" \
                "  cmd_fixture:" \
                "    command: edit frontend/app/monthly-trade/page.tsx" \
                > "$PRE_KARO_EDIT_PROJ_DIR/queue/shogun_to_karo.yaml"
            payload=$(printf "%s" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PRE_KARO_EDIT_PROJ_DIR/frontend/app/deterioration/page.tsx\"}}")
            printf "%s" "$payload" | bash "'"$REPO_ROOT"'/scripts/hooks/pre-karo-edit-guard.sh"
        '
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK: ファイル衝突検出"* ]]
}

@test "pre-karo edit guard still blocks the exact repo-relative path" {
    run env AGENT_ID=karo PRE_KARO_EDIT_PROJ_DIR="$BATS_TEST_TMPDIR/project" \
        bash -c '
            mkdir -p "$PRE_KARO_EDIT_PROJ_DIR/queue/tasks"
            printf "%s\n" \
                "task:" \
                "  status: in_progress" \
                "  parent_cmd: cmd_fixture" \
                > "$PRE_KARO_EDIT_PROJ_DIR/queue/tasks/hayate.yaml"
            printf "%s\n" \
                "commands:" \
                "  cmd_fixture:" \
                "    command: edit frontend/app/deterioration/page.tsx" \
                > "$PRE_KARO_EDIT_PROJ_DIR/queue/shogun_to_karo.yaml"
            payload=$(printf "%s" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PRE_KARO_EDIT_PROJ_DIR/frontend/app/deterioration/page.tsx\"}}")
            printf "%s" "$payload" | bash "'"$REPO_ROOT"'/scripts/hooks/pre-karo-edit-guard.sh"
        '
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: ファイル衝突検出"* ]]
}

@test "quality candidate requires whole English action tokens" {
    run bash -c '
        source "'"$REPO_ROOT"'/scripts/lib/gate_hook_quality_contract.sh"
        gate_hook_quality_contract_evaluate "command: hook renewal documentation"
        gate_hook_quality_contract_evaluate "command: address hook documentation typo"
        gate_hook_quality_contract_evaluate "command: add hook quality guard"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = $'no\tpass\tpass' ]
    [ "${lines[1]}" = $'no\tpass\tpass' ]
    [ "${lines[2]}" = $'yes\tmissing\tmissing' ]
}
