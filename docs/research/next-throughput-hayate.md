# 完了pipeline最終checkpoint候補 実測

計測日: 2026-07-20 / worker: hayate / task: `cmd_karo_next_throughput_hayate_2207`

## 結論

`related-only`を採用候補とする。同一HEADの3試行すべてで292/292 PASS、FAIL 0、SKIP 0、declared=observed（欠落0）。wall中央値は51,192msで、integration中央値143,674msより64.4%短い。

## 候補と一次結果

| 候補 | 対象 | wall_ms（3回） | 品質 | 判定 |
|---|---|---:|---|---|
| full | `run_tests.sh unit`の直近同日receipt 3本 | 437,521 / 406,469 / 559,195 | 1/3 PASS、2/3 FAIL、SKIP 0。HEAD・対象数も不一致 | 不採用 |
| related-only | `cmd_complete_gate*`、`cmd_complete_{insight,resume,wrapper}`の12ファイル | 45,659 / 54,884 / 51,192 | 各292/292 PASS、FAIL 0、SKIP 0、欠落0 | **採用候補** |
| integration | related 12 + 完了境界9ファイル | 123,235 / 143,674 / 168,935 | 687/687、687/687、686/687。3回目にheavy-job zombie判定1 FAIL、SKIP 0、欠落0 | 不採用 |

fullのreceiptは `run_tests_20260720T111934_1261680.json`、`run_tests_20260720T112743_1441136.json`、`run_tests_20260720T113446_1597826.json`。比較条件が揃わないこと自体を品質差として扱い、最速候補にはしない。

related receiptは `run_tests_20260720T131028_2837716.json`、`run_tests_20260720T131114_2865570.json`、`run_tests_20260720T131209_2903928.json`。integration receiptは `run_tests_20260720T131300_2938812.json`、`run_tests_20260720T131503_3021000.json`、`run_tests_20260720T131727_3102664.json`。

integration第3試行の唯一のFAILは `test_heavy_job_admission.bats` の「GitHub runner型: 終了済みzombieだけのprocess groupはdrain済みとして扱う」。検査縮小やSKIP化は行わず、候補をそのまま不採用とした。

## 適用境界

related-onlyは完了pipeline自身の変更に対する最終checkpoint候補であり、別subsystem変更やwave統合の全量品質保証を置換しない。対象manifestの12ファイル、declared=observed、FAIL 0、SKIP 0を同時に満たす場合だけ有効とする。

origin: `[[completion_pipeline_next_bottleneck]] -> [[full_and_integration_cost_or_flake]] -> [[related_only_final_checkpoint_candidate]]`
