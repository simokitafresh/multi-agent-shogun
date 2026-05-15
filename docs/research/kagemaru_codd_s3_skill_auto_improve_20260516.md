# kagemaru CoDD S3: skill_auto_improve.sh

metadata:
- task_id: `cmd_training_codd_s3_kagemaru`
- target: `scripts/skill_auto_improve.sh`
- date: 2026-05-16
- scope: CoDD training analysis and design documentation. No production code changes.

## 1. Spec Equivalent

`codd spec` is not available in local CoDD v2.18.0 (`Error: No such command 'spec'`). This section records the required spec-equivalent design for `skill_auto_improve.sh`.

### Purpose

`skill_auto_improve.sh` reads skill execution failures and converts recurring FAIL patterns into deterministic SKILL.md prevention steps. In `--apply` mode it writes new auto-prevention lines and tracks unresolved patterns for code-fix escalation.

### Inputs

| Input | Default / Source | Role |
| --- | --- | --- |
| skill log | `logs/skill_execution_log.yaml` | FAIL source data |
| skill directories | `skills`, `~/.codex/skills`, `~/.claude/skills` | target `SKILL.md` discovery |
| gate fix hints | `scripts/gates/gate_report_format_main.py` | concrete fix-hint generation |
| escalation state | `logs/skill_auto_improve_state.json` | unchanged streak tracking |
| bulletin writer | `scripts/bulletin_write.sh` | code-fix escalation channel |

### Constraints

- Must be dry-run by default; `--apply` is required for file mutation.
- Must avoid duplicate auto-prevention markers with stable SHA1 marker IDs.
- Must map `gate_report_format` failures to `report-write`.
- Must preserve skill file structure and insert under `### 自動防止ステップ` when present.
- Must classify repeated unchanged patterns as code-fix-required after threshold.
- Must cache parsed log entries by log mtime and size to reduce YAML load cost.

## 2. Elicit / Lexicon Findings

Executed command:

| Command | Result | Evidence |
| --- | --- | --- |
| `codd elicit --path . --format md` | FAIL | bundled `shogun_core/manifest.yaml` lacks required `prompt_extension` |

Manual requirement holes and coverage axes:

| Axis | Gap | Why It Matters |
| --- | --- | --- |
| mutation safety | `--apply` can edit skill files across three roots | needs explicit fixture coverage for scope filtering and duplicate marker behavior |
| cache correctness | log cache key uses only mtime and size | same-size rewrite with preserved mtime can reuse stale entries |
| escalation idempotency | bulletin notification state is separate from bulletin write success semantics | repeated failures can be under- or over-notified if state write fails |
| parser tolerance | YAML load failures collapse to empty execution list | malformed logs can look like "no failures" |
| insertion quality | heading heuristics decide insertion point | unusual SKILL.md structures can receive prevention lines in confusing sections |
| classification quality | code-fix-required is keyword and unchanged-streak based | false positives possible for skill-doc-fixable patterns that already have marker collision |

## 3. Generate / Validate / Measure Results

Executed commands:

| Command | Result | Evidence |
| --- | --- | --- |
| `bash -n scripts/skill_auto_improve.sh` | PASS | shell syntax OK |
| `bash scripts/skill_auto_improve.sh --top 1 --dry-run` | PASS | emitted top FAIL rows for cmd-complete, dashboard-update, report-write, verdict-check |
| `codd spec --path . scripts/skill_auto_improve.sh` | FAIL | local CoDD v2.18.0 has no `spec` command |
| `codd elicit --path . --format md` | FAIL | `shogun_core` manifest missing `prompt_extension` |
| `codd generate --path . --wave 1` | PASS | wave_config generated from 11 requirements; 0 generated; `docs/test/acceptance_criteria.md` and `docs/governance/adr_batch_yaml_io.md` skipped |
| `codd validate --path .` | PASS | validated 16 Markdown files |
| `codd measure --path . --json` | PASS | health_score 95, validation_errors 0, validation_warnings 0, coverage_ratio 0.0 |
| `codd dag verify --path . --format json` | PASS | completed after a long wait; checks passed, with `depends_on_consistency` skipped because propagation output was missing |

Design quality score: 7/10.

Rationale:

- Strengths: dry-run default, stable marker de-duplication, gate-specific fix hint integration, and escalation state for repeated unchanged failures.
- Weaknesses: broad mutation surface in apply mode, silent empty results on malformed logs, heuristic insertion/classification, long-running DAG verification, and missing target-specific CoDD graph requirements.

## 4. Improvement Candidates

1. Add fixture tests for dry-run aggregation and apply insertion.
   - Cover duplicate marker skip, existing auto section, fallback insertion, `--skill` filtering, and gate_report_format -> report-write mapping.

2. Add a `--json` output mode.
   - Emit skill/rank/count/gate/reason/path/classification for dashboard or gate consumers without parsing the table text.

3. Harden log cache invalidation.
   - Include a content hash or disable cache when mtime precision is unreliable.

4. Surface malformed log/config errors.
   - Emit WARN rows or non-zero status for unreadable YAML when not in a known no-log state.

5. Add apply-mode guardrails.
   - Report target paths before mutation and support `--repo-skills-only` to avoid accidental writes outside the current repo.

6. Add target-specific CoDD requirements.
   - Create `codd/requirements/skill_auto_improve_requirements.md` before rerunning `codd generate`; current generation only sees existing generic requirements.

## 5. Binary AC Check

| AC | Result | Evidence |
| --- | --- | --- |
| AC1 | PASS | `codd spec` failure recorded; spec-equivalent purpose, constraints, and scope generated in this document |
| AC2 | PASS | `codd elicit` executed; failure recorded; manual requirement holes and coverage axes listed |
| AC3 | PASS | `codd generate` executed; 0 generated / 2 skipped result recorded |
| AC4 | PASS | `codd validate` and `codd dag verify` executed and passed; DAG verify was long-running |
| AC5 | PASS | `codd measure` executed; health_score 95 recorded; 6 improvements identified |
