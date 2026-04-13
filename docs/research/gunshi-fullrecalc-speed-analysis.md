<!-- last_updated: 2026-04-09 -->
<!-- Vercel移設元: context/gunshi-fullrecalc-speed-analysis.md (267行) -->
<!-- 移設日: 2026-04-13 -->
# fullrecalculate速度向上 残改善分析 (軍師)
# 2026-03-29T01:00更新 | 第3サイクル計測357.28s(-44%)反映

## 現状ステータス
- **★本番計測: 357.28s** (cmd_1478, run_id=20260328_154605)。OPT-12/13/14/15+cmd_1469-1473全適用
- baseline 637.80s → 357.28s (**-44.0%**)。pre-OPT 3566.86s → 357.28s (10.0x改善)。初回11,818s → 357.28s (**97.0%削減**)
- signal=453,663件(baseline完全一致)。zero-signal=0件。nested FoF回帰解消(OPT-13)
- GP-124(signal整合性チェック)でzero-signal自動検知ゲート追加済み

## 本番計測Phase別時間分布 (cmd_1466実測)

### Layer概要
| Layer | 時間 | 割合 | pre-OPT | 改善率 |
|-------|------|------|---------|--------|
| L2 (Standard) | 240.66s | 37.7% | 2700.49s | 11.2x |
| L3 (FoF) | 362.27s | 56.8% | 719.70s | 2.0x |
| Overhead | 34.87s | 5.5% | — | — |
| **Total** | **637.80s** | **100%** | **3566.86s** | **5.6x** |

### L2 substep内訳 (240.66s)
| substep | 時間 | L2内割合 | 全体割合 |
|---------|------|---------|---------|
| **trade_perf** | **142.78s** | **59.3%** | **22.4%** |
| db_write | 47.38s | 19.7% | 7.4% |
| metrics | 17.85s | 7.4% | 2.8% |
| rolling_chart | 14.84s | 6.2% | 2.3% |
| phase45_monthly_returns | 12.47s | 5.2% | 2.0% |
| rolling_summary | 6.21s | 2.6% | 1.0% |
| drawdown | 5.88s | 2.4% | 0.9% |
| risk_mgmt | 3.42s | 1.4% | 0.5% |
| signal_calc | 1.06s | 0.4% | 0.2% |
| perf_calc | 0.0s | — | 除去済み |

### L3 FoF内訳 (362.27s, 59 FoF)
| substep | 時間 | L3内割合 | 全体割合 |
|---------|------|---------|---------|
| **db_write** | **130.64s** | **36.1%** | **20.5%** |
| **unmeasured** | **74.64s** | **20.6%** | **11.7%** |
| daily_loop | 71.0s | 19.6% | 11.1% |
| monthly_returns_gen | 56.61s | 15.6% | 8.9% |
| db_query | 16.87s | 4.7% | 2.6% |
| cache_init | 8.25s | 2.3% | 1.3% |
| dataframe_prep | 3.64s | 1.0% | 0.6% |

### Phase 5b Precompute内訳 (191.85s)
| generator | 時間 | 割合 |
|-----------|------|------|
| **Trade Perf** | **142.78s** | **74.4%** |
| Metrics | 17.85s | 9.3% |
| Rolling Chart | 14.84s | 7.7% |
| Rolling Summary | 6.21s | 3.2% |
| Drawdown | 5.88s | 3.1% |
| Risk Mgmt | 3.42s | 1.8% |

### ボトルネック順位（全体に対する割合）
1. **L2 trade_perf = 142.78s (22.4%)** — ★cmd_1471偵察完了。内訳下記
2. **L3 db_write = 130.64s (20.5%)** — ★cmd_1470で signals_flush deferred化済み
3. **L3 unmeasured = 74.64s (11.7%)** — ★cmd_1467+1469で正体特定+N+1修正済み
4. **L3 daily_loop = 71.0s (11.1%)** — Phase 4A最適化済みだが残存
5. L3 monthly_returns_gen = 56.61s (8.9%) — OPT-6で512.97s→56.61s (89%削減!)

### L2 trade_perf 142.78s内訳（cmd_1471偵察確定）
| 要素 | 推定時間 | 割合 | 状態 |
|------|---------|------|------|
| load_business_days N+1 | 21-36s | 15-25% | 偵察完了。引数化で即解消 |
| calculate_trade_period_return whileループ | 43-57s | 30-40% | Python overhead。NumPy化要設計 |
| calculate_monthly_return fallback | 14-29s | 10-20% | ★del price_cache(L281)阻害。price_cache転用で解消 |
| per-PF DB write (DELETE+INSERT+commit) | 7-14s | 5-10% | バッチcommit化で解消 |
| bulk_insert+commit | 14-21s | 10-15% | バッチcommit化と合算 |
| Setup (preloaded) | <3s | <2% | OPT-4/5済み |
| pandas/bisect/sanitize | 7-14s | 5-10% | CPU bound |

