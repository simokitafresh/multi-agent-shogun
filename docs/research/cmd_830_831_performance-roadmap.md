# cmd_830+831 万全偵察統合レポート — DM-Signal表示速度 次期改善ロードマップ

> 作成: 家老 2026-03-12 | 水平4名(cmd_830) + 垂直4名(cmd_831) = 8名偵察統合

## §1 改善候補ランク付け（費用対効果順）

### Tier S — 超高ROI（1 cmd以下, 体感改善大）

| # | 施策 | 発見者 | 変更規模 | 期待効果 | 根拠 |
|---|------|--------|----------|----------|------|
| S1 | **client-side routing化** | hanzo(垂直UX) | sidebar.tsx 1箇所 | 全ページ遷移 0.8-1.5s→0.05-0.1s | window.location.href→router.push()。Next.js App Router+output:exportでも動作。体感改善80% |
| S2 | **pool_pre_ping=True** | tobisaru(垂直infra) | database.py 1行 | 接続断耐性+500エラー防止 | Renderメンテナンス/瞬断時の初回リクエスト失敗を防止。~1msオーバーヘッド |

### Tier A — 高ROI（1-2 cmd, 定量改善顕著）

| # | 施策 | 発見者 | 変更規模 | 期待効果 | 根拠 |
|---|------|--------|----------|----------|------|
| A1 | **/api/signals request-scope cache注入** | sasuke(水平signals)+saizo(垂直code) | signals.py+price_ratio_calculator.py | 473→4 query, admin 38s→<1s, viewer 200-390ms→<100ms | FoF 38件の再帰展開が97.9%消費。portfolio_cache+signal_cache注入で解消 |
| A2 | **benchmark TickerMonthlyReturn fast path** | kagemaru(水平BE) | benchmark.py 1箇所 | 427ms→50ms (10倍) | TickerDailyReturn 2500行→TickerMonthlyReturn 120行。fallback維持 |
| A3 | **Signal全件ロード集約化** | kagemaru(水平BE)+hayate(水平cache)+saizo(垂直code) | monthly_returns_calc+annual_returns_calc | 288ms→5ms | Signal.date全件→func.min/max SQL集約。3名が独立発見 |
| A4 | **ETag永続化(IndexedDB)** | hayate(水平cache) | api-cache.ts+api-client.ts | Monthly Returns warm退行解消(186→129ms以下) | etagStoreメモリのみ→IndexedDB永続化。reload後も304成立 |

### Tier B — 中ROI（1-2 cmd, 段階的改善）

| # | 施策 | 発見者 | 変更規模 | 期待効果 |
|---|------|--------|----------|----------|
| B1 | Compare Summary Map化+useMemo | kirimaru(水平FE)+saizo(垂直code) | compare-summary/page.tsx | 53,508比較→O(1) lookup。timing切替高速化 |
| B2 | useDelayedLoading 6ページ適用 | hanzo(垂直UX) | 6ページファイル | スピナーチラつき解消。既存フック活用で工数最小 |
| B3 | prefetch/page fetch責務統一 | saizo(垂直code)+hayate(水平cache) | usePrefetch+signals-context+各page | visible page dataはpage側に一本化。effect重複排除 |
| B4 | etagStore data重複排除 | kotaro(垂直dataflow) | api-client.ts 4箇所 | RAM ~50%削減。etagStore→etag stringのみ |
| B5 | ETag拡張(signals/performance/deterioration) | tobisaru(垂直infra) | 3エンドポイント | 304応答率向上。SWRとの相乗効果 |
| B6 | execution-timing context useMemo化 | saizo(垂直code) | execution-timing-context.tsx 1箇所 | signals更新時の巻き添え再render防止 |
| B7 | Monthly Returns state churn削減 | kirimaru(水平FE) | monthly-returns/page.tsx+table | quick/full二段→background upgrade。setMonthlyReturns(null)廃止 |

### Tier C — 構造的リファクタ（3+ cmd, 大規模変更）

