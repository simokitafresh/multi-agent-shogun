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

install_selected_test_fixture() {
    local mode="$1"
    mkdir -p "$FAKE_REPO/tests/unit"
    printf '# changed\n' > "$FAKE_REPO/trigger.sh"
    cat > "$FAKE_REPO/scripts/test_select.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s/tests/unit/selected.bats\n' "$PWD"
EOF
    chmod +x "$FAKE_REPO/scripts/test_select.sh"
    cat > "$FAKE_REPO/scripts/run_tests.sh" <<EOF
#!/usr/bin/env bash
case "$mode" in
  timeout)
    trap '' TERM
    while :; do
      printf artifact > generated-by-timeout.txt
      sleep 0.05
    done
    ;;
  failure)
    exit 7
    ;;
esac
EOF
    chmod +x "$FAKE_REPO/scripts/run_tests.sh"
    printf '# fixture\n' > "$FAKE_REPO/tests/unit/selected.bats"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "add selected-test fixture"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"
}

install_cache_fingerprint_fixture() {
    export PREPUSH_TEST_COUNTER="$BATS_TEST_TMPDIR/prepush-test-runs"
    : > "$PREPUSH_TEST_COUNTER"
    mkdir -p "$FAKE_REPO/tests/unit"
    cat > "$FAKE_REPO/scripts/test_select.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s/tests/unit/selected.bats\n' "$PWD"
EOF
    cat > "$FAKE_REPO/scripts/run_tests.sh" <<'EOF'
#!/usr/bin/env bash
: "${PREPUSH_TEST_COUNTER:?}"
printf 'run\n' >> "$PREPUSH_TEST_COUNTER"
receipt_dir="${RUN_TESTS_RECEIPT_DIR:?}"
mkdir -p "$receipt_dir"
source_head="$(git rev-parse HEAD)"
tree_fingerprint="$(git ls-tree -r --full-tree "$source_head" -- \
    scripts lib tests .githooks .claude/hooks 2>/dev/null \
    | LC_ALL=C sort | sha256sum | awk '{print $1}')"
source_fingerprint="$(git ls-tree -r --full-tree "$source_head" -- \
    scripts lib tests/helpers 2>/dev/null \
    | awk '$4 != "scripts/run_tests.sh" {print $3}' \
    | sha256sum | awk '{print $1}')"
receipt="$receipt_dir/run_${source_head}.json"
artifact="${receipt%.json}.output"
printf '1..1\nok 1 selected\n' > "$artifact"
output_sha256="$(sha256sum "$artifact" | awk '{print $1}')"
python3 - "$receipt" "$artifact" "$output_sha256" "$source_head" \
    "$source_fingerprint" "$tree_fingerprint" <<'PY'
import json
import sys

receipt, artifact, output_sha256, source_head, source_fingerprint, tree_fingerprint = sys.argv[1:]
json.dump({
    "version": 3,
    "complete": True,
    "result": "PASS",
    "rc": 0,
    "duration_ms": 1,
    "output_sha256": output_sha256,
    "declared_test_count": 1,
    "observed_test_count": 1,
    "skip_count": 0,
    "artifact": artifact,
    "signal": None,
    "command": ["bash", "scripts/run_tests.sh", "affected"],
    "source_head": source_head,
    "test_paths": ["tests/unit/selected.bats"],
    "run_id": source_head,
    "commit_sha": source_head,
    "source_fingerprint": source_fingerprint,
    "tree_fingerprint": tree_fingerprint,
    "run_manifest": {
        "cache": {"directory": "", "enabled": False},
        "commit_sha": source_head,
        "selector_input_fingerprint": source_fingerprint,
        "selected_paths_fingerprint": source_fingerprint,
        "estimated_cost": {"selected_files": 1, "suite_timeout_sec": 60},
        "scope_identity": {
            "mode": "affected",
            "selected_file_count": 1,
            "discovered_file_count": None,
            "started_file_count": 1,
            "executed_file_count": 1,
            "cached_file_count": 0,
            "failed_files": [],
            "failed_file_count": 0,
            "complete": True,
            "full_scope": False,
            "full_scope_claimable": False,
        },
    },
}, open(receipt, "w", encoding="utf-8"))
PY
EOF
    chmod +x "$FAKE_REPO/scripts/test_select.sh" "$FAKE_REPO/scripts/run_tests.sh"
    printf '# selected contract\n' > "$FAKE_REPO/tests/unit/selected.bats"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "add cache fingerprint fixture"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"
}

latest_artifact_text() {
    find "$FAKE_REPO/logs/hook_artifacts" -name "*.log" -newer "$FAKE_REPO" -print0 2>/dev/null \
        | xargs -0 cat 2>/dev/null
}

