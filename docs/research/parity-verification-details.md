# 月次リターン傾き分析 + ルックアヘッドバイアス検証
<!-- 出典: context/dm-signal-research.md §19.1-19.13, §20 -->
<!-- cmd_270/271/272/276, 2026-02-23 -->

> 結論: 推奨窓幅36M。3指標統合(raw傾き/α傾き/ER)でImproving=0体、四神全てエッジ劣化。LA検証は本番+GS双方でバイアス未検出(信頼度:高)。

---

## §19. 月次リターン傾き分析 (cmd_270)

PFの「今の調子」を月次リターン分布の時間的変化で判定する。3Phase構成。

| Phase | 内容 | 結論 |
|-------|------|------|
| A: ACF分析 | 代表PF8体の月次リターン自己相関を算出し推奨窓幅を決定 | 最大有意lag=35M(DM7+/DM-safe)、推奨41M |
| B: 窓幅比較 | 24M/36M/48M/60Mの4窓幅でレジーム変化検出率を評価 | 36Mが最良検出率(38%) |
| C: 傾きランキング | 全PFの月次リターンに線形回帰。傾き+95%CIで4分類 | 92PF中: Improving 0/Stable 6/Declining 12/Inconclusive 74 |

### 推奨窓幅: 36ヶ月

- ACF推奨: 41M（最大有意lag 35M + バッファ6M）
- レジーム検出最良: 36M（24Mは31%、36Mは38%、48Mは0%、60Mは12%）
- 総合判定: **36M**。ACFとレジーム検出の中間で、実用上のバランスが最良

### ACF分析結果（代表PF8体）

| PF | 最後の有意lag | 解釈 |
|----|-------------|------|
| DM2(青龍) | 2M | 短期相関のみ。ほぼランダムウォーク |
| DM3(朱雀) | 15M | 中程度の持続性 |
| DM6(白虎) | 28M | 強い持続性。トレンドが長期継続 |
| DM7+(玄武) | 35M | 最も強い持続性。長期レジーム依存 |
| DM-safe | 35M | 玄武と同様の長期構造 |
| DM-safe-2 | 13M | 中程度 |
| Ave-X | 5M | 短期。FoF分散効果で自己相関が薄まる |
| DM5 | 15M | 中程度 |

### 全PF調子分類（36M窓）

| 分類 | 条件 | 該当数 | 解釈 |
|------|------|--------|------|
| Improving | p≤0.10 かつ CI下限>0 | 0体 | 統計的に有意な改善トレンドを持つPFはゼロ |
| Stable | p≤0.10 かつ CIが0を跨ぐ | 6体 | 有意だが方向不明確 |
| Declining | p≤0.10 かつ CI上限<0 | 12体 | 統計的に有意な下降トレンド |
| Inconclusive | p>0.10 | 74体 | 傾きがノイズと区別できない |

主要PFの傾き:
- DM7+(玄武): slope=-0.00346/月, **Declining** — エッジ消失の兆候
- DM6(白虎): slope=-0.00143/月, Inconclusive
- DM2(青龍): slope=-0.00066/月, Inconclusive
- DM3(朱雀): slope=-0.00048/月, Inconclusive
- DM-safe: slope=+0.00045/月, Inconclusive
- Ave-X: slope=+0.00054/月, Inconclusive

### 実運用への示唆

1. **Improving(好調)が0体**: 統計的に有意に改善中のPFは存在しない。殿の直感を支持
2. **DM7+(玄武)のDeclining判定**: 四神の中で唯一の有意下降。モニタリング対象
3. **大多数がInconclusive(74/92)**: DM戦略の本質的特性（レジーム切替型）を反映
4. **窓幅36Mの限界**: レジーム変化検出率38%は低い。補完手段が将来課題

### 成果物

| ファイル | 内容 |
|---------|------|
| `outputs/charts/cmd270_phaseA_acf.png` | ACFプロット(代表PF8体) |
| `outputs/charts/cmd270_phaseB_window_comparison.png` | 4窓幅比較チャート |
| `outputs/charts/cmd270_phaseC_slope_ranking.png` | 全PFフォレストプロット(傾き+CI) |
| `outputs/charts/cmd270_phaseC_slope_ranking.csv` | 全PFランキング(CSV) |
| `scripts/analysis/cmd270_monthly_return_slope.py` | 分析スクリプト |

---

## SPY超過リターン(α)分析 (cmd_271)

cmd_270の「生リターン傾き」に対し、市場βを除去したα傾きを追加分析。

- α定義: `alpha_t = PF_monthly_return_t - SPY_monthly_return_t`
- SPY月次リターン: `experiments.db daily_prices` から Open-to-Open で算出（RULE09準拠）
- SPY統計（2000-02〜2026-02, 313 months）: 平均 `0.7439%/月`, 標準偏差 `4.5151%/月`

### α分類基準と全PFサマリー

| 窓幅 | Alpha-Positive | Alpha-Neutral | Alpha-Negative | 解釈 |
|------|----------------|---------------|----------------|------|
| 12M | 0 | 90 | 2 | 短期では大半が中立、2体のみα負 |
| 24M | 0 | 92 | 0 | 全PFが中立（識別力が低い） |
| 36M | 0 | 82 | 10 | 長期で10体がα負、82体はSPY並み |

3窓幅すべてで `Alpha-Positive=0`。統計的に有意な「α改善」PFは確認されなかった。
推奨: **36M**（24Mは識別力不足、12Mは短期ノイズ大）

### β除去前後の判定変化（cmd_270 36Mとの比較）

