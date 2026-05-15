# hayate CoDD R1: cmd_complete_gate.sh

metadata:
- task_id: `cmd_training_codd_r1_hayate`
- target: `scripts/cmd_complete_gate.sh`
- date: 2026-05-16
- worker: hayate
- method: CoDD pipeline surrogate: spec -> elicit/lexicon -> generate artifact -> validate -> measure

## Spec

`cmd_complete_gate.sh` is the command-completion orchestration gate. It accepts one `cmd_*` id, locks per command, short-circuits already-cleared commands unless `--force` is supplied, resolves matching task/report YAML, validates completion evidence, records loop metrics, and runs post-clear automation.

Primary inputs:

| Input | Source | Role |
|---|---|---|
| `CMD_ID` | CLI arg | Completion target. Must match `cmd_*`. |
| command YAML | `queue/shogun_to_karo.yaml` | Source of command metadata, project, title, status. |
| task YAMLs | `queue/tasks/*.yaml` | Matching tasks are selected by `parent_cmd: CMD_ID`. |
| report YAMLs | `queue/reports/` | Evidence source for each matching ninja. |
| gate flags | `queue/gates/{CMD_ID}/` | Required gate state: `lesson`, deferred `archive`, and conditional gates. |
| git history | repo HEAD commits | Changed files, review freshness, scope drift, CoDD registry data. |

Required behavior:

| Area | Requirement |
|---|---|
| Argument safety | Missing or non-`cmd_*` args must exit 1. |
| Concurrency | Per-cmd `flock` must prevent duplicate completion processing. |
| Idempotency | Existing CLEAR in `logs/gate_metrics.log` must exit 0 unless `--force`. |
| Report resolution | Prefer task `report_filename`, then `queue/reports/{ninja}_report_{cmd}.yaml`, then legacy report only if `parent_cmd` matches. |
| Preflight | Generate missing review/lesson/report_merge flags only where safe; `archive` remains deferred until after report reading. |
| Blocking checks | Missing report after completed task, invalid report format, bad `lessons_useful`, bad `lesson_candidate`, binary check failure, `purpose_validation.fit=false`, test skip count >0, broken Vercel references, and CDP production failure must block. |
| Warning checks | Workarounds, CoDD regression, CI red, scope drift, review staleness, partial completion, WTF likelihood, skill/decision candidate issues, and some context/PD checks are non-blocking by design. |
| Clear side effects | On CLEAR: log metrics, update status/changelog/lesson impact, run semantic/context freshness updates, append CoDD registry, run `codd propagate --update`, notify shogun/gunshi/karo, archive, idle matching tasks, and push if needed. |
| Block side effects | On BLOCK: notify karo/gunshi, log quality metrics, update lesson impact, generate failure lessons where applicable, and print actionable reasons. |

Non-goals:

| Non-goal | Reason |
|---|---|
| Full unit replacement of downstream scripts | This gate delegates to existing scripts and should not duplicate their internal assertions. |
| Silent pass on malformed report YAML | Report format is an explicit quality boundary. |
| Preflight archive creation | Archive depends on reports being read by this script first. |

## Elicit And Lexicon Findings

Vocabulary that must stay explicit:

| Term | Current meaning |
|---|---|
| L1 | Existence or required artifact checks. |
| L2 | Substantive report or evidence checks. |
| L3 | Integration checks against broader system state. |
| CLEAR | All blocking gates pass and post-clear side effects are allowed. |
| BLOCK | At least one blocking reason was recorded. |
| WAIT | Report is absent but task is still assigned/acknowledged/in_progress, so completion waits before declaring missing. |
| Deferred gate | A required gate that is intentionally checked after CLEAR work, currently `archive`. |

Requirement holes and coverage axes:

| Gap | Evidence | Coverage axis to add |
|---|---|---|
| Report resolver has mixed shell/Python parsing and legacy fallback rules. | `resolve_report_file()` contains auto-unwrapping plus old-format parent matching. | Fixture matrix for explicit filename, new format, old matching, old stale, wrapped `report:` YAML, and missing report. |
| `purpose_validation` lookup uses `field_get "$report_file" "fit"` while reports store `purpose_validation.fit`. | Lines around purpose validation read top-level `fit`; prior reports use nested structure. | Nested-field fixture proving fit=false blocks and fit=true passes. |
| Binary check parser accepts `PASS/YES/TRUE`, while task/report convention says `yes/no`. | AWK normalizes uppercase values. | Lexicon decision: accepted values for binary checks must be defined once. |
| Preflight lesson gate mutates `lesson.done` with direct `echo >` writes. | `preflight_gate_flags()` upgrades source to `lesson_write` using shell redirection. | YAML/file-write safety axis for gate flag format and atomicity. |
| CLEAR path has many background jobs but only a final `wait`; several jobs are best-effort and failures are hidden. | semantic, context, lesson impact, dashboard, gist, CI, deprecate jobs are async/non-blocking. | Side-effect observability axis: required vs best-effort jobs and failure visibility. |
| CoDD registry append infers before/after measurements from report text. | `append_codd_registry_entry()` scans strings with regex. | Measurement provenance axis: explicit report fields preferred over prose extraction. |
| CI push detection checks for `git push|files_modified` in reports. | Any report with `files_modified` can set `CI_PUSH_DETECTED=true`. | Push evidence axis separating local file changes from actual remote push. |
| Large script has repeated matching-task loops. | Many loops over `MATCHING_TASK_FILES` mutate processed counters repeatedly. | Performance axis for one-pass collection vs repeated validation passes. |

## Generated Design Artifact

Proposed generated design shape for future refactor:

