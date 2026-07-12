#!/usr/bin/env bats
# ac_physical_verify.sh regression tests

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/acpv.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/archive/cmds" "$TEST_TMPDIR/tests/unit"
    cp "$PROJECT_ROOT/scripts/ac_physical_verify.sh" "$TEST_TMPDIR/scripts/ac_physical_verify.sh"
    chmod +x "$TEST_TMPDIR/scripts/ac_physical_verify.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "stdin mode does not reference undefined CMD_TEXT under set -u" {
    run bash "$TEST_TMPDIR/scripts/ac_physical_verify.sh" - <<EOF
AC1 scripts/ac_physical_verify.sh L20
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: ALL PATHS VERIFIED"* ]]
}

@test "cmd_id mode reads archived command and prints related tests" {
    cat > "$TEST_TMPDIR/scripts/context_freshness_check.sh" <<'EOF'
#!/usr/bin/env bash
echo context freshness
EOF
    cat > "$TEST_TMPDIR/tests/unit/test_context_freshness_check.bats" <<'EOF'
#!/usr/bin/env bats
EOF
    # Written via string concatenation, not a literal heredoc line: bats-core's
    # test-plan preprocessor naively regex-scans raw file text for `@test "..." {`
    # with no heredoc-quoting awareness, so a literal fixture line here would be
    # miscounted as a phantom 3rd top-level test in THIS file (plan inflates to
    # "1..3", then "bats: unknown test name" when it tries to run the phantom).
    printf '%s\n' '@'"test \"mentions context_freshness_check\" { true; }" >> "$TEST_TMPDIR/tests/unit/test_context_freshness_check.bats"
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<'EOF'
commands: {}
EOF
    cat > "$TEST_TMPDIR/queue/archive/cmds/cmd_3184_completed_20260605.yaml" <<'EOF'
commands:
  cmd_3184:
    project: infra
    target_path: scripts/context_freshness_check.sh
    command: "AC1 scripts/context_freshness_check.sh L1"
    acceptance_criteria:
      AC1:
        description: "scripts/context_freshness_check.sh exists"
EOF

    run bash "$TEST_TMPDIR/scripts/ac_physical_verify.sh" cmd_3184
    [ "$status" -eq 0 ]
    [[ "$output" == *"scripts/context_freshness_check.sh L1"* ]]
    [[ "$output" == *"関連テスト一覧(target: scripts/context_freshness_check.sh)"* ]]
    [[ "$output" == *"tests/unit/test_context_freshness_check.bats"* ]]
}
