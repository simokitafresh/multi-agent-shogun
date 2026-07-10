# cmd_3828 inbox lost-update guard

- 実施日: 2026-07-10
- 対象: `.claude/hooks/pre-write-edit-combined.sh`
- 原因仮説: `queue/inbox` は symlink で、Write/Edit の直接更新は `inbox_*` の flock 更新と競合し、既読・配備通知を lost update で消失させ得る。

## 実装

`inbox_direct_write_guard` を Write/Edit/MultiEdit の共通フックへ追加した。入力論理パスの `*/queue/inbox/*` と、`realpath -m` 解決後の `queue/inbox` symlink 実体配下を deny する。deny 文には正規経路を明示する。

正規経路:

- `bash scripts/inbox_write.sh <agent> <content>`
- `bash scripts/inbox_mark_read.sh <agent> [msg_id]`
- `bash scripts/inbox_archive.sh <agent>`

## 一次情報確認

```text
$ ls -l queue/inbox
lrwxrwxrwx ... queue/inbox -> /home/simokitafresh/.local/share/multi-agent-shogun/inbox
$ realpath -m queue/inbox
/home/simokitafresh/.local/share/multi-agent-shogun/inbox
```

`head -40 queue/inbox/hayate.yaml` で現物メッセージを確認し、未読の配備指示を `scripts/inbox_mark_read.sh` で flock 経由にて既読化した。

## 二値検証

| 条件 | 結果 | 証跡 |
|---|---|---|
| 直接 Write deny + 正規経路提示 | yes | `tests/unit/test_write_edit_combined_hooks.bats` 51/51 PASS |
| symlink 論理パス・解決先の直接 Edit/Write deny | yes | 同テストの新規3ケース PASS |
| inbox_write/mark_read/archive/bulletin 回帰 | yes | 88/88 PASS、`not ok` 0 |
| フック構文 | yes | `bash -n .claude/hooks/pre-write-edit-combined.sh` |

## 因果

`[[殿指摘20260710_1427_家老に回答未達]] -> [[flock非経由inbox書込みのLost_Update]] -> [[inbox直接書込みhook封鎖]]`