## なぜなぜ分析

### Q1: 260sの60%=155sを占めるL2の内訳は何か？
→ Phase 2-3.7(前処理): ~42s, Phase 4(日次ループ): signal生成+DB書込み, Phase 4.5(monthly_returns_gen): 最大ボトルネック

### Q2: monthly_returns_genはなぜ遅い？
→ 124 PF(65 standard + 59 FoF)に対して_generate_monthly_returns()を個別実行。各実行で: DataFrame構築 → resample → 月ごとの価格比計算 → DB flush。Signal/Portfolio/PriceCacheはOPT-4/5/6で共有済みだが、**月次リターン計算自体とDB書込みは個別**

### Q3: FoFの62sの中で何が最もコストか？
→ コード検証で2つのN+1問題を発見:
  (a) recalculate_fof.py L376-382: 各FoFの各コンポーネントに個別DB query (300-900クエリ)
  (b) 日次ループ(LOOP-1): ~6000-7000日 × 59 FoF。Pythonループオーバーヘッド

### Q4: 日次ループをさらに高速化できないか？
→ holding_signal更新に前日状態依存→完全ベクトル化困難。月変わり日のみ状態遷移+月中一括INSERTの中間案が現実的

### Q5: dead codeは残っているか？ → ★確定
→ fof_signals[target_date]: Dead code確定。書込みのみ(L543,L761)。読取りゼロ。354K dict insert削除で1-3s削減

### Q6: trade_perf 142.78sの中で何が最もコストか？(cmd_1471確定)
→ 3層: (1)load_business_days N+1(21-36s) (2)fallback calc(14-29s,del price_cache阻害) (3)per-PF DB write(7-14s)

## 改善提案（ROI順）

### Tier 1: 即効性高（全項目実装済み）
| # | 改善 | 推定効果 | 状態 |
|---|---|---|---|
| 1★ | component_rebalance_triggers cache参照 | L3: 30-60s | ✅ cmd_1469 |
| 1b★ | load_business_days N+1除去 | L2: 21-36s | ✅ cmd_1472 |
| 2 | gc.collect()削減(59→5回) | L3: 5-12s | ✅ OPT-12 |
| 5 | fof_signals dead code除去 | L3: 1-3s | ✅ OPT-12 |
| 1c | per-PF→バッチcommit | L2: 7-14s | ✅ cmd_1472 |
| 1d | L2 signals INSERT化 | L2: 2-5s | ✅ OPT-14 |

### Tier 2: 大型（実装済み or 残存）
| # | 改善 | 推定効果 | 状態 |
|---|---|---|---|
| NEW-1 | dw_signals_flush最適化 | L3: 40-60s | ✅ cmd_1470 |
| NEW-2a | fallback price_cache保持 | L2: 14-29s | ✅ cmd_1473 |
| NEW-2b | whileループNumPy化 | L2: 10-20s | 保留(ROI未確定) |

## 第3サイクル計測結果（cmd_1478, 357.28s）

### 3サイクル比較
| | baseline(cmd_1466) | **cmd_1478** | 改善率 |
|--|---|---|---|
| Total | 637.80s | **357.28s** | **-44.0%** |
| L2 | 240.66s | **109.47s** | **-54.5%** |
| L3 | 362.27s | **214.01s** | **-40.9%** |

### 新ボトルネック構造(357.28s)
1. L2 trade_perf推定~100-105s(28%) — profiling未発火
2. L3 daily_loop 67.88s(19%)
3. L3 mr_gen 55.21s(15%)
4. L2 db_write 44.89s(13%)
5. L3 dw_signals_flush 41.93s(12%)

### 軍師直接実装(OPT-12〜15)
- OPT-12(00fd5257): gc削減+dead code除去+profiling改善
- OPT-13(f3ff64a7): nested FoF回帰修正(signal_cache補完)
- OPT-14(79663eda): Standard PF signals INSERT化
- OPT-15(1e3401fd): component_weights commit集約59→6

### 残タスク
- NEW-2b(whileループNumPy化): 全適用後にtrade_perf 63-101s→再評価
- trade_perf profiling未発火問題の原因特定
