---
codd:
  node_id: "req:shogun-monitor-refactor-requirements"
  type: requirement
  status: approved
  confidence: 0.95
---

# ninja_monitor.sh Modular Refactoring

## Overview
ninja_monitor.sh is the central daemon of the Shogun multi-agent system (tmux + bash).
It monitors 6 ninja agents, manages their lifecycle, and coordinates with karo (manager) agent.
Currently **3,158 lines with 59 functions in a single file**. Goal: split into focused modules.

## Current Architecture
- Runtime: bash 5.x on WSL2 (Ubuntu)
- Entry point: `scripts/ninja_monitor.sh`
- Daemon loop: 20-second poll cycle in main loop (L2860-3158)
- External dependencies: 12 `source`d libraries in `scripts/lib/` and `lib/`
- Shared state: tmux pane variables (@agent_state, @model_name, @context_pct, etc.)
- File I/O: queue/tasks/*.yaml, queue/inbox/*.yaml, queue/reports/*.yaml, logs/

## Functional Requirements

### FR-1: Module Extraction
Split 59 functions into logical modules under `scripts/lib/monitor/`:
- **idle_management.sh** — idle detection, clear orchestration, deploy-stall handling
  - check_idle, safe_send_clear, handle_confirmed_idle, handle_busy
  - _handle_post_clear_pending, _handle_deploy_stall, _handle_idle_notify, _handle_auto_clear
  - notify_idle_batch, _cleanup_stale_keys
- **stall_detection.sh** — task stall detection and cmd monitoring
  - check_stall, check_report_done_idle_mismatch
  - list_pending_cmds, check_stale_cmds, check_undeployed_cmds
- **health_checks.sh** — infrastructure health monitoring
  - check_ntfy_listener_health, check_inbox_watcher_health
  - check_lesson_health, check_loop_health, check_workaround_pattern, check_gate_improvement
  - check_yaml_size, run_cdp_cleanup, run_lock_cleanup, check_auto_archive
- **karo_monitor.sh** — karo-specific monitoring
  - check_karo_pending_cmd, check_karo_pending, check_karo_clear, send_karo_clear
  - check_karo_idle_cycle
- **pane_management.sh** — tmux pane operations and context tracking
  - discover_panes, check_pane_survival, check_ninja_cli_dead
  - update_context_pct, update_all_context_pct, get_context_pct
  - check_model_names, update_inbox_counts, check_shogun_ctx
- **report_utils.sh** — report file resolution
  - get_latest_report_file, find_matching_report_file, resolve_expected_report_file
  - can_send_clear_with_report_gate, check_and_update_done_task, is_task_deployed
- **state_io.sh** — state file I/O and snapshot generation
  - write_state_file, write_karo_snapshot

### FR-2: Main Loop Remains in ninja_monitor.sh
The main loop (dispatcher) stays in ninja_monitor.sh. It sources all modules and calls functions.
Target: ninja_monitor.sh shrinks from 3,158 to ~500 lines (global variables + main loop + source statements).

### FR-3: Shared State Access
All modules share access to:
- Global variables: NINJA_NAMES[], PANE_TARGETS[], STATE_DIR, SCRIPT_DIR, LOG, etc.
- Associative arrays: STALL_FIRST_SEEN[], STALL_NOTIFIED[], STALL_COUNT[], etc.
- Functions from sourced libraries: yaml_field_get, log, send_inbox_message, etc.

### FR-4: Zero Behavior Change
This is a pure structural refactoring. No logic changes. All 854 existing tests must pass.

## Non-Functional Requirements

### NFR-1: Source Order
Modules must be sourced after external libraries (cli_lookup.sh, etc.) because they depend on those functions.

### NFR-2: No New External Dependencies
No new packages, tools, or languages. Pure bash source-splitting.

### NFR-3: Testability
Each module can be sourced independently in test fixtures (with appropriate mocks).

## Constraints
- Language: Bash 5.x only
- No Python/Node.js in the monitor daemon
- Must work on WSL2 (NTFS-mounted /mnt/c paths)
- ninja_monitor.sh auto-restart mechanism (script hash detection) must detect module changes
- All 854 bats tests must continue to pass with zero SKIP
