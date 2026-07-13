#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GUARD="$ROOT/scripts/dm_signal_research_reflux_guard.sh"
    TMP="$(mktemp -d)"
    DM="$TMP/DM-signal"
    OTHER="$TMP/other"
    CTX="$TMP/dm-signal-research.md"
    printf '# research\n<!-- last_updated: 2026-07-10 test -->\n' > "$CTX"
    for repo in "$DM" "$OTHER"; do
        git init -q "$repo"
        git -C "$repo" config user.email test@example.com
        git -C "$repo" config user.name test
        mkdir -p "$repo/docs/research"
        printf 'base\n' > "$repo/README.md"
        git -C "$repo" add README.md
        git -C "$repo" commit -qm baseline
    done
    export DM_SIGNAL_REPO="$DM"
    export DM_SIGNAL_REFLUX_CONTEXT_FILE="$CTX"
}

teardown() {
    rm -rf "$TMP"
}

make_split_contexts() {
    mkdir -p "$TMP/root/context"
    for name in core ops research; do
        printf '# %s\n<!-- last_updated: 2026-07-14 cmd_old -->\n<!-- source_commit:%s reason:old evidence:old -->\ncmd_3880 reflected\n' \
            "$name" "$(git -C "$DM" rev-parse --short HEAD)" > "$TMP/root/context/dm-signal-$name.md"
    done
}

@test "GA-249: reflected split 3件を同一commit markerへ同期する" {
    make_split_contexts
    printf 'same-day\n' >> "$DM/README.md"
    git -C "$DM" add README.md && git -C "$DM" commit -qm 'cmd_3880: same-day'
    head=$(git -C "$DM" rev-parse HEAD)
    run env SHOGUN_ROOT_DIR="$TMP/root" bash "$GUARD" sync-split --repo "$DM" --commit "$head" --cmd cmd_3880 \
        --context context/dm-signal-core.md --context context/dm-signal-ops.md --context context/dm-signal-research.md
    [ "$status" -eq 0 ]
    [ "$(grep -rl "source_commit:$head" "$TMP/root/context" | wc -l)" -eq 3 ]
}

@test "GA-249: content未反映1件があればmarker更新0件でfail-closed" {
    make_split_contexts
    sed -i 's/cmd_3880 reflected/not reflected/' "$TMP/root/context/dm-signal-ops.md"
    before=$(sha256sum "$TMP/root/context/"*.md)
    run env SHOGUN_ROOT_DIR="$TMP/root" bash "$GUARD" sync-split --repo "$DM" --commit "$(git -C "$DM" rev-parse HEAD)" --cmd cmd_3880 \
        --context context/dm-signal-core.md --context context/dm-signal-ops.md --context context/dm-signal-research.md
    [ "$status" -eq 1 ]
    [ "$before" = "$(sha256sum "$TMP/root/context/"*.md)" ]
}

@test "GA-249: 未統合commitと欠落contextをBLOCKする" {
    make_split_contexts
    git -C "$DM" checkout -qb future
    printf future >> "$DM/README.md" && git -C "$DM" commit -qam future
    future=$(git -C "$DM" rev-parse HEAD)
    git -C "$DM" checkout -q master
    run env SHOGUN_ROOT_DIR="$TMP/root" bash "$GUARD" sync-split --repo "$DM" --commit "$future" --cmd cmd_3880 --context context/dm-signal-core.md
    [ "$status" -eq 2 ]
    run env SHOGUN_ROOT_DIR="$TMP/root" bash "$GUARD" sync-split --repo "$DM" --commit "$(git -C "$DM" rev-parse HEAD)" --cmd cmd_3880 --context context/missing.md
    [ "$status" -eq 1 ]
}

@test "修正前相当: 証跡なしresearch commit候補をBLOCKする" {
    printf 'design\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    run bash "$GUARD" check --repo "$DM"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-220)"* ]]
}

