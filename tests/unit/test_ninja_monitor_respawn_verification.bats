#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

run_helper_case() {
    local ready_on="$1"
    run env PROJECT_ROOT="$PROJECT_ROOT" READY_ON="$ready_on" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        LOG="$BATS_TEST_TMPDIR/monitor.log"
        STATE_DIR="$BATS_TEST_TMPDIR/state"
        mkdir -p "$STATE_DIR"
        : > "$LOG"
        calls=0
        tmux() {
            case "$1" in
                respawn-pane) calls=$((calls + 1)); return 0 ;;
                capture-pane)
                    if [ "$calls" -ge "$READY_ON" ]; then printf "OpenAI Codex\n›\n"; fi
                    return 0 ;;
            esac
            return 0
        }
        cli_profile_get() { [ "$2" = idle_pattern ] && printf "›\n"; }
        sleep() { :; }
        RESPAWN_CLI_VERIFY_TIMEOUT=0 RESPAWN_BACKOFF_FIRST_SEC=5 RESPAWN_BACKOFF_SECOND_SEC=15 \
            _respawn_with_cli_verification pane alpha launch TEST
        rc=$?
        cat "$LOG"
        printf "rc=%s calls=%s\n" "$rc" "$calls"
        exit "$rc"
    '
}

@test "CLI ready after first respawn is accepted and measured" {
    run_helper_case 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"success=1 attempts=1 retries=0"* ]]
    [[ "$output" == *"cumulative_successes=1 cumulative_total=1 success_rate_pct=100"* ]]
    [[ "$output" == *"rc=0 calls=1"* ]]
}

@test "failed verification retries after the 5 second first backoff" {
    run_helper_case 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-BACKOFF: alpha seconds=5 next_attempt=2"* ]]
    [[ "$output" == *"success=1 attempts=2 retries=1"* ]]
    [[ "$output" == *"rc=0 calls=2"* ]]
}

@test "three failed verifications stop after 5 and 15 second backoffs" {
    run_helper_case 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"seconds=5 next_attempt=2"* ]]
    [[ "$output" == *"seconds=15 next_attempt=3"* ]]
    [[ "$output" == *"success=0 attempts=3 retries=2"* ]]
    [[ "$output" == *"CLI unavailable after 3 attempts"* ]]
    [[ "$output" == *"rc=1 calls=3"* ]]
}

@test "default timeout and backoffs bound one failed agent to 110 seconds" {
    run bash -c '
        grep -q "RESPAWN_CLI_VERIFY_TIMEOUT:-30" "$1/scripts/ninja_monitor.sh"
        grep -q "RESPAWN_BACKOFF_FIRST_SEC:-5" "$1/scripts/ninja_monitor.sh"
        grep -q "RESPAWN_BACKOFF_SECOND_SEC:-15" "$1/scripts/ninja_monitor.sh"
        test $((30 * 3 + 5 + 15)) -eq 110
    ' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
}

@test "GA259 dead-only SSOT tests and task YAML remain outside monitor implementation" {
    run bash "$PROJECT_ROOT/tests/unit/../../scripts/respawn_dead_agent.sh" not-configured --dry-run
    [ "$status" -eq 2 ]
    run grep -n "get_ninja_names" "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    [ "$status" -eq 0 ]
    run grep -n "queue/tasks/.*yaml" "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    [ "$status" -eq 0 ]
}

@test "dead pane verification runs in background without blocking the agent scan" {
    run env PROJECT_ROOT="$PROJECT_ROOT" bash -c '
        export NINJA_MONITOR_LIB_ONLY=1
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        unset NINJA_MONITOR_LIB_ONLY
        T="$BATS_TEST_TMPDIR"; SCRIPT_DIR="$T"; STATE_DIR="$T/state"; LOG="$T/log"
        mkdir -p "$STATE_DIR" "$T/scripts"; : > "$LOG"
        printf "#!/bin/bash\nexit 0\n" > "$T/scripts/ntfy.sh"; chmod +x "$T/scripts/ntfy.sh"
        log() { printf "%s\n" "$1" >> "$LOG"; }
        tmux() {
            if [ "$1" = display-message ]; then
                case "$*" in
                    *@lord_active*) printf "0\n" ;;
                    *pane_dead*) printf "1\n" ;;
                    *pane_start_command*) printf "\n" ;;
                    *@agent_id*) printf "alpha\n" ;;
                esac
            fi
            return 0
        }
        build_cli_command() { printf "codex\n"; }
        _respawn_with_cli_verification() {
            : > "$T/respawn.started"
            while [ ! -e "$T/respawn.release" ]; do command sleep 0.05; done
            return 1
        }
        codex_config_apply_agent() { return 0; }
        codex_config_restore() { return 0; }
        NINJA_NAMES=(alpha)
        unset PANE_TARGETS CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
        declare -A PANE_TARGETS=([alpha]=pane) CLI_DEAD_RESTART_TIMES CLI_DEAD_LOOP_LAST_NTFY
        CLI_DEAD_LOOP_WINDOW=300; CLI_DEAD_LOOP_THRESHOLD=2
        check_ninja_cli_dead
        background_pid="$(jobs -pr)"
        printf "background_pid_present=%s\n" "$([ -n "$background_pid" ] && echo yes || echo no)"
        test -n "$background_pid"
        : > "$T/respawn.release"
        wait
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"background_pid_present=yes"* ]]
}
