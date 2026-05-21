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
if [ "${1:-}" = "--resolve" ]; then
    python3 - "$2" "${SEMANTIC_INSIGHTS_PATH:-$TEST_TMPDIR/queue/insights.yaml}" <<'PY'
import sys
target, path = sys.argv[1:3]
lines = open(path, encoding="utf-8").read().splitlines()
out = []
in_target = False
for line in lines:
    if line.startswith("- id: "):
        in_target = line[len("- id: "):].strip() == target
    if in_target and line.startswith("  status:"):
        out.append("  status: done")
    else:
        out.append(line)
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
    echo "RESOLVED: $2"
    exit 0
fi
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

@test "cmd_complete payload appends origin and depends_on causal resources" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2885","title":"セマンティクスインデックス 因果辺","purpose":"semantic-mapへ因果辺を還流","files":["scripts/cmd_complete_gate.sh"],"origin":"[[cmd_2818_causal_NW]] -> [[semantic_map_generate]] -> [[obsidian_link_stagnation]]","depends_on":"[[cmd_2875]] -> [[セマンティック辞書構想]]"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: semantic_dictionary_design updated"* ]]

    grep -q '| causal | `cmd_2885` origin: \[\[cmd_2818_causal_NW\]\] -> \[\[semantic_map_generate\]\] -> \[\[obsidian_link_stagnation\]\] |' "$SEMANTIC_INDEX_PATH"
    grep -q '| causal | `cmd_2885` depends_on: \[\[cmd_2875\]\] -> \[\[セマンティック辞書構想\]\] |' "$SEMANTIC_INDEX_PATH"
    grep -q '`cmd_2885` origin:' "$SEMANTIC_MAP_PATH"
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

@test "LOW: alias expansion runs semantic stress test and records before/after diff" {
    cat > "$TEST_TMPDIR/scripts/semantic_stress_test.sh" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  case "$1" in
    --log) log="$2"; shift 2 ;;
    --baseline) baseline="$2"; shift 2 ;;
    --insights) insights="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$(dirname "$log")" "$(dirname "$baseline")" "$(dirname "$insights")"
printf '{"diff":{"hit_rate_delta":12.5,"no_match_delta":-2}}\n' >> "$log"
printf '{"hit_rate":50.0,"no_match":2,"total":4}\n' > "$baseline"
printf 'insights:\n' > "$insights"
echo 'before_after: hit_rate_delta=12.5 no_match_delta=-2 total_delta=0'
EOF
    chmod +x "$TEST_TMPDIR/scripts/semantic_stress_test.sh"
    export SEMANTIC_STRESS_CMD="$TEST_TMPDIR/scripts/semantic_stress_test.sh"
    export SEMANTIC_STRESS_LOG="$TEST_TMPDIR/logs/stress.log"
    export SEMANTIC_STRESS_BASELINE="$TEST_TMPDIR/logs/baseline.json"
    export INSIGHTS_FILE="$TEST_TMPDIR/queue/insights.yaml"

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-05-05T00:00:00+09:00","summary":"意味検索の話"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"semantic-stress after-alias-change: running"* ]]
    [[ "$output" == *"before_after: hit_rate_delta=12.5 no_match_delta=-2 total_delta=0"* ]]
    [[ "$output" == *"semantic-stress after-alias-change: complete"* ]]
    grep -q '"hit_rate_delta":12.5' "$SEMANTIC_STRESS_LOG"
}

@test "NONE: unmatched payload queues new concept candidate" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_none","title":"完全に未知の話題","purpose":"新規"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NONE: insight queued"* ]]

    grep -q 'semantic_index_update新概念候補' "$TEST_TMPDIR/queue/insights.log"
}

@test "NONE: discussion timestamp with transport-only text is skipped as noise" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-05-20T23:00:11+09:00","summary":"task notification task id tool use id inbox1"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NONE: skipped noise-only candidate for discussion:2026-05-20T23:00:11+09:00"* ]]

    [ ! -f "$TEST_TMPDIR/queue/insights.log" ]
}

@test "NONE: cmd_complete generic event payload is skipped as noise" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2914","title":"cmd_completeイベント","purpose":"GATE CLEAR PASS pending"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NONE: skipped noise-only candidate for cmd_complete:cmd_2914"* ]]

    [ ! -f "$TEST_TMPDIR/queue/insights.log" ]
}

@test "pending semantic insights: similar concept is absorbed into aliases and resolved" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-SIMILAR
  ts: "2026-05-20T00:00:00+09:00"
  insight: "semantic_index_update未登録cmd originノード: [[意味検索改善]] は既存aliasesに一致なし。概念定義とaliases追加を検討せよ"
  priority: "low"
  source: "semantic_index_update"
  status: pending
