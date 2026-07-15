#!/usr/bin/env bats
# Regression tests for deploy_task.sh manual YAML injection.

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    python3 -c "import yaml" 2>/dev/null || return 1
}

@test "cmd_3855: L159 is not blanket-injected into every recon task" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys

script = open(sys.argv[1], encoding="utf-8").read()
assert "RECON_LESSON_IDS = {'L219', 'L211', 'L213', 'L104', 'L129', 'L128'}" in script
assert "RECON_LESSON_IDS.add('L159')" in script
assert "_l159_trigger_terms" in script
PY
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

@test "direct --yaml caller role_reminder survives post-publication field clear" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import re
import sys

script = open(sys.argv[1], encoding="utf-8").read()
main = script[script.index("deploy_task_apply_task_mutations() {"):]
clear = re.search(r'clear_fields="([^"]+)"', main)
assert clear, "post-publication clear_fields not found"
assert "role_reminder" not in clear.group(1).split("|"), clear.group(1)

# The old destination task is still sanitized before --yaml publication, so
# preserving the new source value cannot leak the previous task's reminder.
stale = re.search(r"STALE_FIELDS = \[(.*?)\n\]", script, re.S)
assert stale and "'role_reminder'" in stale.group(1)
PY
}

@test "independent recon injects fixed base and shared-context embargo before nudge" {
    tmpdir="$(mktemp -d)"
    task_file="$tmpdir/task.yaml"
    cat > "$task_file" <<YAML
task:
  parent_cmd: cmd_dual_recon2
  title: independent recon Track B
  purpose: 独立2系統で方式を比較する
  project: infra
  target_path: $PROJECT_ROOT
YAML

    run bash -lc "
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        inject_independent_recon_contract '$task_file' kotaro
    "
    [ "$status" -eq 0 ]

    run python3 - "$task_file" "$PROJECT_ROOT" <<'PY'
import subprocess, sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
head = subprocess.check_output(["git", "-C", sys.argv[2], "rev-parse", "HEAD"], text=True).strip()
assert task["independence_group"] == "cmd_dual", task
assert task["independence_track"] == "B2", task
assert task["independence_base_commit"] == head, task
assert task["independence_worktree_required"] is True, task
assert task["shared_context_embargo"] == "karo_release_required", task
assert "共有context" in task["role_reminder"], task
PY
    [ "$status" -eq 0 ]
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

@test "workaround lesson description preserves regex backslashes as printable text" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("def sync_description(description, related):")
end = source.index("\ntry:\n", start)
namespace = {"re": re}
exec(source[start:end], namespace)

result = namespace["sync_description"](
    "【注入教訓】 old\n──────────\nbody",
    [{"id": "L1020", "summary": r"日本語隣接語は\bpush\bで検出できない"}],
)
assert "\x08" not in result, repr(result)
assert r"\bpush\b" in result, repr(result)
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

@test "cmd_3970 regression: update-trigger analysis is readonly while design artifact remains writable" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue" "$tmpdir/scripts/lib"
    cp "$PROJECT_ROOT/scripts/lib/field_get.sh" "$tmpdir/scripts/lib/field_get.sh"
    cat > "$tmpdir/queue/tasks/hayate.yaml" <<'YAML'
task:
  parent_cmd: cmd_3970
  task_id: cmd_3970_full
  status: assigned
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_3970:
    command: |
      daemon_supervisor.sh・restart_watchers.shのコード現物を読み、呼出し関係を整理する。一本化の設計案をdocs/research/daemon_p4_entry_point_design_20260715.mdに記録する
      gist_sync.shと戦況artifact HTMLの更新トリガー・対象・頻度を整理し統合・分離案を記録する。daemon_watchdog.logとninja_monitor.logから復旧速度実測値を抽出しSLA・RTO数値案を算出して同ファイルに追記する
YAML

    cat > "$tmpdir/run_inject.sh" <<EOF
#!/usr/bin/env bash
set -e
SCRIPT_DIR="$tmpdir"
source "$tmpdir/scripts/lib/field_get.sh"
log() { :; }
$(sed -n '/^inject_readonly_refs()/,/^}/p' "$PROJECT_ROOT/scripts/deploy_task.sh")
inject_readonly_refs "$tmpdir/queue/tasks/hayate.yaml"
EOF
    chmod +x "$tmpdir/run_inject.sh"

    run bash "$tmpdir/run_inject.sh"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/hayate.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

paths = {row['path'] for row in task.get('readonly_ref') or []}
expected = {
    'daemon_supervisor.sh',
    'restart_watchers.sh',
    'gist_sync.sh',
    'daemon_watchdog.log',
    'ninja_monitor.log',
}
assert expected <= paths, (expected, paths)
assert 'docs/research/daemon_p4_entry_point_design_20260715.md' not in paths, paths
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

@test "LS-A16 controls: DM-Signal recalculate cmd injects production parity ACs" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_recalc
  project: dm-signal
  task_id: cmd_recalc_impl
  status: assigned
  description: "holding_signalを更新する"
  acceptance_criteria:
  - id: AC1
    description: "更新が完了する"
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_recalc:
    project: dm-signal
    command: |
      本番DB変更後にfullrecalculateを実行する
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="lsa16_production_parity_controls" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

assert '本番パリティ未確認' in task['stop_for'], task
assert '【LS-A16 本番パリティ必須】' in task['description'], task['description']
ac_text = '\n'.join(ac['description'] for ac in task['acceptance_criteria'])
assert 'DB/API/FEの3レイヤー貫通確認結果' in ac_text, ac_text
assert 'fullrecalculateまたは差分確認' in ac_text, ac_text
assert 'savepoint(begin_nested)' in ac_text, ac_text
PY
}

