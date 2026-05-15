# daemon_watchdog.sh CoDD Pipeline Report

Metadata:
- task_id: `cmd_training_codd_s3_saizo`
- target: `scripts/daemon_watchdog.sh`
- date: 2026-05-16
- worker: saizo
- scope: CoDD training/design-document creation only; no implementation changes

## AC1: Spec Equivalent

Command:
- `/home/simokitafresh/.codd-venv/bin/codd spec --help`

Result:
- FAIL: CoDD 2.18.0 has no `spec` subcommand.
- Compensation: this section records the required spec-equivalent purpose, constraints, and scope from direct script reading.

Purpose:
- Run from cron every minute and keep core Shogun daemons alive.
- Detect missing or stale daemon processes and restart them without requiring human intervention.
- Prevent restart storms with per-daemon throttling.
- Notify operators through `scripts/ntfy.sh` when critical watchdog events occur.
- Emit a heartbeat so external checks can verify that the watchdog itself is running.

Monitored Daemons:
- `scripts/ninja_monitor.sh`: single instance, PID-file assisted.
- `scripts/ntfy_listener.sh`: single instance, process-pattern based.
- `scripts/inbox_watcher.sh`: one watcher per agent, including shogun and all configured agents.

Primary Flow:
1. Resolve repo root, log path, heartbeat path, and restart-state directory.
2. Rotate watchdog log when it exceeds 1 MiB, retaining the last 500 lines.
3. Check crontab registration and warn if missing or still using old flock form.
4. Check `ninja_monitor.sh` through PID file, cmdline verification, fallback pgrep, restart, and startup survival verification.
5. Check `ntfy_listener.sh` through pgrep/cmdline matching and restart if missing.
6. Check each `inbox_watcher.sh`; if process exists, verify heartbeat freshness when unread messages exist.
7. Restart missing inbox watchers with the correct pane target and CLI type.
8. Apply restart-throttle state for each daemon to avoid restart storms.
9. Write `/tmp/daemon_watchdog_heartbeat`.
10. Log aggregate restart count or periodic OK status.

Constraints:
- The script intentionally does not use `set -e`; one daemon check failure must not skip later daemon checks.
- It must not hold a global flock internally; duplicate prevention is delegated to PID/process checks and the daemons themselves.
- Restart actions must be bounded by throttle windows.
- PID validity requires both `kill -0` and cmdline needle match.
- Inbox watcher hang kill only happens when heartbeat is stale and unread messages exist.
- Notifications must be best-effort and must not fail the watchdog.

Scope:
- In scope: daemon liveness checks, stale PID cleanup, restart, throttle state, watchdog heartbeat, warning notifications.
- Out of scope: changing daemon implementations, modifying task/report YAML, or replacing cron management.

## AC2: Elicit / Requirement Holes

Command:
- `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core`

Result:
- FAIL: `LexiconLoadError`, `shogun_core/manifest.yaml` missing required `prompt_extension`.

Manual elicit findings:

| ID | Gap | Risk | Suggested Coverage Axis |
| --- | --- | --- | --- |
| G1 | `check_ntfy_listener` records restart immediately after `nohup` without verifying the process survives startup. | False-positive restart notification if listener exits immediately. | Every restart path verifies post-start process survival or records degraded state. |
| G2 | `check_inbox_watchers` records restart immediately without verifying the watcher survived. | Missing watcher can remain down until next cron cycle while report says restarted. | Restart verification applies consistently to all daemon types. |
| G3 | The script warns about crontab flock form but does not surface the exact offending line. | Operator has to inspect crontab manually. | Crontab warning includes matched line or normalized remediation hint. |
| G4 | Restart state files under `/tmp/daemon_watchdog_state` are not validated for malformed content before arithmetic. | Corrupt state can produce noisy throttle behavior. | State files are parsed defensively and invalid rows are pruned with a log line. |
| G5 | `notify` can trigger outbound ntfy while `ntfy_listener` is itself unhealthy. | Critical listener restart storm notification may fail silently. | Notification delivery has fallback logging with explicit delivery status. |
| G6 | `check_inbox_watchers` depends on tmux pane lookup for agents. | If tmux metadata is stale, watcher restart can be skipped even when inbox exists. | Pane resolution failure is separately counted and surfaced in summary. |
| G7 | `DAEMON_WATCHDOG_LIB_ONLY=1` suppresses main checks but still executes top-level directory creation. | Unit tests sourcing functions can touch filesystem state unexpectedly. | Lib-only contract documents or avoids top-level runtime side effects. |
| G8 | Required tool preflight is implicit. | Missing `pgrep`, `tmux`, `crontab`, or `stat` creates partial failures inside checks. | Required tool availability is checked and reported before daemon checks. |

