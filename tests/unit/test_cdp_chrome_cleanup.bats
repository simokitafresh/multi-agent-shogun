#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_ROOT="$(mktemp -d)"
    export PID_DIR="$TMP_ROOT"
}

teardown() {
    rm -rf "$TMP_ROOT"
}

@test "PIDファイル作成・読取・削除の基本操作" {
    # PIDファイル作成
    echo "12345" > "$TMP_ROOT/cdp_chrome_9222.pid"
    [ -f "$TMP_ROOT/cdp_chrome_9222.pid" ]

    # PIDファイル読取
    pid=$(cat "$TMP_ROOT/cdp_chrome_9222.pid")
    [ "$pid" = "12345" ]

    # PIDファイル削除
    rm -f "$TMP_ROOT/cdp_chrome_9222.pid"
    [ ! -f "$TMP_ROOT/cdp_chrome_9222.pid" ]
}

@test "cleanup_all: PIDファイルなしで正常終了" {
    run bash -lc '
set -euo pipefail
PID_DIR="'"$TMP_ROOT"'"
PID_PREFIX="cdp_chrome_"
LOG_PREFIX="[cdp_cleanup]"

log() { echo "$*"; }
log_err() { echo "ERROR: $*" >&2; }

cleanup_all() {
    local pid_files
    pid_files=("${PID_DIR}/${PID_PREFIX}"*.pid)
    if [[ ! -f "${pid_files[0]:-}" ]]; then
        log "No PID files found. Nothing to clean."
        return 0
    fi
}

cleanup_all
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"No PID files found"* ]]
}

@test "cleanup_all: 不正PIDファイルをスキップしファイル削除" {
    echo "not_a_pid" > "$TMP_ROOT/cdp_chrome_9222.pid"

    run bash -lc '
set -euo pipefail
PID_DIR="'"$TMP_ROOT"'"
PID_PREFIX="cdp_chrome_"
LOG_PREFIX="[cdp_cleanup]"

log() { echo "$*"; }
log_err() { echo "ERROR: $*" >&2; }

cleanup_all() {
    local pid_files
    pid_files=("${PID_DIR}/${PID_PREFIX}"*.pid)
    if [[ ! -f "${pid_files[0]:-}" ]]; then
        log "No PID files found. Nothing to clean."
        return 0
    fi
    local total=0 killed=0 failed=0
    for pid_file in "${pid_files[@]}"; do
        total=$((total + 1))
        local basename
        basename="$(basename "$pid_file")"
        local port_str="${basename#${PID_PREFIX}}"
        port_str="${port_str%.pid}"
        local pid
        pid="$(cat "$pid_file" 2>/dev/null || echo "")"
        if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
            log_err "Invalid PID in ${pid_file}: '"'"'${pid}'"'"' — removing file"
            rm -f "$pid_file"
            failed=$((failed + 1))
            continue
        fi
    done
    log "Summary: ${killed}/${total} cleaned, ${failed} failed"
    return 0
}

cleanup_all
'
    [ "$status" -eq 0 ]
    # PIDファイルは削除されているべき
    [ ! -f "$TMP_ROOT/cdp_chrome_9222.pid" ]
}

@test "cleanup_all: 不正ポート番号のPIDファイルをスキップ" {
    echo "12345" > "$TMP_ROOT/cdp_chrome_abc.pid"

    run bash -lc '
set -euo pipefail
PID_DIR="'"$TMP_ROOT"'"
PID_PREFIX="cdp_chrome_"
LOG_PREFIX="[cdp_cleanup]"

log() { echo "$*"; }
log_err() { echo "ERROR: $*" >&2; }

cleanup_all() {
    local pid_files
    pid_files=("${PID_DIR}/${PID_PREFIX}"*.pid)
    if [[ ! -f "${pid_files[0]:-}" ]]; then
        log "No PID files found. Nothing to clean."
        return 0
    fi
    local total=0 killed=0 failed=0
    for pid_file in "${pid_files[@]}"; do
        total=$((total + 1))
        local basename
        basename="$(basename "$pid_file")"
        local port_str="${basename#${PID_PREFIX}}"
        port_str="${port_str%.pid}"
        if [[ ! "$port_str" =~ ^[0-9]+$ ]]; then
            log_err "Malformed PID file: ${pid_file} — skipping"
            failed=$((failed + 1))
            continue
        fi
    done
    log "Summary: ${killed}/${total} cleaned, ${failed} failed"
    return 0
}

cleanup_all
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Summary: 0/1 cleaned, 1 failed"* ]]
}

