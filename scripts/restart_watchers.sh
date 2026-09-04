#!/bin/bash
# semantic-links: [[inbox_watcherプロセスモデル]]
# restart_watchers.sh — inbox_watcher全プロセスを再起動
# Usage: bash scripts/restart_watchers.sh [--status]
# cmd_100: スクリプト更新後の再起動用

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_WATCHER_COUNT="${EXPECTED_WATCHER_COUNT:-9}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/daemon_maintenance_lock.sh"

watcher_processes() {
    # Match process identity, not an arbitrary occurrence in the argument text.
    # `ps ... args` alone also sees this regex inside `bash -lc "..."`, while
    # the old literal `bash` prefix misses the production `/bin/bash` argv[0].
    # Linux normally exposes the script as truncated `inbox_watcher.s`, but a
    # freshly launched watcher can remain `bash`; exact argv positions reject
    # command-text false positives in both states.
    ps -eo pid=,ppid=,comm=,args= 2>/dev/null | awk '
        ($3 ~ /^inbox_watcher/ || $3 == "bash") && ($4 == "bash" || $4 ~ /\/bash$/) &&
        $5 ~ /\/inbox_watcher\.sh$/ && $6 ~ /^[a-z][a-z0-9_-]*$/ {
            pid=$1; ppid=$2; watcher[pid]=1; parent[pid]=ppid; line[pid]=$0
        }
        END {
            for (pid in watcher) {
                if (!(parent[pid] in watcher)) print line[pid]
            }
        }
    ' | sort -n
}

show_status() {
    local processes actual
    processes="$(watcher_processes)"
    if [ -n "$processes" ]; then
        printf '%s\n' "$processes"
        actual="$(printf '%s\n' "$processes" | wc -l)"
    else
        actual=0
    fi
    echo "inbox_watcher: ${actual}/${EXPECTED_WATCHER_COUNT} running"
    [ "$actual" -eq "$EXPECTED_WATCHER_COUNT" ]
}

usage() {
    echo "Usage: bash scripts/restart_watchers.sh [--status]" >&2
}

case "${1:-}" in
    "") ;;
    --status)
        [ "$#" -eq 1 ] || { usage; exit 2; }
        show_status
        exit $?
        ;;
    *)
        usage
        exit 2
        ;;
esac

if is_maintenance_active; then
    echo "SKIP: daemon maintenance active (operator=${MAINTENANCE_OPERATOR})"
    exit 0
elif [[ $? -eq 2 ]]; then
    echo "ERROR: daemon maintenance marker is corrupt; refusing restart" >&2
    exit 1
fi

# 並行実行ガード（flock排他）
LOCK_FILE="${RESTART_WATCHERS_LOCK_FILE:-/tmp/restart_watchers.lock}"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "ERROR: restart_watchers.sh is already running. Aborting."
    exit 1
fi

# The restart lock is a short-lived coordinator lock.  Never let it escape
# into a watcher or the status-sync helper that this script detaches.
release_restart_watchers_lock() {
    flock -u 200 2>/dev/null || true
    exec 200>&-
}

# WSL shutdownで/tmp cacheが消えた直後も、三層記憶preflightより先に生成を始める。
# 非同期かつ共通ライブラリのflock single-flightなのでwatcher再起動を待たせない。
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/memory_db_cache.sh"
memory_db_source="${SHOGUN_MEMORY_DB_SOURCE_PATH:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}"
warm_memory_db_cache_async "$SCRIPT_DIR" "$memory_db_source"

# 隔離テスト用: watcher processへ触れず、上記の実起動フローだけを実行する。
if [ "${RESTART_WATCHERS_WARMUP_ONLY:-0}" = "1" ]; then
    exit 0
fi

echo "=== inbox_watcher 再起動 ==="

watcher_process_count() {
    local processes
    processes="$(watcher_processes)"
    if [ -n "$processes" ]; then
        printf '%s\n' "$processes" | wc -l
    else
        echo 0
    fi
}

watcher_pid_for_agent() {
    local agent="$1"
    watcher_processes | awk -v agent="$agent" '$0 ~ ("inbox_watcher\\.sh " agent " ") { print $1 }'
}

wait_for_agent_state() {
    local agent="$1" wanted="$2" i=0 pid
    while [ "$i" -lt 20 ]; do
        pid="$(watcher_pid_for_agent "$agent" | head -1)"
        if { [ "$wanted" = absent ] && [ -z "$pid" ]; } ||
           { [ "$wanted" = present ] && [ -n "$pid" ]; }; then
            return 0
        fi
        sleep 0.1
        ((i++)) || true
    done
    return 1
}

