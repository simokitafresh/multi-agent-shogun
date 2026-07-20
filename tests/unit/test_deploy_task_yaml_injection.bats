#!/usr/bin/env bats
# Regression tests for deploy_task.sh manual YAML injection.
# test_necessity: deploy_taskは新規testの自己参照・重複・抽象的necessityをBLOCKし、具体的不変量だけを恒久化する。

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    python3 -c "import yaml" 2>/dev/null || return 1
}

@test "new test requires non-duplicate non-self-referential necessity while controls pass" {
    tmpdir="$(mktemp -d)"
    git -C "$tmpdir" init -q
    git -C "$tmpdir" config user.email test@example.com
    git -C "$tmpdir" config user.name test
    mkdir -p "$tmpdir/tests"
    printf 'old\n' > "$tmpdir/tests/test_existing.bats"
    git -C "$tmpdir" add . && git -C "$tmpdir" commit -qm base
    check="$tmpdir/check.sh"
    sed "s|local task_file=\"\$1\"|local task_file=\"\$1\"; SCRIPT_DIR='$tmpdir'|" /dev/null >/dev/null

    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'" 2>/dev/null
    [ "$status" -ne 0 ]

    cat > "$tmpdir/task.yaml" <<'YAML'
task:
  planned_paths: [tests/test_new.bats]
  test_necessity:
    defense_target: deploy entry rejects nonsense tests
    overlap_evidence: rg existing tests found no equivalent contract
    overlaps_existing: false
    fixture_self_reference: false
    deprecated_mechanism: false
YAML
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'"
    [ "$status" -eq 0 ]

    for mutation in 'overlaps_existing: true' 'fixture_self_reference: true' 'deprecated_mechanism: true'; do
      sed -i -E "s/(overlaps_existing|fixture_self_reference|deprecated_mechanism): (false|true)/\1: false/g" "$tmpdir/task.yaml"
      key="${mutation%%:*}"; sed -i "s/$key: false/$mutation/" "$tmpdir/task.yaml"
      run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'"
      [ "$status" -ne 0 ]
    done

    sed -i -E 's/(fixture_self_reference|deprecated_mechanism): true/\1: false/; s/overlaps_existing: false/overlaps_existing: true\n    regression_justification: regression reproduces an intentional legacy boundary/' "$tmpdir/task.yaml"
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'"
    [ "$status" -eq 0 ]

    printf 'task:\n  planned_paths: [tests/test_existing.bats]\n' > "$tmpdir/task.yaml"
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'"
    [ "$status" -eq 0 ]
    printf 'task:\n  planned_paths: [scripts/foo.sh]\n' > "$tmpdir/task.yaml"
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'"
    [ "$status" -eq 0 ]
}

@test "test necessity classifier has zero false positives and false negatives at path boundaries" {
    tmpdir="$(mktemp -d)"
    git -C "$tmpdir" init -q
    git -C "$tmpdir" config user.email test@example.com
    git -C "$tmpdir" config user.name test
    git -C "$tmpdir" commit --allow-empty -qm base

    for path in logs/test_timing_ledger.tsv docs/test-plan.md contest/data.tsv; do
      printf 'task:\n  planned_paths: [%s]\n' "$path" > "$tmpdir/task.yaml"
      run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'"
      [ "$status" -eq 0 ]
    done

    for path in tests/unit/test_new.bats tests/test_new.sh test_new.py; do
      printf 'task:\n  planned_paths: [%s]\n' "$path" > "$tmpdir/task.yaml"
      run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'"
      [ "$status" -eq 0 ]
      [[ "$output" == *"transient=$path"* ]]
    done
}

