# 主題1: 全期間再計算(fullrecalculate)速度 — AsIs/ToBe 5W1H設計書 v3.3 (2026-07-28 — cmd_4186計測配線の本番初収穫を反映。v3.2=壁時計確定+3配線実装)

## §0.-1 本番初収穫(2026-07-28定期実行 FoF run=20260728014047YD63KJ — cmd_4186新telemetryの初回本番値。将軍D0回収11:20)

**L3 FoF total 565.92s(78PF)の排他的内訳(profiling原文生貼付)**:
| 区間 | 秒 | 備考 |
|---|---:|---|
| monthly_returns_gen | **318.99** | 最大(前回run 275.20→今回増。run間変動あり) |
| **dw_signals_deferred_flush** | **117.61** | ★下記「二重計上解消」参照 |
| daily_loop | 92.38 | |
| dl_pipeline_exec | 35.03 | |
| dl_signal_gen / dl_rebalance_check | 26.34 / 26.32 | |
| cache_init | 16.73 | |
| db_write / dw_component_weights | 9.09 / 8.76 | |
| unmeasured残余(deferred除く: pf_overhead 6.76+post_loop 1.33+pre_loop 0.05+residual 0.0) | 8.14 | 区分計測でほぼ消滅 |
| dw_signals_append(inner) | 0.01 | |

**★覚醒の核心 — 二重計上の解消**: 旧v3.1で別標的だった「unmeasured 122.41s」(攻め順2位)と「dw_signals_flush 115.26s」(順位除外の混合値)は、**実体がほぼ同一のdeferred DB flush 117.61s**であった。unmeasured_breakdownのdeferred_flush=dw_signals_deferred_flushが完全一致(117.61s)し、inner appendは0.01s。∴L3の真の標的は**mr_gen 319s > deferred flush 117.6s > daily_loop 92.4s**の3本に単純化される(旧「未計測の霧」は本番値で消えた)。

**PF別初収穫(calculation_performance_log substep=fof_total、78行/計430.19s)**: 上位=GSシン四つ目-常勝10.50s、同-激攻7.61s、Ave-X 7.23s、裏Ave-X 7.19s…と**分布は平坦(top8が7-10.5s帯)**。特定PF支配ではなく全PF均等課税 — PF単位の個別最適化よりループ共通コスト(mr_gen・deferred flush)の削減が有効という配分証拠。fof_total計430s vs L3 total 566s の差≈136s=PFループ外(cache_init・mr_gen終端一括etc.)。

## §0.0 運用壁時計(cmd_4184で一次ログ確定 — v3.2新設)

**運用壁時計(殿のデータ反映待ち時間)= 42分25秒(2,545s)** — standard cron起動01:10:13→FoF完了01:52:38(2026-07-27定期実行、standard run=20260727011449IYJS2V / FoF run=20260727014042HSIHNE)。

| 区間 | 時間 | 性質 |
|---|---:|---|
| **standard起動→完了(親区間)** | **6分07秒(367s)** | 下記2行の親 |
| ├ standard側L1待機(sync-wait) | 4分01秒(241s) | 上流ETL成功待ち |
| └ standard計算等(367-241) | 2分06秒(126s) | 待機外のrun内時間 |
| standard完了→FoF cron起動 | 23分54秒(1,434s) | **cron時差(schedule gap)— 計算ではなく待機** |
| FoF側L2待機 | 0秒 | 待機なし |
| FoF起点壁時計(補助KPI) | 12分24秒(744s) | FoF cron起動→FoF完了 |

- 検算(家老レビュー①反映): 367+1,434+744=2,545s=42分25秒で隣接境界の秒差合計と一致
- **正KPI=standard起点**(殿の運用目的=データ反映の待ち時間に合致)。FoF起点は補助値
- **旧807.9秒(91.3+716.6)は「累積計算時間」であり壁時計ではない**(cmd_4179 §4の総運用時間記述は本値で訂正済み=assumption_invalidation)
- 含意: 壁時計42分25秒のうち**cron時差23分54秒(56%)は計算と独立の待機**。ただしschedule変更は個別スクリプト覚醒高速化(殿裁定19:44)とは別のschedule設計であり、**別設計候補として§4-8に記録するのみ — 殿裁可まで起票しない**(家老レビュー②反映)

