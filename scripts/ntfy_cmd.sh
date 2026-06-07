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

trim_yaml_scalar_v() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  _TRIMMED_YAML_SCALAR="$value"
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
      trim_yaml_scalar_v "${trimmed#id:}"
      value="$_TRIMMED_YAML_SCALAR"
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
        trim_yaml_scalar_v "${trimmed#purpose:}"
        RAW="$_TRIMMED_YAML_SCALAR"
        break
      fi
      [ "$_watch_count" -lt 5 ] || _watch_list=0
    elif [ "$_watch_key" = "1" ]; then
      _watch_count=$((_watch_count + 1))
      if [[ "$trimmed" == purpose:* ]] || [[ "$trimmed" == title:* ]]; then
        trim_yaml_scalar_v "${trimmed#*:}"
        RAW="$_TRIMMED_YAML_SCALAR"
        break
      fi
      [ "$_watch_count" -lt 5 ] || _watch_key=0
    fi
  done < "$YAML_FILE"
  unset _watch_list _watch_key _watch_count trimmed value _TRIMMED_YAML_SCALAR

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
_ntfy_cmd_sources=("$SCRIPT_DIR/queue/inbox/karo.yaml")
if [ -d "$SCRIPT_DIR/archive/inbox" ]; then
  _ntfy_cmd_archives=("$SCRIPT_DIR"/archive/inbox/karo_*.yaml)
  if [ -e "${_ntfy_cmd_archives[0]}" ]; then
    for ((_i=${#_ntfy_cmd_archives[@]}-1; _i>=0 && ${#_ntfy_cmd_sources[@]}<4; _i--)); do
      _ntfy_cmd_sources+=("${_ntfy_cmd_archives[$_i]}")
    done
  fi
fi
for src in "${_ntfy_cmd_sources[@]}"; do
  [ -f "$src" ] || continue
  _prev1=""; _prev2=""; _prev3=""; _prev4=""; _prev5=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == *"from: gunshi"* ]]; then
      for _candidate in "$_prev1" "$_prev2" "$_prev3" "$_prev4" "$_prev5"; do
        if [[ "$_candidate" == *"$CMD_ID"* && "$_candidate" =~ verdict[:\ ]*([A-Z_]+) ]]; then
          GUNSHI_VERDICT="${BASH_REMATCH[1]}"
        fi
      done
      [ -n "$GUNSHI_VERDICT" ] && break
    fi
    _prev5="$_prev4"; _prev4="$_prev3"; _prev3="$_prev2"; _prev2="$_prev1"; _prev1="$line"
  done < "$src"
  [ -n "$GUNSHI_VERDICT" ] && break
done
unset _ntfy_cmd_sources _ntfy_cmd_archives _i _prev1 _prev2 _prev3 _prev4 _prev5 _candidate

# Gist URL取得（current_projectのgist_urlをprojects.yamlから解決）
GIST_URL=""
PROJECTS_YAML="$SCRIPT_DIR/config/projects.yaml"
if [ -f "$PROJECTS_YAML" ]; then
  CURRENT_PJ=""
  _project_found=0
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    if [[ "$trimmed" == current_project:* ]]; then
      trim_yaml_scalar_v "${trimmed#current_project:}"
      CURRENT_PJ="$_TRIMMED_YAML_SCALAR"
      continue
    fi
    if [[ "$trimmed" == "- id:"* ]]; then
      trim_yaml_scalar_v "${trimmed#- id:}"
      [ "$_TRIMMED_YAML_SCALAR" = "$CURRENT_PJ" ] && _project_found=1 || _project_found=0
      continue
    fi
    if [ "$_project_found" = "1" ] && [[ "$trimmed" == gist_url:* ]]; then
      trim_yaml_scalar_v "${trimmed#gist_url:}"
      GIST_URL="$_TRIMMED_YAML_SCALAR"
      break
    fi
  done < "$PROJECTS_YAML"
  unset CURRENT_PJ _project_found trimmed _TRIMMED_YAML_SCALAR
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
