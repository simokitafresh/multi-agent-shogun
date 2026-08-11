# DM-Signal依存マップ 将軍まとめ資料(cmd_4294成果物の要約)

作成: 将軍 2026-08-11 23:56 | 一次成果物: `DM-signal/docs/research/cmd_4294_dm-signal-page-data-api-map.md`(疾風・gist [4bb22f90](https://gist.github.com/4bb22f907b2b6a4d9bb899cf6cc70a41)) | 関連: 補填設計書§10(gist 2d1e7458)

## 1. 母数(コード現物抽出・2026-08-11 main)

| 項目 | 値 |
|---|---|
| FE routeページ | 21 |
| route固有APIを直接呼ぶページ | 16 |
| 静的/封鎖ページ(/, /docs, /faq, /offline, /trades) | 6区分 |
| 表示系endpoint(handler→table→生成層まで特定) | 33行(一次成果物§2の全表) |
| 全route共通の間接依存 | signals / viewer-permissions / pageview / prefetch(layout.tsx共通配置) |

## 2. 構造の発見(SSOT観点で最重要)

**ほぼ全ての表示系endpointが「precomputed_raw(L5 snapshot)を先に読み、無ければL2/L3テーブルへfallbackして再計算する」二重経路を持つ。**

- 例: `/api/performance` = precomputed_raw(performance) → monthly_returns fallback。`/api/annual-returns` = precomputed_raw → AnnualReturnsCalculator再計算。`/api/monthly-trade` = precomputed_raw → calculator fallback。
- 含意: **同じ数値がL5経路とfallback経路の2つの関数で生成されうる** — 殿指摘「同じ数値を別関数・別ルートで作成していないか」の構造的温床が全endpoint横断で存在する。項目単位の重複生成監査はcmd_4295で実施。
- 生成層の正: L1=ticker returns(`ticker_returns.py`) / L2=standard signals+monthly_returns(`recalculate_fast.py`) / L3=FoF+派生テーブル(`recalculate_fof.py`ほか) / L5=表示payload snapshot(`precompute_raw.py`)。L5は計算の正ではなくcacheである(一次成果物§2脚注)。

## 3. 既知表示欠け3系のcut point(ソースレベル分類)

| 欠け | FE側 | 切断点 |
|---|---|---|
| monthly_trade未表示 | FE呼出しは正常(`/monthly-trade`→`/api/monthly-trade/{id}`→MonthlyTradeTable) | **FE切断なし。API応答/precomputed_raw cache側** — ブラウザのAPI応答statusで切り分け可 |
| drawdownsページSPY drawdown%未表示 | FEはbenchmark_drawdownsをchart/tableへ渡し済み | **FE未要求ではない。`monthly_returns.benchmark_cumulative*`列またはbenchmark_tickerのnull** → 条件付き描画がスキップされる |
| ベンチマーク系列全般 | compareページのみ独立`/api/benchmark/{ticker}`、他はportfolio系endpointの内蔵列 | **endpoint毎に別**: API-null vs テーブル未計算を応答と行の現物で分類要 |

共通パターン: 3件ともFE側は正常で、**切断はデータ層(L5 cache/L2・L3テーブル列のnull)** — cache一本化(§10.1)とT8復旧の守備範囲に一致する。

## 4. 使い方

- FE/BE変更cmdの影響範囲判定 → 一次成果物§3のmermaid図(ページ→endpoint→テーブル→生成層)。
- I5完全性(T7合格条件)の充足リスト → §1母数+§3欠けcut point。
- 項目単位のSSOT監査(重複生成検出・BE/FE計算区分・関数名・ファイル&フォルダー構造) → cmd_4295成果物(起票済み)。

## 因果リンク

- ← [[cmd_4294_dm-signal-page-data-api-map]] 一次成果物
- → [[dm-production-issues-asis-tobe-5w1h_20260810]] §10.1タスクリスト・I5完全性契約
- → [[dm-signal-ssot-audit-map]] cmd_4295(項目単位SSOT監査)
