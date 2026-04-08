---
# Generated: 2026-03-26
# Source: Background research agent output (cmd_1410)
# Conversation: a4235eac-de13-4036-add6-9df09ba804ea
# Contents: Nested FoF portfolio construction, momentum-of-momentum,
#           regime detection, Kelly criterion implementation guide
---
# Nested FoF: Momentum, Regime Detection, and Kelly Criterion Implementation Guide

> Comprehensive research on cutting-edge portfolio construction for a Fund-of-Funds
> of momentum strategies. Part 1 covers theory and frameworks; Part 2 provides
> concrete Python implementations for momentum-of-momentum selection, VIX/SMA
> regime detection, and Kelly criterion position sizing.

---

# Part 1: Cutting-Edge Portfolio Construction Theories and Frameworks (2024-2025)

## 1. Beyond Modern Portfolio Theory

### 1.1 Hierarchical Risk Parity (HRP) and Variants

**Core Framework**: HRP, introduced by Marcos Lopez de Prado (2016), replaces the full covariance inversion of Markowitz with a three-step process: (1) hierarchical clustering of assets by correlation distance, (2) quasi-diagonalization of the covariance matrix, and (3) top-down inverse-variance allocation through recursive bisection. The key advantage is that estimation errors remain contained within clusters and do not propagate across the entire portfolio.

**Recent Advances (2024-2025)**:

- **Return-Adjusted HRP and Schur Portfolios** (2024): A new approach models covariance matrices as adjacency structures of hierarchical (Sierpinski) graphs and uses the Schur complement method to recursively reduce the optimization problem. This preserves full covariance information while achieving exponential computational efficiency -- only 3x3 matrix inversions are needed regardless of portfolio size. This bridges the gap between Markowitz (full information, expensive) and HRP (fast, information loss). [Paper: arxiv.org/html/2503.12328v1]

- **Tail Dependence Clustering**: Instead of standard Pearson correlation, newer variants cluster assets using tail dependence measures, which is particularly relevant for momentum strategies where tail risk and crash co-movements matter far more than average correlations.

- **Hierarchical Equal Risk Contribution (HERC)**: Extends HRP by allowing 32 different risk measures (not just variance) for the allocation step, including CVaR, Maximum Drawdown, and Conditional Drawdown at Risk. Available in Riskfolio-Lib 7.2.

- **Fast HRP Methods**: 2024 research on computational efficiency enables HRP to scale to very large portfolios with constrained variants.

**Key Insight for FoF**: HRP is naturally suited for a Fund-of-Funds structure where strategies cluster into groups (e.g., momentum types, timeframes). The hierarchical structure prevents a single misestimated correlation from destabilizing the entire allocation.

### 1.2 Nested Clustered Optimization (NCO)

NCO (Lopez de Prado, 2019) addresses both sources of instability in portfolio optimization through a two-stage nested approach:

1. **Inner optimization**: Within each cluster, compute optimal weights using the full training data
2. **Outer optimization**: Between clusters, compute weights using out-of-sample estimates from cross-validation of the inner optimizers

The final portfolio weights are the dot product of inner and outer weights.

**2024 Modification** (World Scientific, 2024): NCO has been reformulated using spectral clustering and Minimum Spanning Tree (MST) instead of the original K-Means, combined with Random Matrix Theory for covariance denoising. The Marcenko-Pastur distribution separates signal eigenvalues from noise eigenvalues before clustering, achieving a 59.85% RMSE reduction in estimation error compared to undenoised covariance. [Reference: worldscientific.com/doi/10.1142/S0129183124500980]

**Practical Recommendation**: For a FoF with 12-33 momentum strategies, NCO with denoised covariance is the strongest candidate. The inner estimator should be minimum-variance (since momentum strategies already target returns), and the outer estimator should use equal-weight or inverse-variance (to avoid propagating estimation errors between clusters).

### 1.3 Network Risk Parity (Minimum Connectivity)

Network Risk Parity (2023-2024) replaces hierarchical clustering with graph-theoretic portfolio construction:

- Assets are nodes; correlations are edges
- The Minimum Spanning Tree (MST) extracts the core inter-asset structure
- Portfolio weights are determined by each asset's position in the network (central vs. peripheral)
- **Peripheral assets receive higher weights** because they provide genuine diversification

**Key Finding**: Network Risk Parity outperforms HRP as the number of portfolio constituents increases, because graph structures preserve more relationship information than trees. Investing in the peripheries of the correlation network provides superior diversification benefits. [Reference: link.springer.com/article/10.1057/s41260-023-00347-8]

### 1.4 Entropy-Based Diversification

**Meucci's Effective Number of Bets (ENB)**: Measures the Shannon entropy of variance contributions from uncorrelated risk factors. ENB = exp(-sum(p_i * log(p_i))) where p_i are the fractional variance contributions from PCA-derived uncorrelated factors. A portfolio with ENB = 1 has all risk in one bet; ENB = N means perfectly diversified across N independent bets.

**Maximum Diversification Portfolio (Choueifaty & Coignard)**: Maximizes the Diversification Ratio = (weighted sum of individual volatilities) / (portfolio volatility). The squared diversification ratio equals the effective number of independent risk factors.

**2024-2025 Extension**: Weighted Shannon Entropy integrated into mean-variance optimization. This distribution-free approach achieves higher diversification scores, more balanced allocations, and improved downside protection in heavy-tailed markets (e.g., crypto, volatile equity). Entropy-based portfolios showed higher Sharpe ratios and less negative CVaR versus both equal-weight and traditional mean-variance. [Reference: mdpi.com/2227-9091/13/12/253]

**Practical Recommendation**: Use ENB as a diagnostic metric. After constructing a FoF portfolio via HRP or NCO, compute ENB. If ENB is significantly less than the number of strategies, the portfolio has hidden concentration -- strategies that appear different are loading on the same factor.

### 1.5 Factor-Based Hierarchical Allocation

Multi-factor risk parity applies hierarchical allocation at the factor level rather than the asset level:

1. Decompose strategy returns into factor exposures (momentum, value, quality, etc.)
2. Apply risk parity across factors, not assets
3. Use hierarchical clustering to group factors that co-move

**2024 Result**: Integrated risk parity portfolios (2006-2022) showed "more stable risk-return profile than independently constructed strategies, especially in high volatility and down-market periods." [Reference: sciencedirect.com/science/article/abs/pii/S1057521923001709]

---

## 2. Momentum-Based Portfolio Construction

### 2.1 Combining Multiple Momentum Strategies

