#!/usr/bin/env bash
# ============================================================
# health_check.sh — ヘルスチェックデーモン
# ============================================================
# インフラスクリプト（エージェントではない）のため、ポーリング許可。
# 異常検知時にkaroへinbox_writeで通知。家老が調査・対応。
#
# 起動: shutsujin_departure.sh から nohup で起動
# 停止: pkill -f "health_check.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"

# --- 設定 ---
INTERVAL=60          # チェック間隔（秒）
TASK_TIMEOUT=45      # タスク停滞閾値（分）
INBOX_TIMEOUT=10     # 未読メッセージ滞留閾値（分）

# 監視対象: 全忍者（settings.yamlから動的取得 — cmd_1136）
read -ra MONITORED_AGENTS <<< "$(get_ninja_names)"

# --- ログ関数 ---
log() {
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $1"
}

# --- チェック関数 ---

# Check 1: タスクYAMLがin_progressのまま長時間
check_task_stalled() {
    local agent="$1"
    local task_file="${SCRIPT_DIR}/queue/tasks/${agent}.yaml"

    [ -f "$task_file" ] || return 0

    # 1回のpython3呼出しでstatus/age_minutes/task_idを一括取得（3回→1回に統合）
    local task_info
    task_info=$(python3 -c "
import yaml, sys
from datetime import datetime
try:
    with open('${task_file}') as f:
        data = yaml.safe_load(f) or {}
    task = data.get('task', {})
    status = task.get('status', 'idle')
    task_id = task.get('task_id', 'unknown')
    ts = task.get('deployed_at', '') or task.get('timestamp', '')
    age = 0
    if ts:
        dt = datetime.fromisoformat(str(ts).replace('Z', '+00:00'))
        now = datetime.now(dt.tzinfo) if dt.tzinfo else datetime.now()
        age = int((now - dt).total_seconds() / 60)
    print(f'{status}|{age}|{task_id}')
except Exception:
    print('idle|0|unknown')
" 2>/dev/null || echo "idle|0|unknown")

    local status age_minutes task_id
    IFS='|' read -r status age_minutes task_id <<< "$task_info"

    if [ "$status" != "in_progress" ] && [ "$status" != "assigned" ]; then
        return 0
    fi

    if [ "$age_minutes" -ge "$TASK_TIMEOUT" ]; then
        log "ALERT: ${agent} task stalled (${age_minutes}min, task: ${task_id})"
        bash "${SCRIPT_DIR}/scripts/inbox_write.sh" karo \
            "health_alert: ${agent} task stalled (${age_minutes}min, task: ${task_id}). Investigate pane and YAML status." \
            health_alert health_check
    fi
}

# Check 2: inbox に未読メッセージが長時間滞留
check_inbox_backlog() {
    local agent="$1"
    local inbox_file="${SCRIPT_DIR}/queue/inbox/${agent}.yaml"

    [ -f "$inbox_file" ] || return 0

    local unread_age
    unread_age=$(python3 -c "
import yaml, sys
from datetime import datetime
try:
    with open('${inbox_file}') as f:
        data = yaml.safe_load(f) or {}
    messages = data.get('messages', [])
    if not isinstance(messages, list):
        print(0); sys.exit(0)
    max_age = 0
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        if msg.get('read', True):
            continue
        ts = msg.get('timestamp', '')
        if not ts:
            continue
        try:
            dt = datetime.fromisoformat(str(ts).replace('Z', '+00:00'))
            now = datetime.now(dt.tzinfo) if dt.tzinfo else datetime.now()
            age = (now - dt).total_seconds() / 60
            if age > max_age:
                max_age = age
        except:
            pass
    print(int(max_age))
except:
    print(0)
" 2>/dev/null || echo "0")

    if [ "$unread_age" -ge "$INBOX_TIMEOUT" ]; then
        log "ALERT: ${agent} inbox backlog (oldest unread: ${unread_age}min)"
        bash "${SCRIPT_DIR}/scripts/inbox_write.sh" karo \
            "health_alert: ${agent} inbox backlog (oldest unread: ${unread_age}min). Agent may be unresponsive." \
            health_alert health_check
    fi
}

# Check 3: inbox_watcher プロセスが死亡
check_watcher_alive() {
    local agent="$1"

    if ! pgrep -f "inbox_watcher.sh ${agent}" > /dev/null 2>&1; then
        log "ALERT: inbox_watcher for ${agent} is dead. Attempting restart..."

        # 自動再起動を試みる
        local pane_target
        pane_target=$(python3 -c "
import yaml, sys
try:
    with open('${SCRIPT_DIR}/config/settings.yaml') as f:
        cfg = yaml.safe_load(f) or {}
    # Lookup pane from known mapping
    import yaml as _y
    with open('${SCRIPT_DIR}/config/settings.yaml') as _sf:
        _sdata = _y.safe_load(_sf)
    agents = ['karo'] + list((_sdata or {}).get('cli', {}).get('agents', {}).keys())
    if '${agent}' in agents:
        idx = agents.index('${agent}') + 1  # pane index (1-based)
        print(f'shogun:agents.{idx}')
    else:
        print('')
except:
    print('')
" 2>/dev/null || echo "")

        if [ -n "$pane_target" ]; then
            local watcher_cli
            watcher_cli=$(tmux show-options -p -t "$pane_target" -v @agent_cli 2>/dev/null || echo "claude")
            nohup bash "${SCRIPT_DIR}/scripts/inbox_watcher.sh" "${agent}" "${pane_target}" "${watcher_cli}" \
                &>> "${SCRIPT_DIR}/logs/inbox_watcher_${agent}.log" &
            disown
            log "Restarted inbox_watcher for ${agent}"
        fi

        bash "${SCRIPT_DIR}/scripts/inbox_write.sh" karo \
            "health_alert: inbox_watcher for ${agent} was dead. Auto-restart attempted. Verify recovery." \
            health_alert health_check
    fi
}

# Check 4: pane のプロセスが死亡（Claude が落ちた）
check_pane_alive() {
    local agent="$1"

    # Find pane by @agent_id
    local pane_id
    pane_id=$(tmux list-panes -t shogun:agents -F '#{pane_index}' -f "#{==:#{@agent_id},${agent}}" 2>/dev/null | head -1)

    if [ -z "$pane_id" ]; then
        # Pane not found at all
        log "ALERT: pane for ${agent} not found"
        bash "${SCRIPT_DIR}/scripts/inbox_write.sh" karo \
            "health_alert: pane for ${agent} not found in tmux. Agent may need manual restart." \
            health_alert health_check
        return 0
    fi

    # Check if pane has a running process (not just shell prompt)
    local pane_pid
    pane_pid=$(tmux list-panes -t shogun:agents -F '#{pane_pid}' -f "#{==:#{@agent_id},${agent}}" 2>/dev/null | head -1)

    if [ -n "$pane_pid" ]; then
        # Check if Claude/codex/copilot/kimi process is running under this pane
        local child_count
        child_count=$(pgrep -P "$pane_pid" 2>/dev/null | wc -l)

        if [ "$child_count" -eq 0 ]; then
            # Shell running but no child process (CLI may have exited)
            # Check if pane shows a shell prompt (indicating CLI died)
            local last_line
            last_line=$(tmux capture-pane -t "shogun:agents.${pane_id}" -p -J 2>/dev/null | grep -v '^$' | tail -1)

            if echo "$last_line" | grep -qE '[\$#>] *$'; then
                log "ALERT: CLI process for ${agent} appears dead (shell prompt visible)"
                bash "${SCRIPT_DIR}/scripts/inbox_write.sh" karo \
                    "health_alert: CLI process for ${agent} appears dead. Shell prompt visible. May need restart." \
                    health_alert health_check
            fi
        fi
    fi
}

# --- メインループ ---
log "Health check daemon started (interval: ${INTERVAL}s, task_timeout: ${TASK_TIMEOUT}min, inbox_timeout: ${INBOX_TIMEOUT}min)"
log "Monitored agents: ${MONITORED_AGENTS[*]}"

while true; do
    # tmuxセッションが存在するか確認
    if ! tmux has-session -t shogun 2>/dev/null; then
        log "shogun session not found. Waiting..."
        sleep "$INTERVAL"
        continue
    fi

    for agent in "${MONITORED_AGENTS[@]}"; do
        # 各チェックはエラーを吐いても止まらない
        check_task_stalled "$agent" || true
        check_inbox_backlog "$agent" || true
        check_watcher_alive "$agent" || true
        check_pane_alive "$agent" || true
    done

    # 家老のwatcherも確認（karo自身は監視対象外だがwatcherは必要）
    check_watcher_alive "karo" || true

    sleep "$INTERVAL"
done
