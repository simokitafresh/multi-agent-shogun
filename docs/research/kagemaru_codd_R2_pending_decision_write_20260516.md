# cmd_training_codd_r2_kagemaru: pending_decision_write.sh CoDD Spec

date: 2026-05-16
worker: kagemaru
target: `scripts/pending_decision_write.sh`
pipeline: spec -> elicit/lexicon -> generate -> validate -> measure

## 1. Spec

### Purpose

`scripts/pending_decision_write.sh` is the authoritative write boundary for
`queue/pending_decisions.yaml`, the system of record for unresolved and resolved
Lord decisions. It creates, resolves, lists, and recalculates pending-decision
entries while keeping the summary counts, dashboard "要対応" section, and
post-resolution context-sync alerts aligned with the primary YAML data.

The real requirement is not "append a PD row"; it is "preserve decision continuity
across sessions while making unresolved human decisions visible until they are
reflected into the passive knowledge layer."

### Scope

- Dispatch subcommands: `create`, `resolve`, `list`, and `recalc`.
- Initialize `queue/pending_decisions.yaml` when missing.
- Validate `create` arguments and restrict type to `lord_decision`, `skill_candidate`,
  `escalation`, or `action_required`.
- Generate monotonic `PD-XXX` IDs by scanning existing decisions.
- Write `summary.total`, `summary.resolved`, and `summary.pending` from actual entries.
- Serialize updates under a flock and replace files atomically.
- Sync dashboard "要対応" on create and resolve.
- Resolve existing PDs idempotently when already resolved.
- Mark `context_synced` false on most real resolutions, with explicit exemptions for
  reconcile, test, archived-project direct, and `--no-context-sync`.
- Run `gate_pd_sync.sh` after successful resolve, then append context TODO records.
- Provide an awk-based list view with pending/default, all, and multiline summary flattening.
- Recalculate stale summary counts without changing decision bodies.

### Non-scope

- It does not decide whether a decision should be created; upstream reviewers and Karo decide.
- It does not update the target context file; it only flags and logs the need.
- It does not archive resolved decisions; `archive_completed.sh` owns archival.
- It does not validate whether a resolved decision duplicates an existing one; duplicate checks
  live in `gate_dc_duplicate.sh` and Karo review flow.
- It does not own dashboard full regeneration; `dashboard_update.sh` remains the full rebuild path.

## 2. Elicit / Lexicon Findings

`codd elicit --format md --path .` failed before target analysis because the configured
`shogun_core` lexicon manifest was not found. The findings below combine code reading,
unit-test evidence, and lexicon-style coverage axes.

| ID | Hole / Coverage Axis | Evidence | Impact |
| --- | --- | --- | --- |
| GAP-1 | YAML write exception scope is undocumented | `create` and `resolve` use Python `yaml.dump` for `queue/pending_decisions.yaml` | Global ops YAML guidance bans generic dump; this script needs a documented exception or safer writer |
| GAP-2 | Dashboard sync has two implementations | Shell `dashboard_add_pending/remove_pending` exist, and Python has `_sync_dashboard_*` copies | Divergence can make create/resolve behavior differ from helper behavior that appears unused |
| GAP-3 | Project-aware context sync is incomplete for created entries | `resolve` checks `d.get('project', '')`, but `create` does not store project | Archived-project exemption and context TODO routing can degrade to `unknown` |
| GAP-4 | List parser assumes a narrow YAML layout | `cmd_list` detects `^- id:` and two-space fields with awk | YAML formatting changes from dump options or manual repair can make list output silently wrong |
| GAP-5 | Dashboard update and PD YAML update are not a single transaction | Python writes PD YAML, then syncs dashboard; resolve also runs gate/TODO outside flock | Partial success can leave dashboard or TODO out of sync with primary data |
| GAP-6 | Lock retry policy is fixed and unmeasured | Three attempts with 5-second flock wait and 1-second sleep | Under parallel Karo/automation writes, user-visible delay or failure threshold is not tied to an SLO |
| GAP-7 | Summary recalc has narrow status matching | `recalc` counts only lines exactly matching `status: resolved` | Quoted values or indentation changes can undercount resolved entries |
| GAP-8 | Existing tests validate happy paths well but not corruption/partial-sync recovery | 21 bats tests cover create/resolve/list/recalc basics | Failures in dashboard sync, gate_pd_sync, malformed YAML, and lock contention are less covered |