| # | 施策 | 発見者 | 期待効果 | 備考 |
|---|------|--------|----------|------|
| C1 | FoF expand bulk化 | kagemaru(水平BE)+saizo(垂直code) | monthly-trade FoF 564ms削減 | expand_portfolio_to_tickers内部クエリ自体の削減が本質 |
| C2 | MonthlyReturn共通service化 | saizo(垂直code) | 3 endpoint重複走査解消 | performance/monthly-returns/monthly-trade統合 |
| C3 | open/close variant selector | kotaro(垂直dataflow) | payload 25-30%削減(8 API) | BE+FE同時変更。後方互換variant=both |
| C4 | Rolling Returns hover ref化 | kirimaru(水平FE) | hover中SVG再render停止 | state→ref+imperative overlay |
| C5 | Admin component分割 | kirimaru(水平FE) | 1013行ページのReact.memo島化 | DB Status/PortfolioEditor分離 |
| C6 | raw_signal除去 | kotaro(垂直dataflow) | payload 5-10%削減 | FE未使用フィールド。全消費者grep確認必須 |
| C7 | ticker dict圧縮 | kotaro(垂直dataflow) | payload 15-20%削減 | top-level 1回+変更月のみ。FE表示ロジック変更 |

## §2 垂直×水平 突合（一致点と相違点）

### 一致点（複数観点で独立確認）

| 所見 | 水平 | 垂直 | 信頼度 |
|------|------|------|--------|
| Signal全件ロードが無駄 | kagemaru(BE)+hayate(cache) | saizo(code) | ★★★ 3名独立確認 |
| compare-summary metrics.find O(n²) | kirimaru(FE) | saizo(code) | ★★★ 2名独立確認 |
| prefetch+page二重fetch | hayate(cache) | saizo(code) | ★★★ 2名独立確認 |
| /api/signals FoF cache未注入 | sasuke(signals) | saizo(code) | ★★★ 2名独立確認 |
| ETag永続化が必要 | hayate(cache) | tobisaru(infra) | ★★ 2名が補完的に確認 |

### 垂直でのみ発見（水平では見えなかった盲点）

| 所見 | 発見者 | 重要度 |
|------|--------|--------|
| **window.location.hrefによるfull page reload** | hanzo(UX) | ★★★ 最大発見。体感改善80% |
| execution-timing context fan-out rerender | saizo(code) | ★★ |
| etagStore data重複(RAM倍増) | kotaro(dataflow) | ★★ |
| open/close二重送信(8 API横断) | kotaro(dataflow) | ★★ |
| useDelayedLoading定義済み未使用 | hanzo(UX) | ★ |
| pool_pre_ping未設定 | tobisaru(infra) | ★ |
| viewer権限ロード中ナビ消失 | hanzo(UX) | ★ |

## §3 推奨実装順序（ロードマップ）

```
Phase 1（即効性・低リスク）— 2-3 cmd
  S1: client-side routing化
  S2: pool_pre_ping=True
  A2: benchmark fast path
  A3: Signal集約化
  B2: useDelayedLoading適用

Phase 2（コア最適化）— 3-4 cmd
  A1: /api/signals request-scope cache
  A4: ETag永続化
  B1: Compare Summary Map化
  B4: etagStore data重複排除
  B6: execution-timing useMemo化

Phase 3（FE統合最適化）— 2-3 cmd
  B3: prefetch/page fetch責務統一
  B5: ETag拡張(3エンドポイント)
  B7: Monthly Returns state churn削減

Phase 4（構造的改善・要殿裁定）— 4+ cmd
  C1-C7: 大規模リファクタ群
```

## §4 教訓候補（8名から収集）

| 忍者 | 教訓 | PJ |
|------|------|-----|
| sasuke | recursive FoF expanderはroute層からrequest-scope cache注入必須 | dm-signal |
| kirimaru | — | — |
| hayate | persistent data cacheにvalidatorを永続化しないとwarm reloadはfull refetchに崩れる | dm-signal |
| kagemaru | precomputedテーブル存在時はraw再計算APIを残さずfast pathを導入せよ | dm-signal |
| hanzo | Next.js static export ≠ SPAではない。client-side routing動作する | dm-signal |
| saizo | prefetchとpage effectに同一endpoint群を持たせるとorchestration/state update重複は残る | dm-signal |
| kotaro | etagStoreにdataを持たせるとapiCacheと二重保持でRAM倍増 | dm-signal |
| tobisaru | managed DBでのpool_pre_ping必須 + workerごと独立キャッシュのヒット率低下 | dm-signal |

## §5 decision_candidate（忍者から上申）

| 忍者 | 提案 |
|------|------|
| hayate | 修正優先順: ETag永続化が先、prefetch縮退が次 |
| saizo | FE「visible page data owner統一」+ BE「MonthlyReturn slice共通service化」の二段 |
| sasuke | request-scope cache → signal miss memoize → 短TTL endpoint cacheの順 |
