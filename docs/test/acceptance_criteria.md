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
semantic-links: [[テスト品質統合フレームワーク]]

# Acceptance Criteria

## 1. Overview

This document defines acceptance criteria, failure criteria, and E2E test generation instructions for the multi-agent-shogun infrastructure scripts: `cmd_save.sh`, `deploy_task.sh`, `inbox_write.sh`, `ninja_monitor.sh`, `dashboard_auto_section.sh`, `restart_watchers.sh`, and the YAML helper batch operations (`yaml_field_set_batch`, `field_get_multi`). These scripts form the agent communication backbone, task deployment pipeline, quality gating system, and formation monitoring infrastructure.

**Non-negotiable convention compliance:**

| Convention | How this document complies |
|---|---|
| flock-based atomic YAML writes (SR-3 inbox_write, SR-1 deploy_task, SR-3 cmd_save) | AC-INB-04, AC-CMD-07, AC-DEP-09, AC-YML-01 require flock verification in every write path |
| Ninja-to-shogun direct messaging prohibition (SR-2 inbox_write) | AC-INB-02 explicitly tests rejection; FC-INB-01 treats bypass as release blocker |
| API backward compatibility for yaml_field_set/field_get (refactor constraints) | AC-YML-03, AC-YML-06 mandate signature and output compatibility; FC-YML-01 blocks on any regression |
| Zero test regressions (refactor constraints) | AC-REF-05 requires full existing test suite PASS; FC-REF-01 blocks on any FAIL |
| inbox-path-only communication (SR-3 deploy_task, SR-1 inbox_write) | AC-DEP-07, AC-INB-01 verify inbox_write.sh is the sole delivery channel |

### Verifiable Behavior Inventory

The following table enumerates every verifiable behavior from dependency documents and maps each to test scenario(s). Behaviors without coverage are flagged.

