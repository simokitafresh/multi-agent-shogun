# model_switch_preflight.sh CoDD L4 Spec

cmd: cmd_training_L4_codd_202605160001_kagemaru
date: 2026-05-16
author: kagemaru
target: `scripts/model_switch_preflight.sh`

---

## Purpose

`scripts/model_switch_preflight.sh` is the preflight gate for agent model and CLI switching. It checks whether model/CLI literals remain outside the central lookup layer, whether `config/settings.yaml` and `config/cli_profiles.yaml` agree, whether the target ninja can safely be switched, and whether scripts that depend on CLI classification use `scripts/lib/cli_lookup.sh`.

The intended "done" state is: a switch operator can run the script before a model change and receive a reliable binary answer: no blocking hardcodes, no invalid agent CLI schema, no unsafe target task state, and no stale inline `is_codex()` implementations.

---

## Scope

| Item | In Scope | Out of Scope |
|------|----------|--------------|
| Script behavior | Four checks implemented in lines 59-267 | Changing the model-switch procedure itself |
| Inputs | Optional target agent argument, `config/settings.yaml`, `config/cli_profiles.yaml`, `queue/tasks/*.yaml`, git-tracked shell scripts | Direct tmux respawn/model switching |
| Outputs | PASS/WARN/FAIL counts and exit code | Dashboard, report YAML, or inbox mutation |
| CoDD work | Spec, elicit/lexicon gap analysis, generate applicability, validate/measure scoring | Production code changes |

---

## Functional Requirements

| ID | Requirement | Evidence |
|----|-------------|----------|
| FR-1 | Build a dynamic hardcode pattern from all configured agents and fail on forbidden model/CLI literals outside the central config and generated files | `check_hardcodes()` lines 59-94 |
| FR-2 | Validate that each configured agent `type` resolves to a profile in `config/cli_profiles.yaml`, defaulting to `cli.default` when omitted | `check_settings_schema()` lines 98-170 |
| FR-3 | For the target agent, classify `idle/done/completed` as safe and `acknowledged/assigned/in_progress` as switch-warning states | `check_task_status()` lines 174-218 |
| FR-4 | Discover scripts sourcing `cli_lookup.sh` via `git grep`, then fail if any still define inline `is_codex()` | `check_cli_lookup_usage()` lines 222-267 |
| FR-5 | Return exit 1 only when FAIL count is nonzero; warnings must keep exit 0 with an explicit warning summary | summary logic lines 287-304 |

---

## Constraints

| ID | Constraint |
|----|------------|
| C-1 | Must stay read-only; preflight must not mutate `config/`, `queue/`, tmux panes, or inbox files |
| C-2 | Must exclude central config and generated instruction files from hardcode scanning to avoid expected literals causing false positives |
| C-3 | Must avoid wide Python/YAML parsing except where schema validation requires structured parsing |
| C-4 | Must remain performant on WSL2 `/mnt/c`; prefer single-pass `rg`, `awk`, and `git grep` over repeated filesystem scans |
| C-5 | Must report enough detail for a human or follow-up cmd to fix blockers without rerunning with debug flags |

---

## Current Execution Evidence

Commands executed on 2026-05-16:

| Command | Result |
|---------|--------|
| `bash -n scripts/model_switch_preflight.sh` | PASS |
| `bash scripts/model_switch_preflight.sh kagemaru` | FAIL: 10 PASS, 1 FAIL, 1 WARN |
| `codd validate --path .` | PASS: validated 16 Markdown files under configured doc_dirs |
| `codd measure --path . --json` | health_score=95, total_nodes=16, total_edges=12, validation_errors=0, validation_warnings=0 |
| `codd dag verify --path . --format json` | TIMEOUT after 60s, no output |
| `codd elicit --path . --format md` | FAIL: `LexiconLoadError: lexicon manifest not found: shogun_core` |
| `codd lexicon list` | Installed 0, Available 0 |

Observed script failure details:

- Check 1 reported 11 hardcode hits. Several hits were context/index documentation mentions rather than executable switch logic, so the hardcode scan currently mixes operational risk and knowledge-base text.
- Check 3 warned because `kagemaru` was `in_progress`, which is correct for this training task and confirms that the task-state safety check is live.
- Check 4 found 9 dependent scripts and all used `cli_lookup.sh` without inline `is_codex()`.

