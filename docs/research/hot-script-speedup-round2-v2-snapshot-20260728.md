# ホットスクリプト集中高速化 第二弾 — fixed-SHA完了snapshot v2.0

- 実施日: 2026-07-28
- fixed SHA: `60a88c241365039ae28bc2ca525291b6ced9602f`
- unit receipt: `logs/test_receipts/run_tests_20260728T100806_3869311.json`
- unit結果: 2,712/2,712 PASS、FAIL 0、SKIP 0
- unit選択: 180/180 files、source_head=現HEAD（実行終了時）
- snapshot下限: `2026-07-28T02:46:57+00:00`（第一弾最終CLEAR）
- snapshot上限: `2026-07-28T10:08:06+00:00`（fixed-SHA全量unit開始直前）
- 上限をunit開始直前にした理由: 全量unit自身が生成するfixture計測を運用cohortへ混入させないため
- row_count: 選定境界3,355行（第二弾9標的2,536＋除外refresh759＋既存deploy lane 60）
- 参考: 同一窓の台帳全行は11,052行

## v2.0 累積時間序列

| 順 | source:check_id | n | 累積 | median | p95 | max |
|---:|---|---:|---:|---:|---:|---:|
| 1 | `gate_gunshi_report_precheck:full_precheck` | 302 | 793,095ms | 731ms | 10,291ms | 18,932ms |
| 2 | `inbox_write:inbox_write_total` | 479 | 790,054ms | 462ms | 5,703ms | 12,139ms |
| 3 | `report_publish:publish_total` | 453 | 228,930ms | 300ms | 890ms | 13,370ms |
| 4 | `report_field_set:commit_hash` | 584 | 164,320ms | 260ms | 550ms | 1,190ms |
| 5 | `report_publish:atomic_replace` | 397 | 104,130ms | 230ms | 500ms | 840ms |
| 6 | `cmd_save:checks_main` | 55 | 46,420ms | 811ms | 1,697ms | 1,892ms |
| 7 | `report_field_set:task.commit_contract` | 53 | 14,980ms | 270ms | 440ms | 480ms |
| 8 | `report_field_set:parent_contract_fingerprint` | 179 | 13,630ms | 60ms | 190ms | 450ms |
| 9 | `report_field_set:parent_ac_coverage` | 34 | 5,150ms | 120ms | 310ms | 560ms |

## 除外lane（序列へ入れない）

| source:check_id | n | 累積 | median | p95 | max | 除外理由 |
|---|---:|---:|---:|---:|---:|---|
| `three_layer_health:refresh_copy` | 378 | 4,508,010ms | 11,371.5ms | 28,165ms | 61,534ms | background保守lane |
| `three_layer_health:refresh_verify` | 381 | 4,331,800ms | 12,156ms | 16,285ms | 26,812ms | background保守lane |
| `deploy_task:deploy_total` | 60 | 1,440,059ms | 19,898.5ms | 59,979ms | 65,189ms | 既存deploy control-plane改善lane |

## 二値結論

- P1: atomic publish区分計測を恒久化。最大明示子区分12.8% < 40%のため最適化なしで正直no-change CLOSE — PASS
- P2: reflux backlink taskのplanned_pathsへSSOTと生成物の両方を注入 — PASS
- P3-a: fixed-SHA unit FAIL 0 / SKIP 0 — PASS
- P3-b: snapshot上下限とrow_count固定 — PASS
- 第二弾: 9/9クローズ — PASS
- P4: 第三弾後続は殿の認可発話まで凍結 — 継続

origin: `[[殿確定裁定_第二弾閉幕プラン_20260728]] -> [[fixed_SHA_unit_60a88c241]] -> [[第二弾v2.0_snapshot]]`