The CFA Institute (2025) tested 4,000+ momentum portfolio variations with Sharpe ratios ranging from 0.38 to 0.94. The key finding: **an equal-weighted composite of price momentum plus ten alternative momentum signals delivers superior risk-adjusted returns**. The alternative signals include:

| Signal Type | Description | Contribution |
|-------------|-------------|--------------|
| Fundamental momentum | Earnings surprises, analyst revisions | Uncorrelated with price momentum |
| Residual momentum | Firm-specific (market-neutral) patterns | Smoother, higher Sharpe |
| Anchor-based | Distance from 52-week high | Behavioral anchoring |
| Industry momentum | Sector trend propagation | Lead-lag capture |
| Factor momentum | Capital flows into styles | Meta-momentum |

**Practical Insight**: For a FoF of momentum strategies, diversifying across momentum signal types (not just lookback windows) is the primary source of improvement.

### 2.2 Time-Series Momentum vs Cross-Sectional Momentum

**Moskowitz, Ooi, Pedersen (2012)** established that TSMOM is distinct from cross-sectional momentum. Key difference: TSMOM uses an asset's own past return; XSMOM compares relative performance across peers.

**Critical Finding**: TSMOM retains a 1.09% monthly alpha (t-stat 5.40) even after controlling for cross-sectional momentum everywhere factors. The two are complementary, not redundant.

**For FoF Construction**:
- TSMOM strategies naturally scale position by conviction (signal strength determines allocation), making them suitable for absolute return
- XSMOM strategies are inherently relative (long winners, short losers), better suited for long-short structures
- Combining both provides genuine diversification because the alpha sources are distinct

### 2.3 Multi-Horizon Trend Following: The Barbell Discovery

**Landmark 2025 Finding** (arxiv.org/html/2510.23150v2): Traditional CTA strategies use 5 lookback windows (20d, 60d, 125d, 250d, 500d). This research proves that **the medium-term band (60-125 days) is structurally redundant**:

| Horizon | Sharpe | Correlation with Adjacent | Role |
|---------|--------|--------------------------|------|
| 20-day | 0.33 | 0.44 with longer | Crisis convexity, mean-reversion |
| 60-day | 0.21 | High | Redundant |
| 125-day | 0.21 | 0.84-0.90 with adjacent | Redundant |
| 250-day | 0.35 | Moderate | Transition zone |
| 500-day | 0.47 | Low with short | Persistent macro trends |

**Optimal Structure**: A "barbell" combining 20-day and 500-day lookbacks. Four horizons (excluding 125d) outperform five. The short-term component contributes disproportionate portfolio asymmetry (convex payoffs during reversals), while the long-term captures macro trends.

**Complementary Finding** (arxiv.org/html/2507.15876v1): The Sharpe-maximizing blend is approximately **17% short-term + 83% long-term** based on empirical data, though 50/50 is optimal when expected returns are equal.

### 2.4 Momentum Crash Protection

**The Problem**: Traditional price momentum has documented maximum drawdowns of -88%, with left-skewed, fat-tailed distributions. Crashes typically occur when markets rebound sharply after declines (momentum shorts rally hard).

**Volatility Scaling Solutions**:

- **Barroso & Santa-Clara (2015)**: Scale momentum exposure inversely to its own realized volatility. Result: virtually eliminated crashes, nearly doubled Sharpe ratio
- **Daniel & Moskowitz (2016)**: Dynamic scaling using forecasts of both momentum mean and variance. Improves on constant volatility scaling
- **2020 Extension**: Conditional scaling -- reduce risk exposure specifically in extreme high-volatility states, increase in low-volatility states. Significantly reduced drawdowns and tail risks across all major equity markets

**CFA Institute 2025 Result**: Volatility-managed momentum (RM_MOM) delivered ~18% annualized returns with drawdowns cut nearly in half compared to unmanaged momentum.

**Practical Recommendation for FoF**: At the individual strategy level, each momentum strategy should implement its own volatility scaling. At the FoF level, implement a second layer: scale overall portfolio exposure based on aggregate momentum volatility. This two-layer approach provides both micro and macro crash protection.

### 2.5 Adaptive Momentum Allocation

**TrendFolios Framework** (2025, arxiv.org/html/2506.09330v1): Combines momentum + trend-following through a "majority vote" algorithm across multiple timeframes. Portfolio weights use **inverse tracking-error weighting** rather than inverse volatility. Result: moderate portfolio achieved 0.48 Sharpe (vs traditional 60/40) with 3.14% annual excess return over 1997-2023.

---

## 3. Economic Regime-Aware Allocation

### 3.1 Turbulence Index (Kritzman & Li)

**Formula**: d_t = (1/n) * (r_t - mu)^T * Sigma^(-1) * (r_t - mu)

This is the Mahalanobis distance of current returns from historical norms, normalized by asset count. It captures both unusual magnitude and unusual correlation patterns.

**Portfolio Allocation Rule**: Convert turbulence to percentile rank (0-100%). Allocate that percentage to cash, remainder to equities. Backtest result: Sharpe improved from ~1.0 to ~2.20; max drawdown reduced from ~32% to ~6%.

### 3.2 Absorption Ratio

**Formula**: AR = sum(variance of top N eigenvectors) / sum(variance of all n eigenvectors), where N ~ n/5.

High AR = concentrated risk (markets fragile, assets moving together). Low AR = dispersed risk (resilient, diversified).

**Portfolio Rule**: Same percentile-to-cash mapping. Backtest result: Sharpe from 0.54 to 0.85; max drawdown from 55% to 15%.

**Complementarity**: Turbulence captures acute shocks (spikes during crises). Absorption captures systemic fragility (builds before crises). Use both: AR as early warning, turbulence as confirmation signal.

### 3.3 Statistical Jump Model (Non-Parametric Regime Detection)

**The 2024 Breakthrough** (arxiv.org/html/2402.05272v2): The Statistical Jump Model avoids the maximum likelihood estimation problems of Hidden Markov Models. It minimizes: loss = clustering_error + lambda * number_of_state_transitions

When lambda = 0, it reduces to k-means (no temporal information). As lambda increases, state transitions become rarer, creating natural persistence.

**Features Used**: Downside Deviation (10-day), Sortino Ratio (20-day), Sortino Ratio (60-day) -- all derived purely from the return series, no external data needed.

**Results on S&P 500 (1990-2023)**:
- Sharpe: 0.48 -> 0.68 (+0.20)
- Max Drawdown: -55.2% -> -26.6% (halved)
- Turnover: 44% (vs 141% for HMM) -- much more practical
- Robust to 1, 5, and 10-day execution delays

