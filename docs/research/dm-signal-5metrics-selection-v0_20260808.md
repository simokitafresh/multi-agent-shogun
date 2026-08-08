<!-- gist-master: 574b417f1d1377c59b64c4d88f9d4bc5 dm-signal-5metrics-selection-v0_20260808.md -->
# DM-Signal 新規5指標(RRR/DDA/ACS/RRS/ECR) 実装設計書 v0.7

- 作成: shogun 2026-08-08 / v0.2: 現物調査反映 / v0.3: 殿裁定4点反映(18:15) / v0.4: 家老所見8件+軍師所見B反映(18:25) / v0.5: 家老再レビューBLOCK4件反映(18:30) / v0.6: 家老P3限定BLOCK4件反映(18:35) / v0.7: 家老P3再現性BLOCK4件反映(18:40)
- **現況: 設計フェーズ(殿指示18:17「まだ起票しない。設計のみ」)。P1起票は殿の別途下知まで行わない**
- 仕様正本(殿原文・改変禁止): `docs/research/dm-signal-5metrics-v0-original_20260808.md`(gist dae809c3)
- 本書の位置づけ: 殿v0仕様を正とし、DM-Signalへの実装工程・AC・検証契約を定義する。**仕様の変更は殿裁定のみ**。指標定義の解釈が原文と食い違う場合は常に原文が勝つ。
- v0.2調査方法: Exploreエージェント2体でDM-Signalコード現物を精読(2026-08-08 17:15-17:30)。以下の§3/§4/§8の全ファイルパス・行番号は現物確認済み。

## §1. 5W1H

| 項 | 内容 |
|----|------|
| Why | 102PFからのPortfolio Selection問題。過去Performanceの別表現ではなく「将来もEdgeが残るPFをPoint-in-Timeで識別できるか」の検証 |
| What | 新規5指標: RRR(開始時点頑健性)/DDA(DD経路負担)/ACS(Alpha時間一貫性)/RRS(Regime頑健性)/ECR(複利変換効率) + PIT Selection実験基盤 |
| Where | `/mnt/c/Python_app/DM-signal`。v0は**研究層**(`scripts/analysis/` + `outputs/analysis/`)で完結し本番テーブルへ書かない。本番組込み(metrics_impl+portfolio_metrics+UI表示)は実験結果を見た殿裁定後の別工程(→§8) |
| Who | 将軍=設計書 / 家老=分解配備+忖度なしレビュー / 忍者=実装・実験 / 軍師=PIT契約レビュー |
| When | P1計算実装→P2 PIT時系列生成→P3評価。各Phase完了時に殿へ結果報告(v0.1のP0偵察は本書v0.2調査で完了済み) |
| How | 定義固定・最適化禁止・全PF同一適用(原文§1.2)。データは本番PostgreSQL直接読込(CSV利用禁止=cmd_214殿裁定、run_077の5原則準拠) |

## §2. AsIs / ToBe

- **AsIs**: 102PF・既存指標群は「過去の記述」。t時点順位→将来品質の関係を検証する仕組みが存在しない。選択基準が定義されていない。
- **ToBe**: 各月末t・102PF全量の5指標PIT値+Cross-sectional Rankが出力Schema(原文§15)で保存され、Forward Evaluation(原文§9.4)・Benchmark Rules比較(§10)・評価7項目(§11)・冗長性RankCorr(§12)が機械再現可能なスクリプトで出力される。

## §3. データ層の現物(調査済み事実)