@test "multiple new tests require independent path declarations" {
    tmpdir="$(mktemp -d)"
    git -C "$tmpdir" init -q
    git -C "$tmpdir" config user.email test@example.com
    git -C "$tmpdir" config user.name test
    git -C "$tmpdir" commit --allow-empty -qm base
    cat > "$tmpdir/task.yaml" <<'YAML'
task:
  planned_paths: [tests/test_one.bats, tests/test_two.bats]
  test_necessity:
    - path: tests/test_one.bats
      defense_target: first independent invariant remains enforced
      overlap_evidence: no equivalent first-path assertion
      overlaps_existing: false
      fixture_self_reference: false
      deprecated_mechanism: false
YAML
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"persistent=tests/test_one.bats"* ]]
    [[ "$output" == *"transient=tests/test_two.bats"* ]]
    sed -i '/deprecated_mechanism: false/a\    - path: tests/test_two.bats\n      defense_target: second independent invariant remains enforced\n      overlap_evidence: no equivalent second-path assertion\n      overlaps_existing: false\n      fixture_self_reference: false\n      deprecated_mechanism: false' "$tmpdir/task.yaml"
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_test_necessity_precheck '$tmpdir/task.yaml'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"persistent=tests/test_one.bats,tests/test_two.bats"* ]]
    [[ "$output" == *"transient="* ]]
}

@test "ci_fix source requires a positive ci_run_id before publication" {
    tmpdir="$(mktemp -d)"
    for value in missing empty text zero positive non_ci; do
        file="$tmpdir/$value.yaml"
        case "$value" in
            missing) printf 'task:\n  task_type: ci_fix\n' > "$file" ;;
            empty) printf 'task:\n  task_type: ci_fix\n  ci_run_id: ""\n' > "$file" ;;
            text) printf 'task:\n  task_type: ci_fix\n  ci_run_id: abc\n' > "$file" ;;
            zero) printf 'task:\n  task_type: ci_fix\n  ci_run_id: 0\n' > "$file" ;;
            positive) printf 'task:\n  task_type: ci_fix\n  ci_run_id: 29648245683\n' > "$file" ;;
            non_ci) printf 'task:\n  task_type: hotfix\n' > "$file" ;;
        esac
    done

    for value in missing empty text zero; do
        run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; deploy_task_ci_fix_run_id_precheck '$tmpdir/'\"$value\"'.yaml'"
        [ "$status" -eq 1 ]
        [[ "$output" == *"BLOCK: task_type=ci_fix requires ci_run_id as a positive integer"* ]]
    done

    for value in positive non_ci; do
        run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; deploy_task_ci_fix_run_id_precheck '$tmpdir/'\"$value\"'.yaml'"
        [ "$status" -eq 0 ]
    done
}

@test "ci_fix run id guard is ordered before direct YAML task publication" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys

script = open(sys.argv[1], encoding="utf-8").read()
main = script[script.index("deploy_task_main() {"):]
guard = main.index('deploy_task_ci_fix_run_id_precheck "$YAML_FILE"')
publish = main.index('deploy_task_direct_yaml_publish "$task_yaml" "$YAML_FILE"')
report = main.index('deploy_task_apply_task_mutations "$NINJA_NAME"')
delivery = main.index('safe_inbox_write "$NINJA_NAME"')
assert guard < publish < report < delivery, (guard, publish, report, delivery)
PY
}

@test "E3 Level5 injects clean repro scaffold and AC only into ci_fix tasks" {
    tmpdir="$(mktemp -d)"
    for kind in ci_fix impl recon training; do
        printf 'task:\n  task_type: %s\n  acceptance_criteria:\n  - id: AC1\n    description: existing contract\n' "$kind" > "$tmpdir/$kind.yaml"
        run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; inject_ci_fix_clean_repro_contract '$tmpdir/$kind.yaml'"
        [ "$status" -eq 0 ]
    done
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; inject_ci_fix_clean_repro_contract '$tmpdir/ci_fix.yaml'"
    [ "$status" -eq 0 ]

    python3 - "$tmpdir" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
ci = yaml.safe_load((root/'ci_fix.yaml').read_text())['task']
assert ci['ci_fix_clean_repro_evidence']['e2_harness_command'] == ''
assert [x['id'] for x in ci['acceptance_criteria']] == ['AC1', 'AC_CI_FIX_CLEAN_REPRO']
for kind in ('impl', 'recon', 'training'):
    task = yaml.safe_load((root/f'{kind}.yaml').read_text())['task']
    assert 'ci_fix_clean_repro_evidence' not in task
    assert [x['id'] for x in task['acceptance_criteria']] == ['AC1']
PY

    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys
script = open(sys.argv[1], encoding='utf-8').read()
main = script[script.index('deploy_task_apply_task_mutations() {'):]
inject = main.index('inject_ci_fix_clean_repro_contract "$task_file"')
guard = main.index('deploy_task_guard_task_yaml_syntax "post_injection_pre_report_template"')
report = main.index('generate_report_template "$ninja_name"')
assert inject < guard < report, (inject, guard, report)
PY
}

