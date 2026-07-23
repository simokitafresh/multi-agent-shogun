# cmd_4115 timing ratchet variance

## 結論

真因は(b)分散誤検知。旧判定は全ファイル混合集団のp95と最新単発値を比較しており、対象ファイル自身の代表値・分散を使っていなかった。ファイル別の全履歴median + `max(25%, 3*MAD)`をbudget、直近5実測medianを観測値に変更した。

## 一次計測

算出元: `grep '<basename>' logs/test_timing_ledger.tsv` と、`csv.DictReader`で `status=pass, cache_hit=0, suite_root in (all,unit)` を抽出し `statistics.median/pstdev` を計算。

| file | N | min | max | median | pstdev |
|---|---:|---:|---:|---:|---:|
| test_three_layer_preflight.bats | 34 | 9.273 | 203.616 | 41.812 | 36.701 |
| test_gist_verified_write.bats | 13 | 1.337 | 5.384 | 2.486 | 1.122 |
| test_gate_yaml_field_set_block_sync.bats | 14 | 1.768 | 5.942 | 2.985 | 1.429 |

旧コード現物: `baseline_files`（全ファイル混在）からp95を算出し、changed rowの単発`wall_sec > p95 * 1.25`でBLOCK。修正前の実台帳はp95=46.760秒、three-layer最新124.304秒を含みBLOCKだった。

## 境界検証

`tests/unit/test_gate_test_health_ledger.bats`へ固定系列contractを追加。履歴 `[10,10,10,100,10,10,10,10,10]` + 最新12はPASS、直近4値が20へシフトした系列はBLOCK。`bash scripts/run_tests.sh file tests/unit/test_gate_test_health_ledger.bats` は4/4 PASS、FAIL0、SKIP0（receipt `run_tests_20260721T182647_1254516.json`）。

## 修正前後

- 修正前: 全ファイルp95 + 最新単発値。実台帳 `総合判定: BLOCK`。
- 修正後: ファイル別median/MAD + 直近5件median。対象3件の一時スパイクは代表値回帰なしとして除外。
- 実台帳には対象3件とは別の6件が代表値ベースでもBLOCKとして残る。品質を弱めず、別の真性候補を偽陽性修正へ混入させない。

## 再開契約

中断時は本書、`scripts/gates/gate_test_health.sh`、`tests/unit/test_gate_test_health_ledger.bats`の差分を引き継ぐ。

---

## §cmd_4115 AC1 追記 (2026-07-24, tobisaru)

### AC1 偵察結果

**アルゴリズム現物**: `scripts/gates/gate_test_health.sh` L306-315
```
representative = statistics.median(values)  # ファイル別過去実測値のmedian
mad = statistics.median(abs(v-representative) for v in values)
budget = representative + max(representative*0.25, 3.0*mad)
observed = statistics.median((values+[current])[-min_runs:])  # 直近5件median
BLOCK if observed > budget
```
→ **既にmedian+MAD分散考慮型。偽陽性(Case b)はコード現物で否定。**

**仮説3テスト統計** (算出: `grep "<test>" logs/test_timing_ledger.tsv | awk '$9=="pass" && $11=="0" && ($4=="all" || $4=="unit")'`):

| file | N | min | max | median | MAD | budget | observed | BLOCK? |
|------|--:|----:|----:|-------:|----:|-------:|--------:|--------|
| test_three_layer_preflight.bats | 34 | 9.3 | 203.6 | 41.8 | 14.0 | 84.0 | 38.5 | **OK** |
| test_gist_verified_write.bats | 13 | 1.3 | 5.4 | 2.5 | 0.5 | 4.1 | 2.3 | **OK** |
| test_gate_yaml_field_set_block_sync.bats | 14 | 1.8 | 5.9 | 3.0 | 0.8 | 5.3 | 3.1 | **OK** |

**実際のBLOCK原因** (unit cohort最新run 2026-07-20T17:33:53):

| テスト | 初期値 | 直近5件 | observed | budget | 超過 |
|--------|-------:|--------:|--------:|-------:|------|
| test_ninja_scope_commit.bats | 5-11s | [30.6,90.6,37.1,63.6,28.5] | 37.1s | 28.3s | +31% |
| test_cmd_complete_gate_small_consolidated.bats | 2-2.5s | [3.7,6.6,8.8,9.0,3.1] | 6.6s | 3.3s | +98% |
| test_deploy_task_yaml_injection.bats | 12-24s | [40.2,41.6,54.1,62.9,35.4] | 41.6s | 36.4s | +14% |
| test_inbox_write.bats | 15-55s | [94.1,111.4,108.6,150.2,83.2] | 108.6s | 86.6s | +25% |

### 真因判定: Case (a) 本質的遅化

4テストが確認済み。ratchetアルゴリズムは正しく機能しており、gate_test_health.sh変更不要。
**AC2 スコープ分離**: 上記4テストの高速化cmdを将軍へ具申。
