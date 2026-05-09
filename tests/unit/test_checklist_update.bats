#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_DIR
    TEST_DIR="$(mktemp -d "$BATS_TMPDIR/checklist_update.XXXXXX")"
    mkdir -p "$TEST_DIR/scripts"
    cp "$PROJECT_ROOT/scripts/checklist_update.sh" "$TEST_DIR/scripts/checklist_update.sh"
    chmod +x "$TEST_DIR/scripts/checklist_update.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

write_checklist() {
    cat > "$TEST_DIR/checklist.md" <<'EOF'
# progress placeholder
# 進捗: 0/2 (0%)

| No | Target | Size | ETA | Status | Result | Owner | Actual |
|----|--------|------|-----|--------|--------|-------|--------|
| 1 | alpha | S | 1m | pending |  |  | |
| 2 | beta | S | 1m | pending | existing \| escaped | old | |
EOF
}

@test "result pipe and newline are kept inside one markdown cell" {
    write_checklist

    run bash "$TEST_DIR/scripts/checklist_update.sh" "$TEST_DIR/checklist.md" 1 "done" $'ok | pipe\nsecond line' saizo

    [ "$status" -eq 0 ]
    grep -q '^# 進捗: 1/2 (50%)$' "$TEST_DIR/checklist.md"
    grep -q '^| 1 | alpha | S | 1m | done | ok \\| pipe second line | saizo | |$' "$TEST_DIR/checklist.md"
}

@test "escaped pipe in existing row does not break later updates" {
    write_checklist

    run bash "$TEST_DIR/scripts/checklist_update.sh" "$TEST_DIR/checklist.md" 2 Pass "still ok" saizo

    [ "$status" -eq 0 ]
    grep -q '^# 進捗: 1/2 (50%)$' "$TEST_DIR/checklist.md"
    grep -q '^| 2 | beta | S | 1m | Pass | still ok | saizo | |$' "$TEST_DIR/checklist.md"
}

@test "non-integer item number fails without traceback" {
    write_checklist

    run bash "$TEST_DIR/scripts/checklist_update.sh" "$TEST_DIR/checklist.md" abc "done" ok saizo

    [ "$status" -eq 2 ]
    [[ "$output" == "FATAL: checklist_update: item_number must be an integer: abc" ]]
}

@test "unrelated numeric tables do not affect checklist progress" {
    cat > "$TEST_DIR/checklist.md" <<'EOF'
# progress placeholder
# 進捗: 0/2 (0%)

| # | Name | A | B | Status | Result | Owner | Actual |
|---|------|---|---|--------|--------|-------|--------|
| 1 | unrelated | x | y | done | old | old | old |

| # | 対象 | 複雑度 | 見積 | 状態 | 結果 | 担当 | 実績 |
|----|------|--------|------|------|------|------|------|
| 1 | alpha | S | 1m | pending |  |  | |
| 2 | beta | S | 1m | pending |  |  | |
EOF

    run bash "$TEST_DIR/scripts/checklist_update.sh" "$TEST_DIR/checklist.md" 1 done ok saizo

    [ "$status" -eq 0 ]
    grep -q '^| 1 | unrelated | x | y | done | old | old | old |$' "$TEST_DIR/checklist.md"
    grep -q '^| 1 | alpha | S | 1m | done | ok | saizo | |$' "$TEST_DIR/checklist.md"
    grep -q '^# 進捗: 1/2 (50%)$' "$TEST_DIR/checklist.md"
}
