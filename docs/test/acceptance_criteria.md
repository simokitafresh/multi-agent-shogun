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

## 1. Overview

This document defines acceptance criteria, failure criteria, and E2E test generation instructions for the multi-agent shogun infrastructure scripts: `cmd_save.sh`, `deploy_task.sh`, `inbox_write.sh`, `ninja_monitor.sh`, `dashboard_auto_section.sh`, `restart_watchers.sh`, and the `yaml_helpers` batch refactor (`yaml_field_set_batch`, `field_get_multi`).

### Scope

| Module | Script | Primary Responsibility |
|--------|--------|----------------------|
| `module:cmd_save` | `scripts/cmd_save.sh` | Gate shogun command drafts before karo delegation |
| `module:deploy_task` | `scripts/deploy_task.sh` | Assign task YAML to ninja + inbox wake-up |
| `module:inbox_write` | `scripts/inbox_write.sh` | Atomic mailbox write + agent wake-up bridge |
| `module:ninja_monitor` | `scripts/ninja_monitor.sh` | Singleton daemon supervising tmux formation |
| `module:dashboard_auto_section` | `scripts/dashboard_auto_section.sh` | Auto-generate dashboard.md machine-managed section |
| `module:restart_watchers` | `scripts/restart_watchers.sh` | Atomic stop/restart of all inbox_watcher daemons |
| `module:yaml_helpers` | `scripts/lib/yaml_field_set.sh`, `scripts/lib/field_get.sh` | Batch YAML read/write utilities |

### Release-Blocking Conventions Compliance

| Convention | Constraint | How This Document Reflects It |
|------------|-----------|-------------------------------|
| Conv-1: flock-based atomic YAML writes | All YAML mutations in `inbox_write`, `cmd_save`, `deploy_task`, `yaml_helpers` must use flock | AC-SAFETY-1 through AC-SAFETY-4 define flock assertions; Failure Criteria FC-LOCK-* catch violations |
| Conv-1: inbox-path-only communication | Agent messages travel through `queue/inbox/{agent}.yaml` exclusively | AC-INBOX-3, AC-INBOX-8 assert inbox persistence as source of truth; FC-COMM-1 catches direct tmux messaging |
| Conv-2: API backward compatibility | `yaml_field_set` and `field_get` existing signatures must continue to work after batch refactor | AC-YAML-1, AC-YAML-2 assert single-call API preservation; FC-COMPAT-1 catches signature breakage |
| Conv-2: zero test regressions | All existing 48+ tests in `ac_handling` must pass after refactor | AC-YAML-5 defines full regression gate |
| Conv-3: ninja-to-shogun prohibition | `inbox_write.sh` must reject ninja sender targeting shogun | AC-INBOX-2 defines the routing block; FC-ROUTE-1 catches bypass |

### Verifiable Behavior Enumeration

Every verifiable behavior extracted from the dependency design documents is listed below. Each behavior maps to one or more acceptance criteria (AC-*) and test scenarios in §4.

