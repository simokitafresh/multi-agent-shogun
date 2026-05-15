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
TRAINING_EFFECT_LOG="$SCRIPT_DIR/logs/training_effect.log"  # 修行before/after FAIL率比較ログ (cmd_2767)
STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
source "$SCRIPT_DIR/scripts/lib/model_detect.sh"
source "$SCRIPT_DIR/scripts/lib/model_resolve.sh"
source "$SCRIPT_DIR/scripts/lib/field_get.sh"
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
source "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
source "$SCRIPT_DIR/lib/agent_state.sh"
source "$SCRIPT_DIR/lib/rotate_log.sh"
source "$SCRIPT_DIR/lib/cli_adapter.sh"

source "$SCRIPT_DIR/scripts/lib/model_colors.sh"
source "$SCRIPT_DIR/scripts/lib/script_update.sh"
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"

# --- Variables needed by lib functions (outside guard for lib-only mode) ---
STALL_THRESHOLD_MIN=${STALL_THRESHOLD_MIN:-10} # 停滞検知しきい値（分）— assigned+idle状態がこの時間継続で通知 (cmd_1105: 15→10分に短縮)

# --- lib-only mode: skip daemon initialization (tmux/settings依存) ---
if [ "${NINJA_MONITOR_LIB_ONLY:-0}" != "1" ]; then

POLL_INTERVAL=20    # ポーリング間隔（秒）
CONFIRM_WAIT=5      # idle確認待ち（秒）— Phase 2a base wait
STALE_CMD_THRESHOLD=14400 # stale cmd検知しきい値（秒）— pending+subtask未配備が4時間継続で通知
NTFY_HEALTH_THRESHOLD_MIN=10 # ntfy_listenerヘルスチェックしきい値（分）— ログが古ければゾンビ判定
NTFY_RESTART_COOLDOWN_MIN=5  # ntfy_listener連続再起動防止クールダウン（分）
REDISCOVER_EVERY=30 # N回ポーリングごとにペイン再探索
# 家老ペインターゲット（@agent_idから動的解決。EH6: ハードコード排除完了）
KARO_PANE=$(tmux list-panes -t shogun:agents -F 'shogun:agents.#{pane_index}' -f '#{==:#{@agent_id},karo}' 2>/dev/null | head -1)
KARO_PANE="${KARO_PANE:-shogun:agents.1}"  # fallback
# 軍師ペインターゲット（@agent_idから動的解決）
GUNSHI_PANE=$(tmux list-panes -t shogun:agents -F 'shogun:agents.#{pane_index}' -f '#{==:#{@agent_id},gunshi}' 2>/dev/null | head -1)
GUNSHI_PANE="${GUNSHI_PANE:-}"  # 軍師不在時は空（処理スキップ）
NTFY_BATCH_FLUSH_INTERVAL=900 # INFOバッチ通知フラッシュ間隔（秒）

# Self-restart on script change (inbox_watcher.shから移植)
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_HASH="$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null)"
STARTUP_TIME="$EPOCHSECONDS"
MIN_UPTIME=10  # minimum seconds before allowing auto-restart
WATCHED_DEPS=(
    "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
    "$SCRIPT_DIR/scripts/lib/model_detect.sh"
    "$SCRIPT_DIR/scripts/lib/field_get.sh"
    "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
    "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
    "$SCRIPT_DIR/lib/agent_state.sh"
    "$SCRIPT_DIR/lib/rotate_log.sh"
    "$SCRIPT_DIR/scripts/lib/model_colors.sh"
    "$SCRIPT_DIR/scripts/lib/agent_config.sh"
)
DEPS_HASH="$(compute_deps_hash)"
LAST_NTFY_RESTART=0  # ntfy_listener最終再起動時刻（epoch秒）
LAST_NTFY_HEALTH_CHECK=$EPOCHSECONDS  # ntfy_listener health check最終実行時刻（epoch秒）
NTFY_HEALTH_CHECK_INTERVAL=300        # ntfy_listener health check間隔（秒）
LAST_WATCHER_RESTART=0  # inbox_watcher最終再起動時刻（epoch秒）
WATCHER_RESTART_COOLDOWN_MIN=3  # inbox_watcher連続再起動防止クールダウン（分）
LAST_BATCH_FLUSH=0   # ntfy_batch_flush最終実行時刻（epoch秒）
CDP_CLEANUP_SCRIPT="$SCRIPT_DIR/scripts/cdp_chrome_cleanup.sh"
CDP_CLEANUP_INTERVAL=300  # CDP cleanup最小間隔（秒）— 5分
LAST_CDP_CLEANUP=0        # CDP cleanup最終実行時刻（epoch秒）
LOCK_CLEANUP_INTERVAL=3600  # /tmp lock file cleanup間隔（秒）— 1時間
LAST_LOCK_CLEANUP=0         # lock cleanup最終実行時刻（epoch秒）
BULLETIN_ARCHIVE_INTERVAL=3600  # 掲示板archive間隔（秒）— 1時間
LAST_BULLETIN_ARCHIVE=0         # 掲示板archive最終実行時刻（epoch秒）
SKILL_AUTO_IMPROVE_INTERVAL=86400  # skill_auto_improve日次実行間隔（秒）— 1日(旧7日→短縮。BLOCKパターン蓄積→防止ステップ更新を高速化)
SKILL_AUTO_IMPROVE_STATE_FILE="$STATE_DIR/shogun_skill_auto_improve.last"
LESSON_DEPRECATION_INTERVAL=86400  # effectiveness低下教訓のdeprecate候補抽出間隔（秒）— 1日
LESSON_DEPRECATION_STATE_FILE="$STATE_DIR/shogun_lesson_deprecation_candidates.last"
LESSON_DEPRECATION_LOG="$SCRIPT_DIR/logs/lesson_deprecation_candidates.log"
SCRIPT_SIZE_CHECK_INTERVAL=86400  # scripts/配下主要スクリプトの肥大化チェック間隔（秒）— 1日
SCRIPT_SIZE_CHECK_STATE_FILE="$STATE_DIR/shogun_script_size_check.last"
SCRIPT_SIZE_TREND_LOG="$SCRIPT_DIR/logs/script_size_trend.log"
SCRIPT_SIZE_LINE_THRESHOLD=${SCRIPT_SIZE_LINE_THRESHOLD:-2500}
SCRIPT_SIZE_COMPLEXITY_THRESHOLD=${SCRIPT_SIZE_COMPLEXITY_THRESHOLD:-3000}
GATE_FAIL_PASS_TRANSITION_INTERVAL=86400  # gate_fire_log FAIL→PASS遷移率の日次記録間隔（秒）
GATE_FAIL_PASS_TRANSITION_STATE_FILE="$STATE_DIR/shogun_gate_fail_pass_transition.last"
GATE_FAIL_PASS_TRANSITION_LOG="$SCRIPT_DIR/logs/gate_fail_pass_transition.log"
TRAINING_AUTO_DEPLOY_IDLE_THRESHOLD=${TRAINING_AUTO_DEPLOY_IDLE_THRESHOLD:-600}   # 修行自動配備: idle継続しきい値（秒）— context/training-cycle.md §2
TRAINING_AUTO_DEPLOY_COOLDOWN=${TRAINING_AUTO_DEPLOY_COOLDOWN:-86400}             # 修行自動配備: 忍者別クールダウン（秒）
TRAINING_AUTO_DEPLOY_FAIL_RATE=${TRAINING_AUTO_DEPLOY_FAIL_RATE:-20}             # 直近gate FAIL率しきい値（%）
TRAINING_AUTO_DEPLOY_MIN_GATES=${TRAINING_AUTO_DEPLOY_MIN_GATES:-5}              # 直近gateサンプル不足時は修行条件成立
TRAINING_AUTO_DEPLOY_RECENT=${TRAINING_AUTO_DEPLOY_RECENT:-50}                   # 忍者別直近gate参照件数
TRAINING_AUTO_DEPLOY_STATE_PREFIX="$STATE_DIR/shogun_training_auto_deploy"
KARO_IDLE_COOLDOWN=1800   # 家老idle自走サイクルクールダウン（秒）— 30分
LAST_KARO_IDLE_NUDGE=0    # 家老idle自走サイクル最終通知時刻（epoch秒）
CI_STATUS_CACHE="UNKNOWN"       # CI statusキャッシュ値（L4-R24: GitHubAPI毎サイクル削減）
CI_STATUS_CHECK_LAST=0          # CI statusキャッシュ最終更新時刻（epoch秒）
CI_STATUS_CHECK_INTERVAL=300    # CI statusキャッシュ有効期間（秒）— 5分
CLI_DEAD_LOOP_WINDOW=300    # CLI死亡ループ防止ウィンドウ（秒）— 5分 (cmd_1851)
CLI_DEAD_LOOP_THRESHOLD=2   # CLI死亡ループ防止閾値（回）— 5分以内にN回以上でALERT (cmd_1851)

# 監視対象の忍者名リスト（karoと将軍は対象外）
# settings.yamlから動的取得（cmd_1136: ハードコード全廃）
read -ra NINJA_NAMES <<< "$(get_ninja_names)"

mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$STATE_DIR"

fi  # end NINJA_MONITOR_LIB_ONLY guard (daemon init)

log() {
    printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$1" >> "$LOG"
}

acquire_singleton_lock() {
    local pid_file="${STATE_DIR}/ninja_monitor.pid"
    local existing_pid=""

    mkdir -p "$(dirname "$pid_file")"

    if [ -f "$pid_file" ]; then
        existing_pid=$(cat "$pid_file" 2>/dev/null || true)
        if [ "$existing_pid" = "$$" ]; then
            printf '%s\n' "$$" > "$pid_file"
            return 0
        fi
        if _ninja_monitor_pid_is_live "$existing_pid"; then
            log "SINGLETON-EXIT: another ninja_monitor instance is live (pid=${existing_pid}, pid_file=${pid_file})"
            exit 0
        fi
        log "STALE-PID-REMOVED: ${pid_file} contained ${existing_pid:-empty}"
        rm -f "$pid_file"
    fi

    if ( set -o noclobber; printf '%s\n' "$$" > "$pid_file" ) 2>/dev/null; then
        trap 'if [ "$(cat "'"$pid_file"'" 2>/dev/null || true)" = "$$" ]; then rm -f "'"$pid_file"'"; fi' EXIT
        return 0
    fi

    existing_pid=$(cat "$pid_file" 2>/dev/null || true)
    if _ninja_monitor_pid_is_live "$existing_pid"; then
        log "SINGLETON-EXIT: another ninja_monitor instance won pid-file race (pid=${existing_pid}, pid_file=${pid_file})"
        exit 0
    fi

    log "STALE-PID-RACE-RECOVERY: replacing ${pid_file} after non-live pid ${existing_pid:-empty}"
    printf '%s\n' "$$" > "$pid_file"
    trap 'if [ "$(cat "'"$pid_file"'" 2>/dev/null || true)" = "$$" ]; then rm -f "'"$pid_file"'"; fi' EXIT
}

_ninja_monitor_pid_is_live() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1

    local cmdline=""
    cmdline=$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)
    [[ "$cmdline" == *"ninja_monitor.sh"* ]]
}

if [ "${NINJA_MONITOR_LIB_ONLY:-0}" != "1" ]; then
    acquire_singleton_lock
fi

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

build_pane_head_tail_excerpt() {
    local pane_target="$1"
    local capture line
    local -a first_lines=()
    local -a tail_lines=()
    local line_count=0

    capture=$(tmux capture-pane -t "$pane_target" -p -J 2>/dev/null || true)
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        line_count=$((line_count + 1))
        if [ "$line_count" -le 5 ]; then
            first_lines+=("$line")
        fi
        tail_lines+=("$line")
        if [ "${#tail_lines[@]}" -gt 5 ]; then
            tail_lines=("${tail_lines[@]:1}")
        fi
    done <<< "$capture"

    [ "$line_count" -gt 0 ] || return 1
    if [ "$line_count" -le 10 ] 2>/dev/null; then
        printf '%s\n' "${tail_lines[@]}"
        return 0
    fi

    printf '[pane head 5]\n'
    printf '%s\n' "${first_lines[@]}"
    printf '...\n[pane tail 5]\n'
    printf '%s\n' "${tail_lines[@]}"
}

append_pane_excerpt() {
    local message="$1"
    local pane_target="$2"
    local excerpt
    excerpt=$(build_pane_head_tail_excerpt "$pane_target" || true)
    if [ -n "$excerpt" ]; then
        printf '%s\n%s' "$message" "$excerpt"
    else
        printf '%s' "$message"
    fi
}

auto_commit_last_file() {
    printf '%s/.last_auto_commit\n' "${STATE_DIR:-/tmp}"
}

context_batch_commit_last_file() {
    printf '%s/.last_context_batch_commit\n' "${STATE_DIR:-/tmp}"
}

auto_commit_now_epoch() {
    printf '%s\n' "${NINJA_MONITOR_NOW:-${EPOCHSECONDS:-$(date +%s)}}"
}

auto_commit_timestamp_recent() {
    local stamp_file="$1"
    local interval_seconds="$2"
    local now last

    [ -f "$stamp_file" ] || return 1
    now="$(auto_commit_now_epoch)"
    last="$(cat "$stamp_file" 2>/dev/null || true)"
    [[ "$last" =~ ^[0-9]+$ ]] || return 1
    [ $((now - last)) -lt "$interval_seconds" ]
}

write_auto_commit_timestamp() {
    local stamp_file="$1"
    mkdir -p "$(dirname "$stamp_file")"
    auto_commit_now_epoch > "$stamp_file"
}

auto_commit_paths_from_status() {
    sed 's/^...//'
}

filter_regular_auto_commit_paths() {
    auto_commit_paths_from_status | grep -v -E '^context/[^/]*\.md$' || true
}

filter_context_batch_commit_paths() {
    auto_commit_paths_from_status | grep -E '^context/[^/]*\.md$' || true
}

auto_commit_before_clear() {
    local agent_name="$1"
    local uncommitted="$2"
    local regular_paths context_paths last_file context_last_file

    regular_paths="$(printf '%s\n' "$uncommitted" | filter_regular_auto_commit_paths)"
    context_paths="$(printf '%s\n' "$uncommitted" | filter_context_batch_commit_paths)"
    last_file="$(auto_commit_last_file)"
    context_last_file="$(context_batch_commit_last_file)"

    (
        cd "$SCRIPT_DIR" || exit

        if [ -n "${regular_paths//[[:space:]]/}" ]; then
            if auto_commit_timestamp_recent "$last_file" 1800; then
                log "AUTO-COMMIT-SKIP: $agent_name last auto-commit within 30min"
            else
                local regular_commit_paths
                regular_commit_paths="$regular_paths"
                printf '%s\n' "$regular_paths" | xargs -d '\n' git add -- 2>/dev/null || true
                # CI RED防止: instructions/変更時はgenerated filesを再生成(GA-085/089/090の真因)
                if git diff --cached --name-only | grep -q '^instructions/'; then
                    bash scripts/build_instructions.sh 2>/dev/null || true
                    git add instructions/generated/ 2>/dev/null || true
                    regular_commit_paths="${regular_commit_paths}"$'\n''instructions/generated/'
                fi
                if printf '%s\n' "$regular_commit_paths" | xargs -d '\n' git commit -m "chore: auto-commit before /clear ($agent_name) — 運用ファイル" -- 2>/dev/null; then
                    write_auto_commit_timestamp "$last_file"
                fi
            fi
        fi

        if [ -n "${context_paths//[[:space:]]/}" ]; then
            if auto_commit_timestamp_recent "$context_last_file" 3600; then
                log "CONTEXT-BATCH-COMMIT-SKIP: $agent_name last context batch commit within 1h"
            else
                printf '%s\n' "$context_paths" | xargs -d '\n' git add -- 2>/dev/null || true
                if printf '%s\n' "$context_paths" | xargs -d '\n' git commit -m "chore: batch context auto-commit before /clear ($agent_name)" -- 2>/dev/null; then
                    write_auto_commit_timestamp "$context_last_file"
                fi
            fi
        fi
    )
}

if [ "${NINJA_MONITOR_LIB_ONLY:-0}" != "1" ]; then
    log "ninja_monitor started. Monitoring ${#NINJA_NAMES[@]} ninja."
    log "Poll interval: ${POLL_INTERVAL}s, Confirm wait: ${CONFIRM_WAIT}s"
    log "CLI profiles loaded from cli_profiles.yaml via cli_lookup.sh"
fi

