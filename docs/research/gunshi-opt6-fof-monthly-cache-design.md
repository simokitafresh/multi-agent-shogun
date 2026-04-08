# OPT-6: FoF monthly_returns_gen キャッシュ共有設計書 (軍師作成)

## 概要

FoF recalcのmonthly_returns_gen (733.96s, FoF全体の55.9%)のボトルネック。
原因: `_generate_monthly_returns()`が59 FoF各呼出しで独立にDB問い合わせ。
**既にrecalculate_fof.pyに構築済みのsignal_cacheが渡されていない。**

shared_price_cache (116最適化)と同じパターンで修正可能。低リスク。

## 推定効果

- **FoF monthly_returns_gen: 733.96s → ~339s (53.7%削減)**
- 全体recalc: 3324.7s → ~2930s (11.9%追加削減)
- OPT-3/4/5と合算: 3324.7s → ~2000s (39.8%追加削減)

## ボトルネック内訳 (59 FoF, ~12.4s/FoF)

| ボトルネック | 箇所 | 推定コスト | 原因 |
|---|---|---|---|
| Signal per-PFクエリ | monthly_returns.py L63-65 | ~150s | 59 FoF × 個別Signal全量query |
| preload_fof_signals_recursive() | monthly_returns.py L152 | ~200s | signal_cache非共有 → コンポーネントPF毎回再ロード |
| month_end_biz_cache per-PFクエリ | monthly_returns.py L124-135 | ~30s | 同一GROUP BY × 59回 |
| TickerMonthlyReturn per-PFクエリ | monthly_returns.py L160-162 | ~10s | 全PF同一benchmark_ticker |
| Portfolio per-PFクエリ | monthly_returns.py L51 | ~5s | 呼出し元に既にオブジェクトあり |
| expand_portfolio_to_tickers × 月 | monthly_returns.py L231-236 | ~170s | signal_cache共有で改善 |
| DB UPSERT + commit | monthly_returns.py L348-371 | ~170s | 変更なし（FoF-of-FoF依存制約） |

## 変更箇所

### 1. _generate_monthly_returns() シグネチャ拡張 (monthly_returns.py L21-26)

```python
def _generate_monthly_returns(
    db: Session,
    portfolio_id: str,
    price_cache: Optional[PriceCache] = None,
    benchmark_cum_cache: Optional[dict] = None,
    # OPT-6: 以下追加
    signal_cache: Optional[Dict[str, Dict[date, Any]]] = None,
    portfolio_cache: Optional[Dict[str, Portfolio]] = None,
    month_end_biz_cache: Optional[Dict[Tuple[int, int], date]] = None,
    benchmark_ticker_returns: Optional[Dict[str, Tuple[float, float]]] = None,
) -> None:
```

### 2. Signal取得の条件分岐 (monthly_returns.py L51-68)

```python
# OPT-6: portfolio_cacheから取得
if portfolio_cache and portfolio_id in portfolio_cache:
    portfolio = portfolio_cache[portfolio_id]
else:
    portfolio = db.query(Portfolio).filter(Portfolio.id == portfolio_id).first()
if not portfolio:
    return

# ...

# OPT-6: signal_cacheから取得（DB queryスキップ）
if signal_cache and portfolio_id in signal_cache:
    # signal_cacheからpf_signals相当のデータを構築
    sig_dict = signal_cache[portfolio_id]
    pf_signal_dates = sorted(sig_dict.keys())
    dates_raw = [(d,) for d in pf_signal_dates]
    # signal_map構築もsignal_cacheから
    if not is_fof:
        signal_map = {}
        for d, v in sig_dict.items():
            if isinstance(v, dict):
                signal_map[d] = v.get("holding_signal", "")
            else:
                signal_map[d] = v or ""
        signal_dates = sorted(signal_map.keys())
    min_date = pf_signal_dates[0] if pf_signal_dates else date.today()
else:
    # 従来動作: DBクエリ
    pf_signals = db.query(Signal).filter(
        Signal.portfolio_id == portfolio_id
    ).order_by(Signal.date).all()
    if not pf_signals:
        return
    dates_raw = [(s.date,) for s in pf_signals]
    # ...（既存コード）
```

### 3. signal_cache/portfolio_cache構築スキップ (monthly_returns.py L140-152)

```python
# OPT-6: 外部からsignal_cacheが渡された場合はスキップ
if signal_cache is None:
    # 従来動作: 内部構築
    signal_cache_local: Dict[str, Dict[date, Any]] = {}
    portfolio_cache_local: Dict[str, Portfolio] = {portfolio_id: portfolio}
    signal_cache_local[portfolio_id] = {
        s.date: build_signal_cache_value(s) for s in pf_signals
    }
    if is_fof:
        preload_fof_signals_recursive(db, portfolio, signal_cache_local, portfolio_cache_local)
    signal_cache = signal_cache_local
    portfolio_cache = portfolio_cache_local
else:
    # OPT-6: 外部キャッシュ使用。preload_fof_signals_recursiveスキップ
    if portfolio_cache is None:
        portfolio_cache = {portfolio_id: portfolio}
```

### 4. month_end_biz_cache共有 (monthly_returns.py L121-135)

```python
# OPT-6: 外部から渡された場合はスキップ
if month_end_biz_cache is None:
    month_end_biz_cache = {}
    month_ends_query = db.query(...)  # 既存コード
    for row in month_ends_query:
        month_end_biz_cache[(int(row.year), int(row.month))] = row.last_biz_day
```

