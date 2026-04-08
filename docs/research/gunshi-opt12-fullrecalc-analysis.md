# OPT-1/2 軍師分析報告 (2026-03-28T13:30, 最終更新14:25)

## 将軍の実装状況
- OPT-1 (business_days pre-load) + OPT-2 (monthly_returns_map pre-load): **実装完了**
- 対象: `return_calculator.py` + `trade_performance.py`
- テスト: 166 passed (将軍), 592 passed (軍師全体テスト, 既存1 fail無関係)

## 軍師の追加実装
- `trades_calculator.py` (API呼出しパス): OPT-1/2適用済み。テスト合格。

## ★ 全体recalc 最終確定結果 (113 PF)

**Before 7268s → After 3324.7s (54.2%減)**

### フェーズ別実測比較

| フェーズ | Before | After | 差分 | 備考 |
|---|---|---|---|---|
| Preprocessing | 15s | 14.27s | ≒同 | |
| Standard PF calc (65) | 398s | 410.44s | +3% | 誤差範囲 |
| MonthlyReturn gen (65) | 123s | 131.14s | +7% | 誤差範囲 |
| FoF recalc (59) | 1115s | 1313.56s | +18% | ※同時2プロセスの負荷 |
| **Precompute** | **5617s** | **1443.66s** | **-74.3%** | **OPT-1/2の効果** |
| **合計** | **7268s** | **3324.7s** | **-54.2%** | |

※非Precomputeフェーズ: Before 1651s → After 1881s (+14%)。同時に30PFサブセットrecalcが走行していたためDB競合発生。OPT-1/2は非Precomputeフェーズに影響しない。

### Precompute内訳

| Component | Before | After | 削減率 |
|---|---|---|---|
| Trade Perf | 5184s (92.3%) | 1059.61s (73.4%) | **79.6%** |
| Metrics | 135s (2.4%) | 132.13s (9.2%) | 2.0% |
| Rolling Chart | 82s (1.5%) | 77.81s (5.4%) | 5.0% |
| Rolling Summary | 80s (1.4%) | 80.01s (5.5%) | ≒同 |
| Drawdown | 54s (1.0%) | 50.31s (3.5%) | 6.9% |
| Risk Mgmt | 40s (0.7%) | 38.95s (2.7%) | 3.1% |

### Trade Perf 詳細分解

| 項目 | Before | After | 備考 |
|---|---|---|---|
| trade_loop合計 | 4627s | **241.80s** | **94.8%減** |
| ├ get_first_bday | 3133s | 0.000s | OPT-1で消滅 |
| ├ monthly_query | 1073s | 0.000s | OPT-2で消滅 |
| └ fallback_calc | 414s | 239.50s | 追い風-鉄壁229回→2回 |
| preload合計 | 0s | 28.41s | 新規(OPT-1/2のpre-load) |
| overhead (DB write等) | ~557s | ~789s | +42%。原因特定済み(後述) |
| **Trade Perf合計** | **5184s** | **1059.61s** | **79.6%減** |

※124 PF (65 Standard + 59 FoF)。先の「113」は監視途中の値。

### PF別実測 (代表)

| PF | Before trade_loop | After trade_loop | 削減率 | 備考 |
|---|---|---|---|---|
| 旧忍法-Ward | 84.44s | 31.94s | 62% | fallback支配(2回で31.9s) |
| 追い風-鉄壁 | 236s | **3.21s** | **98.6%** | 229回→2回fallback(後述) |
| DM-safe | 48.12s | 1.09s | 98% | 標準PF |
| DM4 | 51.71s | 1.12s | 98% | 標準PF |
| 激攻-白虎(FoF) | — | 1.67s | — | FoFもOPT有効 |
| 常勝-玄武(FoF) | — | 2.32s | — | FoFもOPT有効 |

**全113PFで `monthly_query=0.000s, get_first_bday=0.000s` 確認。OPT-1/2は完全に機能。**

Top 5 slowest PFs (After):
1. 旧忍法-Ward: 31.94s (fallback 2回×~16s)
2. 変わり身-常勝: 5.99s
3. 劇薬bam_guard: 4.45s
4. 劇薬bam: 3.89s
5. 四つ目-鉄壁: 3.61s

## 追い風-鉄壁 Signal=0問題 — 新知見

### 本番DB状態 (確認済み)
- PipelineEngine型の旧FoF 13個がSignalテーブルにレコード0件
- 本番では MonthlyReturn=0, TradePerformance=0

### recalc時の挙動 (今回判明)
**FoF recalcフェーズがMonthlyReturnを正しく再生成する**ため、OPT-2のキャッシュに乗る。
- Before: OPT-2なし → 毎月DBクエリ → キャッシュなし → 全月fallback(229回, 199s)
- After: OPT-2あり → dict pre-load → FoF recalc生成分がhit → 2回のみfallback(3.19s)
- **結論**: recalc文脈ではOPT-2が事実上の解決。本番DB問題は残存するが、recalc性能への影響は消滅

