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

# cmd_karo_impl_prepush_autogen_exclude_20260726
# test_necessity: real incident (logs/push_dirty_tree_bypass.jsonl
# 2026-07-25T15:13:56Z/18:09:14Z) — conversation_retention.sh regenerates
# context/lord-conversation-index.md on every agent turn, re-stamping
# generated_at even when the substantive content is unchanged. That made
# GA-PUSH1 fire on an auto-generated index and forced repeated
# SHOGUN_PUSH_DIRTY_TREE_BYPASS use. An overlap limited to auto-generated
# paths must not BLOCK.
@test "AUTOGEN-EXCLUDE: overlap limited to an auto-generated index path (context/lord-conversation-index.md, the real incident file) is not blocked" {
    mkdir -p "$FAKE_REPO/scripts/lib" "$FAKE_REPO/context"
    cp "$PROJECT_ROOT/scripts/lib/autogen_paths.sh" "$FAKE_REPO/scripts/lib/autogen_paths.sh"
    printf 'index v1\n' > "$FAKE_REPO/context/lord-conversation-index.md"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "add index"
    printf 'index v2 (regenerated)\n' > "$FAKE_REPO/context/lord-conversation-index.md"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "publish index update"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"

    # conversation_retention.shが数分ごとにgenerated_atだけ更新して再生成するのと
    # 同じ形: pushしたcommitと同じpathを未commitで再度上書きする。
    printf 'index v3 (regenerated again, uncommitted)\n' > "$FAKE_REPO/context/lord-conversation-index.md"

    # 成功path(exit 0)では_record_hook_failureが起動せずlogs/hook_artifacts/*.logへの
    # 書込みが発生しない(L945: hookのstderr redirectはBLOCK時のみartifact化される
    # 設計)ため、成功したことそのもの(exit 0・artifact不在)のみを検証する。
    run run_prepush
    [ "$status" -eq 0 ]
    [ -z "$(latest_artifact_text)" ]
}

# test_necessity: the exclusion must not weaken existing protection for
# ordinary (non-autogen) files even when the autogen lib is loaded —
# regression fixture for AC4(a).
@test "AUTOGEN-EXCLUDE陰性(a): with the autogen lib present, a normal file's dirty-overlap is still BLOCKed exactly as before" {
    mkdir -p "$FAKE_REPO/scripts/lib"
    cp "$PROJECT_ROOT/scripts/lib/autogen_paths.sh" "$FAKE_REPO/scripts/lib/autogen_paths.sh"
    printf 'not yet committed\n' >> "$FAKE_REPO/shared.txt"

    run run_prepush
    [ "$status" -eq 1 ]
    artifact="$(latest_artifact_text)"
    [[ "$artifact" == *"BLOCK(GA-PUSH1)"* ]]
    [[ "$artifact" == *"shared.txt"* ]]
}

# test_necessity: AC4(c) — a mixed overlap (autogen path + normal file) must
# still BLOCK, and the reported duplicate path must cite only the normal
# file so operators are not misled into thinking the exclusion is the
# blocker.
@test "AUTOGEN-EXCLUDE陰性(c): overlap mixing an auto-generated path and a normal file BLOCKs, citing only the normal file" {
    mkdir -p "$FAKE_REPO/scripts/lib" "$FAKE_REPO/context"
    cp "$PROJECT_ROOT/scripts/lib/autogen_paths.sh" "$FAKE_REPO/scripts/lib/autogen_paths.sh"
    printf 'index v1\n' > "$FAKE_REPO/context/lord-conversation-index.md"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "add index on top of shared.txt publish"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"

    printf 'not yet committed\n' >> "$FAKE_REPO/shared.txt"
    printf 'index v2 (regenerated, uncommitted)\n' > "$FAKE_REPO/context/lord-conversation-index.md"

    run run_prepush
    [ "$status" -eq 1 ]
    artifact="$(latest_artifact_text)"
    [[ "$artifact" == *"BLOCK(GA-PUSH1)"* ]]
    # 重複path一覧は "  <path>"(2文字インデント)で出力される。changed_filesの
    # 一覧セクションには通常インデントなしでlord-conversation-index.mdが載るため、
    # 「重複pathとして報告していない」ことをインデント付き文字列で厳密に確認する。
    [[ "$artifact" == *$'\n  shared.txt'* ]]
    [[ "$artifact" != *$'\n  context/lord-conversation-index.md'* ]]
}
