# 【✅5/5全クローズ・CI GREEN復帰 — 全量checkpoint実行中】ホットスクリプト集中高速化 第四弾 — AsIs/ToBe 5W1H設計書 v2.4 (2026-07-29 02:02 覚醒更新。版履歴は§-3)

> 第一弾=`hot-script-speedup-asis-tobe-5w1h_20260727.md`(✅CLOSED 12/12)、第二弾=`hot-script-speedup-round2-asis-tobe-5w1h_20260728.md`(✅CLOSED 9/9・閉幕プランP1-P4全充足)、第三弾=`hot-script-speedup-round3-asis-tobe-5w1h_20260728.md`(✅CLOSED 2/2)。本書は殿下知(2026-07-28 20:02)「第四弾の準備も始めよう」に基づき、**第二弾閉幕snapshot v2.0**(`hot-script-speedup-round2-v2-snapshot-20260728.md`、fixed SHA=60a88c241、固定窓2026-07-28T02:46:57Z..10:08:06Z)の序列から標的を引いた第四弾である。殿方針(10:49)「前弾でやったものも依然ボトルネックなら再度トライする」を継承。様式・計測の憲法・完了条件の型は第一弾を踏襲する。

## §-2 第四弾 弾台帳(2026-07-28 21:05時点 — 第一弾§-2完了台帳と同型)

**AC1 read-only集計は4レーン全てGATE CLEAR**(cmd_karo_recon2_round4_ac1_{precheck,inbox,publish,cmdsave}_20260728、家老blt_205801)。集計結果はv3.0 snapshot(`hot-script-speedup-round4-v3-snapshot-20260728.md`)がSSOT。

| # | check | 状態 | AC1診断結果(v3.0 snapshot)と是正予定 | v3.0固定窓実測 |
|---|---|---|---|---|
| 1 | full_precheck(再々) | ✅実装CLEAR(22:16・飛猿 cmd_karo_round4_impl_full_precheck_20260728) | 実測真因=fixed-hash経路の**重複tree走査**(第一仮説body_restの中身)。重複走査を除去 | 個別最大寄与name-only 2,438.6ms→**0呼出**。既存contract 8/8 PASS・FAIL0・SKIP0、正規化stdout SHA-256完全一致 |
| 2 | inbox_write_total | ✅実装CLEAR(21:41・半蔵 cmd_karo_round4_impl_inbox_write_20260728) | 実測真因=第一仮説どおり`delivery_verify`。active watcher時のdelivery verifyを**送達保証を維持した非同期経路**へ移設(自動既読type群・flock persist・nudge契約は不変) | median 354.5ms→**182ms**、p95 4,653→348ms、max 5,304→348ms(after N=3)。選択246/246 PASS・FAIL0・SKIP0 |
| 3 | publish_total(再) | ✅実装CLEAR(22:14・才蔵 cmd_karo_round4_impl_publish_total_20260728) | 外れ値真因=**singleflight待ち+async telemetryへのlock FD継承**。非terminal batchをterminal gate lockから分離 | 2秒競合下6,370ms相当→**248ms**。既存contract 14/14 PASS・FAIL0・SKIP0 |
| 4 | checks_main(再々) | ✅no-change CLOSE(21:46・小太郎 cmd_karo_round4_impl_checks_main_20260728) | v3.0序列は既存最適化(8b5ea59d)後のsnapshotであり追加重複なし→正直no-change | 変更0。選択361/361 PASS・SKIP0 |
| 5 | commit_hash識別子計装 | ✅CLEAR(23:10・才蔵 cmd_karo_round4_impl_commit_hash_20260728) | commit_hash telemetryへreport_id/task_idを非破壊追加(計装恒久残置)。新schema実flowで重複0を確認→設計どおり**batch化なし(no-change)**。重複判定は今後の蓄積でいつでも機械照合可能 | v3.0固定窓before再確認(n=36/median 170ms)。新schema実flow N=1・重複0。対象test 20/20 PASS・FAIL0・SKIP0 |

## §-3 版履歴

