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

# === Test 3: lessons_useful numbered dict → GP-196で自動変換 ===
@test "lessons_useful numbered dict is converted to list (GP-196)" {
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
    # GP-196: numbered dict→list変換が実行される
    [[ "$output" == *"lessons_useful"*"dict"*"list"* ]]
    # lessons_usefulがlistに変換され、内容が保持されている
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
lu = d['lessons_useful']
assert isinstance(lu, list), f'Expected list, got {type(lu)}'
assert len(lu) == 2, f'Expected 2 items, got {len(lu)}'
assert lu[0]['id'] == 'L001', f'Expected L001, got {lu[0][\"id\"]}'
assert lu[1]['id'] == 'L002', f'Expected L002, got {lu[1][\"id\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "knowledge_candidate string is converted to title/detail dict" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_999.yaml"
    cat > "$rpath" <<'EOF'
worker_id: tobisaru
parent_cmd: cmd_999
verdict: PASS
knowledge_candidate: "API endpoint is /v1/report"
files_modified:
  - path: scripts/foo.sh
    change: modified
lessons_useful:
  - id: L001
    useful: true
    reason: helpful
binary_checks:
  AC1:
    - check: test
      result: yes
EOF
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"knowledge_candidate string→dict変換"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
kc = d['knowledge_candidate']
assert isinstance(kc, dict), f'Expected dict, got {type(kc)}'
assert kc.get('found') == True, f'Expected found=True, got {kc}'
assert isinstance(kc.get('items'), list), f'Expected items list, got {kc}'
assert kc['items'][0]['fact'] == 'API endpoint is /v1/report', kc
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 4: binary_checks dict値 → 消火撤去(GP-107)。gate_report_format.shがBLOCK ===
@test "binary_checks single dict value is NOT wrapped (消火撤去: gate blocks)" {
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
    # autofixはdict→list変換しない(消火撤去)
    [[ "$output" != *"binary_checks dict→list wrap"* ]]
    # binary_checks.AC1はdictのまま(変換されていない)
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
bc = d['binary_checks']['AC1']
assert isinstance(bc, dict), f'Expected dict (not converted), got {type(bc)}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 5: MISSINGフィールドは全て消火撤去(GP-107)。gate_report_format.shがBLOCK ===
# Fix6(lessons_useful MISSING→空list)も消火撤去: MISSING→空list生成はBLOCKで代替可能
@test "missing fields: NO fields are auto-filled (消火撤去: gate blocks all)" {
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
    # autofixはどのMISSINGフィールドも自動補完しない(消火撤去)
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
# verdict absent → should NOT be added
assert 'verdict' not in d, f'verdict should not be auto-filled'
# files_modified absent → should NOT be added
assert 'files_modified' not in d, f'files_modified should not be auto-filled'
# lessons_useful absent → should NOT be added (消火撤去: Fix6撤去)
assert 'lessons_useful' not in d, f'lessons_useful should not be auto-filled (Fix6消火撤去)'
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

# === Test 7: binary_checks boolean result → 自動変換しない ===
@test "binary_checks boolean result is not converted by autofix" {
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
    [[ "$output" == *"NO-FIX-NEEDED"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
bc = d['binary_checks']['AC1']
assert bc[0]['result'] is True, f'Expected True, got {bc[0][\"result\"]}'
assert bc[1]['result'] is False, f'Expected False, got {bc[1][\"result\"]}'
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

# === Test 10: verdict推定 → 消火撤去(GP-107)。gate_report_format.shがBLOCK ===
@test "non-standard verdict is NOT inferred (消火撤去: gate blocks)" {
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
    # autofixはverdict推定しない(消火撤去)
    [[ "$output" != *"verdict推定"* ]]
    # verdictはCONDITIONAL_PASSのまま変更されていない
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
assert d['verdict'] == 'CONDITIONAL_PASS', f'Expected CONDITIONAL_PASS, got {d[\"verdict\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "blank verdict is NOT inferred (消火撤去: gate blocks)" {
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
    # autofixはblank verdictを推定しない(消火撤去)
    [[ "$output" != *"verdict推定"* ]]
    # verdictは""のまま変更されていない
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
v = d['verdict']
assert v == '' or v is None, f'Expected empty, got {v!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "pending status is NOT auto-completed when verdict is invalid (消火撤去)" {
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
    # verdict推定なし → is_valid_verdict=False → status推定もなし(消火撤去)
    [[ "$output" != *"status pending→completed"* ]]
    [[ "$output" != *"verdict推定"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
v = d['verdict']
assert v == '' or v is None, f'Expected empty verdict, got {v!r}'
assert d['status'] == 'pending', f'Expected pending, got {d[\"status\"]}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 11: worker_id/parent_cmd推定 → 消火撤去(GP-107 Q1:値の推定=NO) ===
# gate_report_format.shが空値をBLOCKする。autofixが推定すべきでない。
@test "worker_id and parent_cmd are NOT inferred from filename (消火撤去: gate blocks)" {
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
    # autofixはworker_id/parent_cmdを推定しない(消火撤去)
    [[ "$output" != *"worker_id ファイル名から推定"* ]]
    [[ "$output" != *"parent_cmd ファイル名から推定"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
# worker_id/parent_cmdは推定されない(消火撤去)
assert 'worker_id' not in d, f'worker_id should not be auto-inferred'
assert 'parent_cmd' not in d, f'parent_cmd should not be auto-inferred'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 12: binary_checks result PASS/FAIL → 消火撤去(GP-107)。gate_report_format.shがBLOCK ===
@test "binary_checks PASS/FAIL strings are NOT normalized (消火撤去: gate blocks)" {
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
    [[ "$output" == *"NO-FIX-NEEDED"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
bc = d['binary_checks']['AC1']
assert bc[0]['result'] == 'PASS', f'Expected PASS, got {bc[0][\"result\"]}'
assert bc[1]['result'] == 'FAIL', f'Expected FAIL, got {bc[1][\"result\"]}'
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
@test "binary_checks name:value entries keep PASS/ng strings (verdict推定は消火撤去)" {
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
    # verdict推定は消火撤去 — gate_report_format.shがCONDITIONAL_PASSをBLOCK
    [[ "$output" != *"verdict推定"* ]]
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
# verdictはCONDITIONAL_PASSのまま(推定されていない)
assert d['verdict'] == 'CONDITIONAL_PASS', f'Expected CONDITIONAL_PASS, got {d[\"verdict\"]}'
bc1 = d['binary_checks']['AC1']
bc2 = d['binary_checks']['AC2']
assert bc1[0] == {'check': 'committed', 'result': True}, bc1[0]
assert bc1[1] == {'check': 'lint', 'result': 'PASS'}, bc1[1]
assert bc2[0] == {'check': 'tests', 'result': False}, bc2[0]
assert bc2[1] == {'check': 'format', 'result': 'ng'}, bc2[1]
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 13: lessons_useful 単一教訓dict → 消火撤去(GP-107)。gate_report_format.shがBLOCK ===
@test "lessons_useful single lesson dict is NOT wrapped (消火撤去: gate blocks)" {
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
    # autofixは単一dict→list変換しない(消火撤去)
    [[ "$output" != *"単一dict→list wrap"* ]]
    # lessons_usefulはdictのまま
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
lu = d['lessons_useful']
assert isinstance(lu, dict), f'Expected dict (not converted), got {type(lu)}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 14: lessons_useful 教訓IDキーdict → 消火撤去(GP-107)。gate_report_format.shがBLOCK ===
@test "lessons_useful lesson-ID-keyed dict is NOT converted (消火撤去: gate blocks)" {
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
    # autofixはLessonIDキーdict→list変換しない(消火撤去)
    [[ "$output" != *"LessonIDキーdict→list"* ]]
    # lessons_usefulはdictのまま
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
lu = d['lessons_useful']
assert isinstance(lu, dict), f'Expected dict (not converted), got {type(lu)}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# === Test 15: lessons_useful 空dict → 消火撤去(GP-107)。gate_report_format.shがBLOCK ===
@test "lessons_useful empty dict is NOT converted (消火撤去: gate blocks)" {
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
    # autofixは空dict→空list変換しない(消火撤去)
    [[ "$output" != *"空dict→空list"* ]]
    # lessons_usefulは{}のまま
    run python3 -c "
import yaml
with open('$rpath') as f:
    d = yaml.safe_load(f)
lu = d['lessons_useful']
assert isinstance(lu, dict), f'Expected dict (not converted), got {type(lu)}'
assert len(lu) == 0, f'Expected empty dict, got {len(lu)}'
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
assert ac1[0]['result'] == 'PASS', ac1
assert ac1[1]['result'] == 'FAIL', ac1
assert ac2[0]['check'] == 'task AC2 check 1', ac2
assert ac2[1]['check'] == 'task AC2 check 2', ac2
assert ac2[0]['result'] == 'PASS', ac2
assert ac2[1]['result'] == 'PASS', ac2
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
