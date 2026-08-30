#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export FIXTURE_ROOT="$BATS_TEST_TMPDIR/gate-improvement-trigger"
    export TEMPLATE_ROOT="$FIXTURE_ROOT/template"
    mkdir -p "$TEMPLATE_ROOT/scripts/gates" "$TEMPLATE_ROOT/bin" "$TEMPLATE_ROOT/tmp"
    printf '%s\n' '#!/usr/bin/env bash' \
        'if [ "$3" = gate_alert ] && ! printf "%s" "$2" | grep -Eq "^task_id=commander_directive subject_task_id=gate_alert_[A-Za-z0-9._-]+_GA-[0-9]+ parent_cmd=cmd_gate_improvement_[A-Za-z0-9._-]+"; then exit 2; fi' \
        'printf "%s\n" "$*" >> "$GATE_IMPROVEMENT_ROOT/inbox_calls.log"' \
        > "$TEMPLATE_ROOT/scripts/inbox_write.sh"
    chmod +x "$TEMPLATE_ROOT/scripts/inbox_write.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEMPLATE_ROOT/scripts/ntfy.sh"
    chmod +x "$TEMPLATE_ROOT/scripts/ntfy.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" success' > "$TEMPLATE_ROOT/bin/gh"
    chmod +x "$TEMPLATE_ROOT/bin/gh"
}

create_source_repo() {
    local repo="$1" state="$2" base_commit source_commit published_commit
    mkdir -p "$repo"
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    printf '%s\n' 'base' > "$repo/infrastructure.md"
    git -C "$repo" add infrastructure.md
    git -C "$repo" commit -q -m 'base'
    base_commit="$(git -C "$repo" rev-parse HEAD)"

    printf '%s\n' 'source' > "$repo/infrastructure.md"
    git -C "$repo" add infrastructure.md
    git -C "$repo" commit -q -m 'source publication candidate'
    source_commit="$(git -C "$repo" rev-parse HEAD)"

    case "$state" in
        equivalent)
            git -C "$repo" checkout -q -b published "$base_commit"
            printf '%s\n' 'source' > "$repo/infrastructure.md"
            git -C "$repo" add infrastructure.md
            git -C "$repo" commit -q -m 'equivalent publication'
            published_commit="$(git -C "$repo" rev-parse HEAD)"
            ;;
        pending)
            published_commit="$base_commit"
            ;;
        mismatch)
            git -C "$repo" checkout -q -b published "$base_commit"
            printf '%s\n' 'different publication' > "$repo/infrastructure.md"
            git -C "$repo" add infrastructure.md
            git -C "$repo" commit -q -m 'mismatching publication'
            published_commit="$(git -C "$repo" rev-parse HEAD)"
            ;;
        *)
            printf 'unsupported source state: %s\n' "$state" >&2
            return 1
            ;;
    esac

    git -C "$repo" update-ref refs/heads/main "$source_commit"
    git -C "$repo" update-ref refs/remotes/origin/main "$published_commit"
    printf '%s\n' "$source_commit"
}

run_fixture() {
    local name="$1" state="$2" rc="$3" root
    root="$FIXTURE_ROOT/$name"
    local source_repo="$root/source-repo" source_commit body
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
    if [[ "$state" == "normal" ]]; then
        body='--- 総合判定: OK ---'
    elif [[ "$state" == "unresolvable" ]]; then
        source_commit='deadbeefdead'
        body="WARN: infrastructure.md (source_equivalent boundary rejected: source commit $source_commit is not resolvable)"
    else
        source_commit="$(create_source_repo "$source_repo" "$state")"
        body="WARN: infrastructure.md (source_equivalent boundary rejected: source commit $source_commit is not an origin/main ancestor)"
    fi
    printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' '$body'" "exit $rc" \
        > "$root/scripts/gates/gate_context_freshness.sh"
    chmod +x "$root/scripts/gates/gate_context_freshness.sh"
    run env PATH="$root/bin:$PATH" TMPDIR="$root/tmp" \
        GATE_IMPROVEMENT_ROOT="$root" GATE_IMPROVEMENT_SOURCE_REPO="$source_repo" \
        GATE_IMPROVEMENT_NOW=1770000000 GATE_IMPROVEMENT_DEDUP_WINDOW_SECONDS=0 \
        bash "$PROJECT_ROOT/scripts/gate_improvement_trigger.sh"
}

