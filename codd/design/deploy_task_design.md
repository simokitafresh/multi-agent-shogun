---
codd:
  node_id: design:script:deploy-task
  type: design
  status: approved
  confidence: 0.9
  source: brownfield
  depends_on:
  - id: req:script:deploy-task
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/deploy_task.sh
---

# deploy_task.sh Brownfield Design

## Entry Flow

The script initializes shared helpers, parses deployment arguments, validates the target ninja, resolves cmd/task metadata, updates `queue/tasks/{ninja}.yaml`, generates the report template, and sends a `task_assigned` inbox message.

## Core Components

- `parse_deploy_task_args`: normalizes normal, direct, YAML, and forced-cmd modes and appends the absolute task YAML path to the wake message.
- `deploy_task_validate_cli_target`: rejects empty targets, `None`, and accidental cmd ids in the ninja position.
- `reset_stale_fields`: removes stale task-state and gate-notification residue before reusing a task YAML.
- `resolve_cmd_to_task`: reads `queue/shogun_to_karo.yaml` and populates task identity, parent cmd, project, purpose, and status.
- `inject_ac_version`, `verify_ac_consistency`, and related helpers: attach AC identity and detect cmd/task mismatch.
- `inject_task_modifiers`: delegates broad task enrichment to `scripts/lib/inject_task_modifiers.py`.
- `generate_report_template`: creates the ninja report file, protects completed reports, and archives stale templates.
- `safe_inbox_write`: calls `scripts/inbox_write.sh` and verifies persistence around delivery failures.

## Data Boundaries

Inputs are `queue/shogun_to_karo.yaml`, target task YAML, project/context files, and shared lessons. Outputs are the target task YAML, report YAML, deployment logs, optional stale archives, and inbox messages.

## Implementation Evidence

- [[deploy_task.sh]] lines 1876-1906 implement report path selection: `report_filename` wins first, then `ninja_report_${parent_cmd}.yaml`, then the legacy fallback.
- [[deploy_task.sh]] lines 2016-2028 resolve `worker_id`, `task_id`, and `parent_cmd` for the report template; lines 2650-2651 write `report_path` back to the task YAML.
- [[deploy_task.sh]] lines 4914-4930 delegate enrichment to [[inject_task_modifiers.py]], whose header states that seven injection passes were consolidated into one subprocess.
- [[inbox_write.sh]] lines 1132-1154 enforce the downstream report gate by reading `report_path`, then falling back to `parent_cmd`-based report discovery when needed.
- [[deploy_task_brownfield.md]] records the source brownfield run and links this maintained design back to the implementation and acceptance context.

## Report Template Contract

`generate_report_template` must keep `report_filename`, `report_path`, and `parent_cmd` mutually consistent. Downstream `inbox_write.sh` report gates can locate reports through either explicit `report_path` or the legacy `report_filename`/`parent_cmd` fallback, so deploy-time template generation must write all three fields before notifying the ninja.

## Brownfield Evidence

- [[deploy_task.sh]] defines deployment argument parsing near `parse_deploy_task_args`.
- [[deploy_task.sh]] generates report templates in `generate_report_template`.
- [[deploy_task.sh]] centralizes final enrichment in `inject_task_modifiers`.
- [[deploy_task_brownfield.md]] records the CoDD brownfield run for this target.
