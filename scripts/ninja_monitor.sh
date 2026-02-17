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

POLL_INTERVAL=20    # ポーリング間隔（秒）
DEBOUNCE=60         # 同一忍者の再通知抑制（秒）
CONFIRM_WAIT=5      # idle確認待ち（秒）— APIコール間の誤検知防止
CODEX_CONFIRM_WAIT=20  # Codex専用idle確認待ち（秒）— APIコール間隔10-15秒より長く
CODEX_DEBOUNCE=180     # Codex専用再通知抑制（秒）— 短時間サイクル抑制
STALL_THRESHOLD_MIN=15 # 停滞検知しきい値（分）— assigned+idle状態がこの時間継続で通知
REDISCOVER_EVERY=30 # N回ポーリングごとにペイン再探索

# 監視対象の忍者名リスト（karoと将軍は対象外）
NINJA_NAMES=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

log "ninja_monitor started. Monitoring ${#NINJA_NAMES[@]} ninja."
log "Poll interval: ${POLL_INTERVAL}s, Debounce: ${DEBOUNCE}s, Confirm wait: ${CONFIRM_WAIT}s"
log "Codex agents: sasuke,kirimaru (confirm=${CODEX_CONFIRM_WAIT}s, debounce=${CODEX_DEBOUNCE}s)"

# Codex CLI使用忍者の判定
is_codex() {
    [[ "$1" == "sasuke" || "$1" == "kirimaru" ]]
}

# CLI種別に応じたリセットコマンド取得
get_reset_cmd() {
    if is_codex "$1"; then
        echo "/new"
    else
        echo "/clear"
    fi
}

# ─── デバウンス・状態管理（連想配列、bash 4+） ───
declare -A LAST_NOTIFIED  # 最終通知時刻（epoch秒）
declare -A PREV_STATE     # 前回の状態: busy / idle / unknown
declare -A PANE_TARGETS   # 忍者名 → tmuxペインターゲット
declare -A LAST_CLEARED   # 最終/clear送信時刻（epoch秒）
declare -A STALL_FIRST_SEEN  # 停滞初回検知時刻（epoch秒）— assigned+idleを初めて観測した時刻
declare -A STALL_NOTIFIED    # 停滞通知済みフラグ — key: "ninja:task_id", value: "1"

# 案A: PREV_STATE初期化（起動直後のidle→idle通知を防止）
for name in "${NINJA_NAMES[@]}"; do
    PREV_STATE[$name]="idle"
done

CLEAR_DEBOUNCE=300          # /clear再送信抑制（5分）— /clear後のbusy→idleサイクルによるループ防止
CODEX_CLEAR_DEBOUNCE=600    # Codex下忍用デバウンス（10分）— 撤廃時の安全策
KARO_COMPACT_DEBOUNCE=600   # 家老/compact再送信抑制（10分）— compact復帰処理に5-8分かかるため
SHOGUN_ALERT_DEBOUNCE=1800  # 将軍CTXアラート再送信抑制（30分）— 殿を煩わせない

LAST_KARO_COMPACT=0         # 家老の最終/compact送信時刻（epoch秒）
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

# ─── idle検出（単一チェック） ───
# 戻り値: 0=IDLE, 1=BUSY, 2=ERROR
check_idle() {
    local pane_target="$1"

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

    # BUSYパターン検出（いずれかがマッチすればBUSY）
    # 1. "esc to interrupt" — ステータスバー（広いペインで完全表示時）
    # 2. "Running" — ツール実行中（ペイン幅に依存しない）
    # 3. "Streaming" — ストリーミング出力中
    # 4. "background terminal running" — Codex CLIバックグラウンドターミナル稼働中
    if echo "$output" | grep -qE "esc to interrupt|Running|Streaming|background terminal running"; then
        return 1  # BUSY
    fi

    # ❯ プロンプト（Claude Code）または › プロンプト（Codex CLI）があればIDLE候補
    if echo "$output" | grep -qE "❯|›"; then
        return 0  # IDLE候補（要二段階確認）
    fi

    return 1  # デフォルトはBUSY（安全側 — 誤検知防止）
}

