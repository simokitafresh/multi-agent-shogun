#!/usr/bin/env bash
# log_terminal_response.sh — Stopフックで将軍の応答を記録
set -eu

AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
[ "$AGENT_ID" = "shogun" ] || exit 0

# 直近50行をキャプチャ
RAW="$(tmux capture-pane -t "$TMUX_PANE" -p -S -50 2>/dev/null || true)"
[ -n "$RAW" ] || exit 0

# プロンプト行（❯等）で区切り、最後のテキストブロックを抽出
# 最後の❯以降の行を取得（将軍の最新応答）
RESPONSE="$(echo "$RAW" | tac | sed '/❯/q' | tac | grep -v '^[[:space:]]*$' | grep -v '❯' | head -c 500 || true)"
[ -n "$RESPONSE" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/lord_conversation.sh"
export LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.yaml"
export LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"

append_lord_conversation "$RESPONSE" "outbound" "shogun" "terminal"

# Stopフック末尾で24h保持と索引更新を実行（失敗時は記録処理を継続）
if ! bash "$SCRIPT_DIR/scripts/conversation_retention.sh"; then
  echo "[log_terminal_response] WARN: conversation_retention.sh failed" >&2
fi
