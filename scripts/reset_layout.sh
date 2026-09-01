#!/bin/bash
# semantic-links: [[インフラ運用基盤]]
# reset_layout.sh — agentsウィンドウ(shogun:agents)一発復元
# ペイン配置・変数・レイアウト・watcherを初期状態に復元する
#
# Usage:
#   bash scripts/reset_layout.sh                    # 全量復元
#   bash scripts/reset_layout.sh --dry-run           # 診断のみ（変更なし）
#   bash scripts/reset_layout.sh --agent <id>        # 単一エージェントrespawn
#   bash scripts/reset_layout.sh --agent <id> --dry-run  # 単一respawn診断

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# すべてのCLI入力送出は、実tmuxのsocket/session/targetを解決する共通guardを
# 直前に通す。attachedな本番shogunは明示許可なしでfail-closedにする。
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/tmux_live_send_guard.sh"

# ═══════════════════════════════════════════════════════════════
# オプション解析
# ═══════════════════════════════════════════════════════════════
DRY_RUN=false
TARGET_AGENT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --agent)   TARGET_AGENT="${2:-}"; shift 2 ;;
        *)         shift ;;
    esac
done

# ═══════════════════════════════════════════════════════════════
# 並行実行ガード（flock排他）
# split-window/swap-pane/CLI起動は非原子的な複数tmux操作の連鎖であり、
# 2重起動されるとメガバッチで取得したペイン索引が互いに古くなり、
# 想定外のペインにCLI起動コマンドが送られて@agent_id未設定の
# 無主ペインが生じ得る（2026-07-03 cmd_karo_hotfix_auto_update_pane_spawn調査）。
# restart_watchers.sh(FD200)と衝突しないようFD201を使用。
LOCK_FILE="/tmp/shogun_reset_layout.lock"
exec 201>"$LOCK_FILE"
if ! flock -n 201; then
    echo "[reset_layout] SKIP: another reset_layout.sh instance is already running (lock: $LOCK_FILE)"
    exit 0
fi

# shogun:main remain-on-exit on: CLIプロセス終了時にpane残存させwindow消滅を防止
# 根因: remain-on-exit off(デフォルト)→CLI死→pane削除→window内pane 0→window消滅(2026-07-15事故)

# ═══════════════════════════════════════════════════════════════
# 定数: lib キャッシュ source
# 7 NTFS ファイル個別source (~167ms) → tmpfs 1ファイルsource (~9ms)
# キャッシュは /tmp (WSL2 ext4) に保存。/tmp のみ削除で再生成。
# ═══════════════════════════════════════════════════════════════
_LIB_CACHE="/tmp/shogun_reset_layout_lib.sh"
if [[ ! -f "$_LIB_CACHE" ]] || ! grep -q 'MODEL_FAMILY_HELPER_VERSION="2"' "$_LIB_CACHE" 2>/dev/null; then
    cat "$SCRIPT_DIR/scripts/lib/agent_config.sh" \
        "$SCRIPT_DIR/scripts/lib/cli_lookup.sh" \
        "$SCRIPT_DIR/scripts/lib/model_family.sh" \
        "$SCRIPT_DIR/scripts/lib/model_colors.sh" \
        "$SCRIPT_DIR/scripts/lib/model_detect.sh" \
        "$SCRIPT_DIR/scripts/lib/model_resolve.sh" \
        "$SCRIPT_DIR/scripts/lib/pane_format.sh" \
        "$SCRIPT_DIR/scripts/lib/layout_string.sh" \
        > "$_LIB_CACHE" 2>/dev/null \
    || {
        # fallback: 個別source
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
        source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
        source "$SCRIPT_DIR/scripts/lib/model_family.sh"
        source "$SCRIPT_DIR/scripts/lib/model_colors.sh"
        source "$SCRIPT_DIR/scripts/lib/model_detect.sh"
        source "$SCRIPT_DIR/scripts/lib/model_resolve.sh"
        source "$SCRIPT_DIR/scripts/lib/pane_format.sh"
        source "$SCRIPT_DIR/scripts/lib/layout_string.sh"
        _LIB_CACHE=""
    }
fi
if [[ -n "$_LIB_CACHE" ]]; then
    # Pre-set path vars: lib files use BASH_SOURCE[0] for path resolution.
    # When sourced from /tmp, BASH_SOURCE is wrong → pre-set overrides it.
    _AGENT_CONFIG_SCRIPT_DIR="$SCRIPT_DIR"
    CLI_ADAPTER_SETTINGS="$SCRIPT_DIR/config/settings.yaml"
    CLI_LOOKUP_PROFILES="$SCRIPT_DIR/config/cli_profiles.yaml"
    # shellcheck source=/dev/null
    source "$_LIB_CACHE"
fi

# get_all_agents() は監視用に shogun を含む (agent_config.sh L160) が、agents window に
# shogun ペインは無い(将軍は shogun:main 専有)。含めると NUM_AGENTS が実ペイン数(8)を超え、
# Step1で余剰ペイン追加 / Step2で誤swap が起き、2-3-3レイアウトが崩壊する。
# shogun を除外し karo=pane(base), gunshi=pane(base+1)... の正準マッピング(pane_lookup.sh準拠)に揃える。
EXPECTED_AGENTS=()
for _ea0 in $(get_all_agents); do
    [ "$_ea0" = "shogun" ] && continue
    EXPECTED_AGENTS+=("$_ea0")
