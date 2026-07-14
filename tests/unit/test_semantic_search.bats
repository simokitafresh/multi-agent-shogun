#!/usr/bin/env bats
# test_semantic_search.bats — semantic_search.sh unit tests
# Test-speed design: [[semantic-search-test-speed]]

setup_file() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PROJECT_ROOT
    export SEMANTIC_MASTER_INDEX="$BATS_FILE_TMPDIR/index.md"
    export SEMANTIC_SHARED_INDEX_CACHE_DIR="$BATS_FILE_TMPDIR/index_cache"
    mkdir -p "$SEMANTIC_SHARED_INDEX_CACHE_DIR"
    cat > "$SEMANTIC_MASTER_INDEX" <<'EOF'
# セマンティクスインデックス SSOT

## semantic_dictionary_design — セマンティック辞書構想

| 属性 | 値 |
|------|---|
| id | semantic_dictionary_design |
| label | セマンティック辞書構想 |
| aliases | セマンティック辞書, セマンティクスインデックス, 意味検索, 共通概念 |
| related_concepts | growth_loop(relation_type=上位) |

| 種別 | パス/参照 |
|------|----------|
| file | `docs/research/semantic_index_design.md` |
| url | `https://github.com/example/semantic-index-reference` |

## growth_loop — 学習ループ

| 属性 | 値 |
|------|---|
| id | growth_loop |
| label | 学習ループ |
| aliases | 学習ループ, 成長ループ, 二値計測, 共通概念, 三層学習ループ |
| related_concepts | semantic_dictionary_design |

| 種別 | パス/参照 |
|------|----------|
| file | `context/growth-loop.md` |

## local_memory_db — ローカル記憶DB

| 属性 | 値 |
|------|---|
| id | local_memory_db |
| label | ローカル記憶DB |
| aliases | SQLite記憶DB, multi_agent_shogun_memory.db, 記憶DB |
| related_concepts | three_layer_memory_system(relation_type=混同注意) |

| 種別 | パス/参照 |
|------|----------|
| file | `scripts/memory_db_query.sh` |
| should_not_merge_with | three_layer_memory_system — ローカル記憶DBはSQLite/FTS5検索層 |

## three_layer_memory_system — 三層記憶システム

| 属性 | 値 |
|------|---|
| id | three_layer_memory_system |
| label | 三層記憶システム |
| aliases | 三層記憶, 三層記憶システム, 三層記憶アーキテクチャ |
| related_concepts | local_memory_db(relation_type=混同注意), semantic_dictionary_design, growth_loop |

| 種別 | パス/参照 |
|------|----------|
| file | `context/memory-db-schema.md` |
| should_not_merge_with | local_memory_db — 三層記憶システムはDB単体ではなく全体アーキテクチャ |

## alm_research — ALM研究

| 属性 | 値 |
|------|---|
| id | alm_research |
| label | ALM研究 |
| aliases | ALM忍法 |
| related_concepts | growth_loop |

| 種別 | パス/参照 |
|------|----------|
| file | `context/gunshi-alm-38metrics-design.md` |

## gs_ninpo_research — GS忍法研究

| 属性 | 値 |
|------|---|
| id | gs_ninpo_research |
| label | GS忍法研究 |
| aliases | 忍法, L1パイプラインはBB1つ+EWで入力はL0四神PF累積リターン |
| related_concepts | growth_loop |

