# Semantic Audit: daemon/watcher Scripts (cmd_3102 Changes)
<!-- generated: 2026-05-30T02:50:00+09:00 by gunshi idle analysis -->

## Scope

7 scripts changed in HEAD~10 (172 insertions), primarily from cmd_3102 (hidden infra bug fixes):

| Script | Lines Changed | Source CMD |
|--------|--------------|------------|
| daemon_supervisor.sh | +22 | cmd_3102 |
| daemon_watchdog.sh | +5 | cmd_3102 |
| deploy_task.sh | +4 | cmd_3107 |
| gate_shogun_startup.sh | +115 | cmd_3108 |
| inbox_watcher.sh | +4 | cmd_3102 |
| ninja_monitor.sh | +5 | cmd_3102 |
| restart_watchers.sh | +28 | cmd_3102 |

gate_shogun_startup.sh (+115) is cmd_3108 (already reviewed APPROVE+LGTM+47/47 PASS). Focus: daemon/watcher 6 scripts.

## Categories Checked

1. **silent_failure**: Error suppression, return value ignoring, tmpfile loss, subshell return masking
2. **side_effect**: New bugs introduced by fixes (5 patterns from gunshi.md Step 4)
3. **race_condition**: TOCTOU, parallel writes, glob expansion races, non-atomic updates
4. **state_transition**: State transition gaps, dead states, missing transition logic
5. **implicit_assumption**: Cross-script implicit assumptions, deployment path branches

## Findings

### daemon_supervisor.sh (P1 all, 0 bugs)

| Line | Pattern | Priority | Verdict |
|------|---------|----------|---------|
| 73-78 | ppid lookup via /proc with `2>/dev/null \|\| true` | P1 | Design intent: graceful fallback when /proc unavailable. Safe direction (skip filtering) |
| 95-103 | `ds_oldest_pid()` new function | P1 | Input validation (`^[0-9]+$`) present. Pure function, no side effects |
| 133 | `ds_stop_duplicates`: newest->oldest PID kept | P1 | **Key behavioral change**. Risk: stuck oldest survives while healthy newest killed. Mitigated: ninja_monitor heartbeat detects stuck watchers independently |

### restart_watchers.sh (P1 all, 0 bugs)

| Line | Pattern | Priority | Verdict |
|------|---------|----------|---------|
| 22-34 | `watcher_process_count()`: pgrep->ps+awk parent filter | P1 | awk failure->count=0->restart trigger (safe direction). More accurate than pgrep |
| 40-41 | `pkill -TERM -f "[t]imeout.*inotifywait"` + fuser cleanup | P1 | LG016 compliant. During explicit restart only. Expected aggression |
| 70-79 | `verify_watcher_count()`: same parent filter | P1 | Consistent with count function. Diagnostic only (return 1 on mismatch) |

### inbox_watcher.sh (P1 all, 0 bugs)

| Line | Pattern | Priority | Verdict |
|------|---------|----------|---------|
| 925 | `209>&-` on inotifywait background | P1 | Prevents flock fd inheritance to child. Ensures lock release. Standard practice |
| 942 | `209>&-` on poller background | P1 | Same pattern. Consistent application |

### daemon_watchdog.sh (P1, 0 bugs)

| Line | Pattern | Priority | Verdict |
|------|---------|----------|---------|
| 253-256 | `flock -n restart_watchers.lock` skip guard | P1 | Race prevention: skip supervision during restart. Safe direction (defer, not fail) |

### ninja_monitor.sh (P1, 0 bugs)

| Line | Pattern | Priority | Verdict |
|------|---------|----------|---------|
| 3153-3156 | `flock -n restart_watchers.lock` skip guard | P1 | Same pattern as daemon_watchdog. Consistent. Prevents health check during restart |

## Side Effect Analysis (5 Patterns)

1. **return 1 propagation**: No new return 1 added. Skip guards return 0. OK
2. **set +e scope**: No set +e changes. OK
3. **Filter false negatives**: Parent filter could exclude legitimately parentless watchers. Risk: pgrep returns PID without parent -> filtered out -> counted as 0 -> unnecessary restart. Low risk, safe direction
4. **Cap state exclusion**: No cap/threshold changes. OK
5. **Non-atomic 2-step**: Lock check + skip is atomic (single flock call). OK

## Verdict

**Immediate fix required: 0 bugs. Side effect risk: 0.**

All changes are design-intent implementations for cmd_3102 (hidden infra bug fixes). The oldest-PID-kept change is the highest risk item but is mitigated by independent heartbeat monitoring.

## Causal Backlinks

- [[cmd_3102]] -> [[watcher duplicate counting]] -> [[parent filter + oldest-keep + fd closure + lock guard]]
- [[LG016]] -> [[timeout on daemon external calls]] -> [[fuser cleanup during restart]]