| ID | Source | Verifiable Behavior | AC Mapping |
|----|--------|---------------------|------------|
| VB-CMD-01 | req:cmd-save FR-1 | Normalize numeric and `cmd_*` ids then load matching block from `shogun_to_karo.yaml` | AC-CMD-1 |
| VB-CMD-02 | req:cmd-save FR-2 | Validate YAML syntax of command block | AC-CMD-2 |
| VB-CMD-03 | req:cmd-save FR-2 | Reject command when block does not exist in queue file | AC-CMD-2 |
| VB-CMD-04 | req:cmd-save FR-2 | Enforce delegated-state immutability (no mutation after delegation) | AC-CMD-3 |
| VB-CMD-05 | req:cmd-save FR-2 | Check previous pending command state before allowing new delegation | AC-CMD-3 |
| VB-CMD-06 | req:cmd-save FR-2 | Detect archive duplicates | AC-CMD-4 |
| VB-CMD-07 | req:cmd-save FR-2 | Detect concurrent draft conflicts | AC-CMD-4 |
| VB-CMD-08 | req:cmd-save FR-3 | Enforce quality_gate fields (q1-q3 BLOCK, q4 WARNING) | AC-CMD-5 |
| VB-CMD-09 | req:cmd-save FR-3 | Require diagnosis when prior BLOCK/WARN history exists | AC-CMD-6 |
| VB-CMD-10 | req:cmd-save FR-3 | Require environment_change when prior BLOCK/WARN history exists | AC-CMD-6 |
| VB-CMD-11 | req:cmd-save FR-4 | Record BLOCK outcome to quality logs and session-state files | AC-CMD-7 |
| VB-CMD-12 | req:cmd-save FR-4 | Record WARN outcome to quality logs and session-state files | AC-CMD-7 |
| VB-CMD-13 | req:cmd-save FR-4 | Record PASS outcome to quality logs and session-state files | AC-CMD-7 |
| VB-CMD-14 | req:cmd-save FR-5 | Warn on lock contention | AC-CMD-8 |
| VB-CMD-15 | req:cmd-save FR-5 | Warn on uncommitted implementation changes | AC-CMD-8 |
| VB-CMD-16 | req:cmd-save FR-5 | Warn on duplicate GP numbers | AC-CMD-8 |
| VB-CMD-17 | req:cmd-save FR-5 | Warn on scout/recon overlap with existing gunshi analysis | AC-CMD-8 |
| VB-CMD-18 | req:cmd-save FR-6 | Update bulletin action tracking when cmd references action-required bulletin ids | AC-CMD-9 |
| VB-CMD-19 | req:cmd-save SR-1 | Block delegation while gate state is pending or blocked | AC-CMD-3 |
| VB-CMD-20 | req:cmd-save SR-3 | Use flock around shared queue files | AC-SAFETY-1 |
| VB-DEPLOY-01 | req:deploy-task FR-1 | Parse normal positional deployment mode | AC-DEPLOY-1 |
| VB-DEPLOY-02 | req:deploy-task FR-1 | Parse `--direct` deployment mode | AC-DEPLOY-1 |
| VB-DEPLOY-03 | req:deploy-task FR-1 | Parse `--yaml` deployment mode | AC-DEPLOY-1 |
| VB-DEPLOY-04 | req:deploy-task FR-1 | Parse `--cmd` deployment mode | AC-DEPLOY-1 |
| VB-DEPLOY-05 | req:deploy-task FR-1 | Preserve default message that invalidates stale previous task context | AC-DEPLOY-2 |
| VB-DEPLOY-06 | req:deploy-task FR-2 | Validate first positional target is a ninja name | AC-DEPLOY-3 |
| VB-DEPLOY-07 | req:deploy-task FR-2 | Reject empty, `None`, or `cmd_*` id as target | AC-DEPLOY-3 |
| VB-DEPLOY-08 | req:deploy-task FR-3 | Resolve target pane via shared tmux/CLI helpers | AC-DEPLOY-4 |
| VB-DEPLOY-09 | req:deploy-task FR-3 | Determine idle/busy state before delivery | AC-DEPLOY-4 |
| VB-DEPLOY-10 | req:deploy-task FR-4 | Reset stale task fields before new assignment | AC-DEPLOY-5 |
| VB-DEPLOY-11 | req:deploy-task FR-4 | Reset stale notification flags | AC-DEPLOY-5 |
| VB-DEPLOY-12 | req:deploy-task FR-4 | Clean ghost `None.yaml` artifacts | AC-DEPLOY-5 |
| VB-DEPLOY-13 | req:deploy-task FR-5 | Resolve parent cmd into task metadata (parent_cmd, task_id, task_type, project, status, purpose, _ac_task_id) | AC-DEPLOY-6 |
| VB-DEPLOY-14 | req:deploy-task FR-5 | Inject acceptance criteria and AC version | AC-DEPLOY-6 |
| VB-DEPLOY-15 | req:deploy-task FR-5 | Inject related lessons | AC-DEPLOY-6 |
| VB-DEPLOY-16 | req:deploy-task FR-5 | Inject semantic concepts | AC-DEPLOY-6 |
| VB-DEPLOY-17 | req:deploy-task FR-5 | Inject engineering preferences and execution controls | AC-DEPLOY-6 |
| VB-DEPLOY-18 | req:deploy-task FR-6 | Generate report template under `queue/reports/` | AC-DEPLOY-7 |
| VB-DEPLOY-19 | req:deploy-task FR-6 | Do not overwrite completed reports | AC-DEPLOY-7 |
| VB-DEPLOY-20 | req:deploy-task FR-7 | Deliver task notification via `inbox_write.sh` | AC-DEPLOY-8 |
| VB-DEPLOY-21 | req:deploy-task FR-7 | Treat persisted inbox writes as successful even if post-delivery verification is flaky | AC-DEPLOY-8 |
| VB-DEPLOY-22 | req:deploy-task SR-1 | Use shared YAML helpers for queue/task mutation (no free-form YAML dump) | AC-SAFETY-2 |
| VB-DEPLOY-23 | req:deploy-task SR-2 | Block duplicate active deployments when completed peer report exists | AC-DEPLOY-9 |
| VB-DEPLOY-24 | req:deploy-task SR-3 | Keep communication on inbox path; tmux nudge only as re-nudge fallback | AC-DEPLOY-8 |
| VB-INBOX-01 | req:inbox-write FR-1 | Accept target, content, optional type, sender, action fields | AC-INBOX-1 |
| VB-INBOX-02 | req:inbox-write FR-1 | Reject missing or malformed targets | AC-INBOX-1 |
| VB-INBOX-03 | req:inbox-write FR-2 | Validate target agents against known agent list | AC-INBOX-2 |
| VB-INBOX-04 | req:inbox-write FR-2 | Enforce ninja-to-shogun prohibition | AC-INBOX-2 |
| VB-INBOX-05 | req:inbox-write FR-3 | Serialize message with timestamp, id, type, sender, content, read state, optional action | AC-INBOX-3 |
| VB-INBOX-06 | req:inbox-write FR-4 | Use lock files appropriate for WSL2 `/mnt/*` paths | AC-SAFETY-3 |
| VB-INBOX-07 | req:inbox-write FR-5 | Block duplicate active `task_assigned` for same parent cmd | AC-INBOX-4 |
| VB-INBOX-08 | req:inbox-write FR-6 | Provide lesson-injection safety net for task assignments | AC-INBOX-5 |
| VB-INBOX-09 | req:inbox-write FR-7 | Run report format checks for report notifications | AC-INBOX-6 |
| VB-INBOX-10 | req:inbox-write FR-7 | Trigger downstream review/completion for report notifications | AC-INBOX-6 |
| VB-INBOX-11 | req:inbox-write FR-8 | Resolve panes and send CLI-specific nudges only after message persistence | AC-INBOX-7 |
| VB-INBOX-12 | req:inbox-write SR-1 | Inbox persistence is durable source of truth; nudges are secondary | AC-INBOX-8 |
| VB-INBOX-13 | req:inbox-write SR-3 | Preserve flock/atomic write semantics for all mailbox updates | AC-SAFETY-3 |
| VB-MON-01 | req:ninja-monitor FR-1 | Run as singleton daemon (only one instance) | AC-MON-1 |
| VB-MON-02 | req:ninja-monitor FR-1 | Rediscover ninja panes from tmux metadata | AC-MON-1 |
| VB-MON-03 | req:ninja-monitor FR-2 | Detect idle state via `@agent_state`, timestamps, CLI patterns, subprocess cross-checks | AC-MON-2 |
| VB-MON-04 | req:ninja-monitor FR-2 | Detect busy state via same multi-signal approach | AC-MON-2 |
| VB-MON-05 | req:ninja-monitor FR-3 | Clear agents only after idle confirmation and report-gate checks | AC-MON-3 |
| VB-MON-06 | req:ninja-monitor FR-3 | Respawn agents after safe clear | AC-MON-3 |
| VB-MON-07 | req:ninja-monitor FR-4 | Detect pane loss | AC-MON-4 |
| VB-MON-08 | req:ninja-monitor FR-4 | Detect stale deployments | AC-MON-4 |
| VB-MON-09 | req:ninja-monitor FR-4 | Detect undeployed commands | AC-MON-4 |
| VB-MON-10 | req:ninja-monitor FR-4 | Detect karo pending work | AC-MON-4 |
| VB-MON-11 | req:ninja-monitor FR-4 | Detect CLI death | AC-MON-4 |
| VB-MON-12 | req:ninja-monitor FR-4 | Detect inbox unread counts | AC-MON-4 |
| VB-MON-13 | req:ninja-monitor FR-4 | Detect report/task mismatches | AC-MON-4 |
| VB-MON-14 | req:ninja-monitor FR-5 | Generate `queue/karo_snapshot.txt` with cmd, ninja, model, context, report state | AC-MON-5 |
| VB-MON-15 | req:ninja-monitor FR-6 | Monitor inbox watcher health | AC-MON-6 |
| VB-MON-16 | req:ninja-monitor FR-6 | Monitor ntfy listener health | AC-MON-6 |
| VB-MON-17 | req:ninja-monitor FR-6 | Monitor CI status | AC-MON-6 |
| VB-MON-18 | req:ninja-monitor FR-6 | Monitor training auto-deploy conditions | AC-MON-6 |
| VB-MON-19 | req:ninja-monitor FR-6 | Monitor lesson health, loop health, workaround trends, script size trends | AC-MON-6 |
| VB-MON-20 | req:ninja-monitor SR-1 | Prefer hook state and explicit busy evidence over prompt-only idle detection | AC-MON-2 |
| VB-MON-21 | req:ninja-monitor SR-2 | Never clear pane with active task state unless report and idle gates allow | AC-MON-3 |
| VB-MON-22 | req:ninja-monitor SR-3 | Send communication through `inbox_write.sh` | AC-SAFETY-4 |
| VB-DASH-01 | req:dashboard-auto-section FR-1 | Read all 9 data sources | AC-DASH-1 |
| VB-DASH-02 | req:dashboard-auto-section FR-2 | Invoke 5 external subprocess scripts | AC-DASH-2 |
| VB-DASH-03 | req:dashboard-auto-section FR-3 | Generate 10 output sections | AC-DASH-3 |
| VB-DASH-04 | req:dashboard-auto-section FR-4 | `--dry-run` outputs to stdout only | AC-DASH-4 |
| VB-DASH-05 | req:dashboard-auto-section FR-5 | Preserve content outside auto-section markers | AC-DASH-5 |
| VB-DASH-06 | req:dashboard-auto-section FR-6 | ntfy deduplication via `/tmp/mas-dashboard-ntfy-last-clear.txt` | AC-DASH-6 |
| VB-DASH-07 | req:dashboard-auto-section FR-7 | Remove strikethrough entries from 将軍宛報告 section | AC-DASH-7 |
| VB-DASH-08 | req:dashboard-auto-section PR-1 | Cache CI status (60s), context freshness (120s), git rev-list (60s) | AC-DASH-8 |
| VB-DASH-09 | req:dashboard-auto-section PR-2 | Cache awk computations keyed by mtime | AC-DASH-8 |
| VB-DASH-10 | req:dashboard-auto-section PR-3 | Parallel background launch of `context_freshness_check.sh` and `ci_status_check.sh` | AC-DASH-9 |
| VB-DASH-11 | req:dashboard-auto-section PR-4 | Project-scoped cache paths via `cksum` | AC-DASH-8 |
| VB-DASH-12 | req:dashboard-auto-section SR-1 | Atomic write via temp file + `mv` | AC-SAFETY-5 |
| VB-DASH-13 | req:dashboard-auto-section SR-2 | Graceful degradation to `—` placeholders on missing data | AC-DASH-10 |
| VB-DASH-14 | req:dashboard-auto-section SR-3 | Exit 0 on success, exit 1 on failure | AC-DASH-11 |
| VB-DASH-15 | req:dashboard-auto-section SR-4 | Do not modify dashboard when markers absent | AC-DASH-12 |
| VB-WATCH-01 | req:restart-watchers FR-1 | Acquire singleton lock at `/tmp/restart_watchers.lock` via `flock -n` | AC-WATCH-1 |
| VB-WATCH-02 | req:restart-watchers FR-1 | Abort non-zero if lock already held | AC-WATCH-1 |
| VB-WATCH-03 | req:restart-watchers FR-2 | SIGTERM all existing `inbox_watcher.sh` processes | AC-WATCH-2 |
| VB-WATCH-04 | req:restart-watchers FR-2 | Escalate to SIGKILL after 1s for survivors | AC-WATCH-2 |
| VB-WATCH-05 | req:restart-watchers FR-3 | Launch shogun watcher resolving `@agent_cli` from `shogun:main` pane | AC-WATCH-3 |
| VB-WATCH-06 | req:restart-watchers FR-4 | Launch karo watcher from `shogun:agents.1` pane | AC-WATCH-3 |
| VB-WATCH-07 | req:restart-watchers FR-5 | Enumerate agents from `agent_config.sh::get_all_agents()`, skip karo, resolve panes, skip empty | AC-WATCH-4 |
| VB-WATCH-08 | req:restart-watchers FR-6 | Post-launch `pgrep` verification per watcher | AC-WATCH-5 |
| VB-WATCH-09 | req:restart-watchers FR-6 | Exit 1 if any watcher failed to start | AC-WATCH-5 |
| VB-WATCH-10 | req:restart-watchers FR-7 | inotifywait count verification after 2s delay | AC-WATCH-6 |
| VB-WATCH-11 | req:restart-watchers FR-8 | Execute `sync_pane_vars.sh` | AC-WATCH-7 |
| VB-WATCH-12 | req:restart-watchers SR-1 | Two-stage termination (SIGTERM then SIGKILL) | AC-WATCH-2 |
| VB-WATCH-13 | req:restart-watchers SR-2 | Pane resolution failures cause silent skip | AC-WATCH-4 |
| VB-YAML-01 | req:deploy-task-refactor R3 | `yaml_field_set_batch` accepts file, block_id, and N field=value pairs | AC-YAML-1 |
| VB-YAML-02 | req:deploy-task-refactor R3 | Single flock + single awk pass for batch write | AC-YAML-1 |
| VB-YAML-03 | req:deploy-task-refactor R3 | verify_after_write executes once per batch | AC-YAML-1 |
| VB-YAML-04 | req:deploy-task-refactor R4 | `field_get_multi` accepts file and N field names | AC-YAML-2 |
| VB-YAML-05 | req:deploy-task-refactor R4 | Single awk pass for multi-field extraction | AC-YAML-2 |
| VB-YAML-06 | req:deploy-task-refactor R4 | Output format is eval-compatible `field=value` lines | AC-YAML-2 |
| VB-YAML-07 | req:deploy-task-refactor R1 | `resolve_cmd_to_task` uses `yaml_field_set_batch` (7→1 calls) | AC-YAML-3 |
| VB-YAML-08 | req:deploy-task-refactor R2 | `inject_ac_version` uses `field_get_multi` + `yaml_field_set_batch` (6+3→1+1 calls) | AC-YAML-4 |
| VB-YAML-09 | req:deploy-task-refactor | All 48+ existing `ac_handling` tests pass after refactor | AC-YAML-5 |
| VB-YAML-10 | req:deploy-task-refactor | Existing single-call `yaml_field_set` API unchanged | AC-YAML-6 |
| VB-YAML-11 | req:deploy-task-refactor | Existing single-call `field_get` API unchanged | AC-YAML-6 |
| VB-YAML-12 | req:deploy-task-refactor | `resolve_cmd_to_task` completes in ≤150ms (was 627ms) | AC-YAML-7 |
| VB-YAML-13 | req:deploy-task-refactor | `inject_ac_version` completes in ≤120ms (was 541ms) | AC-YAML-7 |

