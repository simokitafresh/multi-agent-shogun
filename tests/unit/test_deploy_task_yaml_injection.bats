#!/usr/bin/env bats
# Regression tests for deploy_task.sh manual YAML injection.

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    python3 -c "import yaml" 2>/dev/null || return 1
}

@test "cmd_2801: _sv multiline scalar indent follows nesting depth" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys
import yaml

script = open(sys.argv[1], encoding="utf-8").read()
start = script.index("def _sv(v, multiline_indent=2):")
end = script.index("frag = '\\n'.join(_yaml_lines('acceptance_criteria'", start)
namespace = {}
exec(script[start:end], namespace)

value = [
    {
        "id": "AC1",
        "checks": [
            {
                "check": "line1\nline2",
                "meta": {"detail": "nested1\nnested2"},
            }
        ],
    }
]
fragment = "\n".join(namespace["_yaml_lines"]("acceptance_criteria", value))
text = "task:\n" + "\n".join("  " + line for line in fragment.split("\n")) + "\n"
data = yaml.safe_load(text)

check = data["task"]["acceptance_criteria"][0]["checks"][0]["check"]
detail = data["task"]["acceptance_criteria"][0]["checks"][0]["meta"]["detail"]
assert check == "line1\nline2", text
assert detail == "nested1\nnested2", text
PY
}

@test "cmd_2801: all deploy_task manual YAML serializers use depth-aware _sv" {
    run grep -c "def _sv(v, multiline_indent=2):" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]

    grep -q "_sv(val, ind + 2)" "$PROJECT_ROOT/scripts/deploy_task.sh"
    grep -q "_sv(item, ind + 2)" "$PROJECT_ROOT/scripts/deploy_task.sh"
    grep -q "sv = _sv(v, ind + 4)" "$PROJECT_ROOT/scripts/deploy_task.sh"
}

@test "cmd_2801: YAML injection failures log ERROR and notify karo" {
    grep -q 'handle_yaml_injection_failure()' "$PROJECT_ROOT/scripts/deploy_task.sh"
    grep -q 'log "ERROR: ${injector_name} failed' "$PROJECT_ROOT/scripts/deploy_task.sh"
    grep -q 'safe_inbox_write "karo" "$message" "deploy_error" "deploy_task"' "$PROJECT_ROOT/scripts/deploy_task.sh"
    grep -q 'inject_related_lessons "$task_file" || handle_yaml_injection_failure "inject_related_lessons"' "$PROJECT_ROOT/scripts/deploy_task.sh"
    grep -q 'inject_ninja_weak_points "$task_file" "$ninja_name" || handle_yaml_injection_failure "inject_ninja_weak_points"' "$PROJECT_ROOT/scripts/deploy_task.sh"
}

@test "task YAML syntax guard stops before report template and task_assigned nudge" {
    tmpdir="$(mktemp -d)"
    task_file="$tmpdir/task.yaml"
    cat > "$task_file" <<'YAML'
task:
  parent_cmd: cmd_bad_yaml
  status: assigned
  notes: 家老一次確認:
    phase 1: copy yaml
    phase 2: mutate fields
YAML

    run bash -lc "
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        log() { printf '%s\n' \"LOG:\$*\"; }
        safe_inbox_write() { printf 'INBOX target=%s type=%s from=%s msg=%s\n' \"\$1\" \"\$3\" \"\$4\" \"\$2\"; }
        deploy_task_guard_task_yaml_syntax post_injection_pre_report_template '$task_file' sasuke
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"INBOX target=karo type=deploy_error from=deploy_task"* ]]
    [[ "$output" == *"task_assigned送信・report template生成・draft review送信を停止"* ]]
}

@test "task YAML syntax guard is ordered before report template generation" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys

script = open(sys.argv[1], encoding="utf-8").read()
main_start = script.index("deploy_task_apply_task_mutations() {")
main = script[main_start:]

guard_idx = main.index('deploy_task_guard_task_yaml_syntax "post_injection_pre_report_template"')
report_idx = main.index('generate_report_template "$ninja_name"')

assert guard_idx < report_idx, (guard_idx, report_idx)
PY
}

@test "postcondition_lesson_inject consumes current deploy postcondition after lesson injection and score update" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys

script = open(sys.argv[1], encoding="utf-8").read()
main_start = script.index("deploy_task_apply_task_mutations() {")
main = script[main_start:]

inject_idx = main.index('inject_related_lessons "$task_file"')
score_idx = main.index('bash "$SCRIPT_DIR/scripts/lesson_update_score.sh" "$inj_project" "$lid" inject')
post_idx = main.index('postcondition_lesson_inject "$task_file"')

