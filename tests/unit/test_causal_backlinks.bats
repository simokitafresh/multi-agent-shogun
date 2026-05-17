#!/usr/bin/env bats
# test_causal_backlinks.bats — causal_backlinks.sh unit tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/causal_backlinks.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
}

setup() {
    TEST_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/docs" "$TEST_ROOT/projects/infra"
    cp "$SRC_SCRIPT" "$TEST_ROOT/scripts/causal_backlinks.sh"
    chmod +x "$TEST_ROOT/scripts/causal_backlinks.sh"
    cat > "$TEST_ROOT/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: LS001
  origin: '[[cmd_2818]]'
  detail: '因果リンク確認'
EOF
    cat > "$TEST_ROOT/docs/trace.md" <<'EOF'
cmd trace: [[cmd_2818]]
EOF
    cat > "$TEST_ROOT/docs/other.md" <<'EOF'
cmd trace: [[cmd_9999]]
EOF
}

@test "returns files that reference the requested Obsidian link" {
    cd "$TEST_ROOT"
    run bash scripts/causal_backlinks.sh cmd_2818

    [ "$status" -eq 0 ]
    [[ "$output" == *"projects/infra/lessons_shogun.yaml"* ]]
    [[ "$output" == *"docs/trace.md"* ]]
    [[ "$output" != *"docs/other.md"* ]]
}

@test "accepts bracketed IDs" {
    cd "$TEST_ROOT"
    run bash scripts/causal_backlinks.sh "[[cmd_2818]]"

    [ "$status" -eq 0 ]
    [[ "$output" == *"docs/trace.md"* ]]
}