**Coverage gap check**: All 88 verifiable behaviors are mapped. No unmapped behaviors.

## 2. Acceptance Criteria

### cmd_save.sh

**AC-CMD-1: ID Normalization and Block Loading**
Given a numeric id `123` or a prefixed id `cmd_123`, when `cmd_save.sh` is invoked, then it normalizes to `cmd_123` and loads the corresponding block from `queue/shogun_to_karo.yaml`. If no matching block exists, exit with BLOCK and a diagnostic message naming the missing id.

**AC-CMD-2: YAML Syntax and Existence Validation**
Given a command block loaded from `shogun_to_karo.yaml`, when the block contains malformed YAML, then exit BLOCK with a syntax error message. When the command block does not exist in the file, exit BLOCK with a missing-command error.

**AC-CMD-3: Delegation State Guards**
- When a command is already in `delegated` state, reject any further mutation and exit BLOCK with an immutability violation message.
- When a previous command for the same scope is in `pending` or `blocked` state, exit BLOCK naming the conflicting command id.
- When a command's gate state is `pending` or `blocked`, do not proceed to delegation.

**AC-CMD-4: Duplicate and Conflict Detection**
- When an identical command id exists in the archive, exit BLOCK naming the duplicate.
- When another draft with overlapping scope is being concurrently edited (detected via lock file or session state), emit WARN with the conflicting draft id.

**AC-CMD-5: Quality Gate Enforcement**
- Fields `q1`, `q2`, `q3`: BLOCK when any is missing or fails validation.
- Field `q4` (depth assessment): WARN when depth is `shallow`; do not BLOCK.
- All quality_gate field names and thresholds are as defined in `scripts/cmd_save.sh` quality_gate section.

**AC-CMD-6: Growth Loop — Diagnosis and Environment Change**
When the command author has prior BLOCK or WARN history (from `logs/gate_metrics.log` or session state), then:
- A `diagnosis` field must be present; missing diagnosis → BLOCK.
- An `environment_change` field must be present with structured `type`, `file`, `pattern` subfields; missing → BLOCK.
- The `pattern` in `environment_change` must be verifiable via `grep` against the specified `file`; unverifiable → WARN.

**AC-CMD-7: Outcome Recording**
For each gate run, write exactly one outcome record to:
- `logs/gate_metrics.log` — append-only line with timestamp, cmd_id, outcome (BLOCK/WARN/PASS), and trigger fields.
- Session state file (`/tmp/mas-cmd-save-session-*.json` or equivalent) — update with latest outcome.

**AC-CMD-8: Advisory Warnings**
Emit WARN (non-blocking) for each of:
- Lock contention detected on `shogun_to_karo.yaml` during read.
- Uncommitted changes in implementation files referenced by the command.
- GP number in the command already exists in `logs/gate_fire_log.yaml`.
- Scout/recon command overlaps with an existing gunshi analysis file in `context/gunshi-*.md`.

**AC-CMD-9: Bulletin Action Tracking**
When the command's `bulletin_ids` field references action-required bulletin entries, update `queue/bulletin_board.yaml` to mark those entries as acted upon with the new cmd id.

### deploy_task.sh

**AC-DEPLOY-1: Deployment Mode Parsing**
- Normal mode: `deploy_task.sh <ninja> <cmd_id>` assigns task from cmd metadata.
- `--direct` mode: `deploy_task.sh --direct <ninja> "<message>"` sends a direct task.
- `--yaml` mode: `deploy_task.sh --yaml <ninja> <yaml_file>` uses pre-built task YAML.
- `--cmd` mode: `deploy_task.sh --cmd <cmd_id> <ninja>` resolves cmd then deploys.
Each mode produces a valid task YAML in `queue/tasks/{ninja}.yaml`.

**AC-DEPLOY-2: Stale Context Invalidation**
The default inbox message delivered to the ninja must contain a directive that invalidates any pre-existing task context (e.g., "タスクYAMLを読んで作業開始せよ。").

**AC-DEPLOY-3: Target Validation**
- Accept only known ninja names (hayate, kagemaru, hanzo, saizo, kotaro, tobisaru) as the target.
- Reject empty string, `None`, any `cmd_*` pattern, and unknown names with a non-zero exit code and diagnostic message.

**AC-DEPLOY-4: Pane Resolution and State Detection**
Resolve the target ninja's tmux pane via `scripts/lib/pane_lookup.sh`. Query `@agent_state` to determine idle/busy. Log the detected state. Proceed with deployment regardless of state (busy ninja receives the assignment for next pickup).

**AC-DEPLOY-5: Stale Artifact Cleanup**
Before writing the new task YAML:
- Reset fields `status`, `progress`, `binary_checks`, `lesson_candidate`, `decision_candidate` to their default empty/initial values.
- Clear stale notification flags (`_notify_sent`, `_nudge_count`).
- If `queue/tasks/None.yaml` exists, delete it (ghost artifact).

