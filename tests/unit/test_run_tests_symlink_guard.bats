#!/usr/bin/env bats

setup() {
    ROOT="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$ROOT/scripts" "$ROOT/tests/fixtures"
    cp "$BATS_TEST_DIRNAME/../../scripts/run_tests.sh" "$ROOT/scripts/run_tests.sh"
    git -C "$ROOT" init -q
    git -C "$ROOT" config user.email test@example.com
    git -C "$ROOT" config user.name test
    printf 'original\n' > "$ROOT/scripts/tracked.sh"
    git -C "$ROOT" add scripts/tracked.sh
    git -C "$ROOT" commit -qm fixture
    REPO_ROOT="$ROOT"
    source "$ROOT/scripts/run_tests.sh"
}

@test "write-through fixture symlink to tracked source is blocked before mutation" {
    ln -s ../../scripts/tracked.sh "$ROOT/tests/fixtures/write-target"
    run guard_fixture_symlink_write_through
    [ "$status" -eq 2 ]
    [[ "$output" == *"resolves to tracked source"* ]]
    [ "$(<"$ROOT/scripts/tracked.sh")" = original ]
}

@test "safe fixture copy is allowed" {
    cp "$ROOT/scripts/tracked.sh" "$ROOT/tests/fixtures/write-target"
    run guard_fixture_symlink_write_through
    [ "$status" -eq 0 ]
}

@test "tracked read-only symlink contract is allowed" {
    ln -s ../../scripts/tracked.sh "$ROOT/tests/fixtures/read-only"
    git -C "$ROOT" add tests/fixtures/read-only
    run guard_fixture_symlink_write_through
    [ "$status" -eq 0 ]
}

@test "broken fixture symlink is allowed because it cannot write through" {
    ln -s ../../scripts/missing.sh "$ROOT/tests/fixtures/broken"
    run guard_fixture_symlink_write_through
    [ "$status" -eq 0 ]
}