| ID | Source | Verifiable Behavior | Test Scenario(s) |
|----|--------|---------------------|-------------------|
| VB-CMD-01 | cmd_save FR-1 | Normalize numeric and `cmd_*` ids then load matching block | AC-CMD-01 |
| VB-CMD-02 | cmd_save FR-2 | Validate YAML syntax | AC-CMD-02 |
| VB-CMD-03 | cmd_save FR-2 | Reject nonexistent command | AC-CMD-02 |
| VB-CMD-04 | cmd_save FR-2 | Reject mutation of delegated-state command | AC-CMD-03 |
| VB-CMD-05 | cmd_save FR-2 | Reject when previous pending command blocks | AC-CMD-03 |
| VB-CMD-06 | cmd_save FR-2 | Detect archive duplicates | AC-CMD-04 |
| VB-CMD-07 | cmd_save FR-2 | Detect concurrent draft conflicts | AC-CMD-04 |
| VB-CMD-08 | cmd_save FR-3 | Enforce quality_gate fields | AC-CMD-05 |
| VB-CMD-09 | cmd_save FR-3 | Require diagnosis/environment-change after prior BLOCK/WARN | AC-CMD-06 |
| VB-CMD-10 | cmd_save FR-4 | Record BLOCK outcome to quality log and session-state | AC-CMD-07 |
| VB-CMD-11 | cmd_save FR-4 | Record WARN outcome to quality log and session-state | AC-CMD-07 |
| VB-CMD-12 | cmd_save FR-4 | Record PASS outcome to quality log and session-state | AC-CMD-07 |
| VB-CMD-13 | cmd_save FR-5 | Warn on lock contention | AC-CMD-08 |
| VB-CMD-14 | cmd_save FR-5 | Warn on uncommitted implementation changes | AC-CMD-08 |
| VB-CMD-15 | cmd_save FR-5 | Warn on duplicate GP numbers | AC-CMD-08 |
| VB-CMD-16 | cmd_save FR-5 | Warn on scout/recon overlap with gunshi analysis | AC-CMD-08 |
| VB-CMD-17 | cmd_save FR-6 | Update bulletin action tracking on bulletin id reference | AC-CMD-09 |
| VB-CMD-18 | cmd_save SR-1 | Block delegation while gate state is pending/blocked | AC-CMD-03 |
| VB-CMD-19 | cmd_save SR-2 | Treat delegated commands as immutable | AC-CMD-03 |
| VB-CMD-20 | cmd_save SR-3 | Use flock around shared queue files | AC-CMD-07 |
| VB-DEP-01 | deploy_task FR-1 | Parse normal deployment mode | AC-DEP-01 |
| VB-DEP-02 | deploy_task FR-1 | Parse `--direct` deployment mode | AC-DEP-01 |
| VB-DEP-03 | deploy_task FR-1 | Parse `--yaml` deployment mode | AC-DEP-01 |
| VB-DEP-04 | deploy_task FR-1 | Parse `--cmd` deployment mode | AC-DEP-01 |
| VB-DEP-05 | deploy_task FR-1 | Preserve default message that invalidates stale context | AC-DEP-01 |
| VB-DEP-06 | deploy_task FR-2 | Reject empty target | AC-DEP-02 |
| VB-DEP-07 | deploy_task FR-2 | Reject `None` target | AC-DEP-02 |
| VB-DEP-08 | deploy_task FR-2 | Reject `cmd_*` id as target | AC-DEP-02 |
| VB-DEP-09 | deploy_task FR-3 | Resolve target pane via tmux/CLI helpers | AC-DEP-03 |
| VB-DEP-10 | deploy_task FR-3 | Determine idle/busy state | AC-DEP-03 |
| VB-DEP-11 | deploy_task FR-4 | Reset stale task fields | AC-DEP-04 |
| VB-DEP-12 | deploy_task FR-4 | Reset stale notification flags | AC-DEP-04 |
| VB-DEP-13 | deploy_task FR-4 | Remove ghost `None.yaml` artifacts | AC-DEP-04 |
| VB-DEP-14 | deploy_task FR-5 | Resolve parent cmd into task metadata | AC-DEP-05 |
| VB-DEP-15 | deploy_task FR-5 | Inject acceptance criteria and AC version | AC-DEP-05 |
| VB-DEP-16 | deploy_task FR-5 | Inject related lessons | AC-DEP-05 |
| VB-DEP-17 | deploy_task FR-5 | Inject semantic concepts | AC-DEP-05 |
| VB-DEP-18 | deploy_task FR-5 | Inject engineering preferences and execution controls | AC-DEP-05 |
| VB-DEP-19 | deploy_task FR-6 | Generate report template under `queue/reports/` | AC-DEP-06 |
| VB-DEP-20 | deploy_task FR-6 | Do not overwrite completed reports | AC-DEP-06 |
| VB-DEP-21 | deploy_task FR-7 | Deliver task notification via inbox_write.sh | AC-DEP-07 |
| VB-DEP-22 | deploy_task FR-7 | Treat persisted inbox writes as successful despite flaky post-delivery verification | AC-DEP-07 |
| VB-DEP-23 | deploy_task SR-1 | Use shared YAML helpers for queue/task mutation | AC-DEP-09 |
| VB-DEP-24 | deploy_task SR-2 | Block duplicate active deployment when completed peer report exists | AC-DEP-08 |
| VB-DEP-25 | deploy_task SR-3 | Keep communication on inbox path; tmux nudge limited to re-nudge fallback | AC-DEP-07 |
| VB-INB-01 | inbox_write FR-1 | Accept target, content, optional type/sender/action | AC-INB-01 |
| VB-INB-02 | inbox_write FR-1 | Reject missing target | AC-INB-01 |
| VB-INB-03 | inbox_write FR-1 | Reject malformed target | AC-INB-01 |
| VB-INB-04 | inbox_write FR-2 | Validate target agent names | AC-INB-02 |
| VB-INB-05 | inbox_write FR-2 | Enforce ninja-to-shogun prohibition | AC-INB-02 |
| VB-INB-06 | inbox_write FR-3 | Serialize message with timestamp, id, type, sender, content, read state, action | AC-INB-03 |
| VB-INB-07 | inbox_write FR-4 | Use lock files appropriate for WSL2 `/mnt/*` paths | AC-INB-04 |
| VB-INB-08 | inbox_write FR-5 | Block duplicate active `task_assigned` for same parent cmd | AC-INB-05 |
| VB-INB-09 | inbox_write FR-6 | Lesson-injection safety net when deploy helpers did not inject | AC-INB-06 |
| VB-INB-10 | inbox_write FR-7 | Run report format checks on report notifications | AC-INB-07 |
| VB-INB-11 | inbox_write FR-7 | Trigger downstream review/completion on report notifications | AC-INB-07 |
| VB-INB-12 | inbox_write FR-8 | Resolve panes and send CLI-specific nudges after persistence | AC-INB-08 |
| VB-INB-13 | inbox_write SR-1 | Inbox persistence is durable source of truth; nudges secondary | AC-INB-04 |
| VB-INB-14 | inbox_write SR-2 | Never allow ninja→shogun bypass | AC-INB-02 |
| VB-INB-15 | inbox_write SR-3 | Preserve flock/atomic write semantics | AC-INB-04 |
| VB-NM-01 | ninja_monitor FR-1 | Run as singleton daemon | AC-NM-01 |
| VB-NM-02 | ninja_monitor FR-1 | Rediscover ninja panes from tmux metadata | AC-NM-01 |
| VB-NM-03 | ninja_monitor FR-2 | Detect idle state via @agent_state | AC-NM-02 |
| VB-NM-04 | ninja_monitor FR-2 | Detect idle via last-active timestamps | AC-NM-02 |
| VB-NM-05 | ninja_monitor FR-2 | Detect idle via CLI-specific prompt/busy patterns | AC-NM-02 |
| VB-NM-06 | ninja_monitor FR-2 | Cross-check subprocess state | AC-NM-02 |
| VB-NM-07 | ninja_monitor FR-3 | Clear agents only after idle confirmation and report-gate checks | AC-NM-03 |
| VB-NM-08 | ninja_monitor FR-3 | Respawn agents after clear | AC-NM-03 |
| VB-NM-09 | ninja_monitor FR-4 | Detect pane loss | AC-NM-04 |
| VB-NM-10 | ninja_monitor FR-4 | Detect stale deployments | AC-NM-04 |
| VB-NM-11 | ninja_monitor FR-4 | Detect undeployed commands | AC-NM-04 |
| VB-NM-12 | ninja_monitor FR-4 | Detect karo pending work | AC-NM-04 |
| VB-NM-13 | ninja_monitor FR-4 | Detect CLI death | AC-NM-04 |
| VB-NM-14 | ninja_monitor FR-4 | Detect inbox unread counts | AC-NM-04 |
| VB-NM-15 | ninja_monitor FR-4 | Detect report/task mismatches | AC-NM-04 |
| VB-NM-16 | ninja_monitor FR-5 | Generate karo_snapshot.txt with cmd, ninja, model, context, report state | AC-NM-05 |
| VB-NM-17 | ninja_monitor FR-6 | Monitor inbox watcher health | AC-NM-06 |
| VB-NM-18 | ninja_monitor FR-6 | Monitor ntfy listener health | AC-NM-06 |
| VB-NM-19 | ninja_monitor FR-6 | Monitor CI status | AC-NM-06 |
| VB-NM-20 | ninja_monitor FR-6 | Monitor training auto-deploy conditions | AC-NM-06 |
| VB-NM-21 | ninja_monitor FR-6 | Monitor lesson health, loop health, workaround trends, script size trends | AC-NM-06 |
| VB-NM-22 | ninja_monitor SR-1 | Prefer hook state over prompt-only idle detection | AC-NM-02 |
| VB-NM-23 | ninja_monitor SR-2 | Never clear pane with active task unless report+idle gates allow | AC-NM-03 |
| VB-NM-24 | ninja_monitor SR-3 | Use inbox_write.sh for agent communication | AC-NM-07 |
| VB-DASH-01 | dashboard FR-1 | Read 10 data sources | AC-DASH-01 |
| VB-DASH-02 | dashboard FR-2 | Invoke 5 external subprocesses | AC-DASH-02 |
| VB-DASH-03 | dashboard FR-3 | Generate 10 output sections | AC-DASH-03 |
| VB-DASH-04 | dashboard FR-4 | `--dry-run` outputs to stdout without modifying dashboard.md | AC-DASH-04 |
| VB-DASH-05 | dashboard FR-5 | Preserve content outside auto-section markers | AC-DASH-05 |
| VB-DASH-06 | dashboard FR-6 | Deduplicated ntfy notification on CLEAR count increase | AC-DASH-06 |
| VB-DASH-07 | dashboard FR-7 | Remove strikethrough entries from 将軍宛報告 section | AC-DASH-07 |
| VB-DASH-08 | dashboard PR-1 | Cache slow subprocess results with TTL (CI: 60s, freshness: 120s, rev-list: 60s) | AC-DASH-08 |
| VB-DASH-09 | dashboard PR-2 | Cache awk computations keyed by mtime | AC-DASH-08 |
| VB-DASH-10 | dashboard PR-3 | Background-launch freshness and CI checks | AC-DASH-08 |
| VB-DASH-11 | dashboard PR-4 | Project-scoped cache paths via cksum | AC-DASH-08 |
| VB-DASH-12 | dashboard SR-1 | Atomic write via temp file + mv | AC-DASH-09 |
| VB-DASH-13 | dashboard SR-2 | Graceful degradation to `—` placeholders | AC-DASH-10 |
| VB-DASH-14 | dashboard SR-3 | Exit 0 on success, exit 1 on failure | AC-DASH-11 |
| VB-DASH-15 | dashboard SR-4 | No modification when markers absent | AC-DASH-11 |
| VB-RW-01 | restart_watchers FR-1 | Singleton lock via flock -n at /tmp/restart_watchers.lock | AC-RW-01 |
| VB-RW-02 | restart_watchers FR-2 | Two-stage stop (SIGTERM → SIGKILL) | AC-RW-02 |
| VB-RW-03 | restart_watchers FR-3 | Launch shogun watcher via @agent_cli from shogun:main pane | AC-RW-03 |
| VB-RW-04 | restart_watchers FR-4 | Launch karo watcher via shogun:agents.1 pane | AC-RW-03 |
| VB-RW-05 | restart_watchers FR-5 | Enumerate remaining agents, skip karo, resolve panes, skip empty | AC-RW-04 |
| VB-RW-06 | restart_watchers FR-6 | Verify each watcher via pgrep after launch | AC-RW-05 |
| VB-RW-07 | restart_watchers FR-7 | Verify inotifywait process count matches watcher count | AC-RW-05 |
| VB-RW-08 | restart_watchers FR-8 | Execute sync_pane_vars.sh | AC-RW-06 |
| VB-RW-09 | restart_watchers SR-1 | Two-stage termination checks remaining count before escalation | AC-RW-02 |
| VB-RW-10 | restart_watchers SR-2 | Pane resolution failure causes silent skip | AC-RW-04 |
| VB-RW-11 | restart_watchers SR-3 | Watcher logs append to per-agent log files | AC-RW-03 |
| VB-YML-01 | refactor R3 | yaml_field_set_batch writes multiple fields in 1 flock + 1 awk pass | AC-YML-01 |
| VB-YML-02 | refactor R4 | field_get_multi extracts multiple fields in 1 awk pass | AC-YML-04 |
| VB-YML-03 | refactor R3 | yaml_field_set_batch performs verify_after_write once | AC-YML-02 |
| VB-YML-04 | refactor R3 | Existing yaml_field_set API unchanged | AC-YML-03 |
| VB-YML-05 | refactor R4 | Existing field_get API unchanged | AC-YML-06 |
| VB-YML-06 | refactor R1 | resolve_cmd_to_task uses batch (7→1 write) | AC-REF-01 |
| VB-YML-07 | refactor R2 | inject_ac_version uses batch read + batch write | AC-REF-02 |
| VB-YML-08 | refactor constraint | All existing tests PASS after refactor | AC-REF-05 |
| VB-YML-09 | refactor R1 | resolve_cmd_to_task ≤100ms (from 627ms) | AC-REF-03 |
| VB-YML-10 | refactor R2 | inject_ac_version ≤80ms (from 541ms) | AC-REF-04 |

