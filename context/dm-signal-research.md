# DM-signal 研究コンテキスト
<!-- last_updated: 2026-07-14 cmd_3879 -->
<!-- dm_signal_research_reflux: fingerprint=634f72ae2a89530f574cec48d157b6bd16074bc5fa35379df8b68cf3e9ebe711; mode=synced; evidence_b64=Y29udGV4dC9kbS1zaWduYWwtcmVzZWFyY2gubWQgY21kXzM4Nzlfc2FmZV9idW5kbGVfdjLntKLlvJXjgbjmnIDntYLlhajph48xODEwIFBBU1MvU0tJUDDjgahnb2xkZW4gU0hB44KS5ZCM5pyf -->
<!-- source_commit:29ea37a9 reason:cmd_3879_safe_bundle_v2_main_integration evidence:research_cmd_3879_safe_bundle_v2_entry -->

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
- L823: yotsumeはcmd_1186のOUT_DIR変更でDM家系別split GSファイルがbak化され、他6忍法と異なるファイル構造になっている（cmd_3713）

18,744パターンから3モードチャンピオン選出。SPA検定3モード全てPASS。

| モード | CAGR | MaxDD | NHR | base | top_n | 構成四神 |
|--------|------|-------|-----|------|-------|---------|
| 激攻 | 62.41% | -18.45% | 59.06% | 18M | top1 | 常勝青龍,常勝朱雀,鉄壁玄武,激攻白虎 |
| 鉄壁 | 54.84% | -15.87% | 53.02% | 18M | top2 | 常勝青龍,常勝朱雀,鉄壁白虎,激攻玄武 |
| 常勝 | 46.80% | -32.87% | 63.98% | 6M | top2 | 常勝朱雀,鉄壁白虎,鉄壁玄武,激攻白虎 |

既存忍法比較: 四つ目は性能レンジ内(激攻CAGR 62.41%は変わり身62.25%同水準)。突出優位なし。
- L413: DM7+ XLU1銘柄ではtop_n軸が冗長(top_n=1とtop_n=2が完全同一リターン)。48→24体に圧縮可能（cmd_1078）
- L493: 四つ目(MultiView)忍法のnumpy再実装で4窓union+タイミングオフセットに不一致リスク（cmd_1410）
- **新四つ目(WeightedMultiView)GS完了(cmd_3386→3388)**: 45150パターン・42秒・147/147月次突合一致。根因教訓: universe yamlのsource_type=local_sqliteは本番PostgreSQLと入力が異なる→UUID完備でもDB経路に切替必須。open-to-open比較が正道(PI-008)。→ [[cmd_3388_根因特定+0不一致達成]] → `docs/research/cmd_3387_weighted_yotsume_full.md`
- CoDD設計書: [[cmd-284]](四つ目GSスクリプト), [[champion-selector]](GS champion選出ロジック) → `docs/research/cmd_1991_codd_extract/modules/`

---

## 研究関連教訓索引 (projects/dm-signal/lessons.yaml)

### 影響算定/再現性

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L146 | 最新引け軸を使う比較ではlatest_close_dateを先に確定し、軸重複を判定する | cmd_495 |
| L145 | FoF差分はholding_signal文字列ではなく、展開後ticker×weightで比較する | cmd_495 |
| L186 | 日次比較偵察は対象日N点固定に加えMAX(date)確認を同時実施すると欠落原因を誤診しにくい | recon |
| L830 | pf_L0規模(N=12程度)の小標本ランキング分析では両軸quantile交差分類が機能せず、tie処理は平均順位化が必須 | cmd_3768_gap_method |
| L874 | exact差分オラクルは比較対象フィールドの機能的意味(downstream消費有無)を先に検証してから比較契約を作る | cmd_karo_recon_cmd3851_A |

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
| L685 | 別layerへ既存selectorを流用する前に固定パスと突合分岐を確認する | cmd_2412 |
| L686 | robustness実行前にSQLite月次保存形式を確認する | cmd_2413 |
| L693 | day lookback指定と月次return入力が混在する研究cmdでは時間解像度の写像を成果物へ明記 | cmd_2436 |
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
| L667 | GS robustnessのlookback_index軸では連動メタデータ列(lookback_label等)を固定条件から外す | cmd_2357 |
| L674 | gs_grid_robustnessのL1軸検証では従属ラベル列(lookback_label/base_label等)も可変扱いにせよ | cmd_2391 |

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
| L699 | holding_signalパリティ検証ではNULL行を比較対象から除外する | cmd_2448 |

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
→ 詳細: `docs/research/dm-signal-research-shin-shijin-v2.md`

v2全面再設計: DNA事前制約+データ駆動lookback→12体。R28 Ward ClSel研究(27cmd)完結。
**確定**: K=4 Momentum唯一3条件PASS。β調整後超越条件全FAIL(ClSel αなし)。Ward FoFはPD-004でkeep。
- 確定パラメータ表・R10-R27・パリティ検証・奥義-シン忍法(cmd_1822/1840/1844)・GS高速化第2世代(79x)・CPCV/相関/パターン分析 → `docs/research/dm-signal-research-shin-shijin-v2.md`
- L750: シン四神12体は全ペアで最悪時相関≈1.0: 同一5ticker宇宙内の分散は最悪時に消える（cmd_3425）
- L751: 奥義(FoF of FoF)のmax相関はシン四神同様に≒1.0。根因は戦略同質性（cmd_3426）
- L752: 相関乖離分析の閾値設計: σベース閾値は同一母集団(層別)でのみ有効。混成母集団では分散拡大でシグナル消失（cmd_3430）
- L753: DM-Signalシン四神にMomentum Turning Points適用: Bull偏重でBear/Rebound観測不足→新BB不採用（cmd_3431）
- L825: GSパターン相関分析でサンプル33%→全量100%移行時、ペアにより相関の安定性が大きく異なる(CAGR系ペアは安定、AvgUWPとの組合せは不安定)（cmd_3716）
- L826: 指標選出ツールは「グローバル1チャンピオン」と「グループ別チャンピオン」の粒度差を明示せよ（cmd_3756）

---

## §28-§35. 前処理研究・ALM設計（2026-04-01〜2026-04-22）
→ 詳細: `docs/research/dm-signal-research-alm.md`

§29: 金融ML知識辞書61エントリ拡充 + FDA Smoothing研究(§29)。§30: EMA/L1 OOS検証(過適合判定、PBO>0.5)。
§31: ALMファミリー別研究。§32: ALM L0×忍法7種比較。§33: 6目的関数横比較。§34: 41/42 ROBUST。
§35: ALM本番組込み設計(殿裁定2026-04-06)→L0パリティ確定→L2 2×2因子分析→L3 2体EW(α>L2)→CoDD高速化(5本完了)。
- CoDD設計書: [[l1-alm-wf-engine]](ALM L1 WFエンジン), [[wf-runner]](WFランナー), [[cmd-1826-memory-analysis]](メモリ分析), [[cmd-1847-neighbor-analysis]](近傍パラメータ分析), [[cmd-1869-2x2-factor-analysis]](2×2因子分析), [[cmd-1870-beta-adjusted-2x2]](β調整2×2分析) → `docs/research/cmd_1991_codd_extract/modules/`
Vintage 2020 OOS検証(cmd_2228): ss/as全objectiveでα6 positive。

## §36. 金融ML知識辞書 2026-04-30 追加9件（cmd_2426〜cmd_2434）

→ 一覧SSOT: `/mnt/c/Python_app/DM-signal/docs/research/knowledge-base/index.md`

2026-04-30時点で `docs/research/knowledge-base/methods/` に追加・反映済みの9件。DM-Signal適用時は各methodのLayer/Phaseと、DM PF=L0意思決定系列・月次データ制約を照合してから採否判定する。

| ID | エントリ | 結論(1行) | 参照 |
|----|---------|-----------|------|
| M77 | X-Trend Few-Shot Learning | GP変化点で過去レジームcontextを作り、cross-attentionで新レジーム・未見資産へ少数データ適応するL2-L3候補。 | `docs/research/knowledge-base/methods/x-trend-few-shot.md` |
| M78 | Momentum Transformer | Decoder-Only TFTをDMN position sizingへ接続し、VSN+masked attentionで説明可能性を持つ深層momentum候補。 | `docs/research/knowledge-base/methods/momentum-transformer.md` |
| M20 | Network Momentum | Levy area/DTWのlead-lag行列をgraph learningで疎adjacency化し、先行市場TSMOMを集約するL2拡張。 | `docs/research/knowledge-base/methods/network-momentum.md` |
| M79 | DeepUnifiedMom | MMoE+MTLでfast/medium/slow TSMOMを同時学習し、CANで3袖配分する統一momentum portfolio。 | `docs/research/knowledge-base/methods/deep-unified-momentum.md` |
| M80 | VAA / BAA | 13612W breadth momentum と canary universe でoffensive/defensiveを切替えるKeller系TAA。 | `docs/research/knowledge-base/methods/vigilant-bold-asset-allocation.md` |
| M81 | Hierarchical Momentum | 相関距離クラスタごとに12M momentum最大銘柄を選び、正momentum銘柄へ等配分するロングオンリーPF構築。 | `docs/research/knowledge-base/methods/hierarchical-momentum.md` |
| M82 | Factor Momentum | 既存factor portfolioの過去1年return符号でlong/short月次rotationし、個別UMDをfactor自己相関で説明する。 | `docs/research/knowledge-base/methods/factor-momentum.md` |
| M83 | ADTS / CADTS Bandit Portfolio | discount+sliding-window Thompson Samplingで非定常stock pickingを行い、離散weight superarmへ拡張する。 | `docs/research/knowledge-base/methods/bandit-portfolio-adts.md` |
| M84 | Expert Aggregation WASA | awake expertだけを指数重みで集約し、specialized CRP poolから距離閾値で助言を選ぶonline portfolio手法。 | `docs/research/knowledge-base/methods/expert-aggregation-wasa.md` |
| S06 | Tail Risk Hedging: Put vs Trend | OTM Putは長期負リターンの保険コスト、Multi-Asset Trendは長期正リターン+テールヘッジ。急速下落はPut有利、緩やかな下落はTrend有利。 | `docs/research/knowledge-base/sources/aqr-ilmanen-2021-tail-risk-hedging-put-vs-trend.md` |

