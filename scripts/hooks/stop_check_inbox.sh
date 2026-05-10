#!/usr/bin/env bash
# @source: cmd_451 (inbox未読チェックstop防止hook)
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
case "$SOURCE_PATH" in
  */scripts/hooks/*) SCRIPT_DIR="${SOURCE_PATH%/scripts/hooks/*}" ;;
  scripts/hooks/*) SCRIPT_DIR="." ;;
  *) SCRIPT_DIR="$(cd "${SOURCE_PATH%/*}/../.." && pwd)" ;;
esac
readonly COMPLETE_PATTERN='任務完了|完了でござる|報告YAML.*更新|task completed|タスク完了'
readonly ERROR_PATTERN='エラー.*中断|失敗.*中断|error.*abort|failed.*stop'
readonly SUMMARY_LIMIT=5
readonly SUMMARY_SNIPPET_LEN=80

IFS='' read -r -d '' payload || true
if [[ -z "$payload" ]]; then
  exit 0
fi

# cmd_2076: jq -e . (validation) → bash文字列マッチに変更 (~5ms削減)
# 初回改善。前回アプローチなし。
if [[ "$payload" != '{'* ]]; then
  exit 0
fi

STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"

agent_id="${TMUX_AGENT_ID:-}"
if [[ -z "$agent_id" ]] && command -v tmux >/dev/null 2>&1; then
  agent_cache=""
  if [[ -n "${TMUX:-}${TMUX_PANE:-}" ]]; then
    cache_key="${TMUX:-no_tmux}_${TMUX_PANE:-no_pane}"
    cache_key="${cache_key//[^A-Za-z0-9_.-]/_}"
    agent_cache="$STATE_DIR/shogun_agent_id_${cache_key}"
    if [[ -s "$agent_cache" ]]; then
      IFS= read -r agent_id < "$agent_cache" || agent_id=""
    fi
  fi

  if [[ -z "$agent_id" ]]; then
    if [[ -n "${TMUX_PANE:-}" ]]; then
      agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    elif [[ -n "${TMUX:-}" ]]; then
      agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
    fi
    if [[ -n "$agent_id" && -n "$agent_cache" ]]; then
      [[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"
      printf '%s\n' "$agent_id" > "$agent_cache" 2>/dev/null || true
    fi
  fi
fi

if [[ -z "$agent_id" ]]; then
  exit 0
fi

[[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"
idle_flag="${STATE_DIR}/shogun_idle_${agent_id}"
last_assistant_message=""
if [[ "$payload" == *'"last_assistant_message"'* ]]; then
  last_assistant_message="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
fi

# cmd_2076: jq -r '.stop_hook_active...' → bash文字列マッチに変更 (~5ms削減)
stop_hook_active=false
if [[ "$payload" == *'"stop_hook_active":true'* || "$payload" == *'"stop_hook_active": true'* ]]; then
  stop_hook_active=true
fi
if [[ "$stop_hook_active" == "true" ]]; then
  : > "$idle_flag"
  exit 0
fi

notify_completion() {
  local msg_type="$1"
  local message="$2"
  (
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" "$msg_type" "$agent_id"
  ) >/dev/null 2>&1 &
}

if [[ -n "$last_assistant_message" && "$agent_id" != "shogun" && "$agent_id" != "gunshi" ]]; then
  if printf '%s\n' "$last_assistant_message" | grep -Eiq "$COMPLETE_PATTERN"; then
    notify_completion "report_completed" "${agent_id}、タスク完了"
  elif printf '%s\n' "$last_assistant_message" | grep -Eiq "$ERROR_PATTERN"; then
    notify_completion "error_report" "${agent_id}、エラー停止"
  fi
fi

inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
if [[ ! -f "$inbox_file" ]]; then
  exit 0
fi

fast_cache=""
if [[ -z "$last_assistant_message" && "$agent_id" != "karo" && "$agent_id" != "gunshi" && "$agent_id" != "shogun" ]]; then
  _ninja_task_for_cache="$SCRIPT_DIR/queue/tasks/${agent_id}.yaml"
  fast_cache="$STATE_DIR/shogun_stop_check_inbox_fast_${agent_id}"
  if [[ -f "$_ninja_task_for_cache" && -f "$fast_cache" && ! "$inbox_file" -nt "$fast_cache" && ! "$_ninja_task_for_cache" -nt "$fast_cache" ]]; then
    : > "$idle_flag"
    exit 0
  fi
fi

has_unread=false
if grep -qE '^[[:space:]]*read:[[:space:]]*false[[:space:]]*$' "$inbox_file" 2>/dev/null; then
  has_unread=true
fi

if [[ "$has_unread" == "true" ]]; then
  unread_count="$(grep -cE '^[[:space:]]*read:[[:space:]]*false[[:space:]]*$' "$inbox_file" 2>/dev/null || true)"
  if [[ ! "$unread_count" =~ ^[0-9]+$ ]]; then
    unread_count=1
  fi
  : > "$idle_flag"
  # cmd_2111: python3 2回→1回に統合(サブプロセス削減)
  INBOX_FILE="$inbox_file" SUMMARY_LIMIT_ENV="$SUMMARY_LIMIT" SUMMARY_SNIPPET_LEN_ENV="$SUMMARY_SNIPPET_LEN" UNREAD_COUNT="$unread_count" python3 - <<'PY'
import os, json, yaml

inbox_path = os.environ["INBOX_FILE"]
limit = int(os.environ["SUMMARY_LIMIT_ENV"])
snippet_len = int(os.environ["SUMMARY_SNIPPET_LEN_ENV"])
unread_count = int(os.environ["UNREAD_COUNT"])

with open(inbox_path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

CONCLUSION_TYPES = {"bulletin_notify", "review_feedback", "retraction", "analysis_result", "review_result", "report_review_result", "verify_result"}

parts = []
has_conclusion = False
for msg in data.get("messages", []):
    if msg.get("read") is not False:
        continue
    sender = str(msg.get("from", "?"))
    msg_type = str(msg.get("type", "?"))
    content = " ".join(str(msg.get("content", "")).split())
    content = content[:snippet_len]
    parts.append(f"[{sender}/{msg_type}] {content}")
    if msg_type in CONCLUSION_TYPES:
        has_conclusion = True
    if len(parts) >= limit:
        break

result = " | ".join(parts)
if has_conclusion:
    result += " | ★結論を含む通知あり。自分の証拠と突合せよ。矛盾があれば問い返せ。撤回は突合後。"

if result:
    reason_text = f"inbox未読{unread_count}件あり。内容: {result}"
else:
    reason_text = f"inbox未読{unread_count}件あり"

print(json.dumps({"decision": "block", "reason": reason_text}, ensure_ascii=False))
PY
else
  # 家老向け: inbox未読0でもpending workがあれば次アクションを表示(Codex STALL防止)
  if [[ "$agent_id" == "karo" ]]; then
    _pending_actions=()

    # 1. 完了忍者の報告パイプライン(status=done → レビュー/GATE処理が必要)
    for _tf in "$SCRIPT_DIR"/queue/tasks/*.yaml; do
      [[ -f "$_tf" ]] || continue
      _ninja_name="$(basename "$_tf" .yaml)"
      _task_status="$(awk '/^[[:space:]]*status:/{print $2; exit}' "$_tf" 2>/dev/null || true)"
      _task_pcmd="$(awk '/^  parent_cmd:/{print $2; exit}' "$_tf" 2>/dev/null || true)"
      if [[ "$_task_status" == "done" ]]; then
        _pending_actions+=("${_ninja_name}(${_task_pcmd}) status=done → 報告レビュー/GATE処理を進めよ")
      fi
    done

    # 2. 未配備CMD(status=delegated + task未作成。on_hold/shelved/blockedは除外)
    _delegated_cmds="$(awk '/^  cmd_[0-9]+:/{cmd=$1; gsub(/:$/,"",cmd)} cmd && /status:.*(on_hold|shelved|blocked)/{cmd=""} cmd && /status:.*delegated/{print cmd; cmd=""}' "$SCRIPT_DIR/queue/shogun_to_karo.yaml" 2>/dev/null || true)"
    for _dcmd in $_delegated_cmds; do
      _has_task=false
      for _tf2 in "$SCRIPT_DIR"/queue/tasks/*.yaml; do
        if grep -q "parent_cmd:.*${_dcmd}" "$_tf2" 2>/dev/null; then
          _has_task=true
          break
        fi
      done
      if [[ "$_has_task" == "false" ]]; then
        _pending_actions+=("${_dcmd} status=delegated → 忍者配備を進めよ")
      fi
    done

    if (( ${#_pending_actions[@]} > 0 )); then
      _action_text="$(printf '%s; ' "${_pending_actions[@]}")"
      _reason="inbox未読0件だが次アクションあり: ${_action_text%%; }"
      jq -n --arg reason "$_reason" '{"decision":"block","reason":$reason}'
      exit 0
    fi
  fi

  # 忍者向け: task完了後に勝手な作業を始めるのを防止
  # status=done/completed + inbox未読0 → 待機指示
  if [[ "$agent_id" != "karo" && "$agent_id" != "gunshi" && "$agent_id" != "shogun" ]]; then
    _ninja_task="$SCRIPT_DIR/queue/tasks/${agent_id}.yaml"
    if [[ -f "$_ninja_task" ]]; then
      if grep -qE '^[[:space:]]*status:[[:space:]]*(done|completed)([[:space:]]|$)' "$_ninja_task" 2>/dev/null; then
        : > "$idle_flag"
        _reason="Task completed. Wait for next task assignment from karo. Do NOT start new work."
        jq -n --arg reason "$_reason" '{"decision":"block","reason":$reason}'
        exit 0
      fi
    fi
  fi

  : > "$idle_flag"
  if [[ -n "$fast_cache" ]]; then
    : > "$fast_cache"
  fi
fi

exit 0
