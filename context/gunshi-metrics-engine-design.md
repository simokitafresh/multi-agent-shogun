<!-- last_updated: 2026-04-09 -->
# Metrics Research Engine — Rolling拡張設計書

<!-- cmd: metrics_engine_design | author: gunshi | created: 2026-04-04T00:30:00+09:00 -->

## §1 現状と目的

### 既存エンジン (cmd_1730で疾風が実装済み)

`scripts/analysis/standard_pf_preprocessing/metrics_research_engine.py`

| 機能 | 状態 | 詳細 |
|------|------|------|
| MetricsCalculator import | **完了** | `sys.path.insert(0, backend)` → `from app.services.metrics_calculator import MetricsCalculator` |
| DTB3キャッシュ | **完了** | `load_dtb3_cache()` → 1クエリで全期間取得 |
| 全PFメトリクス計算 | **完了** | `get_all_pf_metrics(years, source="calculator")` → 65PF×42メトリクス DataFrame |
| キャッシュ読取 | **完了** | `load_cached_pf_metrics(years)` → portfolio_metricsテーブルから取得 |
| パリティ検証 | **完了** | `verify_portfolio_metrics_parity(years, atol=1e-12)` → calculator vs cache突合 |
| flatten | **完了** | `flatten_metrics_payload()` → nested dict → flat dict (metric__slug__timing__field) |

### 不足 (本設計で追加)

| 機能 | 必要理由 |
|------|---------|
| **Rolling計算** | ALM研究でlookbackごとのメトリクス時系列が必要。DMAの特徴量 |
| **3Dテンソル** | 65PF×170月×42メトリクス。全PF横断分析・ヒートマップ・ランキング推移 |
| **数値メトリクスAPI** | ALM研究スクリプトから `import → 1行` で3Dテンソル取得 |

### 背景 (研究日誌Phase 20)

ALM(Adaptive Lookback Momentum)研究では:
- Levy DMAの包含確率(IP)が1M lookbackに偏る問題(Phase 19.5)
- DMAの目的関数(Binary=方向予測) ≠ 実際に儲かるlookback(18M)
- **42メトリクスを特徴量に使い、目的関数をCAGRベースに改良する**(cmd_1729→cmd_1730)
- 本番metrics_calculator.pyと同一ロジック必須(殿指示: 独自計算は本番と乖離)

## §2 アーキテクチャ

```
既存エンジン (変更なし)
├── get_all_pf_metrics(years, source)     → 全PF単一期間 DataFrame
├── load_cached_pf_metrics(years)          → キャッシュ読取
├── verify_portfolio_metrics_parity()      → パリティ検証
└── flatten_metrics_payload()              → dict → flat dict

★ 新規追加
├── NUMERIC_METRICS: list[str]             → 42メトリクスのうち数値のみ34個
├── compute_rolling_metrics(pf_id, window_months=60)
│     → pd.DataFrame shape=(T-window, 34)  # 1PFのrolling数値メトリクス
├── compute_all_rolling(window_months=60)
│     → dict[str, pd.DataFrame]            # 全PF {pf_id: DataFrame}
├── build_tensor(window_months=60)
│     → np.ndarray shape=(N_pf, T_windows, 34), pf_ids, metric_names, dates
└── get_metric_names()
      → list[str]                          # 34メトリクス名（テンソル列順）
```

### import API (ALM研究スクリプトから)

```python
from metrics_research_engine import build_tensor, get_metric_names

# 本番PFテンソル
tensor, pf_ids, metric_names, dates = build_tensor(window_months=60)
# tensor.shape = (65, ~170, 34)
```

### ★ §2.1 仮想戦略API (ALM拡張)

ALM研究では**任意の月次リターン系列**(本番PFではなくシミュレーション結果)から34メトリクスを計算する。

#### 用途
6 lookback × 月次top N選択 → 仮想戦略リターン → 34メトリクスでlookback評価 → 34通りのALM

#### API設計

```python
from metrics_research_engine import (
    compute_metrics_from_returns,
    compute_rolling_from_returns,
    get_metric_names,
)

# (1) 仮想戦略 → 34メトリクス(1ショット)
metrics = compute_metrics_from_returns(
    monthly_returns,           # pd.Series (DatetimeIndex, float)
    benchmark_returns=spy_ret, # pd.Series (optional, default=None→NaN)
    dtb3_cache=dtb3_df,        # pd.DataFrame (optional, default=None→rf=0)
)
# → dict[str, float] (34メトリクス)

# (2) 仮想戦略 → Rolling 34メトリクス
rolling_df = compute_rolling_from_returns(
    monthly_returns,
    window_months=60,
    benchmark_returns=spy_ret,
    dtb3_cache=dtb3_df,
)
# → pd.DataFrame shape=(T-60, 34)

# (3) ALM 6 lookback一括
results = {}
for lb in [1, 3, 6, 12, 18, 24]:
    strategy_returns = simulate_alm(lb, ...)  # ALM研究側
    results[lb] = compute_metrics_from_returns(strategy_returns, ...)
# → {1: {34 metrics}, 3: {...}, ...}
```

#### 実装方針: 既存compute_34_metricsを完全再利用

`_prepare_monthly_metrics_frame`は既にportfolio_returnからcumulativeを自動生成する(L275-278)。ベンチマーク/RF不在時もNaN/0.0でfallback(L303-311)。**新関数はDataFrame構築ラッパーのみ。計算ロジック追加ゼロ。**

```python
def compute_metrics_from_returns(
    monthly_returns: pd.Series,
    benchmark_returns: pd.Series | None = None,
    dtb3_cache: pd.DataFrame | None = None,
) -> dict[str, float]:
    """任意のリターン系列から34メトリクスを計算。DB不要。"""
    df = pd.DataFrame({"portfolio_return": monthly_returns}, index=monthly_returns.index)
    if benchmark_returns is not None:
        df["benchmark_return"] = benchmark_returns
    # _prepare_monthly_metrics_frameがcumulative/rf_return等を自動生成
    return compute_34_metrics(_prepare_monthly_metrics_frame(df, dtb3_cache=dtb3_cache))


def compute_rolling_from_returns(
    monthly_returns: pd.Series,
    window_months: int = 60,
    benchmark_returns: pd.Series | None = None,
    dtb3_cache: pd.DataFrame | None = None,
) -> pd.DataFrame:
    """任意のリターン系列のRolling 34メトリクス。DB不要。"""
    df = pd.DataFrame({"portfolio_return": monthly_returns}, index=monthly_returns.index)
    if benchmark_returns is not None:
        df["benchmark_return"] = benchmark_returns
    prepared = _prepare_monthly_metrics_frame(df, dtb3_cache=dtb3_cache)
    rows = []
    for t in range(window_months, len(prepared)):
        slc = prepared.iloc[t - window_months : t]
        rows.append(compute_34_metrics(slc))
    return pd.DataFrame(rows, index=prepared.index[window_months:], columns=NUMERIC_METRICS)
```

