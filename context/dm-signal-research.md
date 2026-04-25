# DM-signal 研究コンテキスト
<!-- last_updated: 2026-04-17 cmd_karo_context_freshness_1993 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

コア定義(§0-5,8,10-11,13,15,18) → `context/dm-signal-core.md`
運用手順(§6-7,9,12,14,16-17) → `context/dm-signal-ops.md`
補足: 旧詳細資料(`parity-verification-details.md`, `edge-detection-cycles.md`, `spa-overfitting-analysis.md`, `gs-results-by-ninjutsu.md`)は未復旧。現存するdocs/researchは `cmd_484/485/486/488` の4件のみ。

---

## §19. 月次リターン傾き分析 (cmd_270/271/272)

→ 詳細資料: 未復旧（本節を一次情報として扱う）

| 指標 | cmd | 結論(1行) |
|------|-----|----------|
| raw傾き(36M窓) | 270 | Improving=0体, Declining=12体, Inconclusive=74体。推奨窓幅36M |
| α傾き(SPY除去) | 271 | Alpha-Positive=0(全窓幅)。36Mで10体がα負(真のエッジ消失) |
| エッジ残存率 | 272 | Median 32%。四神全劣化: DM6=9.3%, DM7+=5.1%, DM2=-21.4%, DM3=-741.7% |
| 3指標統合 | 270-272 | 急速劣化ではなく緩やかなα低下。四神は3指標全てで低評価→優先監視 |

殿の指摘: α中立≠α水準ゼロ。「raw+α」二段判定を標準化。

### エッジ検知 C1-C4 (cmd_273/274) + 外部データ(cmd_282) + 日次(cmd_281)

→ 詳細資料: 未復旧（本節を一次情報として扱う）

**正式結論: 月次粒度二値分類でのprecision 80%は構造的に不可能**

| Cycle | 最良手法 | Precision | n | 突破手段 |
|-------|---------|-----------|---|---------|
| C1(cmd_273/274) | VolWeighted | 42.0% | 1,325 | 3指標複合(月次派生のみ) |
| C2(cmd_274) | 22特徴量LogReg HC | 65.5% | 132 | 週次粒度変更(DM3限定) |
| C3(cmd_274) | Regime+HC0.7 | 72.7% | 11 | bear限定+HC filter(n犠牲) |
| C4(cmd_274) | c2_logreg22 | 59.7% | 127 | Meta-Ensemble(改善なし) |
| 情報理論(C4-B) | Bayes上界 | **69%** | — | **数学的上界。80%は到達不可能** |
| 外部データ(cmd_282) | DTB3追加 | 上界63.7% | — | 悪化(-5.2pp)。次元の呪い |
| 日次(cmd_281) | 日次Bayes上界 | 63.2% | — | 月次(69%)より悪化。粒度変更無効 |

構造的SNR限界: σ(4-8%/月)>>α(0.5-2%/月), SNR≈0.1-0.5。n≥30での天井≈62%。

---

## §20. ルックアヘッドバイアス検証 (cmd_276)

→ 詳細資料: 未復旧（本節を一次情報として扱う）

**本番+GS双方でLA未検出。信頼度:高。** 全14BB+全5忍法GSでtarget_date以前参照を確認。
残存リスク: R1(当日終値未確定ガード不在, medium)。StockData API仕様は未検証。

---

## §21. 過剰最適化検証 (cmd_277)

→ 詳細資料: 未復旧（本節を一次情報として扱う）

**全5忍法PASS。** SPA検定でH0棄却不能、IS/OOS劣化なし。

| 忍法 | SPA p値 | GS空間 | 判定 |
|------|---------|--------|------|
| 分身 | N/A | 1 | PASS(数学的証明, パラメータ自由度0) |
| 追い風 | 0.36 | 42,174 | MODERATE_PASS(OOS>IS) |
| 抜き身 | 0.99 | 152,295 | PASS(FS champ OOS+29.9%) |
| 変わり身 | 0.73 | 28,116 | PASS |
| 加速 | 0.99 | 238,986 | PASS |

自由度: 名目0.23/実効0.15(中程度)。学術的裏付け+資産分散+GFS正則化で緩和。
- L414: DM7+ 24M RXLU CPCV Max_Run-up PBO=1.0。24M窓は変化極めて緩慢でCPCV短期テスト窓に不適合（cmd_1078）
注意: ISのみ最適パラメータ(短lookback)は過剰適合リスク → full-sample選出必須。

---

## §22. 外部データ統合エッジ検知 (cmd_282)

→ 詳細資料: 未復旧（本節を一次情報として扱う）

DTB3(3ヶ月T-Bill利回り)の12特徴量MI分析。最大MI=0.058bits(C2-Bの63%)。
Bayes上界: C2-B only=69% → C2-B+DTB3=63.7%(**悪化**)。Phase2(FRED API等)不要。

---

## §23. 日次粒度エッジ検知 (cmd_281)

→ 詳細資料: 未復旧（本節を一次情報として扱う）

日次Bayes上界63.2% < 月次69%(**悪化**)。全22特徴量AUC 0.506-0.543(ランダム)。
DM3高精度はTMV含有+クラスバランスの固有構造。汎化不可。Phase2不要。

---

## §24. 四つ目(yotsume) フルGSチャンピオン選出 (cmd_284)

→ 詳細資料: 未復旧（本節を一次情報として扱う）

18,744パターンから3モードチャンピオン選出。SPA検定3モード全てPASS。

| モード | CAGR | MaxDD | NHR | base | top_n | 構成四神 |
|--------|------|-------|-----|------|-------|---------|
| 激攻 | 62.41% | -18.45% | 59.06% | 18M | top1 | 常勝青龍,常勝朱雀,鉄壁玄武,激攻白虎 |
| 鉄壁 | 54.84% | -15.87% | 53.02% | 18M | top2 | 常勝青龍,常勝朱雀,鉄壁白虎,激攻玄武 |
| 常勝 | 46.80% | -32.87% | 63.98% | 6M | top2 | 常勝朱雀,鉄壁白虎,鉄壁玄武,激攻白虎 |

既存忍法比較: 四つ目は性能レンジ内(激攻CAGR 62.41%は変わり身62.25%同水準)。突出優位なし。
- L413: DM7+ XLU1銘柄ではtop_n軸が冗長(top_n=1とtop_n=2が完全同一リターン)。48→24体に圧縮可能（cmd_1078）
- L493: 四つ目(MultiView)忍法のnumpy再実装で4窓union+タイミングオフセットに不一致リスク（cmd_1410）

---

## 研究関連教訓索引 (projects/dm-signal/lessons.yaml)

### 影響算定/再現性

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L146 | 最新引け軸を使う比較ではlatest_close_dateを先に確定し、軸重複を判定する | cmd_495 |
| L145 | FoF差分はholding_signal文字列ではなく、展開後ticker×weightで比較する | cmd_495 |
| L186 | 日次比較偵察は対象日N点固定に加えMAX(date)確認を同時実施すると欠落原因を誤診しにくい | recon |

### GS結果/パラメータ

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L117 | SPA p=0.99: 15万パターンGSチャンピオンはtop群内で統計的有意差なし | cmd_277 |
| L105 | BB config未拘束がGS無効パターン量産の根因。Pydantic制約はPortfolio層偏在 | cmd_264 |
| L134 | GS結果利用時はDATA_CATALOG.md + meta.yaml参照必須 | — |
| L132 | GS構成四神と本番FoF構成PFの不一致 | — |
| L286 | ルールベース戦略のOOS検証はpipeline blockではなくGS runner上位の評価層に配置 | cmd_860 |
| L299 | GS shared metricsとrunner CSV metricsが別系統だとdrift | cmd_861 |
| L572 | GS runnerの正規パスはbackend/app/jobsではなくscripts/analysis/grid_search [deprecated] | cmd_alm_ninpo_recon |
| L581 | gs_data_loader unit_naming format変数はdisplay/pattern/kのみ。{family}は不可 | cmd_1795 |
| L102 | MultiView skip_months=[0,1,2,3]はクラス変数固定、config変更不可 | cmd_253 |
| L100 | MultiView base_period_months≥4必須(skip=3で0ヶ月問題) | cmd_253 |
| L101 | MultiView Phase3 momentum_cache事前計算はFoF専用でskip | cmd_253 |
| L099 | pipeline_config LIKE '%ReversalFilter%'はTrendReversalFilter誤検知→jsonb_path_exists | cmd_253 |
| L069 | GS candidate→pipeline_config構築はregister_shijin_portfolios.py準拠で統一 | cmd_196 |
| L068 | PipelineEngineはpipeline_config内lookback_periodsを使用(外部periods/weights/units無視) | cmd_196 |
| L060 | 非月次リバランスGSチャンピオンは月次制約下で大幅劣化(特にkasoku) | cmd_190 |
| L059 | 検証スクリプト参照CSVはcmd番号更新と同時追従が必要 | cmd_185 |
| L058 | subset型GSのmonthly CSV出力にはcommon_months注入が必須 | saizo |
| L057 | 168バッチGS結果は忍法ごとにCSV有無が異なる | cmd_180 |
| L055 | kasokuはdiff方式=激攻、ratio方式=常勝に特化 | cmd_168 |
| L053 | oikaze R3: common_months注入でfast/seq月次CSVを完全一致化 | cmd_165 |
| L052 | kasoku R4: PeriodIndex参照最適化で19%短縮 | cmd_165 |
| L051 | nukimi R4: 0.05秒級GSでmultiprocessingは逆効果 | cmd_165 |
| L050 | kasoku R3: precomputed picks+純Pythonループで4.54倍速 | cmd_165 |
| L049 | bunshin R3: 純Pythonインナーループは逆効果、fixed-arity vectorization有効 | subtask_165_bunshin_r3 |
| L048 | nukimi R3: precompute keyはtop_n_effを使う | subtask_165_nukimi_r3 |
| L047 | kawarimi R3: NumPy呼出し排除で5.5倍速 | subtask_165_kawarimi_r3 |
| L041 | GS高速化: NumPyベクトル化+前処理キャッシュで55倍速 | cmd_161 |
| L040 | nukimi C2候補はgekkou列のみ使用(close/openは同一CSVで暫定統一) | cmd_160 |
| L039 | 064_champion CSVとC12 UUIDは別データ。GS比較は同一ソース必須 | cmd_160 |
| L033 | GSパラメータとAPI登録ペイロードの乖離は本番結果乖離に直結 | cmd_123 |
| L027 | C抜き身のCANDIDATE_SET不一致(CS4→C11_CCNh)は結果乖離要因 | — |
| L013 | GS align_months交差集合はlookback warm-upを失わせる | — |
| L338 | 忍法15体分析時に分身不在を事前確認 | cmd_1010 |
| L341 | 既存GSチャンピオン流用時はdeployed portfolio configを正本にする | cmd_1012 |
| L409 | nukimi/oikaze momentum計算はcmd_227で既にnumpy ratio方式に移行済み。偵察で再提案注意 | cmd_1064 |
| L342 | 2段重ねBTのStage1変更はnominal_output変動を伴い大幅Sharpe変動の主因 | cmd_1012 |
| L343 | experiments.db monthly_returnsのシグナルJSON内ティッカー構成でL1ファミリー分類が可能 | cmd_1014 |
| L348 | 長lookbackを含むL1 GSはnominal periodではなくlive common periodを先に固定せよ | cmd_1018 |
| L358 | 非典型lookback(4M/5M/10M)がGSチャンピオン上位。間引きはチャンピオン喪失リスク | cmd_1025 |
| L359 | kasoku旧GS Top100でdiff=73件/ratio=27件。倍率制約は1位を消す | cmd_1025 |
| L012 | GSのdrop_latest=Trueはexperiments.dbでは不要 | — |
| L008 | GS構成四神[歴史的記述]と本番FoF構成PFの不一致 | — |

### パリティ検証

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L086 | GS tiebreak本番準拠: cutoff_score全包含方式 | cmd_217 |
| L091 | GS momentum計算はcumulative_return ratio方式(prod方式はtiebreak不一致) | cmd_222 |
| L093 | SVMF月次/日次判定バグ: 行数ヒューリスティック→is_monthly_data()で修正 | cmd_227 |
| L094 | oikaze cutoff_score epsilon tolerance(1e-12)が必要 | cmd_227 |
| L092 | kawarimi tiebreak float64精度同値タイ: ハイブリッド方式で解決 | cmd_223 |
| L089 | GS-本番パリティはデータソース一致が前提条件 | cmd_222 |
| L090 | GS NaN vs 本番cumulative_returnデータパス差異でコンポーネント選出変化 | cmd_225 |
| L087 | kasoku長lookback(12M/24M)で初期化期間差異 | cmd_217 |
| L088 | L1パリティPASSはtie処理網羅の証明にはならない | cmd_218 |
| L095 | kasoku main()がcumulative_returns未ロード→常にfallback使用 | cmd_227 |
| L096 | skip処理のデータ頻度判定はis_monthly_data()使用(行数ヒューリスティック禁止) | cmd_234 |
| L097 | SVMF/MVMFのskip計算=is_monthly_data()適用(L093の拡張) | cmd_233 |
| L098 | SVMF fallback target_date未フィルタリング(将来データ参照) | cmd_227 |
| L077 | GS CSV monthly_return=open-based / 本番cumulative_return=close-based | cmd_207 |
| L074 | verify_all_portfolios.pyのskipロジックはquarterly_mar対応が必要 | cmd_205 |
| L073 | FoFパリティ検証ではコンポーネント初期化月をスキップしない | cmd_205 |
| L072 | GS計算開始日フィルタはPhase 1後にsignal_history一括適用 | cmd_197 |
| L071 | 低頻度リバランスPFの初期化期間は複数月。skipロジックで全Cash月をカバー | cmd_197 |
| L070 | PipelineEngine pathとmatrix pathのNaN処理厳格さに差異あり | cmd_197 |
| L062 | L2モメンタム式(pct_change≡product(1+r)-1)は数学的等価 | cmd_193 |
| L061 | verify_all_portfolios.pyはFoF(type=fof)をスキップしL1四神未検証だった | cmd_193 |
| L031 | FoFパリティ(加速-C)は164/167一致。残3件はモメンタム計算差異 | — |
| L026 | 本番FoFコンポーネント取得は`/api/portfolios/get`のみ | — |
| L024 | signal_historyキーはPhase2 month_last_trading_daysと同型必須 | — |
| L019 | 同スコア時はタイブレーク均等保有ルールを明示適用する | — |
| L017 | FoFリターン計算乖離は根本原因特定・修正まで実施する | — |
| L016 | monthly-trade APIのフィールド意味を誤解しない(シグナル一致率の見かけに注意) | — |
| L005 | FoFパリティ比較は本番の現行パラメータ確認を先行する | — |
| L361 | 歴史GS出力と現DB rerunの比較はnear-match帯を設けよ | cmd_1027 |
| L378 | パリティベースラインはコード変更と同一環境で生成すべき | cmd_1032 |
| L389 | PeriodIndex.to_timestamp(how='end')は23:59:59.999生成→normalize()で00:00:00化必須 | cmd_1035 |
| L391 | kawarimi worst選出tiebreak: ranked_asc[:N]と本番ranked_desc[-N:]で選出が異なる | cmd_1035 |
| L392 | yotsume 4視点union batch simでIEEE 754 FPノイズ(5.55e-17)。パリティ閾値1e-12 | cmd_1035 |
| L422 | シグナル突合はリターン逆推定では不十分。GS関数に直接シグナル出力が必要 | cmd_1097 |
| L423 | FoF BBシミュレーションM-1オフセット必須 | cmd_1102 |
| L424 | パリティpartial/MTD仮説は1.5%。98.5%はGS月次vsP日次の構造的乖離 | cmd_1106 |
| L425 | シン四神v2パリティ不一致の95%はRC4解像度差異 | cmd_1106 |
| L426 | パリティ検証のpartial/MTD仮説は全体の1.5%のみ。構造的差異(日次vs月次解像度)が98.5% | cmd_1106 |
| L427 | resample(ME).last()はカレンダー月末を返す。実取引日との差異がシグナル帰属ズレを引き起こす | cmd_1115 |
| L428 | valid_start_date計算は全構成シンボル(relative+absolute+safe_haven+DTB3)を含めよ | cmd_1115 |
| L429 | パリティ検証における非決定的順序とpartial-month初月の扱い | cmd_1116 |
| L476 | FoF top_n=1でもselection_blocks空ならmomentum選択なし(EqualWeight) [PI候補] | cmd_1251 |
| L485 | FoF初月hs_cross不一致は全FoF共通パターン（monthly_returns初月NaN） | cmd_1342 |
| L486 | MAF(ratio)パリティはPhase B-Dと完全同一挙動。selection block種別に非依存 | cmd_1345 |
| L487 | PI強制化時は波及先関数の未更新チェック必須（GS側simulate等） | cmd_1349 |
| L488 | 非市場ティッカー(^VIX/DTB3)は全コードパスで統一除外必須（PI-010同根） | cmd_1353 |
| L586 | ゴールデンデータ比較ACは当月DB更新を考慮して設計せよ（進行中月差異は正常） | cmd_1817 |