---

## Elicit / Lexicon Findings

| Gap | Severity | Finding | Proposed Coverage Axis |
|-----|----------|---------|------------------------|
| G1 | High | Hardcode scan does not distinguish executable files from context/index docs. A documentation entry containing `gpt-5.5` can block a model switch even when runtime code is safe. | `hardcode_source_classification`: executable, config, generated, documentation, archive |
| G2 | High | Target agent names are not validated before task lookup. A typo target becomes `queue/tasks/{typo}.yaml`; if missing, it is treated as idle/safe. | `target_agent_membership`: target must be in `get_all_agents()` |
| G3 | Medium | Settings schema only checks `type`; it does not verify required profile fields such as launch command, absolute path for Codex, or model/effort compatibility. | `profile_contract`: type exists, launch command exists, Codex launch command absolute, model args coherent |
| G4 | Medium | `codd elicit` cannot run because the configured/default `shogun_core` lexicon manifest is unavailable, while `codd lexicon list` shows no installed or bundled lexicons. | `codd_lexicon_readiness`: configured lexicon path exists before claiming elicit coverage |
| G5 | Medium | `codd dag verify` timed out after 60s on the current project. DAG verification health is therefore not bounded enough for routine preflight training use. | `dag_verify_runtime_budget`: verify must complete under a documented timeout or be scoped |
| G6 | Low | Python schema validation exits 0 inside the heredoc even after parse/read errors and relies on printed `ERROR:` lines for failure accounting. This is functional but makes shell-level failure semantics implicit. | `embedded_validator_contract`: child parser rc and emitted status must agree |

---

## Generate Applicability

`codd generate --wave N` is not directly applicable to `scripts/model_switch_preflight.sh` in this task because the active CoDD config targets `codd/brownfield_targets/` and doc dirs under `codd/`, while the requested artifact is a training spec in `docs/research/`. Running generation would require a wave definition and may invoke the configured AI command. For this L4 task, generation is represented by this manual CoDD-compatible design artifact plus command-level validation/measurement.

---

## Validate / Measure Assessment

Automated CoDD project score is strong for the currently configured DAG:

- `health_score`: 95
- `validation_errors`: 0
- `validation_warnings`: 0
- `documents_checked`: 16
- `orphan_nodes`: 4

The score does not fully cover `model_switch_preflight.sh`, because that script is outside the configured `scan.source_dirs`. Manual design quality score for this specific artifact: **78/100**.

Score rationale:

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Purpose clarity | 18/20 | The preflight purpose and binary exit rule are clear |
| Scope boundaries | 14/20 | Config/generated exclusions exist, but docs/context scanning creates false-positive risk |
| Requirement coverage | 18/20 | Four checks map cleanly to functional requirements |
| Edge-case coverage | 13/20 | Target typo, profile contract, and lexicon readiness are under-specified |
| Measurability | 15/20 | PASS/WARN/FAIL counts exist; CoDD DAG scope/runtime are not yet bounded |

---

## Improvement Candidates

1. Split hardcode scanning into executable and documentation modes. Runtime files should block; context/docs hits should be WARN unless they reference an active command path or generated instruction.
2. Add target membership validation before task status lookup. Unknown targets should be FAIL, not "task fileなし（idle）".
3. Extend settings schema validation from `type` existence to profile contract checks: profile `launch_cmd`, Codex absolute path, allowed model/effort fields, and deprecated model aliases.
4. Add a CoDD readiness check for lexicon configuration. If `elicit` expects `shogun_core`, the manifest path should be part of the repo or the config should explicitly select discovery mode.
5. Scope `codd dag verify` for routine training/preflight use, or record a documented timeout budget so verification cannot hang the learning loop.
6. Make the embedded Python validator return nonzero on parse/read failure and capture rc explicitly, while preserving current aggregated FAIL reporting.

---

## Binary Checks

| Check | Result | Evidence |
|-------|--------|----------|
| AC1 spec recorded in `docs/research/` | yes | This file |
| AC2 elicit/lexicon gaps identified | yes | G1-G6 above |
| AC3 validate/measure executed and design improvements >= 3 identified | yes | CoDD command results + six improvement candidates |

