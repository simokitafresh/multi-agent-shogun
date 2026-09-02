#!/usr/bin/env bats
# test_necessity: cmd_4446 単一publisher化 U2(docs/research/single_publisher_asis_tobe_5w1h_20260902.md
# §9.1)。忍者 worktree の local commit 成果物(source_tree+patch)を report_received 時点で
# STATE_DIR へ複製し、worktree 消失後も publisher が tree id 一致で復元できることと、
# 報告 gate が manifest の source_sha/paths 不一致を検出することを守る不変量。
# origin: [[cmd_4446_U2_publish_artifact]] -> [[single_publisher_asis_tobe_5w1h_20260902_v35_APPROVE]] -> [[worktree消失後の成果物復元]]

bats_require_minimum_version 1.5.0

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    PUBLISH_ARTIFACT="$REPO_ROOT/scripts/publish_artifact.sh"
    GATE="$REPO_ROOT/scripts/gates/gate_report_format.sh"
    export SHOGUN_STATE_DIR="$BATS_TEST_TMPDIR/state"
}

setup_fixture_repo() {
    local repo="$1"
    git init -q "$repo"
    git -C "$repo" config user.email test@example.invalid
    git -C "$repo" config user.name fixture
    printf 'A\n' > "$repo/a.txt"
    printf 'KEEP\n' > "$repo/keep.txt"
    git -C "$repo" add a.txt keep.txt
    git -C "$repo" commit -q -m base
}

# --- AC1: capture/restore -------------------------------------------------

@test "publish_artifact capture writes manifest with source_sha/source_tree/patch_sha/base/paths" {
    local repo="$BATS_TEST_TMPDIR/repo1"
    setup_fixture_repo "$repo"
    local base
    base="$(git -C "$repo" rev-parse HEAD)"
    printf 'A\nB\n' > "$repo/a.txt"
    printf 'new\n' > "$repo/b.txt"
    git -C "$repo" add a.txt b.txt
    git -C "$repo" commit -q -m change
    local sha
    sha="$(git -C "$repo" rev-parse HEAD)"
    local expected_tree
    expected_tree="$(git -C "$repo" rev-parse "${sha}^{tree}")"

    run bash "$PUBLISH_ARTIFACT" capture task_manifest "$repo" "$base" "$sha"
    [ "$status" -eq 0 ]

    local manifest="$SHOGUN_STATE_DIR/publish_queue/artifacts/task_manifest/manifest.yaml"
    [ -f "$manifest" ]
    [ -f "$SHOGUN_STATE_DIR/publish_queue/artifacts/task_manifest/patch.diff" ]
    run python3 -c "
import yaml, sys
d = yaml.safe_load(open(sys.argv[1])) or {}
assert d.get('source_sha') == sys.argv[2], d
assert d.get('source_tree') == sys.argv[3], d
assert d.get('base') == sys.argv[4], d
assert sorted(d.get('paths') or []) == ['a.txt', 'b.txt'], d
print('OK')
" "$manifest" "$sha" "$expected_tree" "$base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "publish_artifact capture then restore reproduces tree id after worktree removal" {
    local repo="$BATS_TEST_TMPDIR/repo2"
    setup_fixture_repo "$repo"
    local base
    base="$(git -C "$repo" rev-parse HEAD)"
    printf 'A\nB\n' > "$repo/a.txt"
    printf 'new\n' > "$repo/b.txt"
    git -C "$repo" add a.txt b.txt
    git -C "$repo" commit -q -m change
    local sha
    sha="$(git -C "$repo" rev-parse HEAD)"
    local expected_tree
    expected_tree="$(git -C "$repo" rev-parse "${sha}^{tree}")"

    run bash "$PUBLISH_ARTIFACT" capture task_roundtrip "$repo" "$base" "$sha"
    [ "$status" -eq 0 ]

    # A separate tree checked out at base, independent of $repo.
    local dest="$BATS_TEST_TMPDIR/dest2"
    git clone -q "$repo" "$dest"
    git -C "$dest" checkout -q "$base"

    # The original worktree is gone: restore must not depend on it.
    rm -rf "$repo"

    run --separate-stderr bash "$PUBLISH_ARTIFACT" restore task_roundtrip "$dest"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected_tree" ]
}

@test "publish_artifact capture handles file deletion (restore reproduces removal)" {
    local repo="$BATS_TEST_TMPDIR/repo3"
    setup_fixture_repo "$repo"
    local base
    base="$(git -C "$repo" rev-parse HEAD)"
    rm "$repo/keep.txt"
    printf 'A2\n' > "$repo/a.txt"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m remove
    local sha
    sha="$(git -C "$repo" rev-parse HEAD)"
    local expected_tree
    expected_tree="$(git -C "$repo" rev-parse "${sha}^{tree}")"

    run bash "$PUBLISH_ARTIFACT" capture task_delete "$repo" "$base" "$sha"
    [ "$status" -eq 0 ]

    local dest="$BATS_TEST_TMPDIR/dest3"
    git clone -q "$repo" "$dest"
    git -C "$dest" checkout -q "$base"
    rm -rf "$repo"

    run --separate-stderr bash "$PUBLISH_ARTIFACT" restore task_delete "$dest"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected_tree" ]
    [ ! -e "$dest/keep.txt" ]
}

@test "publish_artifact capture SKIPs (rc=3) and writes nothing when base==source_sha (empty diff)" {
    local repo="$BATS_TEST_TMPDIR/repo4"
    setup_fixture_repo "$repo"
    local head
    head="$(git -C "$repo" rev-parse HEAD)"

    run bash "$PUBLISH_ARTIFACT" capture task_empty "$repo" "$head" "$head"
    [ "$status" -eq 3 ]
    [ ! -e "$SHOGUN_STATE_DIR/publish_queue/artifacts/task_empty" ]
}

@test "publish_artifact restore FAILs (rc=1) when manifest source_tree does not match applied patch" {
    local repo="$BATS_TEST_TMPDIR/repo5"
    setup_fixture_repo "$repo"
    local base
    base="$(git -C "$repo" rev-parse HEAD)"
    printf 'A\nB\n' > "$repo/a.txt"
    git -C "$repo" add a.txt
    git -C "$repo" commit -q -m change
    local sha
    sha="$(git -C "$repo" rev-parse HEAD)"

    run bash "$PUBLISH_ARTIFACT" capture task_corrupt "$repo" "$base" "$sha"
    [ "$status" -eq 0 ]

    # Corrupt the manifest's source_tree so it can never match the applied patch.
    local manifest="$SHOGUN_STATE_DIR/publish_queue/artifacts/task_corrupt/manifest.yaml"
    sed -i "s/^source_tree: .*/source_tree: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'/" "$manifest"

    local dest="$BATS_TEST_TMPDIR/dest5"
    git clone -q "$repo" "$dest"
    git -C "$dest" checkout -q "$base"

    run --separate-stderr bash "$PUBLISH_ARTIFACT" restore task_corrupt "$dest"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"tree mismatch"* ]]
}

