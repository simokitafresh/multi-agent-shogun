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

- Agent validation helpers: `is_core_agent`, `known_agent_from_fs`, `sender_is_ninja_from_fs`, and config fallback loading. — [[inbox_write.sh]] L51
- YAML helpers: `inbox_yaml_field_get`, `inbox_yaml_emit_field`, `inbox_collect_records`, `inbox_write_records`, and `inbox_replace_file_with_retry`.
- Duplicate deployment gate: `find_active_peer_deployments` and `notify_karo_duplicate_deploy_block`. — [[inbox_write.sh]] L164
- Lesson safety net: task assignment path checks and injects universal lessons if missing.
- Report path extraction and template detection: locate relevant report YAMLs and guard report notification quality.
- Delivery helpers: pane resolution, tmux timeout wrapper, Codex-specific task nudge, and delivery verification.

## Data Boundaries

Inputs are CLI arguments, `queue/tasks/`, `queue/inbox/`, report YAMLs, agent config, and tmux pane metadata. Outputs are inbox YAML records, wake-up nudges, duplicate-deployment notifications, report-gate side effects, and logs.

## Review Round-trip SLO and Async Boundary

- SLO: isolated overflow fixtures for both `karo -> gunshi` (`review_draft`) and `gunshi -> karo` (`review_result`) must keep entry-to-persistence p95 below 130ms and must be strictly faster than the recorded before p95.
- Synchronous boundary: routing guards, message serialization, flock acquisition, durable inbox append, overflow retention, and the observable watcher nudge/delivery check remain mandatory before a delivery is accepted.
- Asynchronous boundary: memory DB mirroring remains best-effort after durable YAML persistence; it must not delay or replace mailbox persistence.
- Overflow compaction uses one awk selection/emission pass, preserving every unread record and the newest 30 read records. This replaces the prior awk-to-Bash-array-to-per-record-write reconstruction without changing retention semantics.
- Regression entry: `tests/unit/test_inbox_write.bats` T-008/T-009/T-010 guard retention and lost updates; `tests/unit/test_inbox_watcher_delivery_latency.bats` guards watcher delivery evidence and latency reporting. The round-trip benchmark protocol and before/after evidence are recorded in `docs/research/cmd_karo_hotfix_speed_pipeline_inbox_roundtrip_202607162255.md`.

## Cross-References

- [[inbox_write.sh]] is the primary implementation; its header (line 2) declares `semantic-links: [[YAML安全書込み]], [[インフラ設計意図カタログ]]` and line 4 documents the usage interface as `bash scripts/inbox_write.sh <target_agent> <content> [type] [from] [action]`.
- [[inbox_write_brownfield.md]] is the CoDD brownfield report for this target and records the elicitation run.
- [[cmd_2762_inbox_write_requirements.md]] is the requirements baseline; it defines FR-1 through FR-8 (target validation, routing enforcement, WSL2-safe locking, duplicate deployment blocking, lesson-injection safety net, report gate side-effects) and SR-1 through SR-3 (persistence-first, ninja-to-shogun prohibition, flock semantics) — this design satisfies `req:script:inbox-write` (line 3 of requirements).

## Brownfield Evidence

- `scripts/inbox_write.sh` lists supported message types in its header.
- `scripts/inbox_write.sh` validates target and sender routing before persistence.
- `scripts/inbox_write.sh` blocks duplicate task assignment before writing the message.
- `codd/brownfield/inbox_write_brownfield.md` records the CoDD brownfield run for this target.
- Test coverage: [[test_inbox_write.bats]] (line 2: "inbox_write.sh ユニットテスト T-001 ~ T-012: リグレッションテスト仕様書実装") covers the core routing, persistence, and gate side-effect behaviors.
