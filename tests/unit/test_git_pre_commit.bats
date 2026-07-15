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
        "$TEST_ROOT/context" "$TEST_ROOT/projects/infra" \
        "$TEST_ROOT/queue/tasks" "$TEST_ROOT/queue/reports" "$TEST_ROOT/logs"

    cp "$SOURCE_HOOK" "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"
    chmod +x "$TEST_ROOT/scripts/hooks/git-pre-commit.sh"

    cat > "$TEST_ROOT/scripts/build_instructions.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_ROOT/scripts/build_instructions.sh"
    cat > "$TEST_ROOT/scripts/semantic_index_update.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "$1" "$2" >> logs/semantic_index_update.calls
EOF
    chmod +x "$TEST_ROOT/scripts/semantic_index_update.sh"
    cat > "$TEST_ROOT/scripts/semantic_map_generate.sh" <<'EOF'
#!/usr/bin/env bash
printf 'semantic_map_generate\n' >> logs/semantic_map_generate.calls
EOF
    chmod +x "$TEST_ROOT/scripts/semantic_map_generate.sh"

    cat > "$TEST_ROOT/tool.py" <<'EOF'
print("ok")
EOF
    cat > "$TEST_ROOT/instructions/base.md" <<'EOF'
# base
EOF
    cat > "$TEST_ROOT/instructions/generated/base.md" <<'EOF'
# generated
EOF
    cat > "$TEST_ROOT/context/infrastructure.md" <<'EOF'
# infra context
EOF
    cat > "$TEST_ROOT/projects/infra.yaml" <<'EOF'
project:
  id: infra
EOF
    cat > "$TEST_ROOT/projects/infra/lessons.yaml" <<'EOF'
lessons: []
EOF
    cat > "$TEST_ROOT/tests/unit/test_cmd_save.bats" <<'EOF'
#!/usr/bin/env bats
EOF
    # Written via string concatenation, not a literal heredoc line: bats-core's
    # test-plan preprocessor naively regex-scans raw file text for `@test "..." {`
    # with no heredoc-quoting awareness, so a literal fixture line here would be
    # miscounted as a phantom top-level test in THIS file (inflated plan count,
    # then "bats: unknown test name" when it tries to run the phantom).
    printf '%s\n' '@'"test \"existing cmd_save coverage\" {" '    [ 1 -eq 1 ]' '}' >> "$TEST_ROOT/tests/unit/test_cmd_save.bats"
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
        git add scripts/hooks/git-pre-commit.sh scripts/build_instructions.sh \
            scripts/semantic_index_update.sh scripts/semantic_map_generate.sh tool.py \
            instructions/base.md instructions/generated/base.md tests/unit/test_cmd_save.bats \
            context/infrastructure.md projects/infra.yaml projects/infra/lessons.yaml \
            queue/tasks/kagemaru.yaml queue/reports/kagemaru_report.yaml logs/hook_failures.yaml
        git commit -qm "init"
    )
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

run_hook() {
    run bash -c 'cd "$1" && SEMANTIC_HOOK_SYNC=1 bash scripts/hooks/git-pre-commit.sh' -- "$TEST_ROOT"
}

@test "blocks yaml dump in staged python additions and records hook failure" {
    cat >> "$TEST_ROOT/tool.py" <<'EOF'
import yaml
yaml.safe_dump(data, open("queue/tasks/test.yaml", "w"))
EOF
    (
        cd "$TEST_ROOT"
        : > logs/hook_failures.yaml
        git add tool.py
    )

    run_hook

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCKED: yaml.dump/yaml.safe_dump detected in staged files"* ]]
    grep -q "hook: pre-commit" "$TEST_ROOT/logs/hook_failures.yaml"
}

