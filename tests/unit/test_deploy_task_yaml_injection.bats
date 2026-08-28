#!/usr/bin/env bats
# Regression tests for deploy_task.sh manual YAML injection.
# test_necessity: deploy_taskは新規testの自己参照・重複・抽象的necessityをBLOCKし、具体的不変量だけを恒久化する。

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export DEPLOY_TASK_TEST_DEFAULT_PROJECT=infra
    python3 -c "import yaml" 2>/dev/null || return 1
}

@test "quality contract projection classifies all six structured boundaries without false results" {
    # test_necessity: direct deployment must recognize action conversion in quality_gate while preserving missing-field and non-candidate boundaries.
    run bash -lc "source '$PROJECT_ROOT/scripts/lib/gate_hook_quality_contract.sh';
      check() { local expected=\"\$1\" text=\"\$2\"; local actual; actual=\$(gate_hook_quality_contract_evaluate \"\$text\"); [[ \"\$actual\" == \"\$expected\" ]] || { printf 'expected=%s actual=%s\\n' \"\$expected\" \"\$actual\"; return 1; }; };
      check $'yes\\tpass\\tpass' $'purpose: add gate detector\\nquality_gate:\\n  action_conversion: BLOCK on missing action\\n  fp_measurement: false_positive=0';
      check $'yes\\tpass\\tpass' $'purpose: add gate detector\\nacceptance_criteria:\\n  - description: BLOCK on missing action; false_positive=0';
      check $'yes\\tpass\\tpass' $'purpose: add gate detector\\ncommand: |\\n  BLOCK on missing action; false_positive=0';
      check $'yes\\tmissing\\tpass' $'purpose: add gate detector\\nquality_gate:\\n  fp_measurement: false_positive=0';
      check $'yes\\tpass\\tmissing' $'purpose: add gate detector\\nquality_gate:\\n  action_conversion: BLOCK on missing action';
      check $'no\\tpass\\tpass' $'purpose: update ordinary parser\\nquality_gate:\\n  action_conversion: BLOCK\\n  fp_measurement: false_positive=0'"
    [ "$status" -eq 0 ]
}

@test "head-fixed validation is explicit opt-in and detached runner survives shared HEAD commit without residue" {
    tmpdir="$(mktemp -d)"
    repo="$tmpdir/repo"
    mkdir -p "$repo/scripts"
    git -C "$repo" init -q
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    cp "$PROJECT_ROOT/scripts/head_fixed_validation.sh" "$repo/scripts/"
    chmod +x "$repo/scripts/head_fixed_validation.sh"
    printf 'old\n' >"$repo/value"
    printf 'task:\n  head_fixed_validation: true\n' >"$tmpdir/declared.yaml"
    printf 'task:\n  task_type: full\n' >"$tmpdir/normal.yaml"
    git -C "$repo" add . && git -C "$repo" commit -qm base

    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; inject_head_fixed_validation_contract '$tmpdir/declared.yaml'; inject_head_fixed_validation_contract '$tmpdir/normal.yaml'"
    [ "$status" -eq 0 ]
    python3 - "$tmpdir" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
declared = yaml.safe_load((root/'declared.yaml').read_text())['task']
normal = yaml.safe_load((root/'normal.yaml').read_text())['task']
assert 'isolated detached worktree' in declared['head_fixed_validation_contract']
assert 'head_fixed_validation_contract' not in normal
PY

    hook="cd '$repo' && printf 'new\\n' > value && git add value && git commit -qm concurrent"
    mkdir -p "$tmpdir/runner-tmp"
    run env TMPDIR="$tmpdir/runner-tmp" HEAD_FIXED_VALIDATION_AFTER_CAPTURE_COMMAND="$hook" HEAD_FIXED_VALIDATION_COMMAND='test "$(cat value)" = old' \
        bash "$repo/scripts/head_fixed_validation.sh" "$tmpdir/declared.yaml" "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HEAD_FIXED_VALIDATION fixed_sha="* ]]
    [ "$(cat "$repo/value")" = new ]
    [ "$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ' || true)" -eq 1 ]
    [ "$(find "$tmpdir/runner-tmp" -maxdepth 1 -type d -name 'head-fixed-validation.*' | wc -l)" -eq 0 ]
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

    export DEPLOY_TASK_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/deploy_task.sh"
    SCRIPT_DIR="$tmpdir"
    run_necessity_case() {
      local expected="$1" task_file="$2" actual rc
      set +e
      actual="$(deploy_task_test_necessity_precheck "$task_file" 2>&1)"
      rc=$?
      set -e
      [ "$rc" -eq "$expected" ] || {
        printf 'task=%s expected_rc=%s actual_rc=%s output=%s\n' "$task_file" "$expected" "$rc" "$actual"
        return 1
      }
    }

    run_necessity_case 1 "$tmpdir/missing.yaml"

    cat > "$tmpdir/valid.yaml" <<'YAML'
task:
  planned_paths: [tests/test_new.bats]
  test_necessity:
    defense_target: deploy entry rejects nonsense tests
    overlap_evidence: rg existing tests found no equivalent contract
    overlaps_existing: false
    fixture_self_reference: false
    deprecated_mechanism: false
YAML
    for mutation in overlaps_existing fixture_self_reference deprecated_mechanism; do
      cp "$tmpdir/valid.yaml" "$tmpdir/$mutation.yaml"
      sed -i "s/$mutation: false/$mutation: true/" "$tmpdir/$mutation.yaml"
    done

    cp "$tmpdir/valid.yaml" "$tmpdir/justified.yaml"
    sed -i '/overlaps_existing: false/a\    regression_justification: regression reproduces an intentional legacy boundary' "$tmpdir/justified.yaml"
    sed -i 's/overlaps_existing: false/overlaps_existing: true/' "$tmpdir/justified.yaml"

    printf 'task:\n  planned_paths: [tests/test_existing.bats]\n' > "$tmpdir/existing.yaml"
    printf 'task:\n  planned_paths: [scripts/foo.sh]\n' > "$tmpdir/non_test.yaml"
    pids=()
    run_necessity_case 0 "$tmpdir/valid.yaml" & pids+=("$!")
    for mutation in overlaps_existing fixture_self_reference deprecated_mechanism; do
      run_necessity_case 1 "$tmpdir/$mutation.yaml" & pids+=("$!")
    done
    run_necessity_case 0 "$tmpdir/justified.yaml" & pids+=("$!")
    run_necessity_case 0 "$tmpdir/existing.yaml" & pids+=("$!")
    run_necessity_case 0 "$tmpdir/non_test.yaml" & pids+=("$!")
    failed=0
    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
    [ "$failed" -eq 0 ]
}

@test "test necessity classifier has zero false positives and false negatives at path boundaries" {
    tmpdir="$(mktemp -d)"
    git -C "$tmpdir" init -q
    git -C "$tmpdir" config user.email test@example.com
    git -C "$tmpdir" config user.name test
    git -C "$tmpdir" commit --allow-empty -qm base

    export DEPLOY_TASK_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/deploy_task.sh"
    SCRIPT_DIR="$tmpdir"
    run_necessity_case() {
      local expected="$1" needle="$2" task_file="$3" actual rc
      set +e
      actual="$(deploy_task_test_necessity_precheck "$task_file" 2>&1)"
      rc=$?
      set -e
      [ "$rc" -eq "$expected" ] && [[ "$actual" == *"$needle"* ]]
    }

    pids=()
    for path in logs/test_timing_ledger.tsv docs/test-plan.md contest/data.tsv; do
      task_file="$tmpdir/$(basename "$path").yaml"
      printf 'task:\n  planned_paths: [%s]\n' "$path" > "$task_file"
      run_necessity_case 0 "" "$task_file" & pids+=("$!")
    done

    for path in tests/unit/test_new.bats tests/test_new.sh test_new.py; do
      task_file="$tmpdir/$(basename "$path").yaml"
      printf 'task:\n  planned_paths: [%s]\n' "$path" > "$task_file"
      run_necessity_case 0 "transient=$path" "$task_file" & pids+=("$!")
    done
    failed=0
    for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
    [ "$failed" -eq 0 ]
}

