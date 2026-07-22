#!/bin/bash
# semantic-links: [[インフラ設計意図カタログ]], [[インフラ運用基盤]], [[デーモン監視と復旧]], [[忍者修行サイクル品質]], [[編成管理]]
# doc-links: [[infrastructure.md]], [[infra-details]], [[training-cycle]], [[training-cycle.md]], [[ninja_monitor_requirements.md]], [[ninja_monitor_design.md]], [[three-layer-memory-l0-l7-penetration-design_20260604]], [[multi-cli-hook-event-commonization-design_20260602]]
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

# cmd_training_speed_ninja_monitor_20260607140828: サブシェル不要の純bash文字列演算でSCRIPT_DIR解決
_NM_SELF="${BASH_SOURCE[0]}"
[[ "$_NM_SELF" != /* ]] && _NM_SELF="$PWD/$_NM_SELF"
SCRIPT_DIR="${_NM_SELF%/scripts/ninja_monitor.sh}"
LOG="$SCRIPT_DIR/logs/ninja_monitor.log"
TRAINING_EFFECT_LOG="$SCRIPT_DIR/logs/training_effect.log"  # 修行before/after FAIL率比較ログ (cmd_2767)
STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"
source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
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
source "$SCRIPT_DIR/scripts/lib/disk_space_watch.sh"
source "$SCRIPT_DIR/scripts/lib/report_terminal_state.sh"
source "$SCRIPT_DIR/scripts/lib/respawn_recovery.sh"

# --- CTX profile cache（L4-R?: cli_profile_getサブシェル呼び出し削減） ---
# update_context_pct ループ内での$(cli_profile_get ...)サブシェル(78ms/回)を排除するグローバルキャッシュ
# 主シェル文脈(update_all_context_pct経由)でのみ有効。サブシェルからのget_context_pct呼び出しは従来通り
declare -gA _CTX_PROFILE_PATTERN_CACHE _CTX_PROFILE_MODE_CACHE 2>/dev/null || \
    declare -A _CTX_PROFILE_PATTERN_CACHE _CTX_PROFILE_MODE_CACHE 2>/dev/null || true

# --- Variables needed by lib functions (outside guard for lib-only mode) ---
STALL_THRESHOLD_MIN=${STALL_THRESHOLD_MIN:-10} # 停滞検知しきい値（分）— assigned+idle状態がこの時間継続で通知 (cmd_1105: 15→10分に短縮)
KARO_PENDING_CMD_GRACE_SEC=${KARO_PENDING_CMD_GRACE_SEC:-30} # cmd_save→cmd_delegate正規フローの短いpending窓をcmd_pending重複通知しない猶予
CI_RED_PARALLEL_THRESHOLD_SEC=${CI_RED_PARALLEL_THRESHOLD_SEC:-900}

# E1: CI RED中に遊休戦力と未配備cmdが共存する過剰直列化を、同一run世代で一度だけ検出する。
_ci_red_run_details() {
    local run_id="$1"
    timeout 15 gh run view "$run_id" --repo simokitafresh/multi-agent-shogun \
        --json headSha,createdAt 2>/dev/null \
        | jq -r --arg run "$run_id" '[$run, .headSha, (.createdAt | fromdateiso8601)] | @tsv'
}

_ci_red_idle_count() {
    python3 - "$SCRIPT_DIR/queue/tasks" <<'PY'
import glob, sys, yaml
count = 0
for path in glob.glob(sys.argv[1] + "/*.yaml"):
    try:
        task = (yaml.safe_load(open(path)) or {}).get("task", {})
    except Exception:
        continue
    if task.get("status") == "idle":
        count += 1
print(count)
PY
}

_ci_red_first_idle_ninja() {
    python3 - "$SCRIPT_DIR/queue/tasks" <<'PY'
import glob, os, sys, yaml
for path in sorted(glob.glob(sys.argv[1] + "/*.yaml")):
    try:
        task = (yaml.safe_load(open(path)) or {}).get("task", {})
    except Exception:
        continue
    if task.get("status") == "idle":
        print(os.path.basename(path).removesuffix(".yaml"))
        break
PY
}

_ci_red_first_deployable_cmd() {
    python3 - "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$SCRIPT_DIR/queue/tasks" <<'PY'
import glob, sys, yaml
try:
    data = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    raise SystemExit(0)
deployed = set()
for path in glob.glob(sys.argv[2] + "/*.yaml"):
    try:
        task = (yaml.safe_load(open(path)) or {}).get("task", {})
    except Exception:
        continue
    if task.get("status") != "idle" and task.get("parent_cmd"):
        deployed.add(str(task["parent_cmd"]))
items = data.get("commands", data.get("cmds", data if isinstance(data, list) else []))
if isinstance(items, dict):
    items = list(items.values())
for item in items if isinstance(items, list) else []:
    cmd = str(item.get("id") or item.get("cmd_id") or "") if isinstance(item, dict) else ""
    if (cmd and item.get("status") in {"pending", "approved"}
            and item.get("parallel_ok") is True and cmd not in deployed):
        print(cmd)
        break
PY
}

_ci_red_parallel_gate_log() {
    local result="$1" detail="$2" log_file="${CI_RED_PARALLEL_GATE_LOG:-$SCRIPT_DIR/logs/gate_fire_log.yaml}"
    detail="${detail//\"/_}"
    mkdir -p "${log_file%/*}"
    {
        flock 9
        printf '%s\n' "- ts: \"$(date -Iseconds)\", gate: ci_red_structural_autodeploy, result: ${result}, detail: \"${detail}\"" >&9
    } 9>>"$log_file"
}

check_ci_red_parallelization_guard() {
    local ci_status="${1:-$CI_STATUS_CACHE}" now="${2:-$EPOCHSECONDS}"
    local idle_count="${3:-}" deployable_cmd="${4:-}" details="${5:-}" idle_ninja="${6:-}"
    [[ "$ci_status" == RED:* ]] || return 0
    local run_id="${ci_status#RED:}"; run_id="${run_id%%:*}"
    [[ -n "$details" ]] || details="$(_ci_red_run_details "$run_id")"
    local detail_run sha red_since
    IFS=$'\t' read -r detail_run sha red_since <<< "$details"
    [[ "$detail_run" == "$run_id" && -n "$sha" && "$red_since" =~ ^[0-9]+$ ]] || return 0
    local duration=$((now - red_since))
    (( duration >= CI_RED_PARALLEL_THRESHOLD_SEC )) || return 0
    [[ -n "$idle_count" ]] || idle_count="$(_ci_red_idle_count)"
    (( idle_count >= 1 )) || return 0
    [[ -n "$deployable_cmd" ]] || deployable_cmd="$(_ci_red_first_deployable_cmd)"
    [[ -n "$deployable_cmd" ]] || return 0
    [[ -n "$idle_ninja" ]] || idle_ninja="$(_ci_red_first_idle_ninja)"
    [[ -n "$idle_ninja" ]] || return 0

    local state_file="${CI_RED_PARALLEL_STATE_FILE:-$STATE_DIR/shogun_ci_red_parallelization.notified}"
    local generation="${run_id}:${sha}" lock_file="${state_file}.lock" previous=""
    mkdir -p "${state_file%/*}"
    exec {ci_red_lock_fd}>"$lock_file"
    if ! flock -n "$ci_red_lock_fd"; then
        _ci_red_parallel_gate_log BLOCK "run=${run_id} sha=${sha} lock_busy=1"
        exec {ci_red_lock_fd}>&-
        return 0
    fi
    [[ -f "$state_file" ]] && IFS= read -r previous < "$state_file"
    if [[ "$previous" != "$generation" ]]; then
        if bash "$SCRIPT_DIR/scripts/deploy_task.sh" "$idle_ninja" "$deployable_cmd" \
            >> "${CI_RED_PARALLEL_DEPLOY_LOG:-$SCRIPT_DIR/logs/deploy_ci_red_parallel.log}" 2>&1; then
            printf '%s\n' "$generation" > "${state_file}.tmp.$$"
            mv "${state_file}.tmp.$$" "$state_file"
            _ci_red_parallel_gate_log PASS "run=${run_id} sha=${sha} ninja=${idle_ninja} cmd=${deployable_cmd} auto_deploy=1 duplicate=0"
        else
            _ci_red_parallel_gate_log BLOCK "run=${run_id} sha=${sha} ninja=${idle_ninja} cmd=${deployable_cmd} deploy_task_failed=1"
        fi
    fi
    flock -u "$ci_red_lock_fd"
    exec {ci_red_lock_fd}>&-
}

# --- lib-only mode: skip daemon initialization (tmux/settings依存) ---
if [ "${NINJA_MONITOR_LIB_ONLY:-0}" != "1" ]; then

POLL_INTERVAL=20    # ポーリング間隔（秒）
CONFIRM_WAIT=5      # idle確認待ち（秒）— Phase 2a base wait
STALE_CMD_THRESHOLD=14400 # stale cmd検知しきい値（秒）— pending+subtask未配備が4時間継続で通知
NTFY_HEALTH_THRESHOLD_MIN=10 # ntfy_listenerヘルスチェックしきい値（分）— ログが古ければゾンビ判定
NTFY_RESTART_COOLDOWN_MIN=5  # ntfy_listener連続再起動防止クールダウン（分）
REDISCOVER_EVERY=30 # N回ポーリングごとにペイン再探索
# 家老ペインターゲット（@agent_idから動的解決。EH6: ハードコード排除完了）
KARO_PANE=$(pane_lookup karo 2>/dev/null || true)
KARO_PANE="${KARO_PANE:-${TMUX_WINDOW:-shogun:agents}.1}"  # fallback
# 軍師ペインターゲット（@agent_idから動的解決）
GUNSHI_PANE=$(pane_lookup gunshi 2>/dev/null || true)
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
    "$SCRIPT_DIR/scripts/lib/model_resolve.sh"
    "$SCRIPT_DIR/scripts/lib/field_get.sh"
    "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
    "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
    "$SCRIPT_DIR/lib/agent_state.sh"
    "$SCRIPT_DIR/lib/rotate_log.sh"
    "$SCRIPT_DIR/lib/cli_adapter.sh"
    "$SCRIPT_DIR/scripts/lib/model_colors.sh"
    "$SCRIPT_DIR/scripts/lib/agent_config.sh"
    "$SCRIPT_DIR/scripts/lib/script_update.sh"
)
DEPS_HASH="$(compute_deps_hash)"
LAST_NTFY_RESTART=0  # ntfy_listener最終再起動時刻（epoch秒）
LAST_NTFY_HEALTH_CHECK=$EPOCHSECONDS  # ntfy_listener health check最終実行時刻（epoch秒）
NTFY_HEALTH_CHECK_INTERVAL=300        # ntfy_listener health check間隔（秒）
LAST_WATCHER_RESTART=0  # inbox_watcher最終再起動時刻（epoch秒）
WATCHER_RESTART_COOLDOWN_MIN=3  # inbox_watcher連続再起動防止クールダウン（分）
LAST_BATCH_FLUSH=0   # ntfy_batch_flush最終実行時刻（epoch秒）
CDP_CLEANUP_SCRIPT="$SCRIPT_DIR/scripts/cdp_chrome_cleanup.sh"
LOCK_CLEANUP_INTERVAL=3600  # /tmp lock file cleanup間隔（秒）— 1時間
LAST_LOCK_CLEANUP=0         # lock cleanup最終実行時刻（epoch秒）
BULLETIN_ARCHIVE_INTERVAL=3600  # 掲示板archive間隔（秒）— 1時間
LAST_BULLETIN_ARCHIVE=0         # 掲示板archive最終実行時刻（epoch秒）
MEMORY_DB_LIVE_DRAIN_INTERVAL=${MEMORY_DB_LIVE_DRAIN_INTERVAL:-60}  # live insert退避queue drain間隔（秒）
LAST_MEMORY_DB_LIVE_DRAIN=0     # memory_db_live_insert_queue最終drain時刻（epoch秒）
THREE_LAYER_MAINTENANCE_INTERVAL=${THREE_LAYER_MAINTENANCE_INTERVAL:-3600}  # 三層記憶tmp cleanup+dry-run候補抽出間隔（秒）— 1時間
THREE_LAYER_MAINTENANCE_TMP_TTL_HOURS=${THREE_LAYER_MAINTENANCE_TMP_TTL_HOURS:-1}  # 4h→1h: 孤児tmp蓄積速度が速いため短縮(LK004再現)
THREE_LAYER_MAINTENANCE_TIMEOUT=${THREE_LAYER_MAINTENANCE_TIMEOUT:-120}
THREE_LAYER_MAINTENANCE_STATE_FILE="$STATE_DIR/shogun_three_layer_maintenance.last"
THREE_LAYER_MAINTENANCE_LOG="$SCRIPT_DIR/logs/three_layer_maintenance.log"
OBSIDIAN_PROMOTE_THRESHOLD=${OBSIDIAN_PROMOTE_THRESHOLD:-1}  # obsidian candidate自動昇格: candidateがあれば即昇格（殿裁定2026-06-09: 閾値で成長を止めるな）
OBSIDIAN_PROMOTE_INTERVAL=${OBSIDIAN_PROMOTE_INTERVAL:-3600}  # obsidian candidate自動昇格: 1時間間隔チェック（殿裁定2026-06-09: 道は早く伸びるほど有用）
OBSIDIAN_PROMOTE_STATE_FILE="$STATE_DIR/shogun_obsidian_promote.last"
OBSIDIAN_PROMOTE_LOG="$SCRIPT_DIR/logs/obsidian_promote.log"
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
TRAINING_AUTO_DEPLOY_IDLE_THRESHOLD=${TRAINING_AUTO_DEPLOY_IDLE_THRESHOLD:-600}   # 修行自動配備: idle継続しきい値（秒）— [[training-cycle]] §2
TRAINING_AUTO_DEPLOY_COOLDOWN=${TRAINING_AUTO_DEPLOY_COOLDOWN:-86400}             # 修行自動配備: 忍者別クールダウン（秒）
TRAINING_AUTO_DEPLOY_FAIL_RATE=${TRAINING_AUTO_DEPLOY_FAIL_RATE:-20}             # 直近gate FAIL率しきい値（%）
TRAINING_AUTO_DEPLOY_MIN_GATES=${TRAINING_AUTO_DEPLOY_MIN_GATES:-5}              # 直近gateサンプル不足時は修行条件成立
TRAINING_AUTO_DEPLOY_RECENT=${TRAINING_AUTO_DEPLOY_RECENT:-50}                   # 忍者別直近gate参照件数
TRAINING_AUTO_DEPLOY_VARIANT=${TRAINING_AUTO_DEPLOY_VARIANT:-script}             # script / codd — L4修行テンプレート種別
TRAINING_AUTO_DEPLOY_STATE_PREFIX="$STATE_DIR/shogun_training_auto_deploy"
REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD=${REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD:-600}       # 還流在庫自動配備: idle継続しきい値（秒）
REFLUX_AUTO_DEPLOY_COOLDOWN=${REFLUX_AUTO_DEPLOY_COOLDOWN:-3600}                 # 還流在庫自動配備: 忍者別クールダウン（秒）
REFLUX_AUTO_DEPLOY_STATE_PREFIX="$STATE_DIR/shogun_reflux_auto_deploy"
REFLUX_PROMOTION_LEDGER="${REFLUX_PROMOTION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_completed.tsv}"
REFLUX_PROMOTION_DEFERRED_LEDGER="${REFLUX_PROMOTION_DEFERRED_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_deferred.tsv}"
REFLUX_BACKLINK_SCAN_LIMIT=${REFLUX_BACKLINK_SCAN_LIMIT:-50}                     # backlinksゼロ在庫の1回あたり確認上限
REFLUX_BACKLINK_TIMEOUT=${REFLUX_BACKLINK_TIMEOUT:-20}                           # backlinksゼロ確認のtimeout秒
SPEED_TRAINING_LEDGER="${SPEED_TRAINING_LEDGER:-$SCRIPT_DIR/logs/script_speed_training_ledger.yaml}"
KARO_IDLE_COOLDOWN=${KARO_IDLE_COOLDOWN:-1800}   # 家老idle自走サイクルクールダウン（秒）— 30分
KARO_IDLE_NUDGE_STATE_FILE=${KARO_IDLE_NUDGE_STATE_FILE:-$STATE_DIR/shogun_karo_idle_nudge.last}
SHOGUN_IDLE_ANALYSIS_COOLDOWN=3600  # 将軍idle分析triggerクールダウン（秒）— 60分
_SHOGUN_IDLE_TRIGGER_STATE="/tmp/.shogun_idle_trigger_last"
LAST_SHOGUN_IDLE_ANALYSIS_TRIGGER=$(cat "$_SHOGUN_IDLE_TRIGGER_STATE" 2>/dev/null || echo 0) # 将軍idle分析trigger最終通知時刻（epoch秒）— ファイル永続化でrespawn跨ぎ
SHOGUN_IDLE_ANALYSIS_ALL_IDLE_SINCE=0 # 全忍者idle+pipeline空の継続開始時刻（epoch秒）
CI_STATUS_CACHE="UNKNOWN"       # CI statusキャッシュ値（L4-R24: GitHubAPI毎サイクル削減）
CI_STATUS_CHECK_LAST=0          # CI statusキャッシュ最終更新時刻（epoch秒）
CI_STATUS_CHECK_INTERVAL=300    # CI statusキャッシュ有効期間（秒）— 5分
UNPUSHED_COUNT_CACHE=0          # unpushed commits数キャッシュ — git rev-list毎サイクル実行削減
UNPUSHED_COUNT_CHECK_LAST=0     # unpushedキャッシュ最終更新時刻（epoch秒）
UNPUSHED_COUNT_CHECK_INTERVAL=120  # unpushedキャッシュ有効期間（秒）— 2分(git起動コスト削減)
CONTEXT_WARN_SIG_CACHE="missing"   # context_freshness_check.sh --dashboard-warningsキャッシュ値（毎サイクル→300s間隔に削減）
CONTEXT_WARN_SIG_CHECK_LAST=0      # context_warn_sigキャッシュ最終更新時刻（epoch秒）
CONTEXT_WARN_SIG_CHECK_INTERVAL=300  # context_warn_sigキャッシュ有効期間（秒）— 5分（CI_STATUS_CACHEと同様）
CONTEXT_WARN_SIG_TIMEOUT=${CONTEXT_WARN_SIG_TIMEOUT:-20}  # dashboard警告署名生成の上限秒数。詰まり時はsnapshot更新を優先する
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

check_disk_space_watch() {
    local measurement status available_kb warn_gb danger_gb mount_path free_gb message now
    local state_file="${DISK_WATCH_STATE_FILE:-$STATE_DIR/shogun_disk_space_watch.last}"
    local cooldown="${DISK_WATCH_NOTIFY_COOLDOWN_SEC:-1800}"
    measurement="$(disk_space_watch_measure 2>/dev/null || true)"
    IFS='|' read -r status available_kb warn_gb danger_gb mount_path <<< "$measurement"
    [[ "$status" = "WARN" || "$status" = "BLOCK" ]] || return 0
    free_gb="$(disk_space_watch_human_gb "$available_kb")"
    now=$EPOCHSECONDS
    local last_status="" last_epoch=0
    if [[ -f "$state_file" ]]; then
        read -r last_status last_epoch < "$state_file" || true
    fi
    if [[ "$status" = "$last_status" && "$last_epoch" =~ ^[0-9]+$ ]] && (( now - last_epoch < cooldown )); then
        return 0
    fi
    message="【disk残量${status}】${mount_path} free=${free_gb}GB (warn=${warn_gb}GB danger=${danger_gb}GB)。回収タスクを即時配備せよ。"
    if send_inbox_message karo "$message" disk_space_alert; then
        mkdir -p "$(dirname "$state_file")"
        printf '%s %s\n' "$status" "$now" > "$state_file"
        disk_space_watch_log_fire "$SCRIPT_DIR" "$status" "$message"
        log "DISK-SPACE-${status}: notified karo free=${free_gb}GB"
    fi
}

acquire_singleton_lock() {
    local pid_file="${STATE_DIR}/ninja_monitor.pid"
    local owner_file="${NINJA_MONITOR_OWNER_FILE:-${STATE_DIR}/ninja_monitor.owner}"
    local lock_file="${owner_file}.lock"
    local existing_pid="" existing_generation="" existing_heartbeat=""
    local now age tmp lock_fd

    mkdir -p "$(dirname "$owner_file")"
    exec {lock_fd}>"$lock_file"
    flock "$lock_fd"
    now=$EPOCHSECONDS

    if [ -f "$owner_file" ]; then
        read -r existing_pid existing_generation existing_heartbeat < "$owner_file" || true
    elif [ -f "$pid_file" ]; then
        existing_pid=$(cat "$pid_file" 2>/dev/null || true)
    fi

    age=$(( now - ${existing_heartbeat:-0} ))
    if _ninja_monitor_pid_is_live "$existing_pid" \
        && [[ "$existing_heartbeat" =~ ^[0-9]+$ ]] \
        && (( age <= ${NINJA_MONITOR_HEARTBEAT_STALE_SECONDS:-90} )); then
        log "SINGLETON-BLOCK: healthy owner pid=${existing_pid} generation=${existing_generation:-legacy} heartbeat_age=${age}s"
        flock -u "$lock_fd"
        eval "exec ${lock_fd}>&-"
        exit 0
    fi

    NINJA_MONITOR_GENERATION="${now}-$$-${RANDOM}"
    export NINJA_MONITOR_GENERATION
    tmp="${owner_file}.tmp.$$"
    printf '%s %s %s\n' "$$" "$NINJA_MONITOR_GENERATION" "$now" > "$tmp"
    mv "$tmp" "$owner_file"
    printf '%s\n' "$$" > "$pid_file"
    log "SINGLETON-TAKEOVER: old_pid=${existing_pid:-none} old_generation=${existing_generation:-none} heartbeat_age=${age}s new_generation=${NINJA_MONITOR_GENERATION}"
    flock -u "$lock_fd"
    eval "exec ${lock_fd}>&-"
    if [ "${NINJA_MONITOR_RELEASE_OWNER_ON_EXIT:-1}" = "1" ]; then
        trap 'ninja_monitor_release_owner' EXIT
    fi
}

ninja_monitor_release_owner() {
    local owner_file="${NINJA_MONITOR_OWNER_FILE:-${STATE_DIR}/ninja_monitor.owner}"
    local pid_file="${STATE_DIR}/ninja_monitor.pid"
    local pid="" generation="" heartbeat=""
    [ -f "$owner_file" ] || return 0
    read -r pid generation heartbeat < "$owner_file" || true
    if [ "$generation" = "${NINJA_MONITOR_GENERATION:-}" ]; then
        rm -f "$owner_file" "$pid_file"
    fi
}

ninja_monitor_owner_heartbeat() {
    local owner_file="${NINJA_MONITOR_OWNER_FILE:-${STATE_DIR}/ninja_monitor.owner}"
    local lock_file="${owner_file}.lock"
    local pid_file="${STATE_DIR}/ninja_monitor.pid"
    local pid="" generation="" heartbeat="" now tmp lock_fd
    exec {lock_fd}>"$lock_file"
    flock "$lock_fd"
    read -r pid generation heartbeat < "$owner_file" 2>/dev/null || true
    if [ "$generation" != "${NINJA_MONITOR_GENERATION:-}" ]; then
        log "SINGLETON-FENCE: generation ${NINJA_MONITOR_GENERATION:-missing} lost ownership to ${generation:-missing}"
        flock -u "$lock_fd"
        eval "exec ${lock_fd}>&-"
        return 1
    fi
    now=$EPOCHSECONDS
    tmp="${owner_file}.tmp.$$"
    printf '%s %s %s\n' "$$" "$generation" "$now" > "$tmp"
    mv "$tmp" "$owner_file"
    printf '%s\n' "$$" > "$pid_file"
    flock -u "$lock_fd"
    eval "exec ${lock_fd}>&-"
}

_ninja_monitor_pid_is_live() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    if [ -n "${NINJA_MONITOR_LIVENESS_OVERRIDE_PID:-}" ] \
        && [ "$pid" = "$NINJA_MONITOR_LIVENESS_OVERRIDE_PID" ]; then
        return 0
    fi
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

# shellcheck disable=SC2120  # Optional settings_file override is used by focused tests/manual probes.
get_max_clear_per_cmd() {
    local settings_file="${1:-$SCRIPT_DIR/config/settings.yaml}"
    local value=""

    if [ -f "$settings_file" ]; then
        value=$(awk '
            /^[^[:space:]#][^:]*:/ {
                in_token_budget = ($0 ~ /^token_budget:[[:space:]]*$/)
                next
            }
            in_token_budget && /^[[:space:]]+max_clear_per_cmd:[[:space:]]*/ {
                sub(/^[^:]*:[[:space:]]*/, "")
                gsub(/["'\''[:space:]]/, "")
                print
                exit
            }
        ' "$settings_file" 2>/dev/null || true)
    fi

    if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]; then
        echo "$value"
    else
        echo "3"
    fi
}

_clear_loop_state_file() {
    local agent_name="$1"
    mkdir -p "$STATE_DIR"
    printf '%s/shogun_clear_count_%s.tsv\n' "$STATE_DIR" "$agent_name"
}

_task_parent_cmd_for_clear_count() {
    local agent_name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${agent_name}.yaml"
    local parent_cmd=""
    local task_status=""

    if [ -f "$task_file" ]; then
        task_status=$(yaml_field_get "$task_file" "status" "")
        case "$task_status" in
            assigned|acknowledged|in_progress|pending)
                ;;
            *)
                log "CLEAR-COUNT-SKIP: $agent_name task_status=${task_status:-empty} is not active"
                printf '%s\n' "no_cmd"
                return 0
                ;;
        esac
        parent_cmd=$(yaml_field_get "$task_file" "parent_cmd" "")
        [ -n "$parent_cmd" ] || parent_cmd=$(yaml_field_get "$task_file" "task_id" "")
        [ -n "$parent_cmd" ] || parent_cmd=$(yaml_field_get "$task_file" "_ac_task_id" "")
    fi
    printf '%s\n' "${parent_cmd:-no_cmd}"
}

record_clear_attempt_or_force_idle() {
    local agent_name="$1"
    local reason="${2:-UNKNOWN}"
    local cmd_id="${3:-}"
    local max_clear
    local state_file count previous_cmd
    local task_file="$SCRIPT_DIR/queue/tasks/${agent_name}.yaml"

    [ -n "$cmd_id" ] || cmd_id=$(_task_parent_cmd_for_clear_count "$agent_name")
    if [ "$cmd_id" = "no_cmd" ]; then
        log "CLEAR-COUNT-SKIP: $agent_name has no cmd context, reason=$reason"
        return 0
    fi
    max_clear=$(get_max_clear_per_cmd)
    state_file=$(_clear_loop_state_file "$agent_name")

    if [ -f "$state_file" ]; then
        IFS=$'\t' read -r previous_cmd count < "$state_file" || true
    fi
    if [ "$previous_cmd" != "$cmd_id" ] || ! [[ "${count:-0}" =~ ^[0-9]+$ ]]; then
        count=0
    fi
    count=$((count + 1))
    printf '%s\t%s\n' "$cmd_id" "$count" > "$state_file"

    if [ "$count" -le "$max_clear" ]; then
        log "CLEAR-COUNT: $agent_name cmd=$cmd_id count=${count}/${max_clear} reason=$reason"
        return 0
    fi

    if [ -f "$task_file" ]; then
        yaml_field_set "$task_file" "task" "status" "idle" 2>/dev/null || true
    fi
    send_inbox_message karo "【CLEAR-LOOP-BLOCK】${agent_name} が同一cmd=${cmd_id}で /clear ${count}回。上限=${max_clear}超過のためtaskをidle化して空回りを停止。reason=${reason}" clear_loop_block
    log "CLEAR-LOOP-BLOCK: $agent_name cmd=$cmd_id count=${count}/${max_clear} forced_idle reason=$reason"
    return 1
}