### SPA/過剰最適化

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L117 | SPA p=0.99: チャンピオンはtop群内ノイズ範囲。full-sample選出が妥当 | cmd_277 |
| L114 | 高相関な弱予測器のスタッキングはDM3で精度改善しない | cmd_274 |
| L306 | DM-SignalはGS由来の過適合3兄弟(F08/F09/F10)に最も脆弱 | cmd_862 |

### エッジ検知

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L108 | エッジ残存率バックテスト: precision 18-34%, 単独では不十分 | cmd_273 |
| L111 | Cycle1統合: 月次precision 80%は構造的に困難(SNR壁0.1-0.5) | cmd_274 |
| L110 | 日次/週次粒度でも最大65.5%(DM3限定), 80%未達 | cmd_274 |
| L113 | ターゲット再定義はSNR限界を克服しない(DD>10%はbase_rate変更) | cmd_274 |
| L115 | 回帰→分類パイプラインは月次SNR限界を克服しない | cmd_274 |
| L116 | PF間の相関構造特徴量はエッジ崩壊予測に寄与しない | cmd_274 |
| L112 | monthly_returns.signalがJSON辞書形式→キー抽出必須(未対応で全欠損) | cmd_274 |

### 外部データ

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L120 | DTB3追加はBayes上界を悪化(-5.2pp)。MI=0.058bits,次元の呪い | cmd_282 |
| L119 | DATA_CATALOG 86銘柄 vs experiments.db実際14銘柄の乖離 | cmd_282 |
| L118 | DTB3はdaily_pricesテーブルにticker='DTB3'格納(economic_indicatorsは空) | cmd_282 |

### 弱体化確率(P_det)

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L165 | P_det ローリング基準は検知力天井 β·(n+K)/2 を持つ。固定基準は時間成長するが古いアンカーの代表性リスクあり | cmd_540 |
| L166 | ローリング基準は線形ドリフト検知力が上限飽和するため、副指標なしだと遅い劣化を取り逃しやすい | cmd_540 |
| L278 | P(det)指標を戦略転用する前にlabel taxonomyとstrategy taxonomyを分離せよ | cmd_859 |
| L279 | P(det) recent窓(n=6)のHAC SE推定は統計的に不安定。P6単独をトリガーにするな | cmd_859 |
| L285 | P(det)と構造変化検定を同義扱いするな。break検出と悪化方向判定は分離 | cmd_860 |

### パフォーマンス持続性（cmd_860/861）

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L281 | レバレッジETF fat tails(尖度5-8)は正規性仮定の全統計手法でリスク。t分布 or ノンパラメトリック手法を優先 | cmd_860 |
| L282 | 91PFの実効独立数は20-30。cross-sectional分析では独立PFサブセット選定が必須 | cmd_860 |
| L288 | n=84でのOOS R²は検出力不足。予測力なし≠予測力がない(データ不足の可能性) | cmd_860 |
| L289 | panel化時に91PFをIID時系列として扱うな。month/pf cluster前提でSE補正 | cmd_860 |
| L291 | 91PF panel は横断本数をそのまま有効サンプル数と見なすな | cmd_860 |
| L293 | 多層防御の生命線はLayer4の上流完全独立性 | cmd_861 |
| L294 | PSRとベイズ持続確率は部分冗長。手法統合では冗長ペアを事前特定し吸収せよ | cmd_861 |
| L295 | DSRは試行数直接補正の唯一手法。大規模GS(>10万パターン)で必須 | cmd_861 |
| L297 | 84ヶ月×91PFの高相関panelへraw multivariate HMMを直適用するな | cmd_861 |
| L298 | FracDiffのd最適化を全期間一括で行うな | cmd_861 |
| L301 | PSR/DSRは時系列順序を無視する弱点あり。p平均法で補完必須 | cmd_861 |
| L302 | Backtest validationはtrials_log SSOTがなければ成立しない | cmd_862 |
| L303 | Sharpe inference実装ではkurtosisとexcess kurtosisを混同するな | cmd_862 |
| L304 | n≤5のFoFではEqualWeightがML手法(NCO/HRP)に勝つ可能性がある | cmd_862 |
| L305 | 月次84点データでは高頻度特徴量(VPIN/Kyle/SADF等)の大半が適用不可 | cmd_862 |
| L322 | 候補集合間で比較する事前計算指標は共通期間かサンプル窓メタデータを必ず持たせよ | cmd_1000 |
| L323 | rolling p̄ BTではno-selection warm-upを別指標で明示せよ | cmd_999 |
| L324 | p̄計算のMIN_PERIOD_LENGTH制約とmonths_per_fold設計 | cmd_1002 |
| L327 | 短窓BT reportは実効保有数を条件欄に明示せよ | cmd_1005 |
| L328 | MIN_PERIOD_LENGTH=1だけでは短窓p̄検定が退化しうる | cmd_1005 |
| L334 | top_n=1のp̄ BTはEW-12だけでなく単体12体の同期間比較を必須化せよ | cmd_1008 |
| L335 | 3体プール×mpf=1ではp̄が統計的に退化しtie expansion 100%発生。最小有効mpf=2 | cmd_1008 |
| L336 | ファミリー内3モード選択でp̄は最弱を上回るが最強を上回ることは稀。性能差小ファミリーで有効性相対高 | cmd_1008 |
| L337 | p̄月次戦術運用は選出・退避いずれも無効。Sharpe勝率0/192全敗。5連敗で結論確定 | cmd_1009 |

---

## §25. trade-rule/business_rules突合（2026-03-11 殿確定6裁定）

殿とのtrade-rule.md / business_rules.md / 現行コード突合セッション。cmd_767(trade-rule補完7箇所) → cmd_769(MECE整合) → cmd_770(business_rules乖離10箇所修正)の3段で完了。

| # | 確定内容 | cmd | 影響先 |
|---|---------|-----|--------|
| 1 | FoF参照日: 「直近リバランス時のsignal_dateで確定したsignal」が正。「前月末」表現は不正確 → 避ける | cmd_767 AC6 | RULE08 |
| 2 | wᵢ = 月初目標ウェイト。非リバランス月でも月初リセット（暗黙的月次リバランス = ユーザー公平性設計） | cmd_769 AC2 | RULE05/06 |
| 3 | Trade期間リターン: buy-and-holdではなく月次複利合成 R_trade=Π(1+R_月)-1 | cmd_768 AC1 | RULE05, return_calculator.py |
| 4 | SSOT 3層: Price table(L0) → calculate_monthly_return()(L1) → MonthlyReturn table(L2キャッシュ) | cmd_769 AC4 | core §2 |
| 5 | business_rules.md §3.4 Loading Policy（Optimistic UI禁止）は陳腐化。SWR許可 | cmd_770 AC3 | FE api-client.ts |
| 6 | Safe Haven: コードとbusiness_rules.md §1.1完全一致。Cash=DTB3、safe_haven_asset設定でGLD/XLU等 | cmd_767 AC7 | — |

→ `dm-signal.md` §25 | `projects/dm-signal.yaml` RULE05/06/08/SSOT更新済み
→ cmd_768: calculate_trade_period_return()を月次複利合成に修正完了
→ cmd_770: business_rules.mdの乖離10箇所修正完了

---

## §26. 万全偵察: DM-signal改善候補（cmd_761+762, 2026-03-11）

水平4名(FEバンドル/BE応答/エラー耐性/UX導線) + 垂直4名(GSD式4観点独立分析)の8名同時投入。

### 水平偵察(cmd_761)

| 領域 | 担当 | 主要発見 |
|------|------|---------|
| FEバンドル | 影丸 | Dashboard 139kB最重量。recharts+d3(332KB raw)が最大chunk。KaTeX fonts 1.17MB |
| BE応答速度 | 半蔵 | monthly-returns 1721ms最遅。N+1クエリ(全PF×expanded_tickers)がボトルネック |
| エラー耐性 | 小太郎 | 401連鎖崩壊(1本失敗→全セッション崩壊)。retry/fallback不統一 |
| UX導線 | 才蔵 | 16ページフラットナビ。Admin/一般混在。ページ説明なし |

### 垂直偵察(cmd_762, GSD式)

| 観点 | 担当 | Top3ペインポイント |
|------|------|------------------|
| ユーザー体験 | 飛猿 | (1)初回ロード2-5秒 (2)16項目フラットナビ認知負荷 (3)エラー復帰手段欠如 |
| コード品質 | 霧丸 | 型安全性の穴(any/型assertion)、テストカバレッジ低い重要モジュール |
| データフロー | 佐助 | PF切替→7-11 API殺到。キャッシュ戦略不統一(api-cache/IndexedDB/localStorage混在) |
| インフラ/運用 | 疾風 | Render Free SPOF(1 worker)。監視/アラート不在。ロールバック手段なし |

### 統合: 最高ROI改善策（家老統合AC5）

| 優先 | 施策 | コスト | 効果 | 実行cmd |
|------|------|--------|------|---------|
| 1 | BE N+1クエリ最適化(monthly-returns) | M | 高 | cmd_775/791 |
| 2 | FEバンドル最適化(recharts dynamic import等) | S | 中 | cmd_784/785/786 |
| 3 | prefetch request storm抑制 | M | 高 | cmd_783 |
| 4 | 401連鎖崩壊の隔離(エンドポイント単位) | S | 中 | cmd_758 |
| 5 | フォルダフィルタ共通化(PersistentFolderFilter) | M | 中 | cmd_787 |

→ 多くは後続cmdで着手/完了済み。詳細 → `context/dm-signal-frontend.md` §7以降
- L499: 分析入力データの出自(provenance)検証必須。出自不明データで分析するな（cmd_1440）

## §27. シン四神 v2 設計（2026-03-19 殿・将軍合同検討）
<!-- last_updated: 2026-03-19 v2全面再設計: DNA事前制約+データ駆動lookback確定 -->

### 設計方針（v2 — 旧方式を全面廃止）

**旧方式(v1)**: 広く探索(191,796)→CPCV→Triple-E→脱相関K体→32ユニット。DNA理解が甘くパラメータが幅広すぎた。
**新方式(v2)**: DNA理解→パラメータ事前制約→既存GS結果でlookbackデータ分析→3モードチャンピオン直接選出→**12体**。

