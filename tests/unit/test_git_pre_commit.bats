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
        "$TEST_ROOT/instructions/generated" "$TEST_ROOT/tests"

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
    mkdir -p "$TEST_ROOT/logs"

    (
        cd "$TEST_ROOT"
        git init -q
        git config user.email test@example.com
        git config user.name "Test User"
        git add scripts/hooks/git-pre-commit.sh scripts/build_instructions.sh tool.py \
            instructions/base.md instructions/generated/base.md
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
