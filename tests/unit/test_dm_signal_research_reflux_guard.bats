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
    run bash -c "cd '$DM' && printf '%s' '$payload' | BATS_TEST_FILENAME=fixture DM_SIGNAL_REPO='$DM' DM_SIGNAL_REFLUX_CONTEXT_FILE='$CTX' bash '$ROOT/.claude/hooks/pre-bash-combined.sh'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"GA-220"* ]]
    [ "$(git -C "$DM" rev-list --count HEAD)" -eq 1 ]
}

@test "実pre-bash hookはDM-Signal通常commitを許可する" {
    printf 'change\n' >> "$DM/README.md"
    git -C "$DM" add README.md
    payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C '$DM' commit -m test\"}}"
    run bash -c "cd '$DM' && printf '%s' '$payload' | BATS_TEST_FILENAME=fixture DM_SIGNAL_REPO='$DM' DM_SIGNAL_REFLUX_CONTEXT_FILE='$CTX' bash '$ROOT/.claude/hooks/pre-bash-combined.sh'"
    [ "$status" -eq 0 ]
}

@test "実pre-bash hookは一致するreflux証跡付きresearch commitを許可する" {
    printf 'design\n' > "$DM/docs/research/design.md"
    git -C "$DM" add docs/research/design.md
    bash "$GUARD" prepare --repo "$DM" --mode synced --evidence 'context §54 synced'
    payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C '$DM' commit -m test\"}}"
    run bash -c "cd '$DM' && printf '%s' '$payload' | BATS_TEST_FILENAME=fixture DM_SIGNAL_REPO='$DM' DM_SIGNAL_REFLUX_CONTEXT_FILE='$CTX' bash '$ROOT/.claude/hooks/pre-bash-combined.sh'"
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