**AC-DEPLOY-6: CMD-to-Task Metadata Resolution**
When deploying from a parent cmd, the task YAML must contain:
- `parent_cmd`: the cmd id string.
- `task_id`: generated from cmd id + ninja name.
- `task_type`: derived from cmd type field.
- `project`: from cmd project field.
- `status`: set to `assigned`.
- `purpose`: from cmd purpose/description.
- `_ac_task_id`: internal AC tracking hash.
- `acceptance_criteria`: full AC list from the cmd.
- `ac_version`: computed hash of the AC content.
- `related_lessons`: injected from `projects/{project}/lessons.yaml` matching cmd scope.
- `semantic_concepts`: injected from semantic index matching cmd keywords.
- `engineering_preferences`: from cmd or project defaults.
- `execution_controls`: from cmd (timeout, retry policy, resource limits).

**AC-DEPLOY-7: Report Template Generation**
- Create `queue/reports/{cmd_id}_{ninja}.yaml` with template fields (status: pending, sections matching AC list).
- If a report file for the same cmd+ninja already exists with `status: completed`, do not overwrite; log a skip message.

**AC-DEPLOY-8: Inbox Delivery**
- Invoke `scripts/inbox_write.sh {ninja} "{message}" task_assigned karo`.
- If `inbox_write.sh` exits 0, treat as success regardless of any post-delivery tmux verification result.
- Direct tmux `send-keys` is permitted only as a re-nudge fallback after inbox write succeeds.

**AC-DEPLOY-9: Duplicate Deployment Block**
When a completed report exists at `queue/reports/{cmd_id}_*.yaml` with `status: completed`, and a new deployment is attempted for the same parent cmd, exit BLOCK with a message naming the completed report.

### inbox_write.sh

**AC-INBOX-1: Argument Acceptance and Rejection**
- Accept: `inbox_write.sh <target> "<content>" [type] [sender] [action]`.
- Reject with exit code 1: missing `<target>`, empty `<target>`, malformed target (contains `/`, `..`, or whitespace).

**AC-INBOX-2: Routing Rules**
- Accept messages to: shogun, karo, gunshi, hayate, kagemaru, hanzo, saizo, kotaro, tobisaru.
- When sender is any ninja (hayate|kagemaru|hanzo|saizo|kotaro|tobisaru) and target is `shogun`, exit code 1 with message "ninja-to-shogun direct messaging prohibited".
- Ninja senders may target karo or gunshi.

**AC-INBOX-3: Message Serialization**
Each message appended to `queue/inbox/{target}.yaml` must contain:
- `id`: unique string (timestamp-based or UUID).
- `timestamp`: ISO 8601 with timezone.
- `type`: from argument or default `general`.
- `from`: sender name.
- `content`: message text (multi-line preserved via YAML block scalar).
- `read`: `false`.
- `action`: from argument if provided, otherwise omitted.

**AC-INBOX-4: Duplicate Task Assignment Block**
When `type=task_assigned` and the target ninja's inbox already contains an unread `task_assigned` message for the same `parent_cmd`, exit 0 with a deduplication log message (no duplicate write).

**AC-INBOX-5: Lesson Injection Safety Net**
When `type=task_assigned` and the task YAML at `queue/tasks/{target}.yaml` has an empty `related_lessons` field, append a warning note to the inbox message content indicating lessons were not pre-injected.

**AC-INBOX-6: Report Notification Processing**
When `type=report_received`:
- Validate report YAML at `queue/reports/{referenced_report}.yaml` for required fields (status, binary_checks, lesson_candidate).
- If validation fails, append a format-error note to the inbox message.
- Trigger downstream: write a `review_pending` flag or send a follow-up message to gunshi/karo.

**AC-INBOX-7: Nudge Ordering**
CLI-specific nudge (tmux `send-keys` with `inboxN` pattern) must execute only after the inbox file write returns successfully. If file write fails, no nudge is sent.

**AC-INBOX-8: Persistence as Source of Truth**
The message must be present in `queue/inbox/{target}.yaml` and readable by a subsequent `cat` or `grep` immediately after `inbox_write.sh` exits 0, regardless of whether the tmux nudge succeeded.

### ninja_monitor.sh

**AC-MON-1: Singleton and Pane Discovery**
- Only one instance runs at a time (PID file or flock).
- On startup, enumerate all ninja panes from tmux session `shogun:agents` using `@agent_id` metadata.
- Rediscover panes periodically (each monitoring cycle).

**AC-MON-2: Multi-Signal State Detection**
Idle detection requires conjunction of:
- `@agent_state` tmux variable equals `idle`.
- Last-active timestamp older than threshold (configurable, default 120s).
- CLI prompt pattern matches idle regex (no active tool execution).
- No child subprocess (beyond shell) detected via `pgrep -P`.
Busy detection: any one of the above signals indicates active work.

**AC-MON-3: Safe Clear and Respawn**
- Before clearing a pane: verify idle (AC-MON-2) AND no pending report (task YAML `status` ≠ `in_progress`).
- After clear: respawn the agent CLI with the profile from `config/cli_profiles.yaml`.
- If report gate fails, skip clear and log the reason.

**AC-MON-4: Anomaly Detection Suite**
Detect and report (via `inbox_write.sh` to karo) each of:
- Missing pane (expected pane id not found in tmux).
- Stale deployment (task `status: assigned` with `assigned_at` older than 30 minutes and no progress).
- Undeployed commands (cmd in `shogun_to_karo.yaml` with `status: delegated` but no matching task YAML).
- Karo pending work (unread karo inbox count > 0 for more than 5 minutes).
- CLI death (pane exists but no `claude` process detected).
- Inbox unread accumulation (agent inbox unread count > 3).
- Report/task mismatch (task `status: completed` but no corresponding report file).

**AC-MON-5: Snapshot Generation**
`queue/karo_snapshot.txt` is regenerated each monitoring cycle containing:
- Header with generation timestamp.
- One line per agent: `{role}|{name}|{current_cmd}|{state}|{project}|CTX:{ctx_pct}%|M:{model_abbrev}`.
- Report status section: pending/completed counts per cmd.

**AC-MON-6: Infrastructure Health Monitoring**
Each cycle checks and reports:
- `inbox_watcher.sh` process alive per agent (via `pgrep`).
- `ntfy_listener` process alive.
- CI status (cached, see dashboard PR-1).
- Training auto-deploy eligibility (idle ninja count ≥ 1 AND no active training cmd).
- Lesson health: `lessons.yaml` file mtime freshness.
- Loop health: gate_fire_log growth rate.
- Workaround trend: `karo_workarounds.yaml` entry count delta.
- Script size trend: line count of monitored scripts (WARN if > 4000 lines).

### dashboard_auto_section.sh

**AC-DASH-1: Data Source Reading**
Read all 9 data sources on each invocation:
`karo_snapshot.txt`, `shogun_to_karo.yaml`, `gate_metrics.log`, `tasks/*.yaml`, `settings.yaml`, `cli_profiles.yaml`, `gate_fire_log.yaml`, `lesson_impact.tsv`, `lesson_effectiveness_status.txt`.

**AC-DASH-2: Subprocess Invocation**
Invoke: `knowledge_metrics.sh`, `model_analysis.sh`, `context_freshness_check.sh`, `ci_status_check.sh`, `skill_metrics.sh`. Each returns structured output parsed into the corresponding dashboard section.

**AC-DASH-3: 10 Output Sections**
Generate exactly these sections between `<!-- DASHBOARD_AUTO_START -->` and `<!-- DASHBOARD_AUTO_END -->`:
1. 忍者配備 (ninja deployment table)
2. CI Status (pass/fail/pending)
3. Unpushed Commits WARN (count + oldest commit age)
4. パイプライン (cmd pipeline status)
5. 戦況メトリクス (gate BLOCK/WARN/PASS counts, CLEAR rate)
6. モデル別スコアボード (per-model gate outcomes)
7. 知識サイクル健全度 (lesson count, freshness, coverage)
8. スキル健全度 (skill count, usage, staleness)
9. Context鮮度警告 (files older than threshold)
10. 戦果 (CLEAR count, cumulative achievements)

