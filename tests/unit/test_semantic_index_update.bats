#!/usr/bin/env bats
# test_semantic_index_update.bats — semantic_index_update.sh unit tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/semantic_index_update.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/docs/semantic-index" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    export SEMANTIC_INDEX_PATH="$TEST_TMPDIR/docs/semantic-index/index.md"
    export SEMANTIC_INSIGHT_WRITE="$TEST_TMPDIR/scripts/insight_write.sh"

    cat > "$SEMANTIC_INDEX_PATH" <<'EOF'
# セマンティクスインデックス SSOT

## semantic_dictionary_design — セマンティック辞書構想

| 属性 | 値 |
|------|---|
| id | semantic_dictionary_design |
| label | セマンティック辞書構想 |
| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索 |

| 種別 | パス/参照 |
|------|----------|
| file | `docs/research/semantic_index_design.md` |

## growth_loop — 学習ループ

| 属性 | 値 |
|------|---|
| id | growth_loop |
| label | 学習ループ |
| aliases | 学習ループ, 成長ループ, 二値計測 |

| 種別 | パス/参照 |
|------|----------|
| file | `context/growth-loop.md` |
EOF

    cat > "$SEMANTIC_INSIGHT_WRITE" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$1" "${2:-}" "${3:-}" >> "$TEST_TMPDIR/queue/insights.log"
echo "INS-TEST"
EOF
    chmod +x "$SEMANTIC_INSIGHT_WRITE"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "HIGH: exact alias appends cmd resource to matched concept" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2564","title":"セマンティクスインデックス","purpose":"段階3","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: semantic_dictionary_design updated"* ]]

    grep -q '| cmd | `cmd_2564` セマンティクスインデックス' "$SEMANTIC_INDEX_PATH"
    [ ! -f "$TEST_TMPDIR/queue/insights.log" ]
}

@test "HIGH: two partial aliases append lesson resource" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" lesson '{"id":"L999","title":"学習ループで二値計測を強制する","detail":"test"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: growth_loop updated"* ]]

    grep -q '| lesson | `L999` 学習ループで二値計測を強制する |' "$SEMANTIC_INDEX_PATH"
}

@test "LOW: one partial alias queues insight without editing index" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-05-05T00:00:00+09:00","summary":"意味検索の話"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOW: insight queued"* ]]

    grep -q 'semantic_index_update候補' "$TEST_TMPDIR/queue/insights.log"
    ! grep -q '2026-05-05T00:00:00' "$SEMANTIC_INDEX_PATH"
}

@test "NONE: unmatched payload queues new concept candidate" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_none","title":"完全に未知の話題","purpose":"新規"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NONE: insight queued"* ]]

    grep -q 'semantic_index_update新概念候補' "$TEST_TMPDIR/queue/insights.log"
}

@test "wiring: cmd_complete_gate, lesson_write, and log_terminal_input call semantic_index_update" {
    grep -q 'semantic_index_update.sh.*cmd_complete' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q 'semantic_index_update.sh.*lesson' "$PROJECT_ROOT/scripts/lesson_write.sh"
    grep -q 'semantic_index_update.sh.*discussion' "$PROJECT_ROOT/scripts/log_terminal_input.sh"
}