done
unset _ea0
# karo=red, gunshi=cyan, ninjas=yellow (動的生成)
PROMPT_COLORS=()
for _ea in "${EXPECTED_AGENTS[@]}"; do
    case "$(get_agent_role "$_ea")" in
        karo)   PROMPT_COLORS+=(red) ;;
        gunshi) PROMPT_COLORS+=(cyan) ;;
        *)      PROMPT_COLORS+=(yellow) ;;
    esac
done
unset _ea
NUM_AGENTS=${#EXPECTED_AGENTS[@]}
AGENTS_WINDOW_TARGET="${TMUX_WINDOW:-shogun:agents}"

# シェル設定
SHELL_SETTING=$(grep '^shell:' config/settings.yaml 2>/dev/null | awk '{print $2}')
SHELL_SETTING="${SHELL_SETTING:-bash}"

# ═══════════════════════════════════════════════════════════════
# Mega batch: 1 tmux + 1 ps + 2 awk で全ステップの入力データを一括取得
# 従来の tmux list-panes 4回 → 1回に統合
# build_cli_command N回の python3 subprocess → 0回に削減
# ═══════════════════════════════════════════════════════════════

# --- tmux mega batch (replaces 4 separate list-panes calls) ---
declare -A _MB_AID _MB_DEAD _MB_PID _MB_MODEL _MB_GROUP _MB_CLI
_MB_PANE_COUNT=0
while IFS=$'\t' read -r _pi _aid _dead _pid _mod _grp _cli; do
    [[ -n "$_pi" ]] || continue
    _MB_AID["$_pi"]="$_aid"
    _MB_DEAD["$_pi"]="$_dead"
    _MB_PID["$_pi"]="$_pid"
    _MB_MODEL["$_pi"]="$_mod"
    _MB_GROUP["$_pi"]="$_grp"
    _MB_CLI["$_pi"]="$_cli"
    _MB_PANE_COUNT=$((_MB_PANE_COUNT+1))
done < <(tmux list-panes -t "$AGENTS_WINDOW_TARGET" \
    -F '#{pane_index}	#{@agent_id}	#{pane_dead}	#{pane_pid}	#{@model_name}	#{@agent_group}	#{@agent_cli}')

# --- ps batch (CLI process detection) ---
declare -A _MB_CLI_RUNNING
# 子プロセスにCLI名があるか (従来ロジック)
while read -r _ppid _comm; do
    _ppid="${_ppid#"${_ppid%%[![:space:]]*}"}"
    [[ -n "$_ppid" ]] && _MB_CLI_RUNNING["$_ppid"]=1
done < <(ps -eo ppid,comm 2>/dev/null | grep -E 'claude|codex|copilot|kimi' || true)
# pane_pid自体がCLIプロセスか (Claude Codeはpane直接プロセスとして動く。子はMCPサーバーのみ)
for _pp in "${_MB_PID[@]}"; do
    [[ -z "$_pp" ]] && continue
    [[ -n "${_MB_CLI_RUNNING[$_pp]:-}" ]] && continue
    _self_comm=$(ps -p "$_pp" -o comm= 2>/dev/null || true)
    [[ "$_self_comm" =~ (claude|codex|copilot|kimi) ]] && _MB_CLI_RUNNING["$_pp"]=1
done

# --- settings.yaml batch: agent → type, model_name (replaces N×python3 subshells) ---
declare -A _MB_AGENT_TYPE _MB_AGENT_MODEL_NAME
while IFS=$'\t' read -r _ag _type _mname; do
    [[ -n "$_ag" ]] || continue
    case "$_type" in claude|codex|copilot|kimi) ;; *) _type="claude" ;; esac
    _MB_AGENT_TYPE["$_ag"]="$_type"
    _MB_AGENT_MODEL_NAME["$_ag"]="$_mname"
done < <(awk '
    /^cli:/ { c=1; next }
    c && !/^[[:space:]]/ { exit }
    c && /^  default:/ { sub(/.*: */,""); gsub(/[[:space:]]+$/,""); d=$0; next }
    c && /^  agents:/ { a=1; next }
    a && /^    [a-z]/ {
        if (n!="") print n "\t" (t!="" ? t : (d!="" ? d : "claude")) "\t" mn
        n=$0; sub(/^[[:space:]]+/,"",n)
        if (n ~ /: /) { t=n; sub(/.*: /,"",t); gsub(/[[:space:]]+$/,"",t); sub(/:.*/,"",n) }
        else { sub(/:.*$/,"",n); t="" }
        mn=""
        next
    }
    a && n!="" && /^      type:/ { sub(/.*: */,""); gsub(/[[:space:]]+$/,""); t=$0; next }
    a && n!="" && /^      model_name:/ { sub(/.*: */,""); gsub(/[[:space:]]+$/,""); mn=$0; next }
    a && /^[^[:space:]]/ { if (n!="") print n "\t" (t!="" ? t : (d!="" ? d : "claude")) "\t" mn; exit }
    END { if (n!="" && a) print n "\t" (t!="" ? t : (d!="" ? d : "claude")) "\t" mn }
' config/settings.yaml)

# --- cli_profiles.yaml batch: type → launch_cmd, launch_args ---
declare -A _MB_PROFILE_CMD _MB_PROFILE_ARGS
while IFS=$'\t' read -r _ptype _pcmd _pargs; do
    [[ -n "$_ptype" ]] || continue
    _MB_PROFILE_CMD["$_ptype"]="$_pcmd"
    _MB_PROFILE_ARGS["$_ptype"]="$_pargs"
done < <(awk '
    /^profiles:/ { p=1; next }
    p && /^  [a-z]/ {
        if (t!="") print t "\t" cmd "\t" args
        t=$0; sub(/^  /,"",t); sub(/:.*$/,"",t)
        cmd=""; args=""
        next
    }
    p && /^    launch_cmd:/ { sub(/.*: */,""); gsub(/^"|"$/,""); cmd=$0; next }
    p && /^    launch_args:/ { sub(/.*: */,""); gsub(/^"|"$/,""); args=$0; next }
    p && /^[^[:space:]]/ { if (t!="") print t "\t" cmd "\t" args; exit }
    END { if (t!="" && p) print t "\t" cmd "\t" args }
' config/cli_profiles.yaml)

# --- Pre-build all CLI commands (replaces per-agent build_cli_command calls) ---
declare -A _MB_CLI_CMD
for _ag in "${EXPECTED_AGENTS[@]}"; do
    _MB_CLI_CMD["$_ag"]="$(cli_launch_cmd "$_ag")"
done

# ═══════════════════════════════════════════════════════════════
# ヘルパー関数
# ═══════════════════════════════════════════════════════════════

# プロンプト生成（shutsujin_departure.sh generate_prompt()相当）
_generate_prompt() {
    local label="$1"
    local color="$2"

    if [[ "$SHELL_SETTING" == "zsh" ]]; then
        echo "(%F{${color}}%B${label}%b%f) %F{green}%B%~%b%f%# "
    else
        local color_code
        case "$color" in
            red)     color_code="1;31" ;;
            green)   color_code="1;32" ;;
            yellow)  color_code="1;33" ;;
            blue)    color_code="1;34" ;;
            magenta) color_code="1;35" ;;
            cyan)    color_code="1;36" ;;
            *)       color_code="1;37" ;;
        esac
        echo "(\[\033[${color_code}m\]${label}\[\033[0m\]) \[\033[1;32m\]\w\[\033[0m\]\$ "
    fi
}

