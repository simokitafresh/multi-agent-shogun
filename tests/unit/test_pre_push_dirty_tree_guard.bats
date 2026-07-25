#!/usr/bin/env bats
# cmd_karo_impl_commander_scope_commit_20260725
# test_necessity: reproduces the real incident (家老のpushが才蔵の未commit参照整理と
# 衝突しCI setup_fileをRED化した) as a regression fixture. Without this guard, a push
# whose commit touches a path that also has further uncommitted edits in the working
# tree is silently allowed, publishing a state the working tree itself has not
# finished reconciling.
#
# Note: pre-push redirects its own stderr into a per-run artifact file for
# hook_failures.yaml bookkeeping (see `_record_hook_failure`/`exec 2>` at the top of
# .githooks/pre-push), so BLOCK diagnostics land in logs/hook_artifacts/*.log rather
# than the caller-visible `run` output. Assertions read that artifact.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PREPUSH_HOOK="$PROJECT_ROOT/.githooks/pre-push"
    [ -f "$PREPUSH_HOOK" ] || return 1
}

setup() {
    export FAKE_REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FAKE_REPO"
    git -C "$FAKE_REPO" init -q
    git -C "$FAKE_REPO" config user.name test
    git -C "$FAKE_REPO" config user.email test@test.com
    git -C "$FAKE_REPO" config commit.gpgsign false

    # Downstream steps the hook runs after this guard (test selection, ontology
    # check) are unrelated infra this fixture does not exercise; stub them so the
    # bypass path can reach a clean exit 0 without pulling in the whole project.
    mkdir -p "$FAKE_REPO/scripts/gates"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_REPO/scripts/test_select.sh"
    chmod +x "$FAKE_REPO/scripts/test_select.sh"

    printf 'base\n' > "$FAKE_REPO/shared.txt"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "base"
    BASE_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"

    printf 'published change\n' >> "$FAKE_REPO/shared.txt"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "publish shared.txt change"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"
}

run_prepush() {
    (cd "$FAKE_REPO" && printf 'refs/heads/main %s refs/heads/main %s\n' "$LOCAL_SHA" "$BASE_SHA" | bash "$PREPUSH_HOOK" origin "$FAKE_REPO")
}

latest_artifact_text() {
    find "$FAKE_REPO/logs/hook_artifacts" -name "*.log" -newer "$FAKE_REPO" -print0 2>/dev/null \
        | xargs -0 cat 2>/dev/null
}

@test "push is BLOCKED when the pushed commit's path overlaps an uncommitted working-tree change" {
    printf 'not yet committed\n' >> "$FAKE_REPO/shared.txt"

    run run_prepush
    [ "$status" -eq 1 ]
    artifact="$(latest_artifact_text)"
    [[ "$artifact" == *"BLOCK(GA-PUSH1)"* ]]
    [[ "$artifact" == *"shared.txt"* ]]
}

@test "retrying the same dirty state produces the identical BLOCK (not a flaky pass-through)" {
    printf 'not yet committed\n' >> "$FAKE_REPO/shared.txt"

    run run_prepush
    [ "$status" -eq 1 ]
    [[ "$(latest_artifact_text)" == *"BLOCK(GA-PUSH1)"* ]]

    run run_prepush
    [ "$status" -eq 1 ]
    [[ "$(latest_artifact_text)" == *"BLOCK(GA-PUSH1)"* ]]
}

@test "a dirty path that does NOT overlap the pushed commit is not blocked by this guard" {
    printf 'unrelated wip\n' > "$FAKE_REPO/unrelated.txt"

    run run_prepush
    [[ "$(latest_artifact_text)" != *"BLOCK(GA-PUSH1)"* ]]
}

# cmd_karo_impl_commander_scope_commit_20260725 AC4
# test_necessity: emergency D0 pushes must not be blocked forever by this guard; the
# escape hatch must both let the push proceed past this check and record its use so
# usage is measurable (not a silent, unaudited bypass).
@test "escape hatch lets an overlapping push proceed and records the bypass with a reason" {
    printf 'not yet committed\n' >> "$FAKE_REPO/shared.txt"

    run env SHOGUN_PUSH_DIRTY_TREE_BYPASS="emergency CI RED fix" TMUX_AGENT_ID=karo bash -c \
        'cd "$1" && printf "refs/heads/main %s refs/heads/main %s\n" "$2" "$3" | bash "$4" origin "$1"' \
        _ "$FAKE_REPO" "$LOCAL_SHA" "$BASE_SHA" "$PREPUSH_HOOK"

    [ "$status" -eq 0 ]
    [ -f "$FAKE_REPO/logs/push_dirty_tree_bypass.jsonl" ]
    grep -q '"reason": "emergency CI RED fix"' "$FAKE_REPO/logs/push_dirty_tree_bypass.jsonl"
    grep -q '"agent": "karo"' "$FAKE_REPO/logs/push_dirty_tree_bypass.jsonl"
}