@test "prepare済みfingerprintはPASSし同日再変更は再BLOCKする" {
    printf 'v1\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    run bash "$GUARD" prepare --repo "$DM" --mode synced --evidence 'context §54 synced'
    [ "$status" -eq 0 ]
    run bash "$GUARD" check --repo "$DM"
    [ "$status" -eq 0 ]

    printf 'v2\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    run bash "$GUARD" check --repo "$DM"
    [ "$status" -eq 2 ]
}

@test "明示的non-target証跡はPASSする" {
    printf '{}\n' > "$DM/docs/research/ops.json"
    git -C "$DM" add docs/research/ops.json
    run bash "$GUARD" prepare --repo "$DM" --mode non-target --evidence '運用証跡のため研究索引非対象'
    [ "$status" -eq 0 ]
    run bash "$GUARD" check --repo "$DM"
    [ "$status" -eq 0 ]
}

@test "他repoとDM-Signal非research commitは非発火" {
    printf 'x\n' > "$OTHER/docs/research/other.md"
    git -C "$OTHER" add docs/research/other.md
    run bash "$GUARD" check --repo "$OTHER"
    [ "$status" -eq 0 ]

    printf 'change\n' >> "$DM/README.md"
    git -C "$DM" add README.md
    run bash "$GUARD" check-command "cd '$DM' && git commit -m test"
    [ "$status" -eq 0 ]
}

@test "direct git commit command経路をBLOCKする" {
    printf 'design\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    run bash "$GUARD" check-command "git -C '$DM' commit -m test"
    [ "$status" -eq 2 ]
}

@test "ninja_scope_commit入口をcommit前BLOCKする" {
    printf 'design\n' > "$DM/docs/research/design.md"
    run bash -c "cd '$DM' && DM_SIGNAL_REPO='$DM' DM_SIGNAL_REFLUX_CONTEXT_FILE='$CTX' bash '$ROOT/scripts/ninja_scope_commit.sh' -m test -- docs/research/design.md"
    [ "$status" -eq 2 ]
    [ "$(git -C "$DM" rev-list --count HEAD)" -eq 1 ]
}

@test "実pre-bash hook入口をdirect commit前BLOCKする" {
    printf 'design\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C '$DM' commit -m test\"}}"
    run bash -c "cd '$DM' && printf '%s' '$payload' | BATS_TEST_FILENAME=fixture TMUX_AGENT_ID=shogun DM_SIGNAL_REPO='$DM' DM_SIGNAL_REFLUX_CONTEXT_FILE='$CTX' bash '$ROOT/.claude/hooks/pre-bash-combined.sh'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"GA-220"* ]]
    [ "$(git -C "$DM" rev-list --count HEAD)" -eq 1 ]
}

@test "実pre-bash hookはDM-Signal通常commitを許可する" {
    printf 'change\n' >> "$DM/README.md"
    git -C "$DM" add README.md
    payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C '$DM' commit -m test\"}}"
    run bash -c "cd '$DM' && printf '%s' '$payload' | BATS_TEST_FILENAME=fixture TMUX_AGENT_ID=shogun DM_SIGNAL_REPO='$DM' DM_SIGNAL_REFLUX_CONTEXT_FILE='$CTX' bash '$ROOT/.claude/hooks/pre-bash-combined.sh'"
    [ "$status" -eq 0 ]
}

@test "実pre-bash hookは一致するreflux証跡付きresearch commitを許可する" {
    printf 'design\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    bash "$GUARD" prepare --repo "$DM" --mode synced --evidence 'context §54 synced'
    payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C '$DM' commit -m test\"}}"
    run bash -c "cd '$DM' && printf '%s' '$payload' | BATS_TEST_FILENAME=fixture TMUX_AGENT_ID=shogun DM_SIGNAL_REPO='$DM' DM_SIGNAL_REFLUX_CONTEXT_FILE='$CTX' bash '$ROOT/.claude/hooks/pre-bash-combined.sh'"
    [ "$status" -eq 0 ]
}

# --- GA-220: linked worktree identity回帰テスト (git-common-dir正規化) ---