# test_necessity: C6 artifact integrity must reject a patch whose content adds
# a path that is absent from the captured manifest/source tree.
@test "publish_artifact restore FAILs when captured patch is tampered with an undeclared path" {
    local repo="$BATS_TEST_TMPDIR/repo6"
    setup_fixture_repo "$repo"
    local base
    base="$(git -C "$repo" rev-parse HEAD)"
    printf 'A\nB\n' > "$repo/a.txt"
    git -C "$repo" add a.txt
    git -C "$repo" commit -q -m change
    local sha
    sha="$(git -C "$repo" rev-parse HEAD)"

    run bash "$PUBLISH_ARTIFACT" capture task_patch_tampered "$repo" "$base" "$sha"
    [ "$status" -eq 0 ]

    # Replace the captured patch with a valid patch that adds an unlisted path.
    printf 'INJECTED\n' > "$repo/extra.txt"
    git -C "$repo" add extra.txt
    git -C "$repo" commit -q -m attacker
    local attacker_sha
    attacker_sha="$(git -C "$repo" rev-parse HEAD)"
    local patch="$SHOGUN_STATE_DIR/publish_queue/artifacts/task_patch_tampered/patch.diff"
    git -C "$repo" diff "$base" "$attacker_sha" -- a.txt extra.txt > "$patch"

    local dest="$BATS_TEST_TMPDIR/dest6"
    git clone -q "$repo" "$dest"
    git -C "$dest" checkout -q "$base"

    run --separate-stderr bash "$PUBLISH_ARTIFACT" restore task_patch_tampered "$dest"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"tree mismatch"* ]]
}

# test_necessity: C6 artifact integrity must reject a manifest that declares a
# path absent from the patch, before restore can mutate the destination tree.
@test "publish_artifact restore FAILs when manifest declares a path absent from patch" {
    local repo="$BATS_TEST_TMPDIR/repo7"
    setup_fixture_repo "$repo"
    local base
    base="$(git -C "$repo" rev-parse HEAD)"
    printf 'A\nB\n' > "$repo/a.txt"
    git -C "$repo" add a.txt
    git -C "$repo" commit -q -m change
    local sha
    sha="$(git -C "$repo" rev-parse HEAD)"

    run bash "$PUBLISH_ARTIFACT" capture task_manifest_overreport "$repo" "$base" "$sha"
    [ "$status" -eq 0 ]

    # Add a declared path that is not present in patch.diff.
    local manifest="$SHOGUN_STATE_DIR/publish_queue/artifacts/task_manifest_overreport/manifest.yaml"
    printf '%s\n' '- ghost.txt' >> "$manifest"

    local dest="$BATS_TEST_TMPDIR/dest7"
    git clone -q "$repo" "$dest"
    git -C "$dest" checkout -q "$base"

    run --separate-stderr bash "$PUBLISH_ARTIFACT" restore task_manifest_overreport "$dest"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"tree mismatch"* ]]
    [ "$(cat "$dest/a.txt")" = "A" ]
    [ ! -e "$dest/ghost.txt" ]
}

