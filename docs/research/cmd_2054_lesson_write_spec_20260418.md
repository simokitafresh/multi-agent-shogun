# cmd_2054 lesson_write.sh CoDD spec

## Target

- `scripts/lesson_write.sh`
- Registry entry to backfill: `docs/research/codd_refactor_registry.md` line for `scripts/lesson_write.sh`

## Before

- fixture repro:
  - temp `projects.yaml` + `tasks/lessons.md` + `context/test-context.md`
  - `LESSON_WRITE_SCRIPT_DIR=<fixture> LESSON_WRITE_SKIP_SYNC=1 bash scripts/lesson_write.sh testproj ...`
- observed:
  - `70ms`
  - `40ms`
  - `40ms`
  - median `40ms`
- existing registry baseline: `113ms → ~60ms` (`first-write fixture median`)

## Bottleneck

- hot path still pays a few external processes on every write:
  - `date` for lesson timestamp
  - `grep -qF` for context duplicate check
  - another `date` for `lesson.done`
- fixture path includes similar-title warning, so fixed shell/process overhead is visible

## Chosen change

1. replace `date` calls with `printf -v %(... )T`
2. replace context duplicate `grep -qF` with a shell read loop
3. keep Python context append block itself unchanged to avoid behavior drift

## Guardrails

- duplicate title blocking / Jaccard WARN behavior unchanged
- context append / strategic / lesson.done semantics unchanged

## Validation

- `bash -n scripts/lesson_write.sh`
- `bats tests/unit/test_lesson_write.bats`
- same fixture benchmark command as Before

## After

- replay measurement:
  - `116.40ms`, `86.94ms`, `81.37ms`, `82.25ms`, `85.06ms`, `86.08ms`, `76.42ms`
  - median `85.06ms`
- attempted micro-change:
  - no-flag fast path in option parsing
- result:
  - fixture replay regressed against the shipped implementation
  - reverted immediately per `After>=Beforeなら即revert`
  - final code state remains unchanged
