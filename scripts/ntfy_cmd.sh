#!/bin/bash
# ntfy_cmd.sh — cmd通知にpurpose自動付加ラッパー
#
# Usage: bash scripts/ntfy_cmd.sh <cmd_id> "<message>"
#
# shogun_to_karo.yamlからcmdのpurposeを自動取得し、
# 通知に文脈を付加してntfy.sh経由で送信する。
# cmd_idが見つからない場合もエラーにならず、purposeなしで送信する。
#
# 出力例:
#   【家老】cmd_171 タスクYAML自動完了
#   ━ Step 1 調査完了

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: ntfy_cmd.sh <cmd_id> <message>" >&2
    exit 1
fi

CMD_ID="$1"
MESSAGE="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# sender取得（ntfy.shと同じロジック）
SENDER=""
if [ -n "${TMUX_PANE:-}" ]; then
  SENDER="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
if [ -z "$SENDER" ]; then
  SENDER="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
fi
if [ -z "$SENDER" ]; then
  SENDER="unknown"
fi

# sender名を日本語タグに変換
case "$SENDER" in
  shogun)  SENDER_TAG="将軍" ;;
  karo)    SENDER_TAG="家老" ;;
  *)       SENDER_TAG="$SENDER" ;;
esac

# shogun_to_karo.yamlからpurposeを取得
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
PURPOSE=""

if [ -f "$YAML_FILE" ]; then
  # Method 1: commands:リスト形式（id: cmd_XXX）
  RAW=$(grep -A5 -E "id: ${CMD_ID}( |$)" "$YAML_FILE" 2>/dev/null \
    | grep "purpose:" | head -1 \
    | sed 's/^[[:space:]]*purpose:[[:space:]]*//' \
    | sed 's/^"//' | sed 's/"[[:space:]]*$//')

  # Method 2: キー形式フォールバック（cmd_XXX: で始まる形式）
  if [ -z "$RAW" ]; then
    RAW=$(grep -A5 -E "^[[:space:]]+${CMD_ID}:" "$YAML_FILE" 2>/dev/null \
      | grep -E "(purpose|title):" | head -1 \
      | sed 's/^[[:space:]]*\(purpose\|title\):[[:space:]]*//' \
      | sed 's/^"//' | sed 's/"[[:space:]]*$//')
  fi

  # 「—」以前の部分のみ使用（簡潔に）
  if [ -n "$RAW" ]; then
    PURPOSE=$(echo "$RAW" | sed 's/ *—.*//')
  fi
fi

# Gist URL取得（current_projectのgist_urlをprojects.yamlから解決）
GIST_URL=""
PROJECTS_YAML="$SCRIPT_DIR/config/projects.yaml"
if [ -f "$PROJECTS_YAML" ]; then
  CURRENT_PJ=$(grep '^current_project:' "$PROJECTS_YAML" 2>/dev/null | awk '{print $2}')
  if [ -n "$CURRENT_PJ" ]; then
    GIST_URL=$(awk -v id="$CURRENT_PJ" '
      /^[[:space:]]+- id:/ { found=($NF == id) }
      found && /gist_url:/ { gsub(/.*gist_url:[[:space:]]*"?|"?[[:space:]]*$/, ""); print; exit }
    ' "$PROJECTS_YAML" 2>/dev/null)
  fi
fi

# メッセージ組み立て
if [ -n "$PURPOSE" ]; then
  FINAL_MSG="【${SENDER_TAG}】${CMD_ID} ${PURPOSE}
━ ${MESSAGE}"
else
  FINAL_MSG="【${SENDER_TAG}】${CMD_ID}
━ ${MESSAGE}"
fi

# Gistリンク付加
if [ -n "$GIST_URL" ]; then
  FINAL_MSG="${FINAL_MSG}
📋 ${GIST_URL}"
fi

# ntfy.sh経由で送信（二重実装回避）
bash "$SCRIPT_DIR/scripts/ntfy.sh" "$FINAL_MSG"
