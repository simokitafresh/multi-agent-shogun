---
codd:
  node_id: design:script:restart-watchers
  type: design
  status: approved
  confidence: 0.85
  source: brownfield
  depends_on:
  - id: req:script:restart-watchers
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/restart_watchers.sh
---

# restart_watchers.sh Brownfield Design

## Entry Flow

The script acquires a singleton flock, stops all existing inbox_watcher processes in two stages (SIGTERM then SIGKILL), restarts them per-agent using dynamic pane resolution, verifies liveness, checks inotifywait health, and synchronizes pane variables before exiting.

## Core Components

- **Singleton guard**: `flock -n 200` on `/tmp/restart_watchers.lock`; duplicate runs exit 1 immediately.
- **Stop phase**: `pkill -f "inbox_watcher.sh"` followed by `pgrep -fc` count check. If survivors remain, `pkill -9` is issued and rechecked.
- **Shogun/karo watcher launch**: Hardcoded pane targets (`shogun:main`, `shogun:agents.1`). `@agent_cli` is read from the tmux pane option with fallback to `"claude"`. `nohup bash inbox_watcher.sh <agent> <pane> <cli>` is backgrounded with `disown`.
- **Dynamic agent loop**: `get_all_agents()` from `scripts/lib/agent_config.sh` provides the full agent list. `pane_lookup()` from `scripts/lib/pane_lookup.sh` resolves each agent to a pane string. Empty pane strings cause the agent to be skipped silently.
- **Liveness check**: `pgrep -f "inbox_watcher\.sh.*${agent}"` verifies each launched process. Failures accumulate in `failed_agents[]`; any failure triggers exit 1 with the failed list printed.
- **inotifywait health check**: `pgrep -fc "inotifywait.*queue/inbox"` is compared against the success count. A mismatch emits `WARN` but does not change exit status.
- **Pane variable sync**: `scripts/sync_pane_vars.sh` is executed last to propagate tmux variables.

## Data Boundaries

Inputs are tmux pane options (`@agent_cli`), `scripts/lib/agent_config.sh`, and `scripts/lib/pane_lookup.sh`.
Outputs are per-agent `logs/inbox_watcher_{agent}.log` files and running `inbox_watcher.sh` processes.

## Known Gaps

- **gap-1 (CLI fallback)**: The fallback value `"claude"` for `@agent_cli` may resolve to the auto-update binary at `~/.local/bin/claude` rather than the pinned `~/bin/claude`. Operations documentation states the pinned path is mandatory for manual invocations; the fallback may silently use an unpinned CLI.
- **gap-2 (notification on failure)**: exit 1 signals failure to the caller but does not send an inbox_write notification to karo or shogun. ninja_monitor, the primary caller, must detect exit 1 and decide whether to escalate.
- **gap-3 (inotifywait WARN exits 0)**: Incomplete inotifywait coverage is reported as a warning rather than a failure. Callers may treat a zero exit as a fully healthy restart even when some watchers lack file-change detection.

## Brownfield Evidence

- `scripts/restart_watchers.sh` implements the two-stage stop sequence and flock guard in its header block.
- `scripts/restart_watchers.sh` loops over `get_all_agents()` to launch dynamic agents.
- `scripts/restart_watchers.sh` performs liveness and inotifywait checks after the launch loop.
