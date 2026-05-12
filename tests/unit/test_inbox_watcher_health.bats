#!/usr/bin/env bats
# test_inbox_watcher_health.bats - inbox_watcher自動再起動テスト (おしお殿知見)

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "T-IWH-001: dead watcher is detected and restart logged" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts"

# inbox_watcher.shダミー（即座にexit）
cat > "$SCRIPT_DIR/scripts/inbox_watcher.sh" <<'"'"'SH'"'"'
#!/bin/bash
echo "started $1 $2" >> "${WATCHER_TEST_LOG:-/dev/null}"
SH
chmod +x "$SCRIPT_DIR/scripts/inbox_watcher.sh"

TEST_LOG="$(mktemp)"
export WATCHER_TEST_LOG="$TEST_LOG"

log() { echo "$1" >> "$TEST_LOG"; }

# pgrepをモック: 全エージェントのwatcherが死んでいる状態
pgrep() { return 1; }

# tmuxをモック: ペイン解決
tmux() {
    case "$1" in
        list-panes)
            # -f フィルタからagent_idを抽出
            local filter_agent=""
            for arg in "$@"; do
                if [[ "$arg" == *"#{==:#{@agent_id},"* ]]; then
                    filter_agent="${arg##*,}"
                    filter_agent="${filter_agent%\}}"
                fi
            done
            if [ -n "$filter_agent" ]; then
                echo "shogun:agents.3"
            fi
            ;;
        show-options)
            echo "claude"
            ;;
    esac
}

# nohupをモック: 起動コマンドを記録
nohup() {
    echo "NOHUP: $*" >> "$TEST_LOG"
}
disown() { :; }

NINJA_NAMES=(hayate)
LAST_WATCHER_RESTART=0
WATCHER_RESTART_COOLDOWN_MIN=3

check_inbox_watcher_health

grep -q "WARNING: inbox_watcher dead" "$TEST_LOG"
echo "DEAD_DETECTED=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEAD_DETECTED=yes"* ]]
}

@test "T-IWH-002: all watchers alive skips restart" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

TEST_LOG="$(mktemp)"
log() { echo "$1" >> "$TEST_LOG"; }

# pgrepをモック: 全エージェントのwatcherが生きている
pgrep() { return 0; }

NINJA_NAMES=(hayate kagemaru)
LAST_WATCHER_RESTART=0
WATCHER_RESTART_COOLDOWN_MIN=3

check_inbox_watcher_health

# WARNING が出ていないことを確認
if grep -q "WARNING" "$TEST_LOG"; then
    echo "UNEXPECTED_WARNING"
    exit 1
fi
echo "ALL_ALIVE=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALL_ALIVE=yes"* ]]
}

@test "T-IWH-003: cooldown prevents rapid restart" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

TEST_LOG="$(mktemp)"
log() { echo "$1" >> "$TEST_LOG"; }

# pgrepをモック: watcherが死んでいる
pgrep() { return 1; }

NINJA_NAMES=()
WATCHER_RESTART_COOLDOWN_MIN=3
# 直近で再起動したばかり
LAST_WATCHER_RESTART=$EPOCHSECONDS

check_inbox_watcher_health

# クールダウン中なのでWARNINGが出ないことを確認
if grep -q "WARNING" "$TEST_LOG"; then
    echo "COOLDOWN_VIOLATED"
    exit 1
fi
echo "COOLDOWN_RESPECTED=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"COOLDOWN_RESPECTED=yes"* ]]
}

@test "T-IWH-004: stale watcher gets SIGKILL if SIGTERM does not stop it" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts"
touch "$SCRIPT_DIR/scripts/inbox_watcher.sh"

TEST_LOG="$(mktemp)"
log() { echo "$1" >> "$TEST_LOG"; }

pgrep() {
    if [[ "$*" == *"inbox_watcher\\.sh hayate "* ]]; then
        echo 12345
        return 0
    fi
    return 0
}

stat() {
    case "$*" in
        *"/proc/12345"*) echo 100 ;;
        *"inbox_watcher.sh"*) echo 200 ;;
        *) command stat "$@" ;;
    esac
}

kill_state="alive"
kill() {
    case "$1" in
        -0)
            [[ "$kill_state" == "alive" ]]
            ;;
        -KILL)
            echo "KILL_SIGKILL $2" >> "$TEST_LOG"
            kill_state="dead"
            return 0
            ;;
        *)
            echo "KILL_SIGTERM $1" >> "$TEST_LOG"
            return 0
            ;;
    esac
}

tmux() {
    case "$1" in
        list-panes) echo "shogun:agents.3" ;;
        show-options) echo "claude" ;;
    esac
}
nohup() { echo "NOHUP: $*" >> "$TEST_LOG"; }
disown() { :; }
sleep() { :; }

NINJA_NAMES=(hayate)
LAST_WATCHER_RESTART=0
WATCHER_RESTART_COOLDOWN_MIN=3
INBOX_WATCHER_STOP_GRACE_SEC=2

check_inbox_watcher_health

grep -q "SIGTERM sent to stale watcher for hayate" "$TEST_LOG"
grep -q "SIGKILL sent to stale watcher for hayate" "$TEST_LOG"
grep -q "stale watcher for hayate stopped after SIGKILL" "$TEST_LOG"
echo "SIGKILL_FALLBACK=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SIGKILL_FALLBACK=yes"* ]]
}

@test "T-IWH-005: watcher restarts do not inherit ASW_DISABLE_ESCALATION" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/scripts"
touch "$SCRIPT_DIR/scripts/inbox_watcher.sh"

TEST_LOG="$(mktemp)"
log() { echo "$1" >> "$TEST_LOG"; }

pgrep() { return 1; }
tmux() {
    case "$1" in
        list-panes) echo "shogun:agents.3" ;;
        show-options) echo "claude" ;;
    esac
}
nohup() {
    echo "ASW=${ASW_DISABLE_ESCALATION-unset}" >> "$TEST_LOG"
    echo "NOHUP: $*" >> "$TEST_LOG"
}
disown() { :; }

export ASW_DISABLE_ESCALATION=1
NINJA_NAMES=(hayate)
LAST_WATCHER_RESTART=0
WATCHER_RESTART_COOLDOWN_MIN=3

check_inbox_watcher_health

grep -q "ASW=unset" "$TEST_LOG"
echo "ASW_UNSET=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"ASW_UNSET=yes"* ]]
}

@test "T-IWH-006: restart_watchers unsets ASW_DISABLE_ESCALATION before inbox_watcher launches" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
awk "
    /unset ASW_DISABLE_ESCALATION/ { saw_unset=1; next }
    /nohup bash .*inbox_watcher.sh/ {
        if (!saw_unset) {
            print \"missing unset before line \" NR
            exit 1
        }
        launches++
        saw_unset=0
    }
    END {
        if (launches < 3) {
            print \"expected at least 3 watcher launches, got \" launches
            exit 1
        }
    }
" "$PROJECT_ROOT/scripts/restart_watchers.sh"
echo "RESTART_WATCHERS_UNSET=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESTART_WATCHERS_UNSET=yes"* ]]
}