作成: 将軍 | 殿指示(2026-07-22 08:28 主題1起点 / 2026-07-27 19:17「偵察が終わったら設計書の再構築をせよ」/ 19:19「実装には進まず設計書の徹底的なブラッシュアップ完了が目的」)
対象: DM-Signal `fullrecalculate`(全PF全期間の再計算パイプライン、engine=`recalculate_fast.py`)
方針: 品質を落とさず超速化(殿doctrine「削るな速くしろ」)。**本設計書は設計のみ。実装cmdは殿の別途下知まで起票しない(意図的保留であり先送りではない)。**
一次データ: `docs/research/cmd_4179_fullrecalc_timing_recon.md`(飛猿偵察、verdict PASS、Render本番log原文回収)

---

## §0 確定実測(2026-07-27 本番run原文、run ID付き)

**運用の実体はstandard/FoFの2分離runで、cmd_4180現物照合により論理直列と確定(FoF側はetl_layer_sync_wait.shがstandard当日成功まで待つ)。ただしcron起動は時差起動(01:10/01:40)のため、2 runのduration単純和(約805秒)は「累積計算時間」であり運用壁時計の下限ではない(家老指摘③)。壁時計は起点(どのcron起動を0とするか)と待機境界を定義した上で再算出する(§4-6)。**

### §0.1 L3 FoF 503秒の内部内訳(cmd_4180が本番DB `recalculation_timings.layer_data.L3_fof.metadata.profiling` から回収・原文生貼付済み)

| 区間 | 実測 | 備考 |
|---|---:|---|
| **monthly_returns_gen** | **275.20s** | L3内最大(54.7%)。新・最優先標的 |
| unmeasured | 122.41s (24.4%) | 未区分塊。区分計測が次の偵察標的 |
| dw_signals_flush | 115.26s | deferred flush(db_write外側加算のため単純合計不可) |
| daily_loop | 80.61s | |
| dl_pipeline_exec / dl_rebalance_check / dl_signal_gen | 30.14s / 23.45s / 22.98s | |
| cache_init / db_write / dw_component_weights | 14.25s / 7.72s / 7.43s | |

- PF別内訳は`calculation_performance_log`当該run 0行で回収不能。最小計測配線案(既存CalculationPerformanceLog再利用・出力完全一致契約)はcmd_4180成果物に設計済み — **実装は殿裁可後**
- **profiler境界注記(家老指摘②)**: 各区間は排他ではない — daily_loopはdl_*系を包含し、dw_signals_flushは内側db_write appendと外側deferred flush加算の**混合値**。∴単純合計をtotalと比較せず、**dw_signals_flush 115.26sは外側deferred分離の計測が済むまで全量を標的として扱わない**。unmeasured 122.41sはtop-level算出ゆえ妥当。攻め順の各弾はparent/child/exclusive/mixedの境界を弾内で先に確定してから最適化する

| run | PF数 | TOTAL | 内訳(同一run内) |
|---|---|---:|---|
| standard `20260727011449IYJS2V` | 24 | **90.0s** | L2=57.5s(63.3%、うちtrade_perf 1.5s) / L5=12.6s(13.9%) / unaccounted=20.8s(22.9%) |
| FoF `20260727014042HSIHNE` | 78 | **715.0s** | **L3_fof=503s(70.3%)⚠主犯** / L2=154s(21.6%、うちtrade_perf **117s**=L2内76.0%) / L5=42.3s(5.9%) / unaccounted=15.6s(2.2%) |

**ボトルネック序列(確定)**: ①L3 FoF 503秒 → ②L2 trade_perf(FoF側) 117秒 → ③L5 42.3秒。

---

## §1 v1系の誤りの経緯(教訓として保持 — 再発防止の型)

