# cmd_2512 CoDD Spec — post-shogun-inbox-check 非shogun高速化 (2026-05-03)

## Target

- `.claude/hooks/post-shogun-inbox-check.sh`
- Scope: 非shogun pane の PostToolUse hot path を高速化し、shogun pane の inbox 未読警告を維持する。

## Acceptance Criteria

| AC | Binary check |
|----|--------------|
| AC1 | 非shogun path median <= 3ms |
| AC2 | shogun inbox unread check の既存機能を維持し、関連テストが PASS |

## Before

| Path | Method | Samples | Median |
|------|--------|---------|--------|
| non-shogun cached path | `time TMUX_PANE="$pane" .claude/hooks/post-shogun-inbox-check.sh` 7 runs | 10,10,11,8,12,10,8ms | 10ms |

Task YAML baseline: 現行 7.9ms。

## Bottleneck

| Cause | Detail |
|-------|--------|
| bash startup | `/mnt/c` 上の hook shell startup が 7ms 前後 |
| per-call TTL check | 非shogunでも `find -mmin` を毎回起動 |
| cache read | 非shogunは agent_id 値を読む必要がないが毎回 read していた |

## Implementation

| Change | Reason |
|--------|--------|
| shebang `#!/bin/dash` | POSIX範囲の構文に収め、起動コストを削減 |
| non-shogun marker `/tmp/shogun_not_shogun_${TMUX_PANE}` | hot path を marker existence check + exit に短縮 |
| shogun positive cache keeps TTL validation | pane再配置後の stale shogun cache を避け、未読警告機能を維持 |
| `SHOGUN_INBOX_PATH` / `SHOGUN_LORD_CONV_PATH` / `SHOGUN_RECOVERY_MARKER` env override | 実運用デフォルトを保ったまま unit test で shogun path を検証 |

## After

| Path | Method | Samples | Median |
|------|--------|---------|--------|
| non-shogun marker path | `time TMUX_PANE="$pane" .claude/hooks/post-shogun-inbox-check.sh` 21 runs | 4,3,3,3,3,3,3,3,3,3,3,3,4,3,3,3,3,3,3,3,3ms | 3ms |

## Verification

| Check | Result |
|-------|--------|
| `dash -n .claude/hooks/post-shogun-inbox-check.sh` | PASS |
| `bats tests/unit/test_post_shogun_inbox_check.bats` | 2/2 PASS |
| `bats tests/unit/test_write_edit_combined_hooks.bats` | 7/7 PASS |

## Notes

- 非shogun marker は first run で tmux から agent_id を解決した後に作成する。以後の PostToolUse では tmux IPC と cache file read を避ける。
- shogun marker は作らない。shogun path は従来通り inbox/recovery/lord conversation を確認する。