@test "E3 evidence validator blocks six invalid shapes and accepts only FAIL to FIX to PASS" {
    tmpdir="$(mktemp -d)"
    python3 - "$tmpdir" <<'PY'
import copy, pathlib, sys
root = pathlib.Path(sys.argv[1])
base = {
 'e2_harness_command': 'bash tests/e2_clean_ci.sh',
 'pre_fix_receipt': {'path':'pre.json','status':'FAIL','source_commit':'a'*40,'fixed_target':'tests/unit/x.bats#10','started_at':'2026-07-20T01:00:00+09:00','failures':1,'skips':0},
 'post_fix_receipt': {'path':'post.json','status':'PASS','source_commit':'a'*40,'fixed_target':'tests/unit/x.bats#10','started_at':'2026-07-20T01:10:00+09:00','failures':0,'skips':0},
 'push_started_at':'2026-07-20T01:20:00+09:00'}
cases = {}
cases['valid'] = copy.deepcopy(base)
cases['pass_only'] = copy.deepcopy(base); cases['pass_only']['pre_fix_receipt'] = {}
cases['source_mismatch'] = copy.deepcopy(base); cases['source_mismatch']['post_fix_receipt']['source_commit'] = 'b'*40
cases['pre_pass'] = copy.deepcopy(base); cases['pre_pass']['pre_fix_receipt']['status'] = 'PASS'; cases['pre_pass']['pre_fix_receipt']['failures'] = 0
cases['post_fail'] = copy.deepcopy(base); cases['post_fail']['post_fix_receipt']['status'] = 'FAIL'; cases['post_fail']['post_fix_receipt']['failures'] = 1
cases['post_skip'] = copy.deepcopy(base); cases['post_skip']['post_fix_receipt']['skips'] = 1
cases['after_push'] = copy.deepcopy(base); cases['after_push']['post_fix_receipt']['started_at'] = '2026-07-20T01:21:00+09:00'
def scalar(v):
    if v is None: return 'null'
    if isinstance(v, int): return str(v)
    return "'" + str(v).replace("'", "''") + "'"
for name, evidence in cases.items():
    lines = ['task:', '  task_type: ci_fix', '  ci_fix_clean_repro_evidence:']
    for key, value in evidence.items():
        if isinstance(value, dict):
            lines.append(f'    {key}:')
            for k, v in value.items(): lines.append(f'      {k}: {scalar(v)}')
        else: lines.append(f'    {key}: {scalar(value)}')
    (root/f'{name}.yaml').write_text('\n'.join(lines)+'\n')
PY
    for invalid in pass_only source_mismatch pre_pass post_fail post_skip after_push; do
        run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; deploy_task_ci_fix_clean_repro_evidence_validate '$tmpdir/'\"$invalid\"'.yaml'"
        [ "$status" -eq 1 ]
        [[ "$output" == *"BLOCK: ci_fix clean repro evidence"* ]]
    done
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; deploy_task_ci_fix_clean_repro_evidence_validate '$tmpdir/valid.yaml'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: ci_fix clean repro evidence valid"* ]]
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

@test "GA-293 injects codd freshness context only for CoDD planned paths" {
    tmpdir="$(mktemp -d)"
    codd_task="$tmpdir/codd.yaml"
    plain_task="$tmpdir/plain.yaml"
    cat > "$codd_task" <<'YAML'
task:
  project: infra
  task_type: ci_fix
  planned_paths:
  - skills/codd-refactor/SKILL.md
YAML
    cat > "$plain_task" <<'YAML'
task:
  project: other
  task_type: ci_fix
  planned_paths:
  - scripts/unrelated.sh
YAML

    run bash -lc "
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        inject_context_hints '$codd_task'
        inject_context_hints '$plain_task'
    "
    [ "$status" -eq 0 ]

    run python3 - "$codd_task" "$plain_task" <<'PY'
import sys, yaml
codd = yaml.safe_load(open(sys.argv[1]))['task']
plain = yaml.safe_load(open(sys.argv[2]))['task']
assert 'context/codd.md' in codd['context_hints'], codd
assert 'context/codd.md' not in plain.get('context_hints', []), plain
PY
    [ "$status" -eq 0 ]
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
if [[ "$1" == SELECT\ EXISTS* ]]; then
  printf '1\n'
  exit 0
fi
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

# test_necessity: FTS miss bypasses LIKE while FTS hit delegates to the unchanged LIKE output contract.
@test "memory_db_context FTS existence guard bypasses only proven zero-hit queries" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/scripts"
    cat > "$tmpdir/scripts/memory_db_query.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$QUERY_LOG"
if [[ "$1" == SELECT\ EXISTS* ]]; then
  [[ "$1" == *zz_nohit* ]] && printf '0\n' || printf '1\n'
else
  printf '%s\n' '2026-07-21 | stable current LIKE bytes'
fi
EOF
    chmod +x "$tmpdir/scripts/memory_db_query.sh"
    cat > "$tmpdir/run.sh" <<EOF
#!/usr/bin/env bash
SCRIPT_DIR="$tmpdir"
log() { :; }
$(sed -n '/^inject_memory_db_context()/,/^}/p' "$PROJECT_ROOT/scripts/deploy_task.sh")
inject_memory_db_context "\$1"
EOF
    chmod +x "$tmpdir/run.sh"

    for purpose in 'zz_nohit_7f3a9c qq_absent_91de2 never_seen_62ac1' '二重ループ インフラ改善 stable' 'memory 改善 仕組み'; do
      cat > "$tmpdir/queue/tasks/task.yaml" <<YAML
task:
  purpose: "$purpose"
YAML
      : > "$tmpdir/query.log"
      QUERY_LOG="$tmpdir/query.log" run bash "$tmpdir/run.sh" "$tmpdir/queue/tasks/task.yaml"
      [ "$status" -eq 0 ]
      if [[ "$purpose" == zz_nohit* ]]; then
        [ "$(wc -l < "$tmpdir/query.log")" -eq 1 ]
        ! grep -q '^  memory_db_context:' "$tmpdir/queue/tasks/task.yaml"
      else
        [ "$(wc -l < "$tmpdir/query.log")" -eq 2 ]
        grep -q "stable current LIKE bytes" "$tmpdir/queue/tasks/task.yaml"
      fi
    done
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
  readonly_ref:
  - path: daemon_supervisor.sh
    reason: stale partial extraction
  - path: restart_watchers.sh
    reason: stale partial extraction
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
assert len(task.get('readonly_ref') or []) == len(expected), task.get('readonly_ref')
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

@test "L896: DM-Signal restore task receives post-snapshot diagnostic artifact contract" {
    tmpdir="$(mktemp -d)"
    task_file="$tmpdir/task.yaml"
    cat > "$task_file" <<'YAML'
task:
  parent_cmd: cmd_restore_signal
  project: dm-signal
  task_id: cmd_restore_signal_impl
  status: assigned
  purpose: "restore-lockedでholding_signalを復元する"
  acceptance_criteria:
  - id: AC1
    description: "復元が完了する"
YAML

    run env DEPLOY_TASK_LIB_ONLY=1 TASK_FILE_ENV="$task_file" PROJECT_ROOT_ENV="$PROJECT_ROOT" bash -c '
        source "$PROJECT_ROOT_ENV/scripts/deploy_task.sh"
        inject_dm_signal_pf_operation_guardrails "$TASK_FILE_ENV"
    '
    [ "$status" -eq 0 ]

    python3 - "$task_file" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    task = yaml.safe_load(stream)["task"]

guards = task["dm_signal_pf_operation_guardrails"]
artifact = [item for item in guards if "post-snapshot artifact" in item]
assert len(artifact) == 1, guards
for term in ("run_id/source/input provenance", "row_count", "hash", "restore後"):
    assert term in artifact[0], artifact[0]
PY
}

@test "L877: DM-Signal golden-baseline task receives manifest and ignored archive contract" {
    tmpdir="$(mktemp -d)"
    task_file="$tmpdir/task.yaml"
    cat > "$task_file" <<'YAML'
task:
  project: dm-signal
  purpose: "100MB超のgolden-baselineを生成してexact回帰する"
  status: assigned
YAML

    run env DEPLOY_TASK_LIB_ONLY=1 TASK_FILE_ENV="$task_file" PROJECT_ROOT_ENV="$PROJECT_ROOT" bash -c '
        source "$PROJECT_ROOT_ENV/scripts/deploy_task.sh"
        inject_dm_signal_golden_baseline_contract "$TASK_FILE_ENV"
    '
    [ "$status" -eq 0 ]
    python3 - "$task_file" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
contract = task["golden_baseline_contract"]
assert len(contract) == 3, contract
text = " ".join(contract)
for term in ("gitignore", "canonical hash", "row_count", "schema/version", "archive相対path", "二値検証"):
    assert term in text, (term, contract)
PY
}

@test "L877: unrelated DM-Signal task does not receive golden-baseline contract" {
    tmpdir="$(mktemp -d)"
    task_file="$tmpdir/task.yaml"
    cat > "$task_file" <<'YAML'
task:
  project: dm-signal
  purpose: "通常のAPI回帰テストを実行する"
  status: assigned
YAML

    run env DEPLOY_TASK_LIB_ONLY=1 TASK_FILE_ENV="$task_file" PROJECT_ROOT_ENV="$PROJECT_ROOT" bash -c '
        source "$PROJECT_ROOT_ENV/scripts/deploy_task.sh"
        inject_dm_signal_golden_baseline_contract "$TASK_FILE_ENV"
    '
    [ "$status" -eq 0 ]
    python3 - "$task_file" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["task"]
assert "golden_baseline_contract" not in task, task
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

# test_necessity: D006違反taskが忍者へ到達しない配備前不変量を守る。
@test "destructive signal preflight blocks wrapper-hidden dangerous requirements and passes explanations/failpoints" {
    local tmpdir fixture before dangerous safe text
    tmpdir="$(mktemp -d)"
    fixture="$tmpdir/source.yaml"
    printf 'sentinel\n' > "$tmpdir/task.yaml"
    printf 'sentinel\n' > "$tmpdir/report.yaml"
    printf 'sentinel\n' > "$tmpdir/inbox.yaml"

    dangerous=(
      'command: "kill 1234"'
      'command: "pkill -f ninja_monitor"'
      'command: "killall throughput_growth_loop.sh"'
      'purpose: "外部プロセスへsignalを送信して故障注入を実行せよ"'
      'purpose: "対象daemonを終了させる故障注入を行う"'
      'acceptance_criteria: ["process kill故障注入を実行する"]'
      'command: "timeout 5 killall target"'
      'command: "timeout --signal=TERM 5 pkill -f worker"'
      'command: "env MODE=fault timeout -k 1 5 kill 1234"'
    )
    safe=(
      'command: "TEST_FAILPOINT=after_persist bash scripts/worker.sh; test $? -ne 0"'
      'purpose: "D006本文を参照して安全境界を確認する"'
      'purpose: "kill/pkill/killallは禁止であると説明する"'
      'acceptance_criteria: ["外部プロセスsignal要求を検出してBLOCKする"]'
      'acceptance_criteria: ["process kill故障注入要求がある場合は遮断する"]'
      'command: "bash scripts/worker.sh --self-exit-after-persist 17"'
    )

    for text in "${dangerous[@]}"; do
      printf 'task:\n  %s\n' "$text" > "$fixture"
      run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; deploy_task_destructive_signal_precheck '$fixture'"
      [ "$status" -eq 2 ]
      [[ "$output" == *"phase永続保存後に対象プロセス自身が非0終了するテスト専用failpointを使え"* ]]
    done

    for text in "${safe[@]}"; do
      printf 'task:\n  %s\n' "$text" > "$fixture"
      run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; deploy_task_destructive_signal_precheck '$fixture'"
      [ "$status" -eq 0 ]
    done

    run bash -c "cmp -s '$tmpdir/task.yaml' '$tmpdir/report.yaml' && cmp -s '$tmpdir/task.yaml' '$tmpdir/inbox.yaml'"
    [ "$status" -eq 0 ]
}

@test "direct --yaml safe source executes destructive preflight without runtime NameError" {
    local tmpdir source
    tmpdir="$(mktemp -d)"
    source="$tmpdir/safe.yaml"
    cat > "$source" <<'YAML'
task:
  purpose: safe direct fixture
  command: TEST_FAILPOINT=after_persist bash scripts/worker.sh
  acceptance_criteria:
    - description: self exit failpoint returns nonzero after durable phase save
YAML

    run env DEPLOY_TASK_LIB_ONLY=1 SOURCE_FILE="$source" PROJECT_ROOT_ENV="$PROJECT_ROOT" bash -c '
      source "$PROJECT_ROOT_ENV/scripts/deploy_task.sh"
      deploy_task_destructive_signal_precheck "$SOURCE_FILE"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"NameError"* ]]
}

# test_necessity: mutation途中の後段FAILでは作業copyだけを破棄し、公開済taskのSHA/bytesを不変に保つ不変量を守る。
@test "task mutation failure leaves original task SHA unchanged" {
    tmpdir="$(mktemp -d)"; task_file="$tmpdir/task.yaml"
    cat >"$task_file" <<'YAML'
task:
  status: assigned
  task_id: atomic-fixture
  parent_cmd: cmd_atomic_fixture
  project: infra
YAML
    before="$(sha256sum "$task_file" | awk '{print $1}')"
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1 DEPLOY_TASK_TEST_MUTATE_AND_FAIL=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; deploy_task_apply_task_mutations hayate '$task_file'"
    [ "$status" -ne 0 ]
    after="$(sha256sum "$task_file" | awk '{print $1}')"
    [ "$before" = "$after" ]
    run bash -c "compgen -G '${task_file}.mutation.*'"
    [ "$status" -ne 0 ]
}

# test_necessity: --directへYAML pathを誤投入した場合、task publication前に拒否し正規--yaml構文を提示する不変量を守る。
@test "direct mode rejects YAML path cmd before publication" {
    task="$PROJECT_ROOT/queue/tasks/hayate.yaml"
    task_sha_before="$(sha256sum "$task" | awk '{print $1}')"
    run bash "$PROJECT_ROOT/scripts/deploy_task.sh" --direct hayate .cache/task.yaml
    [ "$status" -ne 0 ]
    [[ "$output" == *"Use: deploy_task.sh --yaml <file> <ninja>"* ]]
    [ "$task_sha_before" = "$(sha256sum "$task" | awk '{print $1}')" ]
}

# test_necessity: --yaml経路はsource precheck完了前に旧taskへissued_at/resetを書かず、publish後の成功時だけRecordedを出す順序を守る。
@test "yaml deployment records issued_at only after source precheck and atomic publish" {
    run python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys
s = open(sys.argv[1], encoding='utf-8').read()
main = s[s.index('deploy_task_main() {'):]
assert 'if [ -n "$CMD_ID" ] && { [ "$DIRECT_MODE" != true ] || [ -z "$YAML_FILE" ]; }; then' in main
pre = main.index('deploy_task_source_contract_precheck "$YAML_FILE"')
publish = main.index('deploy_task_direct_yaml_publish "$task_yaml" "$YAML_FILE"')
record = main.index('record_issued_at_once "$task_yaml" "$CMD_ID"', publish)
assert pre < publish < record, (pre, publish, record)
assert 'if [ "$DIRECT_MODE" != true ] || [ -z "$YAML_FILE" ]; then\n                reset_stale_fields' in main
PY
    [ "$status" -eq 0 ]
}

# test_necessity: issued_at helper失敗時にRecorded偽成功ログを出さず、invalid旧taskもvalid sourceのatomic publishでVALIDへ置換できる不変量を守る。
@test "issued_at failure logs no Recorded and valid source replaces invalid destination" {
    tmpdir="$(mktemp -d)"; dest="$tmpdir/task.yaml"; source_yaml="$tmpdir/source.yaml"; log_file="$tmpdir/log"
    printf 'task:\n  broken: [\n' >"$dest"
    printf 'task:\n  status: assigned\n  parent_cmd: cmd_valid\n' >"$source_yaml"
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; log(){ printf '%s\\n' \"\$*\" >>'$log_file'; }; yaml_field_set_batch(){ return 1; }; record_issued_at_once '$source_yaml' cmd_valid now"
    [ "$status" -ne 0 ]
    run grep -c '\[ISSUED_AT\] Recorded' "$log_file"
    [ "$status" -ne 0 ]
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; log(){ :; }; deploy_task_direct_yaml_publish '$dest' '$source_yaml'; python3 -c \"import yaml; yaml.safe_load(open('$dest'))\""
    [ "$status" -eq 0 ]
}

# test_necessity: --yaml full transactionの任意後段FAILでtask/reportを旧bytesへ戻し、新規reportとinbox publicationを残さない不変量を守る。
@test "yaml transaction rollback restores task and report bytes" {
    tmpdir="$(mktemp -d)"; mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue/reports" "$tmpdir/queue/inbox"
    task="$tmpdir/queue/tasks/hayate.yaml"; source_yaml="$tmpdir/source.yaml"
    report="$tmpdir/queue/reports/hayate_report_cmd_tx.yaml"
    printf 'task:\n  status: idle\n  parent_cmd: cmd_old\n' >"$task"
    printf 'task:\n  status: assigned\n  parent_cmd: cmd_tx\n  report_filename: hayate_report_cmd_tx.yaml\n' >"$source_yaml"
    printf 'status: pending\nparent_cmd: cmd_tx\n' >"$report"
    printf 'messages: []\n' >"$tmpdir/queue/inbox/hayate.yaml"
    task_before="$(sha256sum "$task" | awk '{print $1}')"; report_before="$(sha256sum "$report" | awk '{print $1}')"
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; log(){ printf '%s\\n' \"\$*\" >>'$tmpdir/log'; }; yaml_field_set_batch(){ printf '\\n  issued_at: now\\n' >>\"\$1\"; }; deploy_task_yaml_transaction_begin '$task' '$source_yaml' hayate cmd_tx; record_issued_at_once '$task' cmd_tx now; printf 'broken-report\\n' >'$report'; deploy_task_yaml_transaction_rollback"
    [ "$status" -eq 0 ]
    [ "$task_before" = "$(sha256sum "$task" | awk '{print $1}')" ]
    [ "$report_before" = "$(sha256sum "$report" | awk '{print $1}')" ]
    run grep -c '\[ISSUED_AT\] Recorded' "$tmpdir/log"
    [ "$status" -ne 0 ]
    [ "$(grep -c 'type: task_assigned' "$tmpdir/queue/inbox/hayate.yaml" || true)" -eq 0 ]
}

# test_necessity: --yaml transactionで元reportが存在しない場合、FAIL時に途中生成reportを削除しtask SHAを保持する不変量を守る。
@test "yaml transaction rollback removes newly staged report" {
    tmpdir="$(mktemp -d)"; mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue/reports"
    task="$tmpdir/queue/tasks/hayate.yaml"; source_yaml="$tmpdir/source.yaml"; report="$tmpdir/queue/reports/hayate_report_cmd_new.yaml"
    printf 'task:\n  status: idle\n' >"$task"
    printf 'task:\n  parent_cmd: cmd_new\n  report_filename: hayate_report_cmd_new.yaml\n' >"$source_yaml"
    before="$(sha256sum "$task" | awk '{print $1}')"
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; log(){ :; }; deploy_task_yaml_transaction_begin '$task' '$source_yaml' hayate cmd_new; printf 'changed\\n' >'$task'; printf 'new-report\\n' >'$report'; deploy_task_yaml_transaction_rollback"
    [ "$status" -eq 0 ]
    [ "$before" = "$(sha256sum "$task" | awk '{print $1}')" ]
    [ ! -e "$report" ]
}
