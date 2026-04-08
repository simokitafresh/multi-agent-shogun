# メトリクスエンジン修行ナビゲーションシート
<!-- author: gunshi | 2026-04-04 | 忍者の修行品質向上のための事前分析 -->

> **目的**: 修行R1-R4で忍者が迷わず最短で高品質な成果を出すための参照資料。
> **索引**: `context/gunshi-metrics-engine-design.md` §5(修行分解) + §9(ランブック)

---

## A. 修行R2用: 一括ロードSQL設計

### A1. MonthlyReturn一括ロード

現状(engine L148): `load_monthly_as_df(db, portfolio_id)` → PFごとに1 SELECT。65PF=65クエリ。

改善: 全PFを1クエリで取得→pf_id別にDataFrameを分割。

```python
# 一括ロードSQL
from sqlalchemy import select
from app.db.models import MonthlyReturn

all_rows = db.execute(
    select(MonthlyReturn)
    .where(MonthlyReturn.portfolio_id.in_([pf_id for pf_id, _ in portfolios]))
    .order_by(MonthlyReturn.portfolio_id, MonthlyReturn.year_month)
).scalars().all()

# pf_id別にグループ化
from collections import defaultdict
monthly_by_pf: dict[str, list] = defaultdict(list)
for row in all_rows:
    monthly_by_pf[row.portfolio_id].append(row)
```

load_monthly_as_dfはmonthly_return_cacheパラメータを持つ(L190):
```python
# 既存インターフェースをそのまま活用
df = load_monthly_as_df(db, pf_id, monthly_return_cache=monthly_by_pf[pf_id])
```

**効果**: 65 SELECT → 1 SELECT。DB往復64回削減。

### A2. DrawdownPeriod一括ロード

現状: calculate_metrics内部のL476,L578で`db.query(DrawdownPeriod).filter(pf_id, rank==1)`。65PF×2回=130クエリ。

**問題**: calculate_metricsの内部に埋まっており、外からプリロードを渡せない。

**解決策(2つ)**:

**案1(推奨): MonthlyReturn精度のMDDで全計算を統一**
- calculate_metrics内部にはfallbackパスがある(L512-518):
  ```python
  # DrawdownPeriodが空なら月次精度fallback
  if p_mdd is None:  # ← DrawdownPeriodテーブルに該当PFがない場合
      p_mdd, _ = calc_mdd_monthly(monthly_df["portfolio_cumulative"])
  ```
- Rolling計算(R3)では元々月次精度を使う。R2でも同じ精度に統一すれば、全メトリクスの計算がDB非依存になる
- **実装**: DrawdownPeriodクエリをスキップする新パラメータ追加... は本番変更禁止
- **代替**: research engine側で空のDrawdownPeriodテーブルのように振る舞わせる（SQLAlchemy Sessionのquery結果を制御）→ 複雑
- **★最もシンプル**: compute_34_metrics(R3で作る)をR2の段階で先に作り、calculate_metricsの代わりに使う。つまり**R2とR3を統合し、最初からDB非依存の計算関数を使う**

**案2: DrawdownPeriod一括プリロード + monkey-patch**
```python
# 全PF分のworst drawdownを1クエリで取得
from app.db.models import DrawdownPeriod
all_dd = db.execute(
    select(DrawdownPeriod).where(DrawdownPeriod.rank == 1)
).scalars().all()
dd_by_pf = {dd.portfolio_id: dd for dd in all_dd}
# → monkey-patchでcalculate_metricsに渡す方法が必要（複雑）
```

**軍師推奨**: 案1方向。R2とR3のスコープを調整し、compute_34_metrics(DB非依存)を早期に作成。高速化と機能追加を同時に解決。家老判断を仰ぐ。

### A3. JSONキャッシュパターン(research_engine R34準拠)

research_engine.pyのL60-61, L147-176のパターンをそのまま適用:

```python
import json, time
from pathlib import Path

_METRICS_CACHE_DIR = Path(__file__).parent
_METRICS_CACHE_TTL = 86400  # 24 hours

def _cache_path(years: int) -> Path:
    return _METRICS_CACHE_DIR / f"_metrics_cache_{years}y.json"

def get_all_pf_metrics_cached(years: int = 10) -> pd.DataFrame:
    """JSONキャッシュ付き。TTL=24h。fullrecalculate後は手動削除。"""
    cache = _cache_path(years)
    if cache.exists():
        mtime = cache.stat().st_mtime
        if time.time() - mtime < _METRICS_CACHE_TTL:
            return pd.read_json(cache)  # or json.load → DataFrame構築

    # キャッシュなし or 期限切れ → フル計算
    df = get_all_pf_metrics(years=years, source="calculator")

    # キャッシュ保存
    df.to_json(cache)
    return df
```

**注意**: DataFrameのJSON round-tripでfloat精度が落ちる場合あり。`orient="records"` + `double_precision=15`推奨。
**代替**: pickle/parquetの方がround-trip安全。ただしpickleはバージョン依存。parquetはpyarrow依存。JSON+高精度が最もポータブル。

---

## B. 修行R3用: compute_34_metrics公式ナビゲーション

metrics_calculator.py L255-1072から34数値メトリクスの計算公式を抽出。
忍者がこのシートを見ながら1:1転写すれば、漏れなく全メトリクスを実装できる。

### B1. 入力DataFrame要件

compute_34_metricsに渡すDataFrameのカラム:

| カラム | 型 | 元テーブル | 説明 |
|--------|-----|-----------|------|
| portfolio_return | float | MonthlyReturn.monthly_return | 月次リターン(close) |
| portfolio_return_open | float | MonthlyReturn.monthly_return_open | 月次リターン(open) |
| portfolio_cumulative | float | MonthlyReturn.cumulative_return | 累積リターン(close) |
| portfolio_cumulative_open | float | MonthlyReturn.cumulative_return_open | 累積リターン(open) |
| benchmark_return | float | MonthlyReturn.benchmark_return | ベンチマーク月次リターン |
| benchmark_return_open | float | MonthlyReturn.benchmark_return_open | ベンチマーク月次リターン(open) |
| benchmark_cumulative | float | MonthlyReturn.benchmark_cumulative | ベンチマーク累積 |
| benchmark_cumulative_open | float | MonthlyReturn.benchmark_cumulative_open | ベンチマーク累積(open) |
| rf_return | float | EconomicIndicator(DTB3)から算出 | 月次リスクフリーリターン |

index: DatetimeIndex(月末日)

**rf_returnの算出** (metrics_calculator.py L199-206):
```python
rf_daily = (1 + rf_annual / 100.0) ** (1/252) - 1.0
rf_return = rf_daily.resample('ME').apply(lambda x: (1 + x).prod() - 1)
```

### B2. 34メトリクス公式リスト(metrics_calculator.py行番号付き)

**★ = rolling計算時に注意が必要なメトリクス**

#### Return系 (L312-361)
| # | 名前 | 公式 | 行 |
|---|------|------|-----|
| 0 | Arith Mean (m) | `mean(portfolio_return)` | L321 |
| 1 | Arith Mean (a) | `#0 × 12` | L331 |
| 2 | Geo Mean (m) | `(Π(1+r))^(1/n) - 1` | L340-342 |
| 3 | Geo Mean (a) | `(1 + #2)^12 - 1` | L355 |

#### Risk系 (L363-394)
| # | 名前 | 公式 | 行 |
|---|------|------|-----|
| 4 | StdDev (m) | `std(ddof=1)` | L366 |
| 5 | StdDev (a) | `#4 × √12` | L375 |
| 6 | Downside Dev (m) | `√(Σmin(0,r)²/n)` | L383-386 |

#### ★ Year系 (L396-467) — rolling時の注意点
| # | 名前 | 公式 | 行 | 注意 |
|---|------|------|----|------|
| 7 | Best Year | `yearly_annual.max()` | L440 | **年次リサンプル必要。partial year除外(L401-402)**。60M窓では5年分≈5データ点 |
| 8 | Worst Year | `yearly_annual.min()` | L441 | 同上 |

#### ★ MDD系 (L469-539) — rolling時はmonthly fallback
| # | 名前 | 公式 | 行 | 注意 |
|---|------|------|----|------|
| 9 | Max DD | `cummax→drawdown→min` | L512-518 | **DrawdownPeriod非使用。月次精度のcalc_mdd_monthly()を使え** |