build_pane_head_tail_excerpt() {
    local pane_target="$1"
    local capture line
    local -a first_lines=()
    local -a all_lines=()
    local -a tail_lines=()
    local line_count=0

    capture=$(tmux capture-pane -t "$pane_target" -p -J 2>/dev/null || true)
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        line_count=$((line_count + 1))
        if [ "$line_count" -le 5 ]; then
            first_lines+=("$line")
        fi
        # all_lines: ≤10行ケースで全行を保持（tail_linesは最後の5行のみのためL6-L10が欠落するバグ修正）
        if [ "$line_count" -le 10 ]; then
            all_lines+=("$line")
        fi
        tail_lines+=("$line")
        if [ "${#tail_lines[@]}" -gt 5 ]; then
            tail_lines=("${tail_lines[@]:1}")
        fi
    done <<< "$capture"

    [ "$line_count" -gt 0 ] || return 1
    if [ "$line_count" -le 10 ] 2>/dev/null; then
        printf '%s\n' "${all_lines[@]}"
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

auto_commit_normalize_scope_path() {
    local scope_path="$1"

    scope_path="${scope_path%%#*}"
    scope_path="${scope_path#"${scope_path%%[![:space:]]*}"}"
    scope_path="${scope_path%"${scope_path##*[![:space:]]}"}"
    scope_path="${scope_path#- }"
    scope_path="${scope_path#./}"
    case "$scope_path" in
        \"*\") scope_path="${scope_path#\"}"; scope_path="${scope_path%\"}" ;;
        \'*\') scope_path="${scope_path#\'}"; scope_path="${scope_path%\'}" ;;
    esac
    case "$scope_path" in
        ""|"none"|"null"|"FILL_THIS") return 0 ;;
        "$SCRIPT_DIR"/*) scope_path="${scope_path#"$SCRIPT_DIR"/}" ;;
        /*) return 0 ;;
    esac
    scope_path="${scope_path%/}"
    [ -n "$scope_path" ] && printf '%s\n' "$scope_path"
}

auto_commit_scope_paths_for_agent() {
    local agent_name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${agent_name}.yaml"
    local task_status raw_scope

    [ -f "$task_file" ] || return 0
    task_status="$(yaml_field_get "$task_file" "status" "" || true)"
    case "$task_status" in
        assigned|acknowledged|in_progress) ;;
        *)
            log "AUTO-COMMIT-STALE-SCOPE-SKIP: $agent_name task_status=${task_status:-missing}; target_path is not ownership evidence"
            return 0
            ;;
    esac
    raw_scope="$(yaml_field_get "$task_file" "target_path" "" || true)"
    [ -n "${raw_scope//[[:space:]]/}" ] || return 0
    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        auto_commit_normalize_scope_path "$raw_line"
    done <<< "$raw_scope"
}

auto_commit_path_in_scope() {
    local path="$1"
    local scope_path

    shift
    for scope_path in "$@"; do
        [ -n "$scope_path" ] || continue
        if [ "$path" = "$scope_path" ] || [[ "$path" == "$scope_path/"* ]]; then
            return 0
        fi
    done
    return 1
}

# target_pathなし忍者のauto-commitは運用ファイルのみ許可（default-closed）。
# scripts/config等のコード・設定は他エージェント作業中差分の巻き込みリスクがある
# ため明示commitに限定する（2026-06-10 saizo auto-commitが将軍編集中の
# scripts/cmd_save.sh等を巻き込んだ事故の再発防止）。
filter_operational_paths_only() {
    local agent_name="$1"
    local path
    while IFS= read -r path || [ -n "$path" ]; do
        [ -n "$path" ] || continue
        case "$path" in
            queue/*|logs/*|context/*|docs/*|projects/*|tasks/*|dashboard.md)
                printf '%s\n' "$path"
                ;;
            *)
                log "AUTO-COMMIT-OPERATIONAL-SKIP: $agent_name excluded $path (non-operational, no target_path)"
                ;;
        esac
    done
}

filter_auto_commit_paths_by_task_scope() {
    local agent_name="$1"
    local scope_text path
    local -a scope_paths=()

    scope_text="$(auto_commit_scope_paths_for_agent "$agent_name")"
    if [ -z "${scope_text//[[:space:]]/}" ]; then
        filter_operational_paths_only "$agent_name"
        return 0
    fi
    while IFS= read -r path || [ -n "$path" ]; do
        [ -n "$path" ] && scope_paths+=("$path")
    done <<< "$scope_text"
    while IFS= read -r path || [ -n "$path" ]; do
        [ -n "$path" ] || continue
        if auto_commit_path_in_scope "$path" "${scope_paths[@]}"; then
            printf '%s\n' "$path"
        else
            log "AUTO-COMMIT-SCOPE-SKIP: $agent_name excluded $path (outside target_path)"
        fi
    done
}

# cmd_3264: in_progress忍者のtarget_path配下ファイルをauto-commitから除外
# target_path空の忍者はINFO表示のみで除外しない（除外対象は明示的target_pathのみ）
filter_exclude_inprogress_ninja_paths() {
    local clearing_agent="$1"
    local -a excluded_paths=()
    local -a excluded_owners=()
    local ninja_name task_file task_status scope_text _p

    for ninja_name in "${NINJA_NAMES[@]}"; do
        [ "$ninja_name" = "$clearing_agent" ] && continue
        task_file="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"
        [ -f "$task_file" ] || continue
        task_status="$(yaml_field_get "$task_file" "status" "" || true)"
        case "$task_status" in
            assigned|acknowledged|in_progress) ;;
            *) continue ;;
        esac
        scope_text="$(auto_commit_scope_paths_for_agent "$ninja_name")"
        if [ -z "${scope_text//[[:space:]]/}" ]; then
            log "AUTO-COMMIT-INPROGRESS-INFO: $ninja_name is $task_status but has no target_path (not excluded)"
            continue
        fi
        while IFS= read -r _p || [ -n "$_p" ]; do
            if [ -n "$_p" ]; then
                excluded_paths+=("$_p")
                excluded_owners+=("$ninja_name")
            fi
        done <<< "$scope_text"
    done

    if [ ${#excluded_paths[@]} -eq 0 ]; then
        cat
        return 0
    fi

    local path i
    while IFS= read -r path || [ -n "$path" ]; do
        [ -n "$path" ] || continue
        local matched=false
        for i in "${!excluded_paths[@]}"; do
            if [ "$path" = "${excluded_paths[$i]}" ] || [[ "$path" == "${excluded_paths[$i]}/"* ]]; then
                log "AUTO-COMMIT-INPROGRESS-WARN: excluded $path (belongs to ${excluded_owners[$i]} scope, clearing_agent=$clearing_agent)"
                matched=true
                break
            fi
        done
        if [ "$matched" = "false" ]; then
            printf '%s\n' "$path"
        fi
    done
}

filter_regular_auto_commit_paths() {
    auto_commit_paths_from_status | grep -v -E '^context/[^/]*\.md$' || true
}

filter_context_batch_commit_paths() {
    auto_commit_paths_from_status | grep -E '^context/[^/]*\.md$' || true
}

# cmd_3284: scripts/gates/と.claude/hooks/を無条件除外（安全機構のbatch commit巻き込み防止）
# 裁可保留変更がbatch commitに混入し殿のGo-ahead前にpush到達する事故の再発防止。
# silent skip禁止: 除外発生時は必ずログへ可視化する。
filter_exclude_safety_mechanism_paths() {
    local agent_name="$1"
    local path
    while IFS= read -r path || [ -n "$path" ]; do
        [ -n "$path" ] || continue
        case "$path" in
            scripts/gates/*|.claude/hooks/*)
                log "AUTO-COMMIT-SAFETY-EXCLUDE: $agent_name excluded $path (safety mechanism file, unconditional)"
                ;;
            *)
                printf '%s\n' "$path"
                ;;
        esac
    done
}

auto_commit_before_clear() {
    local agent_name="$1"
    local uncommitted="$2"
    local regular_paths context_paths last_file context_last_file

    regular_paths="$(printf '%s\n' "$uncommitted" | filter_regular_auto_commit_paths | filter_auto_commit_paths_by_task_scope "$agent_name" | filter_exclude_inprogress_ninja_paths "$agent_name" | filter_exclude_safety_mechanism_paths "$agent_name")"
    context_paths="$(printf '%s\n' "$uncommitted" | filter_context_batch_commit_paths | filter_auto_commit_paths_by_task_scope "$agent_name" | filter_exclude_inprogress_ninja_paths "$agent_name" | filter_exclude_safety_mechanism_paths "$agent_name")"
    last_file="$(auto_commit_last_file)"
    context_last_file="$(context_batch_commit_last_file)"

    (
        cd "$SCRIPT_DIR" || exit

        local preexisting_staged_paths auto_commit_candidate_paths
        preexisting_staged_paths="$(git diff --cached --name-only 2>/dev/null || true)"
        auto_commit_candidate_paths="$(printf '%s\n%s\n' "$regular_paths" "$context_paths" | sed '/^[[:space:]]*$/d' | sort -u)"
        if [ -n "${preexisting_staged_paths//[[:space:]]/}" ]; then
            local staged_path candidate_path overlaps
            while IFS= read -r staged_path || [ -n "$staged_path" ]; do
                [ -n "$staged_path" ] || continue
                overlaps=false
                while IFS= read -r candidate_path || [ -n "$candidate_path" ]; do
                    [ -n "$candidate_path" ] || continue
                    if [ "$staged_path" = "$candidate_path" ] \
                        || [[ "$staged_path" == "$candidate_path/"* ]] \
                        || [[ "$candidate_path" == "$staged_path/"* ]]; then
                        overlaps=true
                        break
                    fi
                done <<< "$auto_commit_candidate_paths"

                if [ "$overlaps" = "true" ]; then
                    log "AUTO-COMMIT-WARN-SKIP: $agent_name pre-existing staged file overlaps auto-commit scope: $staged_path"
                    return 2
                fi
                log "AUTO-COMMIT-STAGED-PRESERVE: $agent_name preserving scope-out staged file: $staged_path"
            done <<< "$preexisting_staged_paths"
        fi

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

        return 0
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
declare -A STALE_CMD_NOTIFIED  # stale cmd通知済み世代 — key: "cmd_XXX", value: 状態fingerprint
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
declare -A ACTIVE_IDLE_RECOVERY_SENT # active task+idle時の忍者再通知済みフラグ — key: "ninja:task_id:reason", value: "1"

# cmd_karo_hotfix_completion_event_dedupe_20260723: durable report-gate cache.
# REPORT_GATE_SENT suppresses only the
# notification; this cache suppresses the repeated gate execution itself.
# The key binds report bytes, immutable task contract, and gate implementation.
# Mutable task status/timestamps are excluded, so report-only RC stays in its
# own report-fingerprint lane without manufacturing a task generation.
report_gate_generation_key() {
    local report_file="$1" task_file="$2"
    python3 - "$report_file" "$task_file" "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" <<'PY'
import hashlib
import json
import pathlib
import sys
import yaml

report_path, task_path, gate_path = map(pathlib.Path, sys.argv[1:])
task = (yaml.safe_load(task_path.read_text(encoding="utf-8")) or {}).get("task", {})
contract_keys = (
    "task_id", "parent_cmd", "ac_version", "deployed_at", "target_path",
    "planned_paths", "acceptance_criteria", "not_in_scope", "commit_contract",
)
contract = {key: task.get(key) for key in contract_keys}
digest = hashlib.sha256()
digest.update(report_path.read_bytes())
digest.update(json.dumps(contract, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode())
for gate_component in sorted(gate_path.parent.glob("gate_report_format*")):
    if gate_component.is_file():
        digest.update(gate_component.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(gate_component.read_bytes())
print(digest.hexdigest())
PY
}

report_gate_cached_outcome() {
    local name="$1" key="$2" state_file="${STATE_DIR:-/tmp}/report_gate_${name}.state"
    [ -f "$state_file" ] || return 1
    awk -F'\t' -v key="$key" '$1==key && ($2=="PASS" || $2=="FAIL") {print $2; exit}' "$state_file"
}

report_gate_record_outcome() {
    local name="$1" key="$2" outcome="$3" reason="$4"
    local state_file="${STATE_DIR:-/tmp}/report_gate_${name}.state" reason_hash tmp
    reason_hash=$(printf '%s' "$reason" | sha256sum | awk '{print $1}')
    mkdir -p "$(dirname "$state_file")"
    tmp="${state_file}.tmp.$$"
    {
        flock -x -w 5 200 || exit 1
        printf '%s\t%s\t%s\n' "$key" "$outcome" "$reason_hash" > "$tmp"
        mv "$tmp" "$state_file"
    } 200>"${state_file}.lock"
}

run_report_gate_deduped() {
    local name="$1" report_file="$2" task_file="$3"
    local generation cached outcome output
    generation=$(report_gate_generation_key "$report_file" "$task_file" 2>/dev/null || true)
    cached=""
    [ -n "$generation" ] && cached=$(report_gate_cached_outcome "$name" "$generation" 2>/dev/null || true)
    if [ "$cached" = "PASS" ] || [ "$cached" = "FAIL" ]; then
        log "REPORT-GATE-DEDUPE: $name outcome=$cached generation=$generation"
        printf '%s (durable report generation cache)\n' "$cached"
        [ "$cached" = "PASS" ]
        return
    fi

    output=$(bash "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$report_file" 2>&1) || true
    if echo "$output" | grep -q '^PASS'; then outcome=PASS; else outcome=FAIL; fi
    [ -n "$generation" ] && report_gate_record_outcome "$name" "$generation" "$outcome" "$output" || true
    printf '%s\n' "$output"
    [ "$outcome" = "PASS" ]
}
declare -A STALL_COUNT            # DEPLOY-STALL回数カウンター — key: "ninja:subtask_id", value: count
declare -A POST_CLEAR_PENDING     # /new後にpost_clear_cmd送信待ち — key: agent_name, value: epoch秒
declare -A REPORT_DONE_MISMATCH_NOTIFIED  # report done+status未idle通知時刻 — key: "ninja:cmd_id", value: epoch秒
declare -A IDLE_NOTIFY_SENT              # idle通知送信済み時刻 — key: agent_name, value: epoch秒（状態変化ベース+モード切替）
declare -A TRAINING_IDLE_FIRST_SEEN      # 修行自動配備: idle継続開始時刻 — key: agent_name, value: epoch秒
declare -A REFLUX_IDLE_FIRST_SEEN        # 還流在庫自動配備: idle継続開始時刻 — key: agent_name, value: epoch秒
declare -A TRAINING_EFFECT_RECORDED     # 修行効果記録済みフラグ — key: "ninja:task_id", value: "1" (cmd_2767)
declare -A TRAINING_COMPLETION_CHECKED  # 修行完了判定済みフラグ — key: "ninja:task_id", value: "1" (cmd_3230)
PREV_PANE_MISSING=""              # ペイン消失 — 前回の消失忍者リスト（重複送信防止）
declare -A _INBOX_COUNT_CACHE     # サイクル内inbox未読数キャッシュ — key: agent_name, value: count
declare -A _INBOX_FP_CACHE        # サイクル内inbox未読fingerprintキャッシュ — key: agent_name, value: md5 hash
_INBOX_COUNT_CACHE_CYCLE=-1       # キャッシュが有効なサイクル番号（cycleと一致する間は有効）
declare -A CLI_DEAD_RESTART_TIMES    # CLI死亡再起動時刻リスト — key: ninja_name, value: スペース区切りepoch秒リスト (cmd_1851)
declare -A CLI_DEAD_LOOP_LAST_NTFY   # CLI-DEAD-LOOP ntfy最終送信時刻 — key: ninja_name, value: epoch秒 (ntfy flood防止)

# 案A: PREV_STATE初期化（起動直後のidle→idle通知を防止）
for name in "${NINJA_NAMES[@]}"; do
    PREV_STATE[$name]="idle"
done

source "$SCRIPT_DIR/scripts/lib/inbox_nudge_policy.sh"
MAX_RENUDGE="$INBOX_RENUDGE_MAX_ATTEMPTS"
RENUDGE_BACKOFF="$INBOX_RENUDGE_BACKOFF_SEC"
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

    # マッピングを一括パース（N忍者分のecho|grep|awk→1回のread loop、18サブシェル排除）
    declare -A _pmap
    while IFS=' ' read -r _pt _aid; do
        [ -n "$_aid" ] && _pmap[$_aid]="$_pt"
    done <<< "$mapping"

    local found=0
    # L821: 全エージェント(家老+軍師+忍者)をPANE_TARGETSに登録。各論パッチ(個別check関数)不要
    local _all_discover=("shogun" "karo" "gunshi" "${NINJA_NAMES[@]}")
    for name in "${_all_discover[@]}"; do
        local _target="${_pmap[$name]:-}"
        if [ -n "$_target" ]; then
            PANE_TARGETS[$name]="shogun:${_target}"
            found=$((found + 1))
        fi
    done
    unset _pmap

    log "Pane discovery: ${found}/${#_all_discover[@]} agents found"
}

# ─── ペイン生存チェック (cmd_183) ───
# 期待される忍者ペインと実ペインを比較し、消失を検知して家老に通知
check_pane_survival() {
    local actual_agents
    local agents_window="${TMUX_WINDOW:-shogun:agents}"
    if ! actual_agents=$(tmux list-panes -t "$agents_window" -F '#{@agent_id}' 2>/dev/null) || [ -z "$actual_agents" ]; then
        log "PANE-CHECK: Failed to list panes for ${agents_window}"
        return
    fi

    local missing=()
    for name in "${NINJA_NAMES[@]}"; do
        # L324: echo|grep-qx→2 subshell。[[ ]]で純bash(0 subshell)に置換。$'\n'前後付与で行単位厳密マッチ
        if [[ $'\n'"$actual_agents"$'\n' != *$'\n'"$name"$'\n'* ]]; then
            missing+=("$name")
        fi
    done

    # LK009 enforcement: @agent_id重複検知+自動修復
    # 同一agent_idが複数paneに存在 = CLI再起動時の汚染
    local pane_mapping pane_base
    pane_mapping=$(tmux list-panes -t "$agents_window" -F '#{pane_index} #{@agent_id}' 2>/dev/null || true)
    pane_base=$(printf '%s\n' "$pane_mapping" | awk 'NR==1 || $1 < min { min=$1 } END { print min }')
    [[ "$pane_base" =~ ^[0-9]+$ ]] || pane_base=1

    local -A expected_pane  # agent_name → expected pane_index (from settings order, not current @agent_id)
    local -a expected_agents=()
    # get_all_agents() は監視用に shogun を含む (agent_config.sh L160) が、agents window に
    # shogun ペインは無い(将軍は shogun:main)。含めると expected_pane が +1 ずれ、
    # 正しい @agent_id を「衝突」と誤判定して破壊してしまう。shogun を除外し
    # karo=pane(base), gunshi=pane(base+1), ... の正準マッピング(pane_lookup.sh準拠)に揃える。
    local _em_agent
    for _em_agent in $(get_all_agents); do
        [ "$_em_agent" = "shogun" ] && continue
        expected_agents+=("$_em_agent")
    done
    local idx=0
    for name in "${expected_agents[@]}"; do
        expected_pane[$name]=$((pane_base + idx))
        idx=$((idx + 1))
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
                tmux set-option -t "${agents_window}.${pidx}" -p @agent_id "$correct_agent" 2>/dev/null || true
                tmux set-option -t "${agents_window}.${pidx}" -p @agent_state idle 2>/dev/null || true
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
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "ペイン消失: ${missing_str} (${#missing[@]}名)。OOM Kill等の可能性。tmux list-panes -t ${agents_window} で確認されたし" pane_lost ninja_monitor >> "$LOG" 2>&1
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
                    # check_agent_busy=unknownでも、busy markerが無くidle_patternがあればidle補正。
                    # busy-first原則を維持する。thinking中でもfooterにprompt記号が残るため、
                    # idle_pattern単独では誤clearにつながる。
                    local _stale_busy_pat _stale_idle_pat _stale_pane_tail
                    _stale_busy_pat=$(cli_profile_get "$agent_name" "busy_patterns" 2>/dev/null || echo "")
                    if [ -z "$_stale_busy_pat" ]; then
                        _stale_busy_pat="$AGENT_STATE_DEFAULT_BUSY_PATTERN"
                    else
                        _stale_busy_pat="${_stale_busy_pat}|${AGENT_STATE_DEFAULT_BUSY_PATTERN}"
                    fi
                    _stale_idle_pat=$(cli_profile_get "$agent_name" "idle_pattern" 2>/dev/null || echo "")
                    [ -z "$_stale_idle_pat" ] && _stale_idle_pat="❯|›"
                    _stale_pane_tail=$(tmux capture-pane -t "$pane_target" -p -S -30 2>/dev/null || true)
                    if [ -n "$_stale_pane_tail" ] && printf '%s\n' "$_stale_pane_tail" | grep -qiE "$_stale_busy_pat"; then
                        log "HOOK-STALE-UNKNOWN-BUSY: ${agent_name} @agent_state=${agent_state} stale+unknown, pane busy_pattern matched -> keep busy"
                        return 1
                    fi
                    if [ -n "$_stale_pane_tail" ] && printf '%s\n' "$_stale_pane_tail" | grep -qE "$_stale_idle_pat"; then
                        log "HOOK-STALE-IDLE-OVERRIDE: ${agent_name} @agent_state=${agent_state} stale+unknown, but pane idle_pattern matched -> idle"
                        tmux set-option -p -t "$pane_target" @agent_state idle 2>/dev/null || true
                        [ ! -f "${STATE_DIR}/shogun_idle_${agent_name}" ] && touch "${STATE_DIR}/shogun_idle_${agent_name}"
                        return 0
                    fi
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

# respawn-paneのexit 0はCLI起動成功を保証しない。paneにCLIのバナーまたは
# プロンプトが出るまで確認し、失敗時は有界に再試行する。
_pane_cli_is_ready() {
    local pane="$1" agent_name="$2" capture idle_pattern
    capture=$(tmux capture-pane -t "$pane" -p -J -S -100 2>/dev/null || true)
    [ -n "$capture" ] || return 1
    idle_pattern=$(cli_profile_get "$agent_name" "idle_pattern" 2>/dev/null || true)
    [ -n "$idle_pattern" ] || idle_pattern='❯|›'
    printf '%s\n' "$capture" | grep -qE "$idle_pattern|Claude Code|OpenAI Codex|Codex CLI"
}

_wait_for_cli_ready() {
    local pane="$1" agent_name="$2"
    local timeout_sec="${RESPAWN_CLI_VERIFY_TIMEOUT:-30}"
    local poll_sec="${RESPAWN_CLI_VERIFY_POLL_SEC:-1}"
    local elapsed=0
    while (( elapsed < timeout_sec )); do
        _pane_cli_is_ready "$pane" "$agent_name" && return 0
        sleep "$poll_sec"
        elapsed=$((elapsed + poll_sec))
    done
    _pane_cli_is_ready "$pane" "$agent_name"
}

_record_respawn_outcome() {
    local agent_name="$1" success="$2" attempts="$3" elapsed="$4"
    local state_file="${RESPAWN_METRICS_FILE:-$STATE_DIR/respawn_cli_metrics.tsv}"
    local lock_file="${state_file}.lock" total=0 successes=0 success_rate
    mkdir -p "$(dirname "$state_file")"
    exec 208>>"$lock_file"
    flock -w 5 208 || { log "RESPAWN-METRIC-ERROR: agent=$agent_name lock_busy"; return 1; }
    if [ -f "$state_file" ]; then
        read -r total successes < "$state_file" || true
    fi
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    [[ "$successes" =~ ^[0-9]+$ ]] || successes=0
    total=$((total + 1))
    successes=$((successes + success))
    printf '%s %s\n' "$total" "$successes" > "$state_file"
    success_rate=$((successes * 100 / total))
    flock -u 208
    log "RESPAWN-METRIC: agent=$agent_name success=$success attempts=$attempts retries=$((attempts - 1)) recovery_seconds=$elapsed cumulative_successes=$successes cumulative_total=$total success_rate_pct=$success_rate"
}

_respawn_with_cli_verification() {
    local pane="$1" agent_name="$2" launch_command="$3" label="$4"
    local attempt backoff elapsed
    local started=$SECONDS
    for attempt in 1 2 3; do
        log "${label}-ATTEMPT: $agent_name attempt=${attempt}/3"
        # tmux respawn-paneはscrollbackを継承する。前セッションのプロンプトを
        # 新CLIの起動成功と誤認しないよう、各試行の前に残像を消す。
        tmux clear-history -t "$pane" 2>/dev/null || true
        if tmux respawn-pane -k -t "$pane" "$launch_command" 2>/dev/null && \
                respawn_recovery_ready "$pane"; then
            elapsed=$((SECONDS - started))
            _record_respawn_outcome "$agent_name" 1 "$attempt" "$elapsed" || true
            return 0
        fi
        log "${label}-VERIFY-FAIL: $agent_name attempt=${attempt}/3 cli_not_ready"
        if [ "$attempt" -lt 3 ]; then
            if [ "$attempt" -eq 1 ]; then backoff="${RESPAWN_BACKOFF_FIRST_SEC:-5}"; else backoff="${RESPAWN_BACKOFF_SECOND_SEC:-15}"; fi
            log "${label}-BACKOFF: $agent_name seconds=$backoff next_attempt=$((attempt + 1))"
            sleep "$backoff"
        fi
    done
    elapsed=$((SECONDS - started))
    _record_respawn_outcome "$agent_name" 0 3 "$elapsed" || true
    log "${label}-STOP: $agent_name CLI unavailable after 3 attempts"
    return 1
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

    # cmd_2947: status=done is not enough to reset a ninja.  The report YAML
    # must exist first, otherwise auto-clear can erase the post-task reporting work.
    if ! can_send_clear_with_report_gate "$agent_name" "$reason"; then
        log "CLEAR-BLOCKED: $agent_name report gate blocked reset, reason=$reason"
        return 1
    fi

    if ! record_clear_attempt_or_force_idle "$agent_name" "$reason"; then
        return 1
    fi

    # AC3(cmd_karo_hotfix_failed_report_clear_notify_gap): failed taskのrespawnは止めないが、
    # 家老がまだ把握していない可能性がある報告なら、respawn結果を起点にdurable通知する。
    # 殿裁定(2026-07-12 08:43): 通知失敗でrespawnをBLOCKするな。BLOCKは別形態の放置を生む。
    local _fsc_notice_pending=0
    if _failed_task_needs_karo_notice "$agent_name"; then
        _fsc_notice_pending=1
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
        if ! auto_commit_before_clear "$agent_name" "$_uncommitted"; then
            log "CLEAR-BLOCKED: $agent_name auto-commit skipped because pre-existing staged files require preservation, reason=$reason"
            return 1
        fi
    fi

    # /clear前にinboxを既読化（/clear後のnudge再起動を防止）
    bash "$SCRIPT_DIR/scripts/inbox_mark_read.sh" "$agent_name" >> "$LOG" 2>&1 || true

    local clear_cmd
    clear_cmd=$(cli_profile_get "$agent_name" "clear_cmd")
    clear_cmd=${clear_cmd:-"/clear"}
    # LK012はrespawn-pane -kの起動コマンドでcd済み。事前cd送信はCLIにコマンド入力され
    # CTX消費+応答速度低下を招く(殿指摘2026-06-07)。Codex/Claudeともrespawnで対応。

    # Codex CLI: /newはCLI内部状態がtask in progressのまま残ると拒否される。
    # ninja_monitor側のtask statusに関係なく、respawn-pane -kでプロセスごと確実にリセットする。
    # PATH必須: codex shebang=#!/usr/bin/env node → nvm PATHなしでexit 127
    if [ "$(cli_type "$agent_name" 2>/dev/null || echo "claude")" = "codex" ]; then
        # pane_start_commandは二重クォート問題があるため使わない(hayate死亡事故2026-06-07)
        local _launch_cmd
        _launch_cmd=$(cli_launch_cmd "$agent_name" 2>/dev/null || echo "")
        if [ -n "${_launch_cmd:-}" ]; then
            local _launch_command
            _launch_command=$(respawn_recovery_launch_command "$SCRIPT_DIR" "$_launch_cmd" 2>/dev/null || true)
            # per-agent config.toml切替(2層SSOT: settings.yaml→config.toml。SSOT実装=cli_lookup.sh)
            codex_config_apply_agent "$agent_name" && \
                [[ "$_CODEX_CFG_CHANGED" == true ]] && \
                log "CODEX-CFG-SWITCH: $agent_name applied"
            log "CODEX-RESPAWN: $agent_name respawn-pane (codex reset)"
            local _fsc_respawn_ok=1
            [ -n "$_launch_command" ] && tmux respawn-pane -k -t "$pane" "$_launch_command" 2>/dev/null || {
                _fsc_respawn_ok=0
                log "CODEX-RESPAWN-FALLBACK: $agent_name respawn failed"
            }
            if [ "$_fsc_respawn_ok" -eq 1 ] && respawn_recovery_wait_ready "$pane"; then
                _generation=$(respawn_recovery_generation "$pane" 2>/dev/null || true)
                [ -n "$_generation" ] && respawn_recovery_notify "$SCRIPT_DIR" "$agent_name" "$_generation" clear-codex || _fsc_respawn_ok=0
            else
                _fsc_respawn_ok=0
            fi
            _notify_failed_respawn_result "$agent_name" "$_fsc_notice_pending" "$_fsc_respawn_ok"
            if [ "$_fsc_respawn_ok" -ne 1 ]; then
                log "CODEX-RESPAWN-VERIFY-FAIL: $agent_name ready handshake timed out; retry=next_cycle"
                return 1
            fi
            [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${agent_name}.yaml" "status")" = "failed" ] && \
                _mark_failed_task_respawn_completed "$agent_name"
            # respawn-pane -kはscrollback履歴を引き継ぐ(tmux仕様)。Androidアプリが前セッション残像を表示するためクリア(殿実測2026-07-08)
            tmux clear-history -t "$pane" 2>/dev/null || true
            tmux set-option -p -t "$pane" @context_pct "0%" 2>/dev/null || true
            log "CTX-RESET: $agent_name @context_pct → 0% after CODEX-RESPAWN"
            rm -f "${STATE_DIR}/shogun_idle_${agent_name}"
            return 0
        fi
        log "CODEX-RESPAWN-SKIP: $agent_name launch_cmd empty, using $clear_cmd"
    fi

    # Claude CLIもrespawn-pane -kで再起動する。
    # /clearではCLI内部のCTX%計算が前セッション値を維持しCTX 0%にならない(殿指摘2026-06-08)。
    # respawn-pane -kならCLIプロセス再起動でCTX確実に0%。数秒の起動遅延はCTX不正表示より軽微。
    # bypass permissionsはrespawn後もsettings.jsonのpermissions.allowが維持される(確認済み2026-06-07)。
    # gunshi D0 e2b5a4010で/clearに戻したのが根因。respawn-pane復帰(e9ae6839a)。
    local _launch_cmd
    _launch_cmd=$(cli_launch_cmd "$agent_name" 2>/dev/null || echo "")
    if [ -z "${_launch_cmd:-}" ]; then
        _launch_cmd="$HOME/bin/claude --effort high"
    fi
    local _launch_command
    _launch_command=$(respawn_recovery_launch_command "$SCRIPT_DIR" "$_launch_cmd" 2>/dev/null || true)
    log "RESPAWN-PANE: $agent_name respawn-pane -k (CTX確実0%復帰), reason=$reason"
    local _fsc_respawn_ok=1
    [ -n "$_launch_command" ] && tmux respawn-pane -k -t "$pane" "$_launch_command" 2>/dev/null || {
        _fsc_respawn_ok=0
        log "RESPAWN-FALLBACK: $agent_name respawn failed, trying /clear"
        safe_send_keys_atomic "$pane" "$clear_cmd" 0.3 || true
    }
    if [ "$_fsc_respawn_ok" -eq 1 ] && respawn_recovery_wait_ready "$pane"; then
        _generation=$(respawn_recovery_generation "$pane" 2>/dev/null || true)
        [ -n "$_generation" ] && respawn_recovery_notify "$SCRIPT_DIR" "$agent_name" "$_generation" clear-claude || _fsc_respawn_ok=0
    else
        _fsc_respawn_ok=0
    fi
    _notify_failed_respawn_result "$agent_name" "$_fsc_notice_pending" "$_fsc_respawn_ok"
    if [ "$_fsc_respawn_ok" -ne 1 ]; then
        log "RESPAWN-VERIFY-FAIL: $agent_name ready handshake timed out; retry=next_cycle"
        return 1
    fi
    [ "$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${agent_name}.yaml" "status")" = "failed" ] && \
        _mark_failed_task_respawn_completed "$agent_name"
    # respawn-pane -kはscrollback履歴を引き継ぐ(tmux仕様)。Androidアプリが前セッション残像を表示するためクリア(殿実測2026-07-08)
    tmux clear-history -t "$pane" 2>/dev/null || true
    tmux set-option -p -t "$pane" @context_pct "0%" 2>/dev/null || true
    log "CTX-RESET: $agent_name @context_pct → 0% after respawn-pane"
    rm -f "${STATE_DIR}/shogun_idle_${agent_name}"
    return 0
}

# ─── CTX%取得ヘルパー: tmuxキャッシュ書き込み+echo ───
# get_context_pct()内で重複していた3行パターンを1箇所に集約
_ctx_pct_emit() {
    local pane_target="$1" ctx_num="$2"
    tmux set-option -p -t "$pane_target" @context_pct "${ctx_num}%" 2>/dev/null
    echo "$ctx_num"
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
    if [[ "$ctx_val" =~ ([0-9]+) ]]; then
        ctx_num="${BASH_REMATCH[1]}"
    else
        ctx_num=""
    fi
    # @context_pctが非0なら信頼する。0%はrespawn直後の正値でもあるが、
    # CLI種別乖離時に stale 0% として残るため capture-pane で再検出する。
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
                _ctx_pct_emit "$pane_target" "$ctx_num"; return
            fi
        elif [ "$ctx_mode" = "remaining" ]; then
            # remaining モード（例: "XX% context left"）— usage%に変換
            local remaining
            remaining=$(echo "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
            if [ -n "$remaining" ]; then
                ctx_num=$((100 - remaining))
                _ctx_pct_emit "$pane_target" "$ctx_num"; return
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
                    _ctx_pct_emit "$pane_target" "$ctx_num"; return
                fi
            fi
        fi
    fi

    # フォールバック: プロファイルなし or ctx_patternマッチ失敗時
    # CLI type設定と実態の乖離でctx_patternが合わない場合に全パターンを試す
    if [ -z "$ctx_num" ]; then
        ctx_num=$(echo "$output" | grep -oE 'CTX:[0-9]+%' | tail -1 | grep -oE '[0-9]+')
        if [ -n "$ctx_num" ]; then
            _ctx_pct_emit "$pane_target" "$ctx_num"; return
        fi
    fi
    if [ -z "$ctx_num" ]; then
        ctx_num=$(echo "$output" | grep -oE 'Context [0-9]+% used' | tail -1 | grep -oE '[0-9]+')
        if [ -n "$ctx_num" ]; then
            _ctx_pct_emit "$pane_target" "$ctx_num"; return
        fi
    fi
    if [ -z "$ctx_num" ]; then
        local remaining
        remaining=$(echo "$output" | grep -oE '[0-9]+% context left' | tail -1 | grep -oE '[0-9]+')
        if [ -n "$remaining" ]; then
            ctx_num=$((100 - remaining))
            _ctx_pct_emit "$pane_target" "$ctx_num"; return
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

    IFS='|' read -r task_parent_cmd task_id < <(awk '
        BEGIN { pc=""; ti=""; ai="" }
        /^[ \t]*parent_cmd:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); pc=v }
        /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && ti=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ti=v }
        /^[ \t]*_ac_task_id:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ai=v }
        END { print pc "|" (ti!=""?ti:ai) }
    ' "$task_file")
    [ -z "$task_parent_cmd" ] && return 1

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

        IFS='|' read -r report_parent_cmd report_task_id < <(awk '
            BEGIN { pc=""; ti="" }
            /^[ \t]*parent_cmd:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); pc=v }
            /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && ti=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ti=v }
            END { print pc "|" ti }
        ' "$report_file")
        [ -z "$report_parent_cmd" ] && continue
        [ "$report_parent_cmd" != "$task_parent_cmd" ] && continue

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
    # Reservation mutates the shared ledger before deploy_task runs.  Gate on
    # the worker's primary task state first so a busy/failed worker can never
    # create a false assignment that later requires reconciliation.
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
        if ! report_file_has_verdict "$name" "$report_path" "$trigger"; then
            return 1
        fi
        if ! report_notification_completed "$name" "$report_path" "$trigger"; then
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
            local matched_report
            matched_report=$(compgen -G "${dir}/${pattern}" | head -1 || true)
            if [ -n "$matched_report" ]; then
                if ! report_file_has_verdict "$name" "$matched_report" "$trigger"; then
                    return 1
                fi
                if ! report_notification_completed "$name" "$matched_report" "$trigger"; then
                    return 1
                fi
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

report_notification_completed() {
    local name="$1"
    local report_file="$2"
    local trigger="$3"
    local report_epoch
    local report_timestamp
    local -a inbox_sources archive_sources

    report_timestamp=$(yaml_field_get "$report_file" "timestamp" "" 2>/dev/null || true)
    if [ -n "$report_timestamp" ]; then
        report_epoch=$(python3 - "$report_timestamp" <<'PY' 2>/dev/null || true
import datetime as dt
import sys

text = sys.argv[1].strip()
try:
    value = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
except ValueError:
    raise SystemExit(1)
if value.tzinfo is None:
    value = value.replace(tzinfo=dt.datetime.now().astimezone().tzinfo)
print(int(value.timestamp()))
PY
        )
    else
        report_epoch=""
    fi
    # Report timestamps are mutable during review/revision.  An exact-identity
    # report_received can legitimately predate the final report rewrite, so the
    # immutable deployment generation is the acceptance boundary.  This also
    # rejects notifications from a previous deployment.
    local task_deployed_at deployed_epoch
    task_deployed_at=$(yaml_field_get "$SCRIPT_DIR/queue/tasks/${name}.yaml" "deployed_at" "" 2>/dev/null || true)
    deployed_epoch=$(_ninja_monitor_timestamp_epoch "$task_deployed_at") || deployed_epoch=""
    if [[ "$deployed_epoch" =~ ^[0-9]+$ ]]; then
        report_epoch="$deployed_epoch"
    elif ! [[ "$report_epoch" =~ ^[0-9]+$ ]]; then
        report_epoch=0
    fi
    inbox_sources=("$SCRIPT_DIR/queue/inbox/karo.yaml")

    shopt -s nullglob
    archive_sources=("$SCRIPT_DIR/archive/inbox/karo_"*.yaml)
    shopt -u nullglob
    inbox_sources+=("${archive_sources[@]}")

    local report_identity task_identity parent_identity
    report_identity=$(basename "$report_file")
    task_identity=$(yaml_field_get "$report_file" "task_id" "" 2>/dev/null || true)
    parent_identity=$(yaml_field_get "$report_file" "parent_cmd" "" 2>/dev/null || true)

    # shellcheck source=scripts/lib/report_completion_events.sh
    source "$SCRIPT_DIR/scripts/lib/report_completion_events.sh"
    local completion_event_types
    completion_event_types="$REPORT_COMPLETION_EVENT_TYPES"

    if python3 - "$name" "$report_epoch" "$SCRIPT_DIR/data/multi_agent_shogun_memory.db" \
        "$completion_event_types" \
        "$report_identity" "$task_identity" "$parent_identity" "${inbox_sources[@]}" <<'PY'
import datetime as _dt
import os
import re
import sqlite3
import sys

import yaml

name = sys.argv[1]
try:
    report_epoch = int(float(sys.argv[2]))
except Exception:
    report_epoch = 0
memory_db = sys.argv[3]
completion_types = frozenset(sys.argv[4].split())
identities = tuple(value for value in sys.argv[5:8] if value)
sources = sys.argv[8:]


def _has_exact_identity(msg):
    # report_received content predates structured identity fields, so accept
    # either an explicit field or a token-delimited identity in its content.
    haystack = "\n".join(str(msg.get(key, "")) for key in
                          ("report", "report_path", "report_filename",
                           "task_id", "parent_cmd", "content"))
    return any(re.search(r"(?<![A-Za-z0-9_])" + re.escape(identity) +
                         r"(?![A-Za-z0-9_])", haystack)
               for identity in identities)


def _timestamp_epoch(value):
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        dt = _dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=_dt.datetime.now().astimezone().tzinfo)
    return int(dt.timestamp())


for source in sources:
    if not source or not os.path.isfile(source):
        continue
    try:
        with open(source, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    except Exception:
        continue
    messages = data.get("messages") if isinstance(data, dict) else None
    if not isinstance(messages, list):
        continue
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        msg_type = str(msg.get("type", ""))
        sender = str(msg.get("from", ""))
        direct_completion = msg_type in completion_types and sender == name
        reviewed_completion = (
            msg_type == "report_review_result"
            and sender == "gunshi"
            and re.search(r"\bLGTM\b", str(msg.get("content", "")), re.I)
        )
        if not (direct_completion or reviewed_completion):
            continue
        if not _has_exact_identity(msg):
            continue
        msg_epoch = _timestamp_epoch(msg.get("timestamp"))
        if msg_epoch is None:
            continue
        # inbox_write persists the notification after ninja_done validates the
        # report. Allow a small filesystem timestamp skew on WSL2/NTFS.
        if report_epoch == 0 or msg_epoch >= report_epoch - 10:
            sys.exit(0)

# The inbox is the hot queue, not the only durable evidence.  Older versions
# of inbox_prune discarded read entries without archiving them; inbox_write's
# append-only memory event lets the clear gate recover from that history gap.
if os.path.isfile(memory_db):
    try:
        conn = sqlite3.connect(f"file:{memory_db}?mode=ro", uri=True)
        rows = conn.execute(
            """SELECT ts, detail, raw_content FROM events
               WHERE event_type = 'inbox' AND agent = ? AND target = 'karo'
               ORDER BY ts DESC""",
            (name,),
        )
        for ts, detail, raw_content in rows:
            evidence = f"{detail or ''}\n{raw_content or ''}"
            if not any(f"type: {event_type}" in evidence for event_type in completion_types):
                continue
            if not any(re.search(r"(?<![A-Za-z0-9_])" + re.escape(identity) +
                                 r"(?![A-Za-z0-9_])", evidence)
                       for identity in identities):
                continue
            msg_epoch = _timestamp_epoch(ts)
            if msg_epoch is not None and (report_epoch == 0 or msg_epoch >= report_epoch - 10):
                sys.exit(0)
    except (OSError, sqlite3.Error):
        pass
    finally:
        try:
            conn.close()
        except Exception:
            pass

sys.exit(1)
PY
    then
        run_test_speed_completion_callback "$name" "$report_file" || return 1
        return 0
    fi

    log "REPORT-NOTIFY-MISSING-BLOCK: $name report exists and verdict is valid but karo report_received notification is missing (${trigger}, report=$(basename "$report_file"))"
    notify_karo_throttled report_notification_missing "$name" "【自動検知】${name}の報告YAMLは存在するが家老へのreport_received通知が未確認。/clear保留中。対象: $(basename "$report_file")"
    return 1
}

# A completed speed-campaign report advances itself. Only the fixed in-repo
# runner/action pair is accepted; task YAML cannot inject an arbitrary command.
run_test_speed_completion_callback() {
    local name="$1" report_file="$2" task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local enabled
    enabled=$(python3 - "$task_file" <<'PY' 2>/dev/null || true
import sys, yaml
d=(yaml.safe_load(open(sys.argv[1])) or {}).get('task', {})
c=d.get('completion_callback') or {}
if c.get('runner') == 'scripts/test_speed_task_generator.sh' and c.get('action') == 'complete-deploy':
    print('yes')
PY
)
    [ "$enabled" = yes ] || return 0
    if ! bash "$SCRIPT_DIR/scripts/test_speed_task_generator.sh" complete-deploy "$name" "$task_file" "$report_file" >> "$LOG" 2>&1; then
        log "SPEED-CAMPAIGN-CALLBACK-BLOCK: $name report=$(basename "$report_file")"
        return 1
    fi
    log "SPEED-CAMPAIGN-CALLBACK: $name report=$(basename "$report_file")"
}

# 同一(type,ninja)の自動検知通知をクールダウン付きで送る。
# verdict未記入等は解消まで毎pollで再検知されるため、抑制なしでは
# 家老inboxに毎分同一通知が積まれる(2026-06-10 kagemaru長時間処理中に実測)。
# /clear保留(return 1)は維持し、通知だけを間引く。
notify_karo_throttled() {
    local notify_type="$1"
    local name="$2"
    local message="$3"
    local stamp_file="${STATE_DIR:-/tmp}/.notify_${notify_type}_${name}"
    local cooldown="${NINJA_MONITOR_NOTIFY_COOLDOWN:-1800}"
    local fingerprint acknowledged_at prior_fp prior_ack prior_epoch now
    if [ "$notify_type" = "completion_notify_gap" ]; then
        # name carries cmd + immutable LGTM epoch for this notification type.
        # Exclude mutable grace wording so repeated monitor cycles dedupe.
        fingerprint=$(printf '%s\t%s' "$notify_type" "$name" | cksum | awk '{print $1 ":" $2}')
    else
        fingerprint=$(printf '%s\t%s\t%s' "$notify_type" "$name" "$message" | cksum | awk '{print $1 ":" $2}')
    fi
    acknowledged_at=""
    if [ -f "$SCRIPT_DIR/queue/tasks/${name}.yaml" ]; then
        acknowledged_at=$(awk '/^[[:space:]]*acknowledged_at:/{sub(/^[^:]*:[[:space:]]*/,""); gsub(/"/,""); print; exit}' "$SCRIPT_DIR/queue/tasks/${name}.yaml" 2>/dev/null || true)
    fi
    now=$EPOCHSECONDS

    # A report identity is immutable, so this notification is an event rather
    # than a recurring condition.  The generic cooldown below intentionally
    # re-alerts unresolved conditions, but doing that here recreated the same
    # report_notification_missing every 30 minutes after Karo had read it.
    # Consult durable delivery evidence before the process-local stamp: inbox
    # archival, agent scan order, and monitor restarts must not create another
    # notification for the same report identity.
    if [ "$notify_type" = "report_notification_missing" ]; then
        local -a notify_sources
        notify_sources=("$SCRIPT_DIR/queue/inbox/karo.yaml")
        shopt -s nullglob
        notify_sources+=("$SCRIPT_DIR/archive/inbox/karo_"*.yaml)
        shopt -u nullglob
        if python3 - "$message" "$SCRIPT_DIR/data/multi_agent_shogun_memory.db" "${notify_sources[@]}" <<'PY'
import os
import sqlite3
import sys

import yaml

message, memory_db, *sources = sys.argv[1:]
for source in sources:
    if not os.path.isfile(source):
        continue
    try:
        data = yaml.safe_load(open(source, encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        continue
    for item in data.get("messages", []) if isinstance(data, dict) else ():
        if (isinstance(item, dict)
                and item.get("type") == "report_notification_missing"
                and item.get("from") == "ninja_monitor"
                and item.get("content") == message):
            raise SystemExit(0)

if os.path.isfile(memory_db):
    try:
        conn = sqlite3.connect(f"file:{memory_db}?mode=ro", uri=True)
        rows = conn.execute(
            """SELECT detail, raw_content FROM events
               WHERE event_type = 'inbox' AND agent = 'ninja_monitor'
                 AND target = 'karo'
               ORDER BY ts DESC""")
        for detail, raw_content in rows:
            evidence = f"{detail or ''}\n{raw_content or ''}"
            if ("type: report_notification_missing" in evidence
                    and message in evidence):
                raise SystemExit(0)
    except (OSError, sqlite3.Error):
        pass
    finally:
        try:
            conn.close()
        except Exception:
            pass
raise SystemExit(1)
PY
        then
            log "NOTIFY-EXACTLY-ONCE: $notify_type for $name suppressed durable identity"
            return 0
        fi
    fi

    if [ -f "$stamp_file" ]; then
        IFS='|' read -r prior_fp prior_ack prior_epoch < "$stamp_file" || true
        if [ "$prior_fp" = "$fingerprint" ] && [ "$prior_ack" = "$acknowledged_at" ] &&
           [[ "$prior_epoch" =~ ^[0-9]+$ ]] && [ $((now - prior_epoch)) -lt "$cooldown" ]; then
            log "NOTIFY-THROTTLED: $notify_type for $name suppressed fingerprint=$fingerprint acknowledged_at=${acknowledged_at:-none}"
            return 0
        fi
    fi
    if ! bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" "$notify_type" ninja_monitor >> "$LOG" 2>&1; then
        log "WARN: inbox_write $notify_type failed for $name"
        return 0
    fi
    # Use a non-whitespace delimiter: read collapses adjacent tab IFS fields,
    # which shifted an empty acknowledged_at into prior_ack and broke dedupe.
    printf '%s|%s|%s\n' "$fingerprint" "$acknowledged_at" "$now" > "$stamp_file"
}

# ─── karo通知の永続retry outbox (cmd_karo_hotfix_failed_report_clear_notify_gap AC3) ───
# 殿裁定(2026-07-12 08:43): 通知失敗でrespawnをBLOCKするな。BLOCKは別形態の放置を生む。
# 正しい不変量: auto-respawn実行結果を起点に必ずdurable通知を生成し、配送(inbox_write)自体が
# 失敗した場合のみoutboxへ永続化して次サイクルでretryする。paneを止めて代替放置を作らない。
_karo_notify_outbox_file() {
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    printf '%s/karo_notify_outbox.tsv\n' "$STATE_DIR"
}

# karoへdurable通知を試行する。inbox_write成功なら即完了、失敗ならoutboxへ永続化して次サイクルで再送する。
# 呼び出し元(safe_send_clear等)はこの関数の戻り値でrespawn等の処理を止めてはならない。
# 契約(cmd_karo_hotfix_pending_work_generation_dedupe_202607121023で明確化): direct送達成功
# またはoutboxへの永続化成功のいずれかならreturn 0(=通知は将来必ず届く見込みが確定した状態)。
# outbox永続化自体(printf >> outbox_file)が失敗した場合のみreturn 1とし、呼び出し元が
# 世代markerを確定させず次サイクルでretryできるようにする。
notify_karo_durable() {
    local notify_type="$1"
    local name="$2"
    local message="$3"

    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" "$notify_type" ninja_monitor >> "$LOG" 2>&1; then
        return 0
    fi
    log "NOTIFY-OUTBOX-ENQUEUE: $notify_type for $name (inbox_write failed, queued for retry)"
    local outbox_file encoded
    outbox_file=$(_karo_notify_outbox_file)
    encoded=$(printf '%s' "$message" | base64 | tr -d '\n')
    if printf '%s\t%s\t%s\t%s\n' "$EPOCHSECONDS" "$notify_type" "$name" "$encoded" >> "$outbox_file" 2>/dev/null; then
        return 0
    fi
    log "NOTIFY-OUTBOX-ENQUEUE-FAILED: $notify_type for $name (outbox永続化自体が失敗。呼び出し元は世代を確定せず次サイクルでretryせよ)"
    return 1
}

# outbox flushをmain loop各サイクルで呼ぶ。送達成功分は除去し、失敗分だけ次サイクルへ持ち越す。
flush_karo_notify_outbox() {
    local outbox_file
    outbox_file=$(_karo_notify_outbox_file)
    [ -s "$outbox_file" ] || return 0

    local tmp_remaining
    tmp_remaining="${outbox_file}.retry.$$"
    : > "$tmp_remaining"
    local pending=0
    while IFS=$'\t' read -r ts notify_type name encoded; do
        [ -n "$notify_type" ] || continue
        local message
        message=$(printf '%s' "$encoded" | base64 -d 2>/dev/null)
        if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" "$notify_type" ninja_monitor >> "$LOG" 2>&1; then
            log "NOTIFY-OUTBOX-FLUSHED: $notify_type for $name (queued at ${ts})"
        else
            printf '%s\t%s\t%s\t%s\n' "$ts" "$notify_type" "$name" "$encoded" >> "$tmp_remaining"
            pending=$((pending + 1))
        fi
    done < "$outbox_file"
    mv "$tmp_remaining" "$outbox_file"
    [ "$pending" -gt 0 ] && log "NOTIFY-OUTBOX-PENDING: ${pending} message(s) still queued for retry"
    return 0
}

# ─── failed task respawn前後のkaro通知要否判定 (cmd_karo_hotfix_failed_report_clear_notify_gap AC3) ───
# task status=failedのninjaについて、家老がまだ把握していない可能性がある報告かを判定する。
# check_inbox_renudgeのKARO-PENDING抑止基準(GATE CLEAR済み/軍師review済み/parent_cmdなし)と
# 同じ基準を、respawn単発呼び出し向けに単独判定できる形で複製する(バッチ最適化とは別経路)。
_failed_task_needs_karo_notice() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    [ -f "$task_file" ] || return 1

    local task_status parent_cmd
    task_status=$(yaml_field_get "$task_file" "status")
    [ "$task_status" = "failed" ] || return 1

    parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
    if [ -z "$parent_cmd" ] || [ "$parent_cmd" = "none" ]; then
        return 1
    fi

    # GATE CLEAR済み(archived)なら通知不要
    if compgen -G "$SCRIPT_DIR/queue/archive/cmds/${parent_cmd}_completed_"* > /dev/null 2>&1; then
        return 1
    fi
    # GATE CLEAR済み(gate_metrics.log)なら通知不要
    if awk -F '\t' -v cmd="$parent_cmd" '$2 == cmd && $3 == "CLEAR" { found=1; exit } END { exit(found ? 0 : 1) }' "$SCRIPT_DIR/logs/gate_metrics.log" 2>/dev/null; then
        return 1
    fi
    # Durable report_received means karo has already accepted this exact task
    # generation into its workflow, even if gunshi_review_log is not written
    # yet or a replacement Track is already being deployed. Do not emit a late
    # failed_task_respawned false positive for work already acknowledged.
    local failed_task_id failed_deployed_at
    failed_task_id=$(yaml_field_get "$task_file" "task_id")
    failed_deployed_at=$(yaml_field_get "$task_file" "deployed_at")
    # Use the same completion-event contract as inbox acceptance and the clear
    # gate; a valid alias is durable acknowledgement of this task generation.
    # shellcheck source=scripts/lib/report_completion_events.sh
    source "$SCRIPT_DIR/scripts/lib/report_completion_events.sh"
    if python3 - "$name" "$parent_cmd" "$failed_task_id" "$failed_deployed_at" \
        "$REPORT_COMPLETION_EVENT_TYPES" \
        "$SCRIPT_DIR/queue/inbox/karo.yaml" "$SCRIPT_DIR/archive/inbox" <<'PY' 2>/dev/null
import datetime as dt, glob, os, re, sys, yaml
name, parent, task, deployed, completion_event_types, hot, archive = sys.argv[1:]
completion_types=set(completion_event_types.split())
def epoch(v):
    try:
        x=dt.datetime.fromisoformat(str(v).replace('Z','+00:00'))
        if x.tzinfo is None: x=x.replace(tzinfo=dt.datetime.now().astimezone().tzinfo)
        return x.timestamp()
    except Exception: return 0
boundary=epoch(deployed)
ids=[x for x in (parent, task) if x]
for path in [hot, *glob.glob(os.path.join(archive, 'karo_*.yaml'))]:
    try: msgs=(yaml.safe_load(open(path, encoding='utf-8')) or {}).get('messages', [])
    except Exception: continue
    for msg in msgs if isinstance(msgs, list) else []:
        if not isinstance(msg, dict) or msg.get('type') not in completion_types or msg.get('from') != name: continue
        text='\n'.join(str(msg.get(k,'')) for k in ('content','task_id','parent_cmd','report','report_path'))
        if not any(re.search(r'(?<![A-Za-z0-9_])'+re.escape(x)+r'(?![A-Za-z0-9_])', text) for x in ids): continue
        if epoch(msg.get('timestamp')) >= boundary - 10: raise SystemExit(0)
raise SystemExit(1)
PY
    then
        return 1
    fi
    # 軍師review済みなら通知不要
    if [ -f "$SCRIPT_DIR/logs/gunshi_review_log.yaml" ]; then
        local reviewed
        reviewed=$(awk '
            function emit() {
                if (cmd != "" && review_type == "report" && verdict != "") print cmd
            }
            /^[[:space:]]*-[[:space:]]*cmd_id:/ {
                emit()
                cmd=$0; sub(/^[^:]*:[[:space:]]*/, "", cmd); gsub(/["'\''[:space:]]/, "", cmd)
                review_type=""; verdict=""
                next
            }
            /^[[:space:]]*review_type:/ {
                review_type=$0; sub(/^[^:]*:[[:space:]]*/, "", review_type); gsub(/["'\''[:space:]]/, "", review_type)
                next
            }
            /^[[:space:]]*verdict:/ {
                verdict=$0; sub(/^[^:]*:[[:space:]]*/, "", verdict); gsub(/["'\''[:space:]]/, "", verdict)
                next
            }
            END { emit() }
        ' "$SCRIPT_DIR/logs/gunshi_review_log.yaml" 2>/dev/null | grep -qxF "$parent_cmd" && echo yes)
        [ "$reviewed" = "yes" ] && return 1
    fi

    return 0
}

# ─── failed respawn通知のdurable dedupe (karo実運転RC 2026-07-12 09:04) ───
# 同一failed世代(=task_id+parent_cmd+deployed_atが不変の間)がidle+failedのまま繰り返し
# respawnされ続けると、修正直後は同一通知が毎サイクル複数回karoへ届いていた(exactly-once不変量違反)。
# 世代fingerprint+outcome種別(success/failure)単位でmarker fileに記録し、同一世代・同一outcomeの
# 再通知を抑制する。再配備で世代(deployed_at等)が変われば新規通知として扱う。
_failed_respawn_notice_marker_file() {
    local agent_name="$1"
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    printf '%s/failed_respawn_notice_%s.tsv\n' "$STATE_DIR" "$agent_name"
}

_failed_respawn_generation_fingerprint() {
    local agent_name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${agent_name}.yaml"
    local task_id parent_cmd deployed_at
    task_id=$(yaml_field_get "$task_file" "task_id")
    parent_cmd=$(yaml_field_get "$task_file" "parent_cmd")
    deployed_at=$(yaml_field_get "$task_file" "deployed_at")
    printf '%s|%s|%s' "$task_id" "$parent_cmd" "$deployed_at" | md5sum | cut -d' ' -f1
}

_failed_respawn_completed_marker_file() {
    local agent_name="$1"
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    printf '%s/failed_respawn_completed_%s.fp\n' "$STATE_DIR" "$agent_name"
}

# 同じfailed task世代を一度正常にrespawnした後は、次周期以降に再度kill/respawnしない。
# 旧世代との移行中は既存notice markerのsuccessも完了証跡として認める。
_failed_task_respawn_completed() {
    local agent_name="$1"
    local current_fp marker_file stored_fp notice_file notice_fp notice_outcomes
    current_fp=$(_failed_respawn_generation_fingerprint "$agent_name")
    marker_file=$(_failed_respawn_completed_marker_file "$agent_name")
    stored_fp=""
    [ -f "$marker_file" ] && read -r stored_fp < "$marker_file" || true
    [ "$stored_fp" = "$current_fp" ] && return 0

    notice_file=$(_failed_respawn_notice_marker_file "$agent_name")
    notice_fp=""
    notice_outcomes=""
    [ -f "$notice_file" ] && IFS=$'\t' read -r notice_fp notice_outcomes < "$notice_file" || true
    [ "$notice_fp" = "$current_fp" ] && [[ ",$notice_outcomes," == *,success,* ]]
}

_mark_failed_task_respawn_completed() {
    local agent_name="$1" marker_file current_fp
    marker_file=$(_failed_respawn_completed_marker_file "$agent_name")
    current_fp=$(_failed_respawn_generation_fingerprint "$agent_name")
    printf '%s\n' "$current_fp" > "$marker_file"
}

# 既に同一世代+同一outcomeで通知済みならtrue(0)。未通知なら記録してfalse(1)を返す
# (呼び出し側はfalse時のみ通知処理を続ける)。
_failed_respawn_already_notified() {
    local agent_name="$1"
    local outcome="$2"
    local marker_file current_fp stored_fp stored_outcomes

    marker_file=$(_failed_respawn_notice_marker_file "$agent_name")
    current_fp=$(_failed_respawn_generation_fingerprint "$agent_name")

    stored_fp=""
    stored_outcomes=""
    if [ -f "$marker_file" ]; then
        IFS=$'\t' read -r stored_fp stored_outcomes < "$marker_file" || true
    fi

    if [ "$stored_fp" = "$current_fp" ]; then
        case ",${stored_outcomes}," in
            *",${outcome},"*)
                return 0
                ;;
        esac
        stored_outcomes="${stored_outcomes:+${stored_outcomes},}${outcome}"
    else
        stored_fp="$current_fp"
        stored_outcomes="$outcome"
    fi

    printf '%s\t%s\n' "$stored_fp" "$stored_outcomes" > "$marker_file"
    return 1
}

# failed taskのrespawn結果をkaroへdurable通知する。notice_pending=0(対象外)なら何もしない。
# respawnは既にsafe_send_clear側で実行済み/実行放棄済みであり、この関数は結果通知のみを行う。
_notify_failed_respawn_result() {
    local agent_name="$1"
    local notice_pending="$2"
    local respawn_ok="$3"
    local outcome

    [ "$notice_pending" -eq 1 ] || return 0

    if [ "$respawn_ok" -eq 1 ]; then
        outcome="success"
    else
        outcome="failure"
    fi

    if _failed_respawn_already_notified "$agent_name" "$outcome"; then
        log "FAILED-RESPAWN-NOTICE-DEDUPE: $agent_name outcome=$outcome already notified for this generation, skipping"
        return 0
    fi

    if [ "$outcome" = "success" ]; then
        notify_karo_durable failed_task_respawned "$agent_name" \
            "【自動検知】${agent_name}のfailedタスクをrespawn(clear)した。報告は未完了/未レビューの可能性あり。queue/tasks/${agent_name}.yamlと対応reportを確認し、レビュー/完了処理を判断せよ。"
    else
        notify_karo_durable failed_task_respawn_failed "$agent_name" \
            "【自動検知】${agent_name}のrespawnが失敗した。pane状態を確認し手動対応せよ。"
    fi
}

# ─── pending_work通知のdurable世代dedupe (cmd_karo_hotfix_pending_work_generation_dedupe_202607121023) ───
# 実運転RC: 家老inbox未読0でも忍者done/failed報告が残っている間、旧実装は120秒スロットルのみで
# 抑止しており、同一pending集合(worker+task_id+parent_cmd+status+report内容が全て不変)が続く限り
# 2分周期で同一通知が再送され続けていた(通知世代の非永続・集合fingerprint未使用が根因)。
# 上のfailed respawn通知dedupeと同構造で、pending集合全体のcanonical世代fingerprintをdurable
# markerに記録し、fingerprint不変の間は再通知しない。集合変化・report内容変化で新世代になれば
# 即時再通知する。
# AC3順序(判定関数は副作用なしの比較のみ。確定は呼び出し元がnotify_karo_durableの成功
# (=direct成功またはoutbox永続化成功、戻り値0)を確認した後にのみ行う。呼び出し元が
# notify_karo_durable呼び出し前にmarkerを書くと、direct失敗+outbox永続化失敗(プロセス
# クラッシュ等)の場合に通知が永久に失われたまま抑止され続けるため、この順序を厳守する。
# pathの組立のみ(副作用なし)。mkdir等の副作用は各write系関数(mark_notified)が個別に持つ。
_karo_pending_work_notice_marker_file() {
    printf '%s/karo_pending_work_notice.tsv\n' "$STATE_DIR"
}

# 空集合になるまでの通知済み世代を最大64件保持する。単一の「直前世代」だけでは
# A→A+B→Aの振動でAを忘れ、同じAを再通知するため、行単位のbounded setにする。
KARO_PENDING_WORK_SEEN_MAX=64

# 判定のみ(副作用なし)。同一世代で通知確定済みならtrue(0)、未確定ならfalse(1)。
_karo_pending_work_already_notified() {
    local current_fp="$1"
    local marker_file stored_fp

    marker_file=$(_karo_pending_work_notice_marker_file)
    # 速度RC(2026-07-12): cat(外部プロセス)ではなくbuiltin readでmarker内容を読む
    [ -f "$marker_file" ] || return 1
    while IFS= read -r stored_fp; do
        [ "$stored_fp" = "$current_fp" ] && return 0
    done < "$marker_file"
    return 1
}

# notify_karo_durableがreturn 0(direct成功またはoutbox永続化成功)した後にのみ呼ぶこと。
# atomic tmp+mvでmarkerを確定する(生リダイレクトによる部分書込み・クラッシュ時破損を避ける)。
# 最終RC(2026-07-12): mkdir副作用はwrite系のここだけに限定し、_already_notifiedを純比較にする。
_karo_pending_work_mark_notified() {
    local current_fp="$1"
    local marker_file tmp_file stored_fp
    local -a seen_fps=()

    [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR" 2>/dev/null || true
    marker_file=$(_karo_pending_work_notice_marker_file)
    tmp_file="${marker_file}.tmp.$$"
    if [ -f "$marker_file" ]; then
        while IFS= read -r stored_fp; do
            [ -n "$stored_fp" ] && seen_fps+=("$stored_fp")
        done < "$marker_file"
    fi
    seen_fps+=("$current_fp")
    local start=0
    [ "${#seen_fps[@]}" -gt "$KARO_PENDING_WORK_SEEN_MAX" ] && start=$((${#seen_fps[@]} - KARO_PENDING_WORK_SEEN_MAX))
    printf '%s\n' "${seen_fps[@]:start}" > "$tmp_file" && mv -f "$tmp_file" "$marker_file"
}

# 集合世代RC(cmd_karo_hotfix_pending_work_generation_dedupe_202607121023): pending集合が
# 0件になった時にmarkerを残すと、後で同一fingerprintの集合が再出現(軍師review/GATE CLEARで
# 一度解消した後にRC/reopenする実運用)しても旧世代扱いされ通知が漏れる。0件も「集合変化」
# として扱い、pending entriesが空になった時点でmarkerをatomicに消去する。
# 最終RC(2026-07-12): STATE_DIR不存在ならclear対象自体が存在し得ないためmkdirせず即return。
_karo_pending_work_clear_marker() {
    [ -d "$STATE_DIR" ] || return 0
    local marker_file
    marker_file=$(_karo_pending_work_notice_marker_file)
    rm -f "$marker_file" 2>/dev/null || true
}

# ─── 軍師LGTM後の家老未通知検知 (cmd_karo_hotfix_completion_notify_gap) ───
# review_approval.shが正式LGTM時に家老へ自動通知する。本チェックはそのフェイルセーフが
# 機能しない異常経路を検知するバックストップ。自然言語の「報告レビュー」固定文面に依存せず、
# LGTMイベントより前の進捗通知を完了通知と誤認しない。
# cmd_3780実例(2026-07-08): LGTM 22:53:35受領→家老が23:05頃rgで確認するまでbulletin/
# shogun inboxに完了通知ゼロ。殿の質問で家老が気づき手動投稿するまで自動通知は皆無だった。
# draft review(配備前レビュー)は対象外。猶予時間内の正常な処理待ちは誤検知しない。
check_karo_completion_notify_gap() {
    local inbox_karo="$SCRIPT_DIR/queue/inbox/karo.yaml"
    local bulletin_file="$SCRIPT_DIR/queue/bulletin_board.yaml"
    local inbox_shogun="$SCRIPT_DIR/queue/inbox/shogun.yaml"
    local reports_dir="$SCRIPT_DIR/queue/reports"
    local tasks_dir="$SCRIPT_DIR/queue/tasks"
    local gates_dir="$SCRIPT_DIR/queue/gates"
    local grace="${NINJA_MONITOR_LGTM_NOTIFY_GRACE:-300}"

    [ -f "$inbox_karo" ] || return 0

    local pending
    pending=$(python3 - "$inbox_karo" "$bulletin_file" "$inbox_shogun" "$reports_dir" "$tasks_dir" "$gates_dir" "$grace" "$EPOCHSECONDS" <<'PY'
import datetime as dt
import glob
import hashlib
import os
import re
import sys

import yaml

karo_inbox, bulletin_file, shogun_inbox, reports_dir, tasks_dir, gates_dir, grace_s, now_s = sys.argv[1:9]
grace = int(grace_s)
now = int(now_s)


def load_yaml(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return yaml.safe_load(fh) or {}
    except Exception:
        return {}


def epoch(value):
    if not value:
        return None
    text = str(value).strip()
    try:
        parsed = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.datetime.now().astimezone().tzinfo)
    return int(parsed.timestamp())


def dedup_key(cmd_id):
    m = re.match(r'^(cmd_karo_hotfix_ga\d+)(_.+)?$', cmd_id)
    if m:
        return m.group(1)
    m = re.match(r'^(.+)_\d{12,14}$', cmd_id)
    if m:
        return m.group(1)
    return cmd_id


def readonly_child_parent(cmd_id):
    """Return the integrating parent encoded by a read-only child cmd id."""
    match = re.match(r'^(.+?)_(?:[A-Za-z0-9]+_)?(?:recon|scout)\d*$', cmd_id, re.I)
    return dedup_key(match.group(1)) if match else None


karo_data = load_yaml(karo_inbox)
messages = karo_data.get("messages") if isinstance(karo_data, dict) else None
if not isinstance(messages, list):
    sys.exit(0)

lgtm_events = []
reopen_events = []
terminal_events = []
current_report_cmds = set()
readonly_child_reports = set()
readonly_child_report_cmds = set()
# cmd_complete_gate.trigger.log and archive.done are durable evidence that the
# completion gate reached its terminal CLEAR branch.  A later /cmd-complete can
# overwrite the trigger log with "Already CLEARED", so archive.done must also
# participate.  Timestamp ordering keeps an older marker from suppressing a
# later RC -> new LGTM generation.
for gate_dir in glob.glob(os.path.join(gates_dir, "cmd_*")):
    trigger_log = os.path.join(gate_dir, "cmd_complete_gate.trigger.log")
    try:
        with open(trigger_log, "r", encoding="utf-8", errors="replace") as fh:
            terminal_clear = any(
                re.match(r'^GATE CLEAR(?: \(緊急override\))?:', line)
                for line in fh
            )
        if terminal_clear:
            terminal_events.append((dedup_key(os.path.basename(gate_dir)), int(os.path.getmtime(trigger_log))))
    except OSError:
        pass
    archive_marker = os.path.join(gate_dir, "archive.done")
    try:
        terminal_events.append((dedup_key(os.path.basename(gate_dir)), int(os.path.getmtime(archive_marker))))
    except OSError:
        pass
# Formal approvals count only while bound to the current report generation.
# A matching gunshi_notice.sent is the durable transition proving that this
# approved generation was already delivered to Shogun.  Treat that generation
# as terminal regardless of PASS/FAIL; a later RC followed by a new LGTM has a
# newer event timestamp and therefore remains detectable.
for report_path in glob.glob(os.path.join(reports_dir, "*.yaml")):
    report = load_yaml(report_path)
    cmd_id = str(report.get("parent_cmd") or "") if isinstance(report, dict) else ""
    if cmd_id:
        current_report_cmds.add(dedup_key(cmd_id))
        if str(report.get("task_type") or "").lower() in {"recon", "scout"}:
            readonly_child_report_cmds.add(dedup_key(cmd_id))
        if (
            dedup_key(cmd_id) in readonly_child_report_cmds
            and str(report.get("status") or "") == "completed"
            and str(report.get("verdict") or "") in {"PASS", "PASS_NO_IMPROVEMENT"}
        ):
            readonly_child_reports.add(dedup_key(cmd_id))
    commit_id = str(report.get("commit_hash") or report.get("commit") or report.get("git_commit") or "") if isinstance(report, dict) else ""
    if not cmd_id or len(commit_id) != 40:
        continue
    root = os.path.dirname(os.path.dirname(reports_dir))
    rel = os.path.relpath(report_path, root)
    key = hashlib.sha256(rel.encode()).hexdigest()
    approval = load_yaml(os.path.join(gates_dir, cmd_id, "review_approvals", "reports", key, "gunshi.yaml"))
    current_fp = hashlib.sha256(open(report_path, "rb").read()).hexdigest() + ":" + commit_id
    if approval.get("result") == "LGTM" and str(approval.get("fingerprint") or "") == current_fp:
        ts = epoch(approval.get("timestamp"))
        if ts is not None:
            lgtm_events.append((cmd_id, ts))
            notice_marker = os.path.join(
                gates_dir, cmd_id, "review_approvals", "reports", key, "gunshi_notice.sent"
            )
            try:
                terminal_events.append((dedup_key(cmd_id), int(os.path.getmtime(notice_marker))))
            except OSError:
                pass
for msg in messages:
    if not isinstance(msg, dict):
        continue
    if str(msg.get("type", "")) != "review_feedback":
        continue
    content = str(msg.get("content", ""))
    if "draft review" in content.lower():
        continue
    m = re.match(r'^(cmd_[A-Za-z0-9_]+)', content)
    if not m:
        continue
    ts = epoch(msg.get("timestamp"))
    if ts is None:
        continue
    if re.search(r'verdict[:=]\s*(LGTM|APPROVE|PASS)', content, re.I) and (
        dedup_key(m.group(1)) not in current_report_cmds
        or dedup_key(m.group(1)) in readonly_child_report_cmds
    ):
        lgtm_events.append((m.group(1), ts))
    elif re.search(r'verdict[:=]\s*(RC|REJECT|REVISION_REQUESTED)', content, re.I):
        reopen_events.append((dedup_key(m.group(1)), ts))

if not lgtm_events:
    sys.exit(0)

notifications = []
completion_words = re.compile(r'(完了|LGTM|GATE\s*CLEAR|レビュー)', re.I)
# The Karo bulletin_notify below is the current delivery contract.  Historical
# bulletin/Shogun completion evidence remains a terminal compatibility signal:
# its presence may suppress a duplicate, but its absence is never an error.
bulletin_data = load_yaml(bulletin_file)
bulletin_entries = bulletin_data.get("entries") if isinstance(bulletin_data, dict) else None
for entry in (bulletin_entries or []):
    if not isinstance(entry, dict):
        continue
    content = str(entry.get("content", ""))
    notice_ts = epoch(entry.get("posted_at") or entry.get("timestamp"))
    if notice_ts is not None and completion_words.search(content):
        for m in re.finditer(r'(cmd_[A-Za-z0-9_]+)', content):
            notifications.append((dedup_key(m.group(1)), notice_ts))

shogun_data = load_yaml(shogun_inbox)
shogun_messages = shogun_data.get("messages") if isinstance(shogun_data, dict) else None
for msg in (shogun_messages or []):
    if not isinstance(msg, dict):
        continue
    content = str(msg.get("content", ""))
    notice_ts = epoch(msg.get("timestamp"))
    if notice_ts is None or not completion_words.search(content):
        continue
    for m in re.finditer(r'(cmd_[A-Za-z0-9_]+)', content):
        notifications.append((dedup_key(m.group(1)), notice_ts))

for msg in messages:
    if not isinstance(msg, dict):
        continue
    if str(msg.get("type", "")) != "bulletin_notify":
        continue
    content = str(msg.get("content", ""))
    notice_ts = epoch(msg.get("timestamp"))
    if notice_ts is None or not completion_words.search(content):
        continue
    for m in re.finditer(r'(cmd_[A-Za-z0-9_]+)', content):
        notifications.append((dedup_key(m.group(1)), notice_ts))

# LGTM後に家老RC、report差戻し、task再開が起きたcmdは「完了待ち」ではない。
# 各状態の時刻を比較し、古いRCが後続LGTMを抑制しないようにする。
for path in glob.glob(os.path.join(reports_dir, "*.yaml")):
    report = load_yaml(path)
    if not isinstance(report, dict) or str(report.get("status", "")) != "revision_requested":
        continue
    cmd_id = str(report.get("parent_cmd") or report.get("task_id") or "")
    ts = epoch(report.get("timestamp") or report.get("updated_at"))
    if cmd_id and ts is not None:
        reopen_events.append((dedup_key(cmd_id), ts))

active_states = {"assigned", "acknowledged", "in_progress"}
for path in glob.glob(os.path.join(tasks_dir, "*.yaml")):
    data = load_yaml(path)
    task = data.get("task") if isinstance(data, dict) else None
    if not isinstance(task, dict) or str(task.get("status", "")) not in active_states:
        continue
    cmd_id = str(task.get("parent_cmd") or task.get("task_id") or "")
    ts = epoch(task.get("deployed_at") or task.get("updated_at") or task.get("timestamp"))
    if cmd_id and ts is not None:
        reopen_events.append((dedup_key(cmd_id), ts))

for cmd_id, ts in lgtm_events:
    event_key = dedup_key(cmd_id)
    # A read-only recon/scout is evidence for its integrating parent, not an
    # independently completable command.  Suppress only when the child report
    # is terminal PASS and the parent's durable CLEAR happened after this
    # child's LGTM.  Missing/uncleared parents and FAIL reports stay visible.
    child_parent = readonly_child_parent(cmd_id)
    if event_key in readonly_child_reports and child_parent is not None:
        parent_clear_ts = max(
            (clear_ts for key, clear_ts in terminal_events if key == child_parent),
            default=None,
        )
        if parent_clear_ts is not None and parent_clear_ts >= ts:
            continue
    terminal_ts = max(
        (clear_ts for key, clear_ts in terminal_events if key == event_key),
        default=None,
    )
    if terminal_ts is not None:
        # A command is not reopened merely because the same completed report
        # receives a later duplicate LGTM.  Reopening requires primary state:
        # an RC/revision or an active task created after the terminal marker.
        # Without this guard, archived reports disappear from reports_dir and
        # a delayed duplicate review_feedback recreates a permanent false gap.
        explicitly_reopened = any(
            key == event_key and terminal_ts < reopen_ts <= ts
            for key, reopen_ts in reopen_events
        )
        if not explicitly_reopened:
            continue
    if any(key == event_key and reopen_ts >= ts for key, reopen_ts in reopen_events):
        continue
    if any(key == event_key and notice_ts >= ts for key, notice_ts in notifications):
        continue
    if now - ts < grace:
        continue
    # Carry the immutable LGTM event timestamp into the throttle identity.
    # The human-facing message contains mutable grace wording, while a later
    # RC -> LGTM is a distinct generation that must notify exactly once.
    print(f"{cmd_id}\t{int(ts)}")
PY
)

    [ -z "$pending" ] && return 0

    local cmd_id lgtm_generation
    while IFS=$'\t' read -r cmd_id lgtm_generation; do
        [ -z "$cmd_id" ] && continue
        log "KARO-COMPLETION-NOTIFY-GAP: LGTM received for ${cmd_id} but no Karo bulletin receipt within ${grace}s"
        notify_karo_throttled completion_notify_gap "${cmd_id}_${lgtm_generation}" "【自動検知】軍師LGTM(${cmd_id})受領後${grace}秒超過しても家老inboxにbulletin_notifyなし。cmd_complete_gate実行またはreview_approval.shの家老通知を確認せよ。"
    done <<< "$pending"
}

report_file_has_verdict() {
    local name="$1"
    local report_file="$2"
    local trigger="$3"
    local verdict report_status

    verdict=$(yaml_field_get "$report_file" "verdict")
    report_status=$(yaml_field_get "$report_file" "status" "" 2>/dev/null || true)
    case "$verdict" in
        PASS|FAIL|PASS_NO_IMPROVEMENT)
            return 0
            ;;
        "")
            if [ "$report_status" = "pending" ]; then
                log "REPORT-PENDING-BLOCK: $name report is still template/pending (${trigger}, report=$(basename "$report_file"))"
                if [ "$trigger" != "STAGE1-TIMEOUT" ]; then
                    notify_karo_throttled report_pending "$name" "【自動検知】${name}の報告YAMLがpendingのまま。/clear保留中。対象: $(basename "$report_file")"
                fi
                return 1
            fi
            log "VERDICT-EMPTY-BLOCK: $name report exists but verdict empty (${trigger}, report=$(basename "$report_file"))"
            notify_karo_throttled verdict_empty "$name" "【自動検知】${name}の報告にverdictが未記入。/clear保留中。対象: $(basename "$report_file")"
            return 1
            ;;
        *)
            log "VERDICT-INVALID-BLOCK: $name report verdict invalid (${trigger}, verdict=${verdict}, report=$(basename "$report_file"))"
            notify_karo_throttled verdict_invalid "$name" "【自動検知】${name}の報告verdictが不正値(${verdict})。/clear保留中。対象: $(basename "$report_file")"
            return 1
            ;;
    esac
}

find_completed_parent_cmd_report_for_other_ninja() {
    local name="$1"
    local parent_cmd="$2"
    local task_id="${3:-}"
    local dir report_file report_parent_cmd report_status report_worker base
    local report_task_id

    [ -n "$parent_cmd" ] || return 1

    for dir in "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/archive/reports"; do
        [ -d "$dir" ] || continue
        for report_file in "$dir"/*_report_*.yaml "$dir"/*_report.yaml; do
            [ -f "$report_file" ] || continue
            base=$(basename "$report_file")
            case "$base" in
                "${name}_report_"*.yaml|"${name}_report.yaml") continue ;;
            esac

            report_parent_cmd=$(yaml_field_get "$report_file" "parent_cmd")
            [ "$report_parent_cmd" = "$parent_cmd" ] || continue

            report_task_id=$(yaml_field_get "$report_file" "task_id")
            if [ -n "$task_id" ] && [ -n "$report_task_id" ] && [ "$task_id" != "$report_task_id" ]; then
                continue
            fi

            report_status=$(yaml_field_get "$report_file" "status")
            case "$report_status" in
                done|completed|success) ;;
                *) continue ;;
            esac

            report_worker=$(yaml_field_get "$report_file" "worker_id")
            [ "$report_worker" = "$name" ] && continue

            echo "$report_file"
            return 0
        done
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
    IFS='|' read -r task_status parent_cmd task_id < <(awk '
        BEGIN { s=""; pc=""; ti=""; sti=""; ai="" }
        /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && ti=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ti=v }
        /^[ \t]*subtask_id:/ && sti=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); sti=v }
        /^[ \t]*_ac_task_id:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ai=v }
        /^[ \t]*status:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); s=v }
        /^[ \t]*parent_cmd:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); pc=v }
        END { print s "|" pc "|" (sti!=""?sti:(ti!=""?ti:ai)) }
    ' "$task_file")
    case "$task_status" in
        assigned|acknowledged|in_progress|pending) ;;
        *) return 1 ;;
    esac
    [ -n "$parent_cmd" ] || return 1

    completed_report=$(find_completed_parent_cmd_report_for_other_ninja "$name" "$parent_cmd" "$task_id") || return 1
    completed_base=$(basename "$completed_report")

    local lock_file="${STATE_DIR:-/tmp}/task_${name}.lock"
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
        still_completed_report=$(find_completed_parent_cmd_report_for_other_ninja "$name" "$parent_cmd" "$task_id") || { log "AUTO-VOID-SKIP: completed report disappeared for $name parent_cmd=$parent_cmd task_id=$task_id"; exit 1; }

        if ! yaml_field_set "$task_file" "task" "status" "idle"; then
            log "ERROR: yaml_field_set failed for ${name} auto-void status update"
            exit 1
        fi
        yaml_field_set "$task_file" "task" "report_path" "" 2>/dev/null || true
        yaml_field_set "$task_file" "task" "report_filename" "" 2>/dev/null || true
        # Completed parent_cmd/tasks must not remain report-wait targets for the next cmd.
        awk '
            /^[[:space:]]+parent_cmd:[[:space:]]*/ { next }
            /^[[:space:]]+task_id:[[:space:]]*/ { next }
            { print }
        ' "$task_file" > "${task_file}.tmp.$$" && mv "${task_file}.tmp.$$" "$task_file"
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

# YAML timestamp文字列をepoch秒に変換する。無効/空ならreturn 1(何も出力しない)。
# report_notification_completed内の日時変換ロジックと同一パターン。
_ninja_monitor_timestamp_epoch() {
    local text="$1"
    [ -z "$text" ] && return 1
    python3 - "$text" <<'PY' 2>/dev/null
import datetime as dt
import sys

text = sys.argv[1].strip()
try:
    value = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
except ValueError:
    raise SystemExit(1)
if value.tzinfo is None:
    value = value.replace(tzinfo=dt.datetime.now().astimezone().tzinfo)
print(int(value.timestamp()))
PY
}

# Report lifecycle state used by both AUTO-DONE and STALL detection.
# A completed PASS can still be legitimately waiting for post-deploy evidence;
# that is forward progress, not a pending report or an idle worker stall.
report_monitor_state() {
    local report_file="$1"
    [ -f "$report_file" ] || { printf 'missing\n'; return 1; }
    awk '
        BEGIN { status=""; verdict=""; in_post=0; required="false"; completed="false" }
        /^status:[[:space:]]*/ && status=="" { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["[:space:]]|\047/,"",v); status=tolower(v) }
        /^verdict:[[:space:]]*/ && verdict=="" { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["[:space:]]|\047/,"",v); verdict=toupper(v) }
        /^post_deploy_evidence:[[:space:]]*$/ { in_post=1; next }
        in_post && /^[^[:space:]#][^:]*:/ { in_post=0 }
        in_post && /^[[:space:]]+required:[[:space:]]*/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["[:space:]]|\047/,"",v); required=tolower(v) }
        in_post && /^[[:space:]]+run_completed:[[:space:]]*/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["[:space:]]|\047/,"",v); completed=tolower(v) }
        END {
            terminal = (status=="done" || status=="completed" || status=="success")
            req = (required=="true" || required=="yes" || required=="1")
            ran = (completed=="true" || completed=="yes" || completed=="1")
            if (terminal && verdict=="PASS" && req && !ran) print "awaiting_evidence"
            else if (terminal && verdict=="PASS") print "pass_terminal"
            else print "report_pending"
        }
    ' "$report_file"
}

# ─── AC1: 報告YAML完了判定 + タスクYAML自動done更新 ───
# 報告YAMLのparent_cmdがタスクと一致し、status=doneなら自動更新
# 戻り値: 0=完了済み(auto-done実行), 1=未完了
check_and_update_done_task() (
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local report_file=""
    local deploy_lock_dir="$SCRIPT_DIR/queue/locks"
    local deploy_lock_file="$deploy_lock_dir/deploy_ninja_${name}.lock"
    local deploy_lock_fd
    mkdir -p "$deploy_lock_dir"
    exec {deploy_lock_fd}>"$deploy_lock_file"
    if ! flock -n "$deploy_lock_fd"; then
        log "AUTO-DONE-SKIP-DEPLOY-LOCK-BUSY: $name retry=next-cycle"
        return 1
    fi
    # awk単一パスでtask_fileから必要フィールドを一括取得
    # (check_stall/auto_void_if_parent_cmd_completedと同パターン: サブシェル3回削減)
    local task_parent_cmd task_status task_id
    IFS='|' read -r task_parent_cmd task_status task_id < <(awk '
        BEGIN { pc=""; s=""; ti=""; ai="" }
        /^[ \t]*parent_cmd:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); pc=v }
        /^[ \t]*status:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); s=v }
        /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && ti=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ti=v }
        /^[ \t]*_ac_task_id:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); ai=v }
        END { print pc "|" s "|" (ti!=""?ti:ai) }
    ' "$task_file")
    [ -z "$task_parent_cmd" ] && return 1
    # 新形式({ninja}_report_{cmd}.yaml)優先で一致報告を探索。旧形式も許容。
    report_file=$(find_matching_report_file "$name") || return 1
    if [ -L "$report_file" ]; then
        log "AUTO-DONE-SKIP-ARCHIVE-SYMLINK: $name report=$(basename "$report_file")"
        return 1
    fi

    # 報告のparent_cmdを取得
    local report_parent_cmd report_task_id
    report_parent_cmd=$(yaml_field_get "$report_file" "parent_cmd")
    [ -z "$report_parent_cmd" ] && return 1

    # parent_cmd一致チェック
    [ "$task_parent_cmd" != "$report_parent_cmd" ] && return 1

    # task_id一致チェック（同一cmd内のWave間誤マッチ防止）
    report_task_id=$(yaml_field_get "$report_file" "task_id")
    [ -n "$task_id" ] && [ -n "$report_task_id" ] && [ "$task_id" != "$report_task_id" ] && return 1

    # cmd_1262の重複AUTO-DONE防止はdone taskを報告探索前にreturnしていたため、
    # 忍者が先にdoneへ更新する正常経路でpromotion ledger writerが一度も起動しなかった。
    # parent_cmd/task_id一致を確認後に冪等writerのみ実行し、状態更新は引き続き省略する。
    if [ "$task_status" = "done" ]; then
        _reflux_promotion_record_completion_detached "$report_file" || \
            log "REFLUX-LEDGER-BLOCK: failed to detach done task report $(basename "$report_file")"
        # The task/report lifecycle is already terminal.  Publish that state
        # with the single-agent atomic writer.  A full snapshot scans every
        # report/pane and previously stalled this fast path for minutes.
        refresh_karo_snapshot_task_assignment "$name"
        return 0
    fi

    # cmd_karo_hotfix_report_notify_inprogress_guard: 再配備(deployed_at)より前のreportは
    # 前回試行の残骸。in_progress再開後にまだ新しい報告が届いていないだけなのに、
    # 旧いcompleted報告を見てAUTO-DONEしてしまうとreport_notification_missingが偽陽性化する。
    # deployed_at以降のreportのみ「今回の完了」とみなす（deployed_at欠落時は従来どおり）。
    local task_deployed_at retry_deployed_at
    task_deployed_at=$(yaml_field_get "$task_file" "deployed_at" "" 2>/dev/null || true)
    retry_deployed_at=$(yaml_field_get "$task_file" "retry_deployed_at" "" 2>/dev/null || true)
    if [ -n "$retry_deployed_at" ]; then
        task_deployed_at="$retry_deployed_at"
    fi
    if [ -n "$task_deployed_at" ]; then
        local report_timestamp task_deployed_epoch report_epoch
        report_timestamp=$(yaml_field_get "$report_file" "timestamp" "" 2>/dev/null || true)
        task_deployed_epoch=$(_ninja_monitor_timestamp_epoch "$task_deployed_at") || task_deployed_epoch=""
        report_epoch=$(_ninja_monitor_timestamp_epoch "$report_timestamp") || report_epoch=""
        if [ -n "$task_deployed_epoch" ] && [ -n "$report_epoch" ] && [ "$report_epoch" -lt "$task_deployed_epoch" ]; then
            log "AUTO-DONE-SKIP-STALE-REPORT: $name report=$(basename "$report_file") timestamp=$report_timestamp predates deployed_at=$task_deployed_at, status=$task_status kept"
            return 1
        fi
    fi

    # 報告のstatus確認（done/completed/success を完了とみなす）
    local report_status
    report_status=$(yaml_field_get "$report_file" "status")
    local monitor_state
    monitor_state=$(report_monitor_state "$report_file" 2>/dev/null || printf 'report_pending')
    if [ "$monitor_state" = "awaiting_evidence" ]; then
        log "AUTO-DONE-AWAITING-EVIDENCE: $name report=$(basename "$report_file") remains active until post-deploy evidence completes"
        return 1
    fi
    case "$report_status" in
        done|completed|success)
            # 完了確認 — タスクYAMLをdoneに自動更新（flock排他制御）
            local lock_file="${STATE_DIR:-/tmp}/task_${name}.lock"
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
                    log "ERROR: yaml_field_set failed for ${name} task status update"
                    exit 1
                else
                    # done_at/completed_at自動記録（既存なら上書きしない）
                    if [ -z "$(yaml_field_get "$task_file" "done_at")" ]; then
                        if ! bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" "$task_file" task done_at "$completed_ts"; then
                            log "ERROR: yaml_field_set failed for ${name} task done_at update"
                            exit 1
                        fi
                    fi
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
            _reflux_promotion_record_completion_detached "$report_file" || \
                log "REFLUX-LEDGER-BLOCK: failed to detach $(basename "$report_file")"
            refresh_karo_snapshot_task_assignment "$name"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
)

monitor_task_state_fast_path() {
    local name
    for name in "${NINJA_NAMES[@]}"; do
        check_and_update_done_task "$name" >/dev/null 2>&1 || true
    done
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
                if [ -n "$gate_report_file" ] && [ -f "$gate_report_file" ]; then
                    gate_output=$(run_report_gate_deduped "$name" "$gate_report_file" "$task_file" 2>&1) || true
                    if ! echo "$gate_output" | grep -q "^PASS"; then
                        gate_passed=false
                        if [ "${REPORT_GATE_SENT[$gate_key]}" != "1" ]; then
                            REPORT_GATE_SENT[$gate_key]="1"
                            log "REPORT-FORMAT-FAIL: $name report=$(basename "$gate_report_file") output=$gate_output — auto_deploy BLOCKED"
                            bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$name" "報告YAMLフォーマットエラー: ${gate_output}。報告YAMLを修正して再送信せよ。対象: $(basename "$gate_report_file")" report_format_fix karo >> "$LOG" 2>&1 &
                        else
                            log "REPORT-FORMAT-FAIL-RECHECK: $name report=$(basename "$gate_report_file") output=$gate_output — auto_deploy BLOCKED"
                        fi
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
        # awk単一パス: yaml_field_get×2(task_id→_ac_task_id)→awk×1（write_state_file L2924同パターン）
        local last_task=""
        local _nt_task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
        if [ -f "$_nt_task_file" ]; then
            last_task=$(awk '
                /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
                /^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
                END { print t }
            ' "$_nt_task_file")
        fi
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
        # L112: subtask_id優先→task_id→_ac_task_idのフォールバック（nested task形式/subtask_id不在対応）
        # L4-R24最適化パターン: awk単一パスで取得（yaml_field_get×3サブシェルを回避）
        local stall_id
        stall_id=$(awk '
            BEGIN { t="" }
            /^[ \t]*subtask_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
            /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
            /^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
            END { print t }
        ' "$task_file")
        local stall_count_key="${name}:${stall_id}"
        STALL_COUNT[$stall_count_key]=$((${STALL_COUNT[$stall_count_key]:-0} + 1))
        local count=${STALL_COUNT[$stall_count_key]}
        if [ "$count" -ge 2 ]; then
            notify_karo_throttled stall_escalate "$name" \
              "【STALL-ESCALATE】${name}が${stall_id}で${count}回STALL。差し替え必須。"
        fi
    else
        log "DEPLOY-STALL-WAIT: $name $task_status+idle ${elapsed}s < ${effective_debounce}s"
        PREV_STATE[$name]="busy"
    fi
    return 0
}

# dependency待機のfailed taskを、接続cmdのGATE CLEAR後に一度だけ再配備する。
# task YAMLの3フィールドがdurable registrationのSSOT。statusのfailed→assigned
# 遷移がexactly-once fenceとなり、monitor再起動後も復元できる。
_dependency_continuation_gate_clear_epoch() {
    local connected_cmd="$1"
    local gate_dir="$SCRIPT_DIR/queue/gates/$connected_cmd"
    local archive_marker="$gate_dir/archive.done"
    local trigger_log="$gate_dir/cmd_complete_gate.trigger.log"

    if [ -f "$archive_marker" ]; then
        stat -c %Y "$archive_marker" 2>/dev/null
        return
    fi
    if [ -f "$trigger_log" ] && grep -qE '^GATE CLEAR( \(緊急override\))?:' "$trigger_log"; then
        stat -c %Y "$trigger_log" 2>/dev/null
        return
    fi
    return 1
}

_dependency_continuation_gate_log() {
    local result="$1" detail="$2"
    local log_file="${DEPENDENCY_CONTINUATION_GATE_LOG:-$SCRIPT_DIR/logs/gate_fire_log.yaml}"
    detail="${detail//\"/_}"
    mkdir -p "${log_file%/*}"
    {
        flock 9
        printf '%s\n' "- ts: \"$(date -Iseconds)\", gate: dependency_continuation_consumer, result: ${result}, detail: \"${detail}\"" >&9
    } 9>>"$log_file"
}

_handle_dependency_continuation() {
    local name="$1"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    [ -f "$task_file" ] || return 1

    local task_status wait_reason connected_cmd continuation_task_id task_id release_fp
    IFS='|' read -r task_status wait_reason connected_cmd continuation_task_id task_id release_fp < <(awk '
        function value(line) { sub(/^[^:]*:[[:space:]]*/, "", line); gsub(/["'"'"'[:space:]]/, "", line); return line }
        /^[[:space:]]*status:/ && status=="" { status=value($0) }
        /^[[:space:]]*wait_reason:/ && reason=="" { reason=value($0) }
        /^[[:space:]]*wait_connected_cmd:/ && connected=="" { connected=value($0) }
        /^[[:space:]]*continuation_task_id:/ && continuation=="" { continuation=value($0) }
        /^[[:space:]]*task_id:/ && $0 !~ /_ac_task_id:/ && task=="" { task=value($0) }
        /^[[:space:]]*continuation_release_fingerprint:/ && released=="" { released=value($0) }
        END { print status "|" reason "|" connected "|" continuation "|" task "|" released }
    ' "$task_file")

    [ "$task_status" = "failed" ] || return 1
    [ "$wait_reason" = "dependency" ] || return 1

    if [ -z "$connected_cmd" ] || [ -z "$continuation_task_id" ] || [ "$continuation_task_id" != "$task_id" ]; then
        _dependency_continuation_gate_log BLOCK "ninja=${name} durable_fields=invalid wait_reason=${wait_reason} connected=${connected_cmd:-missing} continuation=${continuation_task_id:-missing} task=${task_id:-missing}"
        log "DEPENDENCY-CONTINUATION-BLOCK: $name durable registration invalid"
        return 0
    fi

    local fingerprint="${connected_cmd}:${continuation_task_id}"
    [ "$release_fp" = "$fingerprint" ] && return 0

    local clear_epoch
    clear_epoch=$(_dependency_continuation_gate_clear_epoch "$connected_cmd") || {
        log "DEPENDENCY-CONTINUATION-WAIT: $name connected=$connected_cmd"
        return 0
    }

    local now latency
    now=${EPOCHSECONDS:-$(date +%s)}
    latency=$((now - clear_epoch))
    [ "$latency" -lt 0 ] && latency=0

    # statusを最後に変える。先行フィールド書込み途中に異常終了しても
    # failedのままなので次cycleが再試行でき、assigned公開後は再実行しない。
    yaml_field_set "$task_file" task continuation_release_fingerprint "$fingerprint" || return 0
    yaml_field_set "$task_file" task continuation_released_at "$(date -Iseconds)" || return 0
    yaml_field_set "$task_file" task status assigned || return 0

    if bash "$SCRIPT_DIR/scripts/inbox_write.sh" "$name" \
        "dependency ${connected_cmd} GATE CLEAR。continuation task ${continuation_task_id}を再開せよ。" \
        task_assigned ninja_monitor task_start >> "$LOG" 2>&1; then
        local result=PASS
        [ "$latency" -gt 60 ] && result=BLOCK
        _dependency_continuation_gate_log "$result" "ninja=${name} connected=${connected_cmd} continuation=${continuation_task_id} deploy_count=1 duplicate_count=0 release_latency_sec=${latency}"
        log "DEPENDENCY-CONTINUATION-RELEASE: $name connected=$connected_cmd latency=${latency}s"
    else
        _dependency_continuation_gate_log BLOCK "ninja=${name} connected=${connected_cmd} continuation=${continuation_task_id} inbox_delivery_failed=1 release_latency_sec=${latency}"
    fi
    PREV_STATE[$name]="busy"
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
    local _ac_task_status=""
    if [ -f "$_ac_task_file" ]; then
        _ac_task_status=$(yaml_field_get "$_ac_task_file" "status")
        if [[ "$_ac_task_status" =~ ^(assigned|acknowledged|in_progress)$ ]]; then
            log "AUTO-CLEAR-SKIP: $name has active task (status=$_ac_task_status), deferring to DEPLOY-STALL"
            return
        fi
    fi

    local _ac_cli_type
    _ac_cli_type=$(cli_type "$name" 2>/dev/null || echo "claude")

    # CTX=0%なら既にクリア済み → スキップ（無駄な再clearループ防止）
    # GP-222: Codex CLIではCTX=0は「未検出」の可能性があるためスキップしない
    # ただしrespawn直後(60s以内)はCTX=0%が正常 → respawn無限ループ防止
    local ctx_now
    ctx_now=$(get_context_pct "$target" "$name")
    if [ "${ctx_now:-0}" -le 0 ] 2>/dev/null; then
        if [ "$_ac_cli_type" = "codex" ]; then
            # GP-222: Codex CLIではCTX=0は「未検出」の可能性があるためスキップしない
            # respawn直後(60s以内)はCTX=0%が正常 → respawn無限ループ防止
            local _codex_last_clear="${LAST_CLEARED[$name]:-0}"
            local _codex_elapsed=$(( now - _codex_last_clear ))
            if [ "$_codex_elapsed" -lt 60 ]; then
                log "CODEX-CTX0-SKIP: $name CTX=0% but respawned ${_codex_elapsed}s ago (< 60s), skipping"
                return
            fi
            # 60s経過後はGP-222通り処理継続（CTX=0でもrespawn試行）
        else
            # Non-Codex: CTX=0% → already clean → skip
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
    fi

    # CTX>0%に変化 → カウンタリセット
    CLEAR_SKIP_COUNT[$name]=0
    clear_last="${LAST_CLEARED[$name]:-0}"
    clear_elapsed=$((now - clear_last))

    # CLI種別に応じたデバウンス（cli_profiles.yaml参照）
    local effective_debounce
    effective_debounce=$(cli_profile_get "$agent_id" "clear_debounce")

    # A failed task is terminal from the worker's point of view. Treat it as
    # no-task for recovery latency. The active-status preflight below still
    # closes the race with a concurrently published revision/redeployment.
    if [ "$_ac_task_status" = "failed" ]; then
        if _failed_task_respawn_completed "$name"; then
            log "FAILED-RESPAWN-DEDUPE: $name failed task generation already recovered, skipping repeated respawn"
            return
        fi
        effective_debounce=0
        log "FAILED-RESPAWN-IMMEDIATE: $name failed task treated as no-task (clear_debounce=0)"
    fi

    if [ "$clear_elapsed" -ge "$effective_debounce" ]; then
        if ! can_send_clear_with_report_gate "$name" "AUTO-CLEAR"; then
            log "AUTO-CLEAR-BLOCKED: $name done but report missing, keep context"
            return
        fi
        # ─── RESPAWN直前最終確認（cmd_3347 AC2: background AUTO_DEPLOY race condition防止） ───
        # 理由: _handle_auto_clearの初回status読取り後にバックグラウンドAUTO_DEPLOYサブシェルが
        # status="assigned"を書き込んだ場合、ここでキャッチしなければ稼働開始済みの忍者を破壊する。
        # 根拠ログ: 00:13:57 [AUTO_DEPLOY] OK → 00:13:59 CODEX-RESPAWN (2秒の競合窓)
        # GP-233パターン: grep直接 (yaml_field_get回避、WSL2 NTFS遅延対策)
        if [ -f "$_ac_task_file" ]; then
            local _pre_status
            _pre_status=$(grep -m1 -E '^\s*status:\s*' "$_ac_task_file" 2>/dev/null \
                | sed 's/.*status:[[:space:]]*//' | tr -d "\"'[:space:]" || true)
            if [[ "$_pre_status" =~ ^(assigned|acknowledged|in_progress)$ ]]; then
                log "AUTO-CLEAR-PREFLIGHT-BLOCK: $name task_status=$_pre_status at respawn time (background deploy完了), deferring to DEPLOY-STALL"
                return
            fi
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
    # delegated=家老委任済み=忍者free。refluxブロックは pending|new のみ。
    # 旧: delegated含む→全忍者reflux 7日間停止(promotion在庫188件停滞の根因。殿裁定2026-07-16)
    grep -qE '^\s+status:\s+(pending|new)' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null
}

_retrospective_recurrence_rate() {
    local dq_file="${1:-$SCRIPT_DIR/logs/cmd_design_quality.yaml}"
    [ -f "$dq_file" ] || { printf '0 0 0\n'; return 0; }
    local _ninja_rx_names _ninja_rx_nm
    _ninja_rx_names="$(get_ninja_names 2>/dev/null | sed 's/ /|/g' || echo 'hayate|kagemaru|hanzo|saizo|kotaro|tobisaru')"
    _ninja_rx_nm="^(${_ninja_rx_names})$"
    grep -E '^[[:space:]]*-[[:space:]]*cmd_id:|^[[:space:]]*(gate_result|notes|timestamp):' "$dq_file" 2>/dev/null | awk -v ninja_rx="$_ninja_rx_nm" '
function trim(s) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); gsub(/^["'\''"]|["'\''"]$/, "", s); return s }
function skip_pattern(p) { return p ~ /^draft_lessons/ || p ~ /^ci_failure/ || p ~ /:binary_checks_fail/ }
function normalize_class(p, parts, cls) {
    p = trim(p)
    if (p == "" || skip_pattern(p)) return ""
    split(p, parts, ":")
    cls = trim(parts[1])
    if (cls ~ ninja_rx && length(parts) > 1) cls = trim(parts[2])
    if (cls ~ /environment_change/ || cls ~ /WARN累計昇格/) return ""
    return cls
}
function flush_entry() {
    if (cmd_id != "" && timestamp != "") {
        n++
        gate[n] = gate_result
        notes_arr[n] = notes
    }
    cmd_id = ""; timestamp = ""; gate_result = ""; notes = ""
}
/^[[:space:]]*-[[:space:]]*cmd_id:/ { flush_entry(); s=$0; sub(/.*cmd_id:[[:space:]]*/, "", s); cmd_id=trim(s); next }
/^[[:space:]]*gate_result:/ { s=$0; sub(/^[[:space:]]*gate_result:[[:space:]]*/, "", s); gate_result=trim(s); next }
/^[[:space:]]*notes:/ { s=$0; sub(/^[[:space:]]*notes:[[:space:]]*/, "", s); notes=trim(s); next }
/^[[:space:]]*timestamp:/ { s=$0; sub(/^[[:space:]]*timestamp:[[:space:]]*/, "", s); timestamp=trim(s); next }
END {
    flush_entry()
    recent_start = n - 49
    if (recent_start < 1) recent_start = 1
    prev_start = n - 99
    prev_end = n - 50
    if (prev_start < 1) prev_start = 1
    for (i = recent_start; i <= n; i++) {
        if (gate[i] != "BLOCK" && gate[i] != "WARN") continue
        split(notes_arr[i], pats, "|")
        for (j in pats) {
            cls = normalize_class(pats[j])
            if (cls != "") recent_cls[cls] = 1
        }
    }
    for (i = prev_start; i <= prev_end; i++) {
        if (gate[i] != "BLOCK" && gate[i] != "WARN") continue
        split(notes_arr[i], pats, "|")
        for (j in pats) {
            cls = normalize_class(pats[j])
            if (cls != "") prev_cls[cls] = 1
        }
    }
    for (cls in prev_cls) {
        prev_total++
        if (cls in recent_cls) recur++
    }
    rate = (prev_total > 0) ? int(recur * 100 / prev_total) : 0
    printf "%d %d %d\n", rate + 0, recur + 0, prev_total + 0
}'
}

_pause_speed_training_if_recurrence_high() {
    local helper="$SCRIPT_DIR/tools/bash_speed_training.sh"
    local threshold="${SPEED_TRAINING_RECURRENCE_PAUSE_THRESHOLD:-10}"
    local rate recur total
    [ -r "$helper" ] || return 1
    [ -f "$SPEED_TRAINING_LEDGER" ] || return 1
    if _speed_training_active_test_campaign; then
        log "SPEED-TRAINING-AUTO-PAUSE-SKIP: active test-speed campaign"
        return 1
    fi
    [[ "$threshold" =~ ^[0-9]+$ ]] || threshold=10
    read -r rate recur total < <(_retrospective_recurrence_rate "$SCRIPT_DIR/logs/cmd_design_quality.yaml")
    [ "${total:-0}" -gt 0 ] 2>/dev/null || return 1
    if [ "${rate:-0}" -gt "$threshold" ] 2>/dev/null; then
        if bash "$helper" set-global-status paused "$SPEED_TRAINING_LEDGER" >/dev/null 2>&1; then
            log "SPEED-TRAINING-AUTO-PAUSE: recurrence_rate=${rate}% threshold=${threshold}% recurring=${recur}/${total}; global_status=paused"
        else
            log "SPEED-TRAINING-AUTO-PAUSE-FAIL: recurrence_rate=${rate}% threshold=${threshold}% recurring=${recur}/${total}"
        fi
        return 0
    fi
    return 1
}

_speed_training_active_test_campaign() {
    local task_glob=("$SCRIPT_DIR"/queue/tasks/*.yaml)
    local campaign_ledger="${TEST_SPEED_CAMPAIGN_LEDGER:-$SCRIPT_DIR/logs/test_speed_campaign_ledger.tsv}"
    local status campaign round
    [ -e "${task_glob[0]}" ] || return 1
    while IFS=$'\t' read -r status campaign round; do
        case "$status" in
            assigned|acknowledged|in_progress)
                return 0
                ;;
            done|completed)
                # report公開からcomplete-deploy callbackまでの隙間もactive。
                # 同一roundがledgerへ記録済みならcallback完了なので抑止対象外。
                if [ -n "$campaign" ] && [[ "$round" =~ ^[1-9][0-9]*$ ]] && \
                   ! awk -F '\t' -v c="$campaign" -v r="$round" \
                       'NR > 1 && $1 == c && $2 == r { found=1 } END { exit !found }' \
                       "$campaign_ledger" 2>/dev/null; then
                    return 0
                fi
                ;;
        esac
    done < <(awk '
      function emit() {
        if (is_speed) printf "%s\t%s\t%s\n", status, campaign, round
      }
      FNR == 1 {
        if (NR > 1) emit()
        is_speed=0; status=""; campaign=""; round=""
      }
      /^  parent_cmd:[[:space:]]*/ && $0 ~ /cmd_training_test_speed_/ { is_speed=1 }
      /^  status:[[:space:]]*/ {
        value=$0
        sub(/^  status:[[:space:]]*/, "", value)
        gsub(/[[:space:]\042]/, "", value)
        status=value
      }
      /^    campaign_id:[[:space:]]*/ {
        campaign=$0; sub(/^    campaign_id:[[:space:]]*/, "", campaign); gsub(/[[:space:]\042]/, "", campaign)
      }
      /^    round_index:[[:space:]]*/ {
        round=$0; sub(/^    round_index:[[:space:]]*/, "", round); gsub(/[[:space:]\042]/, "", round)
      }
      END { emit() }
    ' "${task_glob[@]}")
    return 1
}

_speed_training_pipeline_has_work() {
    local helper="$SCRIPT_DIR/tools/bash_speed_training.sh"
    local pending_or_rework assigned_count completed_count reenqueue_count
    [ -r "$helper" ] || return 1
    [ -f "$SPEED_TRAINING_LEDGER" ] || return 1
    pending_or_rework=$(bash "$helper" next "$SPEED_TRAINING_LEDGER" 2>/dev/null || true)
    [ -n "$pending_or_rework" ] && return 0

    assigned_count=$(bash "$helper" status-count assigned "$SPEED_TRAINING_LEDGER" 2>/dev/null || printf '0')
    [ "${assigned_count:-0}" -gt 0 ] 2>/dev/null && return 1

    completed_count=$(bash "$helper" status-count completed "$SPEED_TRAINING_LEDGER" 2>/dev/null || printf '0')
    [ "${completed_count:-0}" -gt 0 ] 2>/dev/null || return 1

    reenqueue_count=$(bash "$helper" re-enqueue "${SPEED_TRAINING_REENQUEUE_LIMIT:-20}" "$SPEED_TRAINING_LEDGER" 2>/dev/null || printf '0')
    if [ "${reenqueue_count:-0}" -gt 0 ] 2>/dev/null; then
        log "SPEED-TRAINING-REENQUEUE: completed_top=${reenqueue_count} limit=${SPEED_TRAINING_REENQUEUE_LIMIT:-20} max_iteration=${SPEED_TRAINING_MAX_ITERATION:-3}"
        return 0
    fi
    return 1
}

_handle_speed_training_auto_deploy() {
    local name="$1"
    local now="$2"
    local helper="$SCRIPT_DIR/tools/bash_speed_training.sh"
    local output status task_file task_status

    [ -n "$name" ] || return 1
    [ -r "$helper" ] || return 1
    task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    [ -f "$task_file" ] || {
        log "SPEED-TRAINING-AUTO-SKIP: $name task file missing"
        return 1
    }
    task_status=$(yaml_field_get "$task_file" "status")
    if [ "$task_status" != "idle" ]; then
        log "SPEED-TRAINING-AUTO-SKIP: $name task status=${task_status:-missing}"
        return 1
    fi

    if _training_pipeline_has_work; then
        log "SPEED-TRAINING-AUTO-SKIP: $name production pipeline has pending work"
        return 1
    fi

    if _pause_speed_training_if_recurrence_high; then
        return 1
    fi

    if ! _speed_training_pipeline_has_work; then
        return 1
    fi

    output=$(bash "$helper" auto-deploy "$name" "$SPEED_TRAINING_LEDGER" 2>&1)
    status=$?
    if [ "$status" -eq 0 ]; then
        log "SPEED-TRAINING-AUTO-DEPLOY: $name ${output}"
        return 0
    fi

    log "SPEED-TRAINING-AUTO-FAIL: $name status=${status} output=${output}"
    return 1
}

_handle_test_speed_auto_deploy() {
    local name="$1" helper="$SCRIPT_DIR/scripts/test_speed_task_generator.sh" output status
    local task_file task_status
    [ -n "$name" ] || return 1
    [ -r "$helper" ] || return 1
    task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    [ -f "$task_file" ] || {
        log "TEST-SPEED-AUTO-SKIP: $name task file missing"
        return 1
    }
    task_status=$(yaml_field_get "$task_file" "status")
    if [ "$task_status" != "idle" ]; then
        log "TEST-SPEED-AUTO-SKIP: $name task status=${task_status:-missing}"
        return 1
    fi
    output=$(bash "$helper" deploy "$name" 2>&1); status=$?
    if [ "$status" -eq 0 ]; then
        log "TEST-SPEED-AUTO-DEPLOY: $name ${output}"
        return 0
    fi
    [ "$output" = "NO_CANDIDATE" ] || log "TEST-SPEED-AUTO-SKIP: $name status=${status} output=${output}"
    return 1
}

_reflux_auto_state_file() {
    local name="$1"
    printf '%s_%s.last\n' "${REFLUX_AUTO_DEPLOY_STATE_PREFIX:-$STATE_DIR/shogun_reflux_auto_deploy}" "$name"
}

_reflux_insight_pending_count() {
    local insights_file="${1:-$SCRIPT_DIR/queue/insights.yaml}"
    [ -f "$insights_file" ] || { printf '0\n'; return 0; }
    awk '
        /^[[:space:]]*status:[[:space:]]*["'\'']?pending["'\'']?[[:space:]]*$/ { n++ }
        END { print n + 0 }
    ' "$insights_file"
}

_reflux_first_pending_insight_id() {
    local insights_file="${1:-$SCRIPT_DIR/queue/insights.yaml}"
    [ -f "$insights_file" ] || return 1
    awk '
        function clean(s) { gsub(/^[[:space:]"'\''"]+|[[:space:]"'\''"]+$/, "", s); return s }
        function prio_score(p) {
            if (p == "high") return 3
            if (p == "medium") return 2
            if (p == "low") return 1
            return 2
        }
        function flush() {
            if (id != "" && status == "pending") {
                score = prio_score(priority) + (fix_known == "true" ? 10 : 0)
                if (!found || score > best_score) {
                    best_id = id
                    best_score = score
                    found = 1
                }
            }
        }
        /^-[[:space:]]+id:[[:space:]]*/ {
            flush()
            id = $0
            sub(/^-[[:space:]]+id:[[:space:]]*/, "", id)
            id = clean(id)
            status = ""
            priority = ""
            fix_known = "false"
            next
        }
        /^  status:[[:space:]]*/ {
            status = $0
            sub(/^  status:[[:space:]]*/, "", status)
            status = clean(status)
            next
        }
        /^  priority:[[:space:]]*/ {
            priority = $0
            sub(/^  priority:[[:space:]]*/, "", priority)
            priority = clean(priority)
            next
        }
        /^  fix_known:[[:space:]]*/ {
            fix_known = $0
            sub(/^  fix_known:[[:space:]]*/, "", fix_known)
            fix_known = clean(fix_known)
            next
        }
        END {
            flush()
            if (found) print best_id
        }
    ' "$insights_file"
}

_reflux_zero_backlink_inventory() {
    local helper="$SCRIPT_DIR/scripts/causal_backlink_counts.sh"
    local limit="${REFLUX_BACKLINK_SCAN_LIMIT:-50}"
    local timeout_sec="${REFLUX_BACKLINK_TIMEOUT:-20}"
    local output status count first_path

    [[ "$limit" =~ ^[0-9]+$ ]] || limit=50
    [[ "$timeout_sec" =~ ^[0-9]+$ ]] || timeout_sec=20
    [ "$limit" -gt 0 ] 2>/dev/null || limit=50
    [ "$timeout_sec" -gt 0 ] 2>/dev/null || timeout_sec=20

    if [ ! -r "$helper" ]; then
        printf '0\t-\tmissing-helper\n'
        return 0
    fi

    if command -v timeout >/dev/null 2>&1; then
        output=$(CAUSAL_BACKLINK_COUNTS_ROOT="$SCRIPT_DIR" timeout "$timeout_sec" bash "$helper" --zero --limit "$limit" 2>/dev/null)
        status=$?
    else
        output=$(CAUSAL_BACKLINK_COUNTS_ROOT="$SCRIPT_DIR" bash "$helper" --zero --limit "$limit" 2>/dev/null)
        status=$?
    fi

    if [ "$status" -ne 0 ]; then
        printf '0\t-\tstatus_%s\n' "$status"
        return 0
    fi

    count=$(printf '%s\n' "$output" | awk 'NF >= 2 { n++ } END { print n + 0 }')
    first_path=$(printf '%s\n' "$output" | awk 'NF >= 2 { print $2; exit }')
    [ -n "$first_path" ] || first_path="-"
    printf '%s\t%s\tok\n' "${count:-0}" "$first_path"
}

# PD登録済み(status: pending)のdecision summaryから教訓IDを抽出する。
# reflux promotionの重複dispatch根因(saizo cmd_reflux_promotion_202607080715実証):
# 家老がdecision_candidateをpending_decisions.yamlへ登録しても、below4候補一覧
# 選定ロジックがそれを一切参照しないため、PD登録済みの候補が繰り返し先頭に居座り
# 同一対象への再dispatchが発生する。新規状態管理は追加せず、既存のpending_decisions.yaml
# を一次情報として参照するのみに留める。
_reflux_promotion_pending_pd_ids() {
    local pd_file="$SCRIPT_DIR/queue/pending_decisions.yaml"
    [ -r "$pd_file" ] || return 0
    python3 - "$pd_file" 2>/dev/null <<'PY'
import re
import sys

import yaml

path = sys.argv[1]
try:
    with open(path, encoding='utf-8') as fh:
        data = yaml.safe_load(fh)
except Exception:
    sys.exit(0)

if not isinstance(data, dict):
    sys.exit(0)

# Role lessons use LS/LK/LG prefixes, while PJ lessons commonly use L<number>.
# Pending PD exclusion must cover all of them or escalated candidates get
# repeatedly dispatched by reflux promotion.
id_re = re.compile(r'(?<![0-9A-Za-z-])(?:LS|LK|LG|L)-?[A-Za-z]?[0-9]+(?![0-9A-Za-z])')
ids = set()
for d in data.get('decisions') or []:
    if not isinstance(d, dict):
        continue
    if d.get('status') != 'pending':
        continue
    summary = d.get('summary', '')
    if isinstance(summary, str):
        ids.update(id_re.findall(summary))

for i in sorted(ids):
    print(i)
PY
}

# Completed promotion reports are the durable consumption ledger.  Lesson
# metadata can lag a valid Level4/5 implementation, so relying only on the
# enforcement inventory redispatches the same lesson until that metadata is
# repaired.  Require both completed status and PASS verdict; drafts and failed
# promotions must remain selectable.
_reflux_promotion_scan_completed_ids() {
    python3 - "$SCRIPT_DIR" 2>/dev/null <<'PY'
import glob
import os
import re
import sys

import yaml

root = sys.argv[1]
paths = glob.glob(os.path.join(root, "queue", "reports", "*.yaml"))
paths += glob.glob(os.path.join(root, "archive", "reports", "**", "*.yaml"), recursive=True)
id_token = r'(?:LS|LK|LG|L)-?[A-Za-z]?[0-9]+'
target_re = re.compile(r'(?:^|昇格候補\s+(?:\[[^]]+\]\s+)?)(%s)(?![0-9A-Za-z])' % id_token)
completed = set()
for path in paths:
    try:
        with open(path, encoding="utf-8") as fh:
            report = yaml.safe_load(fh) or {}
    except Exception:
        continue
    if not isinstance(report, dict):
        continue
    parent = str(report.get("parent_cmd") or "")
    if not parent.startswith("cmd_reflux_promotion_"):
        continue
    if str(report.get("status") or "").lower() not in {"completed", "done"}:
        continue
    if str(report.get("verdict") or "").upper() not in {"PASS", "PASS_NO_IMPROVEMENT"}:
        continue
    # Generated promotion reports retain the selected lesson in purpose,
    # summary, details, or AC checks.  Restrict extraction to those fields so
    # unrelated lessons_useful references cannot consume inventory.
    result = report.get("result") if isinstance(report.get("result"), dict) else {}
    fields = [result.get("summary")]
    checks = report.get("binary_checks") or {}
    if isinstance(checks, dict):
        for entries in checks.values():
            if isinstance(entries, list):
                fields.extend(e.get("check") for e in entries if isinstance(e, dict))
    for value in fields:
        if isinstance(value, str):
            completed.update(target_re.findall(value))
for lesson_id in sorted(completed):
    print(lesson_id)
PY
}

_reflux_promotion_completed_ids() {
    local ledger="${REFLUX_PROMOTION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_completed.tsv}"
    if [ ! -e "$ledger" ]; then
        local lock_file="${ledger}.lock" timestamp id scanned
        mkdir -p "$(dirname "$ledger")"
        {
            flock -x -w 5 200 || return 1
            if [ ! -e "$ledger" ]; then
                scanned=$(_reflux_promotion_scan_completed_ids)
                printf 'completed_at\tlesson_id\treport\n' > "$ledger"
                printf -v timestamp '%(%Y-%m-%dT%H:%M:%S)T' -1
                while IFS= read -r id; do
                    [ -n "$id" ] && printf '%s\t%s\tbackfill\n' "$timestamp" "$id" >> "$ledger"
                done <<< "$scanned"
            fi
        } 200>"$lock_file"
    fi
    [ -r "$ledger" ] || return 0
    awk -F '\t' 'NF >= 2 && $2 != "lesson_id" { print $2 }' "$ledger" | sort -u
}

# A terminal promotion may deliberately stop at the foreign-dirty guard and
# publish a decision_candidate.  That is neither a completed promotion nor a
# permanently pending item: suppress it only while the guarded target/cache
# fingerprint is unchanged.  The TSV is durable and flocked so concurrent
# inventories converge on one reservation.
_reflux_promotion_deferred_suppressed() {
    local candidate="$1" lesson_id source target cache ledger lock fingerprint report_match old_fp
    lesson_id=$(printf '%s\n' "$candidate" | sed -n 's/^\[[^]]*\] \([A-Za-z0-9_-]*\).*/\1/p')
    [ -n "$lesson_id" ] || return 1
    source=$(printf '%s\n' "$candidate" | sed -n 's/^\[\([^]]*\)\].*/\1/p')
    target=$(_reflux_promotion_target_path "$candidate")
    cache="$SCRIPT_DIR/tasks/lessons.md"
    ledger="${REFLUX_PROMOTION_DEFERRED_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_deferred.tsv}"
    lock="${ledger}.lock"
    report_match=$(python3 - "$SCRIPT_DIR" "$lesson_id" 2>/dev/null <<'PY'
import glob, json, os, re, sys, yaml
root, lesson = sys.argv[1:]
for path in glob.glob(os.path.join(root, "queue/reports/*.yaml")) + glob.glob(os.path.join(root, "archive/reports/**/*.yaml"), recursive=True):
    try:
        d = yaml.safe_load(open(path, encoding="utf-8")) or {}
    except Exception:
        continue
    if not str(d.get("parent_cmd") or "").startswith("cmd_reflux_promotion_"):
        continue
    if str(d.get("status") or "").lower() not in {"completed", "done", "failed"}:
        continue
    dc = d.get("decision_candidate") or {}
    if not isinstance(dc, dict) or dc.get("found") is not True:
        continue
    # This is a read-only keyword scan, so JSON provides the same recursive
    # textual projection without invoking a YAML serializer in a shell-owned
    # operational script.
    text = json.dumps(d, ensure_ascii=False, default=str)
    if lesson in text and re.search(r"foreign[ _-]?dirty", text, re.I):
        print(path); break
PY
)
    [ -n "$report_match" ] || return 1
    fingerprint=$({ for p in "$SCRIPT_DIR/$target" "$cache"; do if [ -e "$p" ]; then sha256sum "$p"; else printf 'missing  %s\n' "$p"; fi; done; } | sha256sum | awk '{print $1}')
    mkdir -p "$(dirname "$ledger")"
    {
        flock -x -w 5 200 || return 1
        [ -s "$ledger" ] || printf 'deferred_at\tlesson_id\tfingerprint\ttarget\treport\n' > "$ledger"
        old_fp=$(awk -F '\t' -v id="$lesson_id" '$2==id {fp=$3} END{print fp}' "$ledger")
        if [ -z "$old_fp" ]; then
            printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$lesson_id" "$fingerprint" "$target" "${report_match#"$SCRIPT_DIR"/}" >> "$ledger"
            return 0
        fi
        [ "$old_fp" = "$fingerprint" ] && return 0
        return 2
    } 200>"$lock"
}

_reflux_promotion_record_completion() {
    local report_file="$1"
    local ledger="${REFLUX_PROMOTION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_completed.tsv}"
    local lock_file="${ledger}.lock" lesson_ids timestamp report_rel lesson_id
    [ -r "$report_file" ] || return 1
    lesson_ids=$(python3 - "$report_file" 2>/dev/null <<'PY'
import re, sys, yaml
p=sys.argv[1]
d=yaml.safe_load(open(p, encoding="utf-8")) or {}
if not str(d.get("parent_cmd") or "").startswith("cmd_reflux_promotion_"): raise SystemExit(0)
if str(d.get("status") or "").lower() not in {"completed","done","success"}: raise SystemExit(0)
if str(d.get("verdict") or "").upper() not in {"PASS","PASS_NO_IMPROVEMENT"}: raise SystemExit(0)
token=r'(?:LS|LK|LG|L)-?[A-Za-z]?[0-9]+'
rx=re.compile(r'(?:^|昇格候補\s+(?:\[[^]]+\]\s+)?)(%s)(?![0-9A-Za-z])' % token)
result=d.get("result") if isinstance(d.get("result"),dict) else {}
values=[result.get("summary")]
for entries in (d.get("binary_checks") or {}).values():
    if isinstance(entries,list): values += [x.get("check") for x in entries if isinstance(x,dict)]
print("\n".join(sorted({m for v in values if isinstance(v,str) for m in rx.findall(v)})))
PY
)
    [ -n "$lesson_ids" ] || return 0
    mkdir -p "$(dirname "$ledger")"
    printf -v timestamp '%(%Y-%m-%dT%H:%M:%S)T' -1
    report_rel="${report_file#"$SCRIPT_DIR"/}"
    {
        flock -x -w 5 200 || return 1
        [ -s "$ledger" ] || printf 'completed_at\tlesson_id\treport\n' >> "$ledger"
        while IFS= read -r lesson_id; do
            [ -n "$lesson_id" ] || continue
            if ! awk -F '\t' -v id="$lesson_id" '$2 == id { found=1 } END { exit !found }' "$ledger"; then
                printf '%s\t%s\t%s\n' "$timestamp" "$lesson_id" "$report_rel" >> "$ledger"
            fi
        done <<< "$lesson_ids"
    } 200>"$lock_file"
}

# A plain background subshell remains attached to the monitor's command-
# substitution pipes and can keep the done fast-path waiting.  Double-fork a
# lib-only worker with closed stdio.  Completion is idempotent, so a launch
# failure is retried on the next cycle while the task remains done.
_reflux_promotion_record_completion_detached() {
    local report_file="$1"
    local monitor_script="${BASH_SOURCE[0]}"
    local ledger="${REFLUX_PROMOTION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_completed.tsv}"
    [ -r "$report_file" ] || return 1
    command -v setsid >/dev/null 2>&1 || return 1
    setsid -f env NINJA_MONITOR_LIB_ONLY=1 REFLUX_PROMOTION_LEDGER="$ledger" \
        bash -c '
            source "$1"
            SCRIPT_DIR="$2"
            _reflux_promotion_record_completion "$3"
        ' _ "$monitor_script" "$SCRIPT_DIR" "$report_file" \
        </dev/null >/dev/null 2>&1
}

_reflux_promotion_backfill_and_check() {
    local scanned ledger_ids missing extra id
    scanned=$(_reflux_promotion_scan_completed_ids)
    ledger_ids=$(_reflux_promotion_completed_ids)
    missing=$(comm -23 <(printf '%s\n' "$scanned" | sed '/^$/d' | sort -u) <(printf '%s\n' "$ledger_ids" | sed '/^$/d' | sort -u))
    if [ -n "$missing" ]; then
        while IFS= read -r id; do
            [ -n "$id" ] || continue
            local timestamp ledger="${REFLUX_PROMOTION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_completed.tsv}"
            printf -v timestamp '%(%Y-%m-%dT%H:%M:%S)T' -1
            mkdir -p "$(dirname "$ledger")"
            { flock -x -w 5 200 || return 1; [ -s "$ledger" ] || printf 'completed_at\tlesson_id\treport\n' >> "$ledger"; awk -F '\t' -v x="$id" '$2==x{f=1} END{exit !f}' "$ledger" || printf '%s\t%s\t%s\n' "$timestamp" "$id" backfill >> "$ledger"; } 200>"${ledger}.lock"
        done <<< "$missing"
    fi
    ledger_ids=$(_reflux_promotion_completed_ids)
    extra=$(comm -13 <(printf '%s\n' "$scanned" | sed '/^$/d' | sort -u) <(printf '%s\n' "$ledger_ids" | sed '/^$/d' | sort -u))
    [ -z "$extra" ] || { printf 'BLOCK ledger_extra=%s\n' "$(printf '%s' "$extra" | tr '\n' ',')"; return 1; }
    # Full report reconciliation is a migration/repair operation, not part of
    # the inventory hot path.  Publish the marker only after a zero-diff check;
    # normal completions are appended event-by-event by
    # _reflux_promotion_record_completion.
    : > "${REFLUX_PROMOTION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_completed.tsv}.reconciled-v1"
    printf 'PASS scanned=%s ledger=%s diff=0\n' "$(printf '%s\n' "$scanned" | sed '/^$/d' | wc -l)" "$(printf '%s\n' "$ledger_ids" | sed '/^$/d' | wc -l)"
}

_reflux_promotion_inventory() {
    local helper="$SCRIPT_DIR/scripts/gates/gate_lesson_enforcement_level.sh"
    local timeout_sec="${REFLUX_PROMOTION_TIMEOUT:-20}"
    local output status count first_item candidates_list pd_ids completed_ids cand cand_id completed_skipped=0 deferred_rc=1
    local cache_dir="${STATE_DIR:-$SCRIPT_DIR/.cache}" cache_file sig_file current_sig cached_sig

    [[ "$timeout_sec" =~ ^[0-9]+$ ]] || timeout_sec=20
    [ "$timeout_sec" -gt 0 ] 2>/dev/null || timeout_sec=20

    # Reconcile legacy ledgers exactly once.  Re-scanning every completed
    # report here made the monitor's hot inventory lookup O(report history).
    # After migration, check_and_update_done_task is the event-driven writer.
    local reconcile_marker="${REFLUX_PROMOTION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_completed.tsv}.reconciled-v1"
    if [ ! -e "$reconcile_marker" ] && ! _reflux_promotion_backfill_and_check >/dev/null; then
        printf '0\t-\tledger-inconsistent\n'
        return 1
    fi

    if [ ! -r "$helper" ]; then
        printf '0\t-\tmissing-helper\n'
        return 0
    fi

    cache_file="$cache_dir/reflux_promotion_inventory.raw"
    sig_file="${cache_file}.sig"
    if [ -d "$SCRIPT_DIR/projects" ]; then
        current_sig=$(find "$SCRIPT_DIR/projects" -type f \( -name 'lessons.yaml' -o -name 'lessons_shogun.yaml' -o -name 'lessons_karo.yaml' -o -name 'lessons_gunshi.yaml' \) -printf '%p:%T@:%s\n' 2>/dev/null | sort | sha256sum | awk '{print $1}')
    else
        # An isolated fixture (or a fresh installation before project
        # materialization) legitimately has no lesson tree yet.  Hash the
        # empty inventory without invoking find on a missing root: under a
        # set -euo pipefail caller, find rc=1 would otherwise abort dispatch.
        current_sig=$(printf '' | sha256sum | awk '{print $1}')
    fi
    cached_sig=$(cat "$sig_file" 2>/dev/null || true)
    if [ -n "$current_sig" ] && [ "$current_sig" = "$cached_sig" ] && [ -r "$cache_file" ]; then
        output=$(cat "$cache_file")
        status=0
    else
        if command -v timeout >/dev/null 2>&1; then
            output=$(LESSON_ENFORCEMENT_ROOT="$SCRIPT_DIR" timeout "$timeout_sec" bash "$helper" 2>/dev/null)
            status=$?
        else
            output=$(LESSON_ENFORCEMENT_ROOT="$SCRIPT_DIR" bash "$helper" 2>/dev/null)
            status=$?
        fi
        if [ "$status" -eq 0 ]; then
            mkdir -p "$cache_dir"
            printf '%s\n' "$output" > "$cache_file"
            printf '%s\n' "$current_sig" > "$sig_file"
        fi
    fi

    if [ "$status" -ne 0 ]; then
        printf '0\t-\tstatus_%s\n' "$status"
        return 0
    fi

    count=$(printf '%s\n' "$output" | awk '/^##ENFORCEMENT_LEVEL_BELOW4_COUNT##/{getline c; print c; found=1; exit} END{if(!found) print 0}')
    [[ "$count" =~ ^[0-9]+$ ]] || count=0

    candidates_list=$(printf '%s\n' "$output" | awk '/^=== 昇格候補一覧/{p=1; next} p && /^  - / { sub(/^  - /, ""); print }')
    pd_ids=$(_reflux_promotion_pending_pd_ids)
    completed_ids=$(_reflux_promotion_completed_ids)

    first_item="-"
    if [ -n "$candidates_list" ]; then
        while IFS= read -r cand; do
            [ -n "$cand" ] || continue
            cand_id=$(printf '%s\n' "$cand" | sed -n 's/^\[[^]]*\] \([A-Za-z0-9_-]*\).*/\1/p')
            if [ -n "$cand_id" ] && [ -n "$pd_ids" ] && printf '%s\n' "$pd_ids" | grep -qxF "$cand_id"; then
                continue
            fi
            deferred_rc=1
            if _reflux_promotion_deferred_suppressed "$cand"; then
                completed_skipped=$((completed_skipped + 1))
                continue
            else
                deferred_rc=$?
            fi
            if [ "$deferred_rc" -ne 2 ] && [ -n "$cand_id" ] && [ -n "$completed_ids" ] && printf '%s\n' "$completed_ids" | grep -qxF "$cand_id"; then
                completed_skipped=$((completed_skipped + 1))
                continue
            fi
            first_item="$cand"
            break
        done <<< "$candidates_list"
    fi

    [ -n "$first_item" ] || first_item="-"
    count=$((count - completed_skipped))
    [ "$count" -ge 0 ] || count=0
    printf '%s\t%s\tok\n' "$count" "$first_item"
}

_reflux_promotion_target_path() {
    local candidate="$1"
    local source
    source=$(printf '%s\n' "$candidate" | sed -n 's/^\[\([^]]*\)\].*/\1/p')
    case "$source" in
        lessons_shogun.yaml|lessons_karo.yaml|lessons_gunshi.yaml)
            printf 'projects/infra/%s\n' "$source"
            ;;
        ""|"-")
            printf 'projects/infra/lessons.yaml\n'
            ;;
        *)
            printf 'projects/%s/lessons.yaml\n' "$source"
            ;;
    esac
}

# Atomically claim a promotion lesson at the dispatch boundary.  Inventory is
# intentionally read-only and can race with the event-driven completion writer;
# this lease closes that gap without coupling unrelated lesson IDs.
_reflux_promotion_try_reserve() {
    local candidate="$1" owner="$2"
    local lesson_id ledger
    lesson_id=$(printf '%s\n' "$candidate" | sed -n 's/^\[[^]]*\] \([A-Za-z0-9_-]*\).*/\1/p')
    [ -n "$lesson_id" ] || return 1
    ledger="${REFLUX_PROMOTION_RESERVATION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_reservations.tsv}"
    mkdir -p "$(dirname "$ledger")"
    REFLUX_PROMOTION_LEDGER="${REFLUX_PROMOTION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_completed.tsv}" \
    REFLUX_PROMOTION_DEFERRED_LEDGER="${REFLUX_PROMOTION_DEFERRED_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_deferred.tsv}" \
    python3 - "$SCRIPT_DIR" "$ledger" "$lesson_id" "$owner" <<'PY'
import fcntl, glob, os, re, sys
import yaml

root, ledger, lesson_id, owner = sys.argv[1:]
lock_path = ledger + ".lock"
id_re = re.compile(r"(?<![0-9A-Za-z-])" + re.escape(lesson_id) + r"(?![0-9A-Za-z])")

def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh) or {}
    except Exception:
        return {}
    if isinstance(doc, dict) and isinstance(doc.get("task"), dict):
        return doc["task"]
    return doc if isinstance(doc, dict) else {}

def contains_id(doc):
    return bool(id_re.search(str(doc)))

def ledger_has(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return any(len(row.split("\t")) > 1 and row.split("\t")[1] == lesson_id for row in fh)
    except OSError:
        return False

os.makedirs(os.path.dirname(ledger), exist_ok=True)
with open(lock_path, "a+", encoding="utf-8") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    terminal = any(ledger_has(path) for path in (
        os.environ.get("REFLUX_PROMOTION_LEDGER", os.path.join(root, "logs/reflux_promotion_completed.tsv")),
        os.environ.get("REFLUX_PROMOTION_DEFERRED_LEDGER", os.path.join(root, "logs/reflux_promotion_deferred.tsv")),
    ))
    blocked = terminal
    for path in glob.glob(os.path.join(root, "queue/tasks/*.yaml")):
        doc = load(path)
        if str(doc.get("status") or "") in {"assigned", "acknowledged", "in_progress"} and contains_id(doc):
            blocked = True
    for path in glob.glob(os.path.join(root, "queue/reports/*.yaml")) + glob.glob(os.path.join(root, "archive/reports/**/*.yaml"), recursive=True):
        doc = load(path)
        if str(doc.get("parent_cmd") or "").startswith("cmd_reflux_promotion_") and contains_id(doc):
            blocked = True
    rows = []
    try:
        with open(ledger, encoding="utf-8") as fh:
            rows = [row.rstrip("\n") for row in fh if row.strip()]
    except OSError:
        pass
    # Terminal ledgers are the safe release condition; otherwise a live lease
    # remains blocking even if task/report publication is temporarily delayed.
    active = [r for r in rows if len(r.split("\t")) > 1 and not (terminal and r.split("\t")[1] == lesson_id)]
    if any(len(r.split("\t")) > 1 and r.split("\t")[1] == lesson_id for r in active):
        blocked = True
    if blocked:
        if active != rows:
            with open(ledger, "w", encoding="utf-8") as fh:
                fh.write("\n".join(active) + ("\n" if active else ""))
        raise SystemExit(1)
    from datetime import datetime
    active.append(f"{datetime.now().isoformat(timespec='seconds')}\t{lesson_id}\t{owner}")
    with open(ledger, "w", encoding="utf-8") as fh:
        fh.write("\n".join(active) + "\n")
PY
}

_reflux_promotion_release_reservation() {
    local candidate="$1" owner="$2" lesson_id ledger tmp
    lesson_id=$(printf '%s\n' "$candidate" | sed -n 's/^\[[^]]*\] \([A-Za-z0-9_-]*\).*/\1/p')
    [ -n "$lesson_id" ] || return 0
    ledger="${REFLUX_PROMOTION_RESERVATION_LEDGER:-$SCRIPT_DIR/logs/reflux_promotion_reservations.tsv}"
    [ -e "$ledger" ] || return 0
    tmp="${ledger}.tmp.$$"
    { flock -x -w 5 200 || return 1
      awk -F '\t' -v id="$lesson_id" -v who="$owner" '!(NF>=3 && $2==id && $3==who)' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
    } 200>"${ledger}.lock"
}

_reflux_inventory_snapshot() {
    local insights_file="${1:-$SCRIPT_DIR/queue/insights.yaml}"
    local insight_count first_insight backlink_count first_backlink backlink_status promotion_count first_promotion promotion_status total
    insight_count=$(_reflux_insight_pending_count "$insights_file")
    first_insight=$(_reflux_first_pending_insight_id "$insights_file" 2>/dev/null || true)
    IFS=$'\t' read -r backlink_count first_backlink backlink_status < <(_reflux_zero_backlink_inventory)
    IFS=$'\t' read -r promotion_count first_promotion promotion_status < <(_reflux_promotion_inventory)
    [[ "$insight_count" =~ ^[0-9]+$ ]] || insight_count=0
    [[ "$backlink_count" =~ ^[0-9]+$ ]] || backlink_count=0
    [[ "$promotion_count" =~ ^[0-9]+$ ]] || promotion_count=0
    [ -n "$first_insight" ] || first_insight="-"
    [ -n "$first_backlink" ] || first_backlink="-"
    [ -n "$first_promotion" ] || first_promotion="-"
    total=$((insight_count + backlink_count + promotion_count))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$insight_count" "$backlink_count" "$promotion_count" "$total" \
        "$first_insight" "$first_backlink" "$first_promotion" \
        "${backlink_status:-ok}" "${promotion_status:-ok}"
}

# Select the available inventory with the greatest stock pressure. Ties keep
# the historical insight -> backlink -> promotion order, making selection
# deterministic without adding scheduler state.
_reflux_select_kind() {
    local insight_count="${1:-0}" insight_target="${2:-}"
    local backlink_count="${3:-0}" backlink_target="${4:-}"
    local promotion_count="${5:-0}" promotion_target="${6:-}"
    local best_kind="" best_count=-1 kind count target

    for kind in insight backlink promotion; do
        case "$kind" in
            insight) count="$insight_count"; target="$insight_target" ;;
            backlink) count="$backlink_count"; target="$backlink_target" ;;
            promotion) count="$promotion_count"; target="$promotion_target" ;;
        esac
        [[ "$count" =~ ^[0-9]+$ ]] || count=0
        [ "$count" -gt 0 ] 2>/dev/null || continue
        [ -n "$target" ] && [ "$target" != "-" ] || continue
        if [ "$count" -gt "$best_count" ]; then
            best_kind="$kind"
            best_count="$count"
        fi
    done

    [ -n "$best_kind" ] || return 1
    printf '%s\n' "$best_kind"
}

_reflux_active_target_owner() {
    local target_path="$1"
    local current_name="$2"
    [ -n "$target_path" ] || return 1

    python3 - "$SCRIPT_DIR" "$target_path" "$current_name" <<'PY'
import os
import sys
import yaml

script_dir, target_path, current_name = sys.argv[1:4]
active_statuses = {"active", "assigned", "acknowledged", "in_progress"}

def load_task(path):
    try:
        with open(path, encoding="utf-8") as f:
            doc = yaml.safe_load(f) or {}
    except Exception:
        return {}
    task = doc.get("task") if isinstance(doc.get("task"), dict) else doc
    return task if isinstance(task, dict) else {}

def paths_from(value):
    if isinstance(value, str):
        return [value.strip()] if value.strip() else []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return []

def normalize(path):
    path = path.replace("\\", "/").strip()
    if not path:
        return ""
    if not os.path.isabs(path):
        path = os.path.join(script_dir, path)
    return os.path.normpath(path)

target_norm = normalize(target_path)
if not target_norm:
    raise SystemExit(1)

task_dir = os.path.join(script_dir, "queue", "tasks")
for filename in sorted(os.listdir(task_dir)) if os.path.isdir(task_dir) else []:
    if not filename.endswith(".yaml") or filename.startswith("."):
        continue
    ninja = filename[:-5]
    if ninja == current_name:
        continue
    task = load_task(os.path.join(task_dir, filename))
    status = str(task.get("status") or "").strip()
    if status not in active_statuses:
        continue
    for peer_target in paths_from(task.get("target_path")):
        if normalize(peer_target) == target_norm:
            print(f"{ninja} status={status} parent_cmd={task.get('parent_cmd') or 'unknown'}")
            raise SystemExit(0)
raise SystemExit(1)
PY
}

_yaml_single_quote_scalar() {
    local value="${1:-}"
    value=${value//\'/\'\'}
    printf "'%s'" "$value"
}

_handle_reflux_auto_deploy() {
    local name="$1"
    local now="$2"
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local task_status idle_elapsed last_file last_dir last elapsed
    local insight_before backlink_before promotion_before total_before first_insight first_backlink first_promotion backlink_status promotion_status
    local insight_after backlink_after promotion_after total_after _after_insight _after_backlink _after_promotion _after_backlink_status _after_promotion_status
    local kind target_path cmd_id deploy_script tmp_task purpose ac1 ac2 ac1_yaml ac2_yaml

    [ -n "$name" ] || return 1

    if _training_pipeline_has_work; then
        unset "REFLUX_IDLE_FIRST_SEEN[$name]"
        log "REFLUX-AUTO-SKIP: $name production pipeline has pending work"
        return 1
    fi

    if [ -f "$task_file" ]; then
        task_status=$(yaml_field_get "$task_file" "status")
        case "$task_status" in
            assigned|acknowledged|in_progress|pending|failed)
                unset "REFLUX_IDLE_FIRST_SEEN[$name]"
                log "REFLUX-AUTO-SKIP: $name task status=${task_status}"
                return 1
                ;;
        esac
    fi

    if [ -z "${REFLUX_IDLE_FIRST_SEEN[$name]:-}" ]; then
        REFLUX_IDLE_FIRST_SEEN[$name]=$now
        log "REFLUX-AUTO-WATCH: $name idle tracking started"
        return 1
    fi

    idle_elapsed=$((now - REFLUX_IDLE_FIRST_SEEN[$name]))
    if [ "$idle_elapsed" -lt "${REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD:-600}" ]; then
        log "REFLUX-AUTO-WAIT: $name idle ${idle_elapsed}s < ${REFLUX_AUTO_DEPLOY_IDLE_THRESHOLD:-600}s"
        return 1
    fi

    last_file=$(_reflux_auto_state_file "$name")
    last_dir="${last_file%/*}"
    [ "$last_dir" = "$last_file" ] && last_dir="."
    if ! mkdir -p "$last_dir"; then
        log "REFLUX-AUTO-SKIP: failed to prepare cooldown state dir for ${name}: ${last_dir}"
        return 1
    fi
    if [ -e "$last_file" ] && [ ! -f "$last_file" ]; then
        log "REFLUX-AUTO-SKIP: cooldown state path is not a regular file for ${name}: ${last_file}"
        return 1
    fi
    last=0
    if [ -f "$last_file" ]; then
        read -r last < "$last_file" || last=0
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    elapsed=$((now - last))
    if [ "$elapsed" -lt "${REFLUX_AUTO_DEPLOY_COOLDOWN:-3600}" ]; then
        log "REFLUX-AUTO-COOLDOWN: $name ${elapsed}s < ${REFLUX_AUTO_DEPLOY_COOLDOWN:-3600}s"
        return 1
    fi

    IFS=$'\t' read -r insight_before backlink_before promotion_before total_before first_insight first_backlink first_promotion backlink_status promotion_status < <(_reflux_inventory_snapshot)
    [ "$first_insight" = "-" ] && first_insight=""
    [ "$first_backlink" = "-" ] && first_backlink=""
    [ "$first_promotion" = "-" ] && first_promotion=""
    if [ "${backlink_status:-ok}" != "ok" ]; then
        log "REFLUX-AUTO-COUNT-WARN: $name zero_backlinks_status=${backlink_status}"
    fi
    if [ "${promotion_status:-ok}" != "ok" ]; then
        log "REFLUX-AUTO-COUNT-WARN: $name promotion_status=${promotion_status}"
    fi
    log "REFLUX-AUTO-INVENTORY-BEFORE: $name insights_pending=${insight_before:-0} zero_backlinks=${backlink_before:-0} promotions=${promotion_before:-0} total=${total_before:-0}"

    if [ "${total_before:-0}" -le 0 ] 2>/dev/null; then
        unset "REFLUX_IDLE_FIRST_SEEN[$name]"
        log "REFLUX-AUTO-SKIP: $name no reflux inventory"
        return 1
    fi

    kind=$(_reflux_select_kind \
        "${insight_before:-0}" "$first_insight" \
        "${backlink_before:-0}" "$first_backlink" \
        "${promotion_before:-0}" "$first_promotion" 2>/dev/null || true)
    case "$kind" in
      insight)
        target_path="queue/insights.yaml"
        purpose="還流在庫自動消化: queue/insights.yaml の pending insight ${first_insight} を三層記憶・semantic-map・既存contextで確認し、resolveまたは必要な実修正/decision_candidateへ整理する"
        ac1="対象insight ${first_insight} を一次情報で確認し、resolveまたは必要な実修正/decision_candidateへ整理する"
        ;;
      backlink)
        target_path="$first_backlink"
        purpose="還流在庫自動消化: backlinksゼロ文書 ${first_backlink} を確認し、適切なsemantic-links/origin/因果リンクを追加して孤立を減らす"
        ac1="対象文書 ${first_backlink} のincoming backlinkゼロ状態を確認し、適切な因果リンクを追加する"
        ;;
      promotion)
        target_path=$(_reflux_promotion_target_path "$first_promotion")
        purpose="還流在庫自動消化: 恒久防御未到達の昇格候補 ${first_promotion} を確認し、Level4以上の防御層・配備注入などへ昇格する"
        ac1="昇格候補 ${first_promotion} を一次情報で確認し、恒久防御(Level4以上)へ引き上げるか、decision_candidateへ整理する"
        ;;
      *)
        unset "REFLUX_IDLE_FIRST_SEEN[$name]"
        log "REFLUX-AUTO-SKIP: $name inventory count positive but no target item"
        return 1
        ;;
    esac
    ac2="作業前後の還流在庫残数(insights_pending/zero_backlinks/promotions/total)を報告YAMLへ記録し、実行証拠を残す"
    ac1_yaml=$(_yaml_single_quote_scalar "$ac1")
    ac2_yaml=$(_yaml_single_quote_scalar "$ac2")

    local active_owner
    active_owner=$(_reflux_active_target_owner "$target_path" "$name" 2>/dev/null || true)
    if [ -n "$active_owner" ]; then
        log "REFLUX-AUTO-SKIP: $name target_path already active (${active_owner}): ${target_path}"
        return 1
    fi

    deploy_script="$SCRIPT_DIR/scripts/deploy_task.sh"
    if [ ! -r "$deploy_script" ]; then
        log "REFLUX-AUTO-SKIP: deploy_task.sh not readable"
        return 1
    fi
    if ! mkdir -p "$STATE_DIR"; then
        log "REFLUX-AUTO-SKIP: failed to prepare state dir for ${name}: ${STATE_DIR}"
        return 1
    fi
    if ! tmp_task=$(mktemp "${STATE_DIR}/reflux_auto_${name}.XXXXXX.yaml"); then
        log "REFLUX-AUTO-SKIP: failed to create temporary task YAML for ${name}"
        return 1
    fi

    cmd_id="cmd_reflux_${kind}_$(date '+%Y%m%d%H%M')_${name}"
    if ! cat > "$tmp_task" <<EOF
task:
  parent_cmd: ${cmd_id}
  task_id: ${cmd_id}_exact
  task_type: exact
  project: infra
  target_path: ${target_path}
  scout_exempt: true
  estimated_minutes: 5
  status: assigned
  purpose: |-
    ${purpose}
  acceptance_criteria:
    - id: AC1
      checks:
        - check: ${ac1_yaml}
    - id: AC2
      checks:
        - check: ${ac2_yaml}
  reflux_inventory_before:
    insights_pending: ${insight_before:-0}
    zero_backlinks: ${backlink_before:-0}
    promotions: ${promotion_before:-0}
    total: ${total_before:-0}
EOF
    then
        rm -f "$tmp_task"
        log "REFLUX-AUTO-SKIP: failed to write temporary task YAML for ${name}"
        return 1
    fi
    if ! python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1], encoding="utf-8"))' "$tmp_task" >/dev/null 2>&1; then
        log "REFLUX-AUTO-SKIP: generated task YAML parse failed for ${name}: ${tmp_task}"
        rm -f "$tmp_task"
        return 1
    fi

    if [ "$kind" = "promotion" ] && ! _reflux_promotion_try_reserve "$first_promotion" "$name"; then
        rm -f "$tmp_task"
        log "REFLUX-AUTO-SKIP: $name lesson already reserved/active/terminal: ${first_promotion}"
        return 1
    fi

    log "REFLUX-AUTO-DEPLOY: $name cmd=${cmd_id} kind=${kind} target=${target_path}"
    if bash "$deploy_script" --direct --yaml "$tmp_task" "$name" "$cmd_id" >> "$SCRIPT_DIR/logs/deploy_reflux_auto.log" 2>&1; then
        rm -f "$tmp_task"
        printf '%s\n' "$now" > "$last_file" 2>/dev/null || true
        unset "REFLUX_IDLE_FIRST_SEEN[$name]"
        IFS=$'\t' read -r insight_after backlink_after promotion_after total_after _after_insight _after_backlink _after_promotion _after_backlink_status _after_promotion_status < <(_reflux_inventory_snapshot)
        log "REFLUX-AUTO-INVENTORY-AFTER: $name insights_pending=${insight_after:-0} zero_backlinks=${backlink_after:-0} promotions=${promotion_after:-0} total=${total_after:-0}"
        log "REFLUX-AUTO-DEPLOY-DONE: $name cmd=${cmd_id} kind=${kind}"
        return 0
    fi

    rm -f "$tmp_task"
    if [ -f "$task_file" ]; then
        local _reflux_partial_parent
        _reflux_partial_parent=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
        if [ "$_reflux_partial_parent" = "$cmd_id" ]; then
            yaml_field_set "$task_file" "task" "status" "idle" >/dev/null 2>&1 || true
            yaml_field_set "$task_file" "task" "report_path" "" >/dev/null 2>&1 || true
            yaml_field_set "$task_file" "task" "report_filename" "" >/dev/null 2>&1 || true
            yaml_field_set "$task_file" "task" "ac_version" "" >/dev/null 2>&1 || true
            yaml_field_set "$task_file" "task" "task_id" "" >/dev/null 2>&1 || true
            log "REFLUX-AUTO-ROLLBACK: $name partial task reset after deploy failure cmd=${cmd_id}"
        fi
    fi
    [ "$kind" != "promotion" ] || _reflux_promotion_release_reservation "$first_promotion" "$name" || true
    log "REFLUX-AUTO-DEPLOY-FAIL: $name cmd=${cmd_id} kind=${kind} (non-blocking)"
    return 1
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
                file = $0
                sub(/^.*file:[[:space:]]*"/, "", file)
                sub(/".*$/, "", file)
                if (file == "" || seen[file]++) next
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
            for (i = n; i >= 1; i--) {
                if (lines[i] == "") continue
                file = lines[i]
                sub(/^.*file:[[:space:]]*"/, "", file)
                sub(/".*$/, "", file)
                if (file == "" || seen[file]++) continue
                total++
                if (lines[i] ~ /result:[[:space:]]*FAIL/) fail++
                if (total >= limit) break
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
    local task_status last_file last_dir last elapsed idle_elapsed cmd_id deploy_script tmp_task
    local training_variant training_target training_purpose

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
    last_dir="${last_file%/*}"
    if [ "$last_dir" = "$last_file" ]; then
        last_dir="."
    fi
    if ! mkdir -p "$last_dir"; then
        log "TRAINING-AUTO-SKIP: failed to prepare cooldown state dir for ${name}: ${last_dir}"
        return 1
    fi
    if [ -e "$last_file" ] && [ ! -f "$last_file" ]; then
        log "TRAINING-AUTO-SKIP: cooldown state path is not a regular file for ${name}: ${last_file}"
        return 1
    fi
    if [ -f "$last_file" ] && [ ! -w "$last_file" ]; then
        log "TRAINING-AUTO-SKIP: cooldown state file is not writable for ${name}: ${last_file}"
        return 1
    fi
    if [ ! -e "$last_file" ] && [ ! -w "$last_dir" ]; then
        log "TRAINING-AUTO-SKIP: cooldown state dir is not writable for ${name}: ${last_dir}"
        return 1
    fi
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
    if [ ! -f "$deploy_script" ] || [ ! -r "$deploy_script" ]; then
        log "TRAINING-AUTO-SKIP: deploy_task.sh not readable"
        return 1
    fi

    cmd_id="cmd_training_L4_auto_$(date '+%Y%m%d%H%M')_${name}"
    if ! mkdir -p "$STATE_DIR"; then
        log "TRAINING-AUTO-SKIP: failed to prepare state dir for ${name}: ${STATE_DIR}"
        return 1
    fi
    if ! tmp_task=$(mktemp "${STATE_DIR}/training_auto_${name}.XXXXXX.yaml"); then
        log "TRAINING-AUTO-SKIP: failed to create temporary task YAML for ${name}"
        return 1
    fi
    training_variant="${TRAINING_AUTO_DEPLOY_VARIANT:-script}"
    case "$training_variant" in
        codd)
            training_target="context/training-cycle.md"
            training_purpose="L4修行: coddパイプライン5ステージを設計・実装・検証し、設計書品質向上を報告YAML一発PASSで完了させる"
            ;;
        *)
            training_target="scripts/ninja_monitor.sh"
            training_purpose="L4修行: 指定スクリプトの改善点3つを特定し、最高インパクト1件を実装し、[[リンク]]で知識ネットワークを育て、報告YAMLを一発PASS品質で完成させる"
            ;;
    esac
    if ! cat > "$tmp_task" <<EOF
task:
  parent_cmd: ${cmd_id}
  task_id: ${cmd_id}_training
  task_type: training
  project: infra
  target_path: ${training_target}
  scout_exempt: true
  status: assigned
  purpose: "${training_purpose}"
EOF
    then
        rm -f "$tmp_task"
        log "TRAINING-AUTO-SKIP: failed to write temporary task YAML for ${name}"
        return 1
    fi

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

# ─── 修行完了判定+SKILL.md自動更新トリガー (cmd_3230: Phase3) ───
_trigger_training_completion_check() {
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

    # training taskのみ対象
    local is_training=0
    [[ "$task_type" = "training" ]] && is_training=1
    [[ "$task_id" = *training* ]] && is_training=1
    [ "$is_training" = "1" ] || return 0

    # done/completed状態のみ
    case "$task_status" in
        done|completed) ;;
        *) return 0 ;;
    esac

    [ -n "$task_id" ] || return 0

    # 二重チェック防止
    local key="${name}:${task_id}"
    [ "${TRAINING_COMPLETION_CHECKED[$key]:-}" = "1" ] && return 0

    local check_script="$SCRIPT_DIR/scripts/training_completion_check.sh"
    [ -f "$check_script" ] || return 0

    local result last_line
    result=$(bash "$check_script" --cmd-id "$task_id" --repo-root "$SCRIPT_DIR" 2>&1) || true
    last_line=$(echo "$result" | tail -1)
    log "TRAINING-COMPLETION: $name task=$task_id $last_line"

    TRAINING_COMPLETION_CHECKED[$key]="1"
}

# ─── idle→通知の処理（状態遷移+デバウンス） ───
# 4サブ関数に分割: _handle_post_clear_pending / _handle_deploy_stall /
#                   _handle_idle_notify / _handle_auto_clear
handle_confirmed_idle() {
    local name="$1"

    if _handle_post_clear_pending "$name"; then return; fi
    if _handle_dependency_continuation "$name"; then return; fi
    if _handle_deploy_stall "$name"; then return; fi

    local now
    now=$EPOCHSECONDS
    _clear_stall_tracking_for_completed_idle "$name"
    _handle_idle_notify "$name" "$now"
    _record_training_effect "$name"  # 修行完了時にbefore/after FAIL率を比較記録 (cmd_2767)
    _trigger_training_completion_check "$name"  # 修行完了判定→SKILL.md自動更新 (cmd_3230: Phase3)
    if _handle_reflux_auto_deploy "$name" "$now"; then return; fi
    # 殿裁定(2026-07-15): 本体script面攻略をBats深掘りより優先する。
    if _handle_speed_training_auto_deploy "$name" "$now"; then return; fi
    if _handle_test_speed_auto_deploy "$name"; then return; fi
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
    unset "REFLUX_IDLE_FIRST_SEEN[$name]"
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

    for key in "${!ACTIVE_IDLE_RECOVERY_SENT[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "ACTIVE_IDLE_RECOVERY_SENT[$key]"
    done

    for key in "${!STALL_COUNT[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "STALL_COUNT[$key]"
    done

    for key in "${!DESTRUCTIVE_WARN_LAST[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "DESTRUCTIVE_WARN_LAST[$key]"
    done

    # compound key (agent:cmd_id) の配列: agentが非アクティブなら削除
    # REPORT_DONE_MISMATCH_NOTIFIEDはcmd_idごとに1エントリ蓄積→長期稼働でキー無制限増加
    for key in "${!REPORT_DONE_MISMATCH_NOTIFIED[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "REPORT_DONE_MISMATCH_NOTIFIED[$key]"
    done

    # compound key (agent:task_id) の配列: agentが非アクティブなら削除
    # TRAINING_EFFECT_RECORDEDはtask_idごとに1エントリ蓄積（1日1件ペース）→長期稼働でキー増加
    for key in "${!TRAINING_EFFECT_RECORDED[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "TRAINING_EFFECT_RECORDED[$key]"
    done

    # compound key (agent:task_id) の配列: agentが非アクティブなら削除
    # TRAINING_COMPLETION_CHECKEDはtask_idごとに1エントリ蓄積（cmd_3230で追加、L622修正後に導入されたため
    # 本関数の対象漏れ→長期稼働でキー無制限増加。TRAINING_EFFECT_RECORDEDと同一の蓄積パターン）
    for key in "${!TRAINING_COMPLETION_CHECKED[@]}"; do
        agent_part="${key%%:*}"
        [ -z "${active[$agent_part]}" ] && unset "TRAINING_COMPLETION_CHECKED[$key]"
    done
}

# Codex background terminalの実子孫processが進行中かをfail-closedで判定。
_pane_has_active_background_compute() {
    local target="$1" pane_pid pane_tty capture snapshot_a snapshot_b
    pane_pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null) || return 1
    pane_tty=$(tmux display-message -t "$target" -p '#{pane_tty}' 2>/dev/null) || return 1
    [[ "$pane_pid" =~ ^[0-9]+$ ]] && [ -n "$pane_tty" ] || return 1
    capture=$(tmux capture-pane -p -t "$target" -S -80 2>/dev/null) || return 1
    printf '%s\n' "$capture" | grep -Eqi 'Wait(ed|ing) for background terminal' || return 1
    snapshot_a=$(ps -eo pid=,ppid=,tty=,stat=,time= 2>/dev/null) || return 1
    sleep "${STALL_CPU_SAMPLE_SEC:-1}"
    snapshot_b=$(ps -eo pid=,ppid=,tty=,stat=,time= 2>/dev/null) || return 1
    PANE_BG_ROOT_PID="$pane_pid" PANE_BG_TTY="${pane_tty#/dev/}" python3 - "$snapshot_a" "$snapshot_b" <<'PY'
import os, sys
root = int(os.environ["PANE_BG_ROOT_PID"])
pane_tty = os.environ["PANE_BG_TTY"]
def parse(text):
    rows = {}
    for line in text.splitlines():
        parts = line.split(None, 4)
        if len(parts) == 5:
            rows[int(parts[0])] = (int(parts[1]), parts[2], parts[3], parts[4])
    return rows
def cpu_seconds(value):
    fields = [int(v) for v in value.split(":")]
    return fields[-1] + fields[-2] * 60 + (fields[-3] * 3600 if len(fields) == 3 else 0)
a, b = parse(sys.argv[1]), parse(sys.argv[2])
descendants = {root}
changed = True
while changed:
    changed = False
    for pid, row in b.items():
        if row[0] in descendants and pid not in descendants:
            descendants.add(pid); changed = True
for pid in descendants - {root}:
    if pid not in a or pid not in b:
        continue
    _ppid, tty, state, cpu_b = b[pid]
    if tty not in ("?", pane_tty) or state.startswith(("Z", "X")):
        continue
    if state.startswith(("R", "D")) or cpu_seconds(cpu_b) > cpu_seconds(a[pid][3]):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

# ─── 停滞検知（assigned/acknowledged/in_progress+idle） ───
# 忍者がタスク受領後にペインがidle状態のまま放置された場合、家老に通知
# 閾値: assigned=15分, acknowledged=10分, in_progress=20分(progress未更新時)
_run_dead_pane_recovery() {
    local agent_name="$1"
    bash "$SCRIPT_DIR/scripts/respawn_dead_agent.sh" "$agent_name"
}

# deploy/stall graceは生きているCLIの起動待ちにだけ適用する。
# active taskのdead paneはgraceより先にSSOT経由で復旧する。
recover_dead_active_pane() {
    local agent_name="$1" status="$2" pane_target="$3"
    case "$status" in
        assigned|acknowledged|in_progress) ;;
        *) return 1 ;;
    esac
    [ -n "$pane_target" ] || return 1

    local pane_dead
    pane_dead=$(tmux display-message -t "$pane_target" -p '#{pane_dead}' 2>/dev/null || echo "0")
    [ "$pane_dead" = "1" ] || return 1

    log "ACTIVE-DEAD-RECOVERY: $agent_name status=$status pane_dead=1 recovery=respawn_dead_agent"
    if ! _run_dead_pane_recovery "$agent_name"; then
        log "ACTIVE-DEAD-RECOVERY-BLOCK: $agent_name status=$status pane remained dead or recovery failed"
        return 2
    fi
    pane_dead=$(tmux display-message -t "$pane_target" -p '#{pane_dead}' 2>/dev/null || echo "1")
    if [ "$pane_dead" != "0" ]; then
        log "ACTIVE-DEAD-RECOVERY-BLOCK: $agent_name status=$status post_recovery_dead=$pane_dead"
        return 2
    fi
    log "ACTIVE-DEAD-RECOVERY-PASS: $agent_name status=$status pane_dead=0"
    return 0
}

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
    # 意図的停止は status を壊さず、明示フラグ+理由+遮断元cmdの3点契約で表す。
    local deployed_at_val last_progress stall_detection_paused pause_reason paused_by_cmd
    IFS='|' read -r task_id deployed_at_val last_progress stall_detection_paused pause_reason paused_by_cmd < <(awk '
        BEGIN { t=""; da=""; pa=""; sp=""; pr=""; pb="" }
        /^[ \t]*subtask_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
        /^[ \t]*task_id:/ && !/^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
        /^[ \t]*_ac_task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
        /^[ \t]*cmd_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
        /^[ \t]*deployed_at:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); da=v }
        /^[ \t]*progress_updated_at:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); pa=v }
        /^[ \t]*stall_detection_paused:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); sp=tolower(v) }
        /^[ \t]*pause_reason:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); pr=v }
        /^[ \t]*paused_by_cmd:/ { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); pb=v }
        END { print t "|" da "|" pa "|" sp "|" pr "|" pb }
    ' "$task_file")

    # Ghost Filter: task_id空のSTALL誤検知を排除(cmd_1150)
    if [ -z "$task_id" ]; then
        log "STALL-GHOST: $name has status=${status} but empty task_id — skipping stall detection"
        return
    fi

    # Evidence wait is an explicit progressing state.  Keep the task active,
    # clear any prior stall clock, and do not run the pending-report gate.
    # Conversely, an already-qualified PASS terminal converges immediately
    # through the existing fingerprint/task-id checked AUTO-DONE transaction.
    local active_report active_report_state
    active_report=$(find_matching_report_file "$name" 2>/dev/null || true)
    if [ -n "$active_report" ] && [ -f "$active_report" ]; then
        active_report_state=$(report_monitor_state "$active_report" 2>/dev/null || printf 'report_pending')
        case "$active_report_state" in
            awaiting_evidence)
                unset "STALL_FIRST_SEEN[$name]"
                log "STALL-AWAITING-EVIDENCE: $name task=$task_id report=$(basename "$active_report") progressing=true"
                return
                ;;
            pass_terminal)
                if check_and_update_done_task "$name"; then
                    unset "STALL_FIRST_SEEN[$name]"
                    log "STALL-PASS-AUTO-DONE: $name task=$task_id report=$(basename "$active_report")"
                    return
                fi
                ;;
        esac
    fi

    # dead paneはdeploy graceより優先。復旧を試みたサイクルは
    # PASS/BLOCKのどちらでも後段のgraceへ流さず、次サイクルで再評価する。
    local stall_pane_target="${PANE_TARGETS[$name]:-}"
    local dead_recovery_rc
    if recover_dead_active_pane "$name" "$status" "$stall_pane_target"; then
        dead_recovery_rc=0
    else
        dead_recovery_rc=$?
    fi
    if [ "$dead_recovery_rc" -eq 0 ] || [ "$dead_recovery_rc" -eq 2 ]; then
        unset "STALL_FIRST_SEEN[$name]"
        return "$dead_recovery_rc"
    fi

    # 本番DB排他など、家老が意図的に一時停止した作業を異常STALLと誤認しない。
    # フラグだけで監視を止められないよう、理由と遮断元cmdも必須にする。
    case "$stall_detection_paused" in
        true|yes|1)
            if [ -n "$pause_reason" ] && [ -n "$paused_by_cmd" ]; then
                local paused_stall_key="${name}:${task_id}"
                unset "STALL_FIRST_SEEN[$name]"
                unset "STALL_NOTIFIED[$paused_stall_key]"
                unset "STALL_COUNT[$paused_stall_key]"
                log "STALL-PAUSED: $name task=$task_id blocked_by=$paused_by_cmd reason=$pause_reason"
                return
            fi
            log "STALL-PAUSE-INVALID: $name task=$task_id requires pause_reason and paused_by_cmd; monitoring remains active"
            ;;
    esac

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

    if _pane_has_active_background_compute "$target"; then
        unset "STALL_FIRST_SEEN[$name]"
        log "STALL-ACTIVE-COMPUTE: $name pane=$target has progressing background process"
        return
    fi

    # in_progress without any progress timestamp is not evidence of forward
    # motion.  The old path waited the full in_progress_stall_min before the
    # first recovery nudge (cmd_4043: about 29 minutes idle).  Re-send once on
    # first idle observation; a current progress timestamp, evidence wait, or
    # active background compute has already returned above.
    if [ "$status" = "in_progress" ] && [ -z "$last_progress" ]; then
        local no_progress_key="${name}:${task_id}:initial_no_progress"
        if [ "${ACTIVE_IDLE_RECOVERY_SENT[$no_progress_key]:-}" != "1" ]; then
            ACTIVE_IDLE_RECOVERY_SENT[$no_progress_key]="1"
            send_inbox_message "$name" "in_progressだがprogress_updated_at未記録のidleを検知。task YAMLを再確認し、作業再開またはprogress更新せよ。" task_assigned
            log "STALL-NO-PROGRESS-RESEND: $name task=$task_id first_idle=true"
        else
            log "STALL-NO-PROGRESS-RESEND-SKIP: $name task=$task_id duplicate"
        fi
    fi

    # idle状態 → 停滞追跡開始 or 経過確認
    local now
    now=$EPOCHSECONDS
    if [ -z "${STALL_FIRST_SEEN[$name]}" ]; then
        STALL_FIRST_SEEN[$name]=$now
        log "STALL-WATCH: $name has ${status} task $task_id and is idle (tracking started)"
        evaluate_active_idle_report_recovery "$name" "$task_file" "$status" "$task_id" 0 "$STALL_THRESHOLD_MIN"
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

    evaluate_active_idle_report_recovery "$name" "$task_file" "$status" "$task_id" "$elapsed_min" "$threshold"

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
            notify_karo_throttled stall_escalate "$name" "$escalate_message"
        fi

        if [ "$status" = "in_progress" ]; then
            send_inbox_message "$name" "in_progress停滞を検知。task YAMLを再確認し、作業を再開せよ。" task_assigned
            log "STALL-RECOVERY-SEND: resent task_assigned to ${name} for ${task_id}"
        fi

        unset "STALL_FIRST_SEEN[$name]"
    fi
}

