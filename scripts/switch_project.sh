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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECTS_YAML="$REPO_ROOT/config/projects.yaml"

# --- 引数チェック ---
if [[ $# -lt 1 ]]; then
    echo "[switch_project] Usage: $0 <new-project-id>" >&2
    exit 1
fi

NEW_PROJECT_ID="$1"

# --- config/projects.yaml から情報取得 ---

# 旧 current_project を取得
OLD_PROJECT_ID=$(grep '^current_project:' "$PROJECTS_YAML" | awk '{print $2}')
if [[ -z "$OLD_PROJECT_ID" ]]; then
    echo "[switch_project] ERROR: current_project not found in $PROJECTS_YAML" >&2
    exit 1
fi

# 旧PJ名を取得（id行の次のname行）
OLD_PROJECT_NAME=$(awk -v id="$OLD_PROJECT_ID" '
    /^  - id:/ { found = ($3 == id) }
    found && /name:/ { gsub(/^[^"]*"|"[^"]*$/, "", $0); print; exit }
' "$PROJECTS_YAML")

# 新PJ名を取得
NEW_PROJECT_NAME=$(awk -v id="$NEW_PROJECT_ID" '
    /^  - id:/ { found = ($3 == id) }
    found && /name:/ { gsub(/^[^"]*"|"[^"]*$/, "", $0); print; exit }
' "$PROJECTS_YAML")

if [[ -z "$NEW_PROJECT_NAME" ]]; then
    echo "[switch_project] ERROR: project '$NEW_PROJECT_ID' not found in $PROJECTS_YAML" >&2
    exit 1
fi

# --- 全エージェントに inbox_write で通知 ---
AGENTS=(karo sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)
MSG="PJフォーカス切替: ${OLD_PROJECT_NAME} → ${NEW_PROJECT_NAME}。次の/clear時に新PJ知識がロードされる。"

sent=0
for agent in "${AGENTS[@]}"; do
    bash "$SCRIPT_DIR/inbox_write.sh" "$agent" "$MSG" project_switch shogun
    ((sent++))
done

echo "[switch_project] ${sent}名に通知送信完了 (${OLD_PROJECT_NAME} → ${NEW_PROJECT_NAME})"

# --- ntfy で殿に新PJのGist URLを通知 ---
NEW_GIST_URL=$(awk -v id="$NEW_PROJECT_ID" '
    /^  - id:/ { found = ($3 == id) }
    found && /gist_url:/ { gsub(/^[^"]*"|"[^"]*$/, "", $0); print; exit }
' "$PROJECTS_YAML")

if [[ -n "$NEW_GIST_URL" ]]; then
    bash "$SCRIPT_DIR/ntfy.sh" "PJ切替: ${NEW_PROJECT_NAME} ダッシュボード: ${NEW_GIST_URL}"
    echo "[switch_project] ntfy通知送信: ${NEW_PROJECT_NAME} Gist URL"
else
    echo "[switch_project] gist_url未設定のためntfy通知スキップ: ${NEW_PROJECT_ID}"
fi
