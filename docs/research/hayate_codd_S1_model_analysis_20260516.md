# hayate CoDD S1: model_analysis.sh

metadata:
- task_id: `cmd_training_codd_s1_hayate`
- target: `scripts/model_analysis.sh`
- date: 2026-05-16
- worker: hayate
- method: CoDD pipeline surrogate: spec -> elicit/lexicon -> generate artifact -> validate -> measure

## Spec

`model_analysis.sh` analyzes model performance across gate outcomes and task metadata. It supports human-readable detail output, dashboard summary rows, JSON output, and two-model comparison.

Primary inputs:

| Input | Source | Role |
|---|---|---|
| `--detail` | CLI arg | Print five analysis sections for human review. |
| `--summary` | CLI arg | Print `model_row=...` lines for dashboard integration. |
| `--json` | CLI arg | Emit machine-readable section data. |
| `--compare <model1> <model2>` | CLI arg | Print head-to-head CLEAR rate, trend, and type comparison. |
| `logs/gate_metrics.log` | gate log | Primary source for timestamp, cmd, result, detail, task type, models, and Bloom level. |
| `config/settings.yaml` | config | Current ninja-to-CLI/model mapping. |
| `config/cli_profiles.yaml` | config | Display labels for CLI profile types. |
| `logs/lesson_tracking.tsv` | log | Historical cmd-to-ninja mapping. |
| `logs/ninja_monitor.log` | log | AUTO-DONE/TASK-CLEAR cmd-to-ninja fallback. |
| `logs/deploy_task.log` | log | Deployment complete cmd-to-ninja fallback. |
| `queue/archive/` | archive | Archived inbox, reports, and cmd files for cmd-to-ninja fallback. |

Required behavior:

| Area | Requirement |
|---|---|
| Argument validation | Unknown mode exits 1 with usage; `--compare` requires exactly two model labels. |
| Required data | Missing `logs/gate_metrics.log` exits 1. Optional mapping sources degrade to empty maps. |
| Model normalization | Labels normalize underscores and whitespace; families collapse Opus 4.6 and GPT/Codex 5.4/5.5 variants. |
| Active model filter | Summary output excludes inactive families and `unknown`. |
| Deduplication | Keep the latest gate result per `cmd_id`; sort deduped commands by timestamp for trends. |
| Mapping fallback | Resolve model labels from log column first, then tracking, monitor, deploy log, and archives. |
| Section A | Compute CLEAR rate per model label. |
| Section B | Classify BLOCK reasons into missing gate, lesson, and code quality buckets. |
| Section C | Compute model x task_type matrix plus unknown-task data quality. |
| Section E | Compare recent 20-command CLEAR rate against previous window. |
| Section F | Compute Bloom level x model CLEAR rate. |
| Fast path | `--summary` must avoid Python and use bash/awk for dashboard speed. |

Non-goals:

| Non-goal | Reason |
|---|---|
| Mutating source logs | Analysis is read-only. |
| Full YAML parser in summary path | Summary path is speed-oriented and currently uses awk extraction. |
| Perfect historical attribution | Multiple fallback sources infer cmd-to-ninja when primary columns are absent. |
| Statistical significance testing | Output reports rates and counts, not confidence intervals. |

## Elicit And Lexicon Findings

Vocabulary that must stay explicit:

| Term | Current meaning |
|---|---|
| model label | Display label such as `gpt-5.5 medium fast` or `Opus 4.6 high`. |
| model family | Coarser key such as `gpt_5` or `opus_4_6` used for summary aggregation. |
| active family | Family currently present in `settings.yaml` ninja assignments. |
| deduped command | Latest gate entry per `cmd_id`. |
| task_type | Gate log column used for section C suitability analysis. |
| Bloom level | Gate log column used for section F capability analysis. |
| unknown | Placeholder for missing model or task type after all fallbacks. |

Requirement holes and coverage axes:

| Gap | Evidence | Coverage axis to add |
|---|---|---|
| Model-family logic is duplicated in bash and Python. | Bash `get_family()` and Python `extract_model_family()` encode parallel rules. | Parity fixture: same labels produce same family/slug in summary and JSON modes. |
| Summary path reads only column 6 models, while Python path uses fallback cmd-to-ninja sources. | Summary awk comment says column 6 only; Python merges tracking, monitor, deploy, and archive sources. | Data-source parity axis: missing-model gate rows must have documented summary/detail divergence or shared fallback. |
| Settings parsing in summary is line-based awk. | Summary path extracts `default`, `effort`, agent `type`, `model_name`, and `role` with regexes. | YAML-shape axis: blank lines, reordered keys, quoted values, comments, and nested profile variations. |
| `--compare opus codex` can resolve `codex` to a label with zero samples. | Observed output: `OPUS 4.6 HIGH vs CODEX`, Codex N=0, while active GPT rows exist under `gpt-5.5 medium fast`. | Alias axis: family aliases like `codex`, `gpt`, and `gpt_5` should resolve to active family labels. |
| BLOCK reason taxonomy is coarse and string-fragile. | `classify_block_reason()` checks substrings and defaults to `code_quality`. | Reason taxonomy axis: new gate detail keys must be mapped explicitly or counted as `other_unknown_reason`. |
| Timestamp sorting assumes lexicographic order. | Deduped entries sort by raw timestamp string. | Timestamp format axis: ISO-like format required; malformed timestamps should be detected. |
| Active family filtering can hide historical labels. | Summary excludes labels whose family is not currently active. | Reporting semantics axis: dashboard mode should state active-only scope. |
| Archive parsing scans multiple directories and YAML files. | Python path traverses `queue/archive` inboxes, reports, and cmds. | Performance axis: archive scan upper bound and cold-run timing should be measured on WSL2. |
| `unknown` model is included in detail/json but hidden in summary. | `output_summary()` skips `unknown`; sections A/C/F include it. | Unknown visibility axis: mode differences must be intentional and documented. |
| Error handling is inconsistent across sources. | Missing gate log aborts; optional YAML/log parsing swallows exceptions. | Observability axis: optional-source parse failures should be counted in metadata. |

