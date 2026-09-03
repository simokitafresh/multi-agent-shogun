---
name: x-post-pipeline
description: |
  X運用自動化P0(台帳+calendar)。stock_ledger.yaml(note 49本+完全ガイドの数字ホワイトリスト付き一覧)と
  slot_calendar.yaml(4週×週3枠A/B/C+月次D=13slot)を読み、下書き作成の材料として使う。投稿は行わない。
  TRIGGER: X投稿の下書き作成、週次枠の記事選定、台帳の参照
  DO NOT TRIGGER: 実際のX投稿(P1未実装、scripts/x_ops/x_post_gate.sh PASS後もAPI投稿は別途)、
  note記事本体の編集、dm-signal側の変更
allowed-tools:
  - Read
  - Bash
---

# X Post Pipeline (P0)

## What
`stock_ledger.yaml`(記事1件=1entry。url/title/公開日/frames[A/B/C]/usable_numbers/first_line_candidate)と
`slot_calendar.yaml`(週3枠+月次Dの13slotに台帳entryを割当。angle=切り口)を提供する。

## When
週次枠(マニュアル`docs/research/bam_delivery_manual_grok_20260902.md`§5)の下書きを作る時、
`slot_calendar.yaml`の該当weekのslotから`ledger_key`で`stock_ledger.yaml`の該当entryを引き、
`usable_numbers`(空なら数字は使わない)と`draft_seed`を元に§4包装ルールで整形する。

## NOT When
- `usable_numbers`が空のentryで数字を作文しない(推測禁止)
- 台帳にない記事URL・台帳にないticker/保有シグナルを下書きに入れない
- 生成した下書きは`scripts/x_ops/x_post_gate.sh <file>`でPASSしない限り投稿しない
