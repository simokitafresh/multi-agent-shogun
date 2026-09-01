#!/usr/bin/env bats
# test_necessity: after the push lane auto-integrates origin/main, the only
# FF-pushable first-parent commit is the integration merge (seconds old). The
# min_age settle window must be measured from the oldest local first-parent
# commit the merge carries, not from the merge itself; otherwise every remote
# move restarts the timer and the lane never publishes.
# regression_justification: 2026-09-01 14:22-15:06 the lane logged
# "WAIT ci=GREEN … oldest=<integrate merge> age=2-7s" on four consecutive
# INTEGRATE cycles while unpushed grew 8→25 and no PUSH row appeared.

run_lane_after_integrate() {
    local old_age_sec="$1" expect="$2"
    env PROJECT_ROOT="$PROJECT_ROOT" OLD_AGE="$old_age_sec" EXPECT="$expect" bash -c '
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        root="$BATS_TEST_TMPDIR/push-lane-settle-$OLD_AGE"
        mkdir -p "$root/logs" "$root/state"
        SCRIPT_DIR="$root" STATE_DIR="$root/state" LOG="$root/logs/monitor.log"
        PUSH_LANE_LOG="$root/logs/push.log" PUSH_LANE_LOCK_FILE="$root/state/push.lock"
        PUSH_LANE_GATE_METRICS="$root/logs/gate_metrics.log"
        : > "$PUSH_LANE_GATE_METRICS"
        PUSH_LANE_MIN_AGE_SEC=600
        now=$(date +%s)
        old_local_sha=0123456789012345678901234567890123456789
        merge_sha=abcdefabcdefabcdefabcdefabcdefabcdefabcd
        remote_sha=1111111111111111111111111111111111111111
        old_epoch=$((now - OLD_AGE))
        merge_epoch=$((now - 5))
        git() {
            case "$*" in
                *"rev-list --count"*) printf "2\n" ;;
                *"rev-list --first-parent --reverse"*) printf "%s\n%s\n" "$old_local_sha" "$merge_sha" ;;
                *"show -s --format=%ct $old_local_sha"*) printf "%s\n" "$old_epoch" ;;
                *"show -s --format=%ct $merge_sha"*) printf "%s\n" "$merge_epoch" ;;
                *"symbolic-ref --quiet --short HEAD"*) printf "main\n" ;;
                *"rev-parse origin/main"*) printf "%s\n" "$remote_sha" ;;
                *"merge-base --is-ancestor origin/main HEAD"*) return 0 ;;
                *"merge-base --is-ancestor $remote_sha $old_local_sha"*) return 1 ;;
                *"merge-base --is-ancestor $remote_sha $merge_sha"*) return 0 ;;
                *"rev-parse --git-path hooks"*) printf "%s\n" "$root/hooks" ;;
                *) return 0 ;;
            esac
        }
        push_lane_pre_push_hook_ready() { return 0; }
        push_lane_publish_one() { printf "published=%s\n" "$3" >> "$root/publish.log"; }
        push_lane_regate_waiting_cmds() { :; }
        check_push_lane GREEN
        if [ "$EXPECT" = push ]; then
            test "$(cat "$root/publish.log")" = "published=$merge_sha"
            grep -q "PUSH ci=GREEN .*sha=$merge_sha" "$PUSH_LANE_LOG"
            ! grep -q "^.*WAIT ci=GREEN" "$PUSH_LANE_LOG"
            printf "push=1 sha=merge\n"
        else
            test ! -f "$root/publish.log"
            grep -q "WAIT ci=GREEN .*oldest=$merge_sha age=" "$PUSH_LANE_LOG"
            printf "push=0 wait=1\n"
        fi
    '
}

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "integration merge inherits the age of the oldest local commit: 20 min old batch publishes" {
    run run_lane_after_integrate 1200 push
    [ "$status" -eq 0 ]
    [ "$output" = "push=1 sha=merge" ]
}

@test "integration merge still waits while the oldest local commit is younger than min_age" {
    run run_lane_after_integrate 100 wait
    [ "$status" -eq 0 ]
    [ "$output" = "push=0 wait=1" ]
}