- id: INS-DISTANT
  ts: "2026-05-20T00:00:01+09:00"
  insight: "semantic_index_update未登録cmd originノード: [[完全別物]] は既存aliasesに一致なし。概念定義とaliases追加を検討せよ"
  priority: "low"
  source: "semantic_index_update"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2912","title":"セマンティクスインデックス","purpose":"pending alias吸収","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS_SCORE: 意味検索改善 -> semantic_dictionary_design"* ]]
    [[ "$output" == *"semantic-map regenerated"* ]]

    grep -q '| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索, 意味検索改善 |' "$SEMANTIC_INDEX_PATH"
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-SIMILAR"]["status"] == "done"
assert rows["INS-DISTANT"]["status"] == "pending"
PY
}

@test "pending semantic insights: operational noise is resolved without alias promotion" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-INFO
  ts: "2026-05-21T00:00:00+09:00"
  insight: "[[【INFOバッチ】 04 14 16 CI緑 run 26183925378]] semantic_stress_test candidate_aliases: NO_MATCH source=lord query=【INFOバッチ】 2026-05-21 04:14:16|CI緑: run 26183925378"
  priority: "low"
  source: "semantic_stress_test"
  status: pending
- id: INS-RETURN
  ts: "2026-05-21T00:00:01+09:00"
  insight: "[[【家老】復帰済み]] semantic_stress_test candidate_aliases: NO_MATCH source=lord query=【家老】復帰済み。全忍者idle。cmd待ち。"
  priority: "low"
  source: "semantic_stress_test"
  status: pending
- id: INS-SEMANTIC
  ts: "2026-05-21T00:00:02+09:00"
  insight: "[[意味検索改善]] semantic_stress_test candidate_aliases: NO_MATCH source=lord query=意味検索改善"
  priority: "low"
  source: "semantic_stress_test"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2934","title":"セマンティクスインデックス","purpose":"pending alias吸収","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS_SCORE: 意味検索改善 -> semantic_dictionary_design"* ]]
    [[ "$output" != *"PENDING_ALIAS_SCORE: 【INFOバッチ】"* ]]
    [[ "$output" != *"PENDING_ALIAS_SCORE: 【家老】復帰済み"* ]]

    grep -q '| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索, 意味検索改善 |' "$SEMANTIC_INDEX_PATH"
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-INFO"]["status"] == "done"
assert rows["INS-RETURN"]["status"] == "done"
assert rows["INS-SEMANTIC"]["status"] == "done"
PY
}

@test "pending semantic insights: concept-named AC5 alias lines auto-promote without similarity score" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-AC5
  ts: "2026-05-21T15:00:00+09:00"
  insight: "修行AC5 aliases候補: [[growth_loop]] alias: BLOCK後の環境改善, 失敗から仕組み化"
  priority: "low"
  source: "semantic_index_update"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2936","title":"学習ループ","purpose":"AC5 alias直接昇格","files":["context/training-cycle.md"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS_DIRECT: growth_loop -> growth_loop aliases_added=BLOCK後の環境改善, 失敗から仕組み化"* ]]
    [[ "$output" != *"PENDING_ALIAS_SCORE: BLOCK後の環境改善"* ]]
    [[ "$output" == *"semantic-map regenerated"* ]]

    grep -q '| aliases | 学習ループ, 成長ループ, 自動成長ループ, 二値計測, BLOCK後の環境改善, 失敗から仕組み化 |' "$SEMANTIC_INDEX_PATH"
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-AC5"]["status"] == "done"
PY
}

@test "pending semantic insights: direct alias lines from training source auto-promote end-to-end" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-AC5-TRAINING
  ts: "2026-05-21T15:05:00+09:00"
  insight: "[[growth_loop]] alias: BLOCK後仕組み化"
  priority: "low"
  source: "training"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2938","title":"学習ループ","purpose":"AC5 source filter relaxation","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS_DIRECT: growth_loop -> growth_loop aliases_added=BLOCK後仕組み化"* ]]

    grep -q '| aliases | 学習ループ, 成長ループ, 自動成長ループ, 二値計測, BLOCK後仕組み化 |' "$SEMANTIC_INDEX_PATH"
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-AC5-TRAINING"]["status"] == "done"
PY
}

@test "pending semantic insights: manual direct alias lines auto-promote" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-AC5-MANUAL
  ts: "2026-05-21T20:36:00+09:00"
  insight: "[[growth_loop]] alias: 手動蓄積alias昇格"
  priority: "medium"
  source: "manual"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2946","title":"学習ループ","purpose":"manual source direct alias","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS_DIRECT: growth_loop -> growth_loop aliases_added=手動蓄積alias昇格"* ]]

    grep -q '| aliases | 学習ループ, 成長ループ, 自動成長ループ, 二値計測, 手動蓄積alias昇格 |' "$SEMANTIC_INDEX_PATH"
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-AC5-MANUAL"]["status"] == "done"
PY
}