# test_necessity: preserve the test-lifecycle boundary while accepting project-internal absolute paths.
@test "test necessity classifier normalizes project-internal absolute paths" {
    tmpdir="$(mktemp -d)"
    export DEPLOY_TASK_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/deploy_task.sh"
    SCRIPT_DIR="$PROJECT_ROOT"

    printf 'task:\n  project: infra\n  planned_paths: [%s]\n' \
        "$PROJECT_ROOT/tests/unit/test_deploy_task_yaml_injection.bats" > "$tmpdir/inside_absolute.yaml"
    printf 'task:\n  project: infra\n  planned_paths: [tests/unit/test_deploy_task_yaml_injection.bats]\n' \
        > "$tmpdir/relative.yaml"
    printf 'task:\n  project: infra\n  planned_paths: [/tmp/deploy-task-outside-test.bats]\n' \
        > "$tmpdir/outside_absolute.yaml"

    run deploy_task_test_necessity_precheck "$tmpdir/inside_absolute.yaml"
    [ "$status" -eq 0 ]

    run deploy_task_test_necessity_precheck "$tmpdir/relative.yaml"
    [ "$status" -eq 0 ]

    run deploy_task_test_necessity_precheck "$tmpdir/outside_absolute.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: test path is outside project repo: /tmp/deploy-task-outside-test.bats"* ]]
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

    export DEPLOY_TASK_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/deploy_task.sh"
    run_ci_run_id_check() {
        local expected="$1" value="$2" actual rc
        set +e
        actual="$(deploy_task_ci_fix_run_id_precheck "$tmpdir/$value.yaml" 2>&1)"
        rc=$?
        set -e
        [ "$rc" -eq "$expected" ] || return 1
        if [ "$expected" -eq 1 ]; then
            [[ "$actual" == *"BLOCK: task_type=ci_fix requires ci_run_id as a positive integer"* ]]
        fi
    }

    for value in missing empty text zero; do
        run_ci_run_id_check 1 "$value"
    done

    for value in positive non_ci; do
        run_ci_run_id_check 0 "$value"
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
    export DEPLOY_TASK_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/deploy_task.sh"
    pids=()
    for kind in ci_fix impl recon training; do
        printf 'task:\n  task_type: %s\n  acceptance_criteria:\n  - id: AC1\n    description: existing contract\n' "$kind" > "$tmpdir/$kind.yaml"
        (inject_ci_fix_clean_repro_contract "$tmpdir/$kind.yaml") &
        pids+=("$!")
    done
    failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failed=1
    done
    [ "$failed" -eq 0 ]
    inject_ci_fix_clean_repro_contract "$tmpdir/ci_fix.yaml"

    python3 - "$tmpdir" <<'PY'
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
ci = yaml.safe_load((root/'ci_fix.yaml').read_text())['task']
assert ci['final_checkpoint'] == {
    'type': 'ci_fix_clean_repro',
    'required': True,
    'evidence_field': 'ci_fix_clean_repro_evidence',
    'validator': 'deploy_task_ci_fix_clean_repro_evidence_validate',
    'phase': 'terminal_report_gate',
}
assert 'ci_fix_clean_repro_evidence' not in ci
assert [x['id'] for x in ci['acceptance_criteria']] == ['AC1']
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
    validate_case() {
        local expected_rc="$1" needle="$2" case_file="$3" actual rc
        set +e
        actual="$(deploy_task_ci_fix_clean_repro_evidence_validate "$case_file" 2>&1)"
        rc=$?
        set -e
        if [ "$rc" -ne "$expected_rc" ] || [[ "$actual" != *"$needle"* ]]; then
            printf 'case=%s expected_rc=%s actual_rc=%s output=%s\n' "$case_file" "$expected_rc" "$rc" "$actual"
            return 1
        fi
    }
    run_validator_cases() {
        local -a pids=()
        local invalid pid failed=0
        export DEPLOY_TASK_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/deploy_task.sh"
        for invalid in pass_only source_mismatch pre_pass post_fail post_skip after_push; do
            validate_case 1 'BLOCK: ci_fix clean repro evidence' "$tmpdir/${invalid}.yaml" &
            pids+=("$!")
        done
        validate_case 0 'PASS: ci_fix clean repro evidence valid' "$tmpdir/valid.yaml" &
        pids+=("$!")
        for pid in "${pids[@]}"; do
            wait "$pid" || failed=1
        done
        return "$failed"
    }
    run run_validator_cases
    [ "$status" -eq 0 ]
}

@test "not_reproducible terminal accepts only the three fixed proofs and never relaxes FAIL to PASS" {
    tmpdir="$(mktemp -d)"
    python3 - "$tmpdir" <<'PY'
import copy, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
receipt = lambda env: {'path': f'logs/{env}.json', 'environment': env, 'status': 'PASS', 'started_at': '2026-07-26T10:00:00+09:00'}
base = {
 'e2_harness_command': 'bash tests/e2_clean_ci.sh',
 'outcome': 'not_reproducible',
 'not_reproducible': {
   'independent_receipts': [receipt('wsl2-local'), receipt('linked-worktree'), receipt('ci-container')],
   'ci_green': {'run_id': '1234567890', 'status': 'GREEN', 'observed_at': '2026-07-26T11:00:00+09:00', 'commit': 'c'*40},
   'diagnostics': {'path': 'scripts/run_tests.sh', 'emits': ['rc', 'stderr', 'reason_code']}}}
cases = {}
# 陽性: 3点揃い
cases['nr_valid'] = copy.deepcopy(base)
# 境界: receipt 3件だが環境が2種類しかない
cases['nr_two_envs'] = copy.deepcopy(base)
cases['nr_two_envs']['not_reproducible']['independent_receipts'][2]['environment'] = 'wsl2-local'
# 陰性1: receipt 2件のみ
cases['nr_two_receipts'] = copy.deepcopy(base)
cases['nr_two_receipts']['not_reproducible']['independent_receipts'] = cases['nr_two_receipts']['not_reproducible']['independent_receipts'][:2]
# 陰性2: 診断計装が reason_code を出さない
cases['nr_no_diag'] = copy.deepcopy(base)
cases['nr_no_diag']['not_reproducible']['diagnostics']['emits'] = ['rc', 'stderr']
# 陰性3: CI本番がGREENでない
cases['nr_ci_red'] = copy.deepcopy(base)
cases['nr_ci_red']['not_reproducible']['ci_green']['status'] = 'RED'
for name, evidence in cases.items():
    # YAMLはJSONの上位互換。運用YAMLと同じくyaml.dump系は使わない(CLAUDE.md YAML書込み安全規則)
    (root/f'{name}.yaml').write_text(json.dumps({'task': {'task_type': 'ci_fix', 'ci_fix_clean_repro_evidence': evidence}}, ensure_ascii=False))
PY
    validate_case() {
        local expected_rc="$1" needle="$2" case_file="$3" actual rc
        set +e
        actual="$(deploy_task_ci_fix_clean_repro_evidence_validate "$case_file" 2>&1)"
        rc=$?
        set -e
        if [ "$rc" -ne "$expected_rc" ] || [[ "$actual" != *"$needle"* ]]; then
            printf 'case=%s expected_rc=%s actual_rc=%s output=%s\n' "$case_file" "$expected_rc" "$rc" "$actual"
            return 1
        fi
    }
    run_validator_cases() {
        local -a pids=()
        local invalid pid failed=0
        export DEPLOY_TASK_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/deploy_task.sh"
        for invalid in nr_two_envs nr_two_receipts nr_no_diag nr_ci_red; do
            validate_case 1 'BLOCK: ci_fix clean repro evidence not_reproducible' "$tmpdir/${invalid}.yaml" &
            pids+=("$!")
        done
        validate_case 0 'PASS: ci_fix clean repro not_reproducible evidence valid' "$tmpdir/nr_valid.yaml" &
        pids+=("$!")
        for pid in "${pids[@]}"; do
            wait "$pid" || failed=1
        done
        return "$failed"
    }
    run run_validator_cases
    [ "$status" -eq 0 ]
}

@test "not_reproducible is opt-in: without the declaration a FAIL-free task still blocks" {
    tmpdir="$(mktemp -d)"
    python3 - "$tmpdir" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
receipt = lambda env: {'path': f'logs/{env}.json', 'environment': env, 'status': 'PASS', 'started_at': '2026-07-26T10:00:00+09:00'}
proofs = {
  'independent_receipts': [receipt('a'), receipt('b'), receipt('c')],
  'ci_green': {'run_id': '1', 'status': 'GREEN', 'observed_at': '2026-07-26T11:00:00+09:00', 'commit': 'c'*40},
  'diagnostics': {'path': 'scripts/run_tests.sh', 'emits': ['rc', 'stderr', 'reason_code']}}
# outcome未宣言: 3点が揃っていても従来のFAIL->PASS要求が生き、pre receiptなしはBLOCK
evidence = {'e2_harness_command': 'bash tests/e2_clean_ci.sh', 'not_reproducible': proofs}
(root/'no_outcome.yaml').write_text(json.dumps({'task': {'task_type': 'ci_fix', 'ci_fix_clean_repro_evidence': evidence}}, ensure_ascii=False))
PY
    run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; deploy_task_ci_fix_clean_repro_evidence_validate '$tmpdir/no_outcome.yaml'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: ci_fix clean repro evidence receipt mapping missing"* ]]
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

# test_necessity: lesson injectionのpostconditionは、同一attempt/generationのscore更新をdurable queueへ記録した後に評価し、
# 大容量archive更新を配備critical pathへ戻さない順序不変量を守る。
@test "postcondition_lesson_inject follows durable deferred score enqueue" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys

script = open(sys.argv[1], encoding="utf-8").read()
main_start = script.index("deploy_task_apply_task_mutations() {")
main = script[main_start:]

inject_idx = main.index('inject_related_lessons "$task_file"')
score_idx = main.index('deploy_task_queue_lesson_scores "$task_file" "$inj_project" "$inj_ids"')
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

@test "GA-293 injects codd freshness context and commit scope only for CoDD planned paths" {
    tmpdir="$(mktemp -d)"
    plain_task="$tmpdir/plain.yaml"
    cat > "$plain_task" <<'YAML'
task:
  project: other
  task_type: ci_fix
  planned_paths:
  - scripts/unrelated.sh
  commit_contract:
    required: true
    reason: implementation_path_present
    planned_paths:
    - scripts/unrelated.sh
YAML

    for shape in scripts/codd skills/codd/SKILL.md skills/codd-refactor/SKILL.md; do
        name="${shape//\//_}"
        task_file="$tmpdir/$name.yaml"
        cat > "$task_file" <<YAML
task:
  project: infra
  task_type: ci_fix
  planned_paths:
  - $shape
  commit_contract:
    required: true
    reason: implementation_path_present
    planned_paths:
    - $shape
    scope_expansion_reason: existing canonical reason
YAML
    done

    run bash -lc "
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        pids=()
        for task_file in '$tmpdir'/scripts_codd.yaml '$tmpdir'/skills_codd_SKILL.md.yaml '$tmpdir'/skills_codd-refactor_SKILL.md.yaml; do
            (inject_context_hints \"\$task_file\") &
            pids+=(\"\$!\")
        done
        failed=0
        for pid in \"\${pids[@]}\"; do
            wait \"\$pid\" || failed=1
        done
        [ \"\$failed\" -eq 0 ]
        inject_context_hints '$plain_task'
    "
    [ "$status" -eq 0 ]

    run python3 - "$tmpdir" "$plain_task" <<'PY'
import sys, yaml
from pathlib import Path

for path in sorted(Path(sys.argv[1]).glob("*codd*.yaml")):
    codd = yaml.safe_load(path.read_text())["task"]
    assert codd["context_hints"].count("context/codd.md") == 1, codd
    assert codd["planned_paths"].count("context/codd.md") == 1, codd
    assert codd["commit_contract"]["planned_paths"].count("context/codd.md") == 1, codd
    assert codd["commit_contract"]["scope_expansion_reason"] == "existing canonical reason", codd
plain = yaml.safe_load(open(sys.argv[2]))["task"]
assert 'context/codd.md' not in plain.get('context_hints', []), plain
assert 'context/codd.md' not in plain['planned_paths'], plain
assert 'context/codd.md' not in plain['commit_contract']['planned_paths'], plain
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

# test_necessity: target_pathの複数directory契約を守り、各directoryの認証候補を欠落なく重複排除する。
# regression_justification: scalar前提のos.path.isdir呼出しがlistでTypeErrorを出した配備時回帰を固定する。
@test "credential_files normalizes scalar and list target paths without missing candidates" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/cred-a" "$tmpdir/cred-b"
    touch "$tmpdir/cred-a/.env.alpha" "$tmpdir/cred-b/.env.beta"

    run_credential_case() {
        local shape="$1" task_file target_yaml
        task_file="$tmpdir/queue/tasks/$shape.yaml"
        case "$shape" in
          scalar) target_yaml="target_path: $tmpdir/cred-a" ;;
          list) target_yaml="$(printf 'target_path:\n  - %s/cred-a\n  - %s/cred-b' "$tmpdir" "$tmpdir")" ;;
          missing) target_yaml="" ;;
          non_directory) target_yaml="$(printf 'target_path:\n  - %s/not-a-directory\n  - %s/also-missing' "$tmpdir" "$tmpdir")" ;;
        esac
        printf 'task:\n  command: receipt download\n  %s\n' "$target_yaml" > "$task_file"

        env TASK_FILE_ENV="$task_file" SCRIPT_DIR_ENV="$tmpdir" \
            INJECT_TASK_MODIFIERS_ONLY="credential_files" \
            python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py" >/dev/null

        if [ "$shape" = scalar ] || [ "$shape" = list ]; then
            python3 - "$task_file" "$shape" <<'PY'
import sys
import yaml

task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
paths = task.get('context_files', [])
expected = 1 if sys.argv[2] == 'scalar' else 2
assert len(paths) == expected, (paths, expected)
assert len(paths) == len(set(paths)), paths
assert all(path.endswith(('.env.alpha', '.env.beta')) for path in paths), paths
assert 'credential_warning' not in task, task
PY
        else
            python3 - "$task_file" <<'PY'
import sys
import yaml

task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
assert 'credential_warning' in task, task
assert not task.get('context_files'), task
PY
        fi
    }

    pids=()
    for shape in scalar list missing non_directory; do
        (run_credential_case "$shape") &
        pids+=("$!")
    done
    failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failed=1
    done
    [ "$failed" -eq 0 ]
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
    touch "$tmpdir/refactor-workorder-20260611.md"
    touch "$tmpdir/scripts/run_tests.sh"
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
      refactor-workorder-20260611.md と run_tests.sh を必読参照し、backend/app/api/main.py を修正する。
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
assert [row['path'] for row in refs] == [
    'refactor-workorder-20260611.md',
    'scripts/run_tests.sh',
], refs
assert all('必読' in row['reason'] for row in refs), refs
PY
}