## §DMS-TVP レイヤー別動的選出 研究進捗 (2026-04-30)

**目的**: 各レイヤーから毎月1体を動的に選出し毎月リバランス。
**手法**: Levy & Lopes (2021) DMS-TVP。一次知識=M31。解釈層=`dm-signal/dms-tvp-layer-selection-design.md`

### lookback 5帯域(殿裁定確定)

帯域制約: 超短期10-20D / 短期1-3M / 中期4-6M / 長期7-10M / 超長期11-15M
選定値: [10D, 21D, 84D, 210D, 315D]。cmd_2435(CAGR分布分析)→殿修正→軍師追体験→確定。

### バックテスト結果

| cmd | 内容 | 結果 |
|-----|------|------|
| cmd_2436 | 各PF個別lookback選択 | 設計誤り(殿の目的と不一致) |
| cmd_2437 | L0 12体→1体DMS(α=0.99) | EWに劣後。切替3回/110ヶ月 |
| cmd_2438 | α感度分析(0.90/0.95/0.99) | 全6組合せEWに劣後。α=0.90が最善(CAGR45.9%) |
| cmd_2439 | **Ave 3体選出(進行中)** | 3レイヤー×2lookbackセット。結果待ち |

### Aveシリーズ(殿発案)

同モードPFをファミリー/忍法間でEW均等保有。12体/21体の選択問題を3体(激攻/常勝/鉄壁)に単純化。

| Ave | CAGR | MaxDD | α-CAGR | α-Calmar |
|-----|------|-------|--------|---------|
| Ave四神-激攻 | 47.2% | -37.9% | 27.8% | 1.484 |
| Ave忍法-激攻 | 76.4% | -32.9% | 41.6% | 2.086 |
| Ave奥義-激攻 | 94.3% | -23.8% | 58.9% | 3.702 |
| Ave奥義-常勝 | 69.0% | -30.6% | 40.9% | **4.459** |
| Ave奥義-鉄壁 | 57.0% | -12.9% | 31.8% | 1.880 |

全9体α-CAGR>0。詳細→gist: https://gist.github.com/simokitafresh/97bf38e764ec09070a50f91fd250a1fa
設計追体験→gist: https://gist.github.com/simokitafresh/732d31d0ec93a38b8398ab51cade0f6a

### 2026-05 追記

- cmd_2439 Ave DMS lookbacksは2026-04-30に再実行済み(commit d5acc4f7)。結果確認時は最新成果物を参照する
- cmd_2440 combo exhaustive search、cmd_2442 single-period alignment修正、cmd_2449 combo stability analysis、cmd_2450 hiougi registration artifactsが追加済み
- 2026-05-02 commit 69d7afdbでDMS-TVP layer selection設計書とcmd_2424登録成果物がまとめてコミット済み。登録CSV/summaryは`outputs/registration/cmd_2424/`

## §37. 用語辞書・投資知識リンク 2026-05更新

| 領域 | 結論 | 参照 |
|------|------|------|
| terminology | DM-Signal terminology / disambiguationを拡張。UWP/PTU/MaxDD UWPなど衝突しやすい語はcanonical定義を確認する | commits a39d6d19, ff142314, 40a22dc6; `/mnt/c/Python_app/DM-signal/context/dm-signal-terminology.md` |
| knowledge links | method全件へ関連投資知識リンクを接続済み。研究時は単独methodだけでなくリンク先methodも候補に含める | cmd_3015; `/mnt/c/Python_app/DM-signal/docs/research/knowledge-base/methods/` |
| marketing research outputs | note記事/weekly reportsはDM-Signal知識の公開向け再構成。研究正本ではないが説明・商品設計の文脈確認に使える | commit 1a5f5149; `marketing-director/content/` |

---

## §38. サイズ調整研究 (cmd_3218/3220/3224, 2026-06-08)

→ 詳細資料: `docs/research/cmd_3218_サイズ調整バックテスト.md` / `docs/research/cmd_3220_7戦略バックテスト.md` / `docs/research/cmd_3224_V8過適合検証.md`

### cmd_3218: 危険度スコアによるサイズ調整バックテスト (78体)

**結論: 全体サイズ調整は非推奨。HIGH月平均+3.3%のため削減コスト>改善効果。** → L726

| 指標 | ベースライン | 調整後 | 差分 |
|------|------------|--------|------|
| CAGR | 54.67% | 47.11% | ▲7.56% |
| MaxDD | -26.82% | -26.82% | 変化なし |
| HIGH月平均リターン | — | +3.3% | 機会損失大 |

- 秘奥義のみCalmar改善(5.742→6.460)、MaxDD改善(-2.85%)
- MEDIUMスコア月(-1.0%)が最も危険。HIGH(+3.3%)より精度高い可能性
- スクリプト: `scripts/cmd_3218_size_adjustment_backtest.py`

### cmd_3220: 7戦略サイズ調整(100%/80%)バックテスト

**結論: 全7戦略でΔCAGR < 0。CAGRコストがMaxDD改善を上回り採用不適。** 最良はD10-VIX>25。

| 戦略 | ΔCAGR | ΔMaxDD | ΔSharpe | 評価 |
|------|-------|--------|---------|------|
| D10-VIX>25 | -2.88% | +3.55% | +0.053 | 最良(ΔSharpe正) |
| D11-実現ボラ | -8.18% | +4.28% | +0.028 | CAGRコスト大 |
| E14-HMM | -4.33% | 0% | +0.026 | MaxDD改善なし |
| F15-弱月暦 | -1.78% | +0.83% | +0.006 | 最小コスト |

- スクリプト: `scripts/cmd_3220_7strategy_backtest.py`
- 結果JSON: `docs/research/cmd_3220_7戦略バックテスト.json`

### cmd_3224: V8_T25_MA50 過適合検証(OOS+サブ期間+ローリング3年窓)

**結論: 過適合リスクあり。ローリングSortino勝率5/14(36%)で安定性不足。採用要慎重。**

| 検証 | 結果 | 判定 |
|------|------|------|
| OOS Sortino保持率 | 170.4%(テスト/訓練) | ✓ 過適合でない |
| OOS Calmar保持率 | 226.1% | ✓ 過適合でない |
| ローリング3年 Sortino勝率 | 5/14(36%) | ✗ 安定性不足 |
| サブ期間(COVID) | ΔSortino+0.517 | ✓ 効果あり |
| サブ期間(金利上昇2022) | ΔSortino-0.111 | ✗ 逆効果 |

- 判定基準: OOS保持率≥70% → PASS, ローリング勝率≥50% → 安定 (今回: OOS PASS/ローリングFAIL)
- スクリプト: `scripts/cmd_3224_v8_overfitting_check.py`

### §38教訓（cmd_3215〜3220系）

- L724: deterioration_snapshotsは2026-03以降231件のみ。過去損失月(2010〜2025)分析はVIX+ETRリターンで代替（cmd_3215）
- L725: 前月DTB3急騰(大負前月+39.5% vs 大勝前月+10.2%, p≈0)は全レイヤー共通の大負★★★シグナル（cmd_3217）
- L726: HIGH月翌月平均+3.4%により全体サイズ削減はコスト>改善で非推奨（cmd_3218。§38本文の結論と同一）
- L728: HMMは月次fitで全サンプル1状態のデジェネレート発生。日次fitで訓練→月次集約(50%ルール)が必須（cmd_3220。L727統合）

---

## §39. レイヤー別V8 + マネージドボラ研究 (cmd_3225, 2026-06-11)

→ source commit: `096dd038` (DM-Signal) / 公開向け再構成: `marketing-director/content/articles/note-layered-alpha-not-overfitting.md`

**結論: V8の効果は一枚岩ではない。レイヤー別選出とマネージドボラは「過適合ではなく市場状態依存のα」として説明可能だが、研究正本はmarketing記事ではなく分析commit/実装出力を参照すること。**

| 対象 | 研究上の扱い | 反映理由 |
|------|--------------|----------|
| レイヤー別V8分析 | 既存§38のVIX/サイズ調整研究の後続 | `096dd038` がcmd_3225実装を含む |
| managed volatility | V8閾値単体ではなくリスク制御との組合せ候補 | note記事は説明資料、判断時は実装/出力を一次確認 |
| marketing weekly/note | 研究正本ではない | コンテキスト説明の補助に限定 |
| `docs/research/core-api-endpoints.md` | API索引 | research層よりcore/frontend/ops側で参照 |
| `tasks/lessons.md` | 教訓正本 | research結論ではなくlesson系に還流 |

---

## §40. MTD Daily Returns UX / 速報行 (cmd_3332, 2026-06-12)

→ 正本: `/mnt/c/Python_app/DM-signal/docs/spec/mtd-daily-returns-ux.md` / 実装commit: `90331d88` / 本番検証: `a907c26a`

**結論: OPENモードは翌営業日付の速報行を持つ。確定月次研究やCLOSEモード比較では `is_preliminary=true` を除外し、OPENモードのUX/当月確認だけで暫定値として扱う。**

| 項目 | 研究上の扱い | 根拠 |
|------|--------------|------|
| `is_preliminary=true` | 確定系列ではない | close→翌open代理値で翌営業日付の速報行を生成 |
| CLOSEモード | 速報行なし | `/api/mtd` 実装でOPEN用途の暫定表示として扱う |
| 本番検証 | OPEN/CLOSEスクショ+summary JSONで確認済み | `outputs/prod_checks/cmd_3332/` |
| 月次/GS/パリティ分析 | 除外または別系列明示 | 確定monthly returnと混ぜるとpartial/MTD差分を誤診する |
| 速報行の日付ラベル | 次カレンダー平日の仮置きでよい | 市場カレンダーSSOTなし。Juneteenth等の休場日は `prices`/`ticker_daily_returns` に株価が無いことで判定し、ラベル補正のためだけに市場カレンダー実装を増やさない |

