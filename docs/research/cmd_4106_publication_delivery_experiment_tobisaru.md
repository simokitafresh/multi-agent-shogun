# cmd_4106 publication / delivery 独立実験

- 実施日: 2026-07-20
- 固定base: `75f7c530f59093db4562fbf0a21fbad3b2e75893`
- 実験環境: `/tmp/tobisaru4106b.8ZnHAT` のshared isolated clone。正本script・正本queue・実inboxは変更していない。
- 方法: `DEPLOY_TASK_LIB_ONLY=1` で固定baseの関数を読み、候補を1件ずつ独立fixtureで実行。wall clockは各呼出し前後の `date +%s%N` 差を切上げmsで記録した。ntfyのみ外部送信を禁止し、clone内 `ntfy_cmd.sh` の入口を成功stub化してspawn/markerまでを測定した。

## 実測結果と採否

| 候補 | wall_ms | rc | 成果物検証 | 採否 |
|---|---:|---:|---|---|
| report publication (`generate_report_template`) | 1579 | 0 | 対象report 1件、欠落0、重複0 | 採用。全候補中の支配項であり、同期publication内部の最優先短縮対象 |
| delivery (`safe_inbox_write`) | 406 | 0 | tobisaru isolated inbox新規message 1件、欠落0、重複0 | 採用。publication後の永続配送境界を維持したまま二次短縮対象 |
| post delivery verify (`deploy_task_post_deploy_verify`) | 10 | 0 | pane不存在fixtureを正常処理。生成物契約なし、欠落0、重複0 | 不採用。短縮余地が小さく配送確認の意味を削る価値なし |
| draft review notify (`maybe_notify_draft_review`) | 643 | 0 | gunshi isolated inbox 1件 + marker 1件、欠落0、重複0 | 採用。同期post-delivery支配候補。永続化後の遅延実行候補 |
| initial ntfy (`notify_initial_deploy_ntfy_once`) | 65 | 0 | marker 1件、成功stub spawn 1回、欠落0、重複0 | 不採用。既にbackground spawnで、同期費用は小さい |
| deferred drain (`deploy_task_drain_deferred`) | 591 | 0 | 入力2件→processed=1/skipped=1/failed=0/backlog=0、cache 1件、欠落0、重複0 | 採用（現行配置維持）。同期経路へ戻さず、single-flight backgroundのままにする |

## 結論

支配項は report publication の1579ms。次の実験順は report publication → draft review notify → deferred drain → delivery。post verifyとntfyは合計75msに留まり、機能境界を削っても全体への寄与が小さいため対象外とする。期待成果物は全候補合計で report 1、delivery message 1、draft message 1、draft marker 1、ntfy marker 1、deferred cache 1、backlog 0で、実測も同数だった（欠落0、重複0）。