assert inject_idx < score_idx < post_idx, (inject_idx, score_idx, post_idx)
PY
}

@test "direct --yaml repairs unquoted multiline notes before task mutations" {
    tmpdir="$(mktemp -d)"
    task_file="$tmpdir/task.yaml"
    cat > "$task_file" <<'YAML'
task:
  parent_cmd: cmd_multiline_notes
  status: assigned
  notes: 家老一次確認:
    phase 1: copy yaml
    phase 2: mutate fields
  target_path: scripts/deploy_task.sh
YAML

    run bash -lc "
        set -e
        SCRIPT_DIR='$PROJECT_ROOT'
        LOG='$tmpdir/deploy.log'
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        deploy_task_validate_or_repair_direct_yaml '$task_file' '$task_file'
        yaml_field_set '$task_file' task status assigned
        python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1], encoding=\"utf-8\"))' '$task_file'
    "
    [ "$status" -eq 0 ]

    python3 - "$task_file" <<'PY'
import sys
import yaml

task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert "phase 1: copy yaml" in task["notes"], task
assert task["status"] == "assigned", task
PY
}

@test "direct --yaml keeps source ACs without cmd-source overwrite" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys

script = open(sys.argv[1], encoding="utf-8").read()
needle = 'if [ "${DIRECT_MODE:-false}" = true ] && [ -n "${YAML_FILE:-}" ]; then'
idx = script.index(needle)
window = script[idx:idx + 1200]
assert "keeping source YAML ACs without cmd-source overwrite" in window, window
assert "_overwrite_ac_from_cmd" in window, "non-direct fallback must still overwrite from cmd source"
PY
}

@test "direct --yaml detects preinjected task YAML only when all safety fields exist" {
    tmpdir="$(mktemp -d)"
    task_file="$tmpdir/task.yaml"
    cat > "$task_file" <<'YAML'
task:
  parent_cmd: cmd_preinjected
  status: assigned
  report_filename: sasuke_report_cmd_preinjected.yaml
  related_lessons:
  - id: L001
    summary: injected
  semantic_concepts:
  - agent_formation_management
  standard_skills:
  - report-write
  memory_db_context:
  - "2026-07-02 | context"
  context_hints:
  - context/infrastructure.md
YAML

    run bash -lc "
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        DIRECT_MODE=true
        deploy_task_direct_yaml_is_preinjected '$task_file'
    "
    [ "$status" -eq 0 ]

    python3 - "$task_file" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace('  memory_db_context:\n  - "2026-07-02 | context"\n', '')
path.write_text(text)
PY

    run bash -lc "
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        DIRECT_MODE=true
        deploy_task_direct_yaml_is_preinjected '$task_file'
    "
    [ "$status" -ne 0 ]
}

@test "direct --yaml preinjected fast path preserves injected metadata and skips heavy reinjection block" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys

script = open(sys.argv[1], encoding="utf-8").read()
main_start = script.index("deploy_task_apply_task_mutations() {")
main = script[main_start:]

preserve_idx = main.index('direct_mode: preserving preinjected task metadata')
skip_idx = main.index('direct_mode: preinjected task YAML detected; skipping heavy context/lesson/semantic reinjection')
heavy_idx = main.index('inject_memory_db_context "$task_file"')
report_idx = main.index('generate_report_template "$ninja_name"')

assert preserve_idx < skip_idx < heavy_idx < report_idx, (preserve_idx, skip_idx, heavy_idx, report_idx)
assert 'postcondition_lesson_inject "$task_file" || true\n    fi\n\n    if [ "${DEPLOY_TASK_DIRECT_YAML_PREINJECTED:-0}" != "1" ]; then' in main
PY
}

@test "parallel recon duplicate guard allows different peer task_id before active duplicate BLOCK" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys

script = open(sys.argv[1], encoding="utf-8").read()
needle = 'for dd_task in "$SCRIPT_DIR/queue/tasks/"*.yaml; do'
start = script.index(needle)
window = script[start:start + 2600]

parallel_idx = window.index('parallel_recon: ${deploy_parent_cmd} peer ${dd_ninja}')
block_idx = window.index('BLOCK: ${deploy_parent_cmd} is already assigned to ${dd_ninja}')
same_id_idx = window.index('if [ -n "$deploy_task_id" ] && [ "$deploy_scope_mode" != "exact" ]; then')

assert parallel_idx < same_id_idx < block_idx, (parallel_idx, same_id_idx, block_idx)
assert '[[ "$deploy_scope_mode" =~ ^(recon|scout)$ ]]' in window, window
assert '[ "$deploy_task_id" != "$dd_tid" ]' in window, window
PY
}

