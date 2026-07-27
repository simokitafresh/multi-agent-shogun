# ホットスクリプト集中高速化 — AsIs/ToBe 5W1H設計書 v2.1 (2026-07-27 — cmd_4181再集計+家老指摘④のcurrent cohort再序列反映)

作成: 将軍 | 殿裁定(19:44「個別スクリプト覚醒高速化がベスト」/ 19:46「リストアップして集中的に高速化」/ 20:20「即時対処を選択」)
方針: 構造(型)は変えない。遅いスクリプト=バグとして個別に覚醒高速化。品質2原則(正本突合+境界fixture)維持=「削るな速くしろ」。
一次データ: `docs/research/cmd_4181_overhead_boundary_recon.md`(疾風偵察、verdict PASS、固定snapshot 39,070行+cutoff固定、writer行番号照合済み)
改訂履歴: v1.0の序列は家老BLOCK 6点(blt_195501: begin/end混在・実行本体込み・親子二重計上・lock保持と待ちの混同)で棄却。v2.0はその修正指示(親子非加算・selection/execution/queue_wait/hold分離・cutoff+row snapshot固定)に完全準拠した再集計へ全面置換した。

---

## §0 結論 — 純オーバーヘッド標的序列(current cohort=self_sync是正commit 2026-07-25T02:56:17Z以降のみ。家老指摘④で全期間序列を無効化し再序列)

**「純オーバーヘッド」= 防御機構自体の消費時間。テスト実行本体・子job・lock保持・queue待ちは別母集団へ分離済み(§2)。母集団は是正済み現行コードの発火のみ(全期間集計は過去の既修正分を現在の標的に混ぜるため無効 — self_syncで実証: pre累積1,503.8s/median 1.9s → post累積221.6s/median 73ms=cmd_4168が既に-85%達成済みで現行1位ではなかった)。**

集計コマンド: python3でdefense_overhead.jsonlをtimestamp>2026-07-25T02:56:17Zに限定し境界表準拠pairのwall_msをn/sum/median/p95/max算出(将軍D0実測2026-07-27 21:51)。

| # | source:check_id | 累積(current) | n | median | p95 | max | 型 |
|---|---|---:|---:|---:|---:|---:|---|
| 1 | **cmd_save:checks_main** | **1,790.0s** | 715 | 1.6s | 5.1s | 61.7s | 恒常課税 |
| 2 | report_field_set:commit_hash | 786.4s | 1,936 | 330ms | 1.0s | 2.4s | 恒常課税(回数最多) |
| 3 | cmd_save:q11_semantic_search_overhead | 573.3s | 164 | 1ms | 12.1s | 133.3s | 外れ値 |
| 4 | report_field_set:status | 497.1s | 564 | 340ms | 1.6s | 16.3s | 恒常課税 |
| 5 | git_pre_commit:yaml_ast | 490.6s | 409 | 771ms | 4.1s | 14.9s | 恒常課税 |
| 6 | cmd_save:three_layer_memory_ruling_overhead | 452.0s | 208 | 1ms | 12.7s | 32.2s | 外れ値 |
| 7 | report_field_set:files_modified | 279.4s | 364 | 690ms | 1.5s | 3.0s | 恒常課税 |
| 8 | cmd_save:checks_pre_session | 277.5s | 715 | 189ms | 1.2s | 4.3s | 恒常課税 |
| 9 | git_pre_commit:self_sync | 221.6s | 412 | 73ms | 2.9s | 16.3s | **是正済み残余**(cmd_4168効果確認。残余外れ値のみ偵察対象) |
| 10 | cmd_save:memory_db_token_search_overhead | 201.7s | 164 | 86ms | 4.6s | 14.3s | 混合 |
| 11 | report_field_set:verdict | 187.4s | 266 | 590ms | 1.6s | 4.4s | 恒常課税 |
| 12 | git_pre_commit:instruction_sync | 160.1s | 370 | 1ms | 1ms | 91.0s | 外れ値(極端: median 1ms/max 91s) |

- test_granularityはcurrent cohortで上位12圏外へ後退(post: top1寄与20.9%/top5 50.5%、median 2ms/p95 1.8s — 家老実測)。外れ値弾の対象としては維持
- **外れ値型の弾は表を固定フォーマット化する**: topN寄与率・閾値超過率・発生条件の3点を必須記載(家老指摘④後段)

