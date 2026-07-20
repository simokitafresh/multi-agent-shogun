# 完了統合 FAIL4 retro（hayate）

- 対象: `cmd_karo_hotfix_completion_pipeline_experiment_20260720200304` の最終 unit receipt `logs/test_receipts/run_tests_20260720T103551_627344.json`
- 基準: 修正前 `75f7c530f59093db4562fbf0a21fbad3b2e75893` を `/tmp` へ `git archive` した独立fixture、修正後は現HEAD。各条件2回。
- 元の全量結果: 1,879件、FAIL 4、SKIP 0、wall 367,974ms。誤PASS 0、誤FAIL 4。

## §1 原因別一次結果

| FAIL | 発生条件 | 真因 | 修正前 wall_ms (2回) | 盲目的再試行 | 修正後 wall_ms (2回) | 誤PASS / 誤FAIL |
|---|---|---|---:|---:|---:|---:|
| `test_run_tests`: default all includes root | 無引数runnerを実行 | defaultが`affected`へ変わったのにfixtureが旧`all`契約を期待 | 819 / 837 | 1回再試行して再FAIL | 1,582 / 1,635 | 0 / 1→0 |
| `test_run_tests`: all ignores pass cache | 外側snapshotを1件注入して明示`all` | isolated fixtureが`RUN_TESTS_SNAPSHOT_MANIFEST`を継承し、fixture内2件でなく外側1件を選択 | 1,517 / 1,291 | 1回再試行して再FAIL | 1,553 / 1,591 | 0 / 1→0 |
| `test_run_tests`: unit timing row | 外側snapshotを2件注入して`unit` | 同じ環境漏洩でledgerがfixture内1件ではなく外側2件を記録 | 1,265 / 1,160 | 1回再試行して再FAIL | 4,189 / 1,706 | 0 / 1→0 |
| `test_report_commit_identity`: batch legacy result | batch fixtureを実行 | 厳格化されたreport契約に必須の`lessons_useful` listがfixtureにない | 497 / 464 | 1回再試行して再FAIL | 970 / 962 | 0 / 1→0 |

合計は修正前2試行ともFAIL 4/4、修正後2試行ともPASS 4/4。SKIPは全条件0。したがって時間経過や同一コマンド再実行では直らない決定論的fixture不整合であり、全量再試行は誤FAILを反復するだけだった。

## §2 最速候補と適用境界

採用候補は「production再変更なしで、契約変更と同じcommit境界にfixture同期を置き、focused 4件を1 checkpointだけ実行」である。

1. runner default変更時は、旧defaultを検査するfixtureを明示`all`へ更新する。
2. 独立aggregate fixtureの`setup()`で`RUN_TESTS_ACTIVE`と`RUN_TESTS_SNAPSHOT_MANIFEST`を共に解除する。
3. report validator必須field追加時は、batch fixtureに最小の有効mappingを同時追加する。
4. focused 4件がPASSしてから最終統合checkpointを1回だけ実行する。FAILのまま同一全量suiteを再試行しない。

適用境界はcontract/fixture不整合と外側環境漏洩に限定する。productionロジックのFAIL、非決定的競合、receipt incomplete、SKIP、未知FAILには適用せず、原因別の一次再現を先に行う。品質差分は修正前誤FAIL4→修正後0、誤PASS0→0、SKIP0→0で、検査縮小や閾値緩和はない。

## §3 再試行削減量

- 旧手順: unit全量367,974ms + 原因未確定の再試行（今回の2回目もFAIL 4/4）。
- 候補: focused 4件の修正後1回目合計8,294msでPASS 4/4を確認後、統合checkpointは1回だけ。
- 無効な再試行: 原因ごと1回、合計4回を0回へ削減。全量再試行換算では少なくとも1回（約367,974ms）を削減可能。

origin: `[[completion_pipeline_FAIL4]] -> [[fixture_contract_staleness_and_snapshot_leak]] -> [[focused_once_then_single_integration_checkpoint]]`
