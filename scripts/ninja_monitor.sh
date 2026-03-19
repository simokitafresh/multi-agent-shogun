#!/bin/bash
# shellcheck disable=SC1091,SC2034,SC2129
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
STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
source "$SCRIPT_DIR/scripts/lib/model_detect.sh"
source "$SCRIPT_DIR/scripts/lib/field_get.sh"
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
source "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
source "$SCRIPT_DIR/lib/agent_state.sh"
source "$SCRIPT_DIR/lib/rotate_log.sh"

source "$SCRIPT_DIR/scripts/lib/model_colors.sh"
source "$SCRIPT_DIR/scripts/lib/script_update.sh"

POLL_INTERVAL=20    # ポーリング間隔（秒）
CONFIRM_WAIT=5      # idle確認待ち（秒）— Phase 2a base wait
STALL_THRESHOLD_MIN=10 # 停滞検知しきい値（分）— assigned+idle状態がこの時間継続で通知 (cmd_1105: 15→10分に短縮)
STALE_CMD_THRESHOLD=14400 # stale cmd検知しきい値（秒）— pending+subtask未配備が4時間継続で通知
NTFY_HEALTH_THRESHOLD_MIN=10 # ntfy_listenerヘルスチェックしきい値（分）— ログが古ければゾンビ判定
NTFY_RESTART_COOLDOWN_MIN=5  # ntfy_listener連続再起動防止クールダウン（分）
REDISCOVER_EVERY=30 # N回ポーリングごとにペイン再探索
KARO_PANE="shogun:2.1"  # 家老ペインターゲット（EH6: ハードコード排除）
NTFY_BATCH_FLUSH_INTERVAL=900 # INFOバッチ通知フラッシュ間隔（秒）

# Self-restart on script change (inbox_watcher.shから移植)
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_HASH="$(md5sum "$SCRIPT_PATH" | cut -d' ' -f1)"
STARTUP_TIME="$(date +%s)"
MIN_UPTIME=10  # minimum seconds before allowing auto-restart
LAST_NTFY_RESTART=0  # ntfy_listener最終再起動時刻（epoch秒）
LAST_BATCH_FLUSH=0   # ntfy_batch_flush最終実行時刻（epoch秒）
CDP_CLEANUP_SCRIPT="$SCRIPT_DIR/scripts/cdp_chrome_cleanup.sh"
CDP_CLEANUP_INTERVAL=300  # CDP cleanup最小間隔（秒）— 5分
LAST_CDP_CLEANUP=0        # CDP cleanup最終実行時刻（epoch秒）

# 監視対象の忍者名リスト（karoと将軍は対象外）
# saizo pane 7 (cmd_403: gunshi凍結→saizo復帰)
NINJA_NAMES=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)

mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$STATE_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

send_inbox_message() {
    local to="$1"
    local message="$2"
    local msg_type="$3"
    local from="${4:-ninja_monitor}"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$to" "$message" "$msg_type" "$from" >> "$LOG" 2>&1
}

yaml_field_get() {
    local file="$1"
    local field="$2"
    local default="${3:-}"
    FIELD_GET_NO_LOG=1 field_get "$file" "$field" "$default" 2>/dev/null
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
declare -A STALL_NOTIFIED    # 停滞通知時刻（epoch秒）— key: "ninja:task_id", value: epoch
declare -A STALE_CMD_NOTIFIED  # stale cmd最終通知時刻 — key: "cmd_XXX", value: epoch秒
declare -A PREV_PENDING_SET       # 前回認識したpending cmd集合 — key: cmd_id, value: "1"
declare -A CLEAR_SKIP_COUNT   # CLEAR-SKIPカウンタ — 忍者ごとの連続回数（AC3: ログ抑制用）
declare -A DESTRUCTIVE_WARN_LAST  # 破壊コマンド検知 — key: "ninja:pattern_id", value: epoch秒
declare -A RENUDGE_COUNT          # 未読再nudgeカウンター — key: agent_name, value: 連続再nudge回数
declare -A RENUDGE_FINGERPRINT    # 未読IDのfingerprint — key: agent_name, value: md5 hash (L029: ID集合ベース)
declare -A RENUDGE_LAST_SEND      # 最終renudge送信時刻 — key: agent_name, value: epoch秒
declare -A AUTO_DEPLOY_DONE       # auto_deploy_next.sh呼出済みフラグ — key: "ninja:task_id", value: "1"
declare -A STALL_COUNT            # DEPLOY-STALL回数カウンター — key: "ninja:subtask_id", value: count
declare -A POST_CLEAR_PENDING     # /new後にpost_clear_cmd送信待ち — key: agent_name, value: epoch秒
PREV_PANE_MISSING=""              # ペイン消失 — 前回の消失忍者リスト（重複送信防止）

# 案A: PREV_STATE初期化（起動直後のidle→idle通知を防止）
for name in "${NINJA_NAMES[@]}"; do
    PREV_STATE[$name]="idle"
done

MAX_RENUDGE=5               # 未読再nudge上限回数（同一未読状態に対して）
RENUDGE_BACKOFF=600         # 低頻度バックオフ再通知間隔（10分=600秒）— 同一fingerprint時の安全網
STALL_RENOTIFY_DEBOUNCE=300 # 同一ninja×taskのSTALL再通知デバウンス（5分）
STALL_ESCALATE_THRESHOLD=2  # 同一taskでのstall_escalate発火閾値
KARO_CLEAR_DEBOUNCE=120     # 家老/clear再送信抑制（2分）— /clear復帰~30秒のため
STALE_CMD_DEBOUNCE=1800     # stale cmd同一cmd再通知抑制（30分）
DESTRUCTIVE_DEBOUNCE=300    # 破壊コマンド同一パターン連続通知抑制（5分=300秒）
SHOGUN_ALERT_DEBOUNCE=1800  # 将軍CTXアラート再送信抑制（30分）— 殿を煩わせない

LAST_KARO_CLEAR=0           # 家老の最終/clear送信時刻（epoch秒）
LAST_SHOGUN_ALERT=0         # 将軍の最終アラート送信時刻（epoch秒）
prev_context_warn_sig=""

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
    if ! actual_agents=$(tmux list-panes -t shogun:2 -F '#{@agent_id}' 2>/dev/null) || [ -z "$actual_agents" ]; then
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
            # flag file存在保証（idle状態なら常にflagがあるべき）
            [ ! -f "${STATE_DIR}/shogun_idle_${agent_name}" ] && touch "${STATE_DIR}/shogun_idle_${agent_name}"
            local last_active
            last_active=$(tmux display-message -t "$pane_target" -p '#{@last_active}' 2>/dev/null)
            local now
            now=$(date +%s)
            if [ -n "$last_active" ] && [ $((now - last_active)) -lt 15 ]; then
                return 1  # grace period内はBUSY扱い（thinking中の誤判定防止）
            fi
            # pstree cross-check: @agent_state=idleでも子プロセス存在時はBUSY
            if _agent_state_has_busy_subprocess "$pane_target"; then
                log "PSTREE-OVERRIDE: ${agent_name} @agent_state=idle but bash subprocess detected, treating as BUSY"
                return 1
            fi
            return 0  # IDLE確定（grace period経過）
        fi
        # ─── bash_running: Bashフック設定中はBUSY扱い（STALL誤判定防止） ───
        if [ "$agent_state" = "bash_running" ]; then
            local bash_since
            bash_since=$(tmux display-message -t "$pane_target" -p '#{@bash_running_since}' 2>/dev/null)
            local now_ts
            now_ts=$(date +%s)
            # crash補正: 30分(1800秒)以上bash_running継続ならクラッシュ残留と判断しidle補正
            if [ -n "$bash_since" ] && [ "$bash_since" -gt 0 ] 2>/dev/null && [ $((now_ts - bash_since)) -ge 1800 ]; then
                log "AGENT-STATE-CORRECTION: ${agent_name} @agent_state=bash_running stale (${bash_since}→${now_ts}, $((now_ts - bash_since))s), corrected to idle"
                tmux set-option -p -t "$pane_target" @agent_state idle 2>/dev/null || true
                tmux set-option -p -t "$pane_target" @bash_running_since "" 2>/dev/null || true
                [ ! -f "${STATE_DIR}/shogun_idle_${agent_name}" ] && touch "${STATE_DIR}/shogun_idle_${agent_name}"
                return 0  # crash補正後IDLE
            fi
            return 1  # bash_running中はBUSY
        fi
    fi

    local busy_rc
    if check_agent_busy "$pane_target" "$agent_name"; then
        busy_rc=0
    else
        busy_rc=$?
    fi

    if [ "$busy_rc" -eq 0 ]; then
        if [ -n "$agent_state" ] && [ "$agent_state" != "idle" ]; then
            log "AGENT-STATE-CORRECTION: ${agent_name} @agent_state=${agent_state} but idle prompt detected, corrected to idle"
        fi
        return 0
    fi

    if [ "$busy_rc" -eq 1 ]; then
        return 1
    fi

    # unknown:
    #  - @agent_stateがactive等なら安全側でBUSY
    #  - 未設定かつ判定不能ならERROR
    if [ -n "$agent_state" ] && [ "$agent_state" != "idle" ]; then
        return 1
    fi
    return 2
}

