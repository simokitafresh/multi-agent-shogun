# DM-Signal 新規5指標 設計書 v0 — 殿原文(2026-08-08 17:00頃受領・改変禁止)

> 保存者: shogun。殿がターミナルへ直接投入した原文の全文保存。歴史修正禁止原則によりタイムスタンプ・内容の事後修正を禁ずる。
> 実装設計書(将軍作成)→ `docs/research/dm-signal-5metrics-selection-v0_20260808.md`

---

# DM-Signal 新規5指標 設計書 v0
## 102 Portfolio Selection / Robustness Metrics

## 0. 目的

現在DM-Signalには102個のPortfolio（以下PF）が存在する。

既存Metricsには以下がすでに存在する。

- CAGR
- Arithmetic / Geometric Return
- Standard Deviation
- Sharpe Ratio
- Sortino Ratio
- Calmar Ratio
- Maximum Drawdown
- Drawdown Length
- Recovery Time
- Underwater Period
- Avg Underwater Period
- Skewness
- Kurtosis
- VaR
- Volatility Drag
- Consecutive Loss
- Alpha
- Beta
- Information Ratio
- Treynor Ratio
- Upside Capture
- Downside Capture
- Up/Down Ratio
- Up/Down Spread
- Rolling Return
- Positive Rolling Period
- Benchmark Win Rate
- Regime Analysis
- Min Months vs Benchmark
- その他既存指標

問題は「分析指標が不足している」ことではない。

現在の本質的問題は、

> 102PFの中から、将来運用するPFを何を基準に選択すべきか

というPortfolio Selection問題である。

したがって今回追加する指標は、単純な過去Performanceの別表現ではなく、

1. 開始時点への頑健性
2. Drawdown経路への頑健性
3. Alphaの時間的一貫性
4. Market Regimeへの頑健性
5. Arithmetic EdgeをCompoundingへ変換する効率

を測定する。

新規5指標：

1. RRR — Rolling Robustness Ratio
2. DDA — Drawdown Area
3. ACS — Alpha Consistency Score
4. RRS — Regime Robustness Score
5. ECR — Edge Conversion Ratio

---

# 1. 基本設計思想

## 1.1 今回の目的

各指標について、

「過去に高かったPF」

を見つけること自体を目的としない。

最終目的は、

> 指標t時点の順位が、t以降のPF品質と関係するか

をWalk-Forwardで検証すること。

したがって全指標は必ず、

- Point-in-Time計算可能
- Future Data不使用
- Look-ahead Bias禁止
- Cross-sectional Ranking可能

でなければならない。

---

## 1.2 最適化禁止

v0では以下を禁止する。

- 指標間Weight最適化
- パラメータ探索
- PFごとの異なるParameter
- Layerごとの異なる定義
- Threshold最適化
- Backtest結果を見て式を変更
- 複数LookbackのBest選択
- 合成Super Scoreの作成

最初に定義を固定し、全PFへ同一適用する。

---

## 1.3 指標の方向

全指標について最終的に、

HIGHER = BETTER

へ統一する。

DDAなど「低い方が良い」Raw Metricについては、
Ranking段階で符号反転する。

Raw Data自体は元の意味を保持する。

---

# 2. RRR
# Rolling Robustness Ratio

## 2.1 目的

PFのPerformanceが、

「特定の開始時点に依存していないか」

を測定する。

CAGRは全期間の始点・終点1組しか使用しない。

RRRはRolling Windowを使用することで、

> 投資開始時点をずらしてもBenchmark超過収益が安定していたか

を評価する。

---

## 2.2 Input

月次PF Return：

r_p,t

Benchmark Return：

r_b,t

v0 Rolling Window：

36 months

既存の3Y Rollingデータを利用可能。

---

## 2.3 Rolling Excess CAGR

各Rolling 36M Windowについて、

PF CAGR：

CAGR_p,t

Benchmark CAGR：