# ─── デバウンス・状態管理（連想配列、bash 4+） ───
declare -A LAST_NOTIFIED  # 最終通知時刻（epoch秒）
declare -A PREV_STATE     # 前回の状態: busy / idle / unknown
declare -A PANE_TARGETS   # 忍者名 → tmuxペインターゲット
declare -A LAST_CLEARED   # 最終/clear送信時刻（epoch秒）
declare -A STALL_FIRST_SEEN  # 停滞初回検知時刻（epoch秒）— assigned+idleを初めて観測した時刻
declare -A STALL_NOTIFIED    # 停滞通知時刻（epoch秒）— key: "ninja:task_id", value: epoch
declare -A STALE_CMD_NOTIFIED  # stale cmd最終通知時刻 — key: "cmd_XXX", value: epoch秒
declare -A UNDEPLOYED_CMD_NOTIFIED  # pending+delegated_at超過cmdのntfy送信済みフラグ — key: "cmd_XXX", value: epoch秒
declare -A PREV_PENDING_SET       # 前回認識したpending cmd集合 — key: cmd_id, value: "1"
_PENDING_CMDS_CACHE_CYCLE=-1   # サイクル内pending cmdsキャッシュ — 同一cycle内のpython3再起動を省略
_PENDING_CMDS_CACHE=""         # list_pending_cmdsのキャッシュ結果（同サイクル内で共有）
declare -A CLEAR_SKIP_COUNT   # CLEAR-SKIPカウンタ — 忍者ごとの連続回数（AC3: ログ抑制用）
declare -A DESTRUCTIVE_WARN_LAST  # 破壊コマンド検知 — key: "ninja:pattern_id", value: epoch秒
declare -A RENUDGE_COUNT          # 未読再nudgeカウンター — key: agent_name, value: 連続再nudge回数
declare -A RENUDGE_FINGERPRINT    # 未読IDのfingerprint — key: agent_name, value: md5 hash (L029: ID集合ベース)
declare -A RENUDGE_LAST_SEND      # 最終renudge送信時刻 — key: agent_name, value: epoch秒
declare -A AUTO_DEPLOY_DONE       # auto_deploy_next.sh呼出済みフラグ — key: "ninja:task_id", value: "1"
declare -A REPORT_GATE_SENT      # 報告フォーマットgate FAIL送信済みフラグ — key: "ninja:cmd_id", value: "1"
declare -A UNCOMMITTED_BLOCK_SENT # commit未完了BLOCK送信済みフラグ — key: "ninja:cmd_id", value: "1"
declare -A STALL_COUNT            # DEPLOY-STALL回数カウンター — key: "ninja:subtask_id", value: count
declare -A POST_CLEAR_PENDING     # /new後にpost_clear_cmd送信待ち — key: agent_name, value: epoch秒
declare -A REPORT_DONE_MISMATCH_NOTIFIED  # report done+status未idle通知時刻 — key: "ninja:cmd_id", value: epoch秒
declare -A IDLE_NOTIFY_SENT              # idle通知送信済み時刻 — key: agent_name, value: epoch秒（状態変化ベース+モード切替）
declare -A TRAINING_IDLE_FIRST_SEEN      # 修行自動配備: idle継続開始時刻 — key: agent_name, value: epoch秒
declare -A TRAINING_EFFECT_RECORDED     # 修行効果記録済みフラグ — key: "ninja:task_id", value: "1" (cmd_2767)
PREV_PANE_MISSING=""              # ペイン消失 — 前回の消失忍者リスト（重複送信防止）
declare -A CLI_DEAD_RESTART_TIMES    # CLI死亡再起動時刻リスト — key: ninja_name, value: スペース区切りepoch秒リスト (cmd_1851)
declare -A CLI_DEAD_LOOP_LAST_NTFY   # CLI-DEAD-LOOP ntfy最終送信時刻 — key: ninja_name, value: epoch秒 (ntfy flood防止)

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
REPORT_DONE_MISMATCH_DEBOUNCE=300  # report done+status未idleの同一ninja×cmd再通知抑制（5分=300秒）
IDLE_ACTIVE_COOLDOWN=300           # active mode idle再通知間隔（5分=300秒）— pipeline有時の圧力
SHOGUN_ALERT_DEBOUNCE=1800  # 将軍CTXアラート再送信抑制（30分）— 殿を煩わせない

LAST_KARO_CLEAR=0           # 家老の最終/clear送信時刻（epoch秒）
LAST_SHOGUN_ALERT=0         # 将軍の最終アラート送信時刻（epoch秒）
prev_context_warn_sig=""
prev_ci_status=""
prev_unpushed_count=""

# ─── ペインターゲット探索 ───
# tmuxの@agent_idからペインターゲットを動的に解決
discover_panes() {
    local mapping
    mapping=$(tmux list-panes -t shogun -a -F '#{window_name}.#{pane_index} #{@agent_id}' 2>/dev/null)

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
    if ! actual_agents=$(tmux list-panes -t shogun:agents -F '#{@agent_id}' 2>/dev/null) || [ -z "$actual_agents" ]; then
        log "PANE-CHECK: Failed to list panes for shogun:agents"
        return
    fi

    local missing=()
    for name in "${NINJA_NAMES[@]}"; do
        if ! echo "$actual_agents" | grep -qx "$name"; then
            missing+=("$name")
        fi
    done

    # LK009 enforcement: @agent_id重複検知+自動修復
    # 同一agent_idが複数paneに存在 = CLI再起動時の汚染
    local pane_mapping
    pane_mapping=$(tmux list-panes -t shogun:agents -F '#{pane_index} #{@agent_id}' 2>/dev/null || true)
    local -A expected_pane  # agent_name → expected pane_index (from PANE_TARGETS)
    for name in "${NINJA_NAMES[@]}"; do
        local pt="${PANE_TARGETS[$name]:-}"
        if [ -n "$pt" ]; then
            # extract pane_index from "shogun:agents.N" or "shogun:2.N"
            expected_pane[$name]="${pt##*.}"
        fi
    done
    # also check karo and gunshi
    for name in karo gunshi; do
        local pt_core=""
        pt_core=$(echo "$pane_mapping" | awk -v n="$name" '$2==n {print $1; exit}')
        if [ -n "$pt_core" ]; then
            expected_pane[$name]="$pt_core"
        fi
    done
    while read -r pidx aid; do
        [ -z "$aid" ] && continue
        local exp="${expected_pane[$aid]:-}"
        if [ -n "$exp" ] && [ "$pidx" != "$exp" ]; then
            # This pane has a wrong agent_id (belongs to another pane)
            # Find what agent should be on this pane
            local correct_agent=""
            for ca in "${!expected_pane[@]}"; do
                if [ "${expected_pane[$ca]}" = "$pidx" ]; then
                    correct_agent="$ca"
                    break
                fi
            done
            if [ -n "$correct_agent" ]; then
                log "AGENT-ID-COLLISION: pane ${pidx} has @agent_id='${aid}' but should be '${correct_agent}' → fixing"
                tmux set-option -t "shogun:agents.${pidx}" -p @agent_id "$correct_agent" 2>/dev/null || true
                tmux set-option -t "shogun:agents.${pidx}" -p @agent_state idle 2>/dev/null || true
                bash "$SCRIPT_DIR/scripts/ntfy.sh" "【@agent_id修復】pane ${pidx}: ${aid}→${correct_agent}(LK009)" 2>/dev/null || true
            fi
        fi
    done <<< "$pane_mapping"

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
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "ペイン消失: ${missing_str} (${#missing[@]}名)。OOM Kill等の可能性。tmux list-panes -t shogun:agents で確認されたし" pane_lost ninja_monitor >> "$LOG" 2>&1
    PREV_PANE_MISSING="$missing_str"
}

# ─── 長時間bashプロセス判定（cmd_1671: pstree永久BUSY化修正） ───
# CLI配下の全bashプロセスが閾値(デフォルト30分)以上実行中かチェック
# 戻り値: 0=全て長時間(閾値以上), 1=短時間プロセスあり or プロセスなし
PSTREE_LONGRUN_THRESHOLD=1800  # 30分（秒）
_all_subprocesses_long_running() {
    local pane_target="$1"
    local threshold="${2:-$PSTREE_LONGRUN_THRESHOLD}"
    local pane_pid
    pane_pid=$(tmux display-message -t "$pane_target" -p '#{pane_pid}' 2>/dev/null) || return 1
    [ -n "$pane_pid" ] || return 1

    local tree
    tree=$(pstree -A -p "$pane_pid" 2>/dev/null) || return 1

    local cli_pids
    cli_pids=$(_agent_state_extract_cli_pids "$tree") || return 1

    local found_any=false
    local cli_pid
    for cli_pid in $cli_pids; do
        local bash_pids
        bash_pids=$(_collect_bash_descendants "$cli_pid")
        local bpid
        for bpid in $bash_pids; do
            found_any=true
            local etime
            etime=$(ps -p "$bpid" -o etimes= 2>/dev/null | tr -d ' ')
            if [ -z "$etime" ] || [ "$etime" -lt "$threshold" ] 2>/dev/null; then
                return 1  # 短時間bashあり → まだBUSY
            fi
        done
    done

    $found_any && return 0 || return 1
}

_collect_bash_descendants() {
    local parent_pid="$1"
    local children child child_name
    children=$(pgrep -P "$parent_pid" 2>/dev/null || true)
    [ -n "$children" ] || return 0
    for child in $children; do
        child_name=$(ps -p "$child" -o comm= 2>/dev/null | awk 'NR==1 {print $1}')
        if [ "$child_name" = "bash" ]; then
            echo "$child"
        fi
        _collect_bash_descendants "$child"
    done
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
            now=$EPOCHSECONDS
            if [ -n "$last_active" ] && [ $((now - last_active)) -lt 15 ]; then
                return 1  # grace period内はBUSY扱い（thinking中の誤判定防止）
            fi
            # pstree cross-check: @agent_state=idleでも子プロセス存在時はBUSY
            # cmd_1671: 30分以上実行中のプロセスは除外（永久BUSY化防止）
            if _agent_state_has_busy_subprocess "$pane_target"; then
                if _all_subprocesses_long_running "$pane_target"; then
                    log "PSTREE-LONGRUN: ${agent_name} bash subprocess detected but all running >=${PSTREE_LONGRUN_THRESHOLD}s, treating as IDLE"
                else
                    # cmd_2279: task status=idle/completed/doneならbash subprocessがあっても/clearを許可
                    # GP-233: yaml_field_get→grep簡素化(WSL2 NTFS遅延でfield_getが空文字を返すバグ修正)
                    local _pstree_task_file="$SCRIPT_DIR/queue/tasks/${agent_name}.yaml"
                    local _pstree_task_status=""
                    if [ -f "$_pstree_task_file" ]; then
                        _pstree_task_status=$(grep -m1 -E '^\s*status:\s*' "$_pstree_task_file" 2>/dev/null | sed 's/.*status:\s*//' | tr -d "\"' " || true)
                    fi
                    if [[ "$_pstree_task_status" =~ ^(idle|completed|done)$ ]]; then
                        log "PSTREE-OVERRIDE-SKIP: ${agent_name} task.status=${_pstree_task_status}, bash subprocess ignored, treating as IDLE"
                    else
                        log "PSTREE-OVERRIDE: ${agent_name} @agent_state=idle but bash subprocess detected, task.status=${_pstree_task_status:-EMPTY}, treating as BUSY"
                        return 1
                    fi
                fi
            fi
            return 0  # IDLE確定（grace period経過）
        fi
        # ─── bash_running: Bashフック設定中はBUSY扱い（STALL誤判定防止） ───
        if [ "$agent_state" = "bash_running" ]; then
            local bash_since
            bash_since=$(tmux display-message -t "$pane_target" -p '#{@bash_running_since}' 2>/dev/null)
            local now_ts
            now_ts=$EPOCHSECONDS
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
        # ─── 全non-idle hook状態: hooksを信頼しBUSY扱い ───
        # 真因: active等のhook状態がSECONDARY(pane判定)に落ちると、API呼び出し間の
        # 一瞬のidle promptを誤検知→AGENT-STATE-CORRECTIONが作業中の忍者を/clearした
        # (cmd_1445事故: saizoが作業中に2回/clearされた根因)
        # 設計: hook状態が存在する場合は常にPRIMARYで完結。SECONDARYはhookなし時のみ
        local _ht_last_active _ht_now _ht_elapsed
        _ht_last_active=$(tmux display-message -t "$pane_target" -p '#{@last_active}' 2>/dev/null)
        _ht_now=$EPOCHSECONDS
        _ht_elapsed=0
        if [ -n "$_ht_last_active" ] && [ "$_ht_last_active" -gt 0 ] 2>/dev/null; then
            _ht_elapsed=$((_ht_now - _ht_last_active))
        fi
        # stale補正: @last_activeが空(=hookが動いていない=Codex等)または60秒以上なら
        # 「まず実画面のbusy/idleを確認してから」補正する。
        # 旧実装は stale だけで idle 扱いし、Codex の "Working ..." 中に
        # idle通知を飛ばす誤判定を起こした。
        if [ -z "$_ht_last_active" ] || [ "$_ht_elapsed" -ge 60 ]; then
            local _stale_state_rc
            if check_agent_busy "$pane_target" "$agent_name"; then
                _stale_state_rc=0
            else
                _stale_state_rc=$?
            fi

            case "$_stale_state_rc" in
                0)
                    log "AGENT-STATE-CORRECTION: ${agent_name} @agent_state=${agent_state} stale (last_active=${_ht_last_active}, ${_ht_elapsed}s ago), pane confirms idle"
                    tmux set-option -p -t "$pane_target" @agent_state idle 2>/dev/null || true
                    [ ! -f "${STATE_DIR}/shogun_idle_${agent_name}" ] && touch "${STATE_DIR}/shogun_idle_${agent_name}"
                    return 0
                    ;;
                1)
                    log "HOOK-STALE-BUT-BUSY: ${agent_name} @agent_state=${agent_state} stale, but pane still busy"
                    return 1
                    ;;
                *)
                    log "HOOK-STALE-UNKNOWN: ${agent_name} @agent_state=${agent_state} stale, pane state unknown -> keep busy"
                    return 1
                    ;;
            esac
        fi
        log "HOOK-TRUST: ${agent_name} @agent_state=${agent_state}, hooks trusted as BUSY (last_active=${_ht_elapsed}s ago)"
        return 1  # hooks say non-idle → BUSY
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

    # cmd_1296: /clear前のgit uncommittedチェック
    # cmd_1303: 運用ファイル除外フィルタ（自動更新される運用ファイルで/clearをブロックしない）
    # 改善: BLOCKせず自動commit → /clearを続行（忍者を起こさない）
    local _uncommitted
    # WSL2 NTFS最適化: フルスキャン(1.7s)→パス限定(0.2s)。除外パターンgrepも不要に
    _uncommitted=$(cd "$SCRIPT_DIR" && git status --porcelain -uno -- scripts/ instructions/ config/ context/ CLAUDE.md 2>/dev/null; true)
    if [ -n "$_uncommitted" ]; then
        local _file_list
        _file_list=$(echo "$_uncommitted" | sed 's/^...//' | tr '\n' ' ')
        log "AUTO-COMMIT-BEFORE-CLEAR: $agent_name uncommitted files: $_file_list"
        auto_commit_before_clear "$agent_name" "$_uncommitted"
    fi

    # /clear前にinboxを既読化（/clear後のnudge再起動を防止）
    bash "$SCRIPT_DIR/scripts/inbox_mark_read.sh" "$agent_name" >> "$LOG" 2>&1 || true

    local clear_cmd
    clear_cmd=$(cli_profile_get "$agent_name" "clear_cmd")
    clear_cmd=${clear_cmd:-"/clear"}
    # LK012: /clear前にpane CWDをSHOGUN_ROOTにリセット（Codex忍者がDM-Signal側CWDで起動→task YAML未到達を防止）
    safe_send_keys_atomic "$pane" "cd $SCRIPT_DIR" 0.3 || true
    log "CWD-RESET: $agent_name pane CWD → $SCRIPT_DIR"

    # Codex CLI: /newはtask in progress中に無視される → respawn-pane -k で強制リセット
    # PATH必須: codex shebang=#!/usr/bin/env node → nvm PATHなしでexit 127
    if [ "$(cli_type "$agent_name" 2>/dev/null || echo "claude")" = "codex" ]; then
        local _launch_cmd
        _launch_cmd=$(cli_profile_get "$agent_name" "launch_cmd")
        if [ -n "$_launch_cmd" ]; then
            local _node_dir="${_launch_cmd%/bin/codex*}/bin"
            log "CODEX-RESPAWN: $agent_name respawn-pane (task in progress workaround)"
            tmux respawn-pane -k -t "$pane" "export PATH=\"${_node_dir}:\$PATH\" && cd $SCRIPT_DIR && $_launch_cmd" 2>/dev/null || {
                log "CODEX-RESPAWN-FALLBACK: $agent_name respawn failed"
            }
            rm -f "${STATE_DIR}/shogun_idle_${agent_name}"
            return 0
        fi
    fi

    log "CLEAR-SEND: $agent_name confirmed idle, sending $clear_cmd, reason=$reason"
    if ! safe_send_keys_atomic "$pane" "$clear_cmd" 0.3; then
        log "CLEAR-BLOCKED: $agent_name send failed, reason=$reason"
        return 1
    fi
    if [ "$(cli_type "$agent_name" 2>/dev/null || echo "claude")" = "claude" ]; then
        # /clear resets Claude Code to accept-edits; shift+tab twice restores bypass permissions.
        sleep 2
        safe_send_keys "$pane" S-Tab || true
        sleep 0.1
        safe_send_keys "$pane" S-Tab || true
        log "BYPASS-PERMISSIONS-TOGGLE: $agent_name sent shift+tab x2 after $clear_cmd"
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
    output=$(tmux capture-pane -t "$pane_target" -p -J -S -30 2>/dev/null)

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
        elif [ "$ctx_mode" = "bar" ]; then
            # bar モード（Codex "Context [▌    ]"）— バー充填率をusage%に変換
            local bar_match bar_content bar_total bar_spaces bar_filled
            bar_match=$(echo "$output" | grep -oE "$ctx_pattern" | head -1)
            if [ -n "$bar_match" ]; then
                bar_content="${bar_match#*\[}"
                bar_content="${bar_content%\]}"
                bar_total=${#bar_content}
                if [ "$bar_total" -gt 0 ]; then
                    bar_spaces=$(printf '%s' "$bar_content" | tr -cd ' ' | wc -c)
                    bar_filled=$((bar_total - bar_spaces))
                    ctx_num=$(( (bar_filled * 100) / bar_total ))
                    tmux set-option -p -t "$pane_target" @context_pct "${ctx_num}%" 2>/dev/null
                    echo "$ctx_num"
                    return 0
                fi
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

    # shellcheck disable=SC2012  # find遅延回避(L504: WSL2 NTFS stat変動63-1942ms)。ファイル名に空白なし
    latest_cmd_report=$(ls -t "$SCRIPT_DIR/queue/reports/${name}_report_cmd"*.yaml 2>/dev/null | head -1 || true)
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
    [ -z "$task_id" ] && task_id=$(yaml_field_get "$task_file" "_ac_task_id")

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
        local verdict
        verdict=$(yaml_field_get "$report_path" "verdict")
        if [ -z "$verdict" ]; then
            log "VERDICT-EMPTY-BLOCK: $name report exists but verdict empty (${trigger})"
            if ! bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "【自動検知】${name}の報告にverdictが未記入。/clear保留中。" verdict_empty ninja_monitor >> "$LOG" 2>&1; then
                log "WARN: inbox_write verdict_empty failed for $name"
            fi
            return 1
        fi
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
    if ! bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "【自動検知】${name}がdone状態だが報告未作成。/clear保留中。" report_missing ninja_monitor >> "$LOG" 2>&1; then
        log "WARN: inbox_write report_missing failed for $name"
    fi
    return 1
}

