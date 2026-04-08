# cmd_477 DM-signal Knowledge Audit (sasuke: subtask_477_recon_a)

## Scope

- Date: 2026-03-01 (JST)
- Project: /mnt/c/Python_app/DM-signal
- Source directories:
  - docs/rule/ (AC1)
  - docs/architecture/ (AC4)
- Freshness definition:
  - fresh: updated within 3 months
  - stale: 3-6 months
  - ancient: 6+ months

## AC5 (integrated): Directory Summary

| Directory | File Count | Total Lines | fresh | stale | ancient | unknown | Fresh Ratio |
|---|---:|---:|---:|---:|---:|---:|---:|
| `docs/rule` | 26 | 13481 | 26 | 0 | 0 | 0 | 100.0% |
| `docs/architecture` | 8 | 4314 | 8 | 0 | 0 | 0 | 100.0% |
| `docs/skills` | 25 | 9301 | 25 | 0 | 0 | 0 | 100.0% |
| **Total** | **59** | **27096** | **59** | **0** | **0** | **0** | **100.0%** |


## AC1: docs/rule/ Catalog (26 files)

| File | Subject (1-line) | Lines | Last Updated | Freshness | Dependencies | Category |
|---|---|---:|---|---|---|---|
| `docs/rule/DTB3-guide.md` | DTB3 取扱書（Dual Momentum 向け仕様） | 330 | 2026-01-07 | fresh | - | DB・インフラ |
| `docs/rule/_INDEX.md` | docs/rule配下の索引・導線 | 136 | 2026-02-27 | fresh | ../../AGENTS.md, ../../CLAUDE.md, AGENTS.md, CLAUDE.md, docs/archives/misc/z-archive-check-rule-new-old.md, docs/archives/misc/z-archive-check-rule-old.md | 運用手順 |
| `docs/rule/api-usage-guide.md` | API Usage Guide for the Stock Data Platform | 876 | 2026-01-07 | fresh | docs/implementation-task-list.md | 運用手順 |
| `docs/rule/business_rules.md` | 取引/表示/計算の業務ルール集 | 1070 | 2026-01-31 | fresh | backend/app/api/portfolios.py, backend/app/jobs/recalculate_fast.py, backend/app/jobs/recalculate_fof.py, backend/app/schemas/models.py, backend/app/services/masking_service.py, backend/app/services/price_ratio_calculator.py | 計算ルール |
| `docs/rule/calculation-theory.md` | Return/Metrics/Rebalanceの計算理論 | 1250 | 2026-01-31 | fresh | backend/app/db/models.py, backend/app/jobs/daily_etl.py, backend/app/jobs/recalculate_fast.py, backend/app/services/annual_returns_calculator.py, backend/app/services/drawdowns_calculator.py, backend/app/services/metrics_calculator.py | 計算ルール |
| `docs/rule/check-rule.md` | check-rule: Truth-Based 検証ルール | 302 | 2025-12-31 | fresh | backend/scripts/verify_truth.py, scripts/verify_025_endbalance.py | 検証手順 |
| `docs/rule/database-info.md` | DB構造・接続・運用情報 | 556 | 2026-02-05 | fresh | scripts/setup_local_db.py | DB・インフラ |
| `docs/rule/design-light.md` | DM-Signal - ライトモード デザイン仕様書 | 127 | 2025-12-31 | fresh | - | UI・デザイン |
| `docs/rule/design-list-light.md` | DM-Signal デザイン標準 (Light Mode) | 136 | 2025-12-30 | fresh | - | UI・デザイン |
| `docs/rule/design-list.md` | DM-Signal デザイン現状リスト | 474 | 2025-12-28 | fresh | docs/business_rules.md, docs/design.md | UI・デザイン |
| `docs/rule/design.md` | DM-Signal - デザイン仕様書 | 1299 | 2025-12-28 | fresh | - | UI・デザイン |
| `docs/rule/gs-parity-verification-guide.md` | GS エンジン本番パリティ検証ガイド | 197 | 2026-02-13 | fresh | - | 検証手順 |
| `docs/rule/local-postgresql-guide.md` | ローカルPostgreSQL環境ガイド | 308 | 2026-02-05 | fresh | scripts/setup_local_db.py | DB・インフラ |
| `docs/rule/local-verification-guide.md` | ローカル検証ガイド | 516 | 2026-01-26 | fresh | ../../AGENTS.md, AGENTS.md, scripts/analysis/check_fof_structure.py, scripts/analysis/check_local_db.py, scripts/analysis/new_feature_test.py, scripts/analysis/verify_v0_v2_consistency.py | 検証手順 |
| `docs/rule/ninpou-fof-creation-runbook.md` | 忍法FoF作成ランブック | 670 | 2026-02-15 | fresh | scripts/analysis/create_dc_shijin.py, scripts/analysis/grid_search/run_077_bunshin.py, scripts/analysis/grid_search/run_077_kasoku.py, scripts/analysis/grid_search/run_077_kawarimi.py, scripts/analysis/grid_search/run_077_monban.py, scripts/analysis/grid_search/run_077_nukimi.py | 運用手順 |
| `docs/rule/portfolio-naming-convention.md` | PF命名規則・識別子運用 | 445 | 2026-02-20 | fresh | - | 運用手順 |
| `docs/rule/rebalance-verification.md` | リバランス検証手順と判定基準 | 534 | 2026-01-31 | fresh | backend/app/jobs/recalculate_fast.py, backend/app/services/rebalance.py, backend/app/utils/fof.py, backend/scripts/verify_rebalance.py, backend/scripts/verify_rebalance_comprehensive.py, scripts/verify_rebalance.py | 検証手順 |
| `docs/rule/renderyaml_guide.md` | Render.yaml Configuration Guide & Best Practices | 106 | 2025-12-07 | fresh | render.yaml | DB・インフラ |
| `docs/rule/requirements-spec.md` | デュアルモメンタム・シグナルアプリ 要件定義書 | 374 | 2026-01-05 | fresh | - | 運用手順 |
| `docs/rule/return-consistency-verification.md` | Return Consistency Verification Guide | 297 | 2026-01-15 | fresh | scripts/check_return_consistency.py, scripts/check_return_detail.py, scripts/check_trades_vs_monthly.py, scripts/verify_return_vs_price.py | 検証手順 |
| `docs/rule/rule.md` | DM-Signal Documentation Rule Book | 762 | 2025-12-28 | fresh | ../../AGENTS.md, AGENTS.md, backend/app/api/metrics.py, backend/app/api/signals.py, backend/app/main.py, docs/11th-step.md | 計算ルール |
| `docs/rule/security-status.md` | 認証・認可・レート制限の現状 | 707 | 2026-01-31 | fresh | backend/app/api/auth.py, backend/app/api/viewer_tiers.py, backend/app/auth.py, backend/app/core/rate_limiter.py, backend/app/db/models.py, backend/app/main.py | DB・インフラ |
| `docs/rule/shijin-pf-creation-runbook.md` | 四神PF作成ランブック | 210 | 2026-02-17 | fresh | scripts/analysis/create_dc_shijin.py, scripts/analysis/create_prod_shijin.py, scripts/analysis/grid_search/_extract_cagr_top.py, scripts/analysis/grid_search/_extract_calmar_top.py, scripts/analysis/grid_search/family_grid_search.py, scripts/analysis/rename_prod_create_cagr_shijin.py | 運用手順 |
| `docs/rule/timing-and-bottleneck-analysis.md` | 計測・ボトルネック分析ガイド | 340 | 2026-01-06 | fresh | backend/app/api/etl_trigger.py, backend/app/db/models.py, backend/app/jobs/sync_layers.py, backend/app/utils/timing.py | 運用手順 |
| `docs/rule/trade-rule.md` | Trade Rule SSOT（RULE01-11） | 1280 | 2026-02-08 | fresh | backend/app/services/metrics_calculator.py, backend/app/services/price_ratio_calculator.py, backend/app/services/rebalance.py, backend/app/services/return_calculator.py, backend/app/services/vectorized_momentum.py, backend/app/utils/business_day_utils.py | 計算ルール |
| `docs/rule/vercel-style-guide.md` | Vercelスタイル（Passive Context Indexing）ガイド | 179 | 2026-02-27 | fresh | ../../AGENTS.md, AGENTS.md | UI・デザイン |

