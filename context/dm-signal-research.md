# DM-signal 研究コンテキスト
<!-- last_updated: 2026-02-23 cmd_286 索引化(kotaro) -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。

コア定義(§0-5,8,10-11,13,15,18) → `context/dm-signal-core.md`
運用手順(§6-7,9,12,14,16-17) → `context/dm-signal-ops.md`

---

## §19. 月次リターン傾き分析 (cmd_270/271/272)

→ 詳細: `docs/research/parity-verification-details.md` §19

| 指標 | cmd | 結論(1行) |
|------|-----|----------|
| raw傾き(36M窓) | 270 | Improving=0体, Declining=12体, Inconclusive=74体。推奨窓幅36M |
| α傾き(SPY除去) | 271 | Alpha-Positive=0(全窓幅)。36Mで10体がα負(真のエッジ消失) |
| エッジ残存率 | 272 | Median 32%。四神全劣化: DM6=9.3%, DM7+=5.1%, DM2=-21.4%, DM3=-741.7% |
| 3指標統合 | 270-272 | 急速劣化ではなく緩やかなα低下。四神は3指標全てで低評価→優先監視 |

殿の指摘: α中立≠α水準ゼロ。「raw+α」二段判定を標準化。

### エッジ検知 C1-C4 (cmd_273/274) + 外部データ(cmd_282) + 日次(cmd_281)

→ 詳細: `docs/research/edge-detection-cycles.md`

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

→ 詳細: `docs/research/parity-verification-details.md` §20

**本番+GS双方でLA未検出。信頼度:高。** 全14BB+全5忍法GSでtarget_date以前参照を確認。
残存リスク: R1(当日終値未確定ガード不在, medium)。StockData API仕様は未検証。

---

## §21. 過剰最適化検証 (cmd_277)

→ 詳細: `docs/research/spa-overfitting-analysis.md`

**全5忍法PASS。** SPA検定でH0棄却不能、IS/OOS劣化なし。

| 忍法 | SPA p値 | GS空間 | 判定 |
|------|---------|--------|------|
| 分身 | N/A | 1 | PASS(数学的証明, パラメータ自由度0) |
| 追い風 | 0.36 | 42,174 | MODERATE_PASS(OOS>IS) |
| 抜き身 | 0.99 | 152,295 | PASS(FS champ OOS+29.9%) |
| 変わり身 | 0.73 | 28,116 | PASS |
| 加速 | 0.99 | 238,986 | PASS |

自由度: 名目0.23/実効0.15(中程度)。学術的裏付け+資産分散+GFS正則化で緩和。
注意: ISのみ最適パラメータ(短lookback)は過剰適合リスク → full-sample選出必須。

---

## §22. 外部データ統合エッジ検知 (cmd_282)

→ 詳細: `docs/research/edge-detection-cycles.md` §22

DTB3(3ヶ月T-Bill利回り)の12特徴量MI分析。最大MI=0.058bits(C2-Bの63%)。
Bayes上界: C2-B only=69% → C2-B+DTB3=63.7%(**悪化**)。Phase2(FRED API等)不要。

---

## §23. 日次粒度エッジ検知 (cmd_281)

→ 詳細: `docs/research/edge-detection-cycles.md` §23

日次Bayes上界63.2% < 月次69%(**悪化**)。全22特徴量AUC 0.506-0.543(ランダム)。
DM3高精度はTMV含有+クラスバランスの固有構造。汎化不可。Phase2不要。

---

## §24. 四つ目(yotsume) フルGSチャンピオン選出 (cmd_284)

→ 詳細: `docs/research/gs-results-by-ninjutsu.md`

18,744パターンから3モードチャンピオン選出。SPA検定3モード全てPASS。

| モード | CAGR | MaxDD | NHR | base | top_n | 構成四神 |
|--------|------|-------|-----|------|-------|---------|
| 激攻 | 62.41% | -18.45% | 59.06% | 18M | top1 | 常勝青龍,常勝朱雀,鉄壁玄武,激攻白虎 |
| 鉄壁 | 54.84% | -15.87% | 53.02% | 18M | top2 | 常勝青龍,常勝朱雀,鉄壁白虎,激攻玄武 |
| 常勝 | 46.80% | -32.87% | 63.98% | 6M | top2 | 常勝朱雀,鉄壁白虎,鉄壁玄武,激攻白虎 |

既存忍法比較: 四つ目は性能レンジ内(激攻CAGR 62.41%は変わり身62.25%同水準)。突出優位なし。

---

## 研究関連教訓索引 (projects/dm-signal/lessons.yaml)

### GS結果/パラメータ

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L117 | SPA p=0.99: 15万パターンGSチャンピオンはtop群内で統計的有意差なし | cmd_277 |
| L105 | BB config未拘束がGS無効パターン量産の根因。Pydantic制約はPortfolio層偏在 | cmd_264 |
| L132 | GS結果利用時はDATA_CATALOG.md + meta.yaml参照必須 | — |
| L102 | MultiView skip_months=[0,1,2,3]はクラス変数固定、config変更不可 | cmd_253 |
| L100 | MultiView base_period_months≥4必須(skip=3で0ヶ月問題) | cmd_253 |

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

### SPA/過剰最適化

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L117 | SPA p=0.99: チャンピオンはtop群内ノイズ範囲。full-sample選出が妥当 | cmd_277 |
| L114 | 高相関な弱予測器のスタッキングはDM3で精度改善しない | cmd_274 |

### エッジ検知

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L108 | エッジ残存率バックテスト: precision 18-34%, 単独では不十分 | cmd_273 |
| L111 | Cycle1統合: 月次precision 80%は構造的に困難(SNR壁0.1-0.5) | cmd_274 |
| L110 | 日次/週次粒度でも最大65.5%(DM3限定), 80%未達 | cmd_274 |
| L113 | ターゲット再定義はSNR限界を克服しない(DD>10%はbase_rate変更) | cmd_274 |
| L115 | 回帰→分類パイプラインは月次SNR限界を克服しない | cmd_274 |
| L116 | PF間の相関構造特徴量はエッジ崩壊予測に寄与しない | cmd_274 |

### 外部データ

| ID | 結論(1行) | 出典 |
|----|----------|------|
| L120 | DTB3追加はBayes上界を悪化(-5.2pp)。MI=0.058bits,次元の呪い | cmd_282 |
| L119 | DATA_CATALOG 86銘柄 vs experiments.db実際14銘柄の乖離 | cmd_282 |
| L118 | DTB3はdaily_pricesテーブルにticker='DTB3'格納(economic_indicatorsは空) | cmd_282 |