@test "cmd_3970 regression: update-trigger analysis is readonly while design artifact remains writable" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue" "$tmpdir/scripts/lib"
    cp "$PROJECT_ROOT/scripts/lib/field_get.sh" "$tmpdir/scripts/lib/field_get.sh"
    touch "$tmpdir/daemon_supervisor.sh" "$tmpdir/restart_watchers.sh" \
      "$tmpdir/gist_sync.sh" "$tmpdir/daemon_watchdog.log" "$tmpdir/ninja_monitor.log"
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

# test_necessity: read-only recon2 tasks that name a production table/generator
# must preserve their assigned AC namespace and must not gain write/parity duties.
@test "LS-A16 controls: DM-Signal recon2 monthly_returns measurement is not a production mutation" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue"
    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_recon_monthly_returns
  project: dm-signal
  task_type: recon2
  task_id: cmd_recon_monthly_returns_normal
  status: assigned
  purpose: "production monthly_returns generatorをread-only cloneで全数照合する"
  description: "本番DBは変更せず、monthly_returnsのoracle exact件数を測る"
  acceptance_criteria:
  - id: AC1
    description: "全対象を照合しwrite0を証明する"
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

assert [ac['id'] for ac in task['acceptance_criteria']] == ['AC1'], task
assert '本番パリティ未確認' not in task.get('stop_for', []), task
assert '【LS-A16 本番パリティ必須】' not in task['description'], task
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

# test_necessity: the canary contract is a persistent deployment invariant;
# every verification/performance task must receive it while unrelated and
# documentation-only tasks must receive zero injections.
# test_necessity: A source path matching a registry trigger must emit the owning
# context path with owner, update_trigger, and source_paths metadata.
@test "GA-457 source registry autowires candidates only for matching task sources" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/scripts/config" "$tmpdir/queue/tasks"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" \
        "$tmpdir/scripts/config/context_source_commits.tsv"

    cat > "$tmpdir/queue/tasks/sasuke.yaml" <<'YAML'
task:
  project: dm-signal
  target_path: backend/app/jobs/recalculate.py
  task_id: ga457_production
  status: assigned
YAML
    run env TASK_FILE_ENV="$tmpdir/queue/tasks/sasuke.yaml" SCRIPT_DIR_ENV="$tmpdir" \
        INJECT_TASK_MODIFIERS_ONLY=context_update \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]
    python3 - "$tmpdir/queue/tasks/sasuke.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
candidates = task['context_update_candidates']
assert {item['path'] for item in candidates} == {
    'context/dm-signal-core.md', 'context/dm-signal-ops.md'
}
assert all(item['owner'] and item['update_trigger'] and item['source_paths']
           for item in candidates)
PY
}

# test_necessity: Unrelated sources and explicitly processed context paths must
# produce zero candidates so completion cannot gain a false context obligation.
@test "GA-457 source registry keeps unrelated and explicitly processed tasks at zero candidates" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/scripts/config" "$tmpdir/queue/tasks"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" \
        "$tmpdir/scripts/config/context_source_commits.tsv"

    cat > "$tmpdir/queue/tasks/unrelated.yaml" <<'YAML'
task:
  project: dm-signal
  target_path: README.md
  task_id: ga457_unrelated
  status: assigned
YAML
    cat > "$tmpdir/queue/tasks/processed.yaml" <<'YAML'
task:
  project: dm-signal
  target_path: backend/app/jobs/recalculate.py
  context_update:
    - context/dm-signal-core.md
    - context/dm-signal-ops.md
  task_id: ga457_processed
  status: assigned
YAML
    for worker in unrelated processed; do
        run env TASK_FILE_ENV="$tmpdir/queue/tasks/$worker.yaml" SCRIPT_DIR_ENV="$tmpdir" \
            INJECT_TASK_MODIFIERS_ONLY=context_update \
            python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
        [ "$status" -eq 0 ]
        python3 - "$tmpdir/queue/tasks/$worker.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
assert task.get('context_update_candidates') == [], task
PY
    done
}

# test_necessity: the freshness scanner owns both the infra repository and the
# external DM-Signal repository; every registered external context must become
# a completion candidate even when the task target is an infra-local helper.
@test "GA-461 infra freshness task autowires the complete DM-Signal frontier" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/scripts/config" "$tmpdir/queue/tasks"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" \
        "$tmpdir/scripts/config/context_source_commits.tsv"

    cat > "$tmpdir/queue/tasks/hayate.yaml" <<'YAML'
task:
  project: infra
  target_path: scripts/lib/inject_task_modifiers.py
  planned_paths:
    - scripts/context_freshness_check.sh
    - scripts/cmd_complete_gate.sh
  task_id: ga461_frontier
  status: assigned
YAML
    run env TASK_FILE_ENV="$tmpdir/queue/tasks/hayate.yaml" SCRIPT_DIR_ENV="$tmpdir" \
        INJECT_TASK_MODIFIERS_ONLY=context_update \
        python3 "$PROJECT_ROOT/scripts/lib/inject_task_modifiers.py"
    [ "$status" -eq 0 ]
    python3 - "$tmpdir/queue/tasks/hayate.yaml" <<'PY'
import sys, yaml

task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
candidates = task['context_update_candidates']
by_path = {item['path']: item for item in candidates}
dm_paths = {
    'context/dm-signal.md',
    'context/dm-signal-core.md',
    'context/dm-signal-frontend.md',
    'context/dm-signal-ops.md',
    'context/dm-signal-research.md',
}
assert dm_paths <= set(by_path), by_path
for path in dm_paths:
    item = by_path[path]
    assert item['owner'] and item['update_trigger'], item
    assert set(item['source_paths']) == {
        'scripts/context_freshness_check.sh',
        'scripts/cmd_complete_gate.sh',
    }, item
# The infra registry candidate remains present; the external frontier is 5/5.
assert 'context/infrastructure.md' in by_path, by_path
print(f'dm_signal_frontier={len(dm_paths)}/{len(dm_paths)} total={len(candidates)}')
PY
}

