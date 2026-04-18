#!/usr/bin/env bats
# gate_codd_regression.sh unit tests (cmd_2060)

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/codd_regression.XXXXXX")"
    GATE="$BATS_TEST_DIRNAME/../../scripts/gates/gate_codd_regression.sh"
    chmod +x "$GATE"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

_make_registry() {
    local file="$TEST_ROOT/registry.md"
    {
        cat << 'HEADER'
# CoDD Refactor Registry

| 日付 | 実施者 | 対象スクリプト/領域 | Phase到達 | Before→After | spec/after設計書パス |
|------|--------|---------------------|-----------|--------------|----------------------|
HEADER
        printf '%s\n' "$@"
    } > "$file"
    echo "$file"
}

@test "no regression: all improvements (ms→ms)" {
    reg=$(_make_registry \
        "| 2026-04-18 | hanzo | \`scripts/test.sh\` | Phase 5 | \`100ms → 50ms\` (-50%) | spec |" \
        "| 2026-04-18 | hanzo | \`scripts/other.sh\` | Phase 5 | \`200ms → 80ms\` (-60%) | spec |")
    run bash "$GATE" "$reg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"WARN"* ]]
}

@test "regression detected: After > Before (ms→ms)" {
    reg=$(_make_registry \
        "| 2026-04-18 | hayate | \`.claude/hooks/stop-lint-gate.sh\` | Phase 5 | \`650ms → 840ms\` | spec |")
    run bash "$GATE" "$reg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"stop-lint"* ]]
    [[ "$output" == *"+29%"* ]]
}

@test "regression detected: mixed units ms→s" {
    reg=$(_make_registry \
        "| 2026-04-18 | hayate | \`.claude/hooks/stop-lint-gate.sh\` | Phase 5 | \`650ms → 0.84s\` (isolated) | spec |")
    run bash "$GATE" "$reg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"+29%"* ]]
}

@test "no regression: s→s improvement" {
    reg=$(_make_registry \
        "| 2026-04-18 | hayate | \`scripts/test.sh\` | Phase 5 | \`0.82s → 0.65s\` (-20.7%) | spec |")
    run bash "$GATE" "$reg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [[ "$output" != *"WARN"* ]]
}

@test "no regression: small change within 5% tolerance (noise)" {
    # 100ms → 104ms = +4% = within 5% tolerance
    reg=$(_make_registry \
        "| 2026-04-18 | hanzo | \`scripts/test.sh\` | Phase 5 | \`100ms → 104ms\` (+4%) | spec |")
    run bash "$GATE" "$reg"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
}

@test "regression: exactly 5.1% over threshold triggers WARN" {
    # 100ms → 106ms = +6% > 5% threshold
    reg=$(_make_registry \
        "| 2026-04-18 | hanzo | \`scripts/test.sh\` | Phase 5 | \`100ms → 106ms\` | spec |")
    run bash "$GATE" "$reg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
}

@test "unchanged timing (32ms→32ms) not flagged as regression" {
    reg=$(_make_registry \
        "| 2026-04-18 | tobisaru | \`scripts/diagnose.sh\` | Phase 5 | \`fast-path 32ms→32ms\`(unchanged) / slow-path \`100ms → 15ms\` | spec |")
    run bash "$GATE" "$reg"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
}

@test "missing registry returns SKIP exit 0" {
    run bash "$GATE" "/nonexistent/path/registry.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
}

@test "empty registry returns SKIP" {
    reg="$TEST_ROOT/empty_registry.md"
    echo "# empty" > "$reg"
    run bash "$GATE" "$reg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
}

@test "multiple regressions: both detected" {
    reg=$(_make_registry \
        "| 2026-04-18 | hanzo | \`scripts/a.sh\` | Phase 5 | \`100ms → 200ms\` | spec |" \
        "| 2026-04-18 | hanzo | \`scripts/b.sh\` | Phase 5 | \`50ms → 100ms\` | spec |")
    run bash "$GATE" "$reg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"a.sh"* ]]
    [[ "$output" == *"b.sh"* ]]
}
