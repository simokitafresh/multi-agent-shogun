#!/usr/bin/env bash
set -euo pipefail

DENY_MSG="MCP Memoryは将軍専用。アクセス禁止。"
agent_id=""

# TMUX_PANE/TMUX が設定されている場合のみ tmux を呼出す
# command -v tmux チェック廃止: TMUX_PANE/TMUX が設定=tmux稼働中が保証済み
if [[ -n "${TMUX_PANE:-}" ]]; then
  agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
elif [[ -n "${TMUX:-}" ]]; then
  agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
fi

if [[ "$agent_id" == "shogun" ]]; then
  exit 0
fi

if [[ -z "$agent_id" ]]; then
  echo "${DENY_MSG} (agent_id未取得/非tmux環境)" >&2
else
  echo "${DENY_MSG} (agent_id=${agent_id})" >&2
fi
exit 2