| 項目 | 現物 |
|------|------|
| 月次リターンSSOT | `monthly_returns`テーブル(`backend/app/db/models.py:252-285`)。`monthly_return`(Close)/`monthly_return_open`/`cumulative_return`/`benchmark_return`/`benchmark_cumulative`等。年次は動的計算(AnnualReturnテーブルは廃止済み=models.py:337-339) |
| NAV(wealth index) | テーブルに存在しない。`cumulative_return × initial_balance`で導出(`services/monthly_returns_calculator.py:226`)。**DDAはcumulative_return系列から直接計算する** |
| 102PFの列挙 | `portfolios`テーブル `is_active == True`(models.py:77-99)。102本の整合チェック前例=`scripts/oneshot/cmd_3785_execute_pf_replacement.py:440` |
| layer | **DB列ではない**。PF名プレフィックス判定: `scripts/oneshot/cmd_3225_layer_managed_vol.py:22-33 classify_layer()`(シン/ノンレバレッジシン→L0_四神、GSシン→L1_忍法、奥義-GS-/秘奥義→L3_奥義、他→L2_スタンダード)。出力Schemaの`layer`列はこの関数を流用して埋める |
| Benchmark | PFごとに`portfolios.config["benchmark_ticker"]`、未指定はSPY(`constants.py:33`)。ベンチ月次リターンは`monthly_returns.benchmark_return`にPF行と同居 |
| Risk-Free | DTB3(`constants.py:34`)。`economic_indicators`テーブル(models.py:46-54、年率値)。**RF契約(家老BLOCK①で一本化)**: ACSのRFは`metrics_impl.py`の**現物挙動を忠実に複製**する(load_monthly_as_dfの月末index化L233-257→DTB3 join→L217-228のresample連鎖の実装をそのまま関数呼出しまたは同一コードパスで再現し、既存Alphaとの突合はbit一致水準=相対誤差1e-9を要求)。「理論的に正しい日次複利→月次複利RF」への是正は行わない。理由: ACSの目的は既存Alphaの時間的一貫性測定(殿裁定§6-2と同一原理)であり、RF算出だけ別実装にすると冗長性測定が歪む。既存RF算出自体の理論的是正は本実験のスコープ外(必要なら別件)。`risk_metrics.py:67/80`の年率/12単純除算は不採用 |
| ★PITの構造制約 | `monthly_returns`は毎ETLで**当該portfolio_idの全履歴をDELETE→再INSERT**(`jobs/generators/monthly_returns.py:692`はPF単位の置換。テーブル全体の一括削除ではない)。vintage/as_of列なし。∴「当時に観測された値」の復元は構造的に不可能 |

### §3.1 PITの定義(本実験における)

本実験のPoint-in-Timeは「**現行確定月次リターン系列のas-of切断**」と定義する: 各観測時点tの指標は系列のt以前の行のみを入力とする(将来行の参照=lookaheadを排除)。データvintage(過去時点で実際に観測された値)の再現は上表の構造制約により**不可能**であり、価格の遡及調整リスクは本実験の限界として結果に明記する。原文§13の禁止6項はas-of切断の枠内で全て機械検証する。当月未確定値(MTD)の混入防止は既存規約に従い系列最終行を捨てる(`services/benchmark_returns.py:67-69`の「最終行=MTDは必ず捨てる」規約を全系列へ適用)。

## §4. 既存指標実装の現物と5指標の接続(調査済み事実)

