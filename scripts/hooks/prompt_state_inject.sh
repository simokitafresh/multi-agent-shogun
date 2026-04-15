#!/usr/bin/env bash
# @source: cmd_452 (UserPromptSubmit snapshot注入hook)
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Read stdin JSON (type: user_prompt_submit) ---
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

if ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

# --- Get agent_id from tmux ---
agent_id="unknown"
if command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")"
  elif [[ -n "${TMUX:-}" ]]; then
    agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || echo "unknown")"
  fi
fi
if [[ -z "$agent_id" ]]; then
  agent_id="unknown"
fi

# --- shogun only (exit 0 for all others) ---
if [[ "$agent_id" != "shogun" ]]; then
  exit 0
fi

# --- Timestamp (ISO 8601) ---
timestamp="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "unavailable")"

# --- Inbox unread count ---
inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
unread_count=0
if [[ -f "$inbox_file" ]]; then
  unread_count="$(awk '/^[[:space:]]*read:[[:space:]]*false[[:space:]]*$/{c++} END{print c+0}' "$inbox_file" 2>/dev/null || echo 0)"
  if [[ ! "$unread_count" =~ ^[0-9]+$ ]]; then
    unread_count=0
  fi
fi

# --- karo_snapshot ---
snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
karo_snapshot="unavailable"
if [[ -f "$snapshot_file" ]]; then
  karo_snapshot="$(cat "$snapshot_file" 2>/dev/null || echo "unavailable")"
  if [[ -z "$karo_snapshot" ]]; then
    karo_snapshot="unavailable"
  fi
fi

prompt_text="$(printf '%s' "$payload" | jq -r '.prompt // ""' 2>/dev/null || true)"

# --- 研究日誌全文注入モード検知 ---
research_diary_mode=false
research_diary_file="$SCRIPT_DIR/memory/dialogue_preprocessing_research_20260331.md"
if echo "$prompt_text" | grep -qiE '研究日誌|日誌を読め|日誌を読んで|diary'; then
  if [[ -f "$research_diary_file" ]]; then
    research_diary_mode=true
  fi
fi

if [[ "$research_diary_mode" == "true" ]]; then
  # --- 研究日誌全文注入モード（サイズ制限なし） ---
  diary_content="$(cat "$research_diary_file")"
  verification_questions="
---検証問（各1行で回答。回答なしに作業開始するな。クリア後の新しい将軍として答えよ）---
Q1: 今セッションの作業と研究日誌のどのPhaseが因果的に接続するか？
Q2: 研究日誌の中で最も驚いた転換点はどれか？なぜか？
Q3: 研究日誌から今の問題に適用できる原理は何か？
Q4: Phase Nの結論がPhase Mで覆された例を1つ挙げよ。なぜ覆されたか？（時系列×因果）
Q5: 研究日誌のどのPhaseで殿が将軍の前提を崩したか？今の自分にも同じ前提はないか？確認せよ"

  additional_context="=== 研究日誌全文注入（殿指示検知） ===
timestamp: ${timestamp}
agent: ${agent_id}
--- karo_snapshot ---
${karo_snapshot}
--- 研究日誌（Phase 0から順に追体験せよ） ---
${diary_content}
${verification_questions}"

  printf '%s' "$additional_context" | jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.}}'
  exit 0
fi

# --- 通常モード: Build additionalContext (max 500 chars) ---
header="=== Session Context (auto-injected) ==="
fixed_part="${header}
source: unknown
timestamp: ${timestamp}
agent: ${agent_id}
inbox_unread: ${unread_count}
reminder: 必ず確認してから作業開始せよ
--- karo_snapshot ---
"

fixed_len=${#fixed_part}
max_total=500
snapshot_budget=$((max_total - fixed_len))

if (( snapshot_budget < 0 )); then
  snapshot_budget=0
fi

if (( ${#karo_snapshot} > snapshot_budget )); then
  karo_snapshot="${karo_snapshot:0:$snapshot_budget}"
fi

additional_context="${fixed_part}${karo_snapshot}"

# --- Output JSON ---
printf '%s' "$additional_context" | jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.}}'

exit 0
