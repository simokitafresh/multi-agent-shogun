#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"
    TEST_PROJECT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT/scripts" "$TEST_PROJECT/logs" "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports"
    cp "$PROJECT_ROOT/scripts/record_lesson_feedback.sh" "$TEST_PROJECT/scripts/record_lesson_feedback.sh"
}

@test "record_lesson_feedback upgrades 10-column lesson_impact.tsv to traversal_depth format" {
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-05-19T00:00:00	cmd_old	hayate	L001	injected	pending	pending	infra	impl	unknown
EOF

    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_test.yaml" <<'EOF'
worker_id: hayate
task_id: cmd_test_focused
parent_cmd: cmd_test
project: infra
task_type: focused
lessons_useful:
  - id: L001
    useful: true
    reason: used
EOF

    run bash "$TEST_PROJECT/scripts/record_lesson_feedback.sh" "$TEST_PROJECT/queue/reports/hayate_report_cmd_test.yaml"
    [ "$status" -eq 0 ]

    run head -n 1 "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = $'timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\tscore\ttraversal_depth' ]

    run awk -F'\t' 'NR == 2 { print NF ":" $11 ":" $12 } NR == 3 { print NF ":" $5 ":" $11 ":" $12 }' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"12::"* ]]
    [[ "$output" == *"12:feedback::"* ]]
}

@test "record_lesson_feedback upgrades 11-column score logs by appending traversal_depth" {
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score
2026-05-19T00:00:00	cmd_old	hayate	L001	injected	pending	pending	infra	impl	unknown	7
EOF

    cat > "$TEST_PROJECT/queue/reports/hayate_report_cmd_test.yaml" <<'EOF'
worker_id: hayate
task_id: cmd_test_focused
parent_cmd: cmd_test
project: infra
task_type: focused
lessons_useful:
  - id: L001
    useful: false
    reason: unused
EOF

    run bash "$TEST_PROJECT/scripts/record_lesson_feedback.sh" "$TEST_PROJECT/queue/reports/hayate_report_cmd_test.yaml"
    [ "$status" -eq 0 ]

    run awk -F'\t' 'NR == 1 { print $11 ":" $12 } NR == 2 { print NF ":" $11 ":" $12 } NR == 3 { print NF ":" $5 ":" $6 ":" $11 ":" $12 }' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"score:traversal_depth"* ]]
    [[ "$output" == *"12:7:"* ]]
    [[ "$output" == *"12:feedback:NOT_USEFUL::"* ]]
}

@test "record_lesson_feedback auto-records unreported injected lessons as not useful" {
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level	score	traversal_depth
2026-05-19T00:00:00	cmd_test_exact	kagemaru	L001	injected	pending	pending	infra	exact	unknown	7	0
2026-05-19T00:00:00	cmd_test_exact	kagemaru	L002	injected	pending	pending	infra	exact	unknown	6	0
2026-05-19T00:00:00	cmd_test_exact	kagemaru	L003	injected	pending	pending	infra	exact	unknown	5	0
EOF

    cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<'EOF'
task:
  task_id: cmd_test_exact
  parent_cmd: cmd_test
  project: infra
  task_type: exact
EOF

    cat > "$TEST_PROJECT/queue/reports/kagemaru_report_cmd_test.yaml" <<'EOF'
worker_id: kagemaru
task_id: cmd_test_exact
parent_cmd: cmd_test
project: infra
task_type: exact
lessons_useful:
  - id: L001
    useful: true
    reason: used
EOF

    run bash "$TEST_PROJECT/scripts/record_lesson_feedback.sh" "$TEST_PROJECT/queue/reports/kagemaru_report_cmd_test.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Auto-recorded 2 missing injected lessons as NOT_USEFUL"* ]]

    run awk -F'\t' '$5 == "feedback" { print $4 ":" $6 ":" $7 ":" NF }' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L001:USEFUL:yes:12"* ]]
    [[ "$output" == *"L002:NOT_USEFUL:no:12"* ]]
    [[ "$output" == *"L003:NOT_USEFUL:no:12"* ]]
}
