# hayate CoDD S3: lesson_deprecation_scan.sh

metadata:
- task_id: `cmd_training_codd_s3_hayate`
- target: `scripts/lesson_deprecation_scan.sh`
- date: 2026-05-16
- worker: hayate
- method: CoDD pipeline: spec command attempt -> elicit -> generate -> validate -> measure

## Spec

`lesson_deprecation_scan.sh` scans project lesson indexes and identifies lessons that should be deprecated or reviewed. It can auto-retire confirmed candidates unless `--candidates-only` is supplied.

Primary inputs:

| Input | Source | Role |
|---|---|---|
| `--project dm-signal|infra|all` | CLI arg, default `all` | Limits project set. |
| `--candidates-only` | CLI arg | Disables auto-retirement side effects. |
| `config/projects.yaml` | infra config | Provides project ids, paths, and archived status. |
| `projects/<project>/lessons.yaml` | lesson index | Active/deprecated lessons plus scores. |
| `logs/lesson_tracking.tsv` | tracking log | Last referenced cmd per project/lesson. |
| `logs/lesson_impact.tsv` | impact log | Injection/helpful counts by project/lesson. |
| `queue/shogun_to_karo.yaml` | active cmd queue | cmd -> project map for active commands. |
| `queue/archive/cmds/*.yaml` | archived cmd queue | cmd -> project map cache source. |
| `queue/cmd_project_map_cache.tsv` | generated cache | Speeds archive cmd project lookup. |

Required behavior:

| Area | Requirement |
|---|---|
| Argument validation | Unknown arg exits 1; `--project` without value exits 1. |
| Project filtering | Unknown project exits 1; `all` scans every configured project. |
| Project boundary | Lesson tracking and impact counts must be keyed by `(project_id, lesson_id)`. |
| Deprecated skip | Already deprecated lessons must not be reprocessed. |
| Archived project candidates | Lessons in archived projects are confirmed deprecation candidates. |
| Missing file candidates | Explicit referenced repo paths that no longer exist become confirmed candidates. |
| Review candidates | Existing `.sh` references become review-only candidates, not auto-retired. |
| Effectiveness candidates | Injection/helpful counts use `MAX(YAML, TSV)` to avoid stale-cache false positives. |
| Auto-retirement | Without `--candidates-only`, confirmed missing-file and low-effectiveness candidates call `lesson_deprecate.sh`. |
| Safe reason | Auto-retire reasons are single-line sanitized and capped. |
| Checkpoint | Highest seen lesson id is written to `queue/lesson_deprecation_checkpoint.txt`. |

Non-goals:

| Non-goal | Reason |
|---|---|
| Human final judgment for review candidates | Script only prints review material. |
| Deleting lessons | Deprecation marks lessons; it does not erase history. |
| Full YAML archive parse for every archived cmd | Archive cmd lookup uses text scan + persistent cache for speed. |
| Auto-retiring existing-script references | Existing scripts may indicate structural prevention, so these stay review-only. |

## Elicit And Lexicon Findings

Vocabulary that must stay explicit:

| Term | Current meaning |
|---|---|
| confirmed candidate | Candidate eligible for automatic deprecation when not in candidates-only mode. |
| review candidate | Candidate printed for Karo judgment only. |
| effectiveness rate | helpful_count / injection_count, using project-aware `MAX(YAML, TSV)` counts. |
| project boundary | Same lesson id in different projects must be counted independently. |
| candidates-only mode | Read/scan/report mode that skips calls to `lesson_deprecate.sh`. |
| checkpoint | Highest lesson id seen during the scan. |

Requirement holes and coverage axes:

| Gap | Evidence | Coverage axis to add |
|---|---|---|
| `--candidates-only` still writes checkpoint. | Observed run printed `Checkpoint updated: L613`. | Side-effect axis: candidates-only should document or suppress checkpoint writes. |
| Auto-retirement path is high-risk and not isolated behind a dry-run default. | Default execution can call `lesson_deprecate.sh`. | Safety axis: require explicit `--apply` for mutation, or test default no-mutation expectations. |
| Missing-file detection treats explicit refs as confirmed, but path scope is broad. | `find_file_refs` matches scripts/queue/config/projects/logs/context/tasks/docs paths. | Path classification axis: generated/cache/log references vs source-code references. |
| Existing script references produce many review candidates with no last reference. | `--project infra --candidates-only` produced dozens of review candidates with `参照なし`. | Review noise axis: rank by last reference, injection count, or current structural enforcement. |
| Archive cache has no invalidation on changed archived YAML contents. | Cache stores filename set, not mtime/content hash. | Cache invalidation axis: modified archive file must refresh cmd -> project map. |
| `lesson_tracking.tsv` parser only accepts `cmd_<digits>`. | `cmd_training_*` and suffixed ids are ignored. | Cmd id format axis: training/custom cmd ids should be intentionally excluded or handled. |
| `lesson_deprecate.sh` failures are WARN only and script still exits 0. | Auto loop prints WARN to stderr without failing. | Mutation failure axis: auto-retire failure should affect exit status or summary count. |
| YAML parse failures for project lessons are not surfaced. | Non-dict data is silently skipped. | Input diagnostics axis: missing/corrupt lessons.yaml should be reported. |
| `project_status == archived` can auto-retire all lessons for an archived project. | Confirmed candidate logic does not require additional impact checks. | Archived project policy axis: archived status should be explicit in report before mutation. |
| Checkpoint writes are not atomic. | `open(..., "w")` writes checkpoint directly. | Atomic checkpoint axis: temp + replace or flock. |

## Generated Design Artifact

Actual CoDD command execution:

| Command | Result |
|---|---|
| `codd spec --help` | Failed: local CoDD v2.18.0 has no `spec` subcommand. This document is the spec artifact. |
| `codd elicit --format md --path . --lexicon shogun_core` | Failed with `LexiconLoadError`: bundled `shogun_core` manifest lacks required `prompt_extension`. |
| `codd generate --wave 1 --path .` | Completed command execution, but generated wave_config from existing repo requirements instead of this target spec. It skipped `docs/test/acceptance_criteria.md` and `docs/governance/adr_batch_yaml_io.md`; no target-specific document was generated. |
| `codd validate --path .` | Passed before generate; failed immediately after generate because `codd/codd.yaml` doc_dirs expanded to `docs/`; passed again after cleanup. |
| `codd measure --path . --json` | Passed after cleanup with `health_score=95`, `validation_errors=0`, `documents_checked=16`. |

Proposed generated design shape for a future refactor:

| Component | Responsibility |
|---|---|
| `parse_args` | Validate project filter and mutation mode. |
| `load_project_config` | Return project metadata and roots. |
| `load_cmd_project_map` | Build active + archive cmd map with cache invalidation metadata. |
| `load_tracking_references` | Parse reference history with explicit cmd-id policy. |
| `load_impact_counts` | Compute project-aware injection/helpful counts, excluding PENDING. |
| `load_lessons` | Load project lesson indexes with diagnostics. |
| `classify_missing_file_candidates` | Confirm explicit missing source refs. |
| `classify_review_candidates` | Produce existing-script review candidates with ranking metadata. |
| `classify_effectiveness_candidates` | Apply injection/helpful thresholds. |
| `render_report` | Print metrics, confirmed, review, effectiveness, and mutation summary. |
| `apply_deprecations` | Call `lesson_deprecate.sh` only in explicit mutation mode and aggregate failures. |
| `write_checkpoint` | Atomically write highest seen lesson id. |

Minimum fixtures:

| Fixture | Expected result |
|---|---|
| `unknown_project` | Exit 1 with project id in stderr. |
| `candidates_only_no_deprecate` | No `lesson_deprecate.sh` call. |
| `candidates_only_checkpoint_policy` | Checkpoint behavior is locked by test. |
| `cross_project_same_lesson_id` | Counts do not leak across projects. |
| `yaml_tsv_max_counts` | Higher of YAML/TSV injection/helpful counts is used. |
| `pending_impact_rows` | PENDING rows do not affect counts. |
| `missing_file_confirmed` | Explicit missing source path becomes confirmed candidate. |
| `existing_script_review_only` | Existing `.sh` reference is review-only. |
| `archive_cache_modified_file` | Modified archive YAML refreshes cmd->project cache. |
| `lesson_deprecate_failure` | Mutation failure is reflected in summary and exit policy. |

## Validate And Measure

Manual design quality score: 81/100.

| Category | Score | Note |
|---|---:|---|
| Purpose clarity | 18/20 | Candidate classes and mutation mode are visible. |
| Input/output coverage | 16/20 | Core logs/configs are covered; corrupt input diagnostics are weak. |
| Consistency | 16/20 | Project-aware counts and MAX(YAML, TSV) are strong; checkpoint side effect needs clearer policy. |
| Testability | 17/20 | Existing bats cover cross-project, MAX counts, PENDING, and candidates-only. |
| Maintainability | 14/20 | Single embedded Python block combines cache, parsing, classification, mutation, and reporting. |

Improvement backlog:

1. Make mutation explicit with `--apply` and keep default/candidates-only fully read-only, including checkpoint policy.
2. Add cache invalidation by archive file mtime or content hash, not filename presence only.
3. Surface corrupt/missing project `lessons.yaml` diagnostics in output.
4. Make `lesson_deprecate.sh` failures affect exit status or a machine-readable failure count.
5. Split embedded Python into testable functions for cmd map, tracking, impact counts, classification, rendering, mutation, and checkpoint write.
6. Rank review candidates by recent reference, injection count, and structural enforcement evidence to reduce review noise.
7. Use atomic write for `queue/lesson_deprecation_checkpoint.txt`.

Executed command results:

| Command | Result |
|---|---|
| `/home/simokitafresh/.codd-venv/bin/codd spec --help` | FAIL/tooling fact: `Error: No such command 'spec'`; manual spec artifact created here. |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | FAIL/tooling gap: `LexiconLoadError`, bundled manifest lacks `prompt_extension`. |
| `/home/simokitafresh/.codd-venv/bin/codd generate --wave 1 --path .` | PASS command execution; no target-specific document generated, wave 1 skipped two existing docs, and `codd/codd.yaml` side effect was cleaned up. |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS after cleanup: `OK: validated 16 Markdown files under configured doc_dirs`. |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | PASS after cleanup: `health_score=95`, `validation_errors=0`, `documents_checked=16`, `coverage_ratio=0.0`. |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md --output docs/research/hayate_codd_S3_lesson_deprecation_scan_coverage_20260516.md` | PASS, but totals are `0 axes`; coverage instrumentation is not connected to installed lexicon axes. |
| `bash -n scripts/lesson_deprecation_scan.sh` | PASS. |
| `bats tests/unit/test_lesson_deprecation_scan.bats` | PASS: 4 tests, 0 failed, 0 skipped. |
| `bash scripts/lesson_deprecation_scan.sh --project infra --candidates-only` | PASS: `total_lessons=608`, `active_lessons=572`, `deprecated_lessons=36`; confirmed/effectiveness auto candidates none; review candidates printed; auto-retire skipped; checkpoint updated to `L613`. |

This document is the spec/design/validation artifact for AC1-AC5. Coverage output is recorded in `docs/research/hayate_codd_S3_lesson_deprecation_scan_coverage_20260516.md`.