#### 計算時間見積

- 6 lookback × 170窓 × compute_34_metrics(0.004s/コール) ≈ **4秒**
- 6 lookback × 1ショット(rolling不要の場合) ≈ **0.03秒**
- 見込み1-2分は十分な余裕。**並列化不要**

#### MetricsCalculator再利用方針

compute_34_metricsはMetricsCalculatorの**static methods 4つ**(max_runup/tail_contribution/left_tail_jumps/new_high_frequency)をimportしている(L468-471)。残り30メトリクスは純粋NumPy/pandas。**import可能。転写不要。**

### §2.2 L1シミュレーター — score_fn抽象化による研究パイプライン統合

#### 背景

flair_confidence_study.py L164とlevy_dma_dms_study.py L273に**同一構造**のsimulate_selection_strategyが重複。核心ロジック: score_wide(PF×月のスコア行列)→top_n選択→EWリターン。**score_wideの生成方法だけが研究ごとに違う。**

#### API設計

```python
from metrics_research_engine import simulate_selection, compute_metrics_from_returns

# score_fn: (return_wide, year_month) → pd.Series(PF名→スコア)
# score_fnを差し替えるだけで全L1研究が回る

def simulate_selection(
    return_wide: pd.DataFrame,       # PF×月のリターン行列(columns=PF名, index=year_month)
    score_fn: Callable[[pd.DataFrame, str], pd.Series],  # スコア関数
    top_n: int = 5,
    gate_negative: bool = False,     # 全スコア<0→Cash
) -> pd.Series:
    """汎用L1選択シミュレーション。月次EWリターン系列を返す。"""
    ...
    # → pd.Series(index=DatetimeIndex, values=monthly_return)
```

#### 使用例

```python
# ALM: momentum lookback=18M
def alm_score_fn(return_wide, year_month):
    # 直近18Mの累積リターンをスコアに
    idx = return_wide.index.get_loc(year_month)
    if idx < 18: return pd.Series(dtype=float)
    window = return_wide.iloc[idx-18:idx]
    return (1 + window).prod() - 1

returns = simulate_selection(return_wide, alm_score_fn, top_n=5)
metrics = compute_metrics_from_returns(returns, benchmark_returns=spy)

# FLAIR: confidence top3
def flair_score_fn(return_wide, year_month):
    return flair_confidence_scores[year_month]  # 事前計算済み

returns = simulate_selection(return_wide, flair_score_fn, top_n=3)

# 6 lookback一括ALM
for lb in [1, 3, 6, 12, 18, 24]:
    score_fn = lambda rw, ym, _lb=lb: momentum_score(rw, ym, _lb)
    ret = simulate_selection(return_wide, score_fn, top_n=5)
    results[lb] = compute_metrics_from_returns(ret)
```

#### 実装方針

flair_confidence_study.py L164-212の`simulate_selection_strategy`を汎用化。変更点:
1. `score_wide`引数(事前計算済み行列)→`score_fn`引数(callable)に変更。遅延評価でメモリ効率化
2. 返り値: DataFrame(strategy/year_month/monthly_return/holding_signal)→**pd.Series(monthly_return)に簡素化**。compute_metrics_from_returnsに直接渡せる
3. `strategy_name`削除(呼び出し側で管理)
4. `eligible_months`→`return_wide.index`から自動導出

#### 完全パイプライン

```
score_fn(research固有)
  ↓
simulate_selection(return_wide, score_fn, top_n)    ← §2.2
  ↓ pd.Series(monthly_return)
compute_metrics_from_returns(returns, benchmark)    ← §2.1
  ↓ dict[str, float] (34メトリクス)
ALM研究スクリプトが消費
```

**score_fnを差し替えるだけで全L1研究(ALM/FLAIR/忍法パラメータ)が回る。**

#### §2.2.1 穴塞ぎ+追加機能

**穴(修正必須):**

| # | 穴 | 原因 | 対策 |
|---|-----|------|------|
| 1 | NaN汚染 | score_wide/return_wideにNaN(PF開始前)。argsortでNaNが最上位 | `np.where(np.isnan(scores), -np.inf, scores)`でNaNを最下位に強制 |
| 2 | PF数<top_n | 有効PF数が月によって異なる | `min(top_n, valid_count)`で動的クリップ。valid=0→Cash(0.0) |
| 3 | 引数排他 | score_fn/score_wide両方指定or両方なし | ValueErrorで即座に弾く |

**追加機能:**

| # | 機能 | 理由 | API |
|---|------|------|-----|
| 4 | **holding_signal** | 「いつどのPFが選ばれたか」。ALMのIPヒートマップ分析に必須 | 返り値をNamedTupleに拡張: `SelectionResult(returns: Series, holdings: DataFrame)` |
| 5 | **build_return_wide** | return_wide構築がlevy L116-127でコピペ。統合すべき | `build_return_wide(db) -> DataFrame` (PF×月のリターン行列) |
| 6 | **turnover** | 月次PF入替率。transaction cost分析の前提 | holdings列からshift比較で自動計算。SelectionResultに含める |

**高速化: score_wideモード**

```python
def simulate_selection(
    return_wide: pd.DataFrame,
    score_fn: Callable | None = None,
    score_wide: pd.DataFrame | None = None,  # ★事前計算行列(NumPy一括。100x速い)
    top_n: int = 5,
    gate_negative: bool = False,
) -> SelectionResult:
    # score_wide → NumPy一括(0.01s)。score_fn → 月ごとループ(1-2s)
    if score_wide is not None:
        scores = score_wide.reindex_like(return_wide).values
        scores = np.where(np.isnan(scores), -np.inf, scores)  # 穴1対策
        returns = return_wide.values
        top_idx = np.argsort(-scores, axis=1)[:, :top_n]
        # 穴2対策: NaN return除外
        selected = np.take_along_axis(returns, top_idx, axis=1)
        monthly_ret = np.nanmean(selected, axis=1)
        ...
```

## §3 メトリクス分類

42メトリクスのうち、テンソルに含めるのは**数値メトリクス34個**。テキスト/日付メトリクスは除外。

### 数値メトリクス (34個) — テンソル列