find_completed_parent_cmd_report_for_other_ninja() {
    local name="$1"
    local parent_cmd="$2"
    local dir report_file report_parent_cmd report_status report_worker base

    [ -n "$parent_cmd" ] || return 1

    for dir in "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/archive/reports"; do
        [ -d "$dir" ] || continue
        while IFS= read -r report_file; do
            [ -f "$report_file" ] || continue
            base=$(basename "$report_file")
            case "$base" in
                "${name}_report_"*.yaml|"${name}_report.yaml") continue ;;
            esac

            report_parent_cmd=$(yaml_field_get "$report_file" "parent_cmd")
            [ "$report_parent_cmd" = "$parent_cmd" ] || continue

            report_status=$(yaml_field_get "$report_file" "status")
            case "$report_status" in
                done|completed|success) ;;
                *) continue ;;
            esac

            report_worker=$(yaml_field_get "$report_file" "worker_id")
            [ "$report_worker" = "$name" ] && continue

            echo "$report_file"
            return 0
        done < <(find "$dir" -maxdepth 1 -name '*_report_*.yaml' -o -name '*_report.yaml' 2>/dev/null | sort)
    done

    return 1
}

auto_void_if_parent_cmd_completed() {
    local name="$1"
    local target="$2"
    local trigger="${3:-AUTO-VOID}"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"

    [ -f "$task_file" ] || return 1

    local task_status parent_cmd task_id completed_report completed_base
    task_status=$(yaml_field_get "$task_file" "status")
    case "$task_status" in
        assigned|acknowledged|in_progress|pending) ;;
        *) return 1 ;;
    esac

    parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
    [ -n "$parent_cmd" ] || return 1

    completed_report=$(find_completed_parent_cmd_report_for_other_ninja "$name" "$parent_cmd") || return 1
    completed_base=$(basename "$completed_report")
    task_id=$(yaml_field_get "$task_file" "task_id")
    [ -z "$task_id" ] && task_id=$(yaml_field_get "$task_file" "_ac_task_id")

    local lock_file="/tmp/task_${name}.lock"
    local voided_at
    printf -v voided_at '%(%Y-%m-%dT%H:%M:%S)T' -1
    (
        flock -x -w 5 200 || { log "ERROR: Failed to acquire lock for $name auto-void"; exit 1; }

        local current_status current_parent_cmd still_completed_report
        current_status=$(yaml_field_get "$task_file" "status")
        case "$current_status" in
            assigned|acknowledged|in_progress|pending) ;;
            *) log "AUTO-VOID-SKIP: $name status changed to ${current_status:-empty}"; exit 1 ;;
        esac
        current_parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
        [ "$current_parent_cmd" = "$parent_cmd" ] || { log "AUTO-VOID-SKIP: $name parent_cmd changed to ${current_parent_cmd:-empty}"; exit 1; }
        still_completed_report=$(find_completed_parent_cmd_report_for_other_ninja "$name" "$parent_cmd") || { log "AUTO-VOID-SKIP: completed report disappeared for $name parent_cmd=$parent_cmd"; exit 1; }

        if ! yaml_field_set "$task_file" "task" "status" "idle"; then
            log "ERROR: yaml_field_set failed for ${name} auto-void status update"
            exit 1
        fi
        yaml_field_set "$task_file" "task" "report_path" "" 2>/dev/null || true
        yaml_field_set "$task_file" "task" "report_filename" "" 2>/dev/null || true
        yaml_field_set "$task_file" "task" "voided_at" "$voided_at" 2>/dev/null || true
        yaml_field_set "$task_file" "task" "void_reason" "parent_cmd_completed_by_$(basename "$still_completed_report")" 2>/dev/null || true
    ) 200>"$lock_file" || return 1

    if [ -n "$target" ]; then
        tmux set-option -p -t "$target" @current_task "" 2>/dev/null || true
    fi
    if [ -n "$target" ]; then
        safe_send_clear "$target" "$name" "AUTO-VOID(${trigger})" || log "AUTO-VOID-CLEAR-FAILED: $name parent_cmd=$parent_cmd"
    fi

    send_inbox_message karo "【AUTO-VOID】${name}の後発task ${task_id:-unknown} をvoid。parent_cmd=${parent_cmd} は ${completed_base} で完了済み。taskをidle化し/clear送信。" auto_void
    log "AUTO-VOID: $name task=${task_id:-unknown} parent_cmd=$parent_cmd completed_report=$completed_base"
    return 0
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

    # cmd_1262: 既にdoneなら即リターン（AUTO-DONE重複書込み+通知嵐を根絶）
    local task_status
    task_status=$(yaml_field_get "$task_file" "status")
    [ "$task_status" = "done" ] && return 0

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
    [ -z "$task_id" ] && task_id=$(yaml_field_get "$task_file" "_ac_task_id")
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
            printf -v completed_ts '%(%Y-%m-%dT%H:%M:%S)T' -1
            (
                flock -x -w 5 200 || { log "ERROR: Failed to acquire lock for $name task update"; exit 1; }
                # S05修正: TOCTOU防止 — flock取得後にparent_cmd/task_idの一致を再検証
                local current_parent_cmd current_task_id
                current_parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
                current_task_id=$(yaml_field_get "$task_file" "task_id")
                [ -z "$current_task_id" ] && current_task_id=$(yaml_field_get "$task_file" "_ac_task_id")
                if [ "$current_parent_cmd" != "$task_parent_cmd" ] || { [ -n "$task_id" ] && [ -n "$current_task_id" ] && [ "$current_task_id" != "$task_id" ]; }; then
                    log "WARN: task file changed during check_and_update_done_task for $name (expected parent_cmd=$task_parent_cmd, got $current_parent_cmd)"
                    exit 1
                fi
                if ! yaml_field_set "$task_file" "task" "status" "done"; then
                    # cmd_1156: Flat YAML fallback — yaml_field_set fails when no "task:" block
                    if grep -q "^status:" "$task_file"; then
                        sed -i "s/^status: .*/status: done/" "$task_file"
                        log "FLAT-YAML-FALLBACK: $name status → done (yaml_field_set failed, flat format detected)"
                    else
                        log "ERROR: yaml_field_set failed for ${name} task status update (not flat format either)"
                        exit 1
                    fi
                    # Flat YAML: completed_at via sed (python3 block requires task block)
                    if ! grep -q "^completed_at:" "$task_file"; then
                        sed -i "/^status: done/a completed_at: '$completed_ts'" "$task_file"
                    fi
                    # Post-update verification
                    _verify_status=$(yaml_field_get "$task_file" "status")
                    if [ "$_verify_status" != "done" ]; then
                        log "ERROR: FLAT-YAML-FALLBACK verification failed for ${name} (status=$_verify_status, expected=done)"
                        exit 1
                    fi
                else
                    # completed_at自動記録（cmd_387: 既存なら上書きしない）
                    if [ -z "$(yaml_field_get "$task_file" "completed_at")" ]; then
                        if ! bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" "$task_file" task completed_at "$completed_ts"; then
                            log "ERROR: yaml_field_set failed for ${name} task completed_at update"
                            exit 1
                        fi
                    fi
                fi
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
                # ─── 報告フォーマットgate（cmd_1236: 家老workaround根絶, cmd_1254: FAIL時auto_deployスキップ） ───
                local gate_report_file gate_parent_cmd gate_key gate_output gate_passed
                gate_passed=true
                gate_report_file=$(find_matching_report_file "$name") || true
                gate_parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
                gate_key="${name}:${gate_parent_cmd}"
                # ─── uncommittedチェック（cmd_1263: commit未完了検出 — gate前にBLOCK） ───
                # done/idle状態の忍者にはcommit催促を送らない（/clear妨害防止）
                if [ "${UNCOMMITTED_BLOCK_SENT[$gate_key]}" != "1" ] && [ "$task_status" != "done" ] && [ "$task_status" != "idle" ]; then
                    local uncommit_project_id uncommit_project_path uncommit_files
                    uncommit_project_id=$(yaml_field_get "$task_file" "project")
                    uncommit_project_path="$SCRIPT_DIR"
                    if [ -n "$uncommit_project_id" ]; then
                        local looked_up
                        looked_up=$(grep -A5 "id: ${uncommit_project_id}$" "$SCRIPT_DIR/config/projects.yaml" | grep "path:" | head -1 | sed 's/.*path: *"\([^"]*\)"/\1/')
                        [ -n "$looked_up" ] && [ -d "$looked_up" ] && uncommit_project_path="$looked_up"
                    fi
                    uncommit_files=$(cd "$uncommit_project_path" && { git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } | sort -u)
                    if [ -n "$uncommit_files" ]; then
                        UNCOMMITTED_BLOCK_SENT[$gate_key]="1"
                        local uncommit_file_list
                        uncommit_file_list=$(echo "$uncommit_files" | tr '\n' ' ')
                        log "UNCOMMITTED-BLOCK: $name files=${uncommit_file_list}"
                        bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$name" "未commitファイルあり: ${uncommit_file_list}。git add + git commitを実行せよ。" uncommitted_block karo >> "$LOG" 2>&1 &
                        gate_passed=false
                    fi
                fi
                if [ -n "$gate_report_file" ] && [ -f "$gate_report_file" ] && [ "${REPORT_GATE_SENT[$gate_key]}" != "1" ]; then
                    gate_output=$(bash "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$gate_report_file" 2>&1) || true
                    if ! echo "$gate_output" | grep -q "^PASS"; then
                        gate_passed=false
                        REPORT_GATE_SENT[$gate_key]="1"
                        log "REPORT-FORMAT-FAIL: $name report=$(basename "$gate_report_file") output=$gate_output — auto_deploy BLOCKED"
                        bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$name" "報告YAMLフォーマットエラー: ${gate_output}。報告YAMLを修正して再送信せよ。対象: $(basename "$gate_report_file")" report_format_fix karo >> "$LOG" 2>&1 &
                    else
                        REPORT_GATE_SENT[$gate_key]="1"
                        log "REPORT-FORMAT-PASS: $name report=$(basename "$gate_report_file")"
                    fi
                fi
                # ─── auto_deploy_next.sh 自動発火（二重呼出防止付き, cmd_1254: gate FAIL時スキップ） ───
                if [ "$gate_passed" = "true" ]; then
                    local task_id_val parent_cmd_val
                    task_id_val=$(yaml_field_get "$task_file" "task_id")
                    [ -z "$task_id_val" ] && task_id_val=$(yaml_field_get "$task_file" "_ac_task_id")
                    parent_cmd_val=$(yaml_field_get "$task_file" "parent_cmd")
                    local deploy_key="${name}:${task_id_val}"
                    if [ -n "$parent_cmd_val" ] && [ -n "$task_id_val" ] && [ "${AUTO_DEPLOY_DONE[$deploy_key]}" != "1" ]; then
                        AUTO_DEPLOY_DONE[$deploy_key]="1"
                        log "[AUTO_DEPLOY] Triggering: cmd=${parent_cmd_val} completed=${task_id_val} ninja=${name}"
                        (
                            timeout 30 bash "$SCRIPT_DIR/scripts/auto_deploy_next.sh" "$parent_cmd_val" "$task_id_val" >> "$LOG" 2>&1
                            rc=$?
                            case $rc in
                                0) printf '[%(%Y-%m-%d %H:%M:%S)T] [AUTO_DEPLOY] OK: %sの次サブタスク配備完了 (cmd=%s)\n' -1 "${name}" "${parent_cmd_val}" >> "$LOG" ;;
                                2) printf '[%(%Y-%m-%d %H:%M:%S)T] [AUTO_DEPLOY] SKIP: auto_deploy=false (cmd=%s)\n' -1 "${parent_cmd_val}" >> "$LOG" ;;
                                3) printf '[%(%Y-%m-%d %H:%M:%S)T] [AUTO_DEPLOY] BLOCKED: 未解消依存あり or 忍者不在 (cmd=%s)\n' -1 "${parent_cmd_val}" >> "$LOG" ;;
                                *) printf '[%(%Y-%m-%d %H:%M:%S)T] [AUTO_DEPLOY] ERROR: 配備失敗 rc=%s (cmd=%s)\n' -1 "${rc}" "${parent_cmd_val}" >> "$LOG" ;;
                            esac
                        ) &
                    fi
                else
                    log "[AUTO_DEPLOY] SKIPPED: gate_report_format FAIL for $name (${gate_key}) — STALL検知は継続"
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
                            now_epoch=$EPOCHSECONDS
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

    # 各忍者のCTX%と最終タスクIDとpane状態を収集
    local details=""
    local pane_evidence=""
    for name in "${names[@]}"; do
        local target="${PANE_TARGETS[$name]}"
        local ctx
        ctx=$(get_context_pct "$target" "$name")
        local last_task
        last_task=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${name}.yaml" "task_id")
        [ -z "$last_task" ] && last_task=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${name}.yaml" "_ac_task_id")
        details="${details}${name}(CTX:${ctx}%,last:${last_task}), "
        # pane最終3行を添付（家老がidle判断の直接証拠として使う）
        local pane_tail
        pane_tail=$(tmux capture-pane -t "$target" -p 2>/dev/null | awk 'NF { lines[++n] = $0 } END { start = n - 2; if (start < 1) start = 1; for (i = start; i <= n; i++) { printf "%s%s", sep, lines[i]; sep = "|" } }')
        if [ -n "$pane_tail" ]; then
            pane_evidence="${pane_evidence}[pane:${name}] ${pane_tail} "
        fi
    done
    details="${details%, }"  # 末尾カンマ除去

    # cmd_1671: pipeline空でもidle通知を送る（頻度制限は維持）
    local pipeline_count
    pipeline_count=$(awk '/^[[:space:]]+status:[[:space:]]+(pending|new)/ {c++} END {print c+0}' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || echo 0)
    local pipeline_info=""
    if [ "${pipeline_count:-0}" -eq 0 ]; then
        pipeline_info="(pipeline空)"
    fi

    local msg="idle(新規): ${details}${pipeline_info}。計${#names[@]}名タスク割り当て可能。${pane_evidence:+ pane証拠: ${pane_evidence}}"
    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$msg" ninja_idle ninja_monitor >> "$LOG" 2>&1; then
        log "Batch notification sent to karo: ${names[*]}"
        local now
        now=$EPOCHSECONDS
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

_clear_stall_tracking_for_completed_idle() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    [ -f "$task_file" ] || return 0

    local task_status
    task_status=$(yaml_field_get "$task_file" "status")
    case "$task_status" in
        done|completed|idle) ;;
        *) return 0 ;;
    esac

    local key cleared_first=0 cleared_count=0
    for key in "${!STALL_FIRST_SEEN[@]}"; do
        case "$key" in
            "$name"|"deploy_stall_${name}"|"${name}:"*)
                unset "STALL_FIRST_SEEN[$key]"
                cleared_first=$((cleared_first + 1))
                ;;
        esac
    done

    for key in "${!STALL_COUNT[@]}"; do
        case "$key" in
            "$name"|"deploy_stall_${name}"|"${name}:"*)
                unset "STALL_COUNT[$key]"
                cleared_count=$((cleared_count + 1))
                ;;
        esac
    done

    if [ "$cleared_first" -gt 0 ] || [ "$cleared_count" -gt 0 ]; then
        log "STALL-TRACKING-CLEAR: $name status=$task_status first_seen=${cleared_first} count=${cleared_count}"
    fi
}

