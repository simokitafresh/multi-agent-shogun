# kagemaru CoDD S1: knowledge_metrics.sh

metadata:
- task_id: `cmd_training_codd_s1_kagemaru`
- target: `scripts/knowledge_metrics.sh`
- date: 2026-05-16
- scope: read-only CoDD training analysis. No production code changes.

## 1. Spec Equivalent

### Purpose

`knowledge_metrics.sh` turns lesson injection and reference logs into operational knowledge metrics:

- detect lesson elimination candidates: injected >= threshold and referenced 0 times
- compare CLEAR rate with and without injected lessons, both raw and normalized
- report lesson injection/reference/effectiveness by project and model
- report task duration by ninja/model/task type in `--time` mode
- expose JSON output for downstream dashboard and gate consumers

### Inputs

| Input | Path | Consumer Logic |
| --- | --- | --- |
| lesson tracking TSV | `logs/lesson_tracking.tsv` | main metrics rows: timestamp, cmd_id, ninja, gate_result, injected_ids, referenced_ids, task_type |
| lessons catalog | `projects/*/lessons.yaml` | active/deprecated lessons, injection_count, helpful_count, title, project |
| gate metrics | `logs/gate_metrics.log` | structural BLOCK separation and model/task metadata |
| command archive | `queue/shogun_to_karo.yaml`, `queue/archive/cmds/*.yaml` | cmd_id to project metadata |
| active settings | `config/settings.yaml`, `config/cli_profiles.yaml` | ninja to model family mapping |
| task archives | `queue/tasks/*.yaml`, `archive/tasks/**/*.yaml` | `--time` duration metrics |

### Outputs

| Mode | Output |
| --- | --- |
| default text | elimination candidates, raw delta, normalized delta, top/bottom lessons |
| `--json` | machine-readable metrics for dashboard/gates |
| `--by-project` | project-level injection/reference/effectiveness rates |
| `--by-model` | model-family injection/reference/effectiveness rates |
| `--model` | ninja model CLEAR rates |
| `--time` | task duration averages and slowest task list |

### Constraints

- Missing or empty `logs/lesson_tracking.tsv` must return success with a data-shortage message, not fail the caller.
- Test commands and `ninja=none` rows must be filtered from normalized quality metrics.
- Duplicate cmd rows must be deduplicated with CLEAR preferred.
- Recon/scout rows must be excluded from lesson injection-rate denominator because lesson skip is intentional.
- Deprecated lessons must not appear as elimination candidates.
- Shared cache writes are allowed only for `queue/cmd_project_map_cache.tsv`; operational YAML must not be rewritten by generic YAML dumping.
- WSL2 `/mnt/c` cost matters: repeated full archive scans and repeated process startups should be treated as design risks.

## 2. Elicit / Lexicon Findings

CoDD lexicon surface:

- `codd lexicon list`: installed `shogun_core` with 3 axes.
- `codd coverage report --path . --format md`: PASS but reports 0 axes, so coverage is not currently useful for this target.
- `codd elicit --format md --path .`: FAIL because bundled `shogun_core/manifest.yaml` lacks required `prompt_extension`.

Requirement holes and coverage axes:

| Axis | Gap | Why It Matters |
| --- | --- | --- |
| data freshness | no explicit staleness handling for `cmd_project_map_cache.tsv` when archive files are modified in place | stale cmd->project mapping can distort by-project metrics |
| schema tolerance | TSV parsing assumes first 6 columns and silently skips short rows | malformed rows disappear from denominator with no warning count |
| structural BLOCK taxonomy | `STRUCTURAL_PATTERNS` is a hard-coded list | new structural gate names can inflate quality BLOCK rate |
| cache write ownership | main metrics mode writes `queue/cmd_project_map_cache.tsv` as a side effect | read-only dashboard consumers can unexpectedly mutate queue state |
| output contract | JSON schema is implicit | dashboard/gate consumers can break silently after field changes |
| time mode completeness | `--time` reports "dataなし" when deployed/completed timestamps are absent | not enough signal to distinguish no tasks from missing timestamp instrumentation |
| model normalization | model family extraction is heuristic string parsing | new model labels can be dropped if not in active families |
| test coverage | no direct unit test for `knowledge_metrics.sh` was found | regressions in metrics math rely on integration consumers to catch them |

