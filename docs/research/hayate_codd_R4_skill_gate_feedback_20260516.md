# hayate CoDD R4: skill_gate_feedback.sh

metadata:
- task_id: `cmd_training_codd_r4_hayate`
- target: `scripts/skill_gate_feedback.sh`
- date: 2026-05-16
- worker: hayate
- method: CoDD pipeline surrogate: spec -> elicit/lexicon -> generate artifact -> validate -> measure

## Spec

`skill_gate_feedback.sh` converts gate failures into skill feedback. It identifies the relevant skill from explicit input, gate mapping, or recent skill execution logs, records a failure event, and appends a dated caution under `## 注意ポイント` in the target `SKILL.md`.

Primary inputs:

| Input | Source | Role |
|---|---|---|
| `--gate` | CLI arg | Gate name that produced the result. Required. |
| `--result` | CLI arg | Gate result, commonly `FAIL`. Required. |
| `--reason` / `--stumbling-points` | CLI arg | Failure reason to persist. |
| `--executor` | CLI arg or env | Agent/user associated with the feedback. |
| `--source` | CLI arg | Source path or parent command. Used for matching and exclusions. |
| `--skill` | CLI arg | Explicit skill override. |
| `--dry-run` | CLI arg | Print selected target without writing. |
| skill dirs | `skills:$HOME/.codex/skills:$HOME/.claude/skills` | Search roots for `SKILL.md`. |
| skill log | `logs/skill_execution_log.yaml` | Prior skill execution evidence and dedupe source. |

Required behavior:

| Area | Requirement |
|---|---|
| Argument validation | Missing `--gate` or `--result` exits 2 with usage; unknown args exit 2. |
| Skill selection | Prefer explicit `--skill`, then hardcoded gate mapping, then latest matching FAIL in skill log. |
| Gate mapping | `gate_report_format` maps to `report-write`. |
| Feedback exclusion | `cmd_complete_gate` FAIL for `cmd-complete` is skipped for `cmd_karo_direct*` and `cmd_training*` sources. |
| Logging | If there is no prior logged entry and result is FAIL, append an execution entry unless source is under `tests/`. |
| Dedupe | Avoid duplicate log failures and duplicate SKILL caution bullets. |
| Dry-run | Print selected skill and path, write nothing. |
| Non-FAIL | Log result and stop without editing skill file. |
| FAIL | Append a dated caution bullet to `## 注意ポイント`, creating the section if absent. |
| Atomic write | Use temp file and `os.replace` for SKILL.md update. |

Non-goals:

| Non-goal | Reason |
|---|---|
| Broad semantic skill routing | Current routing is explicit mapping or log-derived, not AI classification. |
| Modifying test fixture sources | Test-source feedback is skipped for log writing. |
| Editing every copy of duplicated skill names | First matching exact skill file wins after deduped search order. |

## Elicit And Lexicon Findings

Vocabulary that must stay explicit:

| Term | Current meaning |
|---|---|
| gate feedback | A gate result converted into persistent skill guidance. |
| stumbling_points | Failure reason text, sourced from CLI reason or prior log entry. |
| explicit skill | `--skill` override, highest priority. |
| mapped skill | Hardcoded gate-to-skill mapping. |
| logged skill | Skill inferred from `skill_execution_log.yaml`. |
| caution bullet | Dated line inserted under `## 注意ポイント` in `SKILL.md`. |

Requirement holes and coverage axes:

| Gap | Evidence | Coverage axis to add |
|---|---|---|
| Gate-to-skill map contains only `gate_report_format`. | `GATE_SKILL_MAP = {"gate_report_format": "report-write"}`. | Routing coverage axis for common gates: `cmd_complete_gate`, `gate_report_format`, commit/scope, lesson, review. |
| Duplicate caution matching requires exact `gate=... reason=...` text. | `has_duplicate_caution()` scans line text. | Normalization axis for truncated reasons, whitespace, quotes, and date changes. |
| Reason is truncated to 180 chars for bullet, but duplicate check uses truncated text only after truncation. | `reason_one = reason_one[:177] + "..."`. | Collision axis for distinct long reasons with same prefix. |
| YAML log append is handcrafted string escaping. | `_yaml_str()` and manual `executions:` append. | YAML validity fixture for quotes, backslashes, Japanese, newlines, and colon-heavy reasons. |
| Skill dir search is flat one-level only. | `for child in root.iterdir(): child / "SKILL.md"`. | Plugin skill axis for nested or namespaced skill paths if needed. |
| If no skill is identified, script exits 0 with `SKIP`. | `print("SKIP: skill not identified")`. | Observability axis: skipped feedback should be counted, not silently lost. |
| Non-FAIL result logs but does not update skill. | `if result.upper() != "FAIL": LOGGED`. | PASS feedback axis: whether positive reinforcement should update metrics only or skill docs. |
| Importing PyYAML is unconditional. | `import yaml` at top of embedded Python. | Dependency preflight axis for environments without PyYAML. |

