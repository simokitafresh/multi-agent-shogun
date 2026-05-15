---
title: "CoDD L4: clear_prep_check.sh"
date: "2026-05-16"
task_id: "cmd_training_L4_codd_c5_hayate"
target: "scripts/clear_prep_check.sh"
worker: "hayate"
---

# CoDD L4: clear_prep_check.sh

## AC1: Spec Equivalent

### Purpose

`scripts/clear_prep_check.sh` is the `/shogun-clear-prep` pre-clear safety gate. It checks whether the current shogun session can be safely cleared without losing unresolved decisions, pending work, operational alerts, active ninja state, conversation record continuity, important uncommitted work, artifact map integrity, new knowledge embedding, and project decision propagation.

### Scope

| Check | Current behavior | Evidence |
|-------|------------------|----------|
| 1. Pending decisions | Counts non-resolved/non-deferred entries in `queue/pending_decisions.yaml` | L22-L60 |
| 2. Pending commands | Counts `status: pending` commands in `queue/shogun_to_karo.yaml` | L62-L100 |
| 3. Dashboard alerts | Reads `🚨 要対応` section from `dashboard.md` | L102-L126 |
| 4. Ninja/snapshot state | Counts active/idle/blocked agents and stale snapshot age | L128-L182 |
| 5. Conversation health | Parses `queue/lord_conversation.jsonl`, counts inbound after latest session summary | L184-L243 |
| 6. Uncommitted important files | Limits git status to `scripts/`, `instructions/`, `config/`, `context/`, `CLAUDE.md` and warns on scripts/context/instructions | L245-L269 |
| 7. Artifact map | Runs `scripts/gates/gate_artifact_map.sh` on `context/l2-okugi-progress.md` | L271-L289 |
| 8. Knowledge embedding | Checks shogun lessons, semantic index date, pending insights, and project yaml freshness | L291-L412 |
| 9. New-game reminder | Emits explicit prompt about whether the next shogun inherits the session learning | L414-L415 |
| 10. Decision propagation | Detects decision keywords in lord conversation and compares latest project yaml mtime | L417-L507 |
| Final status | Emits `[STATUS] ALERT (...)` and exits 1 when issues > 0, otherwise `[STATUS] OK` and exits 0 | L509-L519 |

### Constraints

| Constraint | Reason |
|------------|--------|
| Read-only gate | `/clear` prep must surface loss risk, not repair state implicitly. |
| Alert exit must be nonzero | Session-end hook depends on textual `[STATUS] ALERT`, while direct gate users need rc=1. |
| Must tolerate missing files | Missing conversation/progress/project files must become WARN/SKIP/ALERT, not shell crashes. |
| Must keep output digestible | The user-facing session-end hook extracts only bracket-prefixed summary lines. |
| Must avoid full-repo git status | Existing optimization limits status paths to avoid WSL2 NTFS scan cost. |

### Direct Functional Evidence

| Check | Result |
|-------|--------|
| `bash -n scripts/clear_prep_check.sh` | PASS |
| `bash scripts/clear_prep_check.sh` | Detected current environment risks and returned rc=1 with `[STATUS] ALERT` |
| Observed ALERT reasons | `重要ファイル未commit2`, `成果物欠落2`, `知識埋込み未確認` |

## AC2: Elicit / Lexicon / Coverage Gaps

