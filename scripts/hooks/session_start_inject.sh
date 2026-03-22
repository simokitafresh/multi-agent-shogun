#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Read stdin JSON (type: startup|resume|clear|compact) ---
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

if ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

source_type="$(printf '%s' "$payload" | jq -r '.type // "unknown"' 2>/dev/null || echo "unknown")"

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

# --- compact_state ---
compact_file="$SCRIPT_DIR/queue/compact_state/${agent_id}.yaml"
compact_state="none"
if [[ -f "$compact_file" ]]; then
  compact_state="$(cat "$compact_file" 2>/dev/null || echo "none")"
  if [[ -z "$compact_state" ]]; then
    compact_state="none"
  fi
fi

# --- Build additionalContext (max 500 chars) ---
header="=== Session Context (auto-injected) ==="
fixed_part="${header}
source: ${source_type}
timestamp: ${timestamp}
agent: ${agent_id}
inbox_unread: ${unread_count}
--- karo_snapshot ---
"
compact_section="
--- compact_state ---
${compact_state}"

fixed_len=${#fixed_part}
compact_len=${#compact_section}
max_total=500
snapshot_budget=$((max_total - fixed_len - compact_len))

if (( snapshot_budget < 0 )); then
  snapshot_budget=0
fi

if (( ${#karo_snapshot} > snapshot_budget )); then
  karo_snapshot="${karo_snapshot:0:$snapshot_budget}"
fi

additional_context="${fixed_part}${karo_snapshot}${compact_section}"

# --- Output JSON ---
printf '%s' "$additional_context" | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'

exit 0
