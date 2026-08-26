#!/usr/bin/env bats
# test_necessity: Commit reminders, Karo edit conflict checks, and gate/hook quality classification must preserve task-owned scope without widening to unrelated repository dirt or English substring false positives.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# test_necessity: an isolated task must resolve git scope from its validated
# generation, otherwise primary-checkout dirt can create a false commit warning.
@test "isolated task scope uses clean worktree instead of dirty primary" {
    run env FIXTURE_ROOT="$BATS_TEST_TMPDIR/system" PROJECT_ROOT="$BATS_TEST_TMPDIR/project" \
        WORKTREE_ROOT="$BATS_TEST_TMPDIR/worktree" \
        SOURCE_HOOK="$REPO_ROOT/.claude/hooks/post-bash-commit-reminder.sh" \
        SOURCE_RESOLVER="$REPO_ROOT/scripts/lib/review_source_context.py" \
        SOURCE_IDENTITY="$REPO_ROOT/scripts/lib/report_commit_identity.py" bash -c '
            mkdir -p "$FIXTURE_ROOT/.claude/hooks" "$FIXTURE_ROOT/scripts/lib" \
                "$FIXTURE_ROOT/queue/tasks" "$FIXTURE_ROOT/queue/reports" "$FIXTURE_ROOT/config" \
                "$PROJECT_ROOT"
            cp "$SOURCE_HOOK" "$FIXTURE_ROOT/.claude/hooks/post-bash-commit-reminder.sh"
            cp "$SOURCE_RESOLVER" "$FIXTURE_ROOT/scripts/lib/review_source_context.py"
            cp "$SOURCE_IDENTITY" "$FIXTURE_ROOT/scripts/lib/"
            git -C "$PROJECT_ROOT" init -q
            git -C "$PROJECT_ROOT" config user.email fixture@example.com
            git -C "$PROJECT_ROOT" config user.name fixture
            printf "owned\n" > "$PROJECT_ROOT/owned.txt"
            printf "second\n" > "$PROJECT_ROOT/owned-second.txt"
            git -C "$PROJECT_ROOT" add owned.txt owned-second.txt
            git -C "$PROJECT_ROOT" commit -qm initial
            git clone -q "$PROJECT_ROOT" "$WORKTREE_ROOT"
            head=$(git -C "$WORKTREE_ROOT" rev-parse HEAD)
            generation=$(printf isolated-generation | sha256sum | awk "{print \$1}")
            marker="$FIXTURE_ROOT/task_worktree.json"
            python3 - "$marker" "$generation" "$WORKTREE_ROOT" "$PROJECT_ROOT" <<"PY"
import json, sys
path, generation, worktree, repo = sys.argv[1:]
json.dump({"generation": generation, "task_id": "cmd_isolated", "worktree": worktree,
           "repo": repo, "state": "active", "published_commit": ""}, open(path, "w"))
PY
            printf "primary dirt\n" >> "$PROJECT_ROOT/owned.txt"
            printf "primary dirt\n" >> "$PROJECT_ROOT/owned-second.txt"
            printf "projects: []\n" > "$FIXTURE_ROOT/config/projects.yaml"
            cat > "$FIXTURE_ROOT/queue/tasks/kotaro.yaml" <<YAML
task:
  task_id: cmd_isolated
  parent_cmd: cmd_isolated
  project: fixture
  commit_contract:
    repo_root: $PROJECT_ROOT
    planned_paths: [owned.txt]
  task_worktree_required: true
  task_worktree_workdir: $WORKTREE_ROOT
  task_worktree_path: $WORKTREE_ROOT
  task_worktree_generation: $generation
  task_worktree_marker: $marker
  report_path: queue/reports/kotaro.yaml
YAML
            cat > "$FIXTURE_ROOT/queue/reports/kotaro.yaml" <<YAML
task_id: cmd_isolated
parent_cmd: cmd_isolated
commit_hash: $head
files_modified:
  - path: owned.txt
    change: committed in isolated worktree
YAML
            HOOK_PAYLOAD="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"bash scripts/inbox_write.sh karo done report_received kotaro notify_karo\"}}" \
                bash "$FIXTURE_ROOT/.claude/hooks/post-bash-commit-reminder.sh"
        '
    [ "$status" -eq 0 ]
    [ -z "$output" ]
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

@test "commit reminder resolves external repo_root and nested planned_paths" {
    run env FIXTURE_ROOT="$BATS_TEST_TMPDIR/system" PROJECT_ROOT="$BATS_TEST_TMPDIR/project" \
        SOURCE_HOOK="$REPO_ROOT/.claude/hooks/post-bash-commit-reminder.sh" bash -c '
            mkdir -p "$FIXTURE_ROOT/.claude/hooks" "$FIXTURE_ROOT/queue/tasks" \
                "$FIXTURE_ROOT/queue/reports" "$FIXTURE_ROOT/config" "$PROJECT_ROOT"
            cp "$SOURCE_HOOK" "$FIXTURE_ROOT/.claude/hooks/post-bash-commit-reminder.sh"
            git -C "$PROJECT_ROOT" init -q
            git -C "$PROJECT_ROOT" config user.email fixture@example.com
            git -C "$PROJECT_ROOT" config user.name fixture
            printf "owned\n" > "$PROJECT_ROOT/owned.txt"
            git -C "$PROJECT_ROOT" add owned.txt
            git -C "$PROJECT_ROOT" commit -qm "cmd_external initial"
            head=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
            printf "projects: []\n" > "$FIXTURE_ROOT/config/projects.yaml"
            cat > "$FIXTURE_ROOT/queue/tasks/kotaro.yaml" <<YAML
task:
  task_id: cmd_external
  parent_cmd: cmd_external
  project: missing-registry-entry
  commit_contract:
    repo_root: $PROJECT_ROOT
    planned_paths: [owned.txt]
  report_path: queue/reports/kotaro.yaml
YAML
            cat > "$FIXTURE_ROOT/queue/reports/kotaro.yaml" <<YAML
task_id: cmd_external
parent_cmd: cmd_external
commit_hash: $head
files_modified:
  - path: owned.txt
    change: committed
YAML
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
