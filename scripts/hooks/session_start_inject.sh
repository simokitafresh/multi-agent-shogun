#!/usr/bin/env bash
# @source: cmd_452 (SessionStart context注入hook)
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
# /clear は PreCompact を発火しないため、compact_state は /clear 時に古い情報のまま。
# さらに軍師/将軍/一部忍者は auto-compact 頻度が低く、startup/resume でも構造的に
# 古い情報になる。古い情報を「現在の状態」として注入するとノイズ=誤読リスク。
# 2段階防御: (1) source_type == clear → 全面スキップ注記
#            (2) それ以外でも timestamp が 24h 超なら stale 注記を冒頭に付与
# 殿原則「想像するな確認せよ」(2026-03-21) に準拠。
compact_file="$SCRIPT_DIR/queue/compact_state/${agent_id}.yaml"
compact_state="none"
compact_stale_threshold=86400  # 24h in seconds
if [[ "$source_type" == "clear" ]]; then
  compact_state="(skipped: /clear type does not update compact_state; last value may be stale)"
elif [[ -f "$compact_file" ]]; then
  raw_state="$(cat "$compact_file" 2>/dev/null || echo "")"
  if [[ -z "$raw_state" ]]; then
    compact_state="none"
  else
    # timestamp行を抽出してepoch比較。quote除去にsedを使用
    ts_line="$(grep '^timestamp:' "$compact_file" 2>/dev/null | head -1 | sed "s/^timestamp:[[:space:]]*//; s/^'//; s/'$//")"
    if [[ -n "$ts_line" ]]; then
      ts_epoch="$(date -d "$ts_line" +%s 2>/dev/null || echo 0)"
      now_epoch="$(date +%s)"
      age_sec=$((now_epoch - ts_epoch))
      if (( ts_epoch > 0 && age_sec > compact_stale_threshold )); then
        age_days=$((age_sec / 86400))
        compact_state="(stale: ${age_days}d old; last update=${ts_line}; auto-compact未踏=構造的古さ)
${raw_state}"
      else
        compact_state="$raw_state"
      fi
    else
      compact_state="$raw_state"
    fi
  fi
fi

# --- startup gate セクション削除(2026-04-12殿裁定) ---
# 理由: /clear直後にgate自動実行=無駄なcontext消費。
# 正解: 殿の入力受領時にエージェントがCLAUDE.md recovery手順で手動実行し、
#       その後入力対応する。今まで通りの流れ。
# gate_*_startup.sh は手動実行専用として維持（--brief/通常の2モード）

# --- Build additionalContext ---
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

# karo_snapshotは budget で切り詰め
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