| 5指標の依存 | 既存実装の現物 | 5指標での扱い |
|------------|----------------|---------------|
| RRR: Rolling 3Y CAGR | `jobs/generators/rolling_returns.py:102-108`(`cumulative_return`のshift(months)比の(12/months)乗根)。保存先`rolling_returns_summary`は要約統計のみで**各windowの時系列は保存されない** | Rolling Excess CAGR系列はRRR側で同一式(L106-108と同じ演算)により月次cumulativeから再計算する。既存rolling_returns_summaryは検証時の突合先 |
| ACS: Alpha/RF | `services/metrics_impl.py:946-984`。Beta=Cov/Var(L959-961)+Jensen Alpha=平均超過差(L976)+**×12単純年率化**(L978)。単回帰ではOLS切片と数学同値 | 36M窓の各windowで既存と同一演算(Cov/Var+平均差)を行う=原文§4.2「OLS推定」と数学的に一致。年率化も既存の×12に揃える(→§6-2)。RF月次化は`metrics_impl.py:219-222`方式 |
| RRS: Regime分類 | `services/regime_analysis_service.py:106-122`(regime定義=benchmark月次リターンの**全期間μ±0.5σ**でbull/neutral/bear 3分類)、L132(active_return=portfolio−benchmark)。※行番号は家老抜き打ち検証で訂正済み(2026-08-08)。**full-period定義でありPIT版は実装に存在しない** | 裁定済み(§6-1): 分類規則(band_sigma=0.5・benchmark月次・3分類)は不変のまま、μ/σの計算範囲をt以前に制限したexpanding-window PIT版をRRS側で実装する |
| DDA: Drawdown | `jobs/generators/drawdowns.py:50`(cummax方式、月次cumulative)。metrics側MDD/UWP=`metrics_impl.py:513-`/L659- | DDAは同じcummax方式のD_t系列からmean(abs(D_t))。既存MDD/AvgUWPは冗長性測定(原文§12)の比較相手 |
| ECR: Arithmetic/Geometric | `metrics_impl.py:342`(月次算術平均)/L370(月次幾何平均)/L1219-1229(Volatility Drag=月次のまま算術−幾何) | ECR=g/mu を**月次同士**で計算(原文§6.2の同一Frequency要件は既存実装と整合)。既存VDragは冗長性測定の比較相手 |
| 冗長性測定の既存値 | ★IR/Captureは二重実装が併存: `metrics_impl.py:1362-1391/1127-1164`(True CAGR差/TE、幾何年率化比)と`jobs/generators/risk_metrics.py:143-172`(平均差/TE、単純和比)。Benchmark Win Rate該当は`risk_metrics.py:152-154 win_percent`(metrics_implに同名指標なし) | 原文§12のRankCorr比較相手は**metrics_impl.py側の値を正**とする(本番metrics表の表示元=`portfolio_metrics.metrics_json`の生成元のため)。win_rate系のみrisk_metrics側 |
| timing(Close/Open) | monthly_returnsにClose/Open二重系列。既存Alpha/BetaはCloseのみ(metrics_impl.py L961/L980がopen引数未指定) | v0の5指標は**Close系列のみ**で計算(既存Alpha/Betaと同基準)。Open拡張は別実験 |

## §5. 実装契約(原文からの絶対制約+現物接続)

1. **PIT絶対**(原文§13): §3.1の定義でas-of切断。禁止6項は自動Quality Check(原文§16)+lookahead検査(§7 P2)でFAILさせる。
2. **最適化禁止**(§1.2/§18): Weight合成・パラメータ探索・Layer別定義・Threshold探索・Best Lookback/Horizon選択を実装しない。コードに最適化フックを作らない。
3. **NULL契約**: MAD=0→NULL(RRR/ACS)、mu<=0→NULL(ECR)、history<36M→NULL(RRR/ACS)。特殊値・Infinity・符号反転Raw値を作らない。**NULL reason code必須(殿裁定2026-08-08 18:15)**: 出力Schemaに`rrr_null_reason`/`acs_null_reason`列(値=`INSUFFICIENT_HISTORY`/`INSUFFICIENT_WINDOWS`/`ZERO_MAD`/`INVALID_INPUT`、非NULL時は空)と、`ecr_null_reason`列(値=`NON_POSITIVE_MEAN`(mu<=0)/`INVALID_INPUT`(欠損・非有限入力)、家老所見⑥で追加)を設ける。RRSは`rrs_null_reason`列(値=`NO_REGIME_SAMPLE`(いずれかのregimeが未出現)/`INVALID_INPUT`)。データ不足・計算不能・極端に安定(ZERO_MAD)を区別可能にする。指標定義・式・Thresholdの変更ではなく解析不能理由の保存のみ。
3b. **RRS Reliability Flag(原文§5.7、家老所見③で復元・BLOCK②で基準確定)**: Schemaに`rrs_min_regime_n`(=min(n_up, n_side, n_down)の生値)と`rrs_reliability_flag`を追加。フラグの機械基準(事前固定・実験開始後の変更禁止): `min_regime_n == 0`→`NO_SAMPLE`(RRS=NULL・reason=NO_REGIME_SAMPLE) / `0 < min_regime_n < 12`→`LOW_SAMPLE`(RRSは計算し表示のみ。12ヶ月=年率統計の最小慣行を事前固定基準として採用) / それ以外→空。**除外には一切使わない**(原文§5.7「Thresholdによる除外はしない」)。
4. **方向統一はRank層のみ**(§1.3): Raw値は元の意味を保持。DDAはRank時ascending。
5. **既存定義の再利用**: §4の表の通り既存実装と同一演算・同一パラメータを使う。**新定義を作らない**。唯一の例外はRegimeのPIT化(§6-1の裁定事項)。
6. **パラメータ空間縮小禁止**(殿厳命2026-04-04): 102PF全量(is_active=True)・利用可能全月・Forward horizonはt+1/t+3/t+6/t+12全量(t+1先行可、ただし残りを切り捨てず同一ランナーで継続。Multiple Horizonは別Experimentとして明示=原文§9.4)。
7. **Sample Count併記**(§14/§5.7): rrr_window_count/acs_window_count/regime n_*を必ず出力し、恣意的Minimum Count Filterを置かない。
8. **研究5原則**(run_077準拠): 再現可能・データ+インデックス完結・第三者可読・**過去データを上書きしない**・過剰設計回避。データソースは本番PostgreSQL直接読込(CSV利用禁止=cmd_214殿裁定)。