CAGR_b,t

を計算。

Rolling Excess CAGR：

X_t = CAGR_p,t - CAGR_b,t

---

## 2.4 Median

m = Median(X_t)

---

## 2.5 MAD

MAD = Median(|X_t - m|)

---

## 2.6 RRR

RRR = m / MAD

ただし、

MAD = 0

の場合はdivision-by-zeroを避ける。

推奨：

RRR = NULL

として特殊値を作らない。

---

## 2.7 解釈

RRRが高い：

- Rolling Benchmark Excess Returnが高い
- 開始時点による結果のばらつきが小さい

RRRが低い：

- 一部期間だけPerformanceが高い
- Start-Date Dependencyが大きい

---

## 2.8 理論的位置

Sharpe Ratio：

Return Time SeriesのSignal / Noise

RRR：

Rolling Long-Horizon Excess Performanceの
Signal / Start-Date Dispersion

したがってSharpeとは異なる。

---

## 2.9 UI表示名

Rolling Robustness

補助表示：

Median Excess
MAD Excess
36M Window Count

---

# 3. DDA
# Drawdown Area

## 3.1 目的

Maximum Drawdownの欠点を補完する。

MDDは、

「最悪の一点」

しか測定しない。

しかし投資家が経験する負担は、

- Drawdownの深さ
- Drawdownの長さ

の両方に依存する。

DDAは全期間のUnderwater状態を積分する。

---

## 3.2 Wealth Index

PF NAV：

V_t

Running Maximum：

H_t = max(V_0 ... V_t)

Drawdown：

D_t = V_t / H_t - 1

D_t <= 0

---

## 3.3 Drawdown Area

Raw Drawdown Area：

DDA_raw = (1/T) Σ |D_t|

月次データの場合は全月について計算。

---

## 3.4 単位

decimal または %

例：

DDA = 0.042

なら、

平均的にPeakから4.2%水面下にいたことを意味する。

---

## 3.5 Ranking方向

DDAは小さい方が良い。

Selection用Score：

DDA_score = -DDA_raw

またはRank時のみascending。

Raw値そのものは変更しない。

---

## 3.6 MDDとの違い

Portfolio A：

一度 -30%
すぐ回復

Portfolio B：

-10%前後を長期間継続

MDDではAが悪い。

DDAではBの方が悪くなる可能性がある。

したがって、

MDD = Depth Extreme

DDA = Total Underwater Burden

と定義する。

---

## 3.7 Ulcer Indexとの違い

Ulcer Index：

UI = sqrt(mean(D_t^2))

DDA：

DDA = mean(|D_t|)

UIは深いDDを二乗で強くPenaltyする。

DDAは線形。

v0ではInterpretabilityを優先してDDAを採用する。

UIとの比較検証は別実験とする。

---

## 3.8 UI表示名

Drawdown Area

説明：

Average distance below previous equity high.

---

# 4. ACS
# Alpha Consistency Score

## 4.1 目的

Full-period Alphaが、

「一部の期間だけで作られたものではないか」

を測定する。

Full-period Alphaだけでは、

Alphaの時間的一貫性は分からない。

ACSはRolling Alphaを用いる。

---

## 4.2 Model

各36M Rolling Windowについて、

r_p,t - r_f,t
=
alpha
+
beta × (r_b,t - r_f,t)
+
epsilon_t

をOLS推定。

v0：

36 months fixed

Benchmarkは既存Benchmarkを使用。

Risk-Free Rateは既存Alpha計算と完全に同一仕様。

---

## 4.3 Rolling Alpha

各Windowについて年率化Alpha：

alpha_t

を取得する。

---

## 4.4 Median Rolling Alpha

a_med = Median(alpha_t)

---

## 4.5 Alpha MAD

a_mad = Median(|alpha_t - a_med|)

---

## 4.6 ACS

ACS = a_med / a_mad

a_mad = 0 の場合：

NULL

---

