# snapshot path-lock統合後の残存待機実測

- 実測日: 2026-07-20 JST
- 対象: `scripts/ninja_monitor.sh` の `write_karo_snapshot`
- 方法: 毎回新規の隔離`SCRIPT_DIR`を作り、正常、同一snapshot lockを250ms保持する競合、lock pathをdirectory化した異常を各3回実行した。
- 欠落判定: 成功時は期待するninja行がない場合を欠落、異常時は不完全snapshotが公開されないことを安全契約とした。

## 実測

| 条件 | run | rc | wall ms | lock待機 ms | 期待行欠落 | tmp残留 |
|---|---:|---:|---:|---:|---:|---:|
| 正常 | 1 | 0 | 56 | 0 | 0 | 0 |
| 正常 | 2 | 0 | 49 | 0 | 0 | 0 |
| 正常 | 3 | 0 | 61 | 0 | 0 | 0 |
| 競合 | 1 | 0 | 253 | 217 | 0 | 0 |
| 競合 | 2 | 0 | 270 | 211 | 0 | 0 |
| 競合 | 3 | 0 | 266 | 216 | 0 | 0 |
| 異常 | 1 | 1 | 5 | 0 | 1（公開0） | 0 |
| 異常 | 2 | 1 | 6 | 0 | 1（公開0） | 0 |
| 異常 | 3 | 1 | 12 | 0 | 1（公開0） | 0 |

正常中央値は56ms。競合中央値は266msで、外部holder解放までの実測待機中央値は216msだった。正常・競合は6/6成功、期待行6/6、欠落0、tmp残留0。異常は3/3が非0で即時停止し、不完全snapshot公開0、tmp残留0だった。

## 次律速と最速候補

path単位lockにより隔離fixtureと本番writerの偽競合は解消した。一方、現行はsnapshot全生成（task/report走査、tmux参照を含む約49–61ms）を排他区間内で行うため、実競合ではholder時間がそのままwallへ加算される。

欠落0を維持する最速候補は、private tempへの生成をlock外で行い、lock内を「現行generation確認 → 新しい世代だけatomic `mv`」へ縮小する方式である。単純なlock除去やnonblocking skipはsnapshot欠落を生むため候補外。古い生成物による新snapshot上書きを防ぐgeneration比較を採用条件とする。

## 二値判定

- AC1: PASS — 正常/競合/異常を各3回、合計9/9回実測し、wall・lock待機・欠落・tmp残留を記録した。
- AC2: PASS — 成功経路6/6で欠落0を維持し、generation fencing付きlock外生成＋lock内atomic publishを最速候補として特定した。

## 因果

`[[cmd_karo_impl_snapshot_path_lock_202607202139]] -> [[snapshot生成全体がlock内]] -> [[generation_fenced_publish_only_lock]]`