| # | メトリクス名 | format | 計算の要点 |
|---|-------------|--------|-----------|
| 0 | Arithmetic Mean (monthly) | percent | `mean(portfolio_return)` |
| 1 | Arithmetic Mean (annualized) | percent | monthly×12 |
| 2 | Geometric Mean (monthly) | percent | `(Π(1+r))^(1/n) - 1` |
| 3 | Geometric Mean (annualized) | percent | `(1+geo_m)^12 - 1` |
| 4 | Standard Deviation (monthly) | percent | `std(ddof=1)` |
| 5 | Standard Deviation (annualized) | percent | monthly×√12 |
| 6 | Downside Deviation (monthly) | percent | `√(Σmin(0,r)²/n)` |
| 7 | Best Year | percent | 年次リターン最大 |
| 8 | Worst Year | percent | 年次リターン最小 |
| 9 | Maximum Drawdown | percent | 月次精度MDD(rolling用) |
| 10 | Benchmark Correlation | decimal | `corr(Rp, Rb)` |
| 11 | Beta | decimal | `cov(Rp,Rb)/var(Rb)` |
| 12 | Alpha (annualized) | percent | Jensen's alpha ×12 |
| 13 | R² | percent | `corr²` |
| 14 | Sharpe Ratio | decimal | `(excess_mean/excess_std)×√12` |
| 15 | Sortino Ratio | decimal | `(excess_mean/downside_dev)×√12` |
| 16 | Treynor Ratio (%) | decimal | `((Rp-Rf)×12)/beta ×100` |
| 17 | Calmar Ratio | decimal | `true_CAGR/|MDD|` |
| 18 | Analytical VaR (5%) | percent | `|mean - 1.645×std|` |
| 19 | Upside Capture Ratio (%) | decimal | 上昇市場期間の相対パフォーマンス |
| 20 | Downside Capture Ratio (%) | decimal | 下落市場期間の相対パフォーマンス |
| 21 | Up/Down Spread | decimal | upside - downside |
| 22 | Up/Down Ratio | decimal | upside / downside |
| 23 | Up/Down Vector | decimal | spread × ratio |
| 24 | Positive Period Ratio | decimal | **変換**: 文字列→比率(pos/total) |
| 25 | Gain/Loss Ratio | decimal | avg_gain / |avg_loss| |
| 26 | Skewness | decimal | `skew()` |
| 27 | Excess Kurtosis | decimal | `kurt()` |
| 28 | Max Run-up | percent | 任意安値→高値の最大上昇率 |
| 29 | Tail Contribution Ratio | percent | 上位10%リターン寄与率 |
| 30 | Left-tail Jumps | integer | -2σ超の下落回数 |
| 31 | New High Frequency | percent | 高値更新回数/期間 |
| 32 | Active Return | percent | `CAGR_p - CAGR_b` |
| 33 | Tracking Error | percent | `std(Rp-Rb)×√12` |

**注**: Information Ratio(=Active Return/Tracking Error)は#32,#33から算出可能。テンソルに含めるかは実装時判断。

### 除外メトリクス (8個) — テキスト/日付

MDD Date, Drawdown Length, Recovery Time, Underwater Period, Peak Date, Trough Date, Recovery Date, Positive Periods(文字列版)

## §4 Rolling計算の設計

### 方針

**MetricsCalculatorを直接使わない。** 理由:
1. `calculate_metrics()`はDB依存(Portfolio, DrawdownPeriod)
2. Rolling窓ごとにDB呼出は非効率(65PF×170窓=11,050回)
3. DrawdownPeriodは全期間用の事前計算データ — Rolling窓には不適

**代わりに**: `calculate_metrics()`の**純粋数学部分を抽出**し、DataFrameスライスに適用。
- 本番コードの公式を**1:1転写**
- 最終月(window=全期間)でのパリティ検証で正しさを保証

### 計算フロー

```
1. 全PFのMonthlyReturn + DTB3を1回ロード → メモリDict
2. PFごとに:
   a. monthly_df = 全期間DataFrame (portfolio_return, benchmark_return, cumulative, rf_return)
   b. for t in range(window, T):
        slice = monthly_df[t-window : t]
        metrics[t] = compute_34_metrics(slice)
   c. rolling_df = pd.DataFrame(metrics, index=dates[window:])
3. テンソル化: np.stack([rolling_dfs[pf] for pf in pf_ids])
```

### パフォーマンス見積

- 65PF × 170窓 × 34メトリクス
- 各メトリクス: NumPy 1行 = O(window) ≈ 60要素
- 推定: 65×170×0.005s ≈ 55秒 (目標60秒以内)
- 最適化余地: pandas.rolling()で一括計算(mean/std/skew/kurt)

### パリティ検証

Rolling窓=全期間(years=0)の計算結果を、既存`get_all_pf_metrics(years=0, source="calculator")`と突合。
- 数値メトリクス34個全てで一致(atol=1e-6)
- 1PFでも不一致なら実装不良

## §5 修行分解 — 高速化が先、機能追加は後

### 設計原理: 道具磨き = 高速化 → 機能追加

研究日誌Phase 15-16の教訓: research_engine.py高速化(R32-R34)が全研究cmdに複利で効いた。
- R32: pandas .loc→dict lookup → **179s→4.2s (43x)**
- R34: JSONキャッシュ(TTL=24h) → **7.9s→0.011s (707x)**

メトリクスエンジンも同じ順序: **まず既存エンジンを高速化し、その上にRolling+テンソルを構築する。**
遅いエンジンの上にRollingを載せても遅いまま。高速化が先。

### 修行R1: 速度計測 + ボトルネック分析

**偵察。** 1忍者。

AC:
1. 既存`get_all_pf_metrics(years=10, source="calculator")`の実行時間を計測（65PF全量）
2. PFごとの計算時間を記録し、遅いPF(上位5件)とその原因を特定
3. ボトルネック分析: profiling結果から以下を分類
   - DB I/O (MonthlyReturn取得、DrawdownPeriod取得、DTB3取得)
   - 計算コスト (numpy演算、年次リサンプル、MDD計算)
   - Python overhead (ループ、dict構築)
4. 高速化候補リスト: 改善幅(推定)× 実装難度 で優先順位付け
5. research_engine.pyのR32-R34パターンがそのまま適用可能か判定

binary_checks:
- bc1: 65PF計算の総時間を秒単位で報告 → PASS(計測完了)
- bc2: ボトルネック上位3件を特定+改善幅推定 → PASS(分析完了)

制約:
- 計測のみ。コード変更なし
- profiling: `time.perf_counter()`で区間計測。cProfileは不要（粗い粒度で十分）

### 修行R2: 高速化実装

**道具磨き本体。** 1忍者。R1結果に基づく。

AC:
1. R1で特定したボトルネック上位3件を解消
   - **候補A: バルクMonthlyReturnロード** — 65PF個別クエリ → 1クエリで全PF取得しメモリDict化
   - **候補B: DTB3キャッシュ** — 既存`load_dtb3_cache()`は実装済み。calculator初期化時に渡す仕組みの確認
   - **候補C: DrawdownPeriod一括取得** — 65PF分を1クエリでプリロード
   - **候補D: monthly_df_cache活用** — `calculate_metrics(monthly_df_cache=df)`でDB再取得スキップ
   - **候補E: JSONキャッシュ(TTL=24h)** — research_engineのR34パターン。計算結果をファイルキャッシュ
