#!/usr/bin/env bats
# test_necessity: Concurrent semantic writers serialize and preserve both updates without concept loss with monotonic invariant; violation is BLOCK.
# test_semantic_index_update.bats — semantic_index_update.sh unit tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/semantic_index_update.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/docs/semantic-index" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue" "$TEST_TMPDIR/context"
    export SEMANTIC_INDEX_PATH="$TEST_TMPDIR/docs/semantic-index/index.md"
    export SEMANTIC_MAP_PATH="$TEST_TMPDIR/context/semantic-map.md"
    # Most cases exercise index matching/update behavior; regenerating the
    # same map in every case is unrelated fixed cost.  Tests that assert map
    # output opt back into the production generator explicitly.
    export SEMANTIC_MAP_GENERATE=/bin/true
    export SEMANTIC_INSIGHT_WRITE="$TEST_TMPDIR/scripts/insight_write.sh"
    # Speed: デフォルトでは本番246MB DBを参照しない。memory DB tag propagationテストは自身でオーバーライドする
    export SEMANTIC_MEMORY_DB_PATH="$TEST_TMPDIR/nonexistent_memory.db"
    export SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION=1
    unset SEMANTIC_CMD_HISTORY_FILES
    unset SEMANTIC_INSIGHTS_PATH
    # Parallel Bats runs must not let background semantic_map_generate inspect
    # the real worktree's untracked files and queue unrelated insights.
    export SEMANTIC_NEW_FILE_LIST="__semantic_test_no_new_files__"
    unset SEMANTIC_PROJECTS_CONFIG

    # Keep real map generation focused on the two map-contract assertions.
    # Production defaults scan the full command chronicle and project registry,
    # which are unrelated to this unit fixture and grow with repository history.
    export SEMANTIC_CMD_HISTORY_FILES="$TEST_TMPDIR/nonexistent_cmd_history"
    export SEMANTIC_PROJECTS_CONFIG="$TEST_TMPDIR/nonexistent_projects.yaml"

    local shared_index="$BATS_FILE_TMPDIR/semantic_index.fixture.md"
    local shared_insight_write="$BATS_FILE_TMPDIR/semantic_insight_write.fixture.sh"
    if [ ! -f "$shared_index" ]; then
    cat > "$shared_index" <<'EOF'
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
    fi
    cp "$shared_index" "$SEMANTIC_INDEX_PATH"

    if [ ! -f "$shared_insight_write" ]; then
    cat > "$shared_insight_write" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--resolve" ]; then
    [ "$#" -eq 4 ] || exit 2
    python3 - "$2" "${SEMANTIC_INSIGHTS_PATH:-$TEST_TMPDIR/queue/insights.yaml}" "$3" "$4" <<'PY'
import sys
target, path, reason, artifact = sys.argv[1:5]
lines = open(path, encoding="utf-8").read().splitlines()
out = []
in_target = False
for line in lines:
    if line.startswith("- id: "):
        in_target = line[len("- id: "):].strip() == target
    if in_target and line.startswith("  status:"):
        out.extend(["  status: resolved", f'  resolved_reason: "{reason}"', f'  action_artifact: "{artifact}"', '  resolved_at: "2026-07-14T00:00:00+09:00"'])
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
    chmod +x "$shared_insight_write"
    fi
    cp "$shared_insight_write" "$SEMANTIC_INSIGHT_WRITE"
    chmod +x "$SEMANTIC_INSIGHT_WRITE"
}

@test "memory DB read path is resolved through shared ext4 cache helper" {
    local marker="$TEST_TMPDIR/cache-helper.args"
    local helper="$TEST_TMPDIR/mock-memory-db-cache.sh"
    cat > "$helper" <<'EOF'
prepare_memory_db_for_read() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" > "$SEMANTIC_TEST_CACHE_MARKER"
    printf '%s\n' "$2"
}
EOF

    SEMANTIC_TEST_CACHE_MARKER="$marker" \
    SEMANTIC_MEMORY_DB_CACHE_HELPER="$helper" \
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-07-13T17:00:00+09:00","summary":"cache resolver test"}'

    [ "$status" -eq 0 ]
    [ -s "$marker" ]
    grep -q "$PROJECT_ROOT|$SEMANTIC_MEMORY_DB_PATH|$PROJECT_ROOT/data/multi_agent_shogun_memory.db" "$marker"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "HIGH: exact alias appends cmd resource to matched concept" {
    export SEMANTIC_MAP_GENERATE="$PROJECT_ROOT/scripts/semantic_map_generate.sh"
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2564","title":"セマンティクスインデックス","purpose":"段階3","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: semantic_dictionary_design updated"* ]]
    [[ "$output" == *"semantic-map regenerated"* ]]

    grep -q '| cmd | `cmd_2564` セマンティクスインデックス' "$SEMANTIC_INDEX_PATH"
    grep -q 'セマンティック辞書構想' "$SEMANTIC_MAP_PATH"
    [ ! -f "$TEST_TMPDIR/queue/insights.log" ]
}

