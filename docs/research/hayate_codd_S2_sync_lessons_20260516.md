# hayate CoDD S2: sync_lessons.sh

metadata:
- task_id: `cmd_training_codd_s2_hayate`
- target: `scripts/sync_lessons.sh`
- date: 2026-05-16
- worker: hayate
- method: CoDD pipeline: spec surrogate -> elicit -> generate -> validate -> measure

## Spec

`sync_lessons.sh` synchronizes a project lesson SSOT Markdown file into generated YAML cache files.

Primary inputs:

| Input | Source | Role |
|---|---|---|
| `project_id` | CLI arg, default `dm-signal` | Selects project config and output paths. |
| `config/projects.yaml` | infra config | Resolves `project_id` to external project path. |
| `tasks/lessons.md` | selected project | SSOT lesson body. |
| `projects/<project_id>/lessons_archive.yaml` | generated cache | Existing score fields and historical lesson details. |
| `projects/<project_id>/lessons.yaml` | generated index | Existing score fallback and compact active index output. |
| `logs/lesson_impact.tsv` | infra log | Project-scoped injection/reference counts. |

Required behavior:

| Area | Requirement |
|---|---|
| Project resolution | Missing project id exits 1 with explicit `config/projects.yaml` error. |
| SSOT validation | Missing SSOT file exits 1 before writing generated YAML. |
| Locking | Writes occur under one `flock -w 10` on `projects/<project_id>/lessons.yaml.lock`. |
| Front matter handling | Only line-isolated `---` front matter markers may be removed. |
| Lesson parsing | Prefer canonical `### LNNN: title` entries when present; avoid ghost entries from structural headings. |
| Metadata extraction | Extract date, source, status, deprecated fields, tags, subdomain, when/how, if/then/because, retired, and target_files. |
| Target file inference | Prefer explicit `target_files`; otherwise infer from lesson text using project/local file cache. |
| Ordering and dedup | Sort newest lesson id first and keep one entry per id. |
| Score preservation | Preserve helpful/harmful/injection/reference/last_referenced from archive first, then index fallback. |
| Project boundary | Count lesson impact rows only when `row.project == project_id`. |
| Output shape | Write full archive and compact active index atomically via temp file + `os.replace`. |
| Postcondition | Warn/notify when SSOT `### L` count diverges from parsed output count. |

Non-goals:

| Non-goal | Reason |
|---|---|
| Manual editing of generated YAML | Output files are generated caches and marked `DO NOT EDIT DIRECTLY`. |
| Updating lesson SSOT | The script only reads SSOT and writes cache/archive. |
| Perfect Markdown parsing | Parser is convention-based around current lesson formats. |
| Network dependency | Only optional local `ntfy_batch.sh` notification is attempted on large divergence. |

## Elicit And Lexicon Findings

Vocabulary that must stay explicit:

| Term | Current meaning |
|---|---|
| SSOT | Project-local `tasks/lessons.md`, the source of lesson truth. |
| archive | Full generated lesson YAML with all parsed fields and scores. |
| index | Compact generated active lesson YAML intended for fast loading. |
| active lesson | Lesson whose status is not `deprecated` and lacks deprecated flag. |
| ghost entry | A false lesson produced from structural Markdown headings. |
| impact counts | Project-scoped injection/reference counts derived from `logs/lesson_impact.tsv`. |

Requirement holes and coverage axes:

| Gap | Evidence | Coverage axis to add |
|---|---|---|
| `yaml.dump` is intentionally used inside this generator, but global rules ban yaml.dump for operational YAML. | The script writes generated cache/archive via `yaml.dump`; AGENTS rule bans `yaml.dump` for `queue/`, tasks, inbox, reports, etc. | Generated-vs-operational YAML boundary axis: verify this script never writes queue/tasks/inbox/report YAML. |
| Output line budget is described as compact `<=500 lines`, but not enforced. | Comment says compact Vercel-style `<=500 lines`; no post-write line-count check exists. | Index-size axis: fail/warn when `lessons.yaml` exceeds retrieval budget. |
| Target file cache may walk large project trees on WSL2. | It recursively scans `scripts/tests/context/config/backend/frontend/docs` for SCRIPT_DIR and PROJECT_PATH. | Cold-run performance axis by project size and filesystem type. |
| `project_id == dm-signal` hard-codes an additional path. | Explicit `/mnt/c/Python_app/DM-signal` fallback is appended. | Project portability axis: non-dm project must not inherit dm-specific scanning. |
| Archive/index score preservation silently ignores YAML parse errors. | `except Exception: continue` around old archive/index load. | Observability axis: parse-error count should be reported. |
| `retired` and `deprecated` semantics are partly distinct. | Active filter checks status/deprecated flag, while index also preserves retired. | Lifecycle-state axis: deprecated, retired, draft, confirmed combinations. |
| Summary extraction is convention-heavy and may absorb unrelated bullet text. | It skips known metadata field names and takes the first two non-table/plain lines. | Summary extraction fixture axis for Japanese metadata and free-form bullets. |
| Divergence notification swallows ntfy errors. | `subprocess.run(...); except Exception: pass`. | Alert delivery axis: record notification failure count without aborting sync. |
| Atomic write does not validate generated YAML after replacement. | Temp files are dumped and replaced, but no post-load verification of both outputs. | Post-write YAML validity axis for archive and index. |
| Existing score merge uses max counts, which may preserve stale inflated counters. | Counts merge by max from archive/index/impact. | Score monotonicity axis: intentional max semantics vs reset/correction workflow. |

## Generated Design Artifact

