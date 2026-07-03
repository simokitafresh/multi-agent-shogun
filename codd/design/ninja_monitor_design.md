---
codd:
  node_id: design:script:ninja-monitor
  type: design
  status: approved
  confidence: 0.9
  source: brownfield
  depends_on:
  - id: req:script:ninja-monitor
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/ninja_monitor.sh
---

# ninja_monitor.sh Brownfield Design

## Entry Flow

The daemon loads shared libraries, acquires a singleton pid file, discovers panes, then loops through idle detection, task/report reconciliation, health checks, auto-clear handling, snapshot generation, and notification routines.

## Related Files

- [[ninja_monitor_requirements]] defines the supervision, idle detection, reset safety, snapshot, and health-monitoring requirements satisfied by this design.
- [[ninja_monitor.sh]] is the implementation source for `check_idle`, `safe_send_clear`, `check_stall`, and `write_karo_snapshot`.
- [[ninja_monitor_brownfield]] records the brownfield findings and current implementation evidence for unresolved or downgraded design risks.
- [[test_ninja_monitor_stall.bats]] covers `count_unread_messages_cached`'s per-cycle cache/refresh contract (`tests/unit/test_ninja_monitor_stall.bats:484` `@test "count_unread_messages_cached: same cycle reuses count and next cycle refreshes"`); the unused non-cached duplicate `count_unread_messages` was removed as dead code (cmd_training_L4_auto_202607031741_kotaro).

## Core Components

- `acquire_singleton_lock`: prevents multiple monitor instances from acting on the same formation.
- `discover_panes` and `check_pane_survival`: map expected ninja names to tmux panes and repair/report pane identity problems.
- `check_idle`: combines tmux hook state, last-active grace, subprocess checks, CLI prompt parsing, and stale-state correction.
- `safe_send_clear`: clears or respawns only after idle confirmation and report gating.
- `check_and_update_done_task`, `check_stall`, `check_stale_cmds`, and `check_undeployed_cmds`: reconcile task/cmd lifecycle anomalies.
- `write_karo_snapshot`: writes a compact formation snapshot for karo recovery.
- Health functions: monitor ntfy, inbox watcher, lesson health, loop health, workaround trends, skill improvement, and training auto-deploy.

## Stall Detection Contract

`check_stall` only evaluates task statuses `assigned`, `acknowledged`, and `in_progress`, and ignores entries with no task id to avoid ghost deployment alerts. Newly deployed tasks receive a 300 second grace period from `deployed_at`.

Stall tracking starts only when `check_idle` confirms the target pane is idle. `assigned` uses `STALL_THRESHOLD_MIN`, `acknowledged` uses 10 minutes, and `in_progress` uses `cli_profiles.yaml` `in_progress_stall_min` with a 20 minute fallback. Recent `progress_updated_at` activity within 1200 seconds suppresses `in_progress` stall detection.

Notifications are debounced per `ninja:task` by `STALL_RENOTIFY_DEBOUNCE` and escalate after `STALL_ESCALATE_THRESHOLD` notifications. For `in_progress` stalls, the monitor also sends the ninja a `task_assigned` recovery message so the task YAML is re-read.

## Reset Safety Contract

`safe_send_clear` is the only reset path for healthy panes. It first delegates liveness to `check_idle`, then runs the report gate so `status=done` alone cannot erase pending post-task reporting work.

For Codex agents, reset uses `tmux respawn-pane -k` rather than `/new`, because Codex can keep an internal task-active state after the external task YAML has reached idle or done. The respawn path reloads the configured launch command from the project root and removes the idle flag after restart.

Before reset, the monitor marks the agent inbox read and may auto-commit selected infrastructure paths. This behavior belongs to the infrastructure daemon, not to an agent-to-agent communication path; normal agent messages still use inbox delivery.

## Data Boundaries

Inputs are tmux pane metadata/captures, `queue/tasks/`, `queue/reports/`, `queue/shogun_to_karo.yaml`, logs, and settings. Outputs are `queue/karo_snapshot.txt`, inbox notifications, ntfy messages, state files under `/tmp`, and monitor logs.

## Brownfield Evidence

- `scripts/ninja_monitor.sh` documents two-stage idle detection in its header.
- `scripts/ninja_monitor.sh` implements hook-first idle logic in `check_idle`.
- `scripts/ninja_monitor.sh` writes the formation snapshot in `write_karo_snapshot`.
- `codd/brownfield/ninja_monitor_brownfield.md` records the CoDD brownfield run for this target.
