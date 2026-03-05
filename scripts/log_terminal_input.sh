#!/usr/bin/env bash
# log_terminal_input.sh — UserPromptSubmitフックで殿のターミナル入力を記録
set -euo pipefail

# agent_id判定（将軍ペインのみ）
AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
[ "$AGENT_ID" = "shogun" ] || exit 0

# 入力テキスト取得
INPUT="${CLAUDE_USER_PROMPT:-}"
[ -n "$INPUT" ] || exit 0

# スラッシュコマンド除外
[[ "$INPUT" != /* ]] || exit 0

# nudge除外（inbox1, inbox3等）
[[ "$INPUT" != inbox* ]] || exit 0

# lord_conversation.sh読込・環境変数設定
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/lord_conversation.sh"
export LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.yaml"
export LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"

append_lord_conversation "$INPUT" "inbound" "" "terminal"
