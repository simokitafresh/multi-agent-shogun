#!/usr/bin/env bats
# test_gate_report_autofix.bats — gate_report_autofix.sh unit tests
# cmd_cycle_002: 報告YAML自動修正ゲートのテスト

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_autofix.sh"
    export SRC_GATE_HELPER="$PROJECT_ROOT/scripts/gates/gate_report_autofix_main.py"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_GATE_HELPER" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/autofix.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/logs"
    # Copy script so REPO_ROOT resolves to test tmpdir (no log pollution)
    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_autofix.sh"
    cp "$SRC_GATE_HELPER" "$TEST_TMPDIR/scripts/gates/gate_report_autofix_main.py"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_autofix.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_report_autofix.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# === Test 1: 正常な報告YAML → NO-FIX-NEEDED ===
@test "valid report yields NO-FIX-NEEDED" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
files_modified:
  - path: scripts/foo.sh
    change: modified
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: test passes
      result: "yes"
lesson_candidate:
  found: false
  no_lesson_reason: routine task
  title: ""
  detail: ""
self_gate_check:
  format: PASS
  content: PASS
ac_version_read: "2"
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO-FIX-NEEDED"* ]]
}

# === Test 2: files_modified string → dict変換 ===
@test "files_modified single string is converted to dict list" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
files_modified: scripts/foo.sh
binary_checks:
  AC1:
    - check: test
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"files_modified"* ]]
    # Verify structure
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
fm = d['files_modified']
assert isinstance(fm, list), f'Expected list, got {type(fm)}'
assert fm[0]['path'] == 'scripts/foo.sh'
assert fm[0]['change'] == 'modified'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 3: lessons_useful dict → list変換 ===
@test "lessons_useful numbered dict is converted to list" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
lessons_useful:
  0:
    id: L001
    useful: true
    reason: helpful
  1:
    id: L002
    useful: false
    reason: not applicable
binary_checks:
  AC1:
    - check: test
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"lessons_useful dict→list"* ]]
    # Verify converted to ordered list
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
lu = d['lessons_useful']
assert isinstance(lu, list), f'Expected list, got {type(lu)}'
assert len(lu) == 2
assert lu[0]['id'] == 'L001'
assert lu[1]['id'] == 'L002'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 4: binary_checks dict値 → list wrap ===
@test "binary_checks single dict value is wrapped in list" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
binary_checks:
  AC1:
    check: test passes
    result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"binary_checks"* ]]
    # Verify dict was wrapped in list
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
bc = d['binary_checks']['AC1']
assert isinstance(bc, list), f'Expected list, got {type(bc)}'
assert len(bc) == 1
assert bc[0]['check'] == 'test passes'
assert bc[0]['result'] == 'yes'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 5: MISSINGフィールドの自動復元(Fix6復活+他は撤去維持) ===
# cmd_1496でFix6復活: lessons_useful MISSINGは空listに復元。他フィールドは撤去維持。
@test "missing fields: lessons_useful is auto-filled by Fix6, others are NOT" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
binary_checks:
  AC1:
    - check: test
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    # Verify: lessons_useful IS auto-filled by Fix6 (MISSING→空list)
    # Other fields are NOT auto-filled (Fix22-28撤去維持)
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
# verdict key absent → should NOT be added
assert 'verdict' not in d, f'verdict should not be auto-filled'
# files_modified absent → should NOT be added
assert 'files_modified' not in d, f'files_modified should not be auto-filled'
# lessons_useful IS auto-filled by Fix6 (cmd_1496復活)
assert 'lessons_useful' in d, f'lessons_useful should be auto-filled by Fix6'
assert isinstance(d['lessons_useful'], list), f'lessons_useful should be a list'
# lesson_candidate absent → should NOT be added
assert 'lesson_candidate' not in d, f'lesson_candidate should not be auto-filled'
# self_gate_check absent → should NOT be added
assert 'self_gate_check' not in d, f'self_gate_check should not be auto-filled'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 6: autofix後も元の値が保持される ===
@test "autofix preserves existing field values" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
files_modified: scripts/foo.sh
lessons_useful:
  - id: L001
    useful: true
    reason: very helpful for debugging
binary_checks:
  AC1:
    - check: test passes
      result: yes
lesson_candidate:
  found: true
  no_lesson_reason: ""
  title: important lesson
  detail: detailed description here
self_gate_check:
  format: PASS