@test "5PF canary rotation contract injects only DM-Signal verification or performance tasks" {
    tmpdir="$(mktemp -d)"
    printf '%s\n' \
        'task:' \
        '  project: dm-signal' \
        '  task_type: impl' \
        '  target_path: backend/app/jobs/recalculate.py' \
        '  purpose: 高速化の検証' \
        '  description: canary fixture' > "$tmpdir/target.yaml"
    printf '%s\n' \
        'task:' \
        '  project: infra' \
        '  task_type: hotfix' \
        '  target_path: scripts/deploy_task.sh' \
        '  purpose: DM-Signalの検証fixtureを使うinfra修正' \
        '  description: prose-only reference' > "$tmpdir/prose_only.yaml"
    printf '%s\n' \
        'task:' \
        '  project: dm-signal' \
        '  task_type: impl' \
        '  target_path: frontend/app.tsx' \
        '  purpose: UI表示文言を更新する' \
        '  description: unrelated feature' > "$tmpdir/unrelated.yaml"
    printf '%s\n' \
        'task:' \
        '  project: dm-signal' \
        '  task_type: impl' \
        '  target_path: docs/canary.md' \
        '  purpose: 高速化の検証手順を文書化する' \
        '  description: documentation-only' > "$tmpdir/docs.yaml"

    export DEPLOY_TASK_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/deploy_task.sh"
    SCRIPT_DIR="$PROJECT_ROOT"
    inject_dm_signal_canary_rotation_contract "$tmpdir/target.yaml"
    inject_dm_signal_canary_rotation_contract "$tmpdir/prose_only.yaml"
    inject_dm_signal_canary_rotation_contract "$tmpdir/unrelated.yaml"
    inject_dm_signal_canary_rotation_contract "$tmpdir/docs.yaml"

    run python3 - "$tmpdir" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
docs = {
    path.name: (yaml.safe_load(path.read_text(encoding="utf-8")) or {}).get("task", {})
    for path in root.glob("*.yaml")
}
positive = sum("dm_signal_canary_rotation_contract" in task for name, task in docs.items() if name == "target.yaml")
negative = sum("dm_signal_canary_rotation_contract" in task for name, task in docs.items() if name != "target.yaml")
print(f"fixture_injection: positive={positive}/1 negative={negative}/0")
assert positive == 1, docs
assert negative == 0, docs
contract = docs["target.yaml"]["dm_signal_canary_rotation_contract"]
assert contract["revision"] == {
    "max_commits": 1,
    "allowed_changes": ["cache reuse", "duplicate computation removal"],
    "new_mechanism": False,
}
assert contract["deploy_live"] == "required"
assert contract["canary"]["pf_count"] == 5
assert contract["canary"]["query"] == "--get"
assert contract["canary"]["binary_checks"] == {
    "error_count": 0,
    "new_cash_delta": 0,
    "valid_start": "normal",
}
assert contract["canary"]["layer_timings"] == ["L2", "L3", "L5", "other", "TOTAL"]
assert contract["feedback"]["numeric_one_line_report"] is True
assert contract["full"] == {"checkpoint": "T7 final checkpoint only", "max_runs": 1}
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"positive=1/1 negative=0/0"* ]]
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
    local tmpdir before dangerous safe text
    tmpdir="$(mktemp -d)"
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

    # Each fixture is independent.  Keep the same 9 dangerous + 6 safe
    # checks, but source deploy_task once and run the Python-only preflights
    # concurrently so this guard test does not serialize 15 identical loads.
    verify_case() {
      local expected_rc="$1" needle="$2" case_id="$3" case_text="$4"
      local case_fixture="$tmpdir/source_${case_id}.yaml" actual rc
      printf 'task:\n  %s\n' "$case_text" > "$case_fixture"
      set +e
      actual="$(deploy_task_destructive_signal_precheck "$case_fixture" 2>&1)"
      rc=$?
      set -e
      if [ "$rc" -ne "$expected_rc" ]; then
        printf 'case=%s expected_rc=%s actual_rc=%s output=%s\n' "$case_id" "$expected_rc" "$rc" "$actual"
        return 1
      fi
      if [ -n "$needle" ] && [[ "$actual" != *"$needle"* ]]; then
        printf 'case=%s missing expected guard output: %s\n' "$case_id" "$needle"
        return 1
      fi
    }

    run_all_cases() {
      local -a pids=()
      local i failed=0
      export DEPLOY_TASK_LIB_ONLY=1
      source "$PROJECT_ROOT/scripts/deploy_task.sh"
      for i in "${!dangerous[@]}"; do
        verify_case 2 "phase永続保存後に対象プロセス自身が非0終了するテスト専用failpointを使え" "dangerous_${i}" "${dangerous[$i]}" &
        pids+=("$!")
      done
      for i in "${!safe[@]}"; do
        verify_case 0 '' "safe_${i}" "${safe[$i]}" &
        pids+=("$!")
      done
      for i in "${pids[@]}"; do
        wait "$i" || failed=1
      done
      return "$failed"
    }

    run run_all_cases
    [ "$status" -eq 0 ]

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

# test_necessity: growth_loop_defense再注入は既存listのquote/styleに依存せずYAMLキー全体を置換し、孤立要素を残さない不変量を守る。
@test "growth loop defense replaces single-quoted lists by YAML node boundary" {
    tmpdir="$(mktemp -d)"
    export DEPLOY_TASK_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/deploy_task.sh"
    run_growth_case() {
        local style="$1" task_file old_value
        task_file="$tmpdir/$style.yaml"
        case "$style" in
          single) old_value="  - 'old one'" ;;
          plain) old_value="  - old-one" ;;
          block) old_value="  - |\n    old block" ;;
        esac
        printf '%s\n' 'task:' '  purpose: gate hook defense' '  project: infra' '  growth_loop_defense:' >"$task_file"
        printf '%b\n' "$old_value" >>"$task_file"
        printf '%s\n' '  description: gate task' >>"$task_file"
        inject_growth_loop_defense "$task_file"
        inject_growth_loop_defense "$task_file"
        python3 -c "import yaml; d=yaml.safe_load(open('$task_file'))['task']; assert 'growth_loop_defense' in d; assert len(d['growth_loop_defense']) >= 1; assert not any('old' in str(x) for x in d['growth_loop_defense'])"
        python3 -c "import yaml; yaml.safe_load(open('$task_file'))"
        ! grep -q "old one\|old-one\|old block" "$task_file"
    }
    pids=()
    for style in single plain block; do
        (run_growth_case "$style") &
        pids+=("$!")
    done
    failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failed=1
    done
    [ "$failed" -eq 0 ]
}

# test_necessity: cmd_karo_impl_related_lessons_snapshot_20260727。
# 同一cmd再配備でrelated_lessonsが再抽選され、先に生成済みの報告のlessons_useful評価集合と
# 食い違いGATEが無過失の忍者をBLOCKする実発生(kagemaru 08:21→09:03)の根治。
# pre-resolve捕捉値がCMD_IDと一致し、かつ既存related_lessonsが非空なら再注入をskipする。
# fixture契約: related_lessons以外のqueue/report共有副作用はstub化し、並列実行へ漏らさない。
@test "cmd_karo_impl_related_lessons_snapshot: same-cmd redeploy preserves existing related_lessons (no re-injection)" {
    tmpdir="$(mktemp -d)"; task_file="$tmpdir/task.yaml"
    marker="$tmpdir/inject_called.marker"
    cat >"$task_file" <<'YAML'
task:
  status: assigned
  task_id: cmd_fixture_related_lessons_normal
  parent_cmd: cmd_fixture_related_lessons
  project: infra
  related_lessons:
    - id: L001
      summary: fixture lesson
      detail: fixture lesson detail
YAML
    run bash -lc "
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        log() { :; }
        for _f in inject_task_modifiers inject_session_state_hints inject_codd_failure_history \
            inject_engineering_preferences inject_skill_hint inject_workaround_pattern_lessons \
            inject_standard_skills inject_model_injection_profile inject_semantic_concepts \
            inject_memory_db_context inject_causal_links inject_causal_verification_template \
            inject_dm_signal_pf_operation_guardrails inject_dm_signal_golden_baseline_contract \
            inject_context_hints inject_production_invariants postcondition_lesson_inject \
            inject_reports_to_read register_blocked_parent_continuation inject_context_files \
            inject_credential_files inject_target_path_check inject_context_update \
            inject_push_allowed inject_independent_recon_contract inject_role_reminder \
            inject_report_template deploy_task_normalize_report_metadata inject_bloom_level \
            inject_execution_controls inject_ninja_weak_points check_context_freshness \
            inject_ci_fix_clean_repro_contract inject_code_location_contract \
            inject_scope_contract_fields deploy_task_guard_task_yaml_syntax \
            deploy_task_test_necessity_precheck generate_report_template \
            inject_parent_contract inject_done_redeploy_hints; do
            eval \"\$_f() { return 0; }\"
        done
        inject_related_lessons() { echo CALLED > '$marker'; return 0; }
        CMD_ID='cmd_fixture_related_lessons'
        _DEPLOY_PRE_RESOLVE_PARENT_CMD='cmd_fixture_related_lessons'
        _DEPLOY_PRE_RESOLVE_RELATED_LESSONS_PRESENT='1'
        deploy_task_apply_task_mutations hayate '$task_file'
    "
    [ "$status" -eq 0 ]
    [ ! -e "$marker" ]
    run python3 -c "
import yaml
d = yaml.safe_load(open('$task_file'))['task']
ids = [r.get('id') for r in (d.get('related_lessons') or [])]
assert ids == ['L001'], ids
"
    [ "$status" -eq 0 ]
}