| 版 | 誤り | 訂正 |
|---|---|---|
| v1.0 (07-22) | 「L1-L4内訳は一度も未計測=最大空白」 | 誤り。TIMING SUMMARY基盤はcmd_3842でL5登録まで実装済みで、id206実測(07-10)も存在した。**三層記憶を突合せず起票した将軍の検証スキップ** |
| v1.0 (07-22) | 「L5=9.9%」(671.18−66.64の差引き) | **無効**。671.18秒=id214のDB status総時間、66.64秒=cmd_3835 Phase4の**別run**。異なるrun lineageの数値を差引きした混算(cmd_4179偵察が出典分離で確定) |
| v1.0 (07-22) | 「真ボトルネックはL1-L4のどこか不明」 | 直近本番runの同一run内訳でL3 FoF 70.3%と確定。**run ID単位でしか内訳を語らない**のが正しい型 |

**型**: (1)総時間と内訳は同一run IDの原文からのみ取る。異run差引き禁止 (2)時点比較はPF数・PF集合・cold/warmを固定できる場合のみ倍率を語る (3)設計書の数値主張は起票前に三層記憶と突合する。

---

## §2 As-Is 構造(確定実測に基づく)

### §2.1 L3 FoF 503秒(主犯・70.3%)
- FoF(Fund of Funds)78PFの再計算。FoF of FoFのトポロジカルソート依存=真の逐次依存を含む
- TIMING SUMMARYはL3_fofを一括表示だが、**処理別内訳は本番DBのprofiling保存値から回収済み(§0.1)。未計測なのはPF別のみ**(calculation_performance_log 0行、§4-2)
- 07-10 id206時点ではL3=234s(9.4%)だったが、当時はL5 cold再生成1659.78秒が支配していたため相対比が別物。L5解消後にL3が主犯として露出した構造

### §2.2 L2 trade_perf 117秒(二次・FoF run内)
- standard runでは1.5秒に対しFoF runで117秒 — **trade_perfのコストはFoF run側に集中**(同一日の2 run実測)
- **仮説(未検証・家老BLOCK③反映)**: 過去のN+1除去(OPT-1/2等)がFoF経路に未適用の可能性。cmd_4179一次データの外であり、コード行番号の現物確認を次回偵察のACに含めるまで仮説に留める
- 06-26分析(約100-105秒)との単純比較はrun条件不定のため不可(§4)

### §2.3 L5 precompute_raw 42.3秒(5.9%)
- id206時点はL5=1659.78秒(66.5%)が支配していたが、当時は103PF cold一括であり直近run(FoF 78PF)とは条件が異なる。**「96.7%短縮」という倍率主張は§1の同条件原則に反するため棄却する(家老BLOCK②反映)** — 言えるのは「直近runではL5が同一run内5.9%であり支配的でない」ことのみ
- **既存L5資産(並列化v1.3.1=7.8x、fingerprint skip v1.1)の優先度は低** — 完成設計として保存し、L3/L2解消後に残余が有意なら掘り起こす

### §2.4 制約(cmd_4180で全項目を行番号付き現物確定 — 引継ぎ仮説は解消)
| 項目 | 判定 | 根拠(cmd_4180 AC2表) |
|---|---|---|
| advisory lock排他(fail-closed) | **確定** | recalc_status.pyのpg_try_advisory_lock |
| FoF依存順の逐次実行 | **確定** | Kahnソート+単一for-loop |
| 層内並列の実装 | **なし(棄却)** | ready集合はsortのみ。並列化はSession・共有cache・commit境界の再設計が必要=大工事と判明 |
| MR生成→commit→cache reload→後続親FoFの順序制約 | **確定** | recalculate_fof.pyの逐次連鎖 |
| trade_perf N+1除去がFoF未適用 | **棄却** | preload/cacheは全target_portfolios共通ループへ渡る。FoF 117秒は共通経路上の実測コストであり経路差別ではない |
| standard/FoF cron並列 | **棄却(論理直列)** | etl_layer_sync_wait.shが上流当日成功まで待機 |
- 品質不変量(byte/ID完全一致・境界fixture)は品質2原則由来の全PJ共通契約

---