run_hook_failure_fixture() {
    local root="$FIXTURE_ROOT/hook-failure"
    mkdir -p "$root/scripts/gates" "$root/bin" "$root/tmp" "$root/logs"
    cp "$TEMPLATE_ROOT/scripts/inbox_write.sh" "$root/scripts/inbox_write.sh"
    cp "$TEMPLATE_ROOT/scripts/ntfy.sh" "$root/scripts/ntfy.sh"
    cp "$TEMPLATE_ROOT/bin/gh" "$root/bin/gh"
    chmod +x "$root/scripts/inbox_write.sh" "$root/scripts/ntfy.sh" "$root/bin/gh"
    for gate in gate_lesson_health.sh gate_cmd_state.sh gate_context_freshness.sh gate_p_average_freshness.sh; do
        printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "--- 総合判定: OK ---"' \
            > "$root/scripts/gates/$gate"
        chmod +x "$root/scripts/gates/$gate"
    done
    printf '%s\n' '- timestamp: 2026-08-30T09:00:00+0900' \
        > "$root/logs/hook_failures.yaml"
    run env PATH="$root/bin:$PATH" TMPDIR="$root/tmp" \
        GATE_IMPROVEMENT_ROOT="$root" GATE_IMPROVEMENT_NOW=1770000000 \
        GATE_IMPROVEMENT_DEDUP_WINDOW_SECONDS=0 \
        bash "$PROJECT_ROOT/scripts/gate_improvement_trigger.sh"
}

run_ga_push1_classification_fixture() {
    local root="$FIXTURE_ROOT/ga-push1-classification"
    local hook_hash
    mkdir -p "$root/scripts/gates" "$root/bin" "$root/tmp" "$root/logs/hook_artifacts" \
        "$root/.githooks" "$root/.git/hooks"
    cp "$TEMPLATE_ROOT/scripts/inbox_write.sh" "$root/scripts/inbox_write.sh"
    cp "$TEMPLATE_ROOT/scripts/ntfy.sh" "$root/scripts/ntfy.sh"
    cp "$TEMPLATE_ROOT/bin/gh" "$root/bin/gh"
    chmod +x "$root/scripts/inbox_write.sh" "$root/scripts/ntfy.sh" "$root/bin/gh"
    for gate in gate_lesson_health.sh gate_cmd_state.sh gate_context_freshness.sh gate_p_average_freshness.sh; do
        printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "--- 総合判定: OK ---"' \
            > "$root/scripts/gates/$gate"
        chmod +x "$root/scripts/gates/$gate"
    done
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$root/.githooks/pre-push"
    cp "$root/.githooks/pre-push" "$root/.git/hooks/pre-push"
    hook_hash="$(sha256sum "$root/.githooks/pre-push" | awk '{print $1}')"

    local i artifact
    for i in 1 2 3; do
        artifact="$root/logs/hook_artifacts/expected-$i.log"
        printf '%s\n' \
            '[pre-push] BLOCK(GA-PUSH1): pushしようとしているcommitと、作業ツリーの未commit変更が同一pathを差している。' \
            '[pre-push] 重複path:' \
            '  scripts/example.sh' > "$artifact"
    done
    printf '%s\n' \
        '- timestamp: 2026-08-30T15:33:37+09:00' \
        '  hook: pre-push' \
        '  exit_code: 1' \
        '  artifact: logs/hook_artifacts/expected-1.log' \
        "  hook_sha256: $hook_hash" \
        '  detail: GA-PUSH1 safety block' \
        '- timestamp: 2026-08-30T15:33:39+09:00' \
        '  hook: pre-push' \
        '  exit_code: 1' \
        '  artifact: logs/hook_artifacts/expected-2.log' \
        "  hook_sha256: $hook_hash" \
        '  detail: GA-PUSH1 safety block' \
        '- timestamp: 2026-08-30T15:33:40+09:00' \
        '  hook: pre-push' \
        '  exit_code: 1' \
        '  artifact: logs/hook_artifacts/expected-3.log' \
        "  hook_sha256: $hook_hash" \
        '  detail: GA-PUSH1 safety block' > "$root/logs/hook_failures.yaml"
    run env PATH="$root/bin:$PATH" TMPDIR="$root/tmp" \
        GATE_IMPROVEMENT_ROOT="$root" GATE_IMPROVEMENT_NOW=1770000000 \
        GATE_IMPROVEMENT_DEDUP_WINDOW_SECONDS=0 \
        bash "$PROJECT_ROOT/scripts/gate_improvement_trigger.sh"
}