**Coverage gaps: None.** All verifiable behaviors are mapped to at least one acceptance criterion.

## 2. Acceptance Criteria

### 2.1 cmd_save.sh

| ID | Criterion | Verification Method |
|----|-----------|---------------------|
| AC-CMD-01 | Given input `42`, `cmd_42`, or `cmd_042`, the script normalizes to the same block id and loads the correct entry from `queue/shogun_to_karo.yaml`. | Unit: supply 3 id variants for a single cmd block; assert identical loaded content. |
| AC-CMD-02 | Given a malformed YAML block or a nonexistent cmd id, the script exits with BLOCK and logs the reason to `logs/cmd_save_quality.log`. | Unit: inject syntax-broken YAML; inject valid YAML for id `cmd_99999`; assert exit≠0 and log entry present. |
| AC-CMD-03 | Given a cmd already in `delegated` state, or a cmd whose gate state is `pending`/`blocked`, the script exits with BLOCK and does not mutate `shogun_to_karo.yaml`. Delegated commands are treated as immutable. | Unit: set cmd state to delegated→re-save→assert BLOCK. Set gate to pending→save→assert BLOCK. Checksum `shogun_to_karo.yaml` before and after; assert identical. |
| AC-CMD-04 | Given a cmd whose id matches an archived entry, or a concurrent draft conflict (two saves of same id within 5s), the script emits WARN with descriptive reason. | Unit: pre-populate archive; assert WARN. Simulate concurrent save with flock contention; assert WARN. |
| AC-CMD-05 | Given a cmd missing required `quality_gate` fields (q1–q3), the script exits BLOCK. Given missing q4_depth, the script emits WARN. | Unit: omit q1→BLOCK. Omit q4_depth→WARN. Provide all→PASS. |
| AC-CMD-06 | Given a cmd from a session with prior BLOCK/WARN history and no `diagnosis` or `environment_change` fields, the script exits BLOCK. Given both fields present, the script proceeds. | Unit: create session-state with prior BLOCK; submit cmd without diagnosis→BLOCK. Add diagnosis+environment_change→PASS. |
| AC-CMD-07 | Every BLOCK, WARN, and PASS outcome writes a timestamped entry to `logs/cmd_save_quality.log` and updates session-state files under flock protection. Concurrent invocations do not corrupt the log. | Unit: assert log entry format (timestamp, cmd_id, outcome, reason). Concurrency: run 5 parallel saves; assert no truncated lines in log. |
| AC-CMD-08 | The script warns on: (a) lock contention on `shogun_to_karo.yaml`, (b) uncommitted changes in implementation files referenced by the cmd, (c) duplicate GP numbers across active cmds, (d) scout/recon cmd that overlaps with existing gunshi analysis files. | Unit: 4 separate test cases, each asserting WARN with specific reason string. |
| AC-CMD-09 | Given a cmd referencing `bulletin_action_ids`, the script updates the corresponding bulletin entries' tracking state in `queue/bulletin_board.yaml`. | Unit: create bulletin entry with `action_required: true`; save cmd referencing it; assert tracking field updated. |

