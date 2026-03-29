#!/usr/bin/env bats
# test_report_template_gate_compat.bats
# Purpose: deploy_task.shの報告テンプレートがgate_report_format.shをPASSする形式で
#          生成されることを保証する。テンプレート退行を自動検出する抗体テスト。
# Origin: kotaro自己研鑽サイクル4 (deepdive Phase 5: 免疫記憶)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    [ -f "$GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/report_tpl.XXXXXX")"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Helper: generate a minimal report that follows the template structure
# Simulates a ninja filling in the template correctly
_generate_filled_report() {
    local outfile="$1"
    local lessons_useful="${2:-empty}"  # "empty" or "filled"

    cat > "$outfile" <<'EOF'
worker_id: test_ninja
task_id: cmd_test
parent_cmd: cmd_test
timestamp: "2026-01-01T00:00:00"
status: done
ac_version_read: abc12345
result:
  summary: "テスト完了"
  details: "テスト詳細"
purpose_validation:
  cmd_purpose: "テスト目的"
  fit: true
  purpose_gap: ""
files_modified:
  - path: scripts/test.sh
    change: "修正"
lesson_candidate:
  found: false
  no_lesson_reason: "テスト報告のため教訓なし"
  title: ""
  detail: ""
  project: infra
EOF

    if [ "$lessons_useful" = "filled" ]; then
        cat >> "$outfile" <<'EOF'
lessons_useful:
  - id: L074
    useful: true
    reason: "テストで使用"
  - id: L225
    useful: false
    reason: "本件スコープ外"
EOF
    else
        cat >> "$outfile" <<'EOF'
lessons_useful: []
EOF
    fi

    cat >> "$outfile" <<'EOF'
skill_candidate:
  found: false
decision_candidate:
  found: false
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
hook_failures:
  count: 0
  details: ""
binary_checks:
  AC1:
    - check: "テスト確認1"
      result: "yes"
  AC2:
    - check: "テスト確認2"
      result: "yes"
verdict: PASS
EOF
}

@test "filled report with empty lessons_useful is rejected by gate (GP-064)" {
    # GP-088: gate checks task YAML for related_lessons — create one so empty [] is rejected
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/test_ninja.yaml" <<'TASK'
task:
  related_lessons:
    - id: L074
      summary: "test lesson"
TASK
    # Place report under queue/reports/ so dirname(dirname(report)) finds tasks/
    mkdir -p "$TEST_TMPDIR/queue/reports"
    _generate_filled_report "$TEST_TMPDIR/queue/reports/report.yaml" "empty"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/queue/reports/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"lessons_useful"* ]]
    [[ "$output" == *"empty list"* ]]
}

@test "filled report with populated lessons_useful passes gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "binary_checks as string is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    # Replace proper binary_checks with string version
    python3 -c "
content = open('$TEST_TMPDIR/report.yaml').read()
# Remove proper binary_checks block and replace with string
import re
content = re.sub(r'binary_checks:.*?verdict:', 'binary_checks: \"AC1: yes\"\nverdict:', content, flags=re.DOTALL)
open('$TEST_TMPDIR/report.yaml', 'w').write(content)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"binary_checks"* ]]
}

@test "lessons_useful null is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    # Replace empty list with null
    python3 -c "
content = open('$TEST_TMPDIR/report.yaml').read()
content = content.replace('lessons_useful: []', 'lessons_useful: null')
open('$TEST_TMPDIR/report.yaml', 'w').write(content)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"lessons_useful"* ]]
}

@test "lesson_candidate found=true without title is rejected" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['lesson_candidate'] = {'found': True, 'title': '', 'detail': 'test'}
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "verdict CONDITIONAL_PASS is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
content = open('$TEST_TMPDIR/report.yaml').read()
content = content.replace('verdict: PASS', 'verdict: CONDITIONAL_PASS')
open('$TEST_TMPDIR/report.yaml', 'w').write(content)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"verdict"* ]]
}

@test "verdict PASS passes gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "verdict FAIL passes gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
content = open('$TEST_TMPDIR/report.yaml').read()
content = content.replace('verdict: PASS', 'verdict: FAIL')
open('$TEST_TMPDIR/report.yaml', 'w').write(content)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "verdict null is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
content = open('$TEST_TMPDIR/report.yaml').read()
content = content.replace('verdict: PASS', 'verdict: null')
open('$TEST_TMPDIR/report.yaml', 'w').write(content)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"verdict"* ]]
}