@test "GA-220: linked worktreeはmainと同一DM-Signal repoと判定され証跡なしresearch変更をBLOCKする" {
    git -C "$DM" worktree add -q "$TMP/dm-linked" -b wt-branch
    mkdir -p "$TMP/dm-linked/docs/research"
    printf 'design\n' > "$TMP/dm-linked/docs/research/design.md"
    git -C "$TMP/dm-linked" add docs/research/design.md
    run bash "$GUARD" check --repo "$TMP/dm-linked"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-220)"* ]]
}

@test "GA-220: linked worktreeでもprepare済みfingerprintはPASSする" {
    git -C "$DM" worktree add -q "$TMP/dm-linked2" -b wt-branch2
    mkdir -p "$TMP/dm-linked2/docs/research"
    printf 'v1\n' > "$TMP/dm-linked2/docs/research/design.md"
    git -C "$TMP/dm-linked2" add docs/research/design.md
    run bash "$GUARD" prepare --repo "$TMP/dm-linked2" --mode synced --evidence 'context §54 synced (worktree)'
    [ "$status" -eq 0 ]
    run bash "$GUARD" check --repo "$TMP/dm-linked2"
    [ "$status" -eq 0 ]
}

@test "GA-220: 他repoのlinked worktreeはDM-Signalと誤判定されず非発火のまま" {
    git -C "$OTHER" worktree add -q "$TMP/other-linked" -b other-wt
    mkdir -p "$TMP/other-linked/docs/research"
    printf 'x\n' > "$TMP/other-linked/docs/research/other.md"
    git -C "$TMP/other-linked" add docs/research/other.md
    run bash "$GUARD" check --repo "$TMP/other-linked"
    [ "$status" -eq 0 ]
}

@test "GA-220: 存在しないrepo pathはクラッシュせず非対象として安全にスキップされる" {
    run bash "$GUARD" check --repo "$TMP/does-not-exist"
    [ "$status" -eq 0 ]
}

@test "GA-220: DM_SIGNAL_REPO自体が無効pathならfail-closedでBLOCKする(設定不正を無音でスキップしない)" {
    printf 'design\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    run env DM_SIGNAL_REPO="$TMP/does-not-exist" DM_SIGNAL_REFLUX_CONTEXT_FILE="$CTX" bash "$GUARD" check --repo "$DM"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-220)"* ]]
    [[ "$output" == *"repo identityを解決できない"* ]]
}

@test "GA-220: bare repoを--repoに渡してもクラッシュせず安全に扱う" {
    git init -q --bare "$TMP/bare.git"
    run bash "$GUARD" check --repo "$TMP/bare.git"
    [ "$status" -eq 0 ]
}

# --- GA-220 multiline: heredoc/shell構文耐性のrepo抽出器 (cmd_karo_hotfix_ga220_multiline_commit_parser_202607121306) ---
# 根因: shlex.split()はheredocを理解せず、raw commandを一枚岩のshell引用テキストとして
# 走査するため、heredoc本文(commit messageのデータ)中の引用符がshlexの引用状態を狂わせる。
# 奇数個の埋込み"はValueError crashを誘発し、set -euo pipefailの終了コード伝播で
# check-command全体がresearch非対象の変更まで誤BLOCKしていた(修正前相当の再現はコメントで残す)。

@test "GA-220 multiline: heredoc commit本文に奇数個の埋込みダブルクォートがあっても非research変更を誤BLOCKしない" {
    printf 'change\n' >> "$DM/README.md"
    git -C "$DM" add README.md
    local body='fix(guard): handle "unbalanced quote case

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>'
    local cmd="cd '$DM' && git -C '$DM' commit -m \"\$(cat <<'EOF'
$body
EOF
)\""
    run bash "$GUARD" check-command "$cmd"
    [ "$status" -eq 0 ]
}

@test "GA-220 multiline: heredoc commit本文中のgit/commitという単語(prose)は個別repoとして誤検出しない" {
    printf 'change2\n' >> "$DM/README.md"
    git -C "$DM" add README.md
    local body='fix(docs): explain how to use git commit -m message in this repo

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>'
    local cmd="cd '$DM' && git -C '$DM' commit -m \"\$(cat <<'EOF'
$body
EOF
)\""
    run bash "$GUARD" check-command "$cmd"
    [ "$status" -eq 0 ]
}

