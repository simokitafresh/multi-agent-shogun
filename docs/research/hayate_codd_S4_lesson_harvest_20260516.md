# hayate CoDD S4: lesson_harvest.sh

metadata:
- task_id: `cmd_training_codd_s4_hayate`
- target: `scripts/lesson_harvest.sh`
- date: 2026-05-16
- worker: hayate
- method: CoDD pipeline: spec command attempt -> elicit -> generate -> validate -> measure

## Spec

`lesson_harvest.sh` scans archived ninja reports and lists lesson candidates that have not yet been registered in project lesson indexes.

Primary inputs:

| Input | Source | Role |
|---|---|---|
| archived reports | `queue/archive/reports/*_report_*.yaml` | Source of `lesson_candidate` blocks. |
| project lessons | `projects/**/lessons.yaml`, `projects/**/lessons_archive.yaml` | Registered title set for deduplication. |
| cache | `/tmp/lesson_harvest_{hash}.pkl` | Warm cache for parsed archive scan data. |
| `rg` | executable dependency | Fast line extraction for report and lesson title fields. |
| PyYAML | Python dependency | Fallback parse for block scalars and stringified dict candidates. |

Required behavior:

| Area | Requirement |
|---|---|
| Archive existence | Missing archive directory exits 1 with a clear error. |
| Dependency check | Missing `rg` exits 1 before Python scan. |
| Registered dedup | Titles already in project lesson indexes are not emitted. |
| Lesson-only extraction | `skill_candidate` and other sections must not be counted as lessons. |
| YAML fallback | Block scalars, list/dict candidates, and stringified dicts must be parsed through fallback logic. |
| Cache correctness | Warm cache must match archive mtime key before reuse. |
| Output contract | No candidates prints `未登録候補なし`; otherwise prints count, divider, and `cmd | worker | title | detail`. |

Non-goals:

| Non-goal | Reason |
|---|---|
| Registering lessons | This script only harvests candidates; Karo owns official lesson registration. |
| Editing report archives | Archived reports are source data and must remain unchanged. |
| Full semantic deduplication | Dedup is title-based; fuzzy duplicate analysis belongs to a separate review flow. |

## Elicit And Coverage Findings

`codd elicit --format md --path . --lexicon shogun_core` failed before target analysis because the installed `shogun_core` manifest lacks `prompt_extension`. Manual hole analysis and coverage axes follow.

| Gap | Evidence | Coverage axis to add |
|---|---|---|
| Cache key uses archive directory mtime only. | `_scan_cache_key()` returns `archive_dir.stat().st_mtime`. | Archive content axis: changed child file content should invalidate cache. |
| Registered title dedup is exact string match only. | `if title in registered_titles`. | Duplicate axis: normalized whitespace/quote variants should be measured. |
| Fallback parser silently skips YAML parse failures. | `load_report_fallback()` returns `None` on exception. | Diagnostics axis: corrupt reports should produce a count or warning. |
| Detail truncation can hide distinguishing data. | `detail.replace("\n", " ")[:60]`. | Output usefulness axis: title/detail should preserve enough evidence for Karo review. |
| Cache write failures are swallowed. | `_save_scan_cache()` catches all exceptions and passes. | Cache observability axis: cache disabled/failing should be visible in debug mode. |
| Report section state parser is line-oriented. | `_REPORT_LINE_RE` plus `row["section"]`. | Parser drift axis: nested or reordered report schemas should be tested. |
| Registered lessons scan reads every lessons file. | `rg -uuu ... projects_dir`. | Scope axis: archived/irrelevant projects should be intentionally included or excluded. |

CoDD coverage result:

| Command | Result |
|---|---|
| `codd coverage report --path . --format md --output docs/research/hayate_codd_S4_lesson_harvest_coverage_20260516.md` | PASS, but totals are `0 axes, 0 covered signals`. Coverage instrumentation is not connected to installed lexicon axes. |

## Generated Design Artifact

Actual CoDD command execution:

| Command | Result |
|---|---|
| `codd spec --help` | FAIL/tooling fact: local CoDD v2.18.0 has no `spec` subcommand. This document is the spec artifact. |
| `codd elicit --format md --path . --lexicon shogun_core` | FAIL/tooling gap: `LexiconLoadError`, manifest missing `prompt_extension`. |
| `codd generate --wave 1 --path .` | PASS command execution; `wave_config` was auto-generated from 11 existing requirements, but wave 1 generated 0 target-specific files and skipped 2 existing docs. |
| `codd validate --path .` after generate | FAIL while generated config expanded scan to broad `docs/`; 649 errors and 382 warnings. |
| Config cleanup | Restored `codd/codd.yaml` to pre-generate tracked content because generate rewrote scan scope. |
| `codd validate --path .` after cleanup | PASS: `OK: validated 16 Markdown files under configured doc_dirs`. |
| `codd dag verify --path . --format json` | PASS overall; `depends_on_consistency` skipped because propagation output was absent; `runtime:db_seed:users` unreachable amber remained pass. |
| `codd measure --path . --json` after cleanup | PASS: `health_score=95`, `validation_errors=0`, `validation_warnings=0`, `documents_checked=16`. |

