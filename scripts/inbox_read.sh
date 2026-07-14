#!/usr/bin/env bash
set -euo pipefail

# Codex has no dedicated Read tool, while inbox_mark_read's safety guard
# requires a read receipt.  This helper makes the read observable and records
# the receipt only after the inbox contents were emitted successfully.

if (( $# != 1 )); then
  echo "Usage: $0 <agent_id>" >&2
  exit 2
fi

agent_id="$1"
if [[ ! "$agent_id" =~ ^[a-z_]+$ ]]; then
  echo "ERROR: invalid agent_id: $agent_id" >&2
  exit 2
fi

repo_root="${SHOGUN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
relative_inbox="queue/inbox/${agent_id}.yaml"
inbox_file="${repo_root}/${relative_inbox}"
read_log_dir="${INBOX_READ_LOG_DIR:-/tmp}"
read_log="${read_log_dir}/claude_read_log_${agent_id}.txt"

if [[ ! -f "$inbox_file" ]]; then
  echo "ERROR: inbox not found: $relative_inbox" >&2
  exit 1
fi

cat -- "$inbox_file"
mkdir -p -- "$read_log_dir"
printf '%s\n' "$relative_inbox" >> "$read_log"
