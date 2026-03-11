#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

if ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

stop_hook_active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
if [[ "$stop_hook_active" == "true" ]]; then
  exit 0
fi

agent_id=""
if command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
  elif [[ -n "${TMUX:-}" ]]; then
    agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
  fi
fi

if [[ -z "$agent_id" || "$agent_id" == "shogun" ]]; then
  exit 0
fi

task_file="$SCRIPT_DIR/queue/tasks/${agent_id}.yaml"
field_get_lib="$SCRIPT_DIR/scripts/lib/field_get.sh"
if [[ -f "$task_file" && -f "$field_get_lib" ]]; then
  # shellcheck disable=SC1090
  source "$field_get_lib"

  report_filename="$(field_get "$task_file" "report_filename" "")"
  if [[ -z "$report_filename" ]]; then
    parent_cmd="$(field_get "$task_file" "parent_cmd" "")"
    if [[ -n "$parent_cmd" ]]; then
      report_filename="${agent_id}_report_${parent_cmd}.yaml"
    fi
  fi
  if [[ -n "$report_filename" ]]; then
    task_status="$(field_get "$task_file" "status" "")"
    if [[ "$task_status" == "done" ]]; then
      report_file="$SCRIPT_DIR/queue/reports/${report_filename}"
      archive_file="$SCRIPT_DIR/queue/archive/reports/${report_filename}"
      report_exists=0
      if [[ -f "$report_file" || -f "$archive_file" ]]; then
        report_exists=1
      else
        # Archive files may have date suffix
        base="${report_filename%.yaml}"
        shopt -s nullglob
        archived=("$SCRIPT_DIR/queue/archive/reports/${base}"_*.yaml)
        shopt -u nullglob
        if [[ "${#archived[@]}" -gt 0 ]]; then
          report_exists=1
        fi
      fi
      if [[ "$report_exists" -eq 0 ]]; then
        printf '{"decision":"block","reason":"報告が正しいパスにない。report_filename: %s を確認せよ"}\n' "$report_filename"
        exit 0
      fi
    fi
  fi
fi

inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
if [[ ! -f "$inbox_file" ]]; then
  exit 0
fi

unread_count="$(awk '/^[[:space:]]*read:[[:space:]]*false[[:space:]]*$/{c++} END{print c+0}' "$inbox_file")"
if (( unread_count > 0 )); then
  printf '{"decision":"block","reason":"inbox未読%d件"}\n' "$unread_count"
fi

exit 0
