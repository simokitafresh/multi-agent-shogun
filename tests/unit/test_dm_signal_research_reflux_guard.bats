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