**AC-DASH-4: Dry Run Mode**
When `--dry-run` is passed, output the generated section to stdout and do not modify `dashboard.md`. Exit 0.

**AC-DASH-5: Content Preservation**
All content in `dashboard.md` before `<!-- DASHBOARD_AUTO_START -->` and after `<!-- DASHBOARD_AUTO_END -->` must be byte-identical before and after execution.

**AC-DASH-6: ntfy Deduplication**
- Read last CLEAR count from `/tmp/mas-dashboard-ntfy-last-clear.txt`.
- Send ntfy only when current CLEAR count > stored count.
- Write current CLEAR count to the dedup file after sending.

**AC-DASH-7: Strikethrough Cleanup**
After updating the auto section, scan the 将軍宛報告 section (outside auto markers) for lines matching `~~...~~` and remove them.

**AC-DASH-8: Caching**
- CI status subprocess: cache result for 60s keyed by `cksum($PROJECT_DIR)`.
- Context freshness subprocess: cache result for 120s.
- `git rev-list` output: cache for 60s.
- awk computation results: cache keyed by `mtime` of source files (`gate_fire_log.yaml`, `gate_metrics.log`, `lesson_impact.tsv`, `lesson_effectiveness_status.txt`). Recompute only when mtime changes.
- All cache paths include `cksum($PROJECT_DIR)` to isolate cross-project runs.

**AC-DASH-9: Parallel Subprocess Launch**
`context_freshness_check.sh` and `ci_status_check.sh` must be launched as background processes (`&`) and `wait`-ed together to reduce wall-clock time.

**AC-DASH-10: Graceful Degradation**
When any data source file is missing or any subprocess exits non-zero, substitute `—` for that section's data. Do not abort the entire dashboard generation.

**AC-DASH-11: Exit Codes**
- Exit 0: dashboard.md exists, markers found, generation completed.
- Exit 1: dashboard.md missing OR markers not found.

**AC-DASH-12: Missing Marker Guard**
When `<!-- DASHBOARD_AUTO_START -->` or `<!-- DASHBOARD_AUTO_END -->` is absent from `dashboard.md`, exit 1 without modifying the file.

### restart_watchers.sh

**AC-WATCH-1: Singleton Lock**
Acquire `/tmp/restart_watchers.lock` via `flock -n`. If lock is held by another process, exit with non-zero code and a message indicating concurrent execution.

**AC-WATCH-2: Two-Stage Termination**
1. Send SIGTERM to all processes matching `inbox_watcher\.sh`.
2. Wait 1 second.
3. Re-check for survivors via `pgrep`.
4. Send SIGKILL to any remaining survivors.
5. Verify zero remaining `inbox_watcher.sh` processes before proceeding to launch.

**AC-WATCH-3: Shogun and Karo Watcher Launch**
- Resolve `@agent_cli` from tmux pane `shogun:main` for shogun watcher.
- Resolve `@agent_cli` from tmux pane `shogun:agents.1` for karo watcher.
- Launch each via `nohup inbox_watcher.sh {agent} >> logs/inbox_watcher_{agent}.log 2>&1 &`.

**AC-WATCH-4: Agent Enumeration and Skip Logic**
- Call `get_all_agents()` from `scripts/lib/agent_config.sh`.
- Skip `karo` (already launched in AC-WATCH-3).
- For each remaining agent, resolve pane via `pane_lookup()`.
- If pane resolution returns empty, silently skip (no error).

**AC-WATCH-5: Post-Launch Verification**
- For each launched watcher, run `pgrep -f "inbox_watcher\.sh.*{agent}"`.
- Collect all agents where pgrep finds no matching process.
- If any failed: exit 1 with a list of failed agents.
- If all succeeded: exit 0.

**AC-WATCH-6: inotifywait Count Verification**
After a 2-second delay post-launch:
- Count inotifywait processes via `pgrep -c inotifywait`.
- Compare to number of successfully launched watchers.
- If mismatch: emit WARNING to stderr (non-fatal).

**AC-WATCH-7: Pane Variable Sync**
Execute `scripts/sync_pane_vars.sh` after all watchers are launched and verified.

### yaml_helpers (Batch Refactor)

**AC-YAML-1: yaml_field_set_batch API and Atomicity**
- Signature: `yaml_field_set_batch <file> <block_id> <field1>=<value1> [<field2>=<value2> ...]`.
- Acquires flock exactly once per invocation.
- Executes exactly one awk pass to update/insert all specified fields.
- Runs `verify_after_write` exactly once after the awk pass.
- Atomic replacement via `mv` from temp file.
- Returns exit 0 on success, exit 1 on flock timeout or awk failure.

**AC-YAML-2: field_get_multi API and Output Format**
- Signature: `field_get_multi <file> <field1> [<field2> ...]`.
- Executes exactly one awk pass across the file.
- Output: one line per field in `field=value` format, eval-compatible in bash.
- Missing fields output as `field=` (empty value, no error).
- Returns exit 0 on success, exit 1 on file-not-found.

**AC-YAML-3: resolve_cmd_to_task Batch Migration**
`resolve_cmd_to_task()` in `deploy_task.sh` must call `yaml_field_set_batch` exactly once instead of 7 individual `yaml_field_set` calls. The 7 fields (`parent_cmd`, `task_id`, `task_type`, `project`, `status`, `purpose`, `_ac_task_id`) must all be written in a single flock+awk pass.

**AC-YAML-4: inject_ac_version Batch Migration**
`inject_ac_version()` in `deploy_task.sh` must:
- Call `field_get_multi` exactly once to read all required fields (`ac_version`, `task_id`, `_ac_task_id`, `worker_id`, `_ac_worker_id`).
- Call `yaml_field_set_batch` exactly once to write all output fields (`ac_version`, `_ac_task_id`, `_ac_worker_id`).

**AC-YAML-5: Full Regression Gate**
All existing tests in the `ac_handling` test suite (48+ tests) must pass with zero SKIP and zero FAIL after the refactor. Test execution: `bats tests/ac_handling/`.

**AC-YAML-6: Backward Compatibility**
- `yaml_field_set <file> <block_id> <field> <value>` (single-field signature) continues to work identically.
- `field_get <file> <field>` (single-field signature) continues to work identically.
- No existing caller outside `resolve_cmd_to_task` and `inject_ac_version` requires modification.

**AC-YAML-7: Performance Targets**
- `resolve_cmd_to_task`: wall-clock ≤ 150ms (baseline 627ms, target -76%).
- `inject_ac_version`: wall-clock ≤ 120ms (baseline 541ms, target -78%).
- Measured via `time` wrapper in test harness with a representative task YAML (10+ fields, 50+ lines).

### Cross-Cutting Safety

**AC-SAFETY-1: cmd_save flock Usage**
All reads and writes to `queue/shogun_to_karo.yaml` within `cmd_save.sh` must use `flock -w 10` on a dedicated lock file.

**AC-SAFETY-2: deploy_task YAML Helper Usage**
`deploy_task.sh` must not use `echo >>`, `cat <<EOF >>`, `printf >>`, `yaml.dump`, or `yaml.safe_dump` to mutate any file under `queue/` or `queue/tasks/`. All mutations must go through `yaml_field_set`, `yaml_field_set_batch`, or equivalent shell YAML helpers.

**AC-SAFETY-3: inbox_write Atomic Writes**
All writes to `queue/inbox/{agent}.yaml` must acquire a lock file via `flock`. On WSL2 `/mnt/*` paths, the lock file must be on the same filesystem as the inbox file (not `/tmp/`).

**AC-SAFETY-4: ninja_monitor Communication Path**
`ninja_monitor.sh` must send all agent-facing messages through `scripts/inbox_write.sh`. No direct `tmux send-keys` with message content. Exception: `send-keys ""` (empty enter) for keep-alive is permitted.

**AC-SAFETY-5: dashboard Atomic Write**
`dashboard_auto_section.sh` must write to a temp file first, then `mv` to `dashboard.md`. No in-place `sed -i` or direct write.

## 3. Failure Criteria

A test run is considered FAILED if any of the following conditions is observed.

### Lock and Atomicity Failures

