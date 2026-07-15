#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/logs" "$TEST_ROOT/queue/tasks" "$TEST_ROOT/queue/reports"
    cp "$PROJECT_ROOT/scripts/record_lesson_feedback.sh" "$TEST_ROOT/scripts/record_lesson_feedback.sh"

    cat > "$TEST_ROOT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-07-15T00:00:00	task_exact	sasuke	L001	injected	pending	pending	infra	exact	None	None	None
2026-07-15T00:00:00	task_exact	sasuke	L002	injected	NOT_USEFUL	no	infra	exact	None	None	None
2026-07-15T00:00:00	task_exact	sasuke	L003	injected	NOT_USEFUL	no	infra	exact	None	None	None
2026-07-15T00:00:00	task_exact	sasuke	L002	feedback	NOT_USEFUL	no	infra	exact	None	None	None
EOF
    cat > "$TEST_ROOT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  task_id: task_exact
  parent_cmd: cmd_exact
  assigned_lesson_ids:
    - L001
EOF
    cat > "$TEST_ROOT/queue/reports/sasuke_report_cmd_exact.yaml" <<'EOF'
worker_id: sasuke
task_id: task_exact
parent_cmd: cmd_exact
project: infra
task_type: exact
lessons_useful:
  - id: L001
    useful: true
    reason: assigned
  - id: L002
    useful: false
    reason: stale report contamination
EOF
}

@test "explicit assigned lesson set reconciles feedback and resets unassigned injected rows" {
    run bash "$TEST_ROOT/scripts/record_lesson_feedback.sh" "$TEST_ROOT/queue/reports/sasuke_report_cmd_exact.yaml"
    [ "$status" -eq 0 ]

    run awk -F'\t' '$2=="task_exact" && $5=="feedback" {print $4 ":" $6}' "$TEST_ROOT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = "L001:USEFUL" ]

    run awk -F'\t' '$2=="task_exact" && $5=="injected" && ($4=="L002" || $4=="L003") {print $4 ":" $6 ":" $7}' "$TEST_ROOT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L002:pending:pending"* ]]
    [[ "$output" == *"L003:pending:pending"* ]]
}