@test "LS-A16 controls: mapping-form ACs retain ids and descriptions before appended controls" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_recalc_mapping
  project: dm-signal
  task_id: cmd_recalc_mapping_impl
  status: assigned
  purpose: "本番fullrecalculateを厳密1run実行する"
  acceptance_criteria:
    AC1:
      description: "直前snapshotと復元経路を確認する"
    AC2:
      description: "本番runをexpected artifactへexact照合する"
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands: {}
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="lsa16_production_parity_controls" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

acs = task['acceptance_criteria']
assert [ac['id'] for ac in acs[:2]] == ['AC1', 'AC2'], acs
assert acs[0]['description'] == '直前snapshotと復元経路を確認する', acs
assert acs[1]['description'] == '本番runをexpected artifactへexact照合する', acs
assert len(acs) == 5, acs
assert all(isinstance(ac, dict) and ac.get('description') for ac in acs), acs
PY
}

@test "LS-A16 controls: non DM-Signal recalculate mention does not inject" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_docs
  project: infra
  task_id: cmd_docs_impl
  status: assigned
  description: "recalculateという語を含む文書を更新する"
  acceptance_criteria:
  - id: AC1
    description: "文書が更新される"
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="lsa16_production_parity_controls" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

assert 'stop_for' not in task, task
assert '【LS-A16 本番パリティ必須】' not in task['description'], task['description']
assert len(task['acceptance_criteria']) == 1, task['acceptance_criteria']
PY
}

@test "documentation-only DM-Signal task does not receive DB parity operation gates" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_docs_db_history
  project: dm-signal
  target_path:
  - docs/research/nondeterminism.md
  task_id: cmd_docs_db_history_impl
  status: assigned
  purpose: "本番DB fullrecalculateとparityの過去証跡を文書に追記する"
  description: "restore-allとDB schemaの反例履歴を更新する"
  acceptance_criteria:
  - id: AC1
    description: "文書が更新される"
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_docs_db_history:
    project: dm-signal
    command: |
      本番DB変更後のfullrecalculateとtarget_date parityを文書化する
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="db_backup_controls,lsa16_production_parity_controls,parity_target_date_ac" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

assert [ac['id'] for ac in task['acceptance_criteria']] == ['AC1'], task
assert 'stop_for' not in task, task
assert '【DB変更前バックアップ必須】' not in task['description'], task
assert '【LS-A16 本番パリティ必須】' not in task['description'], task
PY
}

# ── cmd_karo_hotfix_split_ac_modifier_scope_202607131307 回帰テスト ──
# Origin: cmd_3873実配備で、assigned_acs=[AC1,AC2]の分割taskへ
# inject_lsa16_production_parity_controls/inject_parity_target_date_acが
# 汎用AC(AC3-AC6)を無条件追加し、task AC idsが親cmd AC集合を超えて
# inject_parent_contractのparent mapping検証を偽BLOCKした。
@test "cmd_3873: split task with assigned_acs does not receive generic parity/target_date ACs" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_3873_test
  project: dm-signal
  task_id: cmd_3873_test_impl
  status: assigned
  purpose: "P4 AC2再挑戦の前提としてfullrecalculate入力のbundle consumerを実装しparityを確認する"
  description: "本番DB fullrecalculate系cmdの分割task"
  assigned_acs:
  - AC1
  - AC2
  acceptance_criteria:
  - id: AC1
    description: "bundle exportを実装する"
  - id: AC2
    description: "manifest payloadを保存する"
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_3873_test:
    project: dm-signal
    title: "parity検証cmd"
    command: |
      本番DB fullrecalculateとparity確認を行う
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="lsa16_production_parity_controls,parity_target_date_ac" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

