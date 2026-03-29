# DM-signal 研究コンテキスト
<!-- last_updated: 2026-03-29 cmd_1480 鮮度確認(実質変更なし。cmd_1463-1478はops領域) -->

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
- R26結論: 全PF65体2Dグリッド171通り(K=2-20×LB=12-60)。**最適(K*,LB*)=(6,18) Sharpe=1.492**。**Sharpe優位70.8%(121/171)、CAGR優位67.3%、MaxDD優位95.9%(164/171)**。mean Sharpe=1.402, std=0.048, peak_ratio=1.064=頑健。R24(21体)overlap99セルでR26全敗(65体=分散でSharpe水準低下。構造は頑健)。**最適K: R24=4→R25=3→R26=6（体数増でK増加傾向）。LB: R24=30→R25=24→R26=18（体数増でLB短縮傾向）。三段階(12→21→65体)全てで二段EWのSharpe/MaxDD優位構造は一貫**
- R11 M4とR2の差分: 追い風-鉄壁(M4) vs 追い風-激攻(R2)のみ。MaxDD大差(-11.5% vs -16.7%)
- TO(月次入替率): Ward K=5=19.6%, Greedy K=4=22.6%。Ward低回転で実運用有利
- R27結論(cmd_1436): **WardTwoStageEWビルディングブロック実装**。R1-R26研究結論を汎用モジュール化(`scripts/analysis/nested_fof/building_block.py`)。内部K×LBグリッドサーチで最適パラメータ自動決定。R24/R25/R26の3データセット(21体/12体/65体)で既知最適(K*,LB*)再現確認+Sharpe 1e-4以内一致。コールドスタート(データ不足時1/N EW)・k_max自動クランプ実装済み
- R27-旧PF結論(cmd_1441): **旧忍法15体+旧四神12体のWard+TwoStageEW 2Dグリッド分析**。旧忍法: K*=4,LB*=24,Sharpe=2.01,TwoStageEW優位率49.6%。旧四神: K*=4,LB*=12,Sharpe=1.55,TwoStageEW優位率76.7%。合計27体: K*=12,LB*=24,Sharpe=1.75。R25(12体,1.48)/R26(65体,1.49)より高Sharpe → `queue/archive/reports/hayate_report_cmd_1441_20260330.yaml`
- ネオ五神偵察(cmd_1442): **GLD/USO/TIPの既存4absolute資産との相関偵察**。候補-既存max|r|: GLD=0.343(最有力), USO=0.378(次点), TIP=0.769(LQD冗長→不適)。危機時: GLD=利上げ時独立(全<0.17)、USO=COVID時VIX連動(0.719)、TIP=両危機でLQD完全連動。GLD独自ドライバー(中銀/地政学/インフレ) → `queue/archive/reports/hanzo_report_cmd_1442_20260330.yaml`
