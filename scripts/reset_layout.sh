#!/bin/bash
# reset_layout.sh — agentsウィンドウ(shogun:agents)一発復元
# ペイン配置・変数・レイアウト・watcherを初期状態に復元する
#
# Usage:
#   bash scripts/reset_layout.sh            # 実行
#   bash scripts/reset_layout.sh --dry-run  # 診断のみ（変更なし）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# ═══════════════════════════════════════════════════════════════
# オプション解析
# ═══════════════════════════════════════════════════════════════
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# ═══════════════════════════════════════════════════════════════
# 定数
# ═══════════════════════════════════════════════════════════════
EXPECTED_AGENTS=(karo sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)
PROMPT_COLORS=(red blue blue yellow yellow yellow yellow yellow yellow)
LAYOUT_STRING='1a7c,167x49,0,0{71x49,0,0[71x25,0,0,1,71x11,0,26,2,71x11,0,38,3],47x49,72,0[47x16,72,0,4,47x16,72,17,5,47x15,72,34,6],47x49,120,0[47x16,120,0,7,47x16,120,17,8,47x15,120,34,9]}'

# ═══════════════════════════════════════════════════════════════
# CLI Adapter読み込み
# ═══════════════════════════════════════════════════════════════
source "$SCRIPT_DIR/lib/cli_adapter.sh"
source "$SCRIPT_DIR/scripts/lib/model_colors.sh"

# シェル設定
SHELL_SETTING=$(grep '^shell:' config/settings.yaml 2>/dev/null | awk '{print $2}')
SHELL_SETTING="${SHELL_SETTING:-bash}"

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

# モデル表示名を解決（@model_name優先 — settings.yaml参照廃止）
# 引数: agent_id [pane_index]
_resolve_model_display() {
    local agent_id="$1"
    local pane="${2:-}"
    local ct
    ct=$(get_cli_type "$agent_id")

    case "$ct" in
        codex)   echo "Codex" ;;
        copilot) echo "Copilot" ;;
        kimi)    echo "Kimi" ;;
        claude|*)
            # @model_nameから取得（settings.yaml参照廃止）
            if [[ -n "$pane" ]]; then
                local cached
                cached=$(tmux show-options -p -t "shogun:agents.${pane}" -v @model_name 2>/dev/null || echo "")
                if [[ -n "$cached" ]]; then
                    echo "$cached"
                    return
                fi
            fi
            echo "Opus"  # fallback
            ;;
    esac
}

# ログ関数
log()      { echo "[reset_layout] $1"; }
log_ok()   { echo "[reset_layout] OK $1"; }
log_warn() { echo "[reset_layout] WARN $1"; }
log_err()  { echo "[reset_layout] ERROR $1"; }
log_dry()  { echo "[DRY-RUN] $1"; }

# カウンタ
swap_count=0
respawn_count=0
var_fix_count=0

# 復活ペイン追跡
declare -a RESPAWNED
for i in {0..8}; do RESPAWNED[$i]=0; done

# ═══════════════════════════════════════════════════════════════
# Step 1: 前提確認
# ═══════════════════════════════════════════════════════════════
log "Step 1: 前提確認"

PANE_BASE=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)
log "  pane-base-index=$PANE_BASE"

# shogun:agents に9ペイン存在するか確認。不足なら自動追加。
PANE_COUNT=$(tmux list-panes -t shogun:agents -F '#{pane_index}' 2>/dev/null | wc -l)
if [[ "$PANE_COUNT" -gt 9 ]]; then
    log_err "agentsウィンドウに${PANE_COUNT}ペイン（期待: 9）。余剰ペインの手動削除が必要"
    exit 1
fi