### 2.2 deploy_task.sh

| ID | Criterion | Verification Method |
|----|-----------|---------------------|
| AC-DEP-01 | The script correctly parses 4 deployment modes: (a) `deploy_task.sh hayate` (normal), (b) `deploy_task.sh --direct hayate` (direct), (c) `deploy_task.sh --yaml path/to/task.yaml hayate` (yaml), (d) `deploy_task.sh --cmd cmd_123 hayate` (cmd). Each mode produces a valid task YAML assignment. Default message invalidates stale previous task context. | Unit: invoke each mode with fixture data; assert task YAML exists with correct fields and default invalidation message. |
| AC-DEP-02 | Given an empty string, `None`, or `cmd_123` as first positional target, the script exits non-zero with an error message before writing any file. | Unit: 3 cases, each asserting exit≠0 and no task YAML created. |
| AC-DEP-03 | The script resolves the target ninja's tmux pane via shared helper libraries and determines idle/busy state. Given a busy ninja, the script logs a warning but proceeds with deployment. | Integration: mock pane_lookup to return a valid pane; assert state detection output. Mock busy state; assert warning logged and deployment continues. |
| AC-DEP-04 | Before writing a new assignment, the script resets: (a) stale task fields (status, progress, worker_id), (b) stale notification flags, (c) ghost `None.yaml` artifacts under `queue/tasks/`. | Unit: pre-create stale task with old fields + `None.yaml`; run deploy; assert fields reset and `None.yaml` removed. |
| AC-DEP-05 | Given a `--cmd cmd_123` deployment, the script resolves the parent cmd into: task metadata (parent_cmd, task_id, task_type, project, status, purpose, _ac_task_id), acceptance criteria, AC version hash, related lessons, semantic concepts, engineering preferences, and execution controls. All fields are present in the output task YAML. | Unit: create fixture cmd in `shogun_to_karo.yaml` with all sub-fields; deploy; assert every field present in output YAML with correct values. |
| AC-DEP-06 | The script generates a report template at `queue/reports/{cmd_id}_{ninja}.yaml` if none exists. If a completed report already exists (status: completed), the script does not overwrite it. | Unit: (a) deploy with no prior report→assert template created. (b) Pre-create completed report→deploy→assert report content unchanged. |
| AC-DEP-07 | Task notification is delivered exclusively via `scripts/inbox_write.sh`. The inbox file `queue/inbox/{ninja}.yaml` contains a new entry with `type: task_assigned`. Direct tmux send-keys is used only as a re-nudge fallback, never as the primary delivery. Persisted inbox writes are treated as successful even if post-delivery verification fails. | Integration: deploy; assert inbox_write.sh was invoked (via wrapper/log); assert inbox file contains task_assigned entry. |
| AC-DEP-08 | Given a parent cmd for which a completed peer report already exists, the script blocks duplicate active deployment and exits non-zero. | Unit: create completed report for cmd_123 by ninja hayate; attempt deploy cmd_123 to kagemaru; assert exit≠0. |
| AC-DEP-09 | All queue/task YAML mutations use shared YAML helpers (`yaml_field_set`, `yaml_field_set_batch`, `field_get`, `field_get_multi`). No raw `echo >>`, `sed -i`, or `cat >` YAML writes exist in the deployment path. | Static analysis: grep deploy_task.sh for raw YAML write patterns; assert zero matches outside helper calls. |

### 2.3 inbox_write.sh

| ID | Criterion | Verification Method |
|----|-----------|---------------------|
| AC-INB-01 | The script accepts `<target> <content>` as required arguments and `<type> <sender> <action>` as optional. Missing target or empty content causes exit≠0. | Unit: (a) `inbox_write.sh "" "msg"`→exit≠0. (b) `inbox_write.sh karo ""`→exit≠0. (c) `inbox_write.sh karo "test" cmd_new shogun action1`→exit 0 with all fields serialized. |
| AC-INB-02 | Given an invalid agent name (e.g. `nobody`), the script exits≠0. Given a ninja sender targeting shogun (e.g. `inbox_write.sh shogun "msg" report hanzo`), the script exits≠0 with routing violation message. Karo→shogun is permitted. | Unit: (a) invalid target→exit≠0. (b) ninja→shogun→exit≠0 with "routing" in stderr. (c) karo→shogun→exit 0. |
| AC-INB-03 | Each serialized message in `queue/inbox/{agent}.yaml` contains: `id` (unique), `timestamp` (ISO 8601), `type`, `from`, `content`, `read: false`, and optional `action`. | Unit: write 3 messages; parse YAML; assert all 7 fields present per entry; assert ids are unique; assert read=false. |
| AC-INB-04 | Writes use flock on a lock file appropriate for WSL2 `/mnt/*` paths. Under 10 concurrent writers, no message is lost or truncated. Inbox persistence is the durable source of truth. | Concurrency: launch 10 parallel `inbox_write.sh` invocations to the same target; count entries in inbox YAML; assert count=10 with no malformed entries. |
| AC-INB-05 | Given an active `task_assigned` message for `cmd_123` already in the target's inbox (read: false), a second `task_assigned` for `cmd_123` is blocked. | Unit: write task_assigned for cmd_123; write second→assert exit≠0 or dedup message. |
| AC-INB-06 | For `type: task_assigned` messages, if related_lessons are absent from the task YAML, the script injects lessons as a safety net by reading the parent cmd's lesson references. | Unit: create task YAML without related_lessons; send task_assigned; assert lesson fields appear in task YAML after write. |
| AC-INB-07 | For `type: report_received` messages, the script validates the referenced report YAML format and triggers downstream review/completion behavior (e.g. karo inbox notification or gate invocation). | Integration: create valid report YAML; send report_received; assert format check passes and downstream action fires. Create malformed report; assert format check failure logged. |
| AC-INB-08 | Pane resolution and CLI-specific nudge delivery occur only after the inbox message is persisted. If nudge delivery fails (e.g. pane not found), the message remains in the inbox file. | Unit: mock pane_lookup to fail; send message; assert message in inbox file despite nudge failure. |

