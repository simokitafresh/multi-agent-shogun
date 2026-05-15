---
codd:
  node_id: req:script:deploy-task
  type: requirement
  status: approved
  confidence: 0.9
  source: brownfield
  implementation:
  - scripts/deploy_task.sh
---

# deploy_task.sh Brownfield Requirements

## Purpose

`scripts/deploy_task.sh` must be the single supported helper for assigning a task YAML to a ninja and waking that ninja through the inbox path.

## Functional Requirements

- FR-1: Parse normal, `--direct`, `--yaml`, and `--cmd` deployment modes while preserving the default message that invalidates stale previous task context.
- FR-2: Validate that the first positional target is a ninja name, not empty, `None`, or a `cmd_*` id.
- FR-3: Resolve the target pane and determine idle/busy state through shared tmux/CLI helper libraries before delivery.
- FR-4: Reset stale task fields, stale notification flags, and ghost `None.yaml` artifacts before writing a new assignment.
- FR-5: Resolve a parent cmd into task metadata, acceptance criteria, AC version, related lessons, semantic concepts, engineering preferences, and execution controls in the target task YAML.
- FR-6: Generate or complete the matching report template under `queue/reports/` without overwriting completed reports.
- FR-7: Deliver the task notification by invoking `scripts/inbox_write.sh`, treating persisted inbox writes as successful even if post-delivery verification is flaky.

## Safety Requirements

- SR-1: Use shared YAML helpers for queue/task mutation instead of free-form YAML dumping.
- SR-2: Block duplicate active deployments for the same parent cmd when a completed peer report already exists.
- SR-3: Keep task assignment communication on the inbox path; direct tmux nudges are limited to re-nudge fallback.