**序列の型が2種ある**:
- **恒常課税型**(#1,2,4,5,7): medianが数百ms〜秒で毎回発生。→ 実装最適化(全量再parse排除・cache SSOT・プロセス起動削減)が直撃する
- **外れ値型**(#3,6,8,9): medianはほぼゼロでmax数十〜数百秒が累積を支配。→ **最適化の前に外れ値の発生条件特定が先**(常時最適化は的外れになる)

### Tier B: 台帳外(前版から維持)
- B1 家老deepdive追体験(復帰税、本日約68分・悪化傾向) — **家老が偵察自立配備済み**(cmd_karo_recon_deepdive_replay_regression)
- B2 gate_karo_startup.sh / B3 gate_shogun_startup.sh(16.4s/回・TIMING行あり) / B4 ninja_scope_commit本体 / B5 inbox_write(未計測→計測行追加が弾の第一AC)

### 着地済み
- **cmd_4182 doc-only fast-path**(2026-07-27): 文書のみdiffのaffected_tests+heavy_job_admissionスキップ実装済み(guard全維持・陰性対照3ケース)。11分lock保持事故の再発防止

---

## §1 計測境界表(writer現物照合 — 集計の憲法)

全表は`docs/research/cmd_4181_overhead_boundary_recon.md`。要点:
- **集計禁止**: three_layer_health:refresh_window(begin=0ms/end=窓長の混在marker)、cache_rowid_gap(時間でない判定値)
- **参考母集団(非加算)**: queue_wait 3,546s / lock_hold 3,260s / selection+execution 28,359s / execution_body 15,913s / copy・verify(子) 23,457s / parent_total 31,774s
- **原則**: 親totalと子は非加算。affected_testsは実行本体込みゆえ純オーバーヘッド順位から除外。singleflight_holdは保持時間でありwaitではない
- 今後telemetryを追加する者はこの境界分類に従う(新規check_idは分類を明記してから台帳へ)

---

## §2 To-Be — 進め方(v1.0から維持+補強)

1. **1標的=1弾**。ACは同一条件before/after実測差分+品質2原則(挙動不変の正本突合+境界fixture)
2. **順序**: 恒常課税型はcurrent cohort累積順(#1 checks_mainから)。外れ値型は「発生条件特定の偵察」(topN寄与率・閾値超過率・発生条件の3点表必須)を先行させ、最適化はその後。self_syncは残余外れ値の偵察のみ
3. 計測は既存台帳`defense_overhead.jsonl`のみ(新台帳禁止)。効果報告=Δ(累積)で行う。平均のみの報告不可
4. **B1は家老レーンの偵察結果を待って合流**。B5は計測行追加を第一ACに
5. **凍結解除条件**: 本v2.0の家老忖度なしレビュー完了後、殿裁可で順次起票

### 規模感(過大主張の訂正込み)
- v1.0の「1日9時間の浪費」は実行本体込み並行wall総和で**過大であった(撤回)**。純オーバーヘッド上位10件の累積は snapshot期間で約8,300秒(約2.3時間)。恒常課税型は全commit/起票/報告に乗るため、削減は全ロールのターン時間へ直結する

---

## §3 未解決事項
1. 外れ値型(#3,6,8,9)のmax発生条件(717秒のtest_granularity等) — 高速化前の必須偵察
2. self_syncの現状実装照合 — 過去に-83%改善記録がある区間名と同名。同一区間の残余か別区間かをwriter現物で確認してから弾設計
3. B5 inbox_write・B2/B3 startup gateの台帳計装
4. B1復帰税の悪化真因(家老レーン進行中)

## §4 5W1H
- **WHY**: 純オーバーヘッド上位が全commit・起票・報告に毎回課税され、自動成長速度を律速する
- **WHAT**: 境界分類済み台帳に基づく1標的1弾の覚醒高速化。恒常課税型=実装最適化、外れ値型=条件特定→是正
- **WHEN**: 本v2.0レビュー→殿裁可→順次起票。外れ値偵察が先行弾
- **WHERE**: §0序列のwriterスクリプト群。台帳=defense_overhead.jsonl
- **WHO**: 偵察・実装=忍者(1標的1名並列)、検分=家老+軍師、裁可=殿
- **HOW**: 発生条件/真因4型(全量再parse・affected=0全処理・プロセス多段起動・lock持ち過ぎ)→最小差分実装→Δ累積で証明→還流

## §5 因果リンク
- → [[cmd_4181_overhead_boundary_recon]] 本v2の一次データ(境界表+再集計序列)
- → [[deploy control-plane速度改善]] 恒常課税型への手法の型元(cache SSOT/即return)
- → [[cmd_4182]] doc-only fast-path(着地済みの姉妹弾)
- origin: `[[家老BLOCK6点_計測境界混在]] -> [[cmd_4181純オーバーヘッド分離再集計]] -> [[標的序列v2確定_恒常課税型と外れ値型の二分]]`

**MEM引用**:
- [MEM: memory_db ts=2026-07-27 "IB-V: enforcement_level欄は『実装したか』を示すが『効いているか』を示さない"] 外れ値型に「条件特定が先」を課す根拠
- [MEM: obsidian link=[[LS-A09]] (26)集計値はどのイベントの前か後かを確認 — 境界分類を集計の憲法とする根拠]
