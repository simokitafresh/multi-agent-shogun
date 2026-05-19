---
codd:
  node_id: test:acceptance-criteria
  type: test
  depends_on:
  - id: req:script:cmd-save
    relation: derives_from
    semantic: governance
  - id: req:script:deploy-task
    relation: derives_from
    semantic: governance
  - id: req:script:inbox-write
    relation: derives_from
    semantic: governance
  - id: req:script:ninja-monitor
    relation: derives_from
    semantic: governance
  - id: req:script:dashboard-auto-section
    relation: derives_from
    semantic: governance
  - id: req:script:restart-watchers
    relation: derives_from
    semantic: governance
  - id: req:deploy-task-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-overview
    relation: constrained_by
    semantic: governance
  - id: test:test-strategy
    relation: depends_on
    semantic: governance
  conventions:
  - targets:
    - module:inbox_write
    - module:cmd_save
    - module:deploy_task
    - module:yaml_helpers
    reason: flock-based atomic YAML writes and inbox-path-only communication are release-blocking
      safety constraints across all agent-facing scripts (SR-3 inbox_write, SR-1 deploy_task,
      SR-3 cmd_save).
  - targets:
    - module:yaml_helpers
    - module:deploy_task
    reason: API backward compatibility for yaml_field_set and field_get and zero test
      regressions are release-blocking for the batch refactor (refactor constraints).
  - targets:
    - module:inbox_write
    reason: Ninja-to-shogun direct messaging prohibition is a release-blocking routing
      constraint (SR-2 inbox_write).
  modules:
  - cmd_save
  - deploy_task
  - inbox_write
  - ninja_monitor
  - dashboard_auto_section
  - restart_watchers
  - yaml_helpers
---

# Acceptance Criteria

I don't have file read/write tools available in this environment - I only have the MCP memory tools which are blocked for ninja agents. However, the user has provided all the dependency documents in the prompt itself, so I can synthesize the acceptance criteria document directly from those.

# Acceptance Criteria

## 1. Overview

This document defines the acceptance criteria, failure criteria, and E2E test generation meta-prompt for the multi-agent-shogun infrastructure scripts. The scope covers seven core modules that form the backbone of agent communication, task deployment, monitoring, dashboard generation, watcher management, and YAML batch operations:

| Module | Script | Core Responsibility |
|--------|--------|-------------------|
| `cmd_save` | `scripts/cmd_save.sh` | Gate shogun command drafts before karo delegation |
| `deploy_task` | `scripts/deploy_task.sh` | Assign task YAML to ninja and wake via inbox path |
| `inbox_write` | `scripts/inbox_write.sh` | Atomic mailbox writer and agent wake-up bridge |
| `ninja_monitor` | `scripts/ninja_monitor.sh` | Continuous tmux formation supervision and health checks |
| `dashboard_auto_section` | `scripts/dashboard_auto_section.sh` | Auto-generate machine-managed dashboard sections |
| `restart_watchers` | `scripts/restart_watchers.sh` | Atomic watcher stop/restart with verification |
| `yaml_helpers` | `scripts/lib/yaml_field_set.sh`, `scripts/lib/field_get.sh` | Batch YAML field operations (`yaml_field_set_batch`, `field_get_multi`) |

### Non-Negotiable Convention Compliance

| Convention | How Addressed |
|-----------|---------------|
| **flock-based atomic YAML writes** (SR-3 inbox_write, SR-1 deploy_task, SR-3 cmd_save) | Every test that writes to `queue/inbox/*.yaml`, `queue/tasks/*.yaml`, or `queue/shogun_to_karo.yaml` asserts flock acquisition before write and atomic mv replacement. Concurrent write tests verify no data loss under parallel execution. |
| **inbox-path-only communication** (SR-3 deploy_task, SR-1 inbox_write) | Tests assert that `deploy_task.sh` delivers notifications exclusively through `inbox_write.sh`. Direct tmux send-keys is limited to re-nudge fallback. All message persistence is verified in `queue/inbox/{agent}.yaml`. |
| **Ninja-to-shogun direct messaging prohibition** (SR-2 inbox_write) | Dedicated negative tests confirm that `inbox_write.sh` rejects any call where sender is a ninja name and target is `shogun`. Exit code and error message are asserted. |
| **API backward compatibility for yaml_field_set and field_get** (refactor constraints) | All 48 existing `ac_handling` tests must pass without modification after introducing `yaml_field_set_batch` and `field_get_multi`. Existing single-field API signatures remain unchanged. |
| **Zero test regressions** (refactor constraints) | Full test suite runs before and after each refactor step (R1–R4). Any SKIP counts as FAIL. Delta in pass count must be ≥ 0. |

### Verifiable Behavior Inventory

The following table enumerates every verifiable behavior extracted from the dependency documents. Each behavior maps to one or more test scenarios in §2.

