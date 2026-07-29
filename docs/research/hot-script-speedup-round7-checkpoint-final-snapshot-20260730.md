# ホットスクリプト集中高速化 第七弾 — final checkpoint snapshot

## 結論

第二世代final checkpointも **FAIL**。根因修正後の固定SHA
`b480b5b03e618c5fcd2794cb7ecdd7219f968acd` をclean detached worktreeで
unit全量1回だけ計測したが、第一世代と同じ `test_deploy_task.bats` test 7が失敗した。
成功runだけを序列SSOTにする契約によりper-file/per-suite ledgerはpublishされず、
wave-finalとのTOP10比較および第七弾の総短縮効果は確定不能である。

## 第二世代の実行境界とreceipt

| 項目 | 実測 |
|---|---|
| 実行境界 | `/tmp/tobisaru-round7-gen2-4OqPhh`、clean detached worktree、実行前dirty 0 |
| 採用HEAD | `b480b5b03e618c5fcd2794cb7ecdd7219f968acd` |
| command | `BATS_CACHE=0 bash scripts/run_tests.sh unit` |
| 実行回数 | 1 |
| receipt | `logs/test_receipts/run_tests_20260729T215550_2995102.json` |
| receipt SHA-256 | `5739c8fc0819d3c577013a2261d87cbe7ebb11bcfb17b86a419b4489e4d2f229` |
| artifact | `logs/test_receipts/run_tests_20260729T215550_2995102.output` |
| artifact SHA-256 | `75f0d83aa62941d4a57f9ee80209dc971cdd6cfdac24122363d9f241b981cd38` |
| TAP SHA-256 | `b570688a4e7f75f376b2ecce505d55c0d2d6506806fe6d70e920f285a22249b6` |
| run_id | `20260729T215550.2995102.29712` |
| source_fingerprint | `4ecb79b2441d95978261484121439f2b7720b2f3a75607db74c4dec3c28718d9` |
| 結果 | rc=1、FAIL file 1、SKIP 0、cache 0 |
| duration | 590,775ms |

receiptのscope identityは selected 184 / discovered 184 / started 147 /
executed 147 / failed 1。observed/declared test countは2,865/2,865、skip_countは0。

## 失敗の一次結果

失敗対象は `tests/unit/test_deploy_task.bats` のtest 7で、53 tests中52 PASS・1 FAIL:

```text
not ok 7 report commit contract inherits explicit task value and falls back only when absent
# (in test file tests/unit/test_deploy_task.bats, line 161)
#   `wait "$pid"' failed
```

固定SHAは「direct validator root」修正commitだが、5ケースを並列起動して全PIDを
`wait`する当該contractは全量環境でなお非0終了した。checkpoint任務は診断・修正を
scopeに含まないため、追加runを行わず第二世代FAILとして終端する。

## 4識別子結合と比較判定

| 識別子 | 値 |
|---|---|
| run_id | `20260729T215550.2995102.29712` |
| commit_sha | `b480b5b03e618c5fcd2794cb7ecdd7219f968acd` |
| source_fingerprint | `4ecb79b2441d95978261484121439f2b7720b2f3a75607db74c4dec3c28718d9` |
| output_sha256 | `75f0d83aa62941d4a57f9ee80209dc971cdd6cfdac24122363d9f241b981cd38` |

同一4識別子の結合件数は receipt 1 / per-file 0 / per-suite 0。要求値
receipt 1 / per-file 184 / per-suite 1を満たさず、選択集合とのexact joinも成立しない。

| 比較対象 | before: wave-final | after: 第二世代checkpoint | 判定 |
|---|---:|---:|---|
| 全量suite wall | 747.541s | 590.775s（失敗run） | 比較不可 |
| TOP10各file wall | 10件あり | success ledgerなし | 比較不可 |

afterは184 files完走の成功値ではないため、短縮率を算出・採用してはならない。

## 世代履歴

| 世代 | fixed SHA | duration | 結果 |
|---|---|---:|---|
| 第一世代 | `966b4fbe84d4ad9f244a2408ab2adfadac9e6d3a` | 353.669s | 同test 7 FAIL |
| 第二世代 | `b480b5b03e618c5fcd2794cb7ecdd7219f968acd` | 590.775s | 同test 7 FAIL |

origin: `[[第一世代checkpoint合成回帰FAIL]] -> [[根因修正b480b5b]] -> [[第二世代同一test7_FAIL]] -> [[第七弾総短縮効果未確定]]`
