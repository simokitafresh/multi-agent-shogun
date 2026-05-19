#!/usr/bin/env bats
# test_record_lesson_feedback.bats

setup() {
    TEST_PROJECT="$(mktemp -d "$BATS_TMPDIR/record_lesson_feedback.XXXXXX")"
    mkdir -p "$TEST_PROJECT/scripts" "$TEST_PROJECT/logs" "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports"
    cp "$BATS_TEST_DIRNAME/../../scripts/record_lesson_feedback.sh" "$TEST_PROJECT/scripts/record_lesson_feedback.sh"
}

teardown() {
    [ -n "${TEST_PROJECT:-}" ] && [ -d "$TEST_PROJECT" ] && rm -rf "$TEST_PROJECT"
}

@test "record_lesson_feedback upgrades old lesson_impact header and appends score column" {
    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-05-12T00:00:00	cmd_old	sasuke	L001	injected	CLEAR	yes	infra	impl	None
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_cmd_test.yaml" <<'EOF'
worker_id: sasuke
task_id: cmd_test_impl
parent_cmd: cmd_test
project: infra
task_type: impl
lessons_useful:
  - id: L001
    useful: true
    reason: used
  - id: L002
    useful: false
    reason: unrelated
EOF

    run bash "$TEST_PROJECT/scripts/record_lesson_feedback.sh" "$TEST_PROJECT/queue/reports/sasuke_report_cmd_test.yaml"
    [ "$status" -eq 0 ]

    run awk -F'\t' 'NR==1{print $NF}' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [ "$output" = "score" ]

    run awk -F'\t' '$5=="feedback"{print NF ":" $4 ":" $6 ":" $11}' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"11:L001:USEFUL:"* ]]
    [[ "$output" == *"11:L002:NOT_USEFUL:"* ]]
}