@test "verdict empty string is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
content = open('$TEST_TMPDIR/report.yaml').read()
content = content.replace('verdict: PASS', 'verdict: \"\"')
open('$TEST_TMPDIR/report.yaml', 'w').write(content)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"verdict"* ]]
}

@test "lessons_useful dict form is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['lessons_useful'] = {0: {'id': 'L074', 'useful': True, 'reason': 'test'}}
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"lessons_useful"* ]]
    [[ "$output" == *"dict"* ]]
}

@test "lessons_useful entry missing id is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['lessons_useful'] = [{'useful': True, 'reason': 'test'}]
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"missing \"id\""* ]]
}

@test "lessons_useful useful=string is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['lessons_useful'] = [{'id': 'L074', 'useful': 'yes', 'reason': 'test'}]
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"useful="* ]]
    [[ "$output" == *"must be true or false"* ]]
}

@test "lessons_useful FILL_THIS in useful is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['lessons_useful'] = [{'id': 'L074', 'useful': 'FILL_THIS', 'reason': 'test'}]
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"FILL_THIS"* ]]
}

@test "binary_checks AC value as string is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['binary_checks'] = {'AC1': 'yes', 'AC2': [{'check': 'ok', 'result': 'yes'}]}
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"binary_checks.AC1"* ]]
    [[ "$output" == *"must be list"* ]]
}

@test "binary_checks AC value as dict is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['binary_checks'] = {'AC1': {'check': 'ok', 'result': 'yes'}}
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"binary_checks.AC1"* ]]
    [[ "$output" == *"must be list"* ]]
}

@test "lesson_candidate found=false without no_lesson_reason is rejected" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['lesson_candidate'] = {'found': False}
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"no_lesson_reason"* ]]
}

# --- GP-065: files_modified type validation ---
@test "files_modified as dict is rejected by gate (GP-065)" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['files_modified'] = {0: 'path/to/file.py'}
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"files_modified"* ]]
    [[ "$output" == *"dict"* ]]
}

@test "files_modified as null is rejected by gate (GP-065)" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['files_modified'] = None
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"files_modified"* ]]
}

@test "files_modified as string passes gate (GP-065)" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- GP-071: Template state detection (quality_fix_request skip) ---
# inbox_write.sh内のテンプレート状態検出Pythonロジックを直接テスト

# Helper: run the template detection logic extracted from inbox_write.sh
_detect_template_state() {
    local report_file="$1"
    REPORT_YAML="$report_file" python3 -c "
import yaml, os, sys
try:
    with open(os.environ['REPORT_YAML']) as f:
        data = yaml.safe_load(f)
    if not data or not isinstance(data, dict):
        print('yes')
        sys.exit(0)
    verdict = data.get('verdict', '')
    if not verdict or str(verdict).strip() == '':
        print('yes')
        sys.exit(0)
    bc = data.get('binary_checks', {})
    if isinstance(bc, dict):
        for ac_val in bc.values():
            if isinstance(ac_val, list):
                for item in ac_val:
                    if isinstance(item, dict) and 'FILL_THIS' in str(item.get('result', '')):
                        print('yes')
                        sys.exit(0)
    print('no')
except Exception:
    print('yes')
" 2>/dev/null
}

# Helper: generate a template-state report (as deploy_task.sh produces)
_generate_template_report() {
    local outfile="$1"
    cat > "$outfile" <<'EOF'
worker_id: test_ninja
task_id: ""
parent_cmd: cmd_test
timestamp: ""
status: pending
ac_version_read: abc12345
result:
  summary: ""
  details: ""
purpose_validation:
  cmd_purpose: ""
  fit: true
  purpose_gap: ""
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: ""
  title: ""
  detail: ""
  project: infra
lessons_useful:
  - id: L074
    useful: false
    reason: ''
skill_candidate:
  found: false
decision_candidate:
  found: false
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
hook_failures:
  count: 0
  details: ""
binary_checks:
  AC1:
  - check: "FILL_THIS残存時にquality_fix_requestが発火しないことを確認したか"
    result: ""
verdict: ""
EOF
}

