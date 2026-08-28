#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export FIXTURE_ROOT="$BATS_TEST_TMPDIR/gate-improvement-trigger"
    export TEMPLATE_ROOT="$FIXTURE_ROOT/template"
    mkdir -p "$TEMPLATE_ROOT/scripts/gates" "$TEMPLATE_ROOT/bin" "$TEMPLATE_ROOT/tmp"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "%s\n" "$*" >> "$GATE_IMPROVEMENT_ROOT/inbox_calls.log"' \
        > "$TEMPLATE_ROOT/scripts/inbox_write.sh"
    chmod +x "$TEMPLATE_ROOT/scripts/inbox_write.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEMPLATE_ROOT/scripts/ntfy.sh"
    chmod +x "$TEMPLATE_ROOT/scripts/ntfy.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" success' > "$TEMPLATE_ROOT/bin/gh"
    chmod +x "$TEMPLATE_ROOT/bin/gh"
}

run_fixture() {
    local name="$1" body="$2" rc="$3" root="$FIXTURE_ROOT/$name"
    mkdir -p "$root/scripts/gates" "$root/bin" "$root/tmp"
    cp "$TEMPLATE_ROOT/scripts/inbox_write.sh" "$root/scripts/inbox_write.sh"
    cp "$TEMPLATE_ROOT/scripts/ntfy.sh" "$root/scripts/ntfy.sh"
    cp "$TEMPLATE_ROOT/bin/gh" "$root/bin/gh"
    chmod +x "$root/scripts/inbox_write.sh" "$root/scripts/ntfy.sh" "$root/bin/gh"
    for gate in gate_lesson_health.sh gate_cmd_state.sh gate_p_average_freshness.sh; do
        printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "--- 総合判定: OK ---"' \
            > "$root/scripts/gates/$gate"
        chmod +x "$root/scripts/gates/$gate"
    done
    printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' '$body'" "exit $rc" \
        > "$root/scripts/gates/gate_context_freshness.sh"
    chmod +x "$root/scripts/gates/gate_context_freshness.sh"
    run env PATH="$root/bin:$PATH" TMPDIR="$root/tmp" \
        GATE_IMPROVEMENT_ROOT="$root" GATE_IMPROVEMENT_SOURCE_REPO="$PROJECT_ROOT" \
        GATE_IMPROVEMENT_NOW=1770000000 GATE_IMPROVEMENT_DEDUP_WINDOW_SECONDS=0 \
        bash "$PROJECT_ROOT/scripts/gate_improvement_trigger.sh"
}

# test_necessity: four source-equivalent publication states are a permanent
# binary contract for improvement-trigger wakeup classification.
# regression_justification: GA-505 showed that equivalent changed-path blobs
# can be published without source-commit ancestry; unknown and missing commits
# must still wake the improvement lane instead of being silently suppressed.
@test "GA-505 source-equivalent publication states keep WARN notifications fail-closed" {
    run_fixture published_ancestor '--- 総合判定: OK ---' 0
    [ "$status" -eq 0 ]
    [[ "$output" != *"SENT: context_freshness"* ]]

    run_fixture unpublished_local_main \
        'WARN: infrastructure.md (source_equivalent boundary rejected: source commit 3f7035401 is not an origin/main ancestor)' 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"source-equivalent publication already matches origin/main"* ]]
    [[ "$output" != *"SENT: context_freshness"* ]]

    run_fixture unknown_commit \
        'WARN: infrastructure.md (source_equivalent boundary rejected: source commit e3c456584109 is not resolvable)' 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: context_freshness"* ]]

    run_fixture missing_commit \
        'WARN: infrastructure.md (source_equivalent boundary rejected: source commit deadbeefdead is not resolvable)' 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: context_freshness"* ]]

    printf '%s\n' 'fixtures=4 expected_notifications=2 observed_notifications=2 false_positive=0 false_negative=0'
}