@test "records hook failure detail as parseable YAML when stderr contains backslash quote" {
    cat >> "$TEST_ROOT/tool.py" <<'EOF'
import yaml
yaml.safe_dump({"bad": "\\'"}, open("queue/tasks/test.yaml", "w"))
EOF
    (
        cd "$TEST_ROOT"
        : > logs/hook_failures.yaml
        git add tool.py
    )

    run_hook

    [ "$status" -eq 1 ]
    python3 - <<PY
import yaml
with open("$TEST_ROOT/logs/hook_failures.yaml", encoding="utf-8") as f:
    data = yaml.safe_load(f)
assert isinstance(data, list)
assert data[-1]["hook"] == "pre-commit"
assert "\\\\'" in data[-1]["detail"]
PY
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

@test "GP-136 blocks all operational YAML write sinks and reports targets" {
    cat >> "$TEST_ROOT/tool.py" <<'EOF'
import yaml
from pathlib import Path
task_path = "queue/tasks/direct.yaml"
report_path = Path("queue/reports/path-open.yaml")
log_path = Path("logs/events.yaml")
with open(task_path, "w") as task_out:
    yaml.dump({"status": "bad"}, task_out)
report_out = report_path.open(mode="a")
yaml.safe_dump({"status": "bad"}, stream=report_out)
log_path.write_text(yaml.dump_all([{"bad": True}]))
EOF
    (cd "$TEST_ROOT" && git add tool.py)

    run_hook

    [ "$status" -eq 1 ]
    [[ "$output" == *"target=queue/tasks/direct.yaml"* ]]
    [[ "$output" == *"target=queue/reports/path-open.yaml"* ]]
    [[ "$output" == *"target=logs/events.yaml"* ]]
}

@test "GP-136 permits StringIO stdout and serialized print projections without operational mutation" {
    before="$(sha256sum "$TEST_ROOT/queue/tasks/kagemaru.yaml" | cut -d' ' -f1)"
    cat >> "$TEST_ROOT/tool.py" <<'EOF'
import io
import sys
import yaml
memory = io.StringIO()
yaml.dump({"projection": True}, memory)
yaml.safe_dump({"projection": True}, sys.stdout)
print(yaml.dump({"projection": True}))
EOF
    (cd "$TEST_ROOT" && git add tool.py)

    run_hook

    [ "$status" -eq 0 ]
    after="$(sha256sum "$TEST_ROOT/queue/tasks/kagemaru.yaml" | cut -d' ' -f1)"
    [ "$before" = "$after" ]
}

@test "GP-136 follows quoted heredoc and distinct path and sink variables" {
    cat >> "$TEST_ROOT/tool.py" <<'PYEOF'
import yaml
destination = 'queue/tasks/heredoc.yaml'
handle = open(destination, 'x')
yaml.dump_all([{"status": "bad"}], handle)
PYEOF
    (cd "$TEST_ROOT" && git add tool.py)

    run_hook

    [ "$status" -eq 1 ]
    [[ "$output" == *"target=queue/tasks/heredoc.yaml"* ]]
    [[ "$output" == *"yaml.dump_all -> write-capable sink"* ]]
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

@test "auto-fixes and stages generated files when build_instructions leaves them dirty (GA-190)" {
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

    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIX: generated instructions were out of sync"* ]]
    [[ "$output" == *"staged: instructions/generated/base.md"* ]]
    run bash -c 'cd "$1" && git diff --cached --name-only' -- "$TEST_ROOT"
    [[ "$output" == *"instructions/generated/base.md"* ]]
}

@test "still blocks when build_instructions.sh itself fails" {
    cat > "$TEST_ROOT/scripts/build_instructions.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
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
    [[ "$output" == *"BLOCKED: build_instructions.sh failed"* ]]
}

@test "GA-222: does not commit unrelated dirty generated content from another source pair" {
    # Independent second source+generated pair, unrelated to base.md
    cat > "$TEST_ROOT/instructions/extra.md" <<'EOF'
# extra source
EOF
    cat > "$TEST_ROOT/instructions/generated/extra.md" <<'EOF'
# extra generated
EOF
    (
        cd "$TEST_ROOT"
        git add instructions/extra.md instructions/generated/extra.md
        git commit -qm "add unrelated extra source+generated pair"
    )

    # Capture base.md's current canonical generated content (may already have been
    # regenerated by an earlier test in this cumulative TEST_ROOT) so this stub
    # reproduces "source unchanged -> identical regen output", independent of test order.
    base_generated_current="$(cat "$TEST_ROOT/instructions/generated/base.md")"

    # build_instructions.sh regenerates ALL generated files from their (unchanged) canonical source
    cat > "$TEST_ROOT/scripts/build_instructions.sh" <<EOF
#!/usr/bin/env bash
dir="\$(dirname "\$0")/.."
cat > "\$dir/instructions/generated/base.md" <<'BASEEOF'
${base_generated_current}
BASEEOF
printf '# extra generated\n' > "\$dir/instructions/generated/extra.md"
EOF
    chmod +x "$TEST_ROOT/scripts/build_instructions.sh"

    # Only base.md source actually changes and is staged for this commit
    cat >> "$TEST_ROOT/instructions/base.md" <<'EOF'
ninja change
EOF
    (
        cd "$TEST_ROOT"
        git add instructions/base.md
    )

    # Meanwhile extra.md's generated file has an unrelated, uncommitted WIP edit
    # (e.g. hand-edited directly by another agent), unrelated to this base.md change
    cat >> "$TEST_ROOT/instructions/generated/extra.md" <<'EOF'
UNRELATED_DIRTY_WIP_FROM_OTHER_AGENT
EOF

    run_hook

    [ "$status" -eq 0 ]
    [[ "$output" == *"generated instructions in sync"* || "$output" == *"AUTO-FIX"* ]]
    run bash -c 'cd "$1" && git show :instructions/generated/extra.md' -- "$TEST_ROOT"
    [[ "$output" != *"UNRELATED_DIRTY_WIP_FROM_OTHER_AGENT"* ]]
    [[ "$output" == *"extra generated"* ]]
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

@test "allows yaml.dump in scripts/lib/yaml_atomic.py (GA-101: centralized dump)" {
    mkdir -p "$TEST_ROOT/scripts/lib"
    cat > "$TEST_ROOT/scripts/lib/yaml_atomic.py" <<'EOF'
"""Atomic YAML rewrite helper. Direct PyYAML dumps are intentionally centralized here."""
import yaml

def atomic_yaml_write(path, data):
    yaml.dump(data, open(path, "w"))
EOF
    (
        cd "$TEST_ROOT"
        git add scripts/lib/yaml_atomic.py
    )

    run_hook

    [ "$status" -eq 0 ]
}

@test "warns when added bats file has existing script-level candidates" {
    cat > "$TEST_ROOT/tests/unit/test_cmd_save_new_rule.bats" <<'EOF'
#!/usr/bin/env bats
EOF
    # See setup()'s test_cmd_save.bats fixture for why this can't be a literal
    # heredoc @test line (bats-core preprocessor miscounts it as a phantom test
    # in THIS file).
    printf '%s\n' '@'"test \"new cmd_save rule\" {" '    bash scripts/cmd_save.sh --help >/dev/null 2>&1 || true' '}' >> "$TEST_ROOT/tests/unit/test_cmd_save_new_rule.bats"
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

@test "does not warn for dedicated test added with matching new production script" {
    cat > "$TEST_ROOT/scripts/new_worker.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_ROOT/tests/unit/test_new_worker.bats" <<'EOF'
#!/usr/bin/env bats
EOF
    # Include an existing shared-script reference that used to trigger the
    # broad candidate scan despite the new worker/test one-to-one pairing.
    printf '%s\n' '@'"test \"new worker\" {" '    bash scripts/new_worker.sh' '    bash scripts/cmd_save.sh --help >/dev/null 2>&1 || true' '}' >> "$TEST_ROOT/tests/unit/test_new_worker.bats"
    (
        cd "$TEST_ROOT"
        git add scripts/new_worker.sh tests/unit/test_new_worker.bats
    )

    run_hook

    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN: new test_*.bats file may duplicate existing script-level tests."* ]]
}

@test "runs semantic propagation when context files are staged" {
    cat >> "$TEST_ROOT/context/infrastructure.md" <<'EOF'
new context line
EOF
    (
        cd "$TEST_ROOT"
        git add context/infrastructure.md
    )

    run_hook

    [ "$status" -eq 0 ]
    grep -q '^discussion' "$TEST_ROOT/logs/semantic_index_update.calls"
    grep -q 'context/infrastructure.md' "$TEST_ROOT/logs/semantic_index_update.calls"
    grep -q '^semantic_map_generate$' "$TEST_ROOT/logs/semantic_map_generate.calls"
}

@test "runs semantic propagation when project yaml files are staged" {
    cat >> "$TEST_ROOT/projects/infra.yaml" <<'EOF'
description: updated
EOF
    (
        cd "$TEST_ROOT"
        git add projects/infra.yaml
    )

    run_hook

    [ "$status" -eq 0 ]
    grep -q '^discussion' "$TEST_ROOT/logs/semantic_index_update.calls"
    grep -q 'projects/infra.yaml' "$TEST_ROOT/logs/semantic_index_update.calls"
    grep -q '^semantic_map_generate$' "$TEST_ROOT/logs/semantic_map_generate.calls"
}