# ─── CTX%取得（多重ソース） ───
# @context_pct変数 → capture-pane出力「CTX:XX%」→ 0(不明)
# statusline.shのtmux set-option -pがサブプロセスで失効する問題の回避策
get_context_pct() {
    local pane_target="$1"
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

    # Source 2a: Claude Code パターン: "CTX:XX%" (usage%)
    ctx_num=$(echo "$output" | grep -oE 'CTX:[0-9]+%' | tail -1 | grep -oE '[0-9]+')
    if [ -n "$ctx_num" ]; then
        tmux set-option -p -t "$pane_target" @context_pct "${ctx_num}%" 2>/dev/null
        echo "$ctx_num"
        return 0
    fi

    # Source 2b: Codex CLI パターン: "XX% context left" (remaining% → usage%に変換)
    local remaining
    remaining=$(echo "$output" | grep -oE '[0-9]+% context left' | tail -1 | grep -oE '[0-9]+')
    if [ -n "$remaining" ]; then
        ctx_num=$((100 - remaining))
        tmux set-option -p -t "$pane_target" @context_pct "${ctx_num}%" 2>/dev/null
        echo "$ctx_num"
        return 0
    fi

    echo "0"
    return 1
}

# ─── 案E: タスク配備済み判定（二重チェック: YAML + ペイン実態） ───
is_task_deployed() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    if [ -f "$task_file" ]; then
        if grep -qE 'status:\s*(assigned|in_progress)' "$task_file" 2>/dev/null; then
            # YAML says active — cross-check with actual pane state
            local target="${PANE_TARGETS[$name]}"
            if [ -n "$target" ]; then
                local pane_idle=false
                local task_empty=false

                # Check if pane shows ❯/› prompt (idle)
                check_idle "$target"
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
        local ctx=$(get_context_pct "$target")
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

        debounce_time=$DEBOUNCE
        if is_codex "$name"; then
            debounce_time=$CODEX_DEBOUNCE
        fi

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
        ctx_now=$(get_context_pct "$target")
        if [ "${ctx_now:-0}" -le 0 ] 2>/dev/null; then
            log "CLEAR-SKIP: $name CTX=${ctx_now}%, already clean"
        else
            clear_last="${LAST_CLEARED[$name]:-0}"
            clear_elapsed=$((now - clear_last))

            # Codex下忍はデバウンス延長(600秒)
            local effective_debounce=$CLEAR_DEBOUNCE
            if [ "$agent_id" = "sasuke" ] || [ "$agent_id" = "kirimaru" ]; then
                effective_debounce=$CODEX_CLEAR_DEBOUNCE
            fi

            if [ $clear_elapsed -ge $effective_debounce ]; then
                local reset_cmd
                reset_cmd=$(get_reset_cmd "$name")
                log "AUTO-CLEAR: $name idle+no_task CTX=${ctx_now}%, sending $reset_cmd"
                tmux send-keys -t "$target" "$reset_cmd"
                sleep 0.3
                tmux send-keys -t "$target" Enter
                LAST_CLEARED[$name]=$now
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

    check_idle "$target"
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