| ID | Failure Condition | Severity |
|----|-------------------|----------|
| FC-LOCK-1 | `cmd_save.sh` writes to `shogun_to_karo.yaml` without holding flock | BLOCK |
| FC-LOCK-2 | `inbox_write.sh` writes to any inbox file without holding flock | BLOCK |
| FC-LOCK-3 | `deploy_task.sh` mutates task/queue YAML via raw shell redirection (echo/cat/printf) instead of yaml helpers | BLOCK |
| FC-LOCK-4 | `yaml_field_set_batch` acquires flock more than once per invocation | BLOCK |
| FC-LOCK-5 | `dashboard_auto_section.sh` writes `dashboard.md` without temp-file+mv pattern | BLOCK |
| FC-LOCK-6 | `restart_watchers.sh` proceeds without acquiring singleton lock | BLOCK |

### Routing and Communication Failures

| ID | Failure Condition | Severity |
|----|-------------------|----------|
| FC-ROUTE-1 | `inbox_write.sh` delivers a message from any ninja to shogun | BLOCK |
| FC-COMM-1 | `ninja_monitor.sh` sends message content via `tmux send-keys` instead of `inbox_write.sh` | BLOCK |
| FC-COMM-2 | `deploy_task.sh` sends task content via `tmux send-keys` without prior successful inbox write | BLOCK |

### Compatibility Failures

| ID | Failure Condition | Severity |
|----|-------------------|----------|
| FC-COMPAT-1 | Existing single-argument `yaml_field_set <file> <block> <field> <value>` call fails after batch refactor | BLOCK |
| FC-COMPAT-2 | Existing single-argument `field_get <file> <field>` call fails after batch refactor | BLOCK |
| FC-COMPAT-3 | Any of the 48+ `ac_handling` tests returns SKIP or FAIL after refactor | BLOCK |

### Gate and Quality Failures

| ID | Failure Condition | Severity |
|----|-------------------|----------|
| FC-GATE-1 | `cmd_save.sh` allows delegation of a cmd with missing q1, q2, or q3 fields | BLOCK |
| FC-GATE-2 | `cmd_save.sh` allows delegation while gate state is `blocked` or `pending` | BLOCK |
| FC-GATE-3 | `cmd_save.sh` does not record outcome (BLOCK/WARN/PASS) to `gate_metrics.log` | BLOCK |
| FC-GATE-4 | `cmd_save.sh` allows cmd with prior BLOCK history but no `diagnosis` field | BLOCK |
| FC-GATE-5 | `cmd_save.sh` allows cmd with prior BLOCK history but no `environment_change` field | BLOCK |

### State Management Failures

| ID | Failure Condition | Severity |
|----|-------------------|----------|
| FC-STATE-1 | `deploy_task.sh` overwrites a completed report (`status: completed`) | BLOCK |
| FC-STATE-2 | `deploy_task.sh` accepts `None`, empty string, or `cmd_*` as ninja target | BLOCK |
| FC-STATE-3 | `ninja_monitor.sh` clears a pane with `status: in_progress` task | BLOCK |
| FC-STATE-4 | `inbox_write.sh` writes duplicate `task_assigned` for same parent cmd to same ninja | WARN |

### Dashboard Failures

| ID | Failure Condition | Severity |
|----|-------------------|----------|
| FC-DASH-1 | Content outside `<!-- DASHBOARD_AUTO_START/END -->` markers is modified | BLOCK |
| FC-DASH-2 | `--dry-run` mode modifies `dashboard.md` | BLOCK |
| FC-DASH-3 | Missing data source causes script abort instead of `—` placeholder | BLOCK |
| FC-DASH-4 | Script modifies dashboard when markers are absent | BLOCK |

### Watcher Failures

| ID | Failure Condition | Severity |
|----|-------------------|----------|
| FC-WATCH-1 | Watchers launched before all old `inbox_watcher.sh` processes are terminated | BLOCK |
| FC-WATCH-2 | Script exits 0 when one or more watchers failed `pgrep` verification | BLOCK |
| FC-WATCH-3 | `sync_pane_vars.sh` not executed after watcher launch | WARN |

### Performance Failures

| ID | Failure Condition | Severity |
|----|-------------------|----------|
| FC-PERF-1 | `resolve_cmd_to_task` wall-clock > 150ms after refactor (median of 10 runs) | WARN |
| FC-PERF-2 | `inject_ac_version` wall-clock > 120ms after refactor (median of 10 runs) | WARN |
| FC-PERF-3 | Dashboard generation wall-clock increases > 20% after cache implementation | WARN |

## 4. E2E Test Generation Meta-Prompt

### Purpose

This section provides machine-readable instructions for `codd propagate` to auto-generate E2E tests covering all acceptance criteria and failure criteria defined above.

### MECE Domain Decomposition

| Domain | Description | Output: API Integration | Output: Browser |
|--------|-------------|------------------------|-----------------|
| cmd-gate | cmd_save.sh quality gate, normalization, delegation guards | `tests/e2e/cmd-gate.spec.ts` | N/A (CLI-only) |
| deploy-task | deploy_task.sh modes, validation, metadata resolution, report templates | `tests/e2e/deploy-task.spec.ts` | N/A (CLI-only) |
| inbox-routing | inbox_write.sh argument handling, routing rules, serialization, dedup | `tests/e2e/inbox-routing.spec.ts` | N/A (CLI-only) |
| ninja-monitor | ninja_monitor.sh singleton, state detection, anomaly detection, snapshot | `tests/e2e/ninja-monitor.spec.ts` | N/A (CLI-only) |
| dashboard | dashboard_auto_section.sh generation, caching, dry-run, preservation | `tests/e2e/dashboard.spec.ts` | N/A (CLI-only) |
| watchers | restart_watchers.sh lifecycle, lock, termination, verification | `tests/e2e/watchers.spec.ts` | N/A (CLI-only) |
| yaml-helpers | yaml_field_set_batch, field_get_multi, backward compat, performance | `tests/e2e/yaml-helpers.spec.ts` | N/A (CLI-only) |
| safety-cross-cutting | flock enforcement, routing prohibition, atomic write patterns | `tests/e2e/safety-cross-cutting.spec.ts` | N/A (CLI-only) |

> **Note**: All modules are CLI shell scripts, not web applications. There are no browser tests. All tests use shell execution (`child_process.execSync` or bats) as the test driver, not HTTP clients or browser automation.

### Test Level: Shell Integration Tests

Since all target modules are bash scripts, E2E tests use **shell integration mode**:
- Test framework: `bats-core` (Bash Automated Testing System) for native shell testing, or Node.js `child_process` wrappers in `.spec.ts` files for structured reporting.
- Each test invokes the target script with controlled inputs and asserts exit codes, file mutations, and log output.
- Shared fixtures provide mock `queue/`, `logs/`, `config/`, and tmux stubs.

### Runtime Environment

```
# Prerequisites
- bats-core >= 1.10.0 installed
- tmux >= 3.3 running with session "shogun" (or mock via TMUX_STUB=1)
- flock available (util-linux)
- Project root at $PROJECT_DIR with queue/, logs/, config/ directories
- WSL2 environment with /mnt/c accessible

# Setup sequence
1. export PROJECT_DIR=$(pwd)
2. export TEST_MODE=1  # scripts check this to use test fixtures
3. mkdir -p /tmp/mas-test-{inbox,tasks,reports,logs}
4. cp tests/e2e/fixtures/* /tmp/mas-test-*/  # seed test data
5. bats tests/e2e/*.spec.ts  # or: npx jest tests/e2e/

# Teardown
rm -rf /tmp/mas-test-*
```

### Scenario Derivation per Domain

#### Domain: cmd-gate

