#!/usr/bin/env bats
# test_necessity: Parallel backfill runs are idempotent and produce exactly one marker per target; violation is BLOCK.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    ROOT="$BATS_TEST_TMPDIR/fixture"
    GATES="$ROOT/gates"
    REPORTS="$ROOT/reports"
    mkdir -p "$GATES/cmd_archived" "$GATES/cmd_training_fixture" "$GATES/cmd_existing" "$REPORTS"
    touch "$GATES/cmd_archived/archive.done" "$GATES/cmd_existing/review_gate.done"
}

run_backfill() {
    BACKFILL_REVIEW_GATES_DIR="$GATES" BACKFILL_REVIEW_REPORTS_DIR="$REPORTS" \
        bash "$PROJECT_ROOT/scripts/backfill_review_gate_done.sh"
}

@test "backfills archive training and completed quoted reports without touching pending" {
    cat > "$REPORTS/completed.yaml" <<'EOF'
parent_cmd: "cmd_from_report"
status: 'completed'
EOF
    cat > "$REPORTS/pending.yaml" <<'EOF'
parent_cmd: cmd_pending
status: pending
EOF

    run run_backfill
    [ "$status" -eq 0 ]
    [ "$output" = "backfill_review_gate_done: 3 directories processed" ]
    [ -f "$GATES/cmd_archived/review_gate.done" ]
    [ -f "$GATES/cmd_training_fixture/review_gate.done" ]
    [ -f "$GATES/cmd_from_report/review_gate.done" ]
    [ ! -e "$GATES/cmd_pending" ]

    run run_backfill
    [ "$status" -eq 0 ]
    [ "$output" = "backfill_review_gate_done: 0 directories processed" ]
}

@test "empty report directory and incomplete YAML remain safe no-ops" {
    cat > "$REPORTS/incomplete.yaml" <<'EOF'
result:
  summary: no top-level status or parent
EOF
    touch "$GATES/cmd_archived/review_gate.done" "$GATES/cmd_training_fixture/review_gate.done"

    run run_backfill
    [ "$status" -eq 0 ]
    [ "$output" = "backfill_review_gate_done: 0 directories processed" ]
}

@test "parallel runs remain idempotent and produce one marker per target" {
    cat > "$REPORTS/completed.yaml" <<'EOF'
parent_cmd: cmd_parallel
status: completed
EOF
    run_backfill > "$ROOT/one.out" &
    p1=$!
    run_backfill > "$ROOT/two.out" &
    p2=$!
    wait "$p1"
    wait "$p2"

    [ -f "$GATES/cmd_parallel/review_gate.done" ]
    [ "$(find "$GATES/cmd_parallel" -name review_gate.done | wc -l)" -eq 1 ]
}

@test "missing gates root fails closed" {
    GATES="$ROOT/missing-gates"
    run run_backfill
    [ "$status" -ne 0 ]
}
