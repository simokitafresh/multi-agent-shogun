# ホットスクリプト集中高速化 第二弾 — AsIs/ToBe 5W1H設計書 v1.1 (2026-07-28 — 家老REQUEST_CHANGES 3点反映。§0序列は暫定、第一弾12/12完了後の再snapshotで最終確定してから殿裁可。実装凍結継続)

## §-0 v1.1改訂(家老レビュー2・blt_105708の全採用)

1. **refresh_copy/refresh_verifyを序列から除外**: 家老一次確認(memory_db_cache.sh・memory_db_live_insert_async.py・ninja_monitor.sh現物)により、refreshは`setsid -f` double-forkのbackground実行・呼出し側は旧cache即返却・live insertはSKIP_CACHE_SYNC=1 — **純ターンoverheadではなくbackground保守lane**と確定。v1.0の新1-2位は誤分類だった(「新規check_idは分類を明記してから台帳へ」違反の実例として記録。background laneの長時間化はターン外の別課題であり、必要なら第三弾以降で別母集団として扱う)
2. **集計の再現性必須化**: 集計コマンドへ上限timestampと対象row_countの固定を追加(下記§0)。下限08:36とdeploy_total既存lane除外は家老妥当判定
3. **序列は暫定**: 第一弾12/12完了後に再snapshot・再序列・scope最終確定を行い、その版(v2.0)で殿裁可を仰ぐ。§-1/§0は暫定草案

> 第一弾=`docs/research/hot-script-speedup-asis-tobe-5w1h_20260727.md`(v2.5、10/12消化・残2弾作業中)。本書は第一弾と同じ様式・同じ計測の憲法(§1境界表)・同じ完了条件の型で、**第一弾是正後のcohortから新序列を引いた第二弾**である。殿方針(2026-07-28 10:49): 第一弾でやったものも依然ボトルネックなら再度トライする。

## §-1 第二弾スコープ決め打ち(第一弾§-1憲法の踏襲 — 数を先に固定)

**決め打ち(暫定草案・v1.1でrefresh系2枠を除外): 3スクリプト・8check+計装2弾=10弾以内**(§0表がSSOT。最終scopeは第一弾12/12後の再序列で確定):

| 実体スクリプト | 担当check_id | 件数 |
|---|---|---:|
| `scripts/gates/gate_gunshi_report_precheck.sh` | full_precheck | 1 |
| `scripts/cmd_save.sh` | checks_main(**再トライ**) | 1 |
| `scripts/report_field_set.sh` | parent_ac_coverage・parent_contract_fingerprint・task.commit_contract・publish_total・atomic_replace・commit_hash(**再トライ**) | 6 |
| (計装のみ・最適化なし) | B5 inbox_write計測行追加・B2/B3 startup gate台帳計装 | 2弾 |

- **完了条件(第一弾と同型)**: 恒常課税型=既存台帳`logs/defense_overhead.jsonl`同条件before/afterのΔ累積・Δmedian実測で是正済み / 外れ値型=発生条件特定(3点表: topN寄与率・閾値超過率・発生条件)→条件ベース是正済み / 計装弾=計測行が台帳へ実記録されることの二値確認のみ
- **第二弾完了宣言=12弾全クローズ→台帳再集計→第三弾序列**
- **スコープ外(途中追加は理由を問わず禁止)**: `deploy_task:deploy_total`(cohortA 3位186.7s/n=4だが**既存deploy control-plane速度改善レーンへ帰属** — 残候補③report_publication/④ninja_scope_commitが整理済みであり、二重管理=車輪の再発明を避ける)・cron時差別設計(fullrecalc側)・上記以外の新規標的

## §0 結論 — 純オーバーヘッド標的序列(cohortA=第一弾10弾の最終CLEAR 2026-07-28T08:36 JST以降のみ)