## 4.7 補助指標

同時に以下も保存する。

Alpha Positive Rate：

APR = count(alpha_t > 0) / N

P10 Rolling Alpha：

Alpha_P10 = percentile(alpha_t, 10)

これらはACSには合成しない。

---

## 4.8 解釈

ACS高：

- Alphaが高い
- Alphaの時系列変動が小さい

ACS低：

- Full-period Alphaが高くても
  一部Windowに依存している可能性

---

## 4.9 RRRとの違い

RRR：

Benchmarkに対する実現超過Return

ACS：

Beta Exposureを除去したRegression Alpha

したがって、

RRR ≠ ACS

両者のRank correlationを後で測定する。

相関が極端に高ければ冗長性を評価する。

---

## 4.10 UI表示名

Alpha Consistency

補助表示：

Median Rolling Alpha
Alpha MAD
Positive Alpha %

---

# 5. RRS
# Regime Robustness Score

## 5.1 目的

特定Market Regimeに依存してPerformanceが成立していないかを測る。

既存Regime分類：

- Up Market
- Sideways Market
- Down Market

をそのまま使用する。

Regime定義を今回変更しない。

---

## 5.2 Active Return

各Regimeについて既存Active Return：

A_up
A_side
A_down

を使用する。

---

## 5.3 RRS

v0では極端に単純化する。

RRS = min(
    A_up,
    A_side,
    A_down
)

---

## 5.4 解釈

RRSは、

> 最も苦手なMarket Regimeにおいて、
> どれだけBenchmark超過Returnを残したか

を意味する。

例：

Up = +12.0%
Sideways = +2.4%
Down = +3.5%

なら、

RRS = +2.4%

となる。

---

## 5.5 なぜ平均を使わないか

平均を使うと、

Up Marketで非常に大きく勝ち、
Down Marketで大きく負けるPF

が高評価になる可能性がある。

RRSの目的は平均Performanceではない。

Worst-Regime Robustnessを測る。

---

## 5.6 なぜ重みを使わないか

Regime Frequency Weightは禁止。

理由：

頻度加重すると、
結局多く発生したRegimeへの適合度になる。

RRSは意図的にmin()のみを使用する。

Parameterなし。

Weightなし。

---

## 5.7 注意

RegimeごとのSample Sizeを必ず保存する。

n_up
n_side
n_down

Sample Sizeが極端に少ないRegimeがある場合は
RRS Reliability Flagを付ける。

ただしv0ではThresholdによる除外はしない。

---

## 5.8 UI表示名

Regime Robustness

説明：

Worst active return across Up / Sideways / Down regimes.

---

# 6. ECR
# Edge Conversion Ratio

## 6.1 目的

Arithmetic Returnとして観測されるEdgeが、

実際のCompounded Growthへどの程度変換されているかを測定する。

既存Volatility Drag：

VDrag = Arithmetic Mean - Geometric Mean

は絶対差。

ECRはこれをRelative Efficiencyとして表現する。

---

## 6.2 Input

Monthly Arithmetic Mean：

mu

Monthly Geometric Mean：

g

必ず同一Frequencyで比較する。

Annual Arithmetic MeanとAnnual CAGRを混在させない。

---

## 6.3 ECR

ECR = g / mu

---

## 6.4 解釈

例：

Arithmetic Mean = 6.57%
Geometric Mean = 6.10%

ECR：

6.10 / 6.57
=
0.928

= 92.8%

意味：

Arithmetic Edgeの約92.8%が
Geometric Growthへ変換されている。

---

## 6.5 理論背景

Small-return approximation：

g ≈ mu - sigma^2 / 2

したがって、

ECR
≈
1 - sigma^2 / (2mu)

ECRは概念的に、

Variance Tax relative to Edge

を測定している。

---

## 6.6 Edge Case

mu <= 0

の場合、ECRは直感的解釈を失う。

したがって：