**Key Advantage**: No probability distribution assumptions. The jump penalty creates regime persistence without parametric estimation, addressing the fundamental criticism of Markov models.

### 3.4 RegimeFolio Pipeline (2024)

A complete regime-aware system achieving 137% cumulative return vs 73.8% for S&P 500 (2020-2024):

1. VIX-based regime classification (rolling quantiles, not fixed thresholds)
2. Separate models per sector-regime pair (Random Forest + Gradient Boosting)
3. Regime-specific covariance estimation (Ledoit-Wolf shrinkage within each regime)
4. Dynamic mean-variance optimization conditioned on current regime

Removing regime segmentation reduced Sharpe by 27%. Removing sector specialization reduced returns by 48pp. Both components are essential.

### 3.5 Asset-Specific Regime Forecasting (2024)

Two-stage framework combining unsupervised (Jump Model) + supervised (XGBoost):

**Stage 1**: Classify historical periods into bull/bear using 8 return-based features
**Stage 2**: Predict future regimes using 5 macro features (Treasury yields, yield curve slope, VIX, stock-bond correlation)

**Critical Insight**: Bearish frequencies differ dramatically across assets (42% for bonds vs 21% for large-cap equity), justifying asset-specific rather than global regime detection.

### 3.6 Rule-Based Regime Detection (Simple, No Estimation)

For practitioners who want to avoid model estimation entirely:

1. **OECD Composite Leading Indicator (CLI)**: Above/below trend + accelerating/decelerating creates 4 regimes (Growing, Stagflation, Slowing, Heating). Average regime duration ~4 months -- enough for tactical adjustment
2. **VIX percentile**: Current VIX vs trailing 252-day distribution. Above 67th percentile = high vol regime
3. **Yield curve slope**: 10Y-2Y spread. Negative = recession risk regime
4. **Combined signal**: Majority vote across these three indicators determines risk-on/risk-off positioning

---

## 4. Kelly Criterion and Practical Position Sizing

### 4.1 Core Formula for Multi-Asset

For continuous distributions: Kelly fraction = (expected excess return) / (variance of returns). For a portfolio: **f* = Sigma^(-1) * mu** where mu = expected excess returns, Sigma = covariance matrix.

### 4.2 Fractional Kelly for FoF

**Consensus across 2024-2025 literature**: Full Kelly is theoretically optimal for long-run growth but practically dangerous due to parameter uncertainty. Practical implementations:

| Fraction | Use Case | Volatility Impact |
|----------|----------|------------------|
| Full Kelly | Theoretical benchmark only | Maximum -- impractical |
| Half Kelly (f/2) | Well-estimated edges, long track records | ~75% of growth, ~50% of variance |
| Quarter Kelly (f/4) | Uncertain parameter estimates | ~50% of growth, ~25% of variance |

**Key 2024 Finding** (Frontiers, 2020/2024 review): Fractional Kelly is mathematically equivalent to full Kelly with shrinkage estimates of market parameters. This means shrinking the covariance matrix toward identity and shrinking expected returns toward zero achieves the same effect as fractional Kelly -- a useful implementation insight.

### 4.3 Practical Implementation for FoF

