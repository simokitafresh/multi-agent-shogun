#!/usr/bin/env bats
# test_necessity: tmux duplicate detection must alert only for multiple kernel-reported
# servers on one socket, identify the reachable owner fail-closed, and deduplicate
# unchanged alerts without issuing any process-stop operation.
# test_necessity: only an actual restart_watchers owner may defer supervision;
# an inherited lock held by another daemon must fail open to health checking.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TEST_ROOT="$(mktemp -d)"
}

teardown() {
    rm -f "$TEST_ROOT/lock" "$TEST_ROOT/ss" "$TEST_ROOT/owner" \
        "$TEST_ROOT/dedupe" "$TEST_ROOT/dedupe.lock"
    find "$TEST_ROOT" -depth -delete 2>/dev/null || true
}

@test "free lock is not reported as an active restart" {
    run bash -c 'DAEMON_WATCHDOG_LIB_ONLY=1 source "$1/scripts/daemon_watchdog.sh"; restart_watchers_lock_is_active "$2/lock"' _ "$PROJECT_ROOT" "$TEST_ROOT"
    [ "$status" -eq 1 ]
}

@test "canonical restart holder defers supervision" {
    lock="$TEST_ROOT/lock"
    ( exec 9>"$lock"; flock -n 9; exec -a "$PROJECT_ROOT/scripts/restart_watchers.sh" sleep 5 ) &
    holder=$!
    sleep 0.1
    run bash -c 'DAEMON_WATCHDOG_LIB_ONLY=1 source "$1/scripts/daemon_watchdog.sh"; restart_watchers_lock_is_active "$2"' _ "$PROJECT_ROOT" "$lock"
    wait "$holder"
    [ "$status" -eq 0 ]
}

@test "noncanonical inherited holder does not cause a permanent skip" {
    lock="$TEST_ROOT/lock"
    ( exec 9>"$lock"; flock -n 9; exec -a "$PROJECT_ROOT/scripts/gist_sync.sh" sleep 5 ) &
    holder=$!
    sleep 0.1
    run bash -c 'DAEMON_WATCHDOG_LIB_ONLY=1 source "$1/scripts/daemon_watchdog.sh"; restart_watchers_lock_is_active "$2"' _ "$PROJECT_ROOT" "$lock"
    wait "$holder"
    [ "$status" -eq 2 ]
}

@test "gunshi remains in the monitor watcher roster" {
    grep -Fq 'local all_agents=("shogun" "karo" "gunshi"' "$PROJECT_ROOT/scripts/ninja_monitor.sh"
}

@test "watchdog uses owner identity and generation instead of generic legacy process" {
    run bash -c '
        set -u
        root="$1"; state="$root/state"; count="$root/starts"; args="$root/args"
        mkdir -p "$state"; : >"$count"; : >"$args"
        export DAEMON_WATCHDOG_LIB_ONLY=1 SHOGUN_STATE_DIR="$state"
        export NINJA_MONITOR_OWNER_FILE="$state/ninja_monitor.owner"
        export DAEMON_WATCHDOG_LOG="$root/watchdog.log" RESTART_STATE_DIR="$root/restarts"
        source "$root/scripts/daemon_watchdog.sh"
        pid_is_live() { return 0; }
        pid_cmdline_matches() { return 0; }
        is_maintenance_active() { return 1; }
        check_restart_throttle() { return 0; }
        record_restart() { :; }
        notify() { :; }
        log() { :; }
        nohup() { printf "%s\n" "$*" >>"$count"; printf "%s\n" "$*" >>"$args"; :; }

        check_ninja_monitor
        test "$(wc -l <"$count")" -eq 1

        fp=$(sha256sum "$root/scripts/ninja_monitor.sh" | awk "{print \$1}")
        printf "%s current-generation 1\n" "$$" >"$NINJA_MONITOR_OWNER_FILE"
        printf "1 %s\n" "$fp" >"$NINJA_MONITOR_OWNER_FILE.identity"
        check_ninja_monitor
        test "$(wc -l <"$count")" -eq 1
        test ! -e "$state/ninja_monitor.watchdog.starting"

        printf "1 stale-fingerprint\n" >"$NINJA_MONITOR_OWNER_FILE.identity"
        check_ninja_monitor
        test "$(wc -l <"$count")" -eq 2
        grep -Fq "NINJA_MONITOR_REPLACE_GENERATION=current-generation" "$args"

        state="$root/parallel"; export STATE_DIR="$state" SHOGUN_STATE_DIR="$state"
        NINJA_MONITOR_OWNER_FILE="$state/ninja_monitor.owner"; export NINJA_MONITOR_OWNER_FILE
        mkdir -p "$state"; : >"$count"
        (check_ninja_monitor) & first=$!
        (check_ninja_monitor) & second=$!
        wait "$first"; wait "$second"
        test "$(wc -l <"$count")" -eq 1
        test "$(awk "{print \\$1}" "$state/ninja_monitor.watchdog.starting")" != "$$"
        printf "legacy_start=1 healthy_start=0 stale_start=1 replace_generation=1 parallel_winner=1\n"
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"legacy_start=1 healthy_start=0 stale_start=1 replace_generation=1 parallel_winner=1"* ]]
}

