#!/usr/bin/env bats
# test_pre_push_hook.bats — .githooks/pre-push ユニットテスト

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_HOOK="$PROJECT_ROOT/.githooks/pre-push"
    [ -f "$SOURCE_HOOK" ] || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/pre_push_hook.XXXXXX")"
    mkdir -p "$TEST_ROOT/.githooks" "$TEST_ROOT/tests/unit" "$TEST_ROOT/mock_bin" "$TEST_ROOT/scripts"

    cp "$SOURCE_HOOK" "$TEST_ROOT/.githooks/pre-push"
    chmod +x "$TEST_ROOT/.githooks/pre-push"
    git -C "$TEST_ROOT" init -q
    git -C "$TEST_ROOT" config user.email test@example.invalid
    git -C "$TEST_ROOT" config user.name "Pre-push Test"
    git -C "$TEST_ROOT" add .githooks/pre-push
    git -C "$TEST_ROOT" commit -qm fixture

    cat > "$TEST_ROOT/mock_bin/timeout" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$TEST_ROOT/timeout_calls.log"
shift
"$@"
MOCK
    chmod +x "$TEST_ROOT/mock_bin/timeout"

    cat > "$TEST_ROOT/scripts/run_tests.sh" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$TEST_ROOT/run_tests_calls.log"
if [ "${MOCK_BATS_FAIL:-0}" = "1" ]; then
    echo "not ok 1 failing test name"
    exit 1
fi
echo "PASS: isolated runner"
MOCK
    chmod +x "$TEST_ROOT/scripts/run_tests.sh"

    cat > "$TEST_ROOT/run_hook.sh" <<'MOCK'
#!/usr/bin/env bash
cd "$(dirname "$0")"
bash ".githooks/pre-push"
MOCK
    chmod +x "$TEST_ROOT/run_hook.sh"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

run_hook() {
    local extra_args="${1:-}"
    local mock_fail="${2:-0}"

    run env TEST_ROOT="$TEST_ROOT" MOCK_BATS_FAIL="$mock_fail" PATH="$TEST_ROOT/mock_bin:$PATH" \
        bash -lc 'cd "$TEST_ROOT" && bash "$TEST_ROOT/.githooks/pre-push"' dummy $extra_args
}

@test "pre-push runs the file-isolated unit runner with timeout 900 and inner jobs 1" {
    run_hook
    [ "$status" -eq 0 ]
    grep -q '^900 env BATS_CACHE=0 BATS_INNER_JOBS=1 bash .*/scripts/run_tests.sh unit$' "$TEST_ROOT/timeout_calls.log"
    grep -q '^unit$' "$TEST_ROOT/run_tests_calls.log"
    [[ "$output" == *"Running unit tests before push..."* ]]
}

@test "pre-push never bypasses run_tests with a direct parallel bats invocation" {
    ! grep -Eq 'timeout [0-9]+ bats |bats tests/unit/ .*--jobs' "$SOURCE_HOOK"
    grep -q 'run_tests.sh" affected' "$SOURCE_HOOK"
    grep -q 'run_tests.sh" unit' "$SOURCE_HOOK"
}

@test "pre-push blocks push when bats fails and keeps failing test output" {
    run_hook "" 1
    [ "$status" -eq 1 ]
    [[ "$output" == *"not ok 1 failing test name"* ]]
    [[ "$output" == *"BLOCKED: unit tests failed. Push aborted."* ]]
}

@test "pre-push still blocks bare force pushes" {
    run env TEST_ROOT="$TEST_ROOT" PATH="$TEST_ROOT/mock_bin:$PATH" \
        "$TEST_ROOT/run_hook.sh" --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"git push --force is forbidden"* ]]
}

@test "pre-push allows force-with-lease after unit tests pass" {
    run env TEST_ROOT="$TEST_ROOT" PATH="$TEST_ROOT/mock_bin:$PATH" \
        "$TEST_ROOT/run_hook.sh" --force-with-lease
    [ "$status" -eq 0 ]
}

@test "concurrent pre-push for the same HEAD runs the full suite once and reuses PASS" {
    cat > "$TEST_ROOT/scripts/run_tests.sh" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$TEST_ROOT/run_tests_calls.log"
if [ "$1" = "unit" ]; then sleep 1; fi
echo "PASS: isolated runner"
MOCK
    chmod +x "$TEST_ROOT/scripts/run_tests.sh"

    env TEST_ROOT="$TEST_ROOT" PATH="$TEST_ROOT/mock_bin:$PATH" \
        bash -lc 'cd "$TEST_ROOT" && bash .githooks/pre-push' >"$TEST_ROOT/first.out" 2>&1 &
    first_pid=$!
    sleep 0.1
    run env TEST_ROOT="$TEST_ROOT" PATH="$TEST_ROOT/mock_bin:$PATH" \
        bash -lc 'cd "$TEST_ROOT" && bash .githooks/pre-push'
    wait "$first_pid"

    [ "$status" -eq 0 ]
    [ "$(grep -c '^unit$' "$TEST_ROOT/run_tests_calls.log")" -eq 1 ]
    [[ "$output" == *"Reusing serialized PASS"* ]]
}
