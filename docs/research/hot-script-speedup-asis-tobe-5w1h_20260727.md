# 【✅ CLOSED — 第一弾完了 12/12】ホットスクリプト集中高速化 — AsIs/ToBe 5W1H設計書 v3.0 (2026-07-28 11:56クローズ)

> **本設計書はクローズ済み(第一弾12/12全GATE CLEAR、最終CLEAR=memory_db_token_search 2026-07-28 11:46:57)。**
> **後継**: 第二弾設計書=`docs/research/hot-script-speedup-round2-asis-tobe-5w1h_20260728.md`(gist e13277d8)。第二弾の最終序列(v2.0)は本弾完了後の台帳再snapshotで確定し殿裁可を仰ぐ。
> 版歴: v2.5=10/12時点 / v2.4.1=three_layer行cohort訂正(家老APPROVE) / v2.3=殿裁定23:25スコープ決め打ち(§-1憲法) / v2.2=cmd_4185外れ値条件 / v2.1=cmd_4181境界再集計。以下の§-2が最終完了台帳、§0以降はクローズ時点の歴史記録である。

## §-2 第一弾 完了台帳(2026-07-28 11:56確定 — 12/12 GATE CLEAR)

集計コマンド: `grep -E "hot_script|cmd_4189" logs/gate_metrics.log | grep CLEAR`(12行、1件=cmd_id一意のCLEAR行=1check) + 各報告YAMLのΔ生貼付。

| # | check | 状態 | 是正内容 | Δ実測(既存台帳同条件before/after) |
|---|---|---|---|---|
| 1 | checks_main | ✅ CLEAR | 不変cmd本文のAC/command抽出を親shellで1回化(重複awk 15回排除) | median 905→688ms(-24.0%)、累積-1,066ms(n=5) |
| 2 | yaml_ast | ✅ CLEAR | affected=0時の全tree走査を除去 | 累積6,908→4ms(-99.9%)、median 2,364→1ms(n=3) |
| 3 | q11_semantic_search | ✅ CLEAR | 同一query並行missの非待機single-flight化+子孫pipe残留除去 | 外れ値3件321,181ms→97,207ms(Δ-223,974ms)、median 107,019→68ms |
| 4 | commit_hash | ✅ CLEAR | 無条件全量再parse2箇所へgrep事前フィルタ | 累積6,450→2,230ms(-65.4%)、median 210→70ms(-66.7%) |
| 5 | files_modified | ✅ CLEAR | 正規化+path検証を1回のYAML parseへ融合 | 累積6,900→3,960ms(-42.6%)、median 690→385ms(-44.2%)(n=10) |
| 6 | status | ✅ CLEAR | 非terminal書込みをatomic fast pathへ分離 | 累積410→320ms(-22.0%)、median 40→30ms(-25.0%)(n=10) |
| 7 | verdict | ✅ CLEAR | bc:no自動FAIL判定統合で重複全量parse1回削減 | 累積10,080→9,664ms(-4.1%)、median 409→381ms(-6.8%)(25走) |
| 8 | self_sync | ✅ CLEAR | 観測5項目追加→枝別実測→skip分岐化(reverify弾で独立再検証済み) | sync分岐median 1,378ms→skip分岐88ms(-93.6%) |
| 9 | three_layer_memory_ruling | ✅ CLEAR | cache miss条件限定の最適化(query正規化key+cmd間cache+negative cache+single-flight) | before=外れ値92件分布(累積1,009,352ms/median 4,126ms)。after=同一query 2並列fixtureで累積2ms/median 1ms(**全92件同条件afterは未計測** — cohort全体の恒常削減値ではない) |
| 10 | checks_pre_session | ✅ CLEAR | 全量YAML再parseをqueue世代一致時のみ再利用 | 同一入力20回でmedian 61.6→18.1ms(-70.7%)、累積1,827→377ms(-79.4%) |
| 11 | memory_db_token_search | ✅ CLEAR(11:46) | tokenなし枝(cohort 164件中56件)のworker起動・DB接触をpredicateで0化+prime済みcache再利用。tokenあり枝のINFO出力契約は不変 | baseline 164件=累積201,675ms/median 86ms。tokenなし枝の計装0件化を分枝実験で証明、full unit 2695/2695 PASS・SKIP0。**after同条件のwall_ms累積・medianは未計測**(次snapshot待ち) |
| 12 | instruction_sync | ✅ CLEAR(11:20) | 正本staged時のみの重い枝(top1 56.9%/top5 93.8%)を差分生成化 | 重い枝実測: 旧265.202s→新1.49s(**-99.4%**)。cohort再集計N=427で母集団前提の一致も再確認。~~-97.2%~~は非同一cohort混在の乗算外挿として**報告内で撤回済み — 引用禁止(第二弾序列材料にも使用禁止)** |