2026-06-20殿裁定: `06/19 ⚡` のような速報行ラベルは市場営業日SSOTではなく仮置きなので、Juneteenth休場を理由に `06/22 ⚡` へ補正する修正は不要。秘奥義-激攻の検算では 2026-06-18 open→close 加重リターン `+1.0088295297%` を 06/18 OPEN MTDへ掛け、`06/19 ⚡` OPEN暫定MTD `-2.5477875184%` が本番APIと差分 `0.0` で一致。`06/19` の株価データは本番DBに存在しない。
因果: [[殿裁定20260620_MTD速報行仮置き]] -> [[Juneteenth休場ラベル問題]] -> [[市場カレンダーなしでは速報行日付を補正しない]]

---

## §41. 相関レジーム研究 (cmd_3425-3431, 2026-06-17)

→ 詳細資料: `DM-signal/docs/research/knowledge-base/experiments/correlation-regime-detection-20260617.md`

**結論: デュアルモメンタムPFは最悪時に全ペアで相関≈1.0。戦略同質性が根因。乖離リフト3-4xは有望だが偽陽性70%。deterioration HIGH判定は逆機能(翌月+8.04%平均回帰)。**

| # | 知見 | 結論(1-2行) | 出典 |
|---|------|------------|------|
| 1 | max相関=戦略同質性 | L0/L1/L2全ペアmax相関≈1.0(0.9956-1.0000)。銘柄宇宙ではなく同一市場環境下の戦略同質性が根因。銘柄レベルGLD×TMVはmax0.26/avg-0.30(真の負相関) | cmd_3425/3426 |
| 2 | 高相関=バブル | avg_corr≥0.60時は上昇率65-69%/日次+0.21-0.36%。高相関は危機ではなくバブル(上昇)シグナル | cmd_3427 |
| 3 | 乖離リフト3-4x・偽陽性70% | 短期(2-4M)-長期(18-24M)乖離でリフト3-4x。偽陽性率70%で実用困難。層別同質母集団が有効。COVID 2020-03は3M前先行検出成功 | cmd_3427/3428 |
| 4 | deterioration逆機能 | DETERIORATING判定→翌月平均+8.04%(平均回帰反発)。HIGH判定は逆機能。WATCH/EARLY_WARNING(n=4)偽陽性25%で有望だがサンプル不足 | cmd_3429 |
| 5 | σ閾値混成母集団不機能 | 異層混合でstd拡大(0.25-0.39)→μ+2σがデータ最大値に近接しシグナル0-1件。固定閾値(0.10)・同質母集団が安定 | cmd_3430 |
| 6 | リスクベースBB不適 | VolScal/CVaR/リスクパリティはリターン差活用構造のDM-Signalに方向が違う(等リターン前提・不適) | cmd_3430 |
| 7 | Turning Points BB不採用 | Bull 80.5%偏重でBear/Rebound観測不足(3件/1件)。高品質PFに転換点BBを適用すると情報量ゼロ・過適合リスクHIGH | cmd_3431 |

---

## §42. 75体+SPY堅牢性全量検証 (cmd_3515, 2026-06-23)

cmd_3512-3514で整備した5本のtrial scripts(IS/OOS/Expanding/WF/Regime)を全レイヤー75体+SPYに拡張し全量検証。
- **結果**: 375/375比較行 + SPY 5/5。欠損0。PASS 308 / FAIL 67 (82.1% PASS)
- **レイヤー別PASS率**: L0(シン四神)=55%, L1(シン忍法)=75%, L2(奥義)=97%, L3(秘奥義)=98%
- **成果物**: `→ /mnt/c/Python_app/DM-signal/outputs/analysis/grid_search_robustness/cmd_3515/summary.json`, `summary.md`
- **教訓**: L768(L1 kasoku_diff: /mnt/c上のSQLiteはp9停滞→/tmpへbyteコピーで回避)

### cmd_3517/3518: α6 robustness全6項目化 (2026-06-23)

cmd_3515はα6のうち3項目のみで「全量探索完了」と扱っていたため、cmd_3517で道具を修正し、cmd_3518で全量再実行。α6はCAGR/NHF/MaxDD/MRU/Calmar/Avg UWPの6項目。
- 設計・経緯: `/mnt/c/Python_app/DM-signal/docs/research/plan_alpha6_robustness_verification.md`
- 実装: `scripts/analysis/grid_search/robustness_common.py`, `scripts/analysis/grid_search/trial_wf.py`
- 成果物: `/mnt/c/Python_app/DM-signal/outputs/analysis/grid_search_robustness/cmd_3518/`
- 注意: 今後「α6 robustness」を参照する場合、cmd_3515単独では3/6項目不足。cmd_3517/3518以後の成果物を正本にする。

## §43. Continuity-risk metrics (cmd_3524/3525, 2026-06-25)

cmd_3524で堅牢性trial JSONへ5つの連続性リスク指標を追加し、cmd_3525でpandas基準に整合。対象はL0/L1/L2の378行。

| 指標 | 定義 | 用途 |
|------|------|------|
| VDrag | arithmetic mean - geometric mean | volatility dragの大きさ |
| Skewness | Fisher-adjusted skewness | tail非対称性 |
| Kurtosis | Fisher-adjusted excess kurtosis | fat-tail度 |
| MinMo | `(1.96*sigma/mu)^2` | 必要月数の目安 |
| MaxConsecLoss | 最大連続マイナス月数 | 連敗耐性 |

- 成果物: `/mnt/c/Python_app/DM-signal/outputs/analysis/grid_search_robustness/cmd_3525_continuity_metrics.md`
- source_dir: `/mnt/c/Python_app/DM-signal/outputs/analysis/grid_search_robustness/cmd_3525`
- 実装: `scripts/analysis/grid_search/cmd_3524_continuity_metrics_report.py`, `scripts/analysis/grid_search/robustness_common.py`

## §44. fullrecalculate冪等性証明 (cmd_3546, 2026-06-26)

本番fullrecalculate(portfolio)前後で signals 102PF / metrics 102PF / DB portfolio_metrics 204行が完全一致。差分0、run_id `20260625_194042`、elapsed 352.5s、verdict PASS。
- 成果物: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3546/diff_result_v4_20260625_194638.json`
- 検証スクリプト: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3546/snapshot_and_verify_v4.py`

## §45. 2026-06-27 source freshness照合

GA-147原因: `dm-signal-research.md`のlast_updatedは2026-06-26で、2026-06-26以後にresearch pathspec対象commitが増加したため`gate_context_freshness.sh`がsource commits ALERTを出した。一次情報分類では、研究正本に反映すべき差分はcmd_3546 fullrecalculate冪等性証明で、§44に反映済み。他の差分はCompare Returns API/frontend/MTD性能・表示修正・docs spec/lessonで、研究索引への恒久知識追記は不要。
横展開候補: 同gateで`obsidian-link-principles.md`もsource commits ALERT継続。防御層候補: context_freshness hotfixタスクへsource commit要約だけでなく、context別pathspec hit件数と「研究正本/実装/補助docs/lesson」の分類欄を自動注入する。

## §46. L1+ BB直列拡張実験 (cmd_3490/3493, 2026-06-22)

殿構想(2026-06-22): L1のselection blockを複数BB直列に拡張(L1+)。**実験完了済み。**

| 項目 | 結果 |
|------|------|
| 道具 | `scripts/analysis/grid_search/run_l1plus_backtest.py` (cmd_3490) |
| 全量実験 | 441パターン一括実行完了。343秒、192MB RSS (cmd_3493) |
| 結果CSV | `outputs/analysis/cmd_3493_l1plus_backtest/cmd_3493_l1plus_batch_results.csv` |
| 月次CSV | `outputs/analysis/cmd_3493_l1plus_backtest/cmd_3493_l1plus_batch_monthly_returns.csv` |
| 計測レポート | `docs/research/cmd_3493_l1plus_batch_all_measurement.md` |

**TOP3(α6指標):**

| rank | BB1 × BB2 | CAGR | MaxDD | Calmar | NHF |
|---:|---|---:|---:|---:|---:|
| 1 | 追い風-鉄壁 × 抜き身-激攻 | 74.9% | -31.9% | 2.34 | 0.553 |
| 2 | 追い風-激攻 × 抜き身-常勝 | 74.7% | -51.0% | 1.46 | 0.537 |
| 3 | 変わり身-鉄壁 × 追い風-激攻 | 73.6% | -26.1% | 2.82 | 0.608 |

→ 詳細: `docs/research/cmd_3490_l1plus_backtest_measurement.md`, `docs/research/cmd_3493_l1plus_batch_all_measurement.md`

## §47. Lighthouse mobile周回計測原票 (cmd_3653, 2026-07-02)

