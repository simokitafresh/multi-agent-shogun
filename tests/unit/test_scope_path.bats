#!/usr/bin/env bats
# test_scope_path.bats - unit tests for scripts/lib/scope_path.sh (GA-222 SSOT)
#
# GA-222: ninja_scope_commit.sh and sync_git_hooks.sh each had their own
# ad-hoc scope-path normalization logic. Across four rounds of review, new
# path representations kept slipping through one script while being fixed in
# the other (directory scope, trailing "/.", root scope ".", "subdir/..",
# plain "..", double slashes). This library is now the single source of
# truth both scripts source, so every representation only needs to be
# handled correctly once, here.

setup() {
    # shellcheck source=scripts/lib/scope_path.sh
    source "$BATS_TEST_DIRNAME/../../scripts/lib/scope_path.sh"
}

@test "normalizes a plain relative path unchanged" {
    run scope_path_normalize "scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks/git-pre-commit.sh" ]
}

@test "normalizes a single-segment path unchanged" {
    run scope_path_normalize "own.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "own.txt" ]
}

@test "collapses double slashes" {
    run scope_path_normalize "scripts//hooks"
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks" ]
}

@test "strips a trailing '/.'" {
    run scope_path_normalize "scripts/hooks/."
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks" ]
}

@test "collapses repeated trailing '/./.'" {
    run scope_path_normalize "scripts/hooks/./."
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks" ]
}

@test "strips a leading './'" {
    run scope_path_normalize "./scripts/hooks"
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks" ]
}

@test "collapses an internal '/./'" {
    run scope_path_normalize "scripts/./hooks/git-pre-commit.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "scripts/hooks/git-pre-commit.sh" ]
}

@test "blocks an absolute path" {
    run scope_path_normalize "/etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" == *"absolute"* ]]
}

@test "blocks an empty path" {
    run scope_path_normalize ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty"* ]]
}

@test "blocks root scope '.'" {
    run scope_path_normalize "."
    [ "$status" -eq 1 ]
    [[ "$output" == *"repository root"* ]]
}

@test "blocks a leading '..' traversal" {
    run scope_path_normalize "../etc/passwd"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'..'"* ]]
}

@test "blocks a mid-path '..' traversal (a/../b)" {
    run scope_path_normalize "a/../b"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'..'"* ]]
}

@test "blocks a trailing '..' traversal (subdir/..)" {
    run scope_path_normalize "subdir/.."
    [ "$status" -eq 1 ]
    [[ "$output" == *"'..'"* ]]
}

@test "blocks a bare '..'" {
    run scope_path_normalize ".."
    [ "$status" -eq 1 ]
    [[ "$output" == *"'..'"* ]]
}

@test "is_in_scope: exact match" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 0 ]
}

@test "is_in_scope: file under an in-scope directory" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "scripts/hooks"
    [ "$status" -eq 0 ]
}

@test "is_in_scope: normalizes both target and scope path before comparing (double slash + trailing /.)" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "scripts//hooks/."
    [ "$status" -eq 0 ]
}

@test "is_in_scope: a similarly-prefixed scope path does not match (boundary requires '/')" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "scripts/hook"
    [ "$status" -eq 1 ]
}

@test "is_in_scope: unrelated path is out of scope" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh" "own.txt"
    [ "$status" -eq 1 ]
}

@test "is_in_scope: empty scope list is always out of scope" {
    run scope_path_is_in_scope "scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 1 ]
}
