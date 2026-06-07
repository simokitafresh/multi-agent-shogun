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

# --- config/projects.yaml から情報取得（2 awk pass: grep+awk×4 → awk×2, ~30ms削減） ---

# Pass 1: current_project のみ取得（単純な1行検索）
OLD_PROJECT_ID=$(awk '/^current_project:/{print $2; exit}' "$PROJECTS_YAML")
if [[ -z "$OLD_PROJECT_ID" ]]; then
    echo "[switch_project] ERROR: current_project not found in $PROJECTS_YAML" >&2
    exit 1
fi

if [[ "$NEW_PROJECT_ID" == "$OLD_PROJECT_ID" ]]; then
    echo "[switch_project] SKIP: already on project '$OLD_PROJECT_ID'. No switch needed." >&2
    exit 0
fi

# Pass 2: OLD名・NEW名・NEW gist_url を1 awk passで一括取得（3 awk → 1 awk）
OLD_PROJECT_NAME="" NEW_PROJECT_NAME="" NEW_GIST_URL=""
while IFS=$'\t' read -r _key _val; do
    case "$_key" in
        old_name) OLD_PROJECT_NAME="$_val" ;;
        new_name) NEW_PROJECT_NAME="$_val" ;;
        new_gist) NEW_GIST_URL="$_val" ;;
    esac
done < <(awk -v old_id="$OLD_PROJECT_ID" -v new_id="$NEW_PROJECT_ID" '
    /^  - id:/ { cur = $3 }
    cur != "" && /^    name:/ {
        v = $0; sub(/^[^:]+:[[:space:]]*"?/, "", v); sub(/"[[:space:]]*$/, "", v); gsub(/[[:space:]]+$/, "", v)
        if (cur == old_id) printf "old_name\t%s\n", v
        if (cur == new_id) printf "new_name\t%s\n", v
    }
    cur != "" && cur == new_id && /^    gist_url:/ {
        v = $0; sub(/^[^:]+:[[:space:]]*"?/, "", v); sub(/"[[:space:]]*$/, "", v); gsub(/[[:space:]]+$/, "", v)
        printf "new_gist\t%s\n", v
    }
' "$PROJECTS_YAML")

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
    bash "$SCRIPT_DIR/inbox_write.sh" "$agent" "$MSG" project_switch shogun &
done
wait

echo "[switch_project] ${#AGENTS[@]}名に通知送信完了 (${OLD_PROJECT_NAME} → ${NEW_PROJECT_NAME})"

# --- ntfy で殿に新PJのGist URLを通知（NEW_GIST_URLは上のawk passで取得済み） ---

if [[ -n "$NEW_GIST_URL" ]]; then
    bash "$SCRIPT_DIR/ntfy.sh" "PJ切替: ${NEW_PROJECT_NAME} ダッシュボード: ${NEW_GIST_URL}"
    echo "[switch_project] ntfy通知送信: ${NEW_PROJECT_NAME} Gist URL"
else
    echo "[switch_project] gist_url未設定のためntfy通知スキップ: ${NEW_PROJECT_ID}"
fi
