# perf_price_cache UnboundLocalError 修正設計

## メタデータ
- 分析者: 軍師(gunshi)
- 日付: 2026-04-25
- トリガー: idle自走 — 掲示板blt_20260425_012033の追加調査
- 対象: backend/app/services/recalculate_fast.py

## §1 バグの構造

| ステップ | 行番号 | 動作 |
|---------|--------|------|
| 1. 初期化 | L1479 | `perf_price_cache = None` |
| 2. 分岐 | L1482-1484 | `if not standard_portfolios:` → Phase 1スキップ |
| 3. 本来の初期化 | L1651 | `perf_price_cache = PriceCache()` ← **スキップされる** |
| 4. 参照 | L2182 | `perf_price_cache.is_loaded()` → **AttributeError** |

FoF-only run(sync_fof)でstandard_portfolios空→Phase 1全スキップ→初期化されず→precompute 109/109全件失敗。

## §2 参照箇所(6箇所)

| 行番号 | 用途 |
|--------|------|
| L2182 | is_loaded()確認 |
| L2208 | _generate_trade_performance()に渡す |
| L2543 | _generate_monthly_returns()に渡す |
| L2585 | ALM第2パス計算 |
| L2608 | ALM後MR生成 |
| L2824 | _run_precompute_generators_for_portfolio() |

## §3 修正案(推奨: 案A)

**案A: 無条件最小初期化**: standard_portfolios空時に`PriceCache()`を空で初期化。
is_loaded()=Falseとなり、後続コードでキャッシュなし動作(DBフォールバック)。

```python
if not standard_portfolios:
    logger.info("No standard portfolios to recalculate.")
    perf_price_cache = PriceCache()  # FoF-only run安全網
```

**理由**: PI-018(silent fallback禁止)に抵触しない。PriceCache()空=キャッシュなし動作=DBから毎回取得=遅いが正確。

## §4 影響範囲

- FoFのprecompute(チャート・メトリクス事前計算)が全滅→Admin UIのFoFチャートデータ未生成
- FoFのシグナル・MonthlyReturn計算は_recalculate_fof_historyで行われるため影響なし
- cmd_2259/2260(MR高速化)とは無関係。sync-fof特有のパス

## §5 テスト方針

1. `python -c "from app.services.recalculate_fast import recalculate_history_fast; ..."` でFoF-only呼出し
2. precompute 109/109でAttributeError消失を確認
3. FoF MR件数が維持されること(回帰テスト)