DM-Signal本番FEのmobile実運用条件計測は、`scripts/mobile_lighthouse_round.py`でCDP 9222隔離プロファイル起動・admin_session注入・Lighthouse mobile条件固定・manifest付き原票保存を単一コマンド化済み。周回原票は `docs/research/lighthouse_rounds/round_YYYYMMDD_{label}/` に保存し、manifestに計測時刻/Chrome起動条件/throttling/target_urls/deploy_commit_hash/executorを残す。
- 初回原票: `docs/research/lighthouse_rounds/round_20260702_cmd3653_mobile_pf/manifest.json`
- 初回JSON: `docs/research/lighthouse_rounds/round_20260702_cmd3653_mobile_pf/monthly-returns_cG9ydGZvbG.json`
- 設計正本: `docs/design/dm-signal-lighthouse-improvement-design.md` §5.2/§5.3
- cmd_3670再計測: `docs/research/lighthouse_rounds/round_20260703_cmd3670_monthly_returns_virtual_after/`。monthly-returns PF指定でPerformance 68→96、TBT 2230→90ms、Bootup 23859→436ms。PF UUID入りbackend requestは記録済みだがHTTP 401のため、実データ表示完了の絶対証明ではなくPF propagation証拠として扱う。
- cmd_3671再計測: `docs/research/lighthouse_rounds/round_20260703_cmd3671_monthly_trade/`。monthly-trade PF指定でPerformance 73→96、TBT 1613→68ms、Main-thread 10393→1415ms。PF UUID入りbackend requestは記録済みだがHTTP 401のため、実データ表示完了の絶対証明ではなくPF propagation証拠として扱う。
- cmd_3672道具改修: `scripts/mobile_lighthouse_round.py` がbackend originにもadmin_session cookieを注入し、manifest `pages[].api_data_evidence` と `pages[].dom_evidence` にデータ到達+描画完了証拠を保存する。試走原票 `docs/research/lighthouse_rounds/round_20260703_cmd3672_auth_data_proof_monthly_returns/` ではPF指定API Fetch 200・transfer_size 3091・resource_size 9335、DOM table 12行、No data/Loadingなしを確認済み。
- cmd_3673正式round: `docs/research/lighthouse_rounds/round_20260703_cmd3673_monthly_data_proof/` と補完 `round_20260703_cmd3673_monthly_trade_data_proof_single/`。実データ描画条件でmonthly-returns Performance 74/TBT 167ms/Bootup 9249ms/Main-thread 11031ms、monthly-trade Performance 80/TBT 62ms/Bootup 9407ms/Main-thread 11018ms。monthly-tradeのformal roundはselected PF transfer 0のため、fresh profile単独roundでFetch 200・transfer_size 3948・resource_size 21433を補完確認。

## §48. 全忍法GS少数実行・既存SQLiteパリティ確認 (cmd_3694, 2026-07-06)

`--pattern-limit`をGS runner 7本(bunshin/oikaze/nukimi/kawarimi/kasoku_diff/kasoku_ratio/weighted_yotsume)に追加し、少数実行(`--pattern-limit 3`)で全て exit 0を確認(AC1 PASS)。既存GS SQLiteとのpattern_idパリティ突合はAC2 FAIL: 最大差分0.0873〜0.319。原因は`--pattern-limit`実装不備ではなく、既存成果物のdata_period_end(〜2026-06)と今回`okugi_l3_168.yaml`入力のdata_period_end(2026-07)の系列差分。2026-07-05の価格データソース移行(yfinance adjusted→EODHD raw+自前調整、`docs/design/gs-recalibration-plan.md`)により全レイヤー再GSが必要と記録されており、本パリティFAILはその症状の一つ。
→ 詳細: `docs/research/cmd_3694_ninpo_gs_small_run_parity.md`

- L828: GS DTB3ローリング計算と本番PipelineEngineのDTB3参照は生値一致でも暦解像度が異なりthreshold_band境界(±2.3e-5程度)で稀にフリップする。GS側=取引日リサンプル系列のNトレーディング日前、本番側=_calculate_economic_indicator_momentumのN日前照会（cmd_3755、PI-028）
- L834: run_077_*.pyをモジュールimportで診断スクリプト再利用時はsys.argvでuniverseを明示指定せよ（cmd_karo_hotfix_yotsume_bootstrap_preflight_202607081515）
- L837: local_sqlite loaderはmonthly_blobと重複pattern_idを標準対応すべき（cmd_3774）
- L838: run_077 monthly blob chunk差は全量GS総時間を支配する（cmd_3775）
- L839: GS blob月次md5はNaN payload差を避けarray_equalで検証する（cmd_3778）

GA-181分類メモ(source commits since last_updated=2026-07-03の3件): 上記45f00c6bのみ研究正本反映対象。`a3059891`(tasks/lessons.md退役8行)・`894736d4`(tasks/lessons.md cmd_3686教訓登録26行)はlesson運用のみで研究索引への追記対象外(L787準拠)。

## §49. GS目的関数相関分析 (cmd_3713-3716, 2026-07-07)

| cmd | 対象 | 結論 |
|-----|------|------|
| cmd_3713 | 7忍法×4DM系の6指標チャンピオン月次リターン相関 | 現行3目的(cagr/maxdd/new_high_ratio)は6C3=20通り中8位。チャンピオン返り値類似度では中位上位 |
| cmd_3714 | 全パターン733,392件の13指標スカラー値相関、13C3=286通り | 現行3目的は148位/286(avg_abs_corr=0.5141)。cagr×new_high_ratio相関0.913が独立性を阻害。最良はkurtosis+vdrag+avg_uwp(avg_abs_corr=0.1499) |
| cmd_3716 | rolling_1y_low追加後の14指標全量相関、14C3=364通り | 候補B(cagr/worst_year_return/avg_uwp)推薦維持。Rolling1yLow×AvgUWPは部分値-0.547→全量-0.444へ変化し、AvgUWP系ペアはサンプル感度が高い |

実装注意: `grid_monthly_fast.csv` は全パターンで先頭連続NaN(burn-in区間)を持つ。月次CSVからmean/prod/cumprod系の追加指標を作る時は `nanmean`、`log1p+nansum`、burn-in中立値埋めを使う。素朴なmean/prod/cumprodはsortino/vdrag/avg_uwp/mruを99.8% NaN化する。
→ 詳細: `outputs/analysis/cmd_3713_metric_combo_correlation_report.md`, `outputs/analysis/cmd_3714_metric13_correlation_report.md`, `docs/research/gs_3objective_correlation_analysis_20260707.md`

## §50. L0/シン方式チャンピオン比較・本番採用逆算 (cmd_3755-3767, 2026-07-08)

- cmd_3755-3763: `shin_shijin_l1_gs.py`へthreshold_band三状態を追加し、L0/シン方式4DM系×3モードで旧基準(CAGR/MaxDD/NHF)と新基準(CAGR/WorstYear/AvgUWP, PD-060)のチャンピオンを比較。現行本番4体のlookbackはtrading_days複数項加重で、標準GSカタログとは完全一致しないため、価格・バンド変更影響とパラメータ空間差分は直接分離できない。
- cmd_3756/3762: 旧基準と新基準の選別結果は`outputs/analysis/cmd_3756_champion_selection_summary.md`、`outputs/analysis/cmd_3762_shin_champion_selection_summary.md`、`outputs/analysis/cmd_3762_prod_champion_percentile_note.md`を正本とする。
- cmd_3767: 本番active 102PFの構成からpf_L0採用を逆算。12体すべて上位PFに採用済みで、未採用二値ではなく採用頻度をpriorにする。unique parent上位は白虎-鉄壁61、青龍-激攻60、玄武-激攻59、青龍-鉄壁57。朱雀-鉄壁だけ6件で外れ値。
- 次段仮説: 青龍/玄武の高採用部品と白虎鉄壁を核にし、朱雀鉄壁を除外または別役割にする。構成採用と月次holding実選択頻度は未分離。
→ 詳細: `docs/research/cmd_3767_pf_l0_adoption_reverse_features.md`, `docs/research/cmd_3767_pf_l0_adoption_summary.csv`, `outputs/analysis/cmd_3763_c1_c4_results.json`
- **無効化注記(2026-07-09)**: cmd_3755-3763のL0 GS(20260708実行分)は本番未同期のGS専用EODHDローカルスナップショット価格を使用しており、cmd_3785で本番pricesとパリティが取れていないことが判明、殿裁定(2026-07-09 13:40)で「違う株価データで行ったGSは全て無効」と裁定された。cmd_3767(pf_L0採用逆算)は本番configの採用実績分析であり価格非依存のため無効化対象外。C1-C4比較の**定性的傾向**はcmd_3797(D1同期済みprices再実行)で概ね再現確認済みだが、**数値そのもの(cagr/maxdd等の具体値)は同一視するな**。最新の正本はcmd_3797 → `docs/research/cmd_3797_phase_a_l0.md`

## §51. 新L0-L3チャンピオン群 α6堅牢性検証 (cmd_3780, 2026-07-08)

工程2で選出した新チャンピオン75体(L0=12, L1=21, L2=21, L3=21)について、4視点(IS/OOS/Expanding/WF)+レジーム3種(Bull/Neutral/Bear)×α6(CAGR/NHF/MaxDD/MRU/Calmar/AvgUWP)を全量算出。出力は75×7×6=3,150 metric rows、coverage 525 rows、nonfinite 0。初版はExpanding/WFが固定同一月集合スライスで450/450完全一致し4視点が実質3視点に縮退していたため、`cmd_karo_hotfix_cmd3780_expanding_wf_rework_202607082310`で動的trial評価へ修正し、完全一致35/450へ縮小。工程4入替の殿裁定材料は修正後commit `edb296cfebe45730657e6fa30fb36212981a796f` を正とする。

計画書正本は本陣 `docs/research/plan_alpha6_band_champions_verification_20260708.md`。DM-Signal側に同名ファイルはない。
→ 詳細: `docs/research/cmd_3780_alpha6_band_champions_robustness.md`, `outputs/analysis/cmd_3780_alpha6_band_champions_input_contract.json`, `outputs/analysis/cmd_3780_alpha6_band_champions_robustness.json`, `outputs/analysis/cmd_3780_alpha6_band_champions_coverage.csv`

## §52. GA-206分類注記: PF入替執行ログは運用ドメイン (cmd_3783-3785, 2026-07-09)

cmd_3783(本番PFバックアップ)/cmd_3784(削除・登録計画)/cmd_3785(削除・登録実行)は`docs/research/`配下にbackup_report/deletion_log/registration_log/parity_verification/db_api_verification等の運用実行ログを生成したが、GS/シグナル分析の研究成果ではない。運用ドメインとして`context/dm-signal-ops.md`(last_updated=2026-07-09 cmd_3784)側で既に追跡済み。本節への研究内容追加は不要と判定し、GA-206(context_freshness ALERT)への回答として記録する。cmd_3785は実行結果を失敗記録として残しており(`docs/research/cmd_3785_execution_report.md`)、原因調査はcmd_karo_recon_cmd3785_parity_rootcause系の別cmdが対応中。
→ 参照: `context/dm-signal-ops.md`, `docs/research/cmd_3785_execution_report.md`