### 2.4 ninja_monitor.sh

| ID | Criterion | Verification Method |
|----|-----------|---------------------|
| AC-NM-01 | The script runs as a singleton daemon (second instance exits immediately). It rediscovers ninja panes from tmux `@agent_id` metadata on each monitoring cycle. | Integration: start monitor; start second instance→assert exit≠0. Verify pane discovery output matches tmux pane list. |
| AC-NM-02 | Idle detection uses a multi-signal approach: `@agent_state` hook variable, last-active timestamps (>threshold), CLI-specific prompt patterns, and subprocess cross-check (`pgrep`). Hook state takes precedence over prompt-only detection. | Unit: set @agent_state=idle + prompt=busy→assert idle (hook wins). Set @agent_state=busy + prompt=idle→assert busy. |
| AC-NM-03 | The script clears or respawns an agent only after both: (a) idle confirmation via multi-signal, and (b) report-gate check confirms no pending report submission. A pane with active task state is never cleared unless both gates pass. | Integration: set agent idle + pending report→assert no clear. Set agent idle + no pending report→assert clear+respawn. |
| AC-NM-04 | The monitor detects and reports: pane loss (tmux pane missing), stale deployments (task_assigned >30min with no progress), undeployed commands, karo pending work, CLI death (process not running), inbox unread counts, and report/task mismatches. Each detection triggers an inbox_write to karo. | Integration: simulate each of the 7 anomalies; assert corresponding inbox message to karo with anomaly type tag. |
| AC-NM-05 | `queue/karo_snapshot.txt` is regenerated each cycle with: each ninja's current cmd, ninja name, model, context window usage percentage, and report state. Format matches `ninja\|{name}\|{cmd}\|{status}\|{project}\|CTX:{pct}%\|M:{model}`. | Unit: with 6 configured ninjas, assert snapshot contains 6 ninja lines matching the format regex. |
| AC-NM-06 | The monitor checks health of: inbox_watcher (pgrep), ntfy_listener (pgrep), CI status (gh run list), training auto-deploy conditions, lesson health (staleness), loop health (cycle counts), workaround trends (recent count), and script size trends (wc -l). Each unhealthy subsystem triggers a warning line in karo_snapshot.txt. | Integration: kill inbox_watcher; run one monitor cycle; assert "inbox_watcher" warning in snapshot. |
| AC-NM-07 | All agent communication from ninja_monitor uses `scripts/inbox_write.sh`. No direct tmux `send-keys` for message content. | Static analysis: grep ninja_monitor.sh for `send-keys` usage; assert all occurrences are either pane control (resize, select) or post-inbox nudge, never message content delivery. |

### 2.5 dashboard_auto_section.sh

| ID | Criterion | Verification Method |
|----|-----------|---------------------|
| AC-DASH-01 | The script reads all 10 specified data sources: `karo_snapshot.txt`, `shogun_to_karo.yaml`, `gate_metrics.log`, `tasks/*.yaml`, `settings.yaml`, `cli_profiles.yaml`, `gate_fire_log.yaml`, `lesson_impact.tsv`, `lesson_effectiveness_status.txt`. Missing sources produce `—` placeholder, not errors. | Unit: provide all sources→assert 10 sections populated. Remove 3 sources→assert those sections show `—`. |
| AC-DASH-02 | The script invokes 5 subprocesses: `knowledge_metrics.sh`, `model_analysis.sh`, `context_freshness_check.sh`, `ci_status_check.sh`, `skill_metrics.sh`. Failed subprocesses produce `—` placeholder output. | Unit: stub all 5 scripts; assert invocation. Stub one to exit 1→assert `—` in corresponding section. |
| AC-DASH-03 | Output contains exactly 10 sections: 忍者配備, CI Status, Unpushed Commits WARN, パイプライン, 戦況メトリクス, モデル別スコアボード, 知識サイクル健全度, スキル健全度, Context鮮度警告, 戦果. | Unit: run script with complete fixtures; assert all 10 section headers present between markers. |
| AC-DASH-04 | With `--dry-run`, the script outputs the generated auto-section to stdout and `dashboard.md` remains byte-identical to its pre-invocation state. | Unit: checksum dashboard.md; run with `--dry-run`; assert stdout non-empty and checksum unchanged. |
| AC-DASH-05 | Content outside `<!-- DASHBOARD_AUTO_START -->` and `<!-- DASHBOARD_AUTO_END -->` markers is preserved byte-for-byte after the script runs. | Unit: add custom content above/below markers; run script; assert custom content unchanged via diff. |
| AC-DASH-06 | ntfy notification fires only when CLEAR count increases. Deduplication uses `/tmp/mas-dashboard-ntfy-last-clear.txt`. Same CLEAR count on consecutive runs produces zero ntfy calls. | Unit: (a) first run with 5 CLEARs→assert ntfy called. (b) second run with 5 CLEARs→assert ntfy NOT called. (c) third run with 6 CLEARs→assert ntfy called. |
| AC-DASH-07 | After auto-section update, strikethrough entries (`~~...~~`) in the 将軍宛報告 section are removed. Non-strikethrough entries are preserved. | Unit: add 2 normal + 2 strikethrough entries to 将軍宛報告; run script; assert 2 normal remain, 0 strikethrough. |
| AC-DASH-08 | Subprocess results are cached with specified TTLs: CI status (60s), context freshness (120s), git rev-list (60s). Awk computations are cached keyed by mtime of source files. `context_freshness_check.sh` and `ci_status_check.sh` launch as background processes. Cache paths are project-scoped via `cksum` of `$PROJECT_DIR`. | Performance: run twice within 30s; assert second run skips subprocess invocation (via counter/log). Assert cache files contain cksum-based path component. |
| AC-DASH-09 | Dashboard writes use atomic temp-file + `mv` pattern. A concurrent reader during write never sees partial content. | Concurrency: background 100 rapid reads while script writes; assert no read returns truncated/empty content. |
| AC-DASH-10 | When all data sources are missing and all subprocesses fail, the script still produces a valid auto-section with `—` placeholders in all 10 sections and exits 0. | Unit: remove all sources; stub all subprocesses to fail; run→assert exit 0 and 10 sections with `—`. |
| AC-DASH-11 | When `dashboard.md` does not exist, the script exits 1. When markers are absent from `dashboard.md`, the script exits 1 and does not modify the file. | Unit: (a) delete dashboard.md→assert exit 1. (b) Create dashboard.md without markers→assert exit 1 and file unchanged. |

