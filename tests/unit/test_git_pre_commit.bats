#!/usr/bin/env bats
# test_git_pre_commit.bats - unit tests for scripts/hooks/git-pre-commit.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_HOOK="$PROJECT_ROOT/scripts/hooks/git-pre-commit.sh"
    [ -f "$SOURCE_HOOK" ] || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/git_pre_commit.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/hooks" "$TEST_ROOT/scripts/lib" "$TEST_ROOT/scripts" \
        "$TEST_ROOT/instructions/generated" "$TEST_ROOT/tests/unit" \
        "$TEST_ROOT/queue/tasks" "$TEST_ROOT/queue/reports" "$TEST_ROOT/logs"

    cp "$SOURCE_HOOK" "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    chmod +x "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"

    cat > "$TEST_ROOT/scripts/build_instructions.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_ROOT/scripts/build_instructions.sh"

    cat > "$TEST_ROOT/tool.py" <<'EOF'
print("ok")
EOF
    cat > "$TEST_ROOT/instructions/base.md" <<'EOF'
# base
EOF
    cat > "$TEST_ROOT/instructions/generated/base.md" <<'EOF'
# generated
EOF
    cat > "$TEST_ROOT/tests/unit/test_cmd_save.bats" <<'EOF'
#!/usr/bin/env bats
@test "existing cmd_save coverage" {
    [ 1 -eq 1 ]
}
EOF
    cat > "$TEST_ROOT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: idle
EOF
    cat > "$TEST_ROOT/queue/reports/kagemaru_report.yaml" <<'EOF'
status: pending
EOF
    cat > "$TEST_ROOT/logs/hook_failures.yaml" <<'EOF'
[]
EOF

    (
        cd "$TEST_ROOT"
        git init -q
        git config user.email test@example.com
        git config user.name "Test User"
        git add scripts/hooks/git-pre-commit.sh scripts/build_instructions.sh tool.py \
            instructions/base.md instructions/generated/base.md tests/unit/test_cmd_save.bats \
            queue/tasks/kagemaru.yaml queue/reports/kagemaru_report.yaml logs/hook_failures.yaml
        git commit -qm "init"
    )
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

run_hook() {
    run bash -c 'cd "$1" && bash scripts/hooks/git-pre-commit.sh' -- "$TEST_ROOT"
}

@test "blocks yaml dump in staged python additions and records hook failure" {
    cat >> "$TEST_ROOT/tool.py" <<'EOF'
import yaml
yaml.safe_dump(data, open("queue/tasks/test.yaml", "w"))
EOF
    (
        cd "$TEST_ROOT"
        git add tool.py
    )

    run_hook

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED: yaml.dump/yaml.safe_dump detected in staged files"* ]]
    grep -q "hook: pre-commit" "$TEST_ROOT/logs/hook_failures.yaml"
}

@test "ignores yaml dump mentions in tests and comments" {
    mkdir -p "$TEST_ROOT/tests"
    cat > "$TEST_ROOT/tests/helper.py" <<'EOF'
import yaml
yaml.dump(data, open("queue/tasks/test.yaml", "w"))
EOF
    cat >> "$TEST_ROOT/tool.py" <<'EOF'
# yaml.safe_dump(data, open("queue/tasks/test.yaml", "w"))
print("still ok")
EOF
    (
        cd "$TEST_ROOT"
        git add tests/helper.py tool.py
    )

    run_hook

    [ "$status" -eq 0 ]
}

@test "ignores yaml dump text in markdown/yaml files and pre_bash_combined_guard helper" {
    mkdir -p "$TEST_ROOT/projects/infra"
    cat > "$TEST_ROOT/projects/infra/lessons.yaml" <<'EOF'
lessons:
  - id: L999
    summary: "yaml.dumpは運用YAMLで禁止"
EOF
    cat > "$TEST_ROOT/README.md" <<'EOF'
Use `yaml.dump(...)` only as explanatory text here.
EOF
    cat > "$TEST_ROOT/scripts/lib/pre_bash_combined_guard.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "$command" == *'yaml.dump'* || "$command" == *'yaml.safe_dump'* ]]; then
    echo "guard"
fi
EOF
    chmod +x "$TEST_ROOT/scripts/lib/pre_bash_combined_guard.sh"
    (
        cd "$TEST_ROOT"
        git add projects/infra/lessons.yaml README.md scripts/lib/pre_bash_combined_guard.sh
    )

    run_hook

    [ "$status" -eq 0 ]
}

@test "checks generated sync when instructions markdown is staged" {
    cat >> "$TEST_ROOT/instructions/base.md" <<'EOF'
new line
EOF
    (
        cd "$TEST_ROOT"
        git add instructions/base.md
    )

    run_hook

    [ "$status" -eq 0 ]
    [[ "$output" == *"instructions/*.md staged"* ]]
    [[ "$output" == *"generated instructions in sync"* ]]
}

@test "blocks when build_instructions leaves generated files dirty" {
    cat > "$TEST_ROOT/scripts/build_instructions.sh" <<'EOF'
#!/usr/bin/env bash
printf '# regenerated\n' > "$(dirname "$0")/../instructions/generated/base.md"
EOF
    chmod +x "$TEST_ROOT/scripts/build_instructions.sh"
    cat >> "$TEST_ROOT/instructions/base.md" <<'EOF'
another line
EOF
    (
        cd "$TEST_ROOT"
        git add scripts/build_instructions.sh instructions/base.md
    )

    run_hook

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED: Generated instructions out of sync."* ]]
}

@test "blocks queue task yaml mixed with implementation files" {
    cat > "$TEST_ROOT/scripts/lib/context_helper.sh" <<'EOF'
#!/usr/bin/env bash
echo helper
EOF
    cat > "$TEST_ROOT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: in_progress
EOF
    (
        cd "$TEST_ROOT"
        git add scripts/lib/context_helper.sh queue/tasks/kagemaru.yaml
    )

    run_hook

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED: queue/tasks/*.yaml cannot be committed with implementation files"* ]]
    [[ "$output" == *"scripts/lib/context_helper.sh"* ]]
}

@test "allows queue task yaml only commit" {
    cat > "$TEST_ROOT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: acknowledged
EOF
    (
        cd "$TEST_ROOT"
        git add queue/tasks/kagemaru.yaml
    )

    run_hook

    [ "$status" -eq 0 ]
}

@test "allows queue task yaml with operational yaml only" {
    cat > "$TEST_ROOT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  status: done
EOF
    cat > "$TEST_ROOT/queue/reports/kagemaru_report.yaml" <<'EOF'
status: completed
EOF
    cat > "$TEST_ROOT/logs/hook_failures.yaml" <<'EOF'
- hook: pre-commit
EOF
    (
        cd "$TEST_ROOT"
        git add queue/tasks/kagemaru.yaml queue/reports/kagemaru_report.yaml logs/hook_failures.yaml
    )

    run_hook

    [ "$status" -eq 0 ]
}

@test "warns when added bats file has existing script-level candidates" {
    cat > "$TEST_ROOT/tests/unit/test_cmd_save_new_rule.bats" <<'EOF'
#!/usr/bin/env bats
@test "new cmd_save rule" {
    bash scripts/cmd_save.sh --help >/dev/null 2>&1 || true
}
EOF
    (
        cd "$TEST_ROOT"
        git add tests/unit/test_cmd_save_new_rule.bats
    )

    run_hook

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: new test_*.bats file may duplicate existing script-level tests."* ]]
    [[ "$output" == *"added: tests/unit/test_cmd_save_new_rule.bats"* ]]
    [[ "$output" == *"candidate: tests/unit/test_cmd_save.bats"* ]]
}