## Generated Design Artifact

Proposed generated design shape for future refactor:

| Component | Responsibility |
|---|---|
| `parse_feedback_args` | Validate CLI and return typed request. |
| `load_skill_catalog` | Discover skill files and expose exact lookup. |
| `load_feedback_log` | Read execution log with parse diagnostics. |
| `resolve_skill_target` | Apply explicit, mapped, and logged routing in order. |
| `plan_feedback` | Decide skip/log/edit actions and dedupe results without writing. |
| `append_skill_log` | Append YAML-safe execution event. |
| `update_skill_doc` | Insert caution bullet atomically. |
| `render_feedback_result` | Print machine-readable result: UPDATED, LOGGED, SKIP, DUPLICATE, DRY_RUN. |

Minimum fixtures:

| Fixture | Expected result |
|---|---|
| `missing_gate` | Exit 2 with usage. |
| `unknown_arg` | Exit 2. |
| `gate_report_format_fail` | Resolves `report-write`. |
| `explicit_skill_override` | Uses explicit skill even if gate map differs. |
| `dry_run` | Prints target and performs no writes. |
| `test_source` | Does not append log entry. |
| `duplicate_failure` | Returns DUPLICATE without new log. |
| `duplicate_caution` | Returns UNCHANGED. |
| `long_reason_collision` | Distinct long reasons remain distinguishable or collision is documented. |

## Validate And Measure

Manual design quality score before CoDD validation: 83/100.

Rationale:

| Category | Score | Note |
|---|---:|---|
| Purpose clarity | 18/20 | Gate failure to skill feedback loop is clear. |
| Input/output coverage | 17/20 | Inputs, logs, and skill file targets are explicit. |
| Safety semantics | 17/20 | Dry-run, test-source skip, dedupe, and atomic replace exist. |
| Testability | 15/20 | Existing unit test file exists, but routing/dedupe matrix should be broader. |
| Maintainability | 16/20 | Logic is compact, but embedded Python mixes routing, logging, and document mutation. |

Improvement backlog:

1. Expand `GATE_SKILL_MAP` or move it to config so common gate failures route without relying on prior skill logs.
2. Emit structured skip reasons for unidentified skills so lost feedback is measurable.
3. Replace exact text duplicate detection with stable normalized IDs over gate, skill, and reason hash.
4. Add fixture tests for `_yaml_str` escaping and generated `skill_execution_log.yaml` parse validity.
5. Split planning from mutation so dry-run and tests can assert exact actions.
6. Add a PyYAML dependency preflight with actionable error text.

Executed command results:

| Command | Result |
|---|---|
| `bash -n scripts/skill_gate_feedback.sh` | PASS. |
| `bash scripts/skill_gate_feedback.sh --gate gate_report_format --result FAIL --reason sample --executor hayate --source tests/unit/sample.bats --dry-run` | PASS: resolved `report-write` and printed target path without writing. |
| `codd validate --path .` | PASS: `OK: validated 16 Markdown files under configured doc_dirs`. |
| `codd measure --path . --json` | PASS: `health_score=95`, `validation_errors=0`, `documents_checked=16`, `coverage_ratio=0.0`. |
| `codd coverage report --path . --format md --output docs/research/hayate_codd_R4_skill_gate_feedback_coverage_20260516.md` | PASS, but totals are `0 axes`; coverage instrumentation is not connected to installed lexicon axes. |
| `codd lexicon list` | PASS: installed `shogun_core` with 3 axes. |
| `codd elicit --format md --path . --lexicon shogun_core` | FAIL/tooling gap: bundled `shogun_core` manifest lacks required `prompt_extension`. |
| `codd plan --path .` | FAIL/tooling gap: `codd.yaml` lacks `wave_config`; direct `codd generate` would mutate project generation state, so this document is the generated design artifact for the task. |

This document is the generated spec/design artifact for AC1-AC3. Full CoDD measure/coverage/elicit results are recorded after command execution in the task report.