## 3. CoDD Command Results

`codd spec` is not a standalone command in local CoDD v2.18.0, so §1 is the spec-equivalent artifact required by the task. The executable CoDD steps were run in order: `elicit`, `generate`, `validate`, `measure`, plus `dag verify` as an additional consistency check.

Executed commands:

| Command | Result | Evidence |
| --- | --- | --- |
| `bash -n scripts/knowledge_metrics.sh` | PASS | shell syntax OK |
| `bash scripts/knowledge_metrics.sh --json --by-project --by-model` | PASS | normalized delta +1.5pp, inject_rate 78.0, ref_rate 91.3 |
| `bash scripts/knowledge_metrics.sh --time` | PASS | reports no duration data |
| `codd elicit --path . --format md` | FAIL | bundled `shogun_core/manifest.yaml` lacks required `prompt_extension` |
| `codd generate --path . --wave 1` | PASS | wave_config generated from 11 requirements; generated `docs/governance/adr_batch_yaml_io.md`; skipped `docs/test/acceptance_criteria.md` |
| `codd validate --path .` | PASS | validated 16 Markdown files |
| `codd measure --path . --json` | PASS | health_score 95, validation_errors 0, warnings 0 |
| `codd dag verify --path . --format json` | PASS | all checks passed; `depends_on_consistency` skipped because propagation output was not present |

Design quality score: 7/10.

Rationale:

- Strengths: robust no-data behavior, normalized metrics separate raw noise from quality signal, deprecated lessons excluded, recon/scout denominator rule encoded, JSON mode supports automation, CoDD validate/measure are green.
- Weaknesses: requirements are not captured as CoDD nodes for this script, `elicit` cannot inspect useful axes due lexicon manifest defect, `generate` selected a broader batch-YAML ADR rather than this target script, cache mutation occurs inside a metrics command, and the metrics schema has no explicit contract tests.

## 4. Improvement Candidates

1. Add a fixture-driven unit test for `knowledge_metrics.sh --json`.
   - Include duplicate cmd rows, CLEAR-preferred dedup, test cmd exclusion, `ninja=none` exclusion, recon/scout denominator exclusion, deprecated lesson exclusion, and structural BLOCK exclusion.

2. Split cache mutation from metrics read path.
   - Move `cmd_project_map_cache.tsv` refresh into an explicit subcommand or helper, and allow dashboard/gate consumers to run the metrics command read-only.

3. Replace hard-coded `STRUCTURAL_PATTERNS` with a config-backed taxonomy.
   - Source structural gate names from a maintained config or gate log field so new gate categories do not require script edits.

4. Define a JSON schema for dashboard/gate consumers.
   - Record required fields and types for `elimination_candidates`, `delta`, `normalized_delta`, `by_project`, and `by_model`.

5. Fix CoDD lexicon integration.
   - Add required `prompt_extension` to `shogun_core` manifest or remove the broken selector from current CoDD config, then rerun `codd elicit` to turn this manual hole list into machine-produced findings.

6. Add target-specific CoDD requirements for `knowledge_metrics.sh`.
   - Current `generate --wave 1` derived a governance ADR from existing requirements, not a knowledge-metrics design node. Add `codd/requirements/knowledge_metrics_requirements.md` before rerunning `generate` if this script is to enter the CoDD graph properly.

## 5. Binary AC Check

| AC | Result | Evidence |
| --- | --- | --- |
| AC1 | PASS | target read and spec-equivalent purpose/constraints/scope recorded in this document |
| AC2 | PASS | elicit/lexicon holes and coverage axes listed; `codd elicit` failure recorded as environment/config defect |
| AC3 | PASS | validate/measure results recorded; score 7/10; 5 improvement candidates identified |
