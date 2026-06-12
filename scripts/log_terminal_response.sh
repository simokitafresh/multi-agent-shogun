#!/usr/bin/env bash
# log_terminal_response.sh — Stopフックで将軍の応答を記録
set -eu

AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
[ -n "$AGENT_ID" ] && [ "$AGENT_ID" != "unknown" ] || exit 0

HOOK_PAYLOAD="$(cat 2>/dev/null || true)"
# Early exit for empty payload
[ -n "$HOOK_PAYLOAD" ] || exit 0

# SCRIPT_DIR: string ops instead of $(cd) subshells (~5ms savings on WSL2)
_ltr_self="${BASH_SOURCE[0]:-$0}"
[[ "$_ltr_self" != /* ]] && _ltr_self="$PWD/$_ltr_self"
SCRIPT_DIR="${_ltr_self%/scripts/log_terminal_response.sh}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/lord_conversation.sh"
export LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.jsonl"
export LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"

extract_detail_with_jq() {
  local transcript_path stop_reason response line

  # Fast path for the common Stop payload shape: transcript_path + transcript JSONL.
  # Avoids a parser process before append_lord_conversation's required DB/JSONL writer.
  if [[ "$HOOK_PAYLOAD" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    transcript_path="${BASH_REMATCH[1]}"
  elif [[ "$HOOK_PAYLOAD" =~ \"transcriptPath\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    transcript_path="${BASH_REMATCH[1]}"
  fi
  if [[ "$HOOK_PAYLOAD" =~ \"stop_reason\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    stop_reason="${BASH_REMATCH[1]}"
  elif [[ "$HOOK_PAYLOAD" =~ \"stopReason\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    stop_reason="${BASH_REMATCH[1]}"
  fi
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    line="$(awk '
      /"type"[[:space:]]*:[[:space:]]*"assistant"/ && /"role"[[:space:]]*:[[:space:]]*"assistant"/ { last = $0 }
      END { print last }
    ' "$transcript_path" 2>/dev/null || true)"
    if [ -n "$line" ]; then
      if [ -z "$stop_reason" ] && [[ "$line" =~ \"stop_reason\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
        stop_reason="${BASH_REMATCH[1]}"
      fi
      if [[ "$line" =~ \"text\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
        response="${BASH_REMATCH[1]}"
        response="${response//\\n/$'\n'}"
        response="${response//\\\"/\"}"
        response="${response//\\\\/\\}"
        printf '%s' "$response"
        [ -z "$stop_reason" ] || printf '\n\n[meta] stop_reason=%s' "$stop_reason"
        return 0
      fi
    fi
  fi

  command -v jq >/dev/null 2>&1 || return 1

  local payload_file tool_result transcript_extract pane_capture
  payload_file="$(mktemp)"
  printf '%s' "$HOOK_PAYLOAD" > "$payload_file"

  transcript_path="$(jq -r '(.transcript_path // .transcriptPath // "") | strings' "$payload_file" 2>/dev/null || true)"
  stop_reason="$(jq -r '(.last_assistant_message.stop_reason // .stop_reason // .stopReason // "") | strings' "$payload_file" 2>/dev/null || true)"
  tool_result="$(jq -cr '(.tool_result // .toolUseResult // empty)' "$payload_file" 2>/dev/null || true)"
  response="$(jq -r '
    (.last_assistant_message.content // [])
    | map(select(.type == "text") | .text // "" | strings | gsub("^\\s+|\\s+$"; ""))
    | map(select(length > 0))
    | join("\n")
  ' "$payload_file" 2>/dev/null || true)"
  rm -f "$payload_file"

  if [ -z "$response" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    transcript_extract="$(jq -r -s '
      map(select(.type == "assistant" and .message.role == "assistant"))
      | last // {}
      | [
          ((.message.stop_reason // "") | strings),
          ((.message.content // [])
            | map(select(.type == "text") | .text // "" | strings | gsub("^\\s+|\\s+$"; ""))
            | map(select(length > 0))
            | join("\n"))
        ]
      | @tsv
    ' "$transcript_path" 2>/dev/null || true)"
    if [ -n "$transcript_extract" ]; then
      local transcript_stop transcript_response
      IFS=$'\t' read -r transcript_stop transcript_response <<EOF
$transcript_extract
EOF
      [ -n "$stop_reason" ] || stop_reason="$transcript_stop"
      [ -n "$response" ] || response="$transcript_response"
    fi
  fi

  if [ -z "$response" ] && [ -n "${TMUX_PANE:-}" ]; then
    pane_capture="$(tmux capture-pane -t "$TMUX_PANE" -p -J -S -200 2>/dev/null || true)"
    if [ -n "$pane_capture" ]; then
      response="$(printf '%s\n' "$pane_capture" | awk '
        /^[[:space:]]*[›❯]/ { last_prompt = NR; next }
        { lines[NR] = $0 }
        END {
          for (i = last_prompt + 1; i <= NR; i++) {
            line = lines[i]
            if (line ~ /^[[:space:]]*$/) continue
            if (line ~ /^[[:space:]]*[›❯]/) continue
            sub(/[[:space:]]+$/, "", line)
            out = out (out ? "\n" : "") line
          }
          if (length(out) > 2500) out = substr(out, 1, 2499) "…"
          print out
        }
      ')"
    fi
  fi

  [ -n "$response" ] || return 1
  printf '%s' "$response"
  [ -z "$stop_reason" ] || printf '\n\n[meta] stop_reason=%s' "$stop_reason"
  if [ -n "$tool_result" ]; then
    local snippet
    snippet="$(printf '%s' "$tool_result" | tr '\n' ' ' | awk '{gsub(/[[:space:]]+/, " "); sub(/^ /, ""); sub(/ $/, ""); if (length($0) > 300) print substr($0, 1, 299) "…"; else print}')"
    [ -z "$snippet" ] || printf '\n[meta] tool_result=%s' "$snippet"
  fi
}

DETAIL="$(extract_detail_with_jq)" || exit 0

[ -n "$DETAIL" ] || exit 0

append_lord_conversation "$DETAIL" "response" "$AGENT_ID" "terminal" "lord"

# Stopフック末尾で24h保持と索引更新をバックグラウンド実行
bash "$SCRIPT_DIR/scripts/conversation_retention.sh" &