if mu <= 0:
    ECR = NULL

とする。

無理に負値やInfinityを表示しない。

---

## 6.7 UI表示名

Edge Conversion

表示：

92.8%

説明：

Share of arithmetic return retained as geometric growth.

---

# 7. 5指標の役割分離

5指標は以下の異なるDimensionを測定する。

RRR
=
WHEN
=
開始時点への頑健性

DDA
=
PATH
=
投資経路の負担

ACS
=
ALPHA
=
Beta調整後Edgeの時間的一貫性

RRS
=
REGIME
=
市場環境への頑健性

ECR
=
COMPOUNDING
=
Arithmetic Edgeの複利変換効率

Conceptual Map：

             Portfolio Robustness
                     |
    ---------------------------------------
    |          |          |        |       |
   WHEN       PATH      ALPHA    REGIME  COMPOUND
    |          |          |        |       |
   RRR        DDA        ACS      RRS     ECR

---

# 8. 重要：現時点では合成しない

v0では以下を禁止する。

CompositeScore =
w1*RRR
+w2*DDA
+w3*ACS
+w4*RRS
+w5*ECR

これは実装しない。

理由：

Weight Selection自体がOptimizationになるため。

まず5指標を独立に評価する。

---

# 9. 102PF Selection実験

## 9.1 仮説

各指標のCross-sectional Rankは、

将来PF Qualityに情報を持つか。

---

## 9.2 観測時点

各月末 t

その時点までに利用可能なデータのみを使用して、

102PFそれぞれについて、

RRR_t
DDA_t
ACS_t
RRS_t
ECR_t

を計算。

---

## 9.3 Cross-sectional Rank

各月102PFをRanking。

Higher-is-betterへ統一。

RRR：descending
DDA：ascending
ACS：descending
RRS：descending
ECR：descending

---

## 9.4 Forward Evaluation

Rank at t

vs

Quality at t+1
Quality at t+3
Quality at t+6
Quality at t+12

v0では最初にt+1のみでもよい。

Multiple Horizon比較をする場合は
別Experimentとして明示する。

---

# 10. Benchmark Selection Rules

新指標の価値を判断するため、
既存の単純Selection Ruleと比較する。

Control：

A. CAGR Rank
B. Sharpe Rank
C. Alpha Rank
D. Calmar Rank
E. Random Selection
F. Equal Weight 102PF

Experimental：

G. RRR Rank
H. DDA Rank
I. ACS Rank
J. RRS Rank
K. ECR Rank

目的：

新指標が単純CAGR/Sharpe/Alphaを
上回るSelection Informationを持つか確認する。

---

# 11. 評価方法

各指標について最低限：

1. Spearman Rank Correlation
2. Top / Middle / Bottom Group Forward Quality
3. Top-minus-Bottom
4. Positive RankCorr Month %
5. First-half / Second-half Direction
6. Layer別結果
7. Existing MetricとのRank Correlation

を出力する。

---

# 12. 冗長性確認

重要。

新指標が既存指標とほぼ同じRankingしか作らない場合、
新規採用価値は低い。

各月Cross-sectionで以下を計算：

corr_rank(RRR, CAGR)
corr_rank(RRR, Sharpe)
corr_rank(RRR, Alpha)

corr_rank(DDA, MDD)
corr_rank(DDA, AvgUWP)
corr_rank(DDA, Calmar)

corr_rank(ACS, Alpha)
corr_rank(ACS, InformationRatio)

corr_rank(RRS, UpDownRatio)
corr_rank(RRS, Alpha)

corr_rank(ECR, VDrag)
corr_rank(ECR, Sharpe)

平均RankCorrを報告する。

目的：

「名前が新しいだけの既存指標」
を排除する。

---

# 13. Point-in-Time制約

最重要。

t月末に計算する指標は、

t以前のデータのみ使用。

禁止：

