---
codd:
  node_id: req:script:clear-prep-check
  type: requirement
  status: approved
  confidence: 0.9
  source: brownfield
  depended_by:
  - id: design:script:clear-prep-check
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/clear_prep_check.sh
---

# clear_prep_check.sh Brownfield Requirements

## Purpose

`scripts/clear_prep_check.sh` must validate the system state before a `/clear` operation, ensuring that all critical checks pass and that no information would be lost when context is cleared.

## Functional Requirements

- FR-1: Execute 11 sequential checks (check1-check11) covering dashboard, inbox, context, snapshot, conv health, git status, artifact map, lessons, and decisions.
- FR-2: Parse `queue/lord_conversation.jsonl` to verify session state, conversation health, decision gaps, and session summary presence.
- FR-3: Execute `git -C $ROOT_DIR status --porcelain` to detect uncommitted changes in scripts/, instructions/, config/, context/, and CLAUDE.md.
- FR-4: Report findings for each check with WARN/INFO/PASS classification.
- FR-5: Terminate with non-zero exit if any check detects a BLOCK condition.
- FR-6: Complete all checks within a target of 1.5 seconds on WSL2 NTFS.

## Performance Requirements

- PR-1: Total execution time must be under 2 seconds on WSL2 NTFS cold run.
- PR-2: `git` invocations must minimize WSL2 NTFS I/O overhead; prefer `git diff HEAD --name-only` over `git status --porcelain` where semantically equivalent.
- PR-3: Python3 process spawns must be consolidated; `lord_conversation.jsonl` must be parsed at most once per invocation.

## Safety Requirements

- SR-1: Each check must be idempotent and read-only (no side effects).
- SR-2: Python3 subprocess spawns must not parse the same file multiple times in one execution.
- SR-3: All check logic must be preserved during refactoring; only I/O patterns may change.