# cmd_karo_hotfix_prepush_snapshot_cleanup_timeout_20260730
# test_necessity: a selected test that ignores TERM and writes an untracked
# artifact inside the clean snapshot must be fully stopped before worktree
# removal. The real incident removed Git registration but left one directory,
# falsely converting an allowed timeout WARN into a cleanup BLOCK.
@test "snapshot timeout waits for test descendants, WARNs, and leaves zero residue" {
    install_selected_test_fixture timeout

    run env PREPUSH_SELECTED_TEST_TIMEOUT_SECONDS=1 \
        PREPUSH_SELECTED_TEST_KILL_AFTER_SECONDS=1 bash -c \
        'cd "$1" && printf "refs/heads/main %s refs/heads/main %s\n" "$2" "$3" | bash "$4" origin "$1"' \
        _ "$FAKE_REPO" "$LOCAL_SHA" "$BASE_SHA" "$PREPUSH_HOOK"

    [ "$status" -eq 0 ]
    artifact="$(latest_artifact_text)"
    [ -z "$artifact" ]
    residue_count="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'shogun-prepush.*' -newer "$FAKE_REPO" | wc -l)"
    [ "$residue_count" -eq 0 ]
}

# test_necessity: an actual selected-test failure is not a timeout and must
# remain a BLOCK with its original non-zero status.
@test "snapshot selected-test real failure remains BLOCK" {
    install_selected_test_fixture failure

    run run_prepush

    [ "$status" -eq 7 ]
    [[ "$(latest_artifact_text)" == *"exit_code: 7"* ]]
}

# test_necessity: cleanup errors must never be swallowed merely to allow a
# push. A deterministic Git wrapper makes only worktree removal fail.
@test "snapshot cleanup failure remains BLOCK" {
    install_selected_test_fixture timeout
    real_git="$(command -v git)"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cleanup_fail_marker="$BATS_TEST_TMPDIR/cleanup-failed-once"
    cat > "$BATS_TEST_TMPDIR/bin/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-C" ] && [ "\$3" = "worktree" ] && [ "\$4" = "remove" ] \
        && [ ! -e "$cleanup_fail_marker" ]; then
  : > "$cleanup_fail_marker"
  exit 1
fi
exec "$real_git" "\$@"
EOF
    chmod +x "$BATS_TEST_TMPDIR/bin/git"

    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
        PREPUSH_SELECTED_TEST_TIMEOUT_SECONDS=1 \
        PREPUSH_SELECTED_TEST_KILL_AFTER_SECONDS=1 bash -c \
        'cd "$1" && printf "refs/heads/main %s refs/heads/main %s\n" "$2" "$3" | bash "$4" origin "$1"' \
        _ "$FAKE_REPO" "$LOCAL_SHA" "$BASE_SHA" "$PREPUSH_HOOK"

    [ "$status" -eq 1 ]
    [[ "$(latest_artifact_text)" == *"clean snapshot cleanup failed"* ]]
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

# cmd_karo_hotfix_prepush_semantic_index_autogen_20260730
# test_necessity: real incident — ninja_monitor.shのreflux backlink自動配備が
# docs/semantic-index/index.mdへ因果リンクを追加する非同期commitを生成する。
# このpathがpush対象commitの変更pathと重なると、GA-PUSH1が反復BLOCKし
# SHOGUN_PUSH_DIRTY_TREE_BYPASSの反復使用を強いていた。この正の境界fixtureは
# semantic-index SSOT単独の重複overlapがBLOCKされないことを保証する
# regressionである。
@test "AUTOGEN-EXCLUDE: overlap limited to docs/semantic-index/index.md (SSOT reflux path) is not blocked" {
    mkdir -p "$FAKE_REPO/scripts/lib" "$FAKE_REPO/docs/semantic-index"
    cp "$PROJECT_ROOT/scripts/lib/autogen_paths.sh" "$FAKE_REPO/scripts/lib/autogen_paths.sh"
    printf 'index v1\n' > "$FAKE_REPO/docs/semantic-index/index.md"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "add semantic index"
    printf 'index v2 (regenerated)\n' > "$FAKE_REPO/docs/semantic-index/index.md"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "publish semantic index update"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"

    printf 'index v3 (regenerated again, uncommitted)\n' > "$FAKE_REPO/docs/semantic-index/index.md"

    run run_prepush
    [ "$status" -eq 0 ]
    [ -z "$(latest_artifact_text)" ]
}

# test_necessity: the semantic-index exclusion must be an exact-path match,
# not a prefix/directory match — a sibling file under the same directory
# (e.g. a source file someone happens to add next to the SSOT) must still
# BLOCK on overlap. Guards against a regex that accidentally matches
# `^docs/semantic-index/` as a prefix instead of the single index.md path.
@test "AUTOGEN-EXCLUDE陰性(b): a different file under docs/semantic-index/ (not index.md itself) still BLOCKs on overlap" {
    mkdir -p "$FAKE_REPO/scripts/lib" "$FAKE_REPO/docs/semantic-index"
    cp "$PROJECT_ROOT/scripts/lib/autogen_paths.sh" "$FAKE_REPO/scripts/lib/autogen_paths.sh"
    printf 'sibling v1\n' > "$FAKE_REPO/docs/semantic-index/other.md"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "add sibling file"
    printf 'sibling v2\n' > "$FAKE_REPO/docs/semantic-index/other.md"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "publish sibling update"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"

    printf 'sibling v3 (uncommitted)\n' > "$FAKE_REPO/docs/semantic-index/other.md"

    run run_prepush
    [ "$status" -eq 1 ]
    artifact="$(latest_artifact_text)"
    [[ "$artifact" == *"BLOCK(GA-PUSH1)"* ]]
    [[ "$artifact" == *"docs/semantic-index/other.md"* ]]
}