pane_add_count=0
if [[ "$PANE_COUNT" -lt 9 ]]; then
    missing=$((9 - PANE_COUNT))
    log "  ${PANE_COUNT}ペイン検出。${missing}ペイン追加"
    for ((m=0; m<missing; m++)); do
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "  split-window: 新ペイン追加 ($((m+1))/${missing})"
        else
            tmux split-window -t shogun:agents -h
            sleep 0.3
        fi
        ((pane_add_count++)) || true
    done

    if [[ "$DRY_RUN" != true ]]; then
        # 追加後: 既存agent_idを収集し、不足エージェントを未割当ペインに配置
        declare -A _existing_ids
        while IFS=$'\t' read -r _pi _aid; do
            [[ -n "$_aid" ]] && _existing_ids["$_aid"]=1
        done < <(tmux list-panes -t shogun:agents -F '#{pane_index}	#{@agent_id}')

        _missing_agents=()
        for _agent in "${EXPECTED_AGENTS[@]}"; do
            [[ -z "${_existing_ids[$_agent]:-}" ]] && _missing_agents+=("$_agent")
        done

        _unassigned_panes=()
        while IFS=$'\t' read -r _pi _aid; do
            [[ -z "$_aid" ]] && _unassigned_panes+=("$_pi")
        done < <(tmux list-panes -t shogun:agents -F '#{pane_index}	#{@agent_id}')

        for ((_a=0; _a<${#_missing_agents[@]}; _a++)); do
            if [[ $_a -lt ${#_unassigned_panes[@]} ]]; then
                tmux set-option -p -t "shogun:agents.${_unassigned_panes[$_a]}" @agent_id "${_missing_agents[$_a]}"
                log "  ${_missing_agents[$_a]} → agents.${_unassigned_panes[$_a]} に割当"
            fi
        done
    fi
fi
log_ok "9ペイン確認済み（追加: ${pane_add_count}件）"

# ═══════════════════════════════════════════════════════════════
# Step 2: ペイン配置修正（swap検出+修正）
# 前方走査: i=0から8まで順に、各ステップで1つ確定
# ═══════════════════════════════════════════════════════════════
log "Step 2: ペイン配置修正"

for i in {0..8}; do
    target_pane=$((PANE_BASE + i))
    expected="${EXPECTED_AGENTS[$i]}"
    actual=$(tmux show-options -p -t "shogun:agents.${target_pane}" -v @agent_id 2>/dev/null || echo "")

    if [[ "$actual" != "$expected" ]]; then
        # 期待するエージェントが実際にどのペインにいるか探索
        found_pane=""
        for j in $(seq $((i + 1)) 8); do
            check_pane=$((PANE_BASE + j))
            check_id=$(tmux show-options -p -t "shogun:agents.${check_pane}" -v @agent_id 2>/dev/null || echo "")
            if [[ "$check_id" == "$expected" ]]; then
                found_pane=$check_pane
                break
            fi
        done

        if [[ -n "$found_pane" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "  swap: agents.${target_pane}(${actual}) <-> agents.${found_pane}(${expected})"
            else
                tmux swap-pane -s "shogun:agents.${target_pane}" -t "shogun:agents.${found_pane}"
                log "  swap: agents.${target_pane}(${actual}) <-> agents.${found_pane}(${expected})"
            fi
            ((swap_count++)) || true
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

# 全ペインの死亡状態を一括取得
DEAD_MAP=$(tmux list-panes -t shogun:agents -F '#{pane_index} #{pane_dead}')

for i in {0..8}; do
    p=$((PANE_BASE + i))
    agent_id="${EXPECTED_AGENTS[$i]}"
    is_dead=$(echo "$DEAD_MAP" | awk -v p="$p" '$1==p {print $2}')

    if [[ "$is_dead" == "1" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "  respawn: agents.${p} (${agent_id}) — 死亡ペイン"
        else
            tmux respawn-pane -t "shogun:agents.${p}"
            sleep 0.5

            # cd + PS1設定
            prompt_str=$(_generate_prompt "${agent_id}" "${PROMPT_COLORS[$i]}")
            tmux send-keys -t "shogun:agents.${p}" "cd \"${SCRIPT_DIR}\" && export PS1='${prompt_str}' && clear" Enter
            sleep 0.5

            # CLI起動（build_cli_command経由 — settings.yaml+cli_profiles.yaml準拠）
            cli_cmd=$(build_cli_command "$agent_id")
            tmux send-keys -t "shogun:agents.${p}" "$cli_cmd" Enter

            log "  respawn: agents.${p} (${agent_id})"
        fi
        RESPAWNED[$i]=1
        ((respawn_count++)) || true
    fi
done
log_ok "respawn完了: ${respawn_count}件"

# ═══════════════════════════════════════════════════════════════
# Step 3.5: CLI未起動ペインにCLI起動
# 生存中だがCLI(claude/codex/copilot/kimi)が動いていないペインを検出
# ═══════════════════════════════════════════════════════════════
log "Step 3.5: CLI起動確認"

cli_start_count=0
PANE_PIDS=$(tmux list-panes -t shogun:agents -F '#{pane_index} #{pane_pid}')

for i in {0..8}; do
    p=$((PANE_BASE + i))
    agent_id="${EXPECTED_AGENTS[$i]}"

    # 既にStep 3でrespawnしたペインはCLI起動済み→スキップ
    [[ "${RESPAWNED[$i]}" == "1" ]] && continue

    # 死亡ペインはStep 3で処理済み（respawnされなかった=ありえないがガード）
    is_dead=$(echo "$DEAD_MAP" | awk -v p="$p" '$1==p {print $2}')
    [[ "$is_dead" == "1" ]] && continue

    # ペインのPIDを取得
    pane_pid=$(echo "$PANE_PIDS" | awk -v p="$p" '$1==p {print $2}')
    [[ -z "$pane_pid" ]] && continue

    # CLI プロセスが子プロセスに存在するか確認
    cli_process=$(pgrep -P "$pane_pid" -af 'claude|codex|copilot|kimi' 2>/dev/null || true)

    if [[ -z "$cli_process" ]]; then
        cli_cmd=$(build_cli_command "$agent_id")
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "  CLI起動: agents.${p} (${agent_id}) — ${cli_cmd}"
        else
            # cd + PS1設定
            prompt_str=$(_generate_prompt "${agent_id}" "${PROMPT_COLORS[$i]}")
            tmux send-keys -t "shogun:agents.${p}" "cd \"${SCRIPT_DIR}\" && export PS1='${prompt_str}' && clear" Enter
            sleep 0.5

            # CLI起動
            tmux send-keys -t "shogun:agents.${p}" "$cli_cmd" Enter

            log "  CLI起動: agents.${p} (${agent_id})"
        fi
        ((cli_start_count++)) || true
    fi
done
log_ok "CLI起動: ${cli_start_count}件"

# ═══════════════════════════════════════════════════════════════
# Step 4: 全ペイン変数の正規化
# @agent_id, @model_name, @agent_tier, @agent_cli → 常に再設定
# @context_pct, @current_task → 死亡ペインのみ初期化
# 背景色(bg=)、ペインタイトル(-T) → 常に再設定
# ═══════════════════════════════════════════════════════════════
log "Step 4: 全ペイン変数の正規化"

for i in {0..8}; do
    p=$((PANE_BASE + i))
    agent_id="${EXPECTED_AGENTS[$i]}"

    # tier決定
    if [[ $i -eq 0 ]]; then
        tier="karo"
    elif [[ $i -le 2 ]]; then
        tier="genin"
    else
        tier="jonin"
    fi

    # CLI type
    cli_t=$(get_cli_type "$agent_id")

    # モデル表示名
    model_display=$(_resolve_model_display "$agent_id" "$p")

    if [[ "$DRY_RUN" == true ]]; then
        # 現在値と比較して差分を表示
        cur_aid=$(tmux show-options -p -t "shogun:agents.${p}" -v @agent_id 2>/dev/null || echo "")
        cur_model=$(tmux show-options -p -t "shogun:agents.${p}" -v @model_name 2>/dev/null || echo "")
        cur_tier=$(tmux show-options -p -t "shogun:agents.${p}" -v @agent_tier 2>/dev/null || echo "")
        cur_cli=$(tmux show-options -p -t "shogun:agents.${p}" -v @agent_cli 2>/dev/null || echo "")

        changes=""
        [[ "$cur_aid" != "$agent_id" ]] && changes+=" @agent_id:${cur_aid:-empty}->${agent_id}"
        [[ "$cur_model" != "$model_display" ]] && changes+=" @model_name:${cur_model:-empty}->${model_display}"
        [[ "$cur_tier" != "$tier" ]] && changes+=" @agent_tier:${cur_tier:-empty}->${tier}"
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
        ((var_fix_count++)) || true
    else
        # 常に再設定（ずれ防止）
        tmux set-option -p -t "shogun:agents.${p}" @agent_id "$agent_id"
        tmux set-option -p -t "shogun:agents.${p}" @model_name "$model_display"
        tmux set-option -p -t "shogun:agents.${p}" @agent_tier "$tier"
        tmux set-option -p -t "shogun:agents.${p}" @agent_cli "$cli_t"

        # 背景色（モデル別動的決定）
        bg_color=$(resolve_bg_color "$agent_id" "$model_display")
        tmux select-pane -t "shogun:agents.${p}" -P "bg=${bg_color}"

        # ペインタイトル
        tmux select-pane -t "shogun:agents.${p}" -T "$model_display"

        # 死亡→復活したペインのみcontext変数初期化（生存ペインは維持）
        if [[ "${RESPAWNED[$i]}" == "1" ]]; then
            tmux set-option -p -t "shogun:agents.${p}" @context_pct "--"
            tmux set-option -p -t "shogun:agents.${p}" @current_task ""
        fi

        ((var_fix_count++)) || true
    fi
done
log_ok "変数正規化: ${var_fix_count}ペイン処理"

# ═══════════════════════════════════════════════════════════════
# Step 4.5: pane-border-format再適用
# shutsujin_departure.sh L21-23と同じ設定をWindow 2(agents)に適用
# Color: karo=#f9e2af(黄) Opus=#cba6f7(紫) Sonnet=#89b4fa(青) else=#a6e3a1(緑)
# ═══════════════════════════════════════════════════════════════
log "Step 4.5: pane-border-format再適用"

if [[ "$DRY_RUN" == true ]]; then
    log_dry "  tmux set-option -w -t shogun:2 pane-border-format '...model-based colors...'"
else
    tmux set-option -w -t shogun:2 pane-border-format \
      '#{?#{==:#{@agent_id},karo},#[fg=#f9e2af],#{?#{m:Opus*,#{@model_name}},#[fg=#cba6f7],#{?#{m:Sonnet*,#{@model_name}},#[fg=#89b4fa],#[fg=#a6e3a1]}}}#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]#{?#{!=:#{@inbox_count},},#[fg=#fab387]#{@inbox_count}#[default],} #{@current_task}' \
      2>/dev/null
    log_ok "pane-border-format再適用完了（Window 2）"
fi

# ═══════════════════════════════════════════════════════════════
# Step 5: レイアウト適用
# ═══════════════════════════════════════════════════════════════
log "Step 5: レイアウト適用"

if [[ "$DRY_RUN" == true ]]; then
    log_dry "  tmux select-layout -t shogun:agents '${LAYOUT_STRING}'"
else
    tmux select-layout -t "shogun:agents" "$LAYOUT_STRING"
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
printf "  %-4s %-10s %-5s %-7s %-8s %-10s %s\n" "Pane" "AgentID" "Dead" "Tier" "CLI" "Model" "BG"
echo "  ──────────────────────────────────────────────────────────"
for i in {0..8}; do
    p=$((PANE_BASE + i))
    _id=$(tmux show-options -p -t "shogun:agents.${p}" -v @agent_id 2>/dev/null || echo "?")
    _dead=$(tmux list-panes -t shogun:agents -F '#{pane_index} #{pane_dead}' | awk -v p="$p" '$1==p {print $2}')
    _tier=$(tmux show-options -p -t "shogun:agents.${p}" -v @agent_tier 2>/dev/null || echo "?")
    _cli=$(tmux show-options -p -t "shogun:agents.${p}" -v @agent_cli 2>/dev/null || echo "?")
    _model=$(tmux show-options -p -t "shogun:agents.${p}" -v @model_name 2>/dev/null || echo "?")
    _display=$(_resolve_model_display "$_id" "$p")
    _bg=$(resolve_bg_color "$_id" "$_display")
    printf "  %-4s %-10s %-5s %-7s %-8s %-10s %s\n" "$p" "$_id" "$_dead" "$_tier" "$_cli" "$_model" "$_bg"
done
echo "=========================================="