| Gap | Observation | Impact |
|-----|-------------|--------|
| GAP-1: YAML parsing is awk-based for PD/cmd | Status/id extraction depends on exact line shapes. | Reordered YAML, nested fields, or alternate list/map style can miscount. |
| GAP-2: Emoji heading dependency | Dashboard alert parsing depends on `## .*🚨 要対応`. | Heading wording or emoji changes can hide alerts. |
| GAP-3: Snapshot format dependency | Ninja counts assume `queue/karo_snapshot.txt` pipe records with fixed fields. | Format drift can make active/blocked counts falsely zero. |
| GAP-4: Conversation session boundary is inferred from latest `session_summary` | No explicit session id is used. | Summaries with odd timestamps can misclassify inbound count. |
| GAP-5: Uncommitted check excludes docs/research | CoDD/training docs can be uncommitted but not counted as critical. | Clear prep can report fewer persistence risks than task reality. |
| GAP-6: Artifact gate output parsing is text-dependent | `grep '^  WARN:'` and `grep '総ブロック'` parse human output. | Gate output wording changes can hide artifact warnings. |
| GAP-7: Knowledge embedding check is shogun-centric | It expects shogun lesson writes even if the current session is ninja/training context. | Running outside shogun can produce expected ALERT noise. |
| GAP-8: Project freshness heuristic mixes chronicle keywords and all cmd projects | It may treat unrelated historical `shogun_to_karo.yaml` projects as current session projects. | False stale-project warnings are possible. |
| GAP-9: CoDD coverage sees zero axes | `codd coverage report` produced 0 axes/0 signals. | CoDD cannot currently score this gate's completeness. |
| GAP-10: CoDD elicit/extract/brownfield do not yield useful bash design here | `elicit` fails on lexicon manifest, `brownfield` rejects file target, `extract` returns 0 modules. | Manual spec remains required for bash gate design quality. |

## AC3: Validate / Measure / Score

| Command | Result |
|---------|--------|
| `/home/simokitafresh/.codd-venv/bin/codd --version` | `codd, version 2.18.0` |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: `OK: validated 16 Markdown files under configured doc_dirs` |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | PASS: `health_score=95`, `validation_errors=0`, `validation_warnings=0`, `documents_checked=16` |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md --output docs/research/hayate_codd_L4_clear_prep_check_coverage_20260516.md` | PASS, but totals are 0 axes / 0 covered signals |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | Tooling gap: `LexiconLoadError`, manifest missing `prompt_extension` |
| `/home/simokitafresh/.codd-venv/bin/codd brownfield scripts/clear_prep_check.sh` | Tooling gap: brownfield target must be a directory, file target rejected |
| `/home/simokitafresh/.codd-venv/bin/codd extract --path . --language bash --source-dirs scripts --output docs/research/hayate_codd_L4_clear_prep_check_extract_20260516` | Tooling gap: 0 modules from 0 files |

### Quality Score

| Dimension | Score | Rationale |
|-----------|------:|-----------|
| Purpose fit | 19/20 | The script directly implements /clear loss-prevention checks and returns a clear aggregate status. |
| Failure signaling | 17/20 | ALERT returns rc=1 and lists reasons; some helper output parsing remains text-dependent. |
| Coverage completeness | 16/20 | Ten check areas cover the main persistence risks; docs/research persistence and role-context noise remain gaps. |
| Maintainability | 11/20 | Large monolithic script with awk/Python/text parsing and repeated heuristics. |
| CoDD observability | 9/20 | CoDD repo score is high, but coverage/elicit/extract do not measure this script meaningfully. |
| Total | 72/100 | Strong operational coverage, but parser fragility and weak machine-readable subcheck contracts remain. |

## Improvements

1. Replace awk YAML extraction for `pending_decisions.yaml` and `shogun_to_karo.yaml` with a small structured Python reader that emits `count|ids` while preserving read-only behavior.
2. Add fixture tests for each final status path: OK, PD pending, cmd pending, stale snapshot, blocked ninja, conversation JSON error, important uncommitted files, artifact WARN, knowledge embedding WARN, and decision propagation ALERT.
3. Split the ten checks into functions returning `status`, `reason`, and `display_lines`, then keep the current text output as a renderer. This preserves the hook digest while enabling unit tests.
4. Add role-aware mode or environment override so ninja/training invocations can record shogun-centric knowledge embedding ALERTs as expected environmental findings rather than task failure.
5. Include `docs/research/` in a separate informational uncommitted bucket, so documentation-only persistence risks are visible without making all docs critical.
6. Replace `gate_artifact_map.sh` human-output parsing with a machine-readable mode or stable summary line.
7. Fix `shogun_core` lexicon manifest and add CoDD coverage axes for clear-prep: unresolved decisions, command queue, dashboard alert, agent state, conversation continuity, git persistence, artifact persistence, knowledge embedding, and decision propagation.

## Binary Checks

| AC | Check | Result |
|----|-------|--------|
| AC1 | Read target and recorded purpose, constraints, scope in docs/research | yes |
| AC2 | Identified elicit/lexicon/coverage holes | yes |
| AC3 | Ran validate/measure and identified at least 3 improvements | yes |