**母集団の定義**: 第一弾の是正が全て入った後の発火のみ(全期間・是正前混入は序列を歪めるため無効 — 第一弾v2.1家老指摘④と同じ規律)。参考としてcohortB(本日全量)も併記するが、**序列はcohortAのみで引く**。

集計コマンド(v1.1で再現性必須化): python3でdefense_overhead.jsonlをtimestamp下限2026-07-27T23:36Z(=08:36 JST)**かつ上限=集計実行時刻(次回再集計時は同一上限で固定)・対象row_countを出力に併記**して、§1境界表準拠pairのwall_msをn/sum/median/p95/max算出(将軍D0実測2026-07-28 10:51。上限未固定はv1.0の欠陥として是正)。

| # | source:check_id | 累積(cohortA) | n | median | p95 | max | 型 |
|---|---|---:|---:|---:|---:|---:|---|
| — | ~~three_layer_health:refresh_copy 872.5s~~ | — | — | — | — | — | **v1.1除外**(background保守lane=純ターンoverheadに非ず。§-0参照) |
| — | ~~three_layer_health:refresh_verify 772.1s~~ | — | — | — | — | — | **v1.1除外**(同上) |
| — | deploy_task:deploy_total | (186.7s) | 4 | 40,320ms | — | 72,050ms | **スコープ外**(既存deployレーン帰属) |
| 1 | gate_gunshi_report_precheck:full_precheck | 102.1s | 102 | 494ms | 3,771ms | 11,279ms | 恒常課税+外れ値尾 |
| 2 | cmd_save:checks_main(再) | 84.4s | 82 | 930ms | 1,789ms | 2,628ms | 恒常課税(第一弾-24%後も残存1位級) |
| 3 | report_field_set:parent_ac_coverage | 44.2s | 41 | 540ms | 2,370ms | 2,420ms | 恒常課税 |
| 4 | report_publish:publish_total | 40.6s | 121 | 230ms | 690ms | 1,740ms | 恒常課税(回数多) |
| 5 | report_field_set:parent_contract_fingerprint | 39.7s | 41 | 400ms | 2,250ms | 2,320ms | 恒常課税 |
| 6 | report_field_set:task.commit_contract | 37.2s | 62 | 355ms | 1,370ms | 1,760ms | 恒常課税 |
| 7 | report_field_set:commit_hash(再) | 34.6s | 160 | 190ms | 410ms | 620ms | 恒常課税(第一弾-66%後も回数最多で残存) |
| 8 | report_publish:atomic_replace | 27.2s | 118 | 180ms | 410ms | 540ms | 恒常課税 |
| 11 | (計装弾)B5 inbox_write | 未計測 | — | — | — | — | 計装のみ |
| 12 | (計装弾)B2/B3 startup gate | 未計測(参考16.4s/回) | — | — | — | — | 計装のみ |

**cohortB(本日全量・参考、序列には不使用)**: refresh_copy 3,723.6s/refresh_verify 3,377.7s/checks_main 2,266.6s(是正前混入)/q11 869.7s(是正前混入)。第一弾対象のq11・three_layer(cmd_save側)・yaml_ast・files_modified・status・verdict・checks_pre_sessionはcohortAで全て12位圏外へ後退=**第一弾の効果が新cohortで確認された**。

**再トライ2件の根拠(殿方針)**: checks_main はfixture上-24%だがcohortA実測median 930msでなお恒常課税4位 — 残余ボトルネックの内訳再実測から。commit_hash はmedian 330→190msへ改善済みだが n=160 の回数最多で累積9位に残存 — 呼出し回数側(batch化)の設計判断が次の軸。

## §1 計測境界表(第一弾から継承 — 集計の憲法)