@test "pending semantic insights: direct alias lines from L7 round source auto-promote" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-AC5-L7R
  ts: "2026-05-21T20:35:00+09:00"
  insight: "[[growth_loop]] alias: 修行ラウンド起点の仕組み化"
  priority: "low"
  source: "hanzo-L7R5"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2946","title":"学習ループ","purpose":"AC5 L7 round source","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS_DIRECT: growth_loop -> growth_loop aliases_added=修行ラウンド起点の仕組み化"* ]]

    grep -q '| aliases | 学習ループ, 成長ループ, 自動成長ループ, 二値計測, 修行ラウンド起点の仕組み化 |' "$SEMANTIC_INDEX_PATH"
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-AC5-L7R"]["status"] == "done"
PY
}

@test "pending semantic insights: direct alias target can resolve through similar concept" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-AC5-L7R-SIMILAR
  ts: "2026-05-21T20:40:00+09:00"
  insight: "[[自動成長ループ改善]] alias: BLOCK後テンプレート改善, 修行結果の環境埋込み"
  priority: "low"
  source: "hayate-L7R5"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2946","title":"学習ループ","purpose":"AC5 similar direct target","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS_DIRECT: 自動成長ループ改善 matched growth_loop via 自動成長ループ"* ]]
    [[ "$output" == *"PENDING_ALIAS_DIRECT: 自動成長ループ改善 -> growth_loop aliases_added=BLOCK後テンプレート改善, 修行結果の環境埋込み"* ]]

    grep -q '| aliases | 学習ループ, 成長ループ, 自動成長ループ, 二値計測, BLOCK後テンプレート改善, 修行結果の環境埋込み |' "$SEMANTIC_INDEX_PATH"
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-AC5-L7R-SIMILAR"]["status"] == "done"
PY
}

@test "NO_MATCH purpose: cmd_complete queues pending aliases and L7f absorbs similar aliases" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    export INSIGHTS_FILE="$SEMANTIC_INSIGHTS_PATH"
    export SEMANTIC_INSIGHT_WRITE="$PROJECT_ROOT/scripts/insight_write.sh"
    export SEMANTIC_DEPLOY_LOG="$TEST_TMPDIR/logs/deploy_task.log"
    export SEMANTIC_NO_MATCH_SCAN_LINES=20
    mkdir -p "$TEST_TMPDIR/logs"
    cat > "$SEMANTIC_DEPLOY_LOG" <<'EOF'
[2026-05-20 10:00:00] [DEPLOY] inject_semantic_concepts: NO_MATCH purpose=意味検索改善 target_path=scripts/foo.sh
[2026-05-20 10:01:00] [DEPLOY] inject_semantic_concepts: NO_MATCH purpose=完全別物 target_path=scripts/bar.sh
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2920","title":"セマンティクスインデックス","purpose":"NO_MATCH purpose aliases","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO_MATCH_PURPOSE_ALIAS: queued 2 pending alias candidate(s)"* ]]
    [[ "$output" == *"PENDING_ALIAS_SCORE: 意味検索改善 -> semantic_dictionary_design"* ]]
    [[ "$output" == *"semantic-map regenerated"* ]]

    grep -q '| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索, 意味検索改善 |' "$SEMANTIC_INDEX_PATH"
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = data["insights"]
similar = [e for e in rows if "[[意味検索改善]]" in e["insight"]][0]
distant = [e for e in rows if "[[完全別物]]" in e["insight"]][0]
assert similar["status"] == "done"
assert distant["status"] == "pending"
PY
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

@test "cmd origin nodes: aliases are checked and only unknown origin node queues insight" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2910","title":"セマンティクスインデックス","purpose":"GATE CLEAR origin自動成長","origin":"[[cmd_2908]] -> [[成長ループ]] -> [[origin_aliases_gap]]","depends_on":"[[unknown_depends_node]]"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: semantic_dictionary_design updated"* ]]

    grep -q 'semantic_index_update未登録cmd originノード: \[\[origin_aliases_gap\]\]' "$TEST_TMPDIR/queue/insights.log"
    ! grep -q 'cmd originノード: \[\[成長ループ\]\]' "$TEST_TMPDIR/queue/insights.log"
    ! grep -q 'cmd originノード: \[\[cmd_2908\]\]' "$TEST_TMPDIR/queue/insights.log"
    grep -c 'origin_aliases_gap' "$TEST_TMPDIR/queue/insights.log" | grep -qx '1'
    grep -q 'semantic_index_update未登録\[\[リンク\]\]ターゲット: \[\[unknown_depends_node\]\]' "$TEST_TMPDIR/queue/insights.log"
}

@test "wiring: cmd_complete_gate, lesson_write, and log_terminal_input call semantic_index_update" {
    grep -q 'semantic_index_update.sh.*cmd_complete' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q 'CMD_YAML_FILE_ENV' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q '"origin": cmd_data.get("origin"' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q '"depends_on": cmd_data.get("depends_on"' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
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
