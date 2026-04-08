# DM-Signal ディレクトリ構成
<!-- cmd_286 | 2026-02-23 | core.md §10から移動。プロジェクト全体のファイル配置 -->

```
/mnt/c/Python_app/DM-signal/
├── backend/
│   ├── app/
│   │   ├── main.py                   # FastAPI起動, router登録(:313-337 +debug:341-343), /healthz
│   │   ├── client.py                 # StockData APIクライアント
│   │   ├── api/                      # 22ルーターファイル(84-88エンドポイント)
│   │   │   ├── signals.py            # GET /api/signals (:67)
│   │   │   ├── portfolios.py         # GET/POST/DELETE /api/portfolios/* (:147,215)
│   │   │   ├── etl_trigger.py        # POST /admin/recalculate-sync (:235)
│   │   │   ├── history.py            # GET /api/history/{id} (:27)
│   │   │   ├── performance.py        # GET /api/performance/{id} (:27)
│   │   │   ├── metrics.py            # GET /api/metrics/* (:18)
│   │   │   └── ... (16 more routers)
│   │   ├── schemas/
│   │   │   ├── response.py           # ApiResponse{success,data,error,message} (:7-12)
│   │   │   ├── pipeline.py           # BlockType enum (:18-37)
│   │   │   └── models.py             # PortfoliosPayload等
│   │   ├── db/
│   │   │   └── models.py             # signals(:91-101), portfolios(:66-84) ORM
│   │   ├── services/
│   │   │   ├── pipeline/
│   │   │   │   ├── base.py           # PipelineBlock, PipelineContext
│   │   │   │   ├── engine.py         # PipelineEngine, execute_pipeline(:63), execute_pipeline_with_blocks(:191)
│   │   │   │   └── blocks/           # 14ブロック実装(Selection 11 + Terminal 3)
│   │   │   ├── return_calculator.py  # SSOT: calculate_monthly_return()
│   │   │   ├── momentum_cache.py     # MomentumCache
│   │   │   ├── vectorized_momentum.py
│   │   │   └── price_ratio_calculator.py  # PFのticker展開ロジック
│   │   └── jobs/
│   │       ├── recalculate_fast.py   # 高速再計算本体(Phase0-5)
│   │       ├── recalculate_fof.py    # FoF再計算（本番用・ローカル不可）
│   │       ├── shared.py             # ブロック登録(:208-253)
│   │       └── flush/
│   │           └── signal_flush.py   # UPSERT実装(:45-54)
│   ├── static/data/
│   │   └── dm_signal.db              # 本番ミラー（PF設定用）
│   └── .env                          # 本番DB接続情報
├── frontend/
│   ├── lib/
│   │   ├── api-client.ts             # API呼び出し(credentials=include, NEXT_PUBLIC_API_HOST)
│   │   └── types/
│   │       ├── api.ts                # SignalsLightResponse(:45-49), PortfoliosPayload(:5-7)
│   │       ├── portfolio.ts          # PortfolioSignal(:97-107)
│   │       └── market.ts             # PortfolioMomentum(:8-13)
│   └── contexts/
│       └── signals-context.tsx       # SignalsContext(:16,38,75-79)
├── scripts/                          # 671件
│   ├── analysis/
│   │   ├── grid_search/              # 188件(探索・検証ランナー群)
│   │   │   ├── grid_search_metrics_v2.py # simulate_strategy_vectorized()
│   │   │   ├── gs_csv_loader.py      # 共通CSVローダー(cmd_160)
│   │   │   ├── template_gs_runner.py # GSテンプレート
│   │   │   └── run_077_*.py          # 全6ブロックGSスクリプト(CSV直接読込)
│   │   └── data_sync/
│   │       └── download_all_prices.py # 価格DL(推奨)
│   ├── verify/                       # 29件(仮説検証/回帰確認)
│   └── core/                         # 6件(運用トリガー/収集)
├── analysis_runs/
│   └── experiments.db                # 分析用DB（価格ground truth）
├── docs/                             # 419-443件
│   ├── _INDEX.md                     # 全体目次（最初にここを読め）
│   ├── rule/                         # 25件: ビジネスルール(trade-rule.md=63K)
│   ├── skills/                       # 25件: 実装パターン
│   ├── portfolio-research/           # 33件: GSガイド
│   └── experiment_log.md             # 実験記録（cmd_035〜の全実験ログ）
├── tasks/                            # _INDEX.md, decisions.md, lessons.md, todo.md
└── outputs/grid_search/              # 分析結果出力先(DATA_CATALOG.md)
```