| 変化タイプ | 件数 | 内容 |
|-----------|------|------|
| Other | 80 | 判定の実質変化なし |
| True-decline | 10 | raw=Declining かつ α=Alpha-Negative（真のエッジ消失） |
| Market-masked | 2 | raw=Declining だが α=Alpha-Neutral（市場要因で見かけ悪化） |
| Market-carried | 0 | 該当なし |

- Market-masked（2）: `95db7c30`, `9ec5ef18`
- True-decline（10）: `87c64386`, `5c06d995`, `3f54546a`, `9834480c`, `e37d84fb`, `ee5d1a32`, `cff7778c`, `94360073`, `DM7+`, `3b2eecab`

### 実運用への示唆（α視点）

- 殿の哲学: **「ベータの除去は大事。本当にアルファがあるかどうかがわかる」**
- rawで不調に見えるPFの一部（2/12）は市場要因を除くと中立であり、即時除外は早計
- 10PFはβ除去後もα負で、真のエッジ消失候補として優先監視対象
- PF評価は「raw + α」の二段判定を標準化する

---

## エッジ残存率分析 (cmd_272)

殿考案の「エッジ残存率」指標。

**定義**: エッジ残存率 = 直近12Mα ÷ 全期間α × 100%
- 100%超 = エッジ拡大中、0-100% = エッジ部分残存、0%未満 = エッジ逆転

**殿の指摘（重要）**:
- α中立（傾きゼロ）≠ α水準ゼロ。SPYを上回るPFが多いのに「中立」は理論側の解釈ミス
- 現実と理論の乖離がある場合、間違っているのは理論の方

**全体統計（92PF、全期間α正）**: Mean: 48%, Median: 32%, Std: 139%
- >100%（エッジ拡大）: 26PF, 0-100%（部分残存）: 38PF, <0%（逆転）: 28PF

**四神エッジ残存率**:

| PF | ランク(/92) | エッジ残存率 | 全期間α | 直近12Mα | 判定 |
|----|------------|-------------|---------|----------|------|
| DM6 | #56 | 9.3% | +2.92% | +0.27% | 大幅劣化 |
| DM7+ | #60 | 5.1% | +1.62% | +0.08% | 大幅劣化 |
| DM2 | #77 | -21.4% | +3.00% | -0.64% | エッジ逆転 |
| DM3 | #93(最下位) | -741.7% | +0.75% | -5.55% | 壊滅的逆転 |

---

## 3指標統合の結論 (cmd_270/271/272)

**統合判定**:
1. **rawリターン傾き**(cmd_270): 大半が"Inconclusive"
2. **α傾き**(cmd_271, 12M窓): 大半が"Alpha-Neutral"
3. **エッジ残存率**(cmd_272): Median 32% — 半数以上でエッジが3分の2以上縮小

3指標の整合性: rawとα傾きが「変化なし」でもER低い → 「急速な劣化」ではなく「全期間にわたる緩やかなα低下」を示唆。四神(DM2/3/6/7+)は3指標全てで低評価。

**成果物**:
- `scripts/analysis/cmd272_edge_retention_rate.py`
- `outputs/charts/cmd272_edge_retention_histogram.png`
- `outputs/charts/cmd272_edge_retention_ranking.png`
- `outputs/charts/cmd272_edge_retention_ranking.csv`
- `outputs/charts/cmd272_three_indicator_summary.png`
- `outputs/charts/cmd272_three_indicator_summary.csv`

---

## §20. ルックアヘッドバイアス検証 (cmd_276)

### 調査概要

| 系統 | 偵察者 | 対象 | 結果 |
|------|--------|------|------|
| 本番パイプライン | 佐助(subtask_276_a) | sync-standard/sync-fof → recalculate_history_fast, 全14BB, FoF, monthly_returns | **LA未検出** |
| GSバックテスト | 霧丸(subtask_276_b) | 全5忍法GS実装 | **LA未検出** |
| 統合判定 | 影丸(subtask_276_integ) | 上記2報告の突合+盲点分析 | **LA未検出** |

### 本番パイプライン検証結果

**全14BBの時点制御**:
- Momentum系: `get_momentum_value_at_date()` で `<=target_date` 参照（`base.py:152-190`）
- MultiView/SingleView: 明示的に `df.index<=target_date` カット
- ComponentPrice/MonthlyReturnMomentum: `year_month→月末変換→dt>target_date除外`
- SafeHaven/EqualWeight/CashTerminal/KalmanMeta: 市場データ参照なし（LA不可）

**FoFタイミング(RULE03/RULE08)**: 月初リバランス日にのみパイプライン実行。RULE01-03,09,10いずれも実装一致。

### GSバックテスト検証結果

全5忍法のGSスクリプトにおいて将来データ参照は未検出。低リスク所見2件:
1. **drop_latest**: データ欠損時の挙動に注意が必要だがLAバイアスではない
2. **門番(monban)のexperiments.db依存**: ポイントインタイムのスナップショットであるためLAリスクは低い

### 残存リスク

| ID | 深刻度 | 内容 | 修正方向性 |
|----|--------|------|-----------|
| R1 | medium | 当日終値未確定ガードがコード上に不在 | `最終確定営業日`算出→calc_end_date固定 |

### 盲点と注記

1. StockData APIの当日データ返却仕様は未検証（外部依存）
2. データ同期パス（download_all_prices.py → experiments.db）のLA混入は未検証
3. 霧丸報告はdeploy_task.sh上書き消失(L103再発)から家老復元

### 最終判定

**本番パイプライン・GSバックテスト双方にルックアヘッドバイアスは確認されず。** 信頼度: **高**。

- 本番14BB全てがtarget_date以前のデータのみを参照することをコードレベルで確認
- GS全5忍法が過去データのみで計算していることを確認
- 残存リスクR1は運用境界の課題であり、LAバイアスそのものではない
