# cmd_training_codd_r1_kagemaru: report_field_set.sh CoDD Spec

date: 2026-05-16
worker: kagemaru
target: `scripts/report_field_set.sh`
pipeline: spec -> elicit/lexicon -> generate -> validate -> measure

## 1. Spec

### Purpose

`scripts/report_field_set.sh` is the safe write boundary for ninja report YAML.
It updates one report field at a time through flock-protected atomic replacement,
validates high-risk field values before write, preserves template structure, and
prevents internally inconsistent reports such as `binary_checks` containing `no`
while `verdict` is written as `PASS`.

The core product requirement is not "write YAML"; it is "make invalid operational
reports hard or impossible to produce while keeping common report updates fast."

### Scope

- Accept CLI shape `<report_path> <dot.notation.key> <value>`, with `-` meaning stdin.
- Resolve relative report paths against the repository root.
- Permit empty scalar values and multi-line values without direct file editing.
- Use fast awk paths for root and 2-level scalar updates.
- Fall back to Python for list/dict values, array indexes, and multi-line values.
- Hold a per-report flock while preparing backup, writing temp file, replacing atomically,
  and validating YAML parseability.
- Validate `lessons_useful`, `binary_checks`, `lesson_candidate`,
  `knowledge_candidate`, `self_gate_check`, and `verdict` before write.
- Normalize common mechanical mistakes such as `PASS`/`FAIL` result aliases in
  `binary_checks`, string paths in `files_modified`, and dict-vs-list confusion in
  `lessons_useful`.
- Auto-complete `status: completed` in the same lock scope when `verdict` is written.
- Restore from backup if post-write YAML parsing fails.

### Non-scope

- It does not decide task quality; gates and reviewers consume the resulting report.
- It does not create the task assignment or the report template.
- It does not own inbox notification; ninja completion still uses `inbox_write.sh`.
- It does not rewrite arbitrary queue YAML. It is scoped to report YAML.
- It does not run tests for the changed work; it only records the reported evidence.

## 2. Elicit / Lexicon Findings

`codd elicit --format md --path .` could not run because the configured
`shogun_core` lexicon manifest was not found. Therefore this section combines
code reading, existing CoDD records, and lexicon-style coverage axes.

| ID | Hole / Coverage Axis | Evidence | Impact |
| --- | --- | --- | --- |
| GAP-1 | Template absence behavior is implicit | The script touches a missing report path and can build a minimal YAML file, while ninja recovery says report templates are mandatory | A missing deploy-generated template can be silently converted into an under-specified report unless gates catch it later |
| GAP-2 | Fast path safety contract is not expressed as a requirement | `_report_field_set_fast_scalar()` has separate root and 2-level awk implementations | Future speed edits can bypass structure preservation or block scalar cleanup if not tied to fixtures |
| GAP-3 | Validation rules are embedded in shell/Python rather than a data model | Field-specific checks are hard-coded in `_validate_field_value()` | Adding a new report field requires code archaeology to know whether it needs pre-write validation |
| GAP-4 | Autofix boundaries are not formally defined | Mechanical fixes are allowed for report shape, but semantic problems still BLOCK | A future autofix could cross from syntax normalization into hiding task failure |
| GAP-5 | Verdict/status atomicity is a critical invariant but not a CoDD node | `verdict` write also updates `status` under the same flock | Regression would recreate an intermediate `verdict`-set / `status`-pending state |
| GAP-6 | Missing-report path and mandatory template policy conflict is not surfaced early | The current R1 `report_path` did not exist before this task | The safest behavior is ambiguous: fail immediately or let `report_field_set.sh` create and gate later |
| GAP-7 | Python fallback still uses `yaml.dump` internally | It is guarded by round-trip validation and scoped to report YAML, but global policy bans yaml.dump for ops YAML | Maintainers need an explicit exception rationale or a future rewrite target |
| GAP-8 | Post-write semantic warnings are advisory for some cases | `binary_checks` quality warnings print after write instead of always blocking | Low-quality check text can reach review if not caught by later gates |

Recommended lexicon axes:

- `report_template_mandatory_boundary`
- `report_scalar_fast_path_preserves_structure`
- `report_structured_field_validation_matrix`
- `report_autofix_syntax_not_semantics`
- `verdict_status_atomic_transition`
- `binary_checks_verdict_consistency`
- `report_yaml_dump_exception_scope`

## 3. Generate / Design Sketch

The design should be represented as a small CoDD node set:

- Requirement: "Report YAML writes must go through a single flock-protected helper."
- Requirement: "Report templates are mandatory; missing template behavior must be explicit."
- Constraint: "Autofix may normalize mechanical format only; it must not hide failed ACs."
- Constraint: "`verdict` and terminal `status` update must be atomic."
- Constraint: "`binary_checks` results must be `yes` or `no`, and any `no` forces `verdict=FAIL`."
- Test fixture: scalar root update preserves surrounding fields.
- Test fixture: nested scalar update removes old block scalar continuation.
- Test fixture: multiline and list writes round-trip as valid YAML.
- Test fixture: `bc:no` plus attempted `verdict=PASS` becomes FAIL or blocks.
- Test fixture: missing report path behavior matches the chosen template policy.

## 4. Validate / Measure Evidence

Commands run from `/mnt/c/tools/multi-agent-shogun`:

| Command | Result |
| --- | --- |
| `bash -n scripts/report_field_set.sh` | PASS |
| `codd validate --path .` | PASS: 16 Markdown files validated |
| `codd measure --path . --json` | PASS: health_score=95, validation_errors=0, validation_warnings=0, total_nodes=16, total_edges=12, orphan_nodes=4, coverage_ratio=0.0 |
| `codd dag verify --path . --format json` | PASS: all checks passed; `depends_on_consistency` skipped because propagation output was not found; `runtime:db_seed:users` unreachable but amber/pass |
| `codd coverage report --path . --format md` | FAIL: Unknown lexicon `shogun_core` |
| `codd elicit --format md --path .` | FAIL: lexicon manifest not found: `shogun_core` |

## 5. Design Score

Score: 7 / 10.

Rationale:

- Strong safety boundary: report writes are centralized, flocked, parsed after write,
  and protected by backups.
- Strong learning-loop enforcement: high-risk fields have pre-write checks and
  `binary_checks`/`verdict` contradiction is structurally prevented.
- Strong operational performance: scalar hot paths avoid full Python work for common updates.
- Good blast-radius control: helper is report-scoped and does not edit arbitrary queue state.
- Weak CoDD coverage: project measure reports 0 tracked source files and 0.0 coverage ratio.
- Weak template contract: missing report path behavior is not reconciled with the mandatory
  report template rule.
- Medium maintainability risk: validation/autofix policy is embedded in a long shell script
  with several Python snippets rather than a declarative schema.

## 6. Improvement Candidates

1. Decide and encode missing-template behavior. If templates are mandatory, `report_field_set.sh`
   should refuse to create a missing report unless an explicit bootstrap mode is used.
2. Extract report field validation rules into a small schema table or shared Python module, then
   have `report_field_set.sh` call that validator.
3. Add fixture tests for verdict/status atomicity, missing report template behavior, block scalar
   replacement, and `binary_checks` semantic warnings.
4. Add a CoDD requirement/design document for `report_field_set.sh` that records the allowed
   `yaml.dump` exception scope or replaces the Python fallback with a round-trip-preserving writer.
5. Fix CoDD lexicon configuration for `shogun_core` so `coverage report` and `elicit` can run
   during L4 training without environment failure.

## 7. Binary Checks

| AC | Check | Result |
| --- | --- | --- |
| AC1 | `report_field_set.sh` was read and a spec-like purpose, constraints, and scope were recorded in this file | yes |
| AC2 | Elicit/lexicon-style requirement holes and coverage axes were listed despite the current lexicon command failure | yes |
| AC3 | `validate`, `measure`, and related CoDD checks were run; design quality was scored and at least three improvements were identified | yes |

## 8. CoDD Generate Results

実行者: kagemaru
日付: 2026-05-16
task_id: `cmd_training_codd_loop2_kagemaru`
対象: `scripts/report_field_set.sh`

### AC1: generate

コマンド:

```bash
timeout 1200 codd generate --wave 1 --force --path .
```

結果:

```text
Generated: docs/test/acceptance_criteria.md (test:acceptance-criteria)
Generated: docs/governance/adr_yaml_batch_operations.md (governance:adr-yaml-batch-operations)
Wave 1: 2 generated, 0 skipped
```

観察: generateは成功し、2件生成・0件skipだった。ただし生成された2件はいずれも既存requirements/wave_config由来の汎用CoDD文書であり、`scripts/report_field_set.sh`専用の追加設計ではなかった。task ACは「既存md末尾に結果追記、別ファイル禁止」なので、生成物は副作用として記録し、最終成果物には含めない。

### AC2: validate

コマンド:

```bash
timeout 1200 codd validate --path .
```

結果:

```text
ERROR: 658 error(s), 11 blocked issue(s), 386 warning(s), 628 Markdown files checked
```

主な失敗:

| 種別 | 例 |
|---|---|
| duplicate node_id | `codd/design/*` と `docs/design/cmd_2762_*` の重複 |
| missing frontmatter | `docs/research/*.md`、`docs/future/*.md` など広範 |
| undefined node | `docs/governance/adr_batch_yaml_io.md` の `design:system-architecture` など |
| wave_config mismatch | `docs/plan/implementation_plan.md`、`docs/research/cmd_2589_codd_acceptance_criteria.md` |
| circular dependency | `docs/research/cmd_1991_codd_extract/modules/*` |

判定: FAIL。現行`codd/codd.yaml`が`docs/`全体をdoc_dirsに含めているため、`report_field_set.sh`単体のvalidateではなく、既存Markdown群全体のCoDD整合性不備を検出している。

### AC3: measure

コマンド:

```bash
timeout 1200 codd measure --path . --json
```

結果:

```json
{
  "health_score": 0,
  "graph": {
    "total_nodes": 16,
    "total_edges": 12,
    "orphan_nodes": 4,
    "max_depth": 1,
    "avg_out_degree": 0.75,
    "connectivity": 0.05
  },
  "coverage": {
    "tracked_files": 0,
    "source_files": 0,
    "design_documents": 628,
    "coverage_ratio": 0.0
  },
  "quality": {
    "validation_errors": 663,
    "validation_warnings": 386,
    "policy_critical": 0,
    "policy_warnings": 0,
    "documents_checked": 628,
    "files_policy_checked": 0,
    "rules_applied": 0
  }
}
```

health_score: 0

### 追完結論

`codd generate --wave 1 --force`は正常終了し、2件生成・0件skipだった。一方で、このR1 report_field_set成果物はCoDD requirements/wave_configに接続されておらず、生成結果は`report_field_set.sh`専用の追補ではなく汎用CoDD文書生成になった。validate/measureは`docs/`全体scanによりFAIL/health_score 0であり、次にやるべきことは`report_field_set.sh`専用requirement nodeとwave_configを作る、または追完訓練用のdoc_dirsを対象成果物に絞ることである。
