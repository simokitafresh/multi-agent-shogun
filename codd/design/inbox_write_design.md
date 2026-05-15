---
codd:
  node_id: design:script:inbox-write
  type: design
  status: approved
  confidence: 0.9
  source: brownfield
  depends_on:
  - id: req:script:inbox-write
    relation: satisfies
    semantic: governance
  implementation:
  - scripts/inbox_write.sh
---

# inbox_write.sh Brownfield Design

## Entry Flow

The script validates arguments and routing, computes the inbox path and lock path, generates message metadata, applies type-specific gates, appends the message under lock, and then performs wake-up or downstream side effects.

## Core Components

- Agent validation helpers: `is_core_agent`, `known_agent_from_fs`, `sender_is_ninja_from_fs`, and config fallback loading.
- YAML helpers: `inbox_yaml_field_get`, `inbox_yaml_emit_field`, `inbox_collect_records`, `inbox_write_records`, and `inbox_replace_file_with_retry`.
- Duplicate deployment gate: `find_active_peer_deployments` and `notify_karo_duplicate_deploy_block`.
- Lesson safety net: task assignment path checks and injects universal lessons if missing.
- Report path extraction and template detection: locate relevant report YAMLs and guard report notification quality.
- Delivery helpers: pane resolution, tmux timeout wrapper, Codex-specific task nudge, and delivery verification.

## Data Boundaries

Inputs are CLI arguments, `queue/tasks/`, `queue/inbox/`, report YAMLs, agent config, and tmux pane metadata. Outputs are inbox YAML records, wake-up nudges, duplicate-deployment notifications, report-gate side effects, and logs.

## Brownfield Evidence

- `scripts/inbox_write.sh` lists supported message types in its header.
- `scripts/inbox_write.sh` validates target and sender routing before persistence.
- `scripts/inbox_write.sh` blocks duplicate task assignment before writing the message.
- `codd/brownfield/inbox_write_brownfield.md` records the CoDD brownfield run for this target.

