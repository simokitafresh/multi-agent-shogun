# GA-228: task YAML mixed-stage prevention

## §1 Finding

| Item | Primary evidence | Result |
|---|---|---|
| Incident | `logs/hook_failures.yaml`, entry timestamp `2026-07-12T06:48:58+09:00` | Tobisaru's pre-commit invocation was blocked by GA-408 after the index contained a task YAML and `context/dm-signal-research.md`. |
| Existing design intent | `git blame` / commit `e8cea6c634` on `scripts/hooks/git-pre-commit.sh` L198-L221, L258-L271 | GA-408 intentionally permits task YAML with operational YAML, but blocks a task YAML plus a non-operational file at commit time. |
| Root-cause verdict | Hook timing | **hook configuration/timing gap, not code-quality failure**: the correct GA-408 check ran only after `git add` had created the invalid mixed index and failure logging had occurred. |

The event is immediately followed by the independent cmd_3860 commits at `06:49:04` and `06:49:12`; no commit was created by the blocked mixed-stage attempt.

## §2 Recurrence inventory

Query: parse all 321 entries in `logs/hook_failures.yaml` and match the exact GA-408 block message. The result is below the task threshold of three, so this records the complete matching population.

| Dimension | Count | Evidence / limitation |
|---|---:|---|
| Same-pattern failures | 1/321 | `queue/tasks/*.yaml cannot be committed with implementation files (GA-408)` |
| Ninja | tobisaru: 1 | The failure record's `ninja` field |
| Hook / execution point | pre-commit: 1 | The record has no shell command field; the primary execution input is the staged file set inspected by GA-408. |
| Mixed non-operational file | `context/dm-signal-research.md`: 1 | Exact path in the recorded detail |
| Task YAML path | not retained: 1 | GA-408 records the task-file class rather than the individual path. This is a logging limitation, not an inferred value. |

## §3 Prevention design and fixtures

`scripts/hooks/git-stage-guard.py` parses actual `git add` command segments and runs each candidate add against a temporary index. It blocks only when the prospective staged set contains both `queue/tasks/*.yaml` and a file outside operational YAML (`queue/**/*.yaml` or `logs/**/*.yaml`). The real index is never mutated during the check.

`.claude/hooks/pre-bash-combined.sh` invokes this guard as Guard 3.7. Both Claude and Codex route Bash PreToolUse through that common dispatcher, so the guard fires before the `git add` command reaches Git.

| Fixture | Expected / measured result |
|---|---|
| task YAML + context | pre-change: stage allowed 1/1; post-change: PreToolUse BLOCK 1/1, real stage remains 0 files |
| task YAML alone | allowed 1/1 |
| task YAML + report/log operational YAML | allowed 1/1 |
| implementation only | allowed 1/1 |

## §4 Verification

| Command | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| `bats tests/unit/test_pre_bash_queue_tasks_guard.bats` | 9 | 0 | 0 |
| `bats tests/unit/test_git_pre_commit.bats` | 15 | 0 | 0 |
| `bash -n .claude/hooks/pre-bash-combined.sh` + `python3 -m py_compile scripts/hooks/git-stage-guard.py` | 2 | 0 | 0 |

## 因果リンク

[[cmd_karo_hotfix_ga408_precommit_guard_20260603]] -> [[GA-408]] -> [[GA-228]] -> [[git_stage_guard]]