| Component | Responsibility |
|---|---|
| `collect_cmd_context` | Resolve command metadata, matching tasks, reports, changed files, project, and task types once. |
| `validate_reports` | Return structured blocking/warning findings for report existence, format, lessons, AC version, binary checks, purpose, candidates, and test skips. |
| `validate_integrations` | Run context, Vercel, CDP, CoDD, CI, scope, review, and drift checks as typed findings. |
| `preflight_flags` | Generate only safe pre-check flags and declare deferred gates. |
| `emit_clear_effects` | Execute post-clear effects with required/best-effort classification. |
| `emit_block_effects` | Execute block notifications, logs, and lesson feedback. |
| `render_gate_summary` | Print L1/L2/L3 status from structured findings. |

Minimum fixtures:

| Fixture | Expected result |
|---|---|
| `assigned_task_no_report` | WAIT, not immediate BLOCK. |
| `done_task_no_report` | BLOCK `report_yaml_missing`. |
| `wrapped_report_yaml` | Auto-unwrap or explicit normalize result. |
| `purpose_validation_fit_false_nested` | BLOCK. |
| `binary_checks_no` | BLOCK unless another worker has PASS in double-deploy case. |
| `test_results_skipped_1` | BLOCK. |
| `lesson_candidate_found_true_no_lesson_done` | WARN plus karo reminder, not CLEAR as registered. |
| `clear_post_effect_archive_deferred` | archive runs after report validation. |

## Validate And Measure

Manual design quality score before CoDD validation: 82/100.

Rationale:

| Category | Score | Note |
|---|---:|---|
| Purpose clarity | 18/20 | Completion gate responsibility is clear. |
| Input/output coverage | 16/20 | Main files are known, but side-effect ordering is implicit in code. |
| Blocking semantics | 18/20 | Many explicit `record_block_reason` calls exist. |
| Testability | 13/20 | Behavior is fixtureable, but current monolith requires heavy integration tests. |
| Maintainability | 17/20 | Helpers exist, but repeated loops and mixed parsers raise risk. |

Improvement backlog:

1. Extract a structured `cmd_context` snapshot so task/report/project/git data is computed once and reused by all checks.
2. Replace ad hoc report field reads with one YAML-aware helper call per report, especially for nested `purpose_validation.fit`.
3. Add Bats fixtures for report resolver, purpose validation, binary checks, test skip count, deferred archive, and double-deploy downgrade behavior.
4. Split post-clear side effects into required and best-effort groups with machine-readable result logging.
5. Replace prose regex extraction for CoDD registry before/after measurements with explicit report fields.
6. Separate actual push evidence from `files_modified` so CI status checks are not triggered by local-only reports.

Executed command results:

| Command | Result |
|---|---|
| `bash -n scripts/cmd_complete_gate.sh` | PASS. |
| `codd validate --path .` | PASS: `OK: validated 16 Markdown files under configured doc_dirs`. |
| `codd measure --path . --json` | PASS: `health_score=95`, `validation_errors=0`, `documents_checked=16`. |
| `codd coverage report --path . --format md --output docs/research/hayate_codd_R1_cmd_complete_gate_coverage_20260516.md` | PASS, but totals are `0 axes`, so coverage instrumentation is not connected to installed lexicon axes. |
| `codd lexicon list` | PASS: installed `shogun_core` with 3 axes. |
| `codd elicit --format md --path . --lexicon shogun_core` | FAIL/tooling gap: bundled `shogun_core` manifest lacks required `prompt_extension`. |
| `codd plan --path .` | FAIL/tooling gap: `codd.yaml` lacks `wave_config`; direct `codd generate` would mutate project generation state, so this document is the generated design artifact for the task. |

CoDD command results are also recorded in the task report. This document is the generated spec/design artifact for AC1-AC3.

## 追完ループ4: codd extract/validate/measure (2026-05-16)

### AC1: extract

| コマンド | Exit | 結果 |
|---|---:|---|
| `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd extract --path .` | 0 | `Extracted: 0 modules from 0 files (0 lines)`; `Output: .codd/extract/`; generated `system-context.md` and `architecture-overview.md` |

Extract output:

- `.codd/extract/system-context.md`
- `.codd/extract/architecture-overview.md`

### AC2: validate

| コマンド | Exit | 結果 |
|---|---:|---|
| `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd validate --path .` | 1 | `ERROR: 651 error(s), 11 blocked issue(s), 386 warning(s), 628 Markdown files checked` |

代表的な検出内容:

- node_id重複: `codd/design/cmd_save_design.md` と `docs/design/cmd_2762_cmd_save_design.md` などで `design:script:*` / `req:script:*` が重複。
- 既存governance文書の未定義参照: `docs/governance/adr_batch_yaml_io.md` が `design:system-architecture` / `detailed:yaml-io-library` を参照。
- 既存docs/research群のCoDD YAML frontmatter欠落が多数。
- 既存extract群に circular dependency と reciprocal reference warning が多数。

### AC3: measure

| コマンド | Exit | health_score | 結果 |
|---|---:|---:|---|
| `timeout 1200 /home/simokitafresh/.codd-venv/bin/codd measure --path .` | 0 | 0/100 | `Graph: 16 nodes, 12 edges, 4 orphans, max depth 1`; `Coverage: 0/0 source files tracked (N/A), 628 design docs`; `Quality: 628 docs validated (655 errors, 386 warnings)` |

Binary checks:

| AC | Check | Result |
|---|---|---|
| AC1 | `timeout 1200 codd extract --path .` を実行し、結果を本ファイル末尾に追記した | yes |
| AC2 | `timeout 1200 codd validate --path .` を実行し、結果を本ファイル末尾に追記した | yes |
| AC3 | `timeout 1200 codd measure --path .` を実行し、health_score=0/100を本ファイル末尾に追記した | yes |
