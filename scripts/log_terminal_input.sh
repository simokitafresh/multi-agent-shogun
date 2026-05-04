#!/usr/bin/env bash
# log_terminal_input.sh — UserPromptSubmitフックで殿のターミナル入力を記録
set -eu

# agent_id判定（将軍ペインのみ）
AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
[ "$AGENT_ID" = "shogun" ] || exit 0

# 入力テキスト取得（stdin JSON の .prompt フィールドから）
INPUT="$(jq -r '.prompt // ""' 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0

# スラッシュコマンド除外
[[ "$INPUT" != /* ]] || exit 0

# nudge除外（inbox1, inbox3等）
[[ "$INPUT" != inbox* ]] || exit 0

# lord_conversation.sh読込・環境変数設定
_log_terminal_input_self="${BASH_SOURCE[0]}"
[[ "$_log_terminal_input_self" != /* ]] && _log_terminal_input_self="$PWD/$_log_terminal_input_self"
SCRIPT_DIR="${_log_terminal_input_self%/scripts/log_terminal_input.sh}"
unset _log_terminal_input_self
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/lord_conversation.sh"
export LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.jsonl"
export LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"

append_lord_conversation "$INPUT" "inbound" "lord" "terminal"

# セマンティクスインデックス候補化。会話記録そのものは上で完了済みのため、失敗しても入力処理は止めない。
if [ -f "$SCRIPT_DIR/scripts/semantic_index_update.sh" ]; then
    if _semantic_payload=$(INPUT_ENV="$INPUT" TS_ENV="$(date -Iseconds)" python3 - <<'PY' 2>/dev/null
import json
import os

print(json.dumps({
    "timestamp": os.environ.get("TS_ENV", ""),
    "summary": os.environ.get("INPUT_ENV", ""),
}, ensure_ascii=False))
PY
    ); then
        bash "$SCRIPT_DIR/scripts/semantic_index_update.sh" discussion "$_semantic_payload" >/dev/null 2>&1 || true
    fi
fi