# モデル表示名を解決（model_resolve.shに委譲。pane_indexからtarget構築）
_resolve_model_display() {
    local agent_id="$1"
    local pane="${2:-}"
    if [[ -n "$pane" ]]; then
        resolve_model_display "$agent_id" "${AGENTS_WINDOW_TARGET}.${pane}"
    else
        resolve_model_display "$agent_id"
    fi
}

# 表示グループを解決（将軍編成の現在値）
_resolve_agent_group() {
    local agent_id="$1"
    local cli_type="$2"
    local model_display="$3"

    if [[ "$agent_id" == "karo" ]]; then
        echo "karo"
        return 0
    fi

    case "$cli_type" in
        codex|copilot|kimi)
            echo "$cli_type"
            ;;
        claude|*)
            model_family_reset_group "$model_display"
            ;;
    esac
}

# ログ関数
log()      { echo "[reset_layout] $1"; }
log_ok()   { echo "[reset_layout] OK $1"; }
log_warn() { echo "[reset_layout] WARN $1"; }
log_err()  { echo "[reset_layout] ERROR $1"; }
log_dry()  { echo "[DRY-RUN] $1"; }

# WSL boot直後の /tmp 掃除完了前にtmuxへ接続するとsocketが消えてghost serverになる。
# active/inactive は完了済み、unknown/空はsystemd非導入またはservice不在として無音通過。
# ─── CLI ready 待ち(stagger) (2026-09-01) ───
# Codex は起動時に ~/.codex/logs_2.sqlite を排他初期化する。複数 pane を sleep 0 で
# 連続起動すると 'database is locked' で全滅(09-01 11:23 実証)。respawn 後は当該 pane の
# CLI ready(可視画面のプロンプト記号=cli_profiles idle_pattern: claude=❯ / codex=›)を待ってから
# 次へ進む。timeout でも処理は止めず WARN のみ。shutsujin_departure.sh CLI_READY_REGEX と同値。
_RL_CLI_READY_REGEX='^[[:space:]]*(❯|›)([[:space:]]|$)|bypass permissions on'
_rl_wait_cli_ready() {
    local target="$1" label="$2" limit="${RESET_LAYOUT_CLI_READY_TIMEOUT:-60}" i
    for ((i=1; i<=limit; i++)); do
        if tmux capture-pane -t "$target" -p 2>/dev/null | grep -Eq "$_RL_CLI_READY_REGEX"; then
            log "  ${label}: CLI ready (${i}s)"
            return 0
        fi
        sleep 1
    done
    log "  WARN ${label}: CLI not ready after ${limit}s (pane=${target})"
    return 1
}

wait_for_tmpfiles_setup() {
    local service="systemd-tmpfiles-setup.service"
    local timeout="${TMPFILES_SETUP_TIMEOUT_SEC:-300}"
    local interval="${TMPFILES_SETUP_POLL_INTERVAL_SEC:-1}"
    local state elapsed started_at

    command -v systemctl >/dev/null 2>&1 || return 0

    state="$(systemctl is-active "$service" 2>/dev/null || true)"
    case "$state" in
        active|inactive|unknown|"") return 0 ;;
        failed)
            log_warn "${service} がfailedのためtmux操作を中断"
            return 1
            ;;
        activating) ;;
        *)
            log_warn "${service} の状態が不明(${state})のためtmux操作を中断"
            return 1
            ;;
    esac

    [[ "$timeout" =~ ^[0-9]+$ ]] || timeout=300
    [[ "$interval" =~ ^[0-9]+([.][0-9]+)?$ ]] || interval=1
    log_warn "${service} がactivatingのため完了まで待機（上限${timeout}秒）"
    started_at="$(date +%s)"
    while :; do
        state="$(systemctl is-active "$service" 2>/dev/null || true)"
        case "$state" in
            active|inactive|unknown)
                elapsed=$(( $(date +%s) - started_at ))
                log "${service} 完了確認（待機${elapsed}秒）"
                return 0
                ;;
            failed)
                log_warn "${service} がfailedになったためtmux操作を中断"
                return 1
                ;;
            activating) ;;
            *)
                log_warn "${service} の状態が不明(${state})のためtmux操作を中断"
                return 1
                ;;
        esac
        elapsed=$(( $(date +%s) - started_at ))
        if (( elapsed >= timeout )); then
            log_warn "${service} の完了待ちがtimeout（${timeout}秒）のためtmux操作を中断"
            return 1
        fi
        sleep "$interval"
    done
}

