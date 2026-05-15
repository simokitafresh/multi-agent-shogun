---
codd:
  node_id: design:script:cmd-save
  type: design
  status: approved
  confidence: 0.9
  source: brownfield
  depends_on:
  - id: req:script:cmd-save
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/cmd_save.sh
---

# cmd_save.sh Brownfield Design

## Entry Flow

The script normalizes the cmd id, loads the current cmd block, accumulates BLOCK/WARN reasons through ordered checks, writes outcome logs on exit, and exits nonzero when blocking conditions remain.

## Core Components

- `load_cmd_block` / cache helpers: isolate the target command block and expose field lookup helpers.
- `extract_cmd_diagnosis` and `parse_structured_environment_change`: enforce diagnosis and environment-change structure after prior failures.
- `record_block_reason`, `record_warn_reason`, and logging helpers: accumulate and persist gate outcomes.
- Quality checks in the main section: validate YAML, delegated state, prior pending cmd, draft multiplicity, quality gate fields, and prior attempt state.
- `show_uncommitted_changes_warning`, `check_gunshi_analysis_overlap`, and related checks: emit non-blocking risk context.
- `update_bulletin_actioned_by_for_cmd`: marks referenced action-required bulletin entries as actioned by the cmd.

## Data Boundaries

Inputs are `queue/shogun_to_karo.yaml`, command archives, quality logs, shogun lessons, bulletin board, and git status. Outputs are stderr gate messages, quality logs, last-cmd state, and bulletin action metadata.

## Brownfield Evidence

- `scripts/cmd_save.sh` documents the gate categories in its header.
- `scripts/cmd_save.sh` begins runtime checks at the cmd id normalization and YAML syntax section.
- `scripts/cmd_save.sh` uses `flock -n` for queue lock contention detection.
- `codd/brownfield/cmd_save_brownfield.md` records the CoDD brownfield run for this target.

