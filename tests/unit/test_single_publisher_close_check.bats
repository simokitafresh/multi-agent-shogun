#!/usr/bin/env bats
# test_necessity: §15 must remain a reproducible binary close boundary. Each
# condition needs an independently observable PASS/FAIL line so a stale daemon,
# dirty root, missing after snapshot, or direct push cannot be hidden by a
# single aggregate status.
# regression_justification: without these checks, the single-publisher rollout
# can be declared complete while one of its five production invariants is false.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE_ROOT="$(mktemp -d --tmpdir="$HOME" close_check_repo.XXXXXX)"
    STATE_ROOT="$(mktemp -d --tmpdir="$HOME" close_check_state.XXXXXX)"
    ORIGIN="$STATE_ROOT/origin.git"
    START="2000-01-01T00:00:00+00:00"
    END="2099-01-01T00:00:00+00:00"
    git init -q --bare "$ORIGIN"
    git init -q -b main "$FIXTURE_ROOT"
    git -C "$FIXTURE_ROOT" config user.email test@example.com
    git -C "$FIXTURE_ROOT" config user.name test
    mkdir -p "$FIXTURE_ROOT/scripts" "$FIXTURE_ROOT/logs"
    cp "$PROJECT_ROOT/scripts/single_publisher_after_snapshot.sh" "$FIXTURE_ROOT/scripts/"
    cp "$PROJECT_ROOT/scripts/single_publisher_close_check.sh" "$FIXTURE_ROOT/scripts/"
    printf '#!/usr/bin/env bash\n' > "$FIXTURE_ROOT/scripts/publisher.sh"
    printf '#!/usr/bin/env bash\n' > "$FIXTURE_ROOT/scripts/publish_direct_commit.sh"
    printf '#!/usr/bin/env bash\n' > "$FIXTURE_ROOT/scripts/publisher_root_drain.sh"
    chmod +x "$FIXTURE_ROOT/scripts"/*.sh
    git -C "$FIXTURE_ROOT" add scripts
    git -C "$FIXTURE_ROOT" commit -qm 'Published-By: publisher'
    git -C "$FIXTURE_ROOT" remote add origin "$ORIGIN"
    git -C "$FIXTURE_ROOT" push -q -u origin main
    AFTER="$STATE_ROOT/after"
    mkdir -p "$AFTER"
    for file in push_lane.window.log pre_push.window.log commits.window.txt merges.window.txt bats_files.txt; do : > "$AFTER/$file"; done
    printf 'fixture\n' > "$AFTER/SHA256SUMS"
    : > "$FIXTURE_ROOT/logs/daemon_watchdog.log"
    export SINGLE_PUBLISHER_REPO_ROOT="$FIXTURE_ROOT"
    export SINGLE_PUBLISHER_AFTER_SNAPSHOT_DIR="$AFTER"
    export DAEMON_WATCHDOG_LOG="$FIXTURE_ROOT/logs/daemon_watchdog.log"
    RUNTIME_LOG="$STATE_ROOT/runtime.log"
    : > "$RUNTIME_LOG"
    export SINGLE_PUBLISHER_RUNTIME_LOG="$RUNTIME_LOG"
    CLOSE="$FIXTURE_ROOT/scripts/single_publisher_close_check.sh"
}

teardown() {
    find "$FIXTURE_ROOT" "$STATE_ROOT" -depth -delete 2>/dev/null || true
}

@test "all five conditions pass and total is binary PASS" {
    run bash "$CLOSE" "$START"
    [ "$status" -eq 0 ]
    [ "$(grep -c ': PASS' <<<"$output")" -eq 6 ]
    [[ "$output" == *"TOTAL: PASS"* ]]
}

@test "trailer condition fails when origin has an unmarked commit" {
    printf 'unmarked\n' > "$FIXTURE_ROOT/unmarked.txt"
    git -C "$FIXTURE_ROOT" add unmarked.txt
    git -C "$FIXTURE_ROOT" commit -qm unmarked
    git -C "$FIXTURE_ROOT" push -q origin main
    run bash "$CLOSE" "$START"
    [ "$status" -eq 1 ]
    [[ "$output" == *"trailer_rate: FAIL"* ]]
}

@test "root condition fails when the tracked root is dirty" {
    printf 'dirty\n' >> "$FIXTURE_ROOT/scripts/publisher.sh"
    run bash "$CLOSE" "$START"
    [ "$status" -eq 1 ]
    [[ "$output" == *"root_sync: FAIL"* ]]
}

@test "publisher self-restart condition fails on a post-reload restart" {
    printf '[2099-01-01 00:00:01] RESTART: publisher.sh restarted on current code pid=99\n' > "$FIXTURE_ROOT/logs/daemon_watchdog.log"
    run bash "$CLOSE" "$START"
    [ "$status" -eq 1 ]
    [[ "$output" == *"publisher_self_restart: FAIL restarts=1"* ]]
}

@test "after snapshot condition fails when required artifact is missing" {
    rm -f "$AFTER/SHA256SUMS"
    run bash "$CLOSE" "$START"
    [ "$status" -eq 1 ]
    [[ "$output" == *"after_snapshot: FAIL"* ]]
}

@test "root direct push condition ignores static push text without a runtime event" {
    printf 'git push origin main\n' > "$FIXTURE_ROOT/scripts/legacy_push.sh"
    run bash "$CLOSE" "$START"
    [ "$status" -eq 0 ]
    [[ "$output" == *"root_direct_push: PASS calls=0"* ]]
}

@test "root direct push condition reports an unmarked runtime push with commit identity" {
    printf 'unmarked runtime\n' > "$FIXTURE_ROOT/runtime.txt"
    git -C "$FIXTURE_ROOT" add runtime.txt
    git -C "$FIXTURE_ROOT" commit -qm 'runtime direct push'
    git -C "$FIXTURE_ROOT" push -q origin main
    sha="$(git -C "$FIXTURE_ROOT" rev-parse HEAD)"
    printf '[2099-01-01 00:00:01] PUSH ci=GREEN sha=%s force=0 hook=1\n' "$sha" > "$RUNTIME_LOG"
    run bash "$CLOSE" "$START"
    [ "$status" -eq 1 ]
    [[ "$output" == *"root_direct_push: FAIL calls=1"* ]]
    [[ "$output" == *"runtime_direct_push: sha=$sha subject=runtime direct push classification=runtime.log"* ]]
}

@test "root direct push condition excludes the publisher runtime path" {
    printf 'publisher runtime\n' > "$FIXTURE_ROOT/publisher.txt"
    git -C "$FIXTURE_ROOT" add publisher.txt
    git -C "$FIXTURE_ROOT" commit -qm $'publisher runtime\n\nPublished-By: publisher'
    git -C "$FIXTURE_ROOT" push -q origin main
    sha="$(git -C "$FIXTURE_ROOT" rev-parse HEAD)"
    printf '[2099-01-01 00:00:01] publisher: root drain push=1 sha=%s\n' "$sha" > "$RUNTIME_LOG"
    run bash "$CLOSE" "$START"
    [ "$status" -eq 0 ]
    [[ "$output" == *"root_direct_push: PASS calls=0"* ]]
}

@test "after snapshot records window files and SHA256SUMS" {
    log="$STATE_ROOT/push_lane.log"
    pre="$STATE_ROOT/pre_push.log"
    printf '[2099-01-01 00:00:01] PUSH lane\n' > "$log"
    printf '[2099-01-01 00:00:01] pre_push_wall_ms=10\n' > "$pre"
    output_dir="$STATE_ROOT/generated-after"
    run env SINGLE_PUBLISHER_AFTER_SNAPSHOT_DIR="$output_dir" \
        SINGLE_PUBLISHER_PUSH_LANE_LOG="$log" SINGLE_PUBLISHER_PRE_PUSH_LOG="$pre" \
        bash "$FIXTURE_ROOT/scripts/single_publisher_after_snapshot.sh" "$START" "$END"
    [ "$status" -eq 0 ]
    [ -f "$output_dir/SHA256SUMS" ]
    [ "$(wc -l < "$output_dir/push_lane.window.log")" -eq 1 ]
    [[ "$output" == *"before_after file=push_lane.window.log"* ]]
}