| Scenario ID | Type | Source AC/FC | Description |
|-------------|------|-------------|-------------|
| CMD-E2E-01 | positive | AC-CMD-1 | Numeric id `123` normalizes to `cmd_123` and loads block |
| CMD-E2E-02 | positive | AC-CMD-1 | Prefixed id `cmd_123` loads matching block |
| CMD-E2E-03 | negative | AC-CMD-2 | Malformed YAML block returns BLOCK exit |
| CMD-E2E-04 | negative | AC-CMD-2 | Non-existent cmd id returns BLOCK exit |
| CMD-E2E-05 | negative | AC-CMD-3 | Delegated cmd rejects mutation (immutability) |
| CMD-E2E-06 | negative | AC-CMD-3 | Pending previous cmd blocks new delegation |
| CMD-E2E-07 | negative | AC-CMD-4 | Archive duplicate returns BLOCK |
| CMD-E2E-08 | negative | AC-CMD-4 | Concurrent draft conflict emits WARN |
| CMD-E2E-09 | negative | FC-GATE-1 | Missing q1 field returns BLOCK |
| CMD-E2E-10 | negative | FC-GATE-1 | Missing q2 field returns BLOCK |
| CMD-E2E-11 | negative | FC-GATE-1 | Missing q3 field returns BLOCK |
| CMD-E2E-12 | positive | AC-CMD-5 | Shallow q4 depth emits WARN but passes |
| CMD-E2E-13 | negative | AC-CMD-6, FC-GATE-4 | Prior BLOCK + missing diagnosis → BLOCK |
| CMD-E2E-14 | negative | AC-CMD-6, FC-GATE-5 | Prior BLOCK + missing environment_change → BLOCK |
| CMD-E2E-15 | positive | AC-CMD-6 | Prior BLOCK + valid diagnosis + verifiable environment_change → PASS |
| CMD-E2E-16 | positive | AC-CMD-7 | PASS outcome recorded in gate_metrics.log |
| CMD-E2E-17 | positive | AC-CMD-7 | BLOCK outcome recorded in gate_metrics.log |
| CMD-E2E-18 | positive | AC-CMD-8 | Lock contention emits WARN |
| CMD-E2E-19 | positive | AC-CMD-8 | Uncommitted changes emit WARN |
| CMD-E2E-20 | positive | AC-CMD-8 | Duplicate GP number emits WARN |
| CMD-E2E-21 | positive | AC-CMD-8 | Scout/recon overlap with gunshi analysis emits WARN |
| CMD-E2E-22 | positive | AC-CMD-9 | Bulletin action ids updated after save |
| CMD-E2E-23 | negative | FC-LOCK-1 | Verify flock is held during shogun_to_karo.yaml write |

#### Domain: deploy-task

| Scenario ID | Type | Source AC/FC | Description |
|-------------|------|-------------|-------------|
| DEP-E2E-01 | positive | AC-DEPLOY-1 | Normal mode creates valid task YAML |
| DEP-E2E-02 | positive | AC-DEPLOY-1 | `--direct` mode creates task YAML with custom message |
| DEP-E2E-03 | positive | AC-DEPLOY-1 | `--yaml` mode uses provided YAML file |
| DEP-E2E-04 | positive | AC-DEPLOY-1 | `--cmd` mode resolves cmd then deploys |
| DEP-E2E-05 | positive | AC-DEPLOY-2 | Inbox message contains stale-context invalidation directive |
| DEP-E2E-06 | negative | AC-DEPLOY-3, FC-STATE-2 | Empty target → non-zero exit |
| DEP-E2E-07 | negative | AC-DEPLOY-3, FC-STATE-2 | `None` target → non-zero exit |
| DEP-E2E-08 | negative | AC-DEPLOY-3, FC-STATE-2 | `cmd_123` as target → non-zero exit |
| DEP-E2E-09 | negative | AC-DEPLOY-3 | Unknown ninja name → non-zero exit |
| DEP-E2E-10 | positive | AC-DEPLOY-5 | Stale task fields reset before new assignment |
| DEP-E2E-11 | positive | AC-DEPLOY-5 | Ghost `None.yaml` deleted if present |
| DEP-E2E-12 | positive | AC-DEPLOY-6 | All 7 metadata fields present in task YAML after cmd resolution |
| DEP-E2E-13 | positive | AC-DEPLOY-6 | AC, ac_version, related_lessons, semantic_concepts injected |
| DEP-E2E-14 | positive | AC-DEPLOY-7 | Report template created at expected path |
| DEP-E2E-15 | negative | AC-DEPLOY-7, FC-STATE-1 | Completed report not overwritten |
| DEP-E2E-16 | positive | AC-DEPLOY-8 | inbox_write.sh invoked with correct arguments |
| DEP-E2E-17 | negative | AC-DEPLOY-9 | Duplicate deployment for completed cmd → BLOCK |
| DEP-E2E-18 | negative | FC-LOCK-3 | Verify no raw shell redirection to queue files |

#### Domain: inbox-routing

| Scenario ID | Type | Source AC/FC | Description |
|-------------|------|-------------|-------------|
| INB-E2E-01 | positive | AC-INBOX-1 | Valid 2-argument invocation (target + content) |
| INB-E2E-02 | positive | AC-INBOX-1 | Valid 5-argument invocation (all optional fields) |
| INB-E2E-03 | negative | AC-INBOX-1 | Missing target → exit 1 |
| INB-E2E-04 | negative | AC-INBOX-1 | Malformed target (contains `/`) → exit 1 |
| INB-E2E-05 | negative | AC-INBOX-2, FC-ROUTE-1 | Ninja sender (hayate) → shogun target → exit 1 |
| INB-E2E-06 | negative | AC-INBOX-2, FC-ROUTE-1 | Ninja sender (kagemaru) → shogun target → exit 1 |
| INB-E2E-07 | positive | AC-INBOX-2 | Ninja sender → karo target → exit 0 |
| INB-E2E-08 | positive | AC-INBOX-3 | Message serialized with all required fields (id, timestamp, type, from, content, read=false) |
| INB-E2E-09 | positive | AC-INBOX-3 | Multi-line content preserved in YAML block scalar |
| INB-E2E-10 | negative | AC-INBOX-4, FC-STATE-4 | Duplicate task_assigned for same parent_cmd → dedup (no second write) |
| INB-E2E-11 | positive | AC-INBOX-5 | task_assigned with empty related_lessons appends warning note |
| INB-E2E-12 | positive | AC-INBOX-6 | report_received triggers format validation |
| INB-E2E-13 | positive | AC-INBOX-7 | Nudge sent only after successful file write |
| INB-E2E-14 | positive | AC-INBOX-8 | Message readable immediately after exit 0 |
| INB-E2E-15 | negative | FC-LOCK-2 | Concurrent writes do not lose messages (flock stress test: 10 parallel writes) |

#### Domain: ninja-monitor

| Scenario ID | Type | Source AC/FC | Description |
|-------------|------|-------------|-------------|
| MON-E2E-01 | positive | AC-MON-1 | Second instance exits immediately (singleton) |
| MON-E2E-02 | positive | AC-MON-2 | Idle detection requires all 4 signals |
| MON-E2E-03 | positive | AC-MON-2 | Single busy signal prevents idle classification |
| MON-E2E-04 | positive | AC-MON-3 | Idle + no pending report → clear succeeds |
| MON-E2E-05 | negative | AC-MON-3, FC-STATE-3 | Active task (in_progress) → clear blocked |
| MON-E2E-06 | positive | AC-MON-4 | Stale deployment detected and reported to karo |
| MON-E2E-07 | positive | AC-MON-4 | Undeployed cmd detected and reported |
| MON-E2E-08 | positive | AC-MON-4 | CLI death detected and reported |
| MON-E2E-09 | positive | AC-MON-5 | karo_snapshot.txt contains expected format and all agents |
| MON-E2E-10 | positive | AC-MON-6 | Dead inbox_watcher detected and reported |
| MON-E2E-11 | negative | FC-COMM-1 | Verify no tmux send-keys with message content in monitor code |

#### Domain: dashboard