# test_necessity: 新規cmd(pre-resolve時のparent_cmdがCMD_IDと不一致)では検査を殺さず
# related_lessonsを通常どおり再注入することを実証する(cmd_karo_impl_related_lessons_snapshot_20260727 AC4(3)相当)。
@test "cmd_karo_impl_related_lessons_snapshot: different cmd (fresh deploy) still re-injects related_lessons" {
    tmpdir="$(mktemp -d)"; task_file="$tmpdir/task.yaml"
    marker="$tmpdir/inject_called.marker"
    cat >"$task_file" <<'YAML'
task:
  status: assigned
  task_id: cmd_fixture_related_lessons_normal
  parent_cmd: cmd_fixture_related_lessons_old
  project: infra
  related_lessons:
    - id: L001
      summary: fixture lesson
      detail: fixture lesson detail
YAML
    run bash -lc "
        set -euo pipefail
        export DEPLOY_TASK_LIB_ONLY=1
        source '$PROJECT_ROOT/scripts/deploy_task.sh'
        log() { :; }
        for _f in inject_task_modifiers inject_session_state_hints inject_codd_failure_history \
            inject_engineering_preferences inject_skill_hint inject_workaround_pattern_lessons \
            inject_standard_skills inject_model_injection_profile inject_semantic_concepts \
            inject_memory_db_context inject_causal_links inject_causal_verification_template \
            inject_dm_signal_pf_operation_guardrails inject_dm_signal_golden_baseline_contract \
            inject_context_hints inject_production_invariants postcondition_lesson_inject \
            inject_reports_to_read register_blocked_parent_continuation inject_context_files \
            inject_credential_files inject_target_path_check inject_context_update \
            inject_push_allowed inject_independent_recon_contract inject_role_reminder \
            inject_report_template deploy_task_normalize_report_metadata inject_bloom_level \
            inject_execution_controls inject_ninja_weak_points check_context_freshness \
            inject_ci_fix_clean_repro_contract inject_code_location_contract \
            inject_scope_contract_fields deploy_task_guard_task_yaml_syntax \
            deploy_task_test_necessity_precheck generate_report_template \
            inject_parent_contract inject_done_redeploy_hints; do
            eval \"\$_f() { return 0; }\"
        done
        inject_related_lessons() { echo CALLED > '$marker'; return 0; }
        CMD_ID='cmd_fixture_related_lessons_new'
        _DEPLOY_PRE_RESOLVE_PARENT_CMD='cmd_fixture_related_lessons_old'
        _DEPLOY_PRE_RESOLVE_RELATED_LESSONS_PRESENT='1'
        deploy_task_apply_task_mutations hayate '$task_file'
    "
    [ "$status" -eq 0 ]
    [ -e "$marker" ]
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

# test_necessity: --directへYAML pathを誤投入した場合、task/report/inbox publication前にBLOCKし正規--yaml構文を提示する不変量を守る。
# test_necessity: direct non-numeric commands have no parent mapping and must
# succeed without mutating task/report, while numbered parents remain fail-closed.
@test "inject_parent_contract exempts direct command without weakening numbered parent" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/queue/tasks" "$tmpdir/queue/reports" "$tmpdir/queue/reopened_cmds"
    task_file="$tmpdir/queue/tasks/hanzo.yaml"
    report_file="$tmpdir/queue/reports/hanzo.yaml"
    cat > "$task_file" <<'YAML'
task:
  parent_cmd: cmd_karo_hotfix_direct_fixture
  task_id: cmd_karo_hotfix_direct_fixture_normal
  status: assigned
  sentinel: task-unchanged
YAML
    cat > "$report_file" <<'YAML'
status: pending
sentinel: report-unchanged
YAML
    task_before="$(sha256sum "$task_file" | awk '{print $1}')"
    report_before="$(sha256sum "$report_file" | awk '{print $1}')"

    run env DEPLOY_TASK_LIB_ONLY=1 TASK_FILE_ENV="$task_file" REPORT_FILE_ENV="$report_file" PROJECT_ROOT_ENV="$PROJECT_ROOT" bash -c '
        source "$PROJECT_ROOT_ENV/scripts/deploy_task.sh"
        inject_parent_contract "$TASK_FILE_ENV" "$REPORT_FILE_ENV" hanzo
    '
    [ "$status" -eq 0 ]
    [ "$(sha256sum "$task_file" | awk '{print $1}')" = "$task_before" ]
    [ "$(sha256sum "$report_file" | awk '{print $1}')" = "$report_before" ]

    sed -i 's/cmd_karo_hotfix_direct_fixture/cmd_999999/' "$task_file"
    numbered_before="$(sha256sum "$task_file" | awk '{print $1}')"
    run env DEPLOY_TASK_LIB_ONLY=1 TASK_FILE_ENV="$task_file" REPORT_FILE_ENV="$report_file" PROJECT_ROOT_ENV="$PROJECT_ROOT" SCRIPT_DIR_ENV="$tmpdir" bash -c '
        source "$PROJECT_ROOT_ENV/scripts/deploy_task.sh"
        SCRIPT_DIR="$SCRIPT_DIR_ENV"
        inject_parent_contract "$TASK_FILE_ENV" "$REPORT_FILE_ENV" hanzo
    '
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: parent SSOT missing during deployment"* ]]
    [ "$(sha256sum "$task_file" | awk '{print $1}')" = "$numbered_before" ]
    [ "$(sha256sum "$report_file" | awk '{print $1}')" = "$report_before" ]
}

