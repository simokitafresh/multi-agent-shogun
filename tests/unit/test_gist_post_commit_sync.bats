#!/usr/bin/env bats
# Contract tests for the commit-blob-only, fail-open gist post-commit trigger.

setup() {
    export TEST_ROOT TRACE
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/gist-post-commit.XXXXXX")"
    TRACE="$TEST_ROOT/trace"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/docs/research"
    cp "$BATS_TEST_DIRNAME/../../scripts/gist_post_commit_sync.sh" "$TEST_ROOT/scripts/"
    cat > "$TEST_ROOT/scripts/gist_verified_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TRACE"
case "${FAKE_MODE:-ok}" in fail) exit 42;; slow) sleep 5;; esac
EOF
    chmod +x "$TEST_ROOT/scripts/gist_verified_write.sh"
    git -C "$TEST_ROOT" init -q
    git -C "$TEST_ROOT" config user.email test@example.com
    git -C "$TEST_ROOT" config user.name tester
    : > "$TRACE"
}

teardown() { [ ! -d "${TEST_ROOT:-}" ] || rm -rf "$TEST_ROOT"; }
commit_all() { git -C "$TEST_ROOT" add -A; git -C "$TEST_ROOT" commit -qm "$1"; git -C "$TEST_ROOT" rev-parse HEAD; }

# test_necessity: A commit with no gist-master document invokes the verifier zero times.
@test "zero targets and empty diff produce zero verifier calls" {
    printf 'plain\n' > "$TEST_ROOT/docs/research/plain.md"
    head="$(commit_all plain)"
    run env TRACE="$TRACE" bash -c "cd '$TEST_ROOT' && bash scripts/gist_post_commit_sync.sh '$head'"
    [ "$status" -eq 0 ]; [ ! -s "$TRACE" ]
    : > "$TRACE"
    run env TRACE="$TRACE" bash -c "cd '$TEST_ROOT' && bash scripts/gist_post_commit_sync.sh '$head'"
    [ "$status" -eq 0 ]; [ ! -s "$TRACE" ]
}

# test_necessity: The first commit and a later single target pass the exact full commit identity, never working-tree content.
@test "initial and single target pass exact committed path and full SHA" {
    printf '<!-- gist-master: a1 first.md -->\ncommitted\n' > "$TEST_ROOT/docs/research/first.md"
    head="$(commit_all initial)"
    printf 'DIRTY\n' >> "$TEST_ROOT/docs/research/first.md"
    run env TRACE="$TRACE" bash -c "cd '$TEST_ROOT' && bash scripts/gist_post_commit_sync.sh '$head'"
    [ "$status" -eq 0 ]
    [ "$(cat "$TRACE")" = "--master docs/research/first.md --commit $head" ]
}

# test_necessity: Multiple targets, rename destinations, and deletions map exactly to surviving committed masters.
@test "multiple rename and delete select only surviving destination masters" {
    printf '<!-- gist-master: a1 a.md -->\na\n' > "$TEST_ROOT/docs/research/a.md"
    printf '<!-- gist-master: b2 b.md -->\nb\n' > "$TEST_ROOT/docs/research/b.md"
    commit_all base >/dev/null
    git -C "$TEST_ROOT" mv docs/research/a.md docs/research/renamed.md
    rm "$TEST_ROOT/docs/research/b.md"
    printf '<!-- gist-master: c3 c.md -->\nc\n' > "$TEST_ROOT/docs/research/c.md"
    head="$(commit_all change)"
    run env TRACE="$TRACE" bash -c "cd '$TEST_ROOT' && bash scripts/gist_post_commit_sync.sh '$head'"
    [ "$status" -eq 0 ]; [ "$(wc -l < "$TRACE")" -eq 2 ]
    grep -q -- "--master docs/research/renamed.md --commit $head" "$TRACE"
    grep -q -- "--master docs/research/c.md --commit $head" "$TRACE"
    ! grep -q 'b.md' "$TRACE"
}

# test_necessity: Verifier failure and timeout warn but cannot reject the already-created local commit.
@test "failure and total timeout are bounded fail-open" {
    printf '<!-- gist-master: a1 a.md -->\na\n' > "$TEST_ROOT/docs/research/a.md"
    head="$(commit_all target)"
    run env TRACE="$TRACE" FAKE_MODE=fail bash -c "cd '$TEST_ROOT' && bash scripts/gist_post_commit_sync.sh '$head'"
    [ "$status" -eq 0 ]; [[ "$output" == *WARN* ]]
    : > "$TRACE"; started="$SECONDS"
    run env TRACE="$TRACE" FAKE_MODE=slow GIST_POST_COMMIT_TIMEOUT_SECONDS=1 bash -c "cd '$TEST_ROOT' && bash scripts/gist_post_commit_sync.sh '$head'"
    [ "$status" -eq 0 ]; [ "$((SECONDS - started))" -lt 4 ]; [[ "$output" == *WARN* ]]
}

# test_necessity: Concurrent and older invocations preserve each full SHA so verifier flock/latestness can arbitrate without identity loss.
@test "parallel and old-after-new invocations preserve commit identities" {
    printf '<!-- gist-master: a1 a.md -->\none\n' > "$TEST_ROOT/docs/research/a.md"
    old="$(commit_all old)"
    printf '<!-- gist-master: a1 a.md -->\ntwo\n' > "$TEST_ROOT/docs/research/a.md"
    new="$(commit_all new)"
    run env TRACE="$TRACE" bash -c "cd '$TEST_ROOT'; bash scripts/gist_post_commit_sync.sh '$new' & bash scripts/gist_post_commit_sync.sh '$old' & wait"
    [ "$status" -eq 0 ]; [ "$(wc -l < "$TRACE")" -eq 2 ]
    grep -q -- "--commit $old" "$TRACE"; grep -q -- "--commit $new" "$TRACE"
}
