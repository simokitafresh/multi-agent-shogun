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
source "$SCRIPT_DIR/scripts/lib/model_detect.sh"
source "$SCRIPT_DIR/scripts/lib/field_get.sh"

source "$SCRIPT_DIR/scripts/lib/model_colors.sh"

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
# saizo pane 7 (cmd_403: gunshi凍結→saizo復帰)
NINJA_NAMES=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)

mkdir -p "$SCRIPT_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
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
declare -A STALL_NOTIFIED    # 停滞通知済みフラグ — key: "ninja:task_id", value: "1"
declare -A STALE_CMD_NOTIFIED  # stale cmd最終通知時刻 — key: "cmd_XXX", value: epoch秒
declare -A PENDING_CMD_NUDGE_COUNT  # pending cmd再起動nudge回数 — key: "cmd_XXX", value: count
declare -A PENDING_CMD_LAST_NUDGE   # pending cmd最終nudge時刻 — key: "cmd_XXX", value: epoch秒
declare -A CLEAR_SKIP_COUNT   # CLEAR-SKIPカウンタ — 忍者ごとの連続回数（AC3: ログ抑制用）
declare -A DESTRUCTIVE_WARN_LAST  # 破壊コマンド検知 — key: "ninja:pattern_id", value: epoch秒
declare -A RENUDGE_COUNT          # 未読再nudgeカウンター — key: agent_name, value: 連続再nudge回数
declare -A RENUDGE_FINGERPRINT    # 未読IDのfingerprint — key: agent_name, value: md5 hash (L029: ID集合ベース)
declare -A RENUDGE_LAST_SEND      # 最終renudge送信時刻 — key: agent_name, value: epoch秒
declare -A PREV_PENDING_SET       # 前回認識したpending cmd集合 — key: cmd_id, value: "1"
declare -A AUTO_DEPLOY_DONE       # auto_deploy_next.sh呼出済みフラグ — key: "ninja:task_id", value: "1"
PREV_PANE_MISSING=""              # ペイン消失 — 前回の消失忍者リスト（重複送信防止）

# 案A: PREV_STATE初期化（起動直後のidle→idle通知を防止）
for name in "${NINJA_NAMES[@]}"; do
    PREV_STATE[$name]="idle"
done

MAX_RENUDGE=5               # 未読再nudge上限回数（同一未読状態に対して）
RENUDGE_BACKOFF=600         # 低頻度バックオフ再通知間隔（10分=600秒）— 同一fingerprint時の安全網
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
            local last_active
            last_active=$(tmux display-message -t "$pane_target" -p '#{@last_active}' 2>/dev/null)
            local now
            now=$(date +%s)
            if [ -n "$last_active" ] && [ $((now - last_active)) -lt 15 ]; then
                return 1  # grace period内はBUSY扱い（thinking中の誤判定防止）
            fi
            return 0  # IDLE確定（grace period経過）
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
        busy_pat="esc to interrupt|Running|Streaming|background terminal running|thinking|thought for"
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