Recommended lexicon axes:

- `pending_decision_primary_data_before_dashboard`
- `pd_id_monotonic_generation`
- `pd_summary_count_consistency`
- `pd_context_sync_visibility`
- `pd_dashboard_partial_sync_recovery`
- `pd_yaml_dump_exception_scope`
- `pd_list_parser_layout_contract`
- `pd_lock_retry_slo`

## 3. Generate / Design Sketch

The design should be represented by a small CoDD node set:

- Requirement: "Every create/resolve must update summary counts from actual decision rows."
- Requirement: "PD YAML is primary; dashboard and TODO logs are derived views."
- Constraint: "Decision IDs must be monotonic and never reuse archived or existing IDs."
- Constraint: "Resolved decisions must remain visible as context-unsynced unless an explicit
  exemption applies."
- Constraint: "Dashboard sync failures must be detectable and recoverable by dashboard rebuild."
- Constraint: "The allowed `yaml.dump` usage for `pending_decisions.yaml` must be documented,
  tested, or replaced."
- Test fixture: create first and second PD, then verify summary counts and dashboard entry.
- Test fixture: resolve with default, with `--no-context-sync`, and already-resolved idempotency.
- Test fixture: list handles multiline summary and all/pending filters.
- Test fixture: malformed or quoted status values are either supported or explicitly rejected.
- Test fixture: simulated dashboard write failure does not corrupt PD YAML and emits a warning.

## 4. Validate / Measure Evidence

Commands run from `/mnt/c/tools/multi-agent-shogun`:

| Command | Result |
| --- | --- |
| `bash -n scripts/pending_decision_write.sh` | PASS |
| `bats tests/unit/test_pending_decision_write.bats` | PASS: 21/21 |
| `codd validate --path .` | PASS: 16 Markdown files validated |
| `codd measure --path . --json` | PASS: health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4, coverage_ratio=0.0 |
| `codd coverage report --path . --format md` | FAIL: Unknown lexicon `shogun_core` |
| `codd elicit --format md --path .` | FAIL: lexicon manifest not found: `shogun_core` |
| `codd dag verify --path . --format json` | PASS: all checks passed; `depends_on_consistency` skipped because propagation output was not found; `runtime:db_seed:users` unreachable but amber/pass |

## 5. Design Score

Score: 7 / 10.

Rationale:

- Strong operational model: one helper centralizes PD create/resolve/list/recalc.
- Good test coverage for core CLI behavior: 21 bats tests cover argument validation, create,
  resolve, list, dashboard sync, and recalc.
- Good learning-loop fit: unresolved decisions stay visible and resolved decisions can trigger
  context-sync debt.
- Good summary consistency: create/resolve/recalc derive counts from actual decisions.
- Weak CoDD source coverage: project measure still reports 0 tracked source files and 0.0 coverage.
- Medium consistency risk: duplicate shell/Python dashboard-sync helpers and non-transactional
  derived-view updates can drift.
- Medium maintainability risk: YAML parsing/writing mixes PyYAML and awk layout assumptions.
- Policy ambiguity: `yaml.dump` on operational YAML needs explicit exception documentation.

## 6. Improvement Candidates

1. Document or remove the `yaml.dump` exception for `queue/pending_decisions.yaml`; preferred
   direction is a shared structured writer with round-trip validation and explicit allowed files.
2. Remove unused shell dashboard sync helpers or make them call the same implementation as the
   Python path, so dashboard create/resolve behavior has one source.
3. Add a `project` argument or extraction rule to `create`, then use it in `resolve` for context
   TODO routing and archived-project exemptions.
