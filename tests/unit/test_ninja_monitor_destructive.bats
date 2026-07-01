#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_ROOT="$(mktemp -d "$BATS_TMPDIR/ninja_monitor_destructive.XXXXXX")"
    mkdir -p "$TMP_ROOT/scripts" "$TMP_ROOT/logs"
    cat > "$TMP_ROOT/scripts/inbox_write.sh" <<SH
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "\$1" "\$2" "\$3" "\$4" >> "$TMP_ROOT/inbox.log"
SH
    chmod +x "$TMP_ROOT/scripts/inbox_write.sh"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

run_destructive_check_with_capture() {
    local capture_file="$1"
    (
        set -euo pipefail
        export NINJA_MONITOR_LIB_ONLY=1
        # shellcheck disable=SC1090,SC1091
        source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
        SCRIPT_DIR="$TMP_ROOT"
        LOG="$TMP_ROOT/logs/ninja_monitor.log"
        DESTRUCTIVE_DEBOUNCE=300
        declare -gA DESTRUCTIVE_WARN_LAST=()
        tmux() {
            cat "$capture_file"
        }
        log() {
            printf '%s\n' "$1" >> "$LOG"
        }
        check_destructive_commands kotaro test-pane
    )
}

@test "destructive command monitor ignores dangerous words in command output" {
    capture="$TMP_ROOT/capture.txt"
    cat > "$capture" <<'EOF'
● Bash(git log --oneline -3 && git show --name-only
      HEAD | head -20)
  ⎿  0caa38f51 fix(training): emit deployable s
     kill tasks
EOF

    run run_destructive_check_with_capture "$capture"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP_ROOT/inbox.log" ]
    [ ! -f "$TMP_ROOT/logs/ninja_monitor.log" ] || ! grep -q "DESTRUCTIVE-WARN" "$TMP_ROOT/logs/ninja_monitor.log"
}

@test "destructive command monitor still detects dangerous words in Bash command text" {
    capture="$TMP_ROOT/capture.txt"
    cat > "$capture" <<'EOF'
● Bash(printf ready &&
      kill 12345)
  ⎿  blocked
EOF

    run run_destructive_check_with_capture "$capture"
    [ "$status" -eq 0 ]
    grep -q "DESTRUCTIVE-WARN: kotaro detected 'kill-command'" "$TMP_ROOT/logs/ninja_monitor.log"
    grep -q "kotaroが危険コマンド検知: kill-command" "$TMP_ROOT/inbox.log"
}
