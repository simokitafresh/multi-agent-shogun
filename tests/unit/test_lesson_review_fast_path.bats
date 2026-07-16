#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE="$BATS_TEST_TMPDIR/project"
    mkdir -p "$FIXTURE/scripts" "$FIXTURE/config" "$FIXTURE/demo/tasks"
    cp "$ROOT/scripts/lesson_review.sh" "$FIXTURE/scripts/lesson_review.sh"
    cat > "$FIXTURE/config/projects.yaml" <<YAML
projects:
  - id: demo
    path: "$FIXTURE/demo"
YAML
}

@test "no-draft Markdown ledger returns the canonical empty result" {
    cat > "$FIXTURE/demo/tasks/lessons.md" <<'MD'
### L001: confirmed lesson
- **status**: confirmed
MD

    run bash "$FIXTURE/scripts/lesson_review.sh" demo

    [ "$status" -eq 0 ]
    [ "$output" = "[lesson_review] No draft lessons found in $FIXTURE/demo/tasks/lessons.md" ]
}

@test "draft metadata falls through to the canonical parser" {
    cat > "$FIXTURE/demo/tasks/lessons.md" <<'MD'
### L007: review this lesson
- **日付**: 2026-07-17
- **出典**: cmd_test
- **status**: draft
MD

    run bash "$FIXTURE/scripts/lesson_review.sh" demo

    [ "$status" -eq 0 ]
    [[ "$output" == *"1 draft lesson(s) found"* ]]
    [[ "$output" == *"L007"* ]]
    [[ "$output" == *"review this lesson"* ]]
}