4ファミリー × 3モード(CAGR/MaxDD/NewHigh)。重複吸収(激攻>常勝>鉄壁)で**10体**。
朱雀・玄武は激攻=常勝が同一変種→常勝消滅。シン忍法はこの10体を材料として構築。
- L415: CPCV(Phase 3)はDM×FoFに構造的不適合として廃止(殿裁定 2026-03-19)。FoF材料は一瞬のきらめきで十分（cmd_1078）
- L494: 将軍予備分析と忍者独立検証で数値が乖離。独立実装間の差異は想定内（cmd_1411）
- L495: 将軍先行分析とのCAGR差異は独立実装間の想定差（cmd_1411）
- L498: ローリングSharpe選抜は遅行指標でWardクラスタ構造選抜に劣後する（cmd_1417）
- L514: Ward Two-Stage EW(k=5,lookback=36mo)のクラスタが141リバランス日(12年)完全固定。1/N EWとの差+0.25%。パフォーマンスに寄与していない定量的証拠（cmd_1570）
- Ward固定化根因(cmd_1578): 相関距離の構造的狭さ(separability=0.33<0.5全期間全k、全ペア距離mean=0.61)。シンv2は旧より高相関(距離26%狭)でWardさらに不安定(ARI安定性45.5%vs旧63.6%)
- K=5/LB=36 vs K=4/LB=24比較(cmd_1576): Sharpe差0.1%未満(2.0801 vs 2.0793)で実質同等。R19(99セルGS)真最適はK=4/LB=30。後方伝播検証不在が根因だがパラメータズレは軽微
- **R28 Ward Cluster Selection(cmd_1579): Ward改善不可の最終根拠**。クラスタ内momentum top1選出+K体EW保有→全K(3,4,5)で現行Ward FoF(全員保有)に全指標劣後。ClSel(K=5) Sharpe1.77<1/N EW1.78。超越条件3つ全FAIL(CAGR:60.6%vs80.6%/Calmar:2.72vs4.18)。**ウェイト変更でもselection変更でもWard改善不可能**
- **R28-シン ClSel逆転(cmd_1581): シン素材で有効に逆転**。シンClSel_K3がCAGR74.6%/Sharpe1.75/Calmar4.60/MaxDD-16.2%/UWP3mで全方式中最良。超越条件B(Calmar4.60>3.90×0.95)PASS+C(UWP3m<5m)PASS。旧忍法では全FAIL→シンで逆転=素材依存性が明確。集中投資リスク(20体中3体)が残課題。cmd_1578(ARI45.5%=クラスタが動く)と整合
- **R28-OOS 過適合なし(cmd_1580): WF-OOS 7窓で旧忍法Ward ClSel過適合フラグなし**。劣化率<30%全K。Ward K=4がOOS最良(CAGR74.0%/Sharpe2.02/Calmar3.57)。Ward vs Simple Momentum: 全KでWard優位(Sharpe差+0.28〜0.49)。Ward vs 1/N EW: K=4,5がEW(Sharpe1.89)上回る。**OOSでクラスタリング付加価値確認**
- R28-K2端点検証(cmd_1584): K=2は全K中CAGR最高(旧61.3%/シン75.8%)だがMaxDD最悪(旧-32.2%/シン-20.4%)。旧は超越条件全FAIL。シンは条件Bのみ辛うじてPASS(Calmar3.72≥3.705)。**K=2は集中リスク許容範囲外。K=3-5が最適帯域**
- R28-指標感度分析(cmd_1582): 4指標(Momentum/Sharpe/Calmar/Sortino)×K=3,4,5=12パターン全てWardFoF全員保有(Sharpe1.85)に劣後。Sharpe選抜K=5が1.80で最高。Sortino-Momentum間ランク相関0.49で最も独立。**指標空間でもWard改善不可**
- **PD-004裁定(2026-03-31殿裁定): Ward FoFはkeep(継続)**。R28-R30研究で付加価値ほぼゼロ+β調整後超越条件全FAIL確定だが、殿判断で維持
- R28-Momentum持続性(cmd_1583): 個別自己相関は全lag非有意。クロスセクショナルhit rateはK=3,4で高度有意(短期1ヶ月)だが長期lookbackで減衰。**R28のmomentum前提は弱い。12ヶ月lookbackの理論的根拠は薄い**
- **R28-シンOOS(cmd_1585): K=3 Calmar41.6%劣化=OVERFIT**。K=4はCalmar28.1%劣化でOK。CAGR劣化は全K7%以内。Ward vs SimpleMom付加価値は旧忍法比半減。**cmd_1581のK=3超越条件B+C PASSはOOSで過適合の可能性。シンでもK=4がOOS最良**。L516登録
- R28-シン指標感度(cmd_1586): シンClSel 4指標(Momentum/Sharpe/Calmar/Sortino)×K=3,4,5=12パターン完了。Sortino K=3がCAGR75.3%/Sharpe1.81/Calmar5.29/MaxDD-14.2%で全方式最高。**超越条件ではmomentum最優(2/3 PASS)。Sortino1/3(Bのみ)、Sharpe/Calmar0/3**。momentumはUWP3m(最短)で条件C PASS。指標変更で超越条件改善せず
- R28-回転率(cmd_1587): ClSel K=3は低回転率。シン平均入替0.77体/月(26%/月)、全入替(3体全交代)は0.9%。入替月vs非入替月リターン差は非有意(p=0.91)。**ローテーション自体はリターンに寄与していない。取引コストは限定的**。シン加速R-激攻が最頻選出(44.7%)
- R28-耐性(cmd_1588): ClSel K=3下落月(EW<-5%,11回)平均-9.76%でEW(-9.52%)微劣後だが最悪月-15.37%はEW(-18.67%)より3.3pp浅。**MaxDD-16.22%は3手法最浅**(EW-22.74%/Ward-20.78%)。COVID暴落2ヶ月底→翌月回復(計3ヶ月)。集中投資リスクは上昇月超過リターン(+0.69pp vs EW)で補完
- **R28-統合(cmd_1589): 全26方式統合比較+推奨**。CAGR TOP3: シンK2_Mom(75.8%)>K3_Sortino(75.3%)>K3_Mom(74.6%)。Calmar TOP3: K3_Sortino(5.29)>K3_Mom(4.60)>K3_Sharpe(4.49)。**3条件全PASS(超越+OOS劣化<30%+Turnover)はシンClSel K=4 Momentumのみ**。K=3 MomはCalmar劣化41.6%FAIL(CAGR劣化7.2%は閾値内)。K=3 SortinoはOOS未検証。**素材効果(シン>旧)が方式選択より支配的。旧ではClSel<FoF<EWだがシンではClSel>EW>FoF(逆転)** → `outputs/analysis/nested_fof/r28_unified_comparison.md`
- **⚠️R28-β分離(cmd_1591): ClSel K=3のCAGR向上95.8%はβ由来、α寄与わずか4.2%**。選出PF平均β=1.105 vs全体1.000(spread+0.105,p<0.0001)。β調整後: CAGR3.14%/Sharpe0.34/Calmar0.15/MaxDD-20.5%/UWP24m。**β調整後超越条件A/B/C全FAIL**。momentum選出は構造的に高βPFを掴む(最頻:シン加速R-激攻β1.233)。OOS: α寄与6.1%だが6窓中2窓でα負。**cmd_1581/1586の超越条件PASSはβ露出込み=αとしての付加価値は確認できない**(assumption_invalidation)。L517登録
- R28-SortinoOOS(cmd_1590): Sortino選出WF-OOS(8窓90m)。K=3: CAGR70.1%/MaxDD-29.0%(full-sample-14.2%から倍増)/Calmar劣化54.4%=**OVERFIT**。K=4: Calmar劣化31.1%=OVERFIT。K=5: 全指標30%未満OK。CAGR/Sharpe劣化率はSortino<Momentum(信頼性高)だがMaxDD劣化はSortino>Momentum(K=3: -103.9% vs -58.7%)。**OOS超越条件は全K全FAIL(0/3)**。**full-sampleのMaxDD優位はIS全体の選出バイアスでOOS消滅**(assumption_invalidation cmd_1586)。L518登録
- **R28-OOS超越(cmd_1592): OOS同士比較で超越条件全方式FAIL**。OOS個体ベスト>full-sample(CAGR96.8%vs92.2%、Calmar4.71vs3.90)。Momentum K=3/4/5全0/3FAIL、**Sortino K=3/4/5全0/3FAIL**、1/N EWのみ条件C PASS(1/3)。原因: (1)OOS個体ベスト上昇で閾値上昇 (2)ClSel OOS性能劣化の二重効果。**選出指標(momentum/Sortino)に関わらずOOSで超越条件未達**。L519登録
- **R28-IS感度(cmd_1593): IS長は結論を変えない。OVERFIT確定**。IS=36/48/60全てCalmar劣化>30%(46.4%/42.6%/41.6%)。MaxDD=-25.7%は全IS長で同一。CAGR/Sharpe劣化7-15%。Cross-metric CV=1-4%。**CLUSTER_LOOKBACK=36が律速**: IS≥36では末尾36ヶ月のみ使用されるためIS長を変えても銘柄選択は変化しない。最適IS=60(最小劣化)。L520登録
- **⚠️R28-4指標β調整(cmd_1596): 全4指標でβ調整後超越条件全FAIL(12判定全FAIL)**。α ranking: Sortino(10.0%)>Sharpe(8.5%)>Calmar(7.9%)>Momentum(4.2%)。βプロファイル: Momentum=高β(1.105,p<0.0001)、Sharpe=低β(0.938,p=0.0003)、Calmar/Sortino=中立(~1.0)。β調整後水準: 最良Sortino(adj CAGR7.5%/Sharpe0.73)でもUWP24m。**ClSel K=3のCAGR向上は全指標でβ露出に依存、αとしての付加価値(超越条件)は確認不能**。L521登録
- R28-Sortino β分離+OOS補完(cmd_1595): **Sortino選出はlow-β(avg β=0.98,市場中立)でα2.4倍**(α share10.0% vs momentum4.2%)。momentum=高β(1.11)は構造的。**選出指標の数学的性質がβプロファイルを構造的に決定**。OOS超越条件はSortino全K0/3 FAIL(momentum同様)。L522登録
- **R28-LB感度(cmd_1594): 最適LB=2ヶ月**。旧忍法K3 t=4.04、シンK4 t=3.75でLB=2が全K一貫最大。標準12M(旧t=2.75/シンt=1.48)は最適でない。**4-5m/10-11mピーク仮説否定**。Spearman rank相関は全LB非有意(ランキング全体の連続相関なし)。assumption_invalidation: cmd_1579/1583。L523登録
- **R28-K値β検証(cmd_1597): K=2-5全水準でβ調整後超越条件全FAIL(16判定全FAIL)**。α share: K=2(6.5%)→K=3(4.2%)→K=4(1.3%)→K=5(1.0%)。**K増加でα効率単調減少**。K=4の3条件唯一PASSはβ主導(assumption_invalidation: cmd_1589)。L525登録
- **R28-統合v2(cmd_1598): 全19cmd最終統合レポート** → `outputs/analysis/nested_fof/r28_final_unified_comparison.md`。β調整後超越12/12 FAIL、OOS全方式FAIL、IS感度OVERFIT確定。3選択肢: (A)ClSel不採用(α不在、EWで十分) (B)Sortino+短期LBで改良版検証 (C)ClSel概念保持+別α源泉探索
- **R28-短期LB BT(cmd_1599): LB=2mは全K全指標でLB=12mに劣後。R28結論覆らず**。β緩和あり(K=3: 1.105→1.021)でα share4.2%→9.2%倍増だがraw CAGR/Sharpe/Calmar/MaxDD(-29.3%)全悪化。**超越条件0/3**。LB短縮で持続性(t統計量)は改善してもBTパフォーマンスは低下。L526登録
- **⚠️R28-短期LB OOS(cmd_1600): LB=2mでOOS劇的改善。Calmar劣化41.5%→逆転-23.5%**。K=3: OOS CAGR82.6%/Sharpe1.78/Calmar3.11/MaxDD-26.6%。LB=12m OOS(K=3 Calmar劣化41.6%=OVERFIT)が**LB=2mで解消**。α寄与7.5%。**full-sampleではLB=12m優位だがOOSではLB=2m優位** — 過適合に強い

- R28-Sortino LB=2m BT(cmd_1601): **Sortino×LB=2mは全K全指標でLB=12mに劣後。α share3.4%**(LB=12m α10%の1/3)。β=0.951(low-β)で鉄壁/常勝モードに偏向。信号安定性STABLE(CV1.58<2.0)だが6m/12mより大幅不安定。momentum LB=2m(α9.2%)よりα低い。**Sortino×短期LBの組み合わせはα効率を悪化させる**
- **R28-LB=2m OOS超越(cmd_1602): raw超越条件C PASS(1/3)**。K=3/K=4ともUWP≤5でC PASS。**LB=2mが唯一ClSelでOOS超越条件Cを通す方式**。ただし**β調整後は0/3 FAIL**。LB=12m ClSel全方式0/3 FAILとの明確な差
- R28-Sortino LB=2m OOS(cmd_1603): **Calmar劣化56.9%=OVERFIT**(LB=12m54.4%と同水準)。momentum LB=2m(-23.5%)とは対照的。**Sortino過適合はLBでなく指標特性(下方偏差推定不安定性)に起因**。momentum LB=2mが最もα効率の高い方式(α7.5%)。L527登録

### R28 研究教訓（cmd_1579-1603）

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L516 | WF-OOS Calmar劣化はMaxDD悪化とCAGR劣化を分離評価すべし | cmd_1585 |
| L517 | momentum選出は高β構造バイアス(p<0.0001)。CAGR向上の95.8%はβ由来 | cmd_1591 |
| L518 | Sortino選出はfull-sample MaxDD優位がOOSで倍増し消滅する | cmd_1590 |
| L519 | OOS個体ベスト≠full-sample。超越条件の閾値はOOS固有値で再計算必須 | cmd_1592 |
| L520 | CLUSTER_LOOKBACK=IS長のときIS増加は選択に影響しない | cmd_1593 |
| L521 | β中立指標(Sortino/Calmar)のα効率はmomentumの2倍以上だが超越条件は不十分 | cmd_1596 |
| L522 | Sortino選出はlow-β PFを選びα成分2.4倍。選出指標がβプロファイルを構造的に決定 | cmd_1595 |
| L523 | overlapping-window mechanical correlation trap。LB>1でt統計量が桁違いに膨れる | cmd_1594 |
| L525 | ClSel K値増加でα効率単調減少(K=2:6.5%→K=5:1.0%)。分散はβ希釈+α希釈 | cmd_1597 |
| L526 | 短LB momentum選出はβ緩和するがリスク指標(MaxDD/UWP)を大幅悪化 | cmd_1599 |
| L527 | Sortino過適合はLB短縮で解消しない。指標特性(下方偏差推定不安定)に起因 | cmd_1603 |
| L529 | NewHigh/UWP選出指標はLB短区間(1-4m)で差別化力が弱い | cmd_1608 |

### 確定パラメータ（殿裁定 2026-03-19）

| パラメータ | DM2(青龍) | DM3(朱雀) | DM6(白虎) | DM7+(玄武) |
|---|---|---|---|---|
| **DNA** | 降りない | 債券方向スイッチ | VIX mean reversion | 構造的逆張り |
| absolute | LQD | TMF | ^VIX | SPXL |
| relative | TQQQ,TECL | TECL,TQQQ | TQQQ,TECL | XLU |
| safe_haven | **XLU固定** | TMV | **GLD固定** | TQQQ |
| top_n | 1, 2 | 1, 2 | 1, 2 | 1 |
| rebalance | **Mのみ** | **Bo, Beのみ** | **Qj, Qf, Qmのみ** | **Mのみ** |
| lookback | **10D〜12M** | **10D〜3M** | **10D〜6M** | **15M〜24M** |
| composite | 3-term許可 | **単一のみ** | 3-term許可 | **単一のみ** |

### DNA制約の根拠

| ファミリー | rebalance根拠 | safe_haven根拠 | lookback根拠（データ実証） |
|---|---|---|---|
| DM2 | 「降りない」は月次行動 | XLU=退避しても株の中に留まる。GLD不適 | 長期+短期composite +14pp。短期はノイズではない |
| DM3 | 3xレバwhipsaw防止 | TMV=債券正逆ペア必須 | short帯(1M-3M)が圧倒。long lookbackは無価値 |
| DM6 | VIXノイズ除去（年4回行動） | GLD=第三軸。XLUは株でありVIXとの独立性不足 | medium(4-6M)+短期compositeが全3指標1位。VIX mean reversionサイクル全体を捕捉 |
| DM7+ | 信号は鈍く月次で十分 | TQQQ=攻守逆転の意図的設計 | 15M=CAGR最大、24M=MaxDD最小。12M削除（劣後） |