## Generated Design Artifact

Proposed generated design shape for a future refactor:

| Component | Responsibility |
|---|---|
| `parse_args` | Validate modes and compare operands. |
| `load_settings_model_map` | Parse settings/profile YAML once with PyYAML, then expose labels and active families. |
| `normalize_model` | Single source of truth for label, slug, and family. |
| `load_gate_entries` | Parse `gate_metrics.log`, validate columns, and preserve raw diagnostics. |
| `load_cmd_ninja_sources` | Load tracking, monitor, deploy, and archive mappings with per-source error counts. |
| `resolve_entry_models` | Apply column-first and fallback resolution deterministically. |
| `dedupe_entries` | Keep latest command by parsed timestamp and expose duplicate counts. |
| `compute_sections` | Produce A/B/C/E/F in one shared data model. |
| `render_detail` | Render human table from shared section data. |
| `render_summary` | Render dashboard rows from shared section data, with active-only scope stated. |
| `render_json` | Render the same shared section data as JSON. |
| `render_compare` | Resolve aliases against labels/families and render comparison. |

Minimum fixtures:

| Fixture | Expected result |
|---|---|
| `missing_gate_log` | Exit 1 with explicit path. |
| `compare_missing_arg` | Exit 1 with compare usage. |
| `family_parity` | Bash/summary and Python/json classify the same labels identically. |
| `settings_blank_lines` | Ninja model map survives blank lines and comments. |
| `gate_duplicate_cmd` | Latest timestamp wins. |
| `missing_model_column_with_tracking` | Detail/json resolve model from tracking; summary divergence is documented or fixed. |
| `unknown_task_type` | Section C data quality counts unknown rows. |
| `block_reason_new_key` | Unmapped reason is visible as unknown/other rather than silently code_quality. |
| `compare_codex_alias` | `codex` resolves to active GPT/Codex family when present. |
| `archive_parse_error` | Error count is reported without aborting unrelated analysis. |

## Validate And Measure

Manual design quality score before CoDD validation: 78/100.

Rationale:

| Category | Score | Note |
|---|---:|---|
| Purpose clarity | 18/20 | Five-axis model analysis and dashboard summary use case are clear. |
| Input/output coverage | 16/20 | Primary and fallback sources are enumerated, but optional-source failures are not observable. |
| Consistency | 13/20 | Summary and detail/json use separate implementations with known divergence risk. |
| Testability | 15/20 | Pure computations are identifiable, but current script is monolithic and mixes parsing/rendering. |
| Maintainability | 16/20 | The Python path is structured by section; the bash fast path duplicates core semantics. |

Improvement backlog:

1. Extract model label/family/slug normalization into one reusable implementation and generate summary output from the same semantics, or add parity tests that lock bash and Python behavior together.
2. Add a compare alias resolver that maps `codex`, `gpt`, and `gpt_5` to active GPT/Codex family labels before falling back to literal labels.
3. Replace summary-mode awk parsing of `settings.yaml` and `cli_profiles.yaml` with a generated compact cache or a tested parser that preserves the fast path without YAML-shape fragility.
4. Add source diagnostics to JSON metadata: optional files present/missing, parse errors, archive files scanned, fallback-attributed command count, and unknown-model count.
5. Make BLOCK reason classification table-driven and report unmapped reason keys separately from `code_quality`.
6. Add cold-run performance measurement for `--summary`, `--detail`, and `--json` because archive and YAML scanning costs vary heavily on WSL2.

Executed command results:

| Command | Result |
|---|---|
| `bash -n scripts/model_analysis.sh` | PASS. |
| `bash scripts/model_analysis.sh --summary` | PASS: emitted `model_row=gpt_5_5_medium_fast ... 96.3 ... up 109`. |
| `bash scripts/model_analysis.sh --json >/tmp/hayate_model_analysis.json && python3 -m json.tool /tmp/hayate_model_analysis.json >/dev/null` | PASS: valid JSON. |
| `bash scripts/model_analysis.sh --compare opus codex` | PASS, but revealed alias/data issue: `CODEX` resolved with N=0 while active GPT/Codex samples exist under another label. |
| `/home/simokitafresh/.codd-venv/bin/codd --version` | PASS: `codd, version 2.18.0`. |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: `OK: validated 16 Markdown files under configured doc_dirs`. |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | PASS: `health_score=95`, `validation_errors=0`, `documents_checked=16`, `coverage_ratio=0.0`. |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md --output docs/research/hayate_codd_S1_model_analysis_coverage_20260516.md` | PASS, but totals are `0 axes`; coverage instrumentation is not connected to installed lexicon axes. |
| `/home/simokitafresh/.codd-venv/bin/codd lexicon list` | PASS: installed `shogun_core` with 3 axes. |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | FAIL/tooling gap: bundled `shogun_core` manifest lacks required `prompt_extension`. |

This document is the generated spec/design artifact for AC1-AC3. Coverage output is recorded in `docs/research/hayate_codd_S1_model_analysis_coverage_20260516.md`.
