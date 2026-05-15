---
title: "CoDD L4: ac_physical_verify.sh"
date: "2026-05-16"
task_id: "cmd_training_L4_codd_c4_hayate"
target: "scripts/ac_physical_verify.sh"
worker: "hayate"
---

# CoDD L4: ac_physical_verify.sh

## AC1: Spec Equivalent

### Purpose

`scripts/ac_physical_verify.sh` is a Level 5 pre-review context generator. It reads cmd text from `queue/shogun_to_karo.yaml` or stdin, extracts file paths, line references, section references, gitignore status, prior commits for the same cmd id, and recent cold review perspectives, then emits a navigation sheet for ninja/reviewer work.

### Scope

| Area | Current behavior | Evidence |
|------|------------------|----------|
| Input modes | `cmd_id` from queue or `-` from stdin | `scripts/ac_physical_verify.sh` L24-L50 |
| Project fallback | `dm-signal` paths fall back to `/mnt/c/Python_app/DM-Signal` | L52-L65, L130-L136 |
| AC complexity warning | `AC_COUNT > 4` emits LG021 warning | L67-L81 |
| Path extraction | hard-coded regex list for absolute, context, projects, instructions, scripts, queue, docs, CLAUDE.md | L92-L107 |
| Line/section extraction | global `L123` and `§N` extraction, then matching against extracted paths | L109-L188 |
| Gitignore check | warns when commit/push AC references gitignored paths | L191-L211 |
| Navigation sheet | extracts references per `AC\d+` block | L213-L239 |
| Parallel work warning | checks recent commits containing cmd id | L242-L257 |
| Adaptive gating | summarizes cold review categories from recent gunshi review log | L266-L288 |

### Constraints

| Constraint | Reason |
|------------|--------|
| No queue YAML writes | The script is read-only by design and must not mutate shared operational YAML. |
| Must fail on missing paths | Exit 1 is the enforcement signal used by reviewers and gates. |
| Must avoid false missing for external project files | Prior incident cmd_2426 showed shogun repo-only lookup misclassified DM-Signal paths. |
| Must not hide gitignored commit risk | Gitignored report/template paths can make commit ACs impossible. |
| Must keep output human-scannable | The consumer is a ninja/reviewer before implementation, not a machine-only parser. |

### Direct Functional Evidence

| Check | Result |
|-------|--------|
| `bash -n scripts/ac_physical_verify.sh` | PASS |
| stdin with existing `scripts/ac_physical_verify.sh L1` and `context/codd.md §1` | PASS, 2 paths verified, line and section shown |
| stdin with missing `scripts/does_not_exist.sh` | PASS as negative test: exit code 1 and MISSING shown |

## AC2: Elicit / Lexicon / Coverage Gaps

| Gap | Observation | Impact |
|-----|-------------|--------|
| GAP-1: AC block regex is narrow | `re.findall(r'(AC\d+.*?)(?=AC\d+|$)', ...)` only recognizes literal `AC1` style blocks. Dict/list ACs without embedded `AC\d+` labels can produce no navigation sheet. | Reviewers may get verified paths but no per-AC mapping. |
| GAP-2: Path lexer misses common repo files | Current regex misses `.json`, `.bats`, `.txt`, extensionless scripts, hidden files, and quoted paths with spaces. | Valid AC references can be invisible, causing false confidence. |
| GAP-3: Line references are global | Every `L123` is checked against every extracted file. There is no binding of line reference to nearest path. | Output can show unrelated line contents when multiple files are present. |
| GAP-4: Project fallback is hard-coded | Only `dm-signal` is mapped. Other project ids have no fallback despite project paths existing in `projects/{id}.yaml`. | Cross-project physical verification will regress as more projects are added. |
| GAP-5: Queue parsing assumes mapping shape | `cmds = data.get('commands', data); cmd = cmds.get(cmd_id, {})` has no diagnostics for malformed queue shape. | Malformed queue produces "not found" rather than structural error. |
| GAP-6: Adaptive gating parses YAML with awk | Review log categories are extracted by line regex rather than YAML parsing. | Multi-line or reformatted YAML can silently drop cold categories. |
| GAP-7: CoDD coverage sees zero axes | `codd coverage report` produced 0 axes/0 signals. | CoDD cannot currently measure this script against a lexicon-backed completeness model. |
| GAP-8: `codd elicit` lexicon load fails | `shogun_core` manifest lacks `prompt_extension`. | Elicit cannot propose holes for this repo until the installed lexicon is fixed. |
| GAP-9: `codd extract` for bash produced 0 files/modules | `extract --language bash --source-dirs scripts` emitted 0 modules from 0 files. | Brownfield design extraction does not provide usable bash structure here. |

