# kagemaru CoDD S2: context_freshness_check.sh

metadata:
- task_id: `cmd_training_codd_s2_kagemaru`
- target: `scripts/context_freshness_check.sh`
- date: 2026-05-16
- scope: CoDD training analysis and design documentation. No production code changes.

## 1. Spec Equivalent

`codd spec` is not available in local CoDD v2.18.0 (`Error: No such command 'spec'`). This section records the required spec-equivalent design for `context_freshness_check.sh`.

### Purpose

`context_freshness_check.sh` detects stale project context files and emits warning lines for dashboard and command-specific flows.

Supported modes:

| Mode | Purpose |
| --- | --- |
| `--dashboard-warnings` | warn for stale context files belonging to projects with recent completed work |
| `--cmd-warnings <cmd_id>` | infer the command project, then warn for stale context files for that project |

### Inputs

| Input | Path / Source | Role |
| --- | --- | --- |
| project registry | `config/projects.yaml` | active project IDs and explicit context file mapping |
| context files | `context/*.md` plus configured files | `last_updated` freshness source |
| command chronicle | `context/cmd-chronicle.md` | fast recent-project detection and cmd->project lookup |
| active command queue | `queue/shogun_to_karo.yaml` | cmd->project lookup for active commands |
| archived commands | `queue/archive/cmds/*.yaml` | fallback project and completion-date lookup |
| archive cache | `CFC_ARCHIVE_CACHE` | precomputed archive metadata from dashboard flow |
| env controls | `CONTEXT_STALE_DAYS`, `CFC_OUTPUT_CACHE_TTL` | freshness threshold and output cache TTL |

### Constraints

- Must not fail when optional archive/chronicle inputs are absent; warnings may be empty.
- Must preserve bounded I/O on WSL2 `/mnt/c`: use chronicle/cache first and archive scan fallback only when needed.
- Must exclude intentionally exempt context files (`README.md`, checklist docs, CDP docs).
- Must infer unlisted `context/*.md` as `infra` when infra is active.
- Must de-duplicate warning lines before output.
- Must cache output by root, mode, cmd, threshold, archive-cache path, exclude list, and current date.

## 2. Elicit / Lexicon Findings

Executed command:

| Command | Result | Evidence |
| --- | --- | --- |
| `codd elicit --path . --format md` | FAIL | bundled `shogun_core/manifest.yaml` lacks required `prompt_extension` |

Manual requirement holes and coverage axes:

| Axis | Gap | Why It Matters |
| --- | --- | --- |
| cache correctness | output cache key includes archive-cache path but not archive-cache file mtime/content | dashboard warnings can stay stale for up to TTL after upstream cache changes |
| parser robustness | `config/projects.yaml` and command YAML are parsed line-by-line | nested YAML shape changes can silently drop project/context mappings |
| date source precedence | chronicle freshness suppresses archive scan entirely when any chronicle row is fresh | recent archive commands missing from chronicle can be ignored |
| warning contract | output is free-form text only | dashboard consumers have no structured project/path/days fields |
| error visibility | broad `except Exception` blocks often collapse to empty results | malformed inputs can look like "no stale context" |
| mode coverage | no explicit fixture test was found for both modes and cache paths | regressions in project inference or stale-day threshold may escape |

## 3. Generate / Validate / Measure Results

Executed commands:

| Command | Result | Evidence |
| --- | --- | --- |
| `bash -n scripts/context_freshness_check.sh` | PASS | shell syntax OK |
| `bash scripts/context_freshness_check.sh --dashboard-warnings` | PASS | emitted stale context warnings, including `context/infrastructure.md last_updated 16日前` |
| `bash scripts/context_freshness_check.sh --cmd-warnings cmd_training_codd_s2_kagemaru` | PASS | no warnings because this training cmd is not present in active/archive command metadata |
| `codd spec --path . scripts/context_freshness_check.sh` | FAIL | local CoDD v2.18.0 has no `spec` command |
| `codd elicit --path . --format md` | FAIL | `shogun_core` manifest missing `prompt_extension` |
| `codd generate --path . --wave 1` | PASS | wave_config generated from 11 requirements; `docs/test/acceptance_criteria.md` and `docs/governance/adr_batch_yaml_io.md` skipped; 0 generated |
| `codd validate --path .` | PASS | validated 16 Markdown files |
| `codd measure --path . --json` | PASS | health_score 95, validation_errors 0, validation_warnings 0, coverage_ratio 0.0 |
| `codd dag verify --path . --format json` | PASS | checks passed; `depends_on_consistency` skipped because propagation output was missing |

Design quality score: 7/10.

Rationale:

- Strengths: bounded archive scan design, dashboard cache integration, defensive no-input behavior, and clear two-mode CLI.
- Weaknesses: line parsers are fragile, warning output is unstructured, cache invalidation is TTL-only, CoDD graph lacks target-specific requirements, and elicit is blocked by lexicon config.

## 4. Improvement Candidates

1. Add fixture tests for both modes.
   - Cover explicit `context_file`, `context_files`, infra fallback, exclude list, missing `last_updated`, stale threshold, and cmd->project lookup from active queue/archive.

2. Add structured output mode.
   - Provide `--json` with fields `{project, path, days_old, reason}` while preserving current text output for dashboard compatibility.

3. Make cache invalidation content-aware.
   - Include archive-cache mtime or checksum and relevant config/context mtimes in the output cache key, or disable output cache for command-specific mode.

4. Replace project and command YAML line parsing with a safe YAML parser where feasible.
   - Use `yaml.safe_load` for config and bounded targeted reads for archive files to reduce silent parser drift.

5. Surface malformed input counts.
   - Track parse failures and emit a WARN summary or JSON diagnostics so broken metadata does not become a false clean result.

6. Add target-specific CoDD requirements.
   - Create `codd/requirements/context_freshness_check_requirements.md` before rerunning `codd generate`; current generation only sees existing generic requirements.

## 5. Binary AC Check

| AC | Result | Evidence |
| --- | --- | --- |
| AC1 | PASS | `codd spec` failure recorded; spec-equivalent purpose, constraints, and scope generated in this document |
| AC2 | PASS | `codd elicit` executed; failure recorded; manual requirement holes and coverage axes listed |
| AC3 | PASS | `codd generate` executed; 0 generated / 2 skipped result recorded |
| AC4 | PASS | `codd validate` and `codd dag verify` executed and recorded |
| AC5 | PASS | `codd measure` executed; health_score 95 recorded; 6 improvements identified |