1. **Calculate rolling Kelly fractions** per strategy using 3-6 month lookback of daily returns
2. **Apply half-Kelly minimum**: Divide all fractions by 2
3. **Cap individual strategy allocation**: No strategy exceeds 25% (addresses Kelly's tendency toward concentration)
4. **Recalculate monthly**: Short estimation windows adapt better to changing market conditions
5. **Correlation adjustment**: The multi-asset Kelly formula naturally reduces allocation to correlated strategies
6. **Rebalancing**: Shorter rebalancing periods substantially improve Kelly portfolio performance (proven in EuroStoxx50 testing, 2007-2019)

### 4.4 Kelly's Weakness and Mitigation

Kelly portfolios are "less diversified" and "riskier in the short term" than Markowitz tangent portfolios. For a FoF, the practical solution is to use Kelly fractions as an input (signal for sizing) rather than the final allocation. Combine Kelly-derived signals with risk parity constraints: let Kelly determine relative conviction, but enforce minimum diversification through HRP or risk parity constraints.

---

## 5. Ensemble Methods for Portfolios

### 5.1 Direct Analogy: Bagging for Portfolios

**Strategy Bagging**: Like bootstrap aggregation reduces variance in prediction, constructing multiple portfolios from bootstrapped covariance estimates and averaging the resulting weights reduces allocation instability. This is essentially what NCO's cross-validation outer optimization achieves.

**2024 Result** (CFA Institute Research Foundation): Ensembles of ML models outperformed traditional regressions across 30,000 US equities. Key mechanisms: (1) regime adaptation, (2) capturing nonlinear relationships, (3) reducing dependence on any single forecasting approach.

### 5.2 Strategy Stacking for FoF

**HPOSS (2024)**: Hierarchical Portfolio Optimization Stacking Strategy translates model stacking directly into portfolio construction. Stacking weights are computed using any portfolio optimization objective. The hierarchy reduces generalization error by partitioning strategies into groups.

**Practical Architecture**:
1. **Base layer**: Individual momentum strategies (the "base learners")
2. **Meta layer**: Combine strategy returns using portfolio optimization (HRP, risk parity, etc.)
3. **Validation**: Use walk-forward cross-validation -- train on expanding window, test on next period

### 5.3 Ensembling Portfolio Strategies (2024)

**Distribution-Free Ensemble Framework** (arxiv.org/html/2406.03652): Combines k portfolio strategies through weighted averaging where weights are proportional to past cumulative wealth. Key properties:

- **Sublinear regret**: Gap between ensemble and best-hindsight allocation grows only as log(n), preventing overfitting
- **No distribution assumptions**: Works regardless of return distributions
- **Hierarchical scaling**: For >10 strategies, partition into 4-6 groups, ensemble within groups, then ensemble across groups

**Practical Recommendations**:
1. Start with uniform (equal) weighting across strategies
2. Allow past performance to guide rebalancing through the wealth-proportional mechanism
3. For large FoF (>10 strategies), use hierarchical partitioning
4. Accept modest Sharpe ratio tradeoffs for superior long-term wealth accumulation

### 5.4 Multi-Hypothesis Ensemble (2025)

Links ensemble prediction diversity directly to out-of-sample risk diversification: "each predictor corresponds to a specific asset or hypothesis." The framework prioritizes strategies from more diverse predictor sets through a diversity-quality tradeoff, even at the expense of lower average predicted returns. Validated on S&P 500 universe and 1300 global bonds over two decades.

### 5.5 Scale-Diversified Portfolio (2024-2025)

Decomposes multivariate asset returns at multiple time scales (wavelet decomposition), optimizes portfolios independently at each scale, then aggregates through inverse-volatility weighting. Out-of-sample result: Sortino ratio 1.15 (test) vs 0.52 (training) -- the rare case where test outperforms training, suggesting genuine diversification rather than overfitting.

### 5.6 Covariance Cleaning as an Ensemble Technique

**Lopez de Prado's Denoising and Detoning**:
- **Denoising**: Use Marcenko-Pastur distribution to identify noise eigenvalues; replace with their average while preserving trace. Reduces estimation error by 59.85%
- **Detoning**: Remove the market-wide first eigenvector to amplify signals from subtler components (sector, style clusters). Reduction in portfolio estimation errors up to 95%

**2024 Neural Network Approach**: A rotation-invariant neural network jointly learns covariance cleaning and portfolio optimization end-to-end. Results (2000-2024): systematically lower realized volatility, smaller max drawdowns, and higher Sharpe ratios than state-of-the-art nonlinear shrinkage. A single model trained on ~500 stocks generalizes to 1,000+ without retraining.

---

## Synthesis: Practical Recommendations for a Momentum FoF

Based on all research reviewed, the strongest practical framework for a FoF of momentum strategies combines:

1. **Strategy Selection**: Diversify across momentum types (price, fundamental, residual), not just lookback windows. Use the barbell structure (short-term + long-term) for trend-following.

2. **Crash Protection**: Each strategy implements its own volatility scaling (Barroso & Santa-Clara style). At the FoF level, a second volatility-scaling layer based on aggregate portfolio realized volatility.

3. **Allocation Method**: NCO with denoised covariance (RMT cleaning) for the primary allocation. Use ENB as a diagnostic -- if ENB is much less than the number of strategies, investigate hidden factor concentration.

4. **Regime Overlay**: Statistical Jump Model (non-parametric, no distribution assumptions) to detect regimes from the FoF return stream itself. Scale overall exposure (75-100% in bull, 25-50% in bear). Use turbulence index as a complementary acute-shock detector.

5. **Position Sizing**: Half-Kelly fractions as conviction signals, constrained by HRP-derived diversification floors. No individual strategy exceeds 25%.

6. **Ensemble Robustness**: Average allocations from multiple methods (NCO, HRP, Risk Parity, Maximum Diversification) using the distribution-free ensemble framework. This "strategy stacking" approach has the strongest theoretical guarantees against overfitting.

---

Sources:
- [Return-Adjusted HRP and Schur Portfolios](https://arxiv.org/html/2503.12328v1)
- [NCO with Random Matrix Theory (2024)](https://www.worldscientific.com/doi/10.1142/S0129183124500980)
- [Riskfolio-Lib 7.2 - Hierarchical Clustering Models](https://riskfolio-lib.readthedocs.io/en/latest/hcportfolio.html)
- [skfolio NCO Implementation](https://skfolio.org/auto_examples/clustering/plot_4_nco.html)
- [Network Risk Parity](https://link.springer.com/article/10.1057/s41260-023-00347-8)
- [CFA Momentum Framework (2025)](https://rpc.cfainstitute.org/blogs/enterprising-investor/2025/momentum-investing-a-stronger-more-resilient-framework-for-long-term-allocators)
- [Trend Premia Barbell Structure](https://arxiv.org/html/2510.23150v2)
- [Short vs Long-Term CTA Trend Factors](https://arxiv.org/html/2507.15876v1)
- [TrendFolios Multi-Asset Framework](https://arxiv.org/html/2506.09330v1)
- [Momentum Crashes and Volatility Scaling](https://alphaarchitect.com/avoiding-momentum-crashes/)
- [Statistical Jump Model for Regime Detection](https://arxiv.org/html/2402.05272v2)
- [RegimeFolio Pipeline](https://arxiv.org/html/2510.14986v1)
- [Asset-Specific Regime Forecasts](https://arxiv.org/html/2406.09578v2)
- [Dynamic Factor Allocation via Regime Signals](https://arxiv.org/html/2410.14841v1)
- [Turbulence Index Methodology](https://portfoliooptimizer.io/blog/the-turbulence-index-measuring-financial-risk/)
- [Absorption Ratio Methodology](https://portfoliooptimizer.io/blog/the-absorption-ratio-measuring-financial-risk/)
- [Practical Kelly Criterion Implementation](https://www.frontiersin.org/journals/applied-mathematics-and-statistics/articles/10.3389/fams.2020.577050/full)
- [Kelly Criterion for Multi-Strategy](https://www.quantstart.com/articles/Money-Management-via-the-Kelly-Criterion/)
- [CFA Ensemble Learning in Investment (2025)](https://rpc.cfainstitute.org/research/foundation/2025/chapter-4-ensemble-learning-investment)
- [Ensembling Portfolio Strategies](https://arxiv.org/html/2406.03652)
- [Multi-Hypothesis Ensemble for Portfolios](https://www.sciencedirect.com/science/article/pii/S0957417425022523)
- [Entropy-Based Portfolio Diversification](https://www.mdpi.com/2227-9091/13/12/253)
- [Lopez de Prado ML for Asset Managers (GitHub)](https://github.com/emoen/Machine-Learning-for-Asset-Managers)
- [Neural Network Covariance Cleaning](https://www.sciencedirect.com/science/article/pii/S2405918826000048)
- [QuantPedia Time-Series Momentum](https://quantpedia.com/strategies/time-series-momentum-effect)
- [First Sentier Regimes, Turbulence and Absorption](https://www.firstsentierinvestors.com/content/dam/web/global/islp-documentation/MAS_Regimes-turbulence-and-absorption.pdf)
- [Morningstar Momentum ETFs 2025](https://www.morningstar.com/funds/momentum-etfs-stall-2025)
- [Morgan Stanley Momentum 2024 Outlook](https://www.morganstanley.com/im/en-us/individual-investor/insights/articles/momentum-ruled-in-2024.html)
- [Mapping Asset Returns to Economic Regimes (FactSet)](https://insight.factset.com/mapping-asset-returns-to-economic-regimes-a-practical-investors-guide)
- [Alpha-Factor Integrated Risk Parity for FoF](https://www.sciencedirect.com/science/article/abs/pii/S1057521923001709)
---

# Part 2: Implementation Guide -- Momentum-of-Momentum, Regime Detection, and Kelly Criterion

## 1. Momentum of Momentum (Cross-Sectional Momentum Applied to Momentum Strategies)

### Academic Evidence

**Ehsani & Linnainmaa (2022), "Factor Momentum and the Momentum Factor", Journal of Finance 77(3):1877-1919:**
- Most factors are positively autocorrelated: a factor earns 1 bp/month after a losing year vs 53 bp/month after a winning year.
- Time-series factor momentum earns **4.2% annualized** (t=7.04); cross-sectional factor momentum earns **2.8% annualized** (t=5.74).
- Momentum is not a distinct risk factor -- it **aggregates autocorrelations** in all other factors. This means applying momentum to momentum strategies is conceptually sound: you are harvesting the autocorrelation of the underlying factor exposures.

**Cakici, Fieberg, Metko & Zaremba (2023)** found empirical factor momentum returns of **4.06%/month (time-series)** and **2.51%/month (cross-sectional)** across 51 countries over 95 years.

**Mutual fund momentum** (Quantpedia/CRSP data): top decile by trailing 6-month returns, held 3 months, equal-weighted, earned **19% annualized** with Sharpe 0.77. Annualized 3-factor alpha of 3.72% (1973-2000).

### Optimal Lookback Period N

The evidence is **not a single best N** but rather:

| Period | Evidence | Notes |
|--------|----------|-------|
| 1 month | Strong short-term autocorrelation in factors | High turnover, high transaction costs |
| 3 month | Best post-2008 for equity/bond momentum | Regime-adaptive |
| 6 month | Classic fund selection lookback (CRSP study) | Most common in fund-of-funds |
| 12 month | Best 1988-2008 for equity/bond momentum | Classic Jegadeesh-Titman |
| Blend (3/6/9/12) | CTA industry standard | Most robust, lowest parameter sensitivity |

**Recommendation for 21 momentum strategies: Use a blend of 3, 6, 9, and 12-month lookbacks** (average the signals). This is what the CTA industry uses in practice because it is robust to regime changes. The optimal single lookback has shifted from 12 months (pre-2008) to 3 months (post-2008), so blending hedges this instability.

### Concrete Implementation

```python
import pandas as pd
import numpy as np

def momentum_of_momentum(
    returns: pd.DataFrame,
    lookbacks: list[int] = [3, 6, 9, 12],
    top_k: int = 7,
    holding_period: int = 1,
    weighting: str = "equal",  # "equal" or "rank_proportional"
) -> pd.DataFrame:
    """
    Cross-sectional momentum applied to momentum sub-strategies.
    
    Parameters
    ----------
    returns : pd.DataFrame
        Monthly returns, columns = 21 strategy names, index = datetime
    lookbacks : list[int]
        Lookback windows in months to blend
    top_k : int
        Number of top strategies to allocate to (e.g., top tercile = 7 of 21)
    holding_period : int
        Months to hold before rebalancing
    weighting : str
        "equal" for 1/K each, "rank_proportional" for rank-weighted
        
    Returns
    -------
    pd.DataFrame
        Portfolio weights (same shape as returns), sums to 1.0 each row
    """
    n_strategies = returns.shape[1]
    
    # Step 1: Compute composite momentum score (blend of lookbacks)
    # For each lookback, compute trailing cumulative return
    composite_score = pd.DataFrame(0.0, index=returns.index, columns=returns.columns)
    
    for lb in lookbacks:
        # Rolling cumulative return over lb months
        # (1+r1)*(1+r2)*...*(1+rN) - 1
        rolling_cum = (1 + returns).rolling(window=lb).apply(np.prod, raw=True) - 1
        composite_score += rolling_cum
    
    composite_score /= len(lookbacks)  # Average across lookbacks
    
    # Step 2: Rank strategies cross-sectionally each month
    # rank: 1 = worst, N = best
    ranks = composite_score.rank(axis=1, ascending=True, method='average')
    
    # Step 3: Select top K and compute weights
    weights = pd.DataFrame(0.0, index=returns.index, columns=returns.columns)
    
    for date in returns.index:
        if pd.isna(composite_score.loc[date]).any():
            continue  # Skip months with insufficient history
            
        month_ranks = ranks.loc[date]
        threshold = n_strategies - top_k  # e.g., 21 - 7 = 14
        selected = month_ranks[month_ranks > threshold].index
        
        if len(selected) == 0:
            continue
            
        if weighting == "equal":
            weights.loc[date, selected] = 1.0 / len(selected)
        elif weighting == "rank_proportional":
            sel_ranks = month_ranks[selected]
            weights.loc[date, selected] = sel_ranks / sel_ranks.sum()
    
    # Step 4: Apply holding period (hold weights for N months)
    if holding_period > 1:
        rebalance_mask = np.arange(len(weights)) % holding_period == 0
        last_weights = None
        for i, date in enumerate(weights.index):
            if rebalance_mask[i] and weights.loc[date].sum() > 0:
                last_weights = weights.loc[date].copy()
            elif last_weights is not None:
                weights.loc[date] = last_weights
    
    return weights


def backtest_mom_of_mom(
    returns: pd.DataFrame,
    weights: pd.DataFrame,
) -> pd.Series:
    """
    Backtest the momentum-of-momentum portfolio.
    
    Returns
    -------
    pd.Series
        Portfolio monthly returns
    """
    # Shift weights by 1 month (use last month's signal for this month's return)
    shifted_weights = weights.shift(1)
    
    # Portfolio return = sum of (weight_i * return_i) across strategies
    portfolio_returns = (shifted_weights * returns).sum(axis=1)
    
    return portfolio_returns


# --- Usage Example ---
# Assume `strategy_returns` is a DataFrame with 21 columns, monthly frequency
#
# weights = momentum_of_momentum(
#     strategy_returns,
#     lookbacks=[3, 6, 9, 12],
#     top_k=7,            # Top tercile of 21
#     holding_period=3,    # Quarterly rebalance
#     weighting="equal"
# )
# pf_returns = backtest_mom_of_mom(strategy_returns, weights)
```

**Key design choices:**
- `top_k=7` (top tercile of 21) is a reasonable starting point. Literature uses top decile for large universes, but with only 21 strategies, top tercile gives enough diversification.
- `holding_period=3` (quarterly) matches the mutual fund momentum literature.
- Blended lookback is strictly more robust than any single lookback.

---

## 2. Simple Regime Detection (No Parameter Estimation)

### Method A: VIX Percentile

**Academic evidence (Bansal & Stivers, 2023):**
- The equity premium steps up nonlinearly when VIX exceeds the **80th-85th percentile** of its trailing distribution.
- Predictive R-squared of 19-29% at 6-12 month horizons (1990-2023).
- This is a conditional mean effect: high VIX predicts high future returns but also signals current distress.

**For a FoF, "risk-off" should mean**: reduce allocation to the most volatile/aggressive sub-strategies and increase allocation to the most defensive ones (or partially move to cash). Going 100% cash forfeits the elevated risk premium that follows VIX spikes.

### Method B: SPY < 200-day SMA (Faber, 2007)

**Academic evidence (Faber, "A Quantitative Approach to Tactical Asset Allocation"):**
- 10-month SMA (approximately equals 200-day SMA) tested across 5 asset classes, 1901-2012.
- Risk-adjusted returns improved universally: lower max drawdown, lower volatility, lower Ulcer index.
- Absolute CAGR slightly lower than buy-and-hold (7.1% vs 9.8% for S&P), but max drawdown drops from ~55% to ~14%.
- Win rate: 49% on absolute returns, but **69% on risk-adjusted returns** over rolling 3-year periods.
- Underperformed buy-and-hold 6 of 8 years after 2008-2009 (whipsaw in trending bull market).
- **Broad parameter stability**: results are similar for 8-month through 12-month SMA. Not a single fragile optimum.

### Which Is Better Supported?

| Criterion | VIX Percentile | SMA Cross |
|-----------|---------------|-----------|
| Predictive R-squared | 19-29% (6-12mo) | Not directly comparable |
| Drawdown reduction | Good (exits during stress) | Excellent (89 years of evidence) |
| Whipsaw risk | Lower (percentile is smoother) | Higher (price crosses SMA frequently) |
| Applicability to FoF | Natural (vol = risk) | Indirect (equity market signal for non-equity strategies) |
| Simplicity | Very simple | Very simple |
| Look-ahead bias risk | None (uses trailing VIX only) | None (uses trailing price only) |

**Recommendation: Use both as a combined signal.** VIX percentile captures volatility regime; SMA captures trend regime. Both firing = strong risk-off. One firing = moderate caution. Neither = full risk-on.

### What "Risk-Off" Means for a FoF of 21 Momentum Strategies

For a FoF of momentum strategies specifically, "risk-off" should NOT mean going to 100% cash, because:
1. Momentum strategies already have built-in trend signals
2. Some momentum strategies (e.g., those in bonds, commodities) benefit from risk-off regimes

Practical implementation:
- **Risk-on**: Full allocation per normal weighting scheme
- **Caution** (one signal fires): Reduce total exposure to 50-70% of target, rest in T-bills
- **Risk-off** (both signals fire): Reduce to 30-50% of target, rest in T-bills

### Concrete Implementation

```python
import pandas as pd
import numpy as np


def compute_regime(
    spy_prices: pd.Series,
    vix_prices: pd.Series,
    sma_window: int = 200,
    vix_lookback: int = 252,
    vix_percentile_threshold: float = 80,
) -> pd.DataFrame:
    """
    Simple regime detection using VIX percentile + SMA cross.
    No parameter estimation, no hidden states.
    
    Parameters
    ----------
    spy_prices : pd.Series
        Daily SPY adjusted close prices
    vix_prices : pd.Series
        Daily VIX close prices
    sma_window : int
        SMA lookback in trading days (200 = ~10 months)
    vix_lookback : int
        Rolling window for VIX percentile (252 = 1 year)
    vix_percentile_threshold : float
        Percentile above which VIX signals risk-off (80-85 recommended)
        
    Returns
    -------
    pd.DataFrame
        Columns: sma_signal (bool), vix_signal (bool), regime (str),
                 exposure_scalar (float)
    """
    df = pd.DataFrame(index=spy_prices.index)
    
    # --- Signal 1: SPY vs 200-day SMA ---
    spy_sma = spy_prices.rolling(window=sma_window).mean()
    df['sma_signal'] = spy_prices < spy_sma  # True = risk-off
    
    # --- Signal 2: VIX percentile ---
    vix_pctile = vix_prices.rolling(window=vix_lookback).apply(
        lambda x: pd.Series(x).rank(pct=True).iloc[-1] * 100,
        raw=False
    )
    df['vix_signal'] = vix_pctile > vix_percentile_threshold  # True = risk-off
    
    # --- Combined regime ---
    def classify_regime(row):
        n_signals = int(row['sma_signal']) + int(row['vix_signal'])
        if n_signals == 0:
            return 'risk_on'
        elif n_signals == 1:
            return 'caution'
        else:
            return 'risk_off'
    
    df['regime'] = df.apply(classify_regime, axis=1)
    
    # --- Exposure scalar for FoF ---
    exposure_map = {
        'risk_on': 1.0,    # Full allocation
        'caution': 0.6,    # 60% of target
        'risk_off': 0.4,   # 40% of target
    }
    df['exposure_scalar'] = df['regime'].map(exposure_map)
    
    return df


def apply_regime_to_fof_weights(
    fof_weights: pd.DataFrame,
    regime_df: pd.DataFrame,
) -> pd.DataFrame:
    """
    Scale FoF weights by regime exposure scalar.
    Remainder goes to cash (not in the DataFrame).
    
    Parameters
    ----------
    fof_weights : pd.DataFrame
        Monthly FoF weights (from momentum_of_momentum or Kelly).
        Index = monthly dates, columns = strategy names
    regime_df : pd.DataFrame
        Daily regime data from compute_regime().
        Must contain 'exposure_scalar' column.
        
    Returns
    -------
    pd.DataFrame
        Adjusted weights. Row sums <= 1.0 (difference = cash)
    """
    # Resample regime to monthly (use month-end regime)
    monthly_regime = regime_df['exposure_scalar'].resample('ME').last()
    
    # Align indices
    aligned_scalar = monthly_regime.reindex(fof_weights.index, method='ffill')
    
    # Scale all weights proportionally
    adjusted = fof_weights.multiply(aligned_scalar, axis=0)
    
    return adjusted


# --- Usage Example ---
# import yfinance as yf
#
# spy = yf.download("SPY", start="2005-01-01")['Adj Close']
# vix = yf.download("^VIX", start="2005-01-01")['Close']
#
# regime = compute_regime(spy, vix, vix_percentile_threshold=80)
# print(regime['regime'].value_counts(normalize=True))
#
# # Apply to previously computed FoF weights
# adjusted_weights = apply_regime_to_fof_weights(fof_weights, regime)
# cash_allocation = 1.0 - adjusted_weights.sum(axis=1)
```

**Design notes:**
- The VIX percentile uses a **trailing** 252-day window (no future data leak).
- The 80th percentile threshold is the one best supported by Bansal & Stivers (2023). Using a fixed VIX level (e.g., VIX > 25) is inferior because VIX's distribution shifts over time.
- The exposure scalars (1.0 / 0.6 / 0.4) are conservative starting points. You can backtest alternatives, but the two-signal approach provides structural robustness that makes the exact scalars less critical.

---

## 3. Kelly Criterion for FoF Allocation

### Mathematical Framework

For continuous returns with multiple correlated assets, the Kelly criterion maximizes the expected log growth rate. The solution is:

**F\* = Sigma^{-1} * mu**

Where:
- **F\*** = Nx1 vector of optimal fractions of capital to allocate
- **Sigma** = NxN covariance matrix of asset returns
- **mu** = Nx1 vector of excess returns (mean returns minus risk-free rate)

**Critical properties:**
- Weights are NOT normalized to sum to 1. The sum determines optimal leverage.
- The solution is mathematically equivalent to the Markowitz tangency portfolio (Ernie Chan, 2014), differing only in that Kelly specifies leverage while Markowitz assumes unit leverage.
- Weights are **20x more sensitive to errors in estimated returns than to errors in the covariance matrix** (Ernie Chan). This is why half-Kelly is essential in practice.

**Half-Kelly**: Multiply all weights by 0.5. This sacrifices ~25% of the expected geometric growth rate but reduces variance by ~75% (the growth curve is parabolic, so half-Kelly sits on the steep part). The KellyPortfolio project notes: "1/4 Kelly reduces expected return by 20% but reduces variance by 80%."

### Concrete Implementation

```python
import pandas as pd
import numpy as np
from scipy.optimize import minimize


def kelly_allocations(
    returns: pd.DataFrame,
    risk_free_rate: float = 0.04,
    kelly_fraction: float = 0.5,
    max_individual_weight: float = 0.25,
    lookback_months: int = 36,
    shrinkage: bool = True,
) -> pd.DataFrame:
    """
    Compute rolling half-Kelly allocations for a FoF of 21 strategies.
    
    Parameters
    ----------
    returns : pd.DataFrame
        Monthly returns, columns = 21 strategy names, index = datetime
    risk_free_rate : float
        Annual risk-free rate (e.g., 0.04 for 4%)
    kelly_fraction : float
        Fraction of full Kelly to use (0.5 = half-Kelly)
    max_individual_weight : float
        Maximum allocation to any single strategy (0.25 = 25%)
    lookback_months : int
        Rolling window for parameter estimation
    shrinkage : bool
        Use Ledoit-Wolf shrinkage on covariance matrix
        
    Returns
    -------
    pd.DataFrame
        Portfolio weights, each row sums to <= 1.0
    """
    rf_monthly = (1 + risk_free_rate) ** (1/12) - 1
    n_strategies = returns.shape[1]
    
    weights_history = pd.DataFrame(
        0.0, index=returns.index, columns=returns.columns
    )
    
    for i in range(lookback_months, len(returns)):
        window = returns.iloc[i - lookback_months:i]
        
        # --- Step 1: Estimate parameters ---
        mu = window.mean().values  # Monthly mean returns
        excess_mu = mu - rf_monthly  # Excess returns
        
        if shrinkage:
            cov = _ledoit_wolf_shrinkage(window.values)
        else:
            cov = window.cov().values
        
        # --- Step 2: Unconstrained full Kelly ---
        try:
            cov_inv = np.linalg.inv(cov)
            f_full = cov_inv @ excess_mu
        except np.linalg.LinAlgError:
            # Singular matrix - use pseudoinverse
            cov_inv = np.linalg.pinv(cov)
            f_full = cov_inv @ excess_mu
        
        # --- Step 3: Apply fractional Kelly ---
        f_scaled = f_full * kelly_fraction
        
        # --- Step 4: Apply constraints via optimization ---
        w = _constrained_kelly(
            excess_mu, cov, kelly_fraction, max_individual_weight
        )
        
        weights_history.iloc[i] = w
    
    return weights_history


def _constrained_kelly(
    excess_mu: np.ndarray,
    cov: np.ndarray,
    kelly_fraction: float,
    max_weight: float,
) -> np.ndarray:
    """
    Solve the constrained Kelly problem:
    max  f'*mu - (1/2)*f'*Sigma*f   (log-growth approximation)
    s.t. 0 <= f_i <= max_weight
         sum(f_i) <= 1.0
         
    Then scale by kelly_fraction.
    """
    n = len(excess_mu)
    
    # Objective: maximize f'*mu - 0.5*f'*Sigma*f
    # scipy minimizes, so we negate
    def neg_growth(f):
        return -(f @ excess_mu - 0.5 * f @ cov @ f)
    
    def neg_growth_jac(f):
        return -(excess_mu - cov @ f)
    
    # Constraints
    constraints = [
        {'type': 'ineq', 'fun': lambda f: 1.0 - np.sum(f)},  # sum <= 1
    ]
    
    bounds = [(0.0, max_weight)] * n  # 0 <= f_i <= max_weight
    
    # Initial guess: equal weight
    x0 = np.full(n, 1.0 / n)
    
    result = minimize(
        neg_growth,
        x0,
        jac=neg_growth_jac,
        method='SLSQP',
        bounds=bounds,
        constraints=constraints,
        options={'maxiter': 1000, 'ftol': 1e-12},
    )
    
    if result.success:
        w = result.x * kelly_fraction
        # Re-normalize if kelly_fraction pushed sum > 1
        if w.sum() > 1.0:
            w = w / w.sum()
        return np.maximum(w, 0.0)  # Numerical cleanup
    else:
        # Fallback: equal weight
        return np.full(n, kelly_fraction / n)


def _ledoit_wolf_shrinkage(X: np.ndarray) -> np.ndarray:
    """
    Ledoit-Wolf linear shrinkage estimator for covariance matrix.
    Shrinks toward scaled identity matrix.
    
    More stable than sample covariance for N ~ T (21 strategies, 36 months).
    """
    T, N = X.shape
    # De-mean
    X_centered = X - X.mean(axis=0)
    
    # Sample covariance
    S = (X_centered.T @ X_centered) / T
    
    # Shrinkage target: scaled identity
    mu_target = np.trace(S) / N
    F = mu_target * np.eye(N)
    
    # Compute optimal shrinkage intensity
    # Frobenius norms
    sum_sq = 0.0
    for t in range(T):
        xt = X_centered[t:t+1].T  # Column vector
        sum_sq += np.sum((xt @ xt.T - S) ** 2)
    
    delta = sum_sq / (T ** 2)
    
    # Squared Frobenius norm of (S - F)
    misfit = np.sum((S - F) ** 2)
    
    # Shrinkage intensity (clipped to [0, 1])
    if misfit == 0:
        alpha = 1.0
    else:
        alpha = min(delta / misfit, 1.0)
    
    return alpha * F + (1 - alpha) * S


# --- Diagnostic: show Kelly properties ---
def kelly_diagnostics(
    returns: pd.DataFrame,
    risk_free_rate: float = 0.04,
) -> dict:
    """
    Compute full (unconstrained) Kelly for diagnostic purposes.
    Shows raw leverage, concentration, and why half-Kelly + caps are needed.
    """
    rf_monthly = (1 + risk_free_rate) ** (1/12) - 1
    mu = returns.mean().values
    excess_mu = mu - rf_monthly
    cov = returns.cov().values
    
    cov_inv = np.linalg.inv(cov)
    f_full = cov_inv @ excess_mu
    
    return {
        'full_kelly_weights': pd.Series(f_full, index=returns.columns),
        'total_leverage': f_full.sum(),
        'max_single_position': f_full.max(),
        'min_single_position': f_full.min(),
        'n_negative': (f_full < 0).sum(),
        'half_kelly_weights': pd.Series(f_full * 0.5, index=returns.columns),
    }


# --- Usage Example ---
# # Given monthly returns for 21 momentum strategies
# weights = kelly_allocations(
#     strategy_returns,
#     risk_free_rate=0.04,        # Current T-bill rate
#     kelly_fraction=0.5,         # Half-Kelly
#     max_individual_weight=0.25, # 25% cap
#     lookback_months=36,         # 3-year estimation window
#     shrinkage=True,             # Ledoit-Wolf (essential for 21 assets / 36 months)
# )
#
# # Check diagnostics on full sample
# diag = kelly_diagnostics(strategy_returns)
# print(f"Full Kelly leverage: {diag['total_leverage']:.1f}x")
# print(f"Strategies with negative (short) weight: {diag['n_negative']}")
```

### Why These Specific Choices

**Ledoit-Wolf shrinkage is essential**: With 21 strategies and a 36-month estimation window, the sample covariance matrix is poorly conditioned (N/T = 0.58). The eigenvalues of the sample covariance are known to be spread too wide (largest overestimated, smallest underestimated). Ledoit-Wolf shrinks toward a scaled identity, which regularizes the inverse. Without shrinkage, the Kelly weights will be wildly unstable month to month.

**25% cap**: Without it, full Kelly can concentrate 50-100%+ in a single strategy that happens to have high Sharpe and low correlation to others. This is statistically fragile -- the Sharpe estimate has large confidence intervals with 36 months of data.

**Half-Kelly**: The log-growth curve is parabolic. At full Kelly, you are at the peak but on a knife edge -- any estimation error pushes you to the right of the peak where geometric growth drops precipitously. At half-Kelly, you sacrifice ~25% of growth but the curve is nearly flat there, providing enormous robustness to parameter misestimation.

**36-month lookback**: A tradeoff. Shorter (24 months) adapts faster but produces noisier covariance estimates. Longer (60 months) is more stable but may include obsolete regimes. 36 months is the industry standard for strategy-level parameter estimation.

---

## Combining All Three

The three components stack naturally:

```python
# 1. Compute momentum-of-momentum weights (strategy selection layer)
mom_weights = momentum_of_momentum(
    strategy_returns, lookbacks=[3, 6, 9, 12], top_k=7
)

# 2. Compute Kelly weights (sizing layer)
kelly_weights = kelly_allocations(
    strategy_returns, kelly_fraction=0.5, max_individual_weight=0.25
)

# 3. Blend: use Kelly for sizing within the MoM-selected set
# Zero out Kelly weights for strategies not selected by MoM
blended_weights = kelly_weights * (mom_weights > 0).astype(float)
# Re-normalize so they sum to Kelly's total exposure
row_sums = blended_weights.sum(axis=1).replace(0, 1)
blended_weights = blended_weights.div(row_sums, axis=0) * kelly_weights.sum(axis=1)

# 4. Apply regime overlay (risk management layer)
regime = compute_regime(spy_prices, vix_prices, vix_percentile_threshold=80)
final_weights = apply_regime_to_fof_weights(blended_weights, regime)

# Cash allocation = 1.0 - final_weights.sum(axis=1)
```

**Architecture**: MoM selects WHICH strategies to invest in (top 7 of 21). Kelly determines HOW MUCH to invest in each selected strategy (correlation-adjusted sizing). Regime overlay determines the TOTAL exposure level (scalar on all weights). These are three independent, complementary decisions.

---

Sources:
- [Ehsani & Linnainmaa (2022) - Factor Momentum and the Momentum Factor, Journal of Finance](https://onlinelibrary.wiley.com/doi/abs/10.1111/jofi.13131)
- [Ehsani & Linnainmaa - NBER Working Paper](https://www.nber.org/papers/w25551)
- [Cakici et al. - Price Momentum or Factor Momentum (Quantpedia summary)](https://quantpedia.com/price-momentum-or-factor-momentum-what-leads-what/)
- [Momentum in Mutual Fund Returns (Quantpedia)](https://quantpedia.com/strategies/momentum-in-mutual-fund-returns)
- [Exploration of CTA Momentum Strategies Using ETFs (Quantpedia)](https://quantpedia.com/exploration-of-cta-momentum-strategies-using-etfs/)
- [Faber - A Quantitative Approach to Tactical Asset Allocation (SSRN)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=962461)
- [200-Day SMA Rule Performance Review (Quant Investing)](https://www.quant-investing.com/blog/four-new-investment-ideas-and-review-of-200-days-sma-rule)
- [Bansal & Stivers - Time-Varying Equity Premia with High-VIX Threshold (Quantpedia)](https://quantpedia.com/time-varying-equity-premia-with-a-high-vix-threshold/)
- [Ernie Chan - Kelly vs. Markowitz Portfolio Optimization](http://epchan.blogspot.com/2014/08/kelly-vs-markowitz-portfolio.html)
- [Kelly Criterion Multi-Asset (Quantdare)](https://quantdare.com/kelly-criterion-part-2/)
- [KellyPortfolio (GitHub)](https://github.com/thk3421-models/KellyPortfolio)
- [BSIC - Kelly Criterion in Portfolio Optimization](https://bsic.it/exploring-the-application-of-kellys-criterion-in-portfolio-optimization/)
- [200-Day Moving Average Strategy Backtest (Quantified Strategies)](https://www.quantifiedstrategies.com/200-day-moving-average-strategy/)