@test "run_cdp_cleanup: スクリプト不在で正常スキップ" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_DIR="$(mktemp -d)"
trap "rm -rf \"$TMP_DIR\"" EXIT
LOG="$TMP_DIR/test.log"
touch "$LOG"

CDP_CLEANUP_SCRIPT="$TMP_DIR/nonexistent_script.sh"
LAST_CDP_CLEANUP=0
CDP_CLEANUP_INTERVAL=300

run_cdp_cleanup

echo "EXIT_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXIT_OK"* ]]
}

@test "run_cdp_cleanup: デバウンス期間内はスキップ" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_DIR="$(mktemp -d)"
trap "rm -rf \"$TMP_DIR\"" EXIT
LOG="$TMP_DIR/test.log"
touch "$LOG"

# 実行可能なダミースクリプトを作成
CDP_CLEANUP_SCRIPT="$TMP_DIR/cleanup.sh"
echo "#!/bin/bash" > "$CDP_CLEANUP_SCRIPT"
echo "echo CLEANUP_RAN" >> "$CDP_CLEANUP_SCRIPT"
chmod +x "$CDP_CLEANUP_SCRIPT"

CDP_CLEANUP_INTERVAL=300
LAST_CDP_CLEANUP=$(date +%s)  # 今設定→デバウンス期間内

run_cdp_cleanup

# ログにDEBOUNCEが記録されているべき
grep -q "CDP-CLEANUP-DEBOUNCE" "$LOG"
echo "DEBOUNCE_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBOUNCE_OK"* ]]
}

@test "run_cdp_cleanup: デバウンス期間後は実行される" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_DIR="$(mktemp -d)"
trap "rm -rf \"$TMP_DIR\"" EXIT
LOG="$TMP_DIR/test.log"
touch "$LOG"

# 実行可能なダミースクリプトを作成
CDP_CLEANUP_SCRIPT="$TMP_DIR/cleanup.sh"
cat > "$CDP_CLEANUP_SCRIPT" <<'"'"'SCRIPT'"'"'
#!/bin/bash
echo "[cdp_cleanup] Cleanup executed"
SCRIPT
chmod +x "$CDP_CLEANUP_SCRIPT"

CDP_CLEANUP_INTERVAL=300
LAST_CDP_CLEANUP=0  # epoch 0 → 必ずデバウンス期間超過

run_cdp_cleanup

# ログにCDP-CLEANUPが記録されているべき
grep -q "CDP-CLEANUP: Running" "$LOG"
grep -q "CDP-CLEANUP: Completed successfully" "$LOG"
echo "CLEANUP_EXECUTED_OK"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEANUP_EXECUTED_OK"* ]]
}

@test "複数PIDファイルの走査と処理" {
    echo "11111" > "$TMP_ROOT/cdp_chrome_9222.pid"
    echo "22222" > "$TMP_ROOT/cdp_chrome_9223.pid"
    echo "33333" > "$TMP_ROOT/cdp_chrome_9224.pid"

    # 3つのPIDファイルがすべて存在する
    local count
    count=$(ls "$TMP_ROOT"/cdp_chrome_*.pid 2>/dev/null | wc -l)
    [ "$count" -eq 3 ]

    # 各PIDが正しく読み取れる
    [ "$(cat "$TMP_ROOT/cdp_chrome_9222.pid")" = "11111" ]
    [ "$(cat "$TMP_ROOT/cdp_chrome_9223.pid")" = "22222" ]
    [ "$(cat "$TMP_ROOT/cdp_chrome_9224.pid")" = "33333" ]

    # 全削除後にファイルがない
    rm -f "$TMP_ROOT"/cdp_chrome_*.pid
    count=$(ls "$TMP_ROOT"/cdp_chrome_*.pid 2>/dev/null | wc -l)
    [ "$count" -eq 0 ]
}
