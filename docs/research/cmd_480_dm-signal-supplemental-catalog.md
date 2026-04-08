# cmd_480: DM-signal 補完カタログ — docs残り + scripts/

> Generated: 2026-03-01 | Agent: kotaro | Parent: cmd_480

---

## §1 docs/archives/ 構造把握 (AC1)

### サブディレクトリ構成（8フォルダ、292件）

| フォルダ | 件数 | 主題 |
|----------|------|------|
| `future/` | 198 | 将来計画・未実装機能の設計ドキュメント（001-181番号付き+補助ファイル） |
| `tasks/` | 27 | 完了タスク記録（1st-10th_task + task-001〜016 + refactor_task） |
| `steps/` | 17 | 開発ステップ記録（1st-16th step + code_review_8th_step） |
| `misc/` | 13 | 雑多（チャート画像1件、デプロイメモ、運用ガイド、open-close解説等） |
| `analysis/` | 12 | 分析・調査レポート（FoF問題、MDD修正、リバランスas-is/to-be、計算問題等） |
| `performance/` | 11 | パフォーマンス改善記録（LCP-1〜3、フロントエンド高速化、recalc高速化等） |
| `reports/` | 8 | 検証レポート・コードレビュー（RL-1〜5、ETLレビュー等） |
| `refactoring/` | 4 | リファクタリング計画・実行（backend/frontend/全体） |

### アーカイブ理由

`_INDEX.md` に明記: 「完了したタスク・過去のドキュメントのアーカイブ」。全ファイルが完了済み or 過去情報として退避されたもの。

### future/ 詳細（198件中194件が番号付きmd）

`_INDEX.md` による分類:

| 番号帯 | セクション | 件数目安 |
|--------|-----------|---------|
| 001-010 | 基盤設計・アーキテクチャ | ~10 |
| 011-020 | ルール・計算理論 | ~10 |
| 021-030 | 分析・改善 | ~10 |
| 031-045 | Performance廃止プロジェクト | ~15 |
| 046-055 | FoF・シグナル統一 | ~10 |
| 056-063 | 統一化・クリーンアップ | ~8 |
| 064-071 | 最適化・新機能 | ~8 |
| 072-084 | API・インフラ・検証 | ~13 |
| 085-093 | パイプライン・リファクタリング | ~9 |
| 094-102 | SSOT統一・リターン計算 | ~9 |
| 103-109 | FoF高速化・評価 | ~7 |
| 110-115 | 分析戦略・メトリクス拡張 | ~6 |
| 116-129 | 本番運用・インフラ最適化 | ~14 |
| 130-155 | UI/UX・フロントエンド改善 | ~26 |
| 156-169 | シグナル研究・エンジン設計 | ~14 |
| 170-181 | パイプライン修正・パリティ検証 | ~12 |

進捗(INDEXより): 完了85件、進行中6件、計画中68件、Research2件、中止3件、その他11件。

補助コンテンツ: `assets/`(画像2件)、`images/`(画像1件)、`tasks/`(サブタスク4件)、PDF1件(CamScanner)、z-archive 2件。

### 参照価値候補（10件以内）

| ファイル | 理由 |
|----------|------|
| `future/002-pipeline-signal-framework.md` | BBパイプラインの原設計思想（35KB） |
| `future/012-rulebase.md` | ルールベースの体系化（25KB） |
| `future/091-production-gridsearch-unification.md` | 本番-GS統一の設計思想 |
| `future/095-return-calculation-unification.md` | リターン計算SSOT化の経緯 |
| `future/100-recalculate-ssot-integration-analysis.md` | recalculate SSOT統合分析 |
| `future/109-fof-pipeline-implementation-plan.md` | FoFパイプライン実装計画 |
| `future/157-A-fast-simulator.md` | 高速シミュレーター設計 |
| `future/175-family-grid-search-reclassification.md` | ファミリーGS再分類 |
| `future/177-deterministic-tiebreak-resolution.md` | タイブレーク決定論的解決 |
| `analysis/investigation_report_final.md` | 計算問題の最終調査レポート |

---

## §2 docs/spec + security + deployment + guide + logging カタログ (AC2)

### docs/spec/ （5件）