# 安全ACは分割task境界を超えて混入させない: AC数は変更前と同じ2のまま
assert [ac['id'] for ac in task['acceptance_criteria']] == ['AC1', 'AC2'], task['acceptance_criteria']
# stop_for/description注記は分割taskでも維持する(安全情報自体は削らない)
assert '本番パリティ未確認' in task['stop_for'], task
assert '【LS-A16 本番パリティ必須】' in task['description'], task['description']
PY
}

@test "cmd_3873: non-split DM-Signal parity cmd still receives full safety AC set" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_3873_test_normal
  project: dm-signal
  task_id: cmd_3873_test_normal_impl
  status: assigned
  purpose: "本番DB fullrecalculateのparity確認を行う"
  description: "本番DB fullrecalculate系cmd"
  acceptance_criteria:
  - id: AC1
    description: "bundle exportを実装する"
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_3873_test_normal:
    project: dm-signal
    title: "parity検証cmd"
    command: |
      本番DB fullrecalculateとparity確認を行う
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="lsa16_production_parity_controls,parity_target_date_ac" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

# assigned_acsが無い(非分割)通常taskでは既存の安全AC注入(3レイヤー確認/fullrecalculate/savepoint/target_date)を維持する
ac_text = '\n'.join(ac['description'] for ac in task['acceptance_criteria'])
assert 'DB/API/FEの3レイヤー貫通確認結果' in ac_text, ac_text
assert 'fullrecalculateまたは差分確認' in ac_text, ac_text
assert 'savepoint(begin_nested)' in ac_text, ac_text
assert 'target_dateがproduction fullrecalculateと同一であること' in ac_text, ac_text
assert len(task['acceptance_criteria']) == 5, task['acceptance_criteria']
PY
}

# ── cmd_karo_hotfix_split_ac_modifier_scope_202607131307 回帰テスト(第2弾) ──
# Origin: karo RC — 本cmd自身のqueue/tasks/kotaro.yaml(project: infra,
# target_path: scripts/deploy_task.sh)がLSA16+target_date AC 4件を誤混入された。
# 原因はis_dm_signal判定がproject/target_pathではなくdescription/purpose等の
# 自由文に対する"DM-Signal"文字列一致だったため。本taskの説明文がcmd_3873
# (DM-Signalのfixture)へ言及しただけでinfra taskがDM-Signal scopeと誤認された。
@test "cmd_karo_hotfix_split_ac_modifier_scope: infra task merely mentioning DM-Signal in prose does not inject" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_karo_hotfix_test_infra_mentions_dmsignal
  project: infra
  target_path: scripts/deploy_task.sh
  task_id: cmd_karo_hotfix_test_infra_mentions_dmsignal_normal
  status: assigned
  purpose: "cmd_3873の実再現では、DM-Signal本番DB fullrecalculate系cmdでassigned_acs=[AC1,AC2]へAC混入しparity確認契約が偽BLOCKした根因を修正する"
  description: "DM-Signal本番DB fullrecalculateのparity検証fixtureを参照しつつ、infra側のtask modifier注入ロジックのみを修正する"
  acceptance_criteria:
  - id: AC1
    description: "modifierのscope判定を修正する"
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_karo_hotfix_test_infra_mentions_dmsignal:
    project: infra
    title: "DM-Signal fixtureを参照するinfra hotfix"
    command: |
      DM-Signal本番DB fullrecalculateとparity確認の事例を根拠にinfra側を直す
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="lsa16_production_parity_controls,parity_target_date_ac" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

# project=infra/target_path非DM-Signalなら、説明文がDM-Signal/fullrecalculate/parityへ
# 言及していてもAC混入ゼロ・stop_forも注入されない
assert [ac['id'] for ac in task['acceptance_criteria']] == ['AC1'], task['acceptance_criteria']
assert 'stop_for' not in task, task
assert '【LS-A16 本番パリティ必須】' not in task['description'], task['description']
PY
}

@test "cmd_karo_hotfix_split_ac_modifier_scope: target_path-based DM-Signal detection still injects (project unset)" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_test_target_path_dmsignal
  target_path: /mnt/c/Python_app/DM-signal
  task_id: cmd_test_target_path_dmsignal_impl
  status: assigned
  purpose: "本番DB fullrecalculateのparity確認を行う"
  description: "本番DB fullrecalculate系cmd"
  acceptance_criteria:
  - id: AC1
    description: "bundle exportを実装する"
