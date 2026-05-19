#!/usr/bin/env bats
# test_cmd_save_semantic_index.bats — cmd_save.sh semantic-index passive INFO tests

setup_file() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PROJECT_ROOT
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^show_semantic_index_matches()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^extract_q11_semantic_query()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^show_q11_semantic_search_matches()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^show_q11_causal_backlinks()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f show_semantic_index_matches extract_q11_semantic_query show_q11_semantic_search_matches show_q11_causal_backlinks
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_semantic.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/docs/semantic-index"
    export PROJECT_DIR="$TEST_TMPDIR"
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
| file | `context/semantic-map.md` |

## growth_loop — 学習ループ

| 属性 | 値 |
|------|---|
| id | growth_loop |
| label | 学習ループ |
| aliases | 学習ループ, 成長ループ, WF |

| 種別 | パス/参照 |
|------|----------|
| file | `context/growth-loop.md` |
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "alias match emits semantic label and primary files" {
    run bash -c 'show_semantic_index_matches "$1" 2>&1' _ "cmd起票時にセマンティクスインデックスを照合する"

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [SEMANTIC] セマンティック辞書構想 matched alias 'セマンティクスインデックス'"* ]]
    [[ "$output" == *"docs/research/semantic_index_design.md"* ]]
    [[ "$output" == *"context/semantic-map.md"* ]]
}

@test "no alias match stays silent" {
    run bash -c 'show_semantic_index_matches "$1" 2>&1' _ "完全に無関係なcmd"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "ASCII aliases require word boundary" {
    run bash -c 'show_semantic_index_matches "$1" 2>&1' _ "WFAだけを含むcmd"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]

    run bash -c 'show_semantic_index_matches "$1" 2>&1' _ "WF を実行するcmd"

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [SEMANTIC] 学習ループ matched alias 'WF'"* ]]
}

@test "q11 semantic_search emits concepts and causal cmd candidates" {
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
printf 'MATCH: causal_traversal_pipeline\n'
printf 'resource: scripts/semantic_search.sh\n'
printf '\ncausal_expansion:\n'
printf -- '- link: [[cmd_2866]]\n'
EOF
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"
    export CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/scripts/semantic_search.sh"

    block='    title: "強化 — q11 semantic search統合"
    purpose: "semantic_search.shをq11へ接続する"
    command: |
      scripts/cmd_save.sh のq11にsemantic_search.shを呼び出す
    quality_gate:
      q11_not_already_done: "grep単独では概念レベルの既存cmdを見逃す"'

    run bash -c 'show_q11_semantic_search_matches "$1" 2>&1' _ "$block"

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: q11 semantic_search 関連概念/既存cmd候補:"* ]]
    [[ "$output" == *"MATCH: causal_traversal_pipeline"* ]]
    [[ "$output" == *"cmd_2866"* ]]
}

@test "q11 semantic_search output is expanded through causal_backlinks" {
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/docs"
    cp "$PROJECT_ROOT/scripts/causal_backlinks.sh" "$TEST_TMPDIR/scripts/causal_backlinks.sh"
    chmod +x "$TEST_TMPDIR/scripts/causal_backlinks.sh"
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
printf 'MATCH: causal_traversal_pipeline\n'
printf 'cmd | `cmd_2875` related prior work\n'
printf 'lesson | `L512` relevant lesson\n'
EOF
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"
    cat > "$TEST_TMPDIR/docs/trace.md" <<'EOF'
origin: [[cmd_2875]]
lesson: [[L512]]
EOF
    export CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/scripts/semantic_search.sh"
    export CMD_SAVE_CAUSAL_BACKLINKS_SCRIPT="$TEST_TMPDIR/scripts/causal_backlinks.sh"
    export SEMANTIC_CAUSAL_ROOT="$TEST_TMPDIR"

    block='    title: "強化 — q11 causal backlinks統合"
    purpose: "semantic_search.shの結果からcausal_backlinks.shを呼び出す"
    command: |
      scripts/cmd_save.sh のq11に因果辺表示を追加する
    quality_gate:
      q11_not_already_done: "既存semantic_searchだけでは因果辺が起票前に見えない"'

    run bash -c 'show_q11_semantic_search_matches "$1" 2>&1' _ "$block"

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: q11 causal_backlinks 因果辺候補:"* ]]
    [[ "$output" == *"- link: [[cmd_2875]]"* ]]
    [[ "$output" == *"- link: [[L512]]"* ]]
    [[ "$output" == *"docs/trace.md"* ]]
}

@test "q11 semantic_search failure falls back without failing" {
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
echo "semantic backend down" >&2
exit 42
EOF
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"
    export CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/scripts/semantic_search.sh"

    block='    title: "強化 — q11 fallback"
    command: "scripts/cmd_save.sh を修正する"'

    run bash -c 'show_q11_semantic_search_matches "$1" 2>&1' _ "$block"

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: q11 semantic_search failed(rc=42)。既存grepチェックへフォールバックします"* ]]
}