get_latest_report_file() {
    local name="$1"
    local legacy_report="$SCRIPT_DIR/queue/reports/${name}_report.yaml"
    local latest_cmd_report=""

    latest_cmd_report=$(ls -1t "$SCRIPT_DIR/queue/reports/${name}_report_cmd"*.yaml 2>/dev/null | head -1 || true)
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

    local report_filename report_path
    report_filename=$(resolve_expected_report_file "$name")
    if [[ "$report_filename" = /* ]]; then
        report_path="$report_filename"
    else
        report_path="$SCRIPT_DIR/queue/reports/${report_filename}"
    fi

    if [ -f "$report_path" ]; then
        return 0
    fi

    log "REPORT-MISSING-BLOCK: $name done but no report at $report_filename (${trigger})"
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
                sed -i "s/status:\s*\(assigned\|acknowledged\|in_progress\)/status: done/" "$task_file"
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

        if [[ "$task_status" =~ ^(assigned|acknowledged|in_progress)$ ]]; then
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
                    yaml_status="${task_status}"
                    log "STALE-TASK: $name has YAML status=$yaml_status but pane is idle, treating as not deployed"
                    return 1  # Stale — treat as not deployed
                fi
            fi
            return 0  # タスク配備済み（active or ペインチェック不可）
        fi
        # Bug2 fix: status=done but @current_task still set → clear it
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
        local last_task
        last_task=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${name}.yaml" "task_id")
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

    # 案E改: タスク配備済みの場合、statusに応じた分岐
    if is_task_deployed "$name"; then
        local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
        local task_status
        task_status=$(yaml_field_get "$task_file" "status")

        # in_progress = 忍者が着手済み。干渉しない
        if [ "$task_status" = "in_progress" ]; then
            log "TASK-DEPLOYED: $name in_progress, skip"
            PREV_STATE[$name]="busy"
            return
        fi

        # assigned/acknowledged = 未着手。デッドロック候補
        local now
        now=$(date +%s)
        local deploy_stall_key="deploy_stall_${name}"
        if [ -z "${STALL_FIRST_SEEN[$deploy_stall_key]}" ]; then
            STALL_FIRST_SEEN[$deploy_stall_key]=$now
            log "DEPLOY-STALL-WATCH: $name has $task_status task, idle (tracking started)"
            PREV_STATE[$name]="busy"
            return
        fi

        local first_seen=${STALL_FIRST_SEEN[$deploy_stall_key]}
        local elapsed=$((now - first_seen))
        local effective_debounce
        effective_debounce=$(cli_profile_get "$name" "clear_debounce")

        if [ "$elapsed" -ge "$effective_debounce" ]; then
            if ! can_send_clear_with_report_gate "$name" "DEPLOY-STALL-CLEAR"; then
                PREV_STATE[$name]="busy"
                return
            fi
            local reset_cmd
            reset_cmd=$(cli_profile_get "$name" "clear_cmd")
            log "DEPLOY-STALL-CLEAR: $name stalled ${elapsed}s with $task_status task, sending $reset_cmd"
            local target="${PANE_TARGETS[$name]}"
            tmux send-keys -t "$target" "$reset_cmd"
            sleep 0.3
            tmux send-keys -t "$target" Enter
            unset STALL_FIRST_SEEN[$deploy_stall_key]
            # /new後にinbox nudgeで新セッションにタスクを知らせる
            sleep 2
            bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$name" "タスクYAMLを読んで作業開始せよ。" task_assigned ninja_monitor >> "$LOG" 2>&1
        else
            log "DEPLOY-STALL-WAIT: $name $task_status+idle ${elapsed}s < ${effective_debounce}s"
            PREV_STATE[$name]="busy"
        fi
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
                if ! can_send_clear_with_report_gate "$name" "AUTO-CLEAR"; then
                    log "AUTO-CLEAR-BLOCKED: $name done but report missing, keep context"
                    PREV_STATE[$name]="idle"
                    return
                fi
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
    # 作業再開 → 停滞追跡リセット + fingerprint リセット（次idle時に新鮮な判定を保証）
    unset STALL_FIRST_SEEN[$name]
    unset STALL_FIRST_SEEN["deploy_stall_${name}"]
    RENUDGE_FINGERPRINT[$name]=""
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
    status=$(yaml_field_get "$task_file" "status")
    task_id=$(yaml_field_get "$task_file" "task_id")

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

# ─── pending cmd検知（遷移駆動 — cmd_255改修） ───
# 新規pending cmd出現時のみ家老に1回通知。同一cmdの繰り返し送信を廃止。
# 長時間未処理のエスカレーションは check_stale_cmds() が担当。
check_karo_pending_cmd() {
    local karo_pane="shogun:2.1"

    # 家老がbusyならスキップ（作業中は割り込み不要）
    check_idle "$karo_pane" "karo"
    if [ $? -ne 0 ]; then
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
            unset PREV_PENDING_SET[$old_id]
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
    local now=$(date +%s)

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

        # fingerprint算出（L029: unread ID集合のsort後hash）
        local current_fp
        current_fp=$(get_unread_fingerprint "$inbox_file")
        local prev_fp="${RENUDGE_FINGERPRINT[$name]:-}"

        # ─── 状態遷移判定 (cmd_255) ───
        if [ "$current_fp" != "$prev_fp" ]; then
            # fingerprint変化 = 新規未読出現 or 既読化で集合変化 → 即送信
            log "RENUDGE-TRANSITION: $name fingerprint changed (unread=$unread_count), sending inbox${unread_count}"
            tmux send-keys -t "$target" "inbox${unread_count}" Enter
            RENUDGE_FINGERPRINT[$name]="$current_fp"
            RENUDGE_LAST_SEND[$name]=$now
            RENUDGE_COUNT[$name]=1
        else
            # 同一fingerprint = 未読集合変化なし → バックオフ再通知判定
            local last_send="${RENUDGE_LAST_SEND[$name]:-0}"
            local elapsed=$((now - last_send))
            local count="${RENUDGE_COUNT[$name]:-0}"

            if [ "$count" -ge "$MAX_RENUDGE" ]; then
                # 上限到達 → ログのみ（5サイクルに1回）
                if [ $((cycle % 5)) -eq 0 ]; then
                    log "RENUDGE-MAX: $name reached MAX_RENUDGE=$MAX_RENUDGE (unread=$unread_count)"
                fi
            elif [ $elapsed -ge $RENUDGE_BACKOFF ]; then
                # バックオフ期間経過 → 安全網の低頻度再通知
                log "RENUDGE-BACKOFF: $name same fingerprint but ${elapsed}s >= ${RENUDGE_BACKOFF}s, safety re-nudge ($((count+1))/$MAX_RENUDGE)"
                tmux send-keys -t "$target" "inbox${unread_count}" Enter
                RENUDGE_LAST_SEND[$name]=$now
                RENUDGE_COUNT[$name]=$((count + 1))
            fi
            # else: バックオフ期間内 → 何もしない（同一状態の繰り返し送信を止める）
        fi
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
            local last_task
            last_task=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${name}.yaml" "task_id")
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
# cmd_320改修: CLIの実モデル値を検出し、@model_nameと比較。不整合があれば自動修正。
# 実モデル検出失敗時はsettings.yaml/cli_profiles.yamlにフォールバック（AC3）。
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

# ─── lesson health定期チェック (cmd_279 Gate3) ───
# gate_lesson_health.shを呼び出し、ALERTなら家老に通知
LAST_LESSON_CHECK=0
LESSON_CHECK_INTERVAL=600  # 10分間隔(秒)
LESSON_ALERT_DEBOUNCE=21600 # 同一ALERT再通知抑制(6時間)
LAST_LESSON_ALERT=0

check_lesson_health() {
    local now=$(date +%s)

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

# ─── archive自動退避 (cmd_279 Gate3 Auto2) ───
# completed cmdでqueue/gates/{cmd_id}/未作成のものを自動archive
# flock排他 + 1 sweep あたり最大1 cmd
ARCHIVE_LOCK="/tmp/ninja_monitor_archive.lock"

check_auto_archive() {
    local cmd_file="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ ! -f "$cmd_file" ] && return

    # completed cmd_idを抽出
    local -a completed_cmds
    mapfile -t completed_cmds < <(awk '
        /^[[:space:]]*-[[:space:]]id:/ {
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

        # flock排他制御でarchive実行
        (
            flock -n 200 || { log "AUTO-ARCHIVE: flock busy, skip $cmd_id"; exit 1; }
            log "AUTO-ARCHIVE: $cmd_id completed + no gates dir, running archive_completed.sh"
            bash "$SCRIPT_DIR/scripts/archive_completed.sh" "$cmd_id" >> "$LOG" 2>&1
        ) 200>"$ARCHIVE_LOCK"

        if [ $? -eq 0 ]; then
            log "AUTO-ARCHIVE: $cmd_id done"
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

# ─── 初期ペイン探索 ───
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

    # ═══ lesson健全性チェック (cmd_279) ═══
    check_lesson_health

    # ═══ archive自動退避 (cmd_279) ═══
    check_auto_archive

    # ═══ STEP 1: ninja_states.yaml 自動生成 ═══
    write_state_file
    write_karo_snapshot   # 家老陣形図更新（毎サイクル）

    # ═══ STEP 2: ダッシュボード自動更新 (cmd_404) ═══
    # 状態変化時のみ呼び出す（コスト最適化）
    current_idle=$(grep "^idle|" "$SCRIPT_DIR/queue/karo_snapshot.txt" 2>/dev/null | head -1 || echo "")
    current_gate_lines=$(wc -l < "$SCRIPT_DIR/logs/gate_metrics.log" 2>/dev/null || echo 0)
    if [[ "$current_idle" != "$prev_idle" || "$current_gate_lines" != "$prev_gate_lines" ]]; then
        bash "$SCRIPT_DIR/scripts/dashboard_auto_section.sh" 2>/dev/null || true
        prev_idle="$current_idle"
        prev_gate_lines="$current_gate_lines"
    fi

    # ═══ Self-restart check ═══
    check_script_update
done