### 旧方式(v1)からの変更点

- CPCV(Phase 3)廃止（FoF材料に完成品基準を当てていた）
- Triple-E事前フィルタ廃止 → CAGR/MaxDD/NHFで直接チャンピオン選出
- 脱相関K体選出廃止 → 各ファミリー3モード×1体
- safe_haven選択肢を1つに固定（DM2: GLD削除、DM6: XLU削除）
- rebalanceをDNA準拠で制約（全6種→1〜3種）
- lookbackをデータ分析に基づき制約（全18点共通→ファミリー別範囲）
- 32ユニット → 10体に簡素化（重複吸収: 激攻>常勝>鉄壁。朱雀・玄武で常勝消滅）
- （L413→§24, L414→§21, L415→§27に振り分け済 2026-03-28）

### データ分析サマリー（既存191,796パターンGS結果から抽出）

データ: `outputs/grid_search/shin_shijin_l1/metrics_DM*.csv`（cmd_1018、本番パリティ100%検証済み）

**DM2** DNA filter後 6,390パターン:
- 3-term composite (CAGR med 38.3%) > 2-term (37.2%) > 1-term (35.9%)
- CAGR 1位: `11M:60|5M:20|20D:20` (+53.7%) — long+medium+ultra_short
- MaxDD 1位: `5M:40|2M:40|15D:20` (-27.7%) — medium+short+ultra_short (※DM6で発見)

**DM3** DNA filter後 12,780パターン:
- short+ultra_short (CAGR med 25.4%) >> long (14.6%)
- CAGR 1位: `1M:80|15D:20` (+35.9%)
- MaxDD 1位: `5M:80|20D:20` (-47.7%)

**DM6** DNA filter後 19,170パターン:
- medium+short+ultra_short composite (MaxDD best -27.7%) がultra_short単独を大幅に上回る
- CAGR 1位: `4M:50|1M:50` (+46.6%, MaxDD -29.4%)
- MaxDD 1位: `5M:40|2M:40|15D:20` (-27.7%)
- 当初想定(ultra_short 10D-20Dのみ)をデータが否定 → 10D-6M compositeに拡大

**DM7+** DNA filter後 8パターン:
- 15M: CAGR +37.9%, MaxDD -45.6%
- 24M: CAGR +30.9%, MaxDD -26.1%
- 12M削除（全指標で15Mに劣後）

→ 設計書: `outputs/analysis/shin_shijin_design.md` §11
→ シン忍法v2結果: `outputs/analysis/shin_ninpo_v2_champions.csv`（21体確定、吸収0）
→ v1記録(参考): Phase 2分析 `shin_shijin_phase2_metrics_analysis.md`, Triple-E `cmd_1022_family_triple_e.md`

### シン忍法v2 GS結果（cmd_1080）

10体 × 7忍法 × 375 subsets = 173,625パターン。全21体ユニーク(吸収0)。
最強: 加速D-激攻 CAGR 86.6%。最堅: 加速D-鉄壁 MaxDD -13.6%。最高NHF: 変わり身-常勝 3.37。

本番登録: L0=L1 standard 10体 + L2 FoF 21体 = **31体**。手順書v2更新必要。

→ チャンピオン一覧: `outputs/analysis/shin_ninpo_v2_champions.csv`
→ 32体ユニバースGS: `outputs/analysis/shin_shijin_phase5_champions.md`（cmd_1075, 733,392パターン）

### Phase 5 全量GSチャンピオン（cmd_1075）

32体ユニバース × 7忍法 = 733,392パターン全量GS完走。

| 指標 | Best忍法 | 値 | ファミリー |
|------|---------|-----|----------|
| Best CAGR | kasoku_ratio | 63.17% | DM2(青龍) |
| Best Calmar | kasoku_ratio | 1.510 | DM6(白虎) |

- Best CAGR: 全7忍法でDM2(青龍)ファミリーがチャンピオン。top_n=1, rebalance=monthly統一
- Best Calmar: 5/7忍法でDM6(白虎)ファミリー。3-4体構成が多い(分散効果)

→ 詳細: `outputs/analysis/shin_shijin_phase5_champions.md`

### GS高速化（cmd_1029-1064）

| マイルストーン | 時間 | 手法 |
|-------------|------|------|
| 初期ベースライン | 23h | 逐次実行 |
| PPE導入(cmd_1031) | 2.8h | Preprocessed Execution全忍法適用 |
| T3 picks vectorize(cmd_1048) | 42min | ctx_buildボトルネック直撃 |
| 並列実行(8忍者) | **12min** | チャンク分割8並列 |
| numpy momentum cube(cmd_1064) | さらに改善 | pandas→numpy slice一括 |

本番パリティ完全一致が全高速化の絶対条件。→ `context/gs-speedup-knowledge.md`

### GS高速化第2世代（cmd_1827-1834）— 150min→1.9min(79x)

BATCH_CHUNK(30x) + 横展開(14x) + gs_runner並列(12x)の三重効果。WFメモリOOM解消(10.2GB→3.68GB)。lazy import(-79.6MB/worker)。gs-bench-gate WARN自動化。CSV I/O: numpy savetxt(float32)置換で270s→4.47s(60x)実装完了(cmd_1836)。BytesIO中継+年月プレフィックス追記パターン(L598)。→ `docs/research/gunshi_research_pipeline_meta_20260410.md` / `docs/research/gunshi_wf_engine_memory_fix_design_20260410.md`

### 奥義-シン忍法（cmd_1822/1840/1844）

**定義**: シン忍法20体を構成PFとしたL2 FoF。3目的(CAGR/NHF/MaxDD)×7忍法=21体。

**2つの方式の違い（殿指摘 2026-04-10）**:

| | シン忍法方式（正） | ALM方式（誤適用） |
|--|-------------------|-------------------|
| **選出方法** | GS全期間結果から事後的に最強パターンを選出 | WFエンジンでIS窓を毎月動的に切替えOOS検証 |
| **パラメータ** | 固定（全期間ベスト1つ） | 動的（毎月変わる） |
| **道具** | GS CSV直接読込み | l1_alm_wf_engine.py |
| **用途** | シン四神/シン忍法/奥義-シン忍法 | ALM四神/ALM忍法 |

**経緯**:
1. **cmd_1822 AC1**: GS新規実行（run_077_*.py --universe okugi_shin_ninpo_20.yaml）→ 7 CSV生成。これは正しい
2. **cmd_1840**: GS CSVにWFエンジン(l1_alm_wf_engine.py)を適用しチャンピオン選出 → **ALM方式を誤適用**。結果は参考データとして保持（破棄しない）
3. **cmd_1844**: GS CSVから事後的に3目的チャンピオンを直接選出 → **正しいシン忍法方式**

**殿指摘(2026-04-10)**: 「シン忍法にALM忍法をしていないか？」→ 奥義-シン忍法は シン忍法と同じ事後選出方式で作るべきところ、将軍がALM方式(WFエンジン)で作った。 「結果は破棄するなよ。それはそれで役に立つ」→ cmd_1840の結果は保持。 「しかし今回やろうとしていたものとは違う」→ cmd_1844で事後選出方式にて再実行。

**データ**:
- GS CSV: `outputs/grid_search/okugi_shin_ninpo_20body/cmd_1822_okugi_shin_ninpo_20body_{忍法}_grid_monthly_20260409.csv`（7本）
- ALM方式結果(参考): `queue/archive/reports/tobisaru_report_cmd_1840_20260410.yaml`
- シン忍法方式結果: `queue/archive/reports/hanzo_report_cmd_1844_20260410.yaml`（PASS。195万パターン→21チャンピオン選出。直列事後計算、OOMなし）

**cmd_1844結果（GS事後方式、正しいシン忍法方式）**: hanzoが7 GS CSV全量(2,859,025パターン。報告の1,958,050は合算ミス)からCAGR/NHF/MaxDDを直接事後計算。7忍法×3目的=21チャンピオン。吸収候補なし。cmd_1840(ALM方式)との比較でGS事後方式のCAGR優位(kawarimi+12.2%, yotsume+8.8%)。MaxDD目的はcmd_1840に選出方向の不整合発見(最悪値選出の疑い→decision_candidate)。

**OOM事故(cmd_1843)と教訓**: wf_runner.py並列ランナー(workers=2)でOOM Killer発動→エージェント死亡。殿裁定: 並列不要、直列1本ずつが正解。cmd_1843クローズ。→ `docs/research/gunshi_wf_oom_prevention_design_20260410.md`

**知見(2026-04-10検証済み)**: ALM方式(WF動的選択)とGS事後方式(全期間最強固定)の激攻・常勝チャンピオン14体中10体が同一pattern_id。全期間最強パターンはALM動的選択でも選ばれる傾向がある。差が出たケース: kawarimi CAGR(GS事後93.0% vs ALM 84.4% = +8.6pp), yotsume CAGR(88.4% vs 81.3% = +7.1pp)。鉄壁(MaxDD目的)はALM方式が最悪値を選出しており比較不能。GS CSV直接計算で独立検証済み(bunshin N2_0072: 両方式78.6%完全一致, kawarimi全222,300パターン中1位=N3_0771_24M 93.0%でcmd_1844と一致)。

- L601: cmd_1840 maximum_drawdown目的は最悪値を選出（GS事後とは逆方向）（cmd_1844）→ **修正済み(86f2e6ae)**: METRIC_DIRECTIONテーブル導入+MINIMIZE_SETから除去+MaxDD=0→NaN選出マスク。→ `docs/research/gunshi_maxdd_direction_bug_design_20260412.md`
- L602: oikaze MaxDD champion ID誤記 N2→N4（cmd_1845）
- L604: IS前半チャンピオンは全期間チャンピオンと完全に異なる(0/21一致)（cmd_1848）
- L605: CAGRチャンピオン系は構造的に過適合リスクが高い: 全忍法でMEDIUM以上、NHF/MaxDD系は全てLOW（cmd_1847）
- L620: L2奥義2×2因子分析でL1傾向継続だが縮小。GS固定の2種混在(DB vs champion)が一因（cmd_1878）

**道具磨き成果（副産物）**:
- OOM対策: load_data() numpy直読み化(cmd_1841)+GS側.npy同時出力(cmd_1842)。WF CSV読込OOM根絶。WF並列実行は禁止(LG025)
- **champion_selector.py**(2026-04-11軍師作成): GS CSV/.npyから3目的チャンピオンを直列選出。NaN-safe+float64+チャンク+方向テーブル+NHF NaN除外。195万パターン→25秒/1GB。cmd_1844と21/21完全一致。→ `docs/research/gunshi_champion_selector_design_20260411.md`
- **MaxDD方向バグ+ゼロバグ修正**(2026-04-12軍師修正, commit 86f2e6ae+2df25f6d): l1_alm_wf_engine.pyにMETRIC_DIRECTIONテーブル(champion_selectorパターン横展開, Level 5)導入。MaxDD負値×argmin=最悪選出→argmax=最浅選出に修正。ゼロバグ: MaxDD=0.0+UWP=0.0(NaN→0由来の偽ゼロ)→NaNマスクで偽チャンピオン防止。ALM四神全6 objective検証済み(argmax方向4つはゼロバグ不発生)。recalculate_fast.pyも予防修正。12テスト全PASS。→ `docs/research/gunshi_maxdd_direction_bug_design_20260412.md`
- **cpcv_analyzer設計**(2026-04-11軍師設計): CPCV(N=8,28fold)6メトリクス一括算出。パーティション事前計算で30倍高速化(kasoku_diff: 7.4秒/758MB)。→ `docs/research/gunshi_cpcv_analyzer_design_20260411.md`

**NaN-safe計算の必須知見(LG025)**: cumprodはNaN伝播で真チャンピオンが消失する(kasoku_diff CAGR実証)。prod方式+有効月数年率化+NaN月NHF除外+float64が正解。全事後計算ツールに埋込み済み

### パリティ検証（cmd_1097-1116）

| cmd | 対象 | 結果 | 教訓 |
|-----|------|------|------|
| cmd_1097 | L1シグナル突合 | GS関数にシグナル直接出力が必要(L422) | リターン逆推定では不十分 |
| cmd_1098 | L1リターン突合 | monthly_return_open列使用必須(L420/PI-008) | GS=Open-to-Open方式 |
| cmd_1106 | v2パリティ分析 | 不一致95%はRC4解像度差異(L425) | partial/MTD仮説は1.5%のみ(L424) |
| cmd_1115 | v2パリティ100% | Signal 1815/1815, Return 1815/1815一致 | resample月末修正(L427)+valid_start_date修正(L428) |
| cmd_1116 | 追加検証 | 非決定的順序+partial-month初月(L429) | — |
| L461 | oikaze batch | precomputed momentum_cube picks vs 本番MomentumFilterBlock選出に乖離(cmd_1200) | batch側のpick計算パスが本番と異なる |
| L473 | ^VIX/DTB3 cache汚染 | price_data_cacheに非市場ティッカーを含めると日付インデックスリサンプルでpct_change参照ズレ(cmd_1243) | **[PI-010]** |
| L479 | selection FoF init月検証不可 | selection付きFoFのinit月はholding_signal=Noneで独立検証不可(cmd_1270) | — |
| L480 | selection FoF初月holding_signal=NULL | selection-based FoF初月のmonthly_returns.holding_signal=NULL問題(cmd_1271) | — |
| L482 | selection-block FoF本番検証可 | selection-block FoFは本番holding_signalベースで検証可。Cash月はスキップ(cmd_1269) | — |

→ パリティ修正詳細: `context/dm-signal-core.md` §4 L419/L427/L428

### CPCV/相関/パターン分析（cmd_1019-1026）

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L351 | CPCV群分割で割り切れない場合のnp.array_split+サイズ差ログ標準化 | cmd_1020 |
| L352 | CPCVでlower-is-betterメトリクス使用時はスコア反転必要 | cmd_1020 |
| L354 | L1フルデータ(191K変種)では全ペア相関が時間的に不安定 | cmd_1019 |
| L355 | DM7+ファミリーPASS候補全4体がGLD系でXLU系全滅 | cmd_1024 |
| L356 | 32体ユニバースのパターン爆発はsize4が86.8%支配。加速が全体の66.1% | cmd_1026 |

⚠ 登録進捗管理はチェックリストに移行済み→`context/checklist-shin-v2-registration.md`

### ネステッドFoF Phase1 (cmd_1410)

→ 成果物: `outputs/analysis/nested_fof/` (CSV3+YAML1+PNG1+PY1)
→ スクリプト: `scripts/analysis/nested_fof/phase1_fof_baseline.py`