# post_clear_cmd送信（cmd_583: /new後の/fast自動有効化）
# 戻り値: 0=処理済み(呼び出し元でreturn), 1=未処理(続行)
_handle_post_clear_pending() {
    local name="$1"
    [ -z "${POST_CLEAR_PENDING[$name]:-}" ] && return 1

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
    now=$EPOCHSECONDS
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
        # STALL-CLEAR: report_path/report_filename残骸を消去（二重配備残骸問題防止）
        # 旧忍者のtask YAMLにreport_pathが残ると、別忍者に再配備後も空報告が生成される
        yaml_field_set "$task_file" "task" "report_path" "" 2>/dev/null || true
        yaml_field_set "$task_file" "task" "report_filename" "" 2>/dev/null || true
        log "DEPLOY-STALL-CLEAR: cleared report_path/report_filename for $name"
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

    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    if [ -f "$task_file" ]; then
        local task_status
        task_status=$(yaml_field_get "$task_file" "status")
        if [ "$task_status" = "failed" ]; then
            log "IDLE-NOTIFY-SKIP: $name task status=failed (not assignable)"
            return
        fi
    fi

    [ "${PREV_STATE[$name]}" = "idle" ] && return

    # モード切替: 既に通知済みの場合、パイプライン状態で判断
    if [ -n "${IDLE_NOTIFY_SENT[$name]:-}" ]; then
        local pipeline_count
        pipeline_count=$(awk '/^[[:space:]]+status:[[:space:]]+(pending|new|delegated)/ {c++} END {print c+0}' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || echo 0)
        if [ "${pipeline_count:-0}" -eq 0 ]; then
            # standby mode: パイプライン空 → 再通知しない（状態変化まで待機）
            log "IDLE-STANDBY: $name already notified, pipeline empty, skipping"
            return
        fi
        # active mode: パイプライン有 → cooldown後に再通知（圧力）
        local idle_elapsed=$((now - IDLE_NOTIFY_SENT[$name]))
        if [ "$idle_elapsed" -lt "$IDLE_ACTIVE_COOLDOWN" ]; then
            log "IDLE-ACTIVE-COOLDOWN: $name ${idle_elapsed}s < ${IDLE_ACTIVE_COOLDOWN}s"
            return
        fi
    fi

    local last elapsed debounce_time
    last="${LAST_NOTIFIED[$name]:-0}"
    elapsed=$((now - last))

    debounce_time=$(cli_profile_get "$name" "debounce")

    if [ "$elapsed" -ge "$debounce_time" ]; then
        log "IDLE confirmed: $name"
        NEWLY_IDLE+=("$name")
        IDLE_NOTIFY_SENT[$name]=$now
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

    # GP-223: タスクが配備済み(assigned/acknowledged/in_progress)ならAUTO-CLEARしない
    # DEPLOY-STALLで処理すべき。AUTO-CLEARすると忍者のrecoveryが中断され無限ループになる
    local _ac_task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    if [ -f "$_ac_task_file" ]; then
        local _ac_task_status
        _ac_task_status=$(yaml_field_get "$_ac_task_file" "status")
        if [[ "$_ac_task_status" =~ ^(assigned|acknowledged|in_progress)$ ]]; then
            log "AUTO-CLEAR-SKIP: $name has active task (status=$_ac_task_status), deferring to DEPLOY-STALL"
            return
        fi
    fi

    # CTX=0%なら既にクリア済み → スキップ（無駄な再clearループ防止）
    # GP-222: Codex CLIではCTX=0は「未検出」の可能性があるためスキップしない
    local ctx_now _ac_cli_type
    ctx_now=$(get_context_pct "$target" "$name")
    _ac_cli_type=$(cli_type "$name" 2>/dev/null || echo "claude")
    if [ "${ctx_now:-0}" -le 0 ] 2>/dev/null && [ "$_ac_cli_type" != "codex" ]; then
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

_training_pipeline_has_work() {
    grep -qE '^\s+status:\s+(pending|new|delegated)' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null
}

_training_auto_state_file() {
    local name="$1"
    printf '%s_%s.last\n' "$TRAINING_AUTO_DEPLOY_STATE_PREFIX" "$name"
}

_training_recent_gate_stats() {
    local name="$1"
    local log_file="$SCRIPT_DIR/logs/gate_fire_log.yaml"
    local recent_limit="${TRAINING_AUTO_DEPLOY_RECENT:-50}"
    [ -f "$log_file" ] || { printf '0 0 0\n'; return 0; }
    [[ "$recent_limit" =~ ^[0-9]+$ ]] || recent_limit=50
    [ "$recent_limit" -gt 0 ] 2>/dev/null || recent_limit=50

    if command -v tac >/dev/null 2>&1; then
        tac "$log_file" 2>/dev/null | awk -v name="$name" -v limit="$recent_limit" '
            $0 ~ ("queue/reports/" name "_report_") || $0 ~ ("/queue/reports/" name "_report_") || $0 ~ ("/queue/archive/reports/" name "_report_") {
                total++
                if ($0 ~ /result:[[:space:]]*FAIL/) fail++
                if (total >= limit) exit
            }
            END {
                pct = (total > 0 ? int((fail * 100 + total - 1) / total) : 0)
                printf "%d %d %d\n", total + 0, fail + 0, pct + 0
            }
        '
        return 0
    fi

    awk -v name="$name" -v limit="$recent_limit" '
        $0 ~ ("queue/reports/" name "_report_") || $0 ~ ("/queue/reports/" name "_report_") || $0 ~ ("/queue/archive/reports/" name "_report_") {
            lines[++n] = $0
        }
        END {
            start = n - limit + 1
            if (start < 1) start = 1
            for (i = start; i <= n; i++) {
                if (lines[i] == "") continue
                total++
                if (lines[i] ~ /result:[[:space:]]*FAIL/) fail++
            }
            pct = (total > 0 ? int((fail * 100 + total - 1) / total) : 0)
            printf "%d %d %d\n", total + 0, fail + 0, pct + 0
        }
    ' "$log_file"
}

_training_condition_met() {
    local name="$1"
    local total fail pct
    read -r total fail pct < <(_training_recent_gate_stats "$name")

    if [ "${total:-0}" -lt "$TRAINING_AUTO_DEPLOY_MIN_GATES" ]; then
        log "TRAINING-AUTO-CHECK: $name eligible (gate samples ${total:-0} < ${TRAINING_AUTO_DEPLOY_MIN_GATES})"
        return 0
    fi

    if [ "${pct:-0}" -ge "$TRAINING_AUTO_DEPLOY_FAIL_RATE" ]; then
        log "TRAINING-AUTO-CHECK: $name eligible (recent FAIL rate ${pct}%=${fail}/${total}, threshold=${TRAINING_AUTO_DEPLOY_FAIL_RATE}%)"
        return 0
    fi

    log "TRAINING-AUTO-SKIP: $name recent FAIL rate ${pct}%=${fail}/${total} below threshold ${TRAINING_AUTO_DEPLOY_FAIL_RATE}%"
    return 1
}

_handle_training_auto_deploy() {
    local name="$1"
    local now="$2"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local task_status last_file last elapsed idle_elapsed cmd_id deploy_script tmp_task

    [ -n "$name" ] || return 1

    if _training_pipeline_has_work; then
        unset "TRAINING_IDLE_FIRST_SEEN[$name]"
        log "TRAINING-AUTO-SKIP: $name production pipeline has pending work"
        return 1
    fi

    if [ -f "$task_file" ]; then
        task_status=$(yaml_field_get "$task_file" "status")
        case "$task_status" in
            assigned|acknowledged|in_progress|pending|failed)
                unset "TRAINING_IDLE_FIRST_SEEN[$name]"
                log "TRAINING-AUTO-SKIP: $name task status=${task_status}"
                return 1
                ;;
        esac
    fi

    if [ -z "${TRAINING_IDLE_FIRST_SEEN[$name]:-}" ]; then
        TRAINING_IDLE_FIRST_SEEN[$name]=$now
        log "TRAINING-AUTO-WATCH: $name idle tracking started"
        return 1
    fi

    idle_elapsed=$((now - TRAINING_IDLE_FIRST_SEEN[$name]))
    if [ "$idle_elapsed" -lt "$TRAINING_AUTO_DEPLOY_IDLE_THRESHOLD" ]; then
        log "TRAINING-AUTO-WAIT: $name idle ${idle_elapsed}s < ${TRAINING_AUTO_DEPLOY_IDLE_THRESHOLD}s"
        return 1
    fi

    last_file=$(_training_auto_state_file "$name")
    last=0
    if [ -f "$last_file" ]; then
        read -r last < "$last_file" || last=0
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    elapsed=$((now - last))
    if [ "$elapsed" -lt "$TRAINING_AUTO_DEPLOY_COOLDOWN" ]; then
        log "TRAINING-AUTO-COOLDOWN: $name ${elapsed}s < ${TRAINING_AUTO_DEPLOY_COOLDOWN}s"
        return 1
    fi

    if ! _training_condition_met "$name"; then
        return 1
    fi

    deploy_script="$SCRIPT_DIR/scripts/deploy_task.sh"
    if [ ! -x "$deploy_script" ]; then
        log "TRAINING-AUTO-SKIP: deploy_task.sh not executable"
        return 1
    fi

    cmd_id="cmd_training_L4_auto_$(date '+%Y%m%d%H%M')_${name}"
    tmp_task=$(mktemp "${STATE_DIR}/training_auto_${name}.XXXXXX.yaml")
    cat > "$tmp_task" <<EOF
task:
  parent_cmd: ${cmd_id}
  task_id: ${cmd_id}_training
  task_type: training
  project: infra
  target_path: scripts/ninja_monitor.sh
  scout_exempt: true
  status: assigned
  purpose: "L4修行: 指定スクリプトの改善点3つを特定し、最高インパクト1件を実装し、報告YAMLを一発PASS品質で完成させる"
EOF

    log "TRAINING-AUTO-DEPLOY: $name cmd=${cmd_id} via deploy_task.sh --direct --yaml"
    if bash "$deploy_script" --direct --yaml "$tmp_task" "$name" "$cmd_id" >> "$SCRIPT_DIR/logs/deploy_training_auto.log" 2>&1; then
        rm -f "$tmp_task"
        printf '%s\n' "$now" > "$last_file" 2>/dev/null || true
        unset "TRAINING_IDLE_FIRST_SEEN[$name]"
        log "TRAINING-AUTO-DEPLOY-DONE: $name cmd=${cmd_id}"
        return 0
    fi

    rm -f "$tmp_task"
    log "TRAINING-AUTO-DEPLOY-FAIL: $name cmd=${cmd_id} (non-blocking)"
    return 1
}

# ─── 修行効果: before FAIL率算出 (cmd_design_quality.yaml) (cmd_2767) ───
# cmd_design_quality.yamlから対象忍者の過去修行cmd BLOCK率を算出
# 出力: "total fail pct" のスペース区切り3値
_training_before_fail_pct() {
    local name="$1"
    local log_file="$SCRIPT_DIR/logs/cmd_design_quality.yaml"
    [ -f "$log_file" ] || { printf '0 0 0\n'; return 0; }

    awk -v name="$name" '
        BEGIN { total=0; fail=0; cmd=""; gate=""; has_ninja=0 }
        /^- cmd_id:/ {
            if (cmd != "" && has_ninja) {
                total++
                if (gate == "BLOCK") fail++
            }
            cmd = $NF; gsub(/["'"'"']/, "", cmd)
            gate = ""
            has_ninja = (cmd ~ /training/ && cmd ~ name) ? 1 : 0
        }
        /^  notes:/ { if ($0 ~ name) has_ninja = 1 }
        /^  gate_result:/ { gate = $2; gsub(/["'"'"']/, "", gate) }
        END {
            if (cmd != "" && has_ninja) {
                total++
                if (gate == "BLOCK") fail++
            }
            pct = (total > 0 ? int(fail * 100 / total) : 0)
            printf "%d %d %d\n", total+0, fail+0, pct+0
        }
    ' "$log_file"
}

# ─── 修行効果記録 (cmd_2767) ───
# 修行task完了時(task_type=training/task_id=*training*)にbefore/after FAIL率を比較してlogs/training_effect.logに記録
_record_training_effect() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"

    [ -f "$task_file" ] || return 0

    local task_type task_id task_status
    IFS='|' read -r task_type task_id task_status < <(awk '
        BEGIN { tt=""; ti=""; ts="" }
        /^[ \t]*task_type:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); tt=v }
        /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && ti=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ti=v }
        /^[ \t]*_ac_task_id:/ && ti=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ti=v }
        /^[ \t]*status:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ts=v }
        END { print tt "|" ti "|" ts }
    ' "$task_file")

    # training taskの検出: task_type=training または task_idがtrainingパターン
    local is_training=0
    [[ "$task_type" = "training" ]] && is_training=1
    [[ "$task_id" = *training* ]] && is_training=1
    [ "$is_training" = "1" ] || return 0

    # done/completed状態のみ対象
    case "$task_status" in
        done|completed) ;;
        *) return 0 ;;
    esac

    [ -n "$task_id" ] || return 0

    # 二重記録防止（連想配列）
    local key="${name}:${task_id}"
    [ "${TRAINING_EFFECT_RECORDED[$key]:-}" = "1" ] && return 0

    # before FAIL率: cmd_design_quality.yamlの過去修行BLOCK率
    local before_total before_fail before_pct
    read -r before_total before_fail before_pct < <(_training_before_fail_pct "$name")
    before_total=${before_total:-0}; before_fail=${before_fail:-0}; before_pct=${before_pct:-0}

    # after FAIL率: gate_fire_log.yamlの直近FAIL率
    local after_total after_fail after_pct
    read -r after_total after_fail after_pct < <(_training_recent_gate_stats "$name")
    after_total=${after_total:-0}; after_fail=${after_fail:-0}; after_pct=${after_pct:-0}

    local delta=$(( after_pct - before_pct ))
    local delta_str
    if [ "$delta" -lt 0 ]; then
        delta_str="${delta}%"
    elif [ "$delta" -gt 0 ]; then
        delta_str="+${delta}%"
    else
        delta_str="±0%"
    fi

    local timestamp
    printf -v timestamp '%(%Y-%m-%dT%H:%M:%S)T' -1
    printf '[%s] TRAINING-EFFECT: ninja=%s task=%s before_block_pct=%d%%(%d/%d) after_fail_pct=%d%%(%d/%d) delta=%s\n' \
        "$timestamp" "$name" "$task_id" \
        "$before_pct" "$before_fail" "$before_total" \
        "$after_pct" "$after_fail" "$after_total" \
        "$delta_str" >> "$TRAINING_EFFECT_LOG"
    log "TRAINING-EFFECT: $name task=$task_id before=${before_pct}% after=${after_pct}% delta=${delta_str}"

    TRAINING_EFFECT_RECORDED[$key]="1"
}

# ─── idle→通知の処理（状態遷移+デバウンス） ───
# 4サブ関数に分割: _handle_post_clear_pending / _handle_deploy_stall /
#                   _handle_idle_notify / _handle_auto_clear
handle_confirmed_idle() {
    local name="$1"

    if _handle_post_clear_pending "$name"; then return; fi
    if _handle_deploy_stall "$name"; then return; fi

    local now
    now=$EPOCHSECONDS
    _clear_stall_tracking_for_completed_idle "$name"
    _handle_idle_notify "$name" "$now"
    _record_training_effect "$name"  # 修行完了時にbefore/after FAIL率を比較記録 (cmd_2767)
    if _handle_training_auto_deploy "$name" "$now"; then return; fi
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
    unset "IDLE_NOTIFY_SENT[$name]"  # 状態変化: busy復帰→次idle時に再通知許可
    unset "TRAINING_IDLE_FIRST_SEEN[$name]"
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

    for key in "${!REPORT_GATE_SENT[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "REPORT_GATE_SENT[$key]"
    done

    for key in "${!UNCOMMITTED_BLOCK_SENT[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "UNCOMMITTED_BLOCK_SENT[$key]"
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
    # GP-233パターン: grep直接でWSL2 NTFS遅延対策（yaml_field_get回避）
    local status task_id
    status=$(grep -m1 -E '^\s*status:\s*' "$task_file" 2>/dev/null \
        | sed 's/.*status:[[:space:]]*//' | tr -d "\"'[:space:]" || true)

    # Early exit: idle/done/等はSTALL対象外（task_id読込も不要）
    case "$status" in
        assigned|acknowledged|in_progress) ;;
        *)
            unset "STALL_FIRST_SEEN[$name]"
            return
            ;;
    esac

    # awk単一パスで残りフィールドを一括取得（従来: yaml_field_get×5=最大5サブシェル → awk×1）
    # L4-R24最適化パターン（write_karo_snapshot/write_state_fileと同方式）
    local deployed_at_val last_progress
    IFS='|' read -r task_id deployed_at_val last_progress < <(awk '
        BEGIN { t=""; da=""; pa="" }
        /^[ \t]*subtask_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
        /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
        /^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
        /^[ \t]*deployed_at:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); da=v }
        /^[ \t]*progress_updated_at:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); pa=v }
        END { print t "|" da "|" pa }
    ' "$task_file")

    # Ghost Filter: task_id空のSTALL誤検知を排除(cmd_1150)
    if [ -z "$task_id" ]; then
        log "STALL-GHOST: $name has status=${status} but empty task_id — skipping stall detection"
        return
    fi

    if [ -n "$deployed_at_val" ]; then
        local deployed_epoch
        deployed_epoch=$(date -d "$deployed_at_val" +%s 2>/dev/null || echo "")
        if [ -n "$deployed_epoch" ]; then
            local now_epoch
            now_epoch=$EPOCHSECONDS
            local deployed_age=$(( now_epoch - deployed_epoch ))
            if [ "$deployed_age" -ge 0 ] && [ "$deployed_age" -lt 300 ]; then
                unset "STALL_FIRST_SEEN[$name]"
                log "STALL-DEPLOY-GRACE: $name deployed ${deployed_age}s ago, within grace period"
                return
            fi
        fi
    fi

    case "$status" in
        assigned|acknowledged)
            ;;
        in_progress)
            # progress_updated_atが最近更新されていれば作業中と判断（last_progressはawk取得済み）
            if [ -n "$last_progress" ]; then
                local progress_epoch
                progress_epoch=$(date -d "$last_progress" +%s 2>/dev/null || echo "0")
                local now_epoch
                now_epoch=$EPOCHSECONDS
                local progress_age=$(( now_epoch - progress_epoch ))
                if [ $progress_age -lt 1200 ]; then
                    # 20分以内にprogress更新あり → 作業中
                    unset "STALL_FIRST_SEEN[$name]"
                    return
                fi
            fi
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
    now=$EPOCHSECONDS
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
        local stall_message
        stall_message=$(append_pane_excerpt "${name}が${task_id}で${elapsed_min}分停滞(status=${status})" "$target")
        send_inbox_message karo "$stall_message" stall_alert
        STALL_NOTIFIED[$stall_key]=$now

        STALL_COUNT[$stall_key]=$(( ${STALL_COUNT[$stall_key]:-0} + 1 ))
        local stall_count=${STALL_COUNT[$stall_key]}
        if [ "$stall_count" -ge "$STALL_ESCALATE_THRESHOLD" ]; then
            local escalate_message
            escalate_message=$(append_pane_excerpt "【STALL-ESCALATE】${name}が${task_id}で${stall_count}回STALL。差し替え必須。" "$target")
            send_inbox_message karo "$escalate_message" stall_escalate
        fi

        if [ "$status" = "in_progress" ]; then
            send_inbox_message "$name" "in_progress停滞を検知。task YAMLを再確認し、作業を再開せよ。" task_assigned
            log "STALL-RECOVERY-SEND: resent task_assigned to ${name} for ${task_id}"
        fi

        unset "STALL_FIRST_SEEN[$name]"
    fi
}

