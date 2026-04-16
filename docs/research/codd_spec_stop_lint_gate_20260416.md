# stop-lint-gate.sh CoDD speedup (cmd_1978)

## Goal

- Target: `.claude/hooks/stop-lint-gate.sh`
- Goal: `3.0s -> <=500ms` on representative Stop-hook paths if possible, without weakening lint coverage

## Before

- Current hook flow:
  - detect agent via `tmux display-message`
  - enumerate changed files via `git diff --name-only --cached` + `git diff --name-only`
  - run `shellcheck` / `ruff` / `biome` once per file
  - hash repeated failures and escalate to `karo`
- Isolated benchmark setup:
  - project-local worktree `.tmp_stop_lint_bench`
  - representative changed files: `.claude/hooks/stop-lint-gate.sh`, `scripts/hooks/test_hooks.sh`, `scripts/slim_yaml.py`
  - command: `TMUX_PANE=%6 bash .claude/hooks/stop-lint-gate.sh >/dev/null`
- Before timings:
  - run1 `0.82s`
  - run2 `0.85s`
  - run3 `1.00s`
  - run4 `0.79s`
  - run5 `0.77s`
  - median `0.82s`

## Bottleneck analysis

### Observed costs

- `git diff --name-only --cached; git diff --name-only` on WSL2 worktree:
  - `0.74-1.11s`
- `git diff-index --cached --name-only HEAD --`:
  - `0.05-0.06s`
- `git ls-files -m`:
  - `0.42-0.43s`
- `shellcheck -S warning` per file:
  - `0.05-0.08s`
- `shellcheck -S warning` batched across 2 files:
  - `0.13-0.14s`
- `ruff check --quiet --select E,W,F scripts/slim_yaml.py`:
  - `0.06-0.07s`

### Conclusions

- Primary bottleneck is changed-file enumeration, not lint execution itself.
- Secondary bottleneck is per-file linter process startup. It is smaller than Git cost but still avoidable.

## Optimization candidates

### Candidate A: Git plumbing for changed-file enumeration

- Replace:
  - `git diff --name-only --cached`
  - `git diff --name-only`
- With:
  - `git diff-index --cached --name-only --diff-filter=ACMRTUXB HEAD --`
  - `git ls-files -m`
- Rationale:
  - preserves tracked staged + tracked unstaged union
  - avoids the expensive porcelain diff path observed on WSL2

### Candidate B: Batch linter invocation per tool

- Replace per-file loops with one invocation per tool:
  - `shellcheck -S warning "${sh_files[@]}"`
  - `ruff check --quiet --select E,W,F "${py_files[@]}"`
  - `npx --yes biome check "${ts_js_files[@]}"`
- Rationale:
  - keeps the same lint engines and severity filters
  - removes repeated process startup cost when multiple files are changed

### Candidate C: Dedupe + prefilter before lint

- Dedupe staged/unstaged file union once via `awk`
- Filter to existing files before extension classification
- Rationale:
  - avoids duplicate linting when a file is both staged and unstaged
  - avoids needless work for renamed/deleted paths

## Safety constraints

- Keep agent skip logic unchanged (`shogun`/`karo`/`gunshi` bypass)
- Keep repeated-failure hash + `inbox_write.sh karo ... error_report` escalation unchanged
- Keep lint coverage unchanged:
  - shell: `shellcheck -S warning`
  - python: `ruff check --quiet --select E,W,F`
  - ts/js: `npx --yes biome check`

## Validation plan

- Add unit tests for:
  - no tracked changes -> clean exit
  - batched shell/python lint invocation
  - new violation -> block + hash write
  - repeated identical violation -> escalate to `karo`
- Re-run isolated before/after benchmark on the same representative changed-file set
- Update `docs/research/codd_refactor_registry.md` with measured result

## After

- Implementation:
  - changed-file collection moved to `git diff-index --cached ... HEAD --` + `git ls-files -m`
  - staged/unstaged union deduped once via `awk`
  - `shellcheck`, `ruff`, `biome` switched from per-file loops to per-tool batched invocation
- Added tests:
  - `tests/unit/test_stop_lint_gate.bats`
  - verified repeated-failure escalation path to `karo`

### Isolated benchmark (same representative changed-file set as Before)

- run1 `0.67s`
- run2 `0.66s`
- run3 `0.64s`
- run4 `0.65s`
- run5 `0.64s`
- median `0.65s`
- improvement vs before median `0.82s -> 0.65s` (`-20.7%`)

### Live worktree benchmark (current task change set)

- run1 `0.61s`
- run2 `0.63s`
- run3 `0.54s`
- run4 `0.52s`
- run5 `0.52s`
- median `0.54s`

## Outcome

- The original `3.0s` profiler number was not reproduced under the current repo state.
- Under a representative mixed shell+python changed-file set, the hook improved materially but did not fully cross `500ms`.
- Under the live worktree for this task, the hook runs near the target (`0.54s` median) while preserving lint behavior and escalation behavior.