Target design shape:

| Component | Responsibility |
|---|---|
| shell preflight | Resolve repo paths, verify archive directory and `rg`. |
| registered title loader | Extract lesson titles from active/archive lesson indexes. |
| archive scanner | Run one `rg` pass over archived reports and build per-report candidate rows. |
| fallback detector | Detect raw scalars that require YAML loading. |
| fallback YAML loader | Parse complex report candidates safely. |
| cache key | Decide whether cached scan data is usable. |
| output renderer | Emit stable candidate lines or the no-candidate message. |

Minimum fixtures:

| Fixture | Expected result |
|---|---|
| no_archive_dir | Exit 1 with archive path. |
| missing_rg | Exit 1 before Python scan. |
| registered_title | Candidate suppressed. |
| block_scalar_detail | Fallback YAML load preserves title and detail. |
| skill_candidate_only | No lesson candidate emitted. |
| stringified_dict_candidate | Extracts content/summary/title from dict-like scalar. |
| child_file_changed_cache | Cache invalidates when archived report content changes. |
| corrupt_report_yaml | Warning/count is emitted instead of silent skip. |

## Validate And Measure

Manual target design quality score: 82/100.

| Category | Score | Note |
|---|---:|---|
| Purpose clarity | 18/20 | Harvest-only scope and output contract are clear. |
| Input/output coverage | 17/20 | Main archive, lessons, cache, and fallback paths are covered. |
| Consistency | 16/20 | Title dedup is deterministic but exact-match only. |
| Testability | 17/20 | Existing bats cover core candidate extraction and fallback behavior. |
| Maintainability | 14/20 | Embedded Python is structured, but cache invalidation and diagnostics are under-specified. |

Improvement backlog:

1. Replace archive-directory mtime cache key with child file mtime/content metadata so modified reports invalidate correctly.
2. Add a debug or summary count for fallback YAML parse failures and skipped malformed reports.
3. Normalize title whitespace and quote variants before deduplication to reduce near-duplicate lesson candidates.
4. Add tests for stringified dict candidates and cache invalidation after archived report content changes.
5. Add an optional `--project` or `--limit` filter for large harvest reviews while keeping default full scan.
6. Preserve more detail evidence in output, or add a `--verbose` mode for full candidate context.

Executed command results:

| Command | Result |
|---|---|
| `/home/simokitafresh/.codd-venv/bin/codd --version` | PASS: `codd, version 2.18.0`. |
| `bash -n scripts/lesson_harvest.sh` | PASS. |
| `/home/simokitafresh/.codd-venv/bin/codd spec --help` | EXPECTED_TOOLING_FAIL: `Error: No such command 'spec'`. |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | TOOLING_FAIL: `LexiconLoadError`, manifest missing `prompt_extension`. |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md --output docs/research/hayate_codd_S4_lesson_harvest_coverage_20260516.md` | PASS, but 0 axes / 0 covered signals. |
| `/home/simokitafresh/.codd-venv/bin/codd generate --wave 1 --path .` | PASS command execution; wave 1 generated 0 files, skipped 2 existing docs, and rewrote `codd/codd.yaml` until restored. |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS after cleanup: `OK: validated 16 Markdown files under configured doc_dirs`. |
| `/home/simokitafresh/.codd-venv/bin/codd dag verify --path . --format json` | PASS with one skipped consistency check and one amber unreachable node that did not fail. |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | PASS after cleanup: `health_score=95`, `validation_errors=0`, `validation_warnings=0`, `documents_checked=16`. |
| `/usr/bin/time -f ... bash scripts/lesson_harvest.sh >/tmp/hayate_lesson_harvest_s4.out` | PASS: `real=6.16 user=2.26 sys=2.00 maxrss=56736`, output listed 598 unregistered candidates. |
| `bats tests/unit/test_lesson_harvest.bats` | PASS: 3 tests, 0 failed, 0 skipped. |

This document is the spec/design/validation artifact for AC1-AC5. Coverage output is recorded in `docs/research/hayate_codd_S4_lesson_harvest_coverage_20260516.md`.
