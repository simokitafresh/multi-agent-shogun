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
    run bash "$TEST_TMPDIR/scripts/insight_write.sh" "normal msg" "high: {inject}" "source: [evil]"
    [ "$status" -eq 0 ]
    [[ "$output" == INS-* ]]

    python3 -c "
import yaml
with open('$TEST_TMPDIR/queue/insights.yaml') as f:
    data = yaml.safe_load(f)
assert len(data['insights']) == 1
assert data['insights'][0]['priority'] == 'high: {inject}'
assert data['insights'][0]['source'] == 'source: [evil]'
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