ac_version_read: "3"
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    # Verify files_modified was fixed but other fields preserved
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
# files_modified was converted
assert isinstance(d['files_modified'], list)
# Other fields preserved exactly
assert d['worker_id'] == 'tobisaru'
assert d['parent_cmd'] == 'cmd_999'
assert d['verdict'] == 'PASS'
assert d['lessons_useful'][0]['reason'] == 'very helpful for debugging'
assert d['lesson_candidate']['title'] == 'important lesson'
assert d['lesson_candidate']['detail'] == 'detailed description here'
assert d['self_gate_check']['format'] == 'PASS'
assert d['ac_version_read'] == '3'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 7: binary_checks boolean result → string変換 ===
@test "binary_checks boolean result is converted to yes/no string" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
binary_checks:
  AC1:
    - check: test passes
      result: true
    - check: no regression
      result: false
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"boolean→string"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
bc = d['binary_checks']['AC1']
assert bc[0]['result'] == 'yes', f'Expected yes, got {bc[0][\"result\"]}'
assert bc[1]['result'] == 'no', f'Expected no, got {bc[1][\"result\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 8: YAML parse error → UNFIXABLE exit 1 ===
@test "YAML parse error returns UNFIXABLE with exit 1" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
  bad_indent: this is invalid YAML
parent_cmd: [unclosed
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNFIXABLE"* ]]
}

# === Test 9: report file not found → UNFIXABLE exit 1 ===
@test "missing report file returns UNFIXABLE with exit 1" {
    run bash "$TEST_GATE" "$TEST_TMPDIR/nonexistent.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNFIXABLE"* ]]
}

