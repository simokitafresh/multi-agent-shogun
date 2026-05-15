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

## Core Components

- `acquire_singleton_lock`: prevents multiple monitor instances from acting on the same formation.
- `discover_panes` and `check_pane_survival`: map expected ninja names to tmux panes and repair/report pane identity problems.
- `check_idle`: combines tmux hook state, last-active grace, subprocess checks, CLI prompt parsing, and stale-state correction.
- `safe_send_clear`: clears or respawns only after idle confirmation and report gating.
- `check_and_update_done_task`, `check_stall`, `check_stale_cmds`, and `check_undeployed_cmds`: reconcile task/cmd lifecycle anomalies.
- `write_karo_snapshot`: writes a compact formation snapshot for karo recovery.
- Health functions: monitor ntfy, inbox watcher, lesson health, loop health, workaround trends, skill improvement, and training auto-deploy.

## Data Boundaries

Inputs are tmux pane metadata/captures, `queue/tasks/`, `queue/reports/`, `queue/shogun_to_karo.yaml`, logs, and settings. Outputs are `queue/karo_snapshot.txt`, inbox notifications, ntfy messages, state files under `/tmp`, and monitor logs.

## Brownfield Evidence

- `scripts/ninja_monitor.sh` documents two-stage idle detection in its header.
- `scripts/ninja_monitor.sh` implements hook-first idle logic in `check_idle`.
- `scripts/ninja_monitor.sh` writes the formation snapshot in `write_karo_snapshot`.
- `codd/brownfield/ninja_monitor_brownfield.md` records the CoDD brownfield run for this target.

