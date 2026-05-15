---
codd:
  node_id: req:script:ninja-monitor
  type: requirement
  status: approved
  confidence: 0.9
  source: brownfield
  implementation:
  - scripts/ninja_monitor.sh
---

# ninja_monitor.sh Brownfield Requirements

## Purpose

`scripts/ninja_monitor.sh` must continuously supervise the shogun tmux formation, detect idle/completed/stalled states, maintain infrastructure health, and notify karo or shogun through supported channels.

## Functional Requirements

- FR-1: Run as a singleton daemon and rediscover ninja panes from tmux metadata.
- FR-2: Detect idle/busy state using `@agent_state`, last-active timestamps, CLI-specific prompt/busy patterns, and subprocess cross-checks.
- FR-3: Safely clear or respawn agents only after idle confirmation and report-gate checks.
- FR-4: Detect pane loss, stale deployments, undeployed commands, karo pending work, CLI death, inbox unread counts, and report/task mismatches.
- FR-5: Generate `queue/karo_snapshot.txt` with cmd, ninja, model, context, and report state.
- FR-6: Monitor inbox watcher, ntfy listener, CI status, training auto-deploy conditions, lesson health, loop health, workaround trends, and script size trends.

## Safety Requirements

- SR-1: Prefer hook state and explicit busy evidence over prompt-only idle detection.
- SR-2: Never clear a pane with active task state unless report and idle gates allow it.
- SR-3: Send agent communication through `scripts/inbox_write.sh` rather than ad hoc message paths.

