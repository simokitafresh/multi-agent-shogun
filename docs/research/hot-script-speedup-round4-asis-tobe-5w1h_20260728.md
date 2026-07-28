# 【❄ 準備中 — 設計のみ・実装0/3】ホットスクリプト集中高速化 第四弾 — AsIs/ToBe 5W1H設計書 v1.0 (2026-07-28 20:05 初版。版履歴は§-3。起票解禁は§3 decision ledger参照)

> 第一弾=`hot-script-speedup-asis-tobe-5w1h_20260727.md`(✅CLOSED 12/12)、第二弾=`hot-script-speedup-round2-asis-tobe-5w1h_20260728.md`(✅CLOSED 9/9・閉幕プランP1-P4全充足)、第三弾=`hot-script-speedup-round3-asis-tobe-5w1h_20260728.md`(⚙#1 CLEAR・#2疾風稼働中)。本書は殿下知(2026-07-28 20:02)「第四弾の準備も始めよう」に基づき、**第二弾閉幕snapshot v2.0**(`hot-script-speedup-round2-v2-snapshot-20260728.md`、fixed SHA=60a88c241、固定窓2026-07-28T02:46:57Z..10:08:06Z)の序列から標的を引いた第四弾である。殿方針(10:49)「前弾でやったものも依然ボトルネックなら再度トライする」を継承。様式・計測の憲法・完了条件の型は第一弾を踏襲する。

## §-2 第四弾 弾台帳(2026-07-28 20:05時点 — 第一弾§-2完了台帳と同型)

| # | check | 状態 | 予定内容 | Δ実測 |
|---|---|---|---|---|
| 1 | full_precheck(再々) | ❄ 準備のみ | 第二弾#1で恒久化した子check_id 7種のサブ区分実測を固定窓で集計→最大寄与フェーズを特定→挙動不変の最小差分是正(stdout完全一致)。外れ値尾(p95 10.3s/max 18.9s)は枝条件を同event記録で特定 | (before: 累積793.1s/n=302/median 731ms/p95 10,291ms/max 18,932ms) |
| 2 | inbox_write_total | ❄ 準備のみ | 第二弾B5計装(persist/nudge/delivery_verify/total)の区分値を固定窓で集計→最大区分を特定→是正。nudge/delivery verify系はwatcher送達契約(自動既読6type・停止中エージェント保護)を不変条件とする | (before: 累積790.1s/n=479/median 462ms/p95 5,703ms/max 12,139ms) |
| 3 | publish_total(再) | ❄ 準備のみ | 第二弾の validator遅延化(-18.6%)後も残存。writer現物照合(§1)を第一手に、恒常部(median 300ms×n453)と外れ値尾(max 13.4s)を分けて是正/条件特定 | (before: 累積228.9s/n=453/median 300ms/p95 890ms/max 13,370ms) |

## §-3 版履歴

- v1.0(20:05): 初版 — snapshot v2.0序列から3標的決め打ち。実装凍結(起票解禁条件=§3)。家老忖度なしレビュー依頼

## §-1 第四弾スコープ決め打ち(第一弾§-1憲法の踏襲 — 数を先に固定)

**決め打ち: 3スクリプト・3標的=3弾**(§0表がSSOT):

| 実体スクリプト(writer現物照合は各弾の第一手) | 担当check_id | 件数 |
|---|---|---:|
| `scripts/gates/gate_gunshi_report_precheck.sh` | full_precheck(再々) | 1 |
| `scripts/inbox_write.sh` | inbox_write_total | 1 |
| report_publish系writer(publish_totalの書込み元を弾内で現物確定) | publish_total(再) | 1 |

- **完了条件(第一弾と同型)**: 恒常課税型=既存台帳`logs/defense_overhead.jsonl`同条件before/afterのΔ累積・Δmedian実測 / 外れ値尾=発生条件特定(3点表)→条件ベース是正 / いずれも品質2原則(挙動不変の正本突合+境界fixture)+選択テストFAIL0・SKIP0。**個別弾への全量unit要求は禁止、全量はwave最終fixed-SHA checkpointで共有一回**(殿裁定13:26)
- **第四弾完了宣言=3弾全クローズ→fixed-SHA全量unit共有1回→固定窓台帳再snapshot→次弾序列**(第二弾閉幕プランの型を踏襲)
- **スコープ外(途中追加は理由を問わず禁止)**: `report_field_set:commit_hash`(第二弾#8 stop-gate判定どおりreport/task識別子計装が先)・`report_publish:atomic_replace`(第二弾#9でno-change確定: 最大子区分12.8%<40%)・`cmd_save:checks_main`(第二弾-30.9%済で46.4sの下位)・startup gate 3本(殿裁定12:43聖域)・three_layer_health系(background保守lane)・deploy_task系(既存deployレーン帰属)・cmd_complete_gate.sh(第三弾#2所有・疾風稼働中)

## §0 結論 — 純オーバーヘッド標的序列(snapshot v2.0=第二弾閉幕時の固定窓。集計の再現条件はsnapshot文書に固定済み)

母集団の定義・集計コマンド・row_count(選定3,355行/targets 2,536行)は`docs/research/hot-script-speedup-round2-v2-snapshot-20260728.md`が正本(commit 0a681c239)。本書は序列の消費側であり再集計しない。

| # | source:check_id | 累積 | n | median | p95 | max | 型 | 第四弾での扱い |
|---|---|---:|---:|---:|---:|---:|---|---|
| 1 | gate_gunshi_report_precheck:full_precheck | 793.1s | 302 | 731ms | 10,291ms | 18,932ms | 恒常課税+外れ値尾 | **弾#1** |
| 2 | inbox_write:inbox_write_total | 790.1s | 479 | 462ms | 5,703ms | 12,139ms | 恒常課税+外れ値尾 | **弾#2** |
| 3 | report_publish:publish_total | 228.9s | 453 | 300ms | 890ms | 13,370ms | 恒常課税+外れ値尾 | **弾#3** |
| 4 | report_field_set:commit_hash | 164.3s | 584 | 260ms | 550ms | 1,190ms | 恒常課税(回数最多) | 除外(識別子計装が先=第二弾#8 stop-gate) |
| 5 | report_publish:atomic_replace | 104.1s | 397 | 230ms | 500ms | 840ms | 恒常課税 | 除外(no-change確定・計装恒久残置) |
| 6 | cmd_save:checks_main | 46.4s | 55 | 811ms | 1,697ms | 1,892ms | 恒常課税 | 除外(第二弾-30.9%済・下位) |
| 7-9 | commit_contract/fingerprint/parent_ac_coverage | 15.0s/13.6s/5.2s | — | — | — | — | 是正済み残余 | 除外 |

## §1 計測境界(第一弾§1の憲法を継承+本弾固有の注意)

- 全表=`docs/research/cmd_4181_overhead_boundary_recon.md`。集計禁止・参考母集団(非加算)・親子非加算の原則は同一
- **B5計装の親子非加算**: inbox_write系はtotalのみ加算対象(persist/nudge/delivery_verifyは非加算子区分)。弾#2の効果Δはtotalで証明し、子区分は寄与特定にのみ使う
- **publish_totalのwriter現物照合を弾#3の第一手に**: source=report_publishの書込み元ファイルを現物確定してから標的化(「新規check_idは分類を明記してから」の教訓の適用)
- **nudge/delivery verifyの契約不変**: inbox_write.shの送達保証(flock persist・watcher nudge・codex delivery verify)と自動既読6type挙動は挙動不変の正本突合対象。速度のために送達保証を削る変更は禁止

## §2 To-Be — 進め方(型を継承)

1. **1標的=1弾・複合弾禁止**。ACは同一条件before/after実測差分+品質2原則+選択テストFAIL0・SKIP0
2. **順序**: 3弾は別ファイルゆえ解禁後は最大3レーン並列(1ファイル=1レーンの原理)。各弾とも「既存計装/子区分の固定窓集計→最大寄与特定→最小差分是正」の計測先行型
3. 計測は既存台帳のみ(新台帳禁止)。削減見込みの事前外挿禁止(実測のみ)
4. **凍結解除条件**: 家老忖度なしレビュー→殿裁可。第三弾#2(疾風)・T4(影丸)の稼働を妨げない(ファイル素集合交わりゼロは§-1で確定)
5. 配備=家老自立配備(karo_direct)。完了ごとに掲示板1行報告、3弾全クローズで完了宣言+再snapshot

## §3 decision ledger(決定済み/裁可待ち/実測待ち)

| 項 | 状態 |
|---|---|
| 標的序列・3弾スコープ | 決定済み(snapshot v2.0固定窓が根拠) |
| 弾#1の最大寄与フェーズ | 実測待ち(第二弾#1の子check 7種計装の固定窓集計が第一AC) |
| 弾#2の最大寄与区分 | 実測待ち(B5計装の固定窓集計が第一AC) |
| 弾#3のwriter実体 | 現物照合待ち(弾内第一手) |
| commit_hash再挑戦の前提 | report/task識別子計装の起票判断は次snapshot後(本弾スコープ外) |
| **殿裁可待ち** | (a)本設計の採否 (b)起票時期 — 推薦=家老レビュー反映後、第三弾#2クローズを待たず別ファイル並列で起票(素集合交わりゼロのため) |

## §4 5W1H

- **WHY**: 第二弾閉幕snapshotで新序列が確定し、上位3標的(full_precheck 793s/inbox_write 790s/publish_total 229s)が全て「全員が毎回踏む」恒常課税+外れ値尾として残存。台帳再集計→新序列→次弾の反復が自動成長の回転そのもの
- **WHAT**: 3スクリプト3弾の覚醒高速化(設計のみ、実装凍結中)。全弾とも既存計装の固定窓集計→最大寄与特定→最小差分是正の計測先行型
- **WHEN**: 家老忖度なしレビュー→殿裁可→起票解禁。第三弾#2・T4と並列可(別ファイル)
- **WHERE**: §-1の3スクリプト+台帳=defense_overhead.jsonl
- **WHO**: 偵察・実装=忍者(最大3レーン)、配備=家老自立、検分=家老+軍師、裁可=殿
- **HOW**: 恒常課税型=子区分集計→最大寄与是正→同条件Δ実測証明、外れ値尾=枝条件の同event記録→3点表→条件ベース是正。送達保証・検査は1つも削らない

## §5 因果リンク

- → [[hot-script高速化設計書]] 第一〜三弾。様式・憲法・完了条件の型元
- → 第二弾閉幕snapshot(`hot-script-speedup-round2-v2-snapshot-20260728.md`) 序列の正本(fixed SHA 60a88c241)
- → [[cmd_4181_overhead_boundary_recon]] 計測境界表(集計の憲法)
- → [[弾スループット全体ボトルネック改善]] T4(影丸稼働)・T1b(蓄積待ち)との並列整理
- → [[殿裁定_全量テスト原則_20260728]] 個別弾選択実行・全量はwave最終1回
- origin: `[[殿下知_第四弾準備_20260728]] -> [[第二弾閉幕snapshot_v2.0序列]] -> [[full_precheck・inbox_write・publish_total三弾]]`