# test_necessity: ON updates must not replace the canonical index in the
# caller's checkout; the publisher receives the generated candidate instead.
@test "PUBLISHER_SINGLE: semantic indexはroot不変でledgerへ出す" {
    local state="${TEST_TMPDIR}/state"
    export SHOGUN_STATE_DIR="$state" PUBLISHER_SINGLE=1
    before="$(sha256sum "$SEMANTIC_INDEX_PATH" | awk '{print $1}')"
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete \
        '{"id":"cmd_publisher_single_semantic","title":"セマンティクスインデックス","purpose":"段階3","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [ "$(sha256sum "$SEMANTIC_INDEX_PATH" | awk '{print $1}')" = "$before" ]
    [ "$(find "$state/ledger_inbox/semantic_index" -maxdepth 1 -type f -name '*.yaml' | wc -l)" -eq 1 ]
    grep -q '"ledger": "semantic_index"' "$state"/ledger_inbox/semantic_index/*.yaml
}

@test "concurrent semantic writers serialize and preserve both updates without concept loss" {
    export SEMANTIC_MAP_GENERATE=/bin/true
    before="$(grep -c '^| id |' "$SEMANTIC_INDEX_PATH")"

    bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete \
        '{"id":"cmd_concurrent_a","title":"セマンティクスインデックス","purpose":"並行A","files":[]}' \
        >"$TEST_TMPDIR/a.log" 2>&1 &
    pid_a=$!
    bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete \
        '{"id":"cmd_concurrent_b","title":"セマンティクスインデックス","purpose":"並行B","files":[]}' \
        >"$TEST_TMPDIR/b.log" 2>&1 &
    pid_b=$!

    wait "$pid_a"
    wait "$pid_b"
    grep -q 'cmd_concurrent_a' "$SEMANTIC_INDEX_PATH"
    grep -q 'cmd_concurrent_b' "$SEMANTIC_INDEX_PATH"
    [ "$(grep -c '^| id |' "$SEMANTIC_INDEX_PATH")" -eq "$before" ]
    [ "$(find "$(dirname "$SEMANTIC_INDEX_PATH")" -maxdepth 1 -name '.index.md.*.tmp' | wc -l)" -eq 0 ]
}

@test "both semantic index writers enforce monotonic concept and duplicate-id invariants" {
    grep -q 'semantic index monotonicity violation' "$PROJECT_ROOT/scripts/semantic_index_update.sh"
    grep -q 'semantic index monotonicity violation' "$PROJECT_ROOT/scripts/semantic_map_generate.sh"
    grep -q 'duplicate concept ids' "$PROJECT_ROOT/scripts/semantic_index_update.sh"
    grep -q 'duplicate concept ids' "$PROJECT_ROOT/scripts/semantic_map_generate.sh"
}

@test "related_concepts relation_type format is preserved during index update" {
    python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索 |\n",
    "| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索 |\n| related_concepts | growth_loop(relation_type=上位) |\n",
    1,
)
path.write_text(text, encoding="utf-8")
PY

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_3151_fixture","title":"意味検索","purpose":"属性付きrelated_conceptsを保持","files":["scripts/semantic_index.py"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH: semantic_dictionary_design updated"* ]]

    grep -Fq '| related_concepts | growth_loop(relation_type=上位) |' "$SEMANTIC_INDEX_PATH"
}

@test "memory DB tag propagation uses FTS5 bm25 one-hop R(c) BH decay" {
    export SEMANTIC_MEMORY_DB_PATH="$TEST_TMPDIR/memory.db"
    python3 - "$SEMANTIC_MEMORY_DB_PATH" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
conn.executescript(
    """
    CREATE TABLE events (
        id TEXT PRIMARY KEY,
        ts TEXT,
        event_type TEXT,
        agent TEXT,
        target TEXT,
        direction TEXT,
        summary TEXT,
        detail TEXT,
        session_id TEXT,
        cmd_id TEXT,
        concepts TEXT,
        source_file TEXT,
        parent_event_id TEXT,
        importance TEXT
    );
    CREATE TABLE event_concepts (
        event_id TEXT NOT NULL,
        concept_name TEXT NOT NULL,
        PRIMARY KEY (event_id, concept_name)
    );
    CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid');
    """
)
rows = [
    ("tagged_semantic", "2026-05-26T00:00:00", "discussion", "shogun", "", "response", "意味検索 FTS5 タグ伝播", "セマンティック辞書構想の概念タグ", "", "", '["semantic_dictionary_design"]', "", "", "high"),
    ("untagged_semantic", "2026-05-26T00:01:00", "discussion", "shogun", "", "response", "意味検索 FTS5 タグ伝播", "未タグの類似イベント", "", "", "", "", "", "high"),
]
conn.executemany("INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
conn.execute("INSERT INTO event_concepts VALUES (?, ?)", ("tagged_semantic", "semantic_dictionary_design"))
conn.execute("INSERT INTO events_fts(events_fts) VALUES ('rebuild')")
conn.commit()
PY

    run env SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION=0 SEMANTIC_TAG_PROPAGATION_LIMIT=10 SEMANTIC_TAG_PROPAGATION_TTL=0 SEMANTIC_TAG_PROPAGATION_MIN_SCORE=0 SEMANTIC_MEMORY_DB_PATH="$SEMANTIC_MEMORY_DB_PATH" bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_2564","title":"セマンティクスインデックス","purpose":"段階3","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MEMORY_TAG_PROPAGATION"* ]]

    python3 - "$SEMANTIC_MEMORY_DB_PATH" <<'PY'
import json
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
rows = conn.execute(
    "SELECT concept_name FROM event_concepts WHERE event_id = 'untagged_semantic'"
).fetchall()
assert rows == [("semantic_dictionary_design",)], rows
concepts = conn.execute("SELECT concepts FROM events WHERE id = 'untagged_semantic'").fetchone()[0]
assert json.loads(concepts) == ["semantic_dictionary_design"], concepts
PY
}

@test "cmd_complete payload appends origin and depends_on causal resources" {
    export SEMANTIC_MAP_GENERATE="$PROJECT_ROOT/scripts/semantic_map_generate.sh"
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

@test "LOW: candidate aliases longer than 30 chars are rejected" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-05-05T00:00:00+09:00","summary":"セマンティクスインデックス長すぎる候補語を拒否するための長文alias"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated"* ]]
    [[ "$output" == *"aliases_added=none"* ]]

    ! grep '^| aliases |' "$SEMANTIC_INDEX_PATH" | grep -q 'セマンティクスインデックス長すぎる候補語を拒否するための長文alias'
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
if ! flock -w 1 "${SEMANTIC_INDEX_LOCK:?}" -c true; then
  echo 'semantic index lock was still held during post-update stress' >&2
  exit 9
fi
echo 'post_update_lock=acquired'
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
    export SEMANTIC_INDEX_LOCK="$SEMANTIC_INDEX_PATH.lock"

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-05-05T00:00:00+09:00","summary":"意味検索の話"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"semantic-stress after-alias-change: running"* ]]
    [[ "$output" == *"post_update_lock=acquired"* ]]
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

@test "NONE: duplicate discussion content skips insight_write when recent insight exists" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-RECENT-DUP
  ts: "2026-06-13T22:00:00+09:00"
  insight: "semantic_index_update新概念候補: discussion:サイクルを回し続けよう は 既存aliasesに一致なし。概念定義とaliases追加を検討せよ"
  priority: "low"
  source: "semantic_index_update"
  status: done
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-06-13T22:10:00+09:00","summary":"サイクルを回し続けよう"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: recent duplicate semantic insight"* ]]
    [[ "$output" == *"NONE: insight skipped for discussion:サイクルを回し続けよう"* ]]

    [ ! -f "$TEST_TMPDIR/queue/insights.log" ]
}

@test "NONE: first-seen discussion content still calls insight_write" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-OTHER
  ts: "2026-06-13T22:00:00+09:00"
  insight: "semantic_index_update新概念候補: discussion:別の発言 は 既存aliasesに一致なし。概念定義とaliases追加を検討せよ"
  priority: "low"
  source: "semantic_index_update"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-06-13T22:10:00+09:00","summary":"サイクルを回し続けよう"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NONE: insight queued for discussion:サイクルを回し続けよう"* ]]

    grep -q 'semantic_index_update新概念候補: discussion:サイクルを回し続けよう' "$TEST_TMPDIR/queue/insights.log"
}

@test "NONE: discussion timestamp with transport-only text is skipped as noise" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-05-20T23:00:11+09:00","summary":"task notification task id tool use id inbox1"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NONE: skipped noise-only candidate for discussion:task notification task id tool use id inbox1"* ]]

    [ ! -f "$TEST_TMPDIR/queue/insights.log" ]
}

# test_necessity: Ephemeral status questions must not create durable concepts,
# while reflective questions with lasting guidance must remain candidates.
@test "NONE: short discussion status question is skipped without suppressing reflective question" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-08-04T08:20:00+09:00","summary":"将軍はどうなってる？"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NONE: skipped noise-only candidate for discussion:将軍はどうなってる？"* ]]
    [ ! -f "$TEST_TMPDIR/queue/insights.log" ]

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" discussion '{"timestamp":"2026-08-04T08:21:00+09:00","summary":"小さく進めるのを忘れていないか？"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NONE: insight queued for discussion:小さく進めるのを忘れていないか？"* ]]
    grep -q '小さく進めるのを忘れていないか？' "$TEST_TMPDIR/queue/insights.log"
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
assert rows["INS-SIMILAR"]["status"] == "resolved"
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
assert rows["INS-INFO"]["status"] == "resolved"
assert rows["INS-RETURN"]["status"] == "resolved"
assert rows["INS-SEMANTIC"]["status"] == "resolved"
assert rows["INS-SEMANTIC"]["resolved_reason"]
assert rows["INS-SEMANTIC"]["action_artifact"]
PY
}

@test "pending semantic insights: semantic stress NO_MATCH is resolved when query now hits" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    export SEMANTIC_SEARCH_CMD="$TEST_TMPDIR/scripts/semantic_search.sh"
    cat > "$SEMANTIC_SEARCH_CMD" <<'EOF'
#!/usr/bin/env bash
if [ "$*" = "週報はnoteに下書きまで頼む" ]; then
    echo "MEMORY_DB_MATCH: $*"
    exit 0
fi
exit 1
EOF
    chmod +x "$SEMANTIC_SEARCH_CMD"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-RECHECK-HIT
  ts: "2026-06-12T00:00:00+09:00"
  insight: "[[週報はnoteに下書きまで頼む]] semantic_stress_test candidate_aliases: NO_MATCH source=lord query=週報はnoteに下書きまで頼む"
  priority: "low"
  source: "semantic_stress_test"
  status: pending
- id: INS-RECHECK-MISS
  ts: "2026-06-12T00:00:01+09:00"
  insight: "[[未知の別物]] semantic_stress_test candidate_aliases: NO_MATCH source=lord query=未知の別物"
  priority: "low"
  source: "semantic_stress_test"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete '{"id":"cmd_3316","title":"セマンティクスインデックス","purpose":"pending recheck","files":["scripts/semantic_index_update.sh"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS_RECHECK: hit now INS-RECHECK-HIT"* ]]
    [[ "$output" != *"週報はnoteに下書きまで頼む |"* ]]

    ! grep -q '週報はnoteに下書きまで頼む' "$SEMANTIC_INDEX_PATH"
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-RECHECK-HIT"]["status"] == "resolved"
assert rows["INS-RECHECK-MISS"]["status"] == "pending"
PY
}

@test "absorb_pending mode does not queue a new concept candidate" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-KNOWN
  ts: "2026-06-12T00:00:00+09:00"
  insight: "[[意味検索]] semantic_stress_test candidate_aliases: NO_MATCH source=lord query=意味検索"
  priority: "low"
  source: "semantic_stress_test"
  status: pending
EOF

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" absorb_pending '{}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS: already known 意味検索"* ]]
    [ ! -f "$TEST_TMPDIR/queue/insights.log" ]
}

@test "candidate_aliases蓄積分を既存概念aliasesへ自動追加しalias数差分を表示する" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    export SEMANTIC_PENDING_ALIAS_THRESHOLD=8
    export SEMANTIC_INDEX_CACHE_DIR="$TEST_TMPDIR/semantic_index_cache"
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-STRESS-AUTO
  ts: "2026-06-27T14:00:00+09:00"
  insight: "[[セマンティックインデックス改善]] semantic_stress_test candidate_aliases: NO_MATCH source=lord query=セマンティックインデックス改善"
  priority: "low"
  source: "semantic_stress_test"
  status: pending
EOF

    before_count="$(python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding="utf-8").read()
block = re.search(r"(?ms)^## semantic_dictionary_design\b.*?(?=^## |\Z)", text).group(0)
row = re.search(r"(?m)^\|\s*aliases\s*\|\s*(.*?)\s*\|$", block).group(1)
print(len([a for a in row.split(",") if a.strip()]))
PY
)"

    run env SEMANTIC_DISABLE_MEMORY_DB=1 SEMANTIC_DISABLE_LLM=1 SEMANTIC_DISABLE_SEARCH_LOG=1 \
        bash "$PROJECT_ROOT/scripts/semantic_search.sh" "セマンティックインデックス改善"
    [ "$status" -eq 1 ]

    run bash "$PROJECT_ROOT/scripts/semantic_alias_absorb_pending.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PENDING_ALIAS_SCORE: セマンティックインデックス改善 -> semantic_dictionary_design"* ]]
    [[ "$output" == *"pending_before=1"* ]]
    [[ "$output" == *"aliases_added=1"* ]]
    [[ "$output" == *"pending_after=0"* ]]
    rm -rf "$SEMANTIC_INDEX_CACHE_DIR"

    after_count="$(python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding="utf-8").read()
block = re.search(r"(?ms)^## semantic_dictionary_design\b.*?(?=^## |\Z)", text).group(0)
row = re.search(r"(?m)^\|\s*aliases\s*\|\s*(.*?)\s*\|$", block).group(1)
print(len([a for a in row.split(",") if a.strip()]))
PY
)"
    [ "$after_count" -eq "$((before_count + 1))" ]
    grep -q '| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索, セマンティックインデックス改善 |' "$SEMANTIC_INDEX_PATH"

    run env SEMANTIC_DISABLE_MEMORY_DB=1 SEMANTIC_DISABLE_LLM=1 SEMANTIC_DISABLE_SEARCH_LOG=1 \
        bash "$PROJECT_ROOT/scripts/semantic_search.sh" "セマンティックインデックス改善"
    [ "$status" -eq 0 ]
    [[ "$output" == *"semantic_dictionary_design"* ]]

    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-STRESS-AUTO"]["status"] == "resolved"
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
assert rows["INS-AC5"]["status"] == "resolved"
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
assert rows["INS-AC5-TRAINING"]["status"] == "resolved"
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
assert rows["INS-AC5-MANUAL"]["status"] == "resolved"
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
assert rows["INS-AC5-L7R"]["status"] == "resolved"
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
assert rows["INS-AC5-L7R-SIMILAR"]["status"] == "resolved"
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
assert similar["status"] == "resolved"
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

@test "lesson resource row preserves project-qualified or explicit stable ref" {
    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" lesson '{"id":"L893","project":"dm-signal","title":"学習ループ managed DB capability"}'
    [ "$status" -eq 0 ]
    grep -q '| lesson | `dm-signal:L893` 学習ループ managed DB capability |' "$SEMANTIC_INDEX_PATH"

    run bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" lesson '{"id":"L893","lesson_ref":"infra:L893","title":"学習ループ CLEAR best effort"}'
    [ "$status" -eq 0 ]
    grep -q '| lesson | `infra:L893` 学習ループ CLEAR best effort |' "$SEMANTIC_INDEX_PATH"
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
    grep -q 'semantic_causal_post_clear.sh' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q 'semantic_index_update.sh' "$PROJECT_ROOT/scripts/semantic_causal_post_clear.sh"
    grep -q 'CMD_YAML_FILE_ENV' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q '"origin": cmd_data.get("origin"' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q '"depends_on": cmd_data.get("depends_on"' "$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    grep -q 'semantic_index_update.sh.*lesson' "$PROJECT_ROOT/scripts/lesson_write.sh"
    grep -q 'semantic_index_update.sh.*discussion' "$PROJECT_ROOT/scripts/log_terminal_input.sh"
    grep -q 'semantic_map_generate.sh' "$PROJECT_ROOT/scripts/semantic_causal_post_clear.sh"
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

@test "semantic map generator auto-intakes projects, new files, and zero-cmd concept backfill" {
    cat > "$TEST_TMPDIR/projects.yaml" <<'EOF'
projects:
  - id: beta-tool
    name: "Beta Tool"
    path: "/tmp/beta-tool"
    context_file: "context/beta-tool.md"
    repo: "https://github.com/example/beta-tool"
    status: active
EOF
    cat > "$TEST_TMPDIR/cmd_history.yaml" <<'EOF'
commands:
  - id: cmd_4001
    purpose: "セマンティクスインデックスを更新する"
    status: completed
  - id: cmd_4002
    purpose: "学習ループと二値計測を強化する"
    status: completed
EOF

    run env \
        SEMANTIC_PROJECTS_CONFIG="$TEST_TMPDIR/projects.yaml" \
        SEMANTIC_CMD_HISTORY_FILES="$TEST_TMPDIR/cmd_history.yaml" \
        SEMANTIC_NEW_FILE_LIST="tests/fixtures/semantic_quality_test_set.json" \
        bash "$PROJECT_ROOT/scripts/semantic_map_generate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"project concepts auto-created: 1"* ]]
    [[ "$output" == *"cmd backfill rows added:"* ]]
    [[ "$output" == *"new file semantic insights queued: 1"* ]]

    grep -q '## project_beta_tool — Beta Tool' "$SEMANTIC_INDEX_PATH"
    grep -q '| related_concepts | external_project_registry |' "$SEMANTIC_INDEX_PATH"
    grep -q '| cmd | `cmd_4001` backfill' "$SEMANTIC_INDEX_PATH"
    grep -q '| cmd | `cmd_4002` backfill' "$SEMANTIC_INDEX_PATH"
    grep -q 'semantic_map_generate新規ファイル候補' "$TEST_TMPDIR/queue/insights.log"
    grep -q 'Beta Tool' "$SEMANTIC_MAP_PATH"

    python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
zero = []
for block in re.split(r"(?m)(?=^## )", text):
    if block.startswith("## ") and not re.search(r"^\|\s*cmd\s*\|", block, re.M):
        zero.append(block.splitlines()[0])
assert not zero, zero
PY
}

@test "semantic map generator makes related_concepts bidirectional" {
    python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索 |\n",
    "| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索 |\n| related_concepts | growth_loop |\n",
    1,
)
path.write_text(text, encoding="utf-8")
PY

    run bash "$PROJECT_ROOT/scripts/semantic_map_generate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"related_concepts bidirectional links added: 1"* ]]

    python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
blocks = {}
for part in re.split(r"(?m)(?=^## )", text):
    if part.startswith("## "):
        blocks[part.splitlines()[0][3:].split(" — ", 1)[0].strip()] = part
assert re.search(r"^\|\s*related_concepts\s*\|.*semantic_dictionary_design", blocks["growth_loop"], re.M)
PY
}

@test "semantic map generator excludes confusion-warning related_concepts from bidirectional links" {
    python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索 |\n",
    "| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索 |\n| related_concepts | growth_loop(relation_type=混同注意) |\n",
    1,
)
path.write_text(text, encoding="utf-8")
PY

    run bash "$PROJECT_ROOT/scripts/semantic_map_generate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"related_concepts bidirectional links added"* ]]

    python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
blocks = {}
for part in re.split(r"(?m)(?=^## )", text):
    if part.startswith("## "):
        blocks[part.splitlines()[0][3:].split(" — ", 1)[0].strip()] = part
assert not re.search(r"^\|\s*related_concepts\s*\|.*semantic_dictionary_design", blocks["growth_loop"], re.M)
PY
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
assert rows["INS-SEMANTIC"]["status"] == "resolved"
assert rows["INS-MANUAL"]["status"] == "pending"
PY
}

@test "semantic map generator auto-resolves handled new_file insights when enabled" {
    export SEMANTIC_INSIGHTS_PATH="$TEST_TMPDIR/queue/insights.yaml"
    mkdir -p "$TEST_TMPDIR/docs/research" "$TEST_TMPDIR/tests/unit"
    touch "$TEST_TMPDIR/docs/research/handled.md"
    touch "$TEST_TMPDIR/tests/unit/_tmp_generated.bats"
    mkdir -p "$TEST_TMPDIR/.karo_worktrees/probe"
    touch "$TEST_TMPDIR/.karo_worktrees/probe/transient.sh"
    touch "$TEST_TMPDIR/docs/research/unhandled.md"
    cat >> "$SEMANTIC_INDEX_PATH" <<'EOF'
| file | `docs/research/handled.md` |
EOF
    cat > "$SEMANTIC_INSIGHTS_PATH" <<'EOF'
insights:
- id: INS-HANDLED
  ts: "2026-06-24T00:00:00+09:00"
  insight: "semantic_map_generate新規ファイル候補: `docs/research/handled.md` は semantic index未登録。既存概念へのfile追加または新概念定義を検討せよ"
  priority: "low"
  source: "semantic_map_generate:new_file"
  status: pending
- id: INS-TMP
  ts: "2026-06-24T00:00:01+09:00"
  insight: "semantic_map_generate新規ファイル候補: `tests/unit/_tmp_generated.bats` は semantic index未登録。既存概念へのfile追加または新概念定義を検討せよ"
  priority: "low"
  source: "semantic_map_generate:new_file"
  status: pending
- id: INS-UNHANDLED
  ts: "2026-06-24T00:00:02+09:00"
  insight: "semantic_map_generate新規ファイル候補: `docs/research/unhandled.md` は semantic index未登録。既存概念へのfile追加または新概念定義を検討せよ"
  priority: "low"
  source: "semantic_map_generate:new_file"
  status: pending
- id: INS-WORKTREE
  ts: "2026-06-24T00:00:03+09:00"
  insight: "semantic_map_generate新規ファイル候補: `.karo_worktrees/probe/transient.sh` は semantic index未登録。既存概念へのfile追加または新概念定義を検討せよ"
  priority: "low"
  source: "semantic_map_generate:new_file"
  status: pending
EOF

    run env INSIGHTS_FILE="$SEMANTIC_INSIGHTS_PATH" SEMANTIC_INSIGHT_AUTO_RESOLVE=1 SEMANTIC_NEW_FILE_LIST=$'docs/research/handled.md\ntests/unit/_tmp_generated.bats\n.karo_worktrees/probe/transient.sh\ndocs/research/unhandled.md' bash "$PROJECT_ROOT/scripts/semantic_map_generate.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"semantic insights auto-resolved: 3"* ]]

    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_INSIGHTS_PATH"))
rows = {e["id"]: e for e in data["insights"]}
assert rows["INS-HANDLED"]["status"] == "resolved"
assert rows["INS-TMP"]["status"] == "resolved"
assert rows["INS-WORKTREE"]["status"] == "resolved"
assert rows["INS-UNHANDLED"]["status"] == "pending"
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

# ── provisional concept 自動生成テスト (AC1/AC2) ───────────────────────────

_setup_provisional_index() {
    # semantic_causal_automationを含むテスト用index.mdを上書き
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

## semantic_causal_automation — セマンティック因果自動化

| 属性 | 値 |
|------|---|
| id | semantic_causal_automation |
| label | セマンティック因果自動化 |
| aliases | セマンティック因果自動化, 因果辺自動還流 |
| related_concepts | |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/semantic_index_update.sh` |

## growth_loop — 学習ループ

| 属性 | 値 |
|------|---|
| id | growth_loop |
| label | 学習ループ |
| aliases | 学習ループ, 成長ループ |

| 種別 | パス/参照 |
|------|----------|
| file | `context/growth-loop.md` |
EOF
    mkdir -p "$TEST_TMPDIR/logs"
    export SEMANTIC_NO_MATCH_FILEPATH_LOG="$TEST_TMPDIR/logs/no_match_filepaths.yaml"
}

@test "AC1: NO_MATCH累積3回でprovisional conceptがindex.mdに挿入される" {
    _setup_provisional_index
    local payload_base='{"id":"cmd_prov_test","title":"test","files":["context/totally_unknown_concept.md"]}'

    # 1回目: count=1, provisional未生成
    run env \
        SEMANTIC_INDEX_PATH="$SEMANTIC_INDEX_PATH" \
        SEMANTIC_NO_MATCH_FILEPATH_LOG="$SEMANTIC_NO_MATCH_FILEPATH_LOG" \
        SEMANTIC_INSIGHT_WRITE="$SEMANTIC_INSIGHT_WRITE" \
        SEMANTIC_INSIGHTS_PATH="${SEMANTIC_INSIGHTS_PATH:-$TEST_TMPDIR/queue/insights.yaml}" \
        SEMANTIC_MAP_GENERATE=/dev/null \
        SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION=1 \
        bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete "$payload_base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO_MATCH_TRACKED: context/totally_unknown_concept.md count=1"* ]]
    ! grep -q "provisional_totally_unknown_concept" "$SEMANTIC_INDEX_PATH"

    # 2回目: count=2, provisional未生成
    run env \
        SEMANTIC_INDEX_PATH="$SEMANTIC_INDEX_PATH" \
        SEMANTIC_NO_MATCH_FILEPATH_LOG="$SEMANTIC_NO_MATCH_FILEPATH_LOG" \
        SEMANTIC_INSIGHT_WRITE="$SEMANTIC_INSIGHT_WRITE" \
        SEMANTIC_INSIGHTS_PATH="${SEMANTIC_INSIGHTS_PATH:-$TEST_TMPDIR/queue/insights.yaml}" \
        SEMANTIC_MAP_GENERATE=/dev/null \
        SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION=1 \
        bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete "$payload_base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO_MATCH_TRACKED: context/totally_unknown_concept.md count=2"* ]]
    ! grep -q "provisional_totally_unknown_concept" "$SEMANTIC_INDEX_PATH"

    # 3回目: count=3, provisional生成
    run env \
        SEMANTIC_INDEX_PATH="$SEMANTIC_INDEX_PATH" \
        SEMANTIC_NO_MATCH_FILEPATH_LOG="$SEMANTIC_NO_MATCH_FILEPATH_LOG" \
        SEMANTIC_INSIGHT_WRITE="$SEMANTIC_INSIGHT_WRITE" \
        SEMANTIC_INSIGHTS_PATH="${SEMANTIC_INSIGHTS_PATH:-$TEST_TMPDIR/queue/insights.yaml}" \
        SEMANTIC_MAP_GENERATE=/dev/null \
        SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION=1 \
        bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete "$payload_base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NO_MATCH_TRACKED: context/totally_unknown_concept.md count=3"* ]]
    [[ "$output" == *"PROVISIONAL_CONCEPT_GENERATED: provisional_totally_unknown_concept"* ]]
    grep -q "provisional_totally_unknown_concept" "$SEMANTIC_INDEX_PATH"

    # provisional conceptの必須フィールドを確認
    grep -q "| id | provisional_totally_unknown_concept |" "$SEMANTIC_INDEX_PATH"
    grep -q "| status | provisional |" "$SEMANTIC_INDEX_PATH"
    grep -q "| auto_generated | true |" "$SEMANTIC_INDEX_PATH"
    grep -q "| file | \`context/totally_unknown_concept.md\` |" "$SEMANTIC_INDEX_PATH"

    # no_match_filepaths.yaml の状態確認
    grep -q "provisional_generated: true" "$SEMANTIC_NO_MATCH_FILEPATH_LOG"
    grep -q "provisional_totally_unknown_concept" "$SEMANTIC_NO_MATCH_FILEPATH_LOG"
}

@test "AC2: NO_MATCH累積1-2回ではprovisional conceptが生成されない" {
    _setup_provisional_index
    local payload1='{"id":"cmd_ac2_1","title":"test","files":["context/yet_another_unknown.md"]}'
    local payload2='{"id":"cmd_ac2_2","title":"test","files":["context/yet_another_unknown.md"]}'

    # 1回目
    run env \
        SEMANTIC_INDEX_PATH="$SEMANTIC_INDEX_PATH" \
        SEMANTIC_NO_MATCH_FILEPATH_LOG="$SEMANTIC_NO_MATCH_FILEPATH_LOG" \
        SEMANTIC_INSIGHT_WRITE="$SEMANTIC_INSIGHT_WRITE" \
        SEMANTIC_INSIGHTS_PATH="${SEMANTIC_INSIGHTS_PATH:-$TEST_TMPDIR/queue/insights.yaml}" \
        SEMANTIC_MAP_GENERATE=/dev/null \
        SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION=1 \
        bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete "$payload1"
    [ "$status" -eq 0 ]
    ! grep -q "provisional_yet_another_unknown" "$SEMANTIC_INDEX_PATH"

    # 2回目
    run env \
        SEMANTIC_INDEX_PATH="$SEMANTIC_INDEX_PATH" \
        SEMANTIC_NO_MATCH_FILEPATH_LOG="$SEMANTIC_NO_MATCH_FILEPATH_LOG" \
        SEMANTIC_INSIGHT_WRITE="$SEMANTIC_INSIGHT_WRITE" \
        SEMANTIC_INSIGHTS_PATH="${SEMANTIC_INSIGHTS_PATH:-$TEST_TMPDIR/queue/insights.yaml}" \
        SEMANTIC_MAP_GENERATE=/dev/null \
        SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION=1 \
        bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete "$payload2"
    [ "$status" -eq 0 ]
    ! grep -q "provisional_yet_another_unknown" "$SEMANTIC_INDEX_PATH"

    # countが2であることをファイルで確認
    python3 - <<PY
import yaml
data = yaml.safe_load(open("$SEMANTIC_NO_MATCH_FILEPATH_LOG"))
entry = data["no_match_files"]["context/yet_another_unknown.md"]
assert entry["count"] == 2, f"expected count=2, got {entry['count']}"
assert entry["provisional_generated"] == False, "provisional_generated should be False"
PY
}

@test "AC1: provisional conceptはsemantic_causal_automationセクションの直後に挿入される" {
    _setup_provisional_index
    local payload='{"id":"cmd_pos_test","title":"test","files":["context/unique_position_check.md"]}'

    # 3回実行してprovisional生成
    for i in 1 2 3; do
        env \
            SEMANTIC_INDEX_PATH="$SEMANTIC_INDEX_PATH" \
            SEMANTIC_NO_MATCH_FILEPATH_LOG="$SEMANTIC_NO_MATCH_FILEPATH_LOG" \
            SEMANTIC_INSIGHT_WRITE="$SEMANTIC_INSIGHT_WRITE" \
            SEMANTIC_INSIGHTS_PATH="${SEMANTIC_INSIGHTS_PATH:-$TEST_TMPDIR/queue/insights.yaml}" \
            SEMANTIC_MAP_GENERATE=/dev/null \
            SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION=1 \
            bash "$PROJECT_ROOT/scripts/semantic_index_update.sh" cmd_complete "$payload" >/dev/null
    done

    # semantic_causal_automationより後にprovisionalが来ることを確認
    python3 - <<PY
content = open("$SEMANTIC_INDEX_PATH", encoding="utf-8").read()
pos_anchor = content.find("## semantic_causal_automation")
pos_provisional = content.find("## provisional_unique_position_check")
assert pos_anchor >= 0, "anchor concept not found"
assert pos_provisional >= 0, "provisional concept not found"
assert pos_provisional > pos_anchor, f"provisional({pos_provisional}) should be after anchor({pos_anchor})"
PY
}