## AC4: docs/architecture/ Catalog

| File | Subject (1-line) | Lines | Last Updated | Freshness | Dependencies | Category |
|---|---|---:|---|---|---|---|
| `docs/architecture/Performance-001.md` | Performance-001: 実測データに基づくパフォーマンス分析 | 267 | 2025-12-24 | fresh | - | DB・インフラ |
| `docs/architecture/Performance.md` | パフォーマンス検証レポート | 1049 | 2025-12-29 | fresh | backend/app/api/metrics.py, backend/app/db/models.py, backend/app/jobs/recalculate_fast.py, backend/app/services/trades_calculator.py, backend/scripts/compare_precomputed.py, backend/scripts/test_trade_perf.py | DB・インフラ |
| `docs/architecture/_INDEX.md` | docs/architecture配下の索引・導線 | 94 | 2026-02-15 | fresh | - | 運用手順 |
| `docs/architecture/architecture.md` | DM-Signal アーキテクチャドキュメント | 1000 | 2026-02-05 | fresh | render.yaml | DB・インフラ |
| `docs/architecture/backend-deep-dive.md` | Backend Deep Dive — 横断的全体マップ | 367 | 2026-03-01 | fresh | scripts/verify_rebalance_comprehensive.py, scripts/verify_truth.py | DB・インフラ |
| `docs/architecture/calculate.md` | リターン計算アーキテクチャ | 424 | 2026-01-29 | fresh | backend/app/services/annual_returns_calculator.py, backend/app/services/drawdowns_calculator.py, backend/app/services/metrics_calculator.py, backend/app/services/monthly_returns_calculator.py, backend/app/services/price_ratio_calculator.py, backend/app/services/rebalance.py | DB・インフラ |
| `docs/architecture/chart_style.md` | Chart Style Guide | 745 | 2026-01-29 | fresh | - | UI・デザイン |
| `docs/architecture/precompute-analysis.md` | 事前計算アーキテクチャ（実装済み） | 368 | 2026-01-29 | fresh | - | DB・インフラ |

