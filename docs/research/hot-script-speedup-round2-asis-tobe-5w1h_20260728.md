# ホットスクリプト集中高速化 第二弾 — AsIs/ToBe 5W1H設計書 v1.2.2 (2026-07-28 — row_count具体整数化(2,835行+除外内訳)。v1.2.1=家老RC全文同期+cluster仮説降格+full_precheck混合型+1file=1レーン原理。序列暫定=第一弾12/12(11:46完了)後の再snapshotでv2.0確定。殿裁可12:19により開始)

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
- **第二弾完了宣言=10弾全クローズ→台帳再集計→第三弾序列**(v1.2.1同期: §-1のrefresh 2枠除外後の弾数へ統一)
- **スコープ外(途中追加は理由を問わず禁止)**: `deploy_task:deploy_total`(cohortA 3位186.7s/n=4だが**既存deploy control-plane速度改善レーンへ帰属** — 残候補③report_publication/④ninja_scope_commitが整理済みであり、二重管理=車輪の再発明を避ける)・cron時差別設計(fullrecalc側)・上記以外の新規標的

## §0 結論 — 純オーバーヘッド標的序列(cohortA=第一弾10弾の最終CLEAR 2026-07-28T08:36 JST以降のみ)

**母集団の定義**: 第一弾の是正が全て入った後の発火のみ(全期間・是正前混入は序列を歪めるため無効 — 第一弾v2.1家老指摘④と同じ規律)。参考としてcohortB(本日全量)も併記するが、**序列はcohortAのみで引く**。

集計コマンド(v1.2.2でrow_count具体整数化): python3でdefense_overhead.jsonlをtimestamp下限**2026-07-27T23:36:00Z**・上限**2026-07-28T01:51:00Z**(将軍D0実測10:51 JSTの実行時刻)に限定し、§1境界表準拠pairのwall_msをn/sum/median/p95/max算出。**固定上下限内の対象event row_count=2,835行**(内訳: 序列対象2,586+除外 refresh_copy=123 / refresh_verify=122 / deploy_total=4。将軍D0再集計2026-07-28 12:15)。次回再snapshotでは新しい下限=第一弾最終CLEAR 11:46:57相当・上限・row_countを同様に固定して引き直す。

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
- **新規check_idの境界分類 → 確定済み(v1.2)**: three_layer_health:refresh_copy/refresh_verify(writer=`scripts/memory_db_live_insert.py:608`付近)は**background保守laneと確定**(家老一次確認+将軍のmemory_db_cache.sh L60-90現読=§3-1)。純オーバーヘッド母集団から除外済み。教訓: 新規check_idは分類を明記してから台帳へ(v1.0はこの違反で誤序列を引いた)
- 外れ値台帳の枝選択コンテキスト(第一弾v2.2 §3-5): 本弾の計装2弾および外れ値弾の観測追加は、枝選択・staged paths・cache hit等を同eventへ記録する要件に従う

## §2 To-Be — 進め方(第一弾§2の型を継承)

