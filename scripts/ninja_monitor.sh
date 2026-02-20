#!/bin/bash
# ninja_monitor.sh — 忍者idle検知デーモン
# Usage: bash scripts/ninja_monitor.sh
#
# 忍者がタスク完了してidle状態になったことを自動検知し、
# 家老(karo)のinboxに通知するバックグラウンドデーモン。
#
# 検知ロジック (二段階):
#   1. @agent_state変数ベース判定（優先）:
#      - @agent_state == "idle" → IDLE
#      - @agent_state == "active" (等) → BUSY
#      - @agent_state 未設定 → フォールバックへ
#   2. フォールバック: tmux capture-pane でプロンプト待ちを検出
#
# 二段階確認 (Phase 1/2):
#   Phase 1: 全忍者を高速スキャン → BUSY/maybe-idle に分類
#   Phase 2: maybe-idle の忍者を CONFIRM_WAIT 秒後に再確認
#   → 両方idleなら CONFIRMED IDLE（APIコール間の一瞬のプロンプト表示を除外）
#
# BUSYパターン (フォールバック時):
#   - "esc to interrupt" — Claude Code処理中のステータスバー表示
#   - "Running" — ツール実行中
#   - "Streaming" — ストリーミング出力中
#   - "background terminal running" — Codex CLIバックグラウンドターミナル稼働中
# IDLEパターン (フォールバック時):
#   - ❯ プロンプト表示（Claude Code）+ BUSYパターンなし
#   - › プロンプト表示（Codex CLI）+ BUSYパターンなし

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/ninja_monitor.log"
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"

POLL_INTERVAL=20    # ポーリング間隔（秒）
CONFIRM_WAIT=5      # idle確認待ち（秒）— Phase 2a base wait
STALL_THRESHOLD_MIN=15 # 停滞検知しきい値（分）— assigned+idle状態がこの時間継続で通知
STALE_CMD_THRESHOLD=14400 # stale cmd検知しきい値（秒）— pending+subtask未配備が4時間継続で通知
REDISCOVER_EVERY=30 # N回ポーリングごとにペイン再探索

# Self-restart on script change (inbox_watcher.shから移植)
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_HASH="$(md5sum "$SCRIPT_PATH" | cut -d' ' -f1)"
STARTUP_TIME="$(date +%s)"
MIN_UPTIME=10  # minimum seconds before allowing auto-restart

# 監視対象の忍者名リスト（karoと将軍は対象外）
NINJA_NAMES=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

log "ninja_monitor started. Monitoring ${#NINJA_NAMES[@]} ninja."
log "Poll interval: ${POLL_INTERVAL}s, Confirm wait: ${CONFIRM_WAIT}s"
log "CLI profiles loaded from cli_profiles.yaml via cli_lookup.sh"

# ─── デバウンス・状態管理（連想配列、bash 4+） ───
declare -A LAST_NOTIFIED  # 最終通知時刻（epoch秒）
declare -A PREV_STATE     # 前回の状態: busy / idle / unknown
declare -A PANE_TARGETS   # 忍者名 → tmuxペインターゲット
declare -A LAST_CLEARED   # 最終/clear送信時刻（epoch秒）
declare -A STALL_FIRST_SEEN  # 停滞初回検知時刻（epoch秒）— assigned+idleを初めて観測した時刻
declare -A STALL_NOTIFIED    # 停滞通知済みフラグ — key: "ninja:task_id", value: "1"
declare -A STALE_CMD_NOTIFIED  # stale cmd最終通知時刻 — key: "cmd_XXX", value: epoch秒
declare -A PENDING_CMD_NUDGE_COUNT  # pending cmd再起動nudge回数 — key: "cmd_XXX", value: count
declare -A PENDING_CMD_LAST_NUDGE   # pending cmd最終nudge時刻 — key: "cmd_XXX", value: epoch秒
declare -A CLEAR_SKIP_COUNT   # CLEAR-SKIPカウンタ — 忍者ごとの連続回数（AC3: ログ抑制用）
declare -A DESTRUCTIVE_WARN_LAST  # 破壊コマンド検知 — key: "ninja:pattern_id", value: epoch秒
declare -A RENUDGE_COUNT          # 未読再nudgeカウンター — key: agent_name, value: 連続再nudge回数
PREV_PANE_MISSING=""              # ペイン消失 — 前回の消失忍者リスト（重複送信防止）

# 案A: PREV_STATE初期化（起動直後のidle→idle通知を防止）
for name in "${NINJA_NAMES[@]}"; do
    PREV_STATE[$name]="idle"
done

MAX_RENUDGE=5               # 未読再nudge上限回数（同一未読状態に対して）
MAX_PENDING_NUDGE=5         # pending cmd同一cmd再起動nudge上限回数
KARO_CLEAR_DEBOUNCE=120     # 家老/clear再送信抑制（2分）— /clear復帰~30秒のため
STALE_CMD_DEBOUNCE=1800     # stale cmd同一cmd再通知抑制（30分）
PENDING_NUDGE_DEBOUNCE=300  # pending cmd同一cmd再起動nudge抑制（5分）
DESTRUCTIVE_DEBOUNCE=300    # 破壊コマンド同一パターン連続通知抑制（5分=300秒）
SHOGUN_ALERT_DEBOUNCE=1800  # 将軍CTXアラート再送信抑制（30分）— 殿を煩わせない

LAST_KARO_CLEAR=0           # 家老の最終/clear送信時刻（epoch秒）
LAST_SHOGUN_ALERT=0         # 将軍の最終アラート送信時刻（epoch秒）

# ─── ペインターゲット探索 ───
# tmuxの@agent_idからペインターゲットを動的に解決
discover_panes() {
    local mapping
    mapping=$(tmux list-panes -t shogun -a -F '#{window_index}.#{pane_index} #{@agent_id}' 2>/dev/null)

    if [ -z "$mapping" ]; then
        log "ERROR: Failed to list tmux panes"
        return 1
    fi

    local found=0
    for name in "${NINJA_NAMES[@]}"; do
        local target
        target=$(echo "$mapping" | grep " ${name}$" | awk '{print $1}')
        if [ -n "$target" ]; then
            PANE_TARGETS[$name]="shogun:${target}"
            found=$((found + 1))
        fi
    done

    log "Pane discovery: ${found}/${#NINJA_NAMES[@]} ninja found"
}