### 修正案 (本番DB向け)
1. **データ修正**: PipelineEngine実行後にSignalテーブルへ同期
2. **コード修正**: `_generate_monthly_returns`がpipeline_logsからも読めるようにする
3. **即効策**: 旧FoFを非アクティブ化 (シン版が後継)

## fallback_calc分析 (After)

全113PF合計: **222.81s** (Before 414s → 46%減)

| PF | 時間 | 呼出し数 | 備考 |
|---|---|---|---|
| 旧忍法-Ward | 31.90s | 2 | 各call ~16s（PF複雑度由来） |
| 追い風-鉄壁 | 3.19s | 2 | OPT-2で229→2回に改善 |
| 残り111 PF | 187.72s | 222 | 正常（partial month×2/PF） |

→ fallback_calc 222.81sは trade_loop 224.90sの**99%を占有**。
→ OPT-1/2後のtrade_loopは実質的にfallback_calcのみ。

## 予測 vs 実測の振返り

| 項目 | 予測 | 実測 | 差異 |
|---|---|---|---|
| trade_loop合計 | ~432s | 224.90s | 予測より48%良い(追い風-鉄壁改善) |
| Trade Perf合計 | ~432s | 1059.61s | overhead(DB write等)を過小評価 |
| Precompute合計 | — | 1443.66s | |
| 全体 | ~2516s | 3324.7s | 非Precomputeフェーズ増(DB競合) |

## Trade Perf overhead 807s の内訳分析 (軍師独自調査)

`[TRADE_PERF DETAIL]` (先頭5PFのみ出力) から分解:

| 項目 | 1PFあたり | 113PF推定合計 | 根拠 |
|---|---|---|---|
| Signal全件query | 1-6s | **~300s** | `db.query(Signal).filter(portfolio_id).order_by(date).all()` L63-65 |
| FoF trade extraction | 0-57s | **~200-300s** | `preload_fof_signals_recursive` L116。FoF共有コンポーネント重複ロード |
| Portfolio query | 220ms | ~25s | Render DBレイテンシ |
| Delete+Flush+Insert+Commit | 不明 | ~150-200s | PF毎のDB往復 |

実測データ (先頭5PF):
```
PF1(FoF): pf=221ms, signals=5892ms, monthly=0ms, trades=57494ms
PF2:      pf=224ms, signals=3236ms, monthly=0ms, trades=1.6ms
PF3:      pf=242ms, signals=1691ms, monthly=0ms, trades=1.4ms
PF4:      pf=227ms, signals=1163ms, monthly=0ms, trades=1.2ms
PF5:      pf=282ms, signals=1058ms, monthly=0ms, trades=1.1ms
```

→ **Signal事前一括ロード (OPT-4)**: 113個別クエリ → 1バルククエリ。推定削減: ~290s
→ **FoF signal共有キャッシュ (OPT-5)**: 共通コンポーネントの重複ロード排除。推定削減: ~200s

### OPT-4 設計案: Signal事前ロード

```python
# recalculate_fast.py precompute loop前に追加:
all_signals = db.query(Signal).order_by(Signal.portfolio_id, Signal.date).all()
signal_cache = {}
for s in all_signals:
    signal_cache.setdefault(s.portfolio_id, []).append(s)
# → _generate_trade_performance(db, pf_id, signal_cache=signal_cache, ...)
```

- 252K signals × ~200bytes/row ≈ 50MB in-memory。問題なし
- 113個別クエリ(avg 2.6s) → 1クエリ(推定5-10s)
- **推定削減: ~290s (Trade Perf全体の27%)**

## 偵察報告との統合 (cmd_1447)

### 影丸報告: Phase4 perf_calc orphaned code
- `prev_perf_cache` (L1497-1621) は出力先なし。除去で Standard PF calc ~40-60%削減 (~170s)
- **要決裁**: 殿の判断が必要 (decision_candidate)

### 小太郎報告: FoF月中データ縮小
- **OPT-A**: `momentum_data`月中をNull化 → DB書込み95%削減
- `fof_signals`マップ = 087最適化後のdead code候補
- pipeline_logs/rebalance_decisions月中書込み = 月初のみで十分

## OPT-1/2後の次期最適化候補 (統合版)

**全体recalc 3324.7s のボトルネック分布**:

| # | 候補 | コスト | 削減見込 | 難易度 | 出典 |
|---|---|---|---|---|---|
| 1 | **OPT-4: Signal事前ロード** | ~300s | ~290s | **低** | 軍師調査 |
| 2 | **Phase4 perf_calc除去** | ~170s | ~170s | 低(要決裁) | 影丸偵察 |
| 3 | **OPT-5: FoF signal共有cache** | ~250s | ~200s | 中 | 軍師調査 |
| 4 | **OPT-A: FoF月中データ縮小** | FoF DB write | 大 | 中 | 小太郎偵察 |
| 5 | **OPT-3: fallback business_days** | ~36s | ~36s | **低** | 軍師調査 |
| 6 | FoF recalc DB最適化 | 1314s | 未定 | 高 | 先行profiling |
| 7 | Trade Perf commit batching | ~180s | 未定 | 中 | 軍師調査 |

