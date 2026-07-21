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