### 5. benchmark_ticker_returns共有 (monthly_returns.py L158-169)

```python
# OPT-6: 外部から渡された場合はスキップ
if benchmark_ticker_returns is None:
    benchmark_ticker_returns = {}
    if benchmark_ticker:
        ticker_returns = db.query(TickerMonthlyReturn).filter(...)  # 既存コード
        # ...
```

### 6. recalculate_fof.py: FoFシグナル→signal_cache変換 (L920後に追加)

```python
# OPT-6: フラッシュしたFoFシグナルをsignal_cacheに追加
# _generate_monthly_returns()がDB re-queryせずに使用
fof_sig_map = {}
for sb in signals_batch:
    sig_date = sb["date"]
    holding = sb.get("holding_signal") or sb.get("signal")
    momentum_data = sb.get("momentum_data")
    if momentum_data and isinstance(momentum_data, dict):
        weights = momentum_data.get("weights")
        if weights:
            fof_sig_map[sig_date] = {"holding_signal": holding, "weights": weights}
            continue
    fof_sig_map[sig_date] = holding
signal_cache[portfolio.id] = fof_sig_map
```

### 7. recalculate_fof.py: 共有キャッシュ構築 (FoFループ前, L287後に追加)

```python
# OPT-6: 共通キャッシュを1回構築
from sqlalchemy import func, extract
from ..db.models import Price, TickerMonthlyReturn

# month_end_biz_cache (59回→1回)
shared_month_end_biz_cache: Dict[Tuple[int, int], date] = {}
month_ends_query = db.query(
    extract('year', Price.date).label('year'),
    extract('month', Price.date).label('month'),
    func.max(Price.date).label('last_biz_day')
).filter(Price.symbol == "SPY").group_by(
    extract('year', Price.date), extract('month', Price.date)
).all()
for row in month_ends_query:
    shared_month_end_biz_cache[(int(row.year), int(row.month))] = row.last_biz_day

# benchmark_ticker_returns (主にSPY、59回→1回)
shared_benchmark_returns: Dict[str, Tuple[float, float]] = {}
for tr in db.query(TickerMonthlyReturn).filter(TickerMonthlyReturn.symbol == "SPY").all():
    if tr.monthly_return is not None:
        shared_benchmark_returns[tr.year_month] = (
            tr.monthly_return,
            tr.monthly_return_open if tr.monthly_return_open is not None else tr.monthly_return,
        )

# portfolio_cache (FoF + コンポーネント)
shared_portfolio_cache: Dict[str, Portfolio] = {}
for p in fof_portfolios:
    shared_portfolio_cache[p.id] = p
for cid in all_component_ids:
    if cid not in shared_portfolio_cache:
        comp = db.query(Portfolio).filter(Portfolio.id == cid).first()
        if comp:
            shared_portfolio_cache[cid] = comp
```

### 8. recalculate_fof.py: L964呼出し変更

```python
_generate_monthly_returns(
    db, portfolio.id,
    price_cache=shared_price_cache,
    signal_cache=signal_cache,                    # OPT-6
    portfolio_cache=shared_portfolio_cache,        # OPT-6
    month_end_biz_cache=shared_month_end_biz_cache,  # OPT-6
    benchmark_ticker_returns=shared_benchmark_returns, # OPT-6
)
```

## 注意事項

1. **FoF-of-FoF依存**: L920後のsignal_cache追加が必須。フラッシュ前にcache追加すると、DB commit前にcacheが先行してしまう。フラッシュ後に追加する順序を守れ。
2. **DB commit**: L371のper-PF commitは維持。FoF-of-FoFのMonthlyReturn再ロード(L977)がcommit済みデータを前提とするため。
3. **benchmark_ticker**: FoFごとに異なるbenchmarkの可能性あり。設計ではSPYデフォルトだが、複数benchmark対応が必要なら辞書をネストする。
4. **非FoFコンテキスト**: Standard PF recalcやAPI単体呼出しでは従来通りNone渡し→内部構築。後方互換性維持。

## OPT-Aとの比較

将軍の優先順位ではOPT-A (FoF momentum_data月中縮小)がmonthly_returns_gen前に位置するが:
- **OPT-A**: DB Write削減 (~167s, 主にsignals_batch INSERT)
- **OPT-6**: Signal query + recursive load削減 (~395s)

OPT-6はOPT-Aの2.4倍の効果で、かつshared_price_cacheと同一パターンのため実装リスクが低い。
**OPT-6 → OPT-Aの順が最適。**

## 全体最適化ロードマップ (更新版)

| 順位 | 最適化 | 削減 | 累積 |
|------|--------|------|------|
| 1 | OPT-4/5 (Trade Perf Signal一括) | -520s | 2805s |
| 2 | Phase4 perf_calc除去 | -351s | 2454s |
| **3** | **OPT-6 (FoF MR cache共有)** | **-395s** | **2059s** |
| 4 | OPT-3 (fallback business_days) | -60s | 1999s |
| 5 | OPT-A (FoF momentum_data縮小) | -167s | 1832s |
| - | **合計** | **-1493s** | **1832s (44.9%追加削減)** |

Before: 7268s → OPT-1/2後: 3325s → 全OPT後: **~1832s (74.8%削減)**