### 2.6 restart_watchers.sh

| ID | Criterion | Verification Method |
|----|-----------|---------------------|
| AC-RW-01 | The script acquires `/tmp/restart_watchers.lock` via `flock -n`. A second concurrent invocation exits≠0 immediately. | Concurrency: hold lock in background; invoke script→assert exit≠0. |
| AC-RW-02 | Existing watcher processes receive SIGTERM first. After 1-second wait, any survivors receive SIGKILL. Each stage checks remaining process count before escalation. | Unit: start mock watchers; run script; assert SIGTERM sent to all; assert SIGKILL only sent if survivors exist after 1s delay. |
| AC-RW-03 | Shogun watcher launches via `@agent_cli` from `shogun:main` pane. Karo watcher launches via `shogun:agents.1` pane. Both use nohup with log output to `logs/inbox_watcher_{agent}.log`. | Integration: run script; assert `pgrep -f "inbox_watcher.*shogun"` succeeds; assert log file exists and is being appended. Same for karo. |
| AC-RW-04 | Remaining agents are enumerated from `agent_config.sh::get_all_agents()`. Karo is skipped. Agents with empty/missing panes are silently skipped (no error). | Unit: configure 6 agents; make 1 pane empty; run→assert 5 watchers started (karo excluded, empty-pane skipped). No error output for skipped agents. |
| AC-RW-05 | Post-launch verification: each watcher detected via `pgrep -f`. After 2-second delay, `inotifywait` process count matches started watcher count. Mismatch emits warning but does not cause exit≠0. | Integration: run script; assert pgrep count = started count. Kill one inotifywait; re-verify→assert warning in output. |
| AC-RW-06 | After all watcher operations, `scripts/sync_pane_vars.sh` is executed. | Unit: stub sync_pane_vars.sh; run restart_watchers; assert stub was invoked. |

### 2.7 YAML Batch Operations (Refactor)

| ID | Criterion | Verification Method |
|----|-----------|---------------------|
| AC-YML-01 | `yaml_field_set_batch <file> <block_id> field1=val1 field2=val2 ... fieldN=valN` writes all N fields in 1 flock acquisition and 1 awk pass. File is rewritten once via atomic mv. | Unit: batch-set 7 fields; assert all present in output. `strace`/timing: assert ≤1 flock call and ≤1 mv call. |
| AC-YML-02 | `yaml_field_set_batch` performs `verify_after_write` exactly once after the single write pass. | Unit: instrument verify function; batch-set 5 fields; assert verify called once. |
| AC-YML-03 | Existing `yaml_field_set <file> <block_id> <field> <value>` API signature and output format are unchanged. All call sites outside deploy_task.sh continue to work. | Regression: run full existing yaml_field_set test suite; assert 0 failures. |
| AC-YML-04 | `field_get_multi <file> field1 field2 ... fieldN` returns `field1=value1\nfield2=value2\n...` in 1 awk pass. Output is eval-safe. | Unit: create YAML with 7 fields; run field_get_multi; assert all 7 returned. Eval output in bash; assert variables set correctly. |
| AC-YML-05 | `field_get_multi` handles missing fields by emitting `field=` (empty value) rather than omitting the line. | Unit: request 3 fields, 1 missing; assert output has 3 lines including empty one. |
| AC-YML-06 | Existing `field_get <file> <field>` API signature and output are unchanged. | Regression: run full existing field_get test suite; assert 0 failures. |
| AC-REF-01 | `resolve_cmd_to_task()` in deploy_task.sh uses `yaml_field_set_batch` for its 7 field writes (parent_cmd, task_id, task_type, project, status, purpose, _ac_task_id). Zero individual `yaml_field_set` calls remain in this function. | Static analysis: grep resolve_cmd_to_task for `yaml_field_set[^_]`; assert 0 matches. Assert `yaml_field_set_batch` present. |
| AC-REF-02 | `inject_ac_version()` in deploy_task.sh uses `field_get_multi` for its 6–7 field reads and `yaml_field_set_batch` for its 3 field writes. Zero individual `yaml_field_set` or `field_get` calls remain in this function. | Static analysis: grep inject_ac_version for standalone `field_get[^_]` and `yaml_field_set[^_]`; assert 0 matches. |
| AC-REF-03 | `resolve_cmd_to_task()` completes in ≤100ms (p95) measured over 50 invocations with representative fixtures. Baseline: 627ms. | Performance: run 50 iterations; compute p95; assert ≤100ms. |
| AC-REF-04 | `inject_ac_version()` completes in ≤80ms (p95) measured over 50 invocations with representative fixtures. Baseline: 541ms. | Performance: run 50 iterations; compute p95; assert ≤80ms. |
| AC-REF-05 | All existing tests (unit + integration) pass with zero failures and zero skips after the refactor. Test count ≥ pre-refactor count. | CI: run full `bats` suite; assert 0 fail, 0 skip, count ≥ pre-refactor baseline. |

## 3. Failure Criteria

Any single failure criterion violation blocks release.

### 3.1 Release Blockers