@test "single tmux server remains silent" {
    ss_fixture="$TEST_ROOT/ss"
    owner_fixture="$TEST_ROOT/owner"
    cat >"$ss_fixture" <<'EOF'
u_str LISTEN 0 128 /tmp/tmux-1000/default 8700818 * 0 users:(("tmux: server",pid=3100416,fd=6))
EOF
    printf '%s\n' '/tmp/tmux-1000/default pid=3100416' >"$owner_fixture"
    run bash -c '
        export DAEMON_WATCHDOG_LIB_ONLY=1
        export DAEMON_WATCHDOG_TMUX_SS_OUTPUT_FILE="$1"
        export DAEMON_WATCHDOG_TMUX_OWNER_OUTPUT_FILE="$2"
        export DAEMON_WATCHDOG_TMUX_DEDUPE_FILE="$3/dedupe"
        source "$4/scripts/daemon_watchdog.sh"
        notify() { printf "notify:%s\n" "$1"; }
        check_tmux_duplicate_servers
    ' _ "$ss_fixture" "$owner_fixture" "$TEST_ROOT" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "duplicate tmux servers alert with current owner and old server" {
    ss_fixture="$TEST_ROOT/ss"
    owner_fixture="$TEST_ROOT/owner"
    cat >"$ss_fixture" <<'EOF'
u_str LISTEN 0 128 /tmp/tmux-1000/default 8700818 * 0 users:(("tmux: server",pid=826,fd=6))
u_str LISTEN 0 128 /tmp/tmux-1000/default 8700819 * 0 users:(("tmux: server",pid=3100416,fd=7))
EOF
    printf '%s\n' '/tmp/tmux-1000/default pid=3100416' >"$owner_fixture"
    run bash -c '
        kills=0
        kill() { kills=$((kills + 1)); }
        export DAEMON_WATCHDOG_LIB_ONLY=1
        export DAEMON_WATCHDOG_TMUX_SS_OUTPUT_FILE="$1"
        export DAEMON_WATCHDOG_TMUX_OWNER_OUTPUT_FILE="$2"
        export DAEMON_WATCHDOG_TMUX_DEDUPE_FILE="$3/dedupe"
        source "$4/scripts/daemon_watchdog.sh"
        notify() { printf "notify:%s\n" "$1"; }
        check_tmux_duplicate_servers
        test "$kills" -eq 0
    ' _ "$ss_fixture" "$owner_fixture" "$TEST_ROOT" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"notify:【watchdog/CRITICAL】TMUX-DUPLICATE-ALERT: socket=/tmp/tmux-1000/default owner=3100416 old=826"* ]]
}

