# ホットスクリプト集中高速化 第七弾 — final checkpoint snapshot

## 結論

第三世代final checkpointも **FAIL**。race根治後の固定SHA
`aed5dfb9b76cdd01c7fae2184bfb8063f32a9422` をclean detached worktreeで
unit全量1回だけ計測した。第一・第二世代を止めた `test_deploy_task.bats`
test 7はPASSしたが、別の `test_lgtm_bundle_guard.bats` がsetup_fileで失敗した。
成功runだけを序列SSOTにする契約によりper-file/per-suite ledgerはpublishされず、
wave-finalとのTOP10比較および第七弾の総短縮効果は確定不能である。

## 第三世代の実行境界とreceipt

| 項目 | 実測 |
|---|---|
| 実行境界 | `/tmp/saizo-round7-gen3-nAL7kI`、clean detached worktree、実行前dirty 0 |
| 採用HEAD | `aed5dfb9b76cdd01c7fae2184bfb8063f32a9422` |
| command | `BATS_CACHE=0 bash scripts/run_tests.sh unit` |
| 実行回数 | 1 |
| receipt | `logs/test_receipts/run_tests_20260729T230432_3742785.json` |
| receipt SHA-256 | `bec58524f05a283848148e7129bb011361798b4f811535c6a4ff31d2ef8fb480` |
| artifact | `logs/test_receipts/run_tests_20260729T230432_3742785.output` |
| artifact SHA-256 | `711412735a612222434dd6b05986ad9a68ad93dde82b0eda0a6f8a6d5000ac84` |
| TAP SHA-256 | `44b57093c11daebe806c0ed56ae6d1f0f7dcab82331e6cba2a9e2a52a8fb6fd5` |
| run_id | `20260729T230432.3742785.18086` |
| source_fingerprint | `3d21b6f581faf829e4e9ed2585756d1f1199ac29e946bac52ba03e5b452c95f3` |
| 結果 | rc=1、FAIL file 1、SKIP 0、cache 0 |
| duration | 425,541ms |

receiptのscope identityは selected 184 / discovered 184 / started 113 /
executed 113 / failed 1。observed/declared test countは2,807/2,819、skip_countは0。

## 失敗の一次結果

失敗対象は `tests/unit/test_lgtm_bundle_guard.bats` のsetup_file:

```text
not ok 1 setup_file failed
# (from function `setup_file' in test file
# /tmp/saizo-round7-gen3-nAL7kI/tests/unit/test_lgtm_bundle_guard.bats, line 8)
#   `[ -x "$LOG_APPEND_SCRIPT" ] || return 1' failed
# bats warning: Executed 1 instead of expected 7 tests
```

race根治の直接対象 `tests/unit/test_deploy_task.bats` はfile全体rc=0。
checkpoint任務は診断・修正をscopeに含まず、追加runを行わず第三世代FAILとして終端した。

## 4識別子結合と比較判定

| 識別子 | 値 |
|---|---|
| run_id | `20260729T230432.3742785.18086` |
| commit_sha | `aed5dfb9b76cdd01c7fae2184bfb8063f32a9422` |
| source_fingerprint | `3d21b6f581faf829e4e9ed2585756d1f1199ac29e946bac52ba03e5b452c95f3` |
| output_sha256 | `711412735a612222434dd6b05986ad9a68ad93dde82b0eda0a6f8a6d5000ac84` |

同一4識別子の結合件数は receipt 1 / per-file 0 / per-suite 0。失敗runの
pending batchはpublishされず、選択184 fileとのexact joinは成立しない。

| 比較対象 | before: wave-final | after: 第三世代checkpoint | 判定 |
|---|---:|---:|---|
| 全量suite wall | 747.541s | 425.541s（失敗run） | 比較不可 |
| TOP10各file wall | 10件あり | success ledgerなし | 比較不可 |

afterは184 files完走の成功値ではないため、短縮率を算出・採用してはならない。

## 世代履歴

| 世代 | fixed SHA | duration | 結果 |
|---|---|---:|---|
| 第一世代 | `966b4fbe84d4ad9f244a2408ab2adfadac9e6d3a` | 353.669s | `test_deploy_task.bats` test 7 FAIL |
| 第二世代 | `b480b5b03e618c5fcd2794cb7ecdd7219f968acd` | 590.775s | 同test 7 FAIL |
| 第三世代 | `aed5dfb9b76cdd01c7fae2184bfb8063f32a9422` | 425.541s | deploy test 7 PASS、`test_lgtm_bundle_guard.bats` setup FAIL |

origin: `[[第二世代checkpoint同一test7_FAIL]] -> [[deploy_task固定tmp共有race根治]] -> [[第三世代別setup_FAIL]] -> [[第七弾総短縮効果未確定]]`