# A terminal report is itself a durable outbox.  Repair a publish interrupted
# after the atomic report replace but before inbox persistence (pane death,
# dispatcher exit, or monitor respawn). inbox_write's structured fingerprint
# transaction makes this safe on every cycle and repairs a missing review child.
repair_terminal_report_outboxes() {
    local name task_file report_path report_full status task_status
    for name in "${NINJA_NAMES[@]}"; do
        task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
        [ -f "$task_file" ] || continue
        task_status=$(yaml_field_get "$task_file" status "" 2>/dev/null || true)
        # inbox_write publishes child review before the atomic done transition.
        # Therefore only a still-active task can inhabit the crash window.
        # Terminal/idle tasks are a steady state and must incur zero publishers.
        case "$task_status" in assigned|acknowledged|in_progress) ;; *) continue ;; esac
        report_path=$(yaml_field_get "$task_file" report_path "" 2>/dev/null || true)
        [ -n "$report_path" ] || continue
        [[ "$report_path" = /* ]] && report_full="$report_path" || report_full="$SCRIPT_DIR/$report_path"
        if [ ! -f "$report_full" ]; then
            report_full="$SCRIPT_DIR/queue/archive/reports/${report_path##*/}"
        fi
        [ -f "$report_full" ] || continue
        status=$(yaml_field_get "$report_full" status "" 2>/dev/null || true)
        case "$status" in completed|done) ;; *) continue ;; esac
        bash "${REPORT_OUTBOX_INBOX_WRITE_PATH:-$SCRIPT_DIR/scripts/inbox_write.sh}" karo \
            "${name}報告完了。report=${report_full##*/}" report_received "$name" notify_karo \
            >/dev/null 2>&1 || log "REPORT-OUTBOX-REPAIR-BLOCK: $name report=${report_full##*/}"
    done
}