@test "GA-220 multiline: heredoc commit(証跡なし)は複数git commandの区切り文字(&&,;)を挟んでもBLOCKする" {
    printf 'design\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    run bash "$GUARD" check-command "echo start && cd '$DM' ; git status ; git -C '$DM' commit -m test"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-220)"* ]]
}

@test "GA-220 multiline: 相対cdと相対git commitでも正しいrepoを抽出しBLOCKする" {
    printf 'design\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    local parent base
    parent="$(dirname "$DM")"
    base="$(basename "$DM")"
    cd "$parent"
    run bash "$GUARD" check-command "cd '$base' && git commit -m test"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-220)"* ]]
}

@test "GA-220 multiline: heredoc外の無効なshell引用符はクラッシュせずfail-closedでBLOCKする(allowlist禁止)" {
    run bash "$GUARD" check-command "git commit -m 'unterminated"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-220)"* ]]
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" != *"ValueError"* ]]
}

@test "GA-220 multiline: prepared linked worktreeのheredoc commitはPASSし同一commandでの再変更は再BLOCKする" {
    git -C "$DM" worktree add -q "$TMP/dm-linked3" -b wt-branch3
    mkdir -p "$TMP/dm-linked3/docs/research"
    printf 'v1\n' > "$TMP/dm-linked3/docs/research/design.md"
    git -C "$TMP/dm-linked3" add docs/research/design.md
    run bash "$GUARD" prepare --repo "$TMP/dm-linked3" --mode synced --evidence 'context sync (worktree heredoc)'
    [ "$status" -eq 0 ]

    local body='fix(research): sync design doc

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>'
    local cmd="cd '$TMP/dm-linked3' && git commit -m \"\$(cat <<'EOF'
$body
EOF
)\""
    run bash "$GUARD" check-command "$cmd"
    [ "$status" -eq 0 ]

    printf 'v2\n' > "$TMP/dm-linked3/docs/research/design.md"
    git -C "$TMP/dm-linked3" add docs/research/design.md
    run bash "$GUARD" check-command "$cmd"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-220)"* ]]
}

@test "GA-236 TOCTOU: 未staged状態でgit add+git commitが同一command連結された場合BLOCKする" {
    printf 'design\n' > "$DM/docs/research/design.md"
    run bash "$GUARD" check-command "cd '$DM' && git add docs/research/design.md && git commit -m test"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-220/GA-236)"* ]]
    [[ "$output" == *"TOCTOU"* ]]
    [ "$(git -C "$DM" rev-list --count HEAD)" -eq 1 ]
}

@test "GA-236 TOCTOU: docs/research対象外のgit add+git commit連結は誤BLOCKしない" {
    printf 'change\n' >> "$DM/README.md"
    run bash "$GUARD" check-command "cd '$DM' && git add README.md && git commit -m test"
    [ "$status" -eq 0 ]
}

@test "GA-236 TOCTOU: git commit -am連結もtracked docs/research変更をBLOCKする" {
    printf 'v1\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    git -C "$DM" commit -qm baseline2
    printf 'v2\n' > "$DM/docs/research/design.md"
    run bash "$GUARD" check-command "cd '$DM' && git commit -am test"
    [ "$status" -eq 2 ]
    [[ "$output" == *"TOCTOU"* ]]
}

@test "GA-236 TOCTOU: 実pre-bash hookでも同一command連結BLOCKが発火する" {
    printf 'design\n' > "$DM/docs/research/design.md"
    payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd '$DM' && git add docs/research/design.md && git commit -m test\"}}"
    run bash -c "cd '$DM' && printf '%s' '$payload' | BATS_TEST_FILENAME=fixture TMUX_AGENT_ID=shogun DM_SIGNAL_REPO='$DM' DM_SIGNAL_REFLUX_CONTEXT_FILE='$CTX' bash '$ROOT/.claude/hooks/pre-bash-combined.sh'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"GA-220"* ]]
    [ "$(git -C "$DM" rev-list --count HEAD)" -eq 1 ]
}