| ID | Condition | Severity |
|----|-----------|----------|
| FC-INB-01 | A ninja agent successfully sends a message to shogun's inbox (ninja→shogun routing bypass). | CRITICAL — violates SR-2 inbox_write, chain-of-command integrity. |
| FC-INB-02 | Concurrent inbox writes (≥2 writers) cause message loss, truncation, or YAML corruption. | CRITICAL — violates SR-3 inbox_write (flock atomicity). |
| FC-CMD-01 | A cmd in `delegated` state is mutated by cmd_save.sh. | CRITICAL — violates SR-2 cmd_save (immutability). |
| FC-CMD-02 | A cmd with gate state `pending` or `blocked` is delegated to karo. | CRITICAL — violates SR-1 cmd_save. |
| FC-CMD-03 | A BLOCK/WARN/PASS outcome is not recorded in quality logs. | HIGH — breaks growth loop audit trail. |
| FC-DEP-01 | deploy_task.sh writes task YAML using raw shell commands (echo, sed, cat) instead of shared YAML helpers. | CRITICAL — violates SR-1 deploy_task (yaml.dump prohibition). |
| FC-DEP-02 | deploy_task.sh sends task content via tmux send-keys instead of inbox_write.sh. | CRITICAL — violates SR-3 deploy_task (inbox-path-only). |
| FC-DEP-03 | A completed report is overwritten by a new deployment. | HIGH — data loss. |
| FC-NM-01 | ninja_monitor clears a pane with an active task and pending report. | CRITICAL — violates SR-2 ninja_monitor. |
| FC-NM-02 | ninja_monitor sends message content via tmux send-keys instead of inbox_write.sh. | HIGH — violates SR-3 ninja_monitor. |
| FC-DASH-01 | dashboard_auto_section.sh modifies content outside the auto-section markers. | CRITICAL — data corruption of lord's manual content. |
| FC-DASH-02 | dashboard_auto_section.sh produces partial/truncated output (non-atomic write). | HIGH — violates SR-1 dashboard. |
| FC-RW-01 | Two restart_watchers instances run simultaneously (lock bypass). | HIGH — violates FR-1 restart_watchers. |
| FC-RW-02 | Watcher processes receive SIGKILL without prior SIGTERM attempt. | MEDIUM — violates SR-1 restart_watchers (two-stage). |
| FC-YML-01 | Any existing test fails after the batch refactor. | CRITICAL — violates refactor zero-regression constraint. |
| FC-YML-02 | `yaml_field_set_batch` acquires flock more than once per invocation. | HIGH — defeats the performance purpose of batching. |
| FC-YML-03 | `yaml_field_set` or `field_get` API signatures change (backward incompatibility). | CRITICAL — violates refactor API compatibility constraint. |
| FC-PERF-01 | `resolve_cmd_to_task` p95 > 200ms after refactor (must be ≤100ms target, 200ms hard ceiling). | HIGH — insufficient improvement. |
| FC-PERF-02 | `inject_ac_version` p95 > 160ms after refactor (must be ≤80ms target, 160ms hard ceiling). | HIGH — insufficient improvement. |

### 3.2 Data Integrity Failures

| ID | Condition |
|----|-----------|
| FC-DATA-01 | Any YAML file under `queue/` contains truncated entries, missing required fields, or unparseable syntax after script execution. |
| FC-DATA-02 | `karo_snapshot.txt` contains stale data (>2 monitoring cycles old) for any ninja without a corresponding staleness warning. |
| FC-DATA-03 | A report template is generated with missing required fields (cmd_id, ninja_name, status, sections). |

## 4. E2E Test Generation Meta-Prompt

### 4.1 MECE Domain Decomposition

| Domain | Scope | Output File |
|--------|-------|-------------|
| cmd-gate | cmd_save.sh: id normalization, YAML validation, state immutability, quality gate enforcement, outcome recording, advisory warnings, bulletin tracking | `tests/e2e/cmd-gate.spec.ts` |
| deploy-task | deploy_task.sh: 4 deployment modes, target validation, stale cleanup, cmd→task resolution, report template generation, inbox delivery, duplicate blocking | `tests/e2e/deploy-task.spec.ts` |
| inbox-routing | inbox_write.sh: argument validation, agent routing (incl. ninja→shogun prohibition), message serialization, flock concurrency, duplicate task_assigned blocking, lesson injection, report format checks, nudge delivery | `tests/e2e/inbox-routing.spec.ts` |
| formation-monitor | ninja_monitor.sh: singleton enforcement, idle detection, clear/respawn gates, anomaly detection (7 types), snapshot generation, subsystem health checks | `tests/e2e/formation-monitor.spec.ts` |
| dashboard-gen | dashboard_auto_section.sh: data source reading, subprocess invocation, 10-section generation, dry-run, marker preservation, ntfy dedup, strikethrough cleanup, caching, atomic writes, graceful degradation | `tests/e2e/dashboard-gen.spec.ts` |
| watcher-lifecycle | restart_watchers.sh: singleton lock, two-stage stop, per-agent launch, pane resolution skip, post-launch verification, inotifywait count, sync_pane_vars | `tests/e2e/watcher-lifecycle.spec.ts` |
| yaml-batch | yaml_field_set_batch, field_get_multi: batch write, batch read, verify_after_write, API compatibility, performance thresholds | `tests/e2e/yaml-batch.spec.ts` |
| refactor-integration | deploy_task.sh after refactor: resolve_cmd_to_task batch usage, inject_ac_version batch usage, full regression suite, performance benchmarks | `tests/e2e/refactor-integration.spec.ts` |

### 4.2 Scenario Derivation Rules

For each domain:

1. **Positive scenarios**: Derive one test per acceptance criterion. Each AC-XXX-NN maps to at least one `test()` block.
2. **Negative scenarios**: Invert each failure criterion into an assertion. Each FC-XXX-NN becomes a test that triggers the failure condition and asserts the system rejects/blocks/logs correctly.
3. **Boundary scenarios**: For numeric thresholds (TTLs, timing, concurrent writers), test at the exact boundary value and one step beyond.
4. **Concurrency scenarios**: For flock-protected operations (inbox_write, yaml_field_set_batch, restart_watchers lock), test with 10 parallel invocations and assert atomicity.

### 4.3 Test Level Separation

**API integration tests** (`*.spec.ts`):
- Execute shell scripts directly via `child_process.execSync` or `execa`.
- Assert exit codes, stdout/stderr content, and file system state (YAML content, log entries, snapshot format).
- Use `tmp` directories for isolated queue/inbox/task fixtures.
- Verify HTTP-level equivalents where applicable (e.g. ntfy calls via mock server).