- 全弾が品質2原則(正本突合+境界fixture)+選択テストFAIL0・SKIP0を遵守。既存台帳のみのΔ証明(新台帳0件)は#1-#10で成立、**例外2件**: #11=after同条件台帳値未計測(構造証明のみ)、#12=重い枝の直接実測(台帳cohort外の同条件対)による証明
- 付随して掘れたインフラバグ2件も即修正済み: deploy_sec誤計上(issued/deployed混在→attempt_id対集計、q11誤3,321秒→真53秒、commit 0932543cc)・commit_hash弾のcontext_freshness BLOCK解消
- 並列構造の確定: 同一fileの別check同時配備はreserved-path collisionでfail-close(正当)。**最大並列=スクリプト単位3レーン**、file内は先行完了待ち直列(将軍裁定02:34)

## §-1 第一弾スコープ決め打ち(殿裁定2026-07-27 23:25 — 本設計書の憲法)

**殿原文**: 『終わりが来ないから、設計書の12スクリプトをやりきらないか？完了した後に第二弾のホットスクリプトをやろう。制限がないとエントロピーが拡大してカオスになる』『改良するスクリプトの数を先に明確に決め打とう』

**決め打ち: 第一弾=3スクリプト・12check・12弾以内**(§0表がSSOT):
| 実体スクリプト | 担当check_id | 件数 |
|---|---|---:|
| `scripts/cmd_save.sh` | checks_main・q11_semantic_search_overhead・three_layer_memory_ruling_overhead・checks_pre_session・memory_db_token_search_overhead | 5 |
| `scripts/report_field_set.sh` | commit_hash・status・files_modified・verdict | 4 |
| `scripts/hooks/git-pre-commit.sh` | yaml_ast・self_sync・instruction_sync | 3 |

- **完了条件(check単位)**: 恒常課税型=before/after Δ累積実測で是正済み / 外れ値型=条件ベース是正済み(q11第一AC=key反復率実測) / self_sync=観測5項目追加→枝別実測→是正判断済み
- **第一弾完了宣言=12check全クローズ**。その時点で台帳を再集計し第二弾の序列を新たに引く
- **スコープ外(全て第二弾以降へ繰延べ)**: Tier B(B1-B5台帳外計装含む)・cron時差別設計・新規標的の途中追加。**途中追加は理由を問わず禁止**(エントロピー抑制が本裁定の目的)

作成: 将軍 | 殿裁定(19:44「個別スクリプト覚醒高速化がベスト」/ 19:46「リストアップして集中的に高速化」/ 20:20「即時対処を選択」)
方針: 構造(型)は変えない。遅いスクリプト=バグとして個別に覚醒高速化。品質2原則(正本突合+境界fixture)維持=「削るな速くしろ」。
一次データ: `docs/research/cmd_4181_overhead_boundary_recon.md`(疾風偵察、verdict PASS、固定snapshot 39,070行+cutoff固定、writer行番号照合済み)
改訂履歴: v1.0の序列は家老BLOCK 6点(blt_195501: begin/end混在・実行本体込み・親子二重計上・lock保持と待ちの混同)で棄却。v2.0はその修正指示(親子非加算・selection/execution/queue_wait/hold分離・cutoff+row snapshot固定)に完全準拠した再集計へ全面置換した。