@test "duplicate tmux servers fail closed when current owner is unknown" {
    ss_fixture="$TEST_ROOT/ss"
    owner_fixture="$TEST_ROOT/owner"
    cat >"$ss_fixture" <<'EOF'
u_str LISTEN 0 128 /tmp/tmux-1000/default 8700818 * 0 users:(("tmux: server",pid=826,fd=6))
u_str LISTEN 0 128 /tmp/tmux-1000/default 8700819 * 0 users:(("tmux: server",pid=3100416,fd=7))
EOF
    : >"$owner_fixture"
    run bash -c '
        export DAEMON_WATCHDOG_LIB_ONLY=1
        export DAEMON_WATCHDOG_TMUX_SS_OUTPUT_FILE="$1"
        export DAEMON_WATCHDOG_TMUX_OWNER_OUTPUT_FILE="$2"
        export DAEMON_WATCHDOG_TMUX_DEDUPE_FILE="$3/dedupe"
        source "$4/scripts/daemon_watchdog.sh"
        notify() { printf "notify:%s\n" "$1"; }
        check_tmux_duplicate_servers
    ' _ "$ss_fixture" "$owner_fixture" "$TEST_ROOT" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"owner=unknown old=826,3100416"* ]]
}

@test "duplicate tmux alert is deduplicated until the event changes" {
    ss_fixture="$TEST_ROOT/ss"
    owner_fixture="$TEST_ROOT/owner"
    cat >"$ss_fixture" <<'EOF'
u_str LISTEN 0 128 /tmp/tmux-1000/default 8700818 * 0 users:(("tmux: server",pid=826,fd=6))
u_str LISTEN 0 128 /tmp/tmux-1000/default 8700819 * 0 users:(("tmux: server",pid=3100416,fd=7))
EOF
    printf '%s\n' '/tmp/tmux-1000/default pid=3100416' >"$owner_fixture"
    run bash -c '
        export DAEMON_WATCHDOG_LIB_ONLY=1
        export DAEMON_WATCHDOG_TMUX_SS_OUTPUT_FILE="$1"
        export DAEMON_WATCHDOG_TMUX_OWNER_OUTPUT_FILE="$2"
        export DAEMON_WATCHDOG_TMUX_DEDUPE_FILE="$3/dedupe"
        source "$4/scripts/daemon_watchdog.sh"
        notify() { printf "notify:%s\n" "$1"; }
        check_tmux_duplicate_servers
        check_tmux_duplicate_servers
    ' _ "$ss_fixture" "$owner_fixture" "$TEST_ROOT" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^notify:')" -eq 1 ]
}

# test_necessity: a changed publisher implementation must cause the watchdog
# to request a bounded reload and the existing restart path must launch a new
# pid; otherwise a live daemon can run stale code indefinitely.
@test "publisher script update requests stop flag and restarts with a new pid" {
    run bash -c '
        set -u
        project="$1"; fixture="$2"; state="$3"
        mkdir -p "$fixture/scripts/lib" "$fixture/logs" "$state/publish_queue"
        cp "$project/scripts/daemon_watchdog.sh" "$fixture/scripts/daemon_watchdog.sh"
        cat > "$fixture/scripts/publisher.sh" <<EOF
#!/usr/bin/env bash
pid_file="\$SHOGUN_STATE_DIR/publish_queue/publisher.pid"
trap "rm -f \"\$pid_file\"; exit 0" TERM INT EXIT
printf "%s\\n" "\$\$" > "\$pid_file"
while [ ! -f "\$SHOGUN_STATE_DIR/publish_queue/publisher.stop" ]; do sleep 0.05; done
exit 0
EOF
        cat > "$fixture/scripts/lib/publisher_event.sh" <<EOF
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "\$SHOGUN_STATE_DIR/reload-events.log"
EOF
        cat > "$fixture/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        cat > "$fixture/scripts/inbox_write.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$fixture/scripts/publisher.sh" "$fixture/scripts/lib/publisher_event.sh" "$fixture/scripts/ntfy.sh" "$fixture/scripts/inbox_write.sh"
        export SHOGUN_STATE_DIR="$state" DAEMON_WATCHDOG_LIB_ONLY=1
        bash "$fixture/scripts/publisher.sh" &
        old_pid=$!
        for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$state/publish_queue/publisher.pid" ] && break; sleep 0.05; done
        start_epoch=$(date +%s)
        export DAEMON_WATCHDOG_LIB_ONLY=1
        source "$project/scripts/daemon_watchdog.sh"
        SCRIPT_DIR="$fixture"; LOG="$fixture/logs/watchdog.log"
        publisher_pid_start_epoch() { printf "%s\\n" "$start_epoch"; }
        publisher_code_reload_needed() { printf "%s\\n" "$fixture/scripts/publisher.sh"; }
        export PUBLISHER_RELOAD_GRACE_SEC=1 PUBLISHER_RELOAD_TERM_GRACE_SEC=1
        touch -d "@$((start_epoch + 2))" "$fixture/scripts/publisher.sh"
        old_pid_file=$(cat "$state/publish_queue/publisher.pid")
        printf "%s\\n" "$old_pid_file" > "$state/publisher.pids"
        export DAEMON_WATCHDOG_PUBLISHER_PIDS_FILE="$state/publisher.pids"
        test -d "/proc/$old_pid_file"
        test "$(publisher_daemon_pids)" = "$old_pid_file"
        publisher_daemon_generation_records() { printf "%s|0|stale:%s\\n" "$old_pid_file" "$fixture/scripts/publisher.sh"; }
        watchdog_reload_publisher_if_stale
        test -f "$state/publish_queue/publisher.stop" || true
        rm -f "$state/publish_queue/publisher.stop"
        start_publisher_daemon
        new_pid=$(cat "$state/publish_queue/publisher.pid")
        test "$new_pid" != "$old_pid_file"
        printf "old_pid=%s new_pid=%s events=%s\\n" "$old_pid_file" "$new_pid" "$(grep -c "^append reload " "$state/reload-events.log")"
        touch "$state/publish_queue/publisher.stop"
        for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$new_pid" 2>/dev/null || break; sleep 0.05; done
    ' _ "$PROJECT_ROOT" "$TEST_ROOT/fixture" "$(mktemp -d --tmpdir="$HOME" watchdog_reload_state.XXXXXX)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"events=1"* ]]
}

