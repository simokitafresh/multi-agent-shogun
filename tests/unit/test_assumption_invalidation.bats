#!/usr/bin/env bats
# test_assumption_invalidation.bats — assumption_invalidation欄のテスト
# cmd_1433: 後方伝播検証の仕組み化

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_report_format.sh"
    export DEPLOY_SCRIPT="$PROJECT_ROOT/scripts/deploy_task.sh"
    [ -f "$GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/ai_test.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/queue/reports" \
             "$TEST_TMPDIR/queue/tasks" \
             "$TEST_TMPDIR/logs"
    # gate_report_format.shをtmpdirにコピー（ログ汚染防止）
    cp "$GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_report_format.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# 共通: 有効な報告YAMLベース（assumption_invalidation以外は全て正常）
_write_base_report() {
    local rpath="$1"
    local ai_block="$2"
    cat > "$rpath" <<EOF
worker_id: tobisaru
task_id: cmd_1433_impl
parent_cmd: cmd_1433
timestamp: "2026-03-27T14:00:00"
status: completed
ac_version_read: bbba2099
result:
  summary: "テスト用報告"
  details: "詳細"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - scripts/deploy_task.sh
lesson_candidate:
  found: false
  no_lesson_reason: "テスト用の報告であるため"
  title: ""
  detail: ""
  project: infra
lessons_useful: []
skill_candidate:
  found: false
decision_candidate:
  found: false
${ai_block}
hook_failures:
  count: 0
  details: ""
binary_checks:
  AC1:
    - check: "テスト項目"
      result: "yes"
verdict: PASS
EOF
}

# === Test 1: テンプレート生成でassumption_invalidation欄含有 ===
@test "deploy_task template contains assumption_invalidation with found/affected_cmds/detail" {
    # deploy_task.shのテンプレート部分をgrepで確認
    run grep -A 3 'assumption_invalidation:' "$DEPLOY_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'found:'
    echo "$output" | grep -q 'affected_cmds:'
    echo "$output" | grep -q 'detail:'
}

# === Test 2: assumption_invalidation欄なし → FAIL ===
@test "gate: assumption_invalidation missing → FAIL" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_1433.yaml"
    # assumption_invalidationブロックなし
    _write_base_report "$rpath" ""
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 1 ]
    echo "$output" | grep -qi 'assumption_invalidation.*MISSING'
}

# === Test 3: found:true + affected_cmds空 → FAIL ===
@test "gate: assumption_invalidation found=true but affected_cmds empty → FAIL" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_1433.yaml"
    local ai_block
    ai_block=$(cat <<'AIEOF'
assumption_invalidation:
  found: true
  affected_cmds: []
  detail: "前提が変わった"
AIEOF
)
    _write_base_report "$rpath" "$ai_block"
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q 'found=true but affected_cmds is empty'
}

# === Test 4: found:false → PASS ===
@test "gate: assumption_invalidation found=false → PASS" {
    local rpath="$TEST_TMPDIR/queue/reports/tobisaru_report_cmd_1433.yaml"
    local ai_block
    ai_block=$(cat <<'AIEOF'
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
AIEOF
)
    _write_base_report "$rpath" "$ai_block"
    run bash "$TEST_GATE" "$rpath"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'PASS'
}
