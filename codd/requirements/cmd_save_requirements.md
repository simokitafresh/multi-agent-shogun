---
codd:
  node_id: req:script:cmd-save
  type: requirement
  status: approved
  confidence: 0.9
  source: brownfield
  depended_by:
  - id: design:script:cmd-save
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/cmd_save.sh
---

# cmd_save.sh Brownfield Requirements

## Purpose

`scripts/cmd_save.sh` must gate shogun command drafts before delegation so low-quality, duplicate, stale, or unsafe commands do not enter the karo deployment queue.

## Functional Requirements

- FR-1: Normalize numeric and `cmd_*` ids, then load the matching block from `queue/shogun_to_karo.yaml`.
- FR-2: Validate YAML syntax, command existence, delegated-state immutability, previous pending command state, archive duplicates, and concurrent draft conflicts.
- FR-3: Enforce `quality_gate` fields and diagnosis/environment-change requirements when prior BLOCK/WARN history exists.
- FR-4: Record BLOCK, WARN, and PASS outcomes into quality logs and session-state files.
- FR-5: Warn on lock contention, uncommitted implementation changes, duplicate GP numbers, and scout/recon overlap with existing gunshi analysis.
- FR-6: Update bulletin action tracking when a command references action-required bulletin ids.

## Safety Requirements

- SR-1: Do not delegate a cmd while its gate state remains pending or blocked.
- SR-2: Treat delegated commands as immutable; further design changes require a new cmd or explicit stop/reissue flow.
- SR-3: Use flock and structured checks around shared queue files.

## Cross-References

- [[cmd_save_design.md]] is the design counterpart that satisfies this requirement (its frontmatter declares `depends_on: req:script:cmd-save`); its Entry Flow section (line 20) documents that the script "normalizes the cmd id, loads the current cmd block, accumulates BLOCK/WARN reasons through ordered checks, writes outcome logs on exit, and exits nonzero when blocking conditions remain."
- [[cmd_save_brownfield.md]] is the CoDD brownfield report for this target; its Cross-References (line 30) tie the implementation to the growth loop: "[[growth-loop.md]] defines cmd_save.sh as the Shogun growth-loop enforcement point: BLOCK/WARN requires structured `environment_change` plus grep verification."
- [[cmd_save.sh]] is the sole implementation listed in this file's frontmatter; its header (line 5) states its purpose as "将軍がEdit toolでshogun_to_karo.yamlに書いたcmdブロックの保存前安全チェック", matching FR-1 through FR-6 above.