| Scenario ID | Type | Source AC/FC | Description |
|-------------|------|-------------|-------------|
| DSH-E2E-01 | positive | AC-DASH-3 | All 10 sections present between markers |
| DSH-E2E-02 | positive | AC-DASH-4, FC-DASH-2 | `--dry-run` outputs to stdout, dashboard unchanged |
| DSH-E2E-03 | positive | AC-DASH-5, FC-DASH-1 | Content outside markers preserved (byte-compare) |
| DSH-E2E-04 | positive | AC-DASH-6 | ntfy sent only on CLEAR count increase |
| DSH-E2E-05 | positive | AC-DASH-6 | ntfy not sent when CLEAR count unchanged |
| DSH-E2E-06 | positive | AC-DASH-7 | Strikethrough entries removed from 将軍宛報告 |
| DSH-E2E-07 | positive | AC-DASH-10, FC-DASH-3 | Missing data source → `—` placeholder, no abort |
| DSH-E2E-08 | negative | AC-DASH-12, FC-DASH-4 | Missing markers → exit 1, file unchanged |
| DSH-E2E-09 | positive | AC-DASH-8 | Cached CI result reused within 60s |
| DSH-E2E-10 | positive | AC-DASH-11 | Exit 0 on successful generation |
| DSH-E2E-11 | negative | FC-LOCK-5 | Verify temp-file+mv write pattern (no sed -i) |
| DSH-E2E-12 | positive | AC-DASH-9 | Parallel subprocess launch reduces wall-clock (timing assertion) |

#### Domain: watchers

| Scenario ID | Type | Source AC/FC | Description |
|-------------|------|-------------|-------------|
| WCH-E2E-01 | positive | AC-WATCH-1 | Singleton lock acquired, second instance exits non-zero |
| WCH-E2E-02 | positive | AC-WATCH-2 | SIGTERM sent, survivors get SIGKILL after 1s |
| WCH-E2E-03 | positive | AC-WATCH-3 | Shogun watcher launched with correct log path |
| WCH-E2E-04 | positive | AC-WATCH-3 | Karo watcher launched with correct log path |
| WCH-E2E-05 | positive | AC-WATCH-4 | Agent with empty pane silently skipped |
| WCH-E2E-06 | positive | AC-WATCH-5, FC-WATCH-2 | All watchers pass pgrep → exit 0 |
| WCH-E2E-07 | negative | AC-WATCH-5, FC-WATCH-2 | One watcher fails pgrep → exit 1 with failed agent list |
| WCH-E2E-08 | positive | AC-WATCH-6 | inotifywait count mismatch emits WARNING |
| WCH-E2E-09 | positive | AC-WATCH-7, FC-WATCH-3 | sync_pane_vars.sh executed after launch |
| WCH-E2E-10 | negative | FC-WATCH-1 | Verify old watchers terminated before new ones launched |

#### Domain: yaml-helpers

| Scenario ID | Type | Source AC/FC | Description |
|-------------|------|-------------|-------------|
| YML-E2E-01 | positive | AC-YAML-1 | yaml_field_set_batch writes 7 fields in single pass |
| YML-E2E-02 | positive | AC-YAML-1 | Single flock acquisition verified (strace or lock log) |
| YML-E2E-03 | positive | AC-YAML-1 | verify_after_write confirms all 7 fields readable |
| YML-E2E-04 | positive | AC-YAML-2 | field_get_multi extracts 5 fields in single pass |
| YML-E2E-05 | positive | AC-YAML-2 | Output is eval-compatible bash format |
| YML-E2E-06 | positive | AC-YAML-2 | Missing field returns empty value (no error) |
| YML-E2E-07 | positive | AC-YAML-3 | resolve_cmd_to_task calls yaml_field_set_batch once (instrumented count) |
| YML-E2E-08 | positive | AC-YAML-4 | inject_ac_version calls field_get_multi once + yaml_field_set_batch once |
| YML-E2E-09 | positive | AC-YAML-5, FC-COMPAT-3 | All 48+ ac_handling tests PASS with zero SKIP |
| YML-E2E-10 | positive | AC-YAML-6, FC-COMPAT-1 | Single-field yaml_field_set still works after batch addition |
| YML-E2E-11 | positive | AC-YAML-6, FC-COMPAT-2 | Single-field field_get still works after multi addition |
| YML-E2E-12 | positive | AC-YAML-7, FC-PERF-1 | resolve_cmd_to_task ≤ 150ms (median of 10 runs) |
| YML-E2E-13 | positive | AC-YAML-7, FC-PERF-2 | inject_ac_version ≤ 120ms (median of 10 runs) |
| YML-E2E-14 | positive | AC-YAML-1 | Concurrent yaml_field_set_batch calls on same file do not corrupt (flock stress: 5 parallel) |

#### Domain: safety-cross-cutting

| Scenario ID | Type | Source AC/FC | Description |
|-------------|------|-------------|-------------|
| SAF-E2E-01 | negative | AC-SAFETY-2, FC-LOCK-3 | grep deploy_task.sh for `echo >>.*queue/\|cat.*>>.*queue/\|printf.*>>.*queue/` → zero matches |
| SAF-E2E-02 | negative | AC-SAFETY-3 | Concurrent inbox_write.sh (10 parallel to same agent) → all messages present, none lost |
| SAF-E2E-03 | negative | FC-ROUTE-1 | All 6 ninja names tested as sender with shogun target → all rejected |
| SAF-E2E-04 | positive | AC-SAFETY-4 | grep ninja_monitor.sh for `send-keys.*"[^"]` patterns → only empty-enter or inboxN patterns |
| SAF-E2E-05 | positive | AC-SAFETY-1 | cmd_save.sh uses flock for every shogun_to_karo.yaml access (grep verification) |

### Architecture Adaptation Rules

1. **Endpoint scanning**: Since all modules are shell scripts (not HTTP endpoints), test generation must scan each script for exported/callable functions via `grep -E '^[a-z_]+\(\)' scripts/*.sh` and generate tests for each public function.
2. **Unimplemented functions**: If a function referenced in requirements is not found in the implementation, mark the test with `# @fixme: function not found` and assert failure with a descriptive message.
3. **tmux dependency**: Tests requiring tmux must check `tmux has-session -t shogun 2>/dev/null` and skip with `skip "tmux session not available"` only in CI environments where tmux is genuinely unavailable. In local test environments, tmux must be running.

### Quality Gate

| Criterion | Threshold |
|-----------|-----------|
| All tests PASS | 100% (zero FAIL) |
| SKIP count | 0 (SKIP = FAIL per project rules) |
| AC coverage | Every AC-* has at least one test scenario |
| FC coverage | Every FC-* has at least one test scenario |
| VB coverage | Every VB-* mapped to at least one AC-* that has a test |
| flock stress tests | 10 concurrent writes → zero message loss |
| Performance assertions | Median of 10 runs within threshold |

### Shared Helpers

All shared test utilities reside in `tests/e2e/helpers/`:

| File | Purpose |
|------|---------|
| `helpers/setup.sh` | Create temp directories, seed fixture data, set `TEST_MODE=1`, mock tmux pane variables |
| `helpers/teardown.sh` | Remove temp directories, kill background processes spawned by tests |
| `helpers/tmux_stub.sh` | Stub `tmux display-message`, `tmux list-panes`, `tmux send-keys` for headless CI |
| `helpers/fixtures/` | Pre-built YAML files: valid cmd blocks, task templates, inbox messages, karo_snapshot, dashboard with markers |
| `helpers/assert_yaml.sh` | Assert field values in YAML files via `field_get` wrapper |
| `helpers/assert_flock.sh` | Wrap script execution with `strace -e trace=flock` and assert flock syscall count |
| `helpers/assert_no_raw_write.sh` | grep target script for prohibited write patterns (echo/cat/printf to queue/) |
| `helpers/timing.sh` | Run a function N times, compute median wall-clock, assert threshold |
| `helpers/concurrent.sh` | Launch N parallel invocations of a script and verify all complete without data loss |

### Generation Markers

All generated test files must include these headers:

```bash
# @generated-from: codd/tests/acceptance-criteria.md
# @generated-by: codd propagate
```

Tests marked with `# @manual` in existing test files must be preserved verbatim during regeneration. The generator must:
1. Scan target file for `# @manual` blocks before overwriting.
2. Splice manual blocks back into the regenerated output at their original position.
3. If a manual block conflicts with a generated scenario id, emit a warning and keep the manual version.

### Traceability Summary

| Gap Check | Result |
|-----------|--------|
| VB-* without AC-* mapping | 0 gaps |
| AC-* without test scenario | 0 gaps |
| FC-* without test scenario | 0 gaps |
| Browser tests required | No (all CLI scripts) |
| API integration tests required | No (all CLI scripts) |
| Shell integration tests required | Yes — primary test level |