## §6. 解釈事項 — **全て殿裁定済み(2026-08-08 18:15)**

1. **RegimeのPIT化方式 → 裁定: expanding-window PIT版を採用**。分類規則(band_sigma=0.5・benchmark月次・3分類)は固定のまま、各時点tでμ/σをt以前のexpanding windowから計算(information set=F_tへの制限であり定義変更ではない)。full-period μ/σはRRSのみ明確なlook-aheadとなるため、PIT絶対の上位原則を優先。
2. **ACSの年率化方式 → 裁定: 既存metrics_impl.pyと同じ×12を採用**。ACSの目的は新しいAlphaの定義ではなく既存Alphaの時間的一貫性の測定であり、Rolling Alphaだけ別の年率化を入れる理由がない(alpha_annual = 12×alpha_monthly)。
3. **NULL reason code → 裁定: 追加**(§5-3へ反映済み)。
4. **Forward Outcomeの事前固定 → 裁定: Primary=Forward Excess Return一本**(§9へ反映済み)。結果を見てからQuality定義を選ぶことは最も危険なチェリーピッキングであり禁止。

## §7. 工程表(Phase分解)

| Phase | 内容 | 完了条件(二値) | 起票cmd(起票時に実番号記入=予約禁止LS-A04(46)) |
|-------|------|----------------|------|
| ~~P0偵察~~ | **完了(2026-08-08 v0.2調査)**: 既存実装・データ経路・PF列挙・出力慣行を§3-§4に確定 | 済 | (本書調査で代替) |
| P1 | **計算実装**: `scripts/analysis/`に5指標計算モジュール+出力Schema(原文§15全列+§5-3/3bの追加列+layer=classify_layer流用)+Quality Check(原文§16)の自動テスト。単一時点t(直近確定月末)での102PF計算 | 原文§15全列+追加列出力+§16全チェックPASS+**既存値突合の二値定義(家老所見⑤)**: 同一入力から再計算した全期間版Alpha/VDrag/MDD/AvgUWPと`portfolio_metrics.metrics_json`現物値の相対誤差が全PF・全4指標で1e-9以下(分母0時は絶対誤差1e-12以下)、**不一致0件**+**DB read-only検証(軍師所見B)**: 実行ログ上でINSERT/UPDATE/DELETE文の発行が0件であることを機械確認。突合の同値規則(家老追加確認): 両側NULLは一致、片側NULLまたはmetrics_json側のkey欠落は不一致として計数し理由を記録 | (未起票) |
| P2 | **PIT時系列生成**: 各月末t×102PF(is_active=True)の5指標を全履歴分生成。出力=`outputs/analysis/`にCSV+meta.yaml+SQLite(`gs_sqlite_output.py`慣行)+DATA_CATALOG追記。**lookahead検査は全月×全102PF(家老所見④: サンプル月方式は探索縮小禁止に反するため全量へ)**: 入力系列をt月で物理切断した再計算値と、全履歴上でas-of計算したt時点値の完全一致を全(t, PF)組で機械検証 | 全月×102PF出力存在+lookahead検査**全組PASS(不一致0件)**+NULL契約通りのNULL分布記録(reason code別集計)+MTD最終行除外の証跡 | (未起票) |
| P3 | **評価**: 原文§9.4 Forward Evaluation(t+1/3/6/12)+§10 Benchmark Rules(Control A-F vs Experimental G-K)+§11評価7項目+§12冗長性RankCorr 12ペア(比較相手は§4の通りmetrics_impl側の値)。**Forward cohort契約(家老BLOCK③)**: 各horizon hの評価cohortは「tで指標が非NULL かつ t+1〜t+hの全月にPF・benchmark両方の月次Close確定値が存在する(t, PF)組」のみ。末尾censor(t+hが未来)・inception欠損・指標NULLは評価から除くが、**月×horizon別の欠落理由集計(censored/inception_gap/metric_null別の件数)と期待行数(有効PF数×有効月数)vs実行数の照合**を必須出力とする。**Cross-sectional Rank契約(家老BLOCK④)**: rank対象=当月の指標非NULL PFのみ(NULL除外)、tie method=average、方向=原文§9.3(DDAのみascending)、月ごとの有効PF数`n_ranked`を全出力行に併記。RankCorrはSpearman(scipy.stats.spearmanr、tie=average前提)。**群境界契約(家老BLOCK②+v0.7①全順序化)**: Top/Middle/Bottomは当月rank対象n_rankedのtercile分割 — 並び順は**(average rank値, portfolio_id昇順)の辞書式全順序**で確定(tie同値間はportfolio_id昇順のsecondary keyで一意化)し、先頭からk=floor(n/3)をTop、末尾kをBottom、余りr=n mod 3は全てMiddleへ配分。各群のnを月ごとに出力。`n_ranked < 3`の月は当該指標の群分析をstatus=`SKIPPED_SMALL_N`として除外し、reason付きで件数報告(v0.7④)。**Random/EqualWeight契約(家老BLOCK③+v0.7②決定論化)**: Control E=候補PFリストをportfolio_id昇順に正規化した上で、`numpy.random.default_rng([seed, month_index])`(seed∈{0..99}、month_index=実験開始月からの連番で**月ごと再初期化**)により当月rank対象からTop群と同数を非復元抽出×100 draw。集約はmean/median/90%CI(`numpy.percentile(…, [5,95], method="linear")`)の3点を全て報告、比較の主読みはmedian。**Control F(v0.7③裁定)**: 原文§10「Equal Weight 102PF」に準拠し**当月の全eligible PF(指標非依存=当月に確定月次リターンが存在する全active PF)の等ウェイト月次リバランス**を正とする。指標別rank対象に合わせたmetric-matched cohort equal weightは**参考control F'**として分離出力し、比較表でF/F'を並記(混同禁止)。**cohort partition式(家老BLOCK④+v0.7④排他優先順位)**: 各hについて候補全集合U_h={(t,p): tでrank対象}を起点に、候補総数 = 実行数 + censored + inception_gap の重複なし分割で照合。**分類の排他優先順位=censored(t+hがデータ末尾超)を先に判定し、残りをinception_gap(t+1..t+h内に欠損月)判定**(両条件成立時はcensoredに分類)。metric_nullはrank対象定義で候補外として別掲。「有効PF数×有効月数」の積算式は使わない | §11の7出力+§12の12ペアRankCorr表が再現可能スクリプトで生成+cohort partition照合(残差0件)+§9(原文§17)観察項目の報告 | (未起票) |