| 指標 | R1(EW21) | 5体精鋭 | 最強個別(加速D-激攻) |
|------|----------|---------|---------------------|
| CAGR | 58.6% | 67.2% | 88.0% |
| MaxDD | -20.4% | -15.4% | -26.5% |
| Sharpe | 1.76 | 2.03 | — |
| NHF | 62.9% | — | — |

- 21体平均ペア相関0.682（高）。同一ファミリー内0.74-0.99、クロスファミリー0.22-0.59
- 少数精鋭(5体): 加速D-激攻/四つ目-鉄壁/加速D-鉄壁/分身/四つ目-激攻。Greedy低相関選択
- ⚠ 四つ目-激攻CAGR差異0.226 (GS=0.714 vs calc=0.488)。MultiView4窓union+タイミング要調査 (L493)

#### 将軍独立分析 — R2設計核心 (cmd_1410事後)

→ 詳細: `docs/research/nested-fof-preliminary-analysis.md`

| 手法 | CAGR | MaxDD | Sharpe | 備考 |
|------|------|-------|--------|------|
| R1(EW21) | 58.6% | -20.4% | 1.76 | 全22戦略中最高Sharpe |
| Greedy Best4 EW | 76.4% | — | — | 事後選択（OOS不明） |
| ★Ward4クラスタ→各最強1体→EW | 73.2% | -13.0% | 2.06 | 理論ベース。パラメータ0 |
| Ward4クラスタ OOS(前半選抜→後半テスト) | 92.5% | — | — | 網羅探索77.7%を+14.8%上回る |

- **R2最有力**: クラスタベースEW（パラメータ0）。理論ベース低相関>統計ベース
- **構造的核**: 加速D-激攻（最高CAGR88%+最低平均相関0.48）。全手法・全期間で選出

#### ウォークフォワード確定結果 (131ヶ月OOS 2015-03〜2026-01)

| 手法 | CAGR | MaxDD | Sharpe | パラメータ |
|------|------|-------|--------|-----------|
| R1 (EW21) | 63.8% | -20.4% | 1.79 | 0 |
| 4cl-AllEW (選抜なし) | 75.2% | -17.3% | 2.08 | 0 |
| **R2 (WF-Cluster BestCAGR EW)** | **80.8%** | **-18.6%** | **2.02** | 0 |
| R5候補 (Cluster+6M Momentum) | 83.3% | -23.1% | 2.05 | 1 |
| InvVol | 79.6% | -17.1% | 2.07 | 0 |

- クラスタ数頑健性: 3-10全てR1超え。4がスムーズなCAGR/Sharpeピーク
- クラスタ安定性: T=144-167で同一4体に収束（加速D-激攻+抜き身-激攻+加速R-鉄壁+追い風-激攻）
- ~~R4(Half-Kelly): 将軍予備分析94.0%~~ → **WF実装(cmd_1412): CAGR69.9%, MaxDD-29.6%, Sharpe1.79。R2に全指標劣後=FAIL**
- 予備94%→実装70%の乖離=Kellyのμ/Σ推定が小標本(N=4)で不安定。DeMiguel(2009)N<50 EW優位と整合
- R4キャップ感度(cmd_1412 AC4): cap0.15-0.50の6パターン全てR2未達。cap0.50でSharpe1.91(R2に漸近=EW化)
- ~~R6_ext(R2+外部レジーム cmd_1412 AC3): CAGR72.7%, Sharpe2.16~~ → **ルックアヘッドバイアス確定(軍師検証)**
  - レジーム: VIX>80pctl AND SPY<10M SMA → 3段階(risk_on97M/caution21M/risk_off13M)
  - **lag-1補正後(前月末データ使用=Faber2007準拠)**: CAGR61.2%, MaxDD-20.7%, Sharpe1.87 → R2にもR1にも劣後
  - 131ヶ月中43ヶ月(32.8%)でレジーム判定変動。バイアス影響は「限定的」ではなく構造的
  - r6_ext_regime.py L153: external_df.loc[t](当月末)使用が原因
- **R7(逆ボラ加重 cmd_1413 AC1)**: CAGR73.4%, Sharpe1.933, MaxDD-20.4%。SharpeとMaxDDでR2超え。**最有望補完候補**
  - R2損失月8/10月で改善(平均+0.60%)。2020-03(COVID): R2=-13.0%→R7=-8.2%(+4.8pp)
  - 弱点: 2022-12 R2=-18.3%→R7=-20.4% — 低ボラ体集中が裏目
- **R8(絶対モメンタム cmd_1413 AC1)**: CAGR73.7%, Sharpe1.896, MaxDD-21.5%。R2と実質同一(BestCAGR戦略は常に正モメンタム→フィルタ不発)
- **R9(VIX連続スケーリング lag-1 cmd_1413 AC2)**: CAGR54.9%, Sharpe1.950。cash60/131月(45.8%)でCAGR壊滅。Sharpe微改善のみ
- **R6lag1(離散レジーム lag-1 cmd_1413 AC2)**: CAGR61.2%, Sharpe2.00(最高), MaxDD-20.7%。CAGR犠牲大
- **ドロップ確定**: R3(HRP/InvVol改善微小), R4(EWに劣後), R5+R4(逆効果), **R6_ext(ルックアヘッドバイアス)**, R8(R2と同一), R9(CAGR壊滅)
- **★CHAMPION確定: R2(Ward4cl EW)** — CAGR74.5%, Sharpe1.92, MaxDD-21.5%。パラメータ0。全ルール中唯一R1を全指標で上回る
- **補完候補**: R7(逆ボラ)はSharpe+MaxDDでR2を上回り損失月も改善。ブレンド検討の余地あり
- 分散分解: R2の優位はσ²低減ではなくμ上昇(+0.126)が支配。効率的フロンティア上方移動
- → 詳細: `docs/research/nested-fof-preliminary-analysis.md`

### R10-R14: 手法拡張+ローリング検証 (cmd_1417-1422)

→ 成果物: `outputs/analysis/nested_fof/r10_*` 〜 `r14_*`

| 手法 | CAGR | Sharpe | MaxDD | Calmar | 備考 |
|------|------|--------|-------|--------|------|
| **R10(Rolling Top4-Sharpe EW, cmd_1417)** | 67.9% | 1.82 | — | — | R2に-6.5%劣後。ローリングSharpe選抜 |
| **R11 M4(GreedyMinCorr K=4, cmd_1419)** | 82.8% | 2.17 | -11.5% | 7.19 | 5手法中Sharpe/Calmar最良。R2と4体中3体共通 |
| **R12 K感度(cmd_1420)** | — | — | — | — | Ward最適K*=5(Sharpe1.97WF)。K=4次善。K3→6脱落なし安定構造 |
| **R13 GreedyK5統合(cmd_1421)** | 85.6% | 2.19 | -12.7% | 6.72 | 4手法事後版Sharpe最良。5体目=抜き身-激攻 |
| **R14 Rolling Ward K=5(cmd_1422)** | 91.3% | 2.18 | -15.1% | 6.06 | ローリング最良。事後版減衰-2.7%=実運用可能 |
| **R15 K感度(cmd_1423)** | 91.3% | 2.18 | — | — | K*=5(最適)。K5/K6プラトー。事後K=5と一致 |
| **R16 LB感度(cmd_1424)** | — | 2.18 | — | 6.06 | LB*=36ヶ月(最適)。broad peak=頑健。[24,36,60]近傍良好 |
| **R17 2Dグリッド(cmd_1425)** | — | 2.13 | — | — | (K*,LB*)=(5,36)=最適。peak_ratio=1.073=頑健。共通期間 |
| **R19 拡張2D(cmd_1427)** | — | 2.19 | — | — | 99通り。最適(K=4,LB=30)。K=5,LB=36=97.5%。peak_ratio=1.12 |
| **R20 時間安定性(cmd_1428)** | — | — | — | — | 48窓×3メトリクス。Sharpe:K=4-5最適54%。3メトリクスK一致0% |
| **R21 因果切り分け(cmd_1429)** | — | 2.13 | — | — | Ward寄与97.2%,モメンタム2.8%。ランダム100回mean=2.07。Sortino:Ward106.1% |
| **R22 3方式統一比較(cmd_1430)** | — | 2.12 | -13.5% | 6.44 | 二段EW=BestCAGRの99.5%。MaxDD/Calmarは二段EW優位。体数不均衡比率avg6.55 |
| **R23 行動メトリクス(cmd_1431)** | — | — | — | — | 48窓ローリング。二段EWとBestCAGRは46-48/48窓同値。連敗全窓同値。行動面でもほぼ同等 |
| **R24 二段EW2Dグリッド(cmd_1432)** | — | — | — | — | 99通り。最適(K=4,LB=30)=BestCAGRと同一。Sharpe73/99優位、MaxDD86/99優位。peak_ratio=1.09 |
| **R25 四神12体2Dグリッド(cmd_1434)** | — | 1.48 | — | — | 90通り。最適(K=3,LB=24)。TwoStageEW優位83.3%(Sharpe)。R24(73.7%)より高優位率。12体でもロバスト |
| **R26 全PF65体2Dグリッド(cmd_1435)** | — | 1.49 | — | — | 171通り。最適(K=6,LB=18)。Sharpe優位70.8%,MaxDD優位95.9%。peak_ratio=1.064。65体でもロバスト |