# === Test 10: verdict推定 from binary_checks ===
@test "non-standard verdict is inferred from binary_checks results" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: CONDITIONAL_PASS
binary_checks:
  AC1:
    - check: test passes
      result: yes
  AC2:
    - check: commit done
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"verdict"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
assert d['verdict'] == 'PASS', f'Expected PASS, got {d[\"verdict\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "blank verdict is inferred only when all binary_checks results are filled" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: ""
binary_checks:
  AC1:
    - check: test passes
      result: yes
  AC2:
    - check: commit done
      result: no
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"verdict推定(1PASS/1FAIL)"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
assert d['verdict'] == 'FAIL', f'Expected FAIL, got {d[\"verdict\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "pending status is completed when verdict becomes valid" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
status: pending
verdict: ""
binary_checks:
  AC1:
    - check: test passes
      result: yes
  AC2:
    - check: commit done
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"status pending→completed"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
assert d['verdict'] == 'PASS', f'Expected PASS, got {d[\"verdict\"]}'
assert d['status'] == 'completed', f'Expected completed, got {d[\"status\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 11: worker_id/parent_cmd推定 from filename ===
@test "worker_id and parent_cmd are inferred from filename" {
    local rpath="$TEST_TMPDIR/queue/reports/hanzo_report_cmd_888.yaml"
    cat > "$rpath" <<'EOF'
verdict: PASS
binary_checks:
  AC1:
    - check: test
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"worker_id"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
assert d['worker_id'] == 'hanzo', f'Expected hanzo, got {d[\"worker_id\"]}'
assert d['parent_cmd'] == 'cmd_888', f'Expected cmd_888, got {d[\"parent_cmd\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 12: binary_checks result PASS/FAIL → yes/no正規化 ===
@test "binary_checks PASS/FAIL strings are normalized to yes/no" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
binary_checks:
  AC1:
    - check: test passes
      result: PASS
    - check: committed
      result: FAIL
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
bc = d['binary_checks']['AC1']
assert bc[0]['result'] == 'yes', f'Expected yes, got {bc[0][\"result\"]}'
assert bc[1]['result'] == 'no', f'Expected no, got {bc[1][\"result\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 12a: fast binary_checks fix emits no awk warning ===
@test "fast binary_checks fix does not emit awk regex warnings" {
    local rpath="$TEST_TMPDIR/queue/reports/saizo_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: saizo
parent_cmd: cmd_999
verdict: CONDITIONAL_PASS
lessons_useful: []
binary_checks:
  AC1:
    - committed: true
    - lint: PASS
  AC2:
    - tests: false
    - format: ng
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" != *"warning"* ]]
    [[ "$output" != *"regexp escape sequence"* ]]
}

# === Test 12b: binary_checks name:value entries + verdict推定 ===
@test "binary_checks name:value entries are normalized and verdict is inferred" {
    local rpath="$TEST_TMPDIR/queue/reports/saizo_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: saizo
parent_cmd: cmd_999
verdict: CONDITIONAL_PASS
lessons_useful: []
binary_checks:
  AC1:
    - committed: true
    - lint: PASS
  AC2:
    - tests: false
    - format: ng
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"binary_checks {name:val}→{check:name,result:val}正規化"* ]]
    [[ "$output" == *"verdict推定(2PASS/2FAIL)"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
assert d['verdict'] == 'FAIL', f'Expected FAIL, got {d[\"verdict\"]}'
bc1 = d['binary_checks']['AC1']
bc2 = d['binary_checks']['AC2']
assert bc1[0] == {'check': 'committed', 'result': 'yes'}, bc1[0]
assert bc1[1] == {'check': 'lint', 'result': 'yes'}, bc1[1]
assert bc2[0] == {'check': 'tests', 'result': 'no'}, bc2[0]
assert bc2[1] == {'check': 'format', 'result': 'no'}, bc2[1]
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 13: lessons_useful 単一教訓dict → list wrap (Pattern B) ===
@test "lessons_useful single lesson dict is wrapped in list" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
lessons_useful:
  id: L074
  useful: true
  reason: helpful for debugging
binary_checks:
  AC1:
    - check: test
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"単一dict→list wrap"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
lu = d['lessons_useful']
assert isinstance(lu, list), f'Expected list, got {type(lu)}'
assert len(lu) == 1, f'Expected 1 item, got {len(lu)}'
assert lu[0]['id'] == 'L074', f'Expected L074, got {lu[0].get(\"id\")}'
assert lu[0]['useful'] == True, f'Expected True, got {lu[0].get(\"useful\")}'
assert lu[0]['reason'] == 'helpful for debugging'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 14: lessons_useful 教訓IDキーdict → list変換 (Pattern C) ===
@test "lessons_useful lesson-ID-keyed dict converts to list with id injection" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
lessons_useful:
  L074:
    useful: true
    reason: helped avoid trap
  L063:
    useful: false
    reason: not relevant
binary_checks:
  AC1:
    - check: test
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"LessonIDキーdict→list"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
lu = d['lessons_useful']
assert isinstance(lu, list), f'Expected list, got {type(lu)}'
assert len(lu) == 2, f'Expected 2 items, got {len(lu)}'
ids = {item['id'] for item in lu}
assert ids == {'L074', 'L063'}, f'Expected L074,L063, got {ids}'
for item in lu:
    if item['id'] == 'L074':
        assert item['useful'] == True
        assert item['reason'] == 'helped avoid trap'
    elif item['id'] == 'L063':
        assert item['useful'] == False
        assert item['reason'] == 'not relevant'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 15: lessons_useful 空dict → 空list変換 ===
@test "lessons_useful empty dict converts to empty list" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
lessons_useful: {}
binary_checks:
  AC1:
    - check: test
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
lu = d['lessons_useful']
assert isinstance(lu, list), f'Expected list, got {type(lu)}'
assert len(lu) == 0, f'Expected empty list, got {len(lu)}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 16: binary_checks [N]キー正規化で task YAML の check 名を再利用 ===
@test "numbered binary_checks reuse task acceptance criteria check names" {
    local tpath="$TEST_TMPDIR/queue/tasks/saizo.yaml"
    local rpath="$TEST_TMPDIR/queue/reports/saizo_report_cmd_999.yaml"
    cat > "$tpath" <<'EOF'
task:
  acceptance_criteria:
    - id: AC1
      binary_checks:
        - check: task AC1 check 1
        - check: task AC1 check 2
    - id: AC2
      binary_checks:
        - check: task AC2 check 1
        - check: task AC2 check 2
EOF
    cat > "$rpath" <<'EOF'
worker_id: saizo
parent_cmd: cmd_999
verdict: PASS
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - "[1]": {result: PASS}
      "[2]": {result: FAIL}
  AC2:
    - "[1]": {result: PASS}
      "[2]": {result: PASS}
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"[N]キー→check/result正規化"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
ac1 = d['binary_checks']['AC1']
ac2 = d['binary_checks']['AC2']
assert ac1[0]['check'] == 'task AC1 check 1', ac1
assert ac1[1]['check'] == 'task AC1 check 2', ac1
assert ac1[0]['result'] == 'yes', ac1
assert ac1[1]['result'] == 'no', ac1
assert ac2[0]['check'] == 'task AC2 check 1', ac2
assert ac2[1]['check'] == 'task AC2 check 2', ac2
assert ac2[0]['result'] == 'yes', ac2
assert ac2[1]['result'] == 'yes', ac2
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