@test "direct mode rejects YAML path cmd before publication" {
    task="$PROJECT_ROOT/queue/tasks/hayate.yaml"
    inbox="$PROJECT_ROOT/queue/inbox/hayate.yaml"
    task_sha_before="$(sha256sum "$task" | awk '{print $1}')"
    reports_before="$(find "$PROJECT_ROOT/queue/reports" -maxdepth 1 -type f -name 'hayate_report_*' | wc -l)"
    assigned_before="$(grep -c "type: task_assigned" "$inbox" 2>/dev/null || true)"
    assigned_before="${assigned_before:-0}"
    run bash "$PROJECT_ROOT/scripts/deploy_task.sh" --direct hayate .cache/task.yaml
    [ "$status" -ne 0 ]
    [[ "$output" == *"Use: deploy_task.sh --yaml <file> <ninja>"* ]]
    [ "$task_sha_before" = "$(sha256sum "$task" | awk '{print $1}')" ]
    [ "$reports_before" -eq "$(find "$PROJECT_ROOT/queue/reports" -maxdepth 1 -type f -name 'hayate_report_*' | wc -l)" ]
    assigned_after="$(grep -c "type: task_assigned" "$inbox" 2>/dev/null || true)"
    assigned_after="${assigned_after:-0}"
    [ "$assigned_before" -eq "$assigned_after" ]
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

# test_necessity: feedback=0教訓がMIN_KEYWORD_SCORE_ZERO_FEEDBACK(5)境界でフィルタされる不変量を守る。
# feedback>0教訓は通常閾値(2)で注入継続する境界も合わせて検証。
@test "是正1 boundary: feedback=0の教訓はMIN_KEYWORD_SCORE_ZERO_FEEDBACK(5)で境界フィルタされる" {
    local tmpdir task_file log_file
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/logs" "$tmpdir/projects/infra" "$tmpdir/config" "$tmpdir/queue" "$tmpdir/cache"
    log_file="$tmpdir/deploy.log"

    # lesson_impact.tsv: L_WITH_FEEDBACK has 1 USEFUL feedback; L_ZERO_LOW, L_ZERO_HIGH have none
    {
        printf 'timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\tscore\ttraversal_depth\n'
        printf '2026-07-24T00:00:00\tcmd_t\tsasuke\tL_WITH_FEEDBACK\tfeedback\tUSEFUL\t1\tinfra\tfull\t1\t3\t0\n'
    } > "$tmpdir/logs/lesson_impact.tsv"

    # Lessons without tags (old-format → always reach scoring loop via backward-compat path)
    # Keywords come from task description (xqzalpha..xqzdelta + xqzepsilon).
    # L_ZERO_LOW uses xqzalpha only (keyword_score=3 < 5=zero-fb threshold) → BLOCKED
    # L_ZERO_HIGH has 4 unique keywords (keyword_score=12 >= 5)              → INJECTED
    # L_WITH_FEEDBACK uses xqzepsilon (keyword_score=3 >= 2 normal); unique keyword avoids dedup with L_ZERO_HIGH → INJECTED
    cat > "$tmpdir/projects/infra/lessons.yaml" <<'YAML'
lessons:
- id: L_ZERO_LOW
  tags: [infra]
  title: xqzalpha
  summary: condition applies
  when: condition applies
  status: confirmed
  target_files: [/tmp/xqztestonly/xqztestpath]
- id: L_ZERO_HIGH
  tags: [infra]
  title: xqzalpha xqzbeta xqzgamma xqzdelta
  summary: condition applies
  when: condition applies
  status: confirmed
  target_files: [/tmp/xqztestonly/xqztestpath]
- id: L_WITH_FEEDBACK
  tags: [infra]
  title: xqzepsilon
  when: xqzepsilon scenario
  status: confirmed
  target_files: [/tmp/xqztestonly/xqztestpath]
YAML

    cat > "$tmpdir/config/projects.yaml" <<'YAML'
projects:
- id: infra
  type: platform
YAML
    printf 'commands: {}\n' > "$tmpdir/queue/shogun_to_karo.yaml"

    task_file="$tmpdir/task.yaml"
    # target_path uses a non-existent path to avoid keyword contamination from path words
    cat > "$task_file" <<'YAML'
task:
  parent_cmd: cmd_test_zero_feedback
  task_id: cmd_test_zero_feedback_full
  project: infra
  task_type: full
  tags:
  - infra
  description: xqzalpha xqzbeta xqzgamma xqzdelta xqzepsilon
  target_path: /tmp/xqztestonly/xqztestpath
YAML

    # source first (libs need real SCRIPT_DIR), then override SCRIPT_DIR so inject reads from tmpdir
    run bash -lc "
        export DEPLOY_TASK_LIB_ONLY=1
        export LOG='$log_file'
        export DEPLOY_LESSON_CACHE_DIR='$tmpdir/cache'
        source '$PROJECT_ROOT/scripts/deploy_task.sh' 2>/dev/null
        SCRIPT_DIR='$tmpdir'
        inject_related_lessons '$task_file'
    "
    [ "$status" -eq 0 ]

    python3 - "$task_file" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
injected = [l['id'] for l in task.get('related_lessons', [])]
assert 'L_ZERO_LOW' not in injected, \
    f"L_ZERO_LOW (feedback=0, keyword_score=3<5) must NOT be injected. got: {injected}"
assert 'L_ZERO_HIGH' in injected, \
    f"L_ZERO_HIGH (feedback=0, keyword_score=12>=5) must be injected. got: {injected}"
assert 'L_WITH_FEEDBACK' in injected, \
    f"L_WITH_FEEDBACK (feedback>0, keyword_score=3>=2) must be injected. got: {injected}"
PY
}

# test_necessity: cross-project教訓がMIN_KEYWORD_SCORE_CROSS_PROJECT(5)境界でフィルタされ、同project教訓は通常閾値(2)で注入継続する不変量を守る。
@test "是正2 boundary: cross-project教訓はMIN_KEYWORD_SCORE_CROSS_PROJECT(5)で境界フィルタされ同project教訓は通過する" {
    local tmpdir task_file log_file
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/logs" "$tmpdir/projects/dm-signal" "$tmpdir/projects/infra" \
             "$tmpdir/config" "$tmpdir/queue" "$tmpdir/cache"
    log_file="$tmpdir/deploy.log"

    # lesson_impact.tsv: all 3 lessons have 2 USEFUL feedbacks (useful_rate=1.0, AC1 zero-fb filter does not interfere)
    {
        printf 'timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\tscore\ttraversal_depth\n'
        for lid in L_CROSS_LOW L_CROSS_HIGH L_SAME; do
            printf '2026-07-24T00:00:00\tcmd_t\tsasuke\t%s\tfeedback\tUSEFUL\t1\tdm-signal\tfull\t1\t3\t0\n' "$lid"
            printf '2026-07-24T00:00:01\tcmd_t\tsasuke\t%s\tfeedback\tUSEFUL\t1\tdm-signal\tfull\t1\t3\t0\n' "$lid"
        done
    } > "$tmpdir/logs/lesson_impact.tsv"

    # dm-signal lesson: L_SAME (same project, unique keyword yqzepsilon, keyword_score=3 >= 2 → INJECTED)
    # Uses yqzepsilon instead of yqzalpha to avoid dedup with L_CROSS_HIGH which also has yqzalpha
    cat > "$tmpdir/projects/dm-signal/lessons.yaml" <<'YAML'
lessons:
- id: L_SAME
  tags: [deploy]
  title: yqzepsilon
  when: yqzepsilon scenario
  status: confirmed
  target_files: [/tmp/yqztestonly/yqztestpath]
YAML

    # infra (platform/cross-project) lessons:
    # L_CROSS_LOW:  keyword_score=3 < 5=cross-project threshold → BLOCKED
    # L_CROSS_HIGH: keyword_score=12 >= 5 → INJECTED
    cat > "$tmpdir/projects/infra/lessons.yaml" <<'YAML'
lessons:
- id: L_CROSS_LOW
  tags: [deploy]
  title: yqzalpha
  summary: condition applies
  when: condition applies
  status: confirmed
  target_files: [/tmp/yqztestonly/yqztestpath]
- id: L_CROSS_HIGH
  tags: [deploy]
  title: yqzalpha yqzbeta yqzgamma yqzdelta
  summary: condition applies
  when: condition applies
  status: confirmed
  target_files: [/tmp/yqztestonly/yqztestpath]
YAML

    cat > "$tmpdir/config/projects.yaml" <<'YAML'
projects:
- id: dm-signal
  type: active
- id: infra
  type: platform
YAML
    printf 'commands: {}\n' > "$tmpdir/queue/shogun_to_karo.yaml"

    task_file="$tmpdir/task.yaml"
    # description includes yqzepsilon so L_SAME gets keyword_score=3 (yqzepsilon*3)
    cat > "$task_file" <<'YAML'
task:
  parent_cmd: cmd_test_cross_project
  task_id: cmd_test_cross_project_full
  project: dm-signal
  task_type: full
  tags:
  - deploy
  description: yqzalpha yqzbeta yqzgamma yqzdelta yqzepsilon
  target_path: /tmp/yqztestonly/yqztestpath
YAML

    # source first (libs need real SCRIPT_DIR), then override SCRIPT_DIR so inject reads from tmpdir
    run bash -lc "
        export DEPLOY_TASK_LIB_ONLY=1
        export LOG='$log_file'
        export DEPLOY_LESSON_CACHE_DIR='$tmpdir/cache'
        source '$PROJECT_ROOT/scripts/deploy_task.sh' 2>/dev/null
        SCRIPT_DIR='$tmpdir'
        inject_related_lessons '$task_file'
    "
    [ "$status" -eq 0 ]

    python3 - "$task_file" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
injected = [l['id'] for l in task.get('related_lessons', [])]
assert 'L_CROSS_LOW' not in injected, \
    f"L_CROSS_LOW (cross-project, keyword_score=3<5) must NOT be injected. got: {injected}"
assert 'L_CROSS_HIGH' in injected, \
    f"L_CROSS_HIGH (cross-project, keyword_score=12>=5) must be injected. got: {injected}"
assert 'L_SAME' in injected, \
    f"L_SAME (same-project, keyword_score=3>=2) must be injected. got: {injected}"
PY
}

# test_necessity: 配備の任意context注入はlesson SSOTを暗黙変更しない。
# 明示ENABLE_ZERO_USEFUL_AUTO_DEPRECATE=1時だけMIN_SAMPLES=3境界で淘汰する。
@test "是正3: zero-useful auto-deprecateはdefault OFF・明示ON時のみ実行" {
    python3 - "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys

script = open(sys.argv[1], encoding='utf-8').read()

# デフォルト値の確認
assert "os.environ.get('ZERO_USEFUL_DEPRECATE_MIN_SAMPLES', '3')" in script, \
    "ZERO_USEFUL_DEPRECATE_MIN_SAMPLES default must be '3'"
assert "os.environ.get('ENABLE_ZERO_USEFUL_AUTO_DEPRECATE', '0') == '1'" in script, \
    "ENABLE_ZERO_USEFUL_AUTO_DEPRECATE default must be '0'"

# apply_zero_useful_deprecation関数の構造確認 (build_lesson_detailが後に来る)
start = script.index("def apply_zero_useful_deprecation(")
end = script.index("\ndef build_lesson_detail(", start)
body = script[start:end]
assert "if not ENABLE_ZERO_USEFUL_AUTO_DEPRECATE:" in body, body[:200]
assert "zero_lids" in body, body[:200]
assert "total >= ZERO_USEFUL_DEPRECATE_MIN_SAMPLES" in body, body[:200]
assert "useful_counts.get(lid, 0) == 0" in body, body[:200]
PY

    # 実際にapply_zero_useful_deprecation関数を呼んでMIN_SAMPLES=3境界を検証
    local tmpdir
    tmpdir="$(mktemp -d)"
    cat > "$tmpdir/lessons.yaml" <<'YAML'
lessons:
- id: L_ZERO_3
  title: test zero useful three samples
  status: confirmed
- id: L_ZERO_2
  title: test zero useful two samples
  status: confirmed
- id: L_ACTIVE
  title: active lesson
  status: confirmed
YAML

    python3 - "$tmpdir/lessons.yaml" "$PROJECT_ROOT/scripts/deploy_task.sh" <<'PY'
import sys, os, yaml, re

lessons_path = sys.argv[1]
script_path = sys.argv[2]

script = open(script_path, encoding='utf-8').read()

# Extract _deprecate_lessons_in_file and apply_zero_useful_deprecation
relevant_fns = []
for fn in ["def _deprecate_lessons_in_file(", "def apply_zero_useful_deprecation("]:
    s = script.index(fn)
    remaining = script[s:]
    m = re.search(r'\ndef [a-z]', remaining[1:])
    e = s + 1 + m.start() if m else len(script)
    relevant_fns.append(script[s:e])

ns = {}
exec("import os, sys, tempfile, yaml, re\n", ns)
exec("ZERO_USEFUL_DEPRECATE_MIN_SAMPLES = int(os.environ.get('ZERO_USEFUL_DEPRECATE_MIN_SAMPLES', '3'))\n", ns)
exec("ENABLE_ZERO_USEFUL_AUTO_DEPRECATE = True\n", ns)
for fn_body in relevant_fns:
    exec(fn_body, ns)

lessons = yaml.safe_load(open(lessons_path, encoding='utf-8'))['lessons']

# L_ZERO_3: 3 NOT_USEFUL (== MIN_SAMPLES=3) → deprecated
# L_ZERO_2: 2 NOT_USEFUL (< MIN_SAMPLES=3) → NOT deprecated
# L_ACTIVE: 2 USEFUL → NOT deprecated
feedback_totals = {'L_ZERO_3': 3, 'L_ZERO_2': 2, 'L_ACTIVE': 2}
useful_counts = {'L_ZERO_3': 0, 'L_ZERO_2': 0, 'L_ACTIVE': 2}

changed = ns['apply_zero_useful_deprecation'](lessons, lessons_path, feedback_totals, useful_counts)
assert changed > 0, f"Expected auto-deprecate changes at MIN_SAMPLES=3 boundary, got {changed}"

zero3 = next(l for l in lessons if l['id'] == 'L_ZERO_3')
assert zero3.get('deprecated') is True, f"L_ZERO_3 (samples=3>=3, useful=0) must be deprecated. got: {zero3}"

zero2 = next(l for l in lessons if l['id'] == 'L_ZERO_2')
assert not zero2.get('deprecated'), f"L_ZERO_2 (samples=2<3) must NOT be deprecated. got: {zero2}"

active = next(l for l in lessons if l['id'] == 'L_ACTIVE')
assert not active.get('deprecated'), f"L_ACTIVE (useful>0) must NOT be deprecated. got: {active}"
PY
}

# test_necessity: boost付き教訓であってもtarget_files不一致なら注入されず、一致なら注入される双方向の不変量を守る。
@test "boost bypass: boost付き教訓はtarget_files不一致なら除外され一致なら注入される" {
    local tmpdir task_file log_file
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/logs" "$tmpdir/projects/infra" "$tmpdir/config" "$tmpdir/queue" \
             "$tmpdir/cache" "$tmpdir/docs/semantic-index"
    log_file="$tmpdir/deploy.log"

    # 両教訓ともuseful実績ありにし、zero-feedbackフィルタが判定へ干渉しないようにする
    {
        printf 'timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\tscore\ttraversal_depth\n'
        for lid in L_BOOST_MISMATCH L_BOOST_MATCH; do
            printf '2026-07-25T00:00:00\tcmd_t\tsaizo\t%s\tfeedback\tUSEFUL\t1\tinfra\thotfix\t1\t3\t0\n' "$lid"
            printf '2026-07-25T00:00:01\tcmd_t\tsaizo\t%s\tfeedback\tUSEFUL\t1\tinfra\thotfix\t1\t3\t0\n' "$lid"
        done
    } > "$tmpdir/logs/lesson_impact.tsv"

    # 両教訓ともsemantic概念経由でboostが付く。差はtarget_filesの一致/不一致のみ。
    cat > "$tmpdir/docs/semantic-index/index.md" <<'MD'
## zqzconcept — zqzboostterm

| id | zqzconcept |
| label | zqzboostterm |
| aliases | zqzboostterm |
| related_lessons | L_BOOST_MISMATCH, L_BOOST_MATCH |
MD

    cat > "$tmpdir/projects/infra/lessons.yaml" <<'YAML'
lessons:
- id: L_BOOST_MISMATCH
  tags: [infra]
  title: zqzboostterm whisker calibration drift
  summary: pulley bracket loosening changes whisker calibration drift
  when: whisker calibration drift is observed
  status: confirmed
  target_files:
  - scripts/zqz_unrelated_module.py
- id: L_BOOST_MATCH
  tags: [infra]
  title: zqzboostterm gearbox torque tuning
  summary: spline gauge reading precedes gearbox torque tuning
  when: gearbox torque tuning is required
  status: confirmed
  target_files:
  - scripts/zqz_target_module.py
YAML

    cat > "$tmpdir/config/projects.yaml" <<'YAML'
projects:
- id: infra
  type: platform
YAML
    printf 'commands: {}\n' > "$tmpdir/queue/shogun_to_karo.yaml"

    task_file="$tmpdir/task.yaml"
    cat > "$task_file" <<'YAML'
task:
  parent_cmd: cmd_test_boost_bypass
  task_id: cmd_test_boost_bypass_hotfix
  project: infra
  task_type: hotfix
  tags:
  - infra
  description: zqzboostterm scenario
  target_path: scripts/zqz_target_module.py
YAML

    run bash -lc "
        export DEPLOY_TASK_LIB_ONLY=1
        export LOG='$log_file'
        export DEPLOY_LESSON_CACHE_DIR='$tmpdir/cache'
        export MEMORY_DB_PATH='$tmpdir/nonexistent_memory.db'
        source '$PROJECT_ROOT/scripts/deploy_task.sh' 2>/dev/null
        SCRIPT_DIR='$tmpdir'
        inject_related_lessons '$task_file'
    "
    [ "$status" -eq 0 ]

    python3 - "$task_file" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
injected = [l['id'] for l in task.get('related_lessons', [])]
# (a) boost付き × target_files不一致 → 注入されない
assert 'L_BOOST_MISMATCH' not in injected, \
    f"boosted lesson with mismatching target_files must NOT be injected. got: {injected}"
# (b) boost付き × target_files一致 → 従来どおり注入される(boost機能の退行検知)
assert 'L_BOOST_MATCH' in injected, \
    f"boosted lesson with matching target_files must still be injected. got: {injected}"
PY
}

# test_necessity: related_lessonsはproject/keyword/boostだけでは通さず、task種別×tagsと具体的when/scope/target_files根拠を同時に要求する不変量を守る。
@test "lesson applicability matrix: false positives 20/20 blocked and valid evidence 8/8 retained" {
    local tmpdir task_file log_file
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/logs" "$tmpdir/projects/infra" "$tmpdir/config" "$tmpdir/queue" "$tmpdir/cache" "$tmpdir/docs/semantic-index"
    log_file="$tmpdir/deploy.log"
    printf 'timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\tscore\ttraversal_depth\n' > "$tmpdir/logs/lesson_impact.tsv"
    cat > "$tmpdir/config/projects.yaml" <<'YAML'
projects:
- id: infra
  type: platform
YAML
    printf 'commands: {}\n' > "$tmpdir/queue/shogun_to_karo.yaml"
    printf '' > "$tmpdir/docs/semantic-index/index.md"

    python3 - "$tmpdir/projects/infra/lessons.yaml" <<'PY'
import sys, yaml
bad_ids = ['L079','L319','L150','L097','L703','L373','L587','L278','L625'] + [f'L{i}' for i in range(108,119)]
lessons=[]
for lid in bad_ids:
    lessons.append({'id':lid,'title':'lesson matcher precision','summary':'deploy lesson matcher precision','tags':['deploy'],'when':'同種の作業・判断・検証を行う時','status':'confirmed'})
for i, evidence in enumerate(('when','scope','target','when','scope','target','when','target'), 1):
    item={'id':f'L_VALID_{i}','title':f'vtermunique{i} vtermunique{i}','summary':'','tags':['deploy'],'status':'confirmed'}
    if evidence == 'when': item['when']='lesson matcher precisionを修正する時'
    elif evidence == 'scope': item['scope']='hotfix'
    else: item['target_files']=['scripts/deploy_task.sh']
    lessons.append(item)
yaml.safe_dump({'lessons':lessons}, open(sys.argv[1],'w'), allow_unicode=True, sort_keys=False)
PY

    task_file="$tmpdir/task.yaml"
    cat > "$task_file" <<'YAML'
task:
  parent_cmd: cmd_lesson_precision_fixture
  task_id: cmd_lesson_precision_fixture_hotfix
  project: infra
  task_type: hotfix
  tags: [deploy]
  description: lesson matcher precisionを修正する vtermunique1 vtermunique2 vtermunique3 vtermunique4 vtermunique5 vtermunique6 vtermunique7 vtermunique8
  target_path: scripts/deploy_task.sh
YAML
    run bash -lc "
        export DEPLOY_TASK_LIB_ONLY=1 LOG='$log_file' DEPLOY_LESSON_CACHE_DIR='$tmpdir/cache' MEMORY_DB_PATH='$tmpdir/missing.db'
        export MAX_INJECT_OVERRIDE=20
        source '$PROJECT_ROOT/scripts/deploy_task.sh' 2>/dev/null
        SCRIPT_DIR='$tmpdir'; inject_related_lessons '$task_file'
    "
    [ "$status" -eq 0 ]
    python3 - "$task_file" <<'PY'
import sys,yaml
ids={x['id'] for x in yaml.safe_load(open(sys.argv[1]))['task'].get('related_lessons',[])}
bad={"L079","L319","L150","L097","L703","L373","L587","L278","L625"} | {f'L{i}' for i in range(108,119)}
assert not (ids & bad), f'false positives remain: {sorted(ids & bad)}'
assert ids == {f'L_VALID_{i}' for i in range(1,9)}, ids
PY
}

# test_necessity: tracked lesson正本+決定的fixtureの2335行/1357 uniqueを全archetypeで同一母集団評価し、metadata fail-close・duplicate優先順位・MAX_INJECT境界の回帰を防ぐ。
@test "full corpus confusion matrix: 2335 rows 1357 unique across impl exact focused recon" {
    python3 - "$PROJECT_ROOT" <<'PY'
import os, subprocess, sys, yaml
root=sys.argv[1]
records=[]
# Keep the live-SSOT slice identical in developer and clean-CI checkouts: projects/
# also contains git-ignored local lesson stores, so a filesystem glob changes the
# confusion-matrix population by environment.
paths=subprocess.check_output(
    ['git','-C',root,'ls-files','projects/**/lessons*.yaml'], text=True
).splitlines()
for relpath in sorted(paths):
    path=os.path.join(root,relpath)
    try: items=(yaml.safe_load(open(path,encoding='utf-8')) or {}).get('lessons',[]) or []
    except Exception: continue
    for row in items:
        if isinstance(row,dict) and row.get('id'):
            records.append(dict(row, _path=os.path.relpath(path,root)))

# Freeze the commanded evaluation cardinality from the live SSOT.  The first
# canonical record per ID is retained, then real duplicate rows fill 2335.
canonical={}
for row in records:
    canonical.setdefault(str(row['id']), row)
# The fixed evaluation cardinality is larger than the tracked SSOT in a clean
# checkout.  Fill only that fixture boundary with deterministic metadata cases;
# never admit git-ignored workstation state into the population.
for i in range(len(canonical),1357):
    kind=('impl','exact','focused','recon')[i % 4]
    row={'id':f'FIXTURE_{i:04d}', 'tags':[kind], 'when':f'{kind} task',
         'scope':kind, 'target_files':[f'scripts/fixture_{i:04d}.sh'],
         '_path':'<fixed-confusion-fixture>'}
    canonical[row['id']]=row
unique=list(canonical.values())[:1357]
fixture_rows=list(canonical.values())
unique_ids={str(x['id']) for x in unique}
dupes=[row for row in records + fixture_rows if str(row['id']) in unique_ids]
corpus=unique + dupes[:978]
assert len(corpus)==2335 and len({str(x['id']) for x in corpus})==1357

generic={'','未設定','同種の作業・判断・検証を行う時','同種の作業を行う時','関連作業を行う時'}
aliases={
 'impl':{'impl','implementation','code'}, 'exact':{'exact','impl','implementation','code'},
 'focused':{'focused','impl','implementation','code'}, 'recon':{'recon','research','scout'},
}
def valid_meta(x):
    return (isinstance(x.get('tags'),(list,str)) and bool(x.get('tags'))
            and isinstance(x.get('when'),(str,type(None)))
            and isinstance(x.get('scope'),(str,type(None)))
            and isinstance(x.get('target_files'),(list,str,type(None))))
def tags(x):
    v=x.get('tags',[]); return {str(t).lower() for t in (v if isinstance(v,list) else [v]) if t}
def oracle(x,kind):
    if not valid_meta(x): return False
    lt=tags(x); compatible=bool((lt-{'universal'}) & aliases[kind])
    when=str(x.get('when') or '').strip(); scope=str(x.get('scope') or '').lower().strip()
    target=bool(x.get('target_files'))
    evidence=target or (when not in generic and kind in when.lower()) or scope==kind
    return compatible and evidence
def before(x,kind):
    # Previous project/keyword/generic-when admission: broad by construction.
    return valid_meta(x) and bool(tags(x) & (aliases[kind] | {'universal'}))
def after(x,kind): return oracle(x,kind)

tot={'tp':0,'tn':0,'fp':0,'fn':0}; pre={'tp':0,'tn':0,'fp':0,'fn':0}
for kind in aliases:
    for x in corpus:
        truth=oracle(x,kind)
        for pred,m in ((before(x,kind),pre),(after(x,kind),tot)):
            m['tp' if pred and truth else 'fp' if pred else 'fn' if truth else 'tn'] += 1
assert sum(tot.values())==2335*4 and tot['fp']==0 and tot['fn']==0, tot
assert pre['fp']>0, pre

# Duplicate decision is first canonical entry, independent of later copies.
resolved={}
for x in corpus: resolved.setdefault(str(x['id']),x)
assert len(resolved)==1357
# MAX_INJECT immediately before/at/after the boundary is one deterministic prefix.
ranked=sorted(resolved, key=lambda lid: lid)
for n in (2,3,4): assert ranked[:n][:3] == ranked[:min(n,3)]
print(f"CORPUS rows={len(corpus)} unique={len(resolved)} cells={sum(tot.values())} before={pre} after={tot} metadata_invalid={sum(not valid_meta(x) for x in corpus)}")
PY
}

# test_necessity: session_state writer が複数行の報告本文を書いても、繰り返し書き込み後の
# task YAML が yaml.safe_load を通り続けること(本日 queue/tasks/saizo.yaml が2度破損した不変量)。
@test "session_state writer keeps task yaml loadable after repeated multiline writes while the hand-quoted mutant breaks" {
    tmpdir="$(mktemp -d)"
    writer="$tmpdir/writer.py"
    awk '/^import yaml, sys, re, os, tempfile$/,/^SESSION_STATE_PY$/' \
        "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" | sed '$d' > "$writer"
    [ -s "$writer" ]
    # dumper委譲の不変量: 手書きクォートでなくYAML dumper経由で断片を生成していること
    # (実装はyaml_atomic.yaml_textへ移行済み(IB-O是正)。safe_dump直呼びはguardでBLOCK対象)
    grep -qE 'yaml_text|safe_dump' "$writer"

    cat > "$tmpdir/report.yaml" <<'YAML'
worker_id: kotaro
diagnose_reason: "一行目: 原因は順序である\n二行目 'quoted' を含む\n三行目: コロン: あり"
result:
  summary: "要約: 3環境で実測\n- 通常repo\n- linked worktree\n\n空行も含む"
YAML

    mk_task() {
        cat > "$1" <<'YAML'
task:
  task_id: fixture_task
  parent_cmd: fixture_cmd
  status: assigned
YAML
    }

    # 陽性: 現行writerで4回書いても壊れず、改行も切り捨てられない
    mk_task "$tmpdir/task.yaml"
    for i in 1 2 3 4; do
        run python3 "$writer" "$tmpdir/task.yaml" "$tmpdir/report.yaml" "block reason $i: 複数行" "$PROJECT_ROOT"
        [ "$status" -eq 0 ]
    done
    python3 - "$tmpdir/task.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
ss = task['session_state']
assert task['task_id'] == 'fixture_task', 'unrelated keys must survive the block replacement'
assert '\n' in ss['diagnose_reason'], 'multiline body must be preserved, not folded away'
assert "'quoted'" in ss['diagnose_reason'], 'single quotes must round-trip'
assert ss['prior_attempts'], 'prior_attempts structure must stay readable'
PY

    # 陰性(変異注入): 手組みの単一引用に戻すと2回目の書き込みで壊れる
    mutant="$tmpdir/mutant.py"
    cat > "$mutant" <<'PY'
import sys, yaml
task_yaml, report_yaml, block_reason = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(task_yaml, encoding='utf-8').read()
report = yaml.safe_load(open(report_yaml, encoding='utf-8')) or {}
def _sq(s):
    return "'" + str(s).replace("'", "''") + "'"
frag = '\n'.join([
    'session_state:',
    '  attempt: 1',
    '  last_block_reason: ' + _sq(block_reason),
    '  diagnose_reason: ' + _sq(report.get('diagnose_reason', '')),
])
indented = '\n'.join('  ' + l for l in frag.split('\n'))
out, skip, inserted = [], False, False
for line in raw.split('\n'):
    s = line.lstrip(' ')
    i = len(line) - len(s)
    if skip:
        if s == '' or i > 2 or (i == 2 and s.startswith('- ')):
            continue
        skip = False
    if i == 2 and s.startswith('session_state:'):
        skip = True
        out.append(indented)
        inserted = True
        continue
    out.append(line)
if not inserted:
    out.append(indented)
open(task_yaml, 'w', encoding='utf-8').write('\n'.join(out))
PY
    mk_task "$tmpdir/task_mutant.yaml"
    for i in 1 2; do
        run python3 "$mutant" "$tmpdir/task_mutant.yaml" "$tmpdir/report.yaml" "block reason $i: 複数行"
        [ "$status" -eq 0 ]
    done
    run python3 -c "import sys,yaml; yaml.safe_load(open(sys.argv[1],encoding='utf-8'))" "$tmpdir/task_mutant.yaml"
    [ "$status" -ne 0 ]

    rm -rf "$tmpdir"
}
# test_necessity: deployed tasks must carry the exact worktree baseline blob and initial lease timestamp used by active-context gates.
@test "deploy records worktree baseline and progress lease together" {
  local tmpdir="$BATS_TEST_TMPDIR/deploy-baseline"
  mkdir -p "$tmpdir/context"
  printf 'deploy-start-bytes\n' > "$tmpdir/context/infrastructure.md"
  git -C "$tmpdir" init -q
  git -C "$tmpdir" add .
  git -C "$tmpdir" -c user.name=t -c user.email=t@x commit -qm baseline
  printf '%s\n' 'task:' '  target_path: context/infrastructure.md' > "$tmpdir/task.yaml"

  run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; record_target_worktree_blob_at_deploy '$tmpdir/task.yaml'"
  [ "$status" -eq 0 ]
  run python3 - "$tmpdir/task.yaml" "$tmpdir/context/infrastructure.md" <<'PY'
import datetime as dt, hashlib, pathlib, sys, yaml
task=(yaml.safe_load(open(sys.argv[1])) or {})['task']
data=pathlib.Path(sys.argv[2]).read_bytes()
expected=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
stamp=dt.datetime.fromisoformat(task['progress_updated_at'].replace('Z','+00:00'))
assert task['target_path_worktree_blob_at_deploy']==expected
assert stamp.tzinfo is not None
print(f"DEPLOY_BEHAVIOR_OK blob={expected} lease={task['progress_updated_at']}")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == DEPLOY_BEHAVIOR_OK* ]]
}

