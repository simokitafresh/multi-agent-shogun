# inbox_write.sh CoDD speedup follow-up (cmd_1979)

- cmd: cmd_1979
- 実施者: hayate
- CoDD Phase到達: Phase 5(before/after計測+実装+検証)。spec先行作成

## Goal

- Target: `scripts/inbox_write.sh`
- Baseline: cmd_1960 after result `50ms`
- Goal: 機能変更なしで通常 write path の残存固定費を削る

## Before

- Reference baseline from cmd_1960:
  - isolated normal path average `50ms`
  - command: `bash scripts/inbox_write.sh karo "bench" wake_up saizo bench`
- Current suspicion:
  - common path still pays target/sender validation cost even when the target can be resolved from queue state alone
  - inbox append path still counts messages via `awk` on every write

## Bottleneck analysis

### Candidate 1: filesystem fast-path for agent resolution

- Current path loaded `agent_config.sh` to validate target/sender when `INBOX_WRITE_TEST` was unset.
- For common production writes, much of that information already exists in:
  - core roles: `shogun`, `karo`, `gunshi`
  - ninja task files: `queue/tasks/{agent}.yaml`
  - inbox files: `queue/inbox/{agent}.yaml`
- A fast path can therefore validate the common case without sourcing `agent_config.sh`.

### Candidate 2: lighter message count on append

- `inbox_append_message_locked()` calls `inbox_message_count()` before deciding whether overflow handling is needed.
- Existing implementation used `awk` for a simple `^- ` line count.
- `grep -c '^- '` is sufficient for this narrow case and was measurably cheaper in looped microbench.

## Implementation

1. Added common-path helpers:
   - `is_core_agent()`
   - `known_agent_from_fs()`
   - `sender_is_ninja_from_fs()`
2. Changed validation flow:
   - first resolve target/sender from static roles + `queue/tasks` / `queue/inbox`
   - only fall back to `ensure_agent_config_loaded()` when filesystem fast-path cannot resolve the target
3. Replaced `inbox_message_count()` internals from `awk` to `grep -c`
4. Added regression tests proving filesystem fast-path works even if `agent_config.sh` would fail when sourced

## Validation

- `bash -n scripts/inbox_write.sh`
- `shellcheck -S warning scripts/inbox_write.sh`
- `bats tests/unit/test_inbox_write.bats`

## After

### Isolated benchmark (same cmd_1960-style workspace)

- command: `INBOX_WRITE_ROOT_OVERRIDE=<tmp> bash scripts/inbox_write.sh karo "bench" wake_up saizo bench`
- batch 1: `0.02 0.02 0.03 0.02 0.02`
- batch 2: `0.03 0.02 0.02 0.02 0.02`
- batch 3: `0.03 0.02 0.02 0.02 0.02`
- overall average: `22ms`
- overall median: `20ms`

### Live worktree benchmark

- runs: `0.03 0.04 0.04 0.05 0.06`
- average: `44ms`
- median: `40ms`

## Result

- baseline `50ms` → isolated average `22ms` (`-56%`)
- baseline `50ms` → live worktree median `40ms` (`-20%`)
- functionality unchanged:
  - normal inbox write still succeeds
  - ninja→shogun direct send still blocks
  - existing `report_received`, forwarding, retry, and overflow tests all pass