run_ga_push1_negative_fixture() {
    local root="$FIXTURE_ROOT/ga-push1-classification"
    local hook_hash
    hook_hash="$(sha256sum "$root/.githooks/pre-push" | awk '{print $1}')"
    printf '%s\n' 0 > "$root/logs/gate_state/gate_improvement_hook_last_count"
    printf '%s\n' \
        '- timestamp: 2026-08-30T15:33:37+09:00' \
        '  hook: pre-push' \
        '  exit_code: 1' \
        '  artifact: logs/hook_artifacts/expected-1.log' \
        "  hook_sha256: $hook_hash" \
        '  detail: GA-PUSH1 safety block' \
        '- timestamp: 2026-08-30T15:33:39+09:00' \
        '  hook: pre-push' \
        '  exit_code: 1' \
        '  artifact: logs/hook_artifacts/expected-2.log' \
        "  hook_sha256: $hook_hash" \
        '  detail: GA-PUSH1 safety block' \
        '- timestamp: 2026-08-30T15:33:40+09:00' \
        '  hook: pre-push' \
        '  exit_code: 1' \
        '  artifact: logs/hook_artifacts/expected-3.log' \
        "  hook_sha256: $hook_hash" \
        '  detail: GA-PUSH1 safety block' \
        '- timestamp: 2026-08-30T15:34:00+09:00' \
        '  hook: pre-push' \
        '  exit_code: 1' \
        '  artifact: logs/hook_artifacts/unexpected.log' \
        "  hook_sha256: $hook_hash" \
        '  detail: selected test failed' > "$root/logs/hook_failures.yaml"
    printf '%s\n' '[pre-push] BLOCK(TEST): selected test failed' \
        > "$root/logs/hook_artifacts/unexpected.log"
    run env PATH="$root/bin:$PATH" TMPDIR="$root/tmp" \
        GATE_IMPROVEMENT_ROOT="$root" GATE_IMPROVEMENT_NOW=1770000000 \
        GATE_IMPROVEMENT_DEDUP_WINDOW_SECONDS=0 \
        bash "$PROJECT_ROOT/scripts/gate_improvement_trigger.sh"
}

run_ga531_mixed_fixture() {
    local root="$FIXTURE_ROOT/ga531-mixed"
    local hook_hash artifact i
    mkdir -p "$root/scripts/gates" "$root/bin" "$root/tmp" "$root/logs/hook_artifacts" \
        "$root/.githooks" "$root/.git/hooks"
    cp "$TEMPLATE_ROOT/scripts/inbox_write.sh" "$root/scripts/inbox_write.sh"
    cp "$TEMPLATE_ROOT/scripts/ntfy.sh" "$root/scripts/ntfy.sh"
    cp "$TEMPLATE_ROOT/bin/gh" "$root/bin/gh"
    chmod +x "$root/scripts/inbox_write.sh" "$root/scripts/ntfy.sh" "$root/bin/gh"
    for gate in gate_lesson_health.sh gate_cmd_state.sh gate_context_freshness.sh gate_p_average_freshness.sh; do
        printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "--- 総合判定: OK ---"' \
            > "$root/scripts/gates/$gate"
        chmod +x "$root/scripts/gates/$gate"
    done
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$root/.githooks/pre-push"
    cp "$root/.githooks/pre-push" "$root/.git/hooks/pre-push"
    hook_hash="$(sha256sum "$root/.githooks/pre-push" | awk '{print $1}')"

    : > "$root/logs/hook_failures.yaml"
    for i in 1 2 3; do
        printf '%s\n' \
            "- timestamp: 2026-08-30T19:56:4${i}+09:00" \
            '  hook: pre-commit' \
            '  exit_code: 1' \
            '  detail: doc_no_changelog' >> "$root/logs/hook_failures.yaml"
    done
    for i in 1 2 3 4 5; do
        artifact="$root/logs/hook_artifacts/expected-$i.log"
        printf '%s\n' \
            '[pre-push] BLOCK(GA-PUSH1): pushしようとしているcommitと、作業ツリーの未commit変更が同一pathを差している。' \
            '[pre-push] 重複path:' \
            '  context/semantic-map.md' > "$artifact"
        printf '%s\n' \
            "- timestamp: 2026-08-30T19:58:0${i}+09:00" \
            '  hook: pre-push' \
            '  exit_code: 1' \
            "  artifact: logs/hook_artifacts/expected-$i.log" \
            "  hook_sha256: $hook_hash" \
            '  detail: GA-PUSH1 safety block' >> "$root/logs/hook_failures.yaml"
    done
    run env PATH="$root/bin:$PATH" TMPDIR="$root/tmp" \
        GATE_IMPROVEMENT_ROOT="$root" GATE_IMPROVEMENT_NOW=1770000000 \
        GATE_IMPROVEMENT_DEDUP_WINDOW_SECONDS=0 \
        bash "$PROJECT_ROOT/scripts/gate_improvement_trigger.sh"
}