- v2.4(02:02): **CI GREEN復帰(run 30377787485 success 8分59秒・origin 0c505e3f2)** — RED真因は二重: (a)unit job timeout-minutes 5に対しテスト増加で実行5分15秒超=恒常タイムアウトcancel(将軍がconcurrency干渉と誤診→静止期間中の同時刻cancelで特定、5→12分是正+契約テスト2件同期、教訓LS101統合) (b)test_three_layer_knowledge_chain.bats 7件FAIL=fixtureがgitignore済みdata/DBをcopyしCI checkoutに不在(影丸ci_fixが正本スキーマ直接生成へ書換え、clean worktree再現証跡付き)。完了宣言の残条件=fixed-SHA全量unit checkpoint(家老へ下知)→固定窓再snapshot(v4.0)→第五弾序列
- v2.3(23:18): 覚醒更新 — **#5 commit_hash識別子計装CLEAR(23:10)で5/5全クローズ**。report_id/task_id非破壊追加・実flow重複0→batch化なし。**完了宣言の残条件=fixed-SHA全量unit共有1回→固定窓再snapshot**だが、CI RED(run 30366688273: ninja_scope_commit race系test67/68 FAIL)未解消のため全量checkpointはCI GREEN復帰後に実施。ci_fix再配備は将軍下知済み(msg_231057)
- v2.2(22:48): 覚醒更新 — **実装4レーン全クローズ(4/5)**: #1 full_precheck=重複tree走査除去(name-only 2,438.6ms→0呼出・stdout SHA一致)/#2 inbox_write=delivery verify非同期化で median354.5→182ms(送達保証不変)/#3 publish_total=singleflight・lock FD継承分離で競合下6,370→248ms/#4 checks_main=no-change CLOSE(v3.0は既存最適化後snapshot)。**残=#5 commit_hash識別子計装のみ**(#3クローズで直列前提充足=解禁)。完了宣言は#5クローズ→fixed-SHA全量unit共有1回→固定窓再snapshotで。CI RED(run 30357551416)はci_fix実装済み・push保留中ゆえGREEN復帰は次回push後
- v2.1(21:15): **殿裁可『では第四弾を開始しよう』=凍結解除条件(iv)充足、実装起票解禁**。§2の順序どおり独立4ファイル4レーン並列(#1 full_precheck/#2 inbox_write_total/#3 publish_total/#4 checks_main)、#5 commit_hash識別子計装は#3クローズ後にreport_field_setレーンで直列。配備=家老自立(karo_direct)。CI RED(run 30357551416)修正はci_fix担当1名が別対処中、CI RED中も新規配備は続行・pushのみGREEN復帰まで保留(殿裁定2026-05-03)
- v2.0(21:05): **v3.0再snapshot反映** — AC1 read-only集計4レーン全GATE CLEAR(家老blt_205801)。序列をv3.0固定窓(2026-07-28T10:08:06Z..11:25:10Z、全1,234行、hash=ce8fa311…)で再集計: 上位3不変、checks_mainがcommit_hashを抜き第4位へ繰上げ。4 distinct script・5弾スコープ増減なし。§0のSSOTを`hot-script-speedup-round4-v3-snapshot-20260728.md`へ差替え。凍結解除条件(i)(ii)(iii)充足、残=殿裁可のみ
- v1.3(20:30): **殿確定裁定20:25『推奨案でよい』** — read-only AC1集計(固定cutoff/hash付き全数・コード差分0)をdistinct 4ファイルで即並列開始(疾風へ初弾20:26配備済み)。実装フェーズと#4識別子計装はv3.0再snapshot後まで凍結維持。協議記録=家老blt_201950+将軍回答(独立一致)
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

## §0 結論 — 純オーバーヘッド標的序列【v3.0確定 — 21:05反映。殿指摘20:11の再集計前提を充足】(snapshot v3.0=第四弾read-only初弾開始前の固定窓)

序列SSOT=`docs/research/hot-script-speedup-round4-v3-snapshot-20260728.md`(source HEAD b40e11a3c、固定窓2026-07-28T10:08:06Z..11:25:10Z inclusive、全1,234行、canonical hash=ce8fa311aab5961d8ca6218256d9c73f62c654b15fa21e32d19dfb9d4fdf4237、集計=家老blt_205801: source/check_id別N/sum/median/nearest-rank p95/max全数集計)。本書は序列の消費側であり再集計しない。v2.0序列からの変化: 上位3不変、checks_mainが第4位へ繰上げ・commit_hashが第5位へ後退。scope増減なし。

| # | source:check_id | 累積 | n | median | p95 | max | 型 | 第四弾での扱い |
|---|---|---:|---:|---:|---:|---:|---|---|
| 1 | gate_gunshi_report_precheck:full_precheck | 99.9s | 31 | 765ms | 15,735ms | 23,090ms | 恒常課税+外れ値尾 | **弾#1**(第一仮説=body_rest 58.1%) |
| 2 | inbox_write:inbox_write_total | 75.6s | 56 | 354.5ms | 4,653ms | 5,304ms | 恒常課税+外れ値尾 | **弾#2**(第一仮説=delivery_verify二重nudge) |
| 3 | report_publish:publish_total | 14.2s | 27 | 280ms | 600ms | 6,370ms | 恒常課税+外れ値尾 | **弾#3**(外れ値尾条件特定先行) |
| 4 | cmd_save:checks_main | 13.1s | 14 | 869.5ms | 2,136ms | 2,136ms | 恒常課税 | **弾#4へ繰上げ**(第一仮説=quality_gate) |
| 5 | report_field_set:commit_hash | 6.9s | 36 | 170ms | 360ms | 510ms | 恒常課税(回数最多) | **弾#5へ後退**(識別子計装+重複証明。publish後直列) |
| 6 | report_publish:atomic_replace | 4.1s | 18 | 210ms | 340ms | 340ms | 恒常課税 | 除外維持(第二弾no-change確定) |
| 7-9 | task.commit_contract/parent_ac_coverage/parent_contract_fingerprint | 2.7s/0.6s/0.5s | — | — | — | — | 是正済み残余 | 除外 |

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
| 標的序列・5弾スコープ | **確定**(v3.0 snapshot序列。上位3不変・checks_main第4位/commit_hash第5位・scope増減なし) |
| 序列の再集計(v3.0 snapshot) | **完了**(第三弾#2・T4クローズ後、固定窓10:08:06Z..11:25:10Z・source HEAD b40e11a3cで引き直し済み。blt_205801) |
| 弾#1の最大寄与フェーズ | **診断済み**=body_rest(子全期間58.1%・固定窓でも最大)。是正実測は実装解禁後 |
| 弾#2の最大寄与区分 | **診断済み**=delivery_verify(443件中BLOCK 393件=watcher二重nudge経路)。送達保証不変で是正 |
| 弾#3のwriter実体 | 確定済み(scripts/report_field_set.sh L336,346) |
| 弾#4(checks_main)の最大寄与 | **診断済み**=quality_gate(子8種で最大累積)。是正実測は実装解禁後 |
| commit_hash弾#5の是正可否 | 識別子計装+重複証明の実測待ち(重複なしならno-change CLOSE) |
| 殿裁可 | **✅取得(21:15『では第四弾を開始しよう』)** — 凍結解除4条件全充足、実装起票解禁済み |

## §4 5W1H

- **WHY**: 第二弾閉幕snapshotで新序列が確定し、上位3標的(full_precheck 793s/inbox_write 790s/publish_total 229s)が全て「全員が毎回踏む」恒常課税+外れ値尾として残存。台帳再集計→新序列→次弾の反復が自動成長の回転そのもの
- **WHAT**: 4 distinct script・5弾の覚醒高速化(設計のみ、実装凍結中)。全弾とも既存計装の固定窓集計→最大寄与特定→最小差分是正の計測先行型
- **WHEN**: 進行中弾クローズ→v3.0再snapshot(序列再集計)→家老レビュー→殿裁可→起票解禁
- **WHERE**: §-1の4 distinct script+台帳=defense_overhead.jsonl
- **WHO**: 偵察・実装=忍者(最大4レーン=idle 4名が全員埋まる。report_field_setレーンは直列2弾)、配備=家老自立、検分=家老+軍師、裁可=殿
- **HOW**: 恒常課税型=子区分集計→最大寄与是正→同条件Δ実測証明、外れ値尾=枝条件の同event記録→3点表→条件ベース是正。送達保証・検査は1つも削らない

## §5 因果リンク

- → [[hot-script高速化設計書]] 第一〜三弾。様式・憲法・完了条件の型元
- → 第四弾v3.0 snapshot(`hot-script-speedup-round4-v3-snapshot-20260728.md`) **序列の正本**(source HEAD b40e11a3c)
- → 第二弾閉幕snapshot(`hot-script-speedup-round2-v2-snapshot-20260728.md`) 旧序列v2.0(fixed SHA 60a88c241)
- → [[cmd_4181_overhead_boundary_recon]] 計測境界表(集計の憲法)
- → [[弾スループット全体ボトルネック改善]] T4(影丸稼働)・T1b(蓄積待ち)との並列整理
- → [[殿裁定_全量テスト原則_20260728]] 個別弾選択実行・全量はwave最終1回
- origin: `[[殿下知_第四弾準備_20260728]] -> [[第二弾閉幕snapshot_v2.0序列]] -> [[殿裁定_4スクリプト以上_20260728]] -> [[家老RC_distinct_script基準]] -> [[full_precheck・inbox_write・publish_total・commit_hash計装・checks_mainの五弾]]`
