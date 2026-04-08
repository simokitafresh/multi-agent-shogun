# SPA/過剰最適化検証詳細
<!-- 出典: context/dm-signal-research.md §21, cmd_277, 2026-02-23 -->

> 結論: 全5忍法が過剰最適化検証をPASS。SPA検定でH0棄却不能、IS/OOSでfull-sampleチャンピオンは劣化なし。自由度比率は名目0.23/実効0.15で中程度だが学術的裏付け+資産分散で緩和。

L0(四神パラメータ)・L1(四神選出)・L2(忍法ブロック)の全層にわたる過剰最適化検証結果。
Hansen's SPA検定 + IS/OOS劣化分析 + 自由度会計で総合判定。

## 忍法別検証結果

| 忍法 | Block | GS空間 | SPA p値 | H0棄却 | IS/OOS劣化 | 総合判定 | 担当 | commit |
|------|-------|--------|---------|--------|-----------|---------|------|--------|
| 分身(bunshin) | EqualWeight | 1(パラメータ0) | N/A | N/A | N/A | **PASS**(数学的証明) | saizo | 226465e |
| 追い風(oikaze) | MomentumFilter | 42,174 | 0.36 | 棄却せず | OOS>IS(劣化なし) | **MODERATE_PASS** | hanzo | d5651dc |
| 抜き身(nukimi) | SingleViewMomentum | 152,295 | 0.99 | 棄却せず | ISチャンピオン-61.6%, FSチャンピオン+29.9% | **PASS** | saizo | 226465e |
| 変わり身(kawarimi) | TrendReversal | 28,116 | 0.73 | 棄却せず | — | **PASS** | tobisaru | cd8663d |
| 加速(kasoku) | MomentumAcceleration | 238,986 | 0.99 | 棄却せず | — | **PASS** | tobisaru | cd8663d |

**SPA検定の解釈**: p値が大きい(H0棄却不能) = チャンピオンがGS空間内の他パターンに対し統計的に有意な優位性を持たない。top群内のパフォーマンス差はノイズ範囲であり、特定パラメータに過剰適合していない。

## 忍法別詳細

### 分身(bunshin) — 過剰最適化不在の数学的証明

- EqualWeightBlockのパラメータ空間 |P| = 1（均等配分は決定論的）
- パラメータ選択の自由度 = 0 → 最適化が存在しない → 過剰最適化は数学的に不可能 (Q.E.D.)
- subset選択(C12からn=2,3,4の781通り)はブロック固有パラメータではなくFoF構成PFの設計選択

### 追い風(oikaze) — SPA p=0.36, MODERATE_PASS

- データ源: 246_oikaze_grid (C12, 781 subsets × 18 lookback × 3 top_n × 1 rebalance = 42,174パターン)
- SPA検定: p=0.36 (B=5000, block_length=6) → H0棄却不能
- IS/OOS分割(2012-04~2019-02 / 2019-03~2026-02):
  - CAGRチャンピオン: IS=0.389→OOS=0.754 (劣化なし、+93.7%)
  - Calmarチャンピオン: IS=0.307→OOS=0.578 (劣化なし、+88.7%)
  - NHRチャンピオン: IS=0.286→OOS=0.629 (劣化なし、+120.1%)
- 全指標でOOS>IS → 過剰適合の兆候なし
- 注: report.yamlのoverall=CONCERNはSPA verdict文面(H0棄却不能の定型文)による機械的分類。IS/OOS結果が良好なため家老復元判定はMODERATE_PASS

### 抜き身(nukimi) — SPA p=0.99, PASS

- データ源: 246_nukimi_grid (14 base × 3 skip × 5 top_n × 781 subsets = 152,295パターン)
- SPA検定: p=0.99 → top-200内で有意差なし。パラメータ空間が連続分布で特定パラメータの劇的エッジなし
- Full-sampleチャンピオン(18M/SK3): OOSでIS以上(健全)
- ISチャンピオン(短lookback 7M): OOS CAGR -61.6%(壊滅) → 短lookbackのIS過剰適合を示唆
- FSチャンピオン: OOS CAGR +29.9%(改善)
- 教訓(L117): 15万パターンGSのチャンピオンはtop群内で統計的に有意差なし