@test "cmd_3368: reset_stale_fields clears auto-injected scalar/list metadata before YAML injection" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import ast
import re
import sys

script = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"STALE_FIELDS = \[(.*?)\n\]", script, re.S)
assert match, "STALE_FIELDS block not found"
fields = {
    node.value
    for node in ast.walk(ast.parse("FIELDS = [" + match.group(1) + "\n]"))
    if isinstance(node, ast.Constant) and isinstance(node.value, str)
}

required = {
    "hypothesis_count",
    "three_strike_rule",
    "growth_loop_defense",
    "semantic_concepts",
    "standard_skills",
    "memory_db_context",
    "related_causal_links",
    "production_invariants",
}
missing = required - fields
assert not missing, f"missing stale reset fields: {sorted(missing)}"
PY
}

@test "memory_db_context injection quotes double and single quotes safely" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/scripts"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_quote
  task_id: cmd_quote_impl
  status: assigned
  purpose: "ontology quote regression"
YAML
    cat > "$tmpdir/scripts/memory_db_query.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '2026-06-20 | 殿: "オントロジー" and can'\''t stop'
EOF
    chmod +x "$tmpdir/scripts/memory_db_query.sh"
    cat > "$tmpdir/run_inject.sh" <<EOF
#!/usr/bin/env bash
set -e
SCRIPT_DIR="$tmpdir"
log() { :; }
$(sed -n '/^inject_memory_db_context()/,/^}/p' "$PROJECT_ROOT/scripts/deploy_task.sh")
inject_memory_db_context "$tmpdir/queue/tasks/sasuke.yaml"
EOF
    chmod +x "$tmpdir/run_inject.sh"

    run bash "$tmpdir/run_inject.sh"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

ctx = task.get('memory_db_context') or []
assert ctx == ['2026-06-20 | 殿: "オントロジー" and can\'t stop'], ctx
PY
}

@test "cmd_3300: deploy_task injects command readonly refs into task YAML" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue" "$tmpdir/scripts/lib"
    cp "$PROJECT_ROOT/scripts/lib/field_get.sh" "$tmpdir/scripts/lib/field_get.sh"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_readonly
  task_id: cmd_readonly_full
  status: assigned
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_readonly:
    command: |
      refactor-workorder-20260611.md を必読参照し、backend/app/api/main.py を修正する。
YAML

    cat > "$tmpdir/run_inject.sh" <<EOF
#!/usr/bin/env bash
set -e
SCRIPT_DIR="$tmpdir"
source "$tmpdir/scripts/lib/field_get.sh"
log() { :; }
$(sed -n '/^inject_readonly_refs()/,/^}/p' "$PROJECT_ROOT/scripts/deploy_task.sh")
inject_readonly_refs "$tmpdir/queue/tasks/sasuke.yaml"
EOF
    chmod +x "$tmpdir/run_inject.sh"

    run bash "$tmpdir/run_inject.sh"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

refs = task.get('readonly_ref') or []
assert refs, task
assert refs[0]['path'] == 'refactor-workorder-20260611.md', refs
assert '必読' in refs[0]['reason'], refs
PY
}

@test "db backup controls: DB cmd injects stop_for and backup instructions" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_db
  task_id: cmd_db_impl
  status: assigned
  description: "DB schema変更を実装する"
  acceptance_criteria:
  - id: AC1
    description: "schema変更が完了する"
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_db:
    command: |
      ALTER TABLE users ADD COLUMN status TEXT;
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="db_backup_controls" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

assert 'バックアップなしのDB変更' in task['stop_for'], task
assert '【DB変更前バックアップ必須】' in task['description'], task['description']
PY
}

@test "recon task modifier injects report-write examples into task YAML" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_recon_examples
  task_id: cmd_recon_examples_scout
  status: assigned
  task_type: scout
  description: "既存依存導線を確認する"
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" \
        SCRIPT_DIR_ENV="$tmpdir" \
        INJECT_TASK_MODIFIERS_ONLY="recon_task_template" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

desc = task.get('description', '')
assert '【report-write quick examples】' in desc, desc
assert 'verified_existing_dependency -' in desc, desc
assert 'memory_references -' in desc, desc
assert task.get('hypothesis_count') == 3, task
PY
}

@test "db backup controls: non-DB cmd does not inject stop_for" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_docs
  task_id: cmd_docs_impl
  status: assigned
  description: "dashboard.mdの文言を更新する"
  acceptance_criteria:
  - id: AC1
    description: "文言が更新される"
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_docs:
    command: |
      dashboard.mdの表示文言を更新する
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="db_backup_controls" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

assert 'stop_for' not in task, task
assert '【DB変更前バックアップ必須】' not in task['description'], task['description']
PY
}
