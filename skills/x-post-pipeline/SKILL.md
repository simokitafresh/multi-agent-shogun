---
name: x-post-pipeline
description: |
  X運用自動化P1(台帳+calendar+XDK)。stock_ledger.yaml(note 49本+完全ガイドの数字ホワイトリスト付き一覧)と
  slot_calendar.yaml(4週×週3枠A/B/C+月次D=13slot)を読み、x_post.shで下書き・gate・承認・公式XDK投稿を行う。
  TRIGGER: X投稿の下書き作成、週次枠の記事選定、台帳の参照、XDK投稿
  DO NOT TRIGGER: note記事本体の編集、dm-signal側の変更
allowed-tools:
  - Read
  - Bash
---

# X Post Pipeline (P1)

## What
`stock_ledger.yaml`(記事1件=1entry。url/title/公開日/frames[A/B/C]/usable_numbers/first_line_candidate)と
`slot_calendar.yaml`(週3枠+月次Dの13slotに台帳entryを割当。angle=切り口)を提供する。
`x_post.sh post` は承認marker・token・5MB画像上限を満たさない限り投稿しない。
認証は `xdk.oauth2_auth.OAuth2PKCEAuth` + `Client(token=tokens)` のOAuth2 user contextを使う。
添付候補は `media/experience-placeholder.png` と `media/comparison-placeholder.png`（いずれも5MB以下）で、保有・ticker情報を含めない。

## When
週次枠(マニュアル`docs/research/bam_delivery_manual_grok_20260902.md`§5)の下書きを作る時、
`slot_calendar.yaml`の該当weekのslotから`ledger_key`で`stock_ledger.yaml`の該当entryを引き、
`usable_numbers`(空なら数字は使わない)と`draft_seed`を元に§4包装ルールで整形する。

## NOT When
- `usable_numbers`が空のentryで数字を作文しない(推測禁止)
- 台帳にない記事URL・台帳にないticker/保有シグナルを下書きに入れない
- 生成した下書きは`scripts/x_ops/x_post_gate.sh <file>`でPASSしない限り投稿しない