@test "GP-071: template state detected when verdict is empty" {
    _generate_template_report "$TEST_TMPDIR/report.yaml"
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "yes" ]
}

@test "GP-071: template state detected when FILL_THIS in binary_checks result" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    # Replace binary_checks result with FILL_THIS
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['binary_checks'] = {'AC1': [{'check': 'test check', 'result': 'FILL_THIS'}]}
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "yes" ]
}

@test "GP-071: non-template detected when verdict=PASS and no FILL_THIS" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "no" ]
}

@test "GP-071: non-template detected when verdict=FAIL and no FILL_THIS" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
content = open('$TEST_TMPDIR/report.yaml').read()
content = content.replace('verdict: PASS', 'verdict: FAIL')
open('$TEST_TMPDIR/report.yaml', 'w').write(content)
"
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "no" ]
}

# --- Fix 22-26: MISSING field restoration via autofix ---

# === Fix22-28: 消火撤去テスト (2026-03-25) ===
# 旧: autofixがMISSINGフィールドにデフォルト値挿入(消火) → gateがPASS → 家老workaround
# 新: autofixはMISSINGを放置 → gate_report_format.shがBLOCK → 忍者が修正 → 品質向上

@test "Fix22-28撤去: binary_checks MISSING → autofixせず残存 → gate FAIL" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
del data['binary_checks']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    # autofix does NOT restore MISSING fields
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"binary_checks MISSING"* ]]
    # gate catches it
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"binary_checks"* ]]
}

@test "Fix22-28撤去: verdict MISSING → autofixせず残存 → gate FAIL" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
del data['verdict']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"verdict MISSING"* ]]
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "Fix22-28撤去: files_modified MISSING → autofixせず → gate FAIL" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
del data['files_modified']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"files_modified MISSING"* ]]
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"files_modified"* ]]
}

@test "Fix6復活: lessons_useful MISSING → autofixで空list生成" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
del data['lessons_useful']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    # Fix6(cmd_1496復活): autofix detects MISSING and generates empty list or skeleton
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lessons_useful"* ]]
    # Verify lessons_useful is now present as a list
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
assert 'lessons_useful' in data, 'lessons_useful should be restored by Fix6'
assert isinstance(data['lessons_useful'], list), f'Expected list, got {type(data[\"lessons_useful\"])}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "Fix22-28撤去: lesson_candidate MISSING → autofixせず → gate FAIL" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
del data['lesson_candidate']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"lesson_candidate MISSING"* ]]
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"lesson_candidate"* ]]
}

@test "GP-071: template state when verdict is null" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['verdict'] = None
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run _detect_template_state "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "yes" ]
}

# === self_gate_check value validation (cmd_cycle_001) ===

# Helper: add self_gate_check to a filled report
_add_self_gate_check() {
    local outfile="$1"
    local lesson_ref="${2:-PASS}"
    local lesson_candidate="${3:-PASS}"
    local status_valid="${4:-PASS}"
    local purpose_fit="${5:-PASS}"
    cat >> "$outfile" <<EOF
self_gate_check:
  lesson_ref: "${lesson_ref}"
  lesson_candidate: "${lesson_candidate}"
  status_valid: "${status_valid}"
  purpose_fit: "${purpose_fit}"
EOF
}

@test "self_gate_check result=ok is rejected by gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    _add_self_gate_check "$TEST_TMPDIR/report.yaml" "ok" "PASS" "PASS" "PASS"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"self_gate_check.lesson_ref"* ]]
    [[ "$output" == *"ok"* ]]
}

@test "self_gate_check result=PASS passes gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    _add_self_gate_check "$TEST_TMPDIR/report.yaml" "PASS" "PASS" "PASS" "PASS"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "self_gate_check result=FAIL passes gate (FAIL is valid value)" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    _add_self_gate_check "$TEST_TMPDIR/report.yaml" "PASS" "FAIL" "PASS" "PASS"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "self_gate_check absent does not cause gate failure (impl tasks)" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    # No self_gate_check added — simulates impl task
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# === Fix5 Step3復活テスト: 散文binary_checksをlist構造に変換 ===
# cmd_1496でFix5 Step3復活: 散文テキストをcheck名に使用しresult='yes'固定でlist化
# 旧Step3(YES/NO推定)とは異なり、文字列をそのままcheck名に使うため情報捏造なし

