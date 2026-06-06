#!/usr/bin/env bats
# test_sg_pre24_generated_penetration.bats
# SG-PRE24: instructions変更時のgenerated/貫通チェック (GP-265)
# 最小fixture: git repo + instructions正本 + generated/ を模擬

setup() {
    TEST_TMPDIR="$BATS_TEST_TMPDIR/pre24_$$"
    mkdir -p "$TEST_TMPDIR"
    # Create a minimal git repo
    cd "$TEST_TMPDIR"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    # Create instructions and generated directories
    mkdir -p instructions/generated
    # Create a source file and generated file
    echo "# gunshi instructions v1" > instructions/gunshi.md
    echo "# generated gunshi v1" > instructions/generated/codex-gunshi.md
    git add -A
    GIT_COMMITTER_DATE="2026-06-06T10:00:00+09:00" GIT_AUTHOR_DATE="2026-06-06T10:00:00+09:00" \
        git commit -q -m "initial"
}

teardown() {
    rm -rf "$TEST_TMPDIR" 2>/dev/null || true
}

# Helper: extract and run SG-PRE24 section in isolation
run_pre24() {
    local repo_root="$TEST_TMPDIR"
    local files_modified="${1:-}"
    cd "$repo_root"
    # Set required variables
    export REPO_ROOT="$repo_root"
    export FILES_MODIFIED="$files_modified"
    export ERRORS=0
    export GATE_PREDICTION="CLEAR"
    export GATE_PREDICTION_REASON=""
    # Extract and run SG-PRE24 section
    local script="$BATS_TEST_TMPDIR/pre24_runner.sh"
    cat > "$script" <<'RUNNER'
#!/usr/bin/env bash
set +e
REPO_ROOT="${REPO_ROOT}"
FILES_MODIFIED="${FILES_MODIFIED}"
ERRORS=${ERRORS:-0}
GATE_PREDICTION="${GATE_PREDICTION:-CLEAR}"
GATE_PREDICTION_REASON="${GATE_PREDICTION_REASON:-}"
RUNNER
    # Append the SG-PRE24 section from the actual script
    sed -n '/^# ─── SG-PRE24/,/^# ─── GATE_PREDICTION/{ /^# ─── GATE_PREDICTION/d; p; }' \
        "$PROJECT_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" >> "$script"
    # Append output of results
    cat >> "$script" <<'FOOTER'
echo "ERRORS=$ERRORS"
echo "GATE_PREDICTION=$GATE_PREDICTION"
FOOTER
    bash "$script"
}

@test "PRE24: no instructions change → SKIP" {
    run run_pre24 "scripts/some_script.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
    [[ "$output" == *"ERRORS=0"* ]]
}

@test "PRE24: instructions change with matching generated → PASS" {
    cd "$TEST_TMPDIR"
    # Both in same commit = same hash → PASS
    run run_pre24 "instructions/gunshi.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"ERRORS=0"* ]]
}

@test "PRE24: instructions change without generated file → BLOCK" {
    cd "$TEST_TMPDIR"
    # Create a new instructions file with no generated counterpart
    echo "# karo instructions" > instructions/karo.md
    git add -A && git commit -q -m "add karo"
    run run_pre24 "instructions/karo.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"対応ファイルなし"* ]]
    [[ "$output" == *"ERRORS=1"* ]]
    [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
}

@test "PRE24: instructions newer than generated → BLOCK with marker check" {
    cd "$TEST_TMPDIR"
    # Update source but not generated, with explicit later timestamp
    echo "# gunshi instructions v2 with unique_marker_xyz" > instructions/gunshi.md
    git add -A
    GIT_COMMITTER_DATE="2026-06-06T20:00:00+09:00" GIT_AUTHOR_DATE="2026-06-06T20:00:00+09:00" \
        git commit -q -m "update gunshi source"
    # generated is stale (still v1, initial commit is earlier)
    run run_pre24 "instructions/gunshi.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"ERRORS=1"* ]]
    [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
}

@test "PRE24: instructions updated and generated also updated → PASS" {
    cd "$TEST_TMPDIR"
    # Update both source and generated
    echo "# gunshi instructions v2 with penetrated_marker" > instructions/gunshi.md
    echo "# generated gunshi v2 with penetrated_marker" > instructions/generated/codex-gunshi.md
    git add -A && git commit -q -m "update both"
    run run_pre24 "instructions/gunshi.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"ERRORS=0"* ]]
}

export PROJECT_ROOT="${PROJECT_ROOT:-/mnt/c/tools/multi-agent-shogun}"
