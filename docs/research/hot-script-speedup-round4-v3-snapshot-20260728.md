# ホットスクリプト集中高速化 第四弾 — 起票前 fixed-window snapshot v3.0

- 実施日: 2026-07-28
- source HEAD: `b40e11a3c9a838933a27f321eae8718824c89c16`
- snapshot下限: `2026-07-28T10:08:06+00:00`（第二弾v2.0上限を継承）
- snapshot上限: `2026-07-28T11:25:10+00:00`（第四弾read-only初弾開始前）
- 固定窓の台帳全行: 1,234行
- 固定窓canonical hash: `ce8fa311aab5961d8ca6218256d9c73f62c654b15fa21e32d19dfb9d4fdf4237`
- 欠損: 下表の全標的で `wall_ms` 欠損0
- 境界: 親totalのみ序列へ加算。子区分は診断用で親へ加算しない

## v3.0 累積時間序列

| 順 | source:check_id | n | 累積 | median | p95 | max | 第四弾での扱い |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | `gate_gunshi_report_precheck:full_precheck` | 31 | 99,914ms | 765ms | 15,735ms | 23,090ms | 弾#1を維持 |
| 2 | `inbox_write:inbox_write_total` | 56 | 75,622ms | 354.5ms | 4,653ms | 5,304ms | 弾#2を維持 |
| 3 | `report_publish:publish_total` | 27 | 14,190ms | 280ms | 600ms | 6,370ms | 弾#3を維持 |
| 4 | `cmd_save:checks_main` | 14 | 13,079ms | 869.5ms | 2,136ms | 2,136ms | 弾#5を第4位へ繰上げ |
| 5 | `report_field_set:commit_hash` | 36 | 6,890ms | 170ms | 360ms | 510ms | 弾#4を維持（識別子計装後に重複有無を判定） |
| 6 | `report_publish:atomic_replace` | 18 | 4,140ms | 210ms | 340ms | 340ms | 除外維持（第二弾no-change） |
| 7 | `report_field_set:task.commit_contract` | 8 | 2,670ms | 285ms | 750ms | 750ms | 除外 |
| 8 | `report_field_set:parent_ac_coverage` | 4 | 610ms | 160ms | 200ms | 200ms | 除外 |
| 9 | `report_field_set:parent_contract_fingerprint` | 4 | 510ms | 120ms | 170ms | 170ms | 除外 |

## read-only AC1 4レーンの診断値

| レーン | 全数結果 | 最大寄与 |
|---|---|---|
| `full_precheck` | 親N=3,610、欠損0、p50=940.5ms、p95=17,128ms、max=128,138ms。固定窓v3.0では上表N=31 | 子全期間N=1,014の `body_rest` 368,805ms / 58.1%。固定窓でも46,304msで最大 |
| `inbox_write_total` | 全イベントN=1,547、必須欠損0。親total N=549、p50=455ms、p95=5,547ms、max=12,139ms | `delivery_verify` は443件中BLOCK 393件。送達保証を削らずwatcherとの二重nudge経路を是正 |
| `publish_total` | N=2,420、欠損0、p50=390ms、p95=1,650ms、max=31,880ms。母集団hash=`303f49e55233fadcc3ce14e6640b2d491587c026125f5525f8d69d2ce747304f` | 子相分類2,405件中 `atomic_replace` 2,101件。ただし既存no-change判定は維持 |
| `checks_main` | 親N=1,355、欠損0、p50=1,182ms、p95=5,652ms、max=132,827ms | 子8種では `quality_gate` が最大累積12,862ms。固定窓でも4,350msで最大 |

## 起票判断

- v2.0から上位3標的は不変。`checks_main` が `commit_hash` を抜き第4位へ上昇したが、4 distinct script・5弾の総スコープ増減は不要。
- 実装順は、独立4ファイルを `full_precheck` / `inbox_write_total` / `publish_total` / `checks_main` で並列開始し、同一writerの `commit_hash` は `publish_total` 完了後に直列実行する。
- `full_precheck` は `body_rest`、`inbox_write_total` は `delivery_verify`、`checks_main` は `quality_gate` を第一仮説とする。推論だけで採用せず、各弾でbefore→変更→afterを同一境界で二値計測する。
- `publish_total` は `atomic_replace` の回数が多いことだけで再実装しない。第二弾の寄与率no-change契約を維持し、外れ値尾の発生条件を先に特定する。
- `commit_hash` は識別子計装で同一報告flow内の重複を一次証明してから採否を決める。重複なしならno-change CLOSE。
- 個別弾は選択テストのみ。unit全量は5弾全クローズ後のfixed-SHA checkpointで共有1回だけ実施する。

origin: `[[第二弾v2.0_snapshot]] -> [[第四弾read_only_AC1_4レーン]] -> [[第四弾v3.0_snapshot]] -> [[4スクリプト5弾起票判断]]`
