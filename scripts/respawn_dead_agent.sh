#!/usr/bin/env bash
# Respawn one dead agent pane through the configured CLI SSOT.
# Refuses live panes so recovery never terminates active work.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
agent="${1:-}"
dry_run="${2:-}"

if [[ ! "$agent" =~ ^(hayate|kagemaru|hanzo|saizo|kotaro|tobisaru)$ ]]; then
    echo "Usage: $0 <ninja> [--dry-run]" >&2
    exit 2
fi
if [[ -n "$dry_run" && "$dry_run" != "--dry-run" ]]; then
    echo "Usage: $0 <ninja> [--dry-run]" >&2
    exit 2
fi

# shellcheck source=/dev/null
source "$ROOT/scripts/lib/pane_lookup.sh"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/cli_lookup.sh"

pane="$(pane_lookup "$agent")"
[[ -n "$pane" ]] || { echo "BLOCK: pane not found for $agent" >&2; exit 1; }
dead="$(tmux display-message -t "$pane" -p '#{pane_dead}')"
if [[ "$dead" != "1" ]]; then
    echo "BLOCK: $agent pane is live; dead-only recovery refused" >&2
    exit 1
fi

launch="$(cli_launch_cmd "$agent")"
[[ -n "$launch" ]] || { echo "BLOCK: launch command not found for $agent" >&2; exit 1; }
if [[ "$dry_run" == "--dry-run" ]]; then
    echo "DRY-RUN: agent=$agent pane=$pane dead=1 launch=$launch"
    exit 0
fi

lock="/tmp/shogun_respawn_dead_${agent}.lock"
exec 201>"$lock"
flock -w 10 201 || { echo "BLOCK: respawn lock busy for $agent" >&2; exit 1; }

node_path="${HOME}/.nvm/versions/node/v20.20.0/bin"
tmux respawn-pane -t "$pane" \
    "reset 2>/dev/null; export PATH=\"${node_path}:\$PATH\"; cd \"${ROOT}\" && exec ${launch}"
tmux clear-history -t "$pane" 2>/dev/null || true
tmux set-option -p -t "$pane" @agent_id "$agent"
tmux set-option -p -t "$pane" @context_pct "0%"
task_state="$(python3 - "$ROOT/queue/tasks/${agent}.yaml" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = data.get("task", data) if isinstance(data, dict) else {}
status = str(task.get("status") or "")
parent = str(task.get("parent_cmd") or "")
print(parent if status in {"assigned", "acknowledged", "in_progress", "pending"} else "")
PY
)"
tmux set-option -p -t "$pane" @current_task "$task_state"

for _ in {1..20}; do
    sleep 0.25
    dead="$(tmux display-message -t "$pane" -p '#{pane_dead}' 2>/dev/null || echo 1)"
    [[ "$dead" == "0" ]] && break
done
[[ "$dead" == "0" ]] || { echo "FAIL: $agent pane remained dead" >&2; exit 1; }
current="$(tmux display-message -t "$pane" -p '#{pane_current_command}')"
echo "PASS: agent=$agent pane=$pane dead=0 current=$current"
