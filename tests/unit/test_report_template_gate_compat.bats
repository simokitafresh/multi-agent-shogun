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

@test "filled report with empty lessons_useful passes gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
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
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
    # Template already has verdict: PASS
    run bash "$GATE_SCRIPT" "$TEST_TMPDIR/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "verdict FAIL passes gate" {
    _generate_filled_report "$TEST_TMPDIR/report.yaml" "empty"
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
