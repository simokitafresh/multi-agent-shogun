#!/usr/bin/env bats
# test_agent_state.bats - unit tests for lib/agent_state.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export AGENT_STATE_LIB="$PROJECT_ROOT/lib/agent_state.sh"
    [ -f "$AGENT_STATE_LIB" ] || return 1
}

@test "check_agent_busy returns busy when busy pattern is detected" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/lib/agent_state.sh"
tmux() {
    case "$1" in
        display-message) echo "active"; return 0 ;;
        capture-pane) echo "Running long operation"; return 0 ;;
        set-option) return 0 ;;
        *) return 0 ;;
    esac
}
cli_profile_get() {
    case "$2" in
        busy_patterns) echo "Running|Streaming" ;;
        idle_pattern) echo "PROMPT" ;;
    esac
}
check_agent_busy "shogun:agents.2" "sasuke"
'
    [ "$status" -eq 1 ]
}

@test "check_agent_busy returns idle and corrects @agent_state on idle prompt" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
STATE_DIR="$(mktemp -d)"
export SHOGUN_STATE_DIR="$STATE_DIR"
source "$PROJECT_ROOT/lib/agent_state.sh"
agent_id="agent_state_idle_test_$$"
flag="$SHOGUN_STATE_DIR/shogun_idle_${agent_id}"
log_file="$(mktemp)"
rm -f "$flag"
tmux() {
    case "$1" in
        display-message) echo "active"; return 0 ;;
        capture-pane) printf "line1\n›\n"; return 0 ;;
        set-option) echo "$*" >> "$log_file"; return 0 ;;
        *) return 0 ;;
    esac
}
cli_profile_get() {
    case "$2" in
        busy_patterns) echo "Running|Streaming" ;;
        idle_pattern) echo "›" ;;
    esac
}
check_agent_busy "shogun:agents.2" "$agent_id"
rc=$?
[ "$rc" -eq 0 ]
[ -f "$flag" ]
grep -q "@agent_state idle" "$log_file"
rm -f "$flag" "$log_file"
rmdir "$SHOGUN_STATE_DIR"
'
    [ "$status" -eq 0 ]
}

@test "check_agent_busy short-circuits when @agent_state is already idle" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
STATE_DIR="$(mktemp -d)"
export SHOGUN_STATE_DIR="$STATE_DIR"
source "$PROJECT_ROOT/lib/agent_state.sh"
agent_id="agent_state_short_circuit_$$"
flag="$SHOGUN_STATE_DIR/shogun_idle_${agent_id}"
capture_calls=0
rm -f "$flag"
tmux() {
    case "$1" in
        display-message) echo "idle"; return 0 ;;
        capture-pane) capture_calls=$((capture_calls + 1)); return 0 ;;
        set-option) return 0 ;;
        *) return 0 ;;
    esac
}
check_agent_busy "shogun:agents.2" "$agent_id"
rc=$?
[ "$rc" -eq 0 ]
[ "$capture_calls" -eq 0 ]
[ -f "$flag" ]
rm -f "$flag"
rmdir "$SHOGUN_STATE_DIR"
'
    [ "$status" -eq 0 ]
}

@test "check_agent_busy returns unknown when neither busy nor idle pattern matches" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/lib/agent_state.sh"
tmux() {
    case "$1" in
        display-message) echo "active"; return 0 ;;
        capture-pane) echo "random output"; return 0 ;;
        set-option) return 0 ;;
        *) return 0 ;;
    esac
}
cli_profile_get() {
    case "$2" in
        busy_patterns) echo "Running|Streaming" ;;
        idle_pattern) echo "PROMPT" ;;
    esac
}
check_agent_busy "shogun:agents.2" "sasuke"
'
    [ "$status" -eq 2 ]
}

@test "agent_is_busy_check detects Claude status bar only from the last non-empty line" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/lib/agent_state.sh"
tmux() {
    case "$1:$5" in
        display-message:#{pane_id}) echo "%1"; return 0 ;;
        *) ;;
    esac
    case "$1" in
        capture-pane)
            printf "older scrollback says esc to interrupt\n❯\nstatus bar esc to interrupt\n"
            return 0
            ;;
        *) return 0 ;;
    esac
}
agent_is_busy_check "shogun:agents.2" "hanzo"
'
    [ "$status" -eq 0 ]
}

@test "agent_is_busy_check detects Codex idle from context-left footer" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/lib/agent_state.sh"
tmux() {
    case "$1:$5" in
        display-message:#{pane_id}) echo "%1"; return 0 ;;
        *) ;;
    esac
    case "$1" in
        capture-pane)
            printf "Ready for next task\n85%% context left\n"
            return 0
            ;;
        *) return 0 ;;
    esac
}
agent_is_busy_check "shogun:agents.2" "sasuke"
'
    [ "$status" -eq 1 ]
}

@test "check_agent_busy returns busy when pstree detects bash subprocess under CLI" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
STATE_DIR="$(mktemp -d)"
export SHOGUN_STATE_DIR="$STATE_DIR"
source "$PROJECT_ROOT/lib/agent_state.sh"
tmux() {
    case "$1" in
        display-message)
            case "$5" in
                *pane_pid*) echo "12345"; return 0 ;;
                *agent_state*) echo "idle"; return 0 ;;
                *) echo ""; return 0 ;;
            esac
            ;;
        set-option) return 0 ;;
        *) return 0 ;;
    esac
}
pstree() { echo "bash(12345)---node(23456)---bash(34567)"; return 0; }
pgrep() { echo "34567"; return 0; }
check_agent_busy "shogun:agents.8" "kotaro"
'
    [ "$status" -eq 1 ]
}

@test "check_agent_busy returns idle when pstree shows no bash subprocess" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
STATE_DIR="$(mktemp -d)"
export SHOGUN_STATE_DIR="$STATE_DIR"
source "$PROJECT_ROOT/lib/agent_state.sh"
agent_id="pstree_no_sub_$$"
flag="$SHOGUN_STATE_DIR/shogun_idle_${agent_id}"
rm -f "$flag"
tmux() {
    case "$1" in
        display-message)
            case "$5" in
                *pane_pid*) echo "12345"; return 0 ;;
                *agent_state*) echo "idle"; return 0 ;;
                *) echo ""; return 0 ;;
            esac
            ;;
        set-option) return 0 ;;
        *) return 0 ;;
    esac
}
pstree() { echo "bash(12345)---node(23456)"; return 0; }
pgrep() { return 1; }
check_agent_busy "shogun:agents.8" "$agent_id"
rc=$?
[ "$rc" -eq 0 ]
[ -f "$flag" ]
rm -f "$flag"
rmdir "$SHOGUN_STATE_DIR"
'
    [ "$status" -eq 0 ]
}

@test "get_agent_state_label returns unknown when pane is absent" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
source "$PROJECT_ROOT/lib/agent_state.sh"
tmux() {
    case "$1:$5" in
        display-message:#{pane_id}) return 1 ;;
        *) return 0 ;;
    esac
}
[ "$(get_agent_state_label "shogun:agents.99" "sasuke")" = "unknown" ]
'
    [ "$status" -eq 0 ]
}