# ─── report done + task status未idle 検知 (cmd_selfimprovement_monitor_report_done) ───
# karo_snapshot.txt の report行で status=done の忍者を抽出し、
# 同忍者の task YAML で status が idle/done でなければ家老にアラート。
# デバウンス: 同一ninja×cmd_idで5分以内の再通知を抑止。
check_report_done_idle_mismatch() {
    local snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
    [ -f "$snapshot_file" ] || return

    local now
    now=$EPOCHSECONDS

    while IFS='|' read -r _type name _summary report_status; do
        [ "$_type" = "report" ] || continue
        [ "$report_status" = "done" ] || continue
        [ -z "$name" ] && continue

        local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
        [ -f "$task_file" ] || continue

        # awk単一パスでstatus/task_id/parent_cmdを一括取得（従来yaml_field_get×3=最大3サブシェル→awk×1）
        # L4-R24最適化パターン（check_stall/write_karo_snapshotと同方式、L511:WSL2プロセス起動コスト削減）
        local task_status task_id parent_cmd
        IFS='|' read -r task_status task_id parent_cmd < <(awk '
            BEGIN { s=""; t=""; p="" }
            /^[ \t]*status:/ && s=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); s=v }
            /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
            /^[ \t]*parent_cmd:/ && p=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); p=v }
            END { print s "|" t "|" (p=="" ? "unknown" : p) }
        ' "$task_file" 2>/dev/null)

        # idle/done は正常状態 → スキップ
        case "$task_status" in
            idle|done) continue ;;
        esac

        # 旧report残存チェック: snapshotの_summaryと現taskのtask_idが不一致なら
        # 新task配備後の旧report残存 → 誤検知なのでスキップ
        if [ "$_summary" != "$task_id" ] && [ -n "$task_id" ]; then
            continue
        fi

        local mismatch_key="${name}:${parent_cmd}"

        # デバウンス: 5分以内の再通知を抑止
        local last_notified=${REPORT_DONE_MISMATCH_NOTIFIED[$mismatch_key]:-0}
        local since_last=$(( now - last_notified ))
        if [ "$last_notified" -gt 0 ] && [ "$since_last" -lt "$REPORT_DONE_MISMATCH_DEBOUNCE" ]; then
            continue
        fi

        log "REPORT-DONE-MISMATCH: ${name} report=done but task status=${task_status} (${parent_cmd})"
        send_inbox_message karo \
            "【REPORT-DONE-MISMATCH】${name}: report=done だが task status=${task_status}（${parent_cmd}）。idle化が必要。" \
            report_done_mismatch
        REPORT_DONE_MISMATCH_NOTIFIED[$mismatch_key]=$now
    done < "$snapshot_file"
}