- P1→P2→P3直列。P3はP2出力に対する読み取り専用。各Phase=1cmd原則。
- v0は本番DB**読み取りのみ**・書込みは`outputs/`研究層のみ。本番DBへのINSERT/UPDATEは一切行わない(∴バックアップ対象外だが、DB接続はread-onlyクエリに限定することをACに含める)。

## §8. 本番組込み時の入口(v0スコープ外・将来参照)

実験で有効性が確認され殿が採用を裁定した場合の組込み点(調査済み): `metrics_impl.py add_metric()`(L281)→`portfolio_metrics.metrics_json`(JSON一括のためカラム追加不要)→`api/metrics.py:302 _cache_has_required_metrics`の必須キー更新(**更新漏れは旧キャッシュ配信バグになる**)→`frontend/lib/api-client.ts`→metrics表示+`tier_visibility_settings`(tier別マスキング)。UI表示名は原文§2.9/§3.8/§4.10/§5.8/§6.7。

## §9. 実験成功条件(原文§17転記)+Forward Outcome階層(殿裁定2026-08-08 18:15)

**主仮説**: Metric rank at t → future benchmark-relative performance。

**Outcome階層(P3実行前に固定・変更禁止)**:
- **Primary Outcome: Forward Excess Return at h=1(t+1のみ)**(家老BLOCK①で一本化)。定義: **複利リターン差** = Π(1+r_p)−Π(1+r_b)(h=1では単月の r_p−r_b に一致。月次Close系列)。単純和・relative wealth比は不採用。理由: 既存IRのActive Return(True CAGR差=複利系、`metrics_impl.py:1370`)と同じ複利差系譜であり冗長性比較が整合する。**生死判定はh=1のForward Excess Return一本**(原文§9.4「v0では最初にt+1のみでもよい」に整合)。
- **Secondary Outcomes**: h∈{3,6,12}のForward Excess Return(Multiple Horizon比較=原文§9.4の通り別Experimentとして明示)/ Forward CAGR / Forward MaxDD / Forward Calmar / Forward Avg UWP / next_return等(ρ(1)実験系の指標群)。参考観察のみ。結果を見てからPrimaryを差し替えることは最も危険なチェリーピッキングとして禁止。

