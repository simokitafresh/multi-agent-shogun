# cmd_training_L4_codd_c5: checklist_progress.sh CoDD spec

date: 2026-05-16
worker: kagemaru
target: `scripts/checklist_progress.sh`
mode: CoDD training L4 cycle 5

## 1. Spec-like purpose

`checklist_progress.sh` is a read-only progress summarizer for Markdown checklist files.
It receives one checklist path, resolves it relative to the repository root when needed,
counts completed items and total checklist items, and prints a compact progress line.

Expected output shape:

```text
<done>/<total> (<integer_percent>%)[ | <ninja>:<count> ...]
```

## 2. Constraints and scope

In scope:

- Require exactly one path argument; missing argument exits with usage text.
- Resolve relative paths from the multi-agent-shogun repository root.
- Fail fast when the target file does not exist.
- Read the target as UTF-8 text.
- Count Markdown checkbox rows: `- [x]` and `- [X]` are done; `- [ ]` is pending.
- Count Markdown table rows as checklist rows when cells contain status signals:
  - Done signals: `✅`, `PASS`, `DONE`, `O`, `OK`
  - Non-done checklist signals: `FAIL`, `NG`, `TODO`, `PENDING`, `SKIP`
- Treat table rows as per-ninja attributable when they have at least 9 columns; the current owner is read from column index 7.
- Floor percentage with integer conversion.
- Produce no persistent writes.

Out of scope:

- Updating checklist status; that belongs to `scripts/checklist_update.sh`.
- Repairing malformed Markdown.
- Validating a formal checklist schema.
- Explaining why a checklist has zero detected items.
- Running agent or dashboard side effects.

## 3. Elicit / requirements holes

The current script expresses behavior directly in parser code, but CoDD has no dedicated
requirement or design node for this tool. That leaves these holes:

1. Table separator contract is implicit and fragile. `is_separator()` uses
   `r'^\|[-:\s|]+\$'`, which appears to match a literal dollar sign rather than a normal
   Markdown table separator ending in `|`. If this is intentional, the reason is undocumented;
   if not, ordinary tables may silently count as zero.
2. Table column schema is undocumented. The 8th cell (`cells[7]`) is treated as the ninja
   owner when `len(cells) >= 9`, but neither header names nor column order are validated.
3. Status taxonomy is undocumented. `O` is a done signal, `SKIP` is a checklist signal but not
   a done signal, and the interaction with the global rule "SKIP = FAIL" is not specified here.
4. Failure visibility is weak. A malformed table or separator mismatch can produce `0/0 (0%)`
   without warning, which hides parser drift.
5. Output schema is unversioned. Downstream consumers must parse a human-oriented string and
   can break if optional owner counts change.
6. Mixed markdown support is incomplete by design but not documented: checkbox rows have no
   owner attribution, while table rows do.
7. Percentage rounding is floor-based, but no requirement declares whether floor, round, or
   decimal precision is expected.

Recommended lexicon axes:

- `checklist_table_separator_contract`
- `checklist_status_taxonomy`
- `checklist_column_schema`
- `checklist_skip_is_fail`
- `checklist_output_schema`
- `checklist_parser_failure_visibility`

## 4. Generate / validation-oriented design sketch

The behavior should be represented by a CoDD node set like:

- Requirement: "Given a Markdown checklist, compute completed and total actionable rows."
- Constraint: "SKIP must be counted as not completed and must remain visible as incomplete."
- Constraint: "Table parsing must accept standard Markdown separator rows."
- Constraint: "Per-owner counts require an explicit owner column contract."
- Test fixture: standard table with PASS/TODO/SKIP rows.
- Test fixture: checkbox-only checklist.
- Test fixture: malformed table separator should emit a warning or documented zero behavior.

The minimal generated test matrix should include:

| Case | Input | Expected |
| --- | --- | --- |
| checkbox_done_pending | `- [x] A`, `- [ ] B` | `1/2 (50%)` |
| table_standard_separator | PASS/TODO rows under `| --- |` | table rows counted |
| skip_row | SKIP status | total increments, done does not |
| owner_column | row with 9+ cells and owner at index 7 | owner count increments |
| malformed_table | separator not detected | warning or documented zero |

## 5. CoDD command evidence

Commands run from `/mnt/c/tools/multi-agent-shogun`:

- `bash -n scripts/checklist_progress.sh`: PASS.
- `codd validate --path .`: PASS, 16 Markdown files validated.
- `codd measure --path . --json`: health_score 95.
- `codd dag verify --path . --format json`: PASS, with `depends_on_consistency` skipped because propagation output was not found.
- `codd coverage report --path . --format md`: 0 axes, 0 covered signals, 0.00%.
- `codd elicit --format md --path .`: FAIL before analysis because `shogun_core/manifest.yaml` lacks required `prompt_extension`.

## 6. Design score

Score: 6 / 10.

Rationale:

- The tool has a compact operational purpose and a small blast radius.
- Read-only behavior is simple and safe.
- Parser contracts are embedded in code instead of CoDD requirements.
- Standard Markdown table separator detection appears suspect.
- No source coverage or lexicon axes exist for this behavior.
- Silent zero-count behavior can hide checklist regressions.

Top improvements:

1. Add a CoDD requirement/design node for `checklist_progress.sh` with explicit table schema,
   status taxonomy, and SKIP semantics.
2. Add fixture tests for standard Markdown tables, checkbox lists, SKIP rows, and owner counts.
3. Fix or document the separator regex; normal Markdown separators should not be silently missed.
4. Add a machine-readable output mode such as JSON for gates and dashboards.
5. Emit warnings for files that contain table-like content but no recognized checklist rows.

## 7. 追完ループ2結果: cmd_training_codd_loop2_hayate

### AC1: generate

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

### AC2: validate

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

Binary check: PASS for execution/logging (exit code 1 was expected and recorded as repo-wide validation failure per AC2)

### AC3: measure

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
Quality: 628 docs validated (653 errors, 386 warnings)
         0 files policy-checked (0 critical, 0 warnings), 0 rules
EXIT_CODE=0
```

health_score: 0

Binary check: PASS (exit code 0)
