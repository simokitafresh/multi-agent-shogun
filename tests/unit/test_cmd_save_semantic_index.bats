#!/usr/bin/env bats
# test_cmd_save_semantic_index.bats — cmd_save.sh semantic-index passive INFO tests

setup_file() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PROJECT_ROOT
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^show_semantic_index_matches()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f show_semantic_index_matches
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
