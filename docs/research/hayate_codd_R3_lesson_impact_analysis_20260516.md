# hayate CoDD R3: lesson_impact_analysis.sh

metadata:
- task_id: `cmd_training_codd_r3_hayate`
- target: `scripts/lesson_impact_analysis.sh`
- date: 2026-05-16
- worker: hayate
- method: CoDD pipeline surrogate: spec -> elicit/lexicon -> generate artifact -> validate -> measure

## Spec

`lesson_impact_analysis.sh` analyzes `logs/lesson_impact.tsv` and reports whether injected lessons are referenced and associated with CLEAR/BLOCK outcomes. It also supports detail view for one lesson and optional synchronization of helpful/harmful counters back into `projects/*/lessons.yaml`.

Primary inputs:

| Input | Source | Role |
|---|---|---|
| impact TSV | `logs/lesson_impact.tsv` | Event source: timestamp, lesson_id, action, result, referenced, task_type, model. |
| lesson files | `projects/*/lessons.yaml` | Summary lookup and sync target for counters. |
| CLI args | `--detail LESSON_ID`, `--sync-counters`, `--dry-run` | Select summary/detail/sync mode and write behavior. |
| PyYAML | Python import | Required for lesson summary loading and sync mode. |

Required behavior:

| Area | Requirement |
|---|---|
| Argument parsing | Unknown args exit with usage; `--detail` requires a lesson id. |
| Row loading | Ignore rows without lesson_id, unsupported actions, and `PENDING` results. |
| Summary mode | Print period, injection totals, top injected lessons, low reference candidates, high BLOCK candidates, never referenced lessons, and A/B comparison. |
| Detail mode | Print summary, injected/reference counts, CLEAR/BLOCK rates, model/task type distribution, and A/B result for one lesson. |
| Sync mode | Count referenced injected lessons only; CLEAR increments helpful, BLOCK increments harmful; optionally update `projects/*/lessons.yaml`. |
| Dry-run | Must not write lesson files, but should show intended updates clearly. |
| Empty data | Must produce meaningful no-data output rather than crashing. |

Non-goals:

| Non-goal | Reason |
|---|---|
| Statistical proof | A/B significance is explicitly heuristic. |
| Editing lessons outside `projects/*/lessons.yaml` | Sync target is project lesson files only. |
| Treating withheld lessons as helpful/harmful | Counters are based on referenced injected lessons only. |

## Elicit And Lexicon Findings

Vocabulary that must stay explicit:

| Term | Current meaning |
|---|---|
| injected | Lesson was provided to a task. |
| withheld | Lesson was in comparison population but not injected. |
| referenced | Worker reported the lesson as used. |
| helpful | Referenced injected lesson associated with CLEAR. |
| harmful | Referenced injected lesson associated with BLOCK. |
| ref_rate | `referenced_count / injected`. |
| CLEAR rate | `inj_clear / injected` or `with_clear / withheld`. |

Requirement holes and coverage axes:

| Gap | Evidence | Coverage axis to add |
|---|---|---|
| `--sync-counters` writes operational YAML via `yaml.dump`. | `sync_counters()` truncates and `yaml.dump(data, f, ...)`. | YAML write safety axis: operational lesson YAML must use sanctioned helper or round-trip-safe writer. |
| `--dry-run` still prints `SYNC:` lines, then a final dry-run summary. | Dry-run execution output shows many `SYNC:` rows. | UX axis distinguishing `WOULD_SYNC` from actual `SYNC`. |
| File locking is per lesson file handle, but no temp-file replace is used. | `f.seek(0); f.truncate(); yaml.dump(...)`. | Atomicity axis for partial-write failure and concurrent readers. |
| `safe_date()` compares date strings only. | Last timestamp is truncated to date. | Timestamp precision axis for same-day ordering. |
| A/B significance is heuristic but prints `p<0.05`. | `sig:*` label text says p<0.05 without statistical test. | Metrics honesty axis: replace with threshold label unless real test is implemented. |
| `load_lesson_summaries()` only reads `data.get("lessons", [])`. | Some role lesson files may use different schema. | Schema coverage axis for role-specific lesson YAML shapes. |
| Summary high BLOCK candidates include 0% BLOCK when all rows are CLEAR. | Sorting over all injected lessons with no minimum block count. | Candidate filtering axis: suppress zero-harm rows or label as no harm candidates. |
| Missing TSV silently returns empty summary. | `load_rows()` returns empty rows for absent file. | Preflight axis: distinguish no data from successful zero-impact period. |