## AC3: Validate / Measure / Score

| Command | Result |
|---------|--------|
| `/home/simokitafresh/.codd-venv/bin/codd --version` | `codd, version 2.18.0` |
| `/home/simokitafresh/.codd-venv/bin/codd validate --path .` | PASS: `OK: validated 16 Markdown files under configured doc_dirs` |
| `/home/simokitafresh/.codd-venv/bin/codd measure --path . --json` | PASS: `health_score=95`, `validation_errors=0`, `validation_warnings=0`, `documents_checked=16` |
| `/home/simokitafresh/.codd-venv/bin/codd coverage report --path . --format md --output docs/research/hayate_codd_L4_ac_physical_verify_coverage_20260516.md` | PASS, but totals are 0 axes / 0 covered signals |
| `/home/simokitafresh/.codd-venv/bin/codd elicit --format md --path . --lexicon shogun_core` | Tooling gap: `LexiconLoadError`, manifest missing `prompt_extension` |
| `/home/simokitafresh/.codd-venv/bin/codd brownfield scripts/ac_physical_verify.sh` | Tooling gap: brownfield target must be a directory, file target rejected |
| `/home/simokitafresh/.codd-venv/bin/codd extract --path . --language bash --source-dirs scripts --output docs/research/hayate_codd_L4_ac_physical_verify_extract_20260516` | Tooling gap: 0 modules from 0 files |

### Quality Score

| Dimension | Score | Rationale |
|-----------|------:|-----------|
| Purpose fit | 18/20 | Script directly implements Level 5 context generation for review preflight. |
| Failure signaling | 17/20 | Missing paths return exit 1; negative sample verified. Structural YAML errors remain weak. |
| Coverage completeness | 11/20 | Regex coverage is useful but misses several repo-relevant file types and AC forms. |
| Maintainability | 12/20 | Multiple embedded Python snippets and hard-coded project mapping increase drift risk. |
| CoDD observability | 9/20 | CoDD repo score is high, but coverage/elicit/extract do not currently see this script meaningfully. |
| Total | 67/100 | Useful operational tool, but specification and coverage axes are under-modeled. |

## Improvements

1. Replace hard-coded `project_dirs = {'dm-signal': ...}` with `projects/{project}.yaml` path lookup, falling back only when the project file is absent or malformed.
2. Replace path extraction regex list with a single structured tokenizer that accepts repo-relevant extensions (`.json`, `.bats`, `.txt`, `.toml`, `.mdx`), extensionless executable paths, and quoted paths.
3. Bind `L123` and `§N` references to the nearest preceding path within the same AC block instead of checking every line reference against every extracted file.
4. Add dedicated Bats fixtures for stdin mode, missing path exit 1, DM-Signal fallback, gitignored commit AC warning, AC>4 warning, and adaptive cold category output.
5. Parse `logs/gunshi_review_log.yaml` as YAML in the adaptive section instead of awk line matching, or explicitly document and test the accepted one-line format.
6. Fix `shogun_core` lexicon manifest so `codd elicit --lexicon shogun_core` can produce repo-specific hole suggestions.
7. Add CoDD coverage axes for "physical path verification", "line/section binding", "project fallback", "gitignore commit risk", and "parallel work warning".

## Binary Checks

| AC | Check | Result |
|----|-------|--------|
| AC1 | Read target and recorded purpose, constraints, scope in docs/research | yes |
| AC2 | Identified elicit/lexicon/coverage holes | yes |
| AC3 | Ran validate/measure and identified at least 3 improvements | yes |