| ID | Source | Verifiable Behavior | Test Scenario(s) |
|----|--------|---------------------|-------------------|
| VB-01 | cmd_save FR-1 | Normalize numeric and `cmd_*` ids then load matching block from `shogun_to_karo.yaml` | AC-CS-01 |
| VB-02 | cmd_save FR-2 | Validate YAML syntax, command existence, delegated-state immutability, pending state, archive duplicates, concurrent draft conflicts | AC-CS-02a through AC-CS-02f |
| VB-03 | cmd_save FR-3 | Enforce quality_gate fields and diagnosis/environment-change when prior BLOCK/WARN history exists | AC-CS-03 |
| VB-04 | cmd_save FR-4 | Record BLOCK, WARN, PASS outcomes into quality logs and session-state files | AC-CS-04a, AC-CS-04b, AC-CS-04c |
| VB-05 | cmd_save FR-5 | Warn on lock contention, uncommitted changes, duplicate GP numbers, scout/recon overlap | AC-CS-05a through AC-CS-05d |
| VB-06 | cmd_save FR-6 | Update bulletin action tracking for referenced action-required bulletin ids | AC-CS-06 |
| VB-07 | cmd_save SR-1 | Block delegation while gate state is pending or blocked | AC-CS-SR1 |
| VB-08 | cmd_save SR-2 | Treat delegated commands as immutable | AC-CS-SR2 |
| VB-09 | cmd_save SR-3 | Use flock around shared queue files | AC-CS-SR3 |
| VB-10 | deploy_task FR-1 | Parse normal, `--direct`, `--yaml`, `--cmd` modes; preserve default stale-context-invalidation message | AC-DT-01a through AC-DT-01d |
| VB-11 | deploy_task FR-2 | Reject empty, `None`, or `cmd_*` as ninja target | AC-DT-02 |
| VB-12 | deploy_task FR-3 | Resolve target pane and determine idle/busy state via tmux/CLI helpers | AC-DT-03 |
| VB-13 | deploy_task FR-4 | Reset stale task fields, notification flags, ghost `None.yaml` artifacts | AC-DT-04 |
| VB-14 | deploy_task FR-5 | Resolve parent cmd into task metadata, AC, AC version, related lessons, semantic concepts, engineering prefs, execution controls | AC-DT-05 |
| VB-15 | deploy_task FR-6 | Generate/complete report template under `queue/reports/` without overwriting completed reports | AC-DT-06 |
| VB-16 | deploy_task FR-7 | Deliver task notification via `inbox_write.sh`; treat persisted writes as success even if post-delivery verification is flaky | AC-DT-07 |
| VB-17 | deploy_task SR-1 | Use shared YAML helpers, not free-form YAML dumping | AC-DT-SR1 |
| VB-18 | deploy_task SR-2 | Block duplicate active deployment when completed peer report exists | AC-DT-SR2 |
| VB-19 | deploy_task SR-3 | Keep communication on inbox path; direct tmux nudge limited to re-nudge fallback | AC-DT-SR3 |
| VB-20 | inbox_write FR-1 | Accept target, content, optional type/sender/action; reject missing/malformed targets | AC-IW-01 |
| VB-21 | inbox_write FR-2 | Validate target agents and enforce sender routing rules including ninja-to-shogun prohibition | AC-IW-02 |
| VB-22 | inbox_write FR-3 | Serialize message records with timestamps, ids, type, sender, content, read state, optional action | AC-IW-03 |
| VB-23 | inbox_write FR-4 | Use WSL2-compatible lock files on `/mnt/*` paths to prevent concurrent write loss | AC-IW-04 |
| VB-24 | inbox_write FR-5 | Block duplicate active `task_assigned` for same parent cmd | AC-IW-05 |
| VB-25 | inbox_write FR-6 | Lesson-injection safety net for task assignments when deploy helpers did not inject | AC-IW-06 |
| VB-26 | inbox_write FR-7 | Report format checks and downstream review/completion trigger for report notifications | AC-IW-07 |
| VB-27 | inbox_write FR-8 | Resolve panes and send CLI-specific nudges only after message persistence | AC-IW-08 |
| VB-28 | inbox_write SR-1 | Inbox persistence is durable source of truth; nudges are secondary | AC-IW-SR1 |
| VB-29 | inbox_write SR-2 | Ninja senders cannot bypass karo to message shogun | AC-IW-SR2 |
| VB-30 | inbox_write SR-3 | flock/atomic write semantics for all mailbox updates | AC-IW-SR3 |
| VB-31 | ninja_monitor FR-1 | Run as singleton daemon; rediscover ninja panes from tmux metadata | AC-NM-01 |
| VB-32 | ninja_monitor FR-2 | Detect idle/busy via `@agent_state`, timestamps, CLI prompt/busy patterns, subprocess cross-checks | AC-NM-02 |
| VB-33 | ninja_monitor FR-3 | Safe clear/respawn only after idle confirmation and report-gate checks | AC-NM-03 |
| VB-34 | ninja_monitor FR-4 | Detect pane loss, stale deployments, undeployed cmds, karo pending, CLI death, inbox unread, report/task mismatches | AC-NM-04a through AC-NM-04g |
| VB-35 | ninja_monitor FR-5 | Generate `queue/karo_snapshot.txt` with cmd, ninja, model, context, report state | AC-NM-05 |
| VB-36 | ninja_monitor FR-6 | Monitor inbox watcher, ntfy listener, CI status, training auto-deploy, lesson health, loop health, workaround trends, script size trends | AC-NM-06 |
| VB-37 | ninja_monitor SR-1 | Prefer hook state and explicit busy evidence over prompt-only idle detection | AC-NM-SR1 |
| VB-38 | ninja_monitor SR-2 | Never clear pane with active task state unless report and idle gates allow | AC-NM-SR2 |
| VB-39 | ninja_monitor SR-3 | Agent communication through `inbox_write.sh` | AC-NM-SR3 |
| VB-40 | dashboard FR-1 | Read 10 data sources: karo_snapshot, shogun_to_karo, gate_metrics, tasks/*.yaml, settings, cli_profiles, gate_fire_log, lesson_impact, lesson_effectiveness | AC-DA-01 |
| VB-41 | dashboard FR-2 | Invoke 5 external subprocesses: knowledge_metrics, model_analysis, context_freshness, ci_status, skill_metrics | AC-DA-02 |
| VB-42 | dashboard FR-3 | Generate 10 output sections: 忍者配備, CI Status, Unpushed Commits WARN, パイプライン, 戦況メトリクス, モデル別スコアボード, 知識サイクル健全度, スキル健全度, Context鮮度警告, 戦果 | AC-DA-03 |
| VB-43 | dashboard FR-4 | `--dry-run` outputs to stdout, leaves `dashboard.md` unchanged | AC-DA-04 |
| VB-44 | dashboard FR-5 | Preserve content outside `<!-- DASHBOARD_AUTO_START -->` / `<!-- DASHBOARD_AUTO_END -->` markers | AC-DA-05 |
| VB-45 | dashboard FR-6 | ntfy notification on CLEAR count increase only (dedup via `/tmp/mas-dashboard-ntfy-last-clear.txt`) | AC-DA-06 |
| VB-46 | dashboard FR-7 | Remove strikethrough entries from 将軍宛報告 section after auto-section update | AC-DA-07 |
| VB-47 | dashboard PR-1 | Cache CI status (60s), context freshness (120s), git rev-list (60s) | AC-DA-PR1 |
| VB-48 | dashboard PR-2 | Cache awk computations keyed by mtime of gate_fire_log, gate_metrics, lesson_impact, lesson_effectiveness | AC-DA-PR2 |
| VB-49 | dashboard PR-3 | Launch context_freshness and ci_status as background processes | AC-DA-PR3 |
| VB-50 | dashboard PR-4 | Project-scoped cache paths via `cksum` of `$PROJECT_DIR` | AC-DA-PR4 |
| VB-51 | dashboard SR-1 | Atomic write via temp file + `mv` | AC-DA-SR1 |
| VB-52 | dashboard SR-2 | Graceful degradation to `—` placeholders on missing data/subprocess failure | AC-DA-SR2 |
| VB-53 | dashboard SR-3 | Exit 0 on success, exit 1 on failure | AC-DA-SR3 |
| VB-54 | dashboard SR-4 | No modification when markers are absent | AC-DA-SR4 |
| VB-55 | restart_watchers FR-1 | Singleton lock at `/tmp/restart_watchers.lock` via `flock -n`; abort non-zero if already running | AC-RW-01 |
| VB-56 | restart_watchers FR-2 | Two-stage stop: SIGTERM → 1s wait → SIGKILL for survivors | AC-RW-02 |
| VB-57 | restart_watchers FR-3 | Launch shogun watcher from `shogun:main` pane `@agent_cli` via nohup | AC-RW-03 |
| VB-58 | restart_watchers FR-4 | Launch karo watcher from `shogun:agents.1` pane via same pattern | AC-RW-04 |
| VB-59 | restart_watchers FR-5 | Enumerate agents from `agent_config.sh::get_all_agents()`, skip karo, resolve panes, skip empty panes | AC-RW-05 |
| VB-60 | restart_watchers FR-6 | Verify each watcher via `pgrep -f`; collect failures and exit 1 on any failure | AC-RW-06 |
| VB-61 | restart_watchers FR-7 | After 2s delay, check inotifywait count matches watcher count; warn on mismatch | AC-RW-07 |
| VB-62 | restart_watchers FR-8 | Execute `sync_pane_vars.sh` post-launch | AC-RW-08 |
| VB-63 | restart_watchers SR-1 | Two-stage termination with process count check before escalation | AC-RW-SR1 |
| VB-64 | restart_watchers SR-2 | Pane resolution failures cause silent skip, not error | AC-RW-SR2 |
| VB-65 | restart_watchers SR-3 | Watcher logs append to per-agent log files | AC-RW-SR3 |
| VB-66 | refactor R1 | `resolve_cmd_to_task()` 7 yaml_field_set calls → 1 batch call via `yaml_field_set_batch` | AC-RF-01 |
| VB-67 | refactor R2 | `inject_ac_version()` 6-7 field_get → 1 awk pass via `field_get_multi`; 3 yaml_field_set → 1 batch | AC-RF-02 |
| VB-68 | refactor R3 | New `yaml_field_set_batch <file> <block_id> <field1>=<value1> ...` function with single flock + single awk pass | AC-RF-03 |
| VB-69 | refactor R4 | New `field_get_multi <file> <field1> <field2> ...` returning `field=value\n` pairs in single awk pass | AC-RF-04 |
| VB-70 | refactor perf | 1-test latency: 2639ms → ~400ms (-85%); 48 ac_handling tests: 34s → ~5s | AC-RF-PERF |

**Coverage flag**: All 70 verifiable behaviors have mapped test scenarios. No uncovered behaviors.

## 2. Acceptance Criteria

### 2.1 cmd_save.sh

| ID | Criterion | Assertion |
|----|-----------|-----------|
| AC-CS-01 | `cmd_save.sh 42` and `cmd_save.sh cmd_42` both load the `cmd_42` block from `queue/shogun_to_karo.yaml` and produce identical gate evaluations | Exit code identical; loaded block fields match |
| AC-CS-02a | Malformed YAML in the cmd block causes BLOCK with error message containing "YAML" | Exit code ≠ 0; `logs/cmd_design_quality.yaml` contains BLOCK entry for the cmd |
| AC-CS-02b | Nonexistent cmd id causes BLOCK with "not found" error | Exit code ≠ 0; BLOCK logged |
| AC-CS-02c | Cmd already in `delegated` state causes BLOCK with immutability error (SR-2) | Exit code ≠ 0; no state change in `shogun_to_karo.yaml` |
| AC-CS-02d | Cmd with pending predecessor in BLOCK state causes BLOCK | Exit code ≠ 0; BLOCK reason references pending predecessor |
| AC-CS-02e | Archive-duplicate cmd (same purpose/target as archived cmd) triggers WARN | WARN entry in quality log |
| AC-CS-02f | Concurrent draft conflict (two cmd_save.sh processes for different cmds) does not corrupt `shogun_to_karo.yaml` | Both processes complete; file is valid YAML; flock serialization verified via strace or timing |
| AC-CS-03 | Cmd with prior BLOCK history missing `diagnosis` or `environment_change` fields causes re-BLOCK | BLOCK entry references missing growth-loop fields |
| AC-CS-04a | BLOCK outcome writes entry to `logs/cmd_design_quality.yaml` with timestamp, cmd_id, outcome=BLOCK, reason | Entry present and parseable |
| AC-CS-04b | WARN outcome writes entry with outcome=WARN and specific warning codes | Entry present; warning codes match triggered conditions |
| AC-CS-04c | PASS outcome writes entry with outcome=PASS; session-state file updated | Entry present; `logs/gunshi_stats.yaml` or session file reflects PASS |
| AC-CS-05a | Lock contention on `shogun_to_karo.yaml` during save triggers WARN with "lock contention" | WARN logged; cmd_save still completes (waits for lock) |
| AC-CS-05b | Uncommitted implementation changes in working tree trigger WARN | WARN message references uncommitted files |
| AC-CS-05c | Duplicate GP number across cmds triggers WARN | WARN identifies the conflicting GP number and cmd |
| AC-CS-05d | Scout/recon cmd overlapping with existing gunshi analysis triggers WARN | WARN references the existing analysis file |
| AC-CS-06 | Cmd referencing action-required bulletin ids updates bulletin action tracking | `queue/bulletin_board.yaml` action entry linked to cmd |
| AC-CS-SR1 | Attempting to delegate cmd with gate_state=pending returns non-zero exit | Exit ≠ 0; no delegation side effects |
| AC-CS-SR2 | After delegation, editing the cmd block and re-running cmd_save causes BLOCK (immutability) | BLOCK with immutability reason |
| AC-CS-SR3 | Under 10 concurrent cmd_save invocations, `shogun_to_karo.yaml` never contains partial writes or corrupted YAML | All invocations exit cleanly; final file passes `yq eval` |

### 2.2 deploy_task.sh

| ID | Criterion | Assertion |
|----|-----------|-----------|
| AC-DT-01a | Normal mode: `deploy_task.sh hayate cmd_100` creates task YAML and sends inbox notification | `queue/tasks/hayate.yaml` contains `parent_cmd: cmd_100`; `queue/inbox/hayate.yaml` has `task_assigned` entry |
| AC-DT-01b | `--direct` mode deploys without cmd resolution | Task YAML created; no `parent_cmd` field or set to direct |
| AC-DT-01c | `--yaml` mode uses provided YAML content verbatim | Task YAML matches provided content |
| AC-DT-01d | `--cmd` mode resolves cmd metadata into task fields | Task YAML contains resolved metadata from `shogun_to_karo.yaml` cmd block |
| AC-DT-02 | `deploy_task.sh "" cmd_100`, `deploy_task.sh None cmd_100`, `deploy_task.sh cmd_100 hayate` all fail with target validation error | Exit code ≠ 0; error message identifies invalid target |
| AC-DT-03 | When target ninja pane is resolvable and idle, deployment proceeds; when busy, appropriate handling occurs | Idle: task assigned; Busy: warning or queuing behavior |
| AC-DT-04 | Before writing new assignment, stale `status`, `progress`, stale notification flags, and `queue/tasks/None.yaml` ghost file are cleaned up | `None.yaml` does not exist after deployment; stale fields reset to defaults |
| AC-DT-05 | `resolve_cmd_to_task()` populates `parent_cmd`, `task_id`, `task_type`, `project`, `status`, `purpose`, `_ac_task_id`, plus related_lessons, semantic_concepts, engineering_preferences, execution_controls | All fields present and non-empty in task YAML when source cmd contains them |
| AC-DT-06 | Report template generated under `queue/reports/` matching task; existing completed report is not overwritten | New deployment: report template exists; completed report: original content preserved |
| AC-DT-07 | Task notification delivered via `inbox_write.sh`; inbox entry has `type: task_assigned` and `read: false` | Inbox file contains the entry; no direct tmux send-keys for primary delivery |
| AC-DT-SR1 | All YAML mutations in deploy_task.sh use `yaml_field_set` or `yaml_field_set_batch` (no raw echo/cat/heredoc YAML writes) | grep of deploy_task.sh for prohibited patterns returns 0 matches |
| AC-DT-SR2 | Deploying cmd_100 to hayate when `queue/reports/cmd_100_kagemaru.yaml` already has `status: completed` blocks the duplicate deployment | Exit ≠ 0; error references existing completed report |
| AC-DT-SR3 | Primary delivery path is `inbox_write.sh`; tmux send-keys only used as re-nudge fallback | Execution trace shows inbox_write.sh called before any send-keys |

### 2.3 inbox_write.sh

| ID | Criterion | Assertion |
|----|-----------|-----------|
| AC-IW-01 | `inbox_write.sh karo "message" report_received hanzo` writes well-formed entry; missing target (`inbox_write.sh "" "msg"`) exits non-zero | Valid call: entry in inbox; invalid: exit ≠ 0 |
| AC-IW-02 | `inbox_write.sh shogun "msg" report hanzo` (ninja→shogun) is rejected; `inbox_write.sh karo "msg" report hanzo` (ninja→karo) succeeds | Ninja→shogun: exit ≠ 0, error contains routing prohibition message; ninja→karo: exit 0 |
| AC-IW-03 | Written message contains `timestamp` (ISO 8601), `id` (unique), `type`, `from`, `content`, `read: false`, and optional `action` | Parse inbox YAML; all fields present with correct types |
| AC-IW-04 | 10 parallel `inbox_write.sh` invocations to the same inbox produce exactly 10 entries with no data loss | Count entries; each has unique id; file is valid YAML |
| AC-IW-05 | Second `task_assigned` for same parent_cmd while first is `read: false` is blocked | Exit ≠ 0; only 1 task_assigned entry for that parent_cmd |
| AC-IW-06 | When `deploy_task.sh` did not inject lessons, `inbox_write.sh` for `task_assigned` type performs lesson-injection safety net | Task YAML or inbox entry includes lesson references |
| AC-IW-07 | `type: report_received` triggers report format validation; malformed report causes warning | Warning logged for malformed report; well-formed report triggers downstream review |
| AC-IW-08 | CLI nudge (tmux send-keys) is sent only after inbox file write is confirmed persisted | Instrumented test: inbox file write timestamp precedes nudge timestamp |
| AC-IW-SR1 | When nudge delivery fails (tmux pane unreachable), inbox entry still persists | Inbox file contains the entry despite nudge failure |
| AC-IW-SR2 | All 6 ninja names (hayate, kagemaru, hanzo, saizo, kotaro, tobisaru) as sender with `shogun` as target are rejected | 6 invocations; all exit ≠ 0 |
| AC-IW-SR3 | Lock file is created under WSL2-compatible path (not `/mnt/c` tmpfs); no EACCES or ENOLCK errors during concurrent writes | Lock file path verified; 10 concurrent writes complete without lock errors |

### 2.4 ninja_monitor.sh

| ID | Criterion | Assertion |
|----|-----------|-----------|
| AC-NM-01 | Second instance of ninja_monitor.sh exits immediately (singleton) | Second process exits non-zero; first continues running |
| AC-NM-02 | Idle detection uses `@agent_state` tmux variable, last-active timestamp (>threshold), CLI prompt pattern, and subprocess cross-check | Mock scenarios: agent_state=idle + no subprocess → detected idle; agent_state=idle + active subprocess → detected busy |
| AC-NM-03 | Pane with active task and incomplete report is never cleared even if idle timer expires | Task YAML has `status: in_progress` + no completed report → pane survives monitor cycle |
| AC-NM-04a | Lost pane (tmux pane removed) is detected and reported | Alert in karo inbox or snapshot |
| AC-NM-04b | Stale deployment (task assigned >2h with no progress) is flagged | Alert with stale deployment details |
| AC-NM-04c | Undeployed cmd (cmd in shogun_to_karo with no matching task) is flagged | Alert identifies the undeployed cmd |
| AC-NM-04d | Karo pending work is detected and reported | Snapshot reflects karo pending state |
| AC-NM-04e | CLI death (process exited) is detected | Alert via inbox_write to karo |
| AC-NM-04f | Inbox unread count is reported per agent | Snapshot contains unread count per agent |
| AC-NM-04g | Report/task mismatch (task completed but no report, or report exists but task not completed) is flagged | Alert identifies the mismatch |
| AC-NM-05 | `queue/karo_snapshot.txt` contains lines for each ninja with format: `ninja\|{name}\|{cmd}\|{status}\|{project}\|CTX:{pct}%\|M:{model}` | Parse snapshot; all active ninjas present with all fields |
| AC-NM-06 | Monitor checks inbox_watcher health, ntfy listener, CI status, training conditions, lesson health, loop health, workaround trends, script size trends | Log entries or snapshot sections for each monitored subsystem |
| AC-NM-SR1 | When `@agent_state=busy` but CLI prompt shows idle pattern, the hook state (busy) takes precedence | Agent not cleared despite prompt pattern match |
| AC-NM-SR2 | Agent with `status: in_progress` in task YAML and no completed report is never cleared | Clear attempt blocked; agent remains active |
| AC-NM-SR3 | All monitor-to-agent communication uses `inbox_write.sh` | grep of ninja_monitor.sh for direct send-keys communication (excluding re-nudge) returns 0 |

### 2.5 dashboard_auto_section.sh

| ID | Criterion | Assertion |
|----|-----------|-----------|
| AC-DA-01 | Script reads all 10 data sources: `karo_snapshot.txt`, `shogun_to_karo.yaml`, `gate_metrics.log`, `tasks/*.yaml`, `settings.yaml`, `cli_profiles.yaml`, `gate_fire_log.yaml`, `lesson_impact.tsv`, `lesson_effectiveness_status.txt` | Execution with all sources present produces complete output; execution with each source missing individually degrades gracefully to `—` |
| AC-DA-02 | 5 subprocess invocations (`knowledge_metrics.sh`, `model_analysis.sh`, `context_freshness_check.sh`, `ci_status_check.sh`, `skill_metrics.sh`) are called | Execution trace confirms all 5 calls |
| AC-DA-03 | Output contains all 10 sections: 忍者配備, CI Status, Unpushed Commits WARN, パイプライン, 戦況メトリクス, モデル別スコアボード, 知識サイクル健全度, スキル健全度, Context鮮度警告, 戦果 | grep for each section heading in output returns matches |
| AC-DA-04 | `--dry-run` outputs generated sections to stdout; `dashboard.md` mtime is unchanged | Compare mtime before/after; stdout contains section content |
| AC-DA-05 | Content before `<!-- DASHBOARD_AUTO_START -->` and after `<!-- DASHBOARD_AUTO_END -->` is byte-identical before and after execution | diff of non-auto sections returns 0 |
| AC-DA-06 | ntfy sent only when CLEAR count increases; repeated runs with same CLEAR count send no notification | First run with new CLEAR: ntfy called; second identical run: ntfy not called; dedup file `/tmp/mas-dashboard-ntfy-last-clear.txt` updated |
| AC-DA-07 | Strikethrough entries (`~~...~~`) in 将軍宛報告 section are removed after auto-section update | grep for `~~` in 将軍宛報告 section returns 0 after execution |
| AC-DA-PR1 | CI status cache (60s), context freshness cache (120s), git rev-list cache (60s) are respected | Two rapid executions: second uses cache (subprocess not re-invoked within TTL) |
| AC-DA-PR2 | awk computation cache invalidates when mtime of source files changes | Touch source file → re-run → awk recomputed; no touch → cached result used |
| AC-DA-PR3 | `context_freshness_check.sh` and `ci_status_check.sh` run as background processes (parallel) | Process tree or timing shows parallel execution |
| AC-DA-PR4 | Cache paths include project-scoped prefix derived from `cksum` of `$PROJECT_DIR` | Cache files under `/tmp/` contain cksum-derived component in path |
| AC-DA-SR1 | Dashboard is written atomically via temp file + `mv` | strace or filesystem observation: temp file created → content written → mv to dashboard.md |
| AC-DA-SR2 | Missing data source → corresponding section shows `—` placeholder, not error or blank | Remove each source; verify `—` in output |
| AC-DA-SR3 | Success → exit 0; missing dashboard.md → exit 1; missing markers → exit 1 | Test all 3 conditions |
| AC-DA-SR4 | Dashboard without `<!-- DASHBOARD_AUTO_START -->` marker → no modification, exit 1 | Dashboard file unchanged; exit 1 |

### 2.6 restart_watchers.sh

| ID | Criterion | Assertion |
|----|-----------|-----------|
| AC-RW-01 | Singleton lock at `/tmp/restart_watchers.lock`; concurrent second instance exits non-zero | Second process: exit ≠ 0; first process continues |
| AC-RW-02 | Existing watchers receive SIGTERM; after 1s, survivors receive SIGKILL | Process inspection: all old watchers terminated within 2s |
| AC-RW-03 | Shogun watcher launched from `shogun:main` pane's `@agent_cli` via nohup; log output to `logs/inbox_watcher_shogun.log` | Process running; log file exists and growing |
| AC-RW-04 | Karo watcher launched from `shogun:agents.1` pane | Process running with karo agent argument |
| AC-RW-05 | Agents enumerated from `get_all_agents()`; karo skipped; empty-pane agents skipped silently | Watcher count = agents with valid panes (minus karo) + shogun + karo |
| AC-RW-06 | `pgrep -f "inbox_watcher\.sh.*{agent}"` succeeds for each launched watcher; any failure → exit 1 | All pgrep succeed → exit 0; one fail → exit 1 with failure list |
| AC-RW-07 | After 2s delay, inotifywait process count matches watcher count; mismatch → warning | Matching: no warning; mismatched: warning message in output |
| AC-RW-08 | `sync_pane_vars.sh` is executed after all watchers launched | Execution trace confirms sync_pane_vars.sh called |
| AC-RW-SR1 | SIGTERM-only terminates all watchers → SIGKILL not sent; SIGTERM leaves survivors → SIGKILL sent for remaining | Two scenarios validated |
| AC-RW-SR2 | Agent with unresolvable pane is skipped without error | Exit code reflects only watcher launch failures, not pane resolution failures |
| AC-RW-SR3 | Each watcher's stdout/stderr appends to `logs/inbox_watcher_{agent}.log` | Log files grow across restarts; no truncation |

### 2.7 yaml_helpers (Batch Operations Refactor)

| ID | Criterion | Assertion |
|----|-----------|-----------|
| AC-RF-01 | `resolve_cmd_to_task()` uses single `yaml_field_set_batch` call instead of 7 individual `yaml_field_set` calls | grep or instrumented trace: 1 batch call, 0 individual yaml_field_set calls for those 7 fields |
| AC-RF-02 | `inject_ac_version()` uses `field_get_multi` (1 call) + `yaml_field_set_batch` (1 call) instead of 6-7 field_get + 3 yaml_field_set | Instrumented trace confirms batch calls |
| AC-RF-03 | `yaml_field_set_batch <file> <block_id> f1=v1 f2=v2 f3=v3` updates all 3 fields in 1 flock acquisition + 1 awk pass | strace: 1 flock call; awk invoked once; all 3 fields updated in output |
| AC-RF-04 | `field_get_multi <file> field1 field2 field3` returns `field1=value1\nfield2=value2\nfield3=value3\n` in 1 awk pass | Output matches expected; awk invoked once |
| AC-RF-03a | `yaml_field_set_batch` with fields containing special characters (spaces, colons, quotes, newlines) produces valid YAML | Output parsed by `yq eval` without error |
| AC-RF-03b | `yaml_field_set_batch` updates existing fields and adds new fields in the same call | Existing field: value changed; new field: added within correct block |
| AC-RF-03c | `yaml_field_set_batch` with zero field arguments exits non-zero | Exit ≠ 0; file unchanged |
| AC-RF-04a | `field_get_multi` for nonexistent field returns empty value for that field | Output: `missing_field=\n` |
| AC-RF-04b | `field_get_multi` with zero field arguments exits non-zero | Exit ≠ 0 |
| AC-RF-PERF | Single test execution time for `resolve_cmd_to_task` + `inject_ac_version` ≤ 500ms (down from 2639ms) | `time` measurement; threshold: 500ms |
| AC-RF-PERF2 | Full 48 `ac_handling` tests complete in ≤ 8s (down from 34s) | `time` measurement; threshold: 8s |
| AC-RF-COMPAT1 | Existing `yaml_field_set <file> <block_id> <field> <value>` API (single field) works unchanged | All existing call sites produce identical output |
| AC-RF-COMPAT2 | Existing `field_get <file> <field>` API (single field) works unchanged | All existing call sites return identical values |
| AC-RF-REGRESS | All 48 existing `ac_handling` tests pass with zero SKIP after refactor | Test output: 48 passed, 0 failed, 0 skipped |

## 3. Failure Criteria

Any of the following conditions constitutes a release-blocking failure:

### 3.1 Data Integrity Failures

| ID | Failure Condition | Impact |
|----|-------------------|--------|
| FC-01 | `queue/inbox/{agent}.yaml` contains corrupted or partial YAML after concurrent writes | Agent communication breakdown; messages lost |
| FC-02 | `queue/shogun_to_karo.yaml` loses cmd entries after concurrent `cmd_save.sh` invocations | Command delegation pipeline broken |
| FC-03 | `queue/tasks/{ninja}.yaml` contains fields from a previous deployment after reset (stale data leak) | Ninja executes wrong task |
| FC-04 | `yaml_field_set_batch` produces invalid YAML (fails `yq eval`) for any input combination | All downstream YAML consumers break |
| FC-05 | Completed report under `queue/reports/` is overwritten by new deployment | Historical data destroyed |

### 3.2 Safety Constraint Violations

| ID | Failure Condition | Impact |
|----|-------------------|--------|
| FC-06 | Ninja agent successfully sends message to shogun via `inbox_write.sh` | Chain-of-command violation; routing constraint broken |
| FC-07 | `cmd_save.sh` allows delegation of a cmd in BLOCK or pending gate state | Unvetted command enters deployment pipeline |
| FC-08 | `ninja_monitor.sh` clears a pane with `status: in_progress` and incomplete report | Active work destroyed |
| FC-09 | `deploy_task.sh` uses raw YAML dumping instead of shared YAML helpers | yaml.dump data loss risk (cmd_1399 incident class) |
| FC-10 | Direct tmux send-keys used as primary delivery path instead of inbox_write.sh | Message persistence not guaranteed |

### 3.3 Refactor Regression Failures

| ID | Failure Condition | Impact |
|----|-------------------|--------|
| FC-11 | Any of the 48 existing `ac_handling` tests fails after refactor | Regression in task deployment pipeline |
| FC-12 | Any test is marked SKIP (SKIP = FAIL per test rules) | Incomplete test coverage |
| FC-13 | `yaml_field_set` single-field API signature or behavior changes | All existing call sites across the codebase break |
| FC-14 | `field_get` single-field API signature or behavior changes | All existing call sites break |
| FC-15 | flock semantics differ between batch and single-field operations | Concurrent write safety regression |

### 3.4 Operational Failures

| ID | Failure Condition | Impact |
|----|-------------------|--------|
| FC-16 | `restart_watchers.sh` leaves orphaned watcher processes after restart cycle | Resource leak; duplicate message delivery |
| FC-17 | `dashboard_auto_section.sh` modifies content outside auto-section markers | Lord's manual dashboard content destroyed |
| FC-18 | `ninja_monitor.sh` fails to detect CLI death for >2 monitor cycles | Ninja silently offline; tasks stall |
| FC-19 | `dashboard_auto_section.sh` sends ntfy on every run regardless of CLEAR count change | Notification spam to lord |
| FC-20 | `restart_watchers.sh` without singleton lock allows concurrent restart causing watcher duplication | Multiple watchers per agent; duplicate inbox processing |

### 3.5 Performance Failures

| ID | Failure Condition | Impact |
|----|-------------------|--------|
| FC-21 | Single test execution exceeds 500ms after batch refactor (target: ~400ms) | Refactor goal not achieved; CI time unacceptable |
| FC-22 | 48 `ac_handling` tests exceed 8s total after batch refactor | CI pipeline slowdown |
| FC-23 | `dashboard_auto_section.sh` subprocess caching fails (every run re-invokes all subprocesses) | Dashboard update latency exceeds acceptable threshold |

## 4. E2E Test Generation Meta-Prompt

### 4.1 Architecture Detection

These modules are bash shell scripts running in a tmux-based multi-agent environment on WSL2. There is no web server or HTTP endpoint — all communication is file-based (YAML mailboxes) with tmux pane management. E2E tests use `bats-core` (Bash Automated Testing System) as the test framework.

### 4.2 Runtime Environment

```
# Prerequisites
- bats-core >= 1.10.0 installed
- tmux server running with `shogun` session and configured panes
- WSL2 environment with /mnt/c accessible
- yq (YAML processor) installed for validation assertions
- flock available (util-linux)

# Test startup sequence
1. Create isolated tmux session: `tmux new-session -d -s test_shogun`
2. Configure pane variables: `@agent_id`, `@agent_cli`, `@agent_state` for each test pane
3. Create fixture YAML files in $BATS_TMPDIR
4. Set PROJECT_DIR=$BATS_TMPDIR to isolate from production data
5. Source shared helpers: `load 'test_helper/common'`

# Teardown
1. Kill all spawned background processes (watchers, monitors)
2. Remove fixture files
3. Kill test tmux session: `tmux kill-session -t test_shogun`
```

### 4.3 MECE Domain Decomposition

| Domain | Scope | Output File |
|--------|-------|-------------|
| `cmd-save-gate` | cmd_save.sh: ID normalization, YAML validation, quality gate, BLOCK/WARN/PASS recording, bulletin tracking | `tests/e2e/cmd-save-gate.spec.bats` |
| `cmd-save-safety` | cmd_save.sh: flock concurrency, delegated-state immutability, pending-state blocking | `tests/e2e/cmd-save-safety.spec.bats` |
| `deploy-task-modes` | deploy_task.sh: normal/--direct/--yaml/--cmd modes, target validation, cmd resolution | `tests/e2e/deploy-task-modes.spec.bats` |
| `deploy-task-safety` | deploy_task.sh: stale field reset, report preservation, duplicate blocking, inbox-path-only delivery | `tests/e2e/deploy-task-safety.spec.bats` |
| `inbox-write-routing` | inbox_write.sh: target validation, sender routing, ninja-to-shogun prohibition, message serialization | `tests/e2e/inbox-write-routing.spec.bats` |
| `inbox-write-concurrency` | inbox_write.sh: flock/atomic writes, 10-parallel write integrity, WSL2 lock compatibility, duplicate task_assigned blocking | `tests/e2e/inbox-write-concurrency.spec.bats` |
| `inbox-write-features` | inbox_write.sh: lesson-injection safety net, report format checks, nudge-after-persist ordering | `tests/e2e/inbox-write-features.spec.bats` |
| `ninja-monitor-detection` | ninja_monitor.sh: singleton, idle/busy detection, pane loss, stale deployment, CLI death, snapshot generation | `tests/e2e/ninja-monitor-detection.spec.bats` |
| `ninja-monitor-safety` | ninja_monitor.sh: hook-state precedence, active-task clear protection, inbox-write-only communication | `tests/e2e/ninja-monitor-safety.spec.bats` |
| `dashboard-generation` | dashboard_auto_section.sh: 10 data sources, 5 subprocesses, 10 output sections, dry-run, marker preservation | `tests/e2e/dashboard-generation.spec.bats` |
| `dashboard-safety` | dashboard_auto_section.sh: atomic write, graceful degradation, ntfy dedup, strikethrough cleanup, exit codes | `tests/e2e/dashboard-safety.spec.bats` |
| `dashboard-performance` | dashboard_auto_section.sh: cache TTL (CI 60s, freshness 120s, git 60s), mtime-keyed cache, background processes, project-scoped paths | `tests/e2e/dashboard-performance.spec.bats` |
| `restart-watchers` | restart_watchers.sh: singleton lock, two-stage termination, per-agent launch, pgrep verification, inotifywait count, sync_pane_vars | `tests/e2e/restart-watchers.spec.bats` |
| `yaml-batch-ops` | yaml_field_set_batch + field_get_multi: batch semantics, special chars, edge cases, backward compatibility | `tests/e2e/yaml-batch-ops.spec.bats` |
| `yaml-batch-perf` | Performance: resolve_cmd_to_task ≤ 500ms, 48-test suite ≤ 8s, single-field API unchanged | `tests/e2e/yaml-batch-perf.spec.bats` |

### 4.4 Scenario Derivation Rules

1. **From Acceptance Criteria (positive)**: Each `AC-*` row in §2 generates one `@test` block asserting the stated behavior.
2. **From Acceptance Criteria (negative)**: Each `AC-*` row with "rejected" / "exit ≠ 0" / "blocked" generates a `@test` block confirming the negative path — invalid input, unauthorized sender, concurrent conflict.
3. **From Failure Criteria (inverted)**: Each `FC-*` row in §3 generates a `@test` block that creates the failure condition and asserts the system prevents or detects it. Example: FC-06 (ninja→shogun) → test that sends ninja→shogun and asserts exit ≠ 0.
4. **From Safety Requirements**: Each `SR-*` from every module generates at least one dedicated safety `@test` that isolates the constraint (flock, routing, immutability).

### 4.5 Architecture Adaptation

```
# Route/endpoint scanning rule for test generation:
# Since these are shell scripts (not HTTP endpoints), scan for:
# 1. Exported functions in scripts/lib/*.sh (public API surface)
# 2. Command-line argument modes (--direct, --yaml, --cmd, --dry-run)
# 3. tmux pane variable interfaces (@agent_id, @agent_state, @agent_cli)
# 4. File-based interfaces (queue/inbox/*.yaml, queue/tasks/*.yaml, etc.)
#
# For any function or mode referenced in requirements but not yet implemented:
#   @test "FIXME: yaml_field_set_batch not yet implemented" {
#     skip "Pending implementation — tracked by AC-RF-03"
#   }
# Note: skip counts as FAIL per test rules. Use test.fixme pattern
# only during generation; implementation must follow immediately.
```

### 4.6 Quality Gate

| Gate | Criterion |
|------|-----------|
| All PASS | Every `@test` block exits 0 |
| Zero SKIP | No `skip` directives in final test suite (SKIP = FAIL) |
| AC Coverage | Every `AC-*` ID from §2 appears in at least one `@test` block's name or comment |
| FC Coverage | Every `FC-*` ID from §3 has a corresponding prevention/detection `@test` |
| VB Coverage | Every `VB-*` ID from §1 Verifiable Behavior Inventory is exercised |
| Convention compliance | flock-based atomic writes verified in concurrency tests; ninja-to-shogun prohibition tested for all 6 ninja names; yaml_field_set backward compatibility confirmed by existing 48 tests passing |
| Performance thresholds | Single-test ≤ 500ms; 48-test suite ≤ 8s |

### 4.7 Shared Helpers

All shared test infrastructure resides in `tests/e2e/helpers/`:

| Helper File | Purpose |
|-------------|---------|
| `tests/e2e/helpers/common.bash` | `setup()` and `teardown()` for tmux test session, fixture directory creation, `PROJECT_DIR` isolation, `PATH` augmentation for scripts under test |
| `tests/e2e/helpers/fixtures.bash` | YAML fixture generators: `create_cmd_fixture`, `create_task_fixture`, `create_inbox_fixture`, `create_snapshot_fixture`, `create_dashboard_fixture` with marker insertion |
| `tests/e2e/helpers/assertions.bash` | `assert_yaml_valid`, `assert_yaml_field`, `assert_yaml_field_absent`, `assert_inbox_entry`, `assert_flock_held`, `assert_file_unchanged`, `assert_exit_nonzero` |
| `tests/e2e/helpers/tmux.bash` | `create_test_pane`, `set_pane_var`, `get_pane_var`, `simulate_idle_agent`, `simulate_busy_agent`, `cleanup_test_panes` |
| `tests/e2e/helpers/concurrency.bash` | `run_parallel <n> <command>` — launches n parallel instances, collects exit codes, returns combined result; `assert_no_data_loss <file> <expected_count>` |
| `tests/e2e/helpers/performance.bash` | `time_ms <command>` — returns execution time in milliseconds; `assert_under_threshold <actual_ms> <max_ms>` |

### 4.8 Generation Markers

All generated test files must include the following headers:

```bash
#!/usr/bin/env bats
# @generated-from: docs/test/acceptance_criteria.md
# @generated-by: codd propagate
```

Tests manually authored or modified must include `# @manual` on the first line after the shebang. `codd propagate` must preserve any `@test` block containing `# @manual` and not overwrite it on regeneration.

### 4.9 Output File Mapping

| Domain File | AC Coverage | FC Coverage |
|-------------|-------------|-------------|
| `tests/e2e/cmd-save-gate.spec.bats` | AC-CS-01 through AC-CS-06 | FC-02, FC-07 |
| `tests/e2e/cmd-save-safety.spec.bats` | AC-CS-SR1, AC-CS-SR2, AC-CS-SR3, AC-CS-02f | FC-02, FC-07 |
| `tests/e2e/deploy-task-modes.spec.bats` | AC-DT-01a through AC-DT-01d, AC-DT-02, AC-DT-05 | — |
| `tests/e2e/deploy-task-safety.spec.bats` | AC-DT-03, AC-DT-04, AC-DT-06, AC-DT-07, AC-DT-SR1, AC-DT-SR2, AC-DT-SR3 | FC-03, FC-05, FC-09, FC-10 |
| `tests/e2e/inbox-write-routing.spec.bats` | AC-IW-01, AC-IW-02, AC-IW-03, AC-IW-SR2 | FC-06 |
| `tests/e2e/inbox-write-concurrency.spec.bats` | AC-IW-04, AC-IW-05, AC-IW-SR3 | FC-01, FC-15 |
| `tests/e2e/inbox-write-features.spec.bats` | AC-IW-06, AC-IW-07, AC-IW-08, AC-IW-SR1 | FC-10 |
| `tests/e2e/ninja-monitor-detection.spec.bats` | AC-NM-01, AC-NM-02, AC-NM-04a through AC-NM-04g, AC-NM-05, AC-NM-06 | FC-18 |
| `tests/e2e/ninja-monitor-safety.spec.bats` | AC-NM-03, AC-NM-SR1, AC-NM-SR2, AC-NM-SR3 | FC-08 |
| `tests/e2e/dashboard-generation.spec.bats` | AC-DA-01, AC-DA-02, AC-DA-03, AC-DA-04, AC-DA-05 | FC-17 |
| `tests/e2e/dashboard-safety.spec.bats` | AC-DA-06, AC-DA-07, AC-DA-SR1, AC-DA-SR2, AC-DA-SR3, AC-DA-SR4 | FC-17, FC-19 |
| `tests/e2e/dashboard-performance.spec.bats` | AC-DA-PR1, AC-DA-PR2, AC-DA-PR3, AC-DA-PR4 | FC-23 |
| `tests/e2e/restart-watchers.spec.bats` | AC-RW-01 through AC-RW-08, AC-RW-SR1, AC-RW-SR2, AC-RW-SR3 | FC-16, FC-20 |
| `tests/e2e/yaml-batch-ops.spec.bats` | AC-RF-01, AC-RF-02, AC-RF-03, AC-RF-03a, AC-RF-03b, AC-RF-03c, AC-RF-04, AC-RF-04a, AC-RF-04b, AC-RF-COMPAT1, AC-RF-COMPAT2, AC-RF-REGRESS | FC-04, FC-11, FC-12, FC-13, FC-14, FC-15 |
| `tests/e2e/yaml-batch-perf.spec.bats` | AC-RF-PERF, AC-RF-PERF2 | FC-21, FC-22 |