# --- AC2: gate_report_format.sh manifest consistency check ---------------

mk_manifest() {
    local task_id="$1" sha="$2" base="$3"
    shift 3
    local dir="$SHOGUN_STATE_DIR/publish_queue/artifacts/$task_id"
    mkdir -p "$dir"
    {
        echo "source_sha: $sha"
        echo "source_tree: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        echo "patch_sha: cafef00dcafef00dcafef00dcafef00dcafef00"
        echo "base: $base"
        echo "paths:"
        local p
        for p in "$@"; do
            echo "- $p"
        done
    } > "$dir/manifest.yaml"
}

mk_report() {
    local path="$1" task_id="$2" sha="$3"
    shift 3
    {
        echo "task_id: $task_id"
        echo "commit_hash: $sha"
        echo "files_modified:"
        local p
        for p in "$@"; do
            echo "- path: $p"
            echo "  change: test"
        done
    } > "$path"
}

@test "gate_report_format --manifest-check PASSes when report and manifest fully match" {
    mk_manifest match_ok aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa base1 a.txt b.txt
    local report="$BATS_TEST_TMPDIR/report_match.yaml"
    mk_report "$report" match_ok aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa a.txt b.txt

    run bash "$GATE" --manifest-check "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS(manifest_consistency)"* ]]
}

@test "gate_report_format --manifest-check FAILs on source_sha mismatch" {
    mk_manifest sha_bad aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa base1 a.txt
    local report="$BATS_TEST_TMPDIR/report_sha.yaml"
    mk_report "$report" sha_bad bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb a.txt

    run bash "$GATE" --manifest-check "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"source_sha mismatch"* ]]
}

@test "gate_report_format --manifest-check FAILs on paths mismatch" {
    mk_manifest paths_bad aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa base1 a.txt b.txt
    local report="$BATS_TEST_TMPDIR/report_paths.yaml"
    mk_report "$report" paths_bad aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa a.txt c.txt

    run bash "$GATE" --manifest-check "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"paths mismatch"* ]]
}

@test "gate_report_format --manifest-check is a no-op PASS when no manifest exists for task_id" {
    local report="$BATS_TEST_TMPDIR/report_nomanifest.yaml"
    mk_report "$report" no_manifest_here aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa a.txt

    run bash "$GATE" --manifest-check "$report"
    [ "$status" -eq 0 ]
}

@test "gate_report_format normal invocation is byte-identical to pre-change behavior when no manifest exists" {
    # Regression guard: the manifest-check hook must not alter exit code or
    # output for any report when publish_queue/artifacts has no entry for its
    # task_id (the common case until U1+U2 are fully wired). Compare against
    # the pre-edit (committed HEAD) revision of this exact script. The
    # baseline copy must live alongside its gate_report_format_main.py /
    # gate_report_format_combined.py siblings (the script locates them via
    # its own BASH_SOURCE directory), so it is staged in scripts/gates/
    # itself under a private name and removed in teardown().
    local old_gate="$REPO_ROOT/scripts/gates/.test_publish_artifact_baseline_gate_report_format.sh"
    run bash -c "git -C '$REPO_ROOT' show HEAD:scripts/gates/gate_report_format.sh > '$old_gate'"
    [ "$status" -eq 0 ]
    [ -s "$old_gate" ]

    # A report missing entirely, and one with a minimal task_id: both must
    # behave identically old vs new since no manifest exists for either.
    local missing_report="$BATS_TEST_TMPDIR/does_not_exist.yaml"
    local minimal_report="$BATS_TEST_TMPDIR/minimal_report.yaml"
    printf 'task_id: some_unrelated_task\n' > "$minimal_report"

    local r
    for r in "$missing_report" "$minimal_report"; do
        run bash "$old_gate" "$r"
        local old_status="$status" old_output="$output"
        run bash "$GATE" "$r"
        [ "$status" -eq "$old_status" ]
        [ "$output" = "$old_output" ]
    done
}

teardown() {
    rm -f "$REPO_ROOT/scripts/gates/.test_publish_artifact_baseline_gate_report_format.sh"
}