2. パリティ保持: 高速化前後で`verify_portfolio_metrics_parity()`がPASS
3. 高速化後の速度計測: R1と同一条件で再計測
4. 目標: **R1計測値の5倍以上高速化** (research_engineのR32=43x、R34=707xが参考)

binary_checks:
- bc1: 高速化後に`verify_portfolio_metrics_parity(years=10, atol=1e-12)` PASS → PASS/FAIL
- bc2: 速度がR1計測値の5倍以上改善 → PASS/FAIL

制約:
- metrics_calculator.pyの本番コードは変更しない。research engine側のみ変更
- パリティ最優先。速度のためにパリティを犠牲にしない
- research_engine.pyのR32-R34パターンを参考にするが、メトリクス固有の最適化も追加

### 修行R3: compute_34_metrics骨格 + Rolling計算

**機能追加。** 1忍者。R2完了後（高速化済みエンジン上に構築）。

AC:
1. `compute_34_metrics(monthly_slice: pd.DataFrame) -> dict[str, float]` 実装
   - metrics_calculator.py L255-1072の公式を1:1転写
   - DrawdownPeriod非依存（月次精度fallback使用）
   - Positive Periods: 文字列→ratio変換
2. `compute_rolling_metrics(pf_id, window_months=60) -> pd.DataFrame` 実装
   - 返り値: shape=(T-window, 34), columns=metric_names
3. `build_tensor(window_months=60) -> tuple[np.ndarray, list, list, list]` 実装
   - tensor.shape = (65, T_windows, 34)
4. 1PF(DM2)全期間で`get_all_pf_metrics`と34数値メトリクス一致確認(atol=1e-6)
5. 計算時間60秒以内

binary_checks:
- bc1: DM2全期間34メトリクスパリティ(atol=1e-6) → PASS/FAIL
- bc2: build_tensor()がshape=(65, >=150, 34) → PASS/FAIL
- bc3: 計算時間≤60秒 → PASS/FAIL

制約:
- 高速化済みエンジン(R2成果)上に構築。R2のバルクロード/キャッシュを活用
- compute_34_metricsは本番公式の1:1転写。独自アレンジ禁止

### 修行R4: パリティ検証強化 + CSV出力 + ランブック

**品質保証+運用基盤。** 1忍者。R3完了後。

AC:
1. `verify_rolling_parity(window_months) -> dict` — 全65PF最終窓 vs get_all_pf_metrics突合
2. CSV出力: `outputs/analysis/standard_pf_preprocessing/cmd_1730_rolling_tensor_60m.csv`
3. `run_and_save()`拡張: rolling結果+パリティをYAML追記
4. **ランブック作成**: `docs/research/metrics-engine-runbook.md` — §9参照

binary_checks:
- bc1: verify_rolling_parity()で不一致=0 → PASS/FAIL
- bc2: CSV出力が65PF × ≥150行 × 36列 → PASS/FAIL
- bc3: ランブックの全コマンドを順に実行して期待結果と一致 → PASS/FAIL

## §6 並列配備計画

### 依存関係図

```
R1(計測) ──→ R2(高速化: バルクロード+キャッシュ)
                          │
R3a(compute_34_metrics) ──┤  ← R1と並列可能！
                          │
                          ▼
              R3b(Rolling+テンソル) ──→ R4(パリティ+CSV+ランブック)
```

### 並列化ポイント

**★R1とR3aは並列可能。** compute_34_metrics(34公式の1:1転写)はDB非依存の純粋関数であり、高速化結果に依存しない。R1で計測している間に、別忍者がR3aの公式転写を進められる。

**R3aが先に完成すれば、R2の高速化方針が変わる:**
- compute_34_metricsがDB非依存 → DrawdownPeriod問題が自動解決(月次精度で統一)
- R2はバルクMonthlyReturnロード + JSONキャッシュに集中できる(DrawdownPeriod対策不要)

### 配備表 — 10分単位タスク

**原則**: 1タスク≤10分。パリティ検証を毎タスク末尾に含める。小さく確実に積む。

#### Wave 1（並列: 忍者A + 忍者B）