| 種別 | パス/参照 |
|------|----------|
| file | `context/gs-speedup-knowledge.md` |
EOF
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/semantic_search.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/docs/semantic-index"
    export SEMANTIC_INDEX_PATH="$TEST_TMPDIR/docs/semantic-index/index.md"
    cp "$SEMANTIC_MASTER_INDEX" "$SEMANTIC_INDEX_PATH"
    export SEMANTIC_CACHE_DIR="$TEST_TMPDIR/cache"
    export SEMANTIC_INDEX_CACHE_DIR="$SEMANTIC_SHARED_INDEX_CACHE_DIR"
    export SEMANTIC_DISABLE_MEMORY_DB_CACHE=1
    export SEMANTIC_MEMORY_DB_CACHE_DIR="$TEST_TMPDIR/memory_db_cache"
    mkdir -p "$TEST_TMPDIR/data"
    export SEMANTIC_SEARCH_LOG_DB_PATH="$TEST_TMPDIR/data/search_logs.db"
    export SEMANTIC_DISABLE_CAUSAL=1
    unset SEMANTIC_MEMORY_DB_PATH
    export SEMANTIC_DISABLE_MEMORY_DB=1
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "first layer returns alias match without invoking LLM" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "意味検索"

    [ "$status" -eq 0 ]
    [[ "$output" == *"## semantic_dictionary_design — セマンティック辞書構想"* ]]
    [[ "$output" == *"matched: 意味検索"* ]]
    [[ "$output" == *"docs/research/semantic_index_design.md"* ]]
    [[ "$output" == *"related_concepts:"* ]]
    [[ "$output" == *"relation_type: 上位"* ]]
    [[ "$output" == *"path_b_score:"* ]]
    [[ "$output" == *"## growth_loop — 学習ループ"* ]]
    [[ "$output" == *"context/growth-loop.md"* ]]
    [[ "$output" == *"- url: \`https://github.com/example/semantic-index-reference\`"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "semantic index parser accepts related_concepts with relation_type and legacy ids" {
    run python3 - "$PROJECT_ROOT" "$SEMANTIC_INDEX_PATH" <<'PY'
import importlib.util
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
index_path = pathlib.Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("semantic_index", root / "scripts" / "semantic_index.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

concepts = {concept["id"]: concept for concept in module.parse_index(index_path)}
semantic = concepts["semantic_dictionary_design"]["related_concepts"]
growth = concepts["growth_loop"]["related_concepts"]
assert semantic == [{"id": "growth_loop", "relation_type": "上位"}], semantic
assert growth == [{"id": "semantic_dictionary_design", "relation_type": "related"}], growth
PY
    [ "$status" -eq 0 ]
}

@test "semantic search excludes relation_type confusion-warning related concepts from expansion" {
    python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "| related_concepts | growth_loop(relation_type=上位) |",
    "| related_concepts | growth_loop(relation_type=混同注意) |",
    1,
)
path.write_text(text, encoding="utf-8")
PY
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "意味検索"

    [ "$status" -eq 0 ]
    [[ "$output" == *"## semantic_dictionary_design — セマンティック辞書構想"* ]]
    [[ "$output" != *"related_concepts:"* ]]
    [[ "$output" != *"## growth_loop — 学習ループ"* ]]
    [[ "$output" != *"relation_type: 混同注意"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "three-layer memory query reaches three_layer_memory_system and keeps local_memory_db as confusion warning" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "三層記憶"

    [ "$status" -eq 0 ]
    first_heading="$(grep '^## ' <<< "$output" | head -n 1)"
    [ "$first_heading" = "## three_layer_memory_system — 三層記憶システム" ]
    [[ "$output" == *"matched: 三層記憶"* ]]
    [[ "$output" == *"- should_not_merge_with: local_memory_db"* ]]
    [[ "$output" != *"relation_type: 混同注意"* ]]
    [[ "$output" != *"## local_memory_db — ローカル記憶DB"* ]]
}

@test "generic memory query does not overexpand into three_layer_memory_system" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "記憶"

    [ "$status" -eq 1 ]
    [[ "$output" == *"NO_MATCH: 記憶"* ]]
    [[ "$output" != *"three_layer_memory_system"* ]]
    [[ "$output" != *"local_memory_db"* ]]
}

@test "semantic_search memory DB cache refresh removes rollback journal sidecar" {
    export SEMANTIC_DISABLE_MEMORY_DB=0
    export SEMANTIC_DISABLE_MEMORY_DB_CACHE=0
    export SEMANTIC_MEMORY_DB_PATH="$TEST_TMPDIR/data/memory.db"
    export SEMANTIC_MEMORY_DB_CACHE_PATH="$TEST_TMPDIR/memory_db_cache/cache.db"
    export SEMANTIC_MEMORY_DB_TIMEOUT=2
    mkdir -p "$TEST_TMPDIR/memory_db_cache"
    python3 - "$SEMANTIC_MEMORY_DB_PATH" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute("CREATE TABLE events (id TEXT PRIMARY KEY, summary TEXT, detail TEXT)")
conn.execute("CREATE VIRTUAL TABLE events_fts USING fts5(summary, detail, content='events', content_rowid='rowid')")
conn.execute("INSERT INTO events (id, summary, detail) VALUES ('e1', 'cache journal keyword', '三層記憶')")
conn.execute("INSERT INTO events_fts(rowid, summary, detail) VALUES (1, 'cache journal keyword', '三層記憶')")
conn.commit()
conn.close()
PY
    touch "$SEMANTIC_MEMORY_DB_CACHE_PATH-journal" "$SEMANTIC_MEMORY_DB_CACHE_PATH-wal" "$SEMANTIC_MEMORY_DB_CACHE_PATH-shm"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "cache journal keyword"

    [ ! -e "$SEMANTIC_MEMORY_DB_CACHE_PATH-journal" ]
    [ ! -e "$SEMANTIC_MEMORY_DB_CACHE_PATH-wal" ]
    [ ! -e "$SEMANTIC_MEMORY_DB_CACHE_PATH-shm" ]
}

@test "three-layer learning loop remains routed to growth_loop" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "三層学習ループ"

    [ "$status" -eq 0 ]
    first_heading="$(grep '^## ' <<< "$output" | head -n 1)"
    [ "$first_heading" = "## growth_loop — 学習ループ" ]
    [[ "$output" == *"三層学習ループ"* ]]
    [[ "$output" != *"## three_layer_memory_system — 三層記憶システム"* ]]
}

@test "first layer expands related concept resources only for a single concept match" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "意味検索"

    [ "$status" -eq 0 ]
    [[ "$output" == *"related_concepts:"* ]]
    [[ "$output" == *"connection_strength="* ]]
    [[ "$output" == *"## growth_loop — 学習ループ"* ]]
    [[ "$output" == *"- file: \`context/growth-loop.md\`"* ]]
    [ "$(grep -c '^## semantic_dictionary_design' <<< "$output")" -eq 1 ]
    [[ "$output" != *"should-not-run"* ]]

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "共通概念"

    [ "$status" -eq 0 ]
    [[ "$output" == *"## semantic_dictionary_design — セマンティック辞書構想"* ]]
    [[ "$output" == *"## growth_loop — 学習ループ"* ]]
    [[ "$output" != *"related_concepts:"* ]]
}

@test "first layer prints shortest matched term first" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "忍法"

    [ "$status" -eq 0 ]
    first_heading="$(grep '^## ' <<< "$output" | head -n 1)"
    [ "$first_heading" = "## gs_ninpo_research — GS忍法研究" ]
    [[ "$output" == *"## alm_research — ALM研究"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "first layer matches multi-word query when every query word appears in one alias" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "L1パイプライン BB"

    [ "$status" -eq 0 ]
    first_heading="$(grep '^## ' <<< "$output" | head -n 1)"
    [ "$first_heading" = "## gs_ninpo_research — GS忍法研究" ]
    [[ "$output" == *"matched: L1パイプラインはBB1つ+EWで入力はL0四神PF累積リターン"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "multi-word query ignores single generic alias matches" {
    cat >> "$SEMANTIC_INDEX_PATH" <<'EOF'

## skill_routing — スキルルーティング

| 属性 | 値 |
|------|---|
| id | skill_routing |
| label | スキルルーティング |
| aliases | commit, スキル選択 |
| related_concepts | growth_loop |

| 種別 | パス/参照 |
|------|----------|
| file | `skills/ninja-commit/SKILL.md` |
EOF
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "context_freshness infrastructure.md source commits last_updated"

    [ "$status" -eq 1 ]
    [[ "$output" == *"NO_MATCH: context_freshness infrastructure.md source commits last_updated"* ]]
    [[ "$output" != *"## skill_routing"* ]]
    [[ "$output" != *"skills/ninja-commit/SKILL.md"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "unmatched first layer does not use LLM by default" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "品質を伸ばす輪"

    [ "$status" -eq 1 ]
    [[ "$output" == *"NO_MATCH: 品質を伸ばす輪"* ]]
    [[ "$output" == *"WARN: LLM fallback disabled by default"* ]]
    [[ "$output" != *"LLM_MATCH"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "explicit env allows unmatched first layer to fall back to LLM and resolve resources" {
    mock_llm="$TEST_TMPDIR/mock_llm.sh"
    cat > "$mock_llm" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo "MATCH: growth_loop"
echo "reason: the query asks about binary learning feedback."
echo "alias candidate: 品質を伸ばす輪"
EOF
    chmod +x "$mock_llm"
    export SEMANTIC_LLM_CMD="$mock_llm"
    export SEMANTIC_ENABLE_LLM_FALLBACK=1

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "品質を伸ばす輪"

    [ "$status" -eq 0 ]
    [[ "$output" == *"LLM_MATCH: 品質を伸ばす輪"* ]]
    [[ "$output" == *"MATCH: growth_loop"* ]]
    [[ "$output" == *"alias candidate: 品質を伸ばす輪"* ]]
    [[ "$output" == *"## growth_loop — 学習ループ"* ]]
    [[ "$output" == *"context/growth-loop.md"* ]]
    [[ "$output" != *"NO_MATCH"* ]]
}

@test "unmatched first layer returns memory DB FTS hits before LLM fallback" {
    archive_dir="$TEST_TMPDIR/archive"
    db_path="$TEST_TMPDIR/data/memory.db"
    mkdir -p "$archive_dir" "$TEST_TMPDIR/data"
    cat > "$archive_dir/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","target":"hayate","direction":"inbound","summary":"aliases未登録語の検索","detail":"DB FTS5フォールバックだけが拾える到達不能語 foobarmemoryonly 学習ループ"}
EOF
    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$archive_dir" \
        --db "$db_path" \
        --semantic-index "$SEMANTIC_INDEX_PATH"
    [ "$status" -eq 0 ]

    export SEMANTIC_MEMORY_DB_PATH="$db_path"
    unset SEMANTIC_DISABLE_MEMORY_DB
    export AGENT_ID=hayate
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "foobarmemoryonly"

    [ "$status" -eq 0 ]
    [[ "$output" == *"MEMORY_DB_MATCH: foobarmemoryonly"* ]]
    [[ "$output" == *"memory_db_concept_ranking:"* ]]
    [[ "$output" == *"top_concept: growth_loop"* ]]
    [[ "$output" == *"MATCH: growth_loop"* ]]
    [[ "$output" == *"aliases未登録語の検索"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "memory DB FTS concept ranking favors recently frequent concepts with R(c)" {
    archive_dir="$TEST_TMPDIR/archive"
    db_path="$TEST_TMPDIR/data/memory.db"
    mkdir -p "$archive_dir" "$TEST_TMPDIR/data"
    cat > "$archive_dir/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-01-01T00:00:00+09:00","agent":"lord","target":"hayate","direction":"inbound","summary":"needle recency old","detail":"needle セマンティック辞書"}
{"ts":"2026-05-25T00:00:00+09:00","agent":"lord","target":"hayate","direction":"inbound","summary":"needle recency recent 1","detail":"needle 学習ループ"}
{"ts":"2026-05-25T01:00:00+09:00","agent":"lord","target":"hayate","direction":"inbound","summary":"needle recency recent 2","detail":"needle 学習ループ"}
{"ts":"2026-05-25T02:00:00+09:00","agent":"lord","target":"hayate","direction":"inbound","summary":"needle recency recent 3","detail":"needle 学習ループ"}
EOF
    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$archive_dir" \
        --db "$db_path" \
        --semantic-index "$SEMANTIC_INDEX_PATH"
    [ "$status" -eq 0 ]

    export SEMANTIC_MEMORY_DB_PATH="$db_path"
    unset SEMANTIC_DISABLE_MEMORY_DB
    export SEMANTIC_RECENCY_NOW="2026-05-26T00:00:00+09:00"
    export SEMANTIC_RECLAMBDA_SENTINEL=unused
    export AGENT_ID=hayate
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "needle"

    [ "$status" -eq 0 ]
    [[ "$output" == *"top_concept: growth_loop"* ]]
    [[ "$output" == *"recency_weight:"* ]]
    [[ "$output" != *"idf:"* ]]
    [[ "$output" == *"ranked with R(c) recency-frequency"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "R(c) scaling uses IQR and median initialization for concepts without timestamps" {
    run env SEMANTIC_RECENCY_NOW="2026-05-26T00:00:00+00:00" python3 - "$PROJECT_ROOT" <<'PY'
import importlib.util
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("semantic_index", root / "scripts" / "semantic_index.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

weights = module.iqr_scaled_recency_weights(
    {
        "old": ["2026-01-01T00:00:00+00:00"],
        "recent": ["2026-05-25T00:00:00+00:00", "2026-05-25T01:00:00+00:00"],
        "new": [],
    }
)
assert weights["old"] < weights["new"] < weights["recent"], weights
PY
    [ "$status" -eq 0 ]
}

@test "search_log_write creates search_logs rows with caller separate from agent_id" {
    run bash "$PROJECT_ROOT/scripts/search_log_write.sh" \
        --db "$SEMANTIC_SEARCH_LOG_DB_PATH" \
        --caller semantic_search \
        --agent-id hayate \
        --elapsed-ms 12 \
        --exit-code 0 \
        "意味検索" 2 0

    [ "$status" -eq 0 ]

    readarray -t rows < <(python3 - "$SEMANTIC_SEARCH_LOG_DB_PATH" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute(
    "SELECT caller, agent_id, query, hit_count, no_match, elapsed_ms, exit_code FROM search_logs"
).fetchone()
print("|".join("" if value is None else str(value) for value in row))
PY
)
    [ "${rows[0]}" = "semantic_search|hayate|意味検索|2|0|12|0" ]

    run python3 - "$SEMANTIC_SEARCH_LOG_DB_PATH" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
columns = [row[1] for row in conn.execute("PRAGMA table_info(search_logs)")]
assert "ts" in columns, columns
assert "elapsed_ms" in columns, columns
PY
    [ "$status" -eq 0 ]
}

@test "semantic_search records hit and NO_MATCH rows after search completion" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "意味検索"
    [ "$status" -eq 0 ]

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "品質を伸ばす輪"
    [ "$status" -eq 1 ]

    readarray -t rows < <(python3 - "$SEMANTIC_SEARCH_LOG_DB_PATH" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
for row in conn.execute(
    """
    SELECT caller, query, hit_count, no_match, elapsed_ms, exit_code
    FROM search_logs
    ORDER BY id
    """
):
    print("|".join(str(value) for value in row))
PY
)
    [ "${#rows[@]}" -eq 2 ]
    [[ "${rows[0]}" == "semantic_search|意味検索|"* ]]
    [[ "${rows[0]}" == *"|0" ]]
    [[ "${rows[0]}" =~ ^semantic_search\\|意味検索\\|[0-9]+\\|0\\|[0-9]+\\|0$ ]]
    [[ "${rows[1]}" =~ ^semantic_search\\|品質を伸ばす輪\\|0\\|1\\|[0-9]+\\|1$ ]]
}

@test "semantic_search records logs when search_log_write is not executable" {
    helper_root="$TEST_TMPDIR/helper_root"
    mkdir -p "$helper_root/scripts"
    cp "$PROJECT_ROOT/scripts/semantic_search.sh" "$helper_root/scripts/semantic_search.sh"
    cp "$PROJECT_ROOT/scripts/semantic_index.py" "$helper_root/scripts/semantic_index.py"
    cp "$PROJECT_ROOT/scripts/search_log_write.sh" "$helper_root/scripts/search_log_write.sh"
    chmod 0644 "$helper_root/scripts/search_log_write.sh"
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$helper_root/scripts/semantic_search.sh" "意味検索"

    [ "$status" -eq 0 ]
    run python3 - "$SEMANTIC_SEARCH_LOG_DB_PATH" <<'PY'
import sqlite3
import sys
conn = sqlite3.connect(sys.argv[1])
row = conn.execute("SELECT query, no_match, exit_code FROM search_logs").fetchone()
assert row == ("意味検索", 0, 0), row
PY
    [ "$status" -eq 0 ]
}

@test "memory DB fallback filters hits to current agent target" {
    archive_dir="$TEST_TMPDIR/archive"
    db_path="$TEST_TMPDIR/data/memory.db"
    mkdir -p "$archive_dir" "$TEST_TMPDIR/data"
    cat > "$archive_dir/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"lord","target":"hayate","direction":"inbound","summary":"hayate宛の殿発言","detail":"sharedtargetneedle 学習ループ"}
{"ts":"2026-05-22T12:01:00+09:00","agent":"lord","target":"karo","direction":"inbound","summary":"karo宛の殿発言","detail":"sharedtargetneedle セマンティック辞書"}
EOF
    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$archive_dir" \
        --db "$db_path" \
        --semantic-index "$SEMANTIC_INDEX_PATH"
    [ "$status" -eq 0 ]

    export SEMANTIC_MEMORY_DB_PATH="$db_path"
    unset SEMANTIC_DISABLE_MEMORY_DB
    export AGENT_ID=hayate
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "sharedtargetneedle"

    [ "$status" -eq 0 ]
    [[ "$output" == *"MEMORY_DB_MATCH: sharedtargetneedle"* ]]
    [[ "$output" == *"top_concept: growth_loop"* ]]
    [[ "$output" == *"hayate宛の殿発言"* ]]
    [[ "$output" != *"karo宛の殿発言"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "memory DB fallback is bounded by SEMANTIC_MEMORY_DB_TIMEOUT" {
    db_path="$TEST_TMPDIR/data/memory.db"
    mkdir -p "$TEST_TMPDIR/data" "$TEST_TMPDIR/bin"
    : > "$db_path"
    cat > "$TEST_TMPDIR/bin/timeout" <<'EOF'
#!/usr/bin/env bash
exit 124
EOF
    chmod +x "$TEST_TMPDIR/bin/timeout"
    export PATH="$TEST_TMPDIR/bin:$PATH"
    export SEMANTIC_MEMORY_DB_PATH="$db_path"
    unset SEMANTIC_DISABLE_MEMORY_DB
    export SEMANTIC_MEMORY_DB_TIMEOUT=1
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "foobarmemoryonly"

    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN: memory DB FTS fallback timed out after 1s"* ]]
    [[ "$output" == *"NO_MATCH: foobarmemoryonly"* ]]
    [[ "$output" == *"WARN: LLM fallback disabled by default"* ]]
    [[ "$output" != *"LLM_MATCH"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "memory DB fallback timeout can use LLM only when explicitly enabled" {
    db_path="$TEST_TMPDIR/data/memory.db"
    mkdir -p "$TEST_TMPDIR/data" "$TEST_TMPDIR/bin"
    : > "$db_path"
    cat > "$TEST_TMPDIR/bin/timeout" <<'EOF'
#!/usr/bin/env bash
exit 124
EOF
    chmod +x "$TEST_TMPDIR/bin/timeout"
    export PATH="$TEST_TMPDIR/bin:$PATH"
    export SEMANTIC_MEMORY_DB_PATH="$db_path"
    unset SEMANTIC_DISABLE_MEMORY_DB
    export SEMANTIC_MEMORY_DB_TIMEOUT=1
    export SEMANTIC_ENABLE_LLM_FALLBACK=1
    export SEMANTIC_LLM_CMD="bash -c 'cat >/dev/null; echo MATCH: growth_loop'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "foobarmemoryonly"

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: memory DB FTS fallback timed out after 1s"* ]]
    [[ "$output" == *"LLM_MATCH: foobarmemoryonly"* ]]
    [[ "$output" == *"MATCH: growth_loop"* ]]
}

@test "first layer expands depth-1 event_links concepts before memory DB concept search" {
    archive_dir="$TEST_TMPDIR/archive"
    db_path="$TEST_TMPDIR/data/memory.db"
    mkdir -p "$archive_dir" "$TEST_TMPDIR/data"
    cat > "$archive_dir/2026-05-22.jsonl" <<'EOF'
{"ts":"2026-05-22T12:00:00+09:00","agent":"shogun","direction":"response","summary":"concept bridge","detail":"[[semantic_dictionary_design]] -> [[cmd_related_step]]"}
EOF
    run python3 "$PROJECT_ROOT/scripts/memory_db_import.py" \
        --archive-dir "$archive_dir" \
        --db "$db_path" \
        --semantic-index "$SEMANTIC_INDEX_PATH"
    [ "$status" -eq 0 ]

    export SEMANTIC_MEMORY_DB_PATH="$db_path"
    export SEMANTIC_CONCEPT_EXPANSION_LIMIT=20
    unset SEMANTIC_DISABLE_MEMORY_DB
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    SEMANTIC_DISABLE_CAUSAL=1 run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "意味検索"

    [ "$status" -eq 0 ]
    [[ "$output" == *"memory_db_concept_results:"* ]]
    [[ "$output" == *"depth: 1"* ]]
    [[ "$output" == *"expansion_limit: 20"* ]]
    [[ "$output" == *"seed_concepts: semantic_dictionary_design, growth_loop"* ]]
    [[ "$output" == *"expanded_concepts: cmd_related_step"* ]]
    [[ "$output" == *"concept bridge"* ]]
    [[ "$output" == *"causal_path:"* ]]
    [[ "$output" == *"links: [[cmd_related_step]] -> [[semantic_dictionary_design]]"* || "$output" == *"links: [[semantic_dictionary_design]] -> [[cmd_related_step]]"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "--llm forces LLM search even when aliases match" {
    mock_llm="$TEST_TMPDIR/mock_llm.sh"
    cat > "$mock_llm" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo "MATCH: growth_loop"
echo "reason: forced semantic search."
EOF
    chmod +x "$mock_llm"
    export SEMANTIC_LLM_CMD="$mock_llm"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" --llm "意味検索"

    [ "$status" -eq 0 ]
    [[ "$output" == *"LLM_MATCH: 意味検索"* ]]
    [[ "$output" == *"MATCH: growth_loop"* ]]
    [[ "$output" == *"## growth_loop — 学習ループ"* ]]
    [[ "$output" != *"matched: 意味検索"* ]]
}

@test "LLM command failure preserves the original exit status" {
    export SEMANTIC_LLM_CMD="exit 7"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" --llm "未知の問い"

    [ "$status" -eq 7 ]
    [[ "$output" == *"ERROR: LLM semantic search failed with exit code 7"* ]]
}

@test "second LLM call with same query hits cache and skips LLM" {
    counter_file="$TEST_TMPDIR/llm_calls"
    : > "$counter_file"
    mock_llm="$TEST_TMPDIR/mock_llm.sh"
    cat > "$mock_llm" <<EOF
#!/usr/bin/env bash
cat >/dev/null
echo call >> "$counter_file"
echo "MATCH: growth_loop"
echo "reason: cache test."
EOF
    chmod +x "$mock_llm"
    export SEMANTIC_LLM_CMD="$mock_llm"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" --llm "キャッシュ確認"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## growth_loop"* ]]
    [ "$(wc -l < "$counter_file")" -eq 1 ]

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" --llm "キャッシュ確認"
    [ "$status" -eq 0 ]
    [[ "$output" == *"## growth_loop"* ]]
    [ "$(wc -l < "$counter_file")" -eq 1 ]
}

@test "SEMANTIC_NO_CACHE=1 bypasses cache and re-invokes LLM" {
    counter_file="$TEST_TMPDIR/llm_calls"
    : > "$counter_file"
    mock_llm="$TEST_TMPDIR/mock_llm.sh"
    cat > "$mock_llm" <<EOF
#!/usr/bin/env bash
cat >/dev/null
echo call >> "$counter_file"
echo "MATCH: growth_loop"
echo "reason: no-cache test."
EOF
    chmod +x "$mock_llm"
    export SEMANTIC_LLM_CMD="$mock_llm"

    SEMANTIC_NO_CACHE=1 run bash "$PROJECT_ROOT/scripts/semantic_search.sh" --llm "再呼出し確認"
    [ "$status" -eq 0 ]
    SEMANTIC_NO_CACHE=1 run bash "$PROJECT_ROOT/scripts/semantic_search.sh" --llm "再呼出し確認"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$counter_file")" -eq 2 ]
}

@test "rejects whitespace-only query before invoking python or LLM" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "   "

    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR: query is empty or whitespace only"* ]]
    [[ "$output" == *"Usage: bash"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "parsed index cache stays in SEMANTIC_INDEX_CACHE_DIR" {
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"
    export SEMANTIC_INDEX_CACHE_DIR="$TEST_TMPDIR/index_cache_contract"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "意味検索"

    [ "$status" -eq 0 ]
    [ ! -e "${SEMANTIC_INDEX_PATH}.cache.json" ]
    [ "$(find "$SEMANTIC_INDEX_CACHE_DIR" -type f -name '*.json' | wc -l)" -eq 1 ]
}

@test "first layer appends causal backlink resources for Obsidian links" {
    unset SEMANTIC_DISABLE_CAUSAL
    mkdir -p "$TEST_TMPDIR/docs"
    python3 - "$SEMANTIC_INDEX_PATH" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = "| file | `context/growth-loop.md` |\n"
replacement = needle + "| causal_chain | `[[cmd_semantic_test]] -> [[semantic_edge]]` |\n| cmd | `cmd_plain_test` plain ID reference |\n"
path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
PY
    cat > "$TEST_TMPDIR/docs/trace.md" <<'EOF'
origin: [[cmd_semantic_test]]
plain: [[cmd_plain_test]]
EOF
    export SEMANTIC_CAUSAL_ROOT="$TEST_TMPDIR"
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "二値計測"

    [ "$status" -eq 0 ]
    [[ "$output" == *"causal_expansion:"* ]]
    [[ "$output" == *"- link: [[cmd_semantic_test]]"* ]]
    [[ "$output" == *"- link: [[cmd_plain_test]]"* ]]
    [[ "$output" == *"docs/trace.md"* ]]
    [[ "$output" != *"should-not-run"* ]]
}

@test "SEMANTIC_DISABLE_CAUSAL suppresses backlink expansion" {
    cat >> "$SEMANTIC_INDEX_PATH" <<'EOF'

| causal_chain | `[[cmd_semantic_test]]` |
EOF
    export SEMANTIC_CAUSAL_ROOT="$TEST_TMPDIR"
    export SEMANTIC_LLM_CMD="bash -c 'echo should-not-run >&2; exit 99'"

    SEMANTIC_DISABLE_CAUSAL=1 run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "二値計測"

    [ "$status" -eq 0 ]
    [[ "$output" != *"causal_expansion:"* ]]
    [[ "$output" != *"- link: [[cmd_semantic_test]]"* ]]
    [[ "$output" != *"should-not-run"* ]]
}