- 全表=`docs/research/cmd_4181_overhead_boundary_recon.md`。集計禁止・参考母集団(非加算)・親子非加算の原則は第一弾§1と同一
- **★新規check_idの境界分類が未確定**: three_layer_health:refresh_copy/refresh_verify(writer=`scripts/memory_db_live_insert.py:608`付近)は境界表制定後に台帳へ入った新顔。refresh_window(集計禁止)と同族のbackground処理である可能性があり、**「純オーバーヘッド(ターンを止める)か、background(ターンを止めない)か」の分類確定が#1・#2弾の第一AC**(誤分類のまま最適化すると的外れ — 第一弾q11の教訓)
- 外れ値台帳の枝選択コンテキスト(第一弾v2.2 §3-5): 本弾の計装2弾および外れ値弾の観測追加は、枝選択・staged paths・cache hit等を同eventへ記録する要件に従う

## §2 To-Be — 進め方(第一弾§2の型を継承)

1. **1標的=1弾・複合弾禁止**。ACは同一条件before/after実測差分+品質2原則(挙動不変の正本突合+境界fixture)
2. **順序**: #1・#2(refresh_copy/verify)は**境界分類確定→3点表offence条件特定→是正**の外れ値型手順を先行。恒常課税型(#3-#10)は累積順
3. 計測は既存台帳`defense_overhead.jsonl`のみ(新台帳禁止)。効果報告=Δ(累積)+Δ(median)。削減見込み額の事前外挿禁止(LG082型 — 実測のみ)
4. **並列構造(第一弾で確定)**: 同一fileの別checkはreserved-path collisionでfail-close=正当。最大並列=スクリプト単位4レーン、file内は先行完了待ち直列
5. **凍結解除条件**: 本v1.0の家老忖度なしレビュー完了後、殿裁可で順次起票。**それまで実装ゼロ**
6. 配備は家老自立配備(karo_direct、第一弾の殿裁定00:08と同型)を既定とする

## §3 未解決事項

1. **refresh_copy/refresh_verifyの境界分類**(§1★) — backgroundならターン影響の実証(どのwait経路に乗るか)まで含めて分類確定が先
2. checks_main残余930msの内訳 — 第一弾cmd_4189のフェーズ分解装置を再利用して残余ボトルネック上位を再実測
3. commit_hashの呼出し回数側(n=160/cohortA)の妥当性 — 単価は是正済みのため、呼出し元の重複呼出し有無の確認が先
4. full_precheckのp95 3.8s/max 11.3sの外れ値条件 — 3点表未作成
5. B5/B2/B3計装の計測点設計(親子非加算の遵守)

## §4 5W1H

- **WHY**: 第一弾で旧上位が圏外へ後退した結果、隠れていた新上位(three_layer_health系1,644s)が露出した。台帳再集計→新序列→次弾の反復が自動成長の回転そのもの
- **WHAT**: cohortA序列に基づく4スクリプト10check+計装2弾の覚醒高速化(設計のみ、実装凍結中)
- **WHEN**: 本v1.0家老レビュー→殿裁可→起票解禁。第一弾残2弾(memory_db_token_search/instruction_sync)の完了とは独立に準備
- **WHERE**: §-1の4スクリプト+台帳=defense_overhead.jsonl
- **WHO**: 偵察・実装=忍者(スクリプト単位4レーン並列)、配備=家老自立、検分=家老+軍師、裁可=殿
- **HOW**: 外れ値型=境界分類→3点表→条件是正、恒常課税型=フェーズ分解→最小差分実装→Δ実測証明、計装弾=計測行追加のみ

## §5 因果リンク

- → [[hot-script高速化設計書]] 第一弾(v2.5)。様式・憲法・並列構造・完了条件の型元
- → [[cmd_4181_overhead_boundary_recon]] 計測境界表(集計の憲法)
- → [[cmd_4185_outlier_conditions]] 外れ値型手順(3点表)の型元
- → [[deploy control-plane速度改善]] deploy_total帰属先(スコープ外判断の根拠)
- origin: `[[殿下知_第二弾準備_20260728]] -> [[第一弾是正後cohortA再集計]] -> [[three_layer_health系新1位露出_第二弾序列v1.0]]`
