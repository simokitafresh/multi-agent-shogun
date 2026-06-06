#!/usr/bin/env bash
set -euo pipefail

DENY_MSG="MCP Memoryは将軍専用。アクセス禁止。"
agent_id=""

cache_file=""
if [[ -n "${TMUX_PANE:-}" || -n "${TMUX:-}" ]]; then
  cache_dir="${GATE_MCP_ACCESS_CACHE_DIR:-/tmp/gate_mcp_access_cache}"
  cache_key="${TMUX_PANE:-${TMUX:-notmux}}"
  cache_key="${cache_key//[^A-Za-z0-9_.-]/_}"
  cache_file="${cache_dir}/${cache_key}.agent_id"
  if [[ -r "$cache_file" ]]; then
    IFS= read -r agent_id < "$cache_file" || agent_id=""
    if [[ -n "$agent_id" && "$agent_id" != "shogun" ]]; then
      echo "${DENY_MSG} (agent_id=${agent_id})" >&2
      exit 2
    fi
  fi
fi

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

if [[ -n "${cache_file:-}" && -n "$agent_id" ]]; then
  mkdir -p "$cache_dir" 2>/dev/null || true
  printf '%s\n' "$agent_id" > "$cache_file" 2>/dev/null || true
fi

if [[ -z "$agent_id" ]]; then
  echo "${DENY_MSG} (agent_id未取得/非tmux環境)" >&2
else
  echo "${DENY_MSG} (agent_id=${agent_id})" >&2
fi
exit 2
