# cmd_3829 掲示板通知 fail-closed

## 結論

`scripts/bulletin_write.sh` は掲示板 YAML への投稿後、各通知先への `inbox_write.sh` を最大3回試行する。全試行失敗時は `logs/bulletin_notify_failures.yaml` へ対象・投稿者・entry_id・試行回数・本文を追記し、標準エラーへ最終失敗を出力して終了コード1を返す。投稿自体の entry_id は標準出力へ残る。

一時失敗から再送成功した場合は正常終了し、失敗ログを作らない。通知先ごとに独立して処理し、1先の失敗で他先の通知を省略しない。

## 変更と根因

- 変更対象: `scripts/bulletin_write.sh` 通知ループ
- 回帰対象: `tests/unit/test_bulletin_board.bats`
- 永続記録: `logs/bulletin_notify_failures.yaml`（flock で追記）
- 根因: 旧実装は `inbox_write.sh` の非ゼロ終了を警告1行へ変換し、投稿者の終了コードを成功のままにしていた
- 因果: `[[殿指摘20260710_1427_家老に回答未達]] -> [[通知失敗の握り潰し設計]] -> [[bulletin通知fail-closed化]]`

## 検証

- `bash -n scripts/bulletin_write.sh`: PASS
- `bats tests/unit/test_bulletin_board.bats`: 通知成功・一時失敗からの再送成功・最終失敗記録を含む全ケースを実行
- 最終失敗ケース: retry=3、終了コード=1、専用ログに `target` と `attempts: 3` を記録
- 再送成功ケース: 初回失敗後2回目成功、終了コード=0、失敗ログなし