assert_gate_identity() {
    local calls_file="$1" gate_name="$2"
    grep -Eq "task_id=commander_directive subject_task_id=gate_alert_${gate_name}_GA-[0-9]+ parent_cmd=cmd_gate_improvement_${gate_name}" \
        "$calls_file"
}

assert_gate_record_identity() {
    local alerts_file="$1" gate_name="$2"
    grep -Eq "task_id: commander_directive" "$alerts_file"
    grep -Eq "subject_task_id: gate_alert_${gate_name}_GA-[0-9]+" "$alerts_file"
    grep -Eq "parent_cmd: cmd_gate_improvement_${gate_name}" "$alerts_file"
}

# test_necessity: four source-equivalent publication states are a permanent
# binary contract for improvement-trigger wakeup classification.
# regression_justification: GA-505 showed that equivalent changed-path blobs
# can be published without source-commit ancestry; unknown and missing commits
# must still wake the improvement lane instead of being silently suppressed.
@test "GA-505 source-equivalent publication states keep WARN notifications fail-closed" {
    run_fixture normal normal 0
    [ "$status" -eq 0 ]
    [[ "$output" != *"SENT: context_freshness"* ]]

    run_fixture equivalent equivalent 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"source-equivalent publication already matches origin/main"* ]]
    [[ "$output" != *"SENT: context_freshness"* ]]

    run_fixture pending pending 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: context_freshness"* ]]

    run_fixture mismatch mismatch 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: context_freshness"* ]]

    run_fixture unresolvable unresolvable 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: context_freshness"* ]]

    printf '%s\n' 'fixtures=4 expected_notifications=3 observed_notifications=3 false_positive=0 false_negative=0'
}

# test_necessity: gate alerts are actionable control-plane messages; both
# production send paths must persist a unique commander envelope and remain
# compatible with inbox_write's fail-closed identity gate.
@test "gate alerts carry identity envelopes on normal and hook paths" {
    run_fixture pending pending 2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK:"* ]]
    assert_gate_identity "$FIXTURE_ROOT/pending/inbox_calls.log" context_freshness
    assert_gate_record_identity "$FIXTURE_ROOT/pending/logs/gate_alerts.yaml" context_freshness

    run_hook_failure_fixture
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK:"* ]]
    assert_gate_identity "$FIXTURE_ROOT/hook-failure/inbox_calls.log" hook_failure
    assert_gate_record_identity "$FIXTURE_ROOT/hook-failure/logs/gate_alerts.yaml" hook_failure
}

# test_necessity: the GA-530 production artifacts are intentional GA-PUSH1
# safety blocks, while an unrelated pre-push failure must remain actionable.
@test "expected GA-PUSH1 safety blocks are suppressed but unexpected failures alert" {
    run_ga_push1_classification_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected GA-PUSH1 safety BLOCKs ignored (expected=3"* ]]
    [[ "$output" != *"SENT: hook_failure"* ]]

    run_ga_push1_negative_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: hook_failure"* ]]
    grep -q 'expected_ga_push1=3' \
        "$FIXTURE_ROOT/ga-push1-classification/logs/gate_alerts.yaml"
    grep -q 'current_generation=1' \
        "$FIXTURE_ROOT/ga-push1-classification/logs/gate_alerts.yaml"
}

# test_necessity: GA-531's eight-record production mix is a permanent
# classification contract: five artifact-proven GA-PUSH1 safety blocks are
# suppressed, while three legacy pre-commit failures remain actionable.
# regression_justification: a mixed batch must not be collapsed into an
# expected-only result or misreported as a current-generation recurrence.
@test "GA-531 mixed batch counts every record and preserves legacy alerting" {
    run_ga531_mixed_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"SENT: hook_failure"* ]]
    grep -q 'ALERT: hook失敗 8件の新規レコード検知' \
        "$FIXTURE_ROOT/ga531-mixed/logs/gate_alerts.yaml"
    grep -q 'legacy=3 expected_ga_push1=5' \
        "$FIXTURE_ROOT/ga531-mixed/logs/gate_alerts.yaml"
}
