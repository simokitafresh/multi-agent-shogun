#!/usr/bin/env bats
# test_insight_sanitize.bats — insight_write.sh サニタイズテスト
# cmd_1407 AC1/AC3: 入力インジェクション防止の検証

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export INSIGHT_SCRIPT="$PROJECT_ROOT/scripts/insight_write.sh"
    [ -f "$INSIGHT_SCRIPT" ] || return 1
    python3 -c "import yaml" 2>/dev/null || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/insight_test.XXXXXX")"
    export INSIGHT_SOURCE_REPEAT_THRESHOLD=0
    mkdir -p "$TEST_TMPDIR/queue"
    echo "insights: []" > "$TEST_TMPDIR/queue/insights.yaml"
    mkdir -p "$TEST_TMPDIR/scripts"
    cp "$INSIGHT_SCRIPT" "$TEST_TMPDIR/scripts/insight_write.sh"
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# --- Basic functionality ---

@test "T-001: normal write creates entry" {
    run bash "$TEST_TMPDIR/scripts/insight_write.sh" "test insight message" "medium" "test_source"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['insights']) == 1
assert data['insights'][0]['insight'] == 'test insight message'
assert data['insights'][0]['priority'] == 'medium'
assert data['insights'][0]['source'] == 'test_source'
assert data['insights'][0]['status'] == 'pending'
"
}

@test "T-002: dedup prevents duplicate entries" {
    run bash "$TEST_TMPDIR/scripts/insight_write.sh" "duplicate message" "high" "source1"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    run bash "$TEST_TMPDIR/scripts/insight_write.sh" "duplicate message" "low" "source2"
    [ "$status" -eq 0 ]
    [[ "$output" == SKIP:* ]]

    python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['insights']) == 1
"
}

# --- AC1: Injection prevention ---

@test "T-003: triple quotes in message don't cause injection" {
    run bash "$TEST_TMPDIR/scripts/insight_write.sh" "msg with '''triple quotes''' inside" "medium" "test"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['insights']) == 1
assert \"'''triple quotes'''\" in data['insights'][0]['insight']
"
}

@test "T-004: backslashes in message handled safely" {
    run bash "$TEST_TMPDIR/scripts/insight_write.sh" 'message with \n and \t and \\ backslashes' "high" "test"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['insights']) == 1
assert 'backslashes' in data['insights'][0]['insight']
"
}

@test "T-005: YAML metacharacters in message don't break structure" {
    run bash "$TEST_TMPDIR/scripts/insight_write.sh" "key: value, {dict}, [list], # comment" "medium" "test"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['insights']) == 1
assert 'key: value' in data['insights'][0]['insight']
assert '{dict}' in data['insights'][0]['insight']
"
}

@test "T-006: YAML metacharacters in priority and source fields" {
    # priority is now validated (high/medium/low only), so use valid priority
    # and test YAML metacharacter sanitization in source field
    run bash "$TEST_TMPDIR/scripts/insight_write.sh" "normal msg" "high" "source: [evil] {inject}"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['insights']) == 1
assert data['insights'][0]['priority'] == 'high'
assert data['insights'][0]['source'] == 'source: [evil] {inject}'
"
}

@test "T-007: Python code injection attempt in message is safely stored" {
    run bash "$TEST_TMPDIR/scripts/insight_write.sh" "'); import os; os.system('echo PWNED'); ('" "medium" "test"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['insights']) == 1
assert 'import os' in data['insights'][0]['insight']
"
}

# --- Resolve mode ---

@test "T-008: resolve mode works correctly" {
    run bash "$TEST_TMPDIR/scripts/insight_write.sh" "resolvable insight" "medium" "test"
    [ "$status" -eq 0 ]
    local id="$output"

    run bash "$TEST_TMPDIR/scripts/insight_write.sh" --resolve "$id"
    [ "$status" -eq 0 ]
    [[ "$output" == RESOLVED:* ]]

    python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert data['insights'][0]['status'] == 'done'
assert 'resolved_at' in data['insights'][0]
"
}

@test "T-009: INSIGHT_REPEAT bulletin includes insight body summary" {
    local test_source="rpt_src_$$"
    local captured_file="$TEST_TMPDIR/bulletin_captured.txt"
    local debounce_key="${test_source//[^a-zA-Z0-9_]/_}"
    local debounce_file="/tmp/shogun_insight_repeat_${debounce_key}.last"

    # Mock bulletin_write.sh to capture args to file (stdout is /dev/null in caller)
    cat > "$TEST_TMPDIR/scripts/bulletin_write.sh" << 'MOCK'
#!/bin/bash
echo "$@" >> "$CAPTURED_FILE"
MOCK
    chmod +x "$TEST_TMPDIR/scripts/bulletin_write.sh"

    # Clear debounce to ensure bulletin fires during this test
    rm -f "$debounce_file"

    # First insight (source_pending_count=1, below threshold=2, no bulletin)
    run env INSIGHT_SOURCE_REPEAT_THRESHOLD=2 CAPTURED_FILE="$captured_file" \
        bash "$TEST_TMPDIR/scripts/insight_write.sh" \
        "Alpha unique insight first entry" medium "$test_source"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    # Second insight (source_pending_count=2 >= threshold=2, triggers INSIGHT_REPEAT)
    run env INSIGHT_SOURCE_REPEAT_THRESHOLD=2 CAPTURED_FILE="$captured_file" \
        bash "$TEST_TMPDIR/scripts/insight_write.sh" \
        "Beta unique insight second entry" medium "$test_source"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    # Assert: bulletin was called and message contains insight body summary
    [ -f "$captured_file" ]
    grep -q "INSIGHT_REPEAT" "$captured_file"
    grep -q "insight_summary=" "$captured_file"
    grep -q "Beta unique insight" "$captured_file"

    # Cleanup debounce file
    rm -f "$debounce_file"
}
