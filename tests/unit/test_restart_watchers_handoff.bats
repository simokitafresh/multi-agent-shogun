#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/restart_watchers.sh"
}

@test "legacy bulk restart has deterministic 9-to-0 delivery gap" {
    run bash -c 'n=9; before=$n; n=0; printf "%s->%s\n" "$before" "$n"'
    [ "$status" -eq 0 ]
    [ "$output" = "9->0" ]
}

@test "rolling handoff enforces root floor and three stable terminal samples" {
    grep -Fq 'current" -lt $((EXPECTED_WATCHER_COUNT - 1))' "$SCRIPT"
    grep -Fq 'for sample in 1 2 3' "$SCRIPT"
    run bash -c 'n=9; min=$n; for agent in {1..9}; do n=$((n-1)); ((n<min)) && min=$n; n=$((n+1)); done; printf "min=%s final=%s samples=%s\n" "$min" "$n" "9,9,9"'
    [ "$status" -eq 0 ]
    [ "$output" = "min=8 final=9 samples=9,9,9" ]
}

@test "handoff preserves singleton locks and startup unread replay contract" {
    ! grep -q 'fuser -k /tmp/inbox_watcher_singleton_' "$SCRIPT"
    grep -Fq 'exec 209>"$SINGLETON_LOCK_FILE"' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    grep -Fq 'process_unread' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
    grep -Fq 'SEND-DEDUPE' "$PROJECT_ROOT/scripts/inbox_watcher.sh"
}

@test "status counts root watcher identity rather than child pollers" {
    grep -Fq 'if (!(parent[pid] in watcher)) print line[pid]' "$SCRIPT"
    ! grep -q 'inotify_count.*EXPECTED_WATCHER_COUNT' "$SCRIPT"
}
