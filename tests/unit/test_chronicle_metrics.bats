#!/usr/bin/env bats
# test_chronicle_metrics.bats — chronicle_metrics.sh archive aggregation tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/chronicle_metrics.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/chronicle_metrics.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/context" "$TEST_TMPDIR/archive/cmd-chronicle"
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/chronicle_metrics.sh"
    chmod +x "$TEST_TMPDIR/scripts/chronicle_metrics.sh"
    export TEST_SCRIPT="$TEST_TMPDIR/scripts/chronicle_metrics.sh"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "all-time metrics include archived chronicle files" {
    cat > "$TEST_TMPDIR/context/cmd-chronicle.md" <<'MD'
# CMD年代記

## 2026-05

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_2000 | 実装 — active cmd | infra | 05-08 | active result |
MD

    cat > "$TEST_TMPDIR/archive/cmd-chronicle/2026-04.md" <<'MD'
# CMD年代記 Archive: 2026-04

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_1000 | 偵察 — archived cmd | dm-signal | 04-12 | archived result |
MD

    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| infra     | 1     |"* ]]
    [[ "$output" == *"| dm-signal | 1     |"* ]]
    [[ "$output" == *"| impl  | 1     |"* ]]
    [[ "$output" == *"| recon | 1     |"* ]]
}

@test "malformed row warning includes source path" {
    cat > "$TEST_TMPDIR/context/cmd-chronicle.md" <<'MD'
# CMD年代記

## 2026-05

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| cmd_bad | missing date | infra | — |
MD

    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: skipping malformed chronicle row at $TEST_TMPDIR/context/cmd-chronicle.md:"* ]]
}