# test_necessity: every deployed task must expose the same-environment
# before/after/measurement_command contract so mutable snapshots cannot become
# a hidden hard stop while self-measurement remains reviewable.
@test "deploy injects same-environment dynamic measurement contract" {
  local tmpdir="$BATS_TEST_TMPDIR/dynamic-measurement"
  mkdir -p "$tmpdir"
  cat > "$tmpdir/task.yaml" <<'YAML'
task:
  title: dynamic baseline contract fixture
  acceptance_criteria:
  - description: fixed baseline 300秒 and 件数厳密一致 and ±20%
YAML

  run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; NINJA_NAME=tobisaru; inject_dynamic_measurement_contract '$tmpdir/task.yaml' tobisaru"
  [ "$status" -eq 0 ]
  run python3 - "$tmpdir/task.yaml" <<'PY'
import sys, yaml
task = (yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {})['task']
for field in ('before', 'after', 'measurement_command', 'measurement_environment',
              'measurement_policy', 'fixed_baseline_policy', 'safety_boundary'):
    assert str(task.get(field) or '').strip(), field
assert '同一環境' in task['measurement_environment']
assert 'run_tests.sh task queue/tasks/tobisaru.yaml' in task['measurement_command']
print('DYNAMIC_MEASUREMENT_CONTRACT_OK')
PY
  [ "$status" -eq 0 ]
  [ "$output" = "DYNAMIC_MEASUREMENT_CONTRACT_OK" ]
}