- R13結論: GreedyK5 > GreedyK4(Sharpe) > WardK4(=R2) > WardK5(静的)。5体目: Greedy=抜き身-激攻、Ward=抜き身-鉄壁(異なる)
- R14結論: ローリングWard K=5が最良。GreedyK5は事後版減衰-17.1%で不安定。全手法R1(Sharpe1.87)を大幅超過
- R15結論: ローリング版K*=5(Sharpe2.1756)。事後版K=5と一致→データスヌーピングバイアスなし。K5/K6プラトー(2.1756 vs 2.1608)。gradual peak=中程度パラメータ感度。選抜安定性: K増でtop1選出率59%→95%、TO低下(22.5%→13.2%)
- R16結論: LB*=36ヶ月(Sharpe2.1756)=cmd_1422完全一致。broad peak=頑健(LB24:2.11, LB60:2.13も良好)。LB48だけやや低下(1.99)。TO: LB増で低下(24%→12%)。Calmar: LB36(6.06)最良
- R17結論: 2次元グリッド30通り。最適(K*,LB*)=(5,36) Sharpe=2.133(共通期間)。peak_ratio=1.073(<1.3)=緩やかな山=頑健。Sharpe std=0.0756(変動極小)。交互作用: LB短→K=4最適、LB中→K=5最適。K=5,LB=36は最適そのもの(100% of peak)
- R19結論: 拡張99通り(K=2-12×LB=12-60)。最適**(K=4, LB=30)** Sharpe=2.1869に移動。K=5,LB=36=97.5%(2.5%差)でプラトー内。peak_ratio=1.12=頑健。Sharpe std=0.1064。LB=30付近にスイートスポット(K=4-6高Sharpe帯)。K≥9やLB≥48は性能低下。K=2は常に最低域
- R20結論: 時間安定性テスト(48窓×3メトリクス)。**Sharpe: K=3-6最適68.8%, K=4-5最適54.2%, LB=18-36最適93.8%**。K=4,LB=30平均ランク11.5/99(上位12%)。**3メトリクス間K一致度0%**(Sharpe→K=4-5, CAGR→K=2, MaxDD→K=3)。K=5,LB=36: Sharpeランク14.4, CAGRランク27.0, MaxDDランク32.2。**R15-R20統合結論: Sharpeベースの最適帯K=4-5,LB=30-36はrobust。ただしCAGR/MaxDDでは最適Kが異なる(メトリクス依存性あり)。殿がヒートマップ+数値で最終判断**
- R21結論: BestCAGR vs ランダム×100因果切り分け(K=5,LB=36固定)。**Ward寄与率97.2%(Sharpe)**、モメンタム効果わずか2.8%。BestCAGR Sharpe=2.1333、ランダム平均=2.0735(std=0.0948)。WorstCAGR=2.0689(ランダム70パーセンタイル)。**Sortino: Ward効果=3.6205、モメンタム効果=-0.2079(微負)**→Ward構造が支配的価値源泉。BestCAGR選択の付加価値は統計的にわずか
- R22結論: 3方式統一比較(K=5,LB=36固定)。**二段EW Sharpe=2.1228=BestCAGR(2.1333)の99.5%**。モメンタム仮定ゼロでもWard構造だけで高パフォーマンス維持。**MaxDD: 二段EW-13.5%<BestCAGR-14.9%。Calmar: 二段EW6.44>BestCAGR6.19**=リスク面で二段EW優位。クラスタ間体数不均衡比率avg6.55(min3.50,max11.00)。ランダム平均=2.0735(R21完全一致)
- R23結論: 3方式行動メトリクスローリング(W=24ヶ月×48窓)。**二段EWとBestCAGRは46-48/48窓で同値**。最大連敗は全窓同値。BestCAGRが微差で優位(NHF:-0.4%, underwater:+0.4%)。ランダム平均は両方式より劣位。**純粋構造(二段EW)は行動面でもBestCAGRとほぼ同等**
- R24結論: 二段EW2Dグリッド99通り(K=2-12×LB=12-60)。**最適(K*,LB*)=(4,30)=BestCAGR(R19)と同一(移動なし)**。Sharpe73/99セル(73.7%)で二段EW優位。**MaxDD86/99セル(86.9%)で二段EW優位(浅いDD)**。ただしCAGR34/99(34.3%)で二段EW劣後。peak_ratio=1.09=頑健。**二段EWはSharpe/リスク面で広範に優位、リターン(CAGR)ではBestCAGR優位**
- R25結論: シン四神v2 12体2Dグリッド90通り(K=2-11×LB=12-60)。**最適(K*,LB*)=(3,24) Sharpe=1.4785**。BestCAGR最適(K=11,LB=36) Sharpe=1.4705。**最適点移動あり(R24:K=4,LB=30→R25:K=3,LB=24)**。TwoStageEW優位83.3%(Sharpe)>R24(73.7%)。共通期間=2017-04~2026-02(107ヶ月)。**12体でも二段EW構造はロバスト、かつ優位率がR24(21体)より向上**
- R29f-shin結論(cmd_1606): **シン忍法v2 20体 LB×4指標2Dグリッド ClSel WF-OOS**。48セル全実行。**BEST: LB=6 Momentum CAGR=88.5%, Calmar劣化=-5.1%(OOS>FS)**。R28ベスト(LB=2 Mom 82.6%)を+5.9pp上回る。EW20(72.3%)を+16.2pp上回る。殿基準全PASS=2/48(MaxDD>SPYがボトルネック)。Calmar劣化<30%=33/48。Momentum指標がCAGRトップ3独占 → `queue/reports/tobisaru_report_cmd_1606.yaml`
- R29f-kyu結論(cmd_1607): **旧忍法15体 LB×4指標2Dグリッド ClSel WF-OOS**。48セル全実行。**BEST: LB=2 Calmar CAGR=77.4%, 劣化9.2%**。殿基準PASS=38/48。Calmar劣化<30%=48/48(全セル、過適合なし)。Momentum列がCAGR最高値独占(LB5:71.9%,LB2:71.3%)。**旧忍法は殿基準PASS率が大幅に高い(38/48 vs shin 2/48)=MaxDDが浅い** → `queue/reports/kotaro_report_cmd_1607.yaml`
- R29g-shin結論(cmd_1608): **シン忍法v2 20体 NewHigh+UWP追加2指標×12LB=24セルWF-OOS**。殿基準20/24 PASS。6指標統合BEST=LB6 Momentum(CAGR 88.5%, Degrad -5.1%)が依然最強。**NewHigh/UWPはLB1-4で同一体を選出(差別化不可)、LB5+で分岐**。NewHigh LB=11最高CAGR(71.6%)、UWP安定64-69% CAGR。既存4指標より低CAGRだが低MaxDD(-20~-23%)/低UWP(3-7m)で安定性優位 → `queue/reports/hayate_report_cmd_1608.yaml`
- R29g-kyu結論(cmd_1609): **旧忍法15体 NewHigh+UWP追加24セルWF-OOS**。殿基準14/24 PASS。6指標統合最適LB=2 Calmar(CAGR 77.4%, 劣化9.2%)。**R29f-kyu(4指標48セル)とマージして6指標統合ヒートマップ出力** → `queue/reports/kagemaru_report_cmd_1609.yaml`
- R30-OPTICS denoise(cmd_1623): **MP法denoised相関+OPTICS密度ベースClSel vs Ward K=3(raw)**。9LB値比較。Ward 7/9 LB値でSharpe/CAGR/MaxDD優位。OPTICS LB>=24でxi抽出が単一クラスタに退化(N=20小集団でreachability同一化)。LB=18: OPTICS Sharpe=1.836微優位だがMaxDD-0.27(Ward-0.21)劣位。β調整: 両手法ともalpha負。**密度ベースClSelはN>=50以上で有効。小集団にはWard K指定が適切(L530)** → `outputs/analysis/nested_fof/r30_denoised_optics_vs_ward.yaml`
- R30-shin結論(cmd_1604): **20体全個体WF-OOS(IS=60m,OOS=12m,step=12m,8窓)+buy&holdベンチマーク**。面: CAGR>TQQQ&TECL=20/20、過適合SUSTAIN=20/OVERFIT=0(全体OOS≥FS)。殿基準ALL_PASS=7/21(**MaxDD>SPYがボトルネック**: 6/20のみ)。点: CAGR1位=加速D-常勝(96.8%)、alpha>0=8/20。**ClSel K=3 LB=2m: CAGR75th(rank6/20)/Sharpe95th(rank2/20)**。EW20 OOS: CAGR72.3%/Sharpe1.77/Calmar3.18 → `queue/reports/hanzo_report_cmd_1604.yaml`
- R26結論: 全PF65体2Dグリッド171通り(K=2-20×LB=12-60)。**最適(K*,LB*)=(6,18) Sharpe=1.492**。**Sharpe優位70.8%(121/171)、CAGR優位67.3%、MaxDD優位95.9%(164/171)**。mean Sharpe=1.402, std=0.048, peak_ratio=1.064=頑健。R24(21体)overlap99セルでR26全敗(65体=分散でSharpe水準低下。構造は頑健)。**最適K: R24=4→R25=3→R26=6（体数増でK増加傾向）。LB: R24=30→R25=24→R26=18（体数増でLB短縮傾向）。三段階(12→21→65体)全てで二段EWのSharpe/MaxDD優位構造は一貫**
- R11 M4とR2の差分: 追い風-鉄壁(M4) vs 追い風-激攻(R2)のみ。MaxDD大差(-11.5% vs -16.7%)
- TO(月次入替率): Ward K=5=19.6%, Greedy K=4=22.6%。Ward低回転で実運用有利
- R27結論(cmd_1436): **WardTwoStageEWビルディングブロック実装**。R1-R26研究結論を汎用モジュール化(`scripts/analysis/nested_fof/building_block.py`)。内部K×LBグリッドサーチで最適パラメータ自動決定。R24/R25/R26の3データセット(21体/12体/65体)で既知最適(K*,LB*)再現確認+Sharpe 1e-4以内一致。コールドスタート(データ不足時1/N EW)・k_max自動クランプ実装済み
- R27-旧PF結論(cmd_1441): **旧忍法15体+旧四神12体のWard+TwoStageEW 2Dグリッド分析**。旧忍法: K*=4,LB*=24,Sharpe=2.01,TwoStageEW優位率49.6%。旧四神: K*=4,LB*=12,Sharpe=1.55,TwoStageEW優位率76.7%。合計27体: K*=12,LB*=24,Sharpe=1.75。R25(12体,1.48)/R26(65体,1.49)より高Sharpe → `queue/archive/reports/hayate_report_cmd_1441_20260330.yaml`
- ネオ五神偵察(cmd_1442): **GLD/USO/TIPの既存4absolute資産との相関偵察**。候補-既存max|r|: GLD=0.343(最有力), USO=0.378(次点), TIP=0.769(LQD冗長→不適)。危機時: GLD=利上げ時独立(全<0.17)、USO=COVID時VIX連動(0.719)、TIP=両危機でLQD完全連動。GLD独自ドライバー(中銀/地政学/インフレ) → `queue/archive/reports/hanzo_report_cmd_1442_20260330.yaml`
- **Standard PF前処理研究日誌**: 思考・判断・結果の時系列記録。候補8手法の選別経緯、本命2つ(Gerber+LW)の研究設計、結果記入欄 → `docs/research/standard-pf-preprocessing-journal.md`
- **前処理研究の全思考過程（殿との対話記録）**: FoF天井→Standard PF転換→EMA+112%/L1+383%→overfit警告→OOS検証。殿の全転換点含む → `memory/dialogue_preprocessing_research_20260331.md`（経験的知識。圧縮禁止。過程が本体）
- BB前処理偵察(cmd_1627): **モメンタム系3BB+全7BB前処理不在確認+注入ポイント特定**。全BB共通基盤=calculate_composite_momentum_vectorized、生close直接pct_change(前処理なし)。注入ポイント5箇所: (A)ブロック内price取得後(副作用小・推奨), (B)base.py load_ticker_prices共通層, (C)vectorized_momentum.py計算基盤層, (D)ティッカー選出ロジック内(Gerber相関), (E)新規SelectionBlock(Gerber独立BB)。加速BBは短期/長期ratio/diffで平滑化と構造的に重複しない(組合せ可)。MonthlyReturnMomentumFilterはDB直接読込で独立。recalculate_fast.py Phase2 momentum_cache生成パスは前処理導入時に整合要件あり。研究仮説3件: H1-EWMA平滑化SNR改善, H2-Gerber閾値低相関選出, H3-対数リターン頑健性 → `queue/reports/hanzo_report_cmd_1627.yaml` / `queue/reports/kagemaru_report_cmd_1627.yaml`
- EMA平滑化研究(cmd_1629): **5PF×5span(0/5/10/21/42)=25条件。close→EMA(span)→pct_change→momentum**。**DM3 span=42でCAGR2倍(0.11→0.23)/Sharpe45%改善**が注目結果。DM7+(504D lookback)はEMA影響ほぼなし。DM6(15D短期lookback)はEMA劣化(遅延が有害)。**EMA効果はlookback依存: 短期PFに恩恵、超短期に有害、長期に不変**。span=0 baseline誤差2-8%(リバランスタイミング簡易実装差) → `queue/archive/reports/hayate_report_cmd_1629_20260331.yaml`
- Gerber gate-level threshold研究(cmd_1628): **65PF×5k(0.0/0.25/0.5/0.75/1.0)=325件。gate判定: diff=mom(asset)-mom(DTB3)>k*σ(diff)→BUY**。k=0.0=本番一致(match率85-97%、リバランス簡易実装差)。才蔵return-level GS1(FAIL)→半蔵gate-level修正。L532: cmd仕様の適用レベル(gate vs return)を実装前にコード注入ポイントと照合確認すべし → `queue/archive/reports/hanzo_report_cmd_1628_20260331.yaml`
- LW shrinkage研究(cmd_1630): **65PF×8config(baseline+ApproachA/B/C×5閾値)=520 walkforward runs**。3アプローチ比較: A(リスク調整momentum/σ)=多ticker PFで最大乖離、B(shrinkage α*mean+(1-α)*momentum)=α小で効果微小、C(z-score threshold gate)=**threshold≥0.5で有意差、≥1.0で顕著**。単一ticker PFでは全アプローチ同一(共分散shrink対象なし)。sklearn LedoitWolf使用 → `queue/reports/kagemaru_report_cmd_1630.yaml` / `outputs/analysis/standard_pf_preprocessing/ledoit_wolf_study_results.yaml`
- FFD研究(cmd_1631): **5PF×5variant(baseline/d_opt/0.3/0.5/0.7)。結論: FFD×AbsoluteMomentumは構造的に非機能**。FFD値にprice level成分が残存→stock FFD>>DTB3 FFD→AbsMom判定が常時通過→Whipsaw=0で全期間ロング固定。FFDは入力前処理としてMomentumFilterランキングには影響するが、AbsMomゲートとしては原理的に無効。d_opt: TQQQ/TECL/XLU=0.25, GLD/LQD/SPXL=0.20, TMF=0.15, TMV=0.05, VIX=0.00(既定常), DTB3=1.00 → `queue/archive/reports/tobisaru_report_cmd_1631_20260331.yaml`
- EMA 65PF全数評価(cmd_1632): **65PF×5span(0/5/10/21/42)=325件walkforward**。cmd_1629(5PFのみ)を65PF全数に拡張。pipeline_configからreference_assetモードstandard PFを自動検出。シン四神12体含む全PFに5指標(CAGR/Sharpe/MaxDD/whipsaw_count/match_rate_vs_span0)算出。ema_smoothing_results_full.yaml出力。commit bd88221d → `outputs/analysis/standard_pf_preprocessing/ema_smoothing_results_full.yaml`
- Kalman Filter研究(cmd_1634): **65PF×4mode(auto_EM/fixed_qr0.01/0.1/1.0)=260件walkforward**。1D random walk+noise KF。auto EM推定(B3)平均CAGR=0.3386、fixed最良qr_0.1(B1)=0.3516。**auto推定はbest fixedより-0.013(やや劣る)**。auto推定のQ/R比は大半4-7に収束(高応答=軽い平滑化)。Benhamou(2018)準拠。半蔵impl → `outputs/analysis/standard_pf_preprocessing/kalman_filter_results.yaml`
- L1 Trend Filter研究(cmd_1633): **65PF×5lambda(0/1/10/100/1000)=325件walkforward**。cvxpy凸最適化でL1区分線形トレンド抽出。**ユニバーサル最良lambda=10(mean CAGR=34.62%)**。per-PF best分布: lam0=14,lam1=17,lam10=8,lam100=12,lam1000=14(均等→overfitリスク)。**22/65PF(34%)に>5pp neighbor gapのoverfit警告**。影丸impl → `outputs/analysis/standard_pf_preprocessing/l1_trend_filter_results.yaml`
- DM6.5 VIXレジーム×中期lookback研究(cmd_1681): **6仮想PF(lookback={42,63,126}×rebalance={M,Q})×4条件=24件walkforward**。DM6構成固定でlookbackを中期に変更。**Q42 Kalman(auto) CAGR 0.524 > DM6 15D baseline 0.504**。「DM6系は前処理で常に劣化」は15D固定条件限定の仮説→中期lookbackでは反例あり。才蔵impl → `outputs/analysis/standard_pf_preprocessing/dm6_5_study_results.yaml`
- DM6.5拡張 全12lookback研究(cmd_1684): **9 lookback(1M~12M)×72条件walkforward + cmd_1681統合12 lookback横比較テーブル**。Q rebalance>M全域。Q_105D(5M)+EMA CAGR=0.468、Q_84D(4M)+L1 CAGR=0.437が有望。7M+はCAGR低下。殿予想の4M/5M確認。注意: cmd_1681=kalman_auto、cmd_1684=ema_span_21で第4条件不一致(L535)。小太郎impl → `outputs/analysis/standard_pf_preprocessing/dm6_5_extended_results.yaml`
- **研究WF共通エンジン(cmd_1691+R31-R37)**: research_engine.py完成。14関数+Strategy Pattern+SSA/FoF/FDA統合。**196s→1.58s(124x)+config 707x**。R31-R34: 高速化。R35: SSA統合。R36: FoF共通関数統合。R37: FDA統合。全研究スクリプトがresearch_engineをimport → `scripts/analysis/standard_pf_preprocessing/research_engine.py`
- シグナル相関変化分析(cmd_1701): **65PF×2条件 相関行列+尖り削減量×FoF Δcagr回帰**。r=-0.199→尖り削減≠FoF悪化主因。depth増幅(L538)が支配変数。L539教訓。小太郎impl → `outputs/analysis/standard_pf_preprocessing/signal_correlation_analysis.yaml`
- FoF全59体EMA間接波及(cmd_1700): **59 FoF×2条件=118WF**。avg_Δcagr=-0.087。改善11/59。**ネスト深度増幅発見**: depth=1(四神)正効果→depth=2(旧忍法)損失増幅→depth=3(Ward)最大損失Δ=-0.182。L538教訓。影丸impl → `outputs/analysis/standard_pf_preprocessing/fof_all59_ema_results.yaml`
- FoF momentum実態監査(cmd_1707): **active 59 FoF = EW 17 / momentum 19 / nested 23**。terminalは58/59が`EqualWeight`だが、**selection_block=0は17/59のみ**。FoF momentum実行経路は `component cumulative returns -> selection block(if any) -> terminal`。cmd_1700スクリプトの「all 59 FoFs are EqualWeight(selection_block=0)」前提は不正確で、L0前処理は42体の選抜結果にも波及しうる → `docs/research/cmd_1707_fof_momentum_audit.md`
- Layer3最終出力前処理研究(cmd_1687): **Ave-X/裏Ave-X × 2条件(baseline/L0 EMA span=5) = 4 WF**。三層研究完結。EMA span=5間接波及→最終出力: Ave-X CAGR+2.2pp(0.359→0.381)/Sharpe+0.064、裏Ave-X CAGR+1.3pp(0.423→0.436)/Sharpe+0.037。MaxDD不変。本番投入でユーザー体験改善確定。半蔵impl → `outputs/analysis/standard_pf_preprocessing/layer3_final_output_results.yaml`
- FoF第二層前処理研究(cmd_1683): **6 FoF(四神+Ave-X+裏Ave-X)×3条件(baseline/間接波及/直接適用)=18件walkforward**。L0 EMA間接波及: 朱雀+0.11 CAGR(最大)。直接適用(C-B)=全FoFで0.0(EW FoFのためL1 momentum pathなし)。疾風impl → `outputs/analysis/standard_pf_preprocessing/fof_layer2_preprocessing_results.yaml`
- PE gate研究(cmd_1635): **65PF×16configs(4window[12,24,36,48M]×4threshold[no_gate,0.7,0.8,0.9])=1040件walkforward**。Bandt&Pompe(2002)準拠PE(m=5,τ=1)。**m=5ではPE値が低くgate大部分未発火**。window=12/24はPE<全閾値(ベースラインと同一)。window=36/t=0.7のみ発火(CAGR win率21.5%)。window=48/t=0.7発火(win率7.7%)。**PE gateは月次リターンのm=5では実用的に無効**。L533: m=5は120パターンの疎分布→低閾値(0.3-0.5)検討要。疾風impl(才蔵・小太郎FAIL→3回目) → `outputs/analysis/standard_pf_preprocessing/entropy_gate_pe_results.yaml`

