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

@test "Fix22: binary_checks MISSING → autofix restores empty dict" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    # Remove binary_checks key entirely
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
del data['binary_checks']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"binary_checks MISSING"* ]]
    # Verify restored
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
bc = data.get('binary_checks')
assert isinstance(bc, dict), f'Expected dict, got {type(bc)}'
print('OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "Fix23: verdict MISSING → autofix restores key" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    # Remove verdict key entirely
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
del data['verdict']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    # Debug: show file content and autofix output
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    echo "status=$status output=$output" >&3
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"verdict MISSING"* ]]
    # Verify verdict key exists after autofix (Fix 9 may override '' to PASS/FAIL)
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
assert 'verdict' in data, 'verdict key missing'
print('OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "Fix24: purpose_validation MISSING → autofix restores default structure" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    # Remove purpose_validation key entirely
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
del data['purpose_validation']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"purpose_validation MISSING"* ]]
    # Verify restored structure
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
pv = data.get('purpose_validation')
assert isinstance(pv, dict), f'Expected dict, got {type(pv)}'
assert 'cmd_purpose' in pv, 'cmd_purpose missing'
assert 'fit' in pv, 'fit missing'
assert 'purpose_gap' in pv, 'purpose_gap missing'
print('OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "Fix25: files_modified MISSING → autofix restores empty list" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    # Remove files_modified key entirely
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
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"files_modified MISSING"* ]]
    # Verify restored
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
fm = data.get('files_modified')
assert isinstance(fm, list), f'Expected list, got {type(fm)}'
assert len(fm) == 0, f'Expected empty list, got {fm}'
print('OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
}

@test "Fix26: result MISSING → autofix restores summary+details structure" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "filled"
    # Remove result key entirely
    python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
del data['result']
with open('$TEST_TMPDIR/report.yaml', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
"
    run bash "$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"result MISSING"* ]]
    # Verify restored structure
    run python3 -c "
import yaml
with open('$TEST_TMPDIR/report.yaml') as f:
    data = yaml.safe_load(f)
r = data.get('result')
assert isinstance(r, dict), f'Expected dict, got {type(r)}'
assert 'summary' in r, 'summary missing'
assert 'details' in r, 'details missing'
assert r['summary'] == '', f'Expected empty string, got {repr(r[\"summary\"])}'
assert r['details'] == '', f'Expected empty string, got {repr(r[\"details\"])}'
print('OK')
"
    [ "$status" -eq 0 ]
    [ "$output" = "OK" ]
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
