#!/usr/bin/env bats
# test_semantic_search.bats — semantic_search.sh unit tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/semantic_search.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/docs/semantic-index"
    export SEMANTIC_INDEX_PATH="$TEST_TMPDIR/docs/semantic-index/index.md"

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
    [[ "$output" != *"should-not-run"* ]]
}

@test "unmatched first layer falls back to LLM and resolves resources" {
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

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "品質を伸ばす輪"

    [ "$status" -eq 0 ]
    [[ "$output" == *"LLM_MATCH: 品質を伸ばす輪"* ]]
    [[ "$output" == *"MATCH: growth_loop"* ]]
    [[ "$output" == *"alias candidate: 品質を伸ばす輪"* ]]
    [[ "$output" == *"## growth_loop — 学習ループ"* ]]
    [[ "$output" == *"context/growth-loop.md"* ]]
    [[ "$output" != *"NO_MATCH"* ]]
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

    run bash "$PROJECT_ROOT/scripts/semantic_search.sh" "未知の問い"

    [ "$status" -eq 7 ]
    [[ "$output" == *"ERROR: LLM semantic search failed with exit code 7"* ]]
}
