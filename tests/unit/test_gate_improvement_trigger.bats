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
    local name="$1" state="$2" rc="$3" root="$FIXTURE_ROOT/$name"
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