`codd generate --wave 1 --path .` was executed as required. Because current `codd/codd.yaml` has no `wave_config`, CoDD auto-derived wave configuration from the existing repository requirements, not from the `sync_lessons.sh` spec above.

Observed generate output:

| Result | Detail |
|---|---|
| Auto planning | `wave_config generated from 11 requirement(s)` |
| Skipped | `docs/test/acceptance_criteria.md (test:acceptance-criteria)` |
| Generated | `docs/governance/adr_yaml_batch_operations.md (governance:adr-yaml-batch-operations)` |
| Cleanup | The generated ADR and broad `codd/codd.yaml` normalization were reverted because they were off-target side effects unrelated to `sync_lessons.sh`. |

Proposed generated design shape for a future `sync_lessons.sh` refactor:

| Component | Responsibility |
|---|---|
| `resolve_project_path` | Parse `config/projects.yaml` and return project path for one id. |
| `load_ssot_body` | Read SSOT and strip only line-isolated front matter. |
| `build_target_file_cache` | Build bounded filename/path cache with project-specific scan limits. |
| `parse_lesson_entries` | Parse canonical and legacy headings into raw lesson dicts. |
| `extract_lesson_metadata` | Extract status/date/source/tags/subdomain/when/how/if_then/target_files. |
| `dedupe_and_sort_lessons` | Keep explicit ids, newest first, one lesson per id. |
| `load_existing_scores` | Load archive/index scores and expose parse diagnostics. |
| `merge_impact_counts` | Apply project-scoped lesson impact data. |
| `render_archive` | Generate full detail YAML. |
| `render_index` | Generate compact active index and enforce retrieval line budget. |
| `write_atomic_yaml` | Dump, reload-validate, and `os.replace` under flock. |
| `check_postconditions` | Count SSOT/output divergence, output line budget, parse diagnostics, and notification status. |

Minimum fixtures:

| Fixture | Expected result |
|---|---|
| `missing_project` | Exit 1 with explicit project id. |
| `missing_ssot` | Exit 1 before touching output files. |
| `front_matter_midline_dashes` | Mid-line `---` in lesson text does not truncate body. |
| `canonical_l_style_only` | Structural headings are ignored when `### LNNN:` entries exist. |
| `legacy_numbered_lessons` | Legacy `## N. title` entries still parse. |
| `explicit_target_files` | Explicit target_files wins over inference. |
| `auto_target_files` | Known basename/path in lesson text is inferred. |
| `project_boundary_impact` | `lesson_impact.tsv` rows for other projects are ignored. |
| `archive_score_preservation` | helpful/harmful/reference scores survive sync. |
| `corrupt_archive` | Sync continues but reports old-cache parse diagnostic. |
| `index_line_budget` | Oversized compact index emits warning or fails gate. |
| `post_write_yaml_validity` | Both generated YAML files reload successfully after replace. |

## Validate And Measure

Manual design quality score: 80/100.

| Category | Score | Note |
|---|---:|---|
| Purpose clarity | 18/20 | SSOT -> archive/index generation is clear. |
| Input/output coverage | 17/20 | Core inputs/outputs are explicit, but optional old-cache parse errors are invisible. |
| Consistency | 15/20 | Atomic writes and project boundary handling are good; lifecycle state semantics need clearer coverage. |
| Testability | 16/20 | Existing bats cover several parser/index behaviors; missing failure/diagnostic fixtures remain. |
| Maintainability | 14/20 | Single embedded Python block mixes parsing, score merge, rendering, and notification. |

Improvement backlog:

1. Split the embedded Python into pure functions for SSOT loading, lesson parsing, score merge, rendering, and postcondition checks so fixtures can target each unit.
2. Add post-write `yaml.safe_load` validation for both archive and index before reporting success.
3. Enforce or report the compact index line budget instead of leaving `<=500 lines` as a comment.
4. Surface old archive/index parse errors and ntfy notification failures in command output.
5. Add cold-run timing benchmarks for large project trees on WSL2, especially target file cache construction.
6. Remove or configure the `dm-signal` hard-coded fallback path so project-specific scan roots live in config.
7. Add lifecycle fixtures covering `deprecated`, `retired`, `draft`, and conflicting combinations.

Executed command results:

| Command | Result |
|---|---|
| `/home/simokitafresh/.codd-venv/bin/codd spec --help` | FAIL/tooling fact: `Error: No such command 'spec'`; spec was recorded manually in this document. |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | FAIL/tooling gap: `LexiconLoadError`, bundled `shogun_core/manifest.yaml` lacks required `prompt_extension`. |
| `/home/simokitafresh/.codd-venv/bin/codd generate --wave 1 --path .` | PASS command execution: generated off-target `docs/governance/adr_yaml_batch_operations.md` from existing requirements; off-target side effects were reverted. |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS after cleanup: `OK: validated 16 Markdown files under configured doc_dirs`. |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | PASS after cleanup: `health_score=95`, `validation_errors=0`, `documents_checked=16`, `coverage_ratio=0.0`. |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md --output docs/research/hayate_codd_S2_sync_lessons_coverage_20260516.md` | PASS, but totals are `0 axes`; coverage instrumentation is not connected to installed lexicon axes. |
| `bash -n scripts/sync_lessons.sh` | PASS. |
| `bats tests/unit/test_sync_lessons.bats` | PASS: 6 tests, 0 failed, 0 skipped. |

This document is the spec/design/validation artifact for AC1-AC3. Coverage output is recorded in `docs/research/hayate_codd_S2_sync_lessons_coverage_20260516.md`.