stop_agent_watcher() {
    local agent="$1" pid pids
    # 2026-09-04 09:40 将軍 D0(T3-S-62): head -1 で先頭 pid だけ止めるため、重複起動した watcher の
    # 2 本目以降が生き残り、旧 script_hash の判定(NBSP 修正前)が並走し続けた(軍師 08:51+09:27 の 2 本を実測)。
    # 同 agent の watcher pid を全て停止する。
    pids="$(watcher_pid_for_agent "$agent")"
    [ -z "$pids" ] && return 0
    for pid in $pids; do kill -TERM "$pid" 2>/dev/null || true; done
    if ! wait_for_agent_state "$agent" absent; then
        for pid in $pids; do kill -KILL "$pid" 2>/dev/null || true; done
        wait_for_agent_state "$agent" absent || {
            echo "ERROR: ${agent} watcherが停止しきれていません (pid=${pid})" >&2
            return 1
        }
    fi
}

verify_watcher_count() {
    local expected="$1"
    local actual
    actual="$(watcher_process_count)"
    if [ "$actual" -ne "$expected" ]; then
        echo "ERROR: inbox_watcherプロセス数が不正です (actual=${actual}, expected=${expected})"
        ps -eo pid=,ppid=,comm=,args= 2>/dev/null | awk '
            ($3 ~ /^inbox_watcher/ || $3 == "bash") && ($4 == "bash" || $4 ~ /\/bash$/) &&
            $5 ~ /\/inbox_watcher\.sh$/ && $6 ~ /^[a-z][a-z0-9_-]*$/ {
                pid=$1; ppid=$2; watcher[pid]=1; parent[pid]=ppid; line[pid]=$0
            }
            END {
                for (pid in watcher) {
                    if (!(parent[pid] in watcher)) print line[pid]
                }
            }
        ' || true
        return 1
    fi
    echo "  OK: inbox_watcher ${actual}/${expected}"
}

# agent単位rolling handoff。旧watcherを全停止する配達空白を作らない。
echo "[1/3] agent単位rolling handoff..."

# PID追跡（個別watcher起動検証用）
declare -a LAUNCHED_AGENTS=()
declare -a LAUNCHED_PIDS=()

# 全エージェント（settings.yaml + @agent_idから動的取得 — cmd_1136）
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"

# 欠員状態からも自己修復できるよう、rolling handoffの前に不足watcherだけ補充する。
# 先に既存watcherを落とすと、8/9開始時は安全下限7へ下がって再起動自体が停止する。
for name in $(get_all_agents); do
    [ -n "$(watcher_pid_for_agent "$name" | head -1)" ] && continue
    if [ "$name" = shogun ]; then pane="shogun:main"; else pane=$(pane_lookup "$name" 2>/dev/null) || true; fi
    [[ -z "$pane" ]] && continue
    _cli=$(tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null || echo "claude")
    unset ASW_DISABLE_ESCALATION
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "${name}" "$pane" "$_cli" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_${name}.log" 200>&- &
    disown
    wait_for_agent_state "$name" present || { echo "ERROR: ${name} 欠員watcher補充失敗" >&2; exit 1; }
    echo "  prefill ${name} → ${pane}"
done
prefill_count="$(watcher_process_count)"
if [ "$prefill_count" -ne "$EXPECTED_WATCHER_COUNT" ]; then
    echo "ERROR: rolling handoff前のwatcher補充不全 (${prefill_count}/${EXPECTED_WATCHER_COUNT})" >&2
    exit 1
fi

# get_all_agents includes shogun; consuming it directly prevents duplicate identity handoff.
for name in $(get_all_agents); do
    if [ "$name" = shogun ]; then pane="shogun:main"; else pane=$(pane_lookup "$name" 2>/dev/null) || true; fi
    [[ -z "$pane" ]] && continue
    stop_agent_watcher "$name"
    current="$(watcher_process_count)"
    if [ "$current" -lt $((EXPECTED_WATCHER_COUNT - 1)) ]; then
        echo "ERROR: rolling handoff中のroot watcher下限違反 (${current} < $((EXPECTED_WATCHER_COUNT - 1)))" >&2
        exit 1
    fi
    _cli=$(tmux show-options -p -t "$pane" -v @agent_cli 2>/dev/null || echo "claude")
    unset ASW_DISABLE_ESCALATION
    nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "${name}" "$pane" "$_cli" \
        &>> "$SCRIPT_DIR/logs/inbox_watcher_${name}.log" 200>&- &
    disown
    echo "  ${name} → ${pane} ($!)"
    LAUNCHED_AGENTS+=("${name}")
    LAUNCHED_PIDS+=("$!")
    wait_for_agent_state "$name" present || { echo "ERROR: ${name} watcher起動失敗" >&2; exit 1; }
