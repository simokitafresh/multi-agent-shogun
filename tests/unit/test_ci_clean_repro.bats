#!/usr/bin/env bats
# test_necessity: clean-CI isolation and receipt boundaries are a public safety contract.

setup() {
    HARNESS="$BATS_TEST_DIRNAME/../../scripts/ci_clean_repro.sh"
    OUT="$BATS_TEST_TMPDIR/out"
    mkdir -p "$OUT"
}

@test "clean run gets fresh HOME minimal env and two receipts" {
    receipt="$OUT/good.json"
    run bash "$HARNESS" --receipt "$receipt" -- bash -c '
      test "$CI" = true && test "$CLEAN_CI" = 1 && test -d "$HOME" && test -d "$TMPDIR"
      test "$(env | cut -d= -f1 | sort | tr "\n" " ")" = "CI CLEAN_CI HOME LANG LC_ALL PATH PWD SHLVL SHOGUN_REPO_ROOT TMPDIR _ "
    '
    [ "$status" -eq 0 ]
    run bash "$BATS_TEST_DIRNAME/../../scripts/run_with_receipt.sh" --verify-receipt "$receipt"
    [ "$status" -eq 0 ]
    run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["parent_home_unchanged"] and d["clean_home_created"] and d["external_repo_env_absent"] and not d["production_env_exposed"]' "${receipt%.json}.clean.json"
    [ "$status" -eq 0 ]
}

@test "parent HOME expectation is rejected" {
    receipt="$OUT/parent.json"
    run env EXPECTED_HOME="$HOME" bash "$HARNESS" --receipt "$receipt" -- bash -c 'test "$HOME" = "$EXPECTED_HOME"'
    [ "$status" -ne 0 ]
}

@test "external repository dependency is absent" {
    receipt="$OUT/external.json"
    run env EXTERNAL_REPO=/secret/repo bash "$HARNESS" --receipt "$receipt" -- bash -c 'test -n "$EXTERNAL_REPO"'
    [ "$status" -ne 0 ]
}

@test "undefined environment dependency is absent" {
    receipt="$OUT/env.json"
    run env REQUIRED_LOCAL_TOKEN=secret bash "$HARNESS" --receipt "$receipt" -- bash -c 'test -n "$REQUIRED_LOCAL_TOKEN"'
    [ "$status" -ne 0 ]
}

@test "production connection environment is absent" {
    receipt="$OUT/prod.json"
    run env DATABASE_URL=postgres://production bash "$HARNESS" --receipt "$receipt" -- bash -c 'test -n "$DATABASE_URL"'
    [ "$status" -ne 0 ]
}