# --- integration wiring: inbox_write.sh report_received capture call -----

@test "inbox_write.sh report_received path calls publish_artifact.sh capture (best-effort, non-blocking)" {
    local iw="$REPO_ROOT/scripts/inbox_write.sh"
    [ -f "$iw" ]
    run grep -n 'TYPE" = "report_received".*publish_artifact.sh" capture' "$iw"
    [ "$status" -eq 0 ]
    # Must be best-effort: a failing capture must never abort inbox_write.sh (set -e is active there).
    run grep -n 'publish_artifact.sh" capture .*|| true' "$iw"
    [ "$status" -eq 0 ]
}

# --- base refresh (2026-09-03 karo hotfix dded45428) ---------------------
# test_necessity: capture の manifest.base は deploy 時の base ではなく、source が
# origin/main を merge 済みなら merge-base(origin/main, source_sha) に置換される。
# 置換されないと publisher C2a が base 以降に origin で動いた path を全て RC し、
# merge 済み task が永久に publish できない(cmd_4465 で 3 回実証)。未 merge の source は
# deploy base のままでなければならない(base を進めると差分が欠落する)。

setup_origin_pair() {
    local origin="$1" work="$2"
    git init -q --bare "$origin"
    git init -q "$work"
    git -C "$work" config user.email test@example.invalid
    git -C "$work" config user.name fixture
    printf 'A\n' > "$work/a.txt"; printf 'S\n' > "$work/shared.txt"
    git -C "$work" add a.txt shared.txt
    git -C "$work" commit -q -m base
    git -C "$work" branch -M main
    git -C "$work" remote add origin "$origin"
    git -C "$work" push -q origin main
}

@test "capture replaces manifest.base with merge-base when source merged origin/main" {
    local origin="$BATS_TEST_TMPDIR/origin.git" work="$BATS_TEST_TMPDIR/work" other="$BATS_TEST_TMPDIR/other"
    setup_origin_pair "$origin" "$work"
    local deploy_base; deploy_base="$(git -C "$work" rev-parse HEAD)"
    # origin advances on shared.txt after deploy
    git clone -q "$origin" "$other"; git -C "$other" config user.email o@example.invalid; git -C "$other" config user.name other
    printf 'S2\n' > "$other/shared.txt"; git -C "$other" commit -q -am remote-change; git -C "$other" push -q origin main
    local remote_tip; remote_tip="$(git -C "$other" rev-parse HEAD)"
    # ninja edits a.txt, then merges origin/main
    printf 'A2\n' > "$work/a.txt"; git -C "$work" commit -q -am ninja-change
    git -C "$work" fetch -q origin; git -C "$work" merge -q --no-edit origin/main
    local sha; sha="$(git -C "$work" rev-parse HEAD)"

    run bash "$PUBLISH_ARTIFACT" capture task_merged "$work" "$deploy_base" "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" == *"base refreshed"* ]]
    run python3 -c "
import yaml, sys
d = yaml.safe_load(open(sys.argv[1])) or {}
assert d.get('base') == sys.argv[2], d
assert sorted(d.get('paths') or []) == ['a.txt'], d
print('OK')
" "$SHOGUN_STATE_DIR/publish_queue/artifacts/task_merged/manifest.yaml" "$remote_tip"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "capture keeps deploy base when source did not merge origin/main" {
    local origin="$BATS_TEST_TMPDIR/origin.git" work="$BATS_TEST_TMPDIR/work" other="$BATS_TEST_TMPDIR/other"
    setup_origin_pair "$origin" "$work"
    local deploy_base; deploy_base="$(git -C "$work" rev-parse HEAD)"
    git clone -q "$origin" "$other"; git -C "$other" config user.email o@example.invalid; git -C "$other" config user.name other
    printf 'S2\n' > "$other/shared.txt"; git -C "$other" commit -q -am remote-change; git -C "$other" push -q origin main
    printf 'A2\n' > "$work/a.txt"; git -C "$work" commit -q -am ninja-change
    git -C "$work" fetch -q origin
    local sha; sha="$(git -C "$work" rev-parse HEAD)"

    run bash "$PUBLISH_ARTIFACT" capture task_unmerged "$work" "$deploy_base" "$sha"
    [ "$status" -eq 0 ]
    [[ "$output" != *"base refreshed"* ]]
    run python3 -c "
import yaml, sys
d = yaml.safe_load(open(sys.argv[1])) or {}
assert d.get('base') == sys.argv[2], d
assert sorted(d.get('paths') or []) == ['a.txt'], d
print('OK')
" "$SHOGUN_STATE_DIR/publish_queue/artifacts/task_unmerged/manifest.yaml" "$deploy_base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