1. **1標的=1弾・複合弾禁止**。ACは同一条件before/after実測差分+品質2原則(挙動不変の正本突合+境界fixture)
2. **順序(v1.2.1同期: refresh 2弾は除外済み)**: 恒常課税型は累積順(#1 full_precheckから)。full_precheckは分散+混合尾のためフェーズ分解と枝条件の**同時計装**から入る(§3-4)。checks_main再トライは恒久サブ区間計装が第一AC(§3-2)
3. 計測は既存台帳`defense_overhead.jsonl`のみ(新台帳禁止)。効果報告=Δ(累積)+Δ(median)。削減見込み額の事前外挿禁止(LG082型 — 実測のみ)
4. **並列構造(第一弾で確定した原理)**: 同一fileの別checkはreserved-path collisionでfail-close=正当。∴**最大並列数=スコープ内の対象スクリプト数(1ファイル=1レーン)**、file内は先行完了待ち直列。本弾の現行スコープ(§-1=3スクリプト)なら3レーン、v2.0再序列でスクリプト数が変われば同数だけレーンが立つ
5. **凍結解除条件**: 第一弾12/12後の再snapshot版(v2.0)への家老忖度なしレビュー完了→殿裁可で順次起票。**それまで実装ゼロ**
6. 配備は家老自立配備(karo_direct、第一弾の殿裁定00:08と同型)を既定とする

## §3 未解決事項 → v1.2で全5項を将軍D0調査済み(2026-07-28 11:30、read-only+台帳集計のみ・実装なし)

1. ~~refresh_copy/verifyの境界分類~~ → **解消(ターン接触なしを現物確定)**: `scripts/lib/memory_db_cache.sh` L60-90現読 — refreshは`setsid -f` double-forkで完全非同期化済み(旧実装の「command substitutionがbackupを待つ」バグはコメントに記録された既修正事項)、cold-cache生成も非同期でreaderはcanonical DBを即使用、preflight外側budget 5sは検索自体の予算でrefresh待ちではない。∴家老判定(background保守lane)を現物で補強。間接影響はcold cache期のcanonical 9p直読でクエリが遅くなる分のみ — これはq11/three_layer(第一弾是正済み)側の計測に現れるため独立標的にしない
2. ~~checks_main残余の内訳~~ → **恒久計装が必要と確定**: cmd_save系の台帳check_idは6種(checks_main/checks_pre_session/q11/three_layer/memory_db_token/session_state)のみでchecks_main内サブ区分は**台帳に存在しない**(cmd_4189のフェーズ分解は報告内の一時実測で恒久化されていない)。∴checks_main再トライ弾の第一AC=サブ区間計測行の恒久追加(外れ値台帳の枝選択コンテキスト要件に従う)→ボトルネック上位特定→是正
3. ~~commit_hash呼出し回数の妥当性~~ → **時間クラスタ集中を実測、batch化は仮説へ降格(家老RC採用)**: cohortA(上限02:30Z固定)でn=243が2分gapクラスタ9個に集中=平均27.0回/クラスタ。ただし台帳event_idにreport/task識別子がなく**「1クラスタ=1報告フロー」は証明不能**(時間クラスタの回数であり同一報告flowの回数ではない)。∴是正弾の第一AC=report/task識別子の同event計装→重複判定→batch化はその後の仮説検証
4. ~~full_precheck 3点表~~ → **作成済み(混合型と判定・家老RC採用)**: n=158/累積180.1s(上限02:30Z固定)、top1寄与6.3%/top5寄与21.5%、>1s率22.2%、median 494ms/p95 3,771ms。**恒常単一型ではなく恒常+混合尾** — 「条件特定偵察不要」の断定は撤回し、弾の型=フェーズ分解と枝条件の**同時計装**→上位特定→是正
5. ~~B5/B2/B3計装の計測点設計~~ → **設計確定**: B5 inbox_write=persist(flock+YAML書込み)/nudge(tmux send-keys)/delivery verify(codex capture)の3計測点+total(加算対象はtotalのみ=親子非加算遵守)。B2/B3 startup gate=既存TIMING行(gate_shogun_startupはTIMING_COVERAGE measured=59が既に出力)をdefense_overhead.jsonlへ転記する薄いwriterブリッジのみ(新規計測実装は不要)

**残る未決定(調査では解消できない工程判断)**: 序列・scopeの最終確定は第一弾12/12完了後の再snapshot(v2.0)で行い殿裁可を仰ぐ — §-0(3)の通り

## §4 5W1H

- **WHY**: 第一弾で旧上位が圏外へ後退し、次の恒常課税上位(full_precheck・report_field_set群・checks_main残余)が標的として確定した。台帳再集計→新序列→次弾の反復が自動成長の回転そのもの
- **WHAT**: cohortA暫定序列に基づく**3スクリプト8check+計装2弾**の覚醒高速化(設計のみ、実装凍結中。最終序列は12/12後の再snapshot=v2.0)
- **WHEN**: 第一弾12/12完了(2026-07-28 11:46確定)→再snapshotでv2.0序列→家老レビュー→殿裁可→起票解禁
- **WHERE**: §-1の**3スクリプト**+台帳=defense_overhead.jsonl
- **WHO**: 偵察・実装=忍者(並列数=対象スクリプト数。1ファイル=1レーンの原理、現行スコープでは3)、配備=家老自立、検分=家老+軍師、裁可=殿
- **HOW**: 恒常課税型=フェーズ分解+枝条件の同時計装→最小差分実装→Δ実測証明、識別子欠落check=計装→重複判定→是正、計装弾=計測行追加のみ

## §5 因果リンク

- → [[hot-script高速化設計書]] 第一弾(v2.5)。様式・憲法・並列構造・完了条件の型元
- → [[cmd_4181_overhead_boundary_recon]] 計測境界表(集計の憲法)
- → [[cmd_4185_outlier_conditions]] 外れ値型手順(3点表)の型元
- → [[deploy control-plane速度改善]] deploy_total帰属先(スコープ外判断の根拠)
- origin: `[[殿下知_第二弾準備_20260728]] -> [[第一弾是正後cohortA再集計]] -> [[three_layer_health系新1位露出_第二弾序列v1.0]]`