done

echo "[2/3] 起動確認..."
# Adaptive poll (max 1s): 単一pgrep-afで全エージェント一括チェック（N並列pgrep回避）
_lp_i=0
_all_launched=0
while [ "$_lp_i" -lt 10 ]; do
    _running=$(pgrep -af "[i]nbox_watcher\.sh" 2>/dev/null || true)
    _all_launched=1
    for _la in "${LAUNCHED_AGENTS[@]}"; do
        if ! printf '%s\n' "$_running" | grep -q "inbox_watcher\.sh ${_la} "; then
            _all_launched=0
            break
        fi
    done
    [ "$_all_launched" -eq 1 ] && break
    sleep 0.1
    ((_lp_i++)) || true
done
failed_agents=()
# 最終確認: 単一pgrep-afでまとめて取得し、各エージェントをgrep確認
_running=$(pgrep -af "[i]nbox_watcher\.sh" 2>/dev/null || true)
for i in "${!LAUNCHED_AGENTS[@]}"; do
    agent="${LAUNCHED_AGENTS[$i]}"
    # 一括取得済みリストからエージェント名で絞り込み（per-agent pgrep排除）
    if ! printf '%s\n' "$_running" | grep -q "inbox_watcher\.sh ${agent} "; then
        failed_agents+=("${agent}")
    fi
done

total=${#LAUNCHED_AGENTS[@]}
failed=${#failed_agents[@]}
ok=$((total - failed))

if [ "$failed" -eq 0 ]; then
    echo "  稼働中: ${ok}/${total} プロセス"
    if [ "$total" -ne "$EXPECTED_WATCHER_COUNT" ]; then
        echo "=== 警告: 起動対象数が正常値と異なります (${total}/${EXPECTED_WATCHER_COUNT}) ==="
        exit 1
    fi
    # 単発snapshot成功直後の死亡を見逃さないよう3連続sampleを要求する。
    for sample in 1 2 3; do
        verify_watcher_count "$EXPECTED_WATCHER_COUNT" || exit 1
        echo "  stable sample ${sample}/3"
        [ "$sample" -eq 3 ] || sleep 0.2
    done
    echo "=== 再起動完了 (${ok}/${total}) ==="
else
    echo "  稼働中: ${ok}/${total} プロセス"
    for agent in "${failed_agents[@]}"; do
        echo "  FAIL: ${agent}"
    done
    echo "=== 警告: ${failed}/${total} watcherが起動失敗 ==="
    exit 1
fi

# GP-226: ヘルスチェック — inotifywaitプロセスが実際に稼働しているか確認
echo "[3/3] ヘルスチェック (inotifywait)..."
# Adaptive poll (max 2s) instead of fixed sleep 2
_iw_i=0
inotify_count=$(pgrep -fc "inotifywait.*queue/inbox" 2>/dev/null) || inotify_count=0
while [[ "$inotify_count" -lt "$ok" ]] && [ "$_iw_i" -lt 20 ]; do
    sleep 0.1
    ((_iw_i++)) || true
    inotify_count=$(pgrep -fc "inotifywait.*queue/inbox" 2>/dev/null) || inotify_count=0
done
if [[ "$inotify_count" -lt "$ok" ]]; then
    echo "  WARN: inotifywait ${inotify_count}/${ok} — watcher起動したがinotifywait未稼働の可能性"
else
    echo "  OK: inotifywait ${inotify_count}/${ok}"
fi

# ペイン変数同期（バックグラウンド — model_detect capture-pane高コスト回避）
echo "[+] ペイン変数同期 (バックグラウンド)..."
# All rolling-handoff children have been verified above; release the
# coordinator before starting this long-lived helper as a final inheritance
# barrier.  A stale holder must not make watchdog supervision skip forever.
release_restart_watchers_lock
nohup bash "$SCRIPT_DIR/scripts/sync_pane_vars.sh" \
    &>> "$SCRIPT_DIR/logs/sync_pane_vars.log" 200>&- &
disown