## §3 To-Be(設計の骨子 — **実装解禁: 殿裁定2026-07-29 10:41『実行しよう。本番環境での計測が必須。計算結果の完全一致が必須だ』**。全弾AC1偵察先行型・本番run ID対計測・正本突合byte/ID一致を絶対条件として家老へ配備下知済み=blt_104157)

### §3.1 攻め順(cmd_4180確定内訳に基づくv3序列)
| 優先 | 標的 | 実測 | 設計課題 |
|---|---|---:|---|
| 1 | **L3内 monthly_returns_gen** | 318.99s(07-28本番) | MR生成→commit→cache reloadの逐次連鎖の中でのMR計算自体の高速化。過去のOPT-6知見の再適用可否から |
| 2 | **L3内 deferred flush(単一標的へ統合)** | 117.61s(07-28本番exclusive) | **v3.3更新: 旧2位unmeasured 122.41sと旧除外dw_signals_flush 115.26sは実体同一(§0.-1二重計上解消)**。run終端deferred DB flushのバルク化・書込み量削減が標的 |
| 3 | L3内 daily_loop | 92.38s(07-28本番) | 過去のベクトル化設計(NEW-2b)の掘り起こし判断 |
| 4 | L2 trade_perf(FoF run) | 117.35s | 共通経路上の実測コスト(経路差別は棄却済み)。cProfileでの機構特定から |
| 5 | L5 42.3s | — | 既存資産(並列化v1.3.1+fingerprint skip)保存のまま。優先度低 |
- **PF別配分証拠(§0.-1)**: fof_total 78PFは平坦分布(top 10.5s)。PF個別最適化ではなく上記共通コスト3本(mr_gen・deferred flush・daily_loop)への集中が正 — 3本で計529s=L3の93%
- **層内並列は「実装なし+再設計大」と確定**したため、攻め順は並列化でなく区間別の計算量削減を主軸とする(品質2原則維持が容易な側)
- **並列/直列の境界検討義務(殿裁定2026-07-29 10:44)**: 『本番での再計算は並列だと結果待ちになるので、並列にする部分と直列にする部分をよく検討せよ』。各弾のAC1偵察に**並列/直列判定表**を必須成果物とする — 対象区間ごとに(a)依存関係(前段結果を読むか) (b)DB書込み衝突(同一テーブル/lock/排他=[[recalculate_pipeline]]の排他・順序制約と突合) (c)並列化した場合の結果待ち(join/lock wait)の発生箇所と見積 (d)判定=並列可/直列必須/条件付き、を現物根拠付きで列挙。**依存や排他がある区間の見せかけ並列化は結果待ちへ形を変えるだけで壁時計を縮めない** — 過去実証: 忍法GS並列配備RSS 8.5GB(LS-A15)・cron論理直列確定(§4-4)。計算量削減が主軸、並列化は判定表で「真に独立」と証明された区間のみ
- **直列優先原則(殿裁定2026-07-29 10:55で確認)**: 『基本的には直列での速度向上が優先で、直列が限界に達したときに並列を検討する。**Renderの本番環境での計算だと念頭におく**』。順序を固定する — (一)直列のまま計算量を削る(アルゴリズム・キャッシュ・重複排除・書込み量削減)を各標的で限界まで先に尽くす (二)直列の削減余地が実測で枯れたと証明された標的についてのみ、判定表で独立性が証明済みの区間の並列化を検討する。理由: 実行環境はRender本番の限られたworker/CPU/メモリであり(ローカル開発機ではない)、並列化はメモリ圧迫(過去実証RSS 8.5GB)・CPU奪い合い・DB接続数増で同居プロセス(API応答・cron)を巻き込み劣化させるリスクを常に持つ。直列の計算量削減はこのリスクがゼロで完全一致検証も容易

### §3.2 目標値の考え方
- 数値決め打ちしない。L3内訳計測後に「削減可能量の実測根拠」から設定
- 参考上限: L3が仮に半減すれば FoF run 715→約464秒(-35%)。trade_perf半減で追加-8%。ただしこれは設計目標でなく規模感の目安