evaluate_active_idle_report_recovery() {
    local name="$1"
    local task_file="$2"
    local status="$3"
    local task_id="$4"
    local elapsed_min="$5"
    local threshold="$6"

    [ -f "$task_file" ] || return 0

    local parent_cmd report_file report_base gate_output gate_result
    parent_cmd=$(yaml_field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
    [ -n "$parent_cmd" ] || parent_cmd=$(yaml_field_get "$task_file" "cmd_id" "" 2>/dev/null || true)
    [ -n "$parent_cmd" ] || return 0

    report_file=$(find_matching_report_file "$name" 2>/dev/null || true)
    if [ -n "$report_file" ] && [ -f "$report_file" ]; then
        report_base=$(basename "$report_file")
        gate_output=$(bash "$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$report_file" 2>&1) || true
        if echo "$gate_output" | grep -q "^PASS"; then
            gate_result="PASS"
        else
            gate_result="FAIL"
        fi
        log "ACTIVE-IDLE-REPORT-EVAL: ${name} task=${task_id} status=${status} report=${report_base} result=${gate_result} elapsed=${elapsed_min}m output=${gate_output}"

        if [ "$gate_result" != "PASS" ] && [ "$elapsed_min" -ge "$threshold" ]; then
            local report_key="${name}:${task_id}:report_format"
            if [ "${ACTIVE_IDLE_RECOVERY_SENT[$report_key]:-}" != "1" ]; then
                ACTIVE_IDLE_RECOVERY_SENT[$report_key]="1"
                send_inbox_message "$name" "idle状態で報告YAML未完了を検知。gate_report_formatを確認し、報告YAMLを修正して家老へ再通知せよ。対象: ${report_base}" report_format_fix
                log "ACTIVE-IDLE-REPORT-RENOTIFY: ${name} task=${task_id} report=${report_base}"
            else
                log "ACTIVE-IDLE-REPORT-RENOTIFY-SKIP: ${name} task=${task_id} duplicate"
            fi
        fi
    fi

    if [ "$elapsed_min" -lt "$threshold" ]; then
        return 0
    fi

    local project_id project_path uncommitted_files commit_key uncommit_file_list
    project_id=$(yaml_field_get "$task_file" "project" "" 2>/dev/null || true)
    project_path="$SCRIPT_DIR"
    if [ -n "$project_id" ]; then
        local looked_up
        looked_up=$(grep -A5 "id: ${project_id}$" "$SCRIPT_DIR/config/projects.yaml" 2>/dev/null | grep "path:" | head -1 | sed 's/.*path: *"\([^"]*\)"/\1/')
        [ -n "$looked_up" ] && [ -d "$looked_up" ] && project_path="$looked_up"
    fi
    uncommitted_files=$(cd "$project_path" && { git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } | sort -u || true)
    [ -n "$uncommitted_files" ] || return 0

    commit_key="${name}:${task_id}:uncommitted"
    if [ "${ACTIVE_IDLE_RECOVERY_SENT[$commit_key]:-}" = "1" ]; then
        log "ACTIVE-IDLE-COMMIT-RENOTIFY-SKIP: ${name} task=${task_id} duplicate"
        return 0
    fi

    ACTIVE_IDLE_RECOVERY_SENT[$commit_key]="1"
    uncommit_file_list=$(echo "$uncommitted_files" | tr '\n' ' ')
    send_inbox_message "$name" "idle状態だが未commitファイルあり: ${uncommit_file_list}。git add + git commitを完了し、報告YAMLにcommit_hashを記録せよ。" uncommitted_block
    log "ACTIVE-IDLE-COMMIT-RENOTIFY: ${name} task=${task_id} files=${uncommit_file_list}"
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

    # awk置換: python3起動コスト削減(WSL2 ~150ms/回 → <1ms) — dict形式対応
    # dict形式: commands:\n  cmd_xxx:\n    status: pending\n    timestamp: ...\n    delegated_at: ...
    # defer契約も同じsnapshotから返し、stale判定と通知世代を一次状態へ束縛する。
    awk '
    function emit() {
        if (cmd_id != "" && status == "pending") {
            print cmd_id "|" timestamp "|" delegated_at "|" deferred_until "|" defer_reason "|" restart_condition
        }
    }
    /^  [[:alnum:]_]+:$/ {
        emit()
        v = $0; sub(/^  /, "", v); sub(/:$/, "", v); gsub(/["'"'"'[:space:]]/, "", v)
        cmd_id = v; status = ""; timestamp = ""; delegated_at = ""
        deferred_until = ""; defer_reason = ""; restart_condition = ""
        next
    }
    /^    status:/ {
        v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/["'"'"'[:space:]]/, "", v)
        status = v; next
    }
    /^    timestamp:/ {
        v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/["\\]/, "", v)
        timestamp = v; next
    }
    /^    delegated_at:/ {
        v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/["\\]/, "", v)
        delegated_at = v; next
    }
    /^    deferred_until:/ {
        v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/["\\]/, "", v)
        deferred_until = v; next
    }
    /^    defer_reason:/ {
        v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/^["'"'']|["'"'']$/, "", v)
        defer_reason = v; next
    }
    /^    restart_condition:/ {
        v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); gsub(/^["'"'']|["'"'']$/, "", v)
        restart_condition = v; next
    }
    END { emit() }
    ' "$cmd_file"
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
    local -A _current_pending=()  # 現サイクルのpending cmd集合 (STALE_CMD_NOTIFIEDプルーン用)

    while IFS='|' read -r cmd_id cmd_timestamp _cmd_delegated_at deferred_until defer_reason restart_condition; do
        [ -z "$cmd_id" ] && continue
        [ -z "$cmd_timestamp" ] && continue
        _current_pending["$cmd_id"]=1

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

        # 意図的deferは期限到来または再開条件成立までstaleではない。
        # restart_conditionは正本writerが成立時に true/met/ready/satisfied へ遷移させる契約。
        local defer_deadline_epoch=0 restart_met=0
        if [ -n "$deferred_until" ]; then
            defer_deadline_epoch=$(date -d "$deferred_until" +%s 2>/dev/null || echo 0)
            [[ "$defer_deadline_epoch" =~ ^[0-9]+$ ]] || defer_deadline_epoch=0
        fi
        case "${restart_condition,,}" in
            true|met|ready|satisfied) restart_met=1 ;;
        esac
        if [ -n "$deferred_until$defer_reason$restart_condition" ] && \
           [ "$restart_met" -eq 0 ] && \
           { [ "$defer_deadline_epoch" -eq 0 ] || [ "$now" -lt "$defer_deadline_epoch" ]; }; then
            log "STALE-CMD-DEFERRED: ${cmd_id} intentional defer active until=${deferred_until:-unspecified} restart=${restart_condition:-unspecified}"
            continue
        fi

        # subtask存在確認: queue/tasks/*.yaml の parent_cmd を照合 (L335: -Fw必須)
        if grep -Fwl "parent_cmd: ${cmd_id}" "$SCRIPT_DIR/queue/tasks/"*.yaml >/dev/null 2>&1; then
            continue
        fi

        local elapsed_hour
        elapsed_hour=$((elapsed_sec / 3600))
        local msg="${cmd_id}が${elapsed_hour}時間pendingのまま。将軍に確認せよ"

        # 同一一次状態は永久dedupeし、期限・条件・理由等の変更だけを新世代とする。
        local notify_generation
        notify_generation=$(printf '%s\0' "$cmd_id" "$cmd_timestamp" "$_cmd_delegated_at" \
            "$deferred_until" "$defer_reason" "$restart_condition" | sha256sum | awk '{print $1}')
        if [ "${STALE_CMD_NOTIFIED[$cmd_id]:-}" = "$notify_generation" ]; then
            continue
        fi

        log "STALE-CMD: ${cmd_id} pending ${elapsed_hour}h with no subtasks, notifying karo"
        if bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$msg" stale_cmd ninja_monitor >> "$LOG" 2>&1; then
            STALE_CMD_NOTIFIED[$cmd_id]="$notify_generation"
        else
            log "ERROR: Failed to send stale cmd notification for ${cmd_id}"
        fi
    done < <(list_pending_cmds_cached)

    # pending_cmdsから外れたcmdのSTALE_CMD_NOTIFIEDエントリを削除 (check_undeployed_cmds同パターン)
    local _stale_cmd_id
    for _stale_cmd_id in "${!STALE_CMD_NOTIFIED[@]}"; do
        if [ -z "${_current_pending[$_stale_cmd_id]:-}" ]; then
            unset "STALE_CMD_NOTIFIED[$_stale_cmd_id]"
            log "STALE-CMD-RESOLVED: ${_stale_cmd_id} no longer pending, pruned from STALE_CMD_NOTIFIED"
        fi
    done
}