4. Replace the awk list/recalc parser with a small structured reader, or define the exact YAML
   layout contract and add tests for quoted status and indentation variants.
5. Add failure-injection tests for dashboard sync failure, malformed `pending_decisions.yaml`,
   flock timeout, and gate_pd_sync failure handling.
6. Fix CoDD `shogun_core` lexicon configuration so `coverage report` and `elicit` run during
   training without environmental failure.

## 7. Binary Checks

| AC | Check | Result |
| --- | --- | --- |
| AC1 | `pending_decision_write.sh` was read and a spec-like purpose, constraints, and scope were recorded in this file | yes |
| AC2 | Elicit/lexicon-style requirement holes and coverage axes were listed despite the current lexicon command failure | yes |
| AC3 | `validate`, `measure`, unit tests, and related CoDD checks were run; design quality was scored and at least three improvements were identified | yes |

## 8. 追完ループ3結果: cmd_training_codd_loop3_hayate

### AC1: extract

Command:

```bash
timeout 1200 codd extract --path .
```

Result:

```text
Extracted: 0 modules from 0 files (0 lines)
Output: .codd/extract/
  system-context.md
  architecture-overview.md

Next steps:
  1. Review generated docs in .codd/extract/
  2. Promote confirmed docs: mv .codd/extract/*.md docs/design/
  3. Run: codd scan  (to build the dependency graph)
EXIT_CODE=0
```

Binary check: PASS (exit code 0)

### AC2: generate

Command:

```bash
timeout 1200 codd generate --wave 1 --force --path .
```

Result:

```text
Generated: docs/test/acceptance_criteria.md (test:acceptance-criteria)
Generated: docs/governance/adr_yaml_batch_operations.md (governance:adr-yaml-batch-operations)
Wave 1: 2 generated, 0 skipped
EXIT_CODE=0
```

Binary check: PASS (exit code 0)

### AC3: validate

Command:

```bash
timeout 1200 codd validate --path .
```

Result summary:

```text
ERROR: 651 error(s), 11 blocked issue(s), 386 warning(s), 628 Markdown files checked
[ERROR] codd/design/cmd_save_design.md: node_id 'design:script:cmd-save' is already defined in docs/design/cmd_2762_cmd_save_design.md
[ERROR] codd/design/deploy_task_design.md: node_id 'design:script:deploy-task' is already defined in docs/design/cmd_2762_deploy_task_design.md
[ERROR] codd/design/inbox_write_design.md: node_id 'design:script:inbox-write' is already defined in docs/design/cmd_2762_inbox_write_design.md
[ERROR] codd/design/ninja_monitor_design.md: node_id 'design:script:ninja-monitor' is already defined in docs/design/cmd_2762_ninja_monitor_design.md
[ERROR] docs/archive/mcas.md: missing CoDD YAML frontmatter
[ERROR] docs/governance/adr_batch_yaml_io.md: depended_by references undefined node 'design:system-architecture'
[ERROR] docs/plan/implementation_plan.md: wave_config mismatch for 'plan:implementation-plan'
[ERROR] docs/research/cmd_1991_codd_extract/modules/cmd-1826-memory-analysis.md: circular dependency detected
[WARNING] docs/test/test_strategy.md: conventions references undefined node 'module:health_checks'
EXIT_CODE=1
```

Binary check: PASS for execution/logging (repo-wide validation failure recorded)

### AC4: measure

Command:

```bash
timeout 1200 codd measure --path .
```

Result:

```text
CoDD Project Metrics — Health Score: 0/100

Graph:   16 nodes, 12 edges, 4 orphans, max depth 1
         avg out-degree 0.75, connectivity 0.050
Coverage: 0/0 source files tracked (N/A), 628 design docs
Quality: 628 docs validated (651 errors, 386 warnings)
         0 files policy-checked (0 critical, 0 warnings), 0 rules
EXIT_CODE=0
```

health_score: 0

Binary check: PASS (exit code 0)