### §3.3 検証の型(実装フェーズで適用)
- 各改善は同一run条件(PF集合固定・warm状態明記)のbefore/after run ID対で計測
- 品質2原則: 正本突合(byte/ID一致)+境界fixture。SKIP=FAIL

---

## §4 未解決事項(v3.3更新 — 本番初収穫で1・2・7も解消)

1. ~~unmeasured区分~~ → **全解消**(v3.3: 本番初収穫§0.-1。unmeasuredの実体=deferred flush 117.61s+残余8.14sで霧は消えた)
2. ~~PF別内訳~~ → **全解消**(v3.3: 78PF/計430.19s回収済み。平坦分布=共通コスト型の配分証拠確定)
3. 06-26分析(357.28秒)のrun lineage未回収 — 比較基準はrun ID付き実測(07-10/07-27)に限定で確定
4. ~~cron実行関係~~ → **解消**(論理直列と確定)
5. id214のTIMING原文は未回収のまま総時間のみ保持(変更なし)
6. ~~運用壁時計の定義~~ → **解消**(cmd_4184: §0.0新設。正KPI=standard起点42分25秒、FoF起点744sは補助。805/807.9秒は累積計算時間と確定)
7. ~~dw_signals_flushの内外分離~~ → **全解消**(v3.3本番値: inner append 0.01s vs outer deferred flush 117.61s。§3.1順位再判定済み — 旧unmeasuredと統合し単一標的2位へ)
8. **(v3.2新規・家老レビュー②で降格)cron時差23分54秒の削減可否 — 別設計候補**: 壁時計の56%が計算外の待機。FoF cron起動前倒し/上流完了イベント駆動化はschedule設計であり、個別スクリプト覚醒高速化路線(殿裁定19:44)のscope外。**別設計候補として記録するのみ。殿裁可まで起票しない**

---

## §5 5W1H(v2)

- **WHY**: fullrecalculate合算807.9秒(FoF 715s支配)がデータ反映と殿の運用サイクルを律速する
- **WHAT**: L3 FoF内部の計測可視化→L3/L2(FoF側trade_perf)の高速化設計。L5は既存資産保存で足りる
- **WHEN**: 設計書ブラッシュアップ完了が現目標(殿下知19:19)。実装・L3計測配線は殿裁可後
- **WHERE**: `recalculate_fast.py` L3_fof区間+trade_perf FoF経路。計測はRender log回収(非接触)を第一候補
- **WHO**: 偵察=忍者、設計レビュー=家老(忖度なし)+軍師、実装判断=殿
- **HOW**: run ID単位の同一run内訳のみで判断。異run混算禁止。品質2原則維持

---

## §6 因果リンク

- → [[cmd_4184_fullrecalc_wallclock]] 運用壁時計の一次確定(§0.0。DM-Signal repo docs/research/cmd_4184_fullrecalc_wallclock.md, commit 464e84e66)
- → [[cmd_4186]] 計測3配線の実装(unmeasured区分・dw内外分離・PF別一括INSERT。DM-Signal backend)
- → [[cmd_4179_fullrecalc_timing_recon]] 本v2の一次データ(run原文+時点間突合+混算棄却)
- → [[recalculate_pipeline]] engine構造・排他・順序制約
- → [[precompute_L5_parallel_design_v1.3]] / [[precompute_fingerprint_skip_design]] L5資産(完成・保存・優先度低)
- → [[gunshi-fullrecalc-speed-analysis]] 過去分析(06-26)。run lineage欠落のため参考扱いへ降格
- origin: `[[殿指示_設計書再構築_20260727]] -> [[cmd_4179偵察_run混算棄却]] -> [[L3_FoF_503s主犯確定_v2再構築]]`

---

**MEM引用**:
- [MEM: memory_db ts=2026-07-10 "再計算の時間がかかりすぎだな。調査しよう [TIMING SUMMARY]…"] 殿のid206 pane直貼り=TIMING基盤稼働の一次証跡
- [MEM: obsidian link=[[LS-A09]] (26)集計値はどのイベントの前か後かを確認 — 異run混算棄却の型]
- [MEM: semantic concept=recalculate_pipeline]