| ファイル | 行数 | 主題 | 鮮度 | 重複 |
|----------|------|------|------|------|
| `_INDEX.md` | 43 | 目次 | — | — |
| `pipeline-blocks.md` | 319 | BBパイプラインブロック仕様。全ブロック型定義 | 2025-12-25 実装完了 | projects/dm-signal.yamlのblock_catalogと一部重複 |
| `Visibility-Settings.md` | 513 | hide_portfolio/hide_signal可視性設定の実装仕様 | 2026-01-25 実装済 | なし |
| `024-chart-all-period-option.md` | 409 | チャート全期間(ALL)オプション。future/024と同名 | 2025-12-28 実装済 | future/024と内容重複の可能性 |
| `monthly-returns-spec.md` | 84 | 月次リターン+MTD+FoF合成のSSOT定義 | 不明 | なし |

### docs/security/ （18件）

| ファイル | 行数 | 主題 | 鮮度 |
|----------|------|------|------|
| `_INDEX.md` | 69 | 目次 | — |
| `security.md` | 678 | セキュリティ全体設計書 | 2025-12-05 検討中 |
| `security-mvp.md` | 1414 | セキュリティMVP設計書（Option C完全版） | 2025-12-17 |
| `security-mvp-review.md` | 93 | MVPレビュー | 2025-12-16 |
| `security-mvp-task.md` | 872 | MVPタスク本体 | — |
| `security-mvp-task-002`〜`014` | 108-872 | 個別セキュリティタスク（13件） | — |

構造: `security.md`(全体方針) → `security-mvp.md`(MVP設計) → `security-mvp-task*.md`(個別実装タスク)。全てBasic認証+CORS+レート制限等のMVPセキュリティ実装記録。重複なし(階層的に整理済み)。

### docs/deployment/ （6件）

| ファイル | 行数 | 主題 | 鮮度 | 重複 |
|----------|------|------|------|------|
| `_INDEX.md` | 62 | 目次 | — | — |
| `PostgreSQL.md` | 101 | PostgreSQL移行決定メモ | 2025-12-22 | SQLite-to-PostgreSQL.mdと経緯重複 |
| `SQLite-to-PostgreSQL.md` | 319 | SQLite vs PostgreSQL比較分析 | 2025-12-21 | 上記と重複 |
| `SQLite-to-PostgreSQL-task.md` | 802 | 移行タスク実行記録(Phase T4完了) | 2025-12-22 | なし |
| `automate-ETL.md` | 507 | ETL自動化設計書 | — | なし |
| `render-info.md` | 138 | Renderプラン情報 | 2025-12-22 | なし |

### docs/guide/ （3件）

| ファイル | 行数 | 主題 | 鮮度 | 重複 |
|----------|------|------|------|------|
| `_INDEX.md` | 37 | 目次 | — | — |
| `faq-jp.md` | 866 | FAQ日本語版（アプリ使い方+パフォーマンス指標解説） | — | faq-en.mdと言語違い重複 |
| `faq-en.md` | 797 | FAQ英語版 | — | faq-jp.mdと言語違い重複 |

### docs/logging/ （1件）

| ファイル | 行数 | 主題 | 鮮度 | 重複 |
|----------|------|------|------|------|
| `LOGGING_GUIDE.md` | 529 | バックエンドログの種類と意味の解説 | — | なし |

---

## §3 scripts/ 全体カタログ (AC3)

### ディレクトリ構造

```
scripts/
├── core/          (6 .py + 1 _INDEX.md)
└── analysis/
    ├── grid_search/ (11 .py)
    └── data_sync/   (10 .py)
```

ルートレベルに直接ファイルなし。全27スクリプト。

### scripts/core/ — 本番API連携ユーティリティ（6件）

| ファイル | 行数 | 役割 | 現役/廃止 |
|----------|------|------|----------|
| `backfill_data.py` | 322 | 過去データのバックフィル（Stock API → DB） | 現役 |
| `collect_all_pf_data.py` | 168 | 全ポートフォリオデータ収集（本番API→JSON保存） | 現役 |
| `fetch_portfolios.py` | 71 | 本番からポートフォリオ一覧取得 | 現役 |
| `run_recalculate.py` | 66 | 再計算APIトリガー（日付指定可） | 現役 |
| `trigger_etl.py` | 5 | ETLジョブトリガー（daily_etl直接実行） | 現役 |
| `upload_portfolios.py` | 78 | ポートフォリオ本番アップロード+再計算 | 現役 |

