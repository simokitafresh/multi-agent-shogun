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

_ntfy_cmd_script="${BASH_SOURCE[0]}"
[[ "$_ntfy_cmd_script" != /* ]] && _ntfy_cmd_script="$PWD/$_ntfy_cmd_script"
_ntfy_cmd_dir="${_ntfy_cmd_script%/*}"
SCRIPT_DIR="${_ntfy_cmd_dir%/*}"
unset _ntfy_cmd_script _ntfy_cmd_dir

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

trim_yaml_scalar() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s\n' "$value"
}

if [ -f "$YAML_FILE" ]; then
  # Method 1: commands:リスト形式（id: cmd_XXX）
  RAW=""
  _watch_list=0
  _watch_key=0
  _watch_count=0
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    [[ "$trimmed" == "- "* ]] && trimmed="${trimmed#- }"
    if [[ "$trimmed" == id:* ]]; then
      value="$(trim_yaml_scalar "${trimmed#id:}")"
      if [ "$value" = "$CMD_ID" ]; then
        _watch_list=1
        _watch_key=0
        _watch_count=0
        continue
      fi
    fi
    if [[ "$trimmed" == "${CMD_ID}:" ]]; then
      _watch_key=1
      _watch_list=0
      _watch_count=0
      continue
    fi
    if [ "$_watch_list" = "1" ]; then
      _watch_count=$((_watch_count + 1))
      if [[ "$trimmed" == purpose:* ]]; then
        RAW="$(trim_yaml_scalar "${trimmed#purpose:}")"
        break
      fi
      [ "$_watch_count" -lt 5 ] || _watch_list=0
    elif [ "$_watch_key" = "1" ]; then
      _watch_count=$((_watch_count + 1))
      if [[ "$trimmed" == purpose:* ]] || [[ "$trimmed" == title:* ]]; then
        RAW="$(trim_yaml_scalar "${trimmed#*:}")"
        break
      fi
      [ "$_watch_count" -lt 5 ] || _watch_key=0
    fi
  done < "$YAML_FILE"
  unset _watch_list _watch_key _watch_count trimmed value

  # Method 2: キー形式フォールバック（cmd_XXX: で始まる形式）
  # (bash loop above handles both formats)

  # 「—」以前の部分のみ使用（簡潔に）
  if [ -n "$RAW" ]; then
    PURPOSE="${RAW%%—*}"
  fi
fi

# streak数取得（dashboard.mdの「連勝」行から数値抽出）
STREAK=""
DASHBOARD="$SCRIPT_DIR/dashboard.md"
if [ -f "$DASHBOARD" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == *"連勝"* && "$line" =~ ([0-9]+) ]]; then
      STREAK="${BASH_REMATCH[1]}"
      break
    fi
  done < "$DASHBOARD"
fi

# 軍師verdict取得（queue/inbox + archive/inboxのgunshi→karo msg）
GUNSHI_VERDICT=""
for src in "$SCRIPT_DIR/queue/inbox/karo.yaml" $(find "$SCRIPT_DIR/archive/inbox" -maxdepth 1 -name 'karo_*.yaml' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -3 | cut -d' ' -f2); do
  [ -f "$src" ] || continue
  RAW_VERDICT=$(grep -B5 "from: gunshi" "$src" 2>/dev/null \
    | grep "$CMD_ID" \
    | grep -o 'verdict[: ]*[A-Z_]*' \
    | sed 's/verdict[: ]*//' | tail -1)
  if [ -n "$RAW_VERDICT" ]; then
    GUNSHI_VERDICT="$RAW_VERDICT"
    break
  fi
done

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

# streak付加（MESSAGE中にGATE CLEARがある場合のみ）
if [[ "$MESSAGE" == *"GATE CLEAR"* ]] && [ -n "$STREAK" ]; then
  MESSAGE="${MESSAGE}(連勝${STREAK})"
fi

# メッセージ組み立て
FINAL_MSG="【${SENDER_TAG}】${CMD_ID} ${MESSAGE}"

if [ -n "$PURPOSE" ]; then
  FINAL_MSG="${FINAL_MSG}
${PURPOSE}"
fi

if [ -n "$GUNSHI_VERDICT" ]; then
  FINAL_MSG="${FINAL_MSG}
軍師: ${GUNSHI_VERDICT}"
fi

# Gistリンク付加
if [ -n "$GIST_URL" ]; then
  FINAL_MSG="${FINAL_MSG}
📋 ${GIST_URL}"
fi

# ntfy.sh経由で送信（二重実装回避）
bash "$SCRIPT_DIR/scripts/ntfy.sh" "$FINAL_MSG"