固定Thresholdなし。観察: Forward RankCorr方向/正月率/Top-Bottom Spread/前半後半一貫性/Layer横断一貫性/既存Metricsとの差別化。核心=「過去Performanceとの相関が低いのにForward Qualityとの関係があるか」。CAGR/Sharpeと同じPFしか選ばない指標は不要と判定する。

## §10. リスク・限界(調査で確定した事実ベース)

- **vintage不可**(§3.1): 遡及価格調整の影響は除去できない。結果報告に限界として明記。
- **Regime PIT初期期間**: expanding-window方式は初期のμ/σが少サンプルで不安定。n_up/n_side/n_downのSample Count併記で可視化(Threshold除外はしない=原文§5.7)。
- **IR/Capture/RF二重実装の混線**: 冗長性測定・突合の相手を§4で固定済み。実装時に`risk_metrics.py`系の値と取り違えるとRankCorrが歪む。
- **102PFのinception分散**: RRR/ACSのNULL期間が長いPFが出る→NULL契約通り出力(除外Filterなし)。
- **layer判定の脆弱性**: PF名プレフィックス判定のため改名で壊れる(既知の構造)。実験時点のclassify_layer結果を出力Schemaに焼き込むことで実験内の一貫性は保つ。
- **★Rolling windowの重複(殿注意2026-08-08)**: RRR/ACSの隣接windowは35/36ヶ月が共通で強く依存する。仕様注記: "Rolling windows are intentionally overlapping; window_count is an observation count, not an effective independent sample size." MADやwindow_countを独立サンプル数のように解釈しない。screening metricとしての記述的使用は問題ない。
- **★ECRの解釈(殿注意2026-08-08)**: ECRはPerformance indicatorではなく**conversion efficiency indicator**。μ=1%,g=0.99%はμ=10%,g=9%よりECRが高くなるが仕様通り。ECR単独で「良いPF」を意味すると解釈しない。

