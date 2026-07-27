<!-- last_updated: 2026-07-27 cmd_4184 -->
<!-- source_commit:464e84e665d8bc750481fcbbe6a2d18de8ecd35c reason:cmd_4184_main_integration evidence:cmd_4184_content_present -->
<!-- Vercel圧縮: 2026-04-13 267行→索引化 -->
# fullrecalculate速度向上 分析 (索引)

> 詳細設計書 → `docs/research/gunshi-fullrecalc-speed-analysis.md` (267行)

## 結論

- 2026-07-27 cmd_4184: 運用壁時計の正はstandard cron起動→FoF完了。直近実測 `01:10:13→01:52:38 UTC=42分25秒`。FoF起点は12分24秒だが上流+cron時差を隠すため補助値のみ。旧91.3s+716.6s=807.9sは累積計算時間で壁時計ではない。06-26値はrun IDなしのため時点間比較から除外。詳細 → `/mnt/c/Python_app/DM-signal/docs/research/cmd_4184_fullrecalc_wallclock.md`
- 2026-07-27 cmd_4180: 同runの本番DBにL3内部内訳が保存済み。`monthly_returns_gen=275.20s`、`unmeasured=122.41s`、`dw_signals_flush=115.26s`、`daily_loop=80.61s`。PF別performance logは0件。FoFはトポロジカル逐次、子MR commit/cache reload後に親へ進み、cronもstandard成功待ちで直列。trade_perfの共有cache/N+1除去はFoFにも適用済み。詳細 → `docs/research/cmd_4180_fullrecalc_l3_recon.md`
- 2026-07-27 cmd_4179: id214総時間671.18秒と別runのL5=66.64秒を差し引いた「L5=9.9%」はrun lineage混算のため棄却。直近FoF run `20260727014042HSIHNE` はL3=503s(70.3%)、L2=154s(21.6%; trade_perf=117s)、L5=42.3s(5.9%)。詳細 → `docs/research/cmd_4179_fullrecalc_timing_recon.md`

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

## 因果リンク

- → [[gunshi-fullrecalc-resilience-analysis.md]] 速度改善がzero-signal解消に寄与した一方、処理時間依存の正確性保証は中断耐性リスクを残す
- → [[gunshi_idle_dm_signal_speed_profiling_20260626]] 2026-06-26 サービス別1PF計測結果(cProfile)。monthly_trade 86s→4.5s等、N+1クエリ最適化の修正前後数値