# test_necessity: AC2's "混在は従来どおりBLOCKを維持する" requirement —
# a mixed overlap of the semantic-index SSOT path and an ordinary source
# path must still BLOCK, citing only the ordinary file, matching the
# existing lord-conversation-index.md mixed-overlap contract above.
@test "AUTOGEN-EXCLUDE陰性(d): overlap mixing docs/semantic-index/index.md and a normal file BLOCKs, citing only the normal file" {
    mkdir -p "$FAKE_REPO/scripts/lib" "$FAKE_REPO/docs/semantic-index"
    cp "$PROJECT_ROOT/scripts/lib/autogen_paths.sh" "$FAKE_REPO/scripts/lib/autogen_paths.sh"
    printf 'index v1\n' > "$FAKE_REPO/docs/semantic-index/index.md"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "add semantic index on top of shared.txt publish"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"

    printf 'not yet committed\n' >> "$FAKE_REPO/shared.txt"
    printf 'index v2 (regenerated, uncommitted)\n' > "$FAKE_REPO/docs/semantic-index/index.md"

    run run_prepush
    [ "$status" -eq 1 ]
    artifact="$(latest_artifact_text)"
    [[ "$artifact" == *"BLOCK(GA-PUSH1)"* ]]
    [[ "$artifact" == *$'\n  shared.txt'* ]]
    [[ "$artifact" != *$'\n  docs/semantic-index/index.md'* ]]
}

# cmd_karo_hotfix_t22_prepush_tree_cache_20260826
# test_necessity: the terminal Ninja PASS receipt must represent the committed
# affected-test tree, so a non-target operational commit reuses PASS with zero
# test reruns while a scripts/ blob change invalidates it and reruns once.
# overlaps_existing: true
# regression_justification: this suite already owns full pre-push hook fixtures;
# extending it reuses that contract boundary without adding another fixture file.
@test "terminal receipt keys the affected-test tree: insights hit, scripts miss" {
    install_cache_fingerprint_fixture

    run run_prepush
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PREPUSH_TEST_COUNTER")" -eq 1 ]
    first_receipt="$FAKE_REPO/logs/test_receipts/run_${LOCAL_SHA}.json"
    [ -f "$first_receipt" ]
    first_fingerprint="$(python3 - "$first_receipt" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["tree_fingerprint"])
PY
)"
    [[ "$first_fingerprint" =~ ^[0-9a-f]{64}$ ]]
    [ "$(python3 - "$first_receipt" <<'PY'
import json
import sys
receipt = json.load(open(sys.argv[1], encoding="utf-8"))
assert receipt["source_head"] == receipt["commit_sha"]
assert receipt["complete"] is True
assert receipt["result"] == "PASS"
assert receipt["rc"] == 0
assert receipt["skip_count"] == 0
print("terminal")
PY
)" = terminal ]

    mkdir -p "$FAKE_REPO/logs"
    printf 'published insight\n' > "$FAKE_REPO/logs/insights.yaml"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "insights: auto-commit"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"

    run run_prepush
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PREPUSH_TEST_COUNTER")" -eq 1 ]
    [ "$(find "$FAKE_REPO/logs/test_receipts" -maxdepth 1 -type f -name '*.json' -print | awk 'NF {n++} END {print n + 0}')" -eq 1 ]
    [ "$(python3 - "$first_receipt" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["tree_fingerprint"])
PY
)" = "$first_fingerprint" ]

    printf '# relevant source change\n' > "$FAKE_REPO/scripts/cache_target.sh"
    git -C "$FAKE_REPO" add -A
    git -C "$FAKE_REPO" commit -q -m "change affected-test source"
    LOCAL_SHA="$(git -C "$FAKE_REPO" rev-parse HEAD)"

    run run_prepush
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$PREPUSH_TEST_COUNTER")" -eq 2 ]
    second_receipt="$FAKE_REPO/logs/test_receipts/run_${LOCAL_SHA}.json"
    [ -f "$second_receipt" ]
    [ "$(find "$FAKE_REPO/logs/test_receipts" -maxdepth 1 -type f -name '*.json' -print | awk 'NF {n++} END {print n + 0}')" -eq 2 ]
    second_fingerprint="$(python3 - "$second_receipt" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["tree_fingerprint"])
PY
)"
    [[ "$second_fingerprint" =~ ^[0-9a-f]{64}$ ]]
    [ "$second_fingerprint" != "$first_fingerprint" ]
}