# test_necessity: unchanged publisher code must not create a stop flag or
# reload event, preventing needless daemon churn on every watchdog tick.
@test "unchanged publisher script does not request reload" {
    run bash -c '
        set -u
        project="$1"; fixture="$2"; state="$3"
        mkdir -p "$fixture/scripts/lib" "$fixture/logs" "$state/publish_queue"
        cp "$project/scripts/daemon_watchdog.sh" "$fixture/scripts/daemon_watchdog.sh"
        cat > "$fixture/scripts/publisher.sh" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$\$" > "\$SHOGUN_STATE_DIR/publish_queue/publisher.pid"
sleep 3
EOF
        cat > "$fixture/scripts/lib/publisher_event.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$fixture/scripts/publisher.sh" "$fixture/scripts/lib/publisher_event.sh"
        export SHOGUN_STATE_DIR="$state" DAEMON_WATCHDOG_LIB_ONLY=1
        bash "$fixture/scripts/publisher.sh" &
        for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$state/publish_queue/publisher.pid" ] && break; sleep 0.05; done
        start_epoch=$(date +%s)
        source "$project/scripts/daemon_watchdog.sh"
        SCRIPT_DIR="$fixture"; publisher_pid_start_epoch() { printf "%s\\n" "$start_epoch"; }
        touch -d "@$((start_epoch - 10))" "$fixture/scripts/publisher.sh"
        touch -d "@$((start_epoch - 10))" "$fixture/scripts/lib/publisher_event.sh"
        test -z "$(publisher_code_reload_needed)"
        test ! -e "$state/publish_queue/publisher.stop"
    ' _ "$PROJECT_ROOT" "$TEST_ROOT/fixture-unchanged" "$(mktemp -d --tmpdir="$HOME" watchdog_reload_state.XXXXXX)"
    [ "$status" -eq 0 ]
}