# ─── stale cmd検知（pending+4時間超+subtask未配備） ───
# queue/shogun_to_karo.yaml から pending cmd を抽出し、
# queue/tasks/*.yaml に parent_cmd が存在しないまま4時間超過したcmdを家老に通知
list_pending_cmds() {
    local cmd_file="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
    [ ! -f "$cmd_file" ] && return

    python3 - "$cmd_file" <<'PYEOF'
import sys
import yaml

cmd_file = sys.argv[1]

try:
    with open(cmd_file, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    sys.exit(0)

cmds = data.get("commands", {})
if isinstance(cmds, dict):
    entries = cmds.items()
elif isinstance(cmds, list):
    entries = ((str(item.get("id", "")), item) for item in cmds if isinstance(item, dict))
else:
    entries = []

for cmd_id, info in entries:
    if not cmd_id or not isinstance(info, dict):
        continue
    if str(info.get("status", "")) != "pending":
        continue
    timestamp = str(info.get("timestamp", "") or "").strip('"')
    delegated_at = str(info.get("delegated_at", "") or "").strip('"')
    print(f"{cmd_id}|{timestamp}|{delegated_at}")
PYEOF
}

# ─── list_pending_cmds サイクル内キャッシュ ───
# check_stale_cmds/check_undeployed_cmds/check_karo_pending_cmd が同一サイクル内で
# 別々にpython3を起動するのを防ぐ。cycleが変わった時だけlist_pending_cmdsを再実行。
list_pending_cmds_cached() {
    local current_cycle="${cycle:-0}"
    if [ "$current_cycle" -eq "$_PENDING_CMDS_CACHE_CYCLE" ]; then
        [ -n "$_PENDING_CMDS_CACHE" ] && printf '%s\n' "$_PENDING_CMDS_CACHE"
        return
    fi
    _PENDING_CMDS_CACHE=$(list_pending_cmds)
    _PENDING_CMDS_CACHE_CYCLE=$current_cycle
    [ -n "$_PENDING_CMDS_CACHE" ] && printf '%s\n' "$_PENDING_CMDS_CACHE"
}

check_stale_cmds() {
    local now
    now=$EPOCHSECONDS

    while IFS='|' read -r cmd_id cmd_timestamp _cmd_delegated_at; do
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
        if [ $elapsed_sec -lt "$STALE_CMD_THRESHOLD" ]; then
            continue
        fi

        # subtask存在確認: queue/tasks/*.yaml の parent_cmd を照合 (L335: -Fw必須)
        if grep -Fwl "parent_cmd: ${cmd_id}" "$SCRIPT_DIR/queue/tasks/"*.yaml >/dev/null 2>&1; then
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
    done < <(list_pending_cmds_cached)
}

check_undeployed_cmds() {
    local now
    now=$EPOCHSECONDS
    local -A current_pending=()

    while IFS='|' read -r cmd_id _cmd_timestamp delegated_at; do
        [ -z "$cmd_id" ] && continue
        [ -z "$delegated_at" ] && continue
        current_pending["$cmd_id"]=1

        if [ -n "${UNDEPLOYED_CMD_NOTIFIED[$cmd_id]:-}" ]; then
            continue
        fi

        local delegated_epoch
        delegated_epoch=$(date -d "$delegated_at" +%s 2>/dev/null || echo "0")
        if [[ ! "$delegated_epoch" =~ ^[0-9]+$ ]] || [ "$delegated_epoch" -le 0 ]; then
            log "WARN: Failed to parse delegated_at: ${cmd_id} delegated_at=${delegated_at}"
            continue
        fi

        local elapsed_sec
        elapsed_sec=$((now - delegated_epoch))
        if [ "$elapsed_sec" -lt 600 ]; then
            continue
        fi

        local elapsed_min delegated_hm msg
        elapsed_min=$((elapsed_sec / 60))
        delegated_hm=$(date -d "$delegated_at" "+%H:%M" 2>/dev/null || echo "$delegated_at")
        msg="未配備cmd: ${cmd_id} (委任時刻: ${delegated_hm}, ${elapsed_min}分経過)"

        log "UNDEPLOYED-CMD: ${cmd_id} pending+delegated_at ${elapsed_min}min, sending ntfy"
        if bash "$SCRIPT_DIR/scripts/ntfy.sh" "$msg" >> "$LOG" 2>&1; then
            UNDEPLOYED_CMD_NOTIFIED["$cmd_id"]=$now
        else
            log "ERROR: Failed to send ntfy for undeployed cmd ${cmd_id}"
        fi
    done < <(list_pending_cmds_cached)

    local notified_cmd
    for notified_cmd in "${!UNDEPLOYED_CMD_NOTIFIED[@]}"; do
        if [ -z "${current_pending[$notified_cmd]:-}" ]; then
            unset "UNDEPLOYED_CMD_NOTIFIED[$notified_cmd]"
            log "UNDEPLOYED-CMD-RESOLVED: ${notified_cmd} no longer pending+delegated_at"
        fi
    done
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

    while IFS='|' read -r cmd_id cmd_timestamp _cmd_delegated_at; do
        [ -z "$cmd_id" ] && continue
        current_ids+=("$cmd_id")

        # 既知のpending → スキップ（遷移なし。stale_cmdsがエスカレーション担当）
        [ "${PREV_PENDING_SET[$cmd_id]:-}" = "1" ] && continue

        # stale通知済みcmdは重複回避
        [ -n "${STALE_CMD_NOTIFIED[$cmd_id]:-}" ] && continue

        # 新規pending cmd → 1回通知
        log "PENDING-CMD-NEW: ${cmd_id} -> karo (new pending detected)"
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "cmd_pending ${cmd_id} 新規pending検知。shogun_to_karo.yamlを確認し着手せよ。" cmd_pending ninja_monitor >> "$LOG" 2>&1
    done < <(list_pending_cmds_cached)

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
    now=$EPOCHSECONDS

    # 5パターンをawk 1パスで検出（WSL2プロセス起動コスト削減: echo|grep×10→awk×1）
    local -a patterns=()
    local detected
    detected=$(printf '%s\n' "$output" | awk '
        /rm[[:space:]]+-rf[[:space:]]+(\/mnt\/c\/(Windows|Users|Program)|\/home|\/[[:space:]]|\/\.|~)/ { print "rm-rf-outside-project" }
        /git[[:space:]]+push.*--force/ && !/force-with-lease/ { print "git-push-force" }
        /(^|[[:space:]])sudo[[:space:]]/ { print "sudo" }
        /(^|[[:space:]])(kill|killall|pkill)[[:space:]]/ { print "kill-command" }
        /curl.*\|.*bash|wget.*\|.*sh/ { print "pipe-to-shell" }
    ' | sort -u)
    while IFS= read -r _dp; do
        [ -z "$_dp" ] && continue
        patterns+=("$_dp")
    done <<< "$detected"

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
    local all_agents=("karo" "gunshi" "${NINJA_NAMES[@]}")
    local now
    now=$EPOCHSECONDS

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

        # 未読0 → 家老pending workチェック後にスキップ
        if [ "$unread_count" -eq 0 ]; then
            # 家老専用: inbox未読0でもpending work(忍者done/delegated未配備)があればnudge
            if [ "$name" = "karo" ]; then
                local _karo_pending=false
                for _ktf in "$SCRIPT_DIR"/queue/tasks/*.yaml; do
                    [ -f "$_ktf" ] || continue
                    local _kts
                    _kts=$(awk '/^  status:/{print $2; exit}' "$_ktf" 2>/dev/null || true)
                    if [ "$_kts" = "done" ]; then
                        # GATE CLEAR済みならpending workではない
                        local _kpcmd
                        _kpcmd=$(awk '/^  parent_cmd:/{print $2; exit}' "$_ktf" 2>/dev/null || true)
                        if [ -n "$_kpcmd" ] && ls "$SCRIPT_DIR/queue/archive/cmds/${_kpcmd}_completed_"* >/dev/null 2>&1; then
                            continue  # archived=GATE CLEAR済み
                        fi
                        _karo_pending=true
                        break
                    fi
                done
                if [ "$_karo_pending" = true ]; then
                    local _karo_target="$KARO_PANE"
                    if [ -n "$_karo_target" ] && check_idle "$_karo_target" "karo"; then
                        local _last="${RENUDGE_LAST_SEND[$name]:-0}"
                        if [ $((now - _last)) -ge 120 ]; then
                            log "KARO-PENDING-NUDGE: karo idle with pending work (ninja done), sending nudge"
                            safe_send_keys_atomic "$_karo_target" "inbox0" 0.3
                            RENUDGE_LAST_SEND[$name]=$now
                        fi
                    fi
                fi
            fi
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
        elif [ "$name" = "gunshi" ]; then
            target="$GUNSHI_PANE"
        else
            target="${PANE_TARGETS[$name]}"
        fi
        [ -z "$target" ] && continue

        # idle判定（busy → skip：作業中はいずれinboxを処理する）
        if ! check_idle "$target" "$name"; then
            continue
        fi

        # CTX=0%でタスクなしの忍者にはnudgeしない（/clear後の無駄な再起動防止）
        if [ "$name" != "karo" ] && [ "$name" != "gunshi" ]; then
            local ctx_pct
            ctx_pct=$(get_context_pct "$target" "$name")
            local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
            local task_status
            task_status=$(yaml_field_get "$task_file" "status" "idle")
            if [ "${ctx_pct:-0}" -le 0 ] 2>/dev/null && { [ "$task_status" = "idle" ] || [ "$task_status" = "done" ]; }; then
                continue
            fi
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
# 引数: $1=pane_target (例: shogun:agents.4), $2=agent_name（省略時はフォールバック）
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
    done < <(tmux list-panes -t shogun:agents -F '2.#{pane_index} #{@agent_id}' 2>/dev/null)
}

# ─── STEP 1: ninja_states.yaml 自動生成 ───
write_state_file() {
    local state_file="$SCRIPT_DIR/queue/ninja_states.yaml"
    local lock_file="/tmp/ninja_states.lock"
    local timestamp
    printf -v timestamp '%(%Y-%m-%dT%H:%M:%S)T' -1

    # flock排他制御（他プロセスが読み書きする可能性に備える）
    # S04修正: サブシェル→ブレースグループ（fd継承によるロック漏洩を回避）
    {
        if ! flock -x -w 5 200; then
            log "ERROR: write_state_file flock failed"
        else
            # YAML生成: 単一ブロックリダイレクトでI/O削減（複数echo >> から変更）
            local karo_status="unknown"
            check_idle "$KARO_PANE" "karo" && karo_status="idle" || karo_status="busy"
            local karo_ctx
            karo_ctx=$(get_context_pct "$KARO_PANE" "karo")

            {
                printf 'updated_at: "%s"\nagents:\n' "$timestamp"
                printf '  karo:\n    pane: "%s"\n    status: %s\n    ctx_pct: %s\n    last_task: ""\n' \
                    "$KARO_PANE" "$karo_status" "$karo_ctx"

                # 忍者
                for name in "${NINJA_NAMES[@]}"; do
                    local target="${PANE_TARGETS[$name]}"
                    if [ -z "$target" ]; then continue; fi

                    local status="${PREV_STATE[$name]:-unknown}"
                    local ctx
                    ctx=$(get_context_pct "$target" "$name")
                    # task_id取得: awkで単一パス（yaml_field_get二重呼出し排除）
                    local last_task=""
                    local _task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
                    if [ -f "$_task_file" ]; then
                        last_task=$(awk '
                            /^[ \t]*task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
                            /^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
                            END { print t }
                        ' "$_task_file")
                    fi

                    printf '  %s:\n    pane: "%s"\n    status: %s\n    ctx_pct: %s\n    last_task: "%s"\n' \
                        "$name" "$target" "$status" "$ctx" "$last_task"
                done
            } > "$state_file"
        fi
    } 200>"$lock_file"
}

# ─── ntfy_listenerヘルスチェック (cmd_635) ───
# heartbeatファイル(ext4)→ログ(NTFS)の順で生存判定。NTFS mtime遅延による偽stale防止
LAST_NTFY_HEALTH_CHECK=${LAST_NTFY_HEALTH_CHECK:-$EPOCHSECONDS}
NTFY_HEALTH_CHECK_INTERVAL=${NTFY_HEALTH_CHECK_INTERVAL:-300}
check_ntfy_listener_health() {
    local now
    now=$EPOCHSECONDS
    local elapsed=$((now - LAST_NTFY_HEALTH_CHECK))
    if [ "$elapsed" -lt "$NTFY_HEALTH_CHECK_INTERVAL" ]; then
        return 0
    fi
    LAST_NTFY_HEALTH_CHECK=$now

    local log_file="$SCRIPT_DIR/logs/ntfy_listener.log"
    local heartbeat_file="/tmp/ntfy_listener.heartbeat"
    local log_epoch=""

    # Phase 1: heartbeatファイル(ext4, 高信頼)で判定
    if [ -f "$heartbeat_file" ]; then
        log_epoch=$(cat "$heartbeat_file" 2>/dev/null || true)
        if [ -n "$log_epoch" ] && [ "$log_epoch" -gt 0 ] 2>/dev/null; then
            # heartbeatが有効 — これで判定（NTFS log不要）
            :
        else
            log_epoch=""
        fi
    fi

    # Phase 2: heartbeat不在時はログファイルにfallback（旧ロジック）
    if [ -z "$log_epoch" ]; then
        if [ ! -f "$log_file" ]; then
            return 0
        fi

        local last_line
        last_line=$(tail -1 "$log_file" 2>/dev/null || true)
        if [ -z "$last_line" ]; then
            return 0
        fi

        local ts_str
        ts_str=$(echo "$last_line" | grep -oP '\[\K[A-Za-z]+ [A-Za-z]+ +\d+ \d+:\d+:\d+ [A-Z]+ \d+' | head -1)
        if [ -z "$ts_str" ]; then
            return 0
        fi

        log_epoch=$(date -d "$ts_str" +%s 2>/dev/null || true)
        if [ -z "$log_epoch" ]; then
            return 0
        fi
    fi

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
    LAST_NTFY_RESTART=$EPOCHSECONDS
    log "ntfy_listener restart triggered by health check"
}

# ─── inbox_watcher生死監視+自動再起動 (おしお殿知見) ───
# watcher_supervisor.sh相当。プロセス生存をpgrepで確認、死亡→個別再起動。
check_inbox_watcher_health() {
    # クールダウン期間内ならスキップ
    local now=$EPOCHSECONDS
    local cooldown_sec=$((WATCHER_RESTART_COOLDOWN_MIN * 60))
    if [ $((now - LAST_WATCHER_RESTART)) -lt "$cooldown_sec" ]; then
        return 0
    fi

    # shogun + karo + 全忍者/軍師のwatcherを確認
    local all_agents=("shogun" "karo" "${NINJA_NAMES[@]}")
    local dead=()

    for agent in "${all_agents[@]}"; do
        if ! pgrep -f "inbox_watcher\\.sh ${agent} " >/dev/null 2>&1; then
            dead+=("$agent")
        fi
    done

    # GP-139 層3: デーモン鮮度チェック — スクリプトmtime > プロセス起動時刻 → 自動再起動
    # 根因: ninja_monitorがMar31版で稼働し続けcmd_1671修正未反映。inbox_watcherも同リスク
    local stale=()
    local watcher_script="$SCRIPT_DIR/scripts/inbox_watcher.sh"
    local script_mtime
    script_mtime=$(stat -c %Y "$watcher_script" 2>/dev/null || echo 0)
    for agent in "${all_agents[@]}"; do
        local watcher_pid
        watcher_pid=$(pgrep -f "inbox_watcher\\.sh ${agent} " 2>/dev/null | head -1 || true)
        if [ -n "$watcher_pid" ]; then
            local proc_start
            proc_start=$(stat -c %Y "/proc/${watcher_pid}" 2>/dev/null || echo 0)
            if [ "$script_mtime" -gt "$proc_start" ] 2>/dev/null; then
                stale+=("$agent")
                dead+=("$agent")  # staleもdead扱いで再起動対象に追加
                log "STALE-DAEMON: inbox_watcher for ${agent} (PID ${watcher_pid}) is outdated — script updated after process start. Scheduling restart."
            fi
        fi
    done

    if [ ${#dead[@]} -eq 0 ]; then
        return 0
    fi

    log "WARNING: inbox_watcher dead/stale for: ${dead[*]}. Restarting..."
    # staleプロセスを停止確認してからrestart
    local restart_blocked=()
    for agent in "${stale[@]}"; do
        local stale_pid
        stale_pid=$(pgrep -f "inbox_watcher\\.sh ${agent} " 2>/dev/null | head -1)
        if [ -n "$stale_pid" ]; then
            if ! stop_stale_inbox_watcher "$agent" "$stale_pid"; then
                restart_blocked+=("$agent")
            fi
        fi
    done

    for agent in "${dead[@]}"; do
        local blocked_agent=""
        for blocked_agent in "${restart_blocked[@]}"; do
            if [ "$agent" = "$blocked_agent" ]; then
                log "WARNING: skipping watcher restart for ${agent}; stale process did not stop"
                continue 2
            fi
        done

        local pane_target=""
        if [ "$agent" = "shogun" ]; then
            pane_target="shogun:main"
        else
            pane_target=$(tmux list-panes -t shogun:agents -F 'shogun:agents.#{pane_index}' \
                -f "#{==:#{@agent_id},${agent}}" 2>/dev/null | head -1)
        fi

        if [ -z "$pane_target" ]; then
            log "WARNING: cannot find pane for ${agent}, skipping watcher restart"
            continue
        fi

        local _cli
        _cli=$(tmux show-options -p -t "$pane_target" -v @agent_cli 2>/dev/null || echo "claude")

        local log_file="$SCRIPT_DIR/logs/inbox_watcher_${agent}.log"

        unset ASW_DISABLE_ESCALATION
        nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "$agent" "$pane_target" "$_cli" \
            &>> "$log_file" &
        disown
        log "inbox_watcher for ${agent} restarted (PID $!, pane=${pane_target})"
    done

    LAST_WATCHER_RESTART=$EPOCHSECONDS
}

stop_stale_inbox_watcher() {
    local agent="$1"
    local pid="$2"
    local grace_sec="${INBOX_WATCHER_STOP_GRACE_SEC:-2}"

    if ! kill -0 "$pid" 2>/dev/null; then
        log "stale watcher for ${agent} already stopped (PID ${pid})"
        return 0
    fi

    kill "$pid" 2>/dev/null || true
    log "SIGTERM sent to stale watcher for ${agent} (PID ${pid})"

    local elapsed=0
    while [ "$elapsed" -lt "$grace_sec" ]; do
        sleep 1
        if ! kill -0 "$pid" 2>/dev/null; then
            log "stale watcher for ${agent} stopped after SIGTERM (PID ${pid})"
            return 0
        fi
        elapsed=$((elapsed + 1))
    done

    kill -KILL "$pid" 2>/dev/null || true
    log "SIGKILL sent to stale watcher for ${agent} (PID ${pid})"

    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        log "WARNING: stale watcher for ${agent} still alive after SIGKILL (PID ${pid}); skipping old-process confirmation"
        return 1
    fi

    log "stale watcher for ${agent} stopped after SIGKILL (PID ${pid})"
    return 0
}

# ─── 家老陣形図(karo_snapshot) — 家老/clear復帰用の圧縮状態 ───
write_karo_snapshot() {
    local snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
    local lock_file="/tmp/karo_snapshot.lock"
    local timestamp
    printf -v timestamp '%(%Y-%m-%dT%H:%M:%S)T' -1

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

                # 忍者task状態 + ペインCTX%
                # L4-R24: statusキャッシュ（idle一覧セクションでyaml_field_get再読込を排除）
                declare -A _snapshot_status
                for name in "${NINJA_NAMES[@]}"; do
                    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
                    # ペインCTX%を取得（PANE_TARGETSから解決。tmux list-panes N回呼出し排除）
                    local _ctx="?%"
                    local _pane_target="${PANE_TARGETS[$name]:-}"
                    if [ -n "$_pane_target" ]; then
                        local _ctx_num
                        if _ctx_num=$(get_context_pct "$_pane_target" "$name"); then
                            _ctx="${_ctx_num}%"
                        fi
                    fi
                    # モデル短縮名を取得（@model_name未設定時はsettings.yamlのmodel_nameへフォールバック）
                    local _model_name="" _model_short="?"
                    if [ -n "$_pane_target" ]; then
                        _model_name=$(tmux show-options -p -t "$_pane_target" -v @model_name 2>/dev/null || echo "")
                    fi
                    if [ -z "$_model_name" ]; then
                        _model_name=$(get_model_display_name "$name" 2>/dev/null || echo "")
                    fi
                    case "$_model_name" in
                        *[Oo]pus*)   _model_short="Op" ;;
                        *[Ss]onnet*) _model_short="So" ;;
                        *[Hh]aiku*)  _model_short="Ha" ;;
                        *gpt*|*GPT*) _model_short="GPT" ;;
                        *[Cc]odex*)  _model_short="Cx" ;;
                        *)           _model_short="?" ;;
                    esac
                    if [ -f "$task_file" ]; then
                        local task_id status project
                        # awk単一パス: yaml_field_get×3→awk×1（453ms→131ms/cycle削減 L4-R24）
                        IFS='|' read -r task_id status project < <(awk '
                            BEGIN { t=""; s=""; p="" }
                            /^[ \t]*task_id:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
                            /^[ \t]*status:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); s=v }
                            /^[ \t]*project:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); p=v }
                            END { print t "|" s "|" p }
                        ' "$task_file")
                        # CLI死亡判定: pane_current_commandがbash/zshならdead (cmd_1851)
                        if [ -n "$_pane_target" ]; then
                            local _pane_cmd
                            _pane_cmd=$(tmux display-message -t "$_pane_target" -p '#{pane_current_command}' 2>/dev/null || true)
                            case "$_pane_cmd" in
                                bash|zsh|sh) status="dead" ;;
                            esac
                        fi
                        _snapshot_status[$name]="${status:-}"
                        echo "ninja|${name}|${task_id:-none}|${status:-idle}|${project:-none}|CTX:${_ctx}|M:${_model_short}"
                    else
                        _snapshot_status[$name]=""
                        echo "ninja|${name}|none|idle|none|CTX:${_ctx}|M:${_model_short}"
                    fi
                done

                # 報告状態
                for name in "${NINJA_NAMES[@]}"; do
                    local report_file=""
                    report_file=$(get_latest_report_file "$name" || true)
                    if [ -n "$report_file" ] && [ -f "$report_file" ]; then
                        # awk単一パスでtask_id/statusを一括取得（従来yaml_field_get×2=2サブシェル→awk×1）
                        # 6忍者×毎cycle=12サブシェル/cycle→6サブシェル/cycle削減（L511:WSL2プロセス起動コスト対策）
                        local report_task report_status
                        IFS='|' read -r report_task report_status < <(awk '
                            BEGIN { t=""; s="" }
                            /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
                            /^[ \t]*status:/ && s=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); s=v }
                            END { print t "|" s }
                        ' "$report_file" 2>/dev/null)
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
                    if [ "${PREV_STATE[$name]}" = "idle" ] || [ "${PREV_STATE[$name]}" = "done" ]; then
                        local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
                        # キャッシュから取得（ninja sectionで収集済み。yaml_field_get再読込排除 L4-R24）
                        local task_status="${_snapshot_status[$name]:-}"
                        if [ -z "$task_status" ] && [ -f "$task_file" ]; then
                            task_status=$(yaml_field_get "$task_file" "status")
                        fi
                        if [ "$task_status" != "in_progress" ] && [ "$task_status" != "acknowledged" ] && [ "$task_status" != "assigned" ] && [ "$task_status" != "failed" ]; then
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

# ─── CLI死亡検知+自動再起動 (cmd_1851) ───
# 全忍者ペインのpane_current_commandを確認し、bash/zshならCLI死亡と判定。
# 5分以内に2回以上再起動した場合はntfy ALERTのみ送信してループ防止。
check_ninja_cli_dead() {
    local now=$EPOCHSECONDS
    for name in "${NINJA_NAMES[@]}"; do
        local pane_target="${PANE_TARGETS[$name]:-}"
        [ -z "$pane_target" ] && continue

        # pane_dead判定を先に実施（Codex dead時はpane_current_command=nodeでスキップされる問題を修正）
        local _early_pane_dead
        _early_pane_dead=$(tmux display-message -t "$pane_target" -p '#{pane_dead}' 2>/dev/null || echo "0")
        if [ "$_early_pane_dead" = "1" ]; then
            # pane自体が死んでいる → CLI死亡確定
            :
        else
            # pane生存時: pane_current_commandでCLI死亡を判定
            local pane_cmd
            pane_cmd=$(tmux display-message -t "$pane_target" -p '#{pane_current_command}' 2>/dev/null || true)

            # bash/zsh/sh以外はCLI稼働中 → スキップ
            case "$pane_cmd" in
                bash|zsh|sh) ;;
                *) continue ;;
            esac
        fi

        log "CLI-DEAD: ${name}@${pane_target} pane_current_command=${pane_cmd} → CLI死亡検知"

        # ループ防止チェック: 直近CLI_DEAD_LOOP_WINDOW秒以内の再起動回数を計算
        local restart_times="${CLI_DEAD_RESTART_TIMES[$name]:-}"
        local recent_count=0
        local new_times=""
        for t in $restart_times; do
            if (( now - t < CLI_DEAD_LOOP_WINDOW )); then
                recent_count=$((recent_count + 1))
                new_times="$new_times $t"
            fi
        done
        CLI_DEAD_RESTART_TIMES[$name]="${new_times# }"  # 期限切れ記録を削除

        if (( recent_count >= CLI_DEAD_LOOP_THRESHOLD )); then
            log "CLI-DEAD-LOOP: ${name} ${recent_count}回再起動/直近${CLI_DEAD_LOOP_WINDOW}秒。ALERTのみ送信し再起動停止。"
            # ntfy flood防止: 同一agentへのLOOP ALERTは30分に1回まで
            local last_ntfy="${CLI_DEAD_LOOP_LAST_NTFY[$name]:-0}"
            if (( now - last_ntfy >= 1800 )); then
                bash "$SCRIPT_DIR/scripts/ntfy.sh" "【ALERT】${name} CLI連続死亡ループ検知。直近5分で${recent_count}回再起動。手動確認が必要。" 2>/dev/null || true
                CLI_DEAD_LOOP_LAST_NTFY[$name]=$now
            fi
            continue
        fi

        # 起動コマンドを取得
        local launch_cmd
        launch_cmd=$(build_cli_command "$name" 2>/dev/null || true)
        if [ -z "$launch_cmd" ]; then
            log "CLI-DEAD: ${name} launch_cmd取得失敗。再起動スキップ。"
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "【ALERT】${name} CLI死亡検知。launch_cmd取得失敗で自動再起動不可。手動確認が必要。" 2>/dev/null || true
            continue
        fi

        # 再起動時刻を記録
        CLI_DEAD_RESTART_TIMES[$name]="${CLI_DEAD_RESTART_TIMES[$name]} ${now}"

        log "CLI-DEAD: ${name} 再起動実行。launch_cmd=${launch_cmd}"

        # pane_dead判定: remain-on-exitでペインが死亡状態ならsend-keysは無効
        local pane_dead
        pane_dead=$(tmux display-message -t "$pane_target" -p '#{pane_dead}' 2>/dev/null || echo "0")

        # バックグラウンドで再起動+30秒後確認（メインループをブロックしない）
        local _pane_target_bg="$pane_target"
        local _name_bg="$name"
        local _launch_bg="$launch_cmd"
        local _pane_dead_bg="$pane_dead"
        local _script_dir_bg="$SCRIPT_DIR"
        (
            if [ "$_pane_dead_bg" = "1" ]; then
                # pane_dead=1: send-keysは無効。respawn-paneでペインプロセスを再生成
                log "CLI-DEAD: ${_name_bg} pane_dead=1 → respawn-pane使用"
                # PATH必須: codex shebang=#!/usr/bin/env node → nvm PATHなしでexit 127
                local _node_path="/home/simokitafresh/.nvm/versions/node/v20.20.0/bin"
                tmux respawn-pane -k -t "$_pane_target_bg" "export PATH=\"${_node_path}:\$PATH\" && cd '${_script_dir_bg}' && ${_launch_bg}" 2>/dev/null || true
            else
                # pane_dead=0: シェルは生きているがCLIが終了した状態。send-keysで再起動
                tmux send-keys -t "$_pane_target_bg" C-c 2>/dev/null || true
                sleep 1
                tmux send-keys -t "$_pane_target_bg" C-c 2>/dev/null || true
                sleep 1
                tmux send-keys -t "$_pane_target_bg" "cd \"${_script_dir_bg}\" && clear" Enter 2>/dev/null || true
                sleep 1
                tmux send-keys -t "$_pane_target_bg" "$_launch_bg" Enter 2>/dev/null || true
            fi
            sleep 30
            # LK009 enforcement: CLI再起動後に@agent_idを再設定（pane変数汚染防止）
            local _current_agent_id
            _current_agent_id=$(tmux display-message -t "$_pane_target_bg" -p '#{@agent_id}' 2>/dev/null || true)
            if [ "$_current_agent_id" != "$_name_bg" ]; then
                log "AGENT-ID-FIX: ${_name_bg}@${_pane_target_bg} agent_id was '${_current_agent_id}' → resetting to '${_name_bg}'"
                tmux set-option -t "$_pane_target_bg" -p @agent_id "$_name_bg" 2>/dev/null || true
            fi
            local post_cmd
            post_cmd=$(tmux display-message -t "$_pane_target_bg" -p '#{pane_current_command}' 2>/dev/null || true)
            case "$post_cmd" in
                bash|zsh|sh)
                    bash "$_script_dir_bg/scripts/ntfy.sh" "【CLI再起動失敗】${_name_bg}: pane_cmd=${post_cmd}（まだshell）。手動確認が必要。" 2>/dev/null || true
                    ;;
                *)
                    bash "$_script_dir_bg/scripts/ntfy.sh" "【CLI再起動成功】${_name_bg}: pane_cmd=${post_cmd}" 2>/dev/null || true
                    ;;
            esac
        ) &
    done
}

# ─── 家老/clear送信共通関数（全コードパスで使用） ───
# デバウンスを内蔵。呼び出し元がデバウンスを気にする必要なし。
# $1: ctx_num（ログ用）, $2: caller（ログ用、省略可）
# 戻り値: 0=送信成功, 1=デバウンスで抑制
send_karo_clear() {
    local ctx_num="${1:-?}"
    local caller="${2:-check_karo_clear}"
    local now
    now=$EPOCHSECONDS
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
    if [ -z "$ctx_num" ] || [ "$ctx_num" -le 70 ] 2>/dev/null; then
        return  # CTX <= 70% → skip
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
    now=$EPOCHSECONDS
    local last=$LAST_SHOGUN_ALERT
    local elapsed=$((now - last))

    # CTX帯dedup: 同じ10%帯(50-59,60-69,70-79...)なら再送しない
    local ctx_band=$(( ctx_num / 10 * 10 ))
    local _ctx_band_file="/tmp/mas-shogun-ctx-band-last.txt"
    local _last_band=0
    if [[ -f "$_ctx_band_file" ]]; then
        _last_band=$(cat "$_ctx_band_file" 2>/dev/null || echo 0)
    fi
    if [ "$ctx_band" -le "$_last_band" ] 2>/dev/null && [ $elapsed -lt $SHOGUN_ALERT_DEBOUNCE ]; then
        log "SHOGUN-ALERT-BAND-DEDUP: CTX:${ctx_num}% band=${ctx_band}% same as last (${_last_band}%)"
        return
    fi

    if [ $elapsed -ge $SHOGUN_ALERT_DEBOUNCE ]; then
        local msg="【monitor】将軍CTX:${ctx_num}%。/compactをご検討ください"
        if bash "$SCRIPT_DIR/scripts/ntfy.sh" "$msg" >> "$LOG" 2>&1; then
            echo "$ctx_band" > "$_ctx_band_file"
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
    local all_agents=("karo" "gunshi" "${NINJA_NAMES[@]}")

    for name in "${all_agents[@]}"; do
        local target
        if [ "$name" = "karo" ]; then
            target="$KARO_PANE"
        elif [ "$name" = "gunshi" ]; then
            target="$GUNSHI_PANE"
        else
            target="${PANE_TARGETS[$name]}"
        fi
        [ -z "$target" ] && continue

        # モデル表示名解決（model_resolve.shに統一委譲）
        local expected
        expected=$(resolve_model_display "$name" "$target")

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
    local all_agents=("karo" "gunshi" "${NINJA_NAMES[@]}")
    local inbox_dir="$SCRIPT_DIR/queue/inbox"

    for name in "${all_agents[@]}"; do
        local inbox_file="${inbox_dir}/${name}.yaml"
        local target
        if [ "$name" = "karo" ]; then
            target="$KARO_PANE"
        elif [ "$name" = "gunshi" ]; then
            target="$GUNSHI_PANE"
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
LAST_LESSON_CHECK=$EPOCHSECONDS
LESSON_CHECK_INTERVAL=600  # 10分間隔(秒)
LESSON_ALERT_DEBOUNCE=21600 # 同一ALERT再通知抑制(6時間)
LAST_LESSON_ALERT=0

# ─── workaround pattern定期チェック (cmd_1153 AC3) ───
LAST_WORKAROUND_PATTERN_CHECK=$EPOCHSECONDS
WORKAROUND_PATTERN_CHECK_INTERVAL=600  # 10分間隔(秒)

# ─── gate_improvement定期チェック (cmd_1114) ───
LAST_GATE_IMPROVEMENT=$EPOCHSECONDS
GATE_IMPROVEMENT_INTERVAL=300  # 5分間隔(秒)

# ─── 第三層loop health定期チェック (三層学習ループ自己監視) ───
LAST_LOOP_HEALTH_CHECK=$EPOCHSECONDS
LOOP_HEALTH_CHECK_INTERVAL=1800  # 30分間隔(秒)
LOOP_HEALTH_ALERT_DEBOUNCE=21600  # 同一ALERT再通知抑制(6時間)
LAST_LOOP_HEALTH_ALERT=0

check_lesson_health() {
    local now
    now=$EPOCHSECONDS

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

check_loop_health() {
    local now
    now=$EPOCHSECONDS

    local elapsed=$((now - LAST_LOOP_HEALTH_CHECK))
    if [ $elapsed -lt $LOOP_HEALTH_CHECK_INTERVAL ]; then
        return
    fi
    LAST_LOOP_HEALTH_CHECK=$now

    local gate_script="$SCRIPT_DIR/scripts/gates/gate_loop_health.sh"
    if [ ! -f "$gate_script" ]; then
        log "LOOP-HEALTH: gate_loop_health.sh not found, skip"
        return
    fi

    local output
    output=$(bash "$gate_script" 2>/dev/null) || true

    # WARNING検出 → ntfy通知(デバウンス付き)
    if echo "$output" | grep -q "WARNING:"; then
        local alert_elapsed=$((now - LAST_LOOP_HEALTH_ALERT))
        if [ $alert_elapsed -lt $LOOP_HEALTH_ALERT_DEBOUNCE ]; then
            log "LOOP-HEALTH-DEBOUNCE: WARNING detected but ${alert_elapsed}s < ${LOOP_HEALTH_ALERT_DEBOUNCE}s"
            return
        fi

        local warnings
        warnings=$(echo "$output" | grep "WARNING:" | tr '\n' ' ')
        log "LOOP-HEALTH: $warnings"
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "【三層ループALERT】${warnings}" >> "$LOG" 2>&1
        LAST_LOOP_HEALTH_ALERT=$now
    else
        # Auto-insight起票は gate_loop_health.sh 内で自動実行済み
        log "LOOP-HEALTH: OK"
    fi
}

check_workaround_pattern() {
    local now
    now=$EPOCHSECONDS

    local elapsed=$((now - LAST_WORKAROUND_PATTERN_CHECK))
    if [ $elapsed -lt $WORKAROUND_PATTERN_CHECK_INTERVAL ]; then
        return
    fi
    LAST_WORKAROUND_PATTERN_CHECK=$now

    local check_script="$SCRIPT_DIR/scripts/workaround_pattern_check.sh"
    if [ ! -f "$check_script" ]; then
        log "WORKAROUND-PATTERN: workaround_pattern_check.sh not found, skip"
        return
    fi

    bash "$check_script" >> "$SCRIPT_DIR/logs/workaround_pattern.log" 2>&1 || true
}

check_gate_improvement() {
    local now
    now=$EPOCHSECONDS

    local elapsed=$((now - LAST_GATE_IMPROVEMENT))
    if [ $elapsed -lt $GATE_IMPROVEMENT_INTERVAL ]; then
        return
    fi
    LAST_GATE_IMPROVEMENT=$now

    local gate_script="$SCRIPT_DIR/scripts/gate_improvement_trigger.sh"
    if [ ! -f "$gate_script" ]; then
        log "GATE-IMPROVEMENT: gate_improvement_trigger.sh not found, skip"
        return
    fi

    bash "$gate_script" >> "$SCRIPT_DIR/logs/gate_improvement.log" 2>&1 || true
}

check_skill_auto_improve() {
    local now last elapsed script
    now=$EPOCHSECONDS
    last=0
    if [ -f "$SKILL_AUTO_IMPROVE_STATE_FILE" ]; then
        read -r last < "$SKILL_AUTO_IMPROVE_STATE_FILE" || last=0
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    elapsed=$((now - last))
    [ "$elapsed" -lt "$SKILL_AUTO_IMPROVE_INTERVAL" ] && return

    script="$SCRIPT_DIR/scripts/skill_auto_improve.sh"
    if [ ! -x "$script" ]; then
        log "SKILL-AUTO-IMPROVE: skill_auto_improve.sh not executable, skip"
        printf '%s\n' "$now" > "$SKILL_AUTO_IMPROVE_STATE_FILE" 2>/dev/null || true
        return
    fi

    log "SKILL-AUTO-IMPROVE: weekly apply start"
    if bash "$script" --apply >> "$SCRIPT_DIR/logs/skill_auto_improve.log" 2>&1; then
        log "SKILL-AUTO-IMPROVE: weekly apply done"
    else
        log "SKILL-AUTO-IMPROVE: weekly apply failed (non-blocking)"
    fi
    printf '%s\n' "$now" > "$SKILL_AUTO_IMPROVE_STATE_FILE" 2>/dev/null || true
}

check_lesson_deprecation_candidates() {
    local now last elapsed script output metrics candidate_count bulletin_content
    now=$EPOCHSECONDS
    last=0
    if [ -f "$LESSON_DEPRECATION_STATE_FILE" ]; then
        read -r last < "$LESSON_DEPRECATION_STATE_FILE" || last=0
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    elapsed=$((now - last))
    [ "$elapsed" -lt "$LESSON_DEPRECATION_INTERVAL" ] && return

    script="$SCRIPT_DIR/scripts/lesson_deprecation_scan.sh"
    if [ ! -x "$script" ]; then
        log "LESSON-DEPRECATION: lesson_deprecation_scan.sh not executable, skip"
        printf '%s\n' "$now" > "$LESSON_DEPRECATION_STATE_FILE" 2>/dev/null || true
        return
    fi

    mkdir -p "$(dirname "$LESSON_DEPRECATION_LOG")"
    log "LESSON-DEPRECATION: daily candidate scan start"
    output=$(bash "$script" --project all --candidates-only 2>&1) || {
        {
            printf '[%s] scan failed\n' "$(date -Is)"
            printf '%s\n\n' "$output"
        } >> "$LESSON_DEPRECATION_LOG"
        log "LESSON-DEPRECATION: daily candidate scan failed (non-blocking)"
        printf '%s\n' "$now" > "$LESSON_DEPRECATION_STATE_FILE" 2>/dev/null || true
        return
    }

    {
        printf '[%s] scan completed\n' "$(date -Is)"
        printf '%s\n\n' "$output"
    } >> "$LESSON_DEPRECATION_LOG"

    metrics=$(printf '%s\n' "$output" | awk '/^METRICS:/ {print; exit}')
    if [ -n "$metrics" ]; then
        log "LESSON-DEPRECATION-METRICS: ${metrics#METRICS: }"
    fi

    candidate_count=$(printf '%s\n' "$output" | awk '/^[[:space:]]+\[[^]]+\] L[0-9]+:/ {count++} END {print count+0}')
    if [ "$candidate_count" -gt 0 ] 2>/dev/null; then
        bulletin_content=$(
            {
                printf 'lesson_deprecation_candidates: effectiveness閾値未満の教訓候補 %s件。承認後は lesson_write.sh <project> --retire <lesson_id> で状態更新されたし。log=%s\n' "$candidate_count" "$LESSON_DEPRECATION_LOG"
                printf '%s\n' "$output" | awk 'NR <= 80 {print}'
            }
        )
        if BULLETIN_NOTIFY=shogun bash "$SCRIPT_DIR/scripts/bulletin_write.sh" ninja_monitor "$bulletin_content" false action_required >> "$LOG" 2>&1; then
            log "LESSON-DEPRECATION: posted ${candidate_count} candidates to shogun bulletin"
        else
            log "LESSON-DEPRECATION: bulletin_write failed (non-blocking)"
        fi
    else
        log "LESSON-DEPRECATION: no candidates"
    fi

    printf '%s\n' "$now" > "$LESSON_DEPRECATION_STATE_FILE" 2>/dev/null || true
}

check_script_size_thresholds() {
    local now last elapsed stats alerts alert_count bulletin_content
    now=$EPOCHSECONDS
    last=0
    if [ -f "$SCRIPT_SIZE_CHECK_STATE_FILE" ]; then
        read -r last < "$SCRIPT_SIZE_CHECK_STATE_FILE" || last=0
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    elapsed=$((now - last))
    [ "$elapsed" -lt "$SCRIPT_SIZE_CHECK_INTERVAL" ] && return

    if [ ! -d "$SCRIPT_DIR/scripts" ]; then
        log "SCRIPT-SIZE: scripts directory not found, skip"
        printf '%s\n' "$now" > "$SCRIPT_SIZE_CHECK_STATE_FILE" 2>/dev/null || true
        return
    fi

    mkdir -p "$(dirname "$SCRIPT_SIZE_TREND_LOG")"
    stats=$(
        find "$SCRIPT_DIR/scripts" -maxdepth 1 -type f -name '*.sh' -print 2>/dev/null \
            | sort \
            | while IFS= read -r script_path; do
                [ -f "$script_path" ] || continue
                awk -v file="${script_path#"$SCRIPT_DIR"/}" '
                    { lines++ }
                    /^[[:space:]]*#/ { next }
                    {
                        if ($0 ~ /^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*[[:space:]]*[(][)]|function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*)/) funcs++
                        if ($0 ~ /^[[:space:]]*(if|elif|for|while|case)[[:space:]]/) branches++
                    }
                    END {
                        complexity = lines + (funcs * 25) + (branches * 5)
                        printf "%s\t%d\t%d\t%d\t%d\n", file, lines, funcs, branches, complexity
                    }
                ' "$script_path"
            done \
            | sort -k2,2nr
    )

    if [ -z "$stats" ]; then
        log "SCRIPT-SIZE: no scripts found"
        printf '%s\n' "$now" > "$SCRIPT_SIZE_CHECK_STATE_FILE" 2>/dev/null || true
        return
    fi

    {
        printf 'timestamp\tfile\tlines\tfunctions\tbranches\tcomplexity\n'
        printf '%s\n' "$stats" | awk -v ts="$(date -Is)" 'BEGIN{OFS="\t"} {print ts,$1,$2,$3,$4,$5}'
    } >> "$SCRIPT_SIZE_TREND_LOG"

    alerts=$(
        printf '%s\n' "$stats" | awk \
            -v line_threshold="$SCRIPT_SIZE_LINE_THRESHOLD" \
            -v complexity_threshold="$SCRIPT_SIZE_COMPLEXITY_THRESHOLD" \
            'BEGIN{OFS="\t"} ($2 > line_threshold || $5 > complexity_threshold) {print $0}'
    )
    alert_count=$(printf '%s\n' "$alerts" | awk 'NF {c++} END {print c+0}')

    if [ "$alert_count" -gt 0 ] 2>/dev/null; then
        printf '%s\n' "$alerts" | while IFS=$'\t' read -r file lines funcs branches complexity; do
            [ -n "$file" ] || continue
            log "SCRIPT-SIZE-ALERT: ${file} lines=${lines}/${SCRIPT_SIZE_LINE_THRESHOLD} complexity=${complexity}/${SCRIPT_SIZE_COMPLEXITY_THRESHOLD} functions=${funcs} branches=${branches}"
        done
        bulletin_content=$(
            {
                printf 'script_size_alert: scripts/配下の主要スクリプト %s件が閾値超過。将軍はリファクタcmd起票を検討されたし。line_threshold=%s complexity_threshold=%s log=%s\n' "$alert_count" "$SCRIPT_SIZE_LINE_THRESHOLD" "$SCRIPT_SIZE_COMPLEXITY_THRESHOLD" "$SCRIPT_SIZE_TREND_LOG"
                printf '%s\n' "$alerts" | awk 'BEGIN{FS="\t"} {printf "- %s: lines=%s functions=%s branches=%s complexity=%s\n",$1,$2,$3,$4,$5}'
            }
        )
        if BULLETIN_NOTIFY=shogun bash "$SCRIPT_DIR/scripts/bulletin_write.sh" ninja_monitor "$bulletin_content" false action_required >> "$LOG" 2>&1; then
            log "SCRIPT-SIZE: posted ${alert_count} refactor request candidates to shogun bulletin"
        else
            log "SCRIPT-SIZE: bulletin_write failed (non-blocking)"
        fi
    else
        local top_summary
        top_summary=$(printf '%s\n' "$stats" | head -3 | awk 'BEGIN{FS="\t"; ORS=" "} {printf "%s:%sl/%scx",$1,$2,$5}')
        log "SCRIPT-SIZE: OK top=${top_summary}"
    fi

    printf '%s\n' "$now" > "$SCRIPT_SIZE_CHECK_STATE_FILE" 2>/dev/null || true
}

check_gate_fail_pass_transition() {
    local now last elapsed
    now=$EPOCHSECONDS
    last=0
    if [ -f "$GATE_FAIL_PASS_TRANSITION_STATE_FILE" ]; then
        read -r last < "$GATE_FAIL_PASS_TRANSITION_STATE_FILE" || last=0
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    elapsed=$((now - last))
    [ "$elapsed" -lt "$GATE_FAIL_PASS_TRANSITION_INTERVAL" ] && return

    if [ ! -f "$SCRIPT_DIR/logs/gate_fire_log.yaml" ]; then
        log "GATE-FAIL-PASS-TRANSITION: gate_fire_log.yaml not found, skip"
        printf '%s\n' "$now" > "$GATE_FAIL_PASS_TRANSITION_STATE_FILE" 2>/dev/null || true
        return
    fi

    if GATE_FAIL_PASS_REPO_ROOT="$SCRIPT_DIR" \
        GATE_FAIL_PASS_OUTPUT="$GATE_FAIL_PASS_TRANSITION_LOG" \
        GATE_FAIL_PASS_NOW="${GATE_FAIL_PASS_NOW:-}" \
        python3 <<'PY' >> "$LOG" 2>&1
import os
import re
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

repo = Path(os.environ["GATE_FAIL_PASS_REPO_ROOT"])
output = Path(os.environ["GATE_FAIL_PASS_OUTPUT"])
now_raw = os.environ.get("GATE_FAIL_PASS_NOW", "").strip()
if now_raw:
    now = datetime.fromisoformat(now_raw.replace("Z", "+00:00"))
else:
    now = datetime.now(timezone.utc)
if now.tzinfo is None:
    now = now.replace(tzinfo=timezone.utc)
cutoff = now - timedelta(days=30)

fire_log = repo / "logs" / "gate_fire_log.yaml"
re_ts = re.compile(r'ts:\s*"([^"]+)"')
re_file = re.compile(r'file:\s*"([^"]*)"')
re_gate = re.compile(r'gate:\s*"?(.*?)"?(?:,|\s+result:)')
re_result = re.compile(r'result:\s*([A-Z][A-Z-]*)')

entries = []
for raw in fire_log.read_text(encoding="utf-8", errors="ignore").splitlines():
    line = raw.strip()
    if not line.startswith("- "):
        continue
    tm = re_ts.search(line)
    gm = re_gate.search(line)
    rm = re_result.search(line)
    if not (tm and gm and rm):
        continue
    fm = re_file.search(line)
    file_value = fm.group(1) if fm else ""
    if file_value.startswith("/tmp/"):
        continue
    try:
        ts = datetime.fromisoformat(tm.group(1).replace("Z", "+00:00"))
    except ValueError:
        continue
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    if ts < cutoff or ts > now + timedelta(minutes=5):
        continue
    entries.append((ts, gm.group(1).strip(), rm.group(1).strip()))

entries.sort(key=lambda item: item[0])
stats = defaultdict(lambda: {"fail": 0, "recovered": 0, "open": 0, "pass": 0})
for _ts, gate, result in entries:
    if result == "FAIL":
        stats[gate]["fail"] += 1
        stats[gate]["open"] += 1
    elif result == "PASS":
        stats[gate]["pass"] += 1
        if stats[gate]["open"] > 0:
            stats[gate]["recovered"] += stats[gate]["open"]
            stats[gate]["open"] = 0

output.parent.mkdir(parents=True, exist_ok=True)
header = "ts\twindow_days\tgate\ttransition_rate_pct\trecovered_fail\tfail_total\tunrecovered_fail\tpass_total\n"
if not output.exists() or output.stat().st_size == 0:
    output.write_text(header, encoding="utf-8")

run_ts = now.isoformat()
rows = []
for gate, item in stats.items():
    fail = item["fail"]
    recovered = item["recovered"]
    rate = round((recovered / fail) * 100) if fail else 100
    rows.append((gate, rate, recovered, fail, item["open"], item["pass"]))
rows.sort(key=lambda row: (-row[3], row[0]))

with output.open("a", encoding="utf-8") as fh:
    if rows:
        for gate, rate, recovered, fail, open_count, pass_count in rows:
            fh.write(f"{run_ts}\t30\t{gate}\t{rate}\t{recovered}\t{fail}\t{open_count}\t{pass_count}\n")
    else:
        fh.write(f"{run_ts}\t30\tSKIP_NO_RECENT_DATA\t0\t0\t0\t0\t0\n")

print(f"GATE-FAIL-PASS-TRANSITION: wrote {len(rows) or 1} row(s) to {output}")
PY
    then
        log "GATE-FAIL-PASS-TRANSITION: daily record done"
    else
        log "GATE-FAIL-PASS-TRANSITION: daily record failed (non-blocking)"
    fi
    printf '%s\n' "$now" > "$GATE_FAIL_PASS_TRANSITION_STATE_FILE" 2>/dev/null || true
}

check_ntfy_batch_flush() {
    local now
    now=$EPOCHSECONDS

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
    now=$EPOCHSECONDS
    local elapsed=$((now - LAST_CDP_CLEANUP))
    if [ "$elapsed" -lt "$CDP_CLEANUP_INTERVAL" ]; then
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

# ═══ /tmp lock file定期cleanup ═══
# lock_path.shが生成するshogun_lock_*.lock + auto_deploy_*.lockが蓄積(10000+件)
# flockはfd操作のため古いファイルは安全に削除可能
run_lock_cleanup() {
    local now=$EPOCHSECONDS
    local elapsed=$((now - LAST_LOCK_CLEANUP))
    if [ "$elapsed" -lt "$LOCK_CLEANUP_INTERVAL" ]; then
        return 0
    fi
    local cleanup_dir="${LOCK_CLEANUP_DIR:-/tmp}"
    local deleted_paths count
    deleted_paths=$(
        find "$cleanup_dir" -maxdepth 1 -type f \
            \( -name "shogun_lock_*.lock" -o -name "auto_deploy_*.lock" \) \
            -mmin +60 -print -delete 2>/dev/null || true
    )
    count=$(printf '%s\n' "$deleted_paths" | awk 'NF {c++} END {print c+0}')
    if [ "$count" -gt 0 ]; then
        log "LOCK-CLEANUP: Removed $count stale lock files from $cleanup_dir"
    fi
    LAST_LOCK_CLEANUP=$now
}

# ═══ 掲示板自動アーカイブ (掲示板肥大防止) ═══
# 1時間ごとに bulletin_archive.sh を実行
# 24h超+closed/no-confirm-needed のエントリをアーカイブ、直近30件保持
check_bulletin_archive() {
    local now=$EPOCHSECONDS
    local elapsed=$((now - LAST_BULLETIN_ARCHIVE))
    if [ "$elapsed" -lt "$BULLETIN_ARCHIVE_INTERVAL" ]; then
        return 0
    fi
    local bulletin_file="$SCRIPT_DIR/queue/bulletin_board.yaml"
    if [ ! -f "$bulletin_file" ]; then
        LAST_BULLETIN_ARCHIVE=$now
        return 0
    fi
    local entry_count
    entry_count=$(awk '/^- id:/ {c++} END {print c+0}' "$bulletin_file" 2>/dev/null || echo 0)
    if [ "$entry_count" -gt 30 ]; then
        local result
        result=$(timeout 30 bash "$SCRIPT_DIR/scripts/bulletin_archive.sh" 2>&1) || true
        if [[ "$result" == *"Archived"* ]]; then
            log "BULLETIN-ARCHIVE: $result"
        fi
    fi
    LAST_BULLETIN_ARCHIVE=$now
}

# ═══ 家老idle自走サイクル起動チェック (cmd_1498) ═══
# 全忍者idle/completed/done + パイプライン空 → 家老に改善サイクル起動を通知
check_karo_idle_cycle() {
    # 自走プロトコルoff時は通知しない
    local idle_cycle_flag
    idle_cycle_flag=$(grep -m1 '^\s*idle_cycle:' "$SCRIPT_DIR/config/settings.yaml" 2>/dev/null | sed 's/.*idle_cycle:[[:space:]]*//' | sed 's/[[:space:]]*#.*//' | tr -d "'" | tr -d '"')
    if [ "$idle_cycle_flag" = "off" ]; then
        return
    fi

    local snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
    [ ! -f "$snapshot_file" ] && return

    # 条件1: 全忍者がidle/completed/doneか確認
    local ninja_total
    ninja_total=$(awk '/^ninja\|/ {c++} END {print c+0}' "$snapshot_file" 2>/dev/null || echo 0)
    [ "${ninja_total:-0}" -eq 0 ] && return

    local active_count
    active_count=$(awk -F'|' '/^ninja\|/ && $4 !~ /^(idle|completed|done)$/ {c++} END {print c+0}' "$snapshot_file" 2>/dev/null || echo 0)
    if [ "${active_count:-0}" -gt 0 ]; then
        return
    fi

    # 条件2: パイプラインに未処理cmdがないか確認
    local pending_count
    pending_count=$(awk '/^[[:space:]]+status:[[:space:]]*(pending|new)/ {c++} END {print c+0}' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || echo 0)
    if [ "${pending_count:-0}" -gt 0 ]; then
        return
    fi

    # クールダウンチェック（30分）
    local now
    now=$EPOCHSECONDS
    local elapsed=$(( now - LAST_KARO_IDLE_NUDGE ))
    if [ "$elapsed" -lt "$KARO_IDLE_COOLDOWN" ]; then
        return
    fi

    # 全条件成立: 家老に改善サイクル起動を通知
    log "KARO-IDLE-CYCLE: All ${ninja_total} ninjas idle/completed/done + pipeline empty → nudging karo"
    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "全忍者idle+パイプライン空。改善サイクルを回せ。" karo_idle_cycle ninja_monitor >> "$LOG" 2>&1; then
        LAST_KARO_IDLE_NUDGE=$now
        log "KARO-IDLE-CYCLE: Sent improvement cycle nudge to karo"
    else
        log "ERROR: KARO-IDLE-CYCLE inbox_write failed"
    fi
}

# ─── 初期ペイン探索 ───
if [ "${NINJA_MONITOR_LIB_ONLY:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

discover_panes

# ─── GP-239: Codex bypass flag check (startup) ───
# hayate事故(2026-04-28): --dangerously-bypass-approvals-and-sandbox欠落→毎回確認プロンプトで停止
for _cbf_name in "${NINJA_NAMES[@]}"; do
    if [ "$(cli_type "$_cbf_name" 2>/dev/null)" = "codex" ]; then
        _cbf_pane="${PANE_MAP[$_cbf_name]:-}"
        [ -z "$_cbf_pane" ] && continue
        _cbf_pid=$(tmux list-panes -t "$_cbf_pane" -F '#{pane_pid}' 2>/dev/null | head -1)
        [ -z "$_cbf_pid" ] && continue
        if ! pstree -a "$_cbf_pid" 2>/dev/null | grep -q 'dangerously-bypass'; then
            log "WARN: ${_cbf_name} Codex missing --dangerously-bypass-approvals-and-sandbox flag"
            echo "[$(date -Is)] WARN: ${_cbf_name} Codex bypass flag missing → confirmation prompts will block ninja" >> "$LOG"
        fi
    fi
done

# ─── メインループ ───
cycle=0
prev_idle=""
prev_gate_lines=0

while true; do
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
                if [ "$_s1_task_status" = "assigned" ] || [ "$_s1_task_status" = "acknowledged" ] || [ "$_s1_task_status" = "in_progress" ] || [ "$_s1_task_status" = "pending" ]; then
                    if auto_void_if_parent_cmd_completed "$name" "$target" "STAGE1"; then
                        PREV_STATE[$name]="idle"
                        continue
                    fi
                    # cmd_1156 AC2: STAGE1-SKIP timeout safety valve
                    _s1_task_mtime=$(stat -c %Y "$_s1_task_file" 2>/dev/null || echo 0)
                    _s1_now=$EPOCHSECONDS
                    _s1_age=$(( _s1_now - _s1_task_mtime ))
                    _s1_threshold=900  # 15 minutes default
                    if [ "$_s1_task_status" = "in_progress" ]; then
                        _s1_threshold=1800  # 30 minutes for in_progress
                    fi
                    if [ "$_s1_age" -ge "$_s1_threshold" ]; then
                        # cmd_1292 AC1: report存在チェック — active taskでreport未提出なら/clear禁止
                        _s1_report_file=$(resolve_expected_report_file "$name")
                        _s1_report_found=false
                        if [[ "$_s1_report_file" = /* ]]; then
                            [ -f "$_s1_report_file" ] && _s1_report_found=true
                        else
                            [ -f "$SCRIPT_DIR/queue/reports/${_s1_report_file}" ] && _s1_report_found=true
                            if [ "$_s1_report_found" = false ]; then
                                compgen -G "$SCRIPT_DIR/queue/archive/reports/${_s1_report_file}" > /dev/null 2>&1 && _s1_report_found=true
                            fi
                        fi
                        if [ "$_s1_report_found" = false ]; then
                            log "STAGE1-REPORT-MISSING: $name task_status=$_s1_task_status stale for ${_s1_age}s but no report (${_s1_report_file}), /clear禁止"
                            PREV_STATE[$name]="busy"
                            continue
                        fi
                        # Stale task: reset status to idle and allow /clear
                        if grep -q "^status:" "$_s1_task_file"; then
                            sed -i "s/^status: .*/status: idle/" "$_s1_task_file"
                        else
                            yaml_field_set "$_s1_task_file" "task" "status" "idle" 2>/dev/null || \
                                sed -i "s/^  status: .*/  status: idle/" "$_s1_task_file"
                        fi
                        log "STAGE1-TIMEOUT: $name task_status=$_s1_task_status stale for ${_s1_age}s, resetting to idle"
                        # cmd_1185 AC2: TIMEOUT後はGuard 2をバイパスしてmaybe_idleへ直接追加
                        # 理由: sed/yaml_field_setでmtime更新→Guard 2が120s未満と誤判定→/clear永久スキップ
                        maybe_idle+=("$name")
                        continue
                    else
                        log "STAGE1-SKIP: $name idle but task_status=${_s1_task_status}, /clear禁止"
                        PREV_STATE[$name]="busy"
                        continue
                    fi
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
                _s1_now=$EPOCHSECONDS
                _s1_age=$((_s1_now - _s1_mtime))
                if [ "$_s1_age" -lt 120 ]; then
                    if [ "$_s1_task_status" = "assigned" ] || [ "$_s1_task_status" = "acknowledged" ] || [ "$_s1_task_status" = "in_progress" ] || [ "$_s1_task_status" = "pending" ]; then
                        log "SKIP_CLEAR: $name recent task update (${_s1_age}s ago), status=$_s1_task_status"
                        PREV_STATE[$name]="busy"
                        continue
                    fi
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
            codex_confirm_wait="${codex_confirm_wait:-$CONFIRM_WAIT}"
            extra_wait=$((codex_confirm_wait - CONFIRM_WAIT))
            sleep "${extra_wait:-0}"

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

    # ═══ report done + status未idle 検知 ═══
    check_report_done_idle_mismatch

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

    # ═══ 未配備cmd常時監視（pending+delegated_at 10分超） ═══
    check_undeployed_cmds

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

    # ═══ skill_auto_improve定期チェック（週1回 cmd_2605） ═══
    check_skill_auto_improve

    # ═══ effectiveness低下教訓deprecate候補の日次抽出（cmd_2757） ═══
    check_lesson_deprecation_candidates

    # ═══ scripts/主要スクリプト肥大化チェック（cmd_2759） ═══
    check_script_size_thresholds

    # ═══ gate_fire_log FAIL→PASS遷移率の日次記録（cmd_2755） ═══
    check_gate_fail_pass_transition

    # ═══ INFOバッチ通知フラッシュ（15分間隔 cmd_960 AC2） ═══
    check_ntfy_batch_flush

    # ═══ STEP 2: 家老の外部/clearチェック（無効化: 殿裁定2026-03-25 家老はAUTOCOMPACTのみ） ═══
    # check_karo_clear

    # ═══ STEP 3: 将軍CTXアラート ═══
    check_shogun_ctx

    # ═══ Phase 3: context_pct更新（全ペイン） ═══
    update_all_context_pct

    # ═══ inbox未読数ペイン変数更新 (cmd_188) ═══
    update_inbox_counts

    # ═══ lesson健全性チェック (cmd_279) ═══
    check_lesson_health

    # ═══ 第三層loop健全性チェック (三層学習ループ自己監視) ═══
    check_loop_health

    # ═══ workaroundパターン検出 (cmd_1153) ═══
    check_workaround_pattern

    # ═══ archive自動退避 (cmd_279) ═══
    check_auto_archive

    # ═══ STEP 1: ninja_states.yaml 自動生成 ═══
    write_state_file
    write_karo_snapshot   # 家老陣形図更新（毎サイクル）
    check_karo_idle_cycle       # 家老idle自走サイクル起動チェック (cmd_1498)
    check_ntfy_listener_health  # ntfy_listenerゾンビ検知 (cmd_635)
    check_inbox_watcher_health  # inbox_watcher死亡検知+自動再起動 (おしお殿知見)
    check_ninja_cli_dead        # 忍者CLI死亡検知+自動再起動 (cmd_1851)
    run_lock_cleanup            # /tmp orphan lock files定期削除
    check_bulletin_archive      # 掲示板自動アーカイブ（肥大防止）

    # ═══ STEP 2: ダッシュボード自動更新 (cmd_404) ═══
    # 状態変化時のみ呼び出す（コスト最適化）
    current_idle=$(grep "^idle|" "$SCRIPT_DIR/queue/karo_snapshot.txt" 2>/dev/null | head -1 || echo "")
    current_gate_lines=$(wc -l < "$SCRIPT_DIR/logs/gate_metrics.log" 2>/dev/null || echo 0)
    current_context_warn_sig=$(
        bash "$SCRIPT_DIR/scripts/context_freshness_check.sh" --dashboard-warnings 2>/dev/null \
            | cksum | awk '{print $1 ":" $2}' || echo "missing"
    )
    # CI status: 5分間隔でキャッシュ更新（GitHubAPI毎サイクル呼出し→1708ms/cycle削減 L4-R24）
    _ci_check_now=$EPOCHSECONDS
    if (( _ci_check_now - CI_STATUS_CHECK_LAST >= CI_STATUS_CHECK_INTERVAL )); then
        CI_STATUS_CACHE=$(bash "$SCRIPT_DIR/scripts/ci_status_check.sh" --status 2>/dev/null || echo "UNKNOWN")
        CI_STATUS_CHECK_LAST=$_ci_check_now
    fi
    current_ci_status="$CI_STATUS_CACHE"
    current_unpushed_count=$(cd "$SCRIPT_DIR" && git rev-list origin/main..HEAD --count 2>/dev/null || echo 0)
    if [[ "$current_idle" != "$prev_idle" || "$current_gate_lines" != "$prev_gate_lines" || "$current_context_warn_sig" != "$prev_context_warn_sig" || "$current_ci_status" != "$prev_ci_status" || "$current_unpushed_count" != "$prev_unpushed_count" ]]; then
        bash "$SCRIPT_DIR/scripts/dashboard_auto_section.sh" 2>/dev/null || true
        prev_idle="$current_idle"
        prev_gate_lines="$current_gate_lines"
        prev_context_warn_sig="$current_context_warn_sig"
        prev_ci_status="$current_ci_status"
        prev_unpushed_count="$current_unpushed_count"
    fi

    # ═══ 連想配列クリーンアップ（10分間隔 H1: メモリリーク防止） ═══
    if [ $((cycle % 30)) -eq 0 ]; then
        _cleanup_stale_keys
    fi

    # ═══ Self-restart check ═══
    check_script_update

    sleep "$POLL_INTERVAL"
done
