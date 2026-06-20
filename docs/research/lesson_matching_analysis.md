# lesson matching analysis

date: 2026-06-20
task: cmd_3466_full
target: `scripts/deploy_task.sh` `inject_related_lessons`

## Finding

Low-useful lesson injection was still possible through two bypasses after the prior MAX_INJECT and keyword-threshold fixes:

1. `target_files` match added `TARGET_PATH_MATCH_BOOST=50` even when `keyword_score=0`.
   Result: a lesson could pass `MIN_KEYWORD_SCORE` only because it mentioned the same changed file, not because its title/summary/content matched the task intent.
2. `tag fallback` used `helpful_count` when all tag-matched lessons had `keyword_score=0`.
   Result: broad tag matches could select historically frequent lessons with no textual relation to the task.

These are the same failure shape as cmd_3254: a boost intended for ranking became a relevance bypass.

## Existing Defenses Preserved

- `MAX_INJECT=3` remains unchanged.
- `MIN_KEYWORD_SCORE_BY_TASK_TYPE` remains unchanged.
- semantic and memory-db boosts still require `keyword_score > 0`.
- `target_files` still works as a strong ranking signal after keyword relevance is established.
- tag fallback still exists, but only for lessons whose `target_files` match the task file.

## Change

- Apply `TARGET_PATH_MATCH_BOOST` only when `keyword_score > 0`.
- Restrict zero-keyword `tag fallback` to `_lesson_matches_task_target_path(l)`.

## Simulation

Added focused Bats cases in `tests/unit/test_deploy_task_lesson_target_relevance.bats`:

| Scenario | Before | After |
|---|---:|---:|
| `target_files` match with `keyword_score=0` and high `helpful_count` | injected | excluded |
| relevant keyword lesson in same task | injected | injected |
| tag fallback with tag-only high `helpful_count` lesson | injected | excluded |
| tag fallback with explicit target file match | injected | injected |

Verification command:

`bats tests/unit/test_deploy_task_lesson_target_relevance.bats`

Result: 6/6 PASS.