## §53. Monthly Trade matched_weight=0.5再分類 (cmd_3808-3809, 2026-07-10)

- cmd_3808の「partial/non-Cash weight偽陽性」分類は殿の理論制約(Cashなし、band時relative/safe haven各50%、weights合計1.0)で再検証対象となり、cmd_3809で本番DB/API/Renderログ/コード行を照合した。
- 結論: band片側欠落ではない。対象PF「奥義-GS-変わり身-鉄壁」の本番DB weightsは2025-12/2026-01/2026-06いずれも合計1.0、`signal_decision_ledger`該当なし。`matched_weight=0.5`はFoF表示展開後に表示weightsとmatched_weightが別基準で残る不整合疑い。
- 正本: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3809_band_weights_half_bug.md`。運用修正候補は`context/dm-signal-ops.md` §60。

## §54. Stage A/vectorized経路再設計 v1.1 (cmd_3840, 2026-07-11)

- 結論: 決定性実証はDM-safe 1PF・先頭5,000行・単一プロセス・vectorized経路に限定。manifest正本は実際にロードしたimmutable artifactのcanonical SHA-256とし、`logical_date`を1 run 1値に固定。snapshot確定後のsource SELECTとflush時ledger queryは0件を強制する。
- 実装順: P1 manifest/snapshot hotfix → P2全PF×全日付differential RED → P3 pure executor SSOT化 → P4 exact GREEN+性能検証。旧 `_compute_pipeline_signals` は定義・呼出とも0件を完了条件とする。
- GA-220 bounded分類: `last_updated=2026-07-10`以後のgate対象commitは3件。研究索引反映対象は`a00e1253` 1件、`44f29418`/`85553199` 2件はcmd_3841の可視性設定孤児清掃・証跡来歴修正であり運用ドメインのため非対象。
→ 正本: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3840_nondeterminism_redesign.md` §7
- v1.2追記(家老運用レビュー blt_20260711_014245反映): P1をP1a(source identity+logical_date+run_id、単独deploy可)/P1b(snapshot+manifest+guard+cron対応)に分割。書込み順序を「read-session全materialize→manifest確定→初めてbusiness write」に確定(現コードは入力load前にconfig snapshot INSERT=write0が偽だった)。standalone L5にmanifest_kind=l5新設。cronはHTTP accepted≠job成功のためterminal poll+失敗nonzero化、L5 fallbackはL3当日成功を実行条件に追加。追加AC7本(業務write0/5caller伝播/manifest消失0/L2失敗遮断/L5被覆/guard0件/全shard網羅)。→ 正本§8
- cmd_3848(P1a追補): local source identityはtracked dirtyに加え、設計§7.1の4 source root内のuntracked path+content SHA fingerprintもdirtyとしてfail-closedする。
- cmd_3850(P1c): production-image/isolated-clone各102PFを同一`input_snapshot_id`・`execution_fingerprint`でcontrolled runし、pre/post 4 artifact各12,385行を比較。4経路すべてexact=true、mismatch/missing=0、snapshot後source SELECT=0、本番business write=0。float差分はruntime/driver/DB/end-to-endのいずれにも再現せず、旧baseline差分は回帰fixtureとして固定。→ `/mnt/c/Python_app/DM-signal/outputs/analysis/cmd_3850/rc25_compare/cmd_3850_float_localization.json` (2026-07-11)
- cmd_3852(P2b RED): §9.7の18表(A10/B1/C3/D2/E2)・全exact fieldを同一新manifest下だけで比較する契約を固定。IEEE754 bit exact、canonical JSON、NULL exact、ledger UTCDateTime 6桁microsecondsを被覆し、全18表の注入RED差分を検出。23 PASS/FAIL0/SKIP0。→ `/mnt/c/Python_app/DM-signal/backend/tests/test_cmd_3852_persisted_inventory_exact.py`, commit `3925242ba285a98d1048069b9c94a63e95c42e4f` (2026-07-11)

## §55. P4 shadow反復exact GREEN、CI GREEN後のAC2再開はlive確認待ち (cmd_3859/cmd_3861, 2026-07-12)

- 結論: 設計書§9.1 P4のAC1(shadow反復exact)はGREEN確定。新鮮production snapshot(`cmd3819_baseline_20260711T204325Z_0e079ac5`)から`cmd3859_shadow_a`/`cmd3859_shadow_b`を新規cloneし並列controlled run、§9.7全18表・133 exact fields・567,751行でmissing 0/mismatch 0/exact=true、manifest_id/input_snapshot_id/execution_fingerprint/effective_source_identity全4識別子が独立プロセス間で完全一致。
- **統合/CI前提は成立、live反映は未確認**: cmd_3860で系列統合を完了し、cmd_3861で全量`1776 passed/8 xfailed/6 xpassed/FAIL 0/SKIP 0`、Pytest CI GREEN(run `29179774396`)を確認。だが2026-07-12 13:54 JSTの`git ls-remote origin refs/heads/main`は`7946aa449f04230af1b260d20d38c3bca4cee333`であり、P4 AC2用隔離branchの非force統合・Render Deploy APIでのlive 40桁commit確認は未完。
- **AC2(本番1run照合)は未実行のまま再開中**: single REPEATABLE READ直前snapshotと復元経路を一次確認し、同一commit・同一target_dateのfresh shadow expected artifactを生成した後に限り、本番`POST /admin/recalculate-sync`を厳密1回実施する。live 40桁commit確認または復元経路が未成立なら、DB/API write前に安全停止する。
→ 正本: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.14(cmd_3859内容はv1.4.14 changelogに記載)、P4 AC2再開=`cmd_karo_hotfix_cmd3859_p4_ac2_resume_202607121337`
→ **続報: §57(2026-07-13)で「live反映は未確認」は解消(live=`34747ad1`確定・deploy済み)、AC2は未実行のまま残と判明**

## §56. origin統合完了・実CI初回全量実行で21件pre-existing failure発覚、push/deploy意図的見送り (cmd_3860, 2026-07-12)

- **cmd_3872追補 (2026-07-13)**: P4 AC2のinput snapshot不一致は、現物上`logical_date`の日跨ぎだけで発生するため日次ETL価格更新の証明ではない。expected成果物はmanifest payload、manifestは入力row_count/end_dateを保存せず、過去入力差分を事後説明不能。再挑戦は同一`logical_date`+PF exact set+4 artifactを固定し完全payloadを先に保存する。→ `docs/research/cmd_3872_input_snapshot_diff.md`

- **AC1完了**: cmd_3859がエスカレーションしたorigin/main(9 commit) vs local main(79 commit)分岐を`git merge origin/main`(force/rebase不使用)で統合、マージコミット`38ec9b8b`。両系列コミットが祖先に含まれることを確認。マージ後`backend/`はlocal main旧tip(`0e079ac5`)と**0差分**(origin側9 commitは家老による個別移植でlocal側の真部分集合と判明。証拠: `git diff d942982b 5430b59b -- backend/app/services/monthly_trade_impl.py`が空)。コンフリクト2件もこの前提でHEAD側採用。
- **実CI初回全量実行で重大発見**: 検証用ブランチをGitHub Actions実CI(全1790テスト、実PostgreSQL)へpushしたところ**24件失敗**(origin/main単体は1件のみ=pre-existingの日付mock問題)。backend/の0差分により、この24件はマージ由来ではなくlocal 79 commit統合状態に既に内在していたと確定。**§cmd_3856(1つ前のP3a作業)が既に「full backend suite参考計測: baseline 38 failed/1734 passed→post-refactor 33 failed/1740 passed(環境起因)」と記録していた既知傾向と整合する**が、cmd_3856時点はローカル参考計測で非blocking扱いだったのに対し、本cmdは実GitHub Actions CIでの計測かつ**実際にpushする(=後述のRender auto-deployにより即本番反映される)最初のcmd**であるため、同じ傾向でもリスク評価を変えた。
- 24件中6件は`RECALC_RSS_CAP_MB`未設定というCI環境要因(本番はcgroupで自動解決、fail-closed設計は意図通り)で、`.github/workflows/pytest.yml`へ慣例値8192を追加(commit`b46170ab`、本番非影響)し24→21件に減少。残21件のうち過半数は`db.info.get(key) is not None`という新設precompute検知コード(cmd_3835/cmd_3849/cmd_3850由来)に対し、旧テストが`MagicMock().info`未設定のままのため誤判定している疑いが強い(実SQLAlchemy Session.infoは本物の空dictのため本番影響は限定的と推定)。**しかし`test_nested_fof_signal.py::test_signal_cache_no_forward_fill`はcmd_1481の実過去障害(Cashシグナル月またぎ伝播)の回帰テストであり、誤判定と断定できる確証を得るまで看過できない**。
- **運用上の確認**: DM-SignalはRender Auto-Deploy: On Commit。`[skip render]`無しのmain push=即本番デプロイ。よってpush(AC2)とdeploy(AC3)は事実上不可分であり、21件の未триaж failureが残る状態でのpushは「未検証コードの即時本番投入」と同義。**本cmdの範囲ではpush/deployを意図的に見送った**。local mainには`38ec9b8b`(統合)+`b46170ab`(CI env fix)の2 commitが未push保持。
- 次アクション: 残21件(特に forward-fill regression 2件)を個別triageするcmdを新規起票→原因確定(test-mock artifactか実装regressionか)→CI真にGREEN確認→push(=deploy)→P4 AC2再実行→P5(cmd_3827回帰)。
- **cmd_3870追補(2026-07-13)**: live `34747ad1`で本番fullrecalculateを厳密1run(id=213、completed/errorなし、687.35秒)したが、production `input_snapshot_id=c2b66a…` と凍結expected `75886e…` が不一致でcanonical comparatorはfail-closedしP4 GREEN未成立。pre-snapshotへrestore-lockedし18/18表・565,756行・rows/schema/order/SHA-256完全一致で原状回復済み。P5へは進まない。→ `/mnt/c/Python_app/DM-signal/docs/research/cmd_3870_p4_ac2_evidence.md`
- **cmd_3873 AC3追補(2026-07-13)**: bundle export/import consumer(hayate commit `75ca73b4`)のAC3(本番非破壊+restore契約固定)を隔離実測で確認。business write=0(bundle/manifest契約28/28 test再実行PASS、`backend/tests/conftest.py`にDB接続autouse fixtureなし=完全isolated、`export_input_bundle`はfile I/Oのみでdb引数自体を持たない)、execution-root pin=本検証のworktree HEAD `75ca73b4`固定+`docs/runbooks/p4-production-restore.md`/`db_capability_launcher.py --execution-root`契約を踏襲、restore-locked=cmd_3870確立のlauncher隔離test suite 12/12 PASS(`restore requires current expected commit`+`locked restore excludes writers and proves empty tables before COPY`で健在確認)、precompute cron等writer非干渉=`PriceCache.load()`がdb.infoのbundle snapshotのみ参照しsource SELECT 0(source table非接触、`SourceSelectGuard`の3テーブルへ未接触)で境界確認。証跡=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3873_bundle_impl_notes.md`
→ 成果物: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3860_integration_and_ci_findings.md`、運用系サマリ: `context/dm-signal-ops.md` §70、正本: `docs/research/cmd_3840_nondeterminism_redesign.md`(P4系列、v1.4.14のまま)