# ─── /clear送信ラッパー（idle確認はcheck_idle()に一本化） ───
# $1: pane_target, $2: agent_name, $3: reason(任意)
# 戻り値: 0=送信, 1=ブロック（次サイクル再試行）
# HOTFIX 2026-03-01: tail -3でステータスバーしか見えずidle prompt検出不能だった
#   → check_idle()に一本化。idle判定ロジックの重複を排除。
safe_send_clear() {
    local pane="$1"
    local agent_name="$2"
    local reason="${3:-UNKNOWN}"

    if [ -z "$pane" ] || [ -z "$agent_name" ]; then
        log "CLEAR-BLOCKED: missing pane/agent, reason=$reason"
        return 1
    fi

    # idle判定をcheck_idle()に委譲（idle flag + capture-pane + busy pattern除外）
    if ! check_idle "$pane" "$agent_name"; then
        log "CLEAR-BLOCKED: $agent_name not idle (check_idle), reason=$reason, will retry next cycle"
        return 1
    fi

    local clear_cmd
    clear_cmd=$(cli_profile_get "$agent_name" "clear_cmd")
    clear_cmd=${clear_cmd:-"/clear"}
    log "CLEAR-SEND: $agent_name confirmed idle, sending $clear_cmd, reason=$reason"
    if ! safe_send_keys_atomic "$pane" "$clear_cmd" 0.3; then
        log "CLEAR-BLOCKED: $agent_name send failed, reason=$reason"
        return 1
    fi
    rm -f "${STATE_DIR}/shogun_idle_${agent_name}"
    return 0
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
    output=$(tmux capture-pane -t "$pane_target" -p -J -S -5 2>/dev/null)

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

get_latest_report_file() {
    local name="$1"
    local legacy_report="$SCRIPT_DIR/queue/reports/${name}_report.yaml"
    local latest_cmd_report=""

    latest_cmd_report=$(find "$SCRIPT_DIR/queue/reports/" -maxdepth 1 -name "${name}_report_cmd*.yaml" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
    if [ -n "$latest_cmd_report" ]; then
        echo "$latest_cmd_report"
        return 0
    fi

    if [ -f "$legacy_report" ]; then
        echo "$legacy_report"
        return 0
    fi

    return 1
}

find_matching_report_file() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local task_parent_cmd task_id
    local report_parent_cmd report_task_id
    local preferred_report legacy_report
    local -a candidates=()

    task_parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
    [ -z "$task_parent_cmd" ] && return 1
    task_id=$(yaml_field_get "$task_file" "task_id")

    preferred_report="$SCRIPT_DIR/queue/reports/${name}_report_${task_parent_cmd}.yaml"
    legacy_report="$SCRIPT_DIR/queue/reports/${name}_report.yaml"
    candidates+=("$preferred_report" "$legacy_report")

    # 追加フォールバック: cmd付き報告の最新から順に確認
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if [ "$f" != "$preferred_report" ] && [ "$f" != "$legacy_report" ]; then
            candidates+=("$f")
        fi
    done < <(ls -1t "$SCRIPT_DIR/queue/reports/${name}_report_cmd"*.yaml 2>/dev/null || true)

    for report_file in "${candidates[@]}"; do
        [ -f "$report_file" ] || continue

        report_parent_cmd=$(yaml_field_get "$report_file" "parent_cmd")
        [ -z "$report_parent_cmd" ] && continue
        [ "$report_parent_cmd" != "$task_parent_cmd" ] && continue

        report_task_id=$(yaml_field_get "$report_file" "task_id")
        if [ -n "$task_id" ] && [ -n "$report_task_id" ] && [ "$task_id" != "$report_task_id" ]; then
            continue
        fi

        echo "$report_file"
        return 0
    done

    return 1
}

resolve_expected_report_file() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local report_filename parent_cmd

    report_filename=$(yaml_field_get "$task_file" "report_filename")
    if [ -z "$report_filename" ]; then
        parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
        if [ -n "$parent_cmd" ]; then
            report_filename="${name}_report_${parent_cmd}.yaml"
        else
            report_filename="${name}_report.yaml"
        fi
    fi

    echo "$report_filename"
}

