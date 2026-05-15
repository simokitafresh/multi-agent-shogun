---
codd:
  node_id: req:script:inbox-write
  type: requirement
  status: approved
  confidence: 0.9
  source: brownfield
  implementation:
  - scripts/inbox_write.sh
---

# inbox_write.sh Brownfield Requirements

## Purpose

`scripts/inbox_write.sh` must be the atomic mailbox writer and wake-up bridge for agent-to-agent communication.

## Functional Requirements

- FR-1: Accept target, content, optional type, sender, and action fields and reject missing or malformed targets.
- FR-2: Validate target agents and enforce sender routing rules, including ninja-to-shogun prohibition.
- FR-3: Serialize message records into `queue/inbox/{agent}.yaml` with timestamps, ids, type, sender, content, read state, and optional action.
- FR-4: Use lock files appropriate for WSL2 `/mnt/*` paths to prevent concurrent write loss.
- FR-5: Block duplicate active `task_assigned` deployments for the same parent cmd.
- FR-6: For task assignments, provide lesson-injection safety net behavior when deploy helpers did not inject lessons.
- FR-7: For report notifications, run report format checks and trigger downstream review/completion behavior.
- FR-8: Resolve panes and send CLI-specific nudges only after message persistence.

## Safety Requirements

- SR-1: Treat inbox persistence as the durable source of truth; wake-up nudges are secondary.
- SR-2: Never allow ninja senders to bypass karo and message shogun directly.
- SR-3: Preserve flock/atomic write semantics for all mailbox updates.