**Browser tests** (`*.browser.spec.ts`):
- Not applicable for this project. All scripts under test are shell-based infrastructure with no web UI. Browser test files are not generated.

### 4.4 Architecture Adaptation

Test generation must:

1. Scan `scripts/` for all `.sh` files referenced in requirements. For each script, verify the entry point function exists.
2. Scan `scripts/lib/` for helper libraries (`yaml_field_set.sh`, `field_get.sh`, `agent_config.sh`, `pane_lookup.sh`). Assert their exported functions match the APIs referenced in tests.
3. For any function or script not yet implemented (e.g. `yaml_field_set_batch` before R3 completion), mark with `test.fixme('awaiting implementation: yaml_field_set_batch')` instead of skipping.
4. Detect WSL2 environment via `uname -r` containing `microsoft`; adjust flock paths and timing thresholds accordingly.

### 4.5 Runtime Environment

**Startup sequence:**

1. No application server required. Tests execute shell scripts directly.
2. Prerequisite: `tmux` server running with `shogun` session (for pane-dependent tests). Tests that require tmux must check `tmux has-session -t shogun 2>/dev/null` and mark themselves `test.fixme('requires tmux shogun session')` if absent.
3. Prerequisite: `bats-core` installed for existing test suite execution in refactor-integration domain.
4. Fixture setup: each test creates a temporary directory (`mktemp -d`), populates it with minimal YAML fixtures, sets `PROJECT_DIR` to the temp directory, and cleans up on teardown.
5. For CI: `tmux` session can be created headless via `tmux new-session -d -s shogun` in the CI setup step. inotifywait tests require `inotify-tools` package.

### 4.6 Quality Gate

| Criterion | Threshold |
|-----------|-----------|
| All tests PASS | 100% (zero FAIL) |
| Zero SKIP | 0 skipped tests (SKIP = FAIL policy) |
| AC coverage | Every AC-XXX-NN has ≥1 corresponding test |
| FC coverage | Every FC-XXX-NN has ≥1 corresponding negative test |
| VB traceability | Every VB-XXX-NN in the traceability table maps to ≥1 executed test |
| Performance tests | p95 values within specified thresholds (AC-REF-03: ≤100ms, AC-REF-04: ≤80ms) |
| Concurrency tests | Zero data loss under 10 parallel writers (AC-INB-04, AC-YML-01) |
| Convention compliance | flock-based writes verified (FC-INB-02, FC-YML-02), inbox-path-only verified (FC-DEP-02, FC-NM-02), ninja→shogun prohibition verified (FC-INB-01), API compatibility verified (FC-YML-03) |

### 4.7 Shared Helpers

All shared test utilities reside in `tests/e2e/helpers/`:

| Helper | Purpose |
|--------|---------|
| `tests/e2e/helpers/fixture-setup.ts` | Create temporary PROJECT_DIR, populate minimal YAML fixtures (shogun_to_karo.yaml, inbox files, task files, settings.yaml, dashboard.md with markers), set environment variables |
| `tests/e2e/helpers/yaml-assert.ts` | Parse YAML files and provide assertion helpers: `assertFieldEquals(file, block, field, value)`, `assertFieldExists(file, block, field)`, `assertEntryCount(file, expected)`, `assertNoCorruption(file)` |
| `tests/e2e/helpers/script-runner.ts` | Execute shell scripts with configurable env, capture stdout/stderr/exit code, support timeout, provide `runScript(path, args, opts)` and `runScriptAsync(path, args, opts)` |
| `tests/e2e/helpers/concurrency.ts` | Launch N parallel script invocations, collect all results, assert atomicity (no lost writes, no corruption) |
| `tests/e2e/helpers/tmux-mock.ts` | Mock tmux commands for tests that don't require real tmux. Provide fake pane metadata, agent_state variables, and capture-pane output |
| `tests/e2e/helpers/timing.ts` | Measure p95 execution time over N iterations. `benchmarkP95(fn, iterations, thresholdMs)` |

### 4.8 Generation Markers

All generated test files must include these headers:

```typescript
// @generated-from: docs/test/acceptance_criteria.md
// @generated-by: codd propagate
```

Tests manually added by developers must include:

```typescript
// @manual
```

`codd propagate` must preserve all `// @manual` blocks during regeneration. Manual blocks are never overwritten or reordered.

### 4.9 Output File Mapping

| Domain | File Path | Test Count (min) |
|--------|-----------|-----------------|
| cmd-gate | `tests/e2e/cmd-gate.spec.ts` | 9 (AC-CMD-01 through AC-CMD-09) + 3 (FC-CMD-01 through FC-CMD-03) |
| deploy-task | `tests/e2e/deploy-task.spec.ts` | 9 (AC-DEP-01 through AC-DEP-09) + 3 (FC-DEP-01 through FC-DEP-03) |
| inbox-routing | `tests/e2e/inbox-routing.spec.ts` | 8 (AC-INB-01 through AC-INB-08) + 2 (FC-INB-01 through FC-INB-02) |
| formation-monitor | `tests/e2e/formation-monitor.spec.ts` | 7 (AC-NM-01 through AC-NM-07) + 2 (FC-NM-01 through FC-NM-02) |
| dashboard-gen | `tests/e2e/dashboard-gen.spec.ts` | 11 (AC-DASH-01 through AC-DASH-11) + 2 (FC-DASH-01 through FC-DASH-02) |
| watcher-lifecycle | `tests/e2e/watcher-lifecycle.spec.ts` | 6 (AC-RW-01 through AC-RW-06) + 2 (FC-RW-01 through FC-RW-02) |
| yaml-batch | `tests/e2e/yaml-batch.spec.ts` | 6 (AC-YML-01 through AC-YML-06) + 3 (FC-YML-01 through FC-YML-03) |
| refactor-integration | `tests/e2e/refactor-integration.spec.ts` | 5 (AC-REF-01 through AC-REF-05) + 2 (FC-PERF-01 through FC-PERF-02) + 3 (FC-DATA-01 through FC-DATA-03) |
| **Total** | | **≥ 81 tests** |
