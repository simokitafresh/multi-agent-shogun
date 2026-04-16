#!/usr/bin/env bats
# test_stop_lint_gate.bats - unit tests for .claude/hooks/stop-lint-gate.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_HOOK="$PROJECT_ROOT/.claude/hooks/stop-lint-gate.sh"
    [ -f "$SOURCE_HOOK" ] || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/stop_lint_gate.XXXXXX")"
    mkdir -p "$TEST_ROOT/.claude/hooks" "$TEST_ROOT/mock_bin" "$TEST_ROOT/scripts"

    cp "$SOURCE_HOOK" "$TEST_ROOT/.claude/hooks/stop-lint-gate.sh"
    chmod +x "$TEST_ROOT/.claude/hooks/stop-lint-gate.sh"

    cat > "$TEST_ROOT/mock_bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "${MOCK_AGENT_ID:-hayate}"
EOF
    chmod +x "$TEST_ROOT/mock_bin/tmux"

    cat > "$TEST_ROOT/mock_bin/shellcheck" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${TEST_ROOT}/shellcheck_calls.log"
if [ "${MOCK_SHELLCHECK_MODE:-pass}" = "fail" ]; then
    printf '%s\n' "${1}:1:1: warning: mock shellcheck failure [SC9999]"
    exit 1
fi
EOF
    chmod +x "$TEST_ROOT/mock_bin/shellcheck"

    cat > "$TEST_ROOT/mock_bin/ruff" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${TEST_ROOT}/ruff_calls.log"
if [ "${MOCK_RUFF_MODE:-pass}" = "fail" ]; then
    printf '%s\n' "${*: -1}:1:1: F401 mock ruff failure"
    exit 1
fi
EOF
    chmod +x "$TEST_ROOT/mock_bin/ruff"

    cat > "$TEST_ROOT/mock_bin/npx" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${TEST_ROOT}/npx_calls.log"
EOF
    chmod +x "$TEST_ROOT/mock_bin/npx"

    cat > "$TEST_ROOT/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TEST_ROOT}/inbox_write.log"
EOF
    chmod +x "$TEST_ROOT/scripts/inbox_write.sh"

    cat > "$TEST_ROOT/a.sh" <<'EOF'
#!/usr/bin/env bash
echo a
EOF
    cat > "$TEST_ROOT/b.sh" <<'EOF'
#!/usr/bin/env bash
echo b
EOF
    cat > "$TEST_ROOT/c.py" <<'EOF'
print("c")
EOF

    (
        cd "$TEST_ROOT"
        git init -q
        git config user.email test@example.com
        git config user.name "Test User"
        git add .claude/hooks/stop-lint-gate.sh a.sh b.sh c.py scripts/inbox_write.sh
        git commit -qm "init"
    )

    export HASH_FILE="$TEST_ROOT/stop_hook_hayate_lint_fail_hash"
    rm -f "$HASH_FILE"
}

teardown() {
    rm -f "${HASH_FILE:-}"
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

run_hook() {
    run env TEST_ROOT="$TEST_ROOT" MOCK_AGENT_ID="hayate" TMUX_PANE="%1" \
        STOP_LINT_HASH_FILE="$HASH_FILE" PATH="$TEST_ROOT/mock_bin:$PATH" \
        bash -c 'cd "$TEST_ROOT" && bash .claude/hooks/stop-lint-gate.sh'
}

@test "exits cleanly when there are no tracked changes" {
    run_hook
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "batches shellcheck and ruff invocations across changed files" {
    printf '# change\n' >> "$TEST_ROOT/a.sh"
    printf '# change\n' >> "$TEST_ROOT/b.sh"
    printf '\n# change\n' >> "$TEST_ROOT/c.py"

    run_hook
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    [ "$(wc -l < "$TEST_ROOT/shellcheck_calls.log")" -eq 1 ]
    grep -q -- "-S warning a.sh b.sh" "$TEST_ROOT/shellcheck_calls.log"
    [ "$(wc -l < "$TEST_ROOT/ruff_calls.log")" -eq 1 ]
    grep -q -- "check --quiet --select E,W,F c.py" "$TEST_ROOT/ruff_calls.log"
    [ ! -f "$TEST_ROOT/npx_calls.log" ]
}

@test "blocks on a new lint violation and records its hash" {
    printf '# change\n' >> "$TEST_ROOT/a.sh"

    run env TEST_ROOT="$TEST_ROOT" MOCK_AGENT_ID="hayate" TMUX_PANE="%1" \
        MOCK_SHELLCHECK_MODE="fail" STOP_LINT_HASH_FILE="$HASH_FILE" PATH="$TEST_ROOT/mock_bin:$PATH" \
        bash -c 'cd "$TEST_ROOT" && bash .claude/hooks/stop-lint-gate.sh'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" == *'ERROR: Lint violations found in changed files'* ]]
    [ -f "$HASH_FILE" ]
}

@test "repeated identical lint violation escalates to karo" {
    printf '# change\n' >> "$TEST_ROOT/a.sh"

    run env TEST_ROOT="$TEST_ROOT" MOCK_AGENT_ID="hayate" TMUX_PANE="%1" \
        MOCK_SHELLCHECK_MODE="fail" STOP_LINT_HASH_FILE="$HASH_FILE" PATH="$TEST_ROOT/mock_bin:$PATH" \
        bash -c 'cd "$TEST_ROOT" && bash .claude/hooks/stop-lint-gate.sh'
    [ "$status" -eq 0 ]

    run env TEST_ROOT="$TEST_ROOT" MOCK_AGENT_ID="hayate" TMUX_PANE="%1" \
        MOCK_SHELLCHECK_MODE="fail" STOP_LINT_HASH_FILE="$HASH_FILE" PATH="$TEST_ROOT/mock_bin:$PATH" \
        bash -c 'cd "$TEST_ROOT" && bash .claude/hooks/stop-lint-gate.sh'
    [ "$status" -eq 0 ]
    [[ "$output" == *'Same lint violations repeated'* ]]
    [ -f "$TEST_ROOT/inbox_write.log" ]
    grep -q "error_report hayate" "$TEST_ROOT/inbox_write.log"
}
