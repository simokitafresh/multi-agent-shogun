#!/usr/bin/env bats
# test_semantic_index_update.bats — semantic_index_update.sh unit tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/semantic_index_update.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/docs/semantic-index" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/context"
    export SEMANTIC_INDEX_PATH="$TEST_TMPDIR/docs/semantic-index/index.md"
    export SEMANTIC_MAP_PATH="$TEST_TMPDIR/context/semantic-map.md"
    export SEMANTIC_MAP_GENERATE="$PROJECT_ROOT/scripts/semantic_map_generate.sh"
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
| url | `https://github.com/example/semantic-index-reference` |

## growth_loop — 学習ループ

| 属性 | 値 |
|------|---|
| id | growth_loop |
| label | 学習ループ |
| aliases | 学習ループ, 成長ループ, 自動成長ループ, 二値計測 |

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
    [[ "$output" == *"semantic-map regenerated"* ]]

    grep -q '| cmd | `cmd_2564` セマンティクスインデックス' "$SEMANTIC_INDEX_PATH"
    grep -q 'セマンティック辞書構想' "$SEMANTIC_MAP_PATH"
    [ ! -f "$TEST_TMPDIR/queue/insights.log" ]
}

@test "HIGH: map regeneration works when generator is readable but not executable" {
    cp "$PROJECT_ROOT/scripts/semantic_map_generate.sh" "$TEST_TMPDIR/scripts/semantic_map_generate.sh"
    chmod 0644 "$TEST_TMPDIR/scripts/semantic_map_generate.sh"
    export SEMANTIC_MAP_GENERATE="$TEST_TMPDIR/scripts/semantic_map_generate.sh"

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2565","title":"セマンティクスインデックス","purpose":"段階3","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: semantic_dictionary_design updated"* ]]
    [[ "$output" == *"semantic-map regenerated"* ]]

    grep -q 'セマンティック辞書構想' "$SEMANTIC_MAP_PATH"
}

@test "HIGH: two partial aliases append lesson resource" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" lesson '{"id":"L999","title":"学習ループで二値計測を強制する","detail":"test"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: growth_loop updated"* ]]

    grep -q '| lesson | `L999` 学習ループで二値計測を強制する |' "$SEMANTIC_INDEX_PATH"
}

@test "LOW: one partial alias triggers alias expansion and update" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-05-05T00:00:00+09:00","summary":"意味検索の話"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated"* ]]
    [[ "$output" == *"aliases_added"* ]]
}

@test "NONE: unmatched payload queues new concept candidate" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_none","title":"完全に未知の話題","purpose":"新規"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NONE: insight queued"* ]]

    grep -q 'semantic_index_update新概念候補' "$TEST_TMPDIR/queue/insights.log"
}

@test "wiki link target: unmatched causal link queues semantic concept insight" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" lesson '{"id":"L998","title":"学習ループで二値計測を強制する","origin":"[[cmd_2867]] -> [[B辞書自動更新+C概念自動発見]]"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: growth_loop updated"* ]]

    grep -q 'semantic_index_update未登録\[\[リンク\]\]ターゲット: \[\[B辞書自動更新+C概念自動発見\]\]' "$TEST_TMPDIR/queue/insights.log"
    grep -q '類似概念TOP3:' "$TEST_TMPDIR/queue/insights.log"
    ! grep -q '\[\[cmd_2867\]\]' "$TEST_TMPDIR/queue/insights.log"
}

@test "wiki link target: similar aliases are recommended and exact aliases are skipped" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" lesson '{"id":"L997","title":"二値計測の確認","origin":"[[自動成長ループ改善]] -> [[成長ループ]]"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: growth_loop updated"* ]]

    grep -q 'semantic_index_update未登録\[\[リンク\]\]ターゲット: \[\[自動成長ループ改善\]\]' "$TEST_TMPDIR/queue/insights.log"
    grep -q 'growth_loop(学習ループ; alias=自動成長ループ' "$TEST_TMPDIR/queue/insights.log"
    ! grep -q 'ターゲット: \[\[成長ループ\]\]' "$TEST_TMPDIR/queue/insights.log"
}

@test "wiring: cmd_complete_gate, lesson_write, and log_terminal_input call semantic_index_update" {
    grep -q 'semantic_index_update.sh.*cmd_complete' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q 'semantic_index_update.sh.*lesson' "$PROJECT_ROOT/scripts/lesson_write.sh"
    grep -q 'semantic_index_update.sh.*discussion' "$PROJECT_ROOT/scripts/log_terminal_input.sh"
    grep -q 'semantic_map_generate.sh' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q 'semantic_map_generate.sh' "$PROJECT_ROOT/scripts/lesson_write.sh"
}

@test "semantic map generator emits CoDD-tracked map from index" {
    run bash "$PROJECT_ROOT/scripts/semantic_map_generate.sh"
    [ "$status" -eq 0 ]

    grep -q 'node_id: design:semantic-map' "$SEMANTIC_MAP_PATH"
    grep -q 'modules:' "$SEMANTIC_MAP_PATH"
    grep -q 'セマンティック辞書構想' "$SEMANTIC_MAP_PATH"
    grep -q 'https://github.com/example/semantic-index-reference' "$SEMANTIC_MAP_PATH"
}

@test "semantic map generator auto-resolves semantic_index_update insights when enabled" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-SEMANTIC
  ts: "2026-05-15T00:00:00+09:00"
  insight: "semantic_index_update新概念候補"
  priority: "low"
  source: "semantic_index_update"
  status: pending
- id: INS-MANUAL
  ts: "2026-05-15T00:00:01+09:00"
  insight: "manual pending"
  priority: "medium"
  source: "manual"
  status: pending
EOF

    run env INSIGHTS_FILE="$SEMANTIC_INSIGHTS_PATH" SEMANTIC_INSIGHT_AUTO_RESOLVE=1 bash "$PROJECT_ROOT/scripts/semantic_map_generate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"semantic insights auto-resolved: 1"* ]]

    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-SEMANTIC"]["status"] == "done"
assert rows["INS-MANUAL"]["status"] == "pending"
PY
}

@test "CoDD and gunshi idle wiring mention semantic index propagation checks" {
    grep -q 'semantic_map_generate.sh --body-only' "$PROJECT_ROOT/codd/codd.yaml"
    grep -q 'semantic_index_drift' "$PROJECT_ROOT/instructions/gunshi.md"
    grep -q 'semantic_index_gap' "$PROJECT_ROOT/instructions/gunshi.md"
    grep -q 'semantic_index_candidate' "$PROJECT_ROOT/instructions/gunshi.md"
    grep -q 'semantic_index_drift' "$PROJECT_ROOT/scripts/gunshi_next_action.sh"
    grep -q 'semantic_index_gap' "$PROJECT_ROOT/scripts/gunshi_next_action.sh"
    grep -q 'semantic_index_candidate' "$PROJECT_ROOT/scripts/gunshi_next_action.sh"
}
