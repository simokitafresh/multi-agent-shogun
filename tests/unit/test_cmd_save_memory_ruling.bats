#!/usr/bin/env bats
# test_cmd_save_memory_ruling.bats — cmd_save.sh三層記憶・殿裁定自動表示テスト
# origin: [[殿指摘_三層記憶未使用_20260614]] -> [[cmd_3376]] -> [[全cmd起票前三層記憶検索強制]]

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PROJECT_ROOT
    SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_memory_ruling.XXXXXX")"
    export TEST_TMPDIR
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/projects"
    export PROJECT_DIR="$TEST_TMPDIR"

    # ── AC1用ラッパー: show_three_layer_memory_ruling_info ──
    {
        printf '#!/usr/bin/env bash\nset -euo pipefail\n'
        printf 'PROJECT_DIR="%s"\n' "$TEST_TMPDIR"
        printf '_SEMANTIC_SESSION_CACHE_DIR="%s/semantic_cache"\n' "$TEST_TMPDIR"
        printf 'mkdir -p "$_SEMANTIC_SESSION_CACHE_DIR" 2>/dev/null || true\n'
        printf 'CMD_BLOCK_NC="${1:-}"\n'
        sed -n '/^show_three_layer_memory_ruling_info()/,/^}$/p' "$SRC_SAVE_SCRIPT"
        printf 'show_three_layer_memory_ruling_info "$CMD_BLOCK_NC" 2>&1\n'
    } > "$TEST_TMPDIR/run_info.sh"
    chmod +x "$TEST_TMPDIR/run_info.sh"

    # ── AC2用ラッパー: check_projects_yaml_forbidden_topics ──
    {
        printf '#!/usr/bin/env bash\nset -euo pipefail\n'
        printf 'PROJECT_DIR="%s"\n' "$TEST_TMPDIR"
        printf 'CMD_BLOCK_NC="${1:-}"\nCMD_BLOCK="$CMD_BLOCK_NC"\n'
        # cmd_block_get_field の軽量スタブ（project フィールド取得用）
        cat <<'STUB'
cmd_block_get_field() {
    local field="${1:-}" default="${2:-}"
    printf '%s\n' "$CMD_BLOCK_NC" | awk -v f="$field" '
        $0 ~ "^[[:space:]]*" f ":[[:space:]]*" {
            sub(/^[[:space:]]*[a-z_-]+:[[:space:]]*/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            print; exit
        }
    ' | head -1
}
STUB
        sed -n '/^check_projects_yaml_forbidden_topics()/,/^}$/p' "$SRC_SAVE_SCRIPT"
        printf 'check_projects_yaml_forbidden_topics 2>&1\n'
    } > "$TEST_TMPDIR/run_forbidden.sh"
    chmod +x "$TEST_TMPDIR/run_forbidden.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ─── AC1: show_three_layer_memory_ruling_info ───

@test "AC1: semantic_searchがマッチすればINFO: [MEMORY_RULING]を出力する" {
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
printf 'MATCH: lord_ruling_alm_disco\n'
printf 'resource: projects/dm-signal.yaml forbidden_topics\n'
EOF
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"

    local block
    block='    title: "ALMディスコン確認"
    purpose: "ALM関連の残存コードを削除する"'

    CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/scripts/semantic_search.sh" \
        run bash "$TEST_TMPDIR/run_info.sh" "$block"

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: [MEMORY_RULING] 三層記憶検索(title+purpose基準):"* ]]
    [[ "$output" == *"MATCH: lord_ruling_alm_disco"* ]]
}

@test "AC1: semantic_searchが空結果の場合は何も出力しない" {
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
printf ''
EOF
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"

    local block
    block='    title: "無関係なcmd"
    purpose: "xyzzy"'

    CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/scripts/semantic_search.sh" \
        run bash "$TEST_TMPDIR/run_info.sh" "$block"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "AC1: semantic_searchが失敗してもエラーを返さない" {
    cat > "$TEST_TMPDIR/scripts/semantic_search.sh" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
    chmod +x "$TEST_TMPDIR/scripts/semantic_search.sh"

    local block
    block='    title: "テスト"
    purpose: "semantic失敗テスト"'

    CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/scripts/semantic_search.sh" \
        run bash "$TEST_TMPDIR/run_info.sh" "$block"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "AC1: semantic_search scriptが存在しない場合は安全にスキップ" {
    local block
    block='    title: "スクリプト不在テスト"
    purpose: "semantic_search不在でも落ちない"'

    CMD_SAVE_SEMANTIC_SEARCH_SCRIPT="$TEST_TMPDIR/scripts/nonexistent.sh" \
        run bash "$TEST_TMPDIR/run_info.sh" "$block"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ─── AC2: check_projects_yaml_forbidden_topics ───

@test "AC2: forbidden_topicがcmd内に含まれていればWARNINGを出力する" {
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<'EOF'
forbidden_topics:
  - topic: "ALM"
    rule: "殿が明示的に言わない限り話題に出すな。ALMはディスコン"
EOF

    local block
    block='    title: "ALM残存コード削除"
    purpose: "ALMモジュールの参照を全て除去する"
    project: dm-signal'

    run bash "$TEST_TMPDIR/run_forbidden.sh" "$block"

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: [MEMORY_RULING] forbidden_topic検出:"* ]]
    [[ "$output" == *"'ALM'"* ]]
    [[ "$output" == *"ALMはディスコン"* ]]
}

@test "AC2: forbidden_topicがcmdに含まれていなければWARNINGを出力しない" {
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<'EOF'
forbidden_topics:
  - topic: "ALM"
    rule: "殿が明示的に言わない限り話題に出すな。ALMはディスコン"
EOF

    local block
    block='    title: "GS改善"
    purpose: "グリッドサーチの高速化"
    project: dm-signal'

    run bash "$TEST_TMPDIR/run_forbidden.sh" "$block"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "AC2: projects yamlが存在しなければ安全にスキップする" {
    local block
    block='    title: "ALMテスト"
    purpose: "ALM動作確認"
    project: nonexistent-project'

    run bash "$TEST_TMPDIR/run_forbidden.sh" "$block"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "AC2: infra.yamlのforbidden_topicsも検索対象になる" {
    cat > "$TEST_TMPDIR/projects/infra.yaml" <<'EOF'
forbidden_topics:
  - topic: "old_workflow"
    rule: "旧ワークフローは廃止済み。言及禁止"
EOF

    local block
    block='    title: "old_workflow復活"
    purpose: "旧ワークフローを再有効化する"
    project: infra'

    run bash "$TEST_TMPDIR/run_forbidden.sh" "$block"

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: [MEMORY_RULING] forbidden_topic検出:"* ]]
    [[ "$output" == *"old_workflow"* ]]
}