## §29. 金融ML知識辞書 拡充 (cmd_1636-1653, cmd_1713, 2026-04-03追記)

前処理研究(§28)の文献サーベイ30+論文の知見が辞書に未記録だったことを契機に、一次知識層の大規模拡充を3波で実施。
guide.mdに純度ルール（一次知識層汚染防止）を追加後、全忍者6名並列投入×3波。

| Wave | cmd | エントリ数 | 領域 |
|------|-----|----------|------|
| 1 | cmd_1636-1641 | 25件 | トレンド推定(L1TF/Kalman/FDA/AdaptiveKalman)、エントロピー(PE/Jump/Shannon/Transfer)、信号分解(SSA/VMD/SG/CF)、適応的(DML/GOC/BBT/SlowMom+CPD)、リスク(JumpModel/VolScale/MedianMom/NetworkMom)、メタ知見(S02-S05/V04) |
| 2 | cmd_1642-1647 | 18件 | モメンタム正典(TSMOM/XSMOM/DualMom)、PF構築(MVO/Ward/RiskParity/BL/MaxDiv/Kelly)、ボラティリティ(GARCH/CVaR/EWMA)、ML基盤(Bootstrap/FeatImp/SeqBoot)。**cmd_1643(Crash/LifeCycle/RegimeSw)ファイル未作成** |
| 3 | cmd_1648-1653 | 18件 | cmd_1643穴埋め(M40/M41/M54)、資産価格(CAPM/FF3/Carhart/FF5/APT)、時系列(ARIMA/VAR/Cointegration)、統計検定(ADF/KPSS/Ljung-Box/Jarque-Bera/Granger) 、マイクロストラクチャー(Amihud/VPIN) |

**累計61エントリ**(methods/47 + validation/8 + portfolio/6 + sources/5 + pitfalls/3)。純度検証PASS（プロジェクト固有データ混入0件）。

### 2026-04-03 追加

| ID | エントリ | 概要 | ファイル |
|----|---------|------|---------|
| M17 | FLAIR (Factored Level And Interleaved Ridge) | `Level × Shape` 分解で周期構造を固定し、圧縮した `Level` のみを Ridge 予測する単一方程式型予測手法。一次知識層と DM-Signal 解釈層を分離して追加 | `docs/research/knowledge-base/methods/m17_flair.md` / `docs/research/knowledge-base/dm-signal/flair-interpretation.md` |

残課題 → `docs/research/research-todo.md`

## §29. Standard PF FDA Smoothing研究 (cmd_1666)
<!-- last_updated: 2026-04-01 -->

FDA(Functional Data Analysis) B-spline smoothingの5PFリトマス紙検証。Boubaker et al.(2021) FRL準拠。

| 条件 | K={4,8,16,32} × λ={0,1e-4,1e-2,1} = 16条件 × 5PF = 80件walkforward |
|------|------|
| 実装 | `scripts/analysis/standard_pf_preprocessing/fda_smoothing_study.py` (790行) |
| 結果 | `outputs/analysis/standard_pf_preprocessing/fda_smoothing_results.yaml` |

**DM3リトマス結果** (baseline: CAGR=0.109, Sharpe=0.456, MaxDD=-0.788):
- Best性能(K=32,λ=0): CAGR+232%, Sharpe+88%, MaxDD+31% — **ただしMatch49.5%(シグナル大幅乖離)**
- バランス(K=8,λ=0.01): CAGR+158%, Match41%
- 高Match(K=4,λ=0): CAGR+49%, Sharpe+23%, Match50.8%

**知見**: K増大は性能向上とMatch率低下のトレードオフ。DM7+のみK=32でMatch98.4%と例外的高整合。PFごとにK感度が大きく異なり一律パラメータ選択は不適。OOS検証(cmd_1660)で判定完了 → 下記§30参照。

## §30. EMA/L1 OOS検証 — overfit定量判定 (cmd_1660)
<!-- last_updated: 2026-04-01 -->

EMA平滑化(cmd_1632)とL1 Trend Filter(cmd_1633)のパラメータ選択がoverfitか本物かを2段階検証。

| Stage | 手法 | EMA結果 | L1結果 |
|-------|------|---------|--------|
| Stage1 IS/OOS split | 65PF×5params。劣化率<30%=ROBUST | universal span=5 **ROBUST**(median deg=-3.6%) | universal lambda=1 **ROBUST**(median deg=-7.7%) |
| Stage1 分布 | OVERFIT/SUSPECT/ROBUST | 4/18/43 | 7/14/44 |
| Stage2 PBO(CSCV 70組合せ) | Probability of Backtest Overfitting | **PBO=0.71 OVERFIT** | **PBO=0.54 OVERFIT** |
| DM3リトマス紙 | Stage1+Stage2 | EMA PBO=0.26 **ROBUST**(span=42, IS Sharpe=0.66→OOS=0.67) | L1 PBO=0.00 **ROBUST**(lambda=1000, IS=1.01→OOS=1.23) |

**結論**: 全体PFレベルではパラメータ選択にoverfit傾向あり(PBO>0.5)。ただしDM3は例外的にROBUST。assumption_invalidation: cmd_1632/1633の「overfit不明」前提を解消。

**性能知見**: L1 cvxpy計算で(ticker,lambda)キャッシュ適用 → 650→65回に削減、実行時間4h→1h(10倍高速化)。LC登録推奨。

→ `queue/reports/saizo_report_cmd_1660.yaml` | `outputs/analysis/standard_pf_preprocessing/oos_verification_results.yaml`

**研究実装教訓(§28-30統合)**: L532(gate/return-level照合)、L533(PE m=5閾値未到達)、L534(cvxpy cache 10x)、L535(cmd間前処理不一致)、L537(engine import必須)、L538/L539(ネスト深度増幅)、L540(fn cache id問題)、L541(depth_summary)、L542(用語テスト固定)、L543(rolling cumsum 50x)、L548(bulk metrics RFはPFごと月次軸)、L550(batch parityでbenchmark共通仮定禁止) — 全て§28-30の研究結果行に内包済み。詳細→projects/dm-signal/lessons.yaml

## §31. ファミリー別ALM + 5番目ファミリー候補 (cmd_1741)
<!-- last_updated: 2026-04-05 -->

absolute_assetでファミリー分類(DM2=LQD/DM3=TMF/DM6=^VIX/DM7+=SPXL)し、Max Run-up目的関数でALM実行。理論的低相関(駆動因子独立性)+危機時相関も分析。

**top候補: DM3** (alm_DM3_top5_win12m__max_run_up)。avg_corr_canonical=0.494(4ファミリー中最低=最分散)。inflation_2022=-0.089(負相関)。

→ `outputs/analysis/alm_research/cmd_1741_family5_analysis.yaml` | `cmd_1741_correlation_matrix.csv` | `cmd_1741_crisis_correlation.csv`
- L554: family ALM研究はmetricsと相関をベクトル化必須(cmd_1741)。L552/L553はinfra L439/L440と重複→削除
- L563: DNA制約(domain knowledge)は1M-12Mフルセットより高いIS max_run_upを3/4ファミリーで達成する（cmd_1759）

## §32. ALM L0×忍法7種 + 既存シン忍法比較 (cmd_1745)
<!-- last_updated: 2026-04-05 -->

ALM L0材料4本を忍法スクリプト7種で束ね、既存シン忍法20体と有限時間4指標で比較。orchestrator(425行)で自動実行。

**top結果: 抜き身-激攻/鉄壁がシン忍法を6/7指標で上回る**(beats_count=6)。四つ目-常勝はbaseline不在(吸収済み)。

→ `outputs/analysis/grid_search/cmd_1745_alm_ninpo_results.yaml` | `cmd_1745_vs_shin_ninpo.yaml`
- L565: 旧加速忍法はkasoku_ratio/kasoku_diffの区別なし。シン版以降からR/D分離（cmd_1761）

## §33. 6目的関数ALM×忍法7本 横比較 (cmd_1747)
<!-- last_updated: 2026-04-05 -->

6目的関数(max_run_up/tail_contribution/nhf/left_tail_jumps_inv/cagr/sharpe)×4ファミリーALM→24本L0→忍法7本→42パターン横比較。

**最汎用: tail_contribution目的が7/7 runner全て改善**。cagr目的=加速R beats6。LTJ_inv目的=抜き身 beats6。Max Run-up=6/7。

→ `outputs/analysis/grid_search/cmd_1747_cross_comparison.yaml` | `cmd_1747_ninpo_6obj_results.yaml`
- L567: tail_contributionは多様性低下要因。nhf/cagrが多様性貢献度最高（cmd_1763）[deprecated]
- L568: 10目的間Spearman相関全45ペアが冗長(|ρ|>0.8)。L0 4体からの選択プロセスが構造的要因（cmd_1764）

## §34. ALM L1 OOS検証 (cmd_1748)
<!-- last_updated: 2026-04-06 -->

6目的関数×忍法7種=42パターンのWF-OOS(IS=60M/OOS=12M/step=12M)。**41/42 ROBUST、1 OVERFIT(tail_contribution×加速R +80.8%)**。

| 目的関数 | ROBUST | OVERFIT | 特記 |
|----------|--------|---------|------|
| max_run_up | 7/7 | 0 | 劣化率-33.6%〜+5.2%。最安定 |
| tail_contribution | 6/7 | 1 | 加速R +80.8% OVERFIT |
| nhf | 7/7 | 0 | 全OOS>full-sample |
| left_tail_jumps_inv | 7/7 | 0 | 全ROBUST |
| cagr | 7/7 | 0 | OOS大幅超過(環境バイアス注意) |
| sharpe | 7/7 | 0 | OOS大幅超過(環境バイアス注意) |

→ `outputs/analysis/alm_research/cmd_1748_partial_*.yaml` (6ファイル)
- L556: GS CSVとALM L0 metricsのユニバース差がパリティ破壊（cmd_1748）
- L557: WF-OOS負の劣化率は過適合否定の十分条件ではない。市場環境バイアス要因（cmd_1748）
- L569: left_tail_jumps_inv早期fold(ウォームアップ期間)で全パターンNaN→OOSスキップで系列長短縮（cmd_1766）[deprecated]

## §35. ALM本番組込み設計 (cmd_1749-1753)
<!-- last_updated: 2026-04-06 -->
> **思考過程**: ALM研究→有限時間4指標→各論パッチ量産→原理1つへの到達 → `memory/dialogue_alm_finite_time_20260404.md`（経験的知識。圧縮禁止）

### 殿裁定 (2026-04-06)
- ALM定義: **L0で動的にlookback期間を変える**（PF選出ではない）
- Admin UI: **案A（表示切替）** — ☑ Adaptive チェックでLookback Periods→ALM CONFIG切替
- Dashboard追加表示: **不要**
- Monthly Trade変更: **不要**
- FE変更: **Admin画面のみ必要**（ユーザー向けページは変更なし）

### BE改修設計 (cmd_1750)
- **Hook場所: recalculate_fast.py（L0）が正。recalculate_fof.py（FoF）は別担当**
- Phase 3.7: ALM候補全LBのmomentum cache追加(+3.1MB/PF, +0.5s/PF)
- Phase 4: L1499月初リバランス直前にALM選出挿入
- fullrecalculate: **2パス方式**（Pass1: fallback LBでMR生成 → Pass2: ALM選出で正式シグナル）
- 日次ETL: 1パス（既存MR使用、追加コスト軽微）
- DBマイグレーション: **不要**（JSON列）
→ `docs/research/cmd_1750_alm_design.md`

### 盲点調査結果 (cmd_1751)
- FoFからALM PFは**透過的に動作**（MonthlyReturnテーブル統一構造）
- Daily cron: sync-standard(01:10UTC)→sync-fof(01:40UTC), mode=PORTFOLIO
- fullrecalculate自動cron: **なし（admin手動のみ）**
- Admin保存: 全124PF一括送信。pipeline_config=JSON列でスキーマレス
→ `docs/research/cmd_1751_fof_analysis.md` | `cmd_1751_cdp_findings.md`

### 実装順序
1. BE: recalculate_fast.py Phase 3.7/4改修 + 2パスfullrecalculate
2. BE: recalculate_fof.py Hook A (FoF側ALM対応)
3. FE: Admin PortfolioEditor.tsx Adaptive チェックボックス+ALM CONFIG
4. 検証: fullrecalculate + daily ETL動作確認

→ 統合設計書: `/mnt/c/Python_app/DM-signal/docs/research/alm-integration-design.md`

### ALM忍法 確定事項 (2026-04-06 殿裁定)
- **命名規則**: ALM-{忍法名}-{モード}（例: ALM-加速D-激攻）
- **3モード目的関数**: 激攻=max_run_up / 常勝=calmar / 鉄壁=UWP（殿裁定）
- **19体確定**（7忍法×3モード=21体 - 吸収2体）: ALM-加速R-鉄壁→常勝に吸収、ALM-分身-鉄壁→激攻に吸収
- **DNA制約版候補LBが3/4ファミリーで優位**（cmd_1759 L563）: DM3+23%/DM6+86%/DM7++56%
- L564: MINIMIZE_METRICSへのランタイムpatchでargmin方向を動的変更可能（cmd_1760）
- L566: ALM吸収はシン吸収と異なりメトリクスが変わる。目的関数が異なるため完全同一にならない（cmd_1762）
- **top_n**: DM2/DM6/DM7+=1、DM3=3（cmd_1759）
- L580: 38メトリクスは6目的維持+後計算添付が最速（cmd_1791）
- L587: METRIC_NAMES変更時はselect_champions_multi_isのmetrics_np dictも同期更新必須（cmd_1819）
- **Ward FoF**: K=3,LB=24がBest。K=5は4体<5クラスタで構造的不可能（cmd_1759 L562）
- **切替安定性**: max_run_up最不安定(20%/月)、left_tail_jumps_inv最安定(9%/月)（cmd_1759）
- **鉄壁4目的(cmd_1760)**: MDD目的がCalmar最高(2.78)。sortino目的の加速DがSharpe1.64(全体最高)
- **3世代比較gist**: https://gist.github.com/simokitafresh/ea687a966e627b5e454524004fdd747e
  - `alm_19_metrics_v2.md` — 19体完全版メトリクス
  - `alm_vs_shin_by_ninjutsu_v3.md` — 忍法別3世代比較(旧/シン/ALM、吸収反映)
  - `alm_vs_shin_full_38metrics.md` — 38メトリクス全量版