### scripts/analysis/grid_search/ — GS探索・検証ランナー（11件）

| ファイル | 行数 | 役割 | 現役/廃止 |
|----------|------|------|----------|
| `grid_search_metrics_v2.py` | 2140 | GSメトリクス計算エンジン V2（ベクトル化+並列） | 現役(中核) |
| `gs_csv_loader.py` | 198 | GFS CSV直接読込モジュール（cmd_160確立） | 現役(共通) |
| `gs_data_loader.py` | 286 | 本番PostgreSQL直接読込モジュール（cmd_214転換） | 現役(共通/CSV後継) |
| `run_077_bunshin.py` | 710 | 分身(EqualWeight)忍法GSランナー | 現役 |
| `run_077_oikaze.py` | 879 | 追い風(MomentumFilter)忍法GSランナー | 現役 |
| `run_077_nukimi.py` | 952 | 抜き身(SingleViewMomentum)忍法GSランナー | 現役 |
| `run_077_kawarimi.py` | 832 | 変わり身(TrendReversal)忍法GSランナー | 現役 |
| `run_077_kasoku.py` | 1093 | 加速(MomentumAcceleration)忍法GSランナー | 現役 |
| `run_077_monban.py` | 941 | 門番(AbsoluteMomentum)忍法GSランナー | 現役(追加設計要) |
| `run_077_kawarimi_mp_exp.py` | 250 | 変わり身マルチプロセス実験版 | 実験用(非正規) |
| `verify_all_portfolios.py` | 256 | 全ポートフォリオパリティ検証 | 現役(検証) |

### scripts/analysis/data_sync/ — データ同期ツール（10件）

| ファイル | 行数 | 役割 | 現役/廃止 |
|----------|------|------|----------|
| `experiment_db.py` | 721 | experiments.db管理（テーブル作成/メトリクス保存） | 現役(中核) |
| `download_prod_data.py` | 617 | 本番→ローカルSQLite一括ダウンロード | 現役 |
| `local_metrics.py` | 514 | ローカルメトリクス計算 | 現役 |
| `download_all_prices.py` | 479 | Stock Data API→全銘柄価格DL | 現役 |
| `sync_prices_from_prod.py` | 168 | 本番PostgreSQL→SQLite価格同期 | 現役(注意:パリティ保証なし) |
| `refresh_sqlite_from_api.py` | 156 | API経由SQLiteリフレッシュ | 現役 |
| `sync_dm_monthly_returns.py` | 147 | 月次リターン同期 | 現役 |
| `delete_invalid_dates.py` | 50 | 不正日付データ削除 | メンテナンス用 |
| `check_lqd_data.py` | 35 | LQDデータ検証 | 診断用 |
| `check_sqlite.py` | 8 | SQLite接続確認 | 診断用(最小) |

### 廃止候補

| ファイル | 理由 |
|----------|------|
| `grid_search/gs_csv_loader.py` | cmd_214でDB直接読込(gs_data_loader.py)に転換。ただしCSVフォールバック用途で残存の可能性あり |
| `grid_search/run_077_kawarimi_mp_exp.py` | 実験版。正規のrun_077_kawarimi.pyが存在 |
| `data_sync/check_sqlite.py` | 8行のみ。接続確認だけの最小スクリプト |

---

## §4 総括

| カテゴリ | 件数 | 状態 |
|----------|------|------|
| docs/archives/ | 292 | 全て完了・退避済み。future/が最大(198件)、_INDEX完備 |
| docs/spec/ | 5 | 実装完了仕様書。pipeline-blocks.mdがprojects/yamlと一部重複 |
| docs/security/ | 18 | MVP セキュリティ実装記録。階層的に整理済み |
| docs/deployment/ | 6 | PostgreSQL移行+Render+ETL自動化記録 |
| docs/guide/ | 3 | FAQ(日英)+目次 |
| docs/logging/ | 1 | バックエンドログガイド |
| scripts/core/ | 6 | 本番API連携。全て現役 |
| scripts/analysis/grid_search/ | 11 | GSランナー群+共通ローダー。忍法別6本が中核 |
| scripts/analysis/data_sync/ | 10 | データ同期ツール。experiment_db.pyが中核 |
| **合計** | **352** | — |