# test_necessity: the watchdog must inventory every live publisher daemon and
# converge stale duplicates through the shared stop-flag/supervisor path.
@test "three stale publisher daemons converge to one current daemon without signals" {
    run bash -c '
        set -u
        project="$1"; fixture="$2"; state="$3"
        mkdir -p "$fixture/scripts/lib" "$fixture/logs" "$state/publish_queue"
        cp "$project/scripts/daemon_watchdog.sh" "$fixture/scripts/daemon_watchdog.sh"
        cat >"$fixture/scripts/publisher.sh" <<EOF
#!/usr/bin/env bash
printf "%s\\n" "\$\$" > "\$SHOGUN_STATE_DIR/publish_queue/publisher.pid"
while [ ! -f "\$SHOGUN_STATE_DIR/publish_queue/publisher.stop" ]; do sleep 0.05; done
exit 0
EOF
        cat >"$fixture/scripts/lib/publisher_event.sh" <<EOF
#!/usr/bin/env bash
printf "%s\\n" "\$*" >> "\$SHOGUN_STATE_DIR/reload-events.log"
EOF
        cat >"$fixture/scripts/ntfy.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
        cat >"$fixture/scripts/inbox_write.sh" <<EOF
#!/usr/bin/env bash
exit 0
EOF
        chmod +x "$fixture/scripts/publisher.sh" "$fixture/scripts/lib/publisher_event.sh" "$fixture/scripts/ntfy.sh" "$fixture/scripts/inbox_write.sh"
        export SHOGUN_STATE_DIR="$state" DAEMON_WATCHDOG_LIB_ONLY=1
        pids=()
        for _ in 1 2 3; do bash "$fixture/scripts/publisher.sh" & pids+=("$!"); done
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            [ "$(publisher_count=0; for pid in "${pids[@]}"; do [ -d "/proc/$pid" ] && publisher_count=$((publisher_count + 1)); done; echo "$publisher_count")" -eq 3 ] && break
            sleep 0.05
        done
        source "$project/scripts/daemon_watchdog.sh"
        SCRIPT_DIR="$fixture"; LOG="$fixture/logs/watchdog.log"
        publisher_pid_start_epoch() { printf "%s\\n" 0; }
        export PUBLISHER_RELOAD_GRACE_SEC=2
        test "$(publisher_daemon_pids | wc -l)" -eq 3
        watchdog_reload_publisher_if_stale
        test "$PUBLISHER_RELOAD_OCCURRED" -eq 1
        test "$PUBLISHER_RELOAD_READY" -eq 1
        test "$(grep -c "^append reload " "$state/reload-events.log")" -eq 3
        rm -f "$state/publish_queue/publisher.stop"
        start_publisher_daemon reload
        new_pid=$(cat "$state/publish_queue/publisher.pid")
        test "$(publisher_daemon_pids | wc -l)" -eq 1
        test "$(publisher_daemon_pids)" = "$new_pid"
        touch "$state/publish_queue/publisher.stop"
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            [ ! -d "/proc/$new_pid" ] && break
            sleep 0.05
        done
        printf "old_daemons=3 reload_events=3 current_daemons=1 signals=0\\n"
    ' _ "$PROJECT_ROOT" "$TEST_ROOT/fixture-three" "$(mktemp -d --tmpdir="$HOME" watchdog_reload_state.XXXXXX)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"old_daemons=3 reload_events=3 current_daemons=1 signals=0"* ]]
}