can_send_clear_with_report_gate() {
    local name="$1"
    local trigger="$2"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"

    # タスクYAMLなし: 報告不要
    [ -f "$task_file" ] || return 0

    local task_status
    task_status=$(yaml_field_get "$task_file" "status")
    # done以外: 報告ゲート対象外
    [ "$task_status" = "done" ] || return 0

    local report_filename report_path parent_cmd base_name search_pattern
    local -a search_dirs search_patterns
    report_filename=$(resolve_expected_report_file "$name")
    if [[ "$report_filename" = /* ]]; then
        report_path="$report_filename"
    else
        report_path="$SCRIPT_DIR/queue/reports/${report_filename}"
    fi

    if [ -f "$report_path" ]; then
        return 0
    fi

    parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
    search_dirs=("$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/archive/reports")

    # Primary pattern: expected cmd-scoped report name prefix.
    if [ -n "$parent_cmd" ]; then
        search_pattern="${name}_report_${parent_cmd}*.yaml"
        search_patterns+=("$search_pattern")
    fi

    # Fallback pattern from report_filename for custom report naming.
    base_name="$(basename "$report_filename")"
    base_name="${base_name%.yaml}"
    if [ -n "$base_name" ]; then
        search_pattern="${base_name}*.yaml"
        if [ "${#search_patterns[@]}" -eq 0 ] || [ "${search_patterns[0]}" != "$search_pattern" ]; then
            search_patterns+=("$search_pattern")
        fi
    fi

    local dir pattern
    for pattern in "${search_patterns[@]}"; do
        for dir in "${search_dirs[@]}"; do
            if compgen -G "${dir}/${pattern}" > /dev/null; then
                return 0
            fi
        done
    done

    if [ -n "$parent_cmd" ]; then
        search_pattern="${name}_report_${parent_cmd}*.yaml"
    else
        search_pattern="${base_name}*.yaml"
    fi
    log "REPORT-MISSING-BLOCK: $name done but no report matching ${search_pattern} in reports/ or archive/reports/ (${trigger})"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "【自動検知】${name}がdone状態だが報告未作成。/clear保留中。" report_missing ninja_monitor >> "$LOG" 2>&1 &
    return 1
}

# ─── AC1: 報告YAML完了判定 + タスクYAML自動done更新 ───
# 報告YAMLのparent_cmdがタスクと一致し、status=doneなら自動更新
# 戻り値: 0=完了済み(auto-done実行), 1=未完了
check_and_update_done_task() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local report_file=""

    # タスクのparent_cmdを取得
    local task_parent_cmd
    task_parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
    [ -z "$task_parent_cmd" ] && return 1

    # 新形式({ninja}_report_{cmd}.yaml)優先で一致報告を探索。旧形式も許容。
    report_file=$(find_matching_report_file "$name") || return 1

    # 報告のparent_cmdを取得
    local report_parent_cmd
    report_parent_cmd=$(yaml_field_get "$report_file" "parent_cmd")
    [ -z "$report_parent_cmd" ] && return 1

    # parent_cmd一致チェック
    [ "$task_parent_cmd" != "$report_parent_cmd" ] && return 1

    # task_id一致チェック（同一cmd内のWave間誤マッチ防止）
    local task_id report_task_id
    task_id=$(yaml_field_get "$task_file" "task_id")
    report_task_id=$(yaml_field_get "$report_file" "task_id")
    [ -n "$task_id" ] && [ -n "$report_task_id" ] && [ "$task_id" != "$report_task_id" ] && return 1

    # 報告のstatus確認（done/completed/success を完了とみなす）
    local report_status
    report_status=$(yaml_field_get "$report_file" "status")
    case "$report_status" in
        done|completed|success)
            # 完了確認 — タスクYAMLをdoneに自動更新（flock排他制御）
            local lock_file="/tmp/task_${name}.lock"
            local completed_ts
            completed_ts="$(date '+%Y-%m-%dT%H:%M:%S')"
            (
                flock -x -w 5 200 || { log "ERROR: Failed to acquire lock for $name task update"; exit 1; }
                # S05修正: TOCTOU防止 — flock取得後にparent_cmd/task_idの一致を再検証
                local current_parent_cmd current_task_id
                current_parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
                current_task_id=$(yaml_field_get "$task_file" "task_id")
                if [ "$current_parent_cmd" != "$task_parent_cmd" ] || { [ -n "$task_id" ] && [ -n "$current_task_id" ] && [ "$current_task_id" != "$task_id" ]; }; then
                    log "WARN: task file changed during check_and_update_done_task for $name (expected parent_cmd=$task_parent_cmd, got $current_parent_cmd)"
                    exit 1
                fi
                if ! yaml_field_set "$task_file" "task" "status" "done"; then
                    log "ERROR: yaml_field_set failed for ${name} task status update"
                    exit 1
                fi
                # completed_at自動記録（cmd_387: 既存なら上書きしない）
                TASK_FILE_ENV="$task_file" COMPLETED_AT_ENV="$completed_ts" python3 -c "
import yaml, sys, os, tempfile
task_file = os.environ['TASK_FILE_ENV']
completed_at = os.environ['COMPLETED_AT_ENV']
try:
    with open(task_file) as f:
        data = yaml.safe_load(f)
    if not data or 'task' not in data:
        sys.exit(0)
    task = data['task']
    if task.get('completed_at'):
        sys.exit(0)
    task['completed_at'] = completed_at
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(task_file), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, task_file)
    except:
        os.unlink(tmp_path)
        raise
except Exception as e:
    print(f'[COMPLETED_AT] ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || true
            ) 200>"$lock_file"
            # subshell+fd redirection の戻り値
            # shellcheck disable=SC2181
            if [ $? -ne 0 ]; then
                return 1
            fi
            log "AUTO-DONE: $name task auto-updated to done (report=$(basename "$report_file"), parent_cmd=$report_parent_cmd, status=$report_status)"
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
        local task_status
        task_status=$(yaml_field_get "$task_file" "status")

        if [[ "$task_status" =~ ^(assigned|acknowledged|in_progress|done)$ ]]; then
            # AC1/AC2: 報告YAML完了チェック（parent_cmd一致+status:done）
            if check_and_update_done_task "$name"; then
                # ─── auto_deploy_next.sh 自動発火（二重呼出防止付き） ───
                local task_id_val parent_cmd_val
                task_id_val=$(yaml_field_get "$task_file" "task_id")
                parent_cmd_val=$(yaml_field_get "$task_file" "parent_cmd")
                local deploy_key="${name}:${task_id_val}"
                if [ -n "$parent_cmd_val" ] && [ -n "$task_id_val" ] && [ "${AUTO_DEPLOY_DONE[$deploy_key]}" != "1" ]; then
                    AUTO_DEPLOY_DONE[$deploy_key]="1"
                    log "[AUTO_DEPLOY] Triggering: cmd=${parent_cmd_val} completed=${task_id_val} ninja=${name}"
                    (
                        timeout 30 bash "$SCRIPT_DIR/scripts/auto_deploy_next.sh" "$parent_cmd_val" "$task_id_val" >> "$LOG" 2>&1
                        rc=$?
                        case $rc in
                            0) echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTO_DEPLOY] OK: ${name}の次サブタスク配備完了 (cmd=${parent_cmd_val})" >> "$LOG" ;;
                            2) echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTO_DEPLOY] SKIP: auto_deploy=false (cmd=${parent_cmd_val})" >> "$LOG" ;;
                            3) echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTO_DEPLOY] BLOCKED: 未解消依存あり or 忍者不在 (cmd=${parent_cmd_val})" >> "$LOG" ;;
                            *) echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUTO_DEPLOY] ERROR: 配備失敗 rc=${rc} (cmd=${parent_cmd_val})" >> "$LOG" ;;
                        esac
                    ) &
                fi
                return 1  # 完了済み — not deployed
            fi

            # done状態は常に未配備扱い（ただし報告一致時は上でauto_deploy発火済み）
            if [ "$task_status" = "done" ]; then
                local target="${PANE_TARGETS[$name]}"
                if [ -n "$target" ]; then
                    local current_task
                    current_task=$(tmux display-message -t "$target" -p '#{@current_task}' 2>/dev/null)
                    if [ -n "$current_task" ]; then
                        tmux set-option -p -t "$target" @current_task "" 2>/dev/null
                        log "TASK-CLEAR: $name @current_task cleared (task status=done, was: $current_task)"
                    fi
                fi
                return 1
            fi

            # YAML says active — cross-check with actual pane state
            local target="${PANE_TARGETS[$name]}"
            if [ -n "$target" ]; then
                local pane_idle=false
                local task_empty=false

                # Check if pane shows idle prompt
                if check_idle "$target" "$name"; then
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
                    # Grace period: skip STALE-TASK if deployed recently (< 5min)
                    local deployed_at_val
                    deployed_at_val=$(yaml_field_get "$task_file" "deployed_at")
                    if [ -n "$deployed_at_val" ]; then
                        local deployed_epoch elapsed
                        deployed_epoch=$(date -d "$deployed_at_val" +%s 2>/dev/null || echo "")
                        if [ -n "$deployed_epoch" ]; then
                            local now_epoch
                            now_epoch=$(date +%s)
                            elapsed=$((now_epoch - deployed_epoch))
                            if [ "$elapsed" -lt 300 ]; then
                                log "STALE-TASK-GRACE: $name deployed ${elapsed}s ago, within grace period"
                                return 0  # Within grace period — treat as deployed
                            fi
                        fi
                    fi
                    local yaml_status
                    yaml_status="${task_status}"
                    log "STALE-TASK: $name has YAML status=$yaml_status but pane is idle, treating as not deployed"
                    return 1  # Stale — treat as not deployed
                fi
            fi
            return 0  # タスク配備済み（active or ペインチェック不可）
        fi
    fi
    return 1  # 未配備
}

# ─── 案B: バッチ通知処理 ───
notify_idle_batch() {
    local -a names=("$@")
    if [ ${#names[@]} -eq 0 ]; then return 0; fi

    # 各忍者のCTX%と最終タスクIDを収集
    local details=""
    for name in "${names[@]}"; do
        local target="${PANE_TARGETS[$name]}"
        local ctx
        ctx=$(get_context_pct "$target" "$name")
        local last_task
        last_task=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${name}.yaml" "task_id")
        details="${details}${name}(CTX:${ctx}%,last:${last_task}), "
    done
    details="${details%, }"  # 末尾カンマ除去

    local msg="idle(新規): ${details}。計${#names[@]}名タスク割り当て可能。"
    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$msg" ninja_idle ninja_monitor >> "$LOG" 2>&1; then
        log "Batch notification sent to karo: ${names[*]}"
        local now
        now=$(date +%s)
        for name in "${names[@]}"; do
            LAST_NOTIFIED[$name]=$now
        done
        return 0
    else
        log "ERROR: Failed to send batch notification"
        return 1
    fi
}

# ─── handle_confirmed_idle サブ関数群 ───

# post_clear_cmd送信（cmd_583: /new後の/fast自動有効化）
# 戻り値: 0=処理済み(呼び出し元でreturn), 1=未処理(続行)
_handle_post_clear_pending() {
    local name="$1"
    [ -z "${POST_CLEAR_PENDING[$name]}" ] && return 1

    local pc_target="${PANE_TARGETS[$name]}"
    [ -z "$pc_target" ] && return 1

    local post_cmd
    post_cmd=$(cli_profile_get "$name" "post_clear_cmd")
    if [ -n "$post_cmd" ]; then
        # AC4: /fastはトグルのため、既にONなら送信しない
        local pc_banner
        pc_banner=$(tmux capture-pane -t "$pc_target" -p -J -S -100 2>/dev/null)
        if echo "$pc_banner" | grep -qE '│.*model:.*fast'; then
            log "POST-CLEAR-CMD-SKIP: $name fast already ON, skipping to avoid toggle-off"
        else
            log "POST-CLEAR-CMD: $name sending $post_cmd after /new"
            safe_send_keys_atomic "$pc_target" "$post_cmd" 0.3
        fi
    fi
    unset "POST_CLEAR_PENDING[$name]"
    PREV_STATE[$name]="idle"
    return 0
}

# deploy stall処理（タスク配備済み+idle時の/clear+再送）
# 戻り値: 0=処理済み(呼び出し元でreturn), 1=未処理(続行)
_handle_deploy_stall() {
    local name="$1"
    ! is_task_deployed "$name" && return 1

    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local task_status
    task_status=$(yaml_field_get "$task_file" "status")

    # acknowledged/in_progress はStage 1（Phase 1）で既にフィルタ済み
    # ここに到達するのは assigned/done/idle/statusなし のみ

    local now
    now=$(date +%s)
    local deploy_stall_key="deploy_stall_${name}"
    if [ -z "${STALL_FIRST_SEEN[$deploy_stall_key]}" ]; then
        STALL_FIRST_SEEN[$deploy_stall_key]=$now
        log "DEPLOY-STALL-WATCH: $name has $task_status task, idle (tracking started)"
        PREV_STATE[$name]="busy"
        return 0
    fi

    local first_seen=${STALL_FIRST_SEEN[$deploy_stall_key]}
    local elapsed=$((now - first_seen))
    local effective_debounce
    effective_debounce=$(cli_profile_get "$name" "clear_debounce")
    # AC3: stall_debounceが定義されていればclear_debounceより優先
    local stall_debounce
    stall_debounce=$(cli_profile_get "$name" "stall_debounce")
    if [ -n "$stall_debounce" ]; then
        effective_debounce=$stall_debounce
    fi

    if [ "$elapsed" -ge "$effective_debounce" ]; then
        if ! can_send_clear_with_report_gate "$name" "DEPLOY-STALL-CLEAR"; then
            PREV_STATE[$name]="busy"
            return 0
        fi
        local target="${PANE_TARGETS[$name]}"
        if ! safe_send_clear "$target" "$name" "DEPLOY-STALL-CLEAR"; then
            PREV_STATE[$name]="busy"
            return 0
        fi
        unset "STALL_FIRST_SEEN[$deploy_stall_key]"
        # cmd_583: /new後にpost_clear_cmd(e.g. /fast)を送信するためpendingセット
        if [ -n "$(cli_profile_get "$name" "post_clear_cmd")" ]; then
            POST_CLEAR_PENDING[$name]=$now
            log "POST-CLEAR-PENDING: $name queued post_clear_cmd after DEPLOY-STALL-CLEAR"
        fi
        # /new後にinbox nudgeで新セッションにタスクを知らせる
        sleep 2
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$name" "タスクYAMLを読んで作業開始せよ。" task_assigned ninja_monitor >> "$LOG" 2>&1
        # AC1: 家老にDEPLOY-STALL通知
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo \
          "【DEPLOY-STALL】${name}が${task_status}のままidle ${elapsed}秒。/clear+再送実施。" \
          deploy_stall ninja_monitor >> "$LOG" 2>&1
        # AC2: STALLカウンター+エスカレーション
        local subtask_id
        subtask_id=$(yaml_field_get "$task_file" "subtask_id")
        local stall_count_key="${name}:${subtask_id}"
        STALL_COUNT[$stall_count_key]=$((${STALL_COUNT[$stall_count_key]:-0} + 1))
        local count=${STALL_COUNT[$stall_count_key]}
        if [ "$count" -ge 2 ]; then
            bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo \
              "【STALL-ESCALATE】${name}が${subtask_id}で${count}回STALL。差し替え必須。" \
              stall_escalate ninja_monitor >> "$LOG" 2>&1
        fi
    else
        log "DEPLOY-STALL-WAIT: $name $task_status+idle ${elapsed}s < ${effective_debounce}s"
        PREV_STATE[$name]="busy"
    fi
    return 0
}

# idle通知（busy→idle遷移時のデバウンス付き通知）
_handle_idle_notify() {
    local name="$1"
    local now="$2"

    [ "${PREV_STATE[$name]}" = "idle" ] && return

    local last elapsed debounce_time
    last="${LAST_NOTIFIED[$name]:-0}"
    elapsed=$((now - last))

    debounce_time=$(cli_profile_get "$name" "debounce")

    if [ "$elapsed" -ge "$debounce_time" ]; then
        log "IDLE confirmed: $name"
        NEWLY_IDLE+=("$name")
    else
        log "DEBOUNCE: $name idle but ${elapsed}s < ${debounce_time}s since last notify"
    fi
}

# idle時自動/clear（毎サイクル判定）
_handle_auto_clear() {
    local name="$1"
    local now="$2"

    local target agent_id clear_last clear_elapsed
    target="${PANE_TARGETS[$name]}"
    [ -z "$target" ] && return

    agent_id=$(tmux display-message -t "$target" -p '#{@agent_id}' 2>/dev/null)

    # CTX=0%なら既にクリア済み → スキップ（無駄な再clearループ防止）
    local ctx_now
    ctx_now=$(get_context_pct "$target" "$name")
    if [ "${ctx_now:-0}" -le 0 ] 2>/dev/null; then
        # AC3: CLEAR-SKIPカウンタ — 連続10回超で5分間隔ログ
        CLEAR_SKIP_COUNT[$name]=$(( ${CLEAR_SKIP_COUNT[$name]:-0} + 1 ))
        local skip_count=${CLEAR_SKIP_COUNT[$name]}
        if [ "$skip_count" -le 10 ]; then
            log "CLEAR-SKIP: $name CTX=${ctx_now}%, already clean (${skip_count}/10)"
        elif [ $(( skip_count % 15 )) -eq 0 ]; then
            # 15サイクル=300秒(5分)ごとにログ出力
            log "CLEAR-SKIP: $name CTX=${ctx_now}%, already clean (continuous: ${skip_count})"
        fi
        return
    fi

    # CTX>0%に変化 → カウンタリセット
    CLEAR_SKIP_COUNT[$name]=0
    clear_last="${LAST_CLEARED[$name]:-0}"
    clear_elapsed=$((now - clear_last))

    # CLI種別に応じたデバウンス（cli_profiles.yaml参照）
    local effective_debounce
    effective_debounce=$(cli_profile_get "$agent_id" "clear_debounce")

    if [ "$clear_elapsed" -ge "$effective_debounce" ]; then
        if ! can_send_clear_with_report_gate "$name" "AUTO-CLEAR"; then
            log "AUTO-CLEAR-BLOCKED: $name done but report missing, keep context"
            return
        fi
        if safe_send_clear "$target" "$name" "AUTO-CLEAR"; then
            LAST_CLEARED[$name]=$now
            # AC4: @current_taskをクリア（次ポーリングでis_task_deployed()がfalseを返すように）
            tmux set-option -p -t "$target" @current_task "" 2>/dev/null
            # cmd_583: /new後にpost_clear_cmd(e.g. /fast)を送信するためpendingセット
            if [ -n "$(cli_profile_get "$name" "post_clear_cmd")" ]; then
                POST_CLEAR_PENDING[$name]=$now
                log "POST-CLEAR-PENDING: $name queued post_clear_cmd after AUTO-CLEAR"
            fi
        fi
    else
        log "CLEAR-DEBOUNCE: $name idle+no_task but ${clear_elapsed}s < ${effective_debounce}s since last /clear"
    fi
}

# ─── idle→通知の処理（状態遷移+デバウンス） ───
# 4サブ関数に分割: _handle_post_clear_pending / _handle_deploy_stall /
#                   _handle_idle_notify / _handle_auto_clear
handle_confirmed_idle() {
    local name="$1"

    if _handle_post_clear_pending "$name"; then return; fi
    if _handle_deploy_stall "$name"; then return; fi

    local now
    now=$(date +%s)
    _handle_idle_notify "$name" "$now"
    _handle_auto_clear "$name" "$now"

    PREV_STATE[$name]="idle"
}

# ─── busy検出処理 ───
handle_busy() {
    local name="$1"

    if [ "${PREV_STATE[$name]}" = "idle" ]; then
        log "ACTIVE: $name resumed work"
    fi
    PREV_STATE[$name]="busy"
    # 作業再開 → 停滞追跡リセット + fingerprint リセット（次idle時に新鮮な判定を保証）
    unset "STALL_FIRST_SEEN[$name]"
    unset "STALL_FIRST_SEEN[deploy_stall_${name}]"
    RENUDGE_FINGERPRINT[$name]=""
}

# ─── 連想配列クリーンアップ（H1: メモリリーク防止） ───
# 長時間稼働で蓄積するinactiveキーを定期削除
_cleanup_stale_keys() {
    # アクティブエージェント集合を構築
    local -A active
    local n
    for n in "${NINJA_NAMES[@]}"; do
        active[$n]=1
    done
    active[karo]=1

    # agent名キーの配列: inactive agentのキーを削除
    local key agent_part
    for key in "${!STALL_FIRST_SEEN[@]}"; do
        agent_part="${key#deploy_stall_}"
        if [ -z "${active[$agent_part]}" ] && [ -z "${active[$key]}" ]; then
            unset "STALL_FIRST_SEEN[$key]"
        fi
    done

    # compound key (agent:task_id) の配列: agentが非アクティブなら削除
    for key in "${!STALL_NOTIFIED[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "STALL_NOTIFIED[$key]"
    done

    for key in "${!AUTO_DEPLOY_DONE[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "AUTO_DEPLOY_DONE[$key]"
    done

    for key in "${!STALL_COUNT[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "STALL_COUNT[$key]"
    done

    for key in "${!DESTRUCTIVE_WARN_LAST[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "DESTRUCTIVE_WARN_LAST[$key]"
    done
}

# ─── 停滞検知（assigned/acknowledged/in_progress+idle） ───
# 忍者がタスク受領後にペインがidle状態のまま放置された場合、家老に通知
# 閾値: assigned=15分, acknowledged=10分, in_progress=20分(progress未更新時)
check_stall() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"

    # タスクファイルなし → 追跡リセット
    if [ ! -f "$task_file" ]; then
        unset "STALL_FIRST_SEEN[$name]"
        return
    fi

    # status判定: assigned/acknowledged/in_progressのみ対象
    local status task_id
    status=$(yaml_field_get "$task_file" "status")
    task_id=$(yaml_field_get "$task_file" "subtask_id")
    [ -z "$task_id" ] && task_id=$(yaml_field_get "$task_file" "task_id")

    case "$status" in
        assigned|acknowledged)
            ;;
        in_progress)
            # progress_updated_atが最近更新されていれば作業中と判断
            local last_progress
            last_progress=$(yaml_field_get "$task_file" "progress_updated_at" "")
            if [ -n "$last_progress" ]; then
                local progress_epoch
                progress_epoch=$(date -d "$last_progress" +%s 2>/dev/null || echo "0")
                local now_epoch
                now_epoch=$(date +%s)
                local progress_age=$(( now_epoch - progress_epoch ))
                if [ $progress_age -lt 1200 ]; then
                    # 20分以内にprogress更新あり → 作業中
                    unset "STALL_FIRST_SEEN[$name]"
                    return
                fi
            fi
            ;;
        *)
            unset "STALL_FIRST_SEEN[$name]"
            return
            ;;
    esac

    # ペインがidleか確認
    local target="${PANE_TARGETS[$name]}"
    if [ -z "$target" ]; then return; fi

    if ! check_idle "$target" "$name"; then
        # busy状態 → 停滞追跡リセット
        unset "STALL_FIRST_SEEN[$name]"
        return
    fi

    # idle状態 → 停滞追跡開始 or 経過確認
    local now
    now=$(date +%s)
    if [ -z "${STALL_FIRST_SEEN[$name]}" ]; then
        STALL_FIRST_SEEN[$name]=$now
        log "STALL-WATCH: $name has ${status} task $task_id and is idle (tracking started)"
        return
    fi

    local first_seen=${STALL_FIRST_SEEN[$name]}
    local elapsed_min=$(( (now - first_seen) / 60 ))

    # statusごとの閾値分岐
    local threshold=$STALL_THRESHOLD_MIN
    case "$status" in
        acknowledged) threshold=10 ;;
        in_progress)
            threshold=$(cli_profile_get "$name" "in_progress_stall_min")
            if ! [[ "$threshold" =~ ^[0-9]+$ ]]; then
                threshold=20
            fi
            ;;
    esac

    local stall_key="${name}:${task_id}"

    if [ "$elapsed_min" -ge "$threshold" ]; then
        local last_notified=${STALL_NOTIFIED[$stall_key]:-0}
        local since_last=$((now - last_notified))
        if [ "$last_notified" -gt 0 ] && [ "$since_last" -lt "$STALL_RENOTIFY_DEBOUNCE" ]; then
            log "STALL-DEBOUNCE: $name $task_id notified ${since_last}s ago (<${STALL_RENOTIFY_DEBOUNCE}s)"
            return
        fi

        log "STALL-DETECTED: $name stalled on $task_id for ${elapsed_min}min (status=${status}), notifying karo"
        send_inbox_message karo "${name}が${task_id}で${elapsed_min}分停滞(status=${status})" stall_alert
        STALL_NOTIFIED[$stall_key]=$now

        STALL_COUNT[$stall_key]=$(( ${STALL_COUNT[$stall_key]:-0} + 1 ))
        local stall_count=${STALL_COUNT[$stall_key]}
        if [ "$stall_count" -ge "$STALL_ESCALATE_THRESHOLD" ]; then
            send_inbox_message karo "【STALL-ESCALATE】${name}が${task_id}で${stall_count}回STALL。差し替え必須。" stall_escalate
        fi

        if [ "$status" = "in_progress" ]; then
            send_inbox_message "$name" "in_progress停滞を検知。task YAMLを再確認し、作業を再開せよ。" task_assigned
            log "STALL-RECOVERY-SEND: resent task_assigned to ${name} for ${task_id}"
        fi

        unset "STALL_FIRST_SEEN[$name]"
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
        cmd_epoch=$(date -d "$cmd_timestamp" +%s 2>/dev/null || echo "0")
        if [[ ! "$cmd_epoch" =~ ^[0-9]+$ ]]; then
            log "WARN: Failed to parse cmd timestamp: ${cmd_id} ts=${cmd_timestamp} epoch=${cmd_epoch:-empty}"
            continue
        fi

        local elapsed_sec
        elapsed_sec=$((now - cmd_epoch))
        if [ $elapsed_sec -lt $STALE_CMD_THRESHOLD ]; then
            continue
        fi

        # subtask存在確認: queue/tasks/*.yaml の parent_cmd を照合
        if grep -l "parent_cmd:.*${cmd_id}" "$SCRIPT_DIR/queue/tasks/"*.yaml >/dev/null 2>&1; then
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

# ─── pending cmd検知（遷移駆動 — cmd_255改修） ───
# 新規pending cmd出現時のみ家老に1回通知。同一cmdの繰り返し送信を廃止。
# 長時間未処理のエスカレーションは check_stale_cmds() が担当。
check_karo_pending_cmd() {
    # 家老がbusyならスキップ（作業中は割り込み不要）
    if ! check_idle "$KARO_PANE" "karo"; then
        return
    fi

    # 現在のpending cmd集合を収集し、新規のみ通知
    local -a current_ids=()

    while IFS='|' read -r cmd_id cmd_timestamp; do
        [ -z "$cmd_id" ] && continue
        current_ids+=("$cmd_id")

        # 既知のpending → スキップ（遷移なし。stale_cmdsがエスカレーション担当）
        [ "${PREV_PENDING_SET[$cmd_id]:-}" = "1" ] && continue

        # stale通知済みcmdは重複回避
        [ -n "${STALE_CMD_NOTIFIED[$cmd_id]:-}" ] && continue

        # 新規pending cmd → 1回通知
        log "PENDING-CMD-NEW: ${cmd_id} -> karo (new pending detected)"
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "cmd_pending ${cmd_id} 新規pending検知。shogun_to_karo.yamlを確認し着手せよ。" cmd_pending ninja_monitor >> "$LOG" 2>&1
    done < <(list_pending_cmds)

    # PREV_PENDING_SETを現在の集合に同期
    # 消えたcmdを除去
    for old_id in "${!PREV_PENDING_SET[@]}"; do
        local found=0
        for cid in "${current_ids[@]}"; do
            [ "$old_id" = "$cid" ] && found=1 && break
        done
        if [ $found -eq 0 ]; then
            unset "PREV_PENDING_SET[$old_id]"
            log "PENDING-CMD-RESOLVED: ${old_id} no longer pending"
        fi
    done
    # 新規を追加
    for cid in "${current_ids[@]}"; do
        PREV_PENDING_SET[$cid]="1"
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
    output=$(tmux capture-pane -t "$target" -p -J -S -20 2>/dev/null)
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

# ─── 未読メッセージのfingerprint算出 (cmd_255) ───
# unread msg IDのsort後hash。countではなくID集合をキー化(L029)。
# $1: inbox_file path
# 出力: md5 hash文字列（未読0件なら空文字）
get_unread_fingerprint() {
    local inbox_file="$1"
    [ ! -f "$inbox_file" ] && echo "" && return

    local ids
    ids=$(awk '
        /^[[:space:]]*id:/ { current_id = $2 }
        /read:[[:space:]]*false/ { if (current_id != "") print current_id }
    ' "$inbox_file" 2>/dev/null | sort | tr '\n' '|')

    if [ -z "$ids" ]; then
        echo ""
        return
    fi
    echo "$ids" | md5sum | cut -d' ' -f1
}

# ─── 未読放置検知+再nudge (cmd_188→cmd_255状態遷移化) ───
# 状態遷移ベース: fingerprint変化時のみ即送信、同一fingerprint時はバックオフ安全網
# inbox_watcherとの二重経路増幅(L029)を抑止する
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
    local now
    now=$(date +%s)

    for name in "${all_agents[@]}"; do
        local inbox_file="$SCRIPT_DIR/queue/inbox/${name}.yaml"

        # inbox file存在チェック
        if [ ! -f "$inbox_file" ]; then
            RENUDGE_FINGERPRINT[$name]=""
            RENUDGE_COUNT[$name]=0
            continue
        fi

        # 未読メッセージ数をカウント
        local unread_count
        unread_count=$(count_unread_messages "$inbox_file")
        # 防御: 非数値は0に強制変換
        [[ ! "$unread_count" =~ ^[0-9]+$ ]] && unread_count=0

        # 未読0 → fingerprint+カウンターリセット＆スキップ
        if [ "$unread_count" -eq 0 ]; then
            if [ -n "${RENUDGE_FINGERPRINT[$name]}" ] || [ "${RENUDGE_COUNT[$name]:-0}" -gt 0 ]; then
                log "RENUDGE-RESET: $name unread=0, fingerprint+counter reset"
            fi
            RENUDGE_FINGERPRINT[$name]=""
            RENUDGE_COUNT[$name]=0
            continue
        fi

        # ペインターゲット取得
        local target
        if [ "$name" = "karo" ]; then
            target="$KARO_PANE"
        else
            target="${PANE_TARGETS[$name]}"
        fi
        [ -z "$target" ] && continue

        # idle判定（busy → skip：作業中はいずれinboxを処理する）
        if ! check_idle "$target" "$name"; then
            continue
        fi

        # fingerprint算出（L029: unread ID集合のsort後hash）
        local current_fp
        current_fp=$(get_unread_fingerprint "$inbox_file")
        local prev_fp="${RENUDGE_FINGERPRINT[$name]:-}"

        # ─── 状態遷移判定 (cmd_255) ───
        if [ "$current_fp" != "$prev_fp" ]; then
            # fingerprint変化 = 新規未読出現 or 既読化で集合変化 → 即送信
            log "RENUDGE-TRANSITION: $name fingerprint changed (unread=$unread_count), sending inbox${unread_count}"
            safe_send_keys_atomic "$target" "inbox${unread_count}" 0.3
            RENUDGE_FINGERPRINT[$name]="$current_fp"
            RENUDGE_LAST_SEND[$name]=$now
            RENUDGE_COUNT[$name]=1
        else
            # 同一fingerprint = 未読集合変化なし → バックオフ再通知判定
            local last_send="${RENUDGE_LAST_SEND[$name]:-0}"
            local elapsed=$((now - last_send))
            local count="${RENUDGE_COUNT[$name]:-0}"

            # AC3: 家老は60秒バックオフで優先re-nudge（忍者のRENUDGE_BACKOFFより短い）
            if [ "$name" = "karo" ] && [ $elapsed -ge 60 ]; then
                log "RENUDGE-KARO-PRIORITY: karo idle+unread=$unread_count, priority re-nudge (${elapsed}s >= 60s)"
                safe_send_keys_atomic "$target" "inbox${unread_count}" 0.3
                RENUDGE_LAST_SEND[$name]=$now
                RENUDGE_COUNT[$name]=$((count + 1))
            elif [ "$count" -ge "$MAX_RENUDGE" ]; then
                # 上限到達 → ログのみ（5サイクルに1回）
                if [ $((cycle % 5)) -eq 0 ]; then
                    log "RENUDGE-MAX: $name reached MAX_RENUDGE=$MAX_RENUDGE (unread=$unread_count)"
                fi
            elif [ $elapsed -ge $RENUDGE_BACKOFF ]; then
                # バックオフ期間経過 → 安全網の低頻度再通知
                log "RENUDGE-BACKOFF: $name same fingerprint but ${elapsed}s >= ${RENUDGE_BACKOFF}s, safety re-nudge ($((count+1))/$MAX_RENUDGE)"
                safe_send_keys_atomic "$target" "inbox${unread_count}" 0.3
                RENUDGE_LAST_SEND[$name]=$now
                RENUDGE_COUNT[$name]=$((count + 1))
            fi
            # else: バックオフ期間内 → 何もしない（同一状態の繰り返し送信を止める）
        fi
    done
}

# ─── context_pct更新（単一ペイン） ───
# get_context_pctのthin wrapper。デフォルト"--"を設定後、再パースで上書き。
# 引数: $1=pane_target (例: shogun:2.4), $2=agent_name（省略時はフォールバック）
# 戻り値: 0=更新成功, 1=失敗(--設定)
update_context_pct() {
    local pane_target="$1"
    local agent_name="$2"
    # デフォルト値設定後、get_context_pctで再パース
    # get_context_pctが成功すれば@context_pctを上書き、失敗すれば"--"が残る
    tmux set-option -p -t "$pane_target" @context_pct "--" 2>/dev/null
    get_context_pct "$pane_target" "$agent_name" > /dev/null
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
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')

    # flock排他制御（他プロセスが読み書きする可能性に備える）
    # S04修正: サブシェル→ブレースグループ（fd継承によるロック漏洩を回避）
    {
        if ! flock -x -w 5 200; then
            log "ERROR: write_state_file flock failed"
        else
            # YAML生成
            echo "updated_at: \"$timestamp\"" > "$state_file"
            echo "agents:" >> "$state_file"

            # 家老
            local karo_status="unknown"
            check_idle "$KARO_PANE" "karo" && karo_status="idle" || karo_status="busy"
            local karo_ctx
            karo_ctx=$(get_context_pct "$KARO_PANE" "karo")
            echo "  karo:" >> "$state_file"
            echo "    pane: \"$KARO_PANE\"" >> "$state_file"
            echo "    status: $karo_status" >> "$state_file"
            echo "    ctx_pct: $karo_ctx" >> "$state_file"
            echo "    last_task: \"\"" >> "$state_file"

            # 忍者
            for name in "${NINJA_NAMES[@]}"; do
                local target="${PANE_TARGETS[$name]}"
                if [ -z "$target" ]; then continue; fi

                local status="${PREV_STATE[$name]:-unknown}"
                local ctx
                ctx=$(get_context_pct "$target" "$name")
                local last_task
                last_task=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${name}.yaml" "task_id")
                [ -z "$last_task" ] && last_task=""

                echo "  ${name}:" >> "$state_file"
                echo "    pane: \"$target\"" >> "$state_file"
                echo "    status: $status" >> "$state_file"
                echo "    ctx_pct: $ctx" >> "$state_file"
                echo "    last_task: \"$last_task\"" >> "$state_file"
            done
        fi
    } 200>"$lock_file"
}

# ─── ntfy_listenerヘルスチェック (cmd_635) ───
# ログの最終行タイムスタンプが古ければゾンビ判定→再起動
check_ntfy_listener_health() {
    local log_file="$SCRIPT_DIR/logs/ntfy_listener.log"

    # ログが存在しない場合はスキップ（listenerが未起動）
    if [ ! -f "$log_file" ]; then
        return 0
    fi

    # 最終行からタイムスタンプを抽出 [Sat Mar  7 03:52:40 JST 2026]
    local last_line
    last_line=$(tail -1 "$log_file" 2>/dev/null || true)
    if [ -z "$last_line" ]; then
        return 0
    fi

    # [Day Mon DD HH:MM:SS TZ YYYY] 形式からタイムスタンプ部分を抽出
    local ts_str
    ts_str=$(echo "$last_line" | grep -oP '\[\K[A-Za-z]+ [A-Za-z]+ +\d+ \d+:\d+:\d+ [A-Z]+ \d+' | head -1)
    if [ -z "$ts_str" ]; then
        return 0
    fi

    # epoch秒に変換
    local log_epoch
    log_epoch=$(date -d "$ts_str" +%s 2>/dev/null || true)
    if [ -z "$log_epoch" ]; then
        return 0
    fi

    local now
    now=$(date +%s)
    local age_min=$(( (now - log_epoch) / 60 ))

    # しきい値以内なら正常 — 何もしない
    if [ "$age_min" -lt "$NTFY_HEALTH_THRESHOLD_MIN" ]; then
        return 0
    fi

    # 連続再起動防止: クールダウン期間内ならスキップ
    local cooldown_sec=$((NTFY_RESTART_COOLDOWN_MIN * 60))
    if [ $((now - LAST_NTFY_RESTART)) -lt "$cooldown_sec" ]; then
        return 0
    fi

    log "WARNING: ntfy_listener log stale (${age_min}min old). Restarting..."
    bash "$SCRIPT_DIR/scripts/restart_ntfy_listener.sh" >> "$LOG" 2>&1 || true
    LAST_NTFY_RESTART=$(date +%s)
    log "ntfy_listener restart triggered by health check"
}

# ─── 家老陣形図(karo_snapshot) — 家老/clear復帰用の圧縮状態 ───
write_karo_snapshot() {
    local snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
    local lock_file="/tmp/karo_snapshot.lock"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')

    # S04修正: サブシェル→ブレースグループ（fd継承によるロック漏洩を回避）
    {
        if ! flock -x -w 5 200; then
            log "ERROR: write_karo_snapshot flock failed"
        else
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
                        /^- id:/ {
                            emit()
                            cmd_id=$3; gsub(/"/, "", cmd_id)
                            cmd_status=""; cmd_purpose=""
                            next
                        }
                        /^  status:/ { cmd_status=$2; next }
                        /^  purpose:/ {
                            cmd_purpose=$0
                            sub(/^  purpose:[[:space:]]*"?/, "", cmd_purpose)
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
                        task_id=$(yaml_field_get "$task_file" "task_id")
                        status=$(yaml_field_get "$task_file" "status")
                        project=$(yaml_field_get "$task_file" "project")
                        echo "ninja|${name}|${task_id:-none}|${status:-idle}|${project:-none}"
                    else
                        echo "ninja|${name}|none|idle|none"
                    fi
                done

                # 報告状態
                for name in "${NINJA_NAMES[@]}"; do
                    local report_file=""
                    report_file=$(get_latest_report_file "$name" || true)
                    if [ -n "$report_file" ] && [ -f "$report_file" ]; then
                        local report_task report_status
                        report_task=$(yaml_field_get "$report_file" "task_id")
                        report_status=$(yaml_field_get "$report_file" "status")
                        [ -n "$report_task" ] && echo "report|${name}|${report_task}|${report_status:-unknown}"
                    fi
                done

                # idle一覧（cmd_519: round-robin回転ポインタ順）
                local rr_last=""
                local rr_file="$SCRIPT_DIR/queue/rr_pointer.txt"
                if [ -f "$rr_file" ]; then
                    rr_last=$(head -1 "$rr_file" 2>/dev/null | tr -d '[:space:]')
                fi

                # 回転順NINJA_NAMES配列を構築
                local rotated_names=()
                if [ -n "$rr_last" ]; then
                    local rr_idx=-1
                    for i in "${!NINJA_NAMES[@]}"; do
                        if [ "${NINJA_NAMES[$i]}" = "$rr_last" ]; then
                            rr_idx=$i
                            break
                        fi
                    done
                    if [ "$rr_idx" -ge 0 ]; then
                        local total=${#NINJA_NAMES[@]}
                        for (( j=1; j<=total; j++ )); do
                            rotated_names+=("${NINJA_NAMES[$(( (rr_idx + j) % total ))]}")
                        done
                    else
                        rotated_names=("${NINJA_NAMES[@]}")
                    fi
                else
                    rotated_names=("${NINJA_NAMES[@]}")
                fi

                local idle_list=""
                for name in "${rotated_names[@]}"; do
                    if [ "${PREV_STATE[$name]}" = "idle" ]; then
                        local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
                        local task_status=""
                        if [ -f "$task_file" ]; then
                            task_status=$(yaml_field_get "$task_file" "status")
                        fi
                        if [ "$task_status" != "in_progress" ] && [ "$task_status" != "acknowledged" ] && [ "$task_status" != "assigned" ]; then
                            idle_list="${idle_list}${name},"
                        fi
                    fi
                done
                idle_list="${idle_list%,}"
                echo "idle|${idle_list:-none}"

            } > "$snapshot_file"
        fi
    } 200>"$lock_file"
}

# ─── 家老/clear送信共通関数（全コードパスで使用） ───
# デバウンスを内蔵。呼び出し元がデバウンスを気にする必要なし。
# $1: ctx_num（ログ用）, $2: caller（ログ用、省略可）
# 戻り値: 0=送信成功, 1=デバウンスで抑制
send_karo_clear() {
    local ctx_num="${1:-?}"
    local caller="${2:-check_karo_clear}"
    local now
    now=$(date +%s)
    local elapsed=$((now - LAST_KARO_CLEAR))

    if [ $elapsed -lt $KARO_CLEAR_DEBOUNCE ]; then
        log "KARO-CLEAR-DEBOUNCE(${caller}): CTX:${ctx_num}% but ${elapsed}s < ${KARO_CLEAR_DEBOUNCE}s"
        return 1
    fi

    # 陣形図を最終更新（鮮度保証）
    write_karo_snapshot

    if ! safe_send_clear "$KARO_PANE" "karo" "KARO-CLEAR(${caller})"; then
        return 1
    fi
    LAST_KARO_CLEAR=$now
    # AC4: /clear後にdebounceファイルを削除（inbox_watcherの再送をブロックしない）
    rm -f "/tmp/inbox_watcher_last_nudge_karo"

    # /clear後の復帰nudge — 家老が空プロンプトでidle化するのを防ぐ
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "/clear復帰。karo_snapshot.txtを読んで作業再開せよ。" clear_recovery ninja_monitor

    return 0
}

# ─── STEP 2: 家老の外部/clearトリガー ───
check_karo_clear() {
    # idle判定
    if ! check_idle "$KARO_PANE" "karo"; then
        return  # busy or error → skip
    fi

    # CTX取得
    local ctx_num
    ctx_num=$(get_context_pct "$KARO_PANE" "karo")
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
    local ctx_num
    ctx_num=$(get_context_pct "$shogun_pane" "shogun")
    if [ -z "$ctx_num" ] || [ "$ctx_num" -le 50 ] 2>/dev/null; then
        return  # CTX <= 50% → skip
    fi

    # デバウンスチェック
    local now
    now=$(date +%s)
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
# cmd_320改修: CLIの実モデル値を検出し、@model_nameと比較。不整合があれば自動修正。
# 実モデル検出失敗時はsettings.yaml/cli_profiles.yamlにフォールバック（AC3）。
check_model_names() {
    local all_agents=("karo" "${NINJA_NAMES[@]}")

    for name in "${all_agents[@]}"; do
        local target
        if [ "$name" = "karo" ]; then
            target="$KARO_PANE"
        else
            target="${PANE_TARGETS[$name]}"
        fi
        [ -z "$target" ] && continue

        # 実モデル検出を試行（AC1: /model切替後のリアルタイム同期）
        local expected
        expected=$(detect_real_model "$name" "$target" 2>/dev/null) || expected=""

        # AC3: 実モデル検出失敗時はsettings.yaml/cli_profiles.yamlにフォールバック
        if [ -z "$expected" ]; then
            expected=$(cli_profile_get "$name" "display_name")
            if [ -z "$expected" ]; then
                expected=$(cli_type "$name")
            fi
        fi

        # 現在値
        local current
        current=$(tmux show-options -p -t "$target" -v @model_name 2>/dev/null || echo "")

        # 整合性チェック + 自動修正（model_name）
        if [ "$current" != "$expected" ]; then
            tmux set-option -p -t "$target" @model_name "$expected" 2>/dev/null
            log "MODEL_NAME_FIX: $name ${current:-<empty>} -> $expected"
        fi

        # bg_color検証（model_nameの一致/不一致に関わらず毎回チェック）
        local expected_bg
        expected_bg=$(resolve_bg_color "$name" "$expected")
        local current_bg
        current_bg=$(tmux show-options -p -t "$target" -v @bg_color 2>/dev/null || echo "")
        # @bg_colorが未設定の場合、実際のペインスタイルからも取得を試みる
        if [ -z "$current_bg" ]; then
            current_bg=$(tmux show-options -p -t "$target" -v "window-style" 2>/dev/null | grep -oP 'bg=#[0-9a-f]+' | head -1 | sed 's/bg=//' || echo "")
        fi
        if [ "$current_bg" != "$expected_bg" ]; then
            tmux select-pane -t "$target" -P "bg=${expected_bg}" 2>/dev/null
            tmux set-option -p -t "$target" @bg_color "$expected_bg" 2>/dev/null
            log "BG_COLOR_FIX: $name ${current_bg:-<empty>} -> $expected_bg (model=$expected)"
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
            target="$KARO_PANE"
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


# ─── lesson health定期チェック (cmd_279 Gate3) ───
# gate_lesson_health.shを呼び出し、ALERTなら家老に通知
LAST_LESSON_CHECK=0
LESSON_CHECK_INTERVAL=600  # 10分間隔(秒)
LESSON_ALERT_DEBOUNCE=21600 # 同一ALERT再通知抑制(6時間)
LAST_LESSON_ALERT=0

# ─── gate_improvement定期チェック (cmd_1114) ───
LAST_GATE_IMPROVEMENT=0
GATE_IMPROVEMENT_INTERVAL=300  # 5分間隔(秒)

check_lesson_health() {
    local now
    now=$(date +%s)

    # 間隔チェック
    local elapsed=$((now - LAST_LESSON_CHECK))
    if [ $elapsed -lt $LESSON_CHECK_INTERVAL ]; then
        return
    fi
    LAST_LESSON_CHECK=$now

    local gate_script="$SCRIPT_DIR/scripts/gates/gate_lesson_health.sh"
    if [ ! -f "$gate_script" ]; then
        log "LESSON-HEALTH: gate_lesson_health.sh not found, skip"
        return
    fi

    local output
    output=$(bash "$gate_script" 2>/dev/null) || true

    # ALERTがあるか確認
    if echo "$output" | grep -q "^ALERT:"; then
        # デバウンスチェック
        local alert_elapsed=$((now - LAST_LESSON_ALERT))
        if [ $alert_elapsed -lt $LESSON_ALERT_DEBOUNCE ]; then
            log "LESSON-HEALTH-DEBOUNCE: ALERT detected but ${alert_elapsed}s < ${LESSON_ALERT_DEBOUNCE}s"
            return
        fi

        local alerts
        alerts=$(echo "$output" | grep "^ALERT:" | tr '\n' ' ')
        log "LESSON-HEALTH: $alerts"
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "lesson健全性ALERT: ${alerts}" lesson_health ninja_monitor >> "$LOG" 2>&1
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "【教訓ALERT】${alerts}" >> "$LOG" 2>&1
        LAST_LESSON_ALERT=$now
    else
        log "LESSON-HEALTH: all projects OK"
    fi
}

check_gate_improvement() {
    local now
    now=$(date +%s)

    local elapsed=$((now - LAST_GATE_IMPROVEMENT))
    if [ $elapsed -lt $GATE_IMPROVEMENT_INTERVAL ]; then
        return
    fi
    LAST_GATE_IMPROVEMENT=$now

    local gate_script="$SCRIPT_DIR/scripts/gates/gate_improvement_trigger.sh"
    if [ ! -f "$gate_script" ]; then
        log "GATE-IMPROVEMENT: gate_improvement_trigger.sh not found, skip"
        return
    fi

    bash "$gate_script" >> "$SCRIPT_DIR/logs/gate_improvement.log" 2>&1 || true
}

check_ntfy_batch_flush() {
    local now
    now=$(date +%s)

    if [ "$LAST_BATCH_FLUSH" -ne 0 ] && [ $((now - LAST_BATCH_FLUSH)) -lt "$NTFY_BATCH_FLUSH_INTERVAL" ]; then
        return
    fi

    bash "$SCRIPT_DIR/scripts/ntfy_batch_flush.sh" >> "$LOG" 2>&1 || true
    LAST_BATCH_FLUSH=$now
}

# ─── archive自動退避 (cmd_279 Gate3 Auto2) ───
# completed cmdでqueue/gates/{cmd_id}/未作成のものを自動archive
# flock排他 + 1 sweep あたり最大1 cmd
ARCHIVE_LOCK="/tmp/ninja_monitor_archive.lock"

check_auto_archive() {
    local cmd_file="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ ! -f "$cmd_file" ] && return

    # completed cmd_idを抽出
    local -a completed_cmds
    # HOTFIX 2026-03-01: cmd_*のみ抽出。AC1-AC4等のacceptance_criteria idを除外
    mapfile -t completed_cmds < <(awk '
        /^[[:space:]]*-[[:space:]]id:[[:space:]]*cmd_/ {
            cmd_id=$3; gsub(/"/, "", cmd_id)
            cmd_status=""
            next
        }
        /^[[:space:]]*status:/ {
            cmd_status=$2
            if (cmd_status == "completed" && cmd_id != "") {
                print cmd_id
            }
        }
    ' "$cmd_file")

    if [ ${#completed_cmds[@]} -eq 0 ]; then
        return
    fi

    # 1 sweepあたり最大1 cmdのみarchive
    for cmd_id in "${completed_cmds[@]}"; do
        local gates_dir="$SCRIPT_DIR/queue/gates/${cmd_id}"

        # gates/ディレクトリが既に存在 → archive済み(archive.done含む)
        if [ -d "$gates_dir" ]; then
            continue
        fi

        # flock排他制御でarchive実行（S04修正: ロックファイル引数形式でfd継承問題を回避）
        log "AUTO-ARCHIVE: $cmd_id completed + no gates dir, running archive_completed.sh"
        if flock -n "$ARCHIVE_LOCK" bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$cmd_id" >> "$LOG" 2>&1; then
            log "AUTO-ARCHIVE: $cmd_id done"
        else
            log "AUTO-ARCHIVE: flock busy or failed, skip $cmd_id"
        fi

        # 1 cmdのみ実行して終了
        break
    done
}

# ─── shogun_to_karo.yaml肥大化監視 (cmd_369 AC3) ───
YAML_SIZE_WARN_THRESHOLD=500       # 行数閾値
YAML_COMPLETED_ALERT_THRESHOLD=10  # completed cmd数閾値

check_yaml_size() {
    local cmd_file="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ ! -f "$cmd_file" ] && return

    # (1) 行数チェック
    local line_count
    line_count=$(wc -l < "$cmd_file")
    if [ "$line_count" -gt "$YAML_SIZE_WARN_THRESHOLD" ]; then
        log "[monitor] WARN: shogun_to_karo.yaml is ${line_count} lines (threshold: ${YAML_SIZE_WARN_THRESHOLD})"
    fi

    # (2) completed/done/cancelled/absorbed cmd数チェック
    # L019教訓: grep -cは0件でexit 1するのでawkで安全にカウント
    # L034教訓: インデント柔軟マッチ(固定space非依存)
    local completed_count
    completed_count=$(awk '/^[[:space:]]*status:[[:space:]]*(completed|done|cancelled|absorbed)/ {c++} END {print c+0}' "$cmd_file")
    if [ "$completed_count" -gt "$YAML_COMPLETED_ALERT_THRESHOLD" ]; then
        log "[monitor] ALERT: ${completed_count} completed cmds in shogun_to_karo.yaml — archive may be failing"
    fi
}

# ─── CDP Chrome idle連動クリーンアップ (cmd_905) ───
run_cdp_cleanup() {
    # スクリプト存在チェック（cmd_905_Aが未配備でもエラーにならない）
    if [ ! -x "$CDP_CLEANUP_SCRIPT" ]; then
        return 0
    fi

    local now
    now=$(date +%s)
    local elapsed=$((now - LAST_CDP_CLEANUP))
    if [ $elapsed -lt $CDP_CLEANUP_INTERVAL ]; then
        log "CDP-CLEANUP-DEBOUNCE: ${elapsed}s < ${CDP_CLEANUP_INTERVAL}s, skip"
        return 0
    fi

    log "CDP-CLEANUP: Running cdp_chrome_cleanup.sh (idle ninja detected)"
    if bash "$CDP_CLEANUP_SCRIPT" >> "$LOG" 2>&1; then
        log "CDP-CLEANUP: Completed successfully"
    else
        log "CDP-CLEANUP: Script exited with error (non-fatal)"
    fi
    LAST_CDP_CLEANUP=$now
}

# ─── 初期ペイン探索 ───
if [ "${NINJA_MONITOR_LIB_ONLY:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

discover_panes

# ─── メインループ ───
cycle=0
prev_idle=""
prev_gate_lines=0

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

        # shogun_to_karo.yaml肥大化監視 (cmd_369 AC3)
        check_yaml_size

        # ログローテーション (cmd_802) — 10分間隔で全ログを検査
        rotate_all_logs "$SCRIPT_DIR/logs" 10000
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
            # ═══ Stage 1: task YAML確認（三段階/clear） ═══
            _s1_task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
            if [ -f "$_s1_task_file" ]; then
                _s1_task_status=$(yaml_field_get "$_s1_task_file" "status")
                if [ "$_s1_task_status" = "acknowledged" ] || [ "$_s1_task_status" = "in_progress" ]; then
                    log "STAGE1-SKIP: $name idle but task_status=${_s1_task_status}, /clear禁止"
                    PREV_STATE[$name]="busy"
                    continue
                fi
            fi
            # ═══ Stage 1.5: レースコンディション防止ガード（OR条件） ═══
            # Guard 1: inbox未読チェック — 未処理メッセージがある = これから作業開始の可能性
            _s1_inbox_file="$SCRIPT_DIR/queue/inbox/${name}.yaml"
            if [ -f "$_s1_inbox_file" ] && grep -q "read: false" "$_s1_inbox_file" 2>/dev/null; then
                log "SKIP_CLEAR: $name has unread inbox"
                PREV_STATE[$name]="busy"
                continue
            fi
            # Guard 2: task YAML鮮度チェック — 2分以内に更新 = 配備直後の可能性
            if [ -f "$_s1_task_file" ]; then
                _s1_mtime=$(stat -c %Y "$_s1_task_file" 2>/dev/null || echo 0)
                _s1_now=$(date +%s)
                _s1_age=$((_s1_now - _s1_mtime))
                if [ "$_s1_age" -lt 120 ]; then
                    log "SKIP_CLEAR: $name recent task update (${_s1_age}s ago)"
                    PREV_STATE[$name]="busy"
                    continue
                fi
            fi
            # Stage 1通過 → Stage 2（Phase 2）へ
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

    # ═══ CDP Chrome cleanup（idle忍者検出時 cmd_905） ═══
    if [ ${#NEWLY_IDLE[@]} -gt 0 ]; then
        run_cdp_cleanup
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

    # ═══ CI赤検知チェック（5分間隔 cmd_715） ═══
    if [ $((cycle % 15)) -eq 0 ]; then
        bash "$SCRIPT_DIR/scripts/ci_status_check.sh" 2>>"$SCRIPT_DIR/logs/ci_status_check.log" || true
    fi

    # ═══ gate_improvement定期チェック（5分間隔 cmd_1114） ═══
    check_gate_improvement

    # ═══ INFOバッチ通知フラッシュ（15分間隔 cmd_960 AC2） ═══
    check_ntfy_batch_flush

    # ═══ STEP 2: 家老の外部/clearチェック ═══
    check_karo_clear

    # ═══ STEP 3: 将軍CTXアラート ═══
    check_shogun_ctx

    # ═══ Phase 3: context_pct更新（全ペイン） ═══
    update_all_context_pct

    # ═══ inbox未読数ペイン変数更新 (cmd_188) ═══
    update_inbox_counts

    # ═══ lesson健全性チェック (cmd_279) ═══
    check_lesson_health

    # ═══ archive自動退避 (cmd_279) ═══
    check_auto_archive

    # ═══ STEP 1: ninja_states.yaml 自動生成 ═══
    write_state_file
    write_karo_snapshot   # 家老陣形図更新（毎サイクル）
    check_ntfy_listener_health  # ntfy_listenerゾンビ検知 (cmd_635)

    # ═══ STEP 2: ダッシュボード自動更新 (cmd_404) ═══
    # 状態変化時のみ呼び出す（コスト最適化）
    current_idle=$(grep "^idle|" "$SCRIPT_DIR/queue/karo_snapshot.txt" 2>/dev/null | head -1 || echo "")
    current_gate_lines=$(wc -l < "$SCRIPT_DIR/logs/gate_metrics.log" 2>/dev/null || echo 0)
    current_context_warn_sig=$(
        bash "$SCRIPT_DIR/scripts/context_freshness_check.sh" --dashboard-warnings 2>/dev/null \
            | cksum | awk '{print $1 ":" $2}' || echo "missing"
    )
    if [[ "$current_idle" != "$prev_idle" || "$current_gate_lines" != "$prev_gate_lines" || "$current_context_warn_sig" != "$prev_context_warn_sig" ]]; then
        bash "$SCRIPT_DIR/scripts/dashboard_auto_section.sh" 2>/dev/null || true
        prev_idle="$current_idle"
        prev_gate_lines="$current_gate_lines"
        prev_context_warn_sig="$current_context_warn_sig"
    fi

    # ═══ 連想配列クリーンアップ（10分間隔 H1: メモリリーク防止） ═══
    if [ $((cycle % 30)) -eq 0 ]; then
        _cleanup_stale_keys
    fi

    # ═══ Self-restart check ═══
    check_script_update
done