## AC2: docs/skills/ Catalog (25 files)

| File | Subject (1-line) | Lines | Last Updated | Freshness | Dependencies | Pair Skill | Allowed Tools |
|---|---|---:|---|---|---|---|---|
| `docs/skills/Agent Skills.md` | Agent Skills | 152 | 2025-12-28 | fresh | - | unpaired | - |
| `docs/skills/_INDEX.md` | skills配下の索引とAgent Skills一覧 | 130 | 2026-02-15 | fresh | AGENTS.md,CLAUDE.md,api-reference.md,best-practices.md,building-block-addition-guide.md,building-block-pattern.md,database-schema.md,document-naming-convention.md,environment-switching.md,fof-pipeline-troubleshooting.md,knowledge-01.md,knowledge-02.md,knowledge-03.md,knowledge-04.md,knowledge-05.md,knowledge-06.md,passive-context-index-standard.md,password-expiry-management.md,performance-audit.md,performance-measurement.md,portfolio-analysis-idea-loop.md,portfolio-analysis-verification.md,skills-creation-guide.md,structural-suspect-ban.md,tier-visibility-control.md | manage-index-md | [Read, Edit, Write, Glob, Grep, Bash] |
| `docs/skills/api-reference.md` | API endpoint仕様・運用注意点 | 737 | 2026-01-31 | fresh | 073-layer-separation-architecture.md,business_rules.md,check-rule.md,database-schema.md,environment-switching.md,password-expiry-management.md,requirements-spec.md,tier-visibility-control.md | api-testing | Read, Grep, Glob, Bash |
| `docs/skills/best-practices.md` | Skills ドキュメント ベストプラクティス | 401 | 2026-01-04 | fresh | - | unpaired | - |
| `docs/skills/building-block-addition-guide.md` | Building Block 追加ガイド | 620 | 2026-01-15 | fresh | building-block-pattern.md | building-block-addition | Read, Grep, Glob, Bash, Edit, Write |
| `docs/skills/building-block-pattern.md` | Building Block Pattern（ビルディングブロックパターン） | 691 | 2026-02-12 | fresh | 001-fof-unified-model.md,002-pipeline-signal-framework.md,building-block-addition-guide.md,business_rules.md | building-block-pattern | Read, Grep, Glob |
| `docs/skills/database-schema.md` | データベース構造スキル (Database Schema Skill) | 871 | 2026-01-28 | fresh | api-reference.md,business_rules.md,calculation-theory.md,check-rule.md,fof-pipeline-troubleshooting.md,password-expiry-management.md | unpaired | - |
| `docs/skills/document-naming-convention.md` | ドキュメント命名規則 (Document Naming Convention) | 299 | 2026-01-07 | fresh | - | document-naming-convention | Read, Grep, Glob |
| `docs/skills/environment-switching.md` | 環境切り替えスキル (Environment Switching Skill) | 351 | 2026-01-05 | fresh | PostgreSQL.md,api-usage-guide.md,check-rule.md,password-expiry-management.md,render-info.md | unpaired | - |
| `docs/skills/fof-pipeline-troubleshooting.md` | FoF Pipeline Troubleshooting Guide | 643 | 2026-01-15 | fresh | 046-fof-signal-unification.md,building-block-addition-guide.md,building-block-pattern.md,business_rules.md,calculation-theory.md | fof-pipeline-troubleshooting | [Read, Glob, Grep, Bash] |
| `docs/skills/knowledge-01.md` | トレンド/逆張り4戦略と低相関分散の基礎 | 72 | 2026-01-05 | fresh | - | unpaired | - |
| `docs/skills/knowledge-02.md` | リセッション型別の資産配分・セクター耐性分析 | 266 | 2026-01-05 | fresh | - | unpaired | - |
| `docs/skills/knowledge-03.md` | デュアルモメンタム研究動向(2015-2025)レビュー | 226 | 2026-01-05 | fresh | - | unpaired | - |
| `docs/skills/knowledge-04.md` | 現行FoF戦略の構造評価とリスク制御解説 | 78 | 2026-01-05 | fresh | - | unpaired | - |
| `docs/skills/knowledge-05.md` | Core Momentum拡張案(平均回帰/ボラ/マクロ/現金層) | 113 | 2026-01-05 | fresh | - | unpaired | - |
| `docs/skills/knowledge-06.md` | (空ファイル: 内容未記載) | 0 | 2026-01-05 | fresh | - | unpaired | - |
| `docs/skills/passive-context-index-standard.md` | Passive Context Index Standard | 152 | 2026-02-02 | fresh | - | unpaired | - |
| `docs/skills/password-expiry-management.md` | Skill: パスワード有効期限管理 | 332 | 2025-12-23 | fresh | password.md | password-expiry-management | [Read, Edit, Write, Glob, Grep, Bash] |
| `docs/skills/performance-audit.md` | パフォーマンス監査ワークフロー | 38 | 2025-12-24 | fresh | - | unpaired(index-claims-performance-audit) | - |
| `docs/skills/performance-measurement.md` | パフォーマンス計測スキル | 41 | 2025-12-24 | fresh | - | unpaired(index-claims-performance-measurement) | - |
| `docs/skills/portfolio-analysis-idea-loop.md` | ポートフォリオ分析アイデア・ループ (Sortino超え / Ret | 481 | 2026-01-05 | fresh | api-reference.md,business_rules.md,calculation-theory.md,kalman-design.md,portfolio-analysis-verification.md | unpaired | - |
| `docs/skills/portfolio-analysis-verification.md` | ポートフォリオ分析・検証スキル | 1321 | 2026-01-07 | fresh | building-block-addition-guide.md,building-block-pattern.md,business_rules.md,calculation-theory.md,kalman-design.md,portfolio-analysis-idea-loop.md | unpaired | - |
| `docs/skills/skills-creation-guide.md` | Skills 作成ガイド (Skills Creation Guide) | 262 | 2025-12-24 | fresh | best-practices.md,xxx.md | skills-creation-guide | [Read, Write, Edit, Glob, Grep, Bash] |
| `docs/skills/structural-suspect-ban.md` | 構造的SUSPECT検出+自動Ban機能 設計書 | 710 | 2026-02-17 | fresh | - | unpaired | - |
| `docs/skills/tier-visibility-control.md` | Tier可視性制御の仕様・実装ガイド | 314 | 2026-01-31 | fresh | Visibility-Settings.md | tier-visibility-control | [Read, Edit, Write, Glob, Grep, Bash] |

### knowledge-01..06 Summary

- knowledge-01: トレンドロング/ショート + ミーンリバージョンロング/ショートの4戦略整理と低相関分散の基礎。
- knowledge-02: リセッション型（信用崩壊/供給停止/インフレ）別に資産・セクター耐性を比較した配分指針。
- knowledge-03: デュアルモメンタム研究の発展（リスク制御、ML/AI、資産拡張、タイミング統合、構築手法）。
- knowledge-04: 現行FoF戦略を「時間分散×ボラ制御」で解説した構造評価メモ。
- knowledge-05: Core Momentumに非相関エンジン（平均回帰/ボラキャリー/マクロ/動的キャッシュ）を重ねる拡張案。
- knowledge-06: 空ファイル（0行、内容未記載）。

## AC3: tasks/lessons.md Classification (128 lessons / 8 categories)

| Category | Count | IDs |
|---|---:|---|
| 計算ロジック | 11 | L017,L018,L020,L062,L071,L072,L077,L087,L090,L111,L115 |
| DB・データ | 11 | L004,L014,L064,L067,L082,L085,L107,L112,L118,L119,L124 |
| GS・最適化 | 17 | L008,L012,L025,L027,L029,L033,L039,L041,L057,L058,L089,L091,L105,L110,L117,L120,L127 |
| パイプライン | 26 | L001,L013,L022,L023,L024,L030,L040,L045,L047,L048,L051,L052,L053,L054,L055,L060,L068,L069,L070,L086,L092,L094,L095,L099,L101,L102 |
| API・FE | 7 | L015,L016,L026,L121,L122,L123,L125 |
| 運用・デプロイ | 22 | L002,L003,L006,L007,L009,L010,L011,L036,L037,L049,L050,L065,L075,L076,L079,L080,L081,L084,L093,L100,L106,L126 |
| 開発プロセス | 10 | L021,L028,L032,L034,L059,L066,L098,L103,L104,L109 |
| その他 | 24 | L005,L019,L031,L035,L038,L042,L043,L044,L046,L056,L061,L063,L073,L074,L078,L083,L088,L096,L097,L108,L113,L114,L116,L128 |

### 計算ロジック

| ID | 1-line Summary |
|---|---|
| L017 | FoFリターン計算方式の乖離 → 根本原因特定・修正完了（2026-02-14） |
| L018 | RULE10: シグナル判定はClose、リターン記録はOpen（2026-02-14） |
| L020 | signal vs holding_signal — リバランスタイミングの罠（2026-02-14） |
| L062 | L2モメンタム計算式(pct_change≡product(1+r)-1)は数学的に等価 — L2にバグなし |
| L071 | 低頻度リバランスPFの初期化期間は複数月 — skipロジックは全Cash初期化月カバー必須 |
| L072 | GS計算開始日フィルタの設計原則 — Phase 1後にsignal_historyを一括フィルタ |
| L077 | GS CSV monthly_return = open-based / Production cumulative_return = close-based |
| L087 | kasoku長lookback(12M/24M)でGS-本番初期化期間差異が発生する |
| L090 | GS monthly_return NaN vs 本番 cumulative_return データパス差異でコンポーネント選出が変わる |
| L111 | Cycle1統合:月次リターン粒度でのエッジ崩壊precision80%は構造的に困難 |
| L115 | 回帰→分類パイプラインは月次リターンSNR限界を克服しない |

### DB・データ

| ID | 1-line Summary |
|---|---|
| L004 | experiments.db はスナップショットであり SSOT ではない |
| L014 | experiments.db と 本番DB の UUID は別体系（2026-02-14） |
| L064 | 本番データアクセスはDATABASE_URLでPostgreSQLに直接接続。API経由禁止 |
| L067 | 殿の個人PF(35体)は本番DBから絶対に削除・変更するな |
| L082 | monthly_returns.portfolio_id(varchar)とportfolios.id(uuid)の型不整合 |
| L085 | テストPF削除のFK依存は16テーブル |
| L107 | 生成物調査ではDATA_CATALOG掲載有無とmeta.output.file実在の二軸照合が有効 |
| L112 | monthly_returns.signalがJSON辞書形式のときはキー抽出しないと日次分布分析が全欠損になる |
| L118 | DTB3はeconomic_indicatorsではなくdaily_pricesテーブルにticker='DTB3'として格納。close_priceカラ... |
| L119 | DATA_CATALOG.mdの86銘柄は本番PostgreSQL側の情報。experiments.db(SQLite)のdaily_pricesは実際1... |
| L124 | DB JSONカラムのstr型防御パターン |

### GS・最適化

| ID | 1-line Summary |
|---|---|
| L008 | GS構成四神と本番FoF構成PFの不一致 |
| L012 | GS の `drop_latest=True` は experiments.db では不要（2026-02-14） |
| L025 | GSスクリプト・データ同期スクリプトのパス規約（2026-02-15） |
| L027 | C抜き身のCANDIDATE_SET不一致 — CS4(4体)→C11_CCNh(11体)（2026-02-15） |
| L029 | gs_metadata による FoF 鮮度追跡（2026-02-15） |
| L033 | API登録スクリプトでPF定義を生成する際、GSスクリプトで使用しているパラメータ（risk_free_asset等）が登録ペイロードに含まれているか必ず... |
| L039 | 064_champion CSVとC12 UUIDは別データ。064はcmd_064時点の旧チャンピオン(143ヶ月)、C12はcmd_123登録の新パタ... |
| L041 | GS高速化: NumPyベクトル化+前処理キャッシュで55倍速 |
| L057 | 168バッチGS結果は忍法ごとにCSV有無が異なる |
| L058 | subset型GSのmonthly CSV出力にはcommon_months注入が必須 |
| L089 | GS-本番パリティはデータソース一致が前提条件 |
| L091 | GS momentum計算はcumulative_return ratio方式を使え(prod方式は浮動小数点タイブレーク不一致) |
| L105 | BB config未拘束がGS無効パターン量産の根因 |
| L110 | 日次/週次粒度変更は月次崩壊予測precision最大65.5%止まり(80%未達) |
| L117 | SPA検定でp=0.99: 15万パターンGSのチャンピオンはtop群内で統計的に有意差なし。パラメータ空間が連続分布で特定パラメータの劇的エッジなし。f... |
| L120 | 外部データ(DTB3)追加はBayes上界を悪化させる(-5.2pp)。情報なき次元追加は次元の呪いで逆効果。MI=0.058bitsの低情報量データは特... |
| L127 | GS結果を利用する際は `DATA_CATALOG.md` と `meta.yaml` を必ず参照する |

### パイプライン

| ID | 1-line Summary |
|---|---|
| L001 | pipeline_config テンプレートのパラメータ名はコードと1:1一致必須 |
| L013 | GS の align_months 交差集合は lookback warm-up を失う（2026-02-14） |
| L022 | PipelineEngine統合の偽陽性 — 0/0 = OK（2026-02-15） |
| L023 | DTB3経済指標のDB照会はPipelineEngine呼び出し回数分累積する（2026-02-15） |
| L024 | signal_historyのキーはPhase 2のmonth_last_trading_daysと同型でなければならない（2026-02-15） |
| L030 | ⚠️ Pipeline momentum_cache未提供でsignal_calcが27倍増（9s→439s）（2026-02-15） |
| L040 | nukimi C2候補はgekkou列のみ使用、close/openは同一CSVデータで暫定統一 |
| L045 | nukimi_c高速化: nukimiとnukimi_cの計算ロジックは完全同一(C-series固有差異なし)。パラメータグリッドのみ異なる(T1-T3... |
| L047 | kawarimi R3: NumPy呼出し排除で5.5倍(0.037秒) |
| L048 | nukimi R3: precompute keyはtop_n_effを使え |
| L051 | nukimi R4: multiprocessingは0.05秒級GSで逆効果 |
| L052 | kasoku R4: PeriodIndex参照最適化で19%短縮 |
| L053 | oikaze R3: common_months注入でfast/seq月次CSV完全一致 |
| L054 | nukimi_c統合可能: PARAM_GRID差分のみで戦略ロジック同一 |
| L055 | kasoku diff方式は激攻、ratio方式は常勝に特化 |
| L060 | 非月次リバランスのGSチャンピオンは月次制約下で大幅劣化する(特にkasoku) |
| L068 | PipelineEngineはpipeline_config内のlookback_periodsを使い、別途渡されたperiods/weights/uni... |
| L069 | GS candidateからpipeline_config構築はregister_shijin_portfolios.pyのbuild_pipeline_... |
| L070 | PipelineEngine pathとmatrix pathのNaN処理厳格さの差異 |
| L086 | GS tiebreak本番完全準拠: cutoff_score全包含方式 |
| L092 | kawarimi tiebreak float64精度同値タイ |
| L094 | oikaze cutoff_score epsilon tolerance(1e-12)が必要 |
| L095 | kasoku main()がcumulative_returnsを未ロード — 転換コード死蔵 |
| L099 | pipeline_config LIKE '%ReversalFilter%' は TrendReversalFilter を誤検知→jsonb_path... |
| L101 | MultiViewのPhase3 momentum_cache事前計算はFoF専用のためskipされる |
| L102 | MultiViewの4視点skip_months=[0,1,2,3]はクラス変数固定でconfigで変更不可 |

### API・FE

| ID | 1-line Summary |
|---|---|
| L015 | 本番API呼び出しは `requests` + HTTPBasicAuth（2026-02-14） |
| L016 | monthly-trade API のフィールド意味（FoF）（2026-02-14） |
| L026 | 本番FoFコンポーネント取得は `/api/portfolios/get` のみ（2026-02-15） |
| L121 | フロント実装前にbackend API実コードの仕様確認必須(PUT vs PATCH、バルクエンドポイント有無) |
| L122 | TTL付きGETキャッシュはwrite操作後に自動無効化されない |
| L123 | WSL2のmatplotlibでは日本語フォントが未登録。plt.rcParams['font.family']指定だけでは不可。font_manager... |
| L125 | Visibility Tier>Globalカスケード構造問題 |

### 運用・デプロイ

| ID | 1-line Summary |
|---|---|
| L002 | ブロック名は BlockType enum 値で統一する |
| L003 | PowerShell の -replace / Set-Content で日本語UTF-8ファイルが文字化けする |
| L006 | 本番API呼び出しは PowerShell `Invoke-RestMethod` を使う |
| L007 | 新FoF追加後の再計算は `sync-fof`（L3）を使う |
| L009 | sync-fof API は Query Parameter 方式（JSON Body ではない） |
| L010 | download_prod_data.py 実行時は PYTHONPATH 設定が必要 |
| L011 | Windows 環境での YAML/ファイル読み込みはエンコーディング明示が必須 |
| L036 | recalculate-syncのstart_dateパラメータは無視される |
| L037 | standard PFでpipeline_config未設定だとrecalculate_fastがCashフォールバック |
| L049 | bunshin R3: 純Pythonインナーループは逆効果。fixed-arity vectorizationが有効 |
| L050 | kasoku R3: precomputed picks+純Pythonインナーループで4.54倍速(0.577→0.127秒) |
| L065 | 本番コードパス統一原則 — 数学的等価でも本番と同一コードパスを使え |
| L075 | 新規PFのrecalculateにはrecalculate-syncが必要 |
| L076 | Layer lockはプロセス内限定。再計算の最終保存点はUPSERTで冪等化しておく |
| L079 | sync-fof APIの409 conflict対応(リトライ+30秒待機必要) |
| L080 | save APIのsuccess=Falseでも実際にはDB登録済み。削除はDB直接DELETEが確実。performanceテーブルは本番DBに存在しない |
| L081 | recalculate Phase0でmonthly_returnsが一時的に空になる |
| L084 | recalculate-statusのis_running=Noneは完了ではない |
| L093 | SingleViewMomentumFilterBlock月次/日次判定バグ |
| L100 | MultiViewMomentumFilterBlockはbase_period_months≥4必須(skip=3で0ヶ月問題) |
| L106 | L103(報告上書き消失)がcmd_263で再発 — deploy_task.shの構造的対策が未実装 |
| L126 | セッション開始時に `todo.md` / `lessons.md` を必ず読む |

### 開発プロセス

| ID | 1-line Summary |
|---|---|
| L021 | 車輪の再発明は厳禁 — 既存スクリプトを先に確認せよ（2026-02-14） |
| L028 | ⚠️ エージェントの独自判断エラー — ユーザー確認なしの設計変更（2026-02-15） |
| L032 | データ構造変更時は全使用箇所を確認せよ（2026-02-15） |
| L034 | Claude CodeはRead未実施のファイルへのWrite/Editを拒否する |
| L059 | 検証スクリプトの参照CSVはcmd番号更新と同時に追従が必要 |
| L066 | 殿裁定事項は3箇所に刻め(MCP+projects/*.yaml+lessons.yaml) |
| L098 | draft |
| L103 | 報告YAMLが後続cmd deployで上書き消失する場合、ソースコード直接読解で復元可能 |
| L104 | subtask間依存でgitignoreがコミット計画をブロック |
| L109 | 分析スクリプトにタイムアウト必須 |

### その他

| ID | 1-line Summary |
|---|---|
| L005 | FoFパリティ比較は本番の現行パラメータを先に確認する |
| L019 | タイブレーク均等保有ルール（2026-02-14） |
| L031 | FoF パリティ検証: 加速-C 164/167、残り3件はモメンタム計算差異（2026-02-15） |
| L035 | FoF参照L0 PFはDELETE不可→UPDATE方式が安全 |
| L038 | sync_lessons.shは最後の## N.以降の### L0xx:エントリを全てスキップする(in_numbered_sectionフラグ未リセット) |
| L042 | L042 |
| L043 | L054 |
| L044 | L055 |
| L046 | L057 |
| L056 | wide形式CSV(76万列)のpd.read_csvはヘッダー先読み+usecolsが必須 |
| L061 | verify_all_portfolios.pyはFoF(type=fof)をスキップする — L1四神パリティは未検証だった |
| L063 | download_prod_data.py monthly-returnsは大量エラーでもexit 0で終了する（偽成功に注意） |
| L073 | FoFパリティ検証ではコンポーネント初期化月をスキップするな |
| L074 | verify_all_portfolios.pyのskipロジックはquarterly_marにも対応必要 |
| L078 | PortfolioRepository.load()は1PFバリデーションエラーで全PF読込失敗する単一障害点 |
| L083 | close_fallback=openは部分欠損closeを補完しない |
| L088 | L1パリティPASSはtie処理網羅の証明にはならない |
| L096 | skip処理のデータ頻度判定はis_monthly_data()を使え（行数ヒューリスティック禁止） |
| L097 | SVMF/MVMFのskip計算には行数ヒューリスティックではなくis_monthly_data()を使え |
| L108 | エッジ残存率バックテスト: 予測精度は限定的だが健全度可視化に有効 |
| L113 | ターゲット再定義は予測タスクの性質を変えるがSNR限界は克服しない |
| L114 | 高相関な弱予測器のスタッキングはDM3で精度改善しない |
| L116 | PF間の相関構造特徴量はエッジ崩壊予測に寄与しない |
| L128 | 忍法FoF作成の正しいフロー（抜き身3の失敗を踏まえた完全版） |

### Stale Lessons

- L010: projects/dm-signal/lessons.yaml上でdeprecated扱い（参照先scripts消滅）
- L025: projects/dm-signal/lessons.yaml上でdeprecated扱い（参照先scripts消滅）
- L042/L043/L044/L046: タイトルがIDのみで要約欠落（実質プレースホルダ）
- L098: タイトルdraftの未確定教訓

### Duplicate Lessons

- L096 と L097: is_monthly_data()適用の同趣旨重複
- L103 と L106: 報告YAML上書き消失問題（再発報告）
- L005, L008, L027, L127: GS候補集合と本番構成不一致の同一系トピック

### Contradictory Lessons

- L006(本番APIはPowerShell Invoke-RestMethod) vs L015(本番APIはrequests+HTTPBasicAuth)
- L007(新FoF再計算はsync-fof) vs L075(新規PFはrecalculate-sync必要)

## AC5 (full): Cross-Directory Analysis (docs/rule + docs/skills)

### Cross Category Table

| 横断カテゴリ | docs/rule件数 | docs/skills件数 | 主な該当ファイル |
|---|---:|---:|---|
| 計算・取引ルール | 6 | 11 | rule: business_rules/calculation-theory/trade-rule 等, skills: building-block*, fof-pipeline, knowledge-01..06, portfolio-analysis* |
| API・DB・データ | 5 | 3 | rule: api-usage-guide/database-info/local-postgresql/DTB3-guide/requirements-spec, skills: api-reference/database-schema/environment-switching |
| 運用・デプロイ・検証 | 8 | 4 | rule: gs-parity/local-verification/runbook群/renderyaml/check-rule, skills: performance-*, password-expiry, tier-visibility |
| ドキュメント規約・メタ | 2 | 7 | rule: _INDEX/vercel-style-guide, skills: _INDEX/best-practices/skills-creation/document-naming/passive-context 等 |
| UI/デザイン | 4 | 0 | rule: design*.md |
| セキュリティ状況 | 1 | 0 | rule: security-status.md |

### Duplicate Topics (docs/rule vs docs/skills)

- 命名規約系: docs/rule/portfolio-naming-convention.md と docs/skills/document-naming-convention.md が重複領域を持つ。
- API運用系: docs/rule/api-usage-guide.md と docs/skills/api-reference.md で呼び出し規約が二重管理。
- FoF構築導線: docs/rule/*runbook.md と docs/skills/building-block-addition-guide.md の責務境界が曖昧。

### Missing Doc Candidates

- docs/skills/knowledge-06.md が空（0行）: knowledgeシリーズ完結用の本文が未整備。
- docs/skills/agent-skill-matrix.md 相当が不在: docs/skills と .claude/skills の対応表SSOTがない。
- tasks/lessons-taxonomy.md 相当が不在: lessonsカテゴリ判定基準が文書化されておらず分類ぶれを誘発。

### _INDEX Consistency

```text
docs/skills file links:
actual_files=25
index_unique_links=24
missing_in_index=_INDEX.md

agent skills links:
actual_skill_dirs=24
index_skill_links=17
missing_in_index=create-ninpou-fof,download-prod-pf,jounin-advisor,ninja-build-force,ninja-council,ninja-daily-report,ninja-doc-review,ninja-monthly-report,ninja-task-force
extra_in_index=performance-audit,performance-measurement

allowed-tools mismatches:
building-block-addition: declared (制限なし) / actual Read,Grep,Glob,Bash,Edit,Write
building-block-pattern: declared (制限なし) / actual Read,Grep,Glob
document-naming-convention: declared (制限なし) / actual Read,Grep,Glob
documentation-guide: declared (制限なし) / actual [Read,Edit,Write,Glob,Grep,Bash]
fof-pipeline-troubleshooting: declared Read,Grep,Glob,Bash,Write / actual [Read,Glob,Grep,Bash]
password-expiry-management: declared (制限なし) / actual [Read,Edit,Write,Glob,Grep,Bash]
performance-analysis: declared (制限なし) / actual [Read,Write,Glob,Grep,Bash]
skills-creation-guide: declared (制限なし) / actual [Read,Write,Edit,Glob,Grep,Bash]
tier-visibility-control: declared (制限なし) / actual [Read,Edit,Write,Glob,Grep,Bash]
create-yaml-toc: declared (制限なし) / actual Read,Grep,Glob,Edit,Write
manage-index-md: declared (制限なし) / actual [Read,Edit,Write,Glob,Grep,Bash]
```

## AC6: Integration Status (with subtask_477_recon_b)

- Referenced file: `queue/reports/kirimaru_report_cmd_477.yaml`
- Integration date: 2026-03-02 (JST)
- Integration outcome:
  - sasuke担当分（AC1/AC4/AC5前半） + kirimaru担当分（AC2/AC3/AC5後半）を単一ドキュメントへ統合完了。
  - 追加反映済み: docs/skills 25ファイルカタログ、lessons 128件分類、重複/欠落/_INDEX整合性監査。
  - AC6 status: integrated (done)


## Notes

- Last Updatedは、原則としてファイル先頭の明示日付を優先し、未記載時は`git log -1 --date=short`、さらに取得不能時はファイルmtimeを使用。
- 依存関係は文書内の参照パス抽出（最大6件）を掲載。
