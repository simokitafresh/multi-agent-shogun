#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/auto_failure_lesson.sh"
    REPORT="$BATS_TEST_TMPDIR/report.yaml"
}

@test "explicit non-failed root status uses the fast skip path" {
    printf 'worker_id: ninja\nstatus: completed\n' > "$REPORT"

    run bash "$SCRIPT" "$REPORT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"status_not_failed (completed)"* ]]
}

@test "status beyond the bounded header falls back to canonical YAML parsing" {
    {
        for index in $(seq 1 65); do
            printf 'field_%s: value\n' "$index"
        done
        printf 'status: completed\n'
    } > "$REPORT"

    run bash "$SCRIPT" "$REPORT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"status_not_failed (completed)"* ]]
}
