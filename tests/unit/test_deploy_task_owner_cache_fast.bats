#!/usr/bin/env bats
# test_necessity: report_publication's owner-task lookup (deploy_task_owner_task_lookup)
# must return values identical to a direct field_get() parse while warm-cache hits skip
# re-reading the owner's task YAML, and must never serve stale values once that YAML
# changes (mtime-keyed invalidation) — losing either property reintroduces the 299-call
# full-file reparse regression (cmd_4165) or a false PROTECT/archive decision.

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "owner_cache"
}

teardown() {
    deploy_task_teardown
}

# test_necessity: warm cache-hit output must be byte-identical to a direct field_get()
# parse of the same owner task YAML, and the lookup must actually populate the
# mtime-keyed cache file (proves the fast path was exercised, not just idempotence).
@test "owner task lookup: cache-hit output matches direct field_get parse and populates cache" {
    local other_task="$TEST_PROJECT/queue/tasks/kagemaru.yaml"
    cat > "$other_task" <<'YAML'
task:
  assigned_to: kagemaru
  parent_cmd: cmd_other_9999
  status: idle
YAML
    run bash -c '
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        first=$(deploy_task_owner_task_lookup kagemaru "$2" cmd_current_1234)
        second=$(deploy_task_owner_task_lookup kagemaru "$2" cmd_current_1234)
        direct_parent=$(field_get "$2" parent_cmd "")
        direct_status=$(field_get "$2" status "")
        printf "FIRST=%s\n" "$first"
        printf "SECOND=%s\n" "$second"
        printf "DIRECT_PARENT=%s\n" "$direct_parent"
        printf "DIRECT_STATUS=%s\n" "$direct_status"
        cache_file="$1/.cache/owner-task/kagemaru"
        [ -f "$cache_file" ] && printf "CACHE_EXISTS=1\n" || printf "CACHE_EXISTS=0\n"
    ' _ "$TEST_PROJECT" "$other_task"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'FIRST=cmd_other_9999\tidle'* ]]
    [[ "$output" == *$'SECOND=cmd_other_9999\tidle'* ]]
    [[ "$output" == *"DIRECT_PARENT=cmd_other_9999"* ]]
    [[ "$output" == *"DIRECT_STATUS=idle"* ]]
    [[ "$output" == *"CACHE_EXISTS=1"* ]]
}

# test_necessity: once the owner's task YAML is rewritten (mtime changes), the cache
# must be rebuilt — a stale cache would misreport a PROTECT/archive decision for a
# ninja who has since moved to a new cmd or finished their task.
@test "owner task lookup: cache invalidates when owner task YAML mtime changes" {
    local other_task="$TEST_PROJECT/queue/tasks/hanzo.yaml"
    cat > "$other_task" <<'YAML'
task:
  assigned_to: hanzo
  parent_cmd: cmd_before_1111
  status: idle
YAML
    run bash -c '
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        before=$(deploy_task_owner_task_lookup hanzo "$2" cmd_current_zzzz)
        printf "BEFORE=%s\n" "$before"
        cat > "$2" <<YAML2
task:
  assigned_to: hanzo
  parent_cmd: cmd_after_2222
  status: assigned
YAML2
        touch -d "@$(( $(stat -c %Y "$2") + 5 ))" "$2"
        after=$(deploy_task_owner_task_lookup hanzo "$2" cmd_current_zzzz)
        printf "AFTER=%s\n" "$after"
    ' _ "$TEST_PROJECT" "$other_task"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'BEFORE=cmd_before_1111\tidle'* ]]
    [[ "$output" == *$'AFTER=cmd_after_2222\tassigned'* ]]
}

# test_necessity: the "same parent_cmd" safety boundary must still resolve the correct
# status via a full field_get() parse — this is the PROTECT-decision path where a
# false read would incorrectly archive an active peer report.
@test "owner task lookup: same-parent_cmd boundary resolves correct status via full parse" {
    local other_task="$TEST_PROJECT/queue/tasks/saizo.yaml"
    cat > "$other_task" <<'YAML'
task:
  assigned_to: saizo
  parent_cmd: cmd_shared_5555
  status: in_progress
YAML
    run bash -c '
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        result=$(deploy_task_owner_task_lookup saizo "$2" cmd_shared_5555)
        printf "RESULT=%s\n" "$result"
    ' _ "$TEST_PROJECT" "$other_task"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'RESULT=cmd_shared_5555\tin_progress'* ]]
}

# test_necessity: when parent_cmd/status fall outside the header scan window (malformed
# boundary), the lookup must still fall back to a full parse instead of silently losing
# detection coverage — this is the "全列挙廃止は境界喪失ゆえ不可" guarantee.
@test "owner task lookup: fields beyond header window still resolve via full-parse fallback" {
    local other_task="$TEST_PROJECT/queue/tasks/tobisaru.yaml"
    {
        printf 'task:\n'
        printf '  assigned_to: tobisaru\n'
        local i
        for i in $(seq 1 250); do
            printf '  padding_field_%d: "filler line to push real fields past the header window"\n' "$i"
        done
        printf '  parent_cmd: cmd_deep_7777\n'
        printf '  status: acknowledged\n'
    } > "$other_task"
    run bash -c '
        set -e
        export DEPLOY_TASK_LIB_ONLY=1
        source "$1/scripts/deploy_task.sh"
        scan=$(deploy_task_owner_header_scan 200 "$2")
        result=$(deploy_task_owner_task_lookup tobisaru "$2" cmd_current_unrelated)
        printf "SCAN=%s\n" "$scan"
        printf "RESULT=%s\n" "$result"
    ' _ "$TEST_PROJECT" "$other_task"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SCAN=__HEADER_MISS__"* ]]
    [[ "$output" == *$'RESULT=cmd_deep_7777\tacknowledged'* ]]
}