---

## §0 結論 — 純オーバーヘッド標的序列【歴史記録: 着手前の序列。全12check是正済み=§-2完了台帳が最終状態】(current cohort=self_sync是正commit 2026-07-25T02:56:17Z以降のみ。家老指摘④で全期間序列を無効化し再序列)

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

**序列の型が2種ある(各項目の型は上表の「型」列がSSOT)**:
- **恒常課税型**(checks_main・commit_hash・status・yaml_ast・files_modified・checks_pre_session・verdict): medianが数百ms〜秒で毎回発生。→ 実装最適化(全量再parse排除・cache SSOT・プロセス起動削減)が直撃する
- **外れ値型**(q11_semantic_search_overhead・three_layer_memory_ruling_overhead・instruction_sync、圏外のtest_granularity): medianはほぼゼロでmax数十〜数百秒が累積を支配。→ **最適化の前に発生条件特定が先**(常時最適化は的外れになる)

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

## §2 To-Be — 進め方【歴史記録: 全工程実施済み。凍結解除(殿裁定23:25)→家老自立配備(殿裁定00:08)→12/12完了】(v1.0から維持+補強)

1. **1標的=1弾**。ACは同一条件before/after実測差分+品質2原則(挙動不変の正本突合+境界fixture)
2. **順序**: 恒常課税型はcurrent cohort累積順(#1 checks_mainから)。外れ値型は「発生条件特定の偵察」(topN寄与率・閾値超過率・発生条件の3点表必須)を先行させ、最適化はその後。self_syncは残余外れ値の偵察のみ
3. 計測は既存台帳`defense_overhead.jsonl`のみ(新台帳禁止)。効果報告=Δ(累積)で行う。平均のみの報告不可
4. **B1は家老レーンの偵察結果を待って合流**。B5は計測行追加を第一ACに
5. **凍結解除条件**: 本v2.1の家老忖度なしレビュー完了後、殿裁可で順次起票

### 規模感(過大主張の訂正込み)
- v1.0の「1日9時間の浪費」は実行本体込み並行wall総和で**過大であった(撤回)**。純オーバーヘッド上位10件の累積は snapshot期間で約8,300秒(約2.3時間)。恒常課税型は全commit/起票/報告に乗るため、削減は全ロールのターン時間へ直結する

---

## §3 未解決事項【クローズ時最終状態: 1-2=特定→是正済み(§-2の#3・#8・#9・#12)、3=B5/B2B3計装は第二弾へ移管(第二弾設計書§-1)、4=B1復帰税は家老レーン継続(本設計書スコープ外で存続)】(v2.2更新 — cmd_4185で1-2を特定/部分特定へ)

1. ~~外れ値型のmax発生条件~~ → **cmd_4185で3点表(topN寄与率・閾値超過率・発生条件)を全数確定**(成果物=`docs/research/cmd_4185_outlier_conditions.md`、閾値=wall_ms>1000):
   | check | 判定 | 発生条件(writer現物照合済み) | 是正の方向性 |
   |---|---|---|---|
   | q11_semantic_search_overhead (N=173/累積672.9s※) | **特定** | command非空+FAST無効+session cache未命中でbackground検索起動 | キャッシュ+発火抑止(`cmd_save.sh:4095-4115`)。top5=503.4s(74.8%)が上限。**削減見込み額は撤回(家老レビュー③): cache hit化の効果はquery key反復率に依存し未計測。是正弾の第一ACでkey反復率を実測してから削減可能量を確定する**(条件特定→削減額のLG082型外挿を禁止) |
   | three_layer_memory_ruling_overhead (N=217/472.9s) | **特定** | FAST無効+query単位cache未命中。同一cmd反復で別query keyが生成される条件が残る | query正規化+negative cacheのcmd保存間共有。>1s群56件(25.8%) |
   | instruction_sync (N=374/160.1s) | **特定** | instructions正本がstagedの時のみbuild実行。top2=125.1s(78.1%)が支配 | buildを入力hash差分生成へ(`git-pre-commit.sh:942-957`) |
   | test_granularity (N=416/159.7s) | **部分特定** | 追加test時のみ全tree候補探索(script参照ごとgrep -RIlF走査)。台帳にstaged pathsなく完全照合不能 | script_ref→test候補の逆引き索引を一度生成(top5=80.7s/50.5%) |
   | self_sync (N=416/222.0s) | **部分特定** | live hook実行時のsync枝。枝選択が台帳に記録されずDrvFS競合と分離不能 | **追加観測が先**: running_is_live_hook/staged_hook_related/cmp_equal/sync_called/reexecの5項目を台帳へ付与してから最適化対象を決める |
   ※累積は追記型ログのため時点依存(設計書確認時573.3s→調査時点672.9s。母集団境界は不変)
2. ~~self_sync残余外れ値の発生条件~~ → 上表の通り**部分特定**。5項目の台帳追加が是正弾の第一AC
3. B5 inbox_write・B2/B3 startup gateの台帳計装
4. B1復帰税の悪化真因(家老レーン進行中)
5. **(v2.2新規)外れ値台帳の枝選択コンテキスト欠落**(cmd_4185 lesson_candidate): wall_ms+event_idだけでは重い枝を特定できない。計測writerは枝選択・staged paths・cache hit/sync/reexecを同eventへ記録すべし — 今後の新規check_id追加時の必須要件(§1の境界分類と併せて計測の憲法へ)

**実装凍結解除後の外れ値弾の型(v2.2確定・家老レビュー④で明文化)**: 常時最適化は的外れ。標的の絞りは q11=cache missのみ、three-layer=cache missのみ、instruction_sync=稀な重い枝のみ、test_granularity=稀な重い枝のみ、self_sync=観測5項目追加→枝別寄与の実測→対象決定の順。**5check=5個の独立弾として各別に起票する(1標的1弾=§2原則)。複合弾は禁止**

## §4 5W1H
- **WHY**: 純オーバーヘッド上位が全commit・起票・報告に毎回課税され、自動成長速度を律速する
- **WHAT**: 境界分類済み台帳に基づく1標的1弾の覚醒高速化。恒常課税型=実装最適化、外れ値型=条件特定→是正
- **WHEN**: 本v2.1レビュー→殿裁可→順次起票。外れ値偵察が先行弾
- **WHERE**: §0序列のwriterスクリプト群。台帳=defense_overhead.jsonl
- **WHO**: 偵察・実装=忍者(1標的1名並列)、検分=家老+軍師、裁可=殿
- **HOW**: 発生条件/真因4型(全量再parse・affected=0全処理・プロセス多段起動・lock持ち過ぎ)→最小差分実装→Δ累積で証明→還流

## §5 因果リンク
- → [[cmd_4185_outlier_conditions]] 外れ値型5checkの3点表+是正弾入力(§3の一次データ)
- → [[cmd_4181_overhead_boundary_recon]] 本v2の一次データ(境界表+再集計序列)
- → [[deploy control-plane速度改善]] 恒常課税型への手法の型元(cache SSOT/即return)
- → [[cmd_4182]] doc-only fast-path(着地済みの姉妹弾)
- origin: `[[家老BLOCK6点_計測境界混在]] -> [[cmd_4181純オーバーヘッド分離再集計]] -> [[標的序列v2確定_恒常課税型と外れ値型の二分]]`

**MEM引用**:
- [MEM: memory_db ts=2026-07-27 "IB-V: enforcement_level欄は『実装したか』を示すが『効いているか』を示さない"] 外れ値型に「条件特定が先」を課す根拠
- [MEM: obsidian link=[[LS-A09]] (26)集計値はどのイベントの前か後かを確認 — 境界分類を集計の憲法とする根拠]