- Full-history metricを過去月へ逆流
- Future benchmark regime利用
- Future Rolling Window利用
- Full-period normalization
- Full-period percentile
- 全期間102PF Rankを過去時点へ使用

すべてPoint-in-Time。

---

# 14. Minimum History

36M Rollingを使用するRRR / ACSには最低履歴が必要。

原則：

history < 36 months
→ NULL

ただし36MちょうどではRolling sampleが1個しかなく
MADが計算不能。

したがって実質的には
複数Rolling Windowが存在する期間から有効となる。

Minimum Window Countを保存する。

v0では恣意的なMinimum Count Filterを設定せず、
Sample Countを結果に必ず併記する。

---

# 15. 出力Schema

portfolio_id
date
layer

rrr
rrr_median_excess
rrr_mad
rrr_window_count

dda

acs
acs_median_alpha
acs_alpha_mad
acs_positive_rate
acs_p10_alpha
acs_window_count

rrs
regime_active_up
regime_active_sideways
regime_active_down
regime_n_up
regime_n_sideways
regime_n_down

ecr
arithmetic_mean_monthly
geometric_mean_monthly

---

# 16. Quality Check

以下を自動検証する。

## RRR

- Rolling Windowが未来を含まない
- Excess = PF - Benchmark
- Median / MAD実装確認

## DDA

- NAV Peak計算確認
- Peak時D=0
- Drawdown時D<0
- DDA>=0

## ACS

- BenchmarkとPF期間一致
- Risk Free定義一致
- Rolling regressionにFuture Dataなし

## RRS

- 既存Regime分類をそのまま使用
- Active Return定義一致
- min()が正しく選択されている

## ECR

- Arithmetic/Geometric Frequency一致
- mu<=0 → NULL
- percentage vs decimal混同禁止

---

# 17. 実験の成功条件

固定数値Thresholdは置かない。

以下を観察する。

- Forward RankCorrの方向
- 正月率
- Top-Bottom Spread
- 前半/後半一貫性
- Layer横断一貫性
- Existing Metricsとの差別化

特に重要なのは、

「過去Performanceとの相関が低いのに、
Forward Qualityとの関係があるか」

である。

これが成立すれば、
新規Selection Informationを持つ可能性がある。

---

# 18. v0でやらないこと

- 5指標のWeight合成
- Machine Learning
- RegressionによるWeight推定
- PCA
- Optimization
- Genetic Algorithm
- Best Lookback探索
- Best Horizon探索
- Threshold探索
- Layer別Parameter
- Market Regime定義変更
- Indicator Combination Search

まず単独指標として情報量を確認する。

---

# 19. 次段階

v0結果確認後のみ進む。

Phase 1：
5指標単独Selection Test

Phase 2：
既存Metricsとの冗長性確認

Phase 3：
Survival / Robustness / Edge の3-stage filtering

Phase 4：
Pareto Frontier Selection

Phase 5：
Correlation Clusterによる類似PF排除

Phase 6：
候補PF集合に対するDynamic Selection
（ρ(1)等のState Variable）

最終構造候補：

102 PF
  ↓
Structural Screening
  ↓
Robustness Selection
  ↓
Non-dominated PF
  ↓
Correlation Clustering
  ↓
Candidate Set
  ↓
Dynamic State Selection
  ↓
Live Portfolio

---

# 20. 設計原則

今回の5指標の目的は、

「最も美しいBacktestを見つけること」

ではない。

目的は、

> 102PFの中から、
> 過去の一時的な勝者ではなく、
> 将来もEdgeが残る可能性の高いPFを
> Point-in-Timeで識別できるか

を検証することである。

したがって、

Performanceの高さより
Selection Informationの有無を優先する。

新しい指標がCAGRやSharpeと同じPFしか選ばないなら、
その指標は不要である。

逆に、

過去Performanceと異なるRankingを作りながら、
Forward Qualityを識別できるなら、

それが今回探している
「102PFから選ぶ基準」
の候補となる。