YAML
    cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands: {}
YAML

    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" INJECT_TASK_MODIFIERS_ONLY="lsa16_production_parity_controls,parity_target_date_ac" \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding='utf-8') as f:
    task = yaml.safe_load(f)['task']

# projectフィールド不在でもtarget_pathがDM-Signalを指せば真陽性を維持する
ac_text = '\n'.join(ac['description'] for ac in task['acceptance_criteria'])
assert 'DB/API/FEの3レイヤー貫通確認結果' in ac_text, ac_text
assert 'target_dateがproduction fullrecalculateと同一であること' in ac_text, ac_text
assert len(task['acceptance_criteria']) == 5, task['acceptance_criteria']
PY
}

# ── cmd_karo_hotfix_deploy_task_atomic_publish_202607111645 回帰テスト ──
# Origin: cmd_3847偵察で、旧direct_modeは$YAML_FILEを検証前に$task_yamlへ直接cpし
# (fail-open)、repair失敗時は壊れた内容がtask_yamlに居座っていた。
# deploy_task_direct_yaml_publish()に切り出し、同一dir candidate経由の
# validate/repair→atomic mvへ統一(fail-closed)。

@test "direct_yaml_publish: 正当なYAMLはtask_yamlへ反映されYAML_FILEも候補ファイルも変更/残存しない" {
    local tmpdir task_yaml yaml_file
    tmpdir="$(mktemp -d)"
    task_yaml="$tmpdir/task.yaml"
    yaml_file="$tmpdir/source.yaml"
    cat > "$task_yaml" <<'EOF'
task:
  status: idle
EOF
    cat > "$yaml_file" <<'EOF'
task:
  status: assigned
  purpose: valid source
EOF
    cp "$yaml_file" "$yaml_file.orig"

    run bash -lc "
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        log() { :; }
        deploy_task_direct_yaml_publish '$task_yaml' '$yaml_file'
    "
    [ "$status" -eq 0 ]

    run diff "$yaml_file.orig" "$yaml_file"
    [ "$status" -eq 0 ]

    run bash -c "compgen -G '${task_yaml}.??????' 2>/dev/null"
    [ "$status" -ne 0 ]

    run python3 -c "
import yaml
task = yaml.safe_load(open('$task_yaml', encoding='utf-8'))['task']
assert task['status'] == 'assigned', task
assert task['purpose'] == 'valid source', task
print('DIRECT_PUBLISH_OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DIRECT_PUBLISH_OK"* ]]
}

@test "direct_yaml_publish: 修復不能なYAMLは旧task_yamlをbyte-identicalに保ちYAML_FILEも候補ファイルも変更/残存しない" {
    local tmpdir task_yaml yaml_file
    tmpdir="$(mktemp -d)"
    task_yaml="$tmpdir/task.yaml"
    yaml_file="$tmpdir/source_broken.yaml"
    cat > "$task_yaml" <<'EOF'
task:
  status: idle
  purpose: pre-existing valid content
EOF
    cp "$task_yaml" "$task_yaml.orig"
    printf 'task:\n  status: "unterminated\n  purpose: [unbalanced\n' > "$yaml_file"
    cp "$yaml_file" "$yaml_file.orig"

    run bash -lc "
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        log() { :; }
        deploy_task_direct_yaml_publish '$task_yaml' '$yaml_file'
    "
    [ "$status" -ne 0 ]

    run diff "$task_yaml.orig" "$task_yaml"
    [ "$status" -eq 0 ]

    run diff "$yaml_file.orig" "$yaml_file"
    [ "$status" -eq 0 ]

    run bash -c "compgen -G '${task_yaml}.??????' 2>/dev/null"
    [ "$status" -ne 0 ]
}

@test "direct_yaml_publish: YAML_FILEが存在しない場合はtask_yamlを変更せず失敗する" {
    local tmpdir task_yaml
    tmpdir="$(mktemp -d)"
    task_yaml="$tmpdir/task.yaml"
    cat > "$task_yaml" <<'EOF'
task:
  status: idle
EOF
    cp "$task_yaml" "$task_yaml.orig"

    run bash -lc "
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        log() { :; }
        deploy_task_direct_yaml_publish '$task_yaml' '$tmpdir/does_not_exist.yaml'
    "
    [ "$status" -ne 0 ]

    run diff "$task_yaml.orig" "$task_yaml"
    [ "$status" -eq 0 ]
}
