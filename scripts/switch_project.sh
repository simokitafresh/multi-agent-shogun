#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# switch_project.sh — PJ切替時の全エージェント通知
# =============================================================================
# Usage: bash scripts/switch_project.sh <new-project-id>
#
# SKILL.md Step 5 で呼ばれるヘルパースクリプト。
# inbox_write broadcastを一括実行する。
# YAML更新やCLAUDE.md編集はSKILL.md内で将軍が実行する。
# =============================================================================

# SCRIPT_DIR/REPO_ROOT: string ops instead of $(cd) subshells (~15ms savings on WSL2)
_sw_self="${BASH_SOURCE[0]}"
[[ "$_sw_self" != /* ]] && _sw_self="$PWD/$_sw_self"
SCRIPT_DIR="${_sw_self%/switch_project.sh}"
REPO_ROOT="${SCRIPT_DIR%/scripts}"
unset _sw_self
PROJECTS_YAML="$REPO_ROOT/config/projects.yaml"

# --- 引数チェック ---
if [[ $# -lt 1 ]]; then
    echo "[switch_project] Usage: $0 <new-project-id>" >&2
    exit 1
fi

NEW_PROJECT_ID="$1"

# --- config/projects.yaml から情報取得（Bash組込み単一pass） ---
OLD_PROJECT_ID="" OLD_PROJECT_NAME="" NEW_PROJECT_NAME="" NEW_GIST_URL="" _cur_project=""
declare -A _project_names=()
while IFS= read -r _line; do
    case "$_line" in
        current_project:*)
            OLD_PROJECT_ID="${_line#current_project: }"
            while [[ "$OLD_PROJECT_ID" == *[[:space:]] ]]; do OLD_PROJECT_ID="${OLD_PROJECT_ID%?}"; done
            ;;
        '  - id: '*)
            _cur_project="${_line#  - id: }"
            while [[ "$_cur_project" == *[[:space:]] ]]; do _cur_project="${_cur_project%?}"; done
            ;;
        '    name: '*)
            _val="${_line#    name: }"
            while [[ "$_val" == *[[:space:]] ]]; do _val="${_val%?}"; done
            _val="${_val%\"}"; _val="${_val#\"}"
            _project_names["$_cur_project"]="$_val"
            [[ "$_cur_project" == "$NEW_PROJECT_ID" ]] && NEW_PROJECT_NAME="$_val"
            ;;
        '    gist_url: '*)
            if [[ "$_cur_project" == "$NEW_PROJECT_ID" ]]; then
                _val="${_line#    gist_url: }"
                while [[ "$_val" == *[[:space:]] ]]; do _val="${_val%?}"; done
                _val="${_val%\"}"; NEW_GIST_URL="${_val#\"}"
            fi
            ;;
    esac
done < "$PROJECTS_YAML"
OLD_PROJECT_NAME="${_project_names["$OLD_PROJECT_ID"]:-}"
unset _project_names _cur_project _line _val

if [[ -z "${OLD_PROJECT_ID:-}" ]]; then
    echo "[switch_project] ERROR: current_project not found in $PROJECTS_YAML" >&2
    exit 1
fi

if [[ "$NEW_PROJECT_ID" == "$OLD_PROJECT_ID" ]]; then
    echo "[switch_project] SKIP: already on project '$OLD_PROJECT_ID'. No switch needed." >&2
    exit 0
fi

if [[ -z "$NEW_PROJECT_NAME" ]]; then
    echo "[switch_project] ERROR: project '$NEW_PROJECT_ID' not found in $PROJECTS_YAML" >&2
    exit 1
fi

# --- 全エージェントに inbox_write で通知（並列化: 直列N×50ms → 並列max(50ms), ~350ms削減） ---
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/agent_config.sh"
read -ra AGENTS <<< "$(get_all_agents)"
MSG="PJフォーカス切替: ${OLD_PROJECT_NAME} → ${NEW_PROJECT_NAME}。次の/clear時に新PJ知識がロードされる。"

for agent in "${AGENTS[@]}"; do
    if [[ "${DRY_RUN:-}" = "1" ]]; then
        echo "[switch_project] DRY_RUN: inbox_write $agent skipped" >&2
    else
        bash "$SCRIPT_DIR/inbox_write.sh" "$agent" "$MSG" project_switch shogun &
    fi
done
wait

echo "[switch_project] ${#AGENTS[@]}名に通知送信完了 (${OLD_PROJECT_NAME} → ${NEW_PROJECT_NAME})"

# --- ntfy で殿に新PJのGist URLを通知（NEW_GIST_URLは上のawk passで取得済み） ---

if [[ "${DRY_RUN:-}" = "1" ]]; then
    echo "[switch_project] DRY_RUN: ntfy skipped" >&2
elif [[ -n "$NEW_GIST_URL" ]]; then
    bash "$SCRIPT_DIR/ntfy.sh" "PJ切替: ${NEW_PROJECT_NAME} ダッシュボード: ${NEW_GIST_URL}"
    echo "[switch_project] ntfy通知送信: ${NEW_PROJECT_NAME} Gist URL"
else
    echo "[switch_project] gist_url未設定のためntfy通知スキップ: ${NEW_PROJECT_ID}"
fi
