# 【❄ 準備中 — 設計のみ・実装0/5・序列は暫定】ホットスクリプト集中高速化 第四弾 — AsIs/ToBe 5W1H設計書 v1.2 (2026-07-28 20:12 家老RC採用=4 distinct script+殿指摘採用=序列の再集計前提。版履歴は§-3)

> 第一弾=`hot-script-speedup-asis-tobe-5w1h_20260727.md`(✅CLOSED 12/12)、第二弾=`hot-script-speedup-round2-asis-tobe-5w1h_20260728.md`(✅CLOSED 9/9・閉幕プランP1-P4全充足)、第三弾=`hot-script-speedup-round3-asis-tobe-5w1h_20260728.md`(⚙#1 CLEAR・#2疾風稼働中)。本書は殿下知(2026-07-28 20:02)「第四弾の準備も始めよう」に基づき、**第二弾閉幕snapshot v2.0**(`hot-script-speedup-round2-v2-snapshot-20260728.md`、fixed SHA=60a88c241、固定窓2026-07-28T02:46:57Z..10:08:06Z)の序列から標的を引いた第四弾である。殿方針(10:49)「前弾でやったものも依然ボトルネックなら再度トライする」を継承。様式・計測の憲法・完了条件の型は第一弾を踏襲する。

## §-2 第四弾 弾台帳(2026-07-28 20:05時点 — 第一弾§-2完了台帳と同型)

| # | check | 状態 | 予定内容 | Δ実測 |
|---|---|---|---|---|
| 1 | full_precheck(再々) | ❄ 準備のみ | 第二弾#1で恒久化した子check_id 7種のサブ区分実測を固定窓で集計→最大寄与フェーズを特定→挙動不変の最小差分是正(stdout完全一致)。外れ値尾(p95 10.3s/max 18.9s)は枝条件を同event記録で特定 | (before: 累積793.1s/n=302/median 731ms/p95 10,291ms/max 18,932ms) |
| 2 | inbox_write_total | ❄ 準備のみ | 第二弾B5計装(persist/nudge/delivery_verify/total)の区分値を固定窓で集計→最大区分を特定→是正。nudge/delivery verify系はwatcher送達契約(自動既読対象type群=現物基準: completion alias 7種/report_notification_missing込み8種/report_review_result込み入力族9種)を不変条件とする。pre-send captureは観測であり自動BLOCKではない(家老計数blt_201528) | (before: 累積790.1s/n=479/median 462ms/p95 5,703ms/max 12,139ms) |
| 3 | publish_total(再) | ❄ 準備のみ(report_field_setレーン直列1発目) | writer現物確定済み(将軍rg実測: scripts/report_field_set.sh:336,346)。恒常部(median 300ms×n453)と外れ値尾(max 13.4s)を分けて是正/条件特定 | (before: 累積228.9s/n=453/median 300ms/p95 890ms/max 13,370ms) |
| 4 | commit_hash識別子計装 | ❄ 準備のみ(同レーン直列2発目・第二弾#8 stop-gate帰結の実行) | event_idへreport/task識別子を非破壊追加(既存台帳schema互換)→固定窓で同一報告flow内の重複呼出しを一次証明→重複ありならbatch化を仮説検証、なければno-change CLOSE | (before: 累積164.3s/n=584=回数最多/median 260ms。「1クラスタ=1報告フロー」は現状証明不能) |
| 5 | checks_main(再々) | ❄ 準備のみ(4本目のdistinct script=cmd_save.sh・家老RC採用) | 第二弾#2で恒久化した非加算子区間8種の固定窓集計→残存最大寄与の是正(第二弾-30.9%後のmedian 811msが対象) | (before: 累積46.4s/n=55/median 811ms/p95 1,697ms/max 1,892ms) |

## §-3 版履歴

- v1.2.1(20:17): 家老PARTIAL指摘(blt_201528)の静的矛盾4件を即修正 — (一)自動既読type群を現物計数(7/8/9種)へ・pre-send capture=観測と明記 (二)集計コマンド帰属をblt_192942へ訂正 (三)writer確定済みへ統一 (四)origin五弾表記へ
- v1.2(20:12): 家老RC(blt_200953)採用 — publish_totalのwriterはreport_field_set.shで#3/#4は同一ファイル(将軍rg一次確認済み)。distinct 4script=gate_gunshi/inbox_write/report_field_set/cmd_saveへ再構成し#5 checks_main再々を追加(4レーン5弾)。+殿指摘20:11採用 — **序列の再集計が起票解禁の前提**(殿20:13訂正: 「最終系」は「再集計」のタイポ): 現§0はsnapshot v2.0の暫定草案であり、進行中弾(第三弾#2・T4)クローズ後の固定窓再snapshot(v3.0)で序列を再集計してから殿裁可を仰ぐ(第二弾§-0(3)と同じ型)
- v1.1(20:08): 殿裁定20:07「スクリプトは4つ以上でやろう。忍者が余っていつも非効率だ」→4弾化(のちv1.2でwriter帰属を訂正)
- v1.0(20:05): 初版 — snapshot v2.0序列から3標的決め打ち。実装凍結(起票解禁条件=§3)。家老忖度なしレビュー依頼

## §-1 第四弾スコープ決め打ち(第一弾§-1憲法の踏襲 — 数を先に固定)

**決め打ち: 4 distinct script・5標的=5弾**(§0表がSSOT。殿裁定20:07=スクリプト4つ以上・idle忍者を遊ばせない。家老RC=writer現物基準で数える):

| 実体スクリプト(writer現物確定済み) | 担当check_id | 弾数 |
|---|---|---:|
| `scripts/gates/gate_gunshi_report_precheck.sh` | full_precheck(再々) | 1 |
| `scripts/inbox_write.sh` | inbox_write_total | 1 |
| `scripts/report_field_set.sh`(publish_total writerもここ=L336,346) | publish_total(再)→commit_hash識別子計装の**直列2弾** | 2 |
| `scripts/cmd_save.sh` | checks_main(再々) | 1 |

- **完了条件(第一弾と同型)**: 恒常課税型=既存台帳`logs/defense_overhead.jsonl`同条件before/afterのΔ累積・Δmedian実測 / 外れ値尾=発生条件特定(3点表)→条件ベース是正 / いずれも品質2原則(挙動不変の正本突合+境界fixture)+選択テストFAIL0・SKIP0。**個別弾への全量unit要求は禁止、全量はwave最終fixed-SHA checkpointで共有一回**(殿裁定13:26)
- **第四弾完了宣言=5弾全クローズ→fixed-SHA全量unit共有1回→固定窓台帳再snapshot→次弾序列**(第二弾閉幕プランの型を踏襲)
- **スコープ外(途中追加は理由を問わず禁止)**: `report_publish:atomic_replace`(第二弾#9でno-change確定: 最大子区分12.8%<40%)・startup gate 3本(殿裁定12:43聖域)・three_layer_health系(background保守lane)・deploy_task系(既存deployレーン帰属)・cmd_complete_gate.sh(第三弾#2所有・疾風稼働中)

## §0 結論 — 純オーバーヘッド標的序列【暫定草案 — 殿指摘20:11: 序列は進行中弾クローズ後の再snapshot(v3.0)で再集計してから確定】(snapshot v2.0=第二弾閉幕時の固定窓)

母集団の定義・固定窓・row_count(選定3,355行/targets 2,536行)は`docs/research/hot-script-speedup-round2-v2-snapshot-20260728.md`が正本(commit 0a681c239)。集計コマンド原文は同snapshot文書内には無く、家老閉幕報告(blt_20260728_192942)に記録されている。本書は序列の消費側であり再集計しない。

| # | source:check_id | 累積 | n | median | p95 | max | 型 | 第四弾での扱い |
|---|---|---:|---:|---:|---:|---:|---|---|
| 1 | gate_gunshi_report_precheck:full_precheck | 793.1s | 302 | 731ms | 10,291ms | 18,932ms | 恒常課税+外れ値尾 | **弾#1** |
| 2 | inbox_write:inbox_write_total | 790.1s | 479 | 462ms | 5,703ms | 12,139ms | 恒常課税+外れ値尾 | **弾#2** |
| 3 | report_publish:publish_total | 228.9s | 453 | 300ms | 890ms | 13,370ms | 恒常課税+外れ値尾 | **弾#3** |
| 4 | report_field_set:commit_hash | 164.3s | 584 | 260ms | 550ms | 1,190ms | 恒常課税(回数最多) | **弾#4**(識別子計装+重複証明。是正はその後の仮説検証) |
| 5 | report_publish:atomic_replace | 104.1s | 397 | 230ms | 500ms | 840ms | 恒常課税 | 除外(no-change確定・計装恒久残置) |
| 6 | cmd_save:checks_main | 46.4s | 55 | 811ms | 1,697ms | 1,892ms | 恒常課税 | **弾#5**(4本目distinct script・家老RC採用) |
| 7-9 | commit_contract/fingerprint/parent_ac_coverage | 15.0s/13.6s/5.2s | — | — | — | — | 是正済み残余 | 除外 |

## §1 計測境界(第一弾§1の憲法を継承+本弾固有の注意)

- 全表=`docs/research/cmd_4181_overhead_boundary_recon.md`。集計禁止・参考母集団(非加算)・親子非加算の原則は同一
- **B5計装の親子非加算**: inbox_write系はtotalのみ加算対象(persist/nudge/delivery_verifyは非加算子区分)。弾#2の効果Δはtotalで証明し、子区分は寄与特定にのみ使う
- **publish_totalのwriterは現物確定済み**: `scripts/report_field_set.sh` L336,346(将軍rg一次確認+家老RC一致)。source名report_publishとwriterファイル名の不一致に注意
- **nudge/delivery verifyの契約不変**: inbox_write.shの送達保証(flock persist・watcher nudge・codex delivery verify)と自動既読対象type群(現物=completion alias 7種、report_notification_missing込み8種、report_review_result込み入力族9種)の挙動は正本突合対象。速度のために送達保証を削る変更は禁止

## §2 To-Be — 進め方(型を継承)

1. **1標的=1弾・複合弾禁止**。ACは同一条件before/after実測差分+品質2原則+選択テストFAIL0・SKIP0
2. **順序**: 解禁後は最大4レーン並列(1ファイル=1レーン)。report_field_setレーンのみ直列2弾(#3→#4)。各弾とも「既存計装/子区分の固定窓集計→最大寄与特定→最小差分是正」の計測先行型
3. 計測は既存台帳のみ(新台帳禁止)。削減見込みの事前外挿禁止(実測のみ)
4. **凍結解除条件(殿指摘20:11で強化)**: (i)進行中弾(第三弾#2・T4)クローズ→(ii)固定窓再snapshot(v3.0)で序列を再集計・scope再検証→(iii)家老忖度なしレビュー→(iv)殿裁可。第三弾#2(疾風)・T4(影丸)の稼働を妨げない(ファイル素集合交わりゼロは§-1で確定)
5. 配備=家老自立配備(karo_direct)。完了ごとに掲示板1行報告、5弾全クローズで完了宣言+再snapshot

## §3 decision ledger(決定済み/裁可待ち/実測待ち)

| 項 | 状態 |
|---|---|
| 標的序列・5弾スコープ | **暫定**(snapshot v2.0草案+殿裁定20:07。最終確定はv3.0再snapshot後=殿指摘20:11) |
| 序列の再集計(v3.0 snapshot) | 実測待ち(第三弾#2・T4クローズ後に固定窓・fixed-SHAで引き直し、scope増減を再判定) |
| 弾#1の最大寄与フェーズ | 実測待ち(第二弾#1の子check 7種計装の固定窓集計が第一AC) |
| 弾#2の最大寄与区分 | 実測待ち(B5計装の固定窓集計が第一AC) |
| 弾#3のwriter実体 | 確定済み(scripts/report_field_set.sh L336,346) |
| commit_hash弾#4の是正可否 | 弾#4の識別子計装+重複証明の実測待ち(重複なしならno-change CLOSE) |
| **殿裁可待ち** | v3.0再snapshot反映版の採否と起票解禁(§2の凍結解除条件(i)-(iv)充足後) |

## §4 5W1H

- **WHY**: 第二弾閉幕snapshotで新序列が確定し、上位3標的(full_precheck 793s/inbox_write 790s/publish_total 229s)が全て「全員が毎回踏む」恒常課税+外れ値尾として残存。台帳再集計→新序列→次弾の反復が自動成長の回転そのもの
- **WHAT**: 4 distinct script・5弾の覚醒高速化(設計のみ、実装凍結中)。全弾とも既存計装の固定窓集計→最大寄与特定→最小差分是正の計測先行型
- **WHEN**: 進行中弾クローズ→v3.0再snapshot(序列再集計)→家老レビュー→殿裁可→起票解禁
- **WHERE**: §-1の4 distinct script+台帳=defense_overhead.jsonl
- **WHO**: 偵察・実装=忍者(最大4レーン=idle 4名が全員埋まる。report_field_setレーンは直列2弾)、配備=家老自立、検分=家老+軍師、裁可=殿
- **HOW**: 恒常課税型=子区分集計→最大寄与是正→同条件Δ実測証明、外れ値尾=枝条件の同event記録→3点表→条件ベース是正。送達保証・検査は1つも削らない

## §5 因果リンク

- → [[hot-script高速化設計書]] 第一〜三弾。様式・憲法・完了条件の型元
- → 第二弾閉幕snapshot(`hot-script-speedup-round2-v2-snapshot-20260728.md`) 序列の正本(fixed SHA 60a88c241)
- → [[cmd_4181_overhead_boundary_recon]] 計測境界表(集計の憲法)
- → [[弾スループット全体ボトルネック改善]] T4(影丸稼働)・T1b(蓄積待ち)との並列整理
- → [[殿裁定_全量テスト原則_20260728]] 個別弾選択実行・全量はwave最終1回
- origin: `[[殿下知_第四弾準備_20260728]] -> [[第二弾閉幕snapshot_v2.0序列]] -> [[殿裁定_4スクリプト以上_20260728]] -> [[家老RC_distinct_script基準]] -> [[full_precheck・inbox_write・publish_total・commit_hash計装・checks_mainの五弾]]`
