<!-- Vercel圧縮: 2026-04-13 267行→索引化 -->
# fullrecalculate速度向上 分析 (索引)

> 詳細設計書 → `docs/research/gunshi-fullrecalc-speed-analysis.md` (267行)

## 結論

| 指標 | 値 |
|------|-----|
| 初回→現在 | 11,818s → **357.28s** (97.0%削減, 33x) |
| baseline→現在 | 637.80s → **357.28s** (-44.0%) |
| signal整合性 | 453,663件(baseline完全一致) |

## 新ボトルネック構造(357.28s時点)

| # | 項目 | 時間 | 割合 | 状態 |
|---|------|------|------|------|
| 1 | L2 trade_perf | ~100-105s | 28% | profiling未発火。要修正 |
| 2 | L3 daily_loop | 67.88s | 19% | Pythonループ。ベクトル化要設計 |
| 3 | L3 mr_gen | 55.21s | 15% | OPT-6最適化済み。安定 |
| 4 | L2 db_write | 44.89s | 13% | Singapore latency制約 |
| 5 | L3 dw_signals_flush | 41.93s | 12% | deferred flush後も残存 |

## 実装済みOPT一覧

→ `docs/research/gunshi-fullrecalc-speed-analysis.md` §改善提案

Tier 1全項目+Tier 2 NEW-1/2a実装済み。残: NEW-2b(whileループNumPy化, ROI未確定)
