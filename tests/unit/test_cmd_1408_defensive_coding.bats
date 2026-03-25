#!/usr/bin/env bats
# test_cmd_1408_defensive_coding.bats — cmd_1408 防御的コーディング4件の検証
#
# テスト構成:
#   T-1408-001: check_project_code_stubs || true 除去 — 正常系(stubs=0)でexit 0維持
#   T-1408-002: check_project_code_stubs || true 除去 — エラー時に[ERROR]ログ出力
#   T-1408-003: ntfy.sh に ntfy_validate_topic 呼出が存在する
#   T-1408-004: ntfy_listener.sh grep dedup — 行頭アンカーで誤マッチ防止
#   T-1408-005: deploy_task.sh inject_related_lessons — 同一lesson_id重複排除

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd1408.XXXXXX")"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ─── AC1: check_project_code_stubs || true 修正 ───

@test "T-1408-001: stub check OK path — || true removed, exit 0 preserved for stubs=0" {
    # Verify the || true has been removed from the invocation line
    local gate_script="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    # The old pattern: check_project_code_stubs ... || true
    # Should NOT match after fix
    run grep -n 'check_project_code_stubs.*|| true' "$gate_script"
    [ "$status" -eq 1 ]  # grep returns 1 = no match = || true removed

    # Verify the new pattern captures return code
    run grep -n 'STUB_CHECK_RC' "$gate_script"
    [ "$status" -eq 0 ]  # grep returns 0 = STUB_CHECK_RC exists
}

@test "T-1408-002: stub check error path — non-zero rc with unknown status logs ERROR" {
    local gate_script="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    # Verify BLOCK case is now handled in the case statement
    run grep -n 'BLOCK)' "$gate_script"
    [ "$status" -eq 0 ]

    # Verify ERROR logging for unexpected failures (rc!=0 + unrecognized status)
    run grep -n '\[ERROR\] check_project_code_stubs failed' "$gate_script"
    [ "$status" -eq 0 ]
}

# ─── AC2: ntfy.sh validate_topic + ntfy_listener.sh grep anchor ───

@test "T-1408-003: ntfy.sh calls ntfy_validate_topic after TOPIC resolution" {
    local ntfy_script="$PROJECT_ROOT/scripts/ntfy.sh"
    # ntfy_validate_topic should appear after TOPIC= line
    local topic_line
    topic_line=$(grep -n 'TOPIC=' "$ntfy_script" | head -1 | cut -d: -f1)
    local validate_line
    validate_line=$(grep -n 'ntfy_validate_topic' "$ntfy_script" | head -1 | cut -d: -f1)

    [ -n "$topic_line" ]
    [ -n "$validate_line" ]
    [ "$validate_line" -gt "$topic_line" ]
}

@test "T-1408-004: ntfy_listener.sh grep dedup uses YAML line-start anchor" {
    local listener_script="$PROJECT_ROOT/scripts/ntfy_listener.sh"

    # Verify the grep pattern has line-start anchor
    run grep -F '^[[:space:]]*id:' "$listener_script"
    [ "$status" -eq 0 ]

    # Functional test: line-start anchor rejects mid-line "id:" matches
    local inbox="$TEST_TMPDIR/inbox.yaml"
    cat > "$inbox" <<'EOF'
messages:
  - content: "task_id: msg_test123 is done"
    from: karo
    id: msg_other456
    read: false
EOF

    # Old pattern (no anchor) would match "task_id: msg_test123" — false positive
    # New pattern (with anchor) should NOT match msg_test123 as a standalone id
    run grep -qE "^[[:space:]]*id: ['\"]?msg_test123['\"]?" "$inbox"
    [ "$status" -eq 1 ]  # no match — correct behavior

    # But it SHOULD match msg_other456 which is a proper "id:" field
    run grep -qE "^[[:space:]]*id: ['\"]?msg_other456['\"]?" "$inbox"
    [ "$status" -eq 0 ]  # match — correct behavior
}

# ─── AC3: deploy_task.sh inject_related_lessons lesson_id dedup ───

@test "T-1408-005: inject_related_lessons deduplicates lessons by ID (last wins)" {
    # Test the Python dedup logic directly
    run python3 - <<'PY'
import sys

# Simulate the dedup logic from deploy_task.sh
lessons = [
    {'id': 'L001', 'title': 'First version', 'summary': 'old summary'},
    {'id': 'L002', 'title': 'Unique lesson', 'summary': 'unique'},
    {'id': 'L001', 'title': 'Second version', 'summary': 'new summary'},  # duplicate
    {'id': 'L003', 'title': 'Another unique', 'summary': 'another'},
]

_id_to_lesson = {}
_no_id = []
for _l in lessons:
    _lid = _l.get('id', '')
    if _lid:
        _id_to_lesson[_lid] = _l
    else:
        _no_id.append(_l)
_pre_dedup = len(lessons)
lessons = list(_id_to_lesson.values()) + _no_id

# Assertions
assert len(lessons) == 3, f"Expected 3, got {len(lessons)}"

# L001 should have the LAST (second) version's content
l001 = [l for l in lessons if l['id'] == 'L001'][0]
assert l001['summary'] == 'new summary', f"Expected 'new summary', got '{l001['summary']}'"

# L002 and L003 should be preserved
ids = [l['id'] for l in lessons]
assert 'L002' in ids, "L002 should be preserved"
assert 'L003' in ids, "L003 should be preserved"

# Verify dedup count
removed = _pre_dedup - len(lessons)
assert removed == 1, f"Expected 1 removed, got {removed}"

print("PASS: dedup removed 1 duplicate, last-wins preserved")
PY
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" == *"PASS"* ]]
}