# ─── ペイン生存チェック (cmd_183) ───
# 期待される忍者ペインと実ペインを比較し、消失を検知して家老に通知
check_pane_survival() {
    local actual_agents
    actual_agents=$(tmux list-panes -t shogun:2 -F '#{@agent_id}' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$actual_agents" ]; then
        log "PANE-CHECK: Failed to list panes for shogun:2"
        return
    fi

    local missing=()
    for name in "${NINJA_NAMES[@]}"; do
        if ! echo "$actual_agents" | grep -qx "$name"; then
            missing+=("$name")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        # 全員生存 — 前回消失状態をリセット
        if [ -n "$PREV_PANE_MISSING" ]; then
            log "PANE-RECOVERED: all ninja panes restored (was: $PREV_PANE_MISSING)"
            PREV_PANE_MISSING=""
        fi
        return
    fi

    # 消失リスト構築
    local missing_str
    missing_str=$(printf '%s,' "${missing[@]}")
    missing_str="${missing_str%,}"

    # 重複送信防止: 前回と同じ消失状態なら再送しない
    if [ "$missing_str" = "$PREV_PANE_MISSING" ]; then
        return
    fi

    log "PANE-LOST: ${missing_str} (${#missing[@]}名消失)"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "ペイン消失: ${missing_str} (${#missing[@]}名)。OOM Kill等の可能性。tmux list-panes -t shogun:2 で確認されたし" pane_lost ninja_monitor >> "$LOG" 2>&1
    PREV_PANE_MISSING="$missing_str"
}

# ─── idle検出（単一チェック） ───
# 戻り値: 0=IDLE, 1=BUSY, 2=ERROR
# $1: pane_target, $2: agent_name（省略時はフォールバックパターン使用）
check_idle() {
    local pane_target="$1"
    local agent_name="$2"

    # ─── Primary: @agent_state変数ベース判定（フックが設定） ───
    local agent_state
    agent_state=$(tmux display-message -t "$pane_target" -p '#{@agent_state}' 2>/dev/null)

    if [ -n "$agent_state" ]; then
        if [ "$agent_state" = "idle" ]; then
            return 0  # IDLE（@agent_state確定）
        else
            return 1  # BUSY（active等 — @agent_state確定）
        fi
    fi

    # ─── Fallback: capture-paneベース判定（@agent_state未設定時） ───
    local output
    output=$(tmux capture-pane -t "$pane_target" -p -S -8 2>/dev/null)
    if [ $? -ne 0 ]; then
        return 2  # ペイン取得失敗
    fi

    # BUSYパターン検出（cli_profiles.yamlから取得）
    local busy_pat
    if [ -n "$agent_name" ]; then
        busy_pat=$(cli_profile_get "$agent_name" "busy_patterns")
    fi
    if [ -z "$busy_pat" ]; then
        busy_pat="esc to interrupt|Running|Streaming|background terminal running"
    fi
    if echo "$output" | grep -qE "$busy_pat"; then
        return 1  # BUSY
    fi

    # IDLEプロンプト検出（cli_profiles.yamlから取得）
    local idle_pat
    if [ -n "$agent_name" ]; then
        idle_pat=$(cli_profile_get "$agent_name" "idle_pattern")
    fi
    if [ -z "$idle_pat" ]; then
        idle_pat="❯|›"
    fi
    if echo "$output" | grep -qE "$idle_pat"; then
        return 0  # IDLE候補（要二段階確認）
    fi

    return 1  # デフォルトはBUSY（安全側 — 誤検知防止）
}

# ─── CTX%取得（多重ソース） ───
# @context_pct変数 → capture-pane出力 → 0(不明)
# $1: pane_target, $2: agent_name（省略時はフォールバックパターン使用）
get_context_pct() {
    local pane_target="$1"
    local agent_name="$2"
    local ctx_val ctx_num

    # Source 1: tmux pane variable (@context_pct)
    ctx_val=$(tmux show-options -p -t "$pane_target" -v @context_pct 2>/dev/null)
    ctx_num=$(echo "$ctx_val" | grep -oE '[0-9]+' | tail -1)
    if [ -n "$ctx_num" ] && [ "$ctx_num" -gt 0 ] 2>/dev/null; then
        echo "$ctx_num"
        return 0
    fi

    # Source 2: Parse CTX from capture-pane output (statusline display)
    local output
    output=$(tmux capture-pane -t "$pane_target" -p -S -5 2>/dev/null)

    # cli_profiles.yamlからパターンとモードを取得
    local ctx_pattern ctx_mode
    if [ -n "$agent_name" ]; then
        ctx_pattern=$(cli_profile_get "$agent_name" "ctx_pattern")
        ctx_mode=$(cli_profile_get "$agent_name" "ctx_mode")
    fi

    if [ -n "$ctx_pattern" ]; then
        if [ "$ctx_mode" = "usage" ]; then
            # usage モード（例: "CTX:XX%"）— 値をそのまま使用
            ctx_num=$(echo "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
            if [ -n "$ctx_num" ]; then
                tmux set-option -p -t "$pane_target" @context_pct "${ctx_num}%" 2>/dev/null
                echo "$ctx_num"
                return 0
            fi
        elif [ "$ctx_mode" = "remaining" ]; then
            # remaining モード（例: "XX% context left"）— usage%に変換
            local remaining
            remaining=$(echo "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
            if [ -n "$remaining" ]; then
                ctx_num=$((100 - remaining))
                tmux set-option -p -t "$pane_target" @context_pct "${ctx_num}%" 2>/dev/null
                echo "$ctx_num"
                return 0
            fi
        fi
    else
        # フォールバック: agent_name未指定時は両パターン試行
        ctx_num=$(echo "$output" | grep -oE 'CTX:[0-9]+%' | tail -1 | grep -oE '[0-9]+')
        if [ -n "$ctx_num" ]; then
            tmux set-option -p -t "$pane_target" @context_pct "${ctx_num}%" 2>/dev/null
            echo "$ctx_num"
            return 0
        fi

        local remaining
        remaining=$(echo "$output" | grep -oE '[0-9]+% context left' | tail -1 | grep -oE '[0-9]+')
        if [ -n "$remaining" ]; then
            ctx_num=$((100 - remaining))
            tmux set-option -p -t "$pane_target" @context_pct "${ctx_num}%" 2>/dev/null
            echo "$ctx_num"
            return 0
        fi
    fi

    echo "0"
    return 1
}

# ─── AC1: 報告YAML完了判定 + タスクYAML自動done更新 ───
# 報告YAMLのparent_cmdがタスクと一致し、status=doneなら自動更新
# 戻り値: 0=完了済み(auto-done実行), 1=未完了
check_and_update_done_task() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local report_file="$SCRIPT_DIR/queue/reports/${name}_report.yaml"

    # 報告ファイル存在確認
    [ ! -f "$report_file" ] && return 1

    # タスクのparent_cmdを取得
    local task_parent_cmd
    task_parent_cmd=$(grep -m1 'parent_cmd:' "$task_file" 2>/dev/null | awk '{print $2}')
    [ -z "$task_parent_cmd" ] && return 1

    # 報告のparent_cmdを取得
    local report_parent_cmd
    report_parent_cmd=$(grep -m1 'parent_cmd:' "$report_file" 2>/dev/null | awk '{print $2}')
    [ -z "$report_parent_cmd" ] && return 1

    # parent_cmd一致チェック
    [ "$task_parent_cmd" != "$report_parent_cmd" ] && return 1

    # 報告のstatus確認（done/completed/success を完了とみなす）
    local report_status
    report_status=$(grep -m1 '^status:' "$report_file" 2>/dev/null | awk '{print $2}')
    case "$report_status" in
        done|completed|success)
            # 完了確認 — タスクYAMLをdoneに自動更新（flock排他制御）
            local lock_file="/tmp/task_${name}.lock"
            (
                flock -x -w 5 200 || { log "ERROR: Failed to acquire lock for $name task update"; return 1; }
                sed -i "s/status:\s*\(assigned\|in_progress\)/status: done/" "$task_file"
            ) 200>"$lock_file"
            if [ $? -ne 0 ]; then
                return 1
            fi
            log "AUTO-DONE: $name task auto-updated to done (report parent_cmd=$report_parent_cmd, status=$report_status)"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ─── 案E: タスク配備済み判定（二重チェック: YAML + ペイン実態 + 報告YAML） ───
is_task_deployed() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    if [ -f "$task_file" ]; then
        if grep -qE 'status:\s*(assigned|in_progress)' "$task_file" 2>/dev/null; then
            # AC1/AC2: 報告YAML完了チェック（parent_cmd一致+status:done）
            if check_and_update_done_task "$name"; then
                return 1  # 完了済み — not deployed
            fi

            # YAML says active — cross-check with actual pane state
            local target="${PANE_TARGETS[$name]}"
            if [ -n "$target" ]; then
                local pane_idle=false
                local task_empty=false

                # Check if pane shows idle prompt
                check_idle "$target" "$name"
                if [ $? -eq 0 ]; then
                    pane_idle=true
                fi

                # Check if @current_task is empty
                local current_task
                current_task=$(tmux display-message -t "$target" -p '#{@current_task}' 2>/dev/null)
                if [ -z "$current_task" ]; then
                    task_empty=true
                fi

                # Both idle → stale task (YAML not updated after completion)
                if $pane_idle && $task_empty; then
                    local yaml_status
                    yaml_status=$(grep -oE 'status:\s*(assigned|in_progress)' "$task_file" 2>/dev/null | head -1 | awk -F': *' '{print $2}')
                    log "STALE-TASK: $name has YAML status=$yaml_status but pane is idle, treating as not deployed"
                    return 1  # Stale — treat as not deployed
                fi
            fi
            return 0  # タスク配備済み（active or ペインチェック不可）
        fi
        # Bug2 fix: status=done but @current_task still set → clear it
        if grep -qE 'status:\s*done' "$task_file" 2>/dev/null; then
            local target="${PANE_TARGETS[$name]}"
            if [ -n "$target" ]; then
                local current_task
                current_task=$(tmux display-message -t "$target" -p '#{@current_task}' 2>/dev/null)
                if [ -n "$current_task" ]; then
                    tmux set-option -p -t "$target" @current_task "" 2>/dev/null
                    log "TASK-CLEAR: $name @current_task cleared (task status=done, was: $current_task)"
                fi
            fi
        fi
    fi
    return 1  # 未配備
}

# ─── 通知処理 ───
notify_idle() {
    local name="$1"
    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "${name}がidle状態。タスク割り当て可能でござる。" ninja_idle ninja_monitor >> "$LOG" 2>&1; then
        log "Notification sent to karo: $name idle"
        LAST_NOTIFIED[$name]=$(date +%s)
        return 0
    else
        log "ERROR: Failed to send notification for $name"
        return 1
    fi
}

# ─── 案B: バッチ通知処理 ───
notify_idle_batch() {
    local -a names=("$@")
    if [ ${#names[@]} -eq 0 ]; then return 0; fi

    # 各忍者のCTX%と最終タスクIDを収集
    local details=""
    for name in "${names[@]}"; do
        local target="${PANE_TARGETS[$name]}"
        local ctx=$(get_context_pct "$target" "$name")
        local last_task=$(grep -m1 'task_id:' "$SCRIPT_DIR/queue/tasks/${name}.yaml" 2>/dev/null | awk '{print $2}')
        details="${details}${name}(CTX:${ctx}%,last:${last_task}), "
    done
    details="${details%, }"  # 末尾カンマ除去

    local msg="idle(新規): ${details}。計${#names[@]}名タスク割り当て可能。"
    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$msg" ninja_idle ninja_monitor >> "$LOG" 2>&1; then
        log "Batch notification sent to karo: ${names[*]}"
        local now=$(date +%s)
        for name in "${names[@]}"; do
            LAST_NOTIFIED[$name]=$now
        done
        return 0
    else
        log "ERROR: Failed to send batch notification"
        return 1
    fi
}

# ─── idle→通知の処理（状態遷移+デバウンス） ───
handle_confirmed_idle() {
    local name="$1"

    # 案E: タスク配備済みならidle通知もauto-clearもスキップ
    if is_task_deployed "$name"; then
        log "TASK-DEPLOYED: $name has assigned/in_progress task, skip idle notification and auto-clear"
        PREV_STATE[$name]="busy"  # タスクがあるならbusy扱いを維持
        return
    fi

    local now
    now=$(date +%s)

    # ─── 通知（busy→idle遷移時のみ） ───
    if [ "${PREV_STATE[$name]}" != "idle" ]; then
        local last elapsed debounce_time
        last="${LAST_NOTIFIED[$name]:-0}"
        elapsed=$((now - last))

        debounce_time=$(cli_profile_get "$name" "debounce")

        if [ $elapsed -ge $debounce_time ]; then
            log "IDLE confirmed: $name"
            NEWLY_IDLE+=("$name")
        else
            log "DEBOUNCE: $name idle but ${elapsed}s < ${debounce_time}s since last notify"
        fi
    fi

    # ─── idle時自動/clear（毎サイクル判定、状態遷移に依存しない） ───
    local target agent_id clear_last clear_elapsed
    target="${PANE_TARGETS[$name]}"
    if [ -n "$target" ]; then
        agent_id=$(tmux display-message -t "$target" -p '#{@agent_id}' 2>/dev/null)

        # CTX=0%なら既にクリア済み → スキップ（無駄な再clearループ防止）
        local ctx_now
        ctx_now=$(get_context_pct "$target" "$name")
        if [ "${ctx_now:-0}" -le 0 ] 2>/dev/null; then
            # AC3: CLEAR-SKIPカウンタ — 連続10回超で5分間隔ログ
            CLEAR_SKIP_COUNT[$name]=$(( ${CLEAR_SKIP_COUNT[$name]:-0} + 1 ))
            local skip_count=${CLEAR_SKIP_COUNT[$name]}
            if [ $skip_count -le 10 ]; then
                log "CLEAR-SKIP: $name CTX=${ctx_now}%, already clean (${skip_count}/10)"
            elif [ $(( skip_count % 15 )) -eq 0 ]; then
                # 15サイクル=300秒(5分)ごとにログ出力
                log "CLEAR-SKIP: $name CTX=${ctx_now}%, already clean (continuous: ${skip_count})"
            fi
        else
            # CTX>0%に変化 → カウンタリセット
            CLEAR_SKIP_COUNT[$name]=0
            clear_last="${LAST_CLEARED[$name]:-0}"
            clear_elapsed=$((now - clear_last))

            # CLI種別に応じたデバウンス（cli_profiles.yaml参照）
            local effective_debounce
            effective_debounce=$(cli_profile_get "$agent_id" "clear_debounce")

            if [ $clear_elapsed -ge $effective_debounce ]; then
                local reset_cmd
                reset_cmd=$(cli_profile_get "$name" "clear_cmd")
                log "AUTO-CLEAR: $name idle+no_task CTX=${ctx_now}%, sending $reset_cmd"
                tmux send-keys -t "$target" "$reset_cmd"
                sleep 0.3
                tmux send-keys -t "$target" Enter
                LAST_CLEARED[$name]=$now
                # AC4: @current_taskをクリア（次ポーリングでis_task_deployed()がfalseを返すように）
                tmux set-option -p -t "$target" @current_task "" 2>/dev/null
            else
                log "CLEAR-DEBOUNCE: $name idle+no_task but ${clear_elapsed}s < ${effective_debounce}s since last /clear"
            fi
        fi
    fi

    PREV_STATE[$name]="idle"
}

# ─── busy検出処理 ───
handle_busy() {
    local name="$1"

    if [ "${PREV_STATE[$name]}" = "idle" ]; then
        log "ACTIVE: $name resumed work"
    fi
    PREV_STATE[$name]="busy"
    # 作業再開 → 停滞追跡リセット
    unset STALL_FIRST_SEEN[$name]
}

# ─── 停滞検知（assigned+idle+15分超） ───
# 忍者がタスクassigned後にペインがidle状態のまま放置された場合、家老に通知
check_stall() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"

    # タスクファイルなし → 追跡リセット
    if [ ! -f "$task_file" ]; then
        unset STALL_FIRST_SEEN[$name]
        return
    fi

    # status: assigned 以外は対象外
    local status task_id
    status=$(grep -m1 'status:' "$task_file" 2>/dev/null | awk '{print $2}')
    task_id=$(grep -m1 'task_id:' "$task_file" 2>/dev/null | awk '{print $2}')

    if [ "$status" != "assigned" ]; then
        unset STALL_FIRST_SEEN[$name]
        return
    fi

    # 同一ninja×同一task_idで通知済みならスキップ（重複防止）
    local stall_key="${name}:${task_id}"
    if [ "${STALL_NOTIFIED[$stall_key]}" = "1" ]; then
        return
    fi

    # ペインがidleか確認
    local target="${PANE_TARGETS[$name]}"
    if [ -z "$target" ]; then return; fi

    check_idle "$target" "$name"
    if [ $? -ne 0 ]; then
        # busy状態 → 停滞追跡リセット
        unset STALL_FIRST_SEEN[$name]
        return
    fi

    # assigned + idle → 停滞追跡開始 or 経過確認
    local now=$(date +%s)
    if [ -z "${STALL_FIRST_SEEN[$name]}" ]; then
        STALL_FIRST_SEEN[$name]=$now
        log "STALL-WATCH: $name has assigned task $task_id and is idle (tracking started)"
        return
    fi

    local first_seen=${STALL_FIRST_SEEN[$name]}
    local elapsed_min=$(( (now - first_seen) / 60 ))

    if [ $elapsed_min -ge $STALL_THRESHOLD_MIN ]; then
        log "STALL-DETECTED: $name stalled on $task_id for ${elapsed_min}min, notifying karo"
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "${name}が${task_id}で${elapsed_min}分停滞" stall_alert ninja_monitor >> "$LOG" 2>&1
        STALL_NOTIFIED[$stall_key]="1"
        unset STALL_FIRST_SEEN[$name]
    fi
}

# ─── stale cmd検知（pending+4時間超+subtask未配備） ───
# queue/shogun_to_karo.yaml から pending cmd を抽出し、
# queue/tasks/*.yaml に parent_cmd が存在しないまま4時間超過したcmdを家老に通知
list_pending_cmds() {
    local cmd_file="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ ! -f "$cmd_file" ] && return

    awk '
        function emit() {
            if (cmd_id != "" && cmd_status == "pending" && cmd_ts != "") {
                print cmd_id "|" cmd_ts
            }
        }
        /^[[:space:]]*-[[:space:]]id:/ {
            emit()
            cmd_id=$3
            gsub(/"/, "", cmd_id)
            cmd_ts=""
            cmd_status=""
            next
        }
        /^[[:space:]]*timestamp:/ {
            cmd_ts=$2
            gsub(/"/, "", cmd_ts)
            next
        }
        /^[[:space:]]*status:/ {
            cmd_status=$2
            next
        }
        END {
            emit()
        }
    ' "$cmd_file"
}

check_stale_cmds() {
    local now
    now=$(date +%s)

    while IFS='|' read -r cmd_id cmd_timestamp; do
        [ -z "$cmd_id" ] && continue
        [ -z "$cmd_timestamp" ] && continue

        # デバウンス: 同一cmdの再通知を30分間隔で抑制
        local last_stale_notify="${STALE_CMD_NOTIFIED[$cmd_id]:-0}"
        if [ $((now - last_stale_notify)) -lt $STALE_CMD_DEBOUNCE ]; then
            continue
        fi

        local cmd_epoch
        cmd_epoch=$(date -d "$cmd_timestamp" +%s 2>/dev/null)
        if [ -z "$cmd_epoch" ]; then
            log "WARN: Failed to parse cmd timestamp: ${cmd_id} ts=${cmd_timestamp}"
            continue
        fi

        local elapsed_sec
        elapsed_sec=$((now - cmd_epoch))
        if [ $elapsed_sec -lt $STALE_CMD_THRESHOLD ]; then
            continue
        fi

        # subtask存在確認: queue/tasks/*.yaml の parent_cmd を照合
        if rg -l --glob '*.yaml' "parent_cmd:\\s*${cmd_id}\\b" "$SCRIPT_DIR/queue/tasks" >/dev/null 2>&1; then
            continue
        fi

        local elapsed_hour
        elapsed_hour=$((elapsed_sec / 3600))
        local msg="${cmd_id}が${elapsed_hour}時間pendingのまま。将軍に確認せよ"

        log "STALE-CMD: ${cmd_id} pending ${elapsed_hour}h with no subtasks, notifying karo"
        if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$msg" stale_cmd ninja_monitor >> "$LOG" 2>&1; then
            STALE_CMD_NOTIFIED[$cmd_id]=$now
        else
            log "ERROR: Failed to send stale cmd notification for ${cmd_id}"
        fi
    done < <(list_pending_cmds)
}

# ─── pending cmd検知（idle家老の自動再起動） ───
# cmdがpendingの間、家老がidleなら inbox_write(cmd_pending)で再起動nudge
# 同一cmdへの無限nudgeは回数上限+デバウンスで抑制
check_karo_pending_cmd() {
    local karo_pane="shogun:2.1"

    # 家老がbusyならスキップ（作業中は割り込み不要）
    check_idle "$karo_pane" "karo"
    if [ $? -ne 0 ]; then
        return
    fi

    local now
    now=$(date +%s)
    local pending_ids=()

    while IFS='|' read -r cmd_id cmd_timestamp; do
        [ -z "$cmd_id" ] && continue
        pending_ids+=("$cmd_id")

        # stale通知済みcmdは重複通知を避ける
        if [ -n "${STALE_CMD_NOTIFIED[$cmd_id]:-}" ]; then
            continue
        fi

        local count="${PENDING_CMD_NUDGE_COUNT[$cmd_id]:-0}"
        if [ "$count" -ge "$MAX_PENDING_NUDGE" ]; then
            continue
        fi

        local last_sent="${PENDING_CMD_LAST_NUDGE[$cmd_id]:-0}"
        if [ $((now - last_sent)) -lt $PENDING_NUDGE_DEBOUNCE ]; then
            continue
        fi

        local msg="cmd_pending ${cmd_id} pending cmd検知: ${cmd_id}。shogun_to_karo.yamlを確認し着手せよ。"
        if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$msg" cmd_pending ninja_monitor >> "$LOG" 2>&1; then
            PENDING_CMD_NUDGE_COUNT[$cmd_id]=$((count + 1))
            PENDING_CMD_LAST_NUDGE[$cmd_id]=$now
            log "PENDING-CMD-NUDGE: ${cmd_id} -> karo (${PENDING_CMD_NUDGE_COUNT[$cmd_id]}/${MAX_PENDING_NUDGE})"
        else
            log "ERROR: Failed pending cmd nudge for ${cmd_id}"
        fi
    done < <(list_pending_cmds)

    # pending解消済みcmdのカウンタをリセット
    local tracked_id still_pending pending_id
    for tracked_id in "${!PENDING_CMD_NUDGE_COUNT[@]}"; do
        still_pending=0
        for pending_id in "${pending_ids[@]}"; do
            if [ "$tracked_id" = "$pending_id" ]; then
                still_pending=1
                break
            fi
        done
        if [ $still_pending -eq 0 ]; then
            unset PENDING_CMD_NUDGE_COUNT[$tracked_id]
            unset PENDING_CMD_LAST_NUDGE[$tracked_id]
            log "PENDING-CMD-RESET: ${tracked_id} no longer pending, counters cleared"
        fi
    done
}

# 互換ラッパー（旧命名）
check_karo_pending() {
    check_karo_pending_cmd
}

# ─── 破壊コマンド検知（capture-pane経由） ───
# capture-pane出力からD001-D008相当の危険コマンドを検知し、家老にWARN通知
# 検知のみ（ブロックはしない）。同一パターンは5分間隔で通知抑制。
check_destructive_commands() {
    local name="$1"
    local target="$2"

    local output
    output=$(tmux capture-pane -t "$target" -p -S -20 2>/dev/null)
    [ -z "$output" ] && return

    local now
    now=$(date +%s)
    local patterns=()

    # Pattern 1: rm -rf + PJ外パス（/mnt/c/Windows, /mnt/c/Users, /home, /, ~ 等）
    if echo "$output" | grep -qE 'rm\s+-rf\s+(/mnt/c/(Windows|Users|Program)|/home|/\s|/\.|~)'; then
        patterns+=("rm-rf-outside-project")
    fi

    # Pattern 2: git push --force（ただし--force-with-leaseを除外）
    if echo "$output" | grep -E 'git\s+push.*--force' 2>/dev/null | grep -qv 'force-with-lease'; then
        patterns+=("git-push-force")
    fi

    # Pattern 3: sudo コマンド
    if echo "$output" | grep -qE '(^|[[:space:]])sudo[[:space:]]'; then
        patterns+=("sudo")
    fi

    # Pattern 4: kill / killall / pkill コマンド
    if echo "$output" | grep -qE '(^|[[:space:]])(kill|killall|pkill)[[:space:]]'; then
        patterns+=("kill-command")
    fi

    # Pattern 5: pipe-to-shell（curl|bash, wget|sh）
    if echo "$output" | grep -qE 'curl.*\|.*bash|wget.*\|.*sh'; then
        patterns+=("pipe-to-shell")
    fi

    # 検知パターンごとにデバウンスチェック+通知
    for pattern in "${patterns[@]}"; do
        local key="${name}:${pattern}"
        local last="${DESTRUCTIVE_WARN_LAST[$key]:-0}"
        local elapsed=$((now - last))

        if [ $elapsed -lt $DESTRUCTIVE_DEBOUNCE ]; then
            log "DESTRUCTIVE-DEBOUNCE: $name '${pattern}' (${elapsed}s < ${DESTRUCTIVE_DEBOUNCE}s)"
            continue
        fi

        log "DESTRUCTIVE-WARN: $name detected '${pattern}'"
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "${name}が危険コマンド検知: ${pattern}" destructive_warn ninja_monitor >> "$LOG" 2>&1
        DESTRUCTIVE_WARN_LAST[$key]=$now
    done
}

# ─── 未読放置検知+再nudge (cmd_188) ───
# idle状態のエージェントのinboxに未読メッセージがある場合、再nudgeを送信
# inbox_watcherのnudgeが一発きりで消失する構造問題への対策
count_unread_messages() {
    local inbox_file="$1"
    local raw_count
    local count

    raw_count=$(awk '/read:[[:space:]]*false/{c++} END{print c+0}' "$inbox_file" 2>/dev/null || echo "0")
    count=$(printf '%s' "$raw_count" | tr -d '\r\n[:space:]')

    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        count=0
    fi

    echo "$count"
}

check_inbox_renudge() {
    local all_agents=("karo" "${NINJA_NAMES[@]}")

    for name in "${all_agents[@]}"; do
        local inbox_file="$SCRIPT_DIR/queue/inbox/${name}.yaml"

        # inbox file存在チェック
        if [ ! -f "$inbox_file" ]; then
            RENUDGE_COUNT[$name]=0
            continue
        fi

        # 未読メッセージ数をカウント
        local unread_count
        unread_count=$(count_unread_messages "$inbox_file")
        # 防御: 非数値は0に強制変換
        [[ ! "$unread_count" =~ ^[0-9]+$ ]] && unread_count=0

        # 未読0 → カウンターリセット＆スキップ
        if [ "$unread_count" -eq 0 ]; then
            if [ "${RENUDGE_COUNT[$name]:-0}" -gt 0 ]; then
                log "RENUDGE-RESET: $name unread=0, counter reset (was ${RENUDGE_COUNT[$name]})"
            fi
            RENUDGE_COUNT[$name]=0
            continue
        fi

        # ペインターゲット取得
        local target
        if [ "$name" = "karo" ]; then
            target="shogun:2.1"
        else
            target="${PANE_TARGETS[$name]}"
        fi
        [ -z "$target" ] && continue

        # idle判定（busy → skip：作業中はいずれinboxを処理する）
        check_idle "$target" "$name"
        if [ $? -ne 0 ]; then
            continue
        fi

        # idle + 未読あり → 再nudge候補
        local count="${RENUDGE_COUNT[$name]:-0}"

        if [ "$count" -ge "$MAX_RENUDGE" ]; then
            # 上限到達 → ログのみ（5サイクルに1回、スパム防止）
            if [ $((cycle % 5)) -eq 0 ]; then
                log "RENUDGE-MAX: $name reached MAX_RENUDGE=$MAX_RENUDGE (unread=$unread_count), manual intervention needed"
            fi
            continue
        fi

        # 再nudge送信（二重ガード: unread>0でなければ絶対に送らない）
        if [ "$unread_count" -gt 0 ] 2>/dev/null; then
            log "RENUDGE: $name idle+unread=$unread_count, sending inbox${unread_count} (attempt $((count+1))/$MAX_RENUDGE)"
            tmux send-keys -t "$target" "inbox${unread_count}" Enter
        else
            log "RENUDGE-GUARD: $name unread=$unread_count blocked by double-guard"
            RENUDGE_COUNT[$name]=0
            continue
        fi
        RENUDGE_COUNT[$name]=$((count + 1))
    done
}

# ─── context_pct更新（単一ペイン） ───
# 引数: $1=pane_target (例: shogun:2.4), $2=agent_name（省略時はフォールバック）
# 戻り値: 0=更新成功, 1=失敗(--設定)
update_context_pct() {
    local pane_target="$1"
    local agent_name="$2"
    local output
    local context_pct="--"

    output=$(tmux capture-pane -t "$pane_target" -p -S -10 2>/dev/null)
    if [ $? -ne 0 ]; then
        tmux set-option -p -t "$pane_target" @context_pct "$context_pct" 2>/dev/null
        return 1
    fi

    # cli_profiles.yamlからパターンとモードを取得
    local ctx_pattern ctx_mode
    if [ -n "$agent_name" ]; then
        ctx_pattern=$(cli_profile_get "$agent_name" "ctx_pattern")
        ctx_mode=$(cli_profile_get "$agent_name" "ctx_mode")
    fi

    if [ -n "$ctx_pattern" ]; then
        if [ "$ctx_mode" = "usage" ]; then
            local match
            match=$(echo "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
            if [ -n "$match" ]; then
                context_pct="${match}%"
            fi
        elif [ "$ctx_mode" = "remaining" ]; then
            local remaining
            remaining=$(echo "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
            if [ -n "$remaining" ]; then
                context_pct="$((100 - remaining))%"
            fi
        fi
    else
        # フォールバック: 両パターン試行
        if echo "$output" | grep -qE 'CTX:[0-9]+%'; then
            context_pct=$(echo "$output" | grep -oE 'CTX:[0-9]+%' | tail -1 | sed 's/CTX://')
        elif echo "$output" | grep -qE '[0-9]+% context left'; then
            local remaining
            remaining=$(echo "$output" | grep -oE '[0-9]+% context left' | tail -1 | grep -oE '[0-9]+')
            context_pct="$((100 - remaining))%"
        fi
    fi

    # tmux変数に設定（全エージェント共通）
    tmux set-option -p -t "$pane_target" @context_pct "$context_pct" 2>/dev/null
    return 0
}

# ─── 全ペインのcontext_pct更新 ───
update_all_context_pct() {
    # 将軍ペイン（Window 1）
    local shogun_panes
    shogun_panes=$(tmux list-panes -t shogun:1 -F '1.#{pane_index}' 2>/dev/null)
    for pane_idx in $shogun_panes; do
        update_context_pct "shogun:$pane_idx" "shogun"
    done

    # 家老 + 忍者ペイン（Window 2）— @agent_idからCLI種別を解決
    while read -r pane_idx agent_id; do
        [ -z "$pane_idx" ] && continue
        update_context_pct "shogun:$pane_idx" "${agent_id:-}"
    done < <(tmux list-panes -t shogun:2 -F '2.#{pane_index} #{@agent_id}' 2>/dev/null)
}

# ─── STEP 1: ninja_states.yaml 自動生成 ───
write_state_file() {
    local state_file="$SCRIPT_DIR/queue/ninja_states.yaml"
    local lock_file="/tmp/ninja_states.lock"
    local timestamp=$(date '+%Y-%m-%dT%H:%M:%S')

    # flock排他制御（他プロセスが読み書きする可能性に備える）
    (
        flock -x 200

        # YAML生成
        echo "updated_at: \"$timestamp\"" > "$state_file"
        echo "agents:" >> "$state_file"

        # 家老
        local karo_pane="shogun:2.1"
        local karo_status="unknown"
        check_idle "$karo_pane" "karo" && karo_status="idle" || karo_status="busy"
        local karo_ctx=$(get_context_pct "$karo_pane" "karo")
        echo "  karo:" >> "$state_file"
        echo "    pane: \"$karo_pane\"" >> "$state_file"
        echo "    status: $karo_status" >> "$state_file"
        echo "    ctx_pct: $karo_ctx" >> "$state_file"
        echo "    last_task: \"\"" >> "$state_file"

        # 忍者
        for name in "${NINJA_NAMES[@]}"; do
            local target="${PANE_TARGETS[$name]}"
            if [ -z "$target" ]; then continue; fi

            local status="${PREV_STATE[$name]:-unknown}"
            local ctx=$(get_context_pct "$target" "$name")
            local last_task=$(grep -m1 'task_id:' "$SCRIPT_DIR/queue/tasks/${name}.yaml" 2>/dev/null | awk '{print $2}')
            [ -z "$last_task" ] && last_task=""

            echo "  ${name}:" >> "$state_file"
            echo "    pane: \"$target\"" >> "$state_file"
            echo "    status: $status" >> "$state_file"
            echo "    ctx_pct: $ctx" >> "$state_file"
            echo "    last_task: \"$last_task\"" >> "$state_file"
        done

    ) 200>"$lock_file"
}

# ─── 家老陣形図(karo_snapshot) — 家老/clear復帰用の圧縮状態 ───
write_karo_snapshot() {
    local snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
    local lock_file="/tmp/karo_snapshot.lock"
    local timestamp=$(date '+%Y-%m-%dT%H:%M:%S')

    (
        flock -x 200

        {
            echo "# 家老陣形図(karo_snapshot) — ninja_monitor.sh自動生成"
            echo "# Generated: $timestamp"

            # cmd状態: shogun_to_karo.yamlから全cmd
            local cmd_file="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
            if [ -f "$cmd_file" ]; then
                awk '
                    function emit() {
                        if (cmd_id != "") {
                            purpose_short = substr(cmd_purpose, 1, 40)
                            print "cmd|" cmd_id "|" cmd_status "|" purpose_short
                        }
                    }
                    /^[[:space:]]*-[[:space:]]id:/ {
                        emit()
                        cmd_id=$3; gsub(/"/, "", cmd_id)
                        cmd_status=""; cmd_purpose=""
                        next
                    }
                    /^[[:space:]]*status:/ { cmd_status=$2; next }
                    /^[[:space:]]*purpose:/ {
                        cmd_purpose=$0
                        sub(/^[[:space:]]*purpose:[[:space:]]*"?/, "", cmd_purpose)
                        sub(/"$/, "", cmd_purpose)
                        next
                    }
                    END { emit() }
                ' "$cmd_file"
            fi

            # 忍者task状態
            for name in "${NINJA_NAMES[@]}"; do
                local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
                if [ -f "$task_file" ]; then
                    local task_id status project
                    task_id=$(grep -m1 'task_id:' "$task_file" 2>/dev/null | awk '{print $2}')
                    status=$(grep -m1 'status:' "$task_file" 2>/dev/null | awk '{print $2}')
                    project=$(grep -m1 'project:' "$task_file" 2>/dev/null | awk '{print $2}')
                    echo "ninja|${name}|${task_id:-none}|${status:-idle}|${project:-none}"
                else
                    echo "ninja|${name}|none|idle|none"
                fi
            done

            # 報告状態
            for name in "${NINJA_NAMES[@]}"; do
                local report_file="$SCRIPT_DIR/queue/reports/${name}_report.yaml"
                if [ -f "$report_file" ]; then
                    local report_task report_status
                    report_task=$(grep -m1 'task_id:' "$report_file" 2>/dev/null | awk '{print $2}')
                    report_status=$(grep -m1 '^status:' "$report_file" 2>/dev/null | awk '{print $2}')
                    [ -n "$report_task" ] && echo "report|${name}|${report_task}|${report_status:-unknown}"
                fi
            done

            # idle一覧
            local idle_list=""
            for name in "${NINJA_NAMES[@]}"; do
                if [ "${PREV_STATE[$name]}" = "idle" ]; then
                    idle_list="${idle_list}${name},"
                fi
            done
            idle_list="${idle_list%,}"
            echo "idle|${idle_list:-none}"

        } > "$snapshot_file"

    ) 200>"$lock_file"
}

# ─── 家老/clear送信共通関数（全コードパスで使用） ───
# デバウンスを内蔵。呼び出し元がデバウンスを気にする必要なし。
# $1: ctx_num（ログ用）, $2: caller（ログ用、省略可）
# 戻り値: 0=送信成功, 1=デバウンスで抑制
send_karo_clear() {
    local ctx_num="${1:-?}"
    local caller="${2:-check_karo_clear}"
    local karo_pane="shogun:2.1"

    local now=$(date +%s)
    local elapsed=$((now - LAST_KARO_CLEAR))

    if [ $elapsed -lt $KARO_CLEAR_DEBOUNCE ]; then
        log "KARO-CLEAR-DEBOUNCE(${caller}): CTX:${ctx_num}% but ${elapsed}s < ${KARO_CLEAR_DEBOUNCE}s"
        return 1
    fi

    # 陣形図を最終更新（鮮度保証）
    write_karo_snapshot

    local clear_cmd
    clear_cmd=$(cli_profile_get "karo" "clear_cmd")
    log "KARO-CLEAR(${caller}): karo CTX:${ctx_num}%, sending ${clear_cmd}"
    tmux send-keys -t "$karo_pane" "$clear_cmd"
    sleep 0.3
    tmux send-keys -t "$karo_pane" Enter
    LAST_KARO_CLEAR=$now
    return 0
}

# ─── STEP 2: 家老の外部/clearトリガー ───
check_karo_clear() {
    local karo_pane="shogun:2.1"

    # idle判定
    check_idle "$karo_pane" "karo"
    if [ $? -ne 0 ]; then
        return  # busy or error → skip
    fi

    # CTX取得
    local ctx_num=$(get_context_pct "$karo_pane" "karo")
    if [ -z "$ctx_num" ] || [ "$ctx_num" -le 50 ] 2>/dev/null; then
        return  # CTX <= 50% → skip
    fi

    # 共通関数でデバウンス付き送信
    send_karo_clear "$ctx_num" "check_karo_clear"
}

# ─── STEP 3: 将軍CTXアラート ───
check_shogun_ctx() {
    local shogun_pane="shogun:1"

    # CTX取得
    local ctx_num=$(get_context_pct "$shogun_pane" "shogun")
    if [ -z "$ctx_num" ] || [ "$ctx_num" -le 50 ] 2>/dev/null; then
        return  # CTX <= 50% → skip
    fi

    # デバウンスチェック
    local now=$(date +%s)
    local last=$LAST_SHOGUN_ALERT
    local elapsed=$((now - last))

    if [ $elapsed -ge $SHOGUN_ALERT_DEBOUNCE ]; then
        local msg="【monitor】将軍CTX:${ctx_num}%。/compactをご検討ください"
        if bash "$SCRIPT_DIR/scripts/ntfy.sh" "$msg" >> "$LOG" 2>&1; then
            log "SHOGUN-ALERT: sent ntfy to lord (CTX:${ctx_num}%)"
            LAST_SHOGUN_ALERT=$now
        else
            log "ERROR: Failed to send shogun alert"
        fi
    else
        log "SHOGUN-ALERT-DEBOUNCE: shogun CTX:${ctx_num}% but ${elapsed}s < ${SHOGUN_ALERT_DEBOUNCE}s since last alert"
    fi
}

# ─── @model_name整合性チェック（REDISCOVER_EVERY周期） ───
# settings.yaml type → cli_profiles.yaml display_name を期待値として、
# 各ペインの@model_nameと比較。不整合があれば自動修正。
check_model_names() {
    local all_agents=("karo" "${NINJA_NAMES[@]}")

    for name in "${all_agents[@]}"; do
        local target
        if [ "$name" = "karo" ]; then
            target="shogun:2.1"
        else
            target="${PANE_TARGETS[$name]}"
        fi
        [ -z "$target" ] && continue

        # 期待値: cli_profiles.yaml の display_name
        local expected
        expected=$(cli_profile_get "$name" "display_name")
        if [ -z "$expected" ]; then
            expected=$(cli_type "$name")
        fi

        # 現在値
        local current
        current=$(tmux show-options -p -t "$target" -v @model_name 2>/dev/null || echo "")

        # 整合性チェック + 自動修正
        if [ "$current" != "$expected" ]; then
            tmux set-option -p -t "$target" @model_name "$expected" 2>/dev/null
            log "MODEL_NAME_FIX: $name ${current:-<empty>} -> $expected"
        fi
    done
}

# ─── inbox未読数ペイン変数更新（全エージェント + 将軍） ───
# 各エージェントのinbox YAMLから read: false の件数をカウントし、
# tmuxペイン変数 @inbox_count に設定。pane-border-formatで参照される。
# 未読0: 空文字（非表示）、未読1以上: " 📨N"
update_inbox_counts() {
    local all_agents=("karo" "${NINJA_NAMES[@]}")
    local inbox_dir="$SCRIPT_DIR/queue/inbox"

    for name in "${all_agents[@]}"; do
        local inbox_file="${inbox_dir}/${name}.yaml"
        local target
        if [ "$name" = "karo" ]; then
            target="shogun:2.1"
        else
            target="${PANE_TARGETS[$name]}"
        fi
        [ -z "$target" ] && continue

        local count=0
        if [ -f "$inbox_file" ]; then
            count=$(count_unread_messages "$inbox_file")
        fi

        if [ "$count" -gt 0 ] 2>/dev/null; then
            tmux set-option -p -t "$target" @inbox_count " 📨${count}" 2>/dev/null
        else
            tmux set-option -p -t "$target" @inbox_count "" 2>/dev/null
        fi
    done

    # 将軍ペイン（shogun:1）
    local shogun_inbox="${inbox_dir}/shogun.yaml"
    local shogun_count=0
    if [ -f "$shogun_inbox" ]; then
        shogun_count=$(count_unread_messages "$shogun_inbox")
    fi

    if [ "$shogun_count" -gt 0 ] 2>/dev/null; then
        tmux set-option -p -t "shogun:1.1" @inbox_count " 📨${shogun_count}" 2>/dev/null
    else
        tmux set-option -p -t "shogun:1.1" @inbox_count "" 2>/dev/null
    fi
}

# ─── Self-restart on script change (inbox_watcher.shから移植) ───
check_script_update() {
    local current_hash
    current_hash="$(md5sum "$SCRIPT_PATH" | cut -d' ' -f1)"
    if [ "$current_hash" != "$SCRIPT_HASH" ]; then
        local uptime=$(($(date +%s) - STARTUP_TIME))
        if [ "$uptime" -lt "$MIN_UPTIME" ]; then
            log "RESTART-GUARD: Script changed but uptime too short (${uptime}s < ${MIN_UPTIME}s), skipping"
            return 0
        fi
        log "AUTO-RESTART: Script file changed (hash: $SCRIPT_HASH → $current_hash), restarting..."
        exec "$SCRIPT_PATH"
    fi
}

# ─── 初期ペイン探索 ───
discover_panes

# ─── メインループ ───
cycle=0

while true; do
    sleep "$POLL_INTERVAL"
    cycle=$((cycle + 1))

    # 定期的にペイン再探索（ペイン構成変更に対応）
    if [ $((cycle % REDISCOVER_EVERY)) -eq 0 ]; then
        discover_panes

        # @model_name整合性チェック（cmd_155）
        check_model_names

        # Inbox pruning (cmd_106) — 10分間隔で既読メッセージを自動削除
        bash "$SCRIPT_DIR/scripts/inbox_prune.sh" 2>>"$SCRIPT_DIR/logs/inbox_prune.log" || true
    fi

    # ═══ ペイン生存チェック (cmd_183) ═══
    check_pane_survival

    # 案B: バッチ通知用配列を初期化
    NEWLY_IDLE=()

    # ═══ Phase 1: 高速スキャン（全忍者） ═══
    maybe_idle=()

    for name in "${NINJA_NAMES[@]}"; do
        target="${PANE_TARGETS[$name]}"
        [ -z "$target" ] && continue

        check_idle "$target" "$name"
        result=$?

        if [ $result -eq 2 ]; then
            log "WARNING: Failed to capture pane for $name ($target)"
            continue
        fi

        if [ $result -eq 0 ]; then
            # IDLE候補 — Phase 2で確認
            maybe_idle+=("$name")
        else
            # 確実にBUSY
            handle_busy "$name"
        fi
    done

    # ═══ Phase 2: 確認チェック（maybe-idle忍者のみ） ═══
    if [ ${#maybe_idle[@]} -gt 0 ]; then
        sleep "$CONFIRM_WAIT"

        # Phase 2a: Claude Code忍者を即チェック（5秒待機で十分）
        codex_idle=()
        for name in "${maybe_idle[@]}"; do
            if [ "$(cli_type "$name")" = "codex" ]; then
                codex_idle+=("$name")
                continue
            fi

            target="${PANE_TARGETS[$name]}"
            check_idle "$target" "$name"
            result=$?

            if [ $result -eq 0 ]; then
                handle_confirmed_idle "$name"
            else
                log "FALSE_POSITIVE: $name was idle briefly, now busy (API call gap)"
                handle_busy "$name"
            fi
        done

        # Phase 2b: Codex忍者は追加待機後にチェック（APIコール間隔が長い）
        if [ ${#codex_idle[@]} -gt 0 ]; then
            codex_confirm_wait=""
            codex_confirm_wait=$(cli_profile_get "${codex_idle[0]}" "confirm_wait")
            extra_wait=$((codex_confirm_wait - CONFIRM_WAIT))
            sleep "${extra_wait:-15}"

            for name in "${codex_idle[@]}"; do
                target="${PANE_TARGETS[$name]}"
                check_idle "$target" "$name"
                result=$?

                if [ $result -eq 0 ]; then
                    handle_confirmed_idle "$name"
                else
                    log "FALSE_POSITIVE: $name was idle briefly, now busy (API call gap)"
                    handle_busy "$name"
                fi
            done
        fi
    fi

    # 案B: Phase 2完了後、バッチ通知を送信（pending cmdがある場合のみ）
    if [ ${#NEWLY_IDLE[@]} -gt 0 ]; then
        if grep -q "status: pending" "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null; then
            notify_idle_batch "${NEWLY_IDLE[@]}"
        else
            log "SKIP idle notification: no pending cmds (${#NEWLY_IDLE[@]} idle: ${NEWLY_IDLE[*]})"
        fi
    fi

    # ═══ 停滞検知チェック（全忍者） ═══
    for name in "${NINJA_NAMES[@]}"; do
        check_stall "$name"
    done

    # ═══ 破壊コマンド検知チェック（全忍者） ═══
    for name in "${NINJA_NAMES[@]}"; do
        target="${PANE_TARGETS[$name]}"
        [ -z "$target" ] && continue
        check_destructive_commands "$name" "$target"
    done

    # ═══ 未読放置検知+再nudge (cmd_188) ═══
    check_inbox_renudge

    # ═══ Stale cmd検知チェック ═══
    check_stale_cmds

    # ═══ Pending cmd検知チェック（2分間隔） ═══
    if [ $((cycle % 6)) -eq 0 ]; then
        check_karo_pending
    fi

    # ═══ STEP 2: 家老の外部/clearチェック ═══
    check_karo_clear

    # ═══ STEP 3: 将軍CTXアラート ═══
    check_shogun_ctx

    # ═══ Phase 3: context_pct更新（全ペイン） ═══
    update_all_context_pct

    # ═══ inbox未読数ペイン変数更新 (cmd_188) ═══
    update_inbox_counts

    # ═══ STEP 1: ninja_states.yaml 自動生成 ═══
    write_state_file
    write_karo_snapshot   # 家老陣形図更新（毎サイクル）

    # ═══ Self-restart check ═══
    check_script_update
done