#### Benchmark相対系 (L725-769)
| # | 名前 | 公式 | 行 |
|---|------|------|-----|
| 10 | Correlation | `corr(Rp, Rb)` | L733 |
| 11 | Beta | `cov(Rp,Rb)/var(Rb, ddof=1)` | L737-739 |
| 12 | Alpha (a) | `((mean_rp-mean_rf) - beta*(mean_rm-mean_rf)) × 12` | L751-757 |
| 13 | R² | `corr²` | L762 |

#### Risk-Adjusted系 (L771-867)
| # | 名前 | 公式 | 行 |
|---|------|------|-----|
| 14 | Sharpe | `(excess.mean()/excess.std(ddof=1)) × √12` | L775-779 |
| 15 | Sortino | `(excess.mean()/√(min(0,excess)².mean())) × √12` | L805-810 |
| 16 | Treynor(%) | `((mean_rp-mean_rf)×12)/beta × 100` | L824-836 |
| 17 | Calmar | `true_CAGR / |MDD|` | L864 |

#### VaR (L869-884)
| # | 名前 | 公式 | 行 |
|---|------|------|-----|
| 18 | VaR(5%) | `|mean - 1.645 × std|` | L875 |

#### Capture系 (L886-927) — benchmarkなしPFではNaN
| # | 名前 | 公式 | 行 |
|---|------|------|-----|
| 19 | Upside Capture(%) | `(p_ann/b_ann)×100` (up_market期間) | L892-911 |
| 20 | Downside Capture(%) | 同上(down_market期間) | L912 |
| 21 | Up/Down Spread | `#19 - #20` | L915 |
| 22 | Up/Down Ratio | `#19 / #20` | L916 |
| 23 | Up/Down Vector | `#21 × #22` | L917 |

#### Other Stats系 (L929-968)
| # | 名前 | 公式 | 行 |
|---|------|------|-----|
| 24 | Pos Period Ratio | `(Rp>0).sum() / len(Rp)` | L931-933 (**文字列→ratio変換**) |
| 25 | Gain/Loss Ratio | `mean(gains) / |mean(losses)|` | L947-954 |
| 26 | Skewness | `skew()` | L962 |
| 27 | Excess Kurtosis | `kurt()` | L966 |

#### Right-tail系 (L970-993) — MetricsCalculator static methods使用
| # | 名前 | 公式 | 行 |
|---|------|------|-----|
| 28 | Max Run-up | `max((v/min_so_far)-1)` (cumulative上) | L34-59 |
| 29 | Tail Contribution | `sum(r > P90) / sum(r > 0)` | L63-91 |
| 30 | Left-tail Jumps | `sum(r < -2σ)` | L94-119 |
| 31 | New High Freq | `new_highs / (n-1)` (cumulative上) | L122-145 |

#### Active系 (L995-1027) — benchmarkなしPFではNaN
| # | 名前 | 公式 | 行 |
|---|------|------|-----|
| 32 | Active Return | `CAGR_p - CAGR_b` (True CAGR, L847-850) | L1003 |
| 33 | Tracking Error | `std(Rp-Rb, ddof=1) × √12` | L1009-1010 |

### B3. True CAGR計算(複数メトリクスで参照)

```python
# L840-850
period_years = len(monthly_df) / 12.0
p_total = (1 + monthly_df["portfolio_return"]).prod()
p_true_cagr = p_total ** (1 / period_years) - 1
```

#17 Calmar, #32 Active Return で使用。

### B4. has_benchmark判定

```python
has_benchmark = "benchmark_cumulative" in df.columns and df["benchmark_cumulative"].notna().any()
```

benchmarkなしPFでは #10-13, #16, #19-23, #32-33 がNaN。テンソルではnp.nanで埋める。

---

## C. 修行R1用: 計測スクリプト雛形

```python
#!/usr/bin/env python3
"""metrics_research_engine 速度計測 (修行R1)"""
import time
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "backend"))

from metrics_research_engine import get_all_pf_metrics

# === 全体計測 ===
t0 = time.perf_counter()
df = get_all_pf_metrics(years=10, source="calculator")
t1 = time.perf_counter()
print(f"total: {t1-t0:.1f}s, PFs: {len(df)}, cols: {len(df.columns)}")

# === PFごとの計測 ===
# get_all_pf_metricsの内部ループにtime.perf_counterを仕込む
# → metrics_research_engine.pyを一時修正し、PFごとの計算時間を記録
```