## §57. P4統合+live deploy完了(commit=34747ad1)・restore契約完成・速度実測-8.80% (v1.4.15, 2026-07-13)

- **結論**: §55/§56記載の「live反映は未確認」「push/deploy見送り」は解消済み。P4統合branch(親`732dfef3`+`8241f41c`)はRender backend(`srv-d4ja7q15pdvs739a4q1g`)へdeploy済み(deploy=`dep-d99oaseq1p3s73d2keb0`、status=live、finishedAt=2026-07-12T12:18:36Z)。live commit=`34747ad118aebd42a05e00a358f2c709542f3ec9`。同commit上のGitHub Actions Pytest run(`29192313574`)もsuccess。**local HEAD(`9252af73`)/origin main(`f17c93cd`)/live(`34747ad1`)の3値は意図的に異なり、P4 AC2のexpected_commitはlive `34747ad1`を用いる**(origin/mainとの混同禁止)。
- **restore契約完成**: negative A(artifact改竄/schema不一致/source commit不一致/DB identity不一致)4/4 PASS、negative B(confirm欠落/lock競合/実行中recalc/途中例外)4/4 PASS、全ケースbusiness write 0・必要時rollback 1。core統合commit=`732dfef3`(5 files/634行、restore core+negative A/B+runbook)。対象42→統合後43 PASS/FAIL0/SKIP0。実行側fail-closed境界としてtracked capability launcher(infra commits `4da46f0e2`→`7ba136462`→`b65d32fc5`)+runbookのexecution-rootをlive commitへpinする契約(`9252af73`)を追補(liveへ新規deployするコードではなくAC2実行側の境界)。
- **速度実測**: shadow run(`run_id=202607112047232OVP4O`)のrecalculation_timings実測total_elapsed_sec=**497.02秒**(before本番545秒比**-8.80%**、bottleneck=L3_fof)。P1c instrumentationは`P1C_ARTIFACT_DIR`未設定の通常経路でhex書出し条件falseのため**本番inert**(production DB同run_id 0件で確認)。
- **P4 AC2の現在地**: 前提不成立blockは全て解消(shadow 2run exact+CI GREEN+restore契約+live hash確定+revert/restore経路)。**残る実行項目**=live `34747ad1`固定worktree/expected_commit確定→credential+one-use nonce→no active recalculation/advisory lock確認→18表pre-snapshot+manifest→fullrecalculate 1回のみ実行→同expected artifactへcanonical exact照合。**AC2本番1run自体は未実行**。GREEN後はP5(cmd_3827事故条件回帰)で決定性最終宣言。
→ 正本: `/mnt/c/Python_app/DM-signal/docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.15、家老一次照合=掲示板`blt_20260713_021355`、commit=`bd1a1b10322d97fa59cba62dd72550e9102c784f` (2026-07-13)

---

## 因果リンク

- ← [[dm-signal]] 研究層
- ← [[dialogue_preprocessing_research_20260331]] 前処理研究日誌
- ← [[dialogue_alm_finite_time_20260404]] ALM有限時間4指標
- ← [[dialogue_miniaturization_why_20260407]] 矮小化→WHY/WHAT因果→時間は人殺し→本番バグ発見
- → [[gunshi-fof-deterioration-analysis.md]] EMA前処理のFoF悪化メカニズム分析
- → [[cmd-284]] [[champion-selector]] 四つ目GS+champion選出(CoDD extract: cmd_1991)
- → [[l1-alm-wf-engine]] [[wf-runner]] ALM WFエンジン+ランナー(CoDD extract: cmd_1991)
- → [[cmd-1826-memory-analysis]] [[cmd-1847-neighbor-analysis]] メモリ+近傍分析(CoDD extract: cmd_1991)
- → [[cmd_286_recalculate-architecture]] fullrecalculateアーキテクチャ設計(cmd_286)
- → [[cmd_480_dm-signal-supplemental-catalog]] DM-Signal補足カタログ(cmd_480)
- → [[cmd_481_dm-signal-infra-catalog]] DM-Signalインフラカタログ(cmd_481)
- → [[cmd_487_dm-signal-cross-reference-map]] DM-Signal相互参照マップ(cmd_487)
- → [[cmd_493_knowledge-decontamination-report]] 知識汚染除去レポート(cmd_493)
- → [[cmd_495_wrong-signal-impact-march]] 誤シグナルの3月インパクト(cmd_495)
- → [[cmd_501_gekikou-four-impact]] 激攻四神インパクト分析(cmd_501)
- → [[cmd_503_frontend-research-restoration]] フロントエンド研究復元(cmd_503)
- → [[cmd_808_monthly-returns-before]] monthly-returns高速化事前調査(cmd_808)
- → [[cmd_830_831_performance-roadmap]] パフォーマンスロードマップ(cmd_830/831)
- → [[cmd_2554_hanzo_dm_signal_polysemy_wave2_kb_research]] DM-Signal多義語Wave2研究(cmd_2554)
- → [[cmd_2554_hayate_semantic_ambiguity_map]] セマンティック曖昧性マップ(cmd_2554)
- → [[cmd_3222_VIX深掘りバックテスト]] VIX深掘りバックテスト(cmd_3222)
- → [[cmd_3223_V8閾値チューニング]] V8閾値チューニング(cmd_3223)
- → [[cmd_3225_レイヤー別+マネージドボラ]] レイヤー別+マネージドボラ分析(cmd_3225)
- → [[cmd_3332_MTD速報行]] MTD Daily Returns UX速報行(cmd_3332)
- → [[cmd_3425_3431_相関レジーム研究]] 相関レジーム7知見(戦略同質性/高相関=バブル/乖離リフト3-4x/deterioration逆機能/σ閾値不適/リスクベースBB不適/Turning Points不採用)(2026-06-17)
- → [[cmd-1869-2x2-factor-analysis]] [[cmd-1870-beta-adjusted-2x2]] 2×2因子+β調整(CoDD extract: cmd_1991)

<!-- 軍師idle分析リンク(cmd_3278自動追記) -->
- [[gunshi-alm-dynamic-iswindow-design]] — 軍師分析: ALM動的isWindow設計
- [[gunshi_alm_parity_drift_analysis_20260409]] — 軍師分析: ALMパリティドリフト分析(2026-04-09)
- [[gunshi_cmd1901_cash_fallback_design_20260414]] — 軍師分析: cmd_1901 Cashフォールバック設計(2026-04-14)
- [[gunshi_consultation_cmd1901_cash_analysis_20260414]] — 軍師相談: cmd_1901 Cash分析(2026-04-14)
- [[gunshi_gs_sqlite_further_optimization_20260429]] — 軍師分析: GS SQLiteさらなる最適化(2026-04-29)
- → [[edge-detection-cycles]] エッジ検出サイクル研究(局所極値検出アルゴリズム)
- → [[gs-results-by-ninjutsu]] 忍術別グリッドサーチ結果一覧(忍法ごとの最適パラメータ)
- → [[nested-fof-design-research]] ネストFoF設計研究(FoF of FoFアーキテクチャ検討)
- → [[nested-fof-momentum-regime-kelly]] ネストFoFモメンタム×レジーム×Kelly比率設計
- → [[spa-overfitting-analysis]] SPA過適合分析(Statistical Performance Analysis: 過適合リスク評価)
- → [[test_select_after_20260506]] テスト選択スクリプト(吸収リファクタ後: 2026-05-06)
- → [[uwp_three_metrics_design]] UWP3指標設計(Upward Pull: 3指標の定義と実装方針)
- → [[cmd_3849_P1b_input_manifest]] P1bはcanonical manifest+price/economic/ledger immutable snapshot+snapshot後source SELECT 0+RSS fail-closed+6 caller共通入口+accepted run_id/manifest bind/parent lineageを実装。検証139 PASS/FAIL0/SKIP0、成果物=`outputs/analysis/cmd_3849_p1b_tests.xml`、commits=`cdd9b60e23e75984c0f03509b50d8021acb2eaa9`,`49bc81b6676fc50f6bb72dce798ce05df29c3fe3` (2026-07-11)
- → [[cmd_3851_P2a_RED]] P2a母集団は標準24PF(adapter経路)×valid_start filter後日付。初回REDの97,687 mismatchはoracleのweights抽出契約バグ、4,982 missingはwarm-up日付誤混入で、signal/exceptionは全数一致=実装ロジック不一致0。FoF78は`recalculate_fof.py`単一実装のためEngine-vs-adapter対立が成立せず、P2a2の新manifest下golden-baseline exact回帰で被覆する。成果物=`outputs/analysis/cmd_3851/cmd_3851_p2a_exact.json`、正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.11 (2026-07-12)
- → [[cmd_3853_P2a_GREEN]] cmd_3851のオラクル契約バグ2点を修正しP2a GREEN化: _adapter_weightsをEngine正準式(execute_pipeline_with_blocks等分ウェイト式)へ差し替え、被覆母集団にportfolio_valid_start_dates filterを適用、coverage assertを102→24標準PFへ訂正。隔離clone(`cmd3850_rc10_clone`)で2007-01-01〜2026-07-11全量再実行し、expected=actual=97,687、missing 0、mismatch 0(前回97,687/4,982から解消)。成果物=`outputs/analysis/cmd_3853/cmd_3853_p2a_exact.json`、commit=`fdffeb9af07a70dc2b25b0362555f77388422cfc`(branch `ninja/kotaro-cmd-3853`) (2026-07-12)
- → [[cmd_3854_P2a2_golden_baseline]] FoF78体はrecalculate_fof.py単一実装でEngine-vs-adapter差分契約が構造的に不成立のため、新manifest下(baseline snapshot `cmd3819_baseline_20260711T034534Z_b1bb8ab7`)で全78/78 FoF PF・243,293行(signal/holding_signal/display_ticker_weights)をgolden-baseline固定(canonical_sha256=`57d8c569ca54adda4eb1f4bafb61bb98e0956764bad6e9f415a8bbe6402bc7ca`)。隔離clone(`cmd3854_fof_regression_check`、production非接触)で`_recalculate_fof_history`を再実行した回帰exact比較はmissing 0/extra 0/mismatch 0(243,293/243,293完全一致)でP2a2契約をGREEN化。成果物=`outputs/analysis/cmd_3854/cmd_3854_p2a2_full_test_run.log`(pytest 5 passed/FAIL0/SKIP0)、正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.11、DM-Signal側commit予定=`ninja/tobisaru-cmd-3854` (2026-07-12)
- → [[cmd_3856_P3a_common_executor]] 設計書§7.5のP3a(共通executor統合)を実装: 新モジュール`backend/app/services/pipeline/executor.py`に純粋関数`execute_pipeline_semantics`(DB/session/subprocess/date.today非依存)を追加し、Engine adapter(`PipelineEngine.execute_pipeline_with_blocks`、旧resolve_block事前解決を廃止)とvectorized batch adapter(`recalculate_fast.py`、旧`_compute_pipeline_signals`112行を全廃)の双方が同一関数を呼ぶ構造へ統合。実装直後の検証で`TypeError: Cannot compare Timestamp with datetime.date`を検出(precomputed_inputsは常にpd.Timestampキーだが、Engine adapter経由の呼出しはdatetime.dateを渡す型不一致。旧`get_momentum_value_at_date`のpd.Timestamp正規化が新executorに欠落)、`ts = pd.Timestamp(target_date)`正規化を追加し回帰テスト`test_execute_pipeline_semantics_accepts_plain_date_like_engine_adapter`を追加して修正。統合後の検証: P2b 23 passed/FAIL0/SKIP0、P2a2 5 passed/FAIL0/SKIP0、P2a(隔離clone`cmd3850_rc10_clone`、2007-01-01〜2026-07-12全量、標準24PF)はportfolio_count=24、expected=actual=97,687、missing 0、**mismatch 0**、errors 0(exit 0)でcmd_3853のbaselineとビット単位一致。backend全域横断検索で`_compute_pipeline_signals`残存参照0件(`scripts/oneshot/cmd_3827_*.py`はbackend外の旧調査用一回限りスクリプトのためAC3対象外、将来再実行時にエラーとなる点はlesson_candidate化)。full backend suite参考計測はbaseline 38 failed/1734 passed→post-refactor 33 failed/1740 passed(新規リグレッション0、環境起因の既存失敗5件が偶発的に解消)。設計書§9.2列挙の6 prod callerは全て`recalculate_history_fast`(標準PF、統合executor経由)または無変更の`PipelineEngine.execute_pipeline`(FoF)を呼ぶのみで統合後経路への切替は構造的に保証。成果物=`docs/research/cmd_3856_p3a_common_executor.md`+`outputs/analysis/cmd_3856/cmd_3856_p2a_exact.json`、正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.11、DM-Signal側branch=`ninja/kotaro-cmd-3856` (2026-07-12)
- → [[cmd_karo_verify_p3b_nocode_closure]] §9.1 P3b no-code closureを二値検証した結果**不成立**、設計書のP3b状態(`after P3a`)は変更せず。理由: cmd_3852(P2b)の23 PASSは合成1行fixtureへ1フィールド差分を注入し検知できるかを見る**比較関数の契約テスト**(`test_every_inventory_table_reports_its_exact_red_mismatch`、DB接続なし)であり、「新manifest下の実データexact」ではない。実データで新manifest下exact確認済みなのは18表中1表(trade_performance)のみ、かつ`float_bit_artifact.py`がFloat 8/13 fieldsしかSELECTしないため同表もDate/String 5 fields(start_date/end_date/trade_date/trade_type/allocation)は未検証。残り17表は実データ比較0件。closure基準(18/18表・missing0・mismatch0・同一新manifest)に遠く、次の最小検証はP1c同様の手法(production image+isolated clone、同一input_snapshot_id)をtrade_performance残り5 fieldsと他17表へ拡張すること。成果物=`docs/research/cmd_karo_verify_p3b_nocode_closure_202607120339.md`、正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.11 (2026-07-12)
- → [[cmd_3857_P3b_inventory_exact]] fresh production-image/isolated-cloneの同一`input_snapshot_id`で全102PFを2 runし、§9.7全18表・135 fields・567,751行を実データexact比較。16/18表exactだが`signals.momentum_data` 11,030行と`recalculation_timings` 1行が非exact(missing 11,031/mismatch 22,062)。sampleでmomentum_data内`input_tickers/output_tickers`順序と`execution_ms`差を確認。tolerance緩和・除外なしでP3b=BLOCKED/P2b RED継続。trade_performanceはDate/String 5 fieldsを含む全15 columns・12,385行exact。成果物=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3857_p3b_inventory_exact.md`、正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.12 (2026-07-12)
- → [[cmd_3858_P3b_GREEN]] cmd_3857の2非exactを根因修正+分類是正: (1)`backend/app/services/pipeline/engine.py`のblock_results構築が`list(context.current_tickers)`(set、プロセスごとの文字列hash順で非決定)を使っていたため`momentum_data`の`input_tickers`/`output_tickers`/`filtered_out`配列順が非決定的だった根因を特定し`sorted(...)`へ置換。(2)実DB直接検証で`recalculation_timings`の`run_id`(実行ごとの一意識別子)、`layer_data._run.input_manifest.run_started_at`/`rss_hard_cap_bytes`、`bottleneck`、`layer_breakdown`(実測でpercentageも非再現: L3_fof 48.2%→47.3%)がwall-clock/システム状態依存のtelemetryであることを確認し、設計書§9.7 row1/row15+一般D分類定義を訂正、比較harness(`backend/tests/test_cmd_3852_persisted_inventory_exact.py`)へ同一境界(`_strip_momentum_data_telemetry`/`_strip_layer_data_telemetry`+recalculation_timings専用`_row_signature`特例)を実装(新規unit test 3本追加、既存28件は無変更でPASS継続、計31 passed/FAIL0/SKIP0)。business field本体の除外・tolerance緩和は0件。(3)cmd_3857と同一条件(fresh `cmd3858_fresh_prod`/`cmd3858_fresh_clone`、同一input_snapshot_id=`df5579bd...`)で§9.7全18表・133 exact fields・567,751行を再実測し**18/18表missing 0・mismatch 0・exact=true**。P3b GREEN、P2b RED解消。成果物=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3858_p3b_green.md`、正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.13 (2026-07-12)
- → [[cmd_3859_P4_shadow_exact_deploy_blocker]] P4のAC1(shadow反復exact)を新鮮production snapshot(`cmd3819_baseline_20260711T204325Z_0e079ac5`、旧baselineはcmd_3826のconfig復元で陳腐化していたため取り直し)起点で実行。`cmd3859_shadow_a`/`cmd3859_shadow_b`を並列controlled runし、§9.7全18表・133 exact fields・567,751行でmissing 0/mismatch 0/exact=true、4識別子(manifest_id/input_snapshot_id/execution_fingerprint/effective_source_identity)完全一致でGREEN確定。AC2(本番1run照合)は、本番Render live deployが`178add2a`(P1a以前、Render Deploy API実測+本番recalculation_timings実測+git分岐の3系統証跡で確定)であるため意図的に未実行。「同一manifest」前提が成立しない状態での強行は無効な結果を招くため、本番デプロイ実行(79コミット統合含む、ninjaタスク権限外)を家老へエスカレーション。正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.14 (2026-07-12)
- → [[cmd_3860_origin統合+push見送り]] origin/main(9 commit)とlocal main(79 commit)を`git merge`で統合(AC1完了、backend/は旧local tipと0差分で安全性確認)。統合状態を初めて実GitHub Actions CIへ通したところ24件失敗(§cmd_3856の「baseline 38 failed参考計測」と整合する既知傾向)、うち6件はCI環境要因(`RECALC_RSS_CAP_MB`)で解消し21件残存。Render Auto-Deploy: On Commitによりpush=即本番デプロイと判明したため、cmd_1481回帰テスト(`test_signal_cache_no_forward_fill`)を含む未триaж21件を残したままのpush/deployを意図的に見送り、triage cmd起票を家老へ推奨。成果物=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3860_integration_and_ci_findings.md` (2026-07-12)
- → [[cmd_3870_P4_AC2_FAIL+exact原状回復]] トップ2体制(家老/goal実行+将軍独立監査、殿credential承認)でP4 AC2本番strict 1run実行(run213、687.35s、completed/error NULL)。canonical comparatorがexpected input_snapshot_id=`75886e9f`(cmd_3859 shadow 07-12)とactual=`c2b66a69`(run213)の不一致でfail-closed=**P4 FAIL・P5禁止**(決定性の反証ではなく照合契約の入力固定不備が主仮説)。AC3原状回復: 初回restoreは待機writer(=etl_trigger Background precompute-raw、Renderログで特定)のPK duplicateでrollback→**restore-locked新設**(18表SHARE ROW EXCLUSIVE一括lock+DELETE後0件assert+row/sha256二重検証、launcher suite 12/12 PASS)→**18/18表・565,756行exact=true原状回復**(manifest sha=`d9ec7e4f`)。次=cmd_3872(input snapshot実差分偵察)→入力固定契約→AC2再挑戦。正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.16 (2026-07-13)
- → [[cmd_3872_input_snapshot_diff]] P4 AC2の`75886e9f`(expected)と`c2b66a69`(production run213)は同一入力ではないと確定。差の必要条件は`logical_date`(manifest採番が`input_snapshot_version+logical_date+PF ID+4 artifact hash`をcanonical SHA-256する設計のため、DB内容が同一でも日を跨げばIDは必ず変わる)。日次ETL価格更新が原因という説はexpected側がinput manifest payload(行数/終端日/artifact hash本体)を保存せずhashのみ永続化しているため現物上まだ反証も実証もできない。再挑戦の入力固定候補: expected生成とproduction runを同一read-only snapshot/cloneから実行し`logical_date`を明示引数で同値固定、比較前に4 artifactの個別hash・PF exact set・行数・min/max dateを完全payloadとして保存する方式を提示。成果物=`docs/research/cmd_3872_input_snapshot_diff.md`、正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.16 (2026-07-13)
- → [[P4_AC2再挑戦方式確定_v1.4.17]] 将軍・家老検討合意(殿指示2026-07-13 12:33)。cmd_3870=決定性FAILではなく**比較前提FAIL**(logical_date日跨ぎ+manifest payload未保存)。再挑戦方式=**single-source immutable input bundle**(T0でread-only materialize→shadow A/B 2run+prod 1runが同一bundleをconsume→18表exact→mismatch時restore-locked)。直前clone expected生成のみ案は家老実測反証(実行窓19分44秒〜28分01秒でwriter混入を排除できない)で不採用。前提実装=bundle export/import consumer+manifest payload保存契約(sha256/row_count/min_max date/PF set/logical_date、schema migration不要)。実装GREENまで再挑戦禁止。正本=`docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.17 (2026-07-13)
- → [[AST恒常スキャンCI]] cmd_3882で18対象表writerをAST/literal SQLからpath+line検出し、AST検出↔registry↔DB enforcement三集合exact、不一致FAIL、動的SQL BLOCK、未登録writer敵対fixtureを固定。設計列挙11 source filesに加え現物走査で`app/utils/timing.py`/`app/services/verification_service.py`も回収し18/18表を検出。cmd_3881合流後はprovider集合注入でPASSへ転じる。詳細=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3882_writer_inventory_ci.md`
- → [[cmd_3868_inventory_perf_root_cause]] cmd_3868 GS DB inventory(146ファイル・37.98GiB)がSHA-256+PRAGMA integrity_checkで10時間超・rchar 3.74TB(91.9倍増幅)化した根因を単一ファイル分離計測で定量特定: 9p(WSL2 DrvFs)への直接read(2)はRPC1回あたり固定遅延(≒3-4ms)を持ち、SQLite既定cache_size(-2000≒2MB)が大ファイルでthrashingを誘発する二重構造(92.2MBファイル実測: integrity_check直接9p=237.98s、cache_size拡大のみ=73.85s(thrashing解消も9p遅延は残存)、**ローカルext4コピー後に実行=1.89s、126倍高速化**)。対策としてコピー(9p、直列、既知教訓L306/L307/L508準拠)+ローカル解析(bounded parallel)のパイプラインへ`scripts/oneshot/cmd_3868_inventory.py`を全面書き換え。per-file JSONL checkpoint(fail-closed、mtime/size不一致で再処理)で中断再開に対応、破損DB/読取不能/worker異常は全てERROR行記録でバッチ継続。pytest 13 passed/FAIL0/SKIP0(`tests/unit/test_cmd_3868_inventory.py`、新旧出力等価性/resume/重複排除/linked worktree/bounded並列上限を検証)、既存長時間プロセス(PID61345)に干渉なし。正本=`docs/research/cmd_3868_inventory_perf_root_cause.md` (2026-07-13)
- → [[cmd_3868_gs_db_generation_cleanup]] 146/146 DB台帳から同一SHA旧世代9件・921174016 bytesを確定。実行直前にrealpath/非symlink/通常file/bytes/git管理外/コード参照0/保持正本SHAを9/9再検証し、個別`rm --`で削除。候補残存0/9、保持正本16/16 SHA一致、df available 304794128384→305715171328(+921042944 bytes)。台帳正本=`docs/research/cmd_3868_gs_db_generation_inventory.md`、commit `9daba5d5` (2026-07-13)
- → [[cmd_3878_container_selection]] safe archive v2は**長さprefix付き単一framed typed stream**を勧告。pickle 0、raw SHA-256→entry検査→artifact hash→schema/row_count→typed decode、3候補×敵対6種=18/18 reject・FAIL0/SKIP0、raw deterministic、streaming可、RSS増分0 KiB(<64 MiB)。SQLiteはstreaming不可、ZIP_STOREDは全基準PASSだがparser/central-directory攻撃面のため次点。成果物=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3878_container_selection.md` (2026-07-13)
- → [[cmd_3878_recon3_track_b]] 基準commit `434c146f`の隔離worktreeで独立実測し、**`framed-json+typed-binary`**を勧告。基準充足=`pickle_free=yes, raw_hash_before_decode=yes, adversarial_reject=6/6, deterministic_raw=yes, rss_cap=yes, streaming_read=yes, streaming_write=yes`。SQLiteはstreaming write不可、ZIP STOREはsize bomb reject 5/6で不採用。Track B成果物=`docs/research/cmd_3878_container_selection.md`、検証コード=`scripts/research/cmd_3878_container_probe.py` (2026-07-13)
- → [[cmd_3879_safe_bundle_v2]] cmd_3878確定方式をproduction consumerへ実装。framed typed stream v2+raw/artifact/schema/canonical hash多段検証、再計算関数非依存read-only materializer、旧export経路残存0、valid bundle source fallback 0を固定。欠落していたcmd_3854 golden原票を隔離Postgresから正規再生成し243,293行・78PF・SHA-256 `57d8c569ca54adda4eb1f4bafb61bb98e0956764bad6e9f415a8bbe6402bc7ca`一致。最終全量=`1810 passed / FAIL0 / SKIP0 / 8 xfailed / 6 xpassed`。正本=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3879_safe_bundle_impl.md` (2026-07-14)
- → [[cmd_3881_DB_fence_migration_FAIL]] v1.4.21 §9.10.5の18表statement-trigger+coordinator+fence functionを単一往復migrationで試作。isolated production snapshot cloneでupgrade 18/18→downgrade 0/18→re-upgrade 18/18、18表canonical row/hash不変、未参加writer明示reject、exact token経路成立、silent skip 0はPASS。しかし4 write class×30 batchはsingle ORM median比1.1834、bulk upsert 1.1639で閾値1.05超過、full recalculationも892.013s→947.861s=比1.062609(>1.01)のため**採用FAIL・本番適用禁止**。閾値緩和ではなくDB fail-closedを保った低overhead方式の再設計が必要。詳細=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3881_db_fence_migration.md` (2026-07-13)
- → [[P4_writer_fence_v1.4.22]] `[[cmd_3881性能FAIL]] -> [[常設trigger通常時課税]] -> [[P4窓限定role trigger]]`。平時はtrigger 0/17、keeperのrecalc advisory取得後だけ単一DDL transactionでrun固有NOLOGIN role+17 statement triggersを原子装着し、通常writerをDB拒否、P4 transactionの`SET LOCAL ROLE`だけ`WHEN=false`でblocker function呼出し0とする。disarm失敗は17/17維持+RECOVERY_REQUIRED、部分drop/expiry fail-open禁止。owner credentialの意図的DDL/SET ROLE悪用は別login分離が必要な脅威境界と明記し、性能閾値(median≤1.05/p95≤1.10/full≤1.01)は緩和0。旧commit `f94513b0`は反例のみでcherry-pick禁止。正本=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.22、commit=`88cc5bd74d5a8926f7bdc65c1bec6d6834feff60` (2026-07-13)
- → [[P4_writer_fence_v1.4.23]] `[[将軍v1.4.22条件付き承認]] -> [[F17_G1集合分離]] -> [[cmd_3881再配備契約]]`。比較集合V=18表をF=output/fence/restore対象17表とG=`signal_decision_ledger` immutable guard 1表に分離。restore DELETE/COPYはFのみ、Gはmutation 0+pre/post canonical hash不変とし、G差分は上書き復旧せず`RECOVERY_REQUIRED`。arm lock順はcanonical辞書順の1通りに固定し、40P01/55P03/57014は自動retry 0回で原子rollback→trigger 0/17+role 0+ARMING不在を別sessionで証明。正本=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3840_nondeterminism_redesign.md` v1.4.23、commit=`611f715bfbe4875e9e8d92c267818ee52324faa0` (2026-07-13)
- → [[cmd_3881_v1.4.23_role_trigger_FAIL]] `[[F17_G1集合分離]] -> [[P4窓限定role_trigger実装]] -> [[armed性能閾値FAIL]]`。isolated cloneでsteady 0/17→armed 17/17→disarmed 0/17、run role 1→0、V=18表hash不変、G mutation 0、通常writer 4/4明示reject、silent skip 0はPASS。30 paired×300 statementsではsingle median 1.1941、bulk median 1.0583、delete+insert p95 1.1994が閾値超過し採用FAIL。full再計測はmicro gate FAILで開始せず、PASS/SKIP扱いにしない。詳細=`/mnt/c/Python_app/DM-signal/docs/research/cmd_3881_db_fence_migration.md` (2026-07-13)