check_undeployed_cmds() {
    local now
    now=$EPOCHSECONDS
    local -A current_pending=()

    while IFS='|' read -r cmd_id _cmd_timestamp delegated_at _deferred_until _defer_reason _restart_condition; do
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
    local now
    now=$EPOCHSECONDS

    # 家老がbusyならスキップ（作業中は割り込み不要）
    if ! check_idle "$KARO_PANE" "karo"; then
        return
    fi

    # 現在のpending cmd集合を収集し、新規のみ通知
    local -a current_ids=()

    while IFS='|' read -r cmd_id cmd_timestamp _cmd_delegated_at _deferred_until _defer_reason _restart_condition; do
        [ -z "$cmd_id" ] && continue

        if [ -n "$cmd_timestamp" ] && [ "${KARO_PENDING_CMD_GRACE_SEC:-0}" -gt 0 ]; then
            local cmd_epoch
            cmd_epoch=$(date -d "$cmd_timestamp" +%s 2>/dev/null || echo "0")
            if [[ "$cmd_epoch" =~ ^[0-9]+$ ]] && [ "$cmd_epoch" -gt 0 ]; then
                local pending_age
                pending_age=$((now - cmd_epoch))
                if [ "$pending_age" -ge 0 ] && [ "$pending_age" -lt "$KARO_PENDING_CMD_GRACE_SEC" ]; then
                    log "PENDING-CMD-GRACE: ${cmd_id} age=${pending_age}s < ${KARO_PENDING_CMD_GRACE_SEC}s; waiting for cmd_delegate/cmd_new"
                    continue
                fi
            fi
        fi

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
        /^[[:space:]]*[●•]?[[:space:]]*Bash\(/ { in_cmd=1 }
        in_cmd && /⎿/ { in_cmd=0; next }
        !in_cmd { next }
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

# ─── 未読メッセージのcount/fingerprint算出 (cmd_255) ───
# unread msg ID集合をキー化(L029)。サイクル内ではcount/fingerprintを同時キャッシュする。
_get_unread_summary_cached() {
    local inbox_file="$1"
    local count_var="${2:-}"
    local fp_var="${3:-}"
    local _ius_agent_name _ius_current_cycle _ius_summary _ius_count _ius_ids _ius_fp

    _ius_agent_name="${inbox_file##*/}"
    _ius_agent_name="${_ius_agent_name%.yaml}"
    _ius_current_cycle="${cycle:-0}"

    if [ "$_ius_current_cycle" != "${_INBOX_COUNT_CACHE_CYCLE:-}" ]; then
        _INBOX_COUNT_CACHE=()
        _INBOX_FP_CACHE=()
        _INBOX_COUNT_CACHE_CYCLE=$_ius_current_cycle
    fi

    if [ ! -f "$inbox_file" ]; then
        [ -n "$count_var" ] && printf -v "$count_var" '%s' "0"
        [ -n "$fp_var" ] && printf -v "$fp_var" '%s' ""
        return
    fi

    if [ "${_INBOX_COUNT_CACHE[$_ius_agent_name]+set}" = "set" ] && [ "${_INBOX_FP_CACHE[$_ius_agent_name]+set}" = "set" ]; then
        [ -n "$count_var" ] && printf -v "$count_var" '%s' "${_INBOX_COUNT_CACHE[$_ius_agent_name]}"
        [ -n "$fp_var" ] && printf -v "$fp_var" '%s' "${_INBOX_FP_CACHE[$_ius_agent_name]}"
        return
    fi

    _ius_summary=$(awk '
        function leading_spaces(line,    i, ch) {
            for (i = 1; i <= length(line); i++) {
                ch = substr(line, i, 1)
                if (ch != " ") return i - 1
            }
            return length(line)
        }
        function direct_field(line, key, item_indent,    indent, pattern) {
            pattern = "^[[:space:]]*" key ":[[:space:]]*"
            if (line ~ ("^-[[:space:]]*" key ":[[:space:]]*")) return 1
            if (line !~ pattern) return 0
            indent = leading_spaces(line)
            return (indent == item_indent + 2)
        }
        function field_value(line, key,    v) {
            v = line
            sub(/^-[[:space:]]*/, "", v)
            sub("^[[:space:]]*" key ":[[:space:]]*", "", v)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            gsub(/^["\047]+|["\047]+$/, "", v)
            return v
        }
        /^[[:space:]]*-[[:space:]]/ {
            item_indent = leading_spaces($0)
            current_id = ""
        }
        direct_field($0, "id", item_indent) {
            current_id = field_value($0, "id")
            gsub(/[[:space:]]/, "", current_id)
            next
        }
        direct_field($0, "read", item_indent) {
            read_value = tolower(field_value($0, "read"))
            if (read_value == "false") {
                count++
                if (current_id != "") ids = ids current_id "|"
            }
        }
        END { printf "%d\t%s\n", count + 0, ids }
    ' "$inbox_file" 2>/dev/null || printf '0\t\n')

    _ius_count="${_ius_summary%%$'\t'*}"
    _ius_ids="${_ius_summary#*$'\t'}"
    [[ "$_ius_count" =~ ^[0-9]+$ ]] || _ius_count=0
    _ius_fp=""
    if [ "$_ius_count" -gt 0 ] 2>/dev/null && [ -n "$_ius_ids" ]; then
        _ius_fp=$(printf '%s' "$_ius_ids" | md5sum | cut -d' ' -f1)
    fi

    _INBOX_COUNT_CACHE[$_ius_agent_name]=$_ius_count
    _INBOX_FP_CACHE[$_ius_agent_name]=$_ius_fp
    [ -n "$count_var" ] && printf -v "$count_var" '%s' "$_ius_count"
    [ -n "$fp_var" ] && printf -v "$fp_var" '%s' "$_ius_fp"
}

# $1: inbox_file path
# 出力: md5 hash文字列（未読0件なら空文字）
get_unread_fingerprint() {
    local inbox_file="$1"
    local _count fp
    _get_unread_summary_cached "$inbox_file" _count fp

    echo "$fp"
}

# ─── 未読放置検知+再nudge (cmd_188→cmd_255状態遷移化) ───
# 状態遷移ベース: fingerprint変化時のみ即送信、同一fingerprint時はバックオフ安全網
# inbox_watcherとの二重経路増幅(L029)を抑止する

# ─── count_unread_messages サイクル内キャッシュ ───
# check_inbox_renudge/update_inbox_counts が同一サイクル内で
# 別々にawk+NTFSアクセスするのを防ぐ。cycleが変わった時だけ再読込。
# WSL2 NTFS I/Oコスト(L508)削減: 17回→9回/cycle（karo+gunshi+6忍者+shogun）
count_unread_messages_cached() {
    local inbox_file="$1"
    local out_var="${2:-}"
    local count _fp

    _get_unread_summary_cached "$inbox_file" count _fp
    if [ -n "$out_var" ]; then
        printf -v "$out_var" '%s' "$count"
    else
        echo "$count"
    fi
}

check_inbox_renudge() {
    local all_agents=("shogun" "karo" "gunshi" "${NINJA_NAMES[@]}")
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

        # 未読メッセージ数をカウント（サイクル内キャッシュ使用）
        local unread_count
        count_unread_messages_cached "$inbox_file" unread_count
        # 防御: 非数値は0に強制変換
        [[ ! "$unread_count" =~ ^[0-9]+$ ]] && unread_count=0

        # 未読0 → 家老pending workチェック後にスキップ
        if [ "$unread_count" -eq 0 ]; then
            # 家老専用: inbox未読0でもpending work(忍者done/delegated未配備)があればnudge
            if [ "$name" = "karo" ]; then
                local _reviewed_report_cmds=""
                if [ -f "$SCRIPT_DIR/logs/gunshi_review_log.yaml" ]; then
                    _reviewed_report_cmds="|$(awk '
                        function emit() {
                            if (cmd != "" && review_type == "report" && verdict != "") print cmd
                        }
                        /^[[:space:]]*-[[:space:]]*cmd_id:/ {
                            emit()
                            cmd=$0; sub(/^[^:]*:[[:space:]]*/, "", cmd); gsub(/["'\''[:space:]]/, "", cmd)
                            review_type=""; verdict=""
                            next
                        }
                        /^[[:space:]]*review_type:/ {
                            review_type=$0; sub(/^[^:]*:[[:space:]]*/, "", review_type); gsub(/["'\''[:space:]]/, "", review_type)
                            next
                        }
                        /^[[:space:]]*verdict:/ {
                            verdict=$0; sub(/^[^:]*:[[:space:]]*/, "", verdict); gsub(/["'\''[:space:]]/, "", verdict)
                            next
                        }
                        END { emit() }
                    ' "$SCRIPT_DIR/logs/gunshi_review_log.yaml" 2>/dev/null | paste -sd'|' -)|"
                fi
                # cmd_karo_hotfix_pending_work_generation_dedupe_202607121023 AC2:
                # 世代fingerprintを求めるため、pending判定を「最初の1件で打ち切り」から
                # 「全pending対象を収集」へ変更する(通知要否のtrue/falseだけでなく、
                # worker+task_id+parent_cmd+status+report内容を全件集めてhash化する)。
                # 速度RC(2026-07-12 11:08 家老指摘、殿定義: 速度もバグ判定対象):
                # report_filename解決にresolve_expected_report_file(=yaml_field_get再走査)を
                # pending件数分呼ぶとprocess数が線形増加しBEFORE比3.9倍まで悪化した。
                # report_filenameはtask_id等と同じ単一awk一括スキャンで抽出し(yaml_field_get
                # 再走査ゼロ化)、report内容hashはpendingのentry収集後にまとめて1回のmd5sum
                # 呼出し(複数path一括)で計算してprocess数を最小化する。
                # L4最適化: for+awk×N(最大6プロセス) → awk×1の全ファイル一括スキャン(WSL2プロセス起動コスト削減 L511)
                # FNR==1で新ファイル開始を検出し前ファイルの結果を出力。ls→compgen -Gに変更(エラー出力防止)
                local -a _kentry_lines=()
                local -a _kreport_paths_needed=()
                while IFS=$'\t' read -r _kworker _kts _kpcmd _ktid _kreportfn; do
                    [ -n "$_kworker" ] || continue
                    # AC2(cmd_karo_hotfix_failed_report_clear_notify_gap): done専用の判定だと
                    # failed報告(cmd_3861実例)がpending work検知から永久に漏れる。done/failed両対象化。
                    [[ "$_kts" = "done" || "$_kts" = "failed" ]] || continue
                    if [ -z "$_kpcmd" ] || [ "$_kpcmd" = "none" ]; then
                        log "KARO-PENDING-SKIP-NO-PARENT-CMD: done task has no parent_cmd"
                        continue
                    fi
                    # GATE CLEAR済みならpending workではない
                    if compgen -G "$SCRIPT_DIR/queue/archive/cmds/${_kpcmd}_completed_"* > /dev/null 2>&1; then
                        continue  # archived=GATE CLEAR済み
                    fi
                    if awk -F '\t' -v cmd="$_kpcmd" '$2 == cmd && $3 == "CLEAR" { found=1; exit } END { exit(found ? 0 : 1) }' "$SCRIPT_DIR/logs/gate_metrics.log" 2>/dev/null; then
                        log "KARO-PENDING-SKIP-GATE-CLEAR: $_kpcmd already has gate CLEAR"
                        continue
                    fi
                    # report_filenameはresolve_expected_report_file相当のfallbackを
                    # サブプロセスなし(pure bash)で再現する(_kpcmdは既に非空・none以外を確認済み)
                    local _kreport_filename _kreport_path
                    if [ -n "$_kreportfn" ]; then
                        _kreport_filename="$_kreportfn"
                    else
                        _kreport_filename="${_kworker}_report_${_kpcmd}.yaml"
                    fi
                    _kreport_path="$SCRIPT_DIR/queue/reports/${_kreport_filename}"
                    # canonical terminal FAILは軍師reviewの有無にかかわらず未処理workではない。
                    # report不在・未完成・非FAILは終端証拠がないため従来どおりpendingに保つ。
                    if [ "$_kts" = "failed" ] && [ -f "$_kreport_path" ]; then
                        local _kreport_status _kreport_verdict
                        read -r _kreport_status _kreport_verdict < <(awk '
                            /^status:/ && status=="" { status=$0; sub(/^[^:]*:[[:space:]]*/, "", status); gsub(/["'\''[:space:]]/, "", status) }
                            /^verdict:/ && verdict=="" { verdict=$0; sub(/^[^:]*:[[:space:]]*/, "", verdict); gsub(/["'\''[:space:]]/, "", verdict) }
                            END { print status, verdict }
                        ' "$_kreport_path" 2>/dev/null)
                        local _kreport_terminal_state
                        _kreport_terminal_state=$(report_terminal_state "$_kreport_path")
                        if [ "$_kreport_terminal_state" = "CLOSED_BLOCKED" ]; then
                            log "KARO-PENDING-SKIP-CLOSED-BLOCKED: $_kpcmd task=failed report=completed verdict=${_kreport_verdict:-unknown}"
                            continue
                        fi
                    fi
                    # 軍師review済みはレビュー工程の終端であり、cmd完了工程の終端ではない。
                    # pending集合へ残して既存の世代dedupeで家老へ完了処理を一度だけ要求する。
                    # GATE CLEAR/archive済みは上段で除外されるため、clear後の再通知は発生しない。
                    if [[ "$_reviewed_report_cmds" == *"|$_kpcmd|"* ]]; then
                        log "KARO-PENDING-REVIEWED-COMPLETION: $_kpcmd has gunshi report review; requesting cmd completion"
                    fi
                    _kentry_lines+=("${_kworker}|${_ktid}|${_kpcmd}|${_kts}|${_kreport_path}")
                    [ -f "$_kreport_path" ] && _kreport_paths_needed+=("$_kreport_path")
                done < <(awk '
                    function emit() {
                        if (fname != "") {
                            w = fname
                            sub(/^.*\//, "", w)
                            sub(/\.yaml$/, "", w)
                            print w "\t" s "\t" p "\t" t "\t" rf
                        }
                    }
                    FNR == 1 { emit(); fname = FILENAME; s=""; p=""; t=""; rf="" }
                    /^[[:space:]]*status:/ && s=="" { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'\''[:space:]]/, "", v); s=v }
                    /^[[:space:]]*parent_cmd:/ && p=="" { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'\''[:space:]]/, "", v); p=v }
                    /^[[:space:]]*task_id:/ && t=="" { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'\''[:space:]]/, "", v); t=v }
                    /^[[:space:]]*report_filename:/ && rf=="" { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'\''[:space:]]/, "", v); rf=v }
                    END { emit() }
                ' "$SCRIPT_DIR"/queue/tasks/*.yaml 2>/dev/null)

                # 存在するreport全件を1回のmd5sum呼出しでまとめてhash化(pending件数分のprocess増加を回避)
                local -A _kreport_hash_map=()
                if [ ${#_kreport_paths_needed[@]} -gt 0 ]; then
                    while IFS= read -r _khashline; do
                        [ -n "$_khashline" ] || continue
                        _kreport_hash_map["${_khashline:34}"]="${_khashline:0:32}"
                    done < <(md5sum "${_kreport_paths_needed[@]}" 2>/dev/null)
                fi

                # 正確性RC(2026-07-12 11:11 家老指摘): 集合fingerprintの元となる並びが
                # queue/tasks/*.yamlのglob順(locale=LC_COLLATE依存)に左右されると、同一の
                # 実pending集合でもlocale差でfpが変わりcanonical不変量が壊れる。忍者は高々
                # 6名でありO(N^2)は無視できるコストのため、追加サブプロセスなしの純bash
                # insertion sortで収集順を固定し、外部sort呼出しを増やさず正確性を確保する。
                local -a _kentry_sorted=()
                local _kcandidate _kinserted _kj
                for _kcandidate in "${_kentry_lines[@]+"${_kentry_lines[@]}"}"; do
                    _kinserted=0
                    for ((_kj=0; _kj<${#_kentry_sorted[@]}; _kj++)); do
                        if [[ "$_kcandidate" < "${_kentry_sorted[_kj]}" ]]; then
                            _kentry_sorted=("${_kentry_sorted[@]:0:_kj}" "$_kcandidate" "${_kentry_sorted[@]:_kj}")
                            _kinserted=1
                            break
                        fi
                    done
                    [ "$_kinserted" -eq 0 ] && _kentry_sorted+=("$_kcandidate")
                done

                local _karo_pending_entries=""
                local _kline _ew _etid _epcmd _ets _erpath _erfp
                for _kline in "${_kentry_sorted[@]+"${_kentry_sorted[@]}"}"; do
                    IFS='|' read -r _ew _etid _epcmd _ets _erpath <<< "$_kline"
                    _erfp="${_kreport_hash_map[$_erpath]:-missing}"
                    _karo_pending_entries="${_karo_pending_entries}${_ew}|${_etid}|${_epcmd}|${_ets}|${_erfp}
"
                done
                if [ -n "$_karo_pending_entries" ]; then
                    local _karo_target="$KARO_PANE"
                    if [ -n "$_karo_target" ] && check_idle "$_karo_target" "karo"; then
                        local _karo_pending_fp
                        _karo_pending_fp=$(printf '%s' "$_karo_pending_entries" | md5sum)
                        _karo_pending_fp="${_karo_pending_fp:0:32}"
                        if _karo_pending_work_already_notified "$_karo_pending_fp"; then
                            log "KARO-PENDING-DEDUPE: generation ${_karo_pending_fp} already notified for this pending set, skipping"
                        else
                            log "KARO-PENDING-INBOX: karo idle with pending work (new generation ${_karo_pending_fp}), sending inbox message"
                            # notify_karo_durableがreturn 0(direct成功またはoutbox永続化成功)の
                            # 場合のみ世代を確定する。return 1(outbox永続化自体が失敗)ならmarkerを
                            # 書かず、次サイクルで同一fpのまま再試行させる(AC3)。
                            if notify_karo_durable pending_work karo "未処理の忍者done/failed報告が残っている。queue/tasks と queue/reports を確認し、レビュー/完了処理/次配備を判断せよ。"; then
                                _karo_pending_work_mark_notified "$_karo_pending_fp"
                            else
                                log "KARO-PENDING-INBOX-RETRY: notify_karo_durable failed to persist (outbox append failed), generation not marked, will retry next cycle"
                            fi
                        fi
                    fi
                else
                    # 集合世代RC: pending集合が0件になった時点でmarkerを消去する。
                    # 消去しないと、後で同一fingerprintの集合が再出現した際に旧世代扱いされ
                    # 通知が漏れる(軍師review/GATE CLEARで一度解消→RC/reopenする実運用を想定)。
                    _karo_pending_work_clear_marker
                fi
            fi
            if [ -n "${RENUDGE_FINGERPRINT[$name]:-}" ] || [ "${RENUDGE_COUNT[$name]:-0}" -gt 0 ]; then
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

        # inbox_watcher owns the durable delivery lease.  Once a generation was
        # pasted, monitor must not create a second delivery path until ACK/set change.
        local watcher_fp="" sent_token=""
        IFS= read -r watcher_fp < "${SHOGUN_STATE_DIR:-/tmp}/inbox_watcher_fingerprint_${name}" 2>/dev/null || true
        sent_token="${SHOGUN_STATE_DIR:-/tmp}/inbox_watcher_sent_${name}_${watcher_fp//[^A-Za-z0-9_.-]/_}"
        if [ -n "$watcher_fp" ] && [ -e "$sent_token" ]; then
            RENUDGE_FINGERPRINT[$name]="$current_fp"
            RENUDGE_COUNT[$name]=1
            continue
        fi

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
    # L4-R?: 最適化版 — set-option "--" + show-options の2往復(~12ms)とcli_profile_getサブシェル(~156ms)を削除
    # 変更前: set-option "--" → show-options(get "--") → capture-pane → cli_profile_get×2(subshell) → set-option N%
    # 変更後: capture-pane → キャッシュ参照(or cli_profile_get初回のみ) → set-option N%
    local output ctx_num ctx_pattern ctx_mode
    output=$(tmux capture-pane -t "$pane_target" -p -J -S -30 2>/dev/null)

    if [ -n "$agent_name" ]; then
        if [[ -n "${_CTX_PROFILE_PATTERN_CACHE[$agent_name]+x}" ]]; then
            # キャッシュヒット: サブシェル不要
            ctx_pattern="${_CTX_PROFILE_PATTERN_CACHE[$agent_name]}"
            ctx_mode="${_CTX_PROFILE_MODE_CACHE[$agent_name]}"
        else
            # キャッシュミス: サブシェルで取得しキャッシュに保存(次回以降0ms)
            ctx_pattern=$(cli_profile_get "$agent_name" "ctx_pattern" 2>/dev/null || echo "")
            ctx_mode=$(cli_profile_get "$agent_name" "ctx_mode" 2>/dev/null || echo "")
            _CTX_PROFILE_PATTERN_CACHE[$agent_name]="$ctx_pattern"
            _CTX_PROFILE_MODE_CACHE[$agent_name]="$ctx_mode"
        fi
    fi

    if [ -n "$ctx_pattern" ]; then
        if [ "$ctx_mode" = "usage" ]; then
            ctx_num=$(printf '%s' "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
        elif [ "$ctx_mode" = "remaining" ]; then
            local remaining
            remaining=$(printf '%s' "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
            [ -n "$remaining" ] && ctx_num=$((100 - remaining))
        elif [ "$ctx_mode" = "bar" ]; then
            local bar_match bar_content bar_total bar_spaces bar_filled
            bar_match=$(printf '%s' "$output" | grep -oE "$ctx_pattern" | head -1)
            if [ -n "$bar_match" ]; then
                bar_content="${bar_match#*\[}"
                bar_content="${bar_content%\]}"
                bar_total=${#bar_content}
                if [ "$bar_total" -gt 0 ]; then
                    bar_spaces=$(printf '%s' "$bar_content" | tr -cd ' ' | wc -c)
                    bar_filled=$((bar_total - bar_spaces))
                    ctx_num=$(( (bar_filled * 100) / bar_total ))
                fi
            fi
        fi
    else
        ctx_num=""
    fi

    # フォールバック: プロファイルなし or ctx_patternマッチ失敗時
    # CLI type設定と実態の乖離(例: claude設定だがCodexで起動)でctx_patternが合わない場合に全パターンを試す
    if [ -z "$ctx_num" ]; then
        ctx_num=$(printf '%s' "$output" | grep -oE 'CTX:[0-9]+%' | tail -1 | grep -oE '[0-9]+')
    fi
    if [ -z "$ctx_num" ]; then
        ctx_num=$(printf '%s' "$output" | grep -oE 'Context [0-9]+% used' | tail -1 | grep -oE '[0-9]+')
    fi
    if [ -z "$ctx_num" ]; then
        local remaining
        remaining=$(printf '%s' "$output" | grep -oE '[0-9]+% context left' | tail -1 | grep -oE '[0-9]+')
        [ -n "$remaining" ] && ctx_num=$((100 - remaining))
    fi

    if [ -n "$ctx_num" ] && [ "$ctx_num" -gt 0 ] 2>/dev/null; then
        tmux set-option -p -t "$pane_target" @context_pct "${ctx_num}%" 2>/dev/null
    else
        tmux set-option -p -t "$pane_target" @context_pct "0%" 2>/dev/null
    fi
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
    done < <(tmux list-panes -t "${TMUX_WINDOW:-shogun:agents}" -F '#{window_index}.#{pane_index} #{@agent_id}' 2>/dev/null)
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
            local karo_pane="${KARO_PANE:-}"
            if [ -z "$karo_pane" ]; then
                karo_pane=$(pane_lookup karo 2>/dev/null || true)
                karo_pane="${karo_pane:-${TMUX_WINDOW:-shogun:agents}.1}"
            fi
            local karo_status="unknown"
            check_idle "$karo_pane" "karo" && karo_status="idle" || karo_status="busy"
            local karo_ctx
            karo_ctx=$(get_context_pct "$karo_pane" "karo")

            {
                printf 'updated_at: "%s"\nagents:\n' "$timestamp"
                printf '  karo:\n    pane: "%s"\n    status: %s\n    ctx_pct: %s\n    last_task: ""\n' \
                    "$karo_pane" "$karo_status" "$karo_ctx"

                # 忍者
                for name in "${NINJA_NAMES[@]}"; do
                    local target="${PANE_TARGETS[$name]:-}"
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
    local restart_lock_dir="${SHOGUN_STATE_DIR:-/tmp}"
    mkdir -p "$restart_lock_dir" 2>/dev/null || restart_lock_dir="/tmp"
    if ! flock -n "$restart_lock_dir/restart_watchers.lock" -c ':' 2>/dev/null; then
        log "SKIP: restart_watchers.sh is running; inbox_watcher health check deferred"
        return 0
    fi

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
            pane_target="$(pane_lookup "$agent" 2>/dev/null || true)"
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
    if ! declare -p NINJA_NAMES >/dev/null 2>&1 || [ "${#NINJA_NAMES[@]}" -eq 0 ]; then
        read -ra NINJA_NAMES <<< "$(get_ninja_names)"
    fi

    # S04修正: サブシェル→ブレースグループ（fd継承によるロック漏洩を回避）
    {
        if ! flock -x -w 5 200; then
            log "ERROR: write_karo_snapshot flock failed"
        else
            local tmp_file
            tmp_file=$(mktemp "${snapshot_file}.tmp.XXXXXX") || {
                log "ERROR: write_karo_snapshot mktemp failed"
                return 1
            }
            if {
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
                    # モデル短縮名を取得（SSOT=実際に稼働しているモデル）
                    # Codex: 末尾ステータスバーに常時表示(gpt-X.X mode · Context N%)
                    # Claude: 末尾にモデル名なし→起動バナー(▝▜█████▛▘)を全スクロールバックで検索
                    # 2026-06-20: -S -200では起動バナーに届かない+ログ内モデル名誤検出バグ修正
                    local _model_name="" _model_short="?"
                    if [ -n "$_pane_target" ]; then
                        # 1st: @model_name cache maintained by check_model_names.
                        _model_name=$(tmux show-options -p -t "$_pane_target" -v @model_name 2>/dev/null || echo "")
                        # 2nd: Codex末尾ステータスバー(SSOT常時表示。軽い)
                        if [ -z "$_model_name" ]; then
                            _model_name=$(tmux capture-pane -t "$_pane_target" -p 2>/dev/null | tail -20 | grep -m1 -oiE 'gpt-[0-9.]+[a-z ]*' || echo "")
                        fi
                        # 3rd: Claude起動バナー(▝▜█████▛▘。末尾にモデル名なし→全スクロールバック必須)
                        if [ -z "$_model_name" ]; then
                            _model_name=$(tmux capture-pane -t "$_pane_target" -p -S - 2>/dev/null | grep '▝▜█████▛▘' | tail -1 | grep -oiE '(Opus|Sonnet|Haiku) [0-9]+\.[0-9]+' || echo "")
                        fi
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
                            /^[ \t]*task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
                            /^[ \t]*status:/ && s=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); s=v }
                            /^[ \t]*project:/ && p=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); p=v }
                            END { print t "|" s "|" p }
                        ' "$task_file")
                        local runtime_state="idle"
                        # CLI死亡判定: pane_current_commandがbash/zshならdead (cmd_1851)
                        if [ -n "$_pane_target" ]; then
                            local _pane_cmd
                            _pane_cmd=$(tmux display-message -t "$_pane_target" -p '#{pane_current_command}' 2>/dev/null || true)
                            case "$_pane_cmd" in
                                bash|zsh|sh) runtime_state="dead" ;;
                            esac
                        fi
                        # snapshot実態乖離補正: task YAMLがidle/completedだがCTX>0%ならcapture-paneで実態確認
                        # Codex CLIはhook未発火で@agent_stateが更新されず、snapshotが古いstatusを表示し続ける問題の根治
                        local _ctx_num_snap="${_ctx%\%}"
                        if [[ "$status" =~ ^(idle|completed|done)$ ]] && [ -n "$_ctx_num_snap" ] && [ "$_ctx_num_snap" != "?" ] && [ "$_ctx_num_snap" -gt 0 ] 2>/dev/null; then
                            if [ -n "$_pane_target" ] && check_agent_busy "$_pane_target" "$name"; then
                                runtime_state="busy"
                            fi
                        elif [[ "$status" =~ ^(assigned|acknowledged|in_progress|pending)$ ]]; then
                            runtime_state="busy"
                        fi
                        _snapshot_status[$name]="${status:-}"
                        local _task_source_ts
                        _task_source_ts=$(date -r "$task_file" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo unknown)
                        echo "ninja|${name}|${task_id:-none}|${status:-idle}|${project:-none}|CTX:${_ctx}|M:${_model_short}|SRC:${_task_source_ts}|TASK:${status:-idle}|RUNTIME:${runtime_state}"
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
                    local _prev_state="${PREV_STATE[$name]:-idle}"
                    if [ "$_prev_state" = "idle" ] || [ "$_prev_state" = "done" ]; then
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
            } > "$tmp_file"; then
                mv "$tmp_file" "$snapshot_file"
            else
                rm -f "$tmp_file"
                log "ERROR: write_karo_snapshot temp write failed"
                return 1
            fi
        fi
    } 200>"$lock_file"
}

refresh_karo_snapshot_fast_path() {
    # 陣形図は復帰用の生存情報。重い監視チェックより前に必ず一度発行する。
    write_state_file
    # Model/banner consistency is documented as a REDISCOVER_EVERY check.
    # Keep snapshot fresh every call, but avoid the multi-pane model scan on
    # every fast-path refresh.
    local _rediscover_every="${REDISCOVER_EVERY:-30}"
    if [ -z "${cycle:-}" ] || [ $((cycle % _rediscover_every)) -eq 0 ]; then
        check_model_names
    fi
    write_karo_snapshot
}

# Publish one task generation without waiting for the monitor's potentially
# long maintenance cycle.  deploy_task/status-transition writers call this
# only after their atomic task YAML publication; the task file remains SSOT.
refresh_karo_snapshot_task_assignment() {
    local name="${1:-}"
    [[ "$name" =~ ^[a-z][a-z0-9_]*$ ]] || return 2
    local task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
    local snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
    local lock_file="${KARO_SNAPSHOT_LOCK_FILE:-/tmp/karo_snapshot.lock}"
    [ -f "$task_file" ] || return 3

    local task_id status project source_ts timestamp runtime_state
    IFS='|' read -r task_id status project < <(awk '
        BEGIN { t=""; s=""; p="" }
        /^[ \t]*task_id:/ && t=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); t=v }
        /^[ \t]*status:/ && s=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); s=v }
        /^[ \t]*project:/ && p=="" { v=$0; sub(/^[^:]*:[ \t]*/,"",v); gsub(/'"'"'|"/,"",v); p=v }
        END { print t "|" s "|" p }
    ' "$task_file")
    [ -n "$task_id" ] || task_id=none
    [ -n "$status" ] || status=idle
    [ -n "$project" ] || project=none
    source_ts=$(date -r "$task_file" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo unknown)
    printf -v timestamp '%(%Y-%m-%dT%H:%M:%S)T' -1
    case "$status" in
        assigned|acknowledged|in_progress|pending) runtime_state=busy ;;
        *) runtime_state=idle ;;
    esac

    {
        flock -x -w 5 200 || return 4
        local tmp_file snapshot_source existing_line ctx_field model_field new_line
        tmp_file=$(mktemp "${snapshot_file}.tmp.XXXXXX") || return 5
        snapshot_source="$snapshot_file"
        [ -f "$snapshot_source" ] || snapshot_source=/dev/null
        existing_line=$(awk -F'|' -v n="$name" '$1=="ninja" && $2==n { print; exit }' "$snapshot_file" 2>/dev/null || true)
        ctx_field=$(awk -F'|' '{for(i=1;i<=NF;i++) if($i ~ /^CTX:/){print $i; exit}}' <<< "$existing_line")
        model_field=$(awk -F'|' '{for(i=1;i<=NF;i++) if($i ~ /^M:/){print $i; exit}}' <<< "$existing_line")
        ctx_field="${ctx_field:-CTX:?%}"
        model_field="${model_field:-M:?}"
        new_line="ninja|${name}|${task_id}|${status}|${project}|${ctx_field}|${model_field}|SRC:${source_ts}|TASK:${status}|RUNTIME:${runtime_state}"
        awk -F'|' -v OFS='|' -v n="$name" -v generated="# Generated: $timestamp" \
            -v replacement="$new_line" -v active="$status" '
            BEGIN { replaced=0 }
            /^# Generated:/ { print generated; next }
            $1=="ninja" && $2==n { print replacement; replaced=1; next }
            $1=="idle" {
                count=split($2, names, ","); out=""
                for (i=1; i<=count; i++) if (names[i] != n && names[i] != "none") out=(out=="" ? names[i] : out "," names[i])
                if (active !~ /^(assigned|acknowledged|in_progress|pending|failed)$/) out=(out=="" ? n : out "," n)
                print "idle", (out=="" ? "none" : out); next
            }
            { print }
            END { if (!replaced) print replacement }
        ' "$snapshot_source" > "$tmp_file" && mv "$tmp_file" "$snapshot_file" || {
            rm -f "$tmp_file"
            return 6
        }
    } 200>"$lock_file"
}

# ─── CLI死亡検知+自動再起動 (cmd_1851 + L821拡張) ───
# 全エージェント(家老+軍師+忍者)のpane_current_commandを確認し、bash/zshならCLI死亡と判定。
# L821: NINJA_NAMESのみだと家老/軍師が監視対象外(各論パッチ禁止。原理1行で全員カバー)。
# 5分以内に2回以上再起動した場合はntfy ALERTのみ送信してループ防止。
check_ninja_cli_dead() {
    local now=$EPOCHSECONDS
    local _all_agents=("shogun" "karo" "gunshi" "${NINJA_NAMES[@]}")
    for name in "${_all_agents[@]}"; do
        local pane_target="${PANE_TARGETS[$name]:-}"
        [ -z "$pane_target" ] && continue

        # 殿が直接操作中のペインは自動再起動対象外(殿裁定2026-06-24)
        # gunshiペインは殿が手動で起動/停止する。ninja_monitorが勝手に再起動するのはバグ。
        local _lord_active
        _lord_active=$(tmux display-message -t "$pane_target" -p '#{@lord_active}' 2>/dev/null || echo "")
        if [ "$_lord_active" = "1" ]; then
            continue
        fi

        # pane_dead判定を先に実施（Codex dead時はpane_current_command=nodeでスキップされる問題を修正）
        local _early_pane_dead
        local pane_cmd=""
        _early_pane_dead=$(tmux display-message -t "$pane_target" -p '#{pane_dead}' 2>/dev/null || echo "0")
        if [ "$_early_pane_dead" = "1" ]; then
            # pane自体が死んでいる → CLI死亡確定
            :
        else
            # pane生存時: pane_current_commandでCLI死亡を判定
            pane_cmd=$(tmux display-message -t "$pane_target" -p '#{pane_current_command}' 2>/dev/null || true)

            # bash/zsh/sh以外はCLI稼働中 → スキップ
            case "$pane_cmd" in
                bash|zsh|sh)
                    local pane_pid cli_child
                    pane_pid=$(tmux display-message -t "$pane_target" -p '#{pane_pid}' 2>/dev/null || true)
                    if [[ "$pane_pid" =~ ^[0-9]+$ ]]; then
                        cli_child=$(ps -o comm= -g "$pane_pid" 2>/dev/null | awk '$1 ~ /^(claude|codex|node)$/ {print $1; exit}' || true)
                        if [ -n "$cli_child" ]; then
                            log "CLI-DEAD-SKIP: ${name}@${pane_target} pane_current_command=${pane_cmd} but live CLI child=${cli_child}"
                            continue
                        fi
                    fi
                    ;;
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

        # 起動コマンドを取得（一次情報優先: 前回起動コマンド→settings.yamlフォールバック）
        local launch_cmd
        launch_cmd=$(tmux display-message -t "$pane_target" -p '#{pane_start_command}' 2>/dev/null || echo "")
        # respawn-pane経由のpane_start_commandは"cd DIR && CLI"等の複合形式。これを再ラップすると
        # cd前置が雪だるま式にネストし引用が崩壊してstatus 126で死ぬ(kagemaru事故 2026-06-10 21:16-22:
        # 1回目respawn後start_command="cd...&&claude"→2回目で export...&& cd...&& "cd...&&claude" に成長)。
        # 複合形式(&&や引用符を含む)は信頼せず、設定から純粋なCLIコマンドを再構築する。
        if [ -z "$launch_cmd" ] || [[ "$launch_cmd" == *'&&'* ]] || [[ "$launch_cmd" == *'"'* ]] \
           || [[ "$launch_cmd" == *"bash"* && "$launch_cmd" != *"claude"* && "$launch_cmd" != *"codex"* ]]; then
            launch_cmd=$(build_cli_command "$name" 2>/dev/null || true)
        fi
        if [ -z "$launch_cmd" ]; then
            log "CLI-DEAD: ${name} launch_cmd取得失敗。再起動スキップ。"
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "【ALERT】${name} CLI死亡検知。launch_cmd取得失敗で自動再起動不可。手動確認が必要。" 2>/dev/null || true
            continue
        fi

        # 再起動時刻を記録
        CLI_DEAD_RESTART_TIMES[$name]="${CLI_DEAD_RESTART_TIMES[$name]} ${now}"

        log "CLI-DEAD: ${name} 再起動実行。launch_cmd=${launch_cmd}"

        # pane_deadは記録用に取得するが、復旧は常にrespawn-paneで行う。
        # send-keys復旧はClaude Code 2.1.87でpane_current_command=bash誤検知時に
        # launch_cmdを生きているCLIプロンプトへ混入させるため禁止。
        local pane_dead
        pane_dead=$(tmux display-message -t "$pane_target" -p '#{pane_dead}' 2>/dev/null || echo "0")

        # バックグラウンドで再起動+30秒後確認（メインループをブロックしない）
        local _pane_target_bg="$pane_target"
        local _name_bg="$name"
        local _launch_bg="$launch_cmd"
        local _pane_dead_bg="$pane_dead"
        local _script_dir_bg="$SCRIPT_DIR"
        (
            log "CLI-DEAD: ${_name_bg} pane_dead=${_pane_dead_bg} → respawn-pane使用"
            # per-agent config.toml切替(SSOT: cli_lookup.sh)
            codex_config_apply_agent "$_name_bg" 2>/dev/null && \
                [[ "$_CODEX_CFG_CHANGED" == true ]] && \
                log "CODEX-CFG-SWITCH(CLI-DEAD): $_name_bg applied"
            # PATH必須: codex shebang=#!/usr/bin/env node → nvm PATHなしでexit 127
            local _launch_command
            _launch_command=$(respawn_recovery_launch_command "$_script_dir_bg" "$_launch_bg" 2>/dev/null || true)
            local _respawn_rc=0
            _respawn_with_cli_verification "$_pane_target_bg" "$_name_bg" \
                "$_launch_command" \
                "CLI-DEAD-RESPAWN" || _respawn_rc=$?
            # LK009 enforcement: CLI再起動後に@agent_idを再設定（pane変数汚染防止）
            local _current_agent_id
            _current_agent_id=$(tmux display-message -t "$_pane_target_bg" -p '#{@agent_id}' 2>/dev/null || true)
            if [ "$_current_agent_id" != "$_name_bg" ]; then
                log "AGENT-ID-FIX: ${_name_bg}@${_pane_target_bg} agent_id was '${_current_agent_id}' → resetting to '${_name_bg}'"
                tmux set-option -t "$_pane_target_bg" -p @agent_id "$_name_bg" 2>/dev/null || true
            fi
            if [ "$_respawn_rc" -eq 0 ]; then
                _generation=$(respawn_recovery_generation "$_pane_target_bg" 2>/dev/null || true)
                if [ -n "$_generation" ] && respawn_recovery_notify "$_script_dir_bg" "$_name_bg" "$_generation" cli-dead; then
                    bash "$_script_dir_bg/scripts/ntfy.sh" "【CLI再起動成功】${_name_bg}: CLIバナー/プロンプト確認済み" 2>/dev/null || true
                else
                    _respawn_rc=1
                fi
            else
                bash "$_script_dir_bg/scripts/ntfy.sh" "【CLI再起動失敗】${_name_bg}: 3回の起動確認に失敗。手動確認が必要。" 2>/dev/null || true
            fi
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
    local _ctx_band_file="${STATE_DIR:-/tmp}/mas-shogun-ctx-band-last.txt"
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
    local all_agents=("shogun" "karo" "gunshi" "${NINJA_NAMES[@]}")

    for name in "${all_agents[@]}"; do
        local target
        if [ "$name" = "karo" ]; then
            target="${KARO_PANE:-}"
            if [ -z "$target" ]; then
                target=$(pane_lookup karo 2>/dev/null || true)
                target="${target:-${TMUX_WINDOW:-shogun:agents}.1}"
            fi
        elif [ "$name" = "gunshi" ]; then
            target="${GUNSHI_PANE:-}"
        else
            target="${PANE_TARGETS[$name]:-}"
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
    local all_agents=("shogun" "karo" "gunshi" "${NINJA_NAMES[@]}")
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
            count_unread_messages_cached "$inbox_file" count
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
        count_unread_messages_cached "$shogun_inbox" shogun_count
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

# ─── throughput_scan定期チェック (cmd_3766) ───
LAST_THROUGHPUT_SCAN=$EPOCHSECONDS
THROUGHPUT_SCAN_INTERVAL=${THROUGHPUT_SCAN_INTERVAL:-300}  # 5分間隔(秒)

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

    # ALERTまたは早期対応が必要なWARNがあるか確認（herestring: echo不要でサブシェル1個削減）
    local lesson_alert_pattern='^(ALERT:|WARN: .*未振り分け教訓.*早期導線|WARN: 新規教訓\+)'
    if grep -Eq "$lesson_alert_pattern" <<< "$output"; then
        # デバウンスチェック
        local alert_elapsed=$((now - LAST_LESSON_ALERT))
        if [ $alert_elapsed -lt $LESSON_ALERT_DEBOUNCE ]; then
            log "LESSON-HEALTH-DEBOUNCE: ALERT detected but ${alert_elapsed}s < ${LESSON_ALERT_DEBOUNCE}s"
            return
        fi

        local alerts
        alerts=$(grep -E "$lesson_alert_pattern" <<< "$output" | tr '\n' ' ')
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

    # WARNING検出 → ntfy通知(デバウンス付き)（herestring: echo不要でサブシェル1個削減）
    if grep -q "WARNING:" <<< "$output"; then
        local alert_elapsed=$((now - LAST_LOOP_HEALTH_ALERT))
        if [ $alert_elapsed -lt $LOOP_HEALTH_ALERT_DEBOUNCE ]; then
            log "LOOP-HEALTH-DEBOUNCE: WARNING detected but ${alert_elapsed}s < ${LOOP_HEALTH_ALERT_DEBOUNCE}s"
            return
        fi

        local warnings
        warnings=$(grep "WARNING:" <<< "$output" | tr '\n' ' ')
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

check_throughput_scan() {
    local now elapsed scan_script
    now=$EPOCHSECONDS
    elapsed=$((now - LAST_THROUGHPUT_SCAN))
    if [ "$elapsed" -lt "$THROUGHPUT_SCAN_INTERVAL" ]; then
        return
    fi
    LAST_THROUGHPUT_SCAN=$now

    scan_script="$SCRIPT_DIR/scripts/throughput_scan.sh"
    if [ ! -x "$scan_script" ]; then
        log "THROUGHPUT-SCAN: throughput_scan.sh not executable, skip"
        return
    fi

    bash "$scan_script" >> "$SCRIPT_DIR/logs/throughput_scan.log" 2>&1 || true
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

check_three_layer_maintenance() {
    local now last elapsed lock_file lock_fd maintenance_timeout
    now=$EPOCHSECONDS
    maintenance_timeout="${THREE_LAYER_MAINTENANCE_TIMEOUT:-120}"
    last=0
    if [ -f "$THREE_LAYER_MAINTENANCE_STATE_FILE" ]; then
        read -r last < "$THREE_LAYER_MAINTENANCE_STATE_FILE" || last=0
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    elapsed=$((now - last))
    [ "$elapsed" -lt "$THREE_LAYER_MAINTENANCE_INTERVAL" ] && return

    mkdir -p "$(dirname "$THREE_LAYER_MAINTENANCE_LOG")"
    lock_file="${THREE_LAYER_MAINTENANCE_LOCK_FILE:-$STATE_DIR/shogun_three_layer_maintenance.lock}"
    exec {lock_fd}>"$lock_file"
    if ! flock -n "$lock_fd"; then
        exec {lock_fd}>&-
        log "THREE-LAYER-MAINTENANCE: already running, skip"
        return
    fi
    # Claim the interval before detaching. The child inherits the locked FD;
    # the kernel releases it even when the child dies without running a trap.
    printf '%s\n' "$now" > "$THREE_LAYER_MAINTENANCE_STATE_FILE" 2>/dev/null || true
    (
        local cleanup_script recall_script promote_script
        cleanup_script="$SCRIPT_DIR/scripts/cleanup_three_layer_tmp.sh"
        if [ -f "$cleanup_script" ]; then
            log "THREE-LAYER-MAINTENANCE: tmp cleanup start"
            timeout "$maintenance_timeout" bash "$cleanup_script" --apply --ttl-hours "${THREE_LAYER_MAINTENANCE_TMP_TTL_HOURS:-4}" >> "$THREE_LAYER_MAINTENANCE_LOG" 2>&1 \
                && log "THREE-LAYER-MAINTENANCE: tmp cleanup done" \
                || log "THREE-LAYER-MAINTENANCE: tmp cleanup failed (non-blocking)"
        fi
        recall_script="$SCRIPT_DIR/scripts/memory_recall_control.sh"
        if [ -f "$recall_script" ]; then
            log "THREE-LAYER-MAINTENANCE: recall_control apply start"
            timeout "$maintenance_timeout" bash "$recall_script" >> "$THREE_LAYER_MAINTENANCE_LOG" 2>&1 \
                && log "THREE-LAYER-MAINTENANCE: recall_control apply done" \
                || log "THREE-LAYER-MAINTENANCE: recall_control apply failed (non-blocking)"
        fi
        promote_script="$SCRIPT_DIR/scripts/obsidian_promote_candidate.sh"
        if [ -f "$promote_script" ]; then
            log "THREE-LAYER-MAINTENANCE: obsidian_promote apply start"
            timeout "$maintenance_timeout" bash "$promote_script" >> "$THREE_LAYER_MAINTENANCE_LOG" 2>&1 \
                && log "THREE-LAYER-MAINTENANCE: obsidian_promote apply done" \
                || log "THREE-LAYER-MAINTENANCE: obsidian_promote apply failed (non-blocking)"
        fi
    ) &
    # Only the detached child keeps the lock. Closing the monitor's copy avoids
    # a permanent lock across hot reload/respawn while preserving single-flight.
    exec {lock_fd}>&-
}

# ─── obsidian candidate自動昇格 (cmd_3240) ───
# obsidian_promote_candidate.shが蓄積したcandidate件数を定期チェックし、
# 閾値超過時にobsidian_promote_finalize.shでstate=obsidian_promotedへ自動遷移する。
# 将軍の/dream(手動)依存を排除し、意志に依存しない自動昇格を実現する。
check_obsidian_candidate_promotion() {
    local now last elapsed candidate_count finalize_script db_path
    now=$EPOCHSECONDS
    last=0
    if [ -f "$OBSIDIAN_PROMOTE_STATE_FILE" ]; then
        read -r last < "$OBSIDIAN_PROMOTE_STATE_FILE" || last=0
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    elapsed=$((now - last))
    [ "$elapsed" -lt "$OBSIDIAN_PROMOTE_INTERVAL" ] && return

    db_path="$SCRIPT_DIR/data/multi_agent_shogun_memory.db"
    if [ ! -f "$db_path" ]; then
        log "OBSIDIAN-PROMOTE: database not found, skip"
        printf '%s\n' "$now" > "$OBSIDIAN_PROMOTE_STATE_FILE" 2>/dev/null || true
        return
    fi

    # sqlite3 CLI不在環境では `|| echo "0"` が常時0を返し候補が永久に昇格されない(2026-07-07実測: 実34件をcandidates=0と誤認)。
    # python3で直接クエリし、失敗時は0扱いにせず明示ERRORでスキップする(silent-zero禁止)。
    candidate_count=$(python3 -c "
import sqlite3, sys
try:
    con = sqlite3.connect('file:' + sys.argv[1] + '?mode=ro', uri=True)
    print(con.execute(\"SELECT COUNT(*) FROM events WHERE state='obsidian_candidate'\").fetchone()[0])
except Exception as exc:
    print('ERROR:' + str(exc))
" "$db_path" 2>/dev/null)
    if ! [[ "$candidate_count" =~ ^[0-9]+$ ]]; then
        log "OBSIDIAN-PROMOTE: ERROR candidate count query failed ($candidate_count) — 0扱いにせずスキップ"
        printf '%s\n' "$now" > "$OBSIDIAN_PROMOTE_STATE_FILE" 2>/dev/null || true
        return
    fi

    if [ "$candidate_count" -lt "$OBSIDIAN_PROMOTE_THRESHOLD" ]; then
        log "OBSIDIAN-PROMOTE: candidates=$candidate_count (threshold=$OBSIDIAN_PROMOTE_THRESHOLD), skip"
        printf '%s\n' "$now" > "$OBSIDIAN_PROMOTE_STATE_FILE" 2>/dev/null || true
        return
    fi

    finalize_script="$SCRIPT_DIR/scripts/obsidian_promote_finalize.sh"
    if [ ! -f "$finalize_script" ]; then
        log "OBSIDIAN-PROMOTE: obsidian_promote_finalize.sh not found, skip"
        printf '%s\n' "$now" > "$OBSIDIAN_PROMOTE_STATE_FILE" 2>/dev/null || true
        return
    fi

    mkdir -p "$(dirname "$OBSIDIAN_PROMOTE_LOG")"
    log "OBSIDIAN-PROMOTE: candidates=$candidate_count >= threshold=$OBSIDIAN_PROMOTE_THRESHOLD, auto-promoting"
    if timeout 120 bash "$finalize_script" --force >> "$OBSIDIAN_PROMOTE_LOG" 2>&1; then
        log "OBSIDIAN-PROMOTE: auto-promote done (candidates=$candidate_count)"
    else
        log "OBSIDIAN-PROMOTE: auto-promote failed (non-blocking)"
    fi

    printf '%s\n' "$now" > "$OBSIDIAN_PROMOTE_STATE_FILE" 2>/dev/null || true
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

    # (1) 行数 + completed/done/cancelled/absorbed cmd数チェック
    # L019教訓: grep -cは0件でexit 1するのでawkで安全にカウント
    # L034教訓: インデント柔軟マッチ(固定space非依存)
    local counts line_count completed_count
    counts=$(awk '
        { lines++ }
        /^[[:space:]]*status:[[:space:]]*(completed|done|cancelled|absorbed)([[:space:]]|$)/ { completed++ }
        END { print lines+0 "|" completed+0 }
    ' "$cmd_file" 2>/dev/null || echo "0|0")
    IFS='|' read -r line_count completed_count <<< "$counts"

    if [ "$line_count" -gt "$YAML_SIZE_WARN_THRESHOLD" ]; then
        log "[monitor] WARN: shogun_to_karo.yaml is ${line_count} lines (threshold: ${YAML_SIZE_WARN_THRESHOLD})"
    fi

    if [ "$completed_count" -gt "$YAML_COMPLETED_ALERT_THRESHOLD" ]; then
        log "[monitor] ALERT: ${completed_count} completed cmds in shogun_to_karo.yaml — archive may be failing"
    fi
}

# ─── CDP Chrome task終端連動クリーンアップ ───
run_cdp_cleanup() {
    local agent_name="$1"
    local task_cmd="${2:-}"
    # スクリプト存在チェック（cmd_905_Aが未配備でもエラーにならない）
    if [ ! -x "$CDP_CLEANUP_SCRIPT" ]; then
        return 0
    fi

    log "CDP-CLEANUP: owner=$agent_name cmd=${task_cmd:-any} terminal task detected"
    local -a args=(--agent "$agent_name")
    [ -n "$task_cmd" ] && args+=(--cmd "$task_cmd")
    if bash "$CDP_CLEANUP_SCRIPT" "${args[@]}" >> "$LOG" 2>&1; then
        log "CDP-CLEANUP: owner=$agent_name completed successfully"
    else
        log "CDP-CLEANUP: owner=$agent_name script exited with error (non-fatal)"
    fi
}

cleanup_terminal_task_cdps() {
    local name task_file status task_cmd
    for name in "${NINJA_NAMES[@]}"; do
        task_file="$SCRIPT_DIR/queue/tasks/${name}.yaml"
        [ -f "$task_file" ] || continue
        status=$(yaml_field_get "$task_file" "status" "" 2>/dev/null || true)
        [[ "$status" =~ ^(done|failed)$ ]] || continue
        task_cmd=$(yaml_field_get "$task_file" "parent_cmd" "" 2>/dev/null || true)
        run_cdp_cleanup "$name" "$task_cmd"
    done
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

# ═══ memory_db live insert退避queue drain ═══
# 正本処理(YAML/inbox/report/gate)はDBロック待ちで止めない。副作用はasync queueへ退避し、
# ninja_monitorが定期的に排水する。新daemonを増やさず既存監視基盤に載せる。
drain_memory_db_live_insert_queue() {
    local now=$EPOCHSECONDS
    local elapsed=$((now - LAST_MEMORY_DB_LIVE_DRAIN))
    if [ "$elapsed" -lt "$MEMORY_DB_LIVE_DRAIN_INTERVAL" ]; then
        return 0
    fi

    local drain_script="$SCRIPT_DIR/scripts/memory_db_live_insert_async.py"
    if [ -f "$drain_script" ]; then
        python3 "$drain_script" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
    LAST_MEMORY_DB_LIVE_DRAIN=$now
}

get_idle_cycle_flag() {
    awk '
        /^[[:space:]]*idle_cycle:[[:space:]]*/ {
            v=$0
            sub(/^[^:]*:[[:space:]]*/, "", v)
            sub(/[[:space:]]*#.*/, "", v)
            gsub(/["'\''[:space:]]/, "", v)
            print v
            exit
        }
    ' "$SCRIPT_DIR/config/settings.yaml" 2>/dev/null || true
}

get_idle_pipeline_state() {
    local snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
    if [ ! -f "$snapshot_file" ]; then
        echo "0|0|0"
        return
    fi

    local snapshot_counts ninja_total active_count pending_count
    snapshot_counts=$(awk -F'|' '
        /^ninja\|/ {
            total++
            if ($4 !~ /^(idle|completed|done)$/) active++
        }
        END { print total+0 "|" active+0 }
    ' "$snapshot_file" 2>/dev/null || echo "0|0")
    IFS='|' read -r ninja_total active_count <<< "$snapshot_counts"

    pending_count=$(awk '/^[[:space:]]+status:[[:space:]]*(pending|new)/ {c++} END {print c+0}' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || echo 0)
    echo "${ninja_total:-0}|${active_count:-0}|${pending_count:-0}"
}

# Durable cooldown transaction for karo idle-cycle delivery.  The state lock
# covers read, decision, delivery, and the successful-delivery epoch update so
# hot reloads, daemon respawns, and concurrent monitor processes share exactly
# one cooldown generation.
deliver_karo_idle_nudge_with_cooldown() {
    local now="${1:?now epoch required}"
    shift
    local state_file="${KARO_IDLE_NUDGE_STATE_FILE:-${STATE_DIR:-/tmp}/shogun_karo_idle_nudge.last}"
    local cooldown="${KARO_IDLE_COOLDOWN:-1800}"
    local state_dir lock_file lock_fd last_epoch tmp_file
    state_dir="${state_file%/*}"
    lock_file="${state_file}.lock"
    mkdir -p "$state_dir" || {
        log "WARN: KARO-IDLE-CYCLE cannot create cooldown state dir: $state_dir"
        return 1
    }
    exec {lock_fd}>"$lock_file" || return 1
    flock "$lock_fd" || { exec {lock_fd}>&-; return 1; }

    if [ -e "$state_file" ] && [ ! -f "$state_file" ]; then
        log "WARN: KARO-IDLE-CYCLE cooldown state is not a regular file: $state_file"
        exec {lock_fd}>&-
        return 1
    fi
    last_epoch="$(cat "$state_file" 2>/dev/null || true)"
    if [ -e "$state_file" ] && { [[ ! "$last_epoch" =~ ^[0-9]+$ ]] || [ "$last_epoch" -gt "$now" ]; }; then
        log "WARN: KARO-IDLE-CYCLE invalid cooldown epoch '${last_epoch:-empty}'; repairing to $now and suppressing this cycle"
        tmp_file="${state_file}.tmp.$$"
        if ! printf '%s\n' "$now" > "$tmp_file" || ! mv -f "$tmp_file" "$state_file"; then
            rm -f "$tmp_file"
            exec {lock_fd}>&-
            return 1
        fi
        exec {lock_fd}>&-
        return 2
    fi
    if [[ "$last_epoch" =~ ^[0-9]+$ ]] && [ $((now - last_epoch)) -lt "$cooldown" ]; then
        exec {lock_fd}>&-
        return 2
    fi

    if "$@"; then
        tmp_file="${state_file}.tmp.$$"
        if ! printf '%s\n' "$now" > "$tmp_file" || ! mv -f "$tmp_file" "$state_file"; then
            rm -f "$tmp_file"
            log "ERROR: KARO-IDLE-CYCLE delivery succeeded but cooldown state update failed"
            exec {lock_fd}>&-
            return 1
        fi
        exec {lock_fd}>&-
        return 0
    fi
    exec {lock_fd}>&-
    return 1
}

# ═══ 家老idle自走サイクル起動チェック (cmd_1498) ═══
# 全忍者idle/completed/done + パイプライン空 → 家老に改善サイクル起動を通知
check_karo_idle_cycle() {
    # 自走プロトコルoff時は通知しない
    local idle_cycle_flag
    idle_cycle_flag=$(get_idle_cycle_flag)
    if [ "$idle_cycle_flag" = "off" ]; then
        return
    fi

    # 条件1: 全忍者がidle/completed/doneか確認
    local ninja_total active_count pending_count idle_state
    idle_state=$(get_idle_pipeline_state)
    IFS='|' read -r ninja_total active_count pending_count <<< "$idle_state"
    [ "${ninja_total:-0}" -eq 0 ] && return

    if [ "${active_count:-0}" -gt 0 ]; then
        return
    fi

    # 条件2: パイプラインに未処理cmdがないか確認
    if [ "${pending_count:-0}" -gt 0 ]; then
        return
    fi

    # durable cooldown transactionへ渡す判定epoch
    local now
    now=$EPOCHSECONDS

    # Snapshot確認後にdeployが成立し得るため、通知直前は全ninjaのdeploy lockを
    # 同時保持してlive task YAMLを再検証する。1つでもbusyなら次cycleへ送る。
    local name task_status lock_file lock_fd held_fd
    local -a idle_cycle_lock_fds=()
    mkdir -p "$SCRIPT_DIR/queue/locks"
    for name in "${NINJA_NAMES[@]}"; do
        lock_file="$SCRIPT_DIR/queue/locks/deploy_ninja_${name}.lock"
        exec {lock_fd}>"$lock_file"
        if ! flock -n "$lock_fd"; then
            log "KARO-IDLE-CYCLE-SKIP: deploy lock busy agent=$name"
            exec {lock_fd}>&-
            for held_fd in "${idle_cycle_lock_fds[@]}"; do
                exec {held_fd}>&-
            done
            return
        fi
        idle_cycle_lock_fds+=("$lock_fd")
    done
    for name in "${NINJA_NAMES[@]}"; do
        task_status=$(awk '/^[[:space:]]+status:[[:space:]]*/ {print $2; exit}' "$SCRIPT_DIR/queue/tasks/${name}.yaml" 2>/dev/null || true)
        case "$task_status" in
            idle|completed|done) ;;
            *)
                log "KARO-IDLE-CYCLE-SKIP: live task active agent=$name status=${task_status:-missing}"
                for held_fd in "${idle_cycle_lock_fds[@]}"; do
                    exec {held_fd}>&-
                done
                return
                ;;
        esac
    done

    # 全条件成立: deployを遮断した同一境界内で家老へ通知する。
    # 送信様ログは配送+durable epoch更新の成功後だけ記録する。
    # 子プロセスにはlock FDを継承させない。親shellは通知完了まで保持する。
    deliver_karo_idle_nudge_with_cooldown "$now" bash -c '
        read -ra inherited_idle_fds <<< "$1"
        for held_fd in "${inherited_idle_fds[@]}"; do
            exec {held_fd}>&-
        done
        exec bash "$2/scripts/inbox_write.sh" karo "全忍者idle+パイプライン空。改善サイクルを回せ。" karo_idle_cycle ninja_monitor
    ' _ "${idle_cycle_lock_fds[*]}" "$SCRIPT_DIR" >> "$LOG" 2>&1
    local delivery_rc=$?
    if [ "$delivery_rc" -eq 0 ]; then
        log "KARO-IDLE-CYCLE: Sent improvement cycle nudge to karo"
    elif [ "$delivery_rc" -eq 1 ]; then
        log "ERROR: KARO-IDLE-CYCLE inbox_write failed"
    fi
    for held_fd in "${idle_cycle_lock_fds[@]}"; do
        exec {held_fd}>&-
    done
}

# Script更新は重いpane再探索周期と分離し、次cycleの業務処理前に反映する。
# 旧版が残したdeploy lock FDもexec前に閉じ、新プロセスへ継承させない。
_ninja_monitor_hot_reload_exec() {
    exec bash "$1"
}

close_inherited_deploy_lock_fds() {
    local fd_path fd_target inherited_fd
    for fd_path in "/proc/$$/fd/"*; do
        [ -e "$fd_path" ] || continue
        fd_target="$(readlink "$fd_path" 2>/dev/null || true)"
        case "$fd_target" in
            */queue/locks/deploy_ninja_*.lock)
                inherited_fd="${fd_path##*/}"
                exec {inherited_fd}>&-
                ;;
        esac
    done
}

reload_ninja_monitor_if_updated() {
    local current_mtime
    current_mtime="$(stat -c %Y "$_NM_SCRIPT_PATH" 2>/dev/null || echo 0)"
    [ "$current_mtime" = "$_NM_START_MTIME" ] && return 0

    log "HOT-RELOAD: ninja_monitor.sh updated (mtime ${_NM_START_MTIME} → ${current_mtime}). Restarting..."
    close_inherited_deploy_lock_fds
    _ninja_monitor_hot_reload_exec "$_NM_SCRIPT_PATH"
}

# Existing monitor idle edge is the single trigger; no new daemon/poll loop.
# A trusted writer publishes one CLI argument per line and atomic rename claims it.
check_throughput_ready_events() {
    local ready_dir="${THROUGHPUT_READY_DIR:-$SCRIPT_DIR/queue/throughput_ready}"
    local manifest running
    local -a connector_args=()
    [ -d "$ready_dir" ] || return 0
    manifest=$(find "$ready_dir" -maxdepth 1 -type f -name '*.args' -print 2>/dev/null | sort | head -1)
    [ -n "$manifest" ] || return 0
    running="${manifest%.args}.running"
    mv "$manifest" "$running" 2>/dev/null || return 0
    mapfile -t connector_args < "$running"
    if bash "$SCRIPT_DIR/scripts/throughput_growth_loop.sh" "${connector_args[@]}" >>"$LOG" 2>&1; then
        mv "$running" "${running%.running}.done"
        log "THROUGHPUT-READY-COMPLETE: manifest=${manifest##*/}"
    else
        mv "$running" "${running%.running}.args"
        log "THROUGHPUT-READY-BLOCK: connector failed manifest=${manifest##*/}"
    fi
}

checkpoint_manifest_field() {
    local path="$1" key="$2"
    sed -n "s/^${key}=//p" "$path" 2>/dev/null | head -1
}

checkpoint_manifest_set() {
    local path="$1" key="$2" value="$3" tmp="${path}.tmp.$$"
    awk -F= -v key="$key" -v value="$value" '
        BEGIN { found=0 }
        $1 == key { print key "=" value; found=1; next }
        { print }
        END { if (!found) print key "=" value }
    ' "$path" > "$tmp" && mv "$tmp" "$path"
}

# Promote deferred review requests only after the exact artifact exists.
# The manifest fingerprint is canonical, so ten monitor cycles still emit one
# durable inbox message. A read message closes the lifecycle as reviewed.
process_checkpoint_manifests() {
    local dir="$SCRIPT_DIR/queue/checkpoint_manifests" manifest state artifact_rel artifact_abs
    local reviewer request_type request_from request_action content_b64 content artifact_hash now delivery_count
    [ -d "$dir" ] || return 0
    now=$EPOCHSECONDS
    for manifest in "$dir"/*.manifest; do
        [ -f "$manifest" ] || continue
        state=$(checkpoint_manifest_field "$manifest" state)
        [ "$state" != "reviewed" ] || continue
        artifact_rel=$(checkpoint_manifest_field "$manifest" artifact_path)
        artifact_abs="$SCRIPT_DIR/$artifact_rel"
        reviewer=$(checkpoint_manifest_field "$manifest" reviewer)
        request_type=$(checkpoint_manifest_field "$manifest" request_type)
        request_from=$(checkpoint_manifest_field "$manifest" request_from)
        request_action=$(checkpoint_manifest_field "$manifest" request_action)
        content_b64=$(checkpoint_manifest_field "$manifest" content_b64)

        if [ "$state" = "awaiting_artifact" ]; then
            [ -f "$artifact_abs" ] || continue
            artifact_hash=$(sha256sum "$artifact_abs" | cut -d' ' -f1)
            checkpoint_manifest_set "$manifest" artifact_hash "$artifact_hash"
            checkpoint_manifest_set "$manifest" ready_at_epoch "$now"
            checkpoint_manifest_set "$manifest" state ready
            state=ready
        fi
        [ "$state" = "ready" ] || continue
        delivery_count=$(checkpoint_manifest_field "$manifest" delivery_count)
        if [ "${delivery_count:-0}" -eq 0 ]; then
            content=$(printf '%s' "$content_b64" | base64 -d 2>/dev/null || true)
            if CHECKPOINT_MANIFEST_READY_DELIVERY=1 bash "$SCRIPT_DIR/scripts/inbox_write.sh" \
                "$reviewer" "$content" "$request_type" "$request_from" "$request_action" >> "$LOG" 2>&1; then
                checkpoint_manifest_set "$manifest" delivery_count 1
                checkpoint_manifest_set "$manifest" last_wake_epoch "$now"
                log "CHECKPOINT-READY-DELIVER: manifest=${manifest##*/} reviewer=$reviewer delivery=1 duplicate=0"
            fi
        fi
        # inbox consumption is the durable reviewed transition.
        if python3 - "$SCRIPT_DIR/queue/inbox/${reviewer}.yaml" "$content" <<'PY' 2>/dev/null
import sys, yaml
path, content = sys.argv[1:]
try: messages=(yaml.safe_load(open(path, encoding='utf-8')) or {}).get('messages', [])
except Exception: raise SystemExit(1)
raise SystemExit(0 if any(isinstance(m,dict) and m.get('type')=='verify_request' and m.get('content')==content and m.get('read') is True for m in messages) else 1)
PY
        then
            checkpoint_manifest_set "$manifest" reviewed_at_epoch "$now"
            checkpoint_manifest_set "$manifest" state reviewed
            log "CHECKPOINT-REVIEWED: manifest=${manifest##*/} reviewer=$reviewer"
        fi
    done
}

# ═══ 将軍idle分析trigger (cmd_3549) ═══
# 全忍者idle/completed/done + パイプライン空が10分以上継続 → 将軍にidle分析開始を通知
check_shogun_idle_analysis_trigger() {
    local trigger_state_file="${_SHOGUN_IDLE_TRIGGER_STATE:-/tmp/.shogun_idle_trigger_last}"
    local idle_cycle_flag
    idle_cycle_flag=$(get_idle_cycle_flag)
    if [ "$idle_cycle_flag" = "off" ]; then
        return
    fi

    local ninja_total active_count pending_count idle_state
    idle_state=$(get_idle_pipeline_state)
    IFS='|' read -r ninja_total active_count pending_count <<< "$idle_state"
    if [ "${ninja_total:-0}" -eq 0 ] || [ "${active_count:-0}" -gt 0 ] || [ "${pending_count:-0}" -gt 0 ]; then
        SHOGUN_IDLE_ANALYSIS_ALL_IDLE_SINCE=0
        return
    fi

    local now idle_age elapsed
    now=$EPOCHSECONDS
    if [ "${SHOGUN_IDLE_ANALYSIS_ALL_IDLE_SINCE:-0}" -eq 0 ]; then
        SHOGUN_IDLE_ANALYSIS_ALL_IDLE_SINCE=$now
        return
    fi
    idle_age=$(( now - SHOGUN_IDLE_ANALYSIS_ALL_IDLE_SINCE ))
    [ "$idle_age" -lt 600 ] && return

    elapsed=$(( now - LAST_SHOGUN_IDLE_ANALYSIS_TRIGGER ))
    if [ "$elapsed" -lt "$SHOGUN_IDLE_ANALYSIS_COOLDOWN" ]; then
        return
    fi

    log "SHOGUN-IDLE-ANALYSIS: All ${ninja_total} ninjas idle/completed/done + pipeline empty for ${idle_age}s → nudging shogun"
    if timeout 15 bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun "全忍者idle+パイプライン空が10分以上継続。idle時自己分析 Step 1-7 を開始せよ。" idle_analysis_trigger ninja_monitor >> "$LOG" 2>&1; then
        LAST_SHOGUN_IDLE_ANALYSIS_TRIGGER=$now
        echo "$now" > "$trigger_state_file"
        log "SHOGUN-IDLE-ANALYSIS: Sent idle_analysis_trigger to shogun"
    else
        log "ERROR: SHOGUN-IDLE-ANALYSIS inbox_write failed"
    fi
}

# check_karo_pane_dead_once / check_gunshi_pane_dead_once は削除済み (L821)
# check_ninja_cli_dead() が全エージェント配列で統一カバー

# ─── GP-239: Codex bypass flag self-heal ───
_codex_bypass_generation() {
    local pane="$1" pane_pid
    pane_pid=$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null || true)
    [ -n "$pane_pid" ] || return 1
    printf '%s\n' "$pane_pid"
}

_codex_bypass_marker_file() {
    local agent_name="$1"
    printf '%s/codex_bypass_recovery_%s.generation\n' "$STATE_DIR" "$agent_name"
}

check_codex_bypass_once() {
    local agent_name="$1" pane="$2" pane_pid task_file task_status generation marker launch launch_command
    [ "$(cli_type "$agent_name" 2>/dev/null || true)" = "codex" ] || return 0
    [ -n "$pane" ] || return 0
    pane_pid=$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null || true)
    [ -n "$pane_pid" ] || { log "CODEX-BYPASS-BLOCK: $agent_name pane_pid_missing"; return 1; }
    if pstree -a "$pane_pid" 2>/dev/null | grep -q -- '--dangerously-bypass-approvals-and-sandbox'; then
        return 0
    fi

    task_file="$SCRIPT_DIR/queue/tasks/${agent_name}.yaml"
    task_status=$(awk '/^[[:space:]]*status:/ {gsub(/["'\''[:space:]]/, "", $2); print $2; exit}' "$task_file" 2>/dev/null || true)
    if [ "$task_status" != "idle" ]; then
        log "CODEX-BYPASS-WARN: $agent_name flag_missing task_status=${task_status:-unknown} respawn=blocked"
        return 1
    fi
    if ! check_idle "$pane" "$agent_name"; then
        log "CODEX-BYPASS-WARN: $agent_name flag_missing pane_not_idle respawn=blocked"
        return 1
    fi

    generation=$(_codex_bypass_generation "$pane" 2>/dev/null || true)
    marker=$(_codex_bypass_marker_file "$agent_name")
    if [ -n "$generation" ] && [ "$(cat "$marker" 2>/dev/null || true)" = "$generation" ]; then
        log "CODEX-BYPASS-DEDUPE: $agent_name generation=$generation respawn=0"
        return 0
    fi

    launch=$(cli_launch_cmd "$agent_name" 2>/dev/null || true)
    launch_command=$(respawn_recovery_launch_command "$SCRIPT_DIR" "$launch" 2>/dev/null || true)
    if [ -z "$launch_command" ]; then
        log "CODEX-BYPASS-BLOCK: $agent_name launch_command_unavailable retry=next_cycle"
        return 1
    fi
    codex_config_apply_agent "$agent_name" 2>/dev/null || {
        log "CODEX-BYPASS-BLOCK: $agent_name config_apply_failed retry=next_cycle"
        return 1
    }
    if ! _respawn_with_cli_verification "$pane" "$agent_name" "$launch_command" "CODEX-BYPASS-RESPAWN"; then
        log "CODEX-BYPASS-BLOCK: $agent_name recovery_failed retry=next_cycle"
        return 1
    fi
    generation=$(respawn_recovery_generation "$pane" 2>/dev/null || true)
    if [ -z "$generation" ] || ! respawn_recovery_notify "$SCRIPT_DIR" "$agent_name" "$generation" codex-bypass; then
        log "CODEX-BYPASS-BLOCK: $agent_name handshake_failed retry=next_cycle"
        return 1
    fi
    mkdir -p "$(dirname "$marker")"
    printf '%s\n' "$generation" > "$marker"
    log "CODEX-BYPASS-RECOVERED: $agent_name generation=$generation respawn=1"
}

check_all_codex_bypass_flags() {
    local agent_name pane
    for agent_name in "${NINJA_NAMES[@]}"; do
        [ "$(cli_type "$agent_name" 2>/dev/null || true)" = "codex" ] || continue
        pane="${PANE_MAP[$agent_name]:-}"
        [ -n "$pane" ] || continue
        check_codex_bypass_once "$agent_name" "$pane" || true
    done
}

# ─── 初期ペイン探索 ───
if [ "${NINJA_MONITOR_LIB_ONLY:-0}" = "1" ]; then
    if [ "${1:-}" = "--refresh-snapshot-task" ]; then
        refresh_karo_snapshot_task_assignment "${2:-}"
        exit $?
    fi
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

# 旧monitorのexecが残したFDはmtime差の有無にかかわらずstartupで除去する。
close_inherited_deploy_lock_fds

discover_panes

# hayate事故(2026-04-28): bypass欠落で確認プロンプト停止。startup直後から検査する。
check_all_codex_bypass_flags

# ─── メインループ ───
cycle=0
prev_idle=""
prev_gate_sig=""
_NM_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
_NM_START_MTIME="$(stat -c %Y "$_NM_SCRIPT_PATH" 2>/dev/null || echo 0)"

while true; do
    cycle=$((cycle + 1))

    # A stale generation is never killed.  The owner record is atomically
    # replaced by its successor and the old loop self-fences at this checkpoint.
    if ! ninja_monitor_owner_heartbeat; then
        exit 0
    fi

    # 毎cycle確認（20秒以内）。重いdiscover_panesは従来どおり10分周期。
    reload_ninja_monitor_if_updated

    # Primary task state is observed before pane waits and maintenance.
    monitor_task_state_fast_path

    # GP-239: 復旧失敗はmarkerを残さず次cycleで再試行する。
    check_all_codex_bypass_flags

    # 定期的にペイン再探索（ペイン構成変更に対応）
    if [ $((cycle % REDISCOVER_EVERY)) -eq 0 ]; then
        discover_panes

        # Inbox pruning (cmd_106) — 10分間隔で既読メッセージを自動削除
        bash "$SCRIPT_DIR/scripts/inbox_prune.sh" 2>>"$SCRIPT_DIR/logs/inbox_prune.log" || true

        # shogun_to_karo.yaml肥大化監視 (cmd_369 AC3)
        check_yaml_size

        # ログローテーション (cmd_802) — 10分間隔で全ログを検査
        rotate_all_logs "$SCRIPT_DIR/logs" 10000
    fi

    # ═══ ペイン生存チェック (cmd_183) ═══
    check_pane_survival

    # ═══ 全エージェントCLI死亡検知 (L821: 原理1行で全員カバー。各論パッチ禁止) ═══
    check_ninja_cli_dead

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
                    # An in-progress task has no wall-clock expiry. Long production
                    # runs routinely exceed 30 minutes; stall detection below owns
                    # liveness decisions and must not be bypassed by an automatic
                    # task reset + /clear here.
                    if [ "$_s1_task_status" = "in_progress" ]; then
                        log "STAGE1-IN-PROGRESS: $name idle observation while task is active, /clear禁止"
                        PREV_STATE[$name]="busy"
                        continue
                    fi
                    # cmd_1156 AC2: pre-start task timeout safety valve
                    _s1_task_mtime=$(stat -c %Y "$_s1_task_file" 2>/dev/null || echo 0)
                    _s1_now=$EPOCHSECONDS
                    _s1_age=$(( _s1_now - _s1_task_mtime ))
                    _s1_threshold=900  # 15 minutes default
                    if [ "$_s1_age" -ge "$_s1_threshold" ]; then
                        # cmd_1292 AC1: report存在チェック — active taskでreport未提出なら/clear禁止
                        _s1_report_file=$(resolve_expected_report_file "$name")
                        _s1_report_found=false
                        _s1_report_path=""
                        if [[ "$_s1_report_file" = /* ]]; then
                            if [ -f "$_s1_report_file" ]; then
                                _s1_report_found=true
                                _s1_report_path="$_s1_report_file"
                            fi
                        else
                            if [ -f "$SCRIPT_DIR/queue/reports/${_s1_report_file}" ]; then
                                _s1_report_found=true
                                _s1_report_path="$SCRIPT_DIR/queue/reports/${_s1_report_file}"
                            fi
                            if [ "$_s1_report_found" = false ]; then
                                _s1_report_path=$(compgen -G "$SCRIPT_DIR/queue/archive/reports/${_s1_report_file}" | head -1 || true)
                                [ -n "$_s1_report_path" ] && _s1_report_found=true
                            fi
                        fi
                        if [ "$_s1_report_found" = false ]; then
                            log "STAGE1-REPORT-MISSING: $name task_status=$_s1_task_status stale for ${_s1_age}s but no report (${_s1_report_file}), /clear禁止"
                            PREV_STATE[$name]="busy"
                            continue
                        fi
                        if ! report_file_has_verdict "$name" "$_s1_report_path" "STAGE1-TIMEOUT"; then
                            log "STAGE1-VERDICT-EMPTY: $name task_status=$_s1_task_status stale for ${_s1_age}s but report verdict empty (${_s1_report_file}), /clear禁止"
                            PREV_STATE[$name]="busy"
                            continue
                        fi
                        # Stale task: reset status to idle and allow /clear
                        # L545対応: flat/nested混在に対応。yaml_field_setはblock_id未発見時にroot-levelへ自動フォールバック
                        # YAML書込み安全規則: sed -i(flock未使用)を排除し、yaml_field_setに一本化
                        yaml_field_set "$_s1_task_file" "task" "status" "idle" 2>/dev/null || \
                            log "WARN: STAGE1-TIMEOUT yaml_field_set failed for $name, proceeding with maybe_idle"
                        log "STAGE1-TIMEOUT: $name task_status=$_s1_task_status stale for ${_s1_age}s, resetting to idle"
                        # cmd_1185 AC2: TIMEOUT後はGuard 2をバイパスしてmaybe_idleへ直接追加
                        # 理由: yaml_field_setでmtime更新→Guard 2が120s未満と誤判定→/clear永久スキップ
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
            _s1_unread_count=0
            if [ -f "$_s1_inbox_file" ]; then
                count_unread_messages_cached "$_s1_inbox_file" _s1_unread_count
                [[ ! "$_s1_unread_count" =~ ^[0-9]+$ ]] && _s1_unread_count=0
            fi
            if [ "$_s1_unread_count" -gt 0 ]; then
                log "SKIP_CLEAR: $name has unread inbox (${_s1_unread_count})"
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

    # ═══ CDP Chrome cleanup（task done/failed終端時、owner限定） ═══
    cleanup_terminal_task_cdps

    # ═══ STEP 1a: 家老陣形図の早期更新 ═══
    # 後段の定期gate/maintenanceが詰まっても、家老復帰・dashboardが古いsnapshotを掴まないようにする。
    refresh_karo_snapshot_fast_path

    process_checkpoint_manifests

    # Failed/BLOCK retro prompts are delivered only after the pane is idle and
    # before another task is assigned. Successful delivery moves the event to
    # awaiting_answer, which is the durable hold marker for deployment.
    for _retro_event in "$SCRIPT_DIR"/queue/retro/verbatim_pending/*.event \
        "$SCRIPT_DIR"/queue/retro/verbatim_awaiting_answer/*.event; do
        [ -f "$_retro_event" ] || continue
        mapfile -t _retro_fields < "$_retro_event"
        _retro_ninja="${_retro_fields[0]:-}"
        _retro_event_id="${_retro_fields[1]:-}"
        _retro_from="${_retro_fields[2]:-}"
        _retro_pane="${PANE_TARGETS[$_retro_ninja]:-}"
        _retro_task="$SCRIPT_DIR/queue/tasks/${_retro_ninja}.yaml"
        mkdir -p "$SCRIPT_DIR/queue/locks"
        exec {_retro_lock_fd}>"$SCRIPT_DIR/queue/locks/deploy_ninja_${_retro_ninja}.lock"
        flock -n "$_retro_lock_fd" || { eval "exec ${_retro_lock_fd}>&-"; continue; }
        source "$SCRIPT_DIR/scripts/lib/retro_pane_prompt.sh"
        if _retro_reconcile_reason=$(retro_pane_prompt_reconcile_pending "$SCRIPT_DIR" "$_retro_event" "$_retro_ninja" "$_retro_event_id"); then
            log "RETRO-TERMINAL-RECONCILED: ninja=$_retro_ninja event=$_retro_event_id reason=$_retro_reconcile_reason"
            flock -u "$_retro_lock_fd" || true
            eval "exec ${_retro_lock_fd}>&-"
            continue
        fi
        case "$_retro_event" in
            */verbatim_awaiting_answer/*)
                flock -u "$_retro_lock_fd" || true
                eval "exec ${_retro_lock_fd}>&-"
                continue
                ;;
        esac
        if [ -f "$_retro_task" ]; then
            _retro_status=$(awk '/^[[:space:]]*status:/ {gsub(/["'\''[:space:]]/, "", $2); print $2; exit}' "$_retro_task" 2>/dev/null || true)
            if ! [[ "$_retro_status" =~ ^(failed|blocked|idle|done)$ ]]; then eval "exec ${_retro_lock_fd}>&-"; continue; fi
        fi
        if [ -z "$_retro_pane" ] || ! check_idle "$_retro_pane" "$_retro_ninja"; then eval "exec ${_retro_lock_fd}>&-"; continue; fi
        if RETRO_PANE_TARGET="$_retro_pane" RETRO_PANE_IDLE_CHECK=true \
            retro_pane_prompt_deliver "$SCRIPT_DIR" "$_retro_ninja" "$_retro_event_id" "$_retro_from"; then
            bash "$SCRIPT_DIR/scripts/retro_write.sh" mark-delivered \
                "$_retro_ninja" "$_retro_event_id" "$(date -Iseconds)" >> "$LOG" 2>&1
            mkdir -p "$SCRIPT_DIR/queue/retro/verbatim_awaiting_answer"
            mv "$_retro_event" "$SCRIPT_DIR/queue/retro/verbatim_awaiting_answer/${_retro_event##*/}"
            log "RETRO-TERMINAL-DELIVER: ninja=$_retro_ninja pane_idle=1 next_task=0 delivery=1 duplicate=0"
        else
            log "RETRO-TERMINAL-BLOCK: ninja=$_retro_ninja delivery=0 retry=next_cycle"
        fi
        flock -u "$_retro_lock_fd" || true
        eval "exec ${_retro_lock_fd}>&-"
    done

    # terminal publish crash-window repair; bounded to one current report per ninja
    repair_terminal_report_outboxes

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

    # ═══ karo通知outbox flush (cmd_karo_hotfix_failed_report_clear_notify_gap AC3) ═══
    flush_karo_notify_outbox

    # ═══ Stale cmd検知チェック ═══
    check_stale_cmds

    # ═══ 未配備cmd常時監視（pending+delegated_at 10分超） ═══
    check_undeployed_cmds

    # ═══ Pending cmd検知チェック（2分間隔） ═══
    if [ $((cycle % 6)) -eq 0 ]; then
        check_karo_pending
    fi

    # ═══ 軍師LGTM後の家老未通知検知（2分間隔 cmd_karo_hotfix_completion_notify_gap） ═══
    if [ $((cycle % 6)) -eq 0 ]; then
        check_karo_completion_notify_gap
    fi

    # ═══ CI赤検知チェック（5分間隔 cmd_715） ═══
    check_disk_space_watch

    if [ $((cycle % 15)) -eq 0 ]; then
        bash "$SCRIPT_DIR/scripts/ci_status_check.sh" 2>>"$SCRIPT_DIR/logs/ci_status_check.log" || true
    fi

    # ═══ gate_improvement定期チェック（5分間隔 cmd_1114） ═══
    check_gate_improvement

    # ═══ throughput_scan定期チェック（5分間隔 cmd_3766） ═══
    check_throughput_scan

    # ═══ skill_auto_improve定期チェック（週1回 cmd_2605） ═══
    check_skill_auto_improve

    # ═══ effectiveness低下教訓deprecate候補の日次抽出（cmd_2757） ═══
    check_lesson_deprecation_candidates

    # ═══ 三層記憶tmp cleanup + dry-run候補抽出（60分間隔） ═══
    check_three_layer_maintenance

    # ═══ obsidian candidate自動昇格（日次 cmd_3240） ═══
    check_obsidian_candidate_promotion

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

    # ═══ STEP 1b: 後段チェック反映後の最終snapshot更新 ═══
    refresh_karo_snapshot_fast_path
    check_karo_idle_cycle       # 家老idle自走サイクル起動チェック (cmd_1498)
    check_throughput_ready_events # durable throughput connector (ready event exactly once)
    check_shogun_idle_analysis_trigger  # 将軍idle時自己分析trigger (cmd_3549)
    check_ntfy_listener_health  # ntfy_listenerゾンビ検知 (cmd_635)
    check_inbox_watcher_health  # inbox_watcher死亡検知+自動再起動 (おしお殿知見)
    # check_ninja_cli_dead — L5133で全エージェント版を毎サイクル先頭で実行済み(L821統合)
    run_lock_cleanup            # /tmp orphan lock files定期削除
    check_bulletin_archive      # 掲示板自動アーカイブ（肥大防止）
    drain_memory_db_live_insert_queue  # memory_db live insert退避queue排水

    # ═══ STEP 2: ダッシュボード自動更新 (cmd_404) ═══
    # 状態変化時のみ呼び出す（コスト最適化）
    current_idle=$(grep "^idle|" "$SCRIPT_DIR/queue/karo_snapshot.txt" 2>/dev/null | head -1 || echo "")
    # gate_metrics変化検知: wc -l(全量134KB読込)→stat mtime+size(メタデータのみ) (L511同原則: 全量scan回避)
    # 秒単位mtimeでは同一秒・同サイズ更新を見逃すため、ナノ秒mtime+path+sizeを使う。
    current_gate_sig=$(stat -c '%n:%y:%s' "$SCRIPT_DIR/logs/gate_metrics.log" 2>/dev/null || echo "missing")
    # context_warn_sig: 5分間隔キャッシュ（context_freshness_check.sh毎サイクル起動→WSL2プロセス起動コスト削減）
    _ctx_warn_now=$EPOCHSECONDS
    if (( _ctx_warn_now - CONTEXT_WARN_SIG_CHECK_LAST >= CONTEXT_WARN_SIG_CHECK_INTERVAL )); then
        CONTEXT_WARN_SIG_CACHE=$(timeout "$CONTEXT_WARN_SIG_TIMEOUT" bash "$SCRIPT_DIR/scripts/context_freshness_check.sh" --dashboard-warnings 2>/dev/null \
            | cksum | awk '{print $1 ":" $2}' || echo "missing")
        CONTEXT_WARN_SIG_CHECK_LAST=$_ctx_warn_now
    fi
    current_context_warn_sig="$CONTEXT_WARN_SIG_CACHE"
    # CI status: 5分間隔でキャッシュ更新（GitHubAPI毎サイクル呼出し→1708ms/cycle削減 L4-R24）
    _ci_check_now=$EPOCHSECONDS
    if (( _ci_check_now - CI_STATUS_CHECK_LAST >= CI_STATUS_CHECK_INTERVAL )); then
        CI_STATUS_CACHE=$(bash "$SCRIPT_DIR/scripts/ci_status_check.sh" --status 2>/dev/null || echo "UNKNOWN")
        CI_STATUS_CHECK_LAST=$_ci_check_now
    fi
    current_ci_status="$CI_STATUS_CACHE"
    check_ci_red_parallelization_guard "$current_ci_status" "$_ci_check_now"
    # unpushed count: 2分間隔キャッシュ（git rev-list毎サイクル実行→WSL2 git起動コスト削減）
    _unpushed_now=$EPOCHSECONDS
    if (( _unpushed_now - UNPUSHED_COUNT_CHECK_LAST >= UNPUSHED_COUNT_CHECK_INTERVAL )); then
        UNPUSHED_COUNT_CACHE=$(cd "$SCRIPT_DIR" && git rev-list origin/main..HEAD --count 2>/dev/null || echo 0)
        UNPUSHED_COUNT_CHECK_LAST=$_unpushed_now
    fi
    current_unpushed_count="$UNPUSHED_COUNT_CACHE"
    if [[ "$current_idle" != "$prev_idle" || "$current_gate_sig" != "$prev_gate_sig" || "$current_context_warn_sig" != "$prev_context_warn_sig" || "$current_ci_status" != "$prev_ci_status" || "$current_unpushed_count" != "$prev_unpushed_count" ]]; then
        bash "$SCRIPT_DIR/scripts/dashboard_auto_section.sh" 2>/dev/null || true
        prev_idle="$current_idle"
        prev_gate_sig="$current_gate_sig"
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