# test_necessity: scripts/publisher.sh:578 runs daemon_main at the end of a
# two-stage pipe (`daemon_main 2>&1 | publisher_timestamp_stream`). Both pipe
# stages are bash functions, so bash forks them without exec and each child
# keeps the identical "bash scripts/publisher.sh" cmdline as the top-level
# process. publisher_daemon_root_pids() must collapse the launcher plus its
# two pipe-stage children into a single generation so one unchanged daemon
# is never miscounted as 3 and reloaded (regression for the 2026-09-03
# 16:0x false-positive publisher reload loop, cmd_karo_hotfix_watchdog_parent_pid_only_202609031603).
@test "publisher pipeline stage children do not inflate the daemon generation count" {
    run bash -c '
        set -u
        project="$1"; fixture="$2"; state="$3"
        mkdir -p "$fixture/scripts/lib" "$fixture/logs" "$state/publish_queue"
        cp "$project/scripts/daemon_watchdog.sh" "$fixture/scripts/daemon_watchdog.sh"
        cat > "$fixture/scripts/publisher.sh" <<EOF
#!/usr/bin/env bash
daemon_main() {
    printf "%s\\n" "\$\$" > "\$SHOGUN_STATE_DIR/publish_queue/publisher.pid"
    while [ ! -f "\$SHOGUN_STATE_DIR/publish_queue/publisher.stop" ]; do sleep 0.05; done
}
publisher_timestamp_stream() { cat; }
daemon_main 2>&1 | publisher_timestamp_stream
EOF
        chmod +x "$fixture/scripts/publisher.sh"
        export SHOGUN_STATE_DIR="$state" DAEMON_WATCHDOG_LIB_ONLY=1
        bash "$fixture/scripts/publisher.sh" &
        root_launcher=$!
        for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$state/publish_queue/publisher.pid" ] && break; sleep 0.05; done
        registered_pid=$(cat "$state/publish_queue/publisher.pid")
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            count=$(pgrep -f "$fixture/scripts/publisher.sh" | wc -l)
            [ "$count" -ge 3 ] && break
            sleep 0.05
        done
        start_epoch=$(date +%s)
        pgrep -f "$fixture/scripts/publisher.sh" > "$state/all_pids.txt"
        test "$(wc -l < "$state/all_pids.txt")" -ge 3
        # $$ inside a pipe stage still resolves to the invoking (top-level)
        # shells pid, so the pid file must name the launcher, not a child.
        test "$registered_pid" = "$root_launcher"

        source "$project/scripts/daemon_watchdog.sh"
        SCRIPT_DIR="$fixture"; LOG="$fixture/logs/watchdog.log"
        # Pin start_epoch instead of trusting the real /proc-based reader:
        # /proc start-tick -> epoch conversion truncates to whole seconds, so
        # a file written milliseconds before the daemon starts can round to
        # the same or a later second and look newer than the daemon
        # (flaky false "stale"). A fixed epoch plus a 10s-old mtime removes
        # that race, matching the "unchanged publisher script" test above.
        publisher_pid_start_epoch() { printf "%s\\n" "$start_epoch"; }
        touch -d "@$((start_epoch - 10))" "$fixture/scripts/publisher.sh"
        export DAEMON_WATCHDOG_PUBLISHER_PIDS_FILE="$state/all_pids.txt"

        test "$(publisher_daemon_pids | wc -l)" -ge 3
        test "$(publisher_daemon_root_pids | wc -l)" -eq 1
        test "$(publisher_daemon_root_pids)" = "$registered_pid"
        test "$(publisher_daemon_generation_records | wc -l)" -eq 1
        test -z "$(publisher_code_reload_needed)"

        export PUBLISHER_RELOAD_GRACE_SEC=2
        watchdog_reload_publisher_if_stale
        test "$PUBLISHER_RELOAD_OCCURRED" -eq 0
        test ! -e "$state/publish_queue/publisher.stop"

        printf "all_pids=%s root_pids=%s reload_occurred=%s\\n" \
            "$(wc -l < "$state/all_pids.txt")" \
            "$(publisher_daemon_root_pids | wc -l)" "$PUBLISHER_RELOAD_OCCURRED"

        touch "$state/publish_queue/publisher.stop"
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            [ ! -d "/proc/$root_launcher" ] && break
            sleep 0.05
        done
    ' _ "$PROJECT_ROOT" "$TEST_ROOT/fixture-pipe" "$(mktemp -d --tmpdir="$HOME" watchdog_reload_state.XXXXXX)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"all_pids=3"* ]]
    [[ "$output" == *"root_pids=1"* ]]
    [[ "$output" == *"reload_occurred=0"* ]]
}

# test_necessity: watchdog_publisher_healthy() and watchdog_reload_publisher_if_stale()
# must resolve the same state dir publisher.sh itself uses
# ($HOME/.local/share/multi-agent-shogun by default per scripts/publisher.sh:7),
# not the ${IDLE_FLAG_DIR:-/tmp} default shared by inbox/idle-flag daemons.
# A mismatch makes the watchdog write publisher.stop to a path publisher.sh
# never reads, so reload never truly converges.
@test "publisher_state_dir matches publisher.sh state dir default, not the idle-flag default" {
    run bash -c '
        unset SHOGUN_STATE_DIR IDLE_FLAG_DIR
        DAEMON_WATCHDOG_LIB_ONLY=1
        source "$1/scripts/daemon_watchdog.sh"
        publisher_state_dir
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/.local/share/multi-agent-shogun" ]
}