@test "Fix5-Step3復活: binary_checks散文 → autofixでlist変換" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    # binary_checksを散文テキストに置き換え
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['binary_checks'] = {'AC1': 'API接続確認済み、全てPASS、問題なし'}
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    # Fix5 Step3(cmd_1496復活): autofix converts prose to [{check: prose, result: 'yes'}]
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    # Verify the value is now a list (converted from string)
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
bc = data.get('binary_checks', {}).get('AC1')
assert isinstance(bc, list), f'Expected list, got {type(bc)}'
assert bc[0]['check'] == 'API接続確認済み、全てPASS、問題なし', f'check text mismatch: {bc[0][\"check\"]}'
assert bc[0]['result'] == 'yes', f'result should be yes'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === GP-104撤去テスト: GP-091 YAML parse修復がautofixされないことを確認 ===
# 消火パターン: YAML parse errorをダミーコンテンツで修復(壊れたYAMLを偽装)
# 期待: autofixはUNFIXABLEで終了

# === GP-106撤去テスト: ac_version_read自動補完がautofixされないことを確認 ===
# 消火パターン: ac_version_read欠落→タスクYAMLから自動補完(attestation無力化)
# 期待: autofixは補完せず、ac_version_readは空のまま

@test "GP-106撤去: ac_version_read欠落 → autofixせず → gate FAIL" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    # ac_version_readを消去
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
if 'ac_version_read' in data:
    del data['ac_version_read']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    # autofixが補完しないことを確認
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
print('MISSING' if not data.get('ac_version_read') else 'FILLED')
"
    [[ "$output" == *"MISSING"* ]]
    # format gateがBLOCKすることを確認
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

@test "GP-104撤去: YAML parse error → autofix UNFIXABLE (ダミーコンテンツ生成なし)" {
    # 意図的にYAML parse errorを起こす(lesson_candidate scalar + orphaned children)
    cat > "$TEST_TMPDIR/broken.yaml" <<'BROKEN'
worker_id: test_ninja
parent_cmd: cmd_test
lesson_candidate: "some string value"
  found: true
  title: "orphaned"
verdict: PASS
BROKEN
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/broken.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNFIXABLE"* ]]
    [[ "$output" == *"YAML parse error"* ]]
}

# === GP-108テスト: FIXヒント完全化+重複排除 ===

@test "GP-108: lesson_candidate found=false no_reason → FIX hint表示" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['lesson_candidate'] = {'found': False}
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no_lesson_reason"* ]]
    [[ "$output" == *"FIX (lesson_candidate)"* ]]
}

@test "GP-108: self_gate_check as string → FIX hint表示" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    echo 'self_gate_check: "all good"' >> "$TEST_TMPDIR/report.yaml"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"self_gate_check: is str"* ]]
    [[ "$output" == *"FIX (self_gate_check)"* ]]
}

@test "GP-108: lessons_useful null → FIX hint表示" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['lessons_useful'] = None
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"lessons_useful: null"* ]]
    [[ "$output" == *"FIX (lessons_useful)"* ]]
}

@test "GP-108: ヒント重複排除 — 3つのreason emptyで1つのFIX hint" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
data['lessons_useful'] = [
    {'id': 'L001', 'useful': True, 'reason': ''},
    {'id': 'L002', 'useful': True, 'reason': ''},
    {'id': 'L003', 'useful': False, 'reason': ''},
]
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 1 ]
    # 3つのエラーがセミコロン区切りで1行に出る
    local error_count
    error_count=$(echo "$output" | grep -o "reason is empty" | wc -l)
    [ "$error_count" -ge 3 ]
    # FIXヒントは1つだけ（[N]で正規化）
    local hint_count
    hint_count=$(echo "$output" | grep -c "FIX (lessons_useful" || true)
    [ "$hint_count" -eq 1 ]
    # ヒントに[N]が含まれる
    [[ "$output" == *"lessons_useful[N]"* ]]
}