| ID | 忍者 | 内容 | 前提 | 目安 |
|----|------|------|------|------|
| **T1** | A | 全PF計算時間を1回計測。total秒+PFごと秒を記録 | なし | 5分 |
| **T2** | B | Return系4メトリクス(#0-3)転写。DM2で4値パリティ | なし | 10分 |
| **T3** | B | Risk系3(#4-6)+Year系2(#7-8)転写。DM2パリティ | T2 | 10分 |
| **T4** | B | MDD(#9)+Benchmark相対4(#10-13)転写。DM2パリティ | T3 | 10分 |
| **T5** | B | Risk-Adjusted4(#14-17)+VaR(#18)転写。DM2パリティ | T4 | 10分 |
| **T6** | B | Capture5(#19-23)+Stats4(#24-27)転写。DM2パリティ | T5 | 10分 |
| **T7** | B | Right-tail4(#28-31)+Active2(#32-33)転写。**全34メトリクスDM2パリティ** | T6 | 10分 |

Wave 1完了: 忍者Aは5分でT1完了→次Wave待ち or 他修行。忍者BはT2-T7で約60分。

#### Wave 2（T1+T7完了後。並列: 忍者A + 忍者C）

| ID | 忍者 | 内容 | 前提 | 目安 |
|----|------|------|------|------|
| **T8** | A | MonthlyReturn一括ロード実装。パリティ確認 | T1 | 10分 |
| **T9** | A | JSONキャッシュ(TTL=24h)実装。パリティ確認 | T8 | 10分 |
| **T10** | A | 高速化後の速度計測。T1との比較レポート | T9 | 5分 |
| **T11** | C | compute_rolling_metrics(DM2, window=60)実装。1PF動作確認 | T7 | 10分 |
| **T12** | C | build_tensor(65PF)実装。shape確認+最終窓パリティ | T11 | 10分 |

#### Wave 3（T12完了後）

| ID | 忍者 | 内容 | 前提 | 目安 |
|----|------|------|------|------|
| **T13** | D | verify_rolling_parity実装。65PF全パリティ | T12 | 10分 |
| **T14** | D | CSV出力+run_and_save拡張 | T13 | 10分 |
| **T15** | D | ランブック作成 `docs/research/metrics-engine-runbook.md` | T14 | 10分 |

**合計15タスク。並列活用で実効90-120分。**

## §7 判断基準 (将軍指定)

1. **本番42メトリクスとの一致率100%** — 数値34メトリクスで浮動小数誤差(atol=1e-6)以内
2. **65PF×170月の計算が60秒以内**
3. **ALM研究cmdからimport一発で3Dテンソルが返る**

## §8 リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| DrawdownPeriod非使用でMDD不一致 | パリティFAIL | 月次精度MDD vs 本番(日次精度DrawdownPeriod)で差異は許容。パリティ検証で差分を明示的に記録 |
| Best Year/Worst Yearの部分年処理差 | 小数点以下の不一致 | metrics_calculator.pyの`is_first_year_partial`ロジックを完全転写 |
| ベンチマークなしPF | Capture/Alpha等がNone | NaN埋め。テンソルのNaN処理はALM研究側で対応 |
| 60秒超過 | 性能基準FAIL | pandas.rolling()一括化 + NumPy vectorize で最適化 |

### MDD精度差の詳細

本番: DrawdownPeriodテーブル(日次精度、事前計算)→`get_mdd_from_drawdown_period()`
Rolling: 月次精度fallback `calc_mdd_monthly()` (cummax→drawdown→min)

月次精度MDDは日次精度MDDより浅い(月中の最大ドローダウンを見逃す)。差は通常1-3pp。
この差はRolling計算の構造的制約(窓ごとにDrawdownPeriodが存在しない)のため不可避。
パリティ検証ではMDDのみatol緩和(1e-2)するか、MDD関連メトリクス(#9,#17 Calmar)を除外判定。

## §9 ランブック — いつでも誰でも何回でも正しく使える

> **目的**: 前提知識のない第三者が秒で理解し、誰がいつ実行しても100%同じ結果を出せる。
> **対象**: `scripts/analysis/standard_pf_preprocessing/metrics_research_engine.py`
> **前提**: gs-runbook.mdと同じ構造。高速化手順も含む。

### §9.1 現状と実行方法

#### 基本実行(全PFメトリクス計算+パリティ検証)
```bash
cd /mnt/c/Python_app/DM-signal
python3 scripts/analysis/standard_pf_preprocessing/metrics_research_engine.py
```

出力:
- `outputs/analysis/standard_pf_preprocessing/cmd_1730_pf_metrics_10y.csv` — 65PF×42メトリクス(10年)
- `outputs/analysis/standard_pf_preprocessing/cmd_1730_pf_metrics_all.csv` — 65PF×42メトリクス(全期間)
- `outputs/analysis/standard_pf_preprocessing/cmd_1730_portfolio_metrics_parity.yaml` — パリティ検証結果

#### Python APIから使う(研究スクリプト内)
```python
from metrics_research_engine import get_all_pf_metrics, load_cached_pf_metrics

# 方法1: 本番calculatorで計算(遅いが正確)
df = get_all_pf_metrics(years=10, source="calculator")

# 方法2: portfolio_metricsテーブルから取得(高速)
df = load_cached_pf_metrics(years=10)

# 方法3: Rolling 3Dテンソル(R3完了後)
from metrics_research_engine import build_tensor, get_metric_names
tensor, pf_ids, metric_names, dates = build_tensor(window_months=60)
# tensor.shape = (65, ~170, 34)
```

### §9.2 パリティ検証手順

#### パリティ = 1つのルール
calculator計算結果とportfolio_metricsテーブル(事前計算)の**全メトリクス完全一致**(atol=1e-12)

#### 検証コマンド
```python
from metrics_research_engine import verify_portfolio_metrics_parity
result = verify_portfolio_metrics_parity(years=10, atol=1e-12)
print(f"PASS: {result['pass']}, mismatches: {result['mismatch_count']}")
```

#### パリティFAIL時の対処
1. `result['sample_mismatches']`で不一致メトリクス名+PF名を確認
2. 原因の99%は**portfolio_metricsテーブルが古い**(fullrecalculate実行後に更新されていない)
3. 本番側でfullrecalculate→portfolio_metrics再計算→再検証

### §9.3 高速化ガイド — ホットパス分析(軍師事前調査)

#### DB呼出しマップ(metrics_calculator.py内)

65PFループ内で毎回呼ばれるDB I/O:

| 行番号 | 呼出し | 内容 | 回数/PF |
|--------|--------|------|---------|
| **L155** | `self.db.execute(select(Portfolio).where(id==pf_id))` | Portfolio取得 | 1 |
| L165 | `load_monthly_as_df(self.db, pf_id)` | MonthlyReturn取得 | **スキップ済み**(monthly_df_cacheで回避。engine L148-149) |
| L184-185 | `select(EconomicIndicator).where(symbol=="DTB3")` | DTB3取得 | **スキップ済み**(dtb3_cache。engine L137-138) |
| **L476** | `self.db.query(DrawdownPeriod).filter(pf_id, rank==1)` | MDD統計取得 | 1 |
| **L578** | `self.db.query(DrawdownPeriod).filter(pf_id, rank==1)` | DD長さ統計取得 | 1 |

**実質の残存DB I/O: 65 × 3回 = 195回** (Portfolio + DrawdownPeriod×2)

research_engine側(engine L148-149)でmonthly_df_cacheとdtb3_cacheは既に対処済み。

#### 高速化の核心: Portfolio + DrawdownPeriodの一括プリロード

```python
# 現状(65回ループ内で毎回DB呼出し)
for pf_id, pf_name in portfolios:
    payload = calculator.calculate_metrics(pf_id, ...)
    # 内部でPortfolio SELECT + DrawdownPeriod SELECT×2 = 3 DB I/O

# 改善案: ループ前に1回で全PF分取得
all_portfolios = {p.id: p for p in db.execute(select(Portfolio)).scalars()}
all_drawdowns = {}  # {pf_id: worst_dd_row}
for dd in db.execute(select(DrawdownPeriod).where(DrawdownPeriod.rank == 1)).scalars():
    all_drawdowns[dd.portfolio_id] = dd
```

**問題**: MetricsCalculator.calculate_metrics()の内部でDB呼出しが埋まっている。外からプリロードデータを渡すインターフェースがない。

**解決策3つ(実装難度順)**:
1. **monthly_df_cacheパターンの拡張**: calculate_metricsにportfolio_cache/drawdown_cacheパラメータ追加 → **本番コード変更必要。禁則**
2. **research engine側でDB Sessionをモック**: 返り値を制御 → 複雑すぎ
3. **★推奨: DrawdownPeriod不使用路線**: calculate_metricsのコード内で月次精度MDD(L512-518)にfallbackするパスがある。DrawdownPeriodテーブルにデータがなければ月次精度に自動フォールバック。→ **DrawdownPeriodを空テーブルとして扱えば月次精度で計算する**。ただしパリティが月次精度vs日次精度でずれる

**★最も簡単な高速化**: DB Sessionの`query(DrawdownPeriod)`がヒットしないようにすれば、月次精度fallbackが走る。差異はMDD関連3メトリクス(Maximum Drawdown, Calmar Ratio, DD関連テキスト)のみ。数値メトリクス34個のうち2個(#9 MDD, #17 Calmar)だけが影響。パリティ検証でこの2個だけatol緩和(1e-2)すれば対応可能。

#### 現在のボトルネック構造(推定)

```
get_all_pf_metrics(source="calculator") — 65PF逐次計算
  └ for pf in portfolios:  (65回ループ)
      ├ load_monthly_as_df(db, pf_id)     → DB I/O (個別SELECT)
      ├ MetricsCalculator.calculate_metrics(pf_id, years, monthly_df_cache)
      │   ├ db.execute(select(Portfolio))  → DB I/O (Portfolio取得)
      │   ├ DTB3 merge + RF計算           → pandas演算
      │   ├ 34メトリクス計算              → numpy/pandas演算
      │   └ get_drawdown_stats_from_db()  → DB I/O (DrawdownPeriod取得)
      └ flatten_metrics_payload()          → dict変換
```

#### 高速化候補(research_engine R32-R34パターン適用)

| # | 対象 | 現状 | 改善案 | 期待効果 | 実績根拠 |
|---|------|------|--------|---------|---------|
| 1 | **MonthlyReturn DB I/O** | 65PF個別SELECT | **1クエリで全PF一括取得→Dict化** | DB往復64回削減 | research_engine: 1クエリ化で安定 |
| 2 | **monthly_df_cache活用** | `load_monthly_as_df`後に`calculate_metrics(monthly_df_cache=df)`渡し | **既に実装済み**(L148-149) — 確認のみ | DB再取得スキップ | metrics_research_engine L148 |
| 3 | **DTB3キャッシュ** | `load_dtb3_cache(db)`で1回取得→calculator初期化時に渡す | **既に実装済み**(L137-138) — 確認のみ | DB往復削減 | metrics_research_engine L137 |
| 4 | **DrawdownPeriod一括取得** | calculate_metrics内で`get_mdd_from_drawdown_period(pf_id)` = PFごとにSELECT | **65PF分を1クエリでプリロード→Dict** | DB往復64回削減 | kawarimi高速化パターン |
| 5 | **Portfolio一括取得** | calculate_metrics内で`select(Portfolio).where(id==pf_id)` = PFごとにSELECT | **65PF分を`_fetch_standard_portfolios`で既取得** → Portfolioオブジェクトもプリキャッシュ | DB往復64回削減 | — |
| 6 | **JSONキャッシュ(TTL=24h)** | なし。毎回フル計算 | **計算結果をJSONファイルにキャッシュ。24h以内は読取のみ** | 2回目以降: 計算ゼロ | research_engine R34: 707x |

#### 高速化の優先順位

```
最優先: #1(バルクMonthlyReturn) + #4(DrawdownPeriod一括) + #5(Portfolio一括)
  → DB I/O削減。65×3=195 DB往復 → 3往復。改善幅最大
次点: #6(JSONキャッシュ)
  → 2回目以降は瞬時。ALM研究で何度も呼ぶなら劇的効果
確認のみ: #2, #3
  → 既に実装済み。コード確認で十分
```

#### 高速化の実装手順(修行R2で使う)

```
1. R1で実行時間を計測(before)
2. #1実装: MonthlyReturn一括SELECT → pf_id→DataFrameのDict
3. パリティ検証: verify_portfolio_metrics_parity → PASS確認
4. #4実装: DrawdownPeriod一括SELECT → pf_id→worst_dd_rowのDict
   ⚠ calculate_metrics()はDB依存。外からプリロードしたデータを渡す方法を検討
   → monthly_df_cacheパターンと同じく、DrawdownPeriodキャッシュをcalculatorに渡す
   → MetricsCalculatorの改造が必要な場合は、research engine側でmonthly精度fallbackを使う
5. パリティ検証: → PASS確認
6. #5実装: Portfolioオブジェクトプリキャッシュ
7. パリティ検証: → PASS確認
8. #6実装: JSONキャッシュ(TTL=24h)
9. パリティ検証: → PASS確認
10. 実行時間を計測(after)
11. 速度比較レポート: before/after + 改善倍率
```

**絶対にやるな**: パリティ検証なしにcommit。複数最適化を同時実装(どこでパリティが壊れたか特定不能)。MetricsCalculatorの本番コードを変更。

### §9.4 Rolling追加後の実行方法(R3完了後)

```bash
# 全PF Rolling 3Dテンソル計算
python3 -c "
from metrics_research_engine import build_tensor, get_metric_names
tensor, pf_ids, metrics, dates = build_tensor(window_months=60)
print(f'shape: {tensor.shape}')
print(f'PFs: {len(pf_ids)}, months: {len(dates)}, metrics: {len(metrics)}')
"

# Rolling パリティ検証
python3 -c "
from metrics_research_engine import verify_rolling_parity
result = verify_rolling_parity(window_months=60)
print(f'PASS: {result[\"pass\"]}, mismatches: {result[\"mismatch_count\"]}')
"
```

### §9.5 入出力パス

| 種類 | パス |
|------|------|
| **エンジン本体** | `scripts/analysis/standard_pf_preprocessing/metrics_research_engine.py` |
| **本番calculator** | `backend/app/services/metrics_calculator.py` |
| **DB接続** | `backend/.env` の DATABASE_URL (READ ONLY) |
| **出力CSV(10年)** | `outputs/analysis/standard_pf_preprocessing/cmd_1730_pf_metrics_10y.csv` |
| **出力CSV(全期間)** | `outputs/analysis/standard_pf_preprocessing/cmd_1730_pf_metrics_all.csv` |
| **パリティYAML** | `outputs/analysis/standard_pf_preprocessing/cmd_1730_portfolio_metrics_parity.yaml` |
| **Rollingテンソル** | `outputs/analysis/standard_pf_preprocessing/cmd_1730_rolling_tensor_60m.csv` (R4で追加) |
| **JSONキャッシュ** | `outputs/analysis/standard_pf_preprocessing/_metrics_cache_*.json` (R2で追加) |

### §9.6 修行ナビゲーションシート(軍師事前分析)

→ `docs/research/gunshi-metrics-engine-training-nav.md`

忍者の修行品質向上のための詳細参照資料:
- **A. R2用**: MonthlyReturn一括ロードSQL設計 + DrawdownPeriod対策2案 + JSONキャッシュパターン(R34準拠)
- **B. R3用**: compute_34_metricsの34公式ナビゲーション(行番号付き、rolling注意点付き)
- **C. R1用**: 計測スクリプト雛形

**軍師推奨(A2)**: DrawdownPeriod問題はcompute_34_metrics(DB非依存)を早期作成で解決。R2とR3のスコープ統合を家老に提案済み。

### §9.7 注意事項

1. **WSL2環境**: python3(Linux)を使え。backend/.envのDATABASE_URLがPostgreSQL接続先
2. **READ ONLY**: 全操作はSELECTのみ。本番DBへのINSERT/UPDATE/DELETE禁止
3. **本番calculator変更禁止**: `backend/app/services/metrics_calculator.py`は読取専用。変更はresearch engine側のみ
4. **パリティ最優先**: 速度のためにパリティを犠牲にしない。改善→パリティ→commit→次の改善
5. **JSONキャッシュのTTL**: fullrecalculate後はキャッシュを手動削除(`rm _metrics_cache_*.json`)。古いキャッシュは本番と乖離する

---

## §10 ALM OOS検証設計

<!-- author: gunshi | created: 2026-04-04T02:50:00+09:00 -->
<!-- 依頼: 将軍 msg_20260404_024659。cmd_1735結果(tracking_error CAGR52.7%)の頑健性検証 -->

### §10.1 何を検証するか — overfit構造の特定

cmd_1735は**34メトリクス×24 lookback**を試し、best ALM=tracking_errorを選んだ。overfit riskは2層ある:

| 層 | 選択対象 | 個数 | overfitリスク |
|----|---------|------|-------------|
| **L1: 目的関数選択** | 34メトリクスのどれを目的関数にするか | 34 | **高（主要リスク）** |
| L2: lookback動的選択 | 毎月どのlookbackを使うか | 24/月 | 低（rolling metricで自動決定、パラメータなし） |

L2は毎月rolling metricで自動決定されるため、パラメータチューニングではない。
**主要リスクはL1: 34通り試して最良を選んだこと。** PBOはこの層を検証する。

### §10.2 Stage 1 — IS/OOS Simple Split

**入力**: cmd_1735の58戦略（24固定+34 ALM）のリターン系列

**方法**:
1. cmd_1735スクリプト(`cmd_1735_alm_research.py`)を再利用し、IS期間/OOS期間それぞれで58戦略のリターンを再計算
2. **重要**: ALMのrolling metricは各期間の開始60ヶ月で構築。OOS期間の最初の60ヶ月はrolling構築に消費される
3. IS/OOS分割点: 全期間(~172月)の中間点。ただしrolling窓60ヶ月+最大lookback24ヶ月=84ヶ月のwarm-upが必要

**手順**:
```
Step 1: 全期間月次リターン(return_wide)を2分割
  IS = months[0 : N//2]   (前半)
  OOS = months[N//2 : N]  (後半)

Step 2: IS期間でALMを構築
  - 6 fixed lookbackのsimulate_selection → ISリターン
  - compute_rolling_from_returns(window=60) on ISリターン
  - 34 ALM構築 → IS期間のALM CAGR/Sharpe
  - IS_best_metric = argmax(ALM CAGR on IS) e.g. "tracking_error"
  - IS_best_fixed = argmax(fixed CAGR on IS)

Step 3: OOS期間で検証（IS_best_metricを固定使用）
  - 同一パイプラインをOOS期間で実行
  - OOS_ALM_performance = IS_best_metricのALM on OOS
  - OOS_fixed_performance = IS_best_fixedの固定 on OOS

Step 4: 劣化率判定
  degradation = (IS_CAGR - OOS_CAGR) / IS_CAGR
  |deg| > 0.30 → OVERFIT
  |deg| > 0.15 → SUSPECT
  else → ROBUST
```

**Q: 目的関数の選択もISで行い、OOSでは固定するか？**
→ **YES。ISでbest metricを選び、OOSではそのmetricを固定して実行。**
OOSで再選択したら別のin-sample testになり検証にならない。
本番運用のシミュレーション: ISで目的関数を決め、以降はその目的関数で運用する。

### §10.3 Stage 2 — PBO (CSCV)

**組合せ変数**: 34メトリクス（=34個の「戦略」）

**方法**: Bailey & López de Prado (2014) CSCV
```
S = 8 equal time blocks (~21ヶ月/block)
C(8,4) = 70 IS/OOS combinations

For each combination:
  IS = 4 blocks, OOS = 4 blocks
  
  For each of 34 metrics:
    ALM on IS blocks → IS_Sharpe[metric]
    ALM on OOS blocks → OOS_Sharpe[metric]
  
  IS_best = argmax(IS_Sharpe)
  OOS_rank = rank of IS_best in OOS_Sharpe
  overfit_flag = (OOS_rank > median_rank)

PBO = count(overfit_flag) / 70
```

**判定基準** (oos_verification_study.pyと同一):
- PBO > 0.50 → **OVERFIT**: 34メトリクスから最良を選ぶプロセス自体が過適合
- PBO < 0.30 → **ROBUST**: tracking_errorの優位は統計的に頑健
- 0.30-0.50 → **SUSPECT**

**ブロック内ALM構築の注意点**:
- 各ブロック(~21ヶ月)は短い。Rolling 60ヶ月窓は構築できない
- **解決策**: 全期間でrolling metricsを事前計算し、各ブロックの月だけを抽出してISまたはOOSに割当。rolling計算自体は全期間データを使う（look-ahead biasにならない: rolling[t]はt-1以前のデータのみ使用）
- Sharpe計算: ブロック内のALM月次リターンからSharpeを算出

### §10.4 実装方針 — 既存コード流用

| 要素 | 既存(oos_verification_study.py) | ALM OOS(新規) |
|------|------|------|
| CSCV block分割 | ✓ L870-876 | **流用** |
| C(8,4)組合せ生成 | ✓ L827 | **流用** |
| overfit count/PBO計算 | ✓ L896-929 | **流用** |
| classify_degradation | ✓ L547-554 | **流用** |
| IS/OOS split | ✓ L593-800 | 構造流用、中身はALMパイプライン |
| simulate_signals | ✓（PFレベル信号生成） | **不使用**（simulate_selection使用） |
| monthly_returns計算 | ✓（PFレベル） | **不使用**（simulate_selection出力） |
| ALMパイプライン | なし | **新規**: cmd_1735スクリプトからALM構築ロジック抽出 |

**推奨**: 新スクリプト `cmd_XXXX_alm_oos_verification.py` を作成。
- cmd_1735_alm_research.pyからALM構築ロジックをimport or コピー
- oos_verification_study.pyからCSCV/PBO判定ロジックを抽出してユーティリティ化 or インライン
- metrics_research_engineのsimulate_selection/compute_rolling_from_returns/compute_metrics_from_returnsを使用

### §10.5 出力仕様

```yaml
# outputs/analysis/alm_research/cmd_XXXX_alm_oos_results.yaml
stage1:
  split_point: "2018-06"  # IS/OOS境界
  is_months: 85
  oos_months: 87
  is_best_alm_metric: "tracking_error"
  is_best_alm_cagr: 0.XX
  oos_best_alm_cagr: 0.XX
  degradation: 0.XX
  judgement: "ROBUST/SUSPECT/OVERFIT"
  is_best_fixed_lb: "23m"
  oos_fixed_cagr: 0.XX
  alm_vs_fixed_oos: 0.XX  # OOSでもALMが固定に勝つか

stage2_pbo:
  n_metrics: 34
  cscv_s: 8
  n_combinations: 70
  pbo: 0.XX
  judgement: "ROBUST/SUSPECT/OVERFIT"
  is_best_distribution:  # 70回のIS-bestで各metricが何回選ばれたか
    tracking_error: 45
    sharpe_ratio: 12
    ...

# + CSV: 70組合せの詳細(IS-best metric, OOS rank, overfit flag)
```

### §10.6 計算量推定

- Stage 1: 58戦略×2期間=116回のsimulate_selection+compute_metrics。~5分
- Stage 2: 34 ALM×70組合せ=2380回のSharpe計算（ブロック内リターンから直接、軽量）。~2分
- **合計: ~10分。忍者1名で十分**

### §10.7 CSCV拡張版 — Stage 0/1もCSCV化

<!-- author: gunshi | created: 2026-04-04T18:25:00+09:00 -->
<!-- 依頼: 将軍 msg_20260404_181830。殿指摘: 前半/後半1分割では不十分 -->

#### 殿指摘と設計方針

cmd_1739のStage 0/1はIS/OOS 1分割(前半/後半)のみ。分割点の選び方で結果が変わる（cmd_1737 vs cmd_1739でStage 0結果が逆転した実例あり）。CSCVの70組合せに拡張すれば分割点依存を排除できる。

#### Q1: Stage 0 CSCV計算量

**Stage 0の検証対象**: 1700 ALM戦略全体から1つを選ぶ行為のoverfit。

**計算方法**:
1. **事前計算(1回)**: 全期間で1700 ALMリターン系列を構築。cmd_1736パイプラインで~3秒(R11済み)
2. **CSCV**: S=8ブロック(各~27ヶ月)、C(8,4)=70組合せ。各組合せで:
   - ISブロックの月を抽出 → 1700戦略のIS Sharpe計算(mean/std)
   - IS-bestを選択
   - OOSブロックの月を抽出 → IS-bestのOOS Sharpeがmedian以下か判定
3. **計算量**: 70組合せ × 1700戦略 × (IS Sharpe + OOS Sharpe) = **238,000回のSharpe計算**

各Sharpe計算: ~27ヶ月のmean/std = numpy操作(マイクロ秒)。
**238,000 × 0.001秒 ≈ 4分**。事前計算3秒含め**合計~4分**。

**重要**: ALMリターン系列は全期間で事前構築（rolling metricsは時系列連続データが必要）。CSCVブロックは事前構築済みリターンから月を抽出するだけ。rolling計算をブロックごとに再実行する必要はない。

#### Q2: Stage 1 CSCV計算量

**Stage 1の検証対象**: 50組合せ(top_n×window)それぞれで、34メトリクスからbest metricを選ぶ行為のoverfit。

**計算量**: 50組合せ × 70回 × 34メトリクス × (IS + OOS) = **238,000回のSharpe計算**。Stage 0と同規模。

**Stage 2との関係**: Stage 2は**全く同じ計算構造**(50×70×34)。違いは判定方法:
- Stage 2: PBO = IS-bestがOOS median以下の確率
- Stage 1 CSCV版: 70回の劣化率の分布(mean/median/std)

**計算を共有可能**: Stage 1 CSCVとStage 2を同時実行し、同じIS/OOSブロック内Sharpeから両方の判定を出す。追加計算コスト≈ゼロ。

#### Q3: Stage 0 CSCVの意義 — 冗長ではない

**Stage 2のPBO**: 各(top_n, window)固定で、**34メトリクス間**の選択overfit。「この(top_n, window)で、どのmetricを使うか」
**Stage 0のPBO**: **1700戦略全体**から1つを選ぶoverfit。「どの(top_n, window, metric)を使うか」

Stage 0は3軸同時選択のoverfit。Stage 2は1軸(metric)のoverfit。**スコープが異なるため冗長ではない。**

ただし注意: 1700パラメータは多い。PBOは「IS-bestがOOS median以下」で判定するが、1700戦略のmedianは「平凡な戦略」になりやすく、IS-bestがmedian以下になる確率(PBO)は自然に0.5に近づく。**検出力が低くなる可能性がある。**

対策: 1700全体ではなく、**Stage 2でROBUSTと判定された組合せの代表戦略のみ**(例: 9 ROBUST組合せの各best metric = 9戦略)をStage 0の対象にする。9戦略間の選択overfitなら検出力が保たれる。

#### Q4: 追加の道具磨き

**不要。** R11完了の現行道具で全計算が高速に実行可能。

追加計算の大半は「ブロック内Sharpe/CAGR」(numpy mean/std)であり、既存のbatch_rolling_metricsとは別レイヤー(もっと軽い)。

唯一の推奨: **1700 ALMリターン系列のキャッシュ**。Foundation Cacheに追加すれば再計算3秒を省ける。だが3秒なので優先度は低い。

#### Q5: 見込み計算時間

**事前計算(1回)**: 1700 ALMリターン系列構築 ~3秒

| 構成 | Stage 0 CSCV | Stage 1+2 CSCV | 合計 |
|------|-------------|----------------|------|
| **忍者1名** | ~4分 | ~4分 | **~8分** |
| **3名並列**(Stage0/1+2/予備) | ~4分 | ~4分 | **~4分** |
| **6名並列** | 効果薄(各Stage自体が4分) | — | **~4分** |

3名並列と6名並列の差がない理由: Stage 0とStage 1+2が独立に実行可能だが、各Stage内の70組合せは逐次(CSCVの組合せループ)。Stage内部の並列化はProcessPoolExecutorで可能だがオーバーヘッドに見合わない(4分→2分)。

**1名で8分、3名で4分。十分高速。**

#### CSCV拡張版の出力仕様

```yaml
stage0_cscv:
  n_strategies: 1700   # or 9(ROBUST代表のみ)
  cscv_s: 8
  n_combinations: 70
  pbo: 0.XX
  judgement: "ROBUST/SUSPECT/OVERFIT"
  is_best_distribution:
    alm_top4_win36m__maximum_drawdown: 25
    alm_top4_win36m__worst_year: 20
    ...

stage1_cscv:   # Stage 2と計算共有。判定方法のみ異なる
  n_combinations: 50
  per_combo:
    - top_n: 1
      rolling_window: 12
      mean_degradation: 0.XX   # 70回の劣化率平均
      std_degradation: 0.XX
      pbo: 0.XX                # 同一データからPBOも算出
      judgement: "ROBUST/SUSPECT/OVERFIT"
    - ...
```