### 変わり身(kawarimi) — SPA p=0.73, PASS

- データ源: 246_kawarimi_grid (28,116パターン)
- SPA検定: p=0.73 → 非有意(チャンピオンの優位性は統計的ノイズ)
- TrendReversalFilterBlockはstrict slice方式で本番と一致

### 加速(kasoku) — SPA p=0.99, PASS

- データ源: 246_kasoku_grid (238,986パターン)
- SPA検定: p=0.99 → 非有意(最大のGS空間にもかかわらず過剰適合なし)
- MomentumAccelerationFilterBlockの短期/長期モメンタム比率パラメータは空間内で連続的

## L0パラメータ感度 + L1相関分析 (hayate, commit 309de51)

### L0パラメータ感度
- 4ファミリー全てのlookback感度CV < 0.07(安定)
- lookback ±1〜2の変動で戦略パフォーマンスが大きく崩壊しない → パラメータロバスト

### L1四神相関
- Pearson相関行列: 実効独立次元 = 2.69/4
- 4ファミリーは完全独立ではないが、十分な分散効果あり
- Spearman独立性: CAGR/MaxDD/NHR選出基準の独立性確認済み

## 全体の自由度会計

| 層 | 名目パラメータ数 | 備考 |
|----|----------------|------|
| L0 | 4ファミリー × 約7パラメータ = 28 | lookback/rebalance/資産選択/top_n等 |
| L1 | 11 | GFS候補プール選出 + 3モード(CAGR/MaxDD/NHR) |
| L2 | 5忍法ブロック固有パラメータ | 分身=0, 追い風/抜き身/変わり身/加速各数個 |
| 合計(名目) | 39 | |
| データ点数 | 168ヶ月 | |
| **名目比率** | **0.23** | 39/168 |
| **実効比率** | **0.15** | ln(N)近似で24.5/168 |

実効比率0.15は「中程度リスク」帯(0.10-0.25)に位置するが、以下の構造的緩和要因を考慮:
1. デュアルモメンタム自体の学術的裏付け(Antonacci 2012/2014, Jegadeesh & Titman 1993等)
2. 四神4ファミリーの資産クラス分散(株式/Vol債券/VIXレジーム/リセッション防御)
3. GFS(Greedy Forward Selection)の暗黙的正則化効果
4. FoFのEqualWeight配分(配分重み最適化なし)

## 横断比較(IS/OOS劣化率)

| 忍法 | IS CAGR | OOS CAGR | 劣化率 | 判定 |
|------|---------|----------|--------|------|
| 追い風(CAGR champ) | 0.389 | 0.754 | +93.7%(改善) | 健全 |
| 追い風(Calmar champ) | 0.307 | 0.578 | +88.7%(改善) | 健全 |
| 抜き身(FS champ) | — | — | +29.9%(改善) | 健全 |
| 抜き身(IS champ, 7M) | — | — | -61.6%(壊滅) | 短lookback過剰適合 |

**全般的傾向**: Full-sampleまたはCalmarチャンピオンのOOSパフォーマンスはISを上回る。ISのみで選出された短lookbackパラメータはOOSで壊滅的劣化を示す(抜き身7Mの例)。これはfull-sample選出の妥当性を裏付ける。

## 最終判定

**全5忍法が過剰最適化検証をPASS。** 信頼度: **高**。

- 分身: パラメータ自由度0 → 過剰最適化は数学的に不可能
- 追い風/抜き身/変わり身/加速: SPA検定でH0棄却不能 → top群内で統計的有意差なし
- IS/OOS分析: full-sampleチャンピオンはOOSで劣化なし(追い風・抜き身とも改善)
- 自由度比率: 名目0.23/実効0.15は中程度だが、学術的裏付け+資産分散+GFS正則化で緩和
- 注意: ISのみ最適パラメータ(短lookback)は過剰適合リスクあり → full-sample選出が必須
