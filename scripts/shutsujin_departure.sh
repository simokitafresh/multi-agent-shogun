#!/bin/bash
# shutsujin_departure.sh — セッション起動時の初期設定スクリプト
# Usage: bash scripts/shutsujin_departure.sh [--dry-run]
#
# tmuxセッション作成後、エージェント起動前に実行する。
# セッション固有の設定を適用する。

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

_self="${BASH_SOURCE[0]}"
_self_dir="${_self%/*}"
[[ "$_self_dir" != /* ]] && _self_dir="$(cd "$_self_dir" && pwd)"
SCRIPT_DIR="${_self_dir%/scripts}"
STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"
AGENTS_PANE_BORDER_FORMAT_PLACEHOLDER='<agent/model/context/inbox/task>'

source_optional() {
    local source_path="$1"
    # shellcheck source=/dev/null
    [ -f "$source_path" ] && source "$source_path"
}

log_dry() {
    echo "[DRY-RUN] $1"
}

run_or_preview() {
    local preview="$1"
    shift
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "$preview"
    else
        "$@"
    fi
}

if [[ "$DRY_RUN" == true ]]; then
    log_dry "mkdir -p ${STATE_DIR}"
else
    mkdir -p "$STATE_DIR"
fi

# ─── 指揮官デフォルトCLI復元（Opus保証） ───
# /switch-to-codex でsettings.yamlが変更されていても、再起動時はデフォルトOpusに戻す。
# 殿裁定(2026-04-22): デフォルトは将軍・家老・軍師=Opus。Codex切替は手動スキル実行時のみ。
_SETTINGS="$SCRIPT_DIR/config/settings.yaml"
for _commander in karo gunshi; do
    if grep -q "^    ${_commander}:" "$_SETTINGS" 2>/dev/null; then
        _current_type=$(awk "/^    ${_commander}:/{found=1} found && /type:/{print \$2; exit}" "$_SETTINGS" 2>/dev/null)
        if [[ "$_current_type" == "codex" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "[DRY-RUN] Reset ${_commander} type: codex → claude (default Opus)"
            else
                sed -i "/^    ${_commander}:/,/^    [a-z]/{s/type: codex/type: claude/}" "$_SETTINGS" 2>/dev/null
                echo "[shutsujin] Reset ${_commander}: codex → claude (default Opus)"
            fi
        fi
    fi
done

# dry-run hot path では agent_config.sh 以外の source を遅延する
source_optional "$SCRIPT_DIR/scripts/lib/agent_config.sh"
if [[ "$DRY_RUN" != true ]]; then
    source_optional "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
    source_optional "$SCRIPT_DIR/scripts/lib/model_detect.sh"
    source_optional "$SCRIPT_DIR/scripts/lib/pane_format.sh"
fi

# 互換ターゲット解決（window名優先、なければ従来index）
resolve_window_target() {
    local named_target="$1"
    local indexed_target="$2"
    if tmux list-panes -t "$named_target" >/dev/null 2>&1; then
        echo "$named_target"
    else
        echo "$indexed_target"
    fi
}

resolve_first_pane_target() {
    local window_target="$1"
    if [[ "$DRY_RUN" == true ]]; then
        echo "${window_target}.1"
        return 0
    fi
    local pane_index
    pane_index=$(tmux list-panes -t "$window_target" -F '#{pane_index}' 2>/dev/null | head -1)
    if [ -n "$pane_index" ]; then
        echo "${window_target}.${pane_index}"
    else
        # pane-base-index=1前提の最終フォールバック
        echo "${window_target}.1"
    fi
}

layout_is_normalized() {
    local pane_base pane_rows row_count=0
    local expected_agents=()
    local expected_count expected_index
    local pane_index pane_dead agent_id model_name agent_group agent_cli

    if ! declare -F get_all_agents >/dev/null 2>&1; then
        return 1
    fi

    read -ra expected_agents <<< "$(get_all_agents 2>/dev/null || echo "")"
    expected_count=${#expected_agents[@]}
    [[ "$expected_count" -gt 0 ]] || return 1

    pane_base=$(tmux show-options -gv pane-base-index 2>/dev/null || echo 0)
    pane_rows=$(tmux list-panes -t "$AGENTS_WINDOW_TARGET" \
        -F '#{pane_index}|#{pane_dead}|#{@agent_id}|#{@model_name}|#{@agent_group}|#{@agent_cli}' \
        2>/dev/null) || return 1

    while IFS='|' read -r pane_index pane_dead agent_id model_name agent_group agent_cli; do
        [[ -n "$pane_index" ]] || continue
        ((row_count++))
        expected_index=$((pane_base + row_count - 1))

        [[ "$pane_index" == "$expected_index" ]] || return 1
        [[ "$pane_dead" == "0" ]] || return 1
        [[ "$agent_id" == "${expected_agents[$((row_count - 1))]}" ]] || return 1
        [[ -n "$model_name" ]] || return 1
        [[ -n "$agent_group" ]] || return 1
        [[ -n "$agent_cli" ]] || return 1
    done <<< "$pane_rows"

    [[ "$row_count" -eq "$expected_count" ]]
}

if [[ "$DRY_RUN" == true ]]; then
    SHOGUN_WINDOW_TARGET="shogun:main"
    AGENTS_WINDOW_TARGET="shogun:agents"
else
    SHOGUN_WINDOW_TARGET=$(resolve_window_target "shogun:main" "shogun:1")
    AGENTS_WINDOW_TARGET=$(resolve_window_target "shogun:agents" "shogun:2")
fi

# ─── agentsウィンドウ自動作成 (cmd_1357) ───
# ウィンドウ不在時に自動作成し、ターゲットを再解決
if [[ "$DRY_RUN" != true ]] && ! tmux list-windows -t shogun -F '#{window_name}' | grep -q '^agents$'; then
    run_or_preview "tmux new-window -t shogun -n agents" tmux new-window -t shogun -n agents
    AGENTS_WINDOW_TARGET=$(resolve_window_target "shogun:agents" "shogun:2")
fi

SHOGUN_PANE_TARGET=$(resolve_first_pane_target "$SHOGUN_WINDOW_TARGET")
LAYOUT_FAST_PATH=false
if [[ "$DRY_RUN" == true ]] && layout_is_normalized; then
    LAYOUT_FAST_PATH=true
fi

# ─── remain-on-exit (cmd_183) ───
# CLIプロセスが死んでもペインを残す（OOM Kill等の原因調査用）
# agents windowのみ。将軍windowは不要。
run_or_preview \
    "tmux set-option -w -t ${AGENTS_WINDOW_TARGET} remain-on-exit on" \
    tmux set-option -w -t "$AGENTS_WINDOW_TARGET" remain-on-exit on 2>/dev/null

echo "[shutsujin] remain-on-exit: on (${AGENTS_WINDOW_TARGET})"

# ─── pane-border-format with inbox count (cmd_188) ───
# 色定義・フォーマット文字列は pane_format.sh に集約（DRY原則）
run_or_preview \
  "tmux set-option -w -t ${AGENTS_WINDOW_TARGET} pane-border-format '${AGENTS_PANE_BORDER_FORMAT_PLACEHOLDER}'" \
  tmux set-option -w -t "$AGENTS_WINDOW_TARGET" pane-border-format \
  "${AGENTS_PANE_BORDER_FORMAT:-$AGENTS_PANE_BORDER_FORMAT_PLACEHOLDER}" \
  2>/dev/null

# shogun: Opus紫(#cba6f7) + model_name + context_pct
run_or_preview \
  "tmux set-option -w -t ${SHOGUN_WINDOW_TARGET} pane-border-status top" \
  tmux set-option -w -t "$SHOGUN_WINDOW_TARGET" pane-border-status top 2>/dev/null
run_or_preview \
  "tmux set-option -w -t ${SHOGUN_WINDOW_TARGET} pane-border-format '<agent/model/context>'" \
  tmux set-option -w -t "$SHOGUN_WINDOW_TARGET" pane-border-format \
  '#[fg=#cba6f7]#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]' \
  2>/dev/null

# 将軍ペイン変数を補正（@model_nameは実モデル優先）
run_or_preview \
    "tmux set-option -p -t ${SHOGUN_PANE_TARGET} @agent_id shogun" \
    tmux set-option -p -t "$SHOGUN_PANE_TARGET" @agent_id shogun 2>/dev/null
shogun_model=""
if [[ "$DRY_RUN" != true ]]; then
    source_optional "$SCRIPT_DIR/lib/cli_adapter.sh"
    source_optional "$SCRIPT_DIR/scripts/lib/model_colors.sh"
    source_optional "$SCRIPT_DIR/scripts/lib/model_resolve.sh"
    shogun_model=$(tmux show-options -p -t "$SHOGUN_PANE_TARGET" -v @model_name 2>/dev/null || echo "")
    if declare -F detect_real_model >/dev/null 2>&1; then
        detected_model=$(detect_real_model shogun "$SHOGUN_PANE_TARGET" 2>/dev/null || echo "")
        if [ -n "$detected_model" ]; then
            shogun_model="$detected_model"
        fi
    fi
fi
if [ -z "$shogun_model" ] && [[ "$DRY_RUN" != true ]] && declare -F cli_profile_get >/dev/null 2>&1; then
    shogun_model=$(cli_profile_get shogun "display_name" 2>/dev/null || echo "")
fi
shogun_model="${shogun_model:-Unknown}"
run_or_preview \
    "tmux set-option -p -t ${SHOGUN_PANE_TARGET} @model_name ${shogun_model}" \
    tmux set-option -p -t "$SHOGUN_PANE_TARGET" @model_name "$shogun_model" 2>/dev/null

echo "[shutsujin] pane-border-format: applied (${SHOGUN_WINDOW_TARGET}, ${AGENTS_WINDOW_TARGET})"
echo "[shutsujin] shogun pane vars: @agent_id=shogun @model_name=${shogun_model} (${SHOGUN_PANE_TARGET})"

# ─── status bar style: Catppuccin Mocha base ───
run_or_preview \
    'tmux set-option -g status-style "bg=#1e1e2e,fg=#cdd6f4"' \
    tmux set-option -g status-style "bg=#1e1e2e,fg=#cdd6f4" 2>/dev/null
echo "[shutsujin] status-style: Catppuccin Mocha base (#1e1e2e)"

# ─── session status-right: datetime ───
run_or_preview \
    "tmux set-option -t shogun status-right-length 200" \
    tmux set-option -t shogun status-right-length 200
run_or_preview \
    "tmux set-option -t shogun status-right '#[fg=#cdd6f4]%Y-%m-%d %H:%M'" \
    tmux set-option -t shogun status-right "#[fg=#cdd6f4]%Y-%m-%d %H:%M"

echo "[shutsujin] status-right: datetime only"


# ─── Prefix+v: clipboard screenshot capture (cmd_551) ───
run_or_preview \
    "tmux bind-key v run-shell 'bash ${SCRIPT_DIR}/scripts/capture_clipboard_image.sh'" \
    tmux bind-key v run-shell "bash ${SCRIPT_DIR}/scripts/capture_clipboard_image.sh"
echo "[shutsujin] keybind: Prefix+v → capture_clipboard_image.sh"

# ─── idle flag initialization (cmd_455) ───
if [[ "$DRY_RUN" == true && "$LAYOUT_FAST_PATH" == true ]]; then
    log_dry "touch ${STATE_DIR}/shogun_idle_{all_agents}"
else
    for agent in $(get_all_agents); do
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "touch ${STATE_DIR}/shogun_idle_${agent}"
        else
            touch "${STATE_DIR}/shogun_idle_${agent}"
        fi
    done
fi
echo "[shutsujin] idle flags: created for all agents"

# ─── レイアウト正規化 (agents window) ───
# ペイン配置・サイズを正規状態に復元（再起動後にレイアウトが崩れる問題の根本対策）
_layout_already_normalized="$LAYOUT_FAST_PATH"
if [[ "$_layout_already_normalized" == true ]]; then
    echo "[shutsujin] layout: reset_layout.sh skipped (already normalized)"
elif layout_is_normalized; then
    _layout_already_normalized=true
    echo "[shutsujin] layout: reset_layout.sh skipped (already normalized)"
elif [[ "$DRY_RUN" == true ]]; then
    log_dry "bash ${SCRIPT_DIR}/scripts/reset_layout.sh --dry-run"
    bash "$SCRIPT_DIR/scripts/reset_layout.sh" --dry-run
else
    bash "$SCRIPT_DIR/scripts/reset_layout.sh"
fi
if [[ "$_layout_already_normalized" == true ]]; then
    echo "[shutsujin] layout: normalized"
else
    echo "[shutsujin] layout: reset_layout.sh applied"
fi