# ─── context_pct更新（単一ペイン） ───
# 引数: pane_target (例: shogun:2.4)
# 戻り値: 0=更新成功, 1=失敗(--設定)
update_context_pct() {
    local pane_target="$1"
    local output
    local context_pct="--"
    local remaining

    output=$(tmux capture-pane -t "$pane_target" -p -S -10 2>/dev/null)
    if [ $? -ne 0 ]; then
        tmux set-option -p -t "$pane_target" @context_pct "$context_pct" 2>/dev/null
        return 1
    fi

    # Claude Code パターン: "CTX:XX%" (statusline.sh出力)
    if echo "$output" | grep -qE 'CTX:[0-9]+%'; then
        context_pct=$(echo "$output" | grep -oE 'CTX:[0-9]+%' | tail -1 | sed 's/CTX://')
    # Codex CLI パターン: "XX% context left"
    elif echo "$output" | grep -qE '[0-9]+% context left'; then
        remaining=$(echo "$output" | grep -oE '[0-9]+% context left' | tail -1 | grep -oE '[0-9]+')
        context_pct="$((100 - remaining))%"
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
        update_context_pct "shogun:$pane_idx"
    done

    # 家老 + 忍者ペイン（Window 2）
    local window2_panes
    window2_panes=$(tmux list-panes -t shogun:2 -F '2.#{pane_index}' 2>/dev/null)
    for pane_idx in $window2_panes; do
        update_context_pct "shogun:$pane_idx"
    done
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
        check_idle "$karo_pane" && karo_status="idle" || karo_status="busy"
        local karo_ctx=$(get_context_pct "$karo_pane")
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
            local ctx=$(get_context_pct "$target")
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

# ─── STEP 2: 家老の外部compactトリガー ───
check_karo_compact() {
    local karo_pane="shogun:2.1"

    # idle判定
    check_idle "$karo_pane"
    if [ $? -ne 0 ]; then
        return  # busy or error → skip
    fi

    # CTX取得
    local ctx_num=$(get_context_pct "$karo_pane")
    if [ -z "$ctx_num" ] || [ "$ctx_num" -le 50 ] 2>/dev/null; then
        return  # CTX <= 50% → skip
    fi

    # デバウンスチェック
    local now=$(date +%s)
    local last=$LAST_KARO_COMPACT
    local elapsed=$((now - last))

    if [ $elapsed -ge $KARO_COMPACT_DEBOUNCE ]; then
        log "KARO-COMPACT: karo CTX:${ctx_num}%, sending /compact"
        tmux send-keys -t "$karo_pane" '/compact'
        sleep 0.3
        tmux send-keys -t "$karo_pane" Enter
        LAST_KARO_COMPACT=$now
    else
        log "KARO-COMPACT-DEBOUNCE: karo CTX:${ctx_num}% but ${elapsed}s < ${KARO_COMPACT_DEBOUNCE}s since last /compact"
    fi
}

# ─── STEP 3: 将軍CTXアラート ───
check_shogun_ctx() {
    local shogun_pane="shogun:1"

    # CTX取得
    local ctx_num=$(get_context_pct "$shogun_pane")
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

        # Inbox pruning (cmd_106) — 10分間隔で既読メッセージを自動削除
        bash "$SCRIPT_DIR/scripts/inbox_prune.sh" 2>>"$SCRIPT_DIR/logs/inbox_prune.log" || true
    fi

    # 案B: バッチ通知用配列を初期化
    NEWLY_IDLE=()

    # ═══ Phase 1: 高速スキャン（全忍者） ═══
    maybe_idle=()

    for name in "${NINJA_NAMES[@]}"; do
        target="${PANE_TARGETS[$name]}"
        [ -z "$target" ] && continue

        check_idle "$target"
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
            if is_codex "$name"; then
                codex_idle+=("$name")
                continue
            fi

            target="${PANE_TARGETS[$name]}"
            check_idle "$target"
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
            extra_wait=$((CODEX_CONFIRM_WAIT - CONFIRM_WAIT))
            sleep "${extra_wait:-15}"

            for name in "${codex_idle[@]}"; do
                target="${PANE_TARGETS[$name]}"
                check_idle "$target"
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

    # ═══ STEP 2: 家老の外部compactチェック ═══
    check_karo_compact

    # ═══ STEP 3: 将軍CTXアラート ═══
    check_shogun_ctx

    # ═══ Phase 3: context_pct更新（全ペイン） ═══
    update_all_context_pct

    # ═══ STEP 1: ninja_states.yaml 自動生成 ═══
    write_state_file
done