Coverage Axes:
- Restart survival verification: each restart path proves the process stayed alive after startup.
- Restart throttle integrity: malformed state and high-frequency restarts are handled deterministically.
- Pane resolution coverage: each agent watcher has an explicit pane lookup result.
- Notification observability: watchdog records whether operator notification was attempted and whether it failed.
- Lib-only safety: test mode has bounded side effects.
- Tool preflight: required OS commands are available before monitoring begins.

## AC3: Generate

Command:
- `timeout 120 /home/simokitafresh/.codd-venv/bin/codd generate --wave 1 --path .`

Result:
- TIMEOUT after 120 seconds.
- Last observed output: `wave_config not found. Auto-generating from requirements...`

Generated Design Status:
- CoDD did not generate a new design document for this target within the timeout.
- This file is the generated task design artifact for the training run, based on source reading and actual CoDD command results.

## AC4: Validate / DAG

Commands:
- `/home/simokitafresh/.codd-venv/bin/codd validate --path .`
- `/home/simokitafresh/.codd-venv/bin/codd dag verify --path . --format json`
- `bash -n scripts/daemon_watchdog.sh`
- `DAEMON_WATCHDOG_LIB_ONLY=1 bash scripts/daemon_watchdog.sh`

Results:
- `codd validate`: PASS, `OK: validated 16 Markdown files under configured doc_dirs`.
- `codd dag verify`: PASS overall.
- DAG warning: `depends_on_consistency` skipped because propagation output was absent.
- DAG warning: `runtime:db_seed:users` is unreachable in transitive closure.
- `bash -n`: PASS.
- Lib-only smoke: PASS, no stdout/stderr output.

## AC5: Measure / Quality Score

Command:
- `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json`

Result:
- `health_score`: 95.
- `validation_errors`: 0.
- `validation_warnings`: 0.
- `documents_checked`: 16.
- `total_nodes`: 16.
- `total_edges`: 12.
- `orphan_nodes`: 4.
- `design_documents`: 622.
- `coverage_ratio`: 0.0.

Design Quality Score for `daemon_watchdog.sh`: 81 / 100

Rationale:
- Strength: the script explicitly avoids `set -e`, matching watchdog semantics where later checks must run after an earlier check fails.
- Strength: PID validation includes cmdline matching, reducing stale or reused PID false positives.
- Strength: restart throttling is per daemon and limits repeated restarts.
- Weakness: only `ninja_monitor` restart verifies immediate survival.
- Weakness: CoDD repo coverage remains 0.0 for source files, so target-specific design coverage depends on this manual artifact.
- Weakness: lib-only mode still has top-level runtime directory creation.

Improvement Points:
1. Add post-restart survival verification for `ntfy_listener` and each `inbox_watcher`, mirroring `ninja_monitor`.
2. Add required-tool preflight for `pgrep`, `tmux`, `crontab`, `stat`, `tail`, and `ntfy.sh` availability.
3. Harden restart-state parsing against malformed timestamps and log pruned invalid rows.
4. Make crontab warnings include the matched old line or an exact replacement snippet.
5. Add a durable summary line for pane lookup failures by agent.
6. Clarify and test `DAEMON_WATCHDOG_LIB_ONLY=1` side-effect contract.
7. Add fixture tests for stale PID, missing process, restart throttle, inbox watcher stale heartbeat with unread, and stale heartbeat without unread.
8. Fix `shogun_core` lexicon manifest so `codd elicit` can generate machine findings.
9. Add CoDD coverage axes for daemon watchdog invariants: restart survival, throttle integrity, pane resolution, notification observability, and lib-only safety.

Binary AC Check:

| AC | Check | Result |
| --- | --- | --- |
| AC1 | Executed `codd spec` path and generated a spec-equivalent design section in `docs/research/`. | yes |
| AC2 | Executed `codd elicit` path and recorded requirement holes plus coverage axes. | yes |
| AC3 | Executed `codd generate` path and recorded timeout/error content. | yes |
| AC4 | Executed `codd validate` and DAG verification; recorded results. | yes |
| AC5 | Executed `codd measure`, reported quality score, and identified at least 3 improvements. | yes |