if ! wait_for_tmpfiles_setup; then
    exit 1
fi

tmux set-option -w -t shogun:main remain-on-exit on 2>/dev/null || true

# 同一socket pathのtmux serverを検知して一覧化する。停止は行わず、
# 現socket所有者を保護したうえで重複時はfail-closedにする。
inspect_duplicate_tmux_servers() {
    local owner_info current_pid current_socket record socket pid queue_pid child_pid child_parent child_comm child_args
    local -a records=() descendants=() pending=()
    local -A socket_counts=() socket_pids=() seen=() descendant_seen=()

    command -v ss >/dev/null 2>&1 || {
        log_warn "tmux server検知に必要なssが見つからないため復元を保留"
        return 1
    }
    owner_info="$(tmux display-message -p '#{pid}|#{socket_path}' 2>/dev/null || true)"
    current_pid="${owner_info%%|*}"
    current_socket="${owner_info#*|}"
    if [[ "$owner_info" == "$current_pid" || ! "$current_pid" =~ ^[0-9]+$ || "$current_socket" != /* ]]; then
        if [[ "${TMUX:-}" == *,*,* ]]; then
            current_socket="${TMUX%%,*}"
            current_pid="${TMUX#*,}"
            current_pid="${current_pid%%,*}"
        fi
    fi

    mapfile -t records < <(
        ss -xlpH 2>/dev/null | awk '
            $1 == "u_str" && $5 ~ /^\// && $0 ~ /tmux: server/ {
                socket=$5; rest=$0
                while (match(rest, /pid=[0-9]+/)) {
                    print socket "\t" substr(rest, RSTART + 4, RLENGTH - 4)
                    rest=substr(rest, RSTART + RLENGTH)
                }
            }
        '
    )
    for record in "${records[@]}"; do
        socket="${record%%$'\t'*}"
        pid="${record#*$'\t'}"
        [[ "$socket" == /* && "$pid" =~ ^[0-9]+$ ]] || continue
        [[ -n "${seen[$socket:$pid]:-}" ]] && continue
        seen["$socket:$pid"]=1
        socket_counts["$socket"]=$(( ${socket_counts[$socket]:-0} + 1 ))
        socket_pids["$socket"]+=" ${pid}"
    done

    for socket in "${!socket_counts[@]}"; do
        (( socket_counts[$socket] > 1 )) || continue
        if [[ "$current_socket" != "$socket" || ! "$current_pid" =~ ^[0-9]+$ ]]; then
            log_warn "同一socket pathのtmux server複数検知だが現owner不明。停止せず復元を保留: socket=${socket} servers=${socket_pids[$socket]}"
            return 1
        fi
        log_warn "同一socket pathのtmux server複数検知: socket=${socket}"
        for pid in ${socket_pids[$socket]}; do
            if [[ "$pid" == "$current_pid" ]]; then
                log "  現socket所有者を保護: pid=${pid} socket=${socket}"
                continue
            fi
            log_warn "  旧tmux server一覧: pid=${pid} socket=${socket}"
            pending=("$pid")
            descendants=()
            descendant_seen=( ["$pid"]=1 )
            while ((${#pending[@]})); do
                queue_pid="${pending[0]}"; pending=("${pending[@]:1}")
                while read -r child_pid child_parent child_comm child_args; do
                    [[ "$child_parent" == "$queue_pid" ]] || continue
                    [[ -n "${descendant_seen[$child_pid]:-}" ]] && continue
                    descendant_seen["$child_pid"]=1
                    pending+=("$child_pid")
                    descendants+=("$child_pid")
                    log_warn "    配下process一覧: pid=${child_pid} ppid=${child_parent} cmd=${child_comm} ${child_args}"
                done < <(ps -eo pid=,ppid=,comm=,args= 2>/dev/null || true)
            done
        done
        log_warn "重複serverの実際の停止は殿の操作境界。自動処理を行わず復元を保留"
        return 1
    done
    return 0
}

inspect_duplicate_tmux_servers

# ═══════════════════════════════════════════════════════════════
# --agent <id> モード: 単一エージェントのペインをrespawn
# 全量復元をスキップし、対象ペインのみrespawn-pane -k+変数+CLI起動
# ═══════════════════════════════════════════════════════════════
if [[ -n "$TARGET_AGENT" ]]; then
    # 対象エージェントのペインを探索
    target_pane=""
    target_idx=""
    while IFS=$'\t' read -r _pi _aid; do
        if [[ "$_aid" == "$TARGET_AGENT" ]]; then
            target_pane="$_pi"
            break
        fi
    done < <(tmux list-panes -t "$AGENTS_WINDOW_TARGET" \
        -F '#{pane_index}	#{@agent_id}' 2>/dev/null)

    if [[ -z "$target_pane" ]]; then
        log_err "${TARGET_AGENT} のペインが見つかりません"
        exit 1
    fi

    # EXPECTED_AGENTSからインデックスを特定(PS1色用)
    for ((i=0; i<NUM_AGENTS; i++)); do
        if [[ "${EXPECTED_AGENTS[$i]}" == "$TARGET_AGENT" ]]; then
            target_idx=$i
            break
        fi
    done

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "--agent ${TARGET_AGENT}: agents.${target_pane} をrespawn予定"
        exit 0
    fi

    log "--agent ${TARGET_AGENT}: agents.${target_pane} をrespawn"
    tmux respawn-pane -k -t "${AGENTS_WINDOW_TARGET}.${target_pane}"
    tmux clear-history -t "${AGENTS_WINDOW_TARGET}.${target_pane}" 2>/dev/null || true
    sleep 0.5

    # cd + PS1
    prompt_color="${PROMPT_COLORS[$target_idx]:-yellow}"
    prompt_str=$(_generate_prompt "${TARGET_AGENT}" "$prompt_color")
    tmux_live_send_guard "${AGENTS_WINDOW_TARGET}.${target_pane}"
    tmux send-keys -t "${AGENTS_WINDOW_TARGET}.${target_pane}" "cd \"${SCRIPT_DIR}\" && export PS1='${prompt_str}' && clear" Enter
    sleep 0.5

    # tmux変数設定
    cli_t="${_MB_AGENT_TYPE[$TARGET_AGENT]:-claude}"
    model_display=$(_resolve_model_display "$TARGET_AGENT" "$target_pane")
    agent_group=$(_resolve_agent_group "$TARGET_AGENT" "$cli_t" "$model_display")
    bg_color=$(resolve_bg_color "$TARGET_AGENT" "$model_display")

    tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${target_pane}" @agent_id "$TARGET_AGENT"
    tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${target_pane}" @model_name "$model_display"
    tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${target_pane}" @agent_group "$agent_group"
    tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${target_pane}" @agent_cli "$cli_t"
    tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${target_pane}" @context_pct "--"
    tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${target_pane}" @current_task ""
    tmux select-pane -t "${AGENTS_WINDOW_TARGET}.${target_pane}" -P "bg=${bg_color}"
    tmux select-pane -t "${AGENTS_WINDOW_TARGET}.${target_pane}" -T "$model_display"

    # CLI起動
    cli_cmd="${_MB_CLI_CMD[$TARGET_AGENT]}"
    tmux_live_send_guard "${AGENTS_WINDOW_TARGET}.${target_pane}"
    tmux send-keys -t "${AGENTS_WINDOW_TARGET}.${target_pane}" "$cli_cmd" Enter
    _rl_wait_cli_ready "${AGENTS_WINDOW_TARGET}.${target_pane}" "${TARGET_AGENT}" || true

    log_ok "${TARGET_AGENT} respawn完了 (pane=${target_pane}, cli=${cli_t}, model=${model_display})"
    exit 0
fi

# カウンタ
swap_count=0
respawn_count=0
var_fix_count=0

# 復活ペイン追跡
declare -a RESPAWNED
for ((i=0; i<NUM_AGENTS; i++)); do RESPAWNED[i]=0; done

# ═══════════════════════════════════════════════════════════════
# Step 1: 前提確認
# ═══════════════════════════════════════════════════════════════
log "Step 1: 前提確認"

# Infer pane-base-index from mega batch (min pane_index) — avoids extra tmux call
if [[ $_MB_PANE_COUNT -gt 0 ]]; then
    PANE_BASE=9999
    for _pi in "${!_MB_AID[@]}"; do
        (( _pi < PANE_BASE )) && PANE_BASE=$_pi
    done
else
    PANE_BASE=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 1)
fi
log "  pane-base-index=$PANE_BASE"

# shogun:agents にNUM_AGENTSペイン存在するか確認。不足なら自動追加。
# Use mega batch data (tmux list-panes was already called once at startup)
declare -A _STEP2_AID
PANE_COUNT="$_MB_PANE_COUNT"
for _pi in "${!_MB_AID[@]}"; do
    _STEP2_AID["$_pi"]="${_MB_AID[$_pi]}"
done

# Claude Agent Teams and stale split-window shells can leave child panes in the
# agents window with no @agent_id. They are not part of the Shogun agent roster
# and collapse the fixed 8-pane agents layout. When the pane count already
# exceeds the expected roster, auto-remove only unowned panes before applying the
# normal excess-pane guard.
if [[ "$PANE_COUNT" -gt "$NUM_AGENTS" ]]; then
    _orphan_panes=()
    while IFS=$'\t' read -r _pi _aid _start_cmd; do
        if [[ -z "$_aid" ]]; then
            _orphan_panes+=("$_pi")
        fi
    done < <(tmux list-panes -t "$AGENTS_WINDOW_TARGET" -F '#{pane_index}	#{@agent_id}	#{pane_start_command}' 2>/dev/null || true)

    if [[ ${#_orphan_panes[@]} -gt 0 ]]; then
        for _pi in "${_orphan_panes[@]}"; do
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "  remove orphan unowned pane: agents.${_pi}"
            else
                log_warn "未所有paneを検知: agents.${_pi}。除去は殿の操作境界へ委譲"
                exit 1
            fi
        done

        if [[ "$DRY_RUN" != true ]]; then
            sleep 0.2
            _MB_AID=()
            _MB_DEAD=()
            _MB_PID=()
            _MB_MODEL=()
            _MB_GROUP=()
            _MB_CLI=()
            _STEP2_AID=()
            _MB_PANE_COUNT=0
            while IFS=$'\t' read -r _pi _aid _dead _pid _mod _grp _cli; do
                [[ -n "$_pi" ]] || continue
                _MB_AID["$_pi"]="$_aid"
                _MB_DEAD["$_pi"]="$_dead"
                _MB_PID["$_pi"]="$_pid"
                _MB_MODEL["$_pi"]="$_mod"
                _MB_GROUP["$_pi"]="$_grp"
                _MB_CLI["$_pi"]="$_cli"
                _STEP2_AID["$_pi"]="$_aid"
                _MB_PANE_COUNT=$((_MB_PANE_COUNT+1))
            done < <(tmux list-panes -t "$AGENTS_WINDOW_TARGET" \
                -F '#{pane_index}	#{@agent_id}	#{pane_dead}	#{pane_pid}	#{@model_name}	#{@agent_group}	#{@agent_cli}')
            PANE_COUNT="$_MB_PANE_COUNT"
        fi
    fi
fi

if [[ "$PANE_COUNT" -gt "$NUM_AGENTS" ]]; then
    log_err "agentsウィンドウに${PANE_COUNT}ペイン（期待: ${NUM_AGENTS}）。余剰ペインの手動削除が必要"
    exit 1
fi

pane_add_count=0
if [[ "$PANE_COUNT" -lt "$NUM_AGENTS" ]]; then
    missing=$((NUM_AGENTS - PANE_COUNT))
    log "  ${PANE_COUNT}ペイン検出。${missing}ペイン追加"
    for ((m=0; m<missing; m++)); do
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "  split-window: 新ペイン追加 ($((m+1))/${missing})"
        else
            tmux split-window -t "$AGENTS_WINDOW_TARGET" -h
            sleep 0.3
        fi
        pane_add_count=$((pane_add_count+1))
    done

    if [[ "$DRY_RUN" != true ]]; then
        # 追加後: 既存agent_idを収集し、不足エージェントを未割当ペインに配置
        declare -A _existing_ids
        while IFS=$'\t' read -r _pi _aid; do
            [[ -n "$_aid" ]] && _existing_ids["$_aid"]=1
        done < <(tmux list-panes -t "$AGENTS_WINDOW_TARGET" -F '#{pane_index}	#{@agent_id}')

        _missing_agents=()
        for _agent in "${EXPECTED_AGENTS[@]}"; do
            [[ -z "${_existing_ids[$_agent]:-}" ]] && _missing_agents+=("$_agent")
        done

        _unassigned_panes=()
        while IFS=$'\t' read -r _pi _aid; do
            [[ -z "$_aid" ]] && _unassigned_panes+=("$_pi")
        done < <(tmux list-panes -t "$AGENTS_WINDOW_TARGET" -F '#{pane_index}	#{@agent_id}')

        for ((_a=0; _a<${#_missing_agents[@]}; _a++)); do
            if [[ $_a -lt ${#_unassigned_panes[@]} ]]; then
                tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${_unassigned_panes[$_a]}" @agent_id "${_missing_agents[$_a]}"
                log "  ${_missing_agents[$_a]} → agents.${_unassigned_panes[$_a]} に割当"
            fi
        done
    fi
fi
log_ok "${NUM_AGENTS}ペイン確認済み（追加: ${pane_add_count}件）"

# ═══════════════════════════════════════════════════════════════
# Step 2: ペイン配置修正（swap検出+修正）
# 前方走査: i=0からNUM_AGENTS-1まで順に、各ステップで1つ確定
# ═══════════════════════════════════════════════════════════════
log "Step 2: ペイン配置修正"

LAST_IDX=$((NUM_AGENTS - 1))
# _STEP2_AID: mega batch-read（Step 1前）で取得済み
for ((i=0; i<=LAST_IDX; i++)); do
    target_pane=$((PANE_BASE + i))
    expected="${EXPECTED_AGENTS[$i]}"
    actual="${_STEP2_AID[$target_pane]:-}"

    if [[ "$actual" != "$expected" ]]; then
        # 期待するエージェントが実際にどのペインにいるか探索（batch mapから参照）
        found_pane=""
        for ((j=i+1; j<=LAST_IDX; j++)); do
            check_pane=$((PANE_BASE + j))
            if [[ "${_STEP2_AID[$check_pane]:-}" == "$expected" ]]; then
                found_pane=$check_pane
                break
            fi
        done

        if [[ -n "$found_pane" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "  swap: agents.${target_pane}(${actual}) <-> agents.${found_pane}(${expected})"
            else
                tmux swap-pane -s "${AGENTS_WINDOW_TARGET}.${target_pane}" -t "${AGENTS_WINDOW_TARGET}.${found_pane}"
                log "  swap: agents.${target_pane}(${actual}) <-> agents.${found_pane}(${expected})"
            fi
            # batch mapをswap後の状態に同期
            _STEP2_AID[$target_pane]="$expected"
            _STEP2_AID[$found_pane]="$actual"
            swap_count=$((swap_count+1))
        else
            log_warn "  ${expected} がどのペインにも見つかりません（@agent_id未設定の可能性）"
        fi
    fi
done
log_ok "swap完了: ${swap_count}件"

# ═══════════════════════════════════════════════════════════════
# Step 3: 死亡ペイン復活
# ═══════════════════════════════════════════════════════════════
log "Step 3: 死亡ペイン検出・復活"

# Use mega batch data (DEAD_MAP from startup mega batch)
declare -A DEAD_MAP
for _pi in "${!_MB_DEAD[@]}"; do
    DEAD_MAP["$_pi"]="${_MB_DEAD[$_pi]}"
done

for ((i=0; i<=LAST_IDX; i++)); do
    p=$((PANE_BASE + i))
    agent_id="${EXPECTED_AGENTS[$i]}"
    is_dead="${DEAD_MAP[$p]:-0}"

    if [[ "$is_dead" == "1" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "  respawn: agents.${p} (${agent_id}) — 死亡ペイン"
        else
            tmux respawn-pane -t "${AGENTS_WINDOW_TARGET}.${p}"
            # respawn-paneはscrollback履歴を引き継ぐ(tmux仕様)。前セッション残像防止(殿実測2026-07-08)
            tmux clear-history -t "${AGENTS_WINDOW_TARGET}.${p}" 2>/dev/null || true
            sleep 0.5

            # cd + PS1設定
            prompt_str=$(_generate_prompt "${agent_id}" "${PROMPT_COLORS[$i]}")
            tmux_live_send_guard "${AGENTS_WINDOW_TARGET}.${p}"
            tmux send-keys -t "${AGENTS_WINDOW_TARGET}.${p}" "cd \"${SCRIPT_DIR}\" && export PS1='${prompt_str}' && clear" Enter
            sleep 0.5

            # CLI起動（mega batch pre-built command — settings.yaml+cli_profiles.yaml準拠）
            cli_cmd="${_MB_CLI_CMD[$agent_id]}"
            tmux_live_send_guard "${AGENTS_WINDOW_TARGET}.${p}"
            tmux send-keys -t "${AGENTS_WINDOW_TARGET}.${p}" "$cli_cmd" Enter
            _rl_wait_cli_ready "${AGENTS_WINDOW_TARGET}.${p}" "${agent_id}" || true

            log "  respawn: agents.${p} (${agent_id})"
        fi
        RESPAWNED[i]=1
        respawn_count=$((respawn_count+1))
    fi
done
log_ok "respawn完了: ${respawn_count}件"

# ═══════════════════════════════════════════════════════════════
# Step 3.5: CLI未起動ペインにCLI起動
# 生存中だがCLI(claude/codex/copilot/kimi)が動いていないペインを検出
# ═══════════════════════════════════════════════════════════════
log "Step 3.5: CLI起動確認"

cli_start_count=0
# Use mega batch data (PID map + CLI running map from startup)

for ((i=0; i<=LAST_IDX; i++)); do
    p=$((PANE_BASE + i))
    agent_id="${EXPECTED_AGENTS[$i]}"

    # 既にStep 3でrespawnしたペインはCLI起動済み→スキップ
    [[ "${RESPAWNED[$i]}" == "1" ]] && continue

    # 死亡ペインはStep 3で処理済み（respawnされなかった=ありえないがガード）
    is_dead="${DEAD_MAP[$p]:-0}"
    [[ "$is_dead" == "1" ]] && continue

    # ペインのPIDを取得（mega batch）
    pane_pid="${_MB_PID[$p]:-}"
    [[ -z "$pane_pid" ]] && continue

    # CLI プロセスが子プロセスに存在するか確認（mega batch mapから参照）
    if [[ -z "${_MB_CLI_RUNNING[$pane_pid]:-}" ]]; then
        cli_cmd="${_MB_CLI_CMD[$agent_id]}"
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "  CLI起動: agents.${p} (${agent_id}) — ${cli_cmd}"
        else
            # cd + PS1設定
            prompt_str=$(_generate_prompt "${agent_id}" "${PROMPT_COLORS[$i]}")
            tmux_live_send_guard "${AGENTS_WINDOW_TARGET}.${p}"
            tmux send-keys -t "${AGENTS_WINDOW_TARGET}.${p}" "cd \"${SCRIPT_DIR}\" && export PS1='${prompt_str}' && clear" Enter
            sleep 0.5

            # CLI起動
            tmux_live_send_guard "${AGENTS_WINDOW_TARGET}.${p}"
            tmux send-keys -t "${AGENTS_WINDOW_TARGET}.${p}" "$cli_cmd" Enter
            _rl_wait_cli_ready "${AGENTS_WINDOW_TARGET}.${p}" "${agent_id}" || true

            log "  CLI起動: agents.${p} (${agent_id})"
        fi
        cli_start_count=$((cli_start_count+1))
    fi
done
log_ok "CLI起動: ${cli_start_count}件"

# ═══════════════════════════════════════════════════════════════
# Step 4: 全ペイン変数の正規化
# @agent_id, @model_name, @agent_group, @agent_cli → 常に再設定
# @context_pct, @current_task → 死亡ペインのみ初期化
# 背景色(bg=)、ペインタイトル(-T) → 常に再設定
# ═══════════════════════════════════════════════════════════════
log "Step 4: 全ペイン変数の正規化"

# ─── Use mega batch data (pane vars + CLI type from startup) ───

for ((i=0; i<=LAST_IDX; i++)); do
    p=$((PANE_BASE + i))
    agent_id="${EXPECTED_AGENTS[$i]}"

    # CLI type (from mega batch — no subshell)
    cli_t="${_MB_AGENT_TYPE[$agent_id]:-claude}"

    # モデル表示名 — use cached @model_name to avoid expensive detect_real_model
    model_display="${_MB_MODEL[$p]:-}"
    if [[ -z "$model_display" ]]; then
        model_display=$(_resolve_model_display "$agent_id" "$p")
    fi
    agent_group=$(_resolve_agent_group "$agent_id" "$cli_t" "$model_display")

    if [[ "$DRY_RUN" == true ]]; then
        # 現在値と比較して差分を表示 (mega batch data, no per-pane tmux calls)
        cur_aid="${_MB_AID[$p]:-}"
        cur_model="${_MB_MODEL[$p]:-}"
        cur_group="${_MB_GROUP[$p]:-}"
        cur_cli="${_MB_CLI[$p]:-}"

        changes=""
        [[ "$cur_aid" != "$agent_id" ]] && changes+=" @agent_id:${cur_aid:-empty}->${agent_id}"
        [[ "$cur_model" != "$model_display" ]] && changes+=" @model_name:${cur_model:-empty}->${model_display}"
        [[ "$cur_group" != "$agent_group" ]] && changes+=" @agent_group:${cur_group:-empty}->${agent_group}"
        [[ "$cur_cli" != "$cli_t" ]] && changes+=" @agent_cli:${cur_cli:-empty}->${cli_t}"

        bg_color=$(resolve_bg_color "$agent_id" "$model_display")
        if [[ -n "$changes" ]]; then
            log_dry "  agents.${p} (${agent_id}):${changes} bg=${bg_color}"
        else
            log_dry "  agents.${p} (${agent_id}): bg=${bg_color}"
        fi
        if [[ "${RESPAWNED[$i]}" == "1" ]]; then
            log_dry "  agents.${p} (${agent_id}): @context_pct,@current_task を初期化"
        fi
        var_fix_count=$((var_fix_count+1))
    else
        # 常に再設定（ずれ防止）
        tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${p}" @agent_id "$agent_id"
        tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${p}" @model_name "$model_display"
        tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${p}" @agent_group "$agent_group"
        tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${p}" @agent_cli "$cli_t"

        # 背景色（モデル別動的決定）
        bg_color=$(resolve_bg_color "$agent_id" "$model_display")
        tmux select-pane -t "${AGENTS_WINDOW_TARGET}.${p}" -P "bg=${bg_color}"

        # ペインタイトル
        tmux select-pane -t "${AGENTS_WINDOW_TARGET}.${p}" -T "$model_display"

        # 死亡→復活したペインのみcontext変数初期化（生存ペインは維持）
        if [[ "${RESPAWNED[$i]}" == "1" ]]; then
            tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${p}" @context_pct "--"
            tmux set-option -p -t "${AGENTS_WINDOW_TARGET}.${p}" @current_task ""
        fi

        var_fix_count=$((var_fix_count+1))
    fi
done
log_ok "変数正規化: ${var_fix_count}ペイン処理"

# ═══════════════════════════════════════════════════════════════
# Step 4.5: pane-border-format再適用
# 色定義・フォーマット文字列は pane_format.sh に集約（DRY原則）
# ═══════════════════════════════════════════════════════════════
log "Step 4.5: pane-border-format再適用"

if [[ "$DRY_RUN" == true ]]; then
    log_dry "  tmux set-option -w -t ${AGENTS_WINDOW_TARGET} pane-border-format '...model-based colors...'"
else
    tmux set-option -w -t "$AGENTS_WINDOW_TARGET" pane-border-format \
      "$AGENTS_PANE_BORDER_FORMAT" \
      2>/dev/null
    log_ok "pane-border-format再適用完了（Window 2）"
fi

# ═══════════════════════════════════════════════════════════════
# Step 5: レイアウト適用
# ═══════════════════════════════════════════════════════════════
log "Step 5: レイアウト適用（動的LAYOUT_STRING生成）"

LAYOUT_STRING=$(generate_layout_string "$AGENTS_WINDOW_TARGET" "$PANE_BASE")
if [[ "$DRY_RUN" == true ]]; then
    log_dry "  tmux select-layout -t ${AGENTS_WINDOW_TARGET} '${LAYOUT_STRING}'"
else
    tmux select-layout -t "$AGENTS_WINDOW_TARGET" "$LAYOUT_STRING"
    log_ok "レイアウト適用完了"
fi

# ═══════════════════════════════════════════════════════════════
# Step 6: inbox_watcher再起動
# ═══════════════════════════════════════════════════════════════
log "Step 6: inbox_watcher再起動"

if [[ "$DRY_RUN" == true ]]; then
    log_dry "  bash scripts/restart_watchers.sh（スキップ）"
else
    bash "$SCRIPT_DIR/scripts/restart_watchers.sh"
    log_ok "watcher再起動完了（restart_watchers.sh + sync_pane_vars.sh）"
fi

# ═══════════════════════════════════════════════════════════════
# Step 7: 結果サマリ
# ═══════════════════════════════════════════════════════════════
echo ""
echo "=========================================="
if [[ "$DRY_RUN" == true ]]; then
    echo " reset_layout 診断結果（DRY-RUN）"
else
    echo " reset_layout 完了サマリ"
fi
echo "=========================================="
echo "  ペイン追加:  ${pane_add_count}件"
echo "  swap件数:    ${swap_count}"
echo "  respawn件数: ${respawn_count}"
echo "  CLI起動:     ${cli_start_count}件"
echo "  変数処理:    ${var_fix_count}ペイン"
echo ""
echo "  最終ペイン一覧:"
echo "  ────────────────────────────────────────────────────"
printf "  %-4s %-10s %-5s %-8s %-8s %-10s %s\n" "Pane" "AgentID" "Dead" "Group" "CLI" "Model" "BG"
echo "  ──────────────────────────────────────────────────────────"
# Summary query: 1 tmux call for current state (after any modifications above)
_summary=$(tmux list-panes -t "$AGENTS_WINDOW_TARGET" \
    -F '#{pane_index}	#{@agent_id}	#{pane_dead}	#{@agent_group}	#{@agent_cli}	#{@model_name}')
while IFS=$'\t' read -r _p _id _dead _group _cli _model; do
    [[ -z "$_p" ]] && continue
    _model="${_model:-$MODEL_FAMILY_DISPLAY_OPUS}"
    _bg=$(resolve_bg_color "$_id" "$_model")
    printf "  %-4s %-10s %-5s %-8s %-8s %-10s %s\n" "$_p" "$_id" "$_dead" "$_group" "$_cli" "$_model" "$_bg"
done <<< "$_summary"
echo "=========================================="
