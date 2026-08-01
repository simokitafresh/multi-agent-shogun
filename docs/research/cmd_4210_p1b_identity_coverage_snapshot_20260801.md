# cmd_4210 P1b identity coverage snapshot

- measured_at: 2026-08-01T22:02:50+09:00
- instrumentation_lower_bound: 2026-07-30T02:54:00+09:00 (`2026-07-29T17:54:00+00:00`)
- common_cutoff: `2026-08-01T13:02:50.549821+00:00`
- source: `logs/defense_overhead.jsonl` (read-only, lower bound through common cutoff: 29,781 rows)
- fixed_population: `logs/gate_metrics.log` の2026-07-28 00:00-21:18 JST、cmd_id最終行=CLEARかつdeploy/work/finalize/e2e全数値ありの53弾（設計書§0.-2aと同一定義）
- fixed_population_sha256: `508000581f50a2198696967bf57acdd85bfe385cb5c875ce020287024e231eb9`
- identity: non-empty `cmd_id` + `generation =~ ^[0-9a-f]{64}$`

## Phase coverage（同一cutoff、生実測）

| phase (`source/check_id`) | identity付きevent / 全event | identity率 | unique cmd | 固定53弾coverage |
|---|---:|---:|---:|---:|
| gunshi_lgtm (`review_approval/gunshi_lgtm`) | 132/132 | 100.0% | 106 | 0/53 |
| karo_accept (`review_approval/karo_accept`) | 135/135 | 100.0% | 119 | 0/53 |
| task_idle (`completion_finalize/task_idle`) | 105/105 | 100.0% | 105 | 0/53 |
| archive (`completion_finalize/archive`) | 118/118 | 100.0% | 116 | 0/53 |
| completion_publish (`dashboard_update/completion_publish`) | 97/97 | 100.0% | 97 | 0/53 |

## Canonical generation pair（同一cutoff、生実測）

| transition | exact `(cmd_id,generation)` pair / upstream unique pair | 欠損 | 右打切り | cmd_id overlap | generation不一致cmd |
|---|---:|---:|---:|---:|---:|
| gunshi_lgtm → karo_accept | 112/126 | 14 | 14 | 102 | 0 |
| karo_accept → task_idle | 0/129 | 129 | 129 | 99 | 99 |
| task_idle → archive | 95/105 | 10 | 10 | 97 | 2 |
| archive → completion_publish | 87/118 | 31 | 31 | 90 | 3 |

- 5 phase完全pair: **0件**。
- report完了起点 (`report_publish/publish_total`): canonical identity付き **175/470 events**、unique `(cmd_id,generation)` **11件**。
- `karo_accept → task_idle` はcmd_idが99件重複するのにexact pairが0件。例: `cmd_karo_hotfix_ga418_infrastructure_freshness_202607311427` はkaro_accept generation prefix=`c7d08c812b32`、task_idle=`75d5b34c7057`。これは蓄積不足ではなくphase境界のgeneration意味不一致。

## P1b機械再開条件の二値判定

| 条件 | 結果 | 一次根拠 |
|---|---|---|
| 必要phase identity充足 | yes | 5/5 phaseでevent identity率100.0% |
| paired N/N | no | 4遷移すべてN/N未達、5 phase完全pair 0件 |
| 欠損0 | no | 14/129/10/31件 |
| 右打切り0 | no | 14/129/10/31件 |
| 固定53弾coverage全数 | no | 全5 phase 0/53 |
| report完了起点とのcanonical結合 | no | 起点175/470、5 phase完全pair 0件 |
| 同一cutoff出力 | yes | 全表を共通cutoff `2026-08-01T13:02:50.549821+00:00` で算出 |

**総合判定: P1b機械再開条件は未充足（P1b起票不可）。**

原因候補の二値分類:

- 計装漏れ: **yes**。全phaseのfield存在率は100%だが、karo_accept→task_idleで同一cmd 99件すべてgeneration不一致のため、canonical identityの意味統一が境界を貫通していない。
- 蓄積不足: **yes（固定母集団条件に対して構造的）**。固定53弾は2026-07-28の計装前歴史窓なので、計装後の自然蓄積を同じ分母へ要求してもcoverageは0/53から増えない。条件維持ならbackfill、自然蓄積を採るなら固定窓の前向き再定義が必要。

## 再現規約

1. `gate_metrics.log` をcmd_id最終行へreduceし、2026-07-28 00:00-21:18 JST・CLEAR・4数値ありを固定母集団にする（53件、上記SHA）。
2. `defense_overhead.jsonl` をinstrumentation lower bound以上かつcommon cutoff以下へ限定する。
3. 5つの`(source,check_id)`ごとに全event、identity付きevent、unique cmd、固定母集団との積集合を数える。
4. 隣接phaseの`(cmd_id,generation)`集合積をpair、upstream差集合を欠損/右打切りとして算出する。
5. `report_publish/publish_total`も同じlower bound/cutoff/identity規約で算出する。
