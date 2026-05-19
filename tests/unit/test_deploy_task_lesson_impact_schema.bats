#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"
}

@test "deploy_task lesson_impact schema includes traversal_depth after score" {
    run grep -F "'score'," "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -F "'traversal_depth'," "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -F "impact_header = '\\t'.join(IMPACT_COLUMNS) + '\\n'" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}

@test "deploy_task writes direct lesson matches with traversal_depth zero" {
    run grep -F 'score_value}\t0\n' "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 2 ]
}

@test "deploy_task upgrades existing lesson_impact header before appending rows" {
    run grep -F "def ensure_impact_header(impact_path):" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -F "ensure_impact_header(impact_log)" "$PROJECT_ROOT/scripts/deploy_task.sh"
    [ "$status" -eq 0 ]
}