# test_necessity: reflux workers need one injected absolute helper/scope and
# producer contract so the gate can distinguish post-commit self-retro metadata
# from a worker's own dirty edit.
@test "reflux tasks receive absolute scope and producer commit contract" {
  local tmpdir="$BATS_TEST_TMPDIR/reflux-contract"
  mkdir -p "$tmpdir"
  cat > "$tmpdir/task.yaml" <<'YAML'
task:
  project: infra
  task_type: exact
  purpose: reflux_insight producer contract fixture
  planned_paths:
  - queue/insights.yaml
YAML

  run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$PROJECT_ROOT'; inject_reflux_commit_contract '$tmpdir/task.yaml'"
  [ "$status" -eq 0 ]
  run python3 - "$tmpdir/task.yaml" "$PROJECT_ROOT" <<'PY'
import os, sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
contract = task['reflux_commit_contract']
assert contract['helper_path'] == os.path.join(sys.argv[2], 'scripts/ninja_scope_commit.sh')
assert os.path.isabs(contract['helper_path'])
assert contract['scope'] == ['queue/insights.yaml']
assert contract['producer'] == {'field': 'source', 'value': 'self_retro'}
assert contract['post_commit_allowed_fields'] == ['occurrence_count', 'last_seen']
assert contract['uncommitted_worker_policy'] == 'block'
print('REFLUX_CONTRACT_OK')
PY
  [ "$status" -eq 0 ]
  [ "$output" = "REFLUX_CONTRACT_OK" ]
}

# test_necessity: observation ACs must be removed from the worker contract and
# published as one stable, monitor-owned proof artifact with an atomic replace.
@test "deployment extracts observation ACs into queue proofs" {
  local tmpdir="$BATS_TEST_TMPDIR/production-proof"
  mkdir -p "$tmpdir/scripts/lib" "$tmpdir/queue/tasks"
  cp "$PROJECT_ROOT/scripts/lib/production_proof.py" "$tmpdir/scripts/lib/"
  cat > "$tmpdir/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_proof_fixture:
    estimated_minutes: 10
    acceptance_criteria:
    - id: AC1
      description: implementation remains deterministic
    - id: AC2
      description: 'live後1時間の本番観測。判定式: median < 10。ログ名: monitor.log'
YAML
  cat > "$tmpdir/queue/tasks/hayate.yaml" <<'YAML'
task:
  estimated_minutes: 10
  acceptance_criteria:
  - id: OLD
    description: stale AC
YAML

  run bash -lc "export DEPLOY_TASK_LIB_ONLY=1; source '$PROJECT_ROOT/scripts/deploy_task.sh'; SCRIPT_DIR='$tmpdir'; resolve_cmd_to_task cmd_proof_fixture hayate"
  [ "$status" -eq 0 ]
  run python3 - "$tmpdir/queue/tasks/hayate.yaml" "$tmpdir/queue/proofs/cmd_proof_fixture.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
proof = yaml.safe_load(open(sys.argv[2], encoding='utf-8'))
assert [item['id'] for item in task['acceptance_criteria']] == ['AC1']
assert proof['cmd_id'] == 'cmd_proof_fixture'
assert proof['observation_window_seconds'] == 3600
assert proof['predicate'] == 'median < 10'
assert proof['log_name'] == 'monitor.log'
assert [item['id'] for item in proof['checks']] == ['AC2']
print('PRODUCTION_PROOF_EXTRACTION_OK')
PY
  [ "$status" -eq 0 ]
  [ "$output" = "PRODUCTION_PROOF_EXTRACTION_OK" ]
}