## §11. 進捗台帳

| 日時 | 事象 |
|------|------|
| 2026-08-08 17:00 | 殿原文受領・全文保存(`dm-signal-5metrics-v0-original_20260808.md`) |
| 2026-08-08 17:05 | 実装設計書v0.1作成(commit 64a1072dd)、gist 574b417f発行 |
| 2026-08-08 17:10 | 殿下知「未調査がないように覚醒してアップデート→家老忖度なしレビュー」 |
| 2026-08-08 17:30 | Explore 2体調査完了→v0.2全面更新(§3データ層/§4既存実装接続/§6裁定事項2件/P0偵察完了扱い)。家老レビューへ |
| 2026-08-08 18:15 | 殿裁定4点: §6-1 Regime expanding-PIT採用 / §6-2 ACS ×12採用 / NULL reason code追加(§5-3) / Primary Outcome=Forward Excess Return固定(§9)。+注意2点(§10: overlapping window注記・ECR解釈)→v0.3反映 |
| 2026-08-08 18:17 | 殿指示「まだ起票しない。設計のみ」→P1起票保留。家老+軍師へレビュー依頼 |
| 2026-08-08 18:25 | 家老レビューREVISE所見8件→v0.4反映: ①ヘッダの起票状態矛盾解消 ②Primary=複利リターン差と定義 ③RRS Reliability Flag復元(§5-3b) ④P2 lookahead検査を全月×全PFへ ⑤P1突合ACを相対誤差1e-9・不一致0件で二値化 ⑥ecr_null_reason追加 ⑦Regime行番号をL106-122/L132へ訂正 ⑧monthly_returns置換をPF単位と明記。再レビューへ |
| 2026-08-08 18:22 | 軍師レビューAPPROVE+所見6件(A=lookahead全量化は家老④と同一でv0.4反映済/B=P1にDB read-only検証AC追加→反映/C-F=問題なし確認)。v0.4に(B)を追加反映 |
| 2026-08-08 18:30 | 家老再レビューREVISE(新規BLOCK4件)→v0.5反映: ①RF契約を現物挙動複製に一本化(§6-2裁定と同一原理で将軍裁定) ②LOW_SAMPLE事前固定基準(0<min_n<12、表示のみ)追加 ③P3 forward cohort契約(欠落理由集計+期待vs実行照合) ④Cross-sectional Rank契約(tie=average/NULL除外/n_ranked併記)。+P1突合のNULL同値規則。再々レビューへ |
| 2026-08-08 18:35 | 家老v0.5レビューREVISE(P3限定BLOCK4件)→v0.6反映: ①Primary=h=1一本固定(h=3/6/12はSecondary=別Experiment) ②tercile群境界契約(floor(n/3)+余りMiddle配分+tie機械分割) ③Random E=seed0-99×100draw・median主読み/EqualWeight F=当月rank対象等ウェイト月次リバランス ④cohort partition式(候補総数=実行+censored+inception_gapの重複なし分割・残差0件)。再レビューへ |
| 2026-08-08 18:40 | 家老v0.6レビューREVISE(P3再現性4件)→v0.7反映: ①tie全順序化(secondary key=portfolio_id昇順) ②Random決定論化(候補ID昇順正規化+default_rng([seed, month_index])月ごと再初期化+percentile linear法固定) ③Control F裁定=原文準拠の全eligible共通control、metric-matched版はF'として分離並記 ④partition排他優先順位(censored先)+n_ranked<3月のSKIPPED_SMALL_N定義。再レビューへ |
