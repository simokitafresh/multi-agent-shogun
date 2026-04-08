<!--
generated: 2026-03-26
cmd: cmd_1410
source: 3-agent parallel research (research-nested-fof, research-anti-overfit, HRP/HERC Python implementation)
session: a4235eac-de13-4036-add6-9df09ba804ea
-->

# Nested FoF HRP/HERC Implementation Guide

> Comprehensive implementation reference for hierarchical portfolio construction using HRP, HERC, walk-forward validation, and PBO overfitting detection. All code examples target the skfolio + scipy ecosystem.

---

## Table of Contents

- [Part 1: Theory -- Hierarchical Portfolio Construction](#part-1-theory----hierarchical-portfolio-construction)
- [Part 2: Theory -- Anti-Overfitting Methods](#part-2-theory----anti-overfitting-methods)
- [Part 3: Python Implementation -- skfolio HRP/HERC](#part-3-python-implementation----skfolio-hrpherc)
- [Part 4: Python Implementation -- scipy Clustering](#part-4-python-implementation----scipy-clustering)
- [Part 5: Python Implementation -- Optimal Subset Selection](#part-5-python-implementation----optimal-subset-selection)
- [Part 6: Python Implementation -- Walk-Forward Validation](#part-6-python-implementation----walk-forward-validation)
- [Part 7: Python Implementation -- PBO (Probability of Backtest Overfitting)](#part-7-python-implementation----pbo-probability-of-backtest-overfitting)
- [Part 8: Practical Validation Pipeline](#part-8-practical-validation-pipeline)
- [Part 9: Nested FoF Architecture](#part-9-nested-fof-architecture)
- [References](#references)

---

## Part 1: Theory -- Hierarchical Portfolio Construction

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

**2024 Modification** (World Scientific, 2024): NCO has been reformulated using spectral clustering and Minimum Spanning Tree (MST) instead of the original K-Means, combined with Random Matrix Theory for covariance denoising. The Marcenko-Pastur distribution separates signal eigenvalues from noise eigenvalues before clustering, achieving a 59.85% RMSE reduction in estimation error compared to undenoised covariance.

### 1.3 Why HRP is Structurally Anti-Overfitting

1. **No matrix inversion**: Avoids the numerical instability that plagues Markowitz
2. **No expected return estimation**: Eliminates the largest source of estimation error (22-56x more impactful than covariance errors)
3. **Hierarchical decomposition**: Instability in one cluster does not propagate to others
4. **Recursive bisection**: Capital allocation decisions are local, not global
5. **Theoretically proven** (Antonov, Lipton, Lopez de Prado 2024): HRP allocation weights are analytically less noisy than Markowitz

### 1.4 HERC Improvements Over HRP

1. **Early stopping via gap statistic**: Does not cluster all the way to single assets, avoiding overfitting to noise
2. **Dendrogram-based splitting**: Respects natural cluster sizes rather than arbitrary bisection
3. **Ward's linkage**: Avoids the chaining effect of single linkage, producing more balanced clusters
4. **Flexible risk measures**: Can use CVaR, CDaR, or variance; CDaR-based HERC achieves statistically superior risk-adjusted performance

### 1.5 Rule-Based Method Comparison

| Method | Parameters Fitted | Covariance Needed? | Returns Needed? | Anti-Overfitting Level |
|--------|-------------------|---------------------|-----------------|----------------------|
| **Equal Weight (1/N)** | 0 | No | No | Maximum (no estimation error possible) |
| **Inverse Volatility** | N volatilities | Diagonal only | No | Very high (no covariance estimation error) |
| **Risk Parity / ERC** | Covariance matrix | Full | No | High (but sensitive to covariance noise) |
| **HRP** | Covariance matrix | Full (no inversion) | No | Very high (no matrix inversion = no instability) |
| **HERC** | Covariance + gap statistic | Full (no inversion) | No | Very high (early stopping prevents overfitting to noise) |
| **NCO** | Covariance + clustering | Full (small inversions) | Optional | High (compartmentalized instability) |
| **Maximum Diversification** | Covariance matrix | Full | No | High (invariance properties) |
| **Minimum Variance** | Covariance matrix | Full (requires inversion) | No | Moderate (sensitive to covariance estimation error) |
| **Mean-Variance (Markowitz)** | Covariance + expected returns | Full (requires inversion) | **Yes** | **Low** (errors in means are 22-56x more impactful than covariance errors) |

### 1.6 Key Researchers

| Researcher | Key Papers | Contribution |
|------------|-----------|-------------|
| Marcos Lopez de Prado | HRP (2016), NCO (2019), ML for Asset Managers (2020), HRP Theoretical Proof (2024) | Founded hierarchical portfolio construction; first theoretical proof HRP < noisy than Markowitz |
| Thomas Raffinot | HCAA (2017, SSRN 2840729), HERC (2018, SSRN 3237540) | HERC algorithm: dendrogram-based splitting + gap statistic + flexible risk measures |
| Antonov, Lipton, Lopez de Prado | HRP Theoretical Evidence (2024, ADIA Lab) | Analytical formulas for allocation weight noise |
| Palomar | Portfolio Optimization: Theory and Application (Cambridge, 2025) | Comprehensive textbook covering HRP, HERC, HCAA, graph-based portfolios |
| Nicolini, Manzi, Delatte | skfolio (arXiv 2507.04176, 2025) | scikit-learn-compatible library implementing HRP, HERC, NCO |

---

## Part 2: Theory -- Anti-Overfitting Methods

### 2.1 Combinatorial Purged Cross-Validation (CPCV)

**Origin**: Lopez de Prado, "Advances in Financial Machine Learning" (2018), Chapter 12.

**How it works**:
1. Divide time series into N sequential, non-overlapping groups (preserving temporal order)
2. Select all combinations of p groups as test sets (p > 1), remaining N-p as training
3. **Purge**: Remove training observations whose label horizon overlaps with test period
4. **Embargo**: Remove a buffer of observations after each test period from training set
5. Result: An **empirical distribution** of OOS outcomes across many paths

**2024 findings** (Arian, Norouzi & Seco, Knowledge-Based Systems 2024): In a synthetic controlled environment, **CPCV demonstrated marked superiority** over Walk-Forward, K-Fold, and Purged K-Fold in mitigating overfitting risks.

### 2.2 Probability of Backtest Overfitting (PBO)

**Origin**: Bailey, Borwein, Lopez de Prado & Zhu (2014/2017). SSRN 2326253.

**What it computes**: The probability that an in-sample optimal strategy underperforms the median out-of-sample. If PBO > 0.5, more than half the time your "best" strategy is actually below average OOS.

**Interpretation thresholds**:
- PBO < 0.10: Low overfitting risk
- PBO 0.10-0.30: Moderate (proceed with caution)
- PBO > 0.30: High overfitting risk (strategy fragile)

### 2.3 Deflated Sharpe Ratio (DSR)

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

### 2.4 Walk-Forward Analysis

- **Anchored (expanding window)**: Training window always starts at t=0 and grows. Better for strategies needing full history.
- **Rolling (fixed window)**: Training window has fixed length, slides forward. Adapts faster to regime changes.
- **Key limitation**: Walk-Forward produces a single path. Supplement with CPCV for overfitting detection.

---

## Part 3: Python Implementation -- skfolio HRP/HERC

### Installation

```bash
pip install skfolio
```

### Minimal Working Example (custom monthly returns DataFrame)

```python
import pandas as pd
import numpy as np
from skfolio import RiskMeasure
from skfolio.optimization import (
    HierarchicalRiskParity,
    HierarchicalEqualRiskContribution,
)
from skfolio.cluster import HierarchicalClustering, LinkageMethod
from skfolio.distance import PearsonDistance, KendallDistance

# --- INPUT: your monthly returns DataFrame ---
# monthly_returns: pd.DataFrame, rows=dates (DatetimeIndex), columns=asset names
# e.g. shape (120, 21) = 120 months x 21 assets

# Train/test split (no shuffle for time series)
split = int(len(monthly_returns) * 0.67)
X_train = monthly_returns.iloc[:split]
X_test  = monthly_returns.iloc[split:]

# --- HRP ---
model_hrp = HierarchicalRiskParity(
    risk_measure=RiskMeasure.CVAR,                # CVaR (ES at 95%)
    distance_estimator=PearsonDistance(),          # correlation-based distance
    hierarchical_clustering_estimator=HierarchicalClustering(
        linkage_method=LinkageMethod.WARD,
    ),
    portfolio_params=dict(name="HRP-CVaR"),
)
model_hrp.fit(X_train)
print("HRP weights:", model_hrp.weights_)

portfolio_hrp = model_hrp.predict(X_test)
print("HRP Sharpe:", portfolio_hrp.annualized_sharpe_ratio)

# --- HERC ---
model_herc = HierarchicalEqualRiskContribution(
    risk_measure=RiskMeasure.CVAR,
    distance_estimator=PearsonDistance(),
    hierarchical_clustering_estimator=HierarchicalClustering(
        linkage_method=LinkageMethod.WARD,
    ),
    portfolio_params=dict(name="HERC-CVaR"),
)
model_herc.fit(X_train)
print("HERC weights:", model_herc.weights_)

portfolio_herc = model_herc.predict(X_test)
print("HERC Sharpe:", portfolio_herc.annualized_sharpe_ratio)
```

### Key `RiskMeasure` options

| Enum | Meaning |
|------|---------|
| `RiskMeasure.VARIANCE` | Default. Standard variance |
| `RiskMeasure.SEMI_VARIANCE` | Downside variance only |
| `RiskMeasure.CVAR` | Conditional VaR (Expected Shortfall) at 95% |
| `RiskMeasure.MAX_DRAWDOWN` | Maximum drawdown |
| `RiskMeasure.CDAR` | Conditional Drawdown at Risk |
| `RiskMeasure.MEAN_ABSOLUTE_DEVIATION` | MAD |

### HRP vs HERC with GridSearchCV (parameter tuning)

```python
from sklearn.model_selection import GridSearchCV
from skfolio.metrics import make_scorer
from skfolio import RatioMeasure
from skfolio.model_selection import WalkForward, cross_val_predict

cv = WalkForward(train_size=252, test_size=60)  # 1yr train, 3mo test (daily)
# For monthly data: train_size=36, test_size=3  (3yr train, 3mo test)

grid_search = GridSearchCV(
    estimator=HierarchicalRiskParity(risk_measure=RiskMeasure.CVAR),
    cv=cv,
    n_jobs=-1,
    param_grid={
        "distance_estimator": [PearsonDistance(), KendallDistance()],
        "hierarchical_clustering_estimator__linkage_method": [
            LinkageMethod.WARD,
            LinkageMethod.COMPLETE,
        ],
    },
    scoring=make_scorer(RatioMeasure.CVAR_RATIO),
)
grid_search.fit(X_train)
best_model = grid_search.best_estimator_
print("Best params:", grid_search.best_params_)
```

### WalkForward with monthly frequency

```python
# For monthly returns with DatetimeIndex:
cv_monthly = WalkForward(
    train_size=36,       # 36 months training
    test_size=1,         # 1 month test
    expend_train=True,   # expanding window (not rolling)
)

# Generate walk-forward portfolio
pred = cross_val_predict(
    best_model,
    X_test,
    cv=cv_monthly,
    n_jobs=-1,
    portfolio_params=dict(name="HRP-WalkForward"),
)
# pred is a MultiPeriodPortfolio
print("Cumulative return:", pred.cumulative_returns)
```

### Key difference: HRP vs HERC

- **HRP**: Bisects the dendrogram into left/right halves at every level. Allocates between halves by inverse-variance. Does NOT use cluster structure beyond ordering.
- **HERC**: Exploits the dendrogram SHAPE. At each dendrogram node, allocates risk equally between the cluster's sub-clusters (not just bisection). Uses a convex solver for weight constraints.

---

## Part 4: Python Implementation -- scipy Clustering

```python
import numpy as np
import pandas as pd
from scipy.spatial.distance import squareform
from scipy.cluster.hierarchy import linkage, dendrogram, fcluster
import matplotlib.pyplot as plt

# --- INPUT ---
# monthly_returns: pd.DataFrame, shape (T, N)
corr = monthly_returns.corr()                     # N x N correlation matrix

# --- Step 1: Correlation -> Distance ---
# Standard formula from Lopez de Prado:
dist_matrix = np.sqrt((1 - corr) / 2.0)           # values in [0, 1]
# dist_matrix is a full N x N symmetric matrix with 0 on diagonal

# --- Step 2: Condensed form (required by scipy linkage) ---
condensed_dist = squareform(dist_matrix, checks=False)

# --- Step 3: Ward linkage ---
# NOTE: Ward is technically defined for Euclidean distances.
# The correlation distance sqrt((1-rho)/2) IS a proper Euclidean metric
# (it equals the Euclidean distance of standardized return vectors),
# so Ward is valid here.
Z = linkage(condensed_dist, method='ward')

# --- Step 4: Plot dendrogram ---
fig, ax = plt.subplots(figsize=(14, 6))
dn = dendrogram(
    Z,
    labels=corr.columns.tolist(),
    leaf_rotation=90,
    leaf_font_size=9,
    ax=ax,
)
ax.set_ylabel("Distance")
ax.set_title("Ward Linkage Dendrogram (Correlation Distance)")
plt.tight_layout()
plt.savefig("dendrogram.png", dpi=150)
plt.show()

# --- Step 5: Extract cluster assignments ---
# Method A: Fixed number of clusters
n_clusters = 4
labels = fcluster(Z, t=n_clusters, criterion='maxclust')
cluster_df = pd.DataFrame({
    'asset': corr.columns,
    'cluster': labels,
})
print(cluster_df.sort_values('cluster'))

# Method B: Distance threshold
labels_dist = fcluster(Z, t=0.7, criterion='distance')

# --- Step 6: Quasi-diagonalization (seriation) ---
def get_quasi_diag(link):
    """Return leaf order from linkage matrix (Lopez de Prado seriation)."""
    link = link.astype(int)
    sort_ix = pd.Series([link[-1, 0], link[-1, 1]])
    num_items = link[-1, 3]
    while sort_ix.max() >= num_items:
        sort_ix.index = range(0, sort_ix.shape[0] * 2, 2)
        df0 = sort_ix[sort_ix >= num_items]
        i = df0.index
        j = df0.values - num_items
        sort_ix[i] = link[j, 0]
        df0 = pd.Series(link[j, 1], index=i + 1)
        sort_ix = pd.concat([sort_ix, df0])
        sort_ix = sort_ix.sort_index()
        sort_ix.index = range(sort_ix.shape[0])
    return sort_ix.tolist()

ordered_indices = get_quasi_diag(Z)
ordered_assets = [corr.columns[i] for i in ordered_indices]
print("Seriated order:", ordered_assets)

# Reorder correlation matrix for visualization
corr_ordered = corr.iloc[ordered_indices, ordered_indices]
```

### Linkage method comparison

| Method | Behavior | Best for |
|--------|----------|----------|
| `ward` | Minimizes total within-cluster variance | Balanced, compact clusters |
| `single` | Minimum pairwise distance (chaining risk) | Lopez de Prado's original HRP |
| `complete` | Maximum pairwise distance | Tight clusters, no chaining |
| `average` | Average pairwise distance | Compromise |

---

## Part 5: Python Implementation -- Optimal Subset Selection

```python
import numpy as np
import pandas as pd
from itertools import combinations

# --- INPUT ---
# corr: pd.DataFrame, shape (21, 21) -- correlation matrix
# monthly_returns: pd.DataFrame, shape (T, 21)
corr = monthly_returns.corr()
assets = corr.columns.tolist()
N = len(assets)  # 21

def avg_pairwise_corr(corr_matrix, subset_indices):
    """Average of all off-diagonal pairwise correlations for a subset."""
    sub = corr_matrix.iloc[subset_indices, subset_indices].values
    n = len(subset_indices)
    # Extract upper triangle (excluding diagonal)
    mask = np.triu_indices(n, k=1)
    pairwise = sub[mask]
    return pairwise.mean()

# --- Exhaustive search over subset sizes 3-7 ---
results = []
for k in range(3, 8):
    n_combos = 0
    best_score = np.inf
    best_subset = None
    for combo in combinations(range(N), k):
        score = avg_pairwise_corr(corr, list(combo))
        n_combos += 1
        if score < best_score:
            best_score = score
            best_subset = combo
    asset_names = [assets[i] for i in best_subset]
    results.append({
        'k': k,
        'avg_corr': best_score,
        'assets': asset_names,
        'n_combinations': n_combos,
    })
    print(f"k={k}: {n_combos:,} combos searched. "
          f"Best avg corr = {best_score:.4f} -> {asset_names}")

results_df = pd.DataFrame(results)
print(results_df)

# --- Combination counts for reference ---
# C(21,3) =   1,330
# C(21,4) =   5,985
# C(21,5) =  20,349
# C(21,6) =  54,264
# C(21,7) = 116,280
# Total    = 198,208  (runs in seconds)
```

### Vectorized version (faster for large N)

```python
def find_min_corr_subset_fast(corr_matrix, k):
    """Vectorized exhaustive search for minimum avg pairwise correlation."""
    vals = corr_matrix.values
    N = vals.shape[0]
    best_score = np.inf
    best_combo = None
    for combo in combinations(range(N), k):
        idx = list(combo)
        sub = vals[np.ix_(idx, idx)]
        # Sum upper triangle, divide by number of pairs
        score = (sub.sum() - np.trace(sub)) / (k * (k - 1))
        if score < best_score:
            best_score = score
            best_combo = combo
    return best_combo, best_score

# Usage:
for k in range(3, 8):
    combo, score = find_min_corr_subset_fast(corr, k)
    names = [assets[i] for i in combo]
    print(f"k={k}: avg_corr={score:.4f}, assets={names}")
```

### With constraint: must include specific asset(s)

```python
def find_min_corr_with_required(corr_matrix, k, required_indices):
    """Search subsets that must include certain assets."""
    vals = corr_matrix.values
    N = vals.shape[0]
    optional = [i for i in range(N) if i not in required_indices]
    n_optional = k - len(required_indices)

    best_score = np.inf
    best_combo = None
    for extra in combinations(optional, n_optional):
        idx = list(required_indices) + list(extra)
        sub = vals[np.ix_(idx, idx)]
        score = (sub.sum() - np.trace(sub)) / (k * (k - 1))
        if score < best_score:
            best_score = score
            best_combo = tuple(idx)
    return best_combo, best_score
```

---

## Part 6: Python Implementation -- Walk-Forward Validation

```python
import pandas as pd
import numpy as np

# --- INPUT ---
# monthly_returns: pd.DataFrame, rows=dates, columns=asset names
# Assume some portfolio_rule function that takes training returns
# and outputs weights (dict or Series)

def portfolio_rule(train_returns: pd.DataFrame) -> pd.Series:
    """Example: inverse-volatility weighting."""
    vol = train_returns.std()
    w = (1.0 / vol)
    w /= w.sum()
    return w

def walk_forward_expanding(
    returns: pd.DataFrame,
    rule_fn,
    min_train_months: int = 24,
    rebalance_every: int = 1,   # rebalance every N months
) -> pd.DataFrame:
    """
    Expanding-window walk-forward backtest.

    Train on months [0..T-1], predict weights, test on month T.
    Expand window, repeat.

    Parameters
    ----------
    returns : pd.DataFrame
        Monthly returns. Rows=dates, columns=assets.
    rule_fn : callable
        Takes training returns DataFrame, returns weights Series.
    min_train_months : int
        Minimum training window before first prediction.
    rebalance_every : int
        Rebalance frequency in months.

    Returns
    -------
    pd.DataFrame with columns: date, portfolio_return, weights (dict)
    """
    dates = returns.index
    n_months = len(dates)

    records = []
    current_weights = None

    for t in range(min_train_months, n_months):
        # Expanding window: always start from month 0
        train = returns.iloc[:t]            # months [0, t-1]
        test_return = returns.iloc[t]       # month t (Series of asset returns)

        # Rebalance?
        months_since_start = t - min_train_months
        if current_weights is None or months_since_start % rebalance_every == 0:
            current_weights = rule_fn(train)

        # Portfolio return = dot product of weights and asset returns
        port_ret = (current_weights * test_return).sum()

        records.append({
            'date': dates[t],
            'portfolio_return': port_ret,
            'weights': current_weights.to_dict(),
            'train_months': t,
        })

    result = pd.DataFrame(records)
    result['cumulative_return'] = (1 + result['portfolio_return']).cumprod()
    return result

# --- Usage ---
wf_results = walk_forward_expanding(
    monthly_returns,
    rule_fn=portfolio_rule,
    min_train_months=24,
    rebalance_every=1,
)
print(wf_results[['date', 'portfolio_return', 'cumulative_return']].tail(10))

# --- Metrics ---
oos_returns = wf_results['portfolio_return']
sharpe = oos_returns.mean() / oos_returns.std() * np.sqrt(12)
max_dd = (wf_results['cumulative_return'] / wf_results['cumulative_return'].cummax() - 1).min()
print(f"OOS Sharpe (annualized): {sharpe:.3f}")
print(f"OOS Max Drawdown: {max_dd:.3f}")
```

### Walk-Forward with HRP (integrating skfolio)

```python
from skfolio.optimization import HierarchicalRiskParity
from skfolio import RiskMeasure

def hrp_rule(train_returns: pd.DataFrame) -> pd.Series:
    """HRP portfolio rule for walk-forward."""
    model = HierarchicalRiskParity(risk_measure=RiskMeasure.CVAR)
    model.fit(train_returns)
    return pd.Series(model.weights_, index=train_returns.columns)

wf_hrp = walk_forward_expanding(
    monthly_returns,
    rule_fn=hrp_rule,
    min_train_months=36,   # 3 years minimum
    rebalance_every=3,     # quarterly rebalance
)
```

### Walk-Forward comparing multiple rules

```python
def equal_weight_rule(train_returns):
    n = train_returns.shape[1]
    return pd.Series(1.0/n, index=train_returns.columns)

def min_var_rule(train_returns):
    cov = train_returns.cov()
    inv_cov = np.linalg.inv(cov.values)
    ones = np.ones(len(cov))
    w = inv_cov @ ones / (ones @ inv_cov @ ones)
    return pd.Series(w, index=train_returns.columns)

rules = {
    'EqualWeight': equal_weight_rule,
    'InvVol': portfolio_rule,
    'MinVar': min_var_rule,
    'HRP': hrp_rule,
}

all_results = {}
for name, fn in rules.items():
    wf = walk_forward_expanding(monthly_returns, fn, min_train_months=36)
    all_results[name] = wf['portfolio_return']
    sr = wf['portfolio_return'].mean() / wf['portfolio_return'].std() * np.sqrt(12)
    print(f"{name}: OOS Sharpe = {sr:.3f}")

comparison = pd.DataFrame(all_results)
cumulative = (1 + comparison).cumprod()
cumulative.plot(title="Walk-Forward Comparison", figsize=(12, 6))
```

---

## Part 7: Python Implementation -- PBO (Probability of Backtest Overfitting)

### Option A: Using pypbo library

```bash
pip install pypbo
```

```python
import numpy as np
import pandas as pd
import pypbo as pbo
import pypbo.perf as perf

# --- INPUT ---
# strategy_returns: pd.DataFrame, shape (T, N_strategies)
#   Each column = one strategy variant / parameter combination
#   Each row = one time period (month)
#   This represents N different backtest trials over the same time period

def metric_func(returns_array):
    """Annualized Sharpe ratio (monthly data -> *sqrt(12))."""
    return np.sqrt(12) * perf.sharpe_iid(returns_array)

S = 16  # Number of partitions (must be even; paper recommends 16)

result = pbo.pbo(
    strategy_returns.values,   # numpy array, shape (T, N_strategies)
    S=S,
    metric_func=metric_func,
    threshold=0.0,             # Sharpe threshold for "loss"
    n_jobs=4,
    plot=True,
    verbose=True,
    hist=True,
)

print(f"PBO = {result.pbo:.4f}")           # Probability of overfitting
print(f"P(OOS loss) = {result.prob_oos_loss:.4f}")  # Prob of OOS Sharpe < threshold
print(f"Performance degradation slope = {result.linear_model.slope:.4f}")
```

### Option B: Manual PBO implementation (no external dependency)

```python
import numpy as np
import pandas as pd
from itertools import combinations
from scipy.special import logit
from scipy.stats import rankdata, gaussian_kde, linregress
from scipy.integrate import quad

def compute_pbo(
    strategy_returns: pd.DataFrame,
    S: int = 16,
    metric_func=None,
    threshold: float = 0.0,
) -> dict:
    """
    Compute Probability of Backtest Overfitting via CSCV.

    Parameters
    ----------
    strategy_returns : pd.DataFrame
        Shape (T, N). Each column = one strategy/parameter variant.
        Each row = one time period return.
    S : int
        Number of partitions (must be even). 16 is recommended.
    metric_func : callable
        Takes 1D array of returns, returns scalar performance metric.
        Default: annualized Sharpe ratio.
    threshold : float
        OOS performance threshold for loss probability.

    Returns
    -------
    dict with keys: pbo, prob_oos_loss, logits, sharpe_is, sharpe_oos,
                    slope, intercept
    """
    if metric_func is None:
        def metric_func(x):
            if x.std() == 0:
                return 0.0
            return x.mean() / x.std() * np.sqrt(12)

    M = strategy_returns.values  # (T, N)
    T, N = M.shape

    # Trim rows so T is divisible by S
    residual = T % S
    if residual > 0:
        M = M[residual:]
    T = M.shape[0]
    chunk_size = T // S

    # Partition into S chunks
    chunks = []
    for i in range(S):
        chunks.append(M[i * chunk_size : (i + 1) * chunk_size, :])

    # CSCV: all combinations of S/2 chunks for training
    half = S // 2
    all_combos = list(combinations(range(S), half))

    logits_list = []
    sharpe_is_list = []
    sharpe_oos_list = []

    for combo in all_combos:
        # Training set (IS): selected chunks
        complement = sorted(set(range(S)) - set(combo))

        train_data = np.concatenate([chunks[i] for i in sorted(combo)], axis=0)
        test_data  = np.concatenate([chunks[i] for i in complement], axis=0)

        # Compute metric for each strategy on IS and OOS
        R_is  = np.array([metric_func(train_data[:, j]) for j in range(N)])
        R_oos = np.array([metric_func(test_data[:, j])  for j in range(N)])

        # Find best IS strategy
        n_star = np.argmax(R_is)

        # Rank of best-IS strategy in OOS
        oos_ranks = rankdata(R_oos)
        rank_of_best = oos_ranks[n_star]

        # Relative rank (omega)
        omega = rank_of_best / (N + 1)
        # Clamp to avoid logit(0) or logit(1)
        omega = np.clip(omega, 0.01, 0.99)

        lam = logit(omega)
        logits_list.append(lam)
        sharpe_is_list.append(R_is[n_star])
        sharpe_oos_list.append(R_oos[n_star])

    logits_arr = np.array(logits_list)

    # PBO = fraction of logits <= 0
    pbo_value = np.mean(logits_arr <= 0)

    # Prob of OOS loss
    oos_arr = np.array(sharpe_oos_list)
    prob_oos_loss = np.mean(oos_arr < threshold)

    # Performance degradation (IS vs OOS of best-IS strategy)
    is_arr = np.array(sharpe_is_list)
    slope_result = linregress(is_arr, oos_arr)

    # KDE-based PBO (continuous estimate)
    if len(set(logits_arr)) > 2:
        kde = gaussian_kde(logits_arr)
        pbo_kde, _ = quad(kde, -np.inf, 0)
    else:
        pbo_kde = pbo_value

    return {
        'pbo': pbo_value,
        'pbo_kde': pbo_kde,
        'prob_oos_loss': prob_oos_loss,
        'logits': logits_arr,
        'sharpe_is': is_arr,
        'sharpe_oos': oos_arr,
        'slope': slope_result.slope,
        'intercept': slope_result.intercept,
        'n_combinations': len(all_combos),
    }

# --- Usage ---
# strategy_returns: DataFrame where each column is a strategy variant
# e.g., 21 different parameter settings tested over 120 months
result = compute_pbo(strategy_returns, S=16, threshold=0.0)

print(f"PBO = {result['pbo']:.3f} (discrete), {result['pbo_kde']:.3f} (KDE)")
print(f"P(OOS loss) = {result['prob_oos_loss']:.3f}")
print(f"Performance degradation slope = {result['slope']:.3f}")
print(f"Number of CSCV combinations = {result['n_combinations']:,}")
```

### Generating strategy_returns for PBO (example: varying HRP parameters)

```python
def generate_strategy_returns_for_pbo(
    monthly_returns: pd.DataFrame,
    min_train: int = 36,
) -> pd.DataFrame:
    """
    Generate a matrix of OOS returns for multiple strategy variants.
    Each column = one parameter combination tested walk-forward.
    """
    from skfolio.optimization import HierarchicalRiskParity
    from skfolio import RiskMeasure
    from skfolio.cluster import HierarchicalClustering, LinkageMethod
    from skfolio.distance import PearsonDistance, KendallDistance

    configs = [
        dict(risk_measure=RiskMeasure.VARIANCE, distance_estimator=PearsonDistance()),
        dict(risk_measure=RiskMeasure.CVAR, distance_estimator=PearsonDistance()),
        dict(risk_measure=RiskMeasure.SEMI_VARIANCE, distance_estimator=PearsonDistance()),
        dict(risk_measure=RiskMeasure.VARIANCE, distance_estimator=KendallDistance()),
        dict(risk_measure=RiskMeasure.CVAR, distance_estimator=KendallDistance()),
        # ... add more parameter combinations
    ]

    all_oos = {}
    for i, cfg in enumerate(configs):
        model = HierarchicalRiskParity(**cfg)
        oos_returns = []
        dates = []
        for t in range(min_train, len(monthly_returns)):
            train = monthly_returns.iloc[:t]
            test_row = monthly_returns.iloc[t]
            model.fit(train)
            w = pd.Series(model.weights_, index=train.columns)
            oos_returns.append((w * test_row).sum())
            dates.append(monthly_returns.index[t])
        all_oos[f"config_{i}"] = oos_returns

    return pd.DataFrame(all_oos, index=dates)

# Then:
strategy_rets = generate_strategy_returns_for_pbo(monthly_returns)
pbo_result = compute_pbo(strategy_rets, S=8)  # S=8 if T is small
```

### PBO visualization

```python
import matplotlib.pyplot as plt

def plot_pbo_results(result):
    fig, axes = plt.subplots(1, 3, figsize=(16, 5))

    # 1. Logit distribution
    ax = axes[0]
    ax.hist(result['logits'], bins=20, density=True, alpha=0.6, color='steelblue')
    if len(set(result['logits'])) > 2:
        kde = gaussian_kde(result['logits'])
        x = np.linspace(result['logits'].min() - 1, result['logits'].max() + 1, 200)
        ax.plot(x, kde(x), 'k-', lw=2)
        ax.fill_between(x, 0, kde(x), where=(x < 0), alpha=0.3, color='red')
    ax.axvline(0, color='red', ls='--')
    ax.set_title(f"PBO = {result['pbo_kde']:.3f}")
    ax.set_xlabel("Logit(rank)")

    # 2. IS vs OOS performance
    ax = axes[1]
    ax.scatter(result['sharpe_is'], result['sharpe_oos'], alpha=0.5, s=10)
    ax.axhline(0, color='grey', ls='--')
    ax.axvline(0, color='grey', ls='--')
    xl = ax.get_xlim()
    x_line = np.linspace(xl[0], xl[1], 100)
    ax.plot(x_line, result['slope'] * x_line + result['intercept'], 'r-', lw=2)
    ax.set_xlabel("IS Sharpe (best config)")
    ax.set_ylabel("OOS Sharpe (same config)")
    ax.set_title(f"Perf. Degradation (slope={result['slope']:.2f})")

    # 3. OOS distribution
    ax = axes[2]
    ax.hist(result['sharpe_oos'], bins=20, alpha=0.6, color='green')
    ax.axvline(0, color='red', ls='--')
    ax.set_title(f"P(OOS loss) = {result['prob_oos_loss']:.3f}")
    ax.set_xlabel("OOS Sharpe of IS-best config")

    plt.tight_layout()
    plt.savefig("pbo_analysis.png", dpi=150)
    plt.show()

plot_pbo_results(result)
```

---

## Part 8: Practical Validation Pipeline

### Step-by-Step Framework

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
| 1.3 | Compute Deflated Sharpe Ratio | `mlfinlab` or manual formula | DSR > 0.95 (>95% probability of genuine alpha) |
| 1.4 | Run SPA test (vs buy-and-hold benchmark) | `arch.bootstrap.SPA` | Consistent p-value < 0.05 |
| 1.5 | Apply HLZ haircut to observed Sharpe | Manual or `quantstrat` | Haircut SR still economically meaningful |
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
  -- FAIL any -> Redesign strategy before touching data

Phase 1: STATISTICAL DETECTION
  -- FAIL PBO or DSR -> Strategy is overfit. Discard or fundamentally redesign.
  -- FAIL SPA/WF -> Weak evidence. Consider as "research-stage only."
  -- PASS all -> Proceed to Phase 2.

Phase 2: ROBUSTNESS
  -- FAIL sensitivity or permutation -> Strategy is fragile. Simplify.
  -- FAIL cross-asset -> Strategy may be asset-specific (acceptable if justified).
  -- FAIL cost sensitivity -> Strategy is not tradeable. Reduce turnover.
  -- PASS all -> Proceed to Phase 3.

Phase 3: LIVE VALIDATION
  -- FAIL paper/live divergence -> Implementation issue or regime shift. Investigate.
  -- PASS -> Deploy with monitoring.
```

---

## Part 9: Nested FoF Architecture

### Two-Level NCO Structure for FoF

NCO directly maps to Fund-of-Funds:
- **Inner level**: Individual assets/strategies within sub-funds
- **Outer level**: Sub-funds within the meta-portfolio
- **Final weights**: Dot product of inner and outer weights

### Capital Allocation: Top-Down Through the Dendrogram

From Palomar's "Portfolio Optimization: Theory and Application" (Cambridge, 2025):

1. Start with total capital at the root
2. At each dendrogram split, compute the split factor: `alpha = variance(subset2) / (variance(subset1) + variance(subset2))`
3. Subset 1 receives weight `alpha`, subset 2 receives weight `(1 - alpha)`
4. Continue recursively until reaching individual assets/funds

### Practical Recommendations for Nested FoF

1. **Structure**: Use hierarchical clustering (Ward's linkage) to discover natural groupings
2. **Inner allocation**: Within each cluster, use inverse volatility or equal risk contribution
3. **Outer allocation**: Across clusters, use HRP recursive bisection or HERC equal risk contribution
4. **Early stopping**: Apply gap statistic to determine the right number of clusters
5. **Covariance estimation**: Apply denoising via Random Matrix Theory (Marchenko-Pastur) before computing distances
6. **No return forecasting**: Rely exclusively on risk-based allocation to eliminate the largest source of estimation error
7. **Validation**: Use CPCV to assess out-of-sample robustness without information leakage

---

## Implementation Tools Summary

```
pip install skfolio scipy numpy pandas matplotlib
pip install pypbo  # optional, for PBO shortcut
```

| Topic | Primary Library | Key Functions |
|-------|----------------|---------------|
| HRP/HERC | `skfolio` | `HierarchicalRiskParity`, `HierarchicalEqualRiskContribution` |
| Clustering | `scipy.cluster.hierarchy` | `linkage`, `fcluster`, `dendrogram`, `squareform` |
| Subset selection | `itertools` + `numpy` | `combinations`, `np.triu_indices` |
| Walk-forward | Pure Python/pandas | Custom expanding-window loop |
| PBO | `pypbo` or manual | CSCV + `scipy.special.logit` + `scipy.stats.gaussian_kde` |
| CPCV | `skfolio` | `CombinatorialPurgedCV` |
| SPA/StepM/MCS | `arch` | `SPA`, `StepM`, `MCS` |
| DSR | Manual or `mlfinlab` | Custom formula (see Part 2) |

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

**Critical implementation notes:**
- skfolio's `fit(X)` expects X as a returns DataFrame (not prices). Use `prices_to_returns()` for price data.
- Ward linkage requires Euclidean distances. The `sqrt((1-rho)/2)` formula IS Euclidean, so Ward is valid.
- For PBO, S must be even. S=16 is standard. With monthly data, T/S must give reasonable chunk sizes (at least 5-10 observations per chunk, so T >= 80 for S=16; use S=8 if T is small).
- The exhaustive subset search for C(21,7) = 116,280 combinations runs in under 1 second with the vectorized version.

---

## References

### Implementation Sources
- [skfolio HRP vs HERC example](https://skfolio.org/auto_examples/clustering/plot_3_hrp_vs_herc.html)
- [skfolio HRP CVaR example](https://skfolio.org/auto_examples/clustering/plot_1_hrp_cvar.html)
- [skfolio HierarchicalRiskParity API](https://skfolio.org/generated/skfolio.optimization.HierarchicalRiskParity.html)
- [skfolio WalkForward API](https://skfolio.org/generated/skfolio.model_selection.WalkForward.html)
- [skfolio Optimization User Guide](https://skfolio.org/user_guide/optimization.html)
- [skfolio NCO Documentation](https://skfolio.org/auto_examples/clustering/plot_4_nco.html)
- [HRP from scratch (Lopez de Prado gist)](https://gist.github.com/jaymon0703/d69ad008b21ef7af4ffd9918713bdda4)
- [HRP implementation & experiments (G. Marti)](https://gmarti.gitlab.io//qfin/2018/10/02/hierarchical-risk-parity-part-1.html)
- [HRP with Python tutorial (Ken Wu)](https://kenwuyang.com/posts/2024_10_20_portfolio_optimization_with_python_hierarchical_risk_parity/)
- [scipy linkage documentation](https://docs.scipy.org/doc/scipy/reference/generated/scipy.cluster.hierarchy.linkage.html)
- [pypbo GitHub repository](https://github.com/esvhd/pypbo)
- [PBO implementation article (Balaena Quant)](https://medium.com/balaena-quant-insights/the-probability-of-backtest-overfitting-pbo-9ba0ac7fb456)
- [Minimal Correlation Portfolio (GitHub)](https://github.com/1kc2/Minimal-Correlation-Portfolio)
- [Walk-forward backtesting implementation](https://www.insightbig.com/post/what-is-walk-forward-backtesting-implementation-in-python)

### Academic Papers
- Lopez de Prado, "Building Diversified Portfolios that Outperform Out-of-Sample" (2016) -- HRP
- Lopez de Prado, "A Robust Estimator of the Efficient Frontier" (SSRN 3469961, 2019) -- NCO
- Raffinot, "Hierarchical Clustering-Based Asset Allocation" (SSRN 2840729, 2017) -- HCAA
- Raffinot, "The Hierarchical Equal Risk Contribution Portfolio" (SSRN 3237540, 2018) -- HERC
- Antonov, Lipton, Lopez de Prado, "Overcoming Markowitz's Instability with HRP" (2024, ADIA Lab) -- HRP theoretical proof
- Bailey, Borwein, Lopez de Prado, Zhu, "The Probability of Backtest Overfitting" (SSRN 2326253, 2014/2017) -- PBO
- Bailey & Lopez de Prado, "The Deflated Sharpe Ratio" (SSRN 2460551, 2014) -- DSR
- Arian, Norouzi & Seco, "Backtest Overfitting in the ML Era" (Knowledge-Based Systems, 2024) -- CPCV comparison
- Palomar, "Portfolio Optimization: Theory and Application" (Cambridge, 2025) -- Comprehensive textbook
- Nicolini, Manzi, Delatte, "skfolio: Portfolio Optimization in Python" (arXiv 2507.04176, 2025) -- skfolio
- Hierarchical Minimum Variance Portfolios (arXiv 2503.12328, March 2025) -- Schur complement recursion
- NCO with Random Matrix Theory (World Scientific, 2024) -- Denoised covariance NCO