## Generated Design Artifact

Proposed generated design shape for future refactor:

| Component | Responsibility |
|---|---|
| `load_impact_events` | Parse TSV into typed events with rejected-row diagnostics. |
| `compute_lesson_stats` | Produce per-lesson counters and rates. |
| `render_summary` | Human-readable summary report. |
| `render_detail` | Human-readable single-lesson detail. |
| `plan_counter_sync` | Build intended changes without touching files. |
| `apply_counter_sync` | Apply changes atomically through an approved YAML writer. |
| `render_sync_plan` | Print `WOULD_SYNC` for dry-run and `SYNC` only for real writes. |

Minimum fixtures:

| Fixture | Expected result |
|---|---|
| `empty_tsv` | Summary prints zero totals and no candidates. |
| `pending_rows` | PENDING rows excluded. |
| `referenced_clear` | helpful increments in sync plan. |
| `referenced_block` | harmful increments in sync plan. |
| `withheld_only` | Does not update helpful/harmful counters. |
| `dry_run_sync` | No file mutation and output uses dry-run wording. |
| `yaml_write_failure` | Existing lesson file remains intact. |
| `zero_block_candidates` | High BLOCK section does not imply harm where BLOCK=0. |

## Validate And Measure

Manual design quality score before CoDD validation: 80/100.

Rationale:

| Category | Score | Note |
|---|---:|---|
| Purpose clarity | 18/20 | Impact analysis objective is clear. |
| Input/output coverage | 17/20 | TSV and lesson YAML inputs are explicit. |
| Safety semantics | 12/20 | Sync mode violates operational YAML write rule via `yaml.dump`. |
| Testability | 16/20 | Pure Python functions are fixtureable, but current implementation is embedded in shell heredoc. |
| Maintainability | 17/20 | Small enough to understand, but summary/detail/sync/writes are coupled. |

Improvement backlog:

1. Replace `yaml.dump` write path with an approved safe writer or text-preserving update helper for `projects/*/lessons.yaml`.
2. Make sync two-phase: compute plan, print plan, then apply atomically only when not dry-run.
3. Rename dry-run output from `SYNC:` to `WOULD_SYNC:` to prevent operational confusion.
4. Add rejected-row counters to summary so malformed TSV data is visible.
5. Filter high BLOCK candidates to rows with at least one BLOCK or label the section as sorted by BLOCK rate.
6. Replace `sig:* p<0.05` wording with `threshold:*` unless a real statistical test is implemented.

Executed command results:

| Command | Result |
|---|---|
| `bash -n scripts/lesson_impact_analysis.sh` | PASS. |
| `bash scripts/lesson_impact_analysis.sh` | PASS: summary printed period `2026-05-14 ~ 2026-05-15`, total injections `470`, unique lessons `181`. |
| `bash scripts/lesson_impact_analysis.sh --sync-counters --dry-run` | PASS as dry-run: printed planned updates; no writes intended. UX gap: rows say `SYNC:` even in dry-run. |
| `codd validate --path .` | PASS: `OK: validated 16 Markdown files under configured doc_dirs`. |
| `codd measure --path . --json` | PASS: `health_score=95`, `validation_errors=0`, `documents_checked=16`, `coverage_ratio=0.0`. |
| `codd coverage report --path . --format md --output docs/research/hayate_codd_R3_lesson_impact_analysis_coverage_20260516.md` | PASS, but totals are `0 axes`; coverage instrumentation is not connected to installed lexicon axes. |
| `codd lexicon list` | PASS: installed `shogun_core` with 3 axes. |
| `codd elicit --format md --path . --lexicon shogun_core` | FAIL/tooling gap: bundled `shogun_core` manifest lacks required `prompt_extension`. |
| `codd plan --path .` | FAIL/tooling gap: `codd.yaml` lacks `wave_config`; direct `codd generate` would mutate project generation state, so this document is the generated design artifact for the task. |

This document is the generated spec/design artifact for AC1-AC3. Full CoDD measure/coverage/elicit results are recorded after command execution in the task report.
