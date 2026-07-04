#!/usr/bin/env bats
# test_inbox_watcher_health.bats - inbox_watcher自動再起動テスト (おしお殿知見)

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SHOGUN_STATE_DIR="$BATS_TEST_TMPDIR/state"
    mkdir -p "$SHOGUN_STATE_DIR"
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
export SHOGUN_STATE_DIR="$TMP_ROOT/state"
mkdir -p "$SHOGUN_STATE_DIR"

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

@test "get_unread_info parses unread ids and multiline special payload without PyYAML fallback" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/queue/inbox"

cat > "$TMP_ROOT/bin/inotifywait" <<'"'"'SH'"'"'
#!/bin/bash
exit 0
SH
chmod +x "$TMP_ROOT/bin/inotifywait"

cat > "$TMP_ROOT/queue/inbox/hayate.yaml" <<'"'"'YAML'"'"'
messages:
- content: '"'"'通常メッセージ'"'"'
  from: '"'"'karo'"'"'
  id: '"'"'msg_002'"'"'
  read: false
  timestamp: '"'"'2026-04-02T14:17:35'"'"'
  type: '"'"'task_assigned'"'"'
- content: |-
    /clear
    続けて復帰せよ
  from: '"'"'karo'"'"'
  id: '"'"'msg_001'"'"'
  read: false
  timestamp: '"'"'2026-04-02T14:17:34'"'"'
  type: '"'"'clear_command'"'"'
- content: '"'"'既読メッセージ'"'"'
  from: '"'"'karo'"'"'
  id: '"'"'msg_003'"'"'
  read: true
  timestamp: '"'"'2026-04-02T14:17:36'"'"'
  type: '"'"'task_assigned'"'"'
YAML

PATH="$TMP_ROOT/bin:$PATH"
export INBOX_WATCHER_LIB_ONLY=1
set -- hayate shogun:agents.3
source "$PROJECT_ROOT/scripts/inbox_watcher.sh"
INBOX="$TMP_ROOT/queue/inbox/hayate.yaml"

raw="$(get_unread_info)"
IFS=$'\''\t'\'' read -r normal_count has_specials fingerprint specials_b64 has_task_assigned <<< "$raw"

[ "$normal_count" = "1" ]
[ "$has_specials" = "true" ]
expected_fingerprint="$(printf msg_002 | sha256sum | cut -d " " -f1)"
[ "$fingerprint" = "$expected_fingerprint" ]
[ "$has_task_assigned" = "true" ]

decoded="$(printf %s "$specials_b64" | base64 -d)"
printf "%s\n" "$decoded" | grep -q "^msg_001"
special_content_b64="$(printf "%s\n" "$decoded" | cut -f3)"
[ "$(printf %s "$special_content_b64" | base64 -d)" = $'\''/clear\n続けて復帰せよ'\'' ]
echo "PARSED_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARSED_OK"* ]]
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
        if (launches < 2) {
            print \"expected at least 2 watcher launch sites, got \" launches
            exit 1
        }
    }
" "$PROJECT_ROOT/scripts/restart_watchers.sh"
echo "RESTART_WATCHERS_UNSET=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESTART_WATCHERS_UNSET=yes"* ]]
}

@test "daemon_watchdog unread count ignores read false text inside message content" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT

cat > "$TMP_ROOT/inbox.yaml" <<'"'"'YAML'"'"'
messages:
- id: msg_1
  content: |
    literal payload:
    read: false
  read: true
- id: msg_2
  content: normal unread
  read: false
YAML

export DAEMON_WATCHDOG_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/daemon_watchdog.sh"
count="$(inbox_unread_count_file "$TMP_ROOT/inbox.yaml")"
[ "$count" = "1" ]
echo "WATCHDOG_UNREAD_COUNT_OK=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WATCHDOG_UNREAD_COUNT_OK=yes"* ]]
}
