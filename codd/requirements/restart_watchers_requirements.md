---
codd:
  node_id: req:script:restart-watchers
  type: requirement
  status: approved
  confidence: 0.85
  source: brownfield
  depended_by:
  - id: design:script:restart-watchers
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/restart_watchers.sh
---

# restart_watchers.sh Brownfield Requirements

## Purpose

`scripts/restart_watchers.sh` must atomically stop all inbox_watcher daemon processes and restart them for every configured agent, then verify that each watcher and its inotifywait subprocess are live before returning success.

## Functional Requirements

- FR-1: Acquire a singleton lock at `/tmp/restart_watchers.lock` using `flock -n` and abort with a non-zero exit code if another instance is already running.
- FR-2: Stop all existing `inbox_watcher.sh` processes via SIGTERM, wait one second, then escalate to SIGKILL for any survivors.
- FR-3: Launch the shogun watcher by resolving `@agent_cli` from the `shogun:main` pane option and starting `inbox_watcher.sh shogun` via `nohup` with log output to `logs/inbox_watcher_shogun.log`.
- FR-4: Launch the karo watcher using the `shogun:agents.1` pane and the same `@agent_cli`/nohup pattern.
- FR-5: Enumerate remaining agents from `scripts/lib/agent_config.sh::get_all_agents()`, skip karo, resolve each pane via `scripts/lib/pane_lookup.sh::pane_lookup()`, and skip agents whose pane is empty.
- FR-6: After launching all watchers, confirm each is detectable via `pgrep -f "inbox_watcher\.sh.*{agent}"`. Collect failures and exit 1 if any watcher failed to start.
- FR-7: After a two-second delay, check that the inotifywait process count matches the number of successfully started watchers and emit a warning if it does not.
- FR-8: Execute `scripts/sync_pane_vars.sh` to synchronize pane variables across the formation.

## Safety Requirements

- SR-1: Termination is two-stage (SIGTERM then optional SIGKILL); each stage checks remaining process count before escalating.
- SR-2: Pane resolution failures cause a silent skip, not an error, to allow partial formations to recover.
- SR-3: All watcher logs append to per-agent log files; stdout of the script itself is not redirected by default.
