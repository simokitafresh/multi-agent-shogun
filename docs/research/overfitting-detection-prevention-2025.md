# Overfitting Detection & Prevention in Quantitative Portfolio Construction

> Research compiled 2026-03-26. Covers academic and practitioner methods 2023-2025.
> cmd: lord research request (overfitting methods survey)

---

## Table of Contents

- [Section 1: Overfitting Detection Methods](#1-overfitting-detection-methods)
- [Section 2: Structural Anti-Overfitting (Prevention by Design)](#2-structural-anti-overfitting)
- [Section 3: 2024-2025 State of the Art](#3-2024-2025-state-of-the-art)
- [Section 4: Practical Validation Pipeline](#4-practical-validation-pipeline)
- [Section 5: Implementation Tools](#5-implementation-tools)
- [Section 6: Key Papers & References](#6-key-papers--references)

---

## 1. Overfitting Detection Methods

### 1.1 Combinatorial Purged Cross-Validation (CPCV)

**Origin**: Lopez de Prado, "Advances in Financial Machine Learning" (2018), Chapter 12.

**Problem it solves**: Standard k-fold CV destroys temporal ordering. Walk-forward produces only a single OOS path (easily overfit). CPCV generates MANY chronology-respecting train-test partitions.

**How it works**:
1. Divide time series into N sequential, non-overlapping groups (preserving temporal order)
2. Select all combinations of p groups as test sets (p > 1), remaining N-p as training
3. **Purge**: Remove training observations whose label horizon overlaps with test period (prevents look-ahead bias)
4. **Embargo**: Remove a buffer of observations after each test period from training set (prevents serial correlation leakage)
5. Result: Not a single OOS score but an **empirical distribution** of OOS outcomes across many paths

**Key advantage**: Generates C(N, p) distinct train/test splits, each respecting temporal order. This reveals the **stability** of strategy performance across diverse historical paths. If performance varies wildly across paths, the strategy is likely overfit.

**2024 findings** (Arian, Norouzi & Seco, Knowledge-Based Systems 2024): In a synthetic controlled environment with Heston stochastic volatility + Merton jump diffusion + regime switching, **CPCV demonstrated marked superiority** over Walk-Forward, K-Fold, and Purged K-Fold in mitigating overfitting risks. Lower PBO scores and superior DSR metrics.

**Novel variants introduced**:
- **Bagged CPCV**: Ensemble of CPCV outputs for robustness
- **Adaptive CPCV**: Dynamic adjustment of fold sizes based on detected market conditions

### 1.2 Probability of Backtest Overfitting (PBO)

**Origin**: Bailey, Borwein, Lopez de Prado & Zhu (2014/2017). SSRN 2326253.

**What it computes**: The probability that an **in-sample optimal strategy underperforms the median out-of-sample**. If PBO > 0.5, more than half the time your "best" strategy is actually below average OOS.

**Method: Combinatorially Symmetric Cross-Validation (CSCV)**:
1. Collect performance matrix M of shape (T x N) where T = time periods, N = strategy configurations tried
2. Partition T rows into S equal sub-matrices
3. Form all C(S, S/2) combinations of sub-matrices for train/test
4. For each combination: find the best strategy in-sample, measure its OOS rank
5. PBO = fraction of combinations where the IS-optimal strategy ranks below OOS median

**Properties**: Model-free, non-parametric, symmetric. Does not assume any distribution on returns.

**Interpretation thresholds**:
- PBO < 0.10: Low overfitting risk
- PBO 0.10-0.30: Moderate (proceed with caution)
- PBO > 0.30: High overfitting risk (strategy fragile)

### 1.3 Deflated Sharpe Ratio (DSR)

**Origin**: Bailey & Lopez de Prado (2014). SSRN 2460551.

**Problem**: Observed Sharpe ratios are inflated by (a) selection bias from multiple testing, (b) non-normal returns (skewness/kurtosis), (c) short track records.

**Formula**:

```
DSR = Z[ (SR_hat - SR_0) * sqrt(T-1) / sqrt(1 - gamma_3 * SR_hat + (gamma_4-1)/4 * SR_hat^2) ]
```

Where:
- `SR_hat` = observed Sharpe ratio of selected strategy
- `SR_0` = expected maximum Sharpe under null (zero true alpha)
- `T` = number of observations
- `gamma_3` = skewness of returns
- `gamma_4` = kurtosis of returns
- `Z[.]` = standard normal CDF

**Computing SR_0 (the benchmark from multiple trials)**:

```
E[max{SR_n}] ≈ E[{SR_n}] + sqrt(V[{SR_n}]) * [(1-gamma)*Z_inv(1-1/N) + gamma*Z_inv(1-1/(N*e^-1))]
```

Where gamma ≈ 0.5772 (Euler-Mascheroni constant), N = number of independent trials.

**Practical example**: Strategy with SR=2.5 selected from 100 trials, backtested over 1250 days, with skewness=-3, kurtosis=10: DSR ≈ 0.90. Meaning 10% chance the strategy is spurious despite the high observed SR.

**Related: Probabilistic Sharpe Ratio (PSR)**:

```
PSR[SR*] = Z[ (SR - SR*) * sqrt(T-1) / sqrt(1 - gamma_3*SR + (gamma_4-1)/4 * SR^2) ]
```

PSR gives the probability that the true SR exceeds a user-defined benchmark SR*. DSR is PSR where the benchmark is computed from the multiple-testing context.

**Minimum Backtest Length (MinBTL)**: Derived from PSR/DSR framework. With only 7 strategy configurations tried, a researcher is expected to find at least one 2-year backtest with SR > 1 even when expected OOS SR = 0. Recommended: 200-500 trades across 2-3 complete market cycles.

### 1.4 Walk-Forward Analysis

**Standard Walk-Forward (WF)**:
1. Train on window [0, t], test on [t, t+k]
2. Shift forward by step s, repeat
3. Concatenate OOS segments

**Anchored (expanding window)**: Training window always starts at t=0 and grows. Better for strategies needing full history. Preferred for weekly/low-frequency.

**Rolling (fixed window)**: Training window has fixed length, slides forward. Adapts faster to regime changes. Preferred for intraday/high-frequency.

**Key limitation** (from 2024 research): Walk-Forward produces a single path that can easily be overfit. It shows "notable shortcomings in false discovery prevention, characterized by increased temporal variability." CPCV is superior for overfitting detection.

**Best practice**: Use WF for realistic performance estimation, but supplement with CPCV for overfitting detection. They serve different purposes.

### 1.5 Bootstrap Reality Check / Hansen's SPA Test

**White's Reality Check (WRC)** (White, 2000):
1. Record ALL strategy variants tested (including abandoned ones)
2. Generate equity curves for all variants (detrended, no costs)
3. Note best strategy's profit P
4. Bootstrap with replacement: resample returns, build new curves, find best performer
5. Repeat 1000+ times
6. Median of bootstrap bests = data mining bias M
7. p-value = fraction of bootstrap bests exceeding P
8. Expected real return = P - M - costs

**Hansen's Superior Predictive Ability (SPA)** test (2005): Improved version of WRC. Uses studentized test statistic that reduces influence of erratic forecasts. Less sensitive to poor/irrelevant alternatives. More powerful.

**Stepwise Multiple Testing (StepM)** (Romano & Wolf, 2005): Extension of SPA. Instead of asking "is ANY model better than benchmark?" (yes/no), it returns the **SET of models** that are superior. Controls Family-Wise Error Rate (FWER).

**Practical limitation**: WRC requires recording ALL discarded variants during development -- extremely cumbersome with ML/automated search.

### 1.6 Multiple Hypothesis Testing Corrections

When testing N strategies, the probability of at least one false positive rises exponentially.

**Bonferroni**: Multiply p-values by N. Very conservative, especially with correlated tests.

**Holm**: Step-down procedure. Less conservative than Bonferroni while controlling FWER.

**Benjamini-Hochberg (BH)**: Controls False Discovery Rate (FDR) rather than FWER. Critical value = (i/m) * Q, where i=rank, m=total tests, Q=chosen FDR. More powerful than Bonferroni for large N.

**Harvey-Liu-Zhu (HLZ, 2016) Haircut Sharpe Ratio**: Specifically designed for finance. Key insight: haircut is **non-linear** -- highest SRs are only moderately penalized, while marginal SRs are penalized more. Accounts for correlation between trials using a "direct modeling approach" with truncated exponential distribution for t-statistics. Three adjustment methods: Bonferroni, Holm, and BHY.

**After 1000 independent backtests**: Expected maximum SR = 3.26 even when true SR = 0. This is pure data mining.

---

## 2. Structural Anti-Overfitting

### 2.1 Constrain Parameter Space via Economic Theory (A Priori)

**Principle**: Strategies grounded in economic theory have fewer degrees of freedom to overfit.

**Approaches**:
- **Bayesian priors from economic theory**: Tu & Zhou showed economic-objective-based priors achieve better OOS certainty-equivalent returns. Chevrier & McCulloch obtained excellent OOS Sharpe ratios with theory-incorporated priors
- **Hierarchical Bayes**: Imposing priors directly on optimal portfolio weights produces well-diversified portfolios with superior OOS performance
- **Economic-motivated regularization**: Constraints calibrated to achieve precise ex-ante goals while avoiding overfitting
- **Genetic Programming with Economic Constraints** (Liu & Zhou, SSRN 4674858): Using economic theory to constrain the search space of GP-discovered strategies

**Practical rule**: Before backtesting, articulate WHY the strategy should work based on economic reasoning. If you cannot, it is likely data-mined.

### 2.2 Parsimony Principle (Fewer Parameters)

**"With four parameters I can fit an elephant, and with five I can make him wiggle his trunk"** -- von Neumann

**Guidelines**:
- Aim for minimum parameters needed to capture the trading idea
- More parameters = exponentially more ways to overfit
- Each parameter doubles the hypothesis space
- Regularization: L1 (LASSO) for automatic feature selection, Elastic Net for combined L1+L2
- Principal Component Regression (PCR) and Partial Least Squares (PLS) for parsimonious forecasting

**Test**: If removing a parameter degrades OOS performance by < 5%, remove it.

### 2.3 Out-of-Sample Testing Protocols

**Three-way split**: Train (60%) / Validate (20%) / Test (20%). Test set is NEVER touched until final evaluation.

**Critical discipline**: Complete ALL research before running any backtest. The vicious cycle: tweak parameters -> run backtest -> tweak -> run -> ... contaminates the entire dataset.

**"Out-of-sample" data is inherently contaminated**: Researchers have lived through it and have priors about what happened. True out-of-sample = live/paper trading only.

### 2.4 Regime-Aware Validation

**Why it matters**: A strategy that works in bull markets but fails in bear markets is overfit to a regime, not to noise, but still fragile.

**Framework** (from literature):
1. **Regime identification**: HMM, Markov switching, distributional clustering
2. **Regime forecast**: Predict current/future regime
3. **Regime-based portfolio model**: Conditional allocation
4. **OOS testing across regimes**: Strategy must perform (or at least not catastrophically fail) across ALL identified regimes

**2024-2025 advances**: Multi-model ensemble HMM voting frameworks for regime detection. Key limitation: HMMs react slowly to sharp structural breaks.

**Practical test**: Run walk-forward validation and segment results by VIX regime (low/medium/high). If Sharpe is positive only in one regime, the strategy has limited robustness.

### 2.5 Cross-Asset Validation

**Principle**: If a trading rule (e.g., momentum, mean-reversion) works across multiple asset classes (equities, FX, commodities, rates), it is less likely overfit to a specific dataset.

**Application**: Test the same signal construction logic on:
- Different geographies (US, Europe, Asia)
- Different asset classes
- Different time periods (pre/post 2008, pre/post COVID)

**Caveat**: Some strategies are legitimately asset-class-specific. Cross-asset validation is evidence of robustness, not a requirement.

### 2.6 Develop for Asset Classes, Not Individual Securities

**Arnott et al. framework**: Build models for entire asset classes rather than individual securities. This naturally constrains the model to capture systematic patterns rather than idiosyncratic noise.

### 2.7 Model Averaging

Combine predictions from multiple models to reduce forecast error variance. Even simple averaging provides meaningful overfitting protection through variance reduction.

---

## 3. 2024-2025 State of the Art

### 3.1 "Backtest Overfitting in the ML Era" (Arian, Norouzi & Seco, 2024)

**Paper**: Knowledge-Based Systems, 2024. SSRN 4686376.

**Key contribution**: First comprehensive comparison of OOS testing methods in a **synthetic controlled environment** where the ground truth is known (Heston + Merton + regime switching). Results:
- **CPCV >> Walk-Forward >> K-Fold ≈ Purged K-Fold** for overfitting detection
- Walk-Forward's single path is unreliable for false discovery prevention
- Bagged CPCV and Adaptive CPCV further improve robustness

### 3.2 GT-Score: Anti-Overfitting Objective Function (Sheppert, 2025)

**Paper**: Journal of Risk and Financial Management, MDPI, 2026 (based on 2025 work). arXiv 2602.00080.

**Key innovation**: Instead of detecting overfitting after the fact, embed anti-overfitting properties directly into the optimization objective.

**Formula**:

```
GT-Score = (mu * ln(z) * r^2) / sigma_d
```

Components:
- `mu` = mean strategy return per observation (performance)
- `ln(z)` = natural log of Z-score (significance gate -- rejects strategies that don't outperform benchmark)
- `r^2` = R-squared of returns (consistency -- penalizes reliance on outlier trades)
- `sigma_d` = downside deviation (risk -- targets drawdown mitigation)

Z-score: `z = (mu - mu_m) / (sigma / sqrt(N))`

**Edge case handling**:
- z <= 0: Large penalty for underperformance
- 0 < z <= 1: Smooth exponential transition
- z > 1: Standard GT-Score formula

**Results**: 98% improvement in generalization ratio (validation return / training return): 0.365 vs 0.185 for baselines. Tested on 50 S&P 500 stocks, 2010-2024, 14,000+ optimization trials.

**Minimum sample**: 50-trade minimum (nmin=50) for statistical stability.

### 3.3 Hypothesis-Driven Walk-Forward Framework (arXiv 2512.12924, 2024)

**Key innovation**: Every trade must originate from a **human-interpretable hypothesis expressed in natural language**. Framework is agnostic to hypothesis source (rule-based, GP, LLM-generated).

**Protocol**:
- Training window: 252 days, Test window: 63 days, Step: 63 days
- 34 independent folds across 2015-2024
- Realistic costs: 5bps slippage + $1 commission
- Position constraints: max 5 concurrent, 20% per position
- Statistical battery: t-tests, bootstrap CI (10k resamples), Monte Carlo permutation (10k shuffles), binomial tests, Shapiro-Wilk
- **Honest reporting**: Authors report 0.55% annualized return, p=0.34 (not significant), 12% statistical power

**Critical finding**: Strategy shows strong regime dependence (SR=-0.21 in low-vol vs SR=1.01 in high-vol). This is the kind of insight that standard backtesting hides.

### 3.4 Goyle's Empirical Framework (SSRN 5331456, 2025)

**Five-pillar validation**: Cross-validation, stress testing, statistical tests, sensitivity analysis, bootstrapping.

**Overfitting measurement**: DSR difference between training and test sets. Results exceeding 1 standard deviation = overfitting flag.

**Two overfitting drivers examined**:
1. Training period length (longer training paradoxically correlates with higher overfitting)
2. Parameter space size (surprising: larger spaces sometimes show lower measured overfitting)

**Sensitivity analysis (neighborhood stability)**:
1. For selected parameter configuration, test neighboring parameters (step * 1.5)
2. Calculate SR across variations
3. Aggregated score: `1/std * 0.4 + mean/best_param_sr * 0.3 + num_positive/total * 0.3`
4. Score >= 1 indicates stable region

**Stress tests for robustness**:
1. Signal reversal (negate factor signals)
2. Volatility amplification (scale returns via log-normal)
3. Regime shifts (invert positions during specific periods)
4. Market crashes (apply scaling factors during extreme events)

### 3.5 QuantBench (2025)

Benchmarking framework for AI methods in quantitative investment. Addresses the lack of standardized benchmarks aligned with testing standards used in the quantitative investment industry.

### 3.6 Can You PROVE a Strategy Is Not Overfit?

**Short answer**: No. You cannot prove a negative. But you can make overfitting **extremely unlikely** through cumulative evidence:

1. **Economic rationale exists** (structural reason for edge)
2. **PBO < 0.10** across CPCV splits
3. **DSR significant** after accounting for all trials
4. **Works across multiple asset classes** and time periods
5. **Walk-forward performance** consistent across regimes
6. **Sensitivity analysis** shows flat performance surface (not a narrow peak)
7. **Bootstrap reality check** p-value < 0.05
8. **Parsimony**: Few parameters relative to data
9. **Live/paper trading** confirms backtested returns

Each test is a filter. A strategy passing ALL of them has vanishingly small probability of being overfit. The probability is never zero, but it can be made arbitrarily small.

---

## 4. Practical Validation Pipeline

### Step-by-Step Framework (Recommended Sequence)

```
Phase 0: DESIGN (before any data touching)
Phase 1: STATISTICAL DETECTION
Phase 2: ROBUSTNESS STRESS TESTING
Phase 3: LIVE VALIDATION
```

#### Phase 0: Design Discipline (Structural Prevention)

| Step | Action | Pass Criteria |
|------|--------|---------------|
| 0.1 | Articulate economic rationale for WHY the strategy works | Clear, theory-based explanation exists |
| 0.2 | Minimize parameters to essential minimum | Each parameter has economic justification |
| 0.3 | Pre-register: define strategy rules, parameter ranges, success criteria BEFORE looking at data | Written specification exists |
| 0.4 | Reserve test set (20% minimum) that will NEVER be touched until Phase 2 | Test set locked and documented |
| 0.5 | Document every configuration/variant you plan to test (for DSR/PBO computation) | Total trial count N recorded |

#### Phase 1: In-Sample Detection

| Step | Action | Tool | Pass Criteria |
|------|--------|------|---------------|
| 1.1 | Run CPCV (n_folds=10, n_test_folds=2, with purge+embargo) | `skfolio.CombinatorialPurgedCV` | OOS distribution has positive mean, low variance |
| 1.2 | Compute PBO from CPCV paths | `pypbo` or custom CSCV | PBO < 0.15 |
| 1.3 | Compute Deflated Sharpe Ratio | `mlfinlab` or manual formula | DSR > 0.95 (i.e., >95% probability of genuine alpha) |
| 1.4 | Run SPA test (vs buy-and-hold benchmark) | `arch.bootstrap.SPA` | Consistent p-value < 0.05 |
| 1.5 | Apply HLZ haircut to observed Sharpe | `quantstrat::SharpeRatio.haircut` (R) | Haircut SR still economically meaningful |
| 1.6 | Walk-forward analysis (rolling, 252-day train / 63-day test) | Custom or `skfolio.WalkForward` | Consistent positive performance across folds |
| 1.7 | Segment WF results by regime (VIX < 15 / 15-25 / > 25) | Custom | No catastrophic regime (SR < -0.5) |

#### Phase 2: Robustness Stress Testing

| Step | Action | Pass Criteria |
|------|--------|---------------|
| 2.1 | Parameter sensitivity: perturb each parameter +/-20% | Performance degrades < 20% (flat surface, not narrow peak) |
| 2.2 | Monte Carlo permutation (10,000 shuffles of returns) | Strategy beats > 95% of permuted versions |
| 2.3 | Bootstrap confidence intervals (10,000 resamples) | 95% CI for Sharpe excludes zero |
| 2.4 | Signal reversal test: negate all signals | Reversed strategy should lose money |
| 2.5 | Transaction cost sensitivity: 2x, 3x assumed costs | Strategy remains profitable at 2x costs |
| 2.6 | Cross-asset validation: apply same logic to different markets | Positive performance in >= 2 independent markets |
| 2.7 | Out-of-period test: reserve test set (from Phase 0.4) | Performance consistent with IS (within 1 std dev) |
| 2.8 | Subsample stability: randomly drop 10-30% of data, retest 100 times | 80%+ of subsamples profitable |

#### Phase 3: Live Validation

| Step | Action | Pass Criteria |
|------|--------|---------------|
| 3.1 | Paper trading (minimum 3 months, ideally 6) | Returns within 2 std dev of backtest |
| 3.2 | Small capital live trading (1/10 of target size, 3 months) | Execution matches paper trading |
| 3.3 | Full deployment with continuous monitoring | Drawdown within backtested range |
| 3.4 | Ongoing PBO/DSR monitoring as new data accumulates | Metrics remain within bounds |

### Decision Matrix

```
Phase 0: DESIGN DISCIPLINE
  └─ FAIL any → Redesign strategy before touching data

Phase 1: STATISTICAL DETECTION
  └─ FAIL PBO or DSR → Strategy is overfit. Discard or fundamentally redesign.
  └─ FAIL SPA/WF → Weak evidence. Consider as "research-stage only."
  └─ PASS all → Proceed to Phase 2.

Phase 2: ROBUSTNESS
  └─ FAIL sensitivity or permutation → Strategy is fragile. Simplify.
  └─ FAIL cross-asset → Strategy may be asset-specific (acceptable if economically justified).
  └─ FAIL cost sensitivity → Strategy is not tradeable in practice. Reduce turnover.
  └─ PASS all → Proceed to Phase 3.

Phase 3: LIVE VALIDATION
  └─ FAIL paper/live divergence → Implementation issue or regime shift. Investigate.
  └─ PASS → Deploy with monitoring.
```

---

## 5. Implementation Tools

### Python Ecosystem

| Tool | Purpose | Install |
|------|---------|---------|
| **skfolio** | CombinatorialPurgedCV, WalkForward, portfolio optimization with scikit-learn API | `pip install skfolio` |
| **arch** | SPA test, StepM, MCS (Model Confidence Set), bootstrap methods | `pip install arch` |
| **pypbo** | Probability of Backtest Overfitting (CSCV implementation) | `pip install pypbo` |
| **mlfinlab** | DSR, PSR, MinBTL, and full AFML toolkit (commercial) | Hudson & Thames |

### skfolio CombinatorialPurgedCV

```python
from skfolio.model_selection import CombinatorialPurgedCV

cv = CombinatorialPurgedCV(
    n_folds=10,        # Total folds
    n_test_folds=2,    # Test folds per split (higher = more paths)
    purged_size=5,     # Remove observations overlapping with test labels
    embargo_size=3     # Buffer after test period
)

# Properties:
# cv.n_splits -> number of train/test combinations
# cv.n_test_paths -> number of reconstructable OOS paths
```

### arch SPA / StepM / MCS

```python
from arch.bootstrap import SPA, StepM, MCS

# SPA: Is ANY model better than benchmark?
spa = SPA(benchmark_losses, model_losses_array, reps=1000)
spa.compute()
# spa.pvalues -> {lower, consistent, upper}. Use "consistent".

# StepM: WHICH models are better than benchmark?
stepm = StepM(benchmark_losses, model_losses_df)
stepm.compute()
# stepm.superior_models -> list of superior model names/indices

# MCS: Which models are statistically indistinguishable from the best?
mcs = MCS(all_model_losses, size=0.10)
mcs.compute()
# mcs.included -> models in confidence set
# mcs.excluded -> models outside confidence set
```

### DSR Computation (Manual)

```python
import numpy as np
from scipy.stats import norm

def deflated_sharpe_ratio(sr_hat, sr_variance, n_trials, T, skew, kurtosis):
    """
    sr_hat: observed Sharpe ratio of selected strategy
    sr_variance: variance of Sharpe ratios across all trials
    n_trials: number of strategies tested (N)
    T: number of return observations
    skew: skewness of returns
    kurtosis: excess kurtosis of returns
    """
    euler_mascheroni = 0.5772156649

    # Expected max SR under null (E[max{SR_n}])
    z_inv = norm.ppf(1 - 1/n_trials)
    z_inv_e = norm.ppf(1 - 1/(n_trials * np.exp(-1)))
    sr_0 = np.sqrt(sr_variance) * (
        (1 - euler_mascheroni) * z_inv + euler_mascheroni * z_inv_e
    )

    # DSR
    numerator = (sr_hat - sr_0) * np.sqrt(T - 1)
    denominator = np.sqrt(1 - skew * sr_hat + (kurtosis - 1) / 4 * sr_hat**2)

    return norm.cdf(numerator / denominator)
```

---

## 6. Key Papers & References

### Foundational

| Paper | Authors | Year | Key Contribution |
|-------|---------|------|------------------|
| Advances in Financial Machine Learning | Lopez de Prado | 2018 | CPCV, purging, embargoing, meta-labeling |
| The Probability of Backtest Overfitting | Bailey, Borwein, Lopez de Prado, Zhu | 2014/2017 | PBO via CSCV (SSRN 2326253) |
| The Deflated Sharpe Ratio | Bailey & Lopez de Prado | 2014 | DSR correcting for selection bias + non-normality (SSRN 2460551) |
| A Reality Check for Data Snooping | White | 2000 | Bootstrap Reality Check (Econometrica) |
| A Test for Superior Predictive Ability | Hansen | 2005 | SPA test (improved WRC) |
| Stepwise Multiple Testing | Romano & Wolf | 2005 | StepM procedure |
| ...and the Cross-Section of Expected Returns | Harvey, Liu & Zhu | 2016 | Haircut SR, multiple testing in finance |
| What to Look for in a Backtest | Lopez de Prado | 2014 | MinBTL, practical checklist (SSRN 2308682) |
| The 10 Reasons Most ML Funds Fail | Lopez de Prado | 2018 | Organizational + technical failure modes |

### 2024-2025

| Paper | Authors | Year | Key Contribution |
|-------|---------|------|------------------|
| Backtest Overfitting in the ML Era | Arian, Norouzi, Seco | 2024 | Synthetic environment comparison; CPCV >> WF (SSRN 4686376) |
| The GT-Score | Sheppert | 2025 | Anti-overfitting objective function (arXiv 2602.00080) |
| Hypothesis-Driven Walk-Forward Framework | (multiple) | 2024 | Interpretable validation template (arXiv 2512.12924) |
| Empirical Framework for Detecting Overfitting | Goyle | 2025 | 5-pillar validation, momentum case study (SSRN 5331456) |
| Regime-Aware Asset Allocation via Statistical Jump Model | (multiple) | 2024 | HMM + walk-forward regime validation (arXiv 2402.05272) |
| skfolio: Portfolio Optimization in Python | Nicolini | 2024/2025 | Unified scikit-learn API for CPCV + portfolio optimization (arXiv 2507.04176) |

### Seven Sins of Quantitative Investing (Arnott et al.)

1. Survivorship bias (excluding failed securities)
2. Look-ahead bias (using future information)
3. Storytelling bias (post-hoc rationalization)
4. Overfitting and data snooping
5. Turnover and transaction cost underestimation
6. Outlier mishandling
7. Asymmetric pattern exploitation and shorting cost underestimation

---

## Appendix: Quick Reference Card

```
DETECTION METHODS (after-the-fact):
  CPCV         → Distribution of OOS paths (most powerful)
  PBO          → P(IS-optimal underperforms OOS median)
  DSR          → P(true alpha > 0) correcting for multiple testing
  SPA/StepM    → Bootstrap test: any/which models beat benchmark?
  WF           → Single OOS path (weak for detection, good for estimation)
  HLZ Haircut  → Non-linear SR adjustment for trial count

PREVENTION METHODS (by design):
  Economic theory → Constrain hypothesis space a priori
  Parsimony      → Minimize parameters (remove non-essential)
  Pre-registration → Define rules before seeing data
  Regime-aware   → Test across market conditions
  Cross-asset    → Validate across markets
  Model averaging → Ensemble for variance reduction

PIPELINE ORDER:
  0. Design discipline (economic rationale, pre-register)
  1. Statistical detection (CPCV → PBO → DSR → SPA → WF)
  2. Robustness (sensitivity → permutation → bootstrap → stress → cross-asset)
  3. Live validation (paper → small capital → full deploy)
```