- L546: ALM foundation cacheは240 fixed seriesの完全性検証が必須（cmd_1737）
- L549: ALM batch統合ではobjective単位fallbackでparityを守る（cmd_karo_batch_R7）
- L554: family ALM研究はmetricsと相関をベクトル化必須（cmd_1741）
- L559: Pass2シグナルflush後のsignal_cache_opt6陳腐化リスク。ALM PF分のcache再構築必須（cmd_1752）CRITICAL
- L560: ALM buffer計算(L708-715)にcandidate_lookbacksのmax値を含める必要あり。378日不足（cmd_1753）
- L561: pipeline_config=Dict[str,Any]でalm_config未検証保存。ALM実装時にバリデーション追加必要（cmd_1753）
- L562: ALM L0 4体でWard FoFを組む場合K=5は構造的不可(体数<クラスタ数)（cmd_1759）
- L641: csv source universe使用時のkawarimi batch vs sequential MD5不一致（cmd_2175）
- L643: ALM忍法21体fold percentile中央値64.3はL0 WFシン四神(72.5)より低い（cmd_2218）
- L563: cmd_1762 BE第一弾完了(da14b6b7)。AlmConfig schema+Phase3.7 ALM cache+vectorized signals実装済み。注意: alm_config読取位置がblock config(実装)とPipelineConfig(schema)で分離→後続cmdで統一必要

### ALM L1: 忍法パラメータ動的選出（2026-04-06殿との設計議論）
- **ALM=lookback戦略のバリエーション**（固定/マルチプル/動的の延長。特別な仕組みではない）
- **忍法別ALM適性**: 加速R(75%)最強、変わり身(46%)最弱。全忍法一律ではなくL1増幅効果に差あり
- **ALM L1設計**: 加速Rのnum/denを動的選出(3パターンA/B/C)。全空間119,493パターン(サブセット含む)。事後フィルタ・事後ラベル
- **道具**: `l1_alm_wf_engine.py`(455行)構築中(cmd_1765/1766)
- **cmd_1763/1764発見**: 10目的間全45ペア相関>0.8(L0 4体共有構造)。目的関数の違いよりlookback戦略の違いが多様性の源泉
- → 詳細: `context/checklist-alm-registration.md` §設計原理
- L564: cmd_1763 ALM目的関数多様性分析完了(1d149a10)。Top1=MRU+NHF+CAGR(3.271)。cagr×MRU相関0.941(高)→実質多様性に注意。tail_contributionは多様性低下要因。calmar/UWPは6目的外→DC記録
- L565: cmd_1764 C(10,3)=120通り完了(e43cefd2)。Top1=MRU+NHF+CAGR(3.271)=cmd_1763と同一→6→10目的拡張で結論頑健。現行ALM Ward#12/120(上位10%)。冗長ペア45件=L0共有の構造要因。sortino欠損率69%→距離計算影響要確認
- L566: cmd_1765 L1 ALM WFエンジン骨格完了(1cbf703f)。CSV読込119,493列+30fold+6メトリクス。GS CSV早期NaN→fillna(0)修正。道具磨き完了→cmd B(タイムボックス60秒実行)が次
- **L0パリティ確定(2026-04-07)**: 12体全PASS (cmd_1774)。hs一致+ret差1e-11(<<1e-6)。momentum_dataにALMメタデータ(relative/absolute/risk_free/safe_haven)存在確認済み。fallbackではなくALM動的選出動作確認。
- **fullrecalculate完了(2026-04-07)**: 殿実行。recalculation_status id=43, 2026-04-07 10:37-10:44 JST (cmd_1787才蔵報告)。2パス方式正常動作。
- **FoF Cash化バグ修正(2026-04-07)**: cmd_1787で修正済み。原因=2026-04-03 perf commit(cdda5ea1/8f411ae9)でMVMF/SVMF/MFのmonthly cacheをdict{月末日:float}で保存→context.target_date(月初第1営業日)でexact .get()→val=None→全ticker除外→Cash。修正=bisect化(get_momentum_value_at_date統一)。commit 1a548111。
- **38メトリクス道具完成(2026-04-07)**: Phase A(cmd_1789→cmd_1791包含)/B(cmd_1791)/C(cmd_1791)完了。select_champions_multi_isが6 objectiveを維持したまま38メトリクスを後計算添付。selection_timeline=180行×47列。7忍法batch 200.65s(300秒制限内)。commit 1da2c487。
- **ALM四神hide維持(殿裁定 2026-04-07)**: global_visibility_settings hide_portfolio=trueのまま維持。パリティ確認済みだが殿裁定でStep 2e N/A扱い。
- **ALM四神フォルダ移動完了(2026-04-07)**: cmd_1792(疾風)でAdmin API経由で「ALM四神」フォルダ作成(folder_id=924734c6-a518-4985-b326-0aad7a68972f)+12体移動完了。非ALM folder_id差分=0。
- **ALM四神リネーム完了(2026-04-07)**: cmd_1788(才蔵)でDM番号→四神名(青龍/朱雀/白虎/玄武)にリネーム。commit saizo_report_cmd_1788.yaml timestamp 2026-04-07T20:05:15。
- **Step 3b WFエンジン36M固定実行(2026-04-08)**: cmd_1798(才蔵)。--multi-isフラグなしで実行→IS窓36M固定。all_success=true、7忍法×186エントリ×38メトリクス。commit 8e7d4b64。
- **Step 3b multi-is WF全量実行(2026-04-08)**: cmd_1799(小太郎)。67窓(6M-72M)×7忍法。IS窓多様性29-38種/忍法(36M固定でない)。213.76s。commit 7724bacb。→ Step 3c(champion確定)が次
- L613: 超越条件C(UWP<5M)は132ヶ月OOS期間に非現実的閾値。SPA全42セル非有意(p>0.4)。ISチャンピオン≒ランダム選択（cmd_1866）
- L615: Cell B(シン×ALM)の一部忍法はGSパラメータ数=1のためALM動的選出≡静的選出。2×2因子分析で縮退ケース注記必要（cmd_1869）

### ALM L2: 2×2因子分析結果 (cmd_1878)
<!-- last_updated: 2026-04-13 -->
- **BB効果**: ALM-BB vs シンBB = **+5.4pp**（GS側+7.2pp / WF側+3.7pp）
- **選出効果**: WF動的 vs GS固定 = **-12.9pp**（shin側-11.1pp / ALM側-14.6pp）
- **L1比較**: L1(BB+15pp/動的-27〜-41pp)→L2で傾向継続だが縮小（L2 GS固定にproduction_db+gs_static_champion混在が一因 → L620）
- **最優秀**: ⑤(ALM-BB×GS固定)×nukimi×激攻 CAGR=1.228 Sharpe=2.054
- **パターン別平均(CAGR)**: ⑤(0.819) > ⑥(0.772) > ③(0.730) > ①(0.707) > ⑧(0.516)最低
- **mode別選出効果**: 鉄壁のみWF優位(+4.4pp)。激攻は大幅WF劣位(-33.5pp)
- **縮退ケース(L615)**: bunshin(expected_patterns=1)はALM-WF≡GS固定(diff=+0.015)
→ 詳細: `queue/reports/kagemaru_report_cmd_1878.yaml` | CSV: `outputs/analysis/alm_research/cmd_1878_l2_okugi_comparison.csv`

### ALM L2: β調整分析 (cmd_1880)
<!-- last_updated: 2026-04-13 -->
- **α>0**: 168/168 (100%)。全体積が超過収益。
- **β調整後2×2効果(sign flip 0)**: BB効果・選出効果ともにrobust
  - static群: BB raw +7.2pp→beta_adj +8.0pp / selection raw -1.7pp→beta_adj -2.0pp
  - wf群: BB raw +3.7pp→beta_adj +3.8pp / selection raw -15.3pp→beta_adj -16.7pp
- **Top5完全一致**: raw/β調整後ともに⑤(nukimi/kasoku_diff/kawarimi/kasoku_ratio/oikaze)の激攻
- **最大順位上昇**: ⑦ oikaze/yotsume 鉄壁 各+21位（β低群=市場連動小→β調整で相対評価上昇）
- **最大順位下降**: ④ bunshin 常勝 -29位（β=1.82の高β群→β調整で下落）
- **⑧が最下位群独占**: ALM-BB×WF動的がβ高(β>1.7)+α低の構造的劣位
- **共通期間**: 88-161ヶ月（忍法/パターン依存）
→ 詳細: `outputs/analysis/alm_research/cmd_1880_l2_beta_adjusted_summary.md` | CSV: `outputs/analysis/alm_research/cmd_1880_l2_beta_adjusted_2x2.csv`

### ALM L2: 168体パターン間相関分析 (cmd_1893)
<!-- last_updated: 2026-04-14 -->
- **共通期間**: 87ヶ月(2018-08〜2025-10)、NaN率0%
- **8パターン間平均相関**: 0.63〜0.77（①ベースライン）
- **①vs各パターン**: ②0.77 > ⑤0.74 > ③0.70 > ⑦0.69 > ⑥0.68 > ④0.67 > ⑧0.63
- **仮説検証**: ①vs⑤(0.736) > ①vs③(0.701) → **確認**（同忍法BB違い > 目的関数違い）
- **多様性**: ⑧(ALM-BB×WF動的)が①と最も低相関(0.63)=追加価値最大。ただしβ調整では最下位群(cmd_1880)
→ 詳細: `outputs/analysis/alm_research/cmd_1893_correlation_summary.md` | CSV: `outputs/analysis/alm_research/cmd_1893_correlation_8x8.csv`

### ALM L3: 2体EW β調整分析 (cmd_1896)
<!-- last_updated: 2026-04-14 -->
- **入力**: 84体(GS固定①③⑤⑦) C(84,2)=3,486ペアEW。88ヶ月月次リターン
- **L3最良α**: 134.3%（①kasoku_diff激攻 + ⑤kasoku_diff激攻）> **L2最強α 101.2%**
- **L2超え**: 161/3,486件(4.62%)
- **Top10構成**: ①×⑤(5件) + ⑤×⑤(5件)のみ。③/⑦はTop10に入らず
- **③/⑦の最良rank**: ⑦ rank25(α=119.4%) > ③ rank43(α=115.8%)
- **結論**: L3はL2を上回る。追加候補は⑤で十分、③/⑦不要
→ 詳細: `outputs/analysis/alm_research/cmd_1896_l3_summary.md` | CSV: `outputs/analysis/alm_research/cmd_1896_l3_beta_adjusted.csv`

### CoDD適用: Phase 3完了 / Phase 4準備 (cmd_1947-1950, cmd_1986-1992)
<!-- last_updated: 2026-04-17 cmd_karo_context_freshness_1993 -->
- **Phase 3高速化完了**: yotsume `-98.6%`, nukimi `-63.3%`, oikaze `-99.3%`, l1_alm_wf `-81%`, bunshin `-78%`。レベルA上位5本のCoDD改善を完了。→ `docs/research/codd_refactor_registry.md` | `docs/research/codd_dmsignal_python_strategy.md` §0.5
- **N体EW比較を横並び化**: cmd_1947-1950系列で1/2/3体EWを同一評価軸に整列。alpha-CalmarはIS/OOS/Expandingで2-3体優位、WFは1体優位。→ `context/l2-okugi-progress.md` §L3 N体EW比較 | `context/senkyoku-log.md`
- **CoDD適用方式はハイブリッドで確定**: OSS版CoDDは `extract`/`measure` を使用し、spec/cProfile/実装/検証は手動で回す。`review`/`implement` は codd-pro 依存で対象外。→ `docs/research/codd_dmsignal_python_strategy.md` §0, §1
- **Phase 4は準備中**: 前提は `(1)` fullrecalculate read-only cProfile, `(2)` cmd_1985偵察結果の設計書反映(compare_recalc_results.py差分), `(3)` `--exclude-months` 実装。→ `docs/research/codd_dmsignal_python_strategy.md` §3.5

### Vintage 2020 OOS検証 (cmd_2228)
<!-- last_updated: 2026-04-22 cmd_2228 -->
- **ss完了**: `outputs/analysis/vintage/2020/vintage_2020_ss_*` 5成果物生成。α6は全objectiveで `alpha_positive=true`。`maximum_drawdown` が最良 (`alpha_annual=2.247561`, `beta_adj_cagr=2.637799`, `alpha_max_dd=0.093083`)。`cagr`/`max_run_up` は bear regime alpha が負で `regime_all_positive=false`。→ `queue/reports/saizo_report_cmd_2228.yaml`
- **as完了**: `outputs/analysis/vintage/2020/vintage_2020_as_*` 5成果物生成。α6は全objectiveで `alpha_positive=true`。`maximum_drawdown` が最良 (`alpha_annual=3.113478`, `beta_adj_cagr=3.621199`, `alpha_max_dd=0.117064`)。`nhf` のみ bull alpha `-0.048525` で `regime_all_positive=false`。`l2_timeline` 19行は IS短縮によるfold減少で設計内。→ `queue/reports/hayate_report_cmd_2228.yaml`
- **共通所見**: 実行入口は `scripts/analysis/alm_research/vintage_pipeline.py`。cmd本文の `outputs/scripts/vintage_pipeline.py` は stale。future contamination は `fold.oos_end <= cutoff` filter + `AssertionError` (`scripts/analysis/alm_research/vintage_pipeline.py` L160-L166付近) で担保。
- **summary+commit完了**: `outputs/analysis/vintage/2020/vintage_2020_summary.md` を新規作成。§3で ss/as alpha6 比較、§4で regime 比較を整理。`outputs/scripts/vintage_pipeline.py` → `scripts/analysis/alm_research/vintage_pipeline.py` の stale path 差分も明記。`DM-Signal` 側 commit は `742337c1`。`.gitignore` に `outputs/analysis/vintage/**/*_l0_metrics.csv` を追加し、2020/2022 の vintage 系成果物を整理。→ `queue/reports/kagemaru_report_cmd_2228.yaml`