### 推奨実行順序
1. **OPT-4** (Signal事前ロード) → 最大効果・最低難易度。即実装可能
2. **Phase4 perf_calc除去** → orphaned code確認後、殿の判断次第
3. **OPT-3** (fallback business_days) → 小さいが確実。OPT-4と同時に実装可能
4. **OPT-5** + **OPT-A** → 中難易度だが効果大

**合計推定削減: OPT-3+4で ~326s → Trade Perf 1060s→~734s、全体 3325s→~2999s (10%追加削減)**

## OPT-4/5 統合設計: Signal & Portfolio 事前一括ロード

### 問題の根因
`_generate_trade_performance()` が113回呼ばれるたびに:
1. **Signal全件クエリ** (L63-65): PF毎に独立クエリ → avg 2.6s × 113 = ~300s
2. **Portfolio クエリ** (L46): avg 230ms × 113 = ~26s
3. **FoF signal_cache** (L107-108): 呼出しごとに**新規作成** → コンポーネントPFの重複ロード

`signal_cache`と`portfolio_cache`がローカルスコープなので、FoF1がコンポーネントAのSignalをロードしても、FoF2は同じAを再度ロード。59 FoFが各3-5コンポーネントを持つ場合、同一Signalが数十回重複取得される。

### 設計

**Step 1: recalculate_fast.py precomputeループ前** (~L1957):
```python
# OPT-4: Signal一括ロード (252K rows, ~50MB, 1クエリ ~5-10s)
from ..db.models import Signal
_t_sig_preload = time.perf_counter()
all_signal_rows = db.query(Signal).order_by(
    Signal.portfolio_id, Signal.date
).all()
signal_preload = {}
for s in all_signal_rows:
    signal_preload.setdefault(s.portfolio_id, []).append(s)
logger.info(f"[OPT-4] Signal preload: {len(all_signal_rows)} rows, "
            f"{len(signal_preload)} portfolios in {time.perf_counter()-_t_sig_preload:.1f}s")

# OPT-5: Portfolio & FoF signal cache (共有)
portfolio_preload = {p.id: p for p in target_portfolios}
# payload.portfoliosから全PF (コンポーネント含む) を追加
for p in payload.portfolios:
    portfolio_preload.setdefault(p.id, p)
fof_shared_signal_cache = {}  # FoF間で共有
```

**Step 2: _generate_trade_performance()にパラメータ追加**:
```python
def _generate_trade_performance(
    db, portfolio_id, *,
    price_cache=None, monthly_return_cache=None, benchmark_cum_cache=None,
    signal_preload=None,          # OPT-4: {pf_id: [Signal]}
    portfolio_preload=None,        # OPT-5: {pf_id: Portfolio}
    fof_signal_cache=None,         # OPT-5: FoF間共有signal_cache
) -> None:
```

**Step 3: 関数内部の変更**:
```python
# L46: Portfolio query → preload使用
if portfolio_preload and portfolio_id in portfolio_preload:
    portfolio = portfolio_preload[portfolio_id]
else:
    portfolio = db.query(Portfolio).filter(Portfolio.id == portfolio_id).first()

# L63-65: Signal query → preload使用
if signal_preload and portfolio_id in signal_preload:
    signals = signal_preload[portfolio_id]
else:
    signals = db.query(Signal).filter(
        Signal.portfolio_id == portfolio_id
    ).order_by(Signal.date).all()

# L107-108: FoF signal_cache → 共有cache使用
if is_fof:
    if fof_signal_cache is not None:
        signal_cache = fof_signal_cache  # 共有参照
    else:
        signal_cache = {}
    ...
```

### 推定効果
| 削減対象 | Before | After | 節約 |
|---|---|---|---|
| Signal個別クエリ (113回) | ~300s | ~5-10s (1回) | **~290s** |
| Portfolio個別クエリ (113回) | ~26s | 0s (preload済み) | **~26s** |
| FoF重複signalロード (59 FoF) | ~200s | ~0s (共有cache) | **~200s** |
| **合計** | ~526s | ~5-10s | **~516-521s** |

Trade Perf: 1060s → ~540-545s (49%減)
全体recalc: 3325s → ~2800-2810s (15%追加減)

### 注意点
- メモリ: 252K Signal rows × ~500bytes ≈ 126MB。recalcプロセスのメモリ予算内
- `fof_signal_cache`共有: 同一dictを全FoFが参照するため、1回preloadされたコンポーネントは再利用
- `signal_preload`は`list`、`fof_signal_cache`は`dict[date, CacheValue]`。フォーマット変換必要

## 既存テスト失敗 (無関係)
- `test_monthly_benchmark_single_source.py`: AttributeError (変更前から存在)
