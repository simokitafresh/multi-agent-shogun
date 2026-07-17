#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export GH_CMD="$BATS_TEST_TMPDIR/fake_gh_gist_index_update.sh"
    cp "$REPO_ROOT/tests/fixtures/fake_gh_gist_index_update.sh" "$GH_CMD"
    chmod 0644 "$GH_CMD"
}

@test "title normalization preserves ASCII lowercase behavior" {
    run bash -c 'source "$1"; title_key "Research REPORT 123"' _ \
        "$REPO_ROOT/scripts/gist_index_update.sh"

    [ "$status" -eq 0 ]
    [ "$output" = "research report 123" ]
}

@test "dry-run renders all 100 fixture gists without editing" {
    run bash "$REPO_ROOT/scripts/gist_index_update.sh" --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"100件中100件を掲載"* ]]
    [[ "$output" == *"[Research Report 100]"* ]]
}
